import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// 상태를 디스크에 게시한다.
///
/// `ControlService` 옆에 얹혀 있었지만 **남남**이다 — 명령을 실행하지 않고,
/// 스냅샷 JSON 을 파일에 실을 뿐이다. 앱이 떠 있지 않아도 마지막 상태를
/// 읽을 수 있어야 하고(그래야 "왜 안 켜졌나" 를 답한다), 떠 있으면
/// 실시간이어야 한다. 제어 실행 경로와 섞여 있으면 "상태 읽기" 와
/// "명령 실행" 이 한 파일에서 교차해, 에이전트 채널 고칠 때 판 진행
/// 코드를 건드릴 위험이 있다.
class StateMirror {
  StateMirror({this.overrideDir});

  /// 테스트에서 임시 디렉터리를 물리는 자리. 앱에서는 항상 null.
  final Directory? overrideDir;

  static Directory defaultDir() => Directory(
    '${Platform.environment['HOME'] ?? '.'}/Library/Application Support/PartyRoom',
  );

  Directory get directory => overrideDir ?? defaultDir();
  File get file => File('${directory.path}/state.json');

  /// 제어 API 를 부를 때 필요한 토큰. 파일을 읽을 수 있는 사람만 쓸 수 있다.
  ///
  /// 루프백 검사만으로는 부족하다 — 인터넷 개방 중이면 cloudflared 가
  /// 로컬에서 접속해 오므로 바깥 요청도 127.0.0.1 로 보인다.
  File get tokenFile => File('${directory.path}/control.json');

  String ensureToken() {
    try {
      if (tokenFile.existsSync()) {
        final j = jsonDecode(tokenFile.readAsStringSync());
        final t = (j as Map)['token'] as String?;
        if (t != null && t.length >= 24) return t;
      }
    } catch (_) {
      // 깨졌으면 새로 만든다.
    }
    final t = _randomToken(32);
    directory.createSync(recursive: true);
    tokenFile.writeAsStringSync(jsonEncode({'token': t}));
    // 다른 사용자가 읽으면 제어 권한을 넘기는 셈이다.
    Process.runSync('/bin/chmod', ['600', tokenFile.path]);
    return t;
  }

  void publish(Map<String, dynamic> snapshot) {
    try {
      directory.createSync(recursive: true);
      // 반쯤 쓰인 파일을 읽는 일이 없게 갈아 끼운다.
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(snapshot),
      );
      tmp.renameSync(file.path);
    } catch (_) {
      // 게시 실패가 파티를 막지는 않는다.
    }
  }

  /// 제어 토큰이라 시계 기반 의사난수로는 부족하다.
  static String _randomToken(int len) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(len, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
