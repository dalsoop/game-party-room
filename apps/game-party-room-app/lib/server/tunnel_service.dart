import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 인터넷 개방 터널을 앱이 직접 띄우고 관리한다.
///
/// 사용성 테스트의 판매 관문 1번: 예전에는 호스트가 터미널에서
/// `cloudflared tunnel --url …` 을 직접 치고 나온 주소를 복사해 붙여넣어야
/// 했다 — 일반 구매자는 여기서 끝난다. 이제 버튼 하나로:
/// cloudflared 를 찾아 실행하고, 출력에서 임시 주소를 읽어 방에 걸고,
/// 프로세스가 죽으면 바로 알린다.
///
/// cloudflared 를 번들하지 않는 이유: 바이너리 ~40MB 에, Cloudflare 가
/// 자동 업데이트를 전제로 배포한다. 설치는 한 줄(brew)이고, 없으면
/// 그 한 줄을 복사 버튼과 함께 보여 준다.
class TunnelService {
  Process? _proc;
  String? _url;

  String? get url => _url;
  bool get running => _proc != null;

  /// 띄운 터널의 흔적. 앱이 죽어도 남는다.
  ///
  /// 자식 프로세스는 부모가 죽어도 따라 죽지 않는다(launchd 가 입양한다).
  /// 그래서 앱을 강제 종료하면 cloudflared 가 남아 **공개 주소가 계속
  /// 살아 있는데 앱은 그 사실을 모른다** — 다음에 앱을 켜면 같은 포트에
  /// 새 방이 뜨고, 방 토큰은 복원되므로 어제 나눠준 링크가 오늘 방에
  /// 그대로 붙는다. 죽은 주소를 살아 있다고 보여주던 버그의 반대편이고
  /// 이쪽이 더 나쁘다. 흔적을 남겨 다음 실행에서 거둔다.
  static File get _pidFile {
    final home = Platform.environment['HOME'] ?? '.';
    return File('$home/Library/Application Support/PartyRoom/tunnel.json');
  }

  static void _writePid(int pid, int port) {
    try {
      final f = _pidFile;
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode({'pid': pid, 'port': port}));
    } catch (_) {
      // 흔적을 못 남겨도 터널 자체는 돈다.
    }
  }

  static void _clearPid() {
    try {
      if (_pidFile.existsSync()) _pidFile.deleteSync();
    } catch (_) {}
  }

  /// 지난 실행이 남긴 터널을 거둔다. 앱 시작에서 한 번 부른다.
  /// 실제로 죽인 것이 있으면 true.
  static bool reapOrphan() {
    try {
      final f = _pidFile;
      if (!f.existsSync()) return false;
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final pid = j['pid'] as int?;
      _clearPid();
      if (pid == null) return false;
      // PID 는 재사용된다 — 이름을 확인하지 않고 죽이면 남의 프로세스를 죽인다.
      final ps = Process.runSync('/bin/ps', ['-o', 'comm=', '-p', '$pid']);
      final name = (ps.stdout as String).trim();
      if (!name.contains('cloudflared')) return false;
      Process.runSync('/bin/kill', ['$pid']);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 터널이 (스스로) 죽었을 때 — 컨트롤러가 주소를 내리고 경고를 세운다.
  void Function()? onDied;

  /// GUI 앱은 셸 PATH 를 물려받지 못한다 — 알려진 설치 위치를 직접 짚는다.
  static const _knownPaths = [
    '/opt/homebrew/bin/cloudflared', // Apple Silicon Homebrew
    '/usr/local/bin/cloudflared', // Intel Homebrew
    '/usr/bin/cloudflared',
  ];

  static String? findBinary() {
    for (final p in _knownPaths) {
      if (File(p).existsSync()) return p;
    }
    // 알려진 위치에 없으면 로그인 셸의 PATH 로 한 번 더 찾는다 —
    // 사용자가 다른 데 설치했을 수 있다(asdf·mise·수동 설치).
    try {
      final r = Process.runSync('/bin/zsh', ['-lc', 'command -v cloudflared']);
      final out = (r.stdout as String).trim();
      if (r.exitCode == 0 && out.isNotEmpty && File(out).existsSync()) {
        return out;
      }
    } catch (_) {
      // 샌드박스 등으로 막히면 그냥 못 찾은 것으로 본다.
    }
    return null;
  }

  static bool get installed => findBinary() != null;

  /// 설치 안내에 보여 줄 명령.
  static const installCommand = 'brew install cloudflared';

  /// 터널을 띄우고 임시 주소를 돌려준다. 실패하면 null.
  ///
  /// 주소는 stderr 로 흘러나온다(배너 박스 안). 30초 안에 안 나오면
  /// 실패로 보고 프로세스를 정리한다 — 방화벽·오프라인이 흔한 원인.
  Future<String?> start(int port) async {
    if (running) return _url;
    final bin = findBinary();
    if (bin == null) return null;

    final proc = await Process.start(bin, [
      'tunnel',
      '--url',
      'http://localhost:$port',
      '--no-autoupdate',
    ]);
    _proc = proc;

    final found = Completer<String?>();
    final urlRe = RegExp(r'https://[a-z0-9-]+\.trycloudflare\.com');

    void scan(String line) {
      final m = urlRe.firstMatch(line);
      if (m != null && !found.isCompleted) found.complete(m.group(0));
    }

    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(scan);
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(scan);

    unawaited(
      proc.exitCode.then((_) {
        // stop() 으로 내린 게 아니라면 스스로 죽은 것이다.
        final wasOurs = identical(_proc, proc);
        if (wasOurs) {
          _proc = null;
          _url = null;
          _clearPid();
          if (!found.isCompleted) found.complete(null);
          onDied?.call();
        }
      }),
    );

    final url = await found.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => null,
    );
    if (url == null) {
      await stop();
      return null;
    }
    _url = url;
    _writePid(proc.pid, port);
    return url;
  }

  Future<void> stop() async {
    final proc = _proc;
    _proc = null;
    _url = null;
    _clearPid();
    if (proc != null) {
      proc.kill();
      // 좀비 방지 — SIGTERM 을 무시하면 강제로.
      unawaited(
        proc.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            proc.kill(ProcessSignal.sigkill);
            return -1;
          },
        ),
      );
    }
  }
}
