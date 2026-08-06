import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'game_module.dart';
import 'participant_link.dart';
import 'player.dart';
import 'room_channels.dart';
import 'room_files.dart';
import 'room_limits.dart';

export 'player.dart';

/// 방 하나 — 참가자·대화·자료·진행 중인 판.
///
/// 예전에는 이 상태가 `RoomServer` 안에 있었고, 그래서 **방이 하나뿐**이었다.
/// 호스트 입장에서는 금요 모임방과 회사방이 각자 QR 을 갖고 동시에 살아
/// 있는 편이 자연스럽다 — 친구 그룹마다 방이 따로다.
///
/// 마침 프로토콜은 처음부터 토큰으로 주소를 매기고 있었다(`?room=<토큰>`,
/// 모든 엔드포인트가 검사). 그래서 참가자 화면은 한 줄도 바뀌지 않는다:
/// 듣는 쪽([RoomServer])이 토큰으로 방을 찾아 넘겨주기만 하면 된다.
///
/// 보안 원칙:
/// - 방 토큰: QR 에 포함, 모든 요청에 필수
/// - 세션 토큰: 참가자별 발급, 자기 정보만 (전송에는 절대 안 싣는다)
/// - 입력 검증 + 인원 제한
class Room {
  Room({
    this.name = '',
    this.limits = const RoomLimits(),
    String? roomToken,
    DateTime? createdAt,
  }) : channels = RoomChannels(limits: limits),
       _files = RoomFiles(limits: limits),
       roomToken = roomToken ?? _randomToken(6),
       createdAt = createdAt ?? DateTime.now() {
    // 칸이 상한에 밀려 사라지면 그 칸의 자료도 함께 치운다.
    channels.onSectionDropped = (id) {
      _files.dropSection(id);
      _broadcastFiles();
    };
    // 빈 칸인지 판정하려면 자료가 있는지도 봐야 한다 — 칸은 파일을 모른다.
    channels.hasFiles = (id) => _files.inSection(id).isNotEmpty;
  }

  /// 호스트가 붙인 이름 — '금요 모임' 처럼. 비면 화면이 방 코드로 부른다.
  String name;

  /// 방을 만든 시각. 목록 정렬과 "언제 만든 방인지" 에 쓴다.
  final DateTime createdAt;

  /// 입장 비밀번호(4자리). null 이면 안 건다.
  ///
  /// 방 토큰(6자리, 31^6 ≈ 8.9억)이 여전히 주 관문이고 이건 **두 번째
  /// 자물쇠**다 — 링크가 엉뚱한 단톡방으로 넘어갔을 때를 막는 용도.
  /// 4자리는 1만 가지뿐이라 그것만으로는 약하지만, 토큰을 이미 가진
  /// 상대에게만 의미가 있고 아래 [_pinGate] 가 연타를 막는다.
  ///
  /// **원문은 이 맥의 저장 파일에만 있다.** 앱을 껐다 켜도 자물쇠가 소리 없이
  /// 풀리면 안 되므로 [toJson] 에는 실린다. 그 밖의 어디로도 — 폰으로 가는
  /// 프레임, 제어 API 응답, 상태 미러, 로그 — 나가지 않고 밖에서는
  /// [hasPin] 불리언만 보인다. `pin_secrecy_test.dart` 가 이 선을 지킨다.
  String? _pin;

  bool get hasPin => _pin != null;

  /// 4자리 숫자만 받는다. 빈 값·null 이면 해제.
  ///
  /// 자물쇠를 손대면 연타 기록도 함께 지운다. 안 그러면 친구들이 못 들어와서
  /// 호스트가 비밀번호를 바꿔 줬는데도 30초 동안 계속 튕긴다 — 원인이 화면
  /// 어디에도 안 보이는, 파티에서 제일 나쁜 종류의 고장이다.
  bool setPin(String? pin) {
    if (pin == null || pin.isEmpty) {
      _pin = null;
      _unlock();
      _touch();
      return true;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) return false;
    _pin = pin;
    _unlock();
    _touch();
    return true;
  }

  void _unlock() {
    _pinFails = 0;
    _pinLockedUntil = null;
  }

  int _pinFails = 0;
  DateTime? _pinLockedUntil;

