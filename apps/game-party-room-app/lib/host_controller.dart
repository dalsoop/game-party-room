import 'dart:async';
import 'dart:convert';

import 'package:party_room_server/party_room_server.dart';
import 'package:shelf/shelf.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'games/game_catalog.dart';
import 'games/game_control.dart';
import 'settings/host_settings.dart';
import 'server/app/bundle_assets.dart';
import 'server/app/prefs_state_store.dart';
import 'server/external_url.dart';
import 'server/host_address.dart';
import 'server/control_service.dart';
import 'server/mc_narrator.dart';
import 'server/mc_service.dart';
import 'server/sound_service.dart';
import 'server/tunnel_service.dart';

/// 호스트 앱 전역 상태 — 서버 수명주기·게임 이벤트를 UI 와 분리.
class HostController extends ChangeNotifier {
  /// 호스트 화면 설정 — 비밀 가리기·QR 크기·게임 규칙.
  HostSettings settings = HostSettings.empty();

  /// 판을 시작하고 굴리고 끝내는 일. 화면은 `ctrl.games.…` 로 부른다.
  ///
  /// 방·설정은 **지연 참조**로 넘긴다 — 보고 있는 방이 바뀌면 그쪽을
  /// 따라가야 하는데, 값으로 넘기면 만든 시점의 방에 얼어붙는다.
  late final GameControl games = GameControl(
    room: () => room,
    settings: () => settings,
    changed: notifyListeners,
    onEnded: () {
      _narrator.reset();
      mcLine = '';
    },
  );

  RoomServer? server;

  /// 지금 화면이 보고 있는 방.
  ///
  /// 서버는 여러 방을 동시에 듣고 있고([RoomServer]), 화면은 그중 하나를
  /// 본다 — 다른 방의 판도 계속 돌아간다.
  Room? room;

  List<Room> get rooms => server?.rooms ?? const [];

  /// 방을 고른다. 없는 토큰이면 아무것도 안 한다.
  void selectRoom(String token) {
    final r = server?.byToken(token);
    if (r == null || identical(r, room)) return;
    room = r;
    _syncGameStatus();
    _rebuildUrl();
    notifyListeners();
    _publish();
  }

  /// 지금 보고 있는 방의 판을 화면 상태에 맞춘다.
  ///
  /// `games.gameStatus` 는 방 하나짜리 시절의 유물이라 **보고 있는 방 하나**를
  /// 가리킨다. 그런데 판은 여러 방에서 동시에 돌고, 문구는 이벤트가 지날
  /// 때만 갱신된다. 그래서 방을 옮기면 옆 방 문구가 그대로 남아 있거나
  /// (앱을 막 켰다면) 빈 칸이었다 — 판이 돌고 있는데도.
  ///
  /// 옮길 때마다, 그리고 복원 직후에 그 방의 모듈에서 다시 만든다.
  void _syncGameStatus() {
    final g = room?.activeGame;
    if (g == null) {
      games.gameStatus = '';
      games.mafiaPhase = '';
      return;
    }
    if (g is MafiaGame) games.mafiaPhase = g.phase.name;
    games.gameStatus = GameCatalog.restoredStatusFor(g) ?? '';
  }

  /// 새 방을 연다.
  /// 방을 새로 연다. 못 열면 **왜 못 여는지**를 [createRoomError] 에 남긴다.
  ///
  /// null 만 돌려주면 화면은 "아무 일도 안 일어난" 것으로 보인다 — 서버가
  /// 정원(최대 [RoomServer.maxRooms]개)을 이유로 거절했다는 사실이 사라진다.
  Room? createRoom(String name) {
    createRoomError = null;
    final srv = server;
    if (srv == null) {
      createRoomError = '방 서버가 아직 안 떴습니다';
      return null;
    }
    try {
      final r = srv.createRoom(name: name.trim());
      room = r;
      _rebuildUrl();
      notifyListeners();
      _publish();
      return r;
    } on StateError catch (e) {
      createRoomError = e.message;
      notifyListeners();
      return null;
    }
  }

  /// 마지막 방 만들기가 왜 실패했는지. 성공하면 null.
  String? createRoomError;

