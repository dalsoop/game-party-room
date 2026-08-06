# 파티룸 — 이어받는 사람에게

작성 2026-07-29 · 기준 `main` · 테스트 서버 295 · 앱 202 · 릴레이 14

친구들과 오프라인에서 하는 파티게임. 맥 앱 한 대가 서버가 되고, 친구들은
QR 로 브라우저만 열면 된다. 인터넷 없이 같은 Wi-Fi 만 있으면 돈다.

**그게 기본이고, 이제 그게 안 될 때의 길이 둘 더 있다** — 밖에 있는 사람을
들이는 랑데부(`relay.ranode.net`)와, 맥 없이도 열려 있는 상시 서버
(`party.ranode.net`). 자세한 것은 9장.

이 문서는 **README 가 안 적는 것**을 적는다: 지금 구조가 왜 이런지, 무엇을
믿어도 되는지, 어디를 조심해야 하는지. 기능 소개는 `../README.md`.

---

## 1. 어디에 무엇이 있나

```
packages/party_room_server/     순수 Dart. Flutter 를 모른다.
  room.dart                     방 하나 — 참가자·대화·자료·진행 중인 판
  room_server.dart              듣는 쪽 — 토큰으로 방을 찾아 넘긴다
  participant_link.dart         참가자에게 닿는 통로(보내기·닫기 둘뿐)
  participant_gate.dart         접속 수립 절차 — 모든 길이 이 문을 지난다
  relay_client.dart             랑데부에 거는 호스트 쪽 끝
  control/                      화면 없이 방을 굴리는 표면(헤드리스가 쓴다)
  bin/serve.dart                헤드리스 진입점
  room_channels.dart            대화 칸(전체 + 판마다)
  room_files.dart               자료 공유·쿼터
  room_persistence.dart         저장·복구
  room_limits.dart              한계값 정본 (서버·폰이 같은 값을 본다)
  games/                        마피아·라이어·투표·구슬·사다리

apps/game-party-room-app/
  lib/host_controller.dart      서버 수명·방 목록·주소·터널·사회자·효과음
  lib/games/game_control.dart   판을 시작하고 굴리고 끝내는 일
  lib/games/game_catalog.dart   종목 목록 — 새 게임은 여기 한 항목만 추가
  lib/pages/                    호스트 화면들
  lib/server/control_service.dart  GUI·CLI 가 함께 지나는 단일 실행 경로
  cli/                          `partyroom` 명령
  assets/web/                   참가자 폰 화면(SPA) — 번들에 실려 서빙된다

packages/party_room_relay/      랑데부 서버. **게임을 모른다.**
  relay_server.dart             짝 지어 주기 + 프레임 나르기 + 화면 서빙
  protocol.dart                 호스트↔릴레이가 쓰는 말
```

**전송은 `ParticipantLink` 뒤에 있다.** 방은 소켓을 직접 안 든다 — 통로가
할 줄 아는 일은 "프레임 하나 보내기, 닫기" 둘뿐이고, 같은 망이든 랑데부를
거치든 방은 구분하지 않는다. 길을 하나 더 늘릴 때 방을 안 뜯어도 되는 것이
이 구조의 값어치다(닌텐도 Pia 가 로컬·인터넷 통신에 공통 API 를 씌운 것과
같은 이유).

**경계는 실제로 지켜지고 있다.** 서버 패키지에 Flutter 의존이 0이고, 화면
문구도 0이다(`Speaker`·`kind`·`round` 같은 사실만 싣고 말로 옮기는 일은
화면이 한다). 앱이 게임 판정을 다시 구현한 곳도 없다.

---

## 2. 먼저 알아야 할 함정

### 참가자 화면은 **앱 번들에서** 나온다

`assets/web/` 을 고쳤으면 **앱을 다시 빌드해야** 폰에 반영된다. 소스를 고치고
브라우저만 새로고침하면 옛 화면이 그대로다 — 이걸로 "고쳤는데 그대로" 를
여러 번 겪었다.

