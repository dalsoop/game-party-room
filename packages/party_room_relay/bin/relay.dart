import 'dart:io';

import 'package:party_room_relay/party_room_relay.dart';

/// 랑데부 서버를 띄운다.
///
/// ```
/// dart run bin/relay.dart --port 8080 --web ./web --base https://party.example.com
/// dart compile exe bin/relay.dart -o relay      # 배포는 바이너리 하나
/// ```
///
/// TLS 는 앞단(Caddy·nginx·Cloudflare)이 맡는다. 참가자 화면이 https 라야
/// 브라우저가 secure context 를 열어 주므로 그것만은 꼭 필요하다.
Future<void> main(List<String> argv) async {
  String? valueOf(String flag) {
    final i = argv.indexOf(flag);
    return (i >= 0 && i + 1 < argv.length) ? argv[i + 1] : null;
  }

  final port =
      int.tryParse(valueOf('--port') ?? Platform.environment['PORT'] ?? '') ??
      8080;
  final webPath = valueOf('--web');
  final base = valueOf('--base');

  final web = webPath == null ? null : Directory(webPath);
  if (web != null && !web.existsSync()) {
    stderr.writeln('참가자 화면 디렉터리가 없습니다: $webPath');
    exit(64);
  }
  if (web == null) {
    stderr.writeln(
      '주의: --web 없이 띄웠습니다. 짝만 지어 주고 참가자 화면은 안 줍니다 — '
      '다른 망의 폰은 열 페이지가 없습니다.',
    );
  }

  final relay = RelayServer(
    port: port,
    webRoot: web,
    publicBase: base,
    // 배포 때 주입한다. 없으면 "지금 뭐가 돌고 있지" 에 답할 수 없다.
    version:
        valueOf('--version') ?? Platform.environment['RELAY_VERSION'] ?? 'dev',
  );
  await relay.start();
  stdout.writeln(
    '랑데부 서버 :${relay.actualPort}'
    '${base == null ? '' : ' · $base'}',
  );

  // 종료 신호에 소켓을 정리하고 나간다 — 호스트들이 재접속할 수 있게.
  for (final sig in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    sig.watch().listen((_) async {
      stdout.writeln('정리하고 종료합니다 (호스트 ${relay.hostCount})');
      await relay.stop();
      exit(0);
    });
  }
}