  /// 더 만들 수 있는가 — 화면이 [새 방] 버튼을 끄는 데 쓴다.
  bool get roomsFull => server?.full ?? false;

  /// 방 이름 바꾸기.
  void renameRoom(String token, String name) {
    final r = server?.byToken(token);
    if (r == null) return;
    r.name = name.trim();
    notifyListeners();
    _publish();
    _persist();
  }

  /// 방을 열거나 닫는다.
  ///
  /// 이름 붙인 방에는 수명 타이머가 없다 — 지난달 링크가 아직 통한다는
  /// 책임을 이 스위치가 대신 진다. 닫으면 입장도 소켓 연결도 거절한다.
  void setRoomOpen(String token, bool open) {
    final r = server?.byToken(token);
    if (r == null) return;
    r.open = open;
    notifyListeners();
    _publish();
    _persist();
  }

  /// 입장 비밀번호를 걸거나 푼다. 4자리 숫자가 아니면 false.
  bool setRoomPin(String token, String? pin) {
    final r = server?.byToken(token);
    if (r == null || !r.setPin(pin)) return false;
    notifyListeners();
    _publish();
    _persist();
    return true;
  }

  void _persist() => server?.onStateChanged?.call();

  /// 방마다 화면 갱신 구독을 건다. 이미 건 방은 건너뛴다.
  ///
  /// 두 가지를 듣는다:
  /// - `lobbyStream` — 입장·퇴장·연결 상태. 이걸 빼먹으면 참가자 목록만
  ///   살아 움직이고 `games.connectedCount` 를 읽는 곳(게임 카드의 "N명 더 필요"
  ///   배지)은 옛 값에 얼어붙는다 — 실사고.
  /// - `filesStream` — **참가자 업로드**. 이건 HTTP 로 들어와서 컨트롤러가
  ///   따로 알 길이 없다. 안 들으면 친구가 사진을 올려도 호스트의 자료함이
  ///   그대로여서, 화면을 나갔다 들어와야 보인다.
  final Map<String, List<StreamSubscription<void>>> _roomSubs = {};

  void _rewireRooms(RoomServer srv) {
    for (final r in srv.rooms) {
      if (_roomSubs.containsKey(r.roomToken)) continue;
      _roomSubs[r.roomToken] = [
        r.lobbyStream.listen((_) => notifyListeners()),
        r.filesStream.listen((_) => notifyListeners()),
      ];
    }
    // 지워진 방의 구독은 놓아 준다.
    final live = {for (final r in srv.rooms) r.roomToken};
    for (final gone in _roomSubs.keys.toList()) {
      if (live.contains(gone)) continue;
      for (final s in _roomSubs.remove(gone)!) {
        s.cancel();
      }
    }
  }

  /// 방을 지운다. 보고 있던 방이면 다른 방으로 옮겨 간다.
  Future<bool> deleteRoom(String token) async {
    final srv = server;
    if (srv == null) return false;
    final deleting = srv.byToken(token);
    final ok = await srv.removeRoom(token);
    if (!ok) return false;
    if (deleting != null) games.forget(deleting);
    if (room?.roomToken == token) room = srv.rooms.firstOrNull;
    _rebuildUrl();
    notifyListeners();
    _publish();
    return true;
  }

  String? url;
  String? error;

  /// 참가자가 접속할 수 있는 주소 후보들. 첫 번째가 기본 선택.
  List<HostAddress> addresses = [];
  int addressIndex = 0;

  /// 터널 주소(예: https://xxx.trycloudflare.com). 세워두면 로컬 IP 대신 이걸 쓴다.
  String? externalBase;

  /// 저장된 인터넷 주소가 지금 응답하지 않는 상태.
  ///
  /// trycloudflare 즉석 터널은 호스트를 껐다 켜면 죽는다. 죽은 주소를
  /// QR 에 그대로 띄우면 **참가자 전원이 접속 불가인데 호스트는 모른다** —
  /// 사용성 테스트에서 실제로 걸린 최악의 침묵 고장이라, 시작할 때 찔러 보고
  /// 죽어 있으면 로컬 주소로 물러난 뒤 경고를 세운다.
  bool externalDead = false;