### 호스트 창은 스크린샷이 안 찍힐 수 있다

창이 다른 Space 에 있으면 `screencapture` 도 접근성 API 도 못 잡는다. 그래서
이 앱에는 CLI 가 있고(`partyroom`), 화면 확인이 필요하면 위젯 테스트로 PNG 를
뽑는다:

```bash
PARTY_SHOTS=1 flutter test test/mafia_page_shots_test.dart   # /tmp/mafia_page_*.png
PARTY_SHOTS=1 flutter test test/other_pages_shots_test.dart  # /tmp/page_*.png
```

평소에는 이 테스트가 안 돈다(아무것도 검사 안 하면서 파일만 쓴다).

### 세션 토큰은 **주소에 안 싣는다**

인증은 WebSocket 첫 프레임(`{type:'auth'}`), 업로드는 `x-party-session` 헤더.
주소에 담으면 브라우저 방문기록·프록시 로그·Cloudflare 접속 로그에 자격증명이
남는다. 한동안 하위호환으로 `?session=` 도 받았지만 지금은 막혀 있고,
`hardening_test.dart` 가 "주소만으로는 안 붙는다" 를 지킨다.

테스트에서 참가자를 붙일 때는 `test/support/participant.dart` 의 `authAs` 를 쓴다.

### 시간으로 기다리지 말고 **상태로** 기다린다

고정 지연(`Future.delayed(150ms)`)으로 기다리는 테스트가 부하를 타고 흔들렸다.
더 나쁜 사례도 있었다 — 150+150ms 가 **우연히 도배 억제 문턱(300ms)을 넘고
있어서**, 기계가 한가해 빨리 진행되면 오히려 실패하는 거꾸로 된 테스트였다.
`waitUntil`·`waitForFrame`(같은 파일)을 쓴다.

### 참가자 화면은 **릴레이 이미지에도** 구워져 있다

`assets/web/` 을 고치면 앱만 다시 빌드해서는 부족하다. 릴레이가 밖에서 온
사람에게 주는 화면은 **그 이미지 안에** 있어서, 이미지를 안 다시 구우면
**밖에서 온 사람만** 조용히 옛 화면을 받는다. 증상이 "들어와지는데 뭔가
이상하다" 라 원인 찾기가 아주 나쁘다.

```bash
curl -s https://relay.ranode.net/healthz     # assets 지문
partyroom relay                              # 호스트가 읽은 저쪽 지문
```

둘이 다르면 이미지를 다시 구워야 한다(9장).

### 빌드 산출물 판정에 `App.framework/App` 을 쓰지 말 것

그건 **심볼릭 링크**라 `stat` 이 링크 자체의 시각을 보여준다. 새로 구운
빌드를 옛 것으로 두 번 오판했다. 진짜 바이너리는
`App.framework/Versions/A/App` 이다.

그리고 **AOT 스냅샷에서 문자열 grep 은 안 통한다** — 한글이든 영어든 안
잡힌다. "이 기능이 빌드에 들었나" 를 grep 으로 확인하려 들지 말고,
앱을 띄워 상태 미러(`state.json`)나 CLI 로 확인한다.

### `flutter build macos` 를 **두 개 동시에 돌리지 말 것**

같은 빌드 DB 를 쥐어서 뒤엣것이 `database is locked` 로 죽는다. 앞엣것이
느려 보여도 살아 있는 경우가 많으니 `pgrep -f xcodebuild` 로 먼저 본다.

### CLI 는 `dart compile exe` 가 아니라 **kernel** 이다

Flutter 번들 SDK 에 `gen_snapshot` 이 없어 `exe` 가 안 된다. `cli/install.sh`
가 커널 스냅샷을 만들고 얇은 래퍼를 PATH 에 건다. 설치는 그 스크립트로 한다.

```bash
cd cli && sh install.sh
```

**설치본과 CLI 는 함께 갱신한다.** 앱에 새 명령이 있는데 CLI 가 옛것이면
"모르는 명령" 으로 헤맨다.

