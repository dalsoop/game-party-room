import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 오류 기록 — **로컬에만 남긴다**.
///
/// 파티 자리에서 앱이 터지면 호스트는 남에게 물어볼 수도, 로그를 뒤질 수도
/// 없다. 그래서 (1) 화면은 붉은 오류 상자 대신 사람 말로 바꾸고,
/// (2) 무슨 일이 있었는지는 파일로 남겨 나중에 보내 줄 수 있게 한다.
///
/// 서버로 보내지 않는 이유: 방에서 오가는 내용(닉네임·채팅·파일 이름)이
/// 스택에 섞여 나올 수 있다. 손님들 대화를 개발자 서버로 나르는 앱을
/// 팔 수는 없다. 신고는 호스트가 **직접** 파일을 보내는 방식이다.
class Diagnostics {
  Diagnostics({this.overrideDir});

  static final Diagnostics instance = Diagnostics();

  /// 테스트에서 임시 디렉터리를 물리는 자리. 앱에서는 항상 null.
  final Directory? overrideDir;

  /// 파일이 무한정 자라면 그것대로 사고다. 이 크기를 넘으면 앞쪽을 버린다.
  static const _maxBytes = 256 * 1024;

  /// 같은 오류가 프레임마다 반복되면(빌드 중 예외) 로그가 초 단위로 찬다.
  /// 직전과 같은 서명은 접어 둔다.
  String? _lastSignature;
  int _repeat = 0;

  Directory get directory =>
      overrideDir ??
      Directory(
        '${Platform.environment['HOME'] ?? '.'}/Library/Logs/PartyRoom',
      );

  File get logFile => File('${directory.path}/errors.log');

  /// 앱 시작에서 한 번. `runZonedGuarded` 와 함께 써야 비동기 오류까지 잡힌다.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack, context: details.library);
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, context: 'platform');
      return true; // 기록했으니 앱은 계속 산다.
    };
    // 위젯 하나가 터졌다고 검붉은 상자를 손님들 앞에 띄우지 않는다.
    ErrorWidget.builder = (details) => _CalmError(details: details);
  }

  void record(Object error, StackTrace? stack, {String? context}) {
    try {
      final signature = '$context|$error';
      if (signature == _lastSignature) {
        _repeat++;
        // 2, 4, 8, 16… 번째만 남긴다 — 반복은 사실이지만 매번 적을 값은 아니다.
        if (_repeat & (_repeat - 1) != 0) return;
      } else {
        _lastSignature = signature;
        _repeat = 0;
      }

      directory.createSync(recursive: true);
      final buf = StringBuffer()
        ..writeln(
          '── ${DateTime.now().toIso8601String()}'
          '${context == null ? '' : ' · $context'}'
          '${_repeat > 0 ? ' · ${_repeat + 1}번째 반복' : ''}',
        )
        ..writeln(error.toString());
      if (stack != null) {
        // 스택 전체는 대부분 프레임워크 내부다. 위쪽 열두 줄이면 원인이 보인다.
        final lines = stack.toString().split('\n');
        buf.writeln(lines.take(12).join('\n'));
      }
      logFile.writeAsStringSync('$buf\n', mode: FileMode.append);
      _trim();
    } catch (_) {
      // 기록에 실패한다고 앱을 멈추지 않는다.
    }
  }

  void _trim() {
    final f = logFile;
    if (!f.existsSync() || f.lengthSync() <= _maxBytes) return;
    final text = f.readAsStringSync();
    // 잘린 지점이 항목 중간이면 읽기 나빠진다 — 항목 경계에서 자른다.
    final cut = text.indexOf('── ', text.length - _maxBytes ~/ 2);
    f.writeAsStringSync(cut < 0 ? '' : text.substring(cut));
  }

  /// 설정 화면에 보여 줄 최근 기록. 최신이 위로 온다.
  List<String> recent({int limit = 20}) {
    final f = logFile;
    if (!f.existsSync()) return const [];
    final entries = f
        .readAsStringSync()
        .split('── ')
        .where((e) => e.trim().isNotEmpty)
        .map((e) => '── $e'.trimRight())
        .toList();
    return entries.reversed.take(limit).toList();
  }

  void clear() {
    if (logFile.existsSync()) logFile.deleteSync();
    _lastSignature = null;
    _repeat = 0;
  }
}

/// 붉은 오류 상자 대신 — 손님들이 보고 있는 화면이다.
class _CalmError extends StatelessWidget {
  const _CalmError({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF11161F),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(height: 8),
          const Text(
            '이 화면에 문제가 생겼습니다',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            '로비로 돌아갔다 다시 들어오면 대개 계속할 수 있습니다.\n'
            '기록은 설정 › 오류 기록에 남았습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9AA7BC), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