  bool get usingExternal => externalBase != null && !externalDead;

  /// 지난 실행에서 남아 있던 터널을 이번에 거뒀다 — 호스트에게 한 번 알린다.
  /// 모르는 사이 방이 인터넷에 열려 있었다는 뜻이라 조용히 넘기면 안 된다.
  bool reapedOrphanTunnel = false;

  void dismissOrphanNotice() {
    reapedOrphanTunnel = false;
    notifyListeners();
  }

  /// 앱이 직접 관리하는 터널. null 아님 = 우리가 띄운 프로세스가 살아 있음.
  final TunnelService tunnel = TunnelService();
  bool get tunnelRunning => tunnel.running;
  bool tunnelStarting = false;

  /// 원클릭 인터넷 개방 — cloudflared 를 띄워 나온 주소를 방에 건다.
  /// 성공하면 null, 실패하면 사람이 읽을 실패 사유를 돌려준다.
  Future<String?> startTunnel() async {
    if (server == null) return '방이 아직 열리지 않았습니다';
    if (!TunnelService.installed) {
      return 'cloudflared 가 설치되어 있지 않습니다';
    }
    tunnelStarting = true;
    notifyListeners();
    try {
      tunnel.onDied = () {
        // 터널이 스스로 죽으면 주소를 내려 로컬로 돌아간다 — 죽은 주소를
        // QR 에 두는 침묵 고장은 이미 한 번 겪었다.
        externalBase = null;
        externalDead = false;
        _saveExternalBase(null);
        _rebuildUrl();
        notifyListeners();
      };
      final url = await tunnel.start(server!.port);
      if (url == null) {
        return '터널을 열지 못했습니다 — 인터넷 연결을 확인하세요';
      }
      externalBase = url;
      externalDead = false;
      // 임시 터널 주소는 이 프로세스와 함께 죽는다 — 저장하면 다음 실행에서
      // 반드시 죽은 주소가 된다. 저장하지 않는다.
      await _saveExternalBase(null);
      _rebuildUrl();
      return null;
    } finally {
      tunnelStarting = false;
      notifyListeners();
    }
  }

  Future<void> stopTunnel() async {
    await tunnel.stop();
    externalBase = null;
    externalDead = false;
    _rebuildUrl();
    notifyListeners();
  }

  HostAddress? get address =>
      addresses.isEmpty ? null : addresses[addressIndex];

  bool restored = false;

  /// 불러올 때 걷어낸 유령 참가자 수 — 한 번 알리고 지운다.
  int prunedOnLoad = 0;

  /// 불러올 때 못 살린 방 수 — 수명 초과 또는 정원 초과.
  int droppedOnLoad = 0;

  void dismissFreshRoomNotice() {
    prunedOnLoad = 0;
    droppedOnLoad = 0;
    notifyListeners();
  }

