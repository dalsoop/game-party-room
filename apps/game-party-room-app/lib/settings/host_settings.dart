import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 호스트 화면 설정.
///
/// 예전에는 방 초기화(앱바)·주소 변경(QR 아래 링크)·전용 Wi-Fi(그 옆 링크)·
/// 터널 주소(시트 안쪽)가 서로 다른 곳에 있었다. 값을 가진 것들은 여기로 모으고,
/// 화면은 이 객체 하나만 본다.
class HostSettings extends ChangeNotifier {
  HostSettings._();

  /// 서버가 뜨기 전에도 화면이 참조할 수 있게 하는 기본값 인스턴스.
  factory HostSettings.empty() => HostSettings._();

  static const _key = 'party_room_host_settings_v1';

  /// 비밀(역할표·라이어 제시어)을 가림막 뒤에 둔다.
  ///
  /// 호스트 화면은 참가자에게 노출되기 쉬운데, 예전엔 "보여주지 마세요" 경고문뿐이었다.
  /// 기본값은 켜짐 — 안전한 쪽이 기본이어야 한다.
  bool hideSecrets = true;

  /// QR 을 크게 — TV·프로젝터로 띄울 때. null 이면 화면 폭으로 자동 판단.
  bool? bigQr;

  /// 진행 효과음(출발·골인·당첨·낮밤). 기본 켜짐 — 큰 화면 연출의 일부다.
  bool soundEnabled = true;

  /// 게임 종목별 규칙. `{ 'mafia': {...}, 'liar': {...} }`
  Map<String, Map<String, dynamic>> gameRules = {};

  // ---- LLM 사회자 ----
  //
  // 켜면 게임의 결정적 순간마다 한 문장이 단톡에 뜬다. 게임 규칙에는 관여하지
  // 않으므로 꺼져 있어도 모든 종목이 그대로 돌아간다(기본 꺼짐).
  bool mcEnabled = false;

  /// 'cli' = 터미널 구독(claude·codex·grok) · 'http' = OpenAI 호환 주소.
  ///
  /// 기본은 cli — 맥에 이미 로그인된 CLI 가 있으면 사용자가 키를 만들 일이
  /// 없다. 이 앱의 사회자는 그 경로를 1순위로 본다.
  String mcProvider = 'cli';

  /// mcProvider == 'cli' 일 때 쓸 백엔드 id.
  String mcCliBackend = 'claude';

  /// OpenAI 호환 엔드포인트. Ollama 를 쓰면 http://localhost:11434/v1.
  String mcBaseUrl = 'http://localhost:11434/v1';
  String mcModel = 'llama3.2';

  /// 로컬 모델이면 비워 둔다.
  String mcApiKey = '';

  /// [McPersona] 의 name.
  String mcPersona = 'classic';

  /// 전용 Wi-Fi 이름(SSID). 접속 QR 을 만들 때 쓴다.
  ///
  /// 플랫폼이 자기 핫스팟 이름을 앱에 알려주지 않아서 호스트가 옮겨 적어야
  /// 하는데, 그 값은 파티마다 그대로다 — 매번 다시 치게 두지 않는다.
  ///
  /// **암호는 저장하지 않는다.** 파티마다 한 번 치는 편이, 평문 설정 파일에
  /// Wi-Fi 암호를 남기는 것보다 낫다. (방 비밀번호가 저장 파일 밖으로 절대
  /// 안 나가는 것과 같은 기준이다.)
  String hotspotSsid = '';

  // ---- 랑데부(밖에 있는 사람) ----

  /// 랑데부 서버 주소. 비어 있으면 이 기능을 안 쓴다 — 기본은 로컬뿐이다.
  String relayBase = '';

  /// 이 호스트임을 증명하는 값. **재접속 때 같은 방 코드를 되찾는 열쇠**라
  /// 저장해 둔다 — 파티 도중에 코드가 바뀌면 이미 나눠 준 QR 이 전부 죽는다.
  /// 남에게 알려 주는 값이 아니다(방 코드와 다르다).
  String relaySecret = '';

  /// 지난번에 받은 방 코드. 릴레이가 아직 비워 두고 있으면 그대로 돌려준다.
  String relayCode = '';

