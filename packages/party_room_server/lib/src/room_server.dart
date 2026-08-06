import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'asset_source.dart';
import 'participant_gate.dart';
import 'participant_link.dart';
import 'room.dart';
import 'room_limits.dart';
import 'web_assets.dart';

export 'player.dart';
export 'room.dart';

/// 포트 하나를 듣고, 토큰으로 방을 찾아 넘긴다.
///
/// 예전에는 이 클래스가 방 **그 자체**였다 — 그래서 방이 하나뿐이었다.
/// 이제 상태는 [Room] 이 갖고 여기는 배선만 한다: 여러 방이 같은 포트에서
/// 동시에 살고, 참가자는 자기 방 토큰으로만 들어온다.
///
/// 참가자 화면은 한 줄도 안 바뀌었다. 프로토콜이 처음부터 `?room=<토큰>` 로
/// 주소를 매기고 모든 엔드포인트가 그 토큰을 검사하고 있었기 때문이다 —
/// 방이 하나라는 것은 구현의 사정이었지 계약이 아니었다.
class RoomServer {
  /// 방 서버 기본 포트 — 참가자 주소·안내문이 모두 이 값을 참조한다.
  static const defaultPort = 8765;

  RoomServer({
    required AssetSource assets,
    this.port = defaultPort,
    this.limits = const RoomLimits(),
    this.maxRooms = defaultMaxRooms,
    this.roomTtl = defaultRoomTtl,
  }) : _webAssets = WebAssets(assets);

  /// 한 서버가 동시에 들고 있을 수 있는 방 수.
  ///
  /// 방 하나가 참가자 20명·자료 1GB 를 물 수 있어서, 개수를 안 막으면
  /// 디스크와 메모리가 조용히 늘어난다. 상시로 도는 공용 서버에서 특히 그렇다.
  static const defaultMaxRooms = 2;

  /// 방이 살아 있는 최대 시간.
  ///
  /// 한동안 수명 타이머가 아예 없었다 — 이름 붙인 방("금요 모임")의 링크가
  /// 다음 주에도 통해야 한다는 이유였고, 그 책임은 호스트의 열림/닫힘
  /// 스위치가 졌다. 상시 공용 서버가 생기면서 그 전제가 달라졌다: 아무도
  /// 안 지우면 방은 영원히 남고 자료도 함께 남는다.
  ///
  /// **개인 기계에서 도는 앱은 이 값을 늘려도 된다** — 정책은 서버마다 다르다.
  static const defaultRoomTtl = Duration(days: 3);

  final int port;

  /// 실제로 잡은 포트. [port] 를 0 으로 주면 OS 가 골라 주므로, 무엇을
  /// 잡았는지는 여기서만 알 수 있다(테스트·헤드리스 로그가 쓴다).
  int get boundPort => _server?.port ?? port;

  /// 새로 만드는 방이 물려받을 한계값.
  final RoomLimits limits;

  final int maxRooms;
  final Duration roomTtl;

  /// 더 만들 수 있는가. 화면이 [새 방] 버튼을 끄는 데 쓴다 —
  /// 눌러 봐야 거절당하는 버튼을 남겨 두지 않는다.
  bool get full => _rooms.length >= maxRooms;

  /// 이 방이 수명을 다했는가.
  bool expired(Room room, [DateTime? now]) =>
      (now ?? DateTime.now()).difference(room.createdAt) >= roomTtl;

  final WebAssets _webAssets;
  HttpServer? _server;

  final List<Room> _rooms = [];

  /// 만든 순서대로. 화면은 이 순서로 목록을 그린다.
  List<Room> get rooms => List.unmodifiable(_rooms);

  Room? byToken(String? token) {
    for (final r in _rooms) {
      if (r.roomToken == token) return r;
    }
    return null;
  }

  /// 상태가 바뀌면(방 추가·삭제 포함) 호출 — 앱이 저장·게시 트리거로 쓴다.
  void Function()? onStateChanged;

  /// 방 목록 자체가 바뀌었을 때.
  final _roomsController = StreamController<List<Room>>.broadcast();
  Stream<List<Room>> get roomsStream => _roomsController.stream;

  /// 어느 방에서 난 게임 이벤트인지 함께 흘린다 — 판은 여러 방에서 동시에
  /// 돌 수 있고, 사회자·효과음은 보고 있는 방과 무관하게 그 방의 것이다.
  final _gameEventController =
      StreamController<(Room, String, Map<String, dynamic>)>.broadcast();
  Stream<(Room, String, Map<String, dynamic>)> get gameEvents =>
      _gameEventController.stream;