  /// 연타 차단.
  ///
  /// 1만 가지는 초당 수백 번이면 금방 다 뒤진다. 다섯 번 틀리면 30초 쉬고,
  /// 그 뒤로도 계속 틀리면 쉬는 시간이 늘어난다 — 사람이 손으로 치는
  /// 속도에는 걸리지 않고 기계에는 걸린다.
  ({bool ok, int retryAfterSeconds}) _pinGate(String? given) {
    final now = DateTime.now();
    final until = _pinLockedUntil;
    if (until != null && now.isBefore(until)) {
      return (
        ok: false,
        retryAfterSeconds: until.difference(now).inSeconds + 1,
      );
    }
    if (given != null && given == _pin) {
      _pinFails = 0;
      _pinLockedUntil = null;
      return (ok: true, retryAfterSeconds: 0);
    }
    _pinFails++;
    if (_pinFails >= 5) {
      final wait = Duration(seconds: 30 * (1 << ((_pinFails - 5) ~/ 5)));
      _pinLockedUntil = now.add(wait);
    }
    return (ok: false, retryAfterSeconds: 0);
  }

  /// 열려 있는가.
  ///
  /// 이름 붙인 방은 호스트가 지울 때까지 산다(수명 타이머 없음). 그러면
  /// 지난달 링크도 살아 있게 되므로, 그 책임을 타이머가 아니라 **호스트가
  /// 스위치로** 진다 — 닫힌 방은 입장도 소켓 연결도 거절한다.
  bool open = true;

  /// 이 방이 지키는 한계값 전부 — 서버와 참가자 화면이 **같은 값**을 본다.
  final RoomLimits limits;

  final String roomToken;

  /// 방 정원 — 예전 이름. 정본은 [limits].
  int get maxPlayers => limits.players;

  final Map<String, Player> _players = {}; // sessionToken -> Player

  GameModule? _activeGame;
  GameModule? get activeGame => _activeGame;
  late final GameContext gameCtx = GameContext(
    players: () => players,
    broadcast: broadcast,
    sendTo: sendTo,
    onGameEvent: (event, data) {
      // 판이 움직였다는 뜻이니 방도 "바뀐 것" 으로 표시한다.
      //
      // 예전에는 이벤트를 흘리기만 했다. 그래서 **판 진행이 저장된 적이
      // 없었다** — 마피아 페이즈도, 사다리 공개도, 투표도. 채팅이나 입장
      // 같은 다른 일이 우연히 저장을 부르면 그때까지의 상태가 얹혀 남았을
      // 뿐이라, "진행 중이던 판이 복구된다" 는 기능이 사실상 운에 달려
      // 있었다(실측: 3줄 공개한 사다리가 재시작 후 0줄로 돌아왔다).
      //
      // 저장은 부르는 쪽에서 모아 친다 — 구슬은 굴러가는 동안 이벤트를
      // 초당 여러 번 낸다.
      _gameEventController.add((event, data));
      _touch();
    },
  );

  final _lobbyController = StreamController<List<Player>>.broadcast();
  Stream<List<Player>> get lobbyStream => _lobbyController.stream;
  List<Player> get players =>
      _players.values.where((p) => !p.kicked).toList(growable: false);

  final _gameEventController =
      StreamController<(String, Map<String, dynamic>)>.broadcast();
  Stream<(String, Map<String, dynamic>)> get gameEvents =>
      _gameEventController.stream;

  /// 상태 변경 시마다 호출 — 호스트 앱이 저장 트리거로 사용.
  void Function()? onStateChanged;

  /// 라이어 게임 커스텀 이미지 (메모리, 게임 시작 시 세팅).
  List<int>? liarImage;
  String liarImageMime = 'image/jpeg';

  // ---- 단톡(채팅) ----
  //
  // 방 전체 채널 하나가 아니라 **섹션**이다: '전체' 는 방이 열려 있는 내내
  // 살고, 게임을 시작할 때마다 그 판의 섹션이 열린다. 자세한 이유와 규칙은
  // [RoomChannels].
  final RoomChannels channels;

  final _chatController = StreamController<Map<String, dynamic>>.broadcast();

  /// 호스트 UI 가 실시간 수신에 쓴다.
  Stream<Map<String, dynamic>> get chatStream => _chatController.stream;

  /// 섹션 하나의 기록. 안 주면 지금 열린 섹션.
  List<Map<String, dynamic>> chatHistoryOf([
    String? sectionId,
  ]) => List.unmodifiable(
    (channels.byId(sectionId ?? channels.defaultId) ?? channels.room).messages,
  );

  /// 예전 이름 — 지금 열린 섹션의 기록.
  List<Map<String, dynamic>> get chatHistory => chatHistoryOf();

  /// 참가자별 마지막 발화 시각 — 도배 억제.
  final Map<String, DateTime> _lastChatAt = {};
  final Map<String, DateTime> _lastRenameAt = {};

