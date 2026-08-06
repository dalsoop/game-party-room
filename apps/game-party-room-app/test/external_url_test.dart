import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/server/external_url.dart';

void main() {
  group('터널 주소 정규화', () {
    test('스킴이 없으면 https 로 본다', () {
      expect(
        ExternalUrl.normalize('abc.trycloudflare.com'),
        'https://abc.trycloudflare.com',
      );
    });

    test('끝의 슬래시를 떼어낸다', () {
      // 안 떼면 최종 주소가 `https://host//?room=` 이 된다.
      expect(ExternalUrl.normalize('https://a.com/'), 'https://a.com');
      expect(ExternalUrl.normalize('https://a.com///'), 'https://a.com');
    });

    test('포트와 경로를 보존한다', () {
      expect(
        ExternalUrl.normalize('http://192.168.0.5:8765'),
        'http://192.168.0.5:8765',
      );
      expect(
        ExternalUrl.normalize('https://a.com/party/'),
        'https://a.com/party',
      );
    });

    test('앞뒤 공백을 정리한다', () {
      expect(ExternalUrl.normalize('  https://a.com  '), 'https://a.com');
    });

    test('쿼리가 붙은 주소는 거부한다', () {
      // 방 토큰 쿼리와 충돌해 참가자가 엉뚱한 방으로 간다.
      expect(ExternalUrl.normalize('https://a.com/?room=XXX'), isNull);
      expect(ExternalUrl.normalize('https://a.com#frag'), isNull);
    });

    test('http/https 가 아니면 거부한다', () {
      expect(ExternalUrl.normalize('ftp://a.com'), isNull);
      expect(ExternalUrl.normalize('ws://a.com'), isNull);
    });

    test('빈 값은 null 이다', () {
      expect(ExternalUrl.normalize(''), isNull);
      expect(ExternalUrl.normalize('   '), isNull);
    });

    test('방 주소를 조립한다', () {
      expect(
        ExternalUrl.roomUrl('https://a.com', 'QNWRVS'),
        'https://a.com/?room=QNWRVS',
      );
    });
  });
}
