import 'package:party_room_server/party_room_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 호스트 앱용 상태 저장소 — 앱 설정에 담는다.
class PrefsStateStore implements StateStore {
  const PrefsStateStore([this.key = 'party_room_state_v1']);

  final String key;

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(key);
}
