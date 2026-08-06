# Party Room (파티룸)

Offline party-game host app (Flutter) — mafia, liar, vote, ladder, marble roulette.

> Source exported from `flutter-app-mono` for public binary + source releases.

## Layout

```
apps/game-party-room-app/   # Flutter host app
packages/party_room_server/ # pure Dart room server
packages/party_room_relay/
packages/llm_cli_runtime/
```


## CI builds

GitHub Actions (`.github/workflows/build.yml`) builds **Android / Windows / macOS / Linux / iOS(unsigned)** on `workflow_dispatch` or tag `v*`.

Notarized macOS DMG and Android APK for end users are on [Releases](https://github.com/dalsoop/party-room/releases) (local Developer ID pipeline).

## Downloads

See [Releases](https://github.com/dalsoop/party-room/releases) for:
- **Android** APK (sideload)
- **macOS** notarized DMG (Developer ID)

iOS → TestFlight (Apple account required). Windows → build on Windows / CI.

## Build

```bash
cd apps/game-party-room-app
flutter pub get
flutter run -d macos   # or android / ios / windows / linux
```

Release helpers: `tools/release.sh` (macOS notarized DMG).

---

# game-party-room-app (파티룸)

**호스트 한 대가 로컬 서버가 되고, 나머지는 QR 스캔으로 브라우저 입장하는 오프라인 파티게임 플랫폼.**
인터넷·외부 서버 불필요 — 같은 Wi-Fi(또는 호스트 핫스팟)만 있으면 동작.

이어받는 사람용 메모(구조·함정·검증법)는 [`docs/HANDOFF.md`](docs/HANDOFF.md).

## 게임

| 게임 | 인원 | 설명 |
|---|---|---|
| 마피아 | 4~20 | 역할 11종(기본4+확장7), 인원수별 자동 편성, 밤/낮/투표 상태머신 |
| 라이어 게임 | 3~20 | 랜덤 제시어 5카테고리 + 사회자 커스텀(글자+이미지 업로드) |
| 익명 투표 | 2~20 | 질문/선택지 즉석 생성, 전원 투표 시 자동 공개 |
| 사다리타기 | 2~20 | 한 줄씩(또는 한꺼번에) 결과 공개 |
| 구슬 룰렛 | 2~20 | 코스·속도·1등/꼴찌 선택, 벌칙자·순서 정하기 |

### 마피아 역할
기본: 마피아 · 의사 · 경찰 · 시민  
확장(8인+부터 자동 편성): 군인(방탄1회) · 영매 · 스파이 · 저격수(필살1회) · 기자 · 정치인(2표) · 연인(동반사망)

## 주요 기능

- **다방**: 호스트 기준으로 방을 여러 개 동시에 운영. 각자 QR을 갖고, 한 방에서 판이 도는 동안 다른 방은 대기할 수 있다.
- **단톡·자료함**: 로비와 별도 화면. 대화 칸은 **전체**(방 상시) + **판마다** 갈린다(말·자료가 있던 판만 남김).
- **입장 비밀번호(옵션)**: 방마다 4자리 숫자 PIN. 방 토큰(QR) 위의 두 번째 자물쇠. 세션 복구 재입장은 다시 묻지 않는다.
- **`partyroom` CLI**: GUI와 같은 `ControlService`를 지난다. 화면 자동화 없이 방·판·자료 조작.

## 아키텍처

```
호스트 앱 (Flutter: iOS/Android/macOS/Windows/Linux)
 └─ party_room_server (순수 Dart 패키지, 포트 8765)
     ├─ /            참가자 SPA (앱 번들 assets/web)
     ├─ /js/* · /img/* · /fonts/*   정적 자산 (화이트리스트)
     ├─ /api/join    입장 (방 토큰 + 닉네임 [+ pin], 세션 발급)
     ├─ /api/upload  자료 업로드 (x-party-session 헤더)
     ├─ /file/<id>   자료 내려받기
     ├─ /ws          실시간 (첫 프레임 type:auth 로 세션 인증)
     └─ /liar-image  라이어 커스텀 이미지 (메모리)
```

- **게임 모듈**: `../../packages/party_room_server/lib/src/games/` 에 `GameModule` 구현 + 레지스트리 등록. 앱 쪽 로비·진행 화면 연결은 `lib/games/game_catalog.dart` 한 항목.
- **보안**: 방 토큰(QR) + 세션 토큰(개인별) + 선택 PIN. 비밀 정보(역할 등)는 해당 세션에만 전송. 세션은 URL에 실지 않는다.
- **복구**: 호스트 앱 재시작 시 방·게임 상태 복원, 참가자 새로고침 시 세션 자동 복구.
- **UX 원칙**: 타이머 없음(진행은 호스트 버튼), 아바타 없음, 참가자는 QR→닉네임→끝.

## 실행

```bash
flutter pub get
flutter run -d <device>            # iOS/Android/macOS 등
flutter build apk --release        # Android 배포
flutter build macos --release      # macOS 배포
```

참가자: 호스트 화면의 QR 스캔 → 브라우저 → 닉네임 입력(PIN이 걸린 방이면 4자리도).

### partyroom CLI (앱이 떠 있을 때)

```bash
partyroom rooms --json             # 방 목록
partyroom room new 금요모임        # 방 만들기
partyroom room pin 4821            # 입장 PIN (해제는 pin off)
partyroom games --json             # 종목·최소인원·받는 action
partyroom start mafia              # 판 시작
partyroom chat 안녕하세요          # 호스트로 한마디
```

설치·상세 명령은 `cli/` 참고. `--json` 은 모든 명령에 붙일 수 있다.

### 이 맥 환경 특이사항 (mavenCentral 403)
이 네트워크에서 maven central이 차단되어 있어 다음이 적용됨:
- `~/.gradle/init.d/coroutines-force.gradle` — coroutines 1.9.0→1.7.3(캐시), listenablefuture→empty 버전 강제
- `network_info_plus`/`wakelock_plus` 미사용 — IP는 `NetworkInterface.list`, 화면 유지는 네이티브 한 줄
  (Android `FLAG_KEEP_SCREEN_ON`, iOS `isIdleTimerDisabled`)

## 배포 빌드
- CI: `.github/workflows/build-game-party-room.yml` — 5플랫폼 아티팩트 (`workflow_dispatch` 또는 `party-room-v*` 태그)
