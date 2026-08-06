import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'protocol.dart';

/// 랑데부 서버 — 짝을 지어 주고 프레임을 날라 준다.
///
/// 하는 일이 셋뿐이다:
///   1. 참가자 화면(정적 파일)을 **https 로** 준다. 이게 없으면 다른 망의
///      폰은 애초에 열 페이지가 없다.
///   2. 호스트가 outbound 로 붙어 코드를 하나 받아 둔다. 인바운드 포트도,
///      NAT 설정도, 방화벽 예외도 필요 없다.
///   3. 코드로 찾아온 참가자와 호스트 사이에서 프레임을 옮긴다.
///
/// **방 안을 들여다보지 않는다.** 프레임은 통째로 지나가고, 게임 규칙은
/// 여기 없다. 그래서 파티룸이 바뀌어도 릴레이는 그대로 돈다.
///
/// 자료 올리기·내려받기는 [isRelayRefused] 로 막는다 — 한 사람 30MB 를
/// 날라 주기 시작하면 이것은 더 이상 가벼운 서버가 아니다.
class RelayServer {
  RelayServer({
    this.port = 8080,
    this.webRoot,
    this.publicBase,
    Random? random,
    this.version = 'dev',
    this.hostIdleTimeout = const Duration(seconds: 90),
    this.httpTimeout = const Duration(seconds: 8),
  }) : _rng = random ?? Random.secure();

  final int port;

  /// 참가자 SPA 가 들어 있는 디렉터리. 없으면 정적 파일을 주지 않는다
  /// (랑데부만 하는 모드 — 시험용).
  final Directory? webRoot;

  /// 참가자에게 알려 줄 바깥 주소 (`https://party.example.com`).
  /// 없으면 호스트가 받은 코드로 알아서 만든다.
  final String? publicBase;

  /// 이 이미지가 어느 소스에서 나왔는가. 배포 때 주입한다.
  ///
  /// 없으면 "지금 뭐가 돌고 있지" 에 답할 수 없고, 그 질문은 **뭔가 이상할
  /// 때** 나온다 — 그때 답을 못 하면 되돌릴 지점도 못 찾는다.
  final String version;

  final Duration hostIdleTimeout;
  final Duration httpTimeout;

  final Random _rng;
  final Map<String, _Host> _hosts = {};
  HttpServer? _server;
  Timer? _reaper;
  DateTime? _startedAt;

  /// 지금 주고 있는 참가자 화면의 지문.
  ///
  /// 화면은 이미지에 구워져 있어서, 앱이 화면을 고쳐도 이미지를 다시 굽지
  /// 않으면 **참가자는 조용히 옛 화면을 받는다.** 증상이 "들어와지는데
  /// 뭔가 이상하다" 라 원인을 찾기 아주 나쁘다. 지문을 밖으로 내면 호스트
  /// 앱이 자기 것과 비교해 먼저 알아챌 수 있다.
  String? _assetsFingerprint;
  String? get assetsFingerprint => _assetsFingerprint;

  /// 지금 붙어 있는 호스트 수 — 운영 확인용.
  int get hostCount => _hosts.length;

  /// 코드가 살아 있는가.
  bool has(String code) => _hosts.containsKey(code.toUpperCase());

  int get actualPort => _server?.port ?? port;

  Future<void> start() async {
    final handler = Cascade()
        .add(_hostSocket)
        .add(_participantSocket)
        .add(_http)
        .handler;
    _startedAt = DateTime.now();
    _assetsFingerprint = _fingerprintAssets();
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    // 반쯤 죽은 호스트가 코드를 물고 있으면, 그 코드로 오는 참가자는 영영
    // 대답을 못 듣는다. 주기적으로 찔러서 정리한다.
    _reaper = Timer.periodic(const Duration(seconds: 30), (_) => _reap());
  }

  Future<void> stop() async {
    _reaper?.cancel();
    for (final h in _hosts.values.toList()) {
      await h.dispose();
    }
    _hosts.clear();
    await _server?.close(force: true);
    _server = null;
  }