  Future<void> start() async {
    try {
      // 지난 실행이 남긴 cloudflared 를 먼저 거둔다 — 살아 있으면 어제 링크가
      // 오늘 방으로 이어진다. 방을 열기 전에 해야 새 방이 그 터널을 물지 않는다.
      if (TunnelService.reapOrphan()) {
        reapedOrphanTunnel = true;
      }
      // 지난 실행이 남긴 업로드 사본(손님 사진·영상)도 여기서 치운다.
      RoomFiles.sweepStale();

      // 기본 포트가 막혀 있으면 누가 물고 있는지 보고 비켜 앉는다.
      final (port, portError) = await RoomPort.pick(
        start: RoomServer.defaultPort,
      );
      if (port == null) {
        error = portError;
        notifyListeners();
        return;
      }

      // 방 서버는 Flutter 를 모른다 — 번들·앱 저장소는 어댑터로 넣어준다.
      const assets = BundleAssetSource();
      final persistence = RoomPersistence(const PrefsStateStore(), assets);
      final srv = RoomServer(assets: assets, port: port);
      final outcome = await persistence.restoreInto(srv);
      restored = outcome.rooms > 0;
      // 오래 안 보인 참가자는 걷어냈다 — 방 자체는 호스트가 지울 때까지 산다.
      prunedOnLoad = outcome.prunedPlayers;
      // 수명이 지났거나 정원을 넘어 안 살아난 방. 조용히 빼면 호스트는
      // "내 방 어디 갔지" 를 답할 수 없다.
      droppedOnLoad = outcome.droppedRooms;
      if (srv.rooms.isEmpty) srv.createRoom();
      room = srv.rooms.first;
      srv.onStateChanged = () {
        _saveSoon(persistence, srv);
        _publish();
      };
      // 제어 API 는 앱 기능이라 방 서버가 아니라 여기서 얹는다.
      srv.extraRoutes = _controlRoute;
      // 토큰은 **여기서** 만든다. 첫 제어 요청 때 만들면 CLI 가 그 첫
      // 요청을 보낼 수단이 없다(닭과 달걀).
      mirror.ensureToken();
      await srv.start();
      // 게임 이벤트는 **모든 방**에서 온다 — 보고 있지 않은 방의 판도 계속
      // 돌고, 그 방의 사회자·효과음은 그 방의 것이다.
      srv.gameEvents.listen((e) => _onGameEvent(e.$1, (e.$2, e.$3)));
      // 방마다 화면 갱신을 태운다. 방이 늘어날 때마다 다시 맞춘다 —
      // 예전에는 시작 시점의 방에만 걸어서, **그 뒤에 만든 방**은
      // 입장·퇴장·업로드가 화면에 안 나타났다(방이 하나뿐이던 시절의 코드).
      _rewireRooms(srv);
      srv.roomsStream.listen((_) {
        _rewireRooms(srv);
        notifyListeners();
      });

      // 복원된 판을 화면 상태에 반영한다. 문구는 종목이 만든다 —
      // 예전에는 여기서 마피아만 손으로 채워, 나머지 네 종목은 판이 돌고
      // 있는데도 상태 줄이 빈 칸이었다.
      _syncGameStatus();

      settings = await HostSettings.load();
      settings.addListener(notifyListeners);
      settings.addListener(() => sound.enabled = settings.soundEnabled);
      sound.enabled = settings.soundEnabled;
      // 첫 재생이 늦지 않게 미리 물려 둔다. 실패해도 게임은 그대로.
      unawaited(sound.warmUp());
      await _loadExternalBase();
      await _probeExternal();
      addresses = await HostAddressFinder.candidates();
      // 터널 주소가 저장돼 있으면 로컬 주소가 하나도 없어도 방을 열 수 있다.
      if (addresses.isEmpty && externalBase == null) {
        // 여기서 그냥 return 하면 이미 포트를 잡은 srv 가 참조 없이 남아,
        // 재시도할 때 같은 포트에 다시 bind 하려다 실패한다.
        await srv.stop();
        error = 'Wi-Fi 또는 핫스팟에 연결해주세요';
        notifyListeners();
        return;
      }
      addressIndex = 0;
      server = srv;
      _rebuildUrl();
      notifyListeners();
      _publish();
    } catch (e) {
      error = _startupMessage(e);
      notifyListeners();
    }
  }

  /// 시작 실패를 사람이 읽을 수 있게 옮긴다. 원문(SocketException …)만 띄우면
  /// "이미 파티룸이 떠 있다" 는 가장 흔한 원인을 알아볼 수 없다.
  static String _startupMessage(Object e) {
    final text = e.toString();
    if (text.contains('Address already in use')) {
      return '이미 파티룸이 실행 중입니다.\n'
          '기존 창을 닫고 다시 시작하세요. (포트 ${RoomServer.defaultPort} 사용 중)';
    }
    return '서버 시작 실패: $e';
  }

  // ---- LLM 사회자 ----

  /// 진행 효과음. 게임 이벤트에서 결정적인 순간에만 운다.
  final SoundService sound = SoundService();

  /// 판을 굴리는 시계 — 화면이 아니라 여기가 들고 있다.

  /// 화면과 CLI 가 함께 지나는 단일 실행 경로.
  late final ControlService control = ControlService(this);

  /// 상태를 디스크에 게시하는 채널 — 에이전트가 스크린샷 없이 읽는다.
  final StateMirror mirror = StateMirror();

  /// 마지막 사회자 발화 — 호스트 화면이 크게 띄운다.
  String mcLine = '';

