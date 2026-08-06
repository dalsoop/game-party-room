import 'dart:io';

/// 참가자 SPA·이미지·스크립트를 어디서 읽을지.
///
/// 이것이 Flutter 결합을 끊는 지점이다. 예전에는 방 서버가 `rootBundle` 을 직접
/// 불러서, 서버 코드가 Flutter 앱 안에서만 돌 수 있었다 — 헤드리스로 못 띄웠다.
///
/// - 호스트 앱: 앱 번들에서 읽는 구현을 주입한다(`BundleAssetSource`).
/// - 헤드리스 서버: [FileAssetSource].
abstract class AssetSource {
  /// 텍스트 자산. 없으면 null.
  Future<String?> loadString(String path);

  /// 바이너리 자산. 없으면 null.
  Future<List<int>?> loadBytes(String path);
}

/// 디렉터리에서 읽는 구현 — 헤드리스 서버용.
class FileAssetSource implements AssetSource {
  FileAssetSource(this.rootDir);

  /// `assets/` 를 포함하는 루트 경로.
  final String rootDir;

  @override
  Future<String?> loadString(String path) async {
    final f = _resolve(path);
    return f?.readAsString();
  }

  @override
  Future<List<int>?> loadBytes(String path) async {
    final f = _resolve(path);
    return f?.readAsBytes();
  }

  File? _resolve(String path) {
    // 자산 경로는 서버가 화이트리스트로 걸러 넘기지만 한 번 더 막는다.
    if (path.contains('..')) return null;
    final f = File('$rootDir/$path');
    return f.existsSync() ? f : null;
  }
}