  /// 참가자 화면 파일들을 훑어 한 줄로 줄인다.
  ///
  /// 이름과 크기만 본다 — 내용을 다 읽으면 6MB 를 매번 해싱하게 되고,
  /// 우리가 잡으려는 것은 "다른 판이 실려 있다" 이지 비트 단위 변조가 아니다.
  String? _fingerprintAssets() {
    final root = webRoot;
    if (root == null) return null;
    try {
      final parts = <String>[];
      for (final f in root.listSync(recursive: true).whereType<File>()) {
        parts.add('${f.path.substring(root.path.length)}:${f.lengthSync()}');
      }
      parts.sort();
      return sha256
          .convert(utf8.encode(parts.join('\n')))
          .toString()
          .substring(0, 16);
    } catch (_) {
      return null;
    }
  }

  void _reap() {
    final now = DateTime.now();
    for (final h in _hosts.values.toList()) {
      if (now.difference(h.lastSeen) > hostIdleTimeout) {
        _hosts.remove(h.code);
        h.dispose();
      } else {
        h.send({'t': RelayFrame.ping});
      }
    }
  }

  String _newCode() {
    // 코드가 겹치면 **남의 파티에 들어가진다.** 확률이 낮아도 다시 뽑는다.
    for (var attempt = 0; attempt < 64; attempt++) {
      final c = [
        for (var i = 0; i < relayCodeLength; i++)
          relayCodeAlphabet[_rng.nextInt(relayCodeAlphabet.length)],
      ].join();
      if (!_hosts.containsKey(c)) return c;
    }
    throw StateError('빈 방 코드를 못 찾았다 — 릴레이가 가득 찼다');
  }

  // ---- 호스트 등록: /host ----

  // Cascade 는 404 를 '다음 handler 로' 로 읽는다 — 그래서 안 맞으면 404 다.
  FutureOr<Response> _hostSocket(Request req) {
    if (req.url.path != 'host') return Response.notFound('');
    return webSocketHandler((WebSocketChannel ws, _) {
      _Host? host;

      void bye() {
        if (host != null && identical(_hosts[host!.code], host)) {
          _hosts.remove(host!.code);
        }
        host?.dispose();
      }

      ws.stream.listen(
        (raw) {
          final m = decodeRelay(raw);
          if (m == null) return;
          host?.lastSeen = DateTime.now();

          if (host == null) {
            if (m['t'] != RelayFrame.hello) return;
            if (m['v'] != relayProtocolVersion) {
              ws.sink.add(
                encodeRelay({
                  't': RelayFrame.denied,
                  'reason': 'version',
                  'want': relayProtocolVersion,
                }),
              );
              ws.sink.close();
              return;
            }
            final secret = m['secret'] as String?;
            if (secret == null || secret.length < 16) {
              // 짧은 비밀은 코드를 빼앗길 수 있다는 뜻이다.
              ws.sink.add(
                encodeRelay({'t': RelayFrame.denied, 'reason': 'secret'}),
              );
              ws.sink.close();
              return;
            }
            // 재접속: 쓰던 코드를 **같은 비밀일 때만** 돌려준다. 이게 없으면
            // 아무나 남의 코드를 달라고 해서 그 파티를 가로챌 수 있다.
            final wanted = (m['code'] as String?)?.toUpperCase();
            var code = _newCode();
            if (wanted != null) {
              final prev = _hosts[wanted];
              if (prev == null) {
                code = wanted.length == relayCodeLength ? wanted : code;
              } else if (prev.secret == secret) {
                prev.dispose();
                _hosts.remove(wanted);
                code = wanted;
              }
              // 남의 코드였으면 조용히 새 코드를 준다 — 알려 줄 이유가 없다.
            }
            host = _Host(code: code, secret: secret, socket: ws);
            _hosts[code] = host!;
            ws.sink.add(
              encodeRelay({
                't': RelayFrame.ready,
                'code': code,
                'base': publicBase ?? '',
              }),
            );
            return;
          }

          switch (m['t']) {
            case RelayFrame.data:
              host!.toParticipant(m['c'] as String?, m['d']);
            case RelayFrame.close:
              host!.dropConn(m['c'] as String?);
            case RelayFrame.httpRes:
              host!.completeHttp(m);
            case RelayFrame.pong:
              break;
          }
        },
        onDone: bye,
        onError: (_) => bye(),
        cancelOnError: true,
      );
    })(req);
  }

