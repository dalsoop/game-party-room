import 'package:flutter/services.dart' show rootBundle;
import 'package:party_room_server/party_room_server.dart';

/// 호스트 앱용 자산 소스 — 앱 번들에서 읽는다.
///
/// 방 서버 자체는 Flutter 를 모른다. 번들 접근은 여기서만 한다.
class BundleAssetSource implements AssetSource {
  const BundleAssetSource();

  @override
  Future<String?> loadString(String path) async {
    try {
      return await rootBundle.loadString(path);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<int>?> loadBytes(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