### 앱 설정을 파일로 직접 고치려 들지 말 것

앱이 샌드박스라 설정은 컨테이너 프리퍼런스에 있고, cfprefsd 가 캐시를 쥐고
있어 파일을 고쳐도 무시된다. `defaults` 는 전역 도메인에 써서 앱이 못 읽는다.
**설정은 화면이나 CLI 로 바꾼다** — 그러라고 `partyroom relay set` 이 있다.

---

## 3. 확인하는 법

```bash
# 단위·통합
cd packages/party_room_server && dart test          # 295 (skip 2)
cd apps/game-party-room-app && flutter test         # 202 (skip 6)
cd packages/party_room_relay && dart test           # 14

# 진짜 배포에 붙어 보는 것(평소 스위트에서 빠져 있다)
cd packages/party_room_server
dart test test/live_relay_manual_test.dart  -t live --run-skipped
dart test test/live_relay_restart_test.dart -t live-disruptive --run-skipped  # 혼자 돌릴 것

# 설치본으로 실제 확인 (화면 자동화가 안 되므로 CLI 로 몬다)
flutter build macos --release
rm -rf /Applications/PartyRoom.app && cp -R build/macos/Build/Products/Release/PartyRoom.app /Applications/
codesign --force --deep --sign - /Applications/PartyRoom.app
open -a /Applications/PartyRoom.app

partyroom rooms --json
partyroom room new 확인
partyroom start mafia && partyroom mafia night && partyroom mafia day
partyroom games --json     # 종목마다 받는 action 목록이 여기 나온다
```

참가자 여럿이 필요하면 `/tmp/play.dart` 같은 하니스로 소켓을 붙인다(장면에
자동 반응하도록 짜 두면 판을 끝까지 굴릴 수 있다).

**테스트만으로는 부족한 변경이 있다.** 애니메이션 루프(구슬·사다리)나 저장
경로를 건드렸으면 설치본에서 실제로 한 판 굴려 봐야 한다 — 이번에 실제로
테스트는 통과하는데 설치본에서만 드러난 문제가 있었다.

---

## 4. 이번에 고친 것 중 기억할 만한 것

숫자는 전부 실측이다.

| 무엇 | 어땠나 |
|---|---|
| 판 진행 저장 | **저장된 적이 없었다.** 게임 이벤트가 방을 "바뀜" 으로 표시하지 않아, 3줄 공개한 사다리가 재시작 후 0줄이 됐다. 지금은 이벤트가 저장을 부르고 800ms 로 모아 친다 |
| 방 정원 | 명단 20(정원)인데 접속 1명이라 아무도 못 들어왔다. 30분 넘게 안 보인 사람부터 자리를 비켜 준다 — 단, **막 들어온 사람(lastSeen 없음)은 절대 안 뺏는다**(동시에 QR 찍으면 서로를 쫓아낸다) |
| 끝난 판 | `ended` 인데 페이즈 명령이 먹혀 남은 2명이 1명이 될 때까지 계속 죽었다 |
| 빈 판 칸 | 구슬 9판을 돌리자 빈 칸 11개가 단톡 탭을 채웠다. 말도 자료도 없는 칸은 안 남긴다 |
| `room pin` | 잘못 부르면 **자물쇠를 풀고 성공을 보고**했다. 모르는 옵션을 거절하고, 해제는 `off` 라고 적어야만 된다 |
| 다방 배선 | `lobbyStream` 구독이 시작 시점의 방에만 걸려 있어, 그 뒤 만든 방은 입장·퇴장이 화면에 안 나타났다 |
| **브로드캐스트** | 285개 테스트가 있는데 `broadcast` 를 **첫 사람에게만** 보내도 전부 통과했다. 채팅·로비·장면 전환이 다 그 길인데 아무도 안 서 있었다. 한 명의 통로가 터져도 나머지가 받도록 함께 고쳤다(탭 닫으면 sink 가 먼저 닫히고 onDone 은 늦게 온다) |
| **이름 바꾸기** | 길이 **아예 없었다.** 서버가 받는 참가자 메시지가 `ping`·`chat` 뿐이라, 오타 하나면 파티 내내 그 이름이었다. `Player.nickname` 주석엔 진작 "바뀌기도 한다" 고 적혀 있었는데 구현만 없었다 |
| **방 개수·수명** | 둘 다 무제한이었다. 개인 맥에선 괜찮았지만 상시 공용 서버가 생기며 전제가 달라졌다 — 서버당 2개·3일. **방의 성질이 아니라 서버 정책**(`maxRooms`·`roomTtl`)이라 기계마다 다르게 둘 수 있다 |
| 전용 Wi-Fi 안내 | 기능은 다 있었는데 **주소가 하나도 없을 때 거기로 가는 길이 사라졌다** — 안내가 필요한 바로 그 순간에 |