  /// 설정이 고른 통로. 터미널 구독이 1순위다.
  McSource get mcSource => settings.mcProvider == 'http'
      ? McHttpSource(
          baseUrl: settings.mcBaseUrl,
          model: settings.mcModel,
          apiKey: settings.mcApiKey.isEmpty ? null : settings.mcApiKey,
        )
      : McCliSource(backendId: settings.mcCliBackend);

  McPersona get mcPersona => McPersona.values.firstWhere(
    (p) => p.name == settings.mcPersona,
    orElse: () => McPersona.classic,
  );

  /// 사회자 한 명. **매번 새로 만들면 안 된다** — 실패 후 쉬는 시간
  /// (`McService._mutedUntil`)이 인스턴스에 붙어 있어서, 새로 만들 때마다
  /// 초기화되면 백오프가 한 번도 작동하지 않는다. CLI 가 로그아웃돼 있으면
  /// 이벤트마다 45초짜리 프로세스가 겹쳐 쌓인다.
  McService? _mcCache;
  String? _mcKey;

  McService? get _mc {
    if (!settings.mcEnabled) return null;
    if (settings.mcProvider == 'http' && settings.mcBaseUrl.isEmpty) {
      return null;
    }
    // 설정이 바뀌면(통로·성격) 그때만 새로 만든다.
    final key =
        '${settings.mcProvider}|${settings.mcCliBackend}|'
        '${settings.mcBaseUrl}|${settings.mcModel}|${settings.mcPersona}';
    if (_mcKey != key || _mcCache == null) {
      _mcKey = key;
      _mcCache = McService(source: mcSource, persona: mcPersona);
    }
    return _mcCache;
  }

  /// 설정 화면의 [연결 테스트] — 실제로 한 문장 받아 본다.
  Future<McProbeResult> probeMc() =>
      McService(source: mcSource, persona: mcPersona).probe();

  /// 사회자 발화 순서 관리 — 한 번에 하나, 밀린 것은 최근 것만.
  /// 규칙과 이유는 [McNarrator] 에 있다.
  late final McNarrator _narrator = McNarrator(() => _mc?.narrate)
    ..onLine = (line) {
      mcLine = line;
      room?.mcChat(line);
      notifyListeners();
    };

  /// 게임 진행과 **분리해서** 부른다 — 사회자가 느려도 판은 그대로 간다.
  void _speakMc(String event, Map<String, dynamic> data) =>
      _narrator.speak(event, data);

  /// 이벤트 → 효과음. 여기 없는 이벤트는 조용히 지나간다 —
  /// 진행률처럼 자주 오는 것에 소리를 붙이면 파티가 시끄러워진다.
  void _playCue(String event, Map<String, dynamic> data) {
    switch (event) {
      case 'mafia_phase':
        switch (data['phase'] as String?) {
          case 'night':
            sound.play(GameSound.night);
          case 'day':
            sound.play(GameSound.day);
          case 'vote_closed':
            sound.play(GameSound.reveal);
        }
      case 'mafia_ended':
      case 'liar_ended':
      case 'marble_done':
      case 'poll_closed':
        sound.play(GameSound.win);
      case 'marble_running':
        sound.play(GameSound.start);
      case 'ladder_reveal':
        sound.play(GameSound.reveal);
      case 'ladder_end':
        sound.play(GameSound.win);
    }
  }

  void _onGameEvent(Room from, (String, Map<String, dynamic>) e) {
    final (event, data) = e;

    // 상태 문구는 각 종목이 GameCatalog 에서 소유한다.
    final text = GameCatalog.statusFor(event, data);
    if (text != null) games.gameStatus = text;

    _speakMc(event, data);
    _playCue(event, data);
    // 보고 있지 않은 방의 판이면 화면 상태(games.gameStatus·games.mafiaPhase)는 건드리지
    // 않는다 — 그건 지금 보고 있는 방의 것이다.
    if (!identical(from, room)) {
      notifyListeners();
      return;
    }

    // 마피아 진행 페이지가 쓰는 고유 상태만 여기서 받는다.
    switch (event) {
      case 'mafia_started':
        games.mafiaRoles = (data['roles'] as Map).cast<String, String>();
        games.mafiaPhase = 'role';
      case 'mafia_phase':
        games.mafiaPhase = data['phase'] as String;
      case 'mafia_ended':
        games.mafiaPhase = 'ended';
    }
    notifyListeners();
  }

