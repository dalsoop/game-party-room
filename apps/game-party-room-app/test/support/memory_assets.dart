import 'package:party_room_server/party_room_server.dart';

/// 참가자 화면만 흉내 내는 자산 원본.
///
/// 포트 판별([RoomPort])이 "이 포트에 앉은 게 파티룸인가" 를 참가자 화면의
/// title 로 확인하므로, 그 한 줄은 진짜로 내줘야 한다.
class MemoryAssets implements AssetSource {
  @override
  Future<String?> loadString(String path) async =>
      path.endsWith('index.html') ? '<html><title>파티룸</title></html>' : null;

  @override
  Future<List<int>?> loadBytes(String path) async => null;
}