  /// 호스트가 보내는 메시지.
  void hostChat(String text, {String? sectionId}) => _appendChat(
    tag: '',
    speaker: Speaker.host,
    text: text,
    sectionId: sectionId,
  );

  /// 사회자(자동 진행)가 보내는 메시지 — 호스트 발화와 구분해 표시한다.
  /// 판이 돌고 있으면 그 판 칸에 남는다 — 사회자의 말은 그 판의 기록이다.
  void mcChat(String text) =>
      _appendChat(tag: '', speaker: Speaker.mc, text: text);

  /// [nickname] 은 참가자 발화에만 의미가 있다. 호스트·사회자의 표시 이름은
  /// **화면이 붙인다** — 서버가 '호스트' 라고 적어 보내면 화면 언어가 여기
  /// 갇히고, 호스트와 사회자를 다르게 그릴 수도 없다([Speaker]).
  void _appendChat({
    required String tag,
    required String speaker,
    required String text,
    String nickname = '',
    String? sectionId,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final section = channels.writableId(sectionId);
    final msg = {
      'type': 'chat_msg',
      'section': section,
      'tag': tag,
      'speaker': speaker,
      if (nickname.isNotEmpty) 'nickname': nickname,
      // 표시는 300자면 충분하고, 무제한이면 붙여넣기 폭탄이 기록을 밀어낸다.
      'text': trimmed.length > limits.chatTextLength
          ? trimmed.substring(0, limits.chatTextLength)
          : trimmed,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    channels.append(section, msg);
    broadcast(msg);
    _chatController.add(msg);
    _touch();
  }

  /// 섹션 목록이 바뀌면 모두에게 알린다 — 폰의 칸 목록이 곧 이 값이다.
  void _broadcastSections() =>
      broadcast({'type': 'sections', 'sections': channels.toWire()});

  // ---- 자료 공유 ----

  final RoomFiles _files;
  List<SharedFile> get sharedFiles => _files.files;

  /// 칸 하나의 자료 — 호스트 화면이 칸별로 보여준다.
  List<SharedFile> sharedFilesIn(String sectionId) =>
      _files.inSection(sectionId);

  SharedFile? fileById(String id) => _files.byId(id);

  bool isSectionFull(String sectionId) => _files.isSectionFull(sectionId);

  String? quotaRefusal(String sectionId, String ownerTag, int bytes) =>
      _files.quotaRefusal(sectionId, ownerTag, bytes);

  /// 이 방의 자료가 쓰고 있는 용량 — 화면의 "n MB / 전체 m MB" 와
  /// 밀려난 칸을 치웠는지 확인하는 자리에서 쓴다.
  int get totalFileBytes => _files.totalBytes;

  /// 이 방의 업로드 사본이 사는 폴더 경로. 아직 아무도 안 올렸으면 null.
  /// (경로 문자열로 내보낸다 — 이 파일은 dart:io 를 안 들여온다.)
  String? get uploadDirPath => _files.uploadDir?.path;

  /// 이 방이 지워졌는지. 지우기는 되돌리지 않는다.
  bool _closed = false;

  /// "이 방의 지금 내용물" 세대. 비우기가 이것을 올린다.
  ///
  /// 불리언 문 하나로는 부족했다 — 비우기는 방을 살려 두는 손잡이라 끝나면
  /// 문이 다시 열리는데, 그 사이에 시작된 느린 업로드는 문이 닫혔던 것을
  /// 보지 못하고 통과했다. 시작할 때 본 세대와 다 쓰고 난 세대가 다르면
  /// 그 파일은 이미 없어진 방의 것이다.
  int _generation = 0;

  /// 참가자가 올린 바이트를 받아 칸에 등록한다.
  ///
  /// 거절 사유가 있으면 파일 대신 사유를 돌려준다. 쿼터의 **최종 판정은
  /// [RoomFiles.saveUpload] 안**에서 난다 — 여기서 미리 물어보고 본문을 받는
  /// 동안 남이 끼어들 수 있기 때문이다.
  ///
  /// 방이 이미 닫혔으면 받지 않는다. 예전에는 느린 업로드가 본문을 다 보내는
  /// 사이에 호스트가 방을 비우거나 지워도 그대로 등록됐다 — 비운 방에 옛
  /// 파일이 되살아나고, 지운 방은 임시 폴더를 새로 만들어 놓고는 아무도
  /// 치우지 않아 디스크에 남았다.
  Future<({SharedFile? file, String? refusal})> saveUpload({
    required String name,
    required List<int> bytes,
    required Player uploader,
    required String sectionId,
  }) async {
    if (_closed) return (file: null, refusal: '방이 닫혔습니다');
    final startedAt = _generation;
    final r = await _files.saveUpload(
      id: _randomToken(8),
      name: name,
      bytes: bytes,
      ownerTag: uploader.tag,
      ownerName: uploader.nickname,
      sectionId: sectionId,
    );
    // 쓰는 사이에 방이 지워졌거나 비워졌으면 되돌린다.
    if ((_closed || _generation != startedAt) && r.file != null) {
      await _files.remove(r.file!.id);
      return (file: null, refusal: '방이 닫혔습니다');
    }
    if (r.file == null) return r;
    _broadcastFiles();
    _touch();
    return r;
  }

  final _filesController = StreamController<void>.broadcast();

  /// 호스트 UI 용 — 참가자 업로드는 HTTP 로 들어와 컨트롤러가 모른다.
  Stream<void> get filesStream => _filesController.stream;

  /// 파일 목록이 바뀔 때마다 전원에게 새 목록을 민다.
  void _broadcastFiles() {
    broadcast({'type': 'files', 'files': _files.toWire()});
    _filesController.add(null);
  }

  /// 호스트가 디스크의 파일을 공유한다. 성공하면 등록된 항목을 돌려준다.
  /// 섹션을 안 주면 지금 열린 칸(판이 돌면 그 판)에 들어간다.
  Future<SharedFile?> shareFile(String path, {String? sectionId}) async {
    final section = channels.writableId(sectionId);
    if (_files.isSectionFull(section)) return null;
    final shared = await _files.shareHostFile(
      id: _randomToken(8),
      path: path,
      sectionId: section,
    );
    if (shared != null) _broadcastFiles();
    return shared;
  }

  /// 판 하나의 자료를 통째로 치운다. 지운 개수를 돌려준다.
  Future<int> removeSectionFiles(String sectionId) async {
    final n = await _files.removeSection(sectionId);
    if (n > 0) {
      _broadcastFiles();
      _touch();
    }
    return n;
  }

  Future<bool> removeFile(String id) async {
    final ok = await _files.remove(id);
    if (ok) _broadcastFiles();
    return ok;
  }

  static String _randomToken(int len) {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // 혼동 문자 제외
    final rng = Random.secure();
    return List.generate(len, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// 방 안에서 겹치지 않는 공개 식별자 4자를 뽑는다.
  ///
  /// 세션 토큰과 무관하게 새로 뽑는다 — 토큰을 잘라 쓰면 로비 화면에
  /// 인증값의 앞자리가 그대로 노출된다.
  String _newTag() {
    final taken = _players.values.map((p) => p.tag).toSet();
    for (var i = 0; i < 64; i++) {
      final t = _randomToken(4);
      if (!taken.contains(t)) return t;
    }
    // 31^4 = 92만 가지에 최대 20명이라 여기까지 올 일은 없지만,
    // 만에 하나 왔다면 겹치지 않는 값을 반드시 돌려줘야 한다.
    var n = 0;
    while (taken.contains('Z${n.toString().padLeft(3, '0')}')) {
      n++;
    }
    return 'Z${n.toString().padLeft(3, '0')}';
  }

  /// 같은 방을 그대로 두고 안을 비운다.
  ///
  /// 방을 **지우는 것과 다르다**: 토큰과 이름이 살아 있으므로 나눠준 QR·링크가
  /// 계속 통한다. 같은 친구 그룹으로 다음 판을 새로 시작할 때 쓰는 손잡이다
  /// — 링크를 다시 뿌리지 않아도 된다.
  Future<void> clear() async {
    // 세대를 올린다 — 이미 시작된 업로드는 다 쓰고 나서 이것을 보고
    // 자기 파일이 없어진 방의 것임을 안다.
    _generation++;
    try {
      _activeGame?.end(gameCtx);
      _activeGame = null;
      // 닫힘을 **기다린다**. 안 기다리면 비우기가 끝났다고 돌아온 뒤에도
      // 옛 소켓이 살아 있어, 바로 이어지는 판단('아무도 없다')이 틀린다.
      await Future.wait([
        for (final p in _players.values)
          if (p.link != null)
            (() async {
              p.link!.sendJson({'type': 'kicked'});
              await p.link!.close();
            })(),
      ]);
      _players.clear();
      _lastChatAt.clear();
      await _files.dispose();
      // 칸을 처음 상태로 — '전체' 하나만 남는다.
      channels.restore(RoomChannels(limits: limits).toJson());
      liarImage = null;
    } finally {
      // 비운 뒤에도 방은 계속 산다 — 세대만 바뀐 것이라 닫지 않는다.
    }
    _notifyLobby();
    _touch();
  }

  /// 이 방의 소켓을 모두 닫고 임시 파일을 치운다. 되돌리지 않는다.
  Future<void> dispose() async {
    _closed = true;
    // 참가자 소켓도 인증 전 소켓과 **같이** 기다린다. 예전에는 이쪽만
    // 안 기다려서, `dispose()` 가 "다 닫았다" 고 돌아온 뒤에도 소켓이
    // 살아 있었다 — 방을 지우고 곧바로 세는 쪽이 틀린 답을 봤다.
    await Future.wait([
      for (final p in _players.values)
        if (p.link != null) p.link!.close(),
    ]);
    // 아직 인증 프레임을 안 보낸 통로도 닫는다. 예전에는 이것들이
    // [Player.link] 에 없어서 살아남았고, 방이 지워진 뒤에 인증하면
    // 참가자 맵이 아직 남아 있어 붙는 데 성공했다 — 지운 방에 계속
    // 채팅·게임 메시지를 보낼 수 있었다.
    for (final c in _pendingLinks.toList()) {
      try {
        await c.close();
      } catch (_) {}
    }
    _pendingLinks.clear();
    await _files.dispose();
  }

  /// 열렸지만 아직 누구인지 밝히지 않은 통로.
  final Set<ParticipantLink> _pendingLinks = {};

  /// 인증 전 통로를 방이 알고 있게 한다 — 방이 지워질 때 함께 닫으려고.
  void watchPending(ParticipantLink c) {
    if (_closed) {
      c.close();
      return;
    }
    _pendingLinks.add(c);
  }

  void unwatchPending(ParticipantLink c) => _pendingLinks.remove(c);

  /// 지워진 방인지 — 붙이기 전에 확인한다.
  bool get closed => _closed;

  // ---- 게임 모듈 ----

  void startGame(GameModule game) {
    _activeGame?.end(gameCtx);
    _activeGame = game;
    // 칸을 열지는 **종목이 정한다**([GameModule.ownsSection]). 방 서버가
    // 일괄로 열면 칸 쓸 일 없는 종목까지 빈 칸을 남긴다.
    if (game.ownsSection) channels.openGame(game.id, game.name);
    game.start(gameCtx);
    _broadcastSections();
    _broadcastRoomStatus();
    _touch();
  }

  Map<String, dynamic> _roomStatus() => {
    'type': 'room_status',
    'gameActive': _activeGame != null,
    if (_activeGame != null) 'gameName': _activeGame!.name,
  };

  void _broadcastRoomStatus() => broadcast(_roomStatus());

  void endGame() {
    _activeGame?.end(gameCtx);
    _activeGame = null;
    // 말이 오간 칸은 남기고 쓰기만 닫는다 — 나중에 그 판만 펼쳐 볼 수
    // 있어야 한다. 아무것도 없던 칸은 여기서 사라진다.
    channels.closeLiveGame();
    broadcast({'type': 'scene', 'scene': 'lobby'});
    _broadcastSections();
    _broadcastRoomStatus();
    _touch();
  }

  // ---- 강퇴 ----

  void kick(String sessionToken) {
    final p = _players[sessionToken];
    if (p == null) return;
    p.kicked = true;
    p.link?.sendJson({'type': 'kicked'});
    p.link?.close();
    p.link = null;
    p.lastSeen = DateTime.now();
    _notifyLobby();
    _broadcastLobby();
    _touch();
  }

  /// 접속 중이 아닌 참가자를 방에서 제거하고 몇 명을 지웠는지 돌려준다.
  ///
  /// 끊긴 참가자는 재접속을 위해 자리를 남겨 두지만, 방치하면 유령이 쌓여
  /// 정원(maxPlayers)을 유령이 다 먹는다 — 복구된 방에서 실제로 겪었다.
  /// 게임 진행 중에는 부르지 말 것: 명단(roster)은 시작 시점에 고정돼 있어
  /// 방 참가자를 지워도 게임은 그 자리를 계속 참조한다.
  int pruneDisconnected() {
    final gone = _players.values
        .where((p) => !p.connected)
        .map((p) => p.sessionToken)
        .toList();
    for (final token in gone) {
      _players.remove(token);
    }
    if (gone.isNotEmpty) {
      _notifyLobby();
      _broadcastLobby();
      _touch();
    }
    return gone.length;
  }

  // ---- 상태 저장/복구 (호스트 앱 재시작 대비) ----

  Map<String, dynamic> toJson() => {
    // 저장 시점 — 접속 중이던 참가자의 lastSeen 이 비어 있으므로,
    // 명단이 얼마나 늙었는지 재는 기준이 된다.
    'savedAt': DateTime.now().millisecondsSinceEpoch,
    'roomToken': roomToken,
    'name': name,
    'open': open,
    // 비밀번호는 이 맥의 저장소에만 있고 전송에는 절대 안 실린다.
    if (_pin != null) 'pin': _pin,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'channels': channels.toJson(),
    'players': _players.values.map((p) => p.toJson()).toList(),
    'game': _activeGame == null
        ? null
        : {'id': _activeGame!.id, 'state': _activeGame!.toJson()},
    // 자료함도 함께 남긴다. 예전에는 목록이 통째로 빠져 있어서, 앱을 껐다
    // 켜면 방·대화는 돌아오는데 나눠 둔 자료만 사라졌다.
    'files': _files.toJson(),
  };

  /// 저장분에서 자료 목록을 되살린다 — 디스크에 남아 있는 것만.
  void restoreFiles(List<dynamic>? raw) => _files.restore(raw);

  /// 저장된 스냅샷으로 참가자 목록 복원. 게임 복원은 [restoreGame] 로.
  void restorePlayers(List<dynamic> playerJsons) {
    for (final j in playerJsons) {
      final p = Player.fromJson(j as Map<String, dynamic>);
      _players[p.sessionToken] = p;
    }
    // 태그 도입 이전 상태 파일에는 태그가 없다. 방을 이어받는 김에 채워 준다.
    for (final p in _players.values) {
      if (p.tag.isEmpty) p.tag = _newTag();
    }
    _notifyLobby();
  }

  void restoreGame(GameModule game, Map<String, dynamic> state) {
    _activeGame = game;
    game.restore(gameCtx, state);
    // 판을 되살렸으면 그 판의 칸도 다시 연다. 예전에는 칸 복구가 전부
    // `live=false` 로 떨어져서, 복구 직후 판은 돌고 있는데 열린 판 칸은
    // 없는 상태가 됐다 — 이어지는 사회자 대사와 업로드가 그 판이 아니라
    // '전체' 칸에 쌓여, 파티가 끝나고 "그 판 때 사진" 을 못 찾게 된다.
    if (!game.ownsSection) return;
    final mine = channels.sections.lastWhere(
      (s) => s.kind == SectionKind.game && s.gameId == game.id,
      orElse: () => channels.openGame(game.id, game.name),
    );
    channels.makeLive(mine.id);
  }

  /// 쓸 수 있는 닉네임인가. 다듬은 값을 주고, 못 쓰면 null.
  ///
  /// **입장과 이름 바꾸기가 같은 자를 쓴다.** 규칙이 두 곳에 있으면 한쪽만
  /// 고쳐져서, 입장 때는 막히는 이름이 바꾸기로는 통과한다.
  static String? cleanNickname(String? raw) {
    final n = (raw ?? '').trim();
    if (n.isEmpty || n.length > 12) return null;
    return n;
  }

  /// 참가자가 보낸 프레임 하나. 서버가 소켓에서 받아 넘긴다.
  void handleMessage(Player from, dynamic raw) {
    if (raw is! String) return;
    if (raw.length > limits.messageBytes) {
      from.link?.close();
      return;
    }
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'ping':
        from.link?.sendJson({'type': 'pong'});
      case 'rename':
        // 이름은 바뀔 수 있어야 한다. 오타 하나로 파티 내내 그 이름을 달고
        // 다니게 두지 않는다 — 태그(4자)는 그대로라 사람 특정에는 지장 없다.
        final want = cleanNickname(msg['nickname'] as String?);
        if (want == null || want == from.nickname) return;
        // 로비 브로드캐스트가 따라오므로 연타를 막는다. 채팅과 같은 간격.
        final lastRename = _lastRenameAt[from.sessionToken];
        final renameNow = DateTime.now();
        if (lastRename != null &&
            renameNow.difference(lastRename) <
                Duration(milliseconds: limits.chatIntervalMs)) {
          return;
        }
        _lastRenameAt[from.sessionToken] = renameNow;
        from.nickname = want;
        // 본인에게도 알린다 — 화면이 낙관적으로 바꿔 놓고 서버가 거절하면
        // 둘이 어긋난 채로 남는다.
        from.link?.sendJson({'type': 'renamed', 'nickname': want});
        _notifyLobby();
        _broadcastLobby();
        _touch();
      case 'chat':
        // 도배 억제 — 너무 빨리 연타하면 조용히 버린다. 에러를 돌려주면
        // 클라이언트가 재시도해서 더 시끄러워진다. 간격의 정본은 RoomLimits.
        final last = _lastChatAt[from.sessionToken];
        final now = DateTime.now();
        if (last != null &&
            now.difference(last) <
                Duration(milliseconds: limits.chatIntervalMs)) {
          return;
        }
        _lastChatAt[from.sessionToken] = now;
        _appendChat(
          tag: from.tag,
          speaker: Speaker.player,
          nickname: from.nickname,
          text: msg['text'] as String? ?? '',
          sectionId: msg['section'] as String?,
        );
      default:
        _activeGame?.onMessage(gameCtx, from, msg);
    }
  }

  // ---- 전송 유틸 ----

  List<Map<String, dynamic>> lobbySnapshot() => players
      .map(
        (p) => {
          'tag': p.tag,
          'nickname': p.nickname,
          'connected': p.connected,
          if (p.lastSeen != null)
            'lastSeenMs': p.lastSeen!.millisecondsSinceEpoch,
        },
      )
      .toList();

  void _notifyLobby() => _lobbyController.add(players);

  void _broadcastLobby() =>
      broadcast({'type': 'lobby', 'players': lobbySnapshot()});

  void broadcast(Map<String, dynamic> msg) {
    // 한 번만 직렬화한다 — 방에 스무 명이면 스무 번 할 이유가 없다.
    final s = jsonEncode(msg);
    for (final p in players) {
      // **한 명이 터져도 나머지는 받는다.** 탭을 닫은 사람의 통로는 sink 가
      // 먼저 닫히고 onDone 은 조금 뒤에 오므로, 그 틈의 브로드캐스트는 닫힌
      // 통로에 쓰게 된다. 그때 예외가 여기로 올라오면 **뒷사람들이 프레임을
      // 통째로 놓친다** — 파티에서 그건 폰 몇 대가 엉뚱한 화면에 멈춰 있는
      // 것으로 나타나고, 아무도 원인을 모른다.
      try {
        p.link?.send(s);
      } catch (_) {}
    }
  }

  void sendTo(String sessionToken, Map<String, dynamic> msg) {
    _players[sessionToken]?.link?.sendJson(msg);
  }

  void _touch() => onStateChanged?.call();

  // ---- 입장·재입장 (서버가 HTTP 로 받아 넘긴다) ----

  /// 입장을 받아 줄지 판정한다. 비밀번호가 걸려 있으면 여기서 검사한다.
  ///
  /// 이미 자리가 있는 사람(세션 복구)은 이 관문을 다시 지나지 않는다 —
  /// 새로고침할 때마다 비밀번호를 다시 묻는 앱은 아무도 안 쓴다.
  ({String? error, int retryAfterSeconds}) admits(String? pin) {
    if (!open) return (error: 'room_closed', retryAfterSeconds: 0);
    if (!hasPin) return (error: null, retryAfterSeconds: 0);
    final gate = _pinGate(pin);
    if (gate.ok) return (error: null, retryAfterSeconds: 0);
    return (
      error: gate.retryAfterSeconds > 0 ? 'pin_locked' : 'pin_required',
      retryAfterSeconds: gate.retryAfterSeconds,
    );
  }

  /// 새 참가자를 앉힌다. 정원이 찼거나 방이 닫혔으면 null.
  /// 자리가 없을 때, 이만큼 안 보인 사람은 비켜 준 것으로 본다.
  ///
  /// 폰이 잠기거나 지하철에 들어간 사람의 자리를 뺏으면 안 되므로 넉넉히
  /// 잡는다. 여기 걸리는 것은 사실상 **지난 파티 손님**이다.
  static const _yieldSeatAfter = Duration(minutes: 30);

  Player? seat(String nickname) {
    if (!open) return null;
    if (players.length >= limits.players && !_freeStaleSeat()) return null;
    final session = _randomToken(16);
    final p = Player(sessionToken: session, nickname: nickname, tag: _newTag());
    _players[session] = p;
    _notifyLobby();
    _broadcastLobby();
    _touch();
    return p;
  }

  /// 정원이 찼을 때 오래 안 보인 사람 하나를 비켜 세운다. 비웠으면 true.
  ///
  /// 이름 붙인 방은 파티마다 다시 쓴다. 그래서 지난주 손님 20명이 명단에
  /// 그대로 남아 정원을 다 먹고, **실제로는 한 명밖에 없는 방인데 아무도
  /// 못 들어오는** 상태가 된다(테스트 중 실제로 걸렸다: 명단 20 · 접속 1).
  /// 손잡이는 `room prune` 으로 이미 있었지만, 파티 중에 호스트가 그것을
  /// 알고 있을 리 없다 — 문 앞에서 막히면 그냥 앱이 고장 난 것으로 보인다.
  ///
  /// 판이 도는 중에는 건드리지 않는다: 명단은 판 시작 시점에 고정돼 있어
  /// 자리를 지우면 게임이 없는 사람을 계속 가리킨다.
  bool _freeStaleSeat() {
    if (_activeGame != null) return false;
    final now = DateTime.now();
    Player? oldest;
    for (final p in _players.values) {
      if (p.connected) continue;
      final seen = p.lastSeen;
      // **lastSeen 이 없는 자리는 안 건드린다.** 그건 "떠난 사람" 이 아니라
      // 방금 `/api/join` 을 마치고 소켓을 여는 중인 사람이다 — 여럿이 동시에
      // QR 을 찍으면 서로를 쫓아내게 된다. (저장분에서 온 자리도 여기 걸리는데,
      // 그쪽은 스냅샷이 오래되면 복구 단계에서 이미 걷힌다.)
      if (seen == null) continue;
      if (now.difference(seen) < _yieldSeatAfter) continue;
      if (oldest == null || seen.isBefore(oldest.lastSeen!)) oldest = p;
    }
    if (oldest == null) return false;
    _players.remove(oldest.sessionToken);
    return true;
  }

  /// 이미 있는 세션인가 — 재입장(새로고침·재접속) 경로.
  Player? bySession(String? session) {
    final p = _players[session];
    return (p == null || p.kicked) ? null : p;
  }

  /// 통로가 붙었다. 자리를 잇고 밀린 것을 내려 준다.
  ///
  /// 같은 세션으로 새로 붙으면 이전 통로는 즉시 정리한다 — 참가자 SPA 는
  /// onclose 후 자동 재연결하고 세션은 localStorage 에 남으므로, 탭 두 개나
  /// 네트워크 전환 때 한 세션에 통로가 겹칠 수 있다.
  void attach(Player p, ParticipantLink link) {
    // 지워진 방에는 못 붙는다. 참가자 맵은 dispose 뒤에도 메모리에 남아
    // 있어서, 늦게 도착한 인증 프레임이 여기까지 올 수 있다.
    if (_closed) {
      link.close();
      return;
    }
    _pendingLinks.remove(link);
    final previous = p.link;
    p.link = link;
    p.lastSeen = null;
    if (previous != null) previous.close();

    _notifyLobby();
    _broadcastLobby();

    link.sendJson({
      'type': 'limits',
      ...limits.toWire(),
      // 자료 주고받기는 **같은 망일 때만** 연다. 랑데부로 들어온 사람에게
      // 30MB 업로드를 열어 주면 남의 서버 대역폭을 태운다(실시간 프레임과
      // 네 자릿수 차이다). 화면이 이 값을 보고 그 자리를 아예 감춘다 —
      // 눌러 봐야 413 이 오는 버튼을 남겨 두는 것이 제일 나쁘다.
      'canFiles': link.path != LinkPath.relay,
    });
    link.sendJson({
      'type': 'sections',
      'sections': channels.toWire(),
      'active': channels.defaultId,
    });
    for (final sec in channels.sections) {
      if (sec.messages.isEmpty) continue;
      link.sendJson({
        'type': 'chat_history',
        'section': sec.id,
        'items': sec.messages.toList(),
      });
    }
    link.sendJson({'type': 'files', 'files': _files.toWire()});
    link.sendJson(_roomStatus());
    _activeGame?.onReconnect(gameCtx, p);
  }

  /// 끊김 처리는 **자기 통로일 때만** 한다. 겹친 이전 통로의 onDone 이
  /// 뒤늦게 도착해 방금 붙은 것을 null 로 만들면, 참가자는 화면상 멀쩡한데
  /// 서버는 "끊김" 으로 보고 비밀 정보 전송이 조용히 사라진다.
  void detach(Player p, ParticipantLink link) {
    if (!identical(p.link, link)) return;
    p.link = null;
    p.lastSeen = DateTime.now();
    _notifyLobby();
    _broadcastLobby();
  }
}
