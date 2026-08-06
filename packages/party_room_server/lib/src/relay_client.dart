import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:party_room_relay/protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'participant_gate.dart';
import 'participant_link.dart';
import 'room_server.dart';

/// 랑데부에 걸어 둔 상태.
enum RelayStatus {
  off,
  connecting,

  /// 코드를 받았다 — 이제 어느 망에서든 들어올 수 있다.
  ready,

  /// 끊겼고 다시 붙는 중. 코드는 그대로 유지된다.
  retrying,

  /// 릴레이가 거절했다(판 불일치 등). 다시 시도해도 소용없다.
  denied,
}

/// 호스트 쪽 랑데부 클라이언트.
///
/// **바깥으로 나가는 연결 하나**가 전부다. 인바운드 포트도, 포트 포워딩도,
/// 방화벽 예외도 필요 없다 — 호스트가 나가서 붙고, 참가자는 릴레이로 온다.
/// 닌텐도 NEX 에 콘솔이 붙어 두는 것과 같은 자리다.
///
/// 방과 게임은 이것의 존재를 모른다. 릴레이로 들어온 참가자도
/// [serveParticipant] 라는 **같은 문**을 지나 [Room] 에 앉는다 — 다른 것은
/// [ParticipantLink.path] 하나뿐이고, 그건 자료 정책과 진단 화면만 본다.
class RelayClient {
  RelayClient({
    required this.server,
    required this.relayBase,
    required this.secret,
    this.code,
    this.onChanged,
    Duration Function(int attempt)? backoff,
  }) : _backoff = backoff ?? _defaultBackoff;

  /// 방을 갖고 있는 쪽. 참가자가 어느 방으로 갈지는 여기서 고른다.
  final RoomServer server;

  /// 랑데부 주소 — `https://party.example.com` 또는 `http://127.0.0.1:8080`.
  final String relayBase;

  /// 이 호스트임을 증명하는 값. **재접속 때 같은 코드를 되찾는 열쇠**라,
  /// 앱이 저장해 두고 매번 같은 것을 넘겨야 파티 중간에 코드가 안 바뀐다.
  final String secret;

  /// 지난번에 받은 코드. 릴레이가 아직 비워 두고 있으면 그대로 돌려준다.
  String? code;

  final void Function()? onChanged;
  final Duration Function(int) _backoff;

  RelayStatus status = RelayStatus.off;

  /// 왜 거절당했는지 — [RelayStatus.denied] 일 때만 채워진다.
  String? deniedReason;

  /// 저쪽 릴레이가 무엇을 돌리고 있는가 (`/healthz`).
  ///
  /// **참가자 화면은 릴레이 이미지에 구워져 있다.** 앱이 화면을 고쳐도
  /// 이미지를 다시 굽지 않으면 밖에서 들어온 사람만 옛 화면을 받고, 증상이
  /// "들어와지는데 뭔가 이상하다" 라 원인을 찾기 아주 나쁘다. 저쪽 판을
  /// 읽어 두면 사람이 화면·CLI 에서 바로 견줘 볼 수 있다.
  String? serverVersion;
  String? serverAssets;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  bool _stopped = false;

  final Map<String, _Conn> _conns = {};

  static Duration _defaultBackoff(int attempt) =>
      Duration(seconds: [1, 2, 4, 8, 15, 30][attempt.clamp(0, 5)]);