  /// 어느 방의 대화인지 함께.
  final _chatController =
      StreamController<(Room, Map<String, dynamic>)>.broadcast();
  Stream<(Room, Map<String, dynamic>)> get chatStream => _chatController.stream;

  /// 앱이 얹는 추가 경로(제어 API 등). 서버는 내용을 모른다 —
  /// 여기에 앱 기능이 들어오면 이 패키지가 헤드리스로 못 돈다.
  Future<Response?> Function(Request req)? extraRoutes;

  /// 방을 하나 연다.
  ///
  /// 토큰은 이 서버 안에서 유일해야 한다 — [byToken] 이 먼저 만난 방만
  /// 돌려주므로, 같은 토큰이 둘이면 뒤엣것은 QR 도 링크도 닿지 않는
  /// 유령이 된다. 화면에는 보이는데 아무도 못 들어오는 방이 제일 나쁘다.
  Room createRoom({String name = '', String? token}) {
    // 먼저 수명이 다한 방을 치운다 — 자리가 나는데도 "가득 찼다" 고 하면
    // 호스트는 무엇을 지워야 할지 모른다.
    sweepExpired();
    if (full) {
      throw StateError('방은 최대 $maxRooms개까지입니다 — 쓰지 않는 방을 지우세요');
    }
    if (token != null && byToken(token) != null) {
      throw ArgumentError.value(token, 'token', '이미 쓰고 있는 방 토큰');
    }
    var room = Room(name: name, limits: limits, roomToken: token);
    // 자동 생성 토큰이 부딪히는 일은 사실상 없지만(31^6), 부딪혔을 때
    // 유령 방을 만드는 것보다 한 번 더 뽑는 편이 싸다.
    while (token == null && byToken(room.roomToken) != null) {
      room = Room(name: name, limits: limits);
    }
    _wire(room);
    _rooms.add(room);
    _publish();
    return room;
  }

  /// 저장분에서 되살린 방을 등록한다.
  ///
  /// 같은 토큰이 이미 있으면 받지 않는다 — 저장 파일이 어쩌다 겹쳐도
  /// (복원 두 번, 손으로 고친 파일) 유령 방으로 이어지지 않게.
  bool adoptRoom(Room room) {
    if (byToken(room.roomToken) != null) return false;
    // 저장분에 수명이 지났거나 정원을 넘는 방이 들어 있을 수 있다 —
    // 그대로 되살리면 한계가 뜻이 없어진다.
    if (expired(room) || full) return false;
    _wire(room);
    _rooms.add(room);
    _publish();
    return true;
  }

  void _wire(Room room) {
    room.onStateChanged = () => onStateChanged?.call();
    room.gameEvents.listen((e) => _gameEventController.add((room, e.$1, e.$2)));
    room.chatStream.listen((m) => _chatController.add((room, m)));
  }

  /// 방을 지운다 — 참가자 소켓을 끊고 업로드 사본도 치운다.
  Future<bool> removeRoom(String token) async {
    final room = byToken(token);
    if (room == null) return false;
    _rooms.remove(room);
    await room.dispose();
    _publish();
    return true;
  }

  void _publish() {
    _roomsController.add(rooms);
    onStateChanged?.call();
  }

  /// 수명이 다한 방을 치우고 몇 개를 치웠는지 돌려준다.
  ///
  /// 파티는 몇 시간짜리라 3일 상한에 걸리는 방은 사실상 끝난 방이다.
  /// 그래도 **접속 중인 사람이 있어도 지운다** — "최대 3일" 이 조건부면
  /// 유령 하나가 방을 영원히 붙잡는다.
  int sweepExpired() {
    final now = DateTime.now();
    final gone = [
      for (final r in _rooms)
        if (expired(r, now)) r,
    ];
    for (final r in gone) {
      _rooms.remove(r);
      unawaited(r.dispose());
    }
    if (gone.isNotEmpty) _publish();
    return gone.length;
  }

  Future<void> start() async {
    final router = Cascade().add(_wsHandler()).add(_httpHandler()).handler;
    _server = await shelf_io.serve(router, InternetAddress.anyIPv4, port);
    // 아무도 방을 만들지 않아도 수명은 흘러간다. 상시 서버에서는 이 비질이
    // 유일한 정리 계기다.
    _sweeper = Timer.periodic(
      const Duration(minutes: 10),
      (_) => sweepExpired(),
    );
  }