### 테스트가 아무것도 안 지키던 자리 셋

보안·계약 테스트는 **돌연변이로 검증한다**(방어를 일부러 떼고 빨간불이 뜨는지
본다). 그 과정에서 셋이 드러났다 — 전부 "통과하지만 아무것도 안 보는" 테스트였다.

1. **브로드캐스트** — 위 표 참조
2. **방 코드 알파벳** — 상수를 그대로 비교해서 상수와 함께 움직였다. 헷갈리는
   글자로 통째로 바꿔도 통과했다. 막고 싶은 글자를 직접 적어야 잣대가 된다
3. **경로 탈출** — 서버를 시험한 적이 없었다. Dart 의 `HttpClient` 는 보내기
   전에, `HttpServer` 는 받기 전에 `..` 를 지운다(소켓에 날것으로 써서 확인했다).
   방어를 통째로 떼어도 통과했다 — 판정을 함수로 꺼내 직접 먹여야 했다

---

## 5. 열려 있는 것

**재현 못 한 것 하나** — 마피아 진행 중 제어 API 가 10초 넘게 응답하지 않은
적이 있다. 이후 수십 번 굴려도 재현되지 않았다. 저장을 모아 치게 바꾼 것이
원인이었을 수 있지만 **확인되지 않았다.** 다시 나오면 그때가 단서다.

**손 못 댄 것**
- 실기기 아이폰 — 백그라운드 소켓 타이밍, HEIC 업로드. 시뮬레이터로는 못 본다.
  (다만 **실제 브라우저로 릴레이 경유 입장까지는 확인했다** — 렌더·입장·소켓·
  자료 차단, 콘솔 오류 0)
- 다방 사용성 — 이제 방이 최대 2개라 그 이상은 정책상 없다. 대신 **방 목록의
  검색칸이 영영 안 나온다**(방이 많을 때만 나타나는 UI). 기능은 안 지웠다

**계속 그 상태로 두는 것**
- `wadecho.com` 이 등록기관 `clientHold`(결제 안 함, 의도된 상태). 그래서
  host-infra 의 `cf-delegation-check` 는 **앞으로도 계속 실패한다.** 고치려
  들지 말 것 — `dns/` 작업은 `TOFU_TARGET=cf` 우회로가 정식 경로다(9장)

**의도적으로 안 한 것**
- 참가자 폰의 마피아 배너 6장 — 짧은 화면에서만 접히게 했고 더 줄이지 않았다
- 호스트 배너는 마피아·라이어·투표에서 뺐다. 구슬·사다리는 원래 없다

---

## 6. 새 게임을 넣으려면

1. `packages/party_room_server/lib/src/games/` 에 `GameModule` 구현
2. `GameRegistry` 에 등록 (저장분 복구가 이걸 본다)
3. 앱의 `game_catalog.dart` 에 **항목 하나** 추가 — 로비 카드·진행 화면·
   상태 문구·복구 문구가 여기서 나온다
4. `ControlService.actions` 에 그 게임이 받는 action 을 적는다 (오류 문구와
   `partyroom games` 가 이 표를 읽는다)
5. 폰 화면이 필요하면 `assets/web/js/games/` 에 추가