  /// 참가자에게 줄 주소. 코드가 없으면 null.
  ///
  /// `https` 로 만든다 — 참가자 화면이 secure context 여야 브라우저가 제
  /// 기능을 다 열어 준다(로컬 http 로는 못 쓰는 것들이 있다).
  String? get joinBase {
    if (code == null) return null;
    final b = relayBase.replaceFirst(RegExp(r'^ws'), 'http');
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  /// 참가자가 이 방으로 들어오는 주소.
  String? joinUrl(String roomToken) {
    final base = joinBase;
    if (base == null) return null;
    return '$base/?c=$code&room=${Uri.encodeComponent(roomToken)}';
  }

  /// 새 비밀 하나. 앱이 처음 한 번 만들어 저장한다.
  static String newSecret([Random? rng]) {
    final r = rng ?? Random.secure();
    const abc =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return [for (var i = 0; i < 32; i++) abc[r.nextInt(abc.length)]].join();
  }

  Future<void> start() async {
    _stopped = false;
    await _open();
  }

  Future<void> stop() async {
    _stopped = true;
    _retry?.cancel();
    _retry = null;
    await _sub?.cancel();
    _sub = null;
    for (final c in _conns.values.toList()) {
      await c.inbound.close();
    }
    _conns.clear();
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;
    _set(RelayStatus.off);
  }

  void _set(RelayStatus s) {
    if (status == s) return;
    status = s;
    onChanged?.call();
  }

  Uri get _hostUri {
    final b = relayBase.replaceFirst(RegExp(r'^http'), 'ws');
    final trimmed = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
    return Uri.parse('$trimmed/host');
  }

  Future<void> _open() async {
    if (_stopped) return;
    _set(_attempt == 0 ? RelayStatus.connecting : RelayStatus.retrying);
    try {
      final ws = WebSocketChannel.connect(_hostUri);
      await ws.ready;
      _ws = ws;
      _sub = ws.stream.listen(
        _onFrame,
        onDone: _dropped,
        onError: (_) => _dropped(),
        cancelOnError: true,
      );
      _send({
        't': RelayFrame.hello,
        'v': relayProtocolVersion,
        'secret': secret,
        if (code != null) 'code': code,
      });
    } catch (_) {
      _dropped();
    }
  }

  void _dropped() {
    _sub?.cancel();
    _sub = null;
    _ws = null;
    // 릴레이가 끊기면 그 길로 들어온 사람들도 같이 끊긴다. 로컬로 들어온
    // 참가자는 아무 영향이 없다 — 그게 로컬 우선의 값어치다.
    for (final c in _conns.values.toList()) {
      c.inbound.close();
    }
    _conns.clear();
    if (_stopped || status == RelayStatus.denied) return;
    _set(RelayStatus.retrying);
    _retry?.cancel();
    _retry = Timer(_backoff(_attempt++), _open);
  }

  void _send(Map<String, Object?> m) {
    try {
      _ws?.sink.add(encodeRelay(m));
    } catch (_) {}
  }

  void _onFrame(Object? raw) {
    final m = decodeRelay(raw);
    if (m == null) return;
    switch (m['t']) {
      case RelayFrame.ready:
        _attempt = 0;
        code = m['code'] as String?;
        _set(RelayStatus.ready);
        unawaited(_readHealth());
        onChanged?.call();
      case RelayFrame.denied:
        deniedReason = m['reason'] as String?;
        _set(RelayStatus.denied);
      case RelayFrame.open:
        _openConn(m['c'] as String?, m['q'] as String? ?? '');
      case RelayFrame.data:
        _conns[m['c']]?.inbound.add(m['d']);
      case RelayFrame.close:
        _conns.remove(m['c'])?.inbound.close();
      case RelayFrame.http:
        _answer(m);
      case RelayFrame.ping:
        _send({'t': RelayFrame.pong});
    }
  }

  /// 저쪽이 무엇을 돌리는지 한 번 읽어 둔다. 실패해도 파티는 계속 돈다.
  Future<void> _readHealth() async {
    final base = joinBase;
    if (base == null) return;
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final res = await (await http.getUrl(
        Uri.parse('$base/healthz'),
      )).close().timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      serverVersion = j['version'] as String?;
      serverAssets = j['assets'] as String?;
      onChanged?.call();
    } catch (_) {
      // 옛 릴레이는 /healthz 가 없다. 그것 때문에 못 쓰게 하지는 않는다.
    } finally {
      http.close(force: true);
    }
  }

  void _openConn(String? id, String query) {
    if (id == null) return;
    final room = server.byToken(Uri.splitQueryString(query)['room']);
    if (room == null || !room.open) {
      // 없는 방으로 온 사람은 여기서 돌려보낸다 — 통로를 열어 두면
      // 릴레이에 유령 연결이 쌓인다.
      _send({'t': RelayFrame.close, 'c': id});
      return;
    }
    // 린트가 여기서만 보면 안 닫힌 것처럼 보인다. 실제로는 [_conns] 가 들고
    // 있다가 셋 중 하나에서 닫는다: 참가자가 끊길 때(close 프레임), 통로를
    // 우리가 접을 때([_closeConn]), 릴레이가 끊길 때([_dropped]).
    // ignore: close_sinks
    final inbound = StreamController<dynamic>();
    final link = _RelayLink(this, id);
    _conns[id] = _Conn(inbound, link);
    serveParticipant(room: room, link: link, inbound: inbound.stream);
  }

  void _answer(Map<String, dynamic> m) {
    final id = m['i'] as String?;
    if (id == null) return;
    if (m['p'] != 'api/join') {
      _send({'t': RelayFrame.httpRes, 'i': id, 's': 404, 'b': '{}'});
      return;
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(m['b'] as String? ?? '') as Map<String, dynamic>;
    } catch (_) {
      _send({
        't': RelayFrame.httpRes,
        'i': id,
        's': 400,
        'b': jsonEncode({'error': 'bad_request'}),
      });
      return;
    }
    // 비밀번호 검사·연타 잠금·정원 판정은 로컬과 **같은 판정기**를 쓴다.
    final r = server.handleJoin(body);
    _send({
      't': RelayFrame.httpRes,
      'i': id,
      's': r.status,
      'b': jsonEncode(r.body),
    });
  }

  void _closeConn(String id) {
    final c = _conns.remove(id);
    if (c == null) return;
    _send({'t': RelayFrame.close, 'c': id});
    c.inbound.close();
  }
}

class _Conn {
  _Conn(this.inbound, this.link);
  final StreamController<dynamic> inbound;
  final _RelayLink link;
}

/// 랑데부를 지나 참가자에게 닿는 통로.
///
/// 방은 이것과 [WebSocketLink] 를 구분하지 않는다 — [ParticipantLink] 가
/// 요구하는 것은 "프레임 하나 보내기, 닫기" 뿐이고 둘 다 그걸 한다.
class _RelayLink implements ParticipantLink {
  _RelayLink(this._client, this._id);

  final RelayClient _client;
  final String _id;

  @override
  LinkPath get path => LinkPath.relay;

  @override
  void send(String frame) =>
      _client._send({'t': RelayFrame.data, 'c': _id, 'd': frame});

  @override
  void sendJson(Map<String, dynamic> message) => send(jsonEncode(message));

  @override
  Future<void> close() async => _client._closeConn(_id);
}