  static Future<HostSettings> load() async {
    final s = HostSettings._();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return s;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      s.hideSecrets = j['hideSecrets'] as bool? ?? true;
      s.bigQr = j['bigQr'] as bool?;
      s.soundEnabled = j['soundEnabled'] as bool? ?? true;
      s.mcEnabled = j['mcEnabled'] as bool? ?? false;
      s.mcProvider = j['mcProvider'] as String? ?? 'cli';
      s.mcCliBackend = j['mcCliBackend'] as String? ?? 'claude';
      s.mcBaseUrl = j['mcBaseUrl'] as String? ?? 'http://localhost:11434/v1';
      s.mcModel = j['mcModel'] as String? ?? 'llama3.2';
      s.mcApiKey = j['mcApiKey'] as String? ?? '';
      s.mcPersona = j['mcPersona'] as String? ?? 'classic';
      s.hotspotSsid = j['hotspotSsid'] as String? ?? '';
      s.relayBase = j['relayBase'] as String? ?? '';
      s.relaySecret = j['relaySecret'] as String? ?? '';
      s.relayCode = j['relayCode'] as String? ?? '';
      final rules = j['gameRules'] as Map<String, dynamic>? ?? {};
      s.gameRules = {
        for (final e in rules.entries)
          e.key: Map<String, dynamic>.from(e.value as Map),
      };
    } catch (_) {
      // 형식이 깨졌으면 기본값으로 — 설정 때문에 방이 안 열리면 안 된다.
    }
    return s;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'hideSecrets': hideSecrets,
        'bigQr': bigQr,
        'soundEnabled': soundEnabled,
        'gameRules': gameRules,
        'mcEnabled': mcEnabled,
        'mcProvider': mcProvider,
        'mcCliBackend': mcCliBackend,
        'mcBaseUrl': mcBaseUrl,
        'mcModel': mcModel,
        'mcApiKey': mcApiKey,
        'mcPersona': mcPersona,
        'hotspotSsid': hotspotSsid,
        'relayBase': relayBase,
        'relaySecret': relaySecret,
        'relayCode': relayCode,
      }),
    );
  }

  void setRelayBase(String v) {
    final t = v.trim();
    if (t == relayBase) return;
    relayBase = t;
    // 서버가 바뀌면 그쪽에서 받은 코드는 뜻이 없다.
    relayCode = '';
    _save();
    notifyListeners();
  }

  void setRelaySecret(String v) {
    relaySecret = v;
    _save();
  }

  void setRelayCode(String v) {
    if (v == relayCode) return;
    relayCode = v;
    _save();
    notifyListeners();
  }

  void setHotspotSsid(String v) {
    final t = v.trim();
    if (t == hotspotSsid) return;
    hotspotSsid = t;
    _save();
    notifyListeners();
  }

  /// 설정 값이 아니라 **바깥 사실**(CLI 설치 여부 등)이 바뀌었을 때 화면만 다시 그린다.
  void notify() => notifyListeners();

  void setHideSecrets(bool v) {
    hideSecrets = v;
    _save();
    notifyListeners();
  }

  void setSoundEnabled(bool v) {
    soundEnabled = v;
    _save();
    notifyListeners();
  }

  void setBigQr(bool? v) {
    bigQr = v;
    _save();
    notifyListeners();
  }

  void setMc({
    bool? enabled,
    String? provider,
    String? cliBackend,
    String? baseUrl,
    String? model,
    String? apiKey,
    String? persona,
  }) {
    if (enabled != null) mcEnabled = enabled;
    if (provider != null) mcProvider = provider;
    if (cliBackend != null) mcCliBackend = cliBackend;
    if (baseUrl != null) mcBaseUrl = baseUrl.trim();
    if (model != null) mcModel = model.trim();
    if (apiKey != null) mcApiKey = apiKey.trim();
    if (persona != null) mcPersona = persona;
    _save();
    notifyListeners();
  }

  /// 종목의 규칙 값 하나를 읽는다. 없으면 [fallback].
  T rule<T>(String gameId, String key, T fallback) {
    final v = gameRules[gameId]?[key];
    return v is T ? v : fallback;
  }

  void setRule(String gameId, String key, Object? value) {
    final g = Map<String, dynamic>.from(gameRules[gameId] ?? {});
    if (value == null) {
      g.remove(key);
    } else {
      g[key] = value;
    }
    gameRules = {...gameRules, gameId: g};
    _save();
    notifyListeners();
  }

  /// 종목의 규칙 전체 — 게임 시작 시 모듈에 넘긴다.
  Map<String, dynamic> rulesFor(String gameId) =>
      Map<String, dynamic>.from(gameRules[gameId] ?? const {});
}
