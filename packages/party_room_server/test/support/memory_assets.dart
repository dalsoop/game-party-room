import 'package:party_room_server/party_room_server.dart';

/// 서버 로직만 보는 테스트용 자산 원본.
///
/// 기본값은 아무것도 내주지 않는다 — 참가자 화면(HTML/JS/이미지)은 [RoomServer]
/// 의 관심사가 아니라서, 방·세션·식별자 계약을 검사하는 테스트는 자산 없이
/// 돌아야 한다.
///
/// 정적 서빙 자체([WebAssets])를 검사할 때는 [strings]·[bytes] 에 가짜 자산을
/// 심어 두고, [stringLoads]·[byteLoads] 로 화이트리스트가 실제로 무엇을
/// 읽으려 했는지 확인한다. 경로 탈출이 화이트리스트를 통과하면 여기 로그에
/// 앱 번들 경로가 찍힌다.
class MemoryAssets implements AssetSource {
  MemoryAssets({this.strings = const {}, this.bytes = const {}});

  /// `loadString` 이 돌려줄 내용. 키는 앱 번들 안 경로
  /// (`assets/web/index.html` 등).
  final Map<String, String> strings;

  /// `loadBytes` 가 돌려줄 내용.
  final Map<String, List<int>> bytes;

  /// `loadString` 이 호출된 경로들 — 화이트리스트 우회 여부를 본다.
  final List<String> stringLoads = [];

  /// `loadBytes` 가 호출된 경로들.
  final List<String> byteLoads = [];

  @override
  Future<String?> loadString(String path) async {
    stringLoads.add(path);
    return strings[path];
  }

  @override
  Future<List<int>?> loadBytes(String path) async {
    byteLoads.add(path);
    return bytes[path];
  }
}
