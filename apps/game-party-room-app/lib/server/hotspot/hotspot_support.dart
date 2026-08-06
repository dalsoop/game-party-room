import 'dart:io';

import '../host_address.dart';

/// 이 플랫폼에서 전용 Wi-Fi(핫스팟)를 어디까지 다룰 수 있는가.
enum HotspotCapability {
  /// 앱이 직접 켤 수 있다 (Android local-only hotspot).
  appManaged,

  /// 앱은 못 켠다 — 사용자가 설정에서 켜고, 앱은 감지·안내만 한다.
  guided,

  /// 이 플랫폼에선 방법이 없다.
  unsupported,
}

/// 온보딩 단계 하나.
class HotspotStep {
  const HotspotStep(this.text, {this.caution = false});

  final String text;

  /// 놓치면 실패하는 함정 — UI 에서 강조한다.
  final bool caution;
}

/// 플랫폼별 핫스팟 안내.
///
/// 플랫폼마다 되는 게 완전히 달라서(앱이 켤 수 있는 곳은 Android 뿐) 분기를 UI 에
/// 흩뿌리지 않고 여기 한 곳에 모은다. 화면은 이 값만 그린다.
class HotspotGuide {
  const HotspotGuide({
    required this.capability,
    required this.platformName,
    required this.title,
    required this.steps,
    this.caveat,
    this.expectedHint,
  });

  final HotspotCapability capability;
  final String platformName;
  final String title;
  final List<HotspotStep> steps;

  /// 이 플랫폼 고유의 제약 — 없으면 null.
  final String? caveat;

  /// 성공했을 때 어떤 주소가 잡히는지.
  final String? expectedHint;

  static HotspotGuide forCurrentPlatform() {
    if (Platform.isMacOS) return _macOS;
    if (Platform.isIOS) return _iOS;
    if (Platform.isAndroid) return _android;
    if (Platform.isWindows) return _windows;
    return _unsupported;
  }

  // ---- 플랫폼별 정의 ----

  static const _macOS = HotspotGuide(
    capability: HotspotCapability.guided,
    platformName: 'macOS',
    title: '인터넷 공유로 전용 Wi-Fi 만들기',
    steps: [
      HotspotStep('시스템 설정 → 일반 → 공유 → "인터넷 공유" 오른쪽 ⓘ 를 누릅니다'),
      HotspotStep(
        '"다음으로부터 연결 공유"에서 **Wi-Fi 가 아닌** 인터페이스를 고릅니다 '
        '(이더넷 어댑터·Thunderbolt·아이폰 USB 테더링)',
        caution: true,
      ),
      HotspotStep('"다음을 사용하는 컴퓨터에"에서 Wi-Fi 를 체크합니다'),
      HotspotStep('"Wi-Fi 옵션…"에서 네트워크 이름과 암호(WPA2/WPA3 개인용)를 정합니다'),
      HotspotStep('인터넷 공유를 켜고, 아래에서 "다시 검색"을 누릅니다'),
    ],
    caveat:
        'macOS 는 Wi-Fi 로 받은 인터넷을 다시 Wi-Fi 로 나눠줄 수 없습니다 — '
        '전파를 하나만 쓰기 때문입니다. 지금처럼 Wi-Fi 로만 연결된 맥이라면 '
        '유선 어댑터나 아이폰 USB 테더링을 인터넷 공급원으로 꽂아야 합니다.',
    expectedHint: '성공하면 bridge100 인터페이스가 생깁니다 (보통 192.168.2.1)',
  );

  static const _iOS = HotspotGuide(
    capability: HotspotCapability.guided,
    platformName: 'iOS / iPadOS',
    title: '개인용 핫스팟 켜기',
    steps: [
      HotspotStep('설정 → 개인용 핫스팟 → "다른 사람의 접속 허용"을 켭니다'),
      HotspotStep('"Wi-Fi 암호"를 참가자에게 알려줄 수 있게 확인합니다'),
      HotspotStep('참가자들이 이 핫스팟에 접속한 뒤, 아래에서 "다시 검색"을 누릅니다'),
      HotspotStep(
        '핫스팟 화면을 벗어나면 대기 상태로 꺼질 수 있으니, '
        '참가자가 모두 붙을 때까지 설정 화면을 열어둡니다',
        caution: true,
      ),
    ],
    caveat:
        'iOS 는 앱이 핫스팟을 켤 수 있는 공개 API 를 제공하지 않습니다 — '
        '설정에서 직접 켜야 합니다.',
    expectedHint: '성공하면 172.20.10.1 주소가 잡힙니다',
  );

  static const _android = HotspotGuide(
    capability: HotspotCapability.appManaged,
    platformName: 'Android',
    title: '앱 전용 핫스팟',
    steps: [
      HotspotStep('아래 "핫스팟 켜기"를 누르면 앱이 임시 Wi-Fi 를 만듭니다'),
      HotspotStep('화면에 뜨는 이름·암호를 참가자에게 보여주거나 QR 로 스캔하게 합니다'),
      HotspotStep('참가자가 접속하면 방 주소가 자동으로 핫스팟 주소로 바뀝니다'),
    ],
    expectedHint: '성공하면 192.168.43.x 주소가 잡힙니다',
  );

  static const _windows = HotspotGuide(
    capability: HotspotCapability.guided,
    platformName: 'Windows',
    title: '모바일 핫스팟 켜기',
    steps: [
      HotspotStep('설정 → 네트워크 및 인터넷 → 모바일 핫스팟을 켭니다'),
      HotspotStep('네트워크 이름·암호를 확인해 참가자에게 알려줍니다'),
      HotspotStep('참가자가 접속하면 아래에서 "다시 검색"을 누릅니다'),
    ],
    expectedHint: '성공하면 192.168.137.1 주소가 잡힙니다',
  );

  static const _unsupported = HotspotGuide(
    capability: HotspotCapability.unsupported,
    platformName: '이 플랫폼',
    title: '전용 Wi-Fi 를 만들 수 없습니다',
    steps: [HotspotStep('참가자와 같은 Wi-Fi 에 연결한 뒤 방 주소를 공유하세요')],
  );
}

/// 지금 핫스팟 주소가 잡혔는지 확인한다.
class HotspotDetector {
  /// 핫스팟으로 분류된 주소가 있으면 그것을, 없으면 null.
  static Future<HostAddress?> detect() async {
    final candidates = await HostAddressFinder.candidates();
    for (final c in candidates) {
      if (c.kind == HostAddressKind.hotspot) return c;
    }
    return null;
  }
}

/// 참가자가 Wi-Fi 에 바로 붙도록 하는 QR 문자열.
///
/// 표준 `WIFI:` 스킴 — iOS/Android 카메라가 그대로 알아본다. 핫스팟 이름·암호를
/// 불러주는 대신 QR 하나로 끝낼 수 있어 오프라인 진행이 훨씬 매끄럽다.
class WifiQr {
  /// [password] 가 비어 있으면 개방형(nopass)으로 만든다.
  static String build({required String ssid, String password = ''}) {
    final t = password.isEmpty ? 'nopass' : 'WPA';
    final s = _escape(ssid);
    final p = _escape(password);
    return 'WIFI:T:$t;S:$s;P:$p;;';
  }

  /// `\ ; , : "` 는 스킴의 구분자라 이스케이프해야 한다 —
  /// 암호에 세미콜론이 들어가면 QR 이 조용히 깨진다.
  static String _escape(String v) {
    final out = StringBuffer();
    for (final ch in v.split('')) {
      if (r'\;,:"'.contains(ch)) out.write(r'\');
      out.write(ch);
    }
    return out.toString();
  }
}