`restoredStatus` 를 빠뜨리면 테스트가 잡는다 — 재시작 후 상태 줄이 빈 칸이
되는 것을 막으려고 넣어 뒀다.

---

## 7. 헤드리스 서버

앱 없이 방을 여는 진입점이 있다. **앱과 완전히 같은 서버 코드**다 —
`AssetSource`·`StateStore` 만 파일시스템 판으로 갈아 끼운다.

```bash
cd packages/party_room_server
dart run bin/serve.dart --assets ../../apps/game-party-room-app [--port 8765]
```

띄우면 참가 URL 을 찍어 준다. **첫 실행은 컴파일 때문에 10초 넘게 걸린다**
— 몇 초 기다렸다가 안 뜬다고 판단하면 안 된다(그렇게 한 번 헛짚었다). 개발 중 **참가자 화면만** 볼 때 편하다 —
맥 앱을 빌드하지 않아도 되고, `assets/web/` 을 고치면 바로 반영된다
(앱 번들과 달리 파일을 직접 읽으므로 2장의 "다시 빌드" 함정이 없다).

**여기가 파일시스템을 직접 읽는다는 점을 기억할 것.** 앱 번들에서는
없는 파일이 그냥 없지만, 여기서는 경로 탈출이 뚫리면 진짜 소스가 샌다.
`WebAssets` 의 화이트리스트가 그걸 막고 `web_assets_test.dart` 가 지킨다
(확장자까지 맞춘 `js/../../secret.js` 같은 모양을 포함해서 — 그게 제일
먼저 뚫리는 자리다).

한동안 아무도 안 돌려 봤던 코드라, 서버 쪽을 크게 고쳤으면 한 번 띄워
보는 편이 좋다. 실제로 이번에 세션 인증·저장 스키마를 바꾼 뒤 확인했다.

**이제 이게 상시로 돈다** — `party.ranode.net` 이 이 진입점을 컨테이너로 만
것이다(9장). 그러면서 셋이 붙었다:

- **제어 API** — `RoomControl` + `ControlEndpoint`. 화면 없이 방·참가자·판을
  다룬다. 토큰이 없으면 문을 아예 안 연다
- **공통 게임 명령** — `GameControlCommands` 가 앱·헤드리스의 시작/종료와
  마피아·라이어·구슬·사다리 세부 진행을 한 번만 구현한다. 실제 시간 진행은
  방마다 하나인 `RoomGameControl` 이 맡아, 다른 방을 골라도 돌던 판이 안 멈춘다
- **SIGTERM** — 예전엔 Ctrl+C(SIGINT)만 받았다. 쿠버네티스는 SIGTERM 을 보내고,
  안 받으면 30초 뒤 강제종료되는 동안 참가자는 멈춘 화면을 본다
- **환경변수** — `PORT`·`PARTY_ASSETS`·`PARTY_STATE`·`PARTY_ROOM_NAME`·
  `PARTY_CONTROL_TOKEN`. 컨테이너에서는 인자보다 값으로 주는 편이 낫다

---

## 8. 판매용 배포

`tools/release.sh` 가 빌드 → Developer ID 서명(Hardened Runtime) → DMG →
애플 공증 → 스테이플 → Gatekeeper 판정까지 한 번에 한다.

**adhoc 서명(`codesign --sign -`)은 개발 전용이다.** 내 맥에서만 통한다 —
남에게 주면 Gatekeeper 가 막고, 받은 사람은 앱이 고장 난 줄 안다.

### 방화벽·로컬 네트워크 권한 — 실측으로 확인한 것

파는 앱이 서버를 열면 두 가지가 걱정된다. 둘 다 확인했다.