  Timer? _sweeper;

  Future<void> stop() async {
    _sweeper?.cancel();
    _sweeper = null;
    for (final r in _rooms) {
      await r.dispose();
    }
    await _server?.close(force: true);
    _server = null;
  }

  // ---- HTTP: 참가자 SPA + 입장 API ----

  Handler _httpHandler() {
    return (Request req) async {
      final path = req.url.path;

      // 앱이 얹은 경로가 먼저 — 제어 API 는 방 상태보다 바깥이다.
      final extra = await extraRoutes?.call(req);
      if (extra != null) return extra;

      // 번들 정적 자산(SPA·폰트·이미지)은 방 상태와 무관 — 별도 모듈에 위임.
      final asset = await _webAssets.serve(path);
      if (asset != null) return asset;

      // 라이어 커스텀 이미지 서빙 (호스트 업로드, 메모리)
      if (path == 'liar-image') {
        final room = byToken(req.url.queryParameters['room']);
        final img = room?.liarImage;
        if (img == null) return Response.notFound('no image');
        return Response.ok(
          img,
          headers: {
            'content-type': room!.liarImageMime,
            'cache-control': 'no-store', // 게임마다 바뀜
          },
        );
      }

      // 자료 내려받기: GET /file/<id>?room=…
      // 방 토큰만 요구한다 — 파일은 그 방 전체에 공개된 것이고, 스트리밍이라
      // 큰 영상도 메모리에 들지 않는다. id 는 서버가 발급한 것만 존재한다
      // (경로를 받지 않으므로 탈출 자체가 불가능).
      if (path.startsWith('file/') && req.method == 'GET') {
        final room = byToken(req.url.queryParameters['room']);
        if (room == null) return Response.forbidden('bad room');
        final shared = room.fileById(path.substring(5));
        if (shared == null) return Response.notFound('no file');
        final file = File(shared.path);
        if (!await file.exists()) return Response.notFound('gone');
        // 한글 파일명 — RFC 5987 filename* 인코딩이 없으면 헤더가 깨진다.
        final encoded = Uri.encodeComponent(shared.name);
        return Response.ok(
          file.openRead(),
          headers: {
            'content-type': shared.mime,
            'content-length': '${shared.size}',
            'content-disposition': "attachment; filename*=UTF-8''$encoded",
            'cache-control': 'no-store',
          },
        );
      }

      // 자료 올리기: POST /api/upload?room=…&name=…  (본문 = 바이트)
      // 세션을 요구한다 — 방 밖에서 아무나 디스크를 채우면 안 된다.
      if (path == 'api/upload' && req.method == 'POST') {
        final q = req.url.queryParameters;
        final room = byToken(q['room']);
        if (room == null) return _json({'error': 'bad_room'}, 403);
        // 세션은 **헤더로만** 받는다. 주소에 담으면 브라우저 방문기록·중간
        // 프록시 로그·인터넷 개방 시 Cloudflare 접속 로그에 인증 자격증명이
        // 그대로 남는다. 참가자 화면은 진작부터 헤더를 쓰고 있었고, 쿼리
        // 경로는 그때 열려 있던 탭을 위한 하위호환이었다 — 이제 없앤다.
        final uploader = room.bySession(req.headers['x-party-session']);
        if (uploader == null) return _json({'error': 'bad_session'}, 403);
        final name = (q['name'] ?? '').trim();
        if (name.isEmpty || name.length > 120) {
          return _json({'error': 'bad_name'}, 400);
        }
        final section = room.channels.writableId(q['section']);
        if (room.isSectionFull(section)) {
          return _json({'error': 'files_full'}, 409);
        }

        final declared = int.tryParse(req.headers['content-length'] ?? '');
        if (declared != null && declared > room.limits.uploadBytes) {
          return _json({'error': 'too_large'}, 413);
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in req.read()) {
          builder.add(chunk);
          // content-length 를 속이는 클라이언트 대비 — 실제 수신량으로도 자른다.
          if (builder.length > room.limits.uploadBytes) {
            return _json({'error': 'too_large'}, 413);
          }
        }
        final bytes = builder.takeBytes();
        if (bytes.isEmpty) return _json({'error': 'empty'}, 400);
        final refusal = room.quotaRefusal(section, uploader.tag, bytes.length);
        if (refusal != null) {
          return _json({'error': 'quota', 'message': refusal}, 429);
        }

        // 위 검사는 30MB 를 다 받아 놓고 거절하지 않으려는 미리보기일 뿐이고,
        // 최종 판정은 방 안에서 난다 — 본문을 받는 동안 남이 끼어들 수 있다.
        final shared = await room.saveUpload(
          name: name,
          bytes: bytes,
          uploader: uploader,
          sectionId: section,
        );
        if (shared.file == null) {
          return _json({'error': 'quota', 'message': shared.refusal}, 429);
        }
        return _json({'ok': true, 'id': shared.file!.id});
      }

      // 입장: POST /api/join {room, nickname, session?}
      if (path == 'api/join' && req.method == 'POST') {
        // 참가자 SPA 가 아닌 아무나 이 엔드포인트를 두드릴 수 있다 —
        // 깨진 본문에 500 을 뱉지 말고 400 으로 돌려보낸다.
        Map<String, dynamic> body;
        try {
          body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        } catch (_) {
          return _json({'error': 'bad_request'}, 400);
        }
        final r = handleJoin(body);
        return _json(r.body, r.status);
      }

      return Response.notFound('not found');
    };
  }