  // ---- 참가자 소켓: /ws?c=CODE&room=… ----

  FutureOr<Response> _participantSocket(Request req) {
    if (req.url.path != 'ws') return Response.notFound('');
    final host = _hosts[(req.url.queryParameters['c'] ?? '').toUpperCase()];
    if (host == null) return Response.notFound('no such room code');

    return webSocketHandler((WebSocketChannel ws, _) {
      // 방 토큰은 그대로 넘긴다 — 릴레이는 어느 방인지 알 필요가 없고,
      // 호스트가 자기 방 목록에서 고른다.
      final id = host.openConn(ws, req.url.query);
      ws.stream.listen(
        (raw) => host.toHost(id, raw),
        onDone: () => host.closeConn(id),
        onError: (_) => host.closeConn(id),
        cancelOnError: true,
      );
    })(req);
  }

  // ---- HTTP: 정적 파일 + 입장 API ----

  Future<Response> _http(Request req) async {
    final path = req.url.path;

    // 살아 있나 · 뭐가 돌고 있나. k8s 프로브도 이걸 쓴다 — 뿌리(`/`)로
    // 찌르면 10초마다 52KB 짜리 화면을 만들어 버리게 된다.
    if (path == 'healthz') {
      return Response.ok(
        jsonEncode({
          'ok': true,
          'version': version,
          'assets': _assetsFingerprint,
          'hosts': _hosts.length,
          'uptimeSeconds': _startedAt == null
              ? 0
              : DateTime.now().difference(_startedAt!).inSeconds,
        }),
        headers: {
          'content-type': 'application/json',
          'cache-control': 'no-store',
        },
      );
    }

    // 릴레이에 태우지 않는 것부터 잘라낸다.
    if (isRelayRefused(path)) {
      return Response(
        413,
        body: jsonEncode({
          'error': 'relay_refused',
          'message': '자료 주고받기는 같은 Wi-Fi 에서만 됩니다',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    if (path == 'api/join' && req.method == 'POST') {
      final host = _hosts[(req.url.queryParameters['c'] ?? '').toUpperCase()];
      if (host == null) {
        return Response.notFound(jsonEncode({'error': 'bad_code'}));
      }
      final body = await req.readAsString();
      if (body.length > 4096) return Response(413, body: 'too large');
      final res = await host.ask(
        method: 'POST',
        path: 'api/join',
        body: body,
        timeout: httpTimeout,
      );
      if (res == null) {
        return Response(504, body: jsonEncode({'error': 'host_timeout'}));
      }
      return Response(
        res.status,
        body: res.body,
        headers: {'content-type': 'application/json'},
      );
    }

    return _static(req, path);
  }

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'application/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'json': 'application/json; charset=utf-8',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'svg': 'image/svg+xml',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
  };

  /// gzip 이 값어치를 하는 것만. 이미 압축된 것(jpg·png·woff2)을 또 밀면
  /// CPU 만 쓰고 바이트는 안 준다.
  static const _compressible = {'html', 'js', 'css', 'json', 'svg', 'ttf'};

  /// 뿌리 **안의** 파일로만 푼다. 밖으로 나가면 null.
  ///
  /// 지금 쓰는 Dart `HttpServer` 는 `..` 를 서버가 받기 전에 지운다 — 소켓에
  /// 날것으로 `GET /../x` 를 써 봐도 여기엔 `x` 로 도착한다. 그래서 **HTTP
  /// 로는 이 판정을 뚫는 요청을 만들 수 없다.**
  ///
  /// 그런데도 남겨 두는 이유는, 이게 없어지면 HTTP 스택을 바꾸거나 `%2F` 를
  /// 풀어 주게 되는 날 조용히 뚫리기 때문이다. 대신 판정을 **함수로 꺼내**
  /// 직접 시험한다 — 통합 테스트로는 이 방어가 도는지 알 수 없었다(떼어
  /// 내도 전부 통과했다).
  static File? resolveInside(Directory root, String name) {
    final rootPath = Directory(root.absolute.path).uri.normalizePath().path;
    final file = File('${root.absolute.path}/$name');
    final resolved = file.uri.normalizePath().path;
    if (!resolved.startsWith(rootPath)) return null;
    // 뿌리 그 자체(디렉터리)를 파일로 내주지 않는다.
    if (resolved.length == rootPath.length) return null;
    return file;
  }

  Future<Response> _static(Request req, String path) async {
    final root = webRoot;
    if (root == null) return Response.notFound('no web root');

    final name = path.isEmpty ? 'index.html' : path;
    final file = resolveInside(root, name);
    if (file == null) return Response.forbidden('nope');
    if (!await file.exists()) return Response.notFound('not found');

    final ext = name.split('.').last.toLowerCase();
    final headers = <String, String>{
      'content-type': _types[ext] ?? 'application/octet-stream',
      // 참가자 화면은 파티마다 같은 것을 다시 받는다. 폰트 하나가 2.45MB 다.
      'cache-control': ext == 'html' ? 'no-cache' : 'public, max-age=604800',
    };

    List<int> bytes = await file.readAsBytes();
    final wantsGzip = (req.headers['accept-encoding'] ?? '').contains('gzip');
    if (wantsGzip && _compressible.contains(ext) && bytes.length > 512) {
      bytes = gzip.encode(bytes);
      headers['content-encoding'] = 'gzip';
    }
    headers['content-length'] = '${bytes.length}';
    return Response.ok(bytes, headers: headers);
  }
}

/// 붙어 있는 호스트 하나.
class _Host {
  _Host({required this.code, required this.secret, required this.socket});

  final String code;
  final String secret;
  final WebSocketChannel socket;
  DateTime lastSeen = DateTime.now();

  final Map<String, WebSocketChannel> _conns = {};
  final Map<String, Completer<_HttpRes?>> _pending = {};
  int _seq = 0;

  void send(Map<String, Object?> m) {
    try {
      socket.sink.add(encodeRelay(m));
    } catch (_) {}
  }

  String openConn(WebSocketChannel ws, String query) {
    final id = 'c${_seq++}';
    _conns[id] = ws;
    send({'t': RelayFrame.open, 'c': id, 'q': query});
    return id;
  }

  void toHost(String id, Object? raw) {
    if (raw is! String) return;
    send({'t': RelayFrame.data, 'c': id, 'd': raw});
  }

  void toParticipant(String? id, Object? frame) {
    if (id == null || frame is! String) return;
    try {
      _conns[id]?.sink.add(frame);
    } catch (_) {}
  }

  void dropConn(String? id) {
    if (id == null) return;
    final ws = _conns.remove(id);
    try {
      ws?.sink.close();
    } catch (_) {}
  }

  /// 참가자 쪽이 끊었다 — 호스트에게 알린다.
  void closeConn(String id) {
    if (_conns.remove(id) == null) return;
    send({'t': RelayFrame.close, 'c': id});
  }

  Future<_HttpRes?> ask({
    required String method,
    required String path,
    required String body,
    required Duration timeout,
  }) {
    final id = 'r${_seq++}';
    final c = Completer<_HttpRes?>();
    _pending[id] = c;
    send({'t': RelayFrame.http, 'i': id, 'm': method, 'p': path, 'b': body});
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        return null;
      },
    );
  }

  void completeHttp(Map<String, dynamic> m) {
    final c = _pending.remove(m['i'] as String?);
    if (c == null || c.isCompleted) return;
    c.complete(
      _HttpRes(
        status: (m['s'] as num?)?.toInt() ?? 500,
        body: m['b'] as String? ?? '',
      ),
    );
  }

  Future<void> dispose() async {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
    // **먼저 비우고 사본으로 돈다.** 소켓을 닫으면 그 자리에서 `onDone` 이
    // 돌아 [closeConn] 이 같은 맵을 건드린다 — 돌면서 지우면 터진다.
    final conns = _conns.values.toList();
    _conns.clear();
    for (final ws in conns) {
      try {
        await ws.sink.close();
      } catch (_) {}
    }
    try {
      await socket.sink.close();
    } catch (_) {}
  }
}

class _HttpRes {
  _HttpRes({required this.status, required this.body});
  final int status;
  final String body;
}