**방화벽은 서명이 해결한다.** macOS 방화벽은 앱을 코드 서명으로 식별하고,
유효한 인증서로 서명된 앱은 자동 허용한다("다운로드한 서명 소프트웨어 자동
허용" 이 기본값 ON). 방화벽을 켠 채 **다른 기기에서** 접속해 확인했다 —
대화상자 없이 그대로 붙는다.

시험이 진짜 방화벽을 거쳤는지도 확인했다: `--setblockall on` 으로 두면
같은 요청이 실패한다(`000`). 안 그러면 "안 막혔다" 가 아니라 "안 거쳤다"
일 수 있다.

**로컬 네트워크 권한은 해당 없다.** macOS 15+ 의 그 권한은 **나가는** 로컬
연결·Bonjour·`.local` 이름 해석에 필요하다. 수신 TCP 를 듣고 받는 것은
권한이 필요 없다. 파티룸은 듣기만 하므로 `NSLocalNetworkUsageDescription`
없이도 문제가 없다(이 맥의 권한 목록에 올라온 적이 없는 것으로도 확인).

### 앱스토어는 지금 구조로 안 된다

서버를 열고 외부 프로세스(cloudflared)를 띄우므로 샌드박스와 맞지 않는다
(`app-sandbox: false`). 직접 배포가 맞는 길이다.

### 아직 안 한 것

- **실제 폰이 Wi-Fi 로 붙는 경로**는 여전히 안 해봤다. 원격 시험은 VPN
  인터페이스로 했다 — ALF 를 거치는 것은 확인했지만 Wi-Fi 와 같은 경로는
  아니다.
- 버전이 `1.0.0+1` 그대로다.
- 설정의 CLI 항목은 자동화용인데, 일반 구매자에게는 "CLI 가 PATH 에 없습니다"
  라는 알 수 없는 경고로 보인다.

---

## 9. 지금 떠 있는 것 (인프라)

| 주소 | 무엇 | 언제 쓰나 |
|---|---|---|
| — | **로컬 직접** | 기본. 같은 Wi-Fi 면 이것뿐이고 제일 빠르다 |
| `relay.ranode.net` | 랑데부 | 참가자가 **다른 망**에 있을 때 |
| `party.ranode.net` | 상시 방 서버 | 맥 앱이 안 떠 있어도 방이 열려 있어야 할 때 |

**로컬이 먼저다.** 랑데부는 두 번째 QR 이지 기본 경로가 아니다.

### 왜 릴레이가 필요한가 (P2P 가 아니라)

브라우저에 벽이 두 겹이다. `RTCPeerConnection` 은 **secure context 전용**이라
`http://192.168.x.x` 로 뿌린 화면에서는 WebRTC 자체가 막히고, 반대로 페이지를
https 로 주면 그 페이지에서 `ws://192.168.x.x` 로 못 붙는다(mixed content).
다른 망의 폰에게 페이지를 줄 방법이 이것뿐이다.

실측: 실시간 프레임은 참가자당 2KB(5인 한 판 9.7KB)라 전부 중계해도 싸다.
비용은 화면 자산(6.3MB, 폰트 하나가 2.45MB)에 있고 gzip + 캐시로 잡는다.
**자료 업로드(1인 30MB)는 아예 안 나른다** — 네 자릿수가 다르다.

### 배포는 저장소 셋을 거친다

```
flutter-app-mono            소스 + Dockerfile + CI 빌드      project 394
kubernetes-infra            차트 + ArgoCD 앱                  project 329
host-infra                  도메인 SSOT (dns/zones/…)         project 261
```

> ⚠️ **project 363 은 swift-app-mono 다.** 한 번 헷갈려 엉뚱한 저장소에 MR 을
> 만들었다(바로 닫았다). MR 은 `glab api` 로 직접 낸다 — `glab mr create` 는
> 호스트 불일치로 실패한다.

**이미지는 CI 가 굽는다.** `packages/party_room_*/**` 나 `assets/web/**` 이
main 에 들어가면 `build-party-room-*` 잡이 `pve-host` 러너에서 굽고
`0.1.0-<커밋sha>` 로 harbor 에 민다. 그 호스트에 docker·harbor 로그인이 이미
있어서 **새 자격증명을 안 심었다.** 수동은 파이프라인에 `BUILD_IMAGES=party-room`.

급할 때의 폴백은 `packages/party_room_*/tools/build-and-push.sh`(맥에서 rsync).
다만 손으로 구운 태그는 git 에 출처가 안 남으니 배포에 박지 말 것.

**배포 태그 올리기**: `kubernetes-infra` 의
`clusters/10.0.50.0/k3s-prod/apps/<앱>/values.yaml` 에서 `image.tag` 를 바꾸고
MR → ArgoCD 가 굴린다.

**도메인 추가**: kubernetes-infra 의 `domain-app-add` 잡이 **실패하며 넣을
내용을 그대로 출력한다**(host-infra `dns/zones/<존>/<서비스>/service.toml`).
그다음 `domain-derive-gate` 가 파생 JSON 3개를 다시 만들라고 시킨다.

**공개 반영은 `cf-apply`(manual)이다.** 그 앞의 `cf-delegation-check` 가
`wadecho.com` 때문에 **항상 실패**하므로(5장), 설계된 우회로를 쓴다:

```bash
# API 로 띄우면 검사 잡이 아예 안 붙는다
glab api --method POST projects/261/pipeline -H 'Content-Type: application/json' \
  --input <(echo '{"ref":"main","variables":[{"key":"TOFU_TARGET","value":"cf"}]}')
# cf-plan 확인 후 cf-apply 를 play
```

### 운영에서 알아야 할 것

- **replicas 를 1 에서 올리지 말 것.** 릴레이는 "방 코드 → 호스트 소켓" 을,
  방 서버는 방·참가자·판을 **메모리에** 든다. 파드가 둘이면 "어떤 사람은 되고
  어떤 사람은 안 된다" 가 되고 원인 찾기가 아주 나쁘다. `strategy: Recreate` 도 같은 이유
- **재시작은 견딘다** — 파드를 갈아 끼워도 방 코드가 유지되고 호스트가 스스로
  돌아온다(`live_relay_restart_test` 가 실물로 확인한다). 업그레이드가 곧 파드
  재시작이라 이게 안 되면 파티 중엔 손도 못 댄다
- **방 서버는 상태 볼륨(5Gi)이 필수**다. 없으면 파드가 갈릴 때마다 지난 파티가
  통째로 사라진다
- `curl -s https://relay.ranode.net/healthz` 로 버전·화면 지문·붙은 호스트 수를 본다

### 헤드리스 제어

```bash
# 서버가 기동 로그에 토큰을 한 번 찍는다 (--control-token / PARTY_CONTROL_TOKEN)
curl -s -X POST https://party.ranode.net/api/control \
  -H "x-party-control: <토큰>" -H 'content-type: application/json' \
  -d '{"command":"status"}'
```

앱과 **같은 계약**이다(`{ok,result}` 봉투, 사용법 400 · 못 함 409).
`mafia night|day|vote|close`, `liar vote|close`, `marble launch|skip`,
`ladder next|all`, `restart` 도 모두 같은 `GameControlCommands` 를 지난다.

**토큰이 없으면 문을 아예 안 연다(503).** 토큰 없는 제어 API 를 인터넷에
붙이는 것이 제일 나쁘다.

---

## 10. 다음 사람이 이어받을 것

**현재 기준**
- 헤드리스 제어와 세부 게임 진행은 MR !54 로 `main` 에 머지됐다
- `party-room-server:0.1.0-67882eb1` 이 배포됐고 공개 주소에서 동작을 확인했다
- 저장소의 format·analyze·test 는 모든 Dart·Flutter 프로젝트를 검사하며,
  실패를 허용하지 않는다

**값어치 순으로**
1. **화면 지문 자동 비교** — 값은 양쪽에서 보이지만 "다르면 경고" 는 아직 없다.
   앱이 자기 번들 화면의 지문을 알아야 한다
2. **실기기 아이폰** — 백그라운드 소켓, HEIC 업로드
3. 릴레이 `/metrics` — 지금은 `/healthz` 뿐이라 시계열이 없다