  /// 입장 판정.
  ///
  /// HTTP 로 들어오든 랑데부가 물어다 주든 **여기 한 곳**을 지난다. 비밀번호
  /// 검사·연타 잠금·정원 판정이 길마다 따로 있으면, 한쪽에만 고쳐진 구멍이
  /// 생긴다 — 그리고 그 구멍은 인터넷 쪽에 생긴다.
  ///
  /// `session` 이 오면 재입장(새로고침·재접속) 경로다: 이미 자리가 있는
  /// 사람은 비밀번호를 다시 안 묻는다. 새로고침할 때마다 다시 묻는 앱은
  /// 아무도 안 쓴다.
  ({int status, Map<String, dynamic> body}) handleJoin(
    Map<String, dynamic> body,
  ) {
    final room = byToken(body['room'] as String?);
    if (room == null) return (status: 403, body: {'error': 'bad_room'});

    final existing = room.bySession(body['session'] as String?);
    if (existing != null) {
      return (
        status: 200,
        body: {
          'session': existing.sessionToken,
          'tag': existing.tag,
          'nickname': existing.nickname,
          'restored': true,
        },
      );
    }

    final gate = room.admits(body['pin'] as String?);
    if (gate.error != null) {
      return (
        status: gate.error == 'room_closed' ? 403 : 401,
        body: {
          'error': gate.error,
          if (gate.retryAfterSeconds > 0) 'retryAfter': gate.retryAfterSeconds,
        },
      );
    }

    // 입장과 이름 바꾸기가 **같은 자**를 쓴다. 규칙이 두 곳에 있으면 한쪽만
    // 고쳐져서, 입장 때는 막히는 이름이 바꾸기로는 통과한다.
    final nickname = Room.cleanNickname(body['nickname'] as String?);
    if (nickname == null) {
      return (status: 400, body: {'error': 'bad_nickname'});
    }
    final p = room.seat(nickname);
    if (p == null) return (status: 409, body: {'error': 'room_full'});
    return (
      status: 200,
      body: {'session': p.sessionToken, 'tag': p.tag, 'nickname': p.nickname},
    );
  }

  // ---- WebSocket: /ws?room=.. ----

  /// 같은 망에서 우리 포트로 곧장 들어오는 길.
  ///
  /// 여기서 하는 일은 **어느 방인지 정하고 통로를 씌우는 것뿐**이다.
  /// 붙은 뒤의 절차(인증 대기 → 자리 잇기 → 정리)는 [serveParticipant] 가
  /// 갖고 있고, 랑데부로 들어오는 길도 같은 문을 지난다.
  Handler _wsHandler() {
    return (Request req) {
      if (req.url.path != 'ws') return Response.notFound('');
      final room = byToken(req.url.queryParameters['room']);
      if (room == null) return Response.forbidden('bad room');
      if (!room.open) return Response.forbidden('room closed');

      return webSocketHandler(
        (WebSocketChannel channel, _) => serveParticipant(
          room: room,
          link: WebSocketLink(channel),
          inbound: channel.stream,
        ),
        // 반쯤 죽은 소켓(터널 끊김·폰 절전)은 onDone 이 안 온다. 서버가
        // 주기적으로 찔러 봐야 "접속 중" 으로 남은 유령이 안 쌓인다.
        pingInterval: const Duration(seconds: 20),
      )(req);
    };
  }

  static Response _json(Map<String, dynamic> body, [int status = 200]) =>
      Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );
}
