import 'dart:io';

/// 인터넷으로 열린 방 주소(터널).
///
/// 로컬망 조건(같은 Wi-Fi·VPN·AP 격리)을 아예 타지 않는 유일한 방법이라
/// "언제 어디서든" 이 필요할 때 쓴다. 호스트가 터널 주소를 붙여넣으면
/// QR·링크가 그 주소로 바뀐다.
class ExternalUrl {
  /// 사람이 붙여넣은 값을 방 주소의 베이스로 정규화한다.
  /// 쓸 수 없는 값이면 null.
  ///
  /// - 스킴이 없으면 https 로 본다 (터널 주소는 사실상 전부 https)
  /// - 끝의 `/` 는 떼어낸다 — 붙은 채로 두면 `//?room=` 이 된다
  /// - 쿼리·프래그먼트가 붙어 있으면 방 토큰과 충돌하므로 거부
  static String? normalize(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return null;

    if (!v.contains('://')) v = 'https://$v';

    final uri = Uri.tryParse(v);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    if (uri.hasQuery || uri.hasFragment) return null;

    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port$path';
  }

  /// 베이스 + 방 토큰 → 참가자에게 줄 최종 주소.
  static String roomUrl(String base, String roomToken) =>
      '$base/?room=$roomToken';

  /// 주소가 지금 응답하는지.
  ///
  /// 즉석 터널(trycloudflare)은 호스트를 껐다 켜면 죽는다 — 죽은 주소를
  /// QR 에 그대로 두면 참가자 전원이 접속 불가인데 호스트는 모른다.
  /// 4초 안에 결판내고, 5xx(cloudflare 530 = 터널 뒤가 없음)도 죽음으로 본다.
  static Future<bool> isReachable(String base) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client
          .getUrl(Uri.parse(base))
          .timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      await res.drain<void>();
      return res.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
