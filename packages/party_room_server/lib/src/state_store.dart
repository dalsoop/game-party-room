import 'dart:io';

/// 방 스냅샷을 어디에 저장할지.
///
/// 예전에는 방 복구가 `shared_preferences`(Flutter 플러그인)에 직접 묶여 있었다.
/// 헤드리스 서버에는 그런 게 없으므로 저장 위치를 주입받는다.
abstract class StateStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// 파일 한 개에 담는 구현 — 헤드리스 서버용.
class FileStateStore implements StateStore {
  FileStateStore(this.path);

  final String path;

  @override
  Future<String?> read() async {
    final f = File(path);
    return f.existsSync() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String value) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    // 쓰는 도중 죽어도 반쪽 파일이 남지 않게 임시 파일 → rename.
    final tmp = File('$path.tmp');
    await tmp.writeAsString(value, flush: true);
    await tmp.rename(path);
  }

  @override
  Future<void> clear() async {
    final f = File(path);
    if (f.existsSync()) await f.delete();
  }
}

/// 저장하지 않는 구현 — 테스트·일회성 방.
class MemoryStateStore implements StateStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async => _value = value;

  @override
  Future<void> clear() async => _value = null;
}