  void _rebuildUrl() {
    final srv = server;
    final r = room;
    if (srv == null || r == null) return;
    // 살아 있는 터널 주소가 있으면 그게 우선 — 로컬망 조건을 아예 타지 않는다.
    final ext = externalBase;
    if (ext != null && !externalDead) {
      url = ExternalUrl.roomUrl(ext, r.roomToken);
      return;
    }
    if (addresses.isEmpty) return;
    url =
        'http://${addresses[addressIndex].ip}:${srv.port}/?room=${r.roomToken}';
  }

  /// 저장된 인터넷 주소가 아직 살아 있는지 확인하고 [externalDead] 를 세운다.
  Future<void> _probeExternal() async {
    final ext = externalBase;
    if (ext == null) {
      externalDead = false;
      return;
    }
    externalDead = !await ExternalUrl.isReachable(ext);
  }

  /// 사용자가 [다시 확인] 을 눌렀을 때 — 터널을 새로 띄운 뒤 재검사한다.
  Future<void> recheckExternal() async {
    await _probeExternal();
    _rebuildUrl();
    notifyListeners();
  }

  /// 터널 주소를 세우거나(문자열) 해제한다(null/빈 값).
  /// 잘못된 값이면 false 를 주고 아무것도 바꾸지 않는다.
  bool setExternalBase(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      externalBase = null;
      _saveExternalBase(null);
      _rebuildUrl();
      notifyListeners();
      return true;
    }
    final normalized = ExternalUrl.normalize(raw);
    if (normalized == null) return false;
    externalBase = normalized;
    // 방금 입력한 주소는 살아 있다고 보고 시작한다 — 입력 직후 죽었는지는
    // 사용자가 [다시 확인] 으로 검사할 수 있다.
    externalDead = false;
    _saveExternalBase(normalized);
    _rebuildUrl();
    notifyListeners();
    // 입력 직후 백그라운드로 한 번 찔러 본다 — 죽어 있으면 바로 경고가 선다.
    _probeExternal().then((_) {
      _rebuildUrl();
      notifyListeners();
    });
    return true;
  }

  static const _externalKey = 'party_room_external_base';

  Future<void> _saveExternalBase(String? v) async {
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_externalKey);
    } else {
      await prefs.setString(_externalKey, v);
    }
  }

  Future<void> _loadExternalBase() async {
    final prefs = await SharedPreferences.getInstance();
    externalBase = prefs.getString(_externalKey);
  }

  /// 참가자가 못 붙을 때 다른 주소로 바꾼다 — 호스트에 인터페이스가 여러 개면
  /// (Wi-Fi + VPN + 핫스팟) 어느 쪽이 닿는지는 자리마다 다르다.
  void selectAddress(int index) {
    if (index < 0 || index >= addresses.length) return;
    addressIndex = index;
    _rebuildUrl();
    notifyListeners();
  }

  /// 네트워크가 바뀐 뒤(핫스팟 켬 등) 주소 목록을 다시 읽는다.
  Future<void> refreshAddresses() async {
    final found = await HostAddressFinder.candidates();
    if (found.isEmpty) return;
    final current = addresses.isEmpty ? null : addresses[addressIndex].ip;
    addresses = found;
    final keep = found.indexWhere((a) => a.ip == current);
    addressIndex = keep >= 0 ? keep : 0;
    _rebuildUrl();
    notifyListeners();
  }

  // ---- 단톡·자료 (방 채널 — 게임과 무관하게 산다) ----

  void sendChat(String text, {String? sectionId}) {
    room?.hostChat(text, sectionId: sectionId);
  }

  /// 파일 선택창을 띄워 고른 파일들을 방에 공유한다. 공유한 개수를 돌려준다.
  /// 섹션을 안 주면 지금 열린 칸(판이 돌면 그 판)에 들어간다.
  Future<int> shareFiles(List<String> paths, {String? sectionId}) async {
    var shared = 0;
    for (final path in paths) {
      if (await room?.shareFile(path, sectionId: sectionId) != null) shared++;
    }
    if (shared > 0) notifyListeners();
    return shared;
  }

  /// 판 하나의 자료를 통째로 치운다.
  Future<int> clearSectionFiles(String sectionId) async {
    final n = await room?.removeSectionFiles(sectionId) ?? 0;
    if (n > 0) notifyListeners();
    return n;
  }

  Future<void> removeSharedFile(String id) async {
    await room?.removeFile(id);
    notifyListeners();
  }

  /// 방 하나를 비운다 — 참가자·대화·자료·진행 중인 판을 지우되
  /// **토큰과 이름은 남긴다.**
  ///
  /// 예전 '방 초기화' 는 저장소를 통째로 비우고 서버를 재시작했다. 방이
  /// 하나뿐일 때는 그게 곧 "이 방 비우기" 였지만, 지금은 **다른 방까지
  /// 날아간다.** 방을 없애는 것은 방 목록의 [지우기] 가 한다.
  ///
  /// 비우기와 지우기를 가르는 이유: 같은 친구 그룹으로 다음 판을 시작할 때
  /// 나눠준 QR·링크를 다시 뿌리고 싶지는 않다.
  Future<void> clearRoom([String? token]) async {
    final r = token == null ? room : server?.byToken(token);
    if (r == null) return;
    _narrator.reset();
    games.stopTracing();
    await r.clear();
    if (identical(r, room)) {
      games.gameStatus = '';
      games.mafiaPhase = '';
      games.mafiaRoles = {};
    }
    notifyListeners();
    _publish();
    _persist();
  }

  /// 창을 닫거나 앱을 끝낼 때 — 터널·서버·소리를 접는다.
  ///
  /// 특히 터널: 우리가 안 죽이면 cloudflared 는 살아남아 공개 주소를 계속
  /// 연다. [dispose] 는 강제 종료 때 불리지 않으므로 [TunnelService.reapOrphan]
  /// 이 다음 실행에서 한 번 더 받쳐 준다.
  /// 상태 게시 — 알림이 몰아칠 때 파일을 초당 수십 번 쓰지 않게 묶는다.
  Timer? _publishTimer;

  void _publish() {
    _publishTimer?.cancel();
    _publishTimer = Timer(const Duration(milliseconds: 250), () {
      mirror.publish(control.snapshot());
    });
  }

  Timer? _saveTimer;
  RoomPersistence? _pendingSave;
  RoomServer? _pendingSaveServer;

  /// 저장을 모아 친다.
  ///
  /// 저장 한 번은 모든 방의 대화·명단·판을 통째로 JSON 으로 만들어 디스크에
  /// 쓰는 일이다. 그런데 "바뀌었다" 는 신호는 잘게 온다 — 채팅 한 줄,
  /// 밤 행동 하나, 그리고 구슬이 굴러가는 동안에는 초당 여러 번. 신호마다
  /// 그대로 쓰면 판이 도는 내내 UI 스레드가 직렬화에 붙들린다.
  ///
  /// 800ms 안에 몰린 변경은 한 번으로 친다. 그 사이에 앱이 죽으면 마지막
  /// 1초를 잃지만, 그 대가로 판이 도는 동안 앱이 멈추지 않는다.
  void _saveSoon(RoomPersistence p, RoomServer srv) {
    _pendingSave = p;
    _pendingSaveServer = srv;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _flushSave);
  }

  /// 미뤄 둔 저장을 지금 쓴다. 종료 직전처럼 더 못 미룰 때.
  void _flushSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final p = _pendingSave;
    final srv = _pendingSaveServer;
    if (p == null || srv == null) return;
    p.save(srv);
  }

  /// 로컬 제어 요청. 토큰이 맞아야 하고, 아니면 방 서버 경로로 넘긴다.
  ///
  /// 루프백 검사만으로는 부족하다 — 인터넷 개방 중에는 cloudflared 가 로컬에서
  /// 접속해 오므로 바깥 요청도 127.0.0.1 로 보인다. 토큰이 진짜 문지기다.
  Future<Response?> _controlRoute(Request req) async {
    if (req.url.path != 'api/control') return null;
    if (req.method != 'POST') {
      return Response(
        405,
        body: '{"ok":false,"error":{"message":"POST only"}}',
      );
    }
    if (req.headers['x-party-control'] != mirror.ensureToken()) {
      return Response.forbidden(
        jsonEncode({
          'ok': false,
          'error': {'message': '제어 토큰이 맞지 않습니다'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _controlJson(400, {
        'ok': false,
        'error': {'message': '본문이 JSON 이 아닙니다'},
      });
    }
    try {
      final result = await control.run(
        body['command'] as String? ?? '',
        (body['args'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      _publish();
      return _controlJson(200, {'ok': true, 'result': result});
    } on ControlUsageError catch (e) {
      return _controlJson(400, {
        'ok': false,
        'error': {'message': e.message, 'kind': 'usage'},
      });
    } on ControlFailure catch (e) {
      return _controlJson(409, {
        'ok': false,
        'error': {'message': e.message, 'kind': 'failure'},
      });
    } catch (e) {
      return _controlJson(500, {
        'ok': false,
        'error': {'message': '$e'},
      });
    }
  }

  static Response _controlJson(int status, Map<String, dynamic> body) =>
      Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  // ---- 랑데부(밖에 있는 사람) ----
  //
  // 로컬이 먼저다. 같은 Wi-Fi 면 참가자는 호스트에게 곧장 붙고 랑데부는
  // 등장하지 않는다 — QR 도 로컬 주소를 그대로 보여준다. 랑데부는 그게
  // 안 되는 사람을 위한 **두 번째 QR** 이다: 망이 다르거나, AP 격리가
  // 걸렸거나, 방화벽이 막았거나.

  RelayClient? relay;

  RelayStatus get relayStatus => relay?.status ?? RelayStatus.off;

  /// 밖에 있는 사람에게 줄 주소. 아직 코드를 못 받았으면 null.
  String? get relayUrl {
    final r = room;
    if (r == null) return null;
    return relay?.joinUrl(r.roomToken);
  }

  String? get relayCode => relay?.code;

  /// 랑데부에 건다. 주소가 설정에 없으면 아무것도 안 한다.
  Future<void> startRelay() async {
    final base = settings.relayBase.trim();
    final srv = server;
    if (base.isEmpty || srv == null) return;
    await stopRelay();
    // 비밀은 **재접속 때 같은 코드를 되찾는 열쇠**다. 파티 도중에 코드가
    // 바뀌면 이미 나눠 준 QR 이 전부 죽으므로, 한 번 만들어 두고 계속 쓴다.
    if (settings.relaySecret.isEmpty) {
      settings.setRelaySecret(RelayClient.newSecret());
    }
    relay = RelayClient(
      server: srv,
      relayBase: base,
      secret: settings.relaySecret,
      code: settings.relayCode.isEmpty ? null : settings.relayCode,
      onChanged: () {
        final c = relay?.code;
        if (c != null && c != settings.relayCode) settings.setRelayCode(c);
        notifyListeners();
      },
    );
    await relay!.start();
    notifyListeners();
  }

  Future<void> stopRelay() async {
    await _stopRelayQuietly();
    notifyListeners();
  }

  /// 알림 없이 접는다.
  ///
  /// [shutdown] 은 [dispose] 가 부르는데, 그 뒤에 `notifyListeners()` 를
  /// 하면 "disposed 된 ChangeNotifier 를 썼다" 로 터진다. 끄는 일과 알리는
  /// 일을 나눠 둔다.
  Future<void> _stopRelayQuietly() async {
    final r = relay;
    relay = null;
    await r?.stop();
  }

  Future<void> shutdown() async {
    _publishTimer?.cancel();
    await _stopRelayQuietly();
    for (final subs in _roomSubs.values) {
      for (final s in subs) {
        await s.cancel();
      }
    }
    _roomSubs.clear();
    // 모아 두던 저장을 지금 쓴다 — 안 그러면 마지막 변경이 통째로 날아간다.
    _flushSave();
    games.stopTracing();
    await tunnel.stop();
    await server?.stop();
    await sound.dispose();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
