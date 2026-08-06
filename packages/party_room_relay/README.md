# party_room_relay — 랑데부 서버

밖에 있는 사람을 파티룸에 들여보내는 길. **로컬이 먼저다** — 같은 Wi-Fi 면
참가자는 호스트에게 곧장 붙고 이 서버는 등장하지 않는다. 여기는 망이 다르거나,
카페 Wi-Fi 가 기기끼리 못 보게 막아 뒀거나(AP 격리), 방화벽이 막았을 때의 길이다.

닌텐도 Pia 의 세 갈래(LDN·LAN·NEX) 중 **NEX** 자리다: 짝을 지어 주고 빠진다.
다른 점은 우리 한쪽이 브라우저라 UDP 로 구멍을 뚫을 수 없다는 것뿐이라, 빠지는
대신 프레임을 날라 준다.

## 왜 서버가 필요한가

브라우저에는 두 겹의 벽이 있다.

1. `RTCPeerConnection` 은 **secure context 전용**이다. `http://192.168.0.183:8765`
   로 뿌린 화면에서는 WebRTC 자체가 막힌다.
2. 반대로 페이지를 `https` 로 주면 그 페이지에서 `ws://192.168.x.x` 로 못 붙는다
   (mixed content).

그래서 "다른 망에 있는 폰"에게는 페이지를 줄 방법 자체가 없다. 이 서버의 존재
이유 절반이 **참가자 화면을 https 로 주는 것**이고, 나머지 절반이 프레임 중계다.

## 가벼운 이유

실측치다.

| | 크기 |
|---|---|
| 실시간 프레임 (5인 한 판 전체) | **9.7KB** (참가자당 약 2KB) |
| 참가자 화면 자산 | 6.3MB (폰트 하나가 2.45MB) |
| 자산 gzip 후 | 약 0.78MB |
| 자료 업로드 | 1인 30MB · 방 1GB |

실시간 프레임은 껌값이라 전부 중계해도 된다. 비용은 **자산**에 있고 그건 gzip +
캐시로 잡는다. 자료 업로드는 네 자릿수가 달라서 **아예 안 나른다**(`isRelayRefused`).
릴레이로 들어온 참가자에게는 화면에서 그 기능을 감춘다 — 눌러 봐야 413 이 오는
버튼을 남겨 두는 것이 제일 나쁘다.

## 지금 떠 있는 곳

**https://relay.ranode.net** (50서버 k3s-prod, ArgoCD 관리)

- 차트: `kubernetes-infra` 의 `charts/party-room-relay`
- 이미지: `harbor.50.internal.kr/library/party-room-relay`
- 도메인 정본: `host-infra` 의 `dns/zones/ranode.net/party-room-relay/service.toml`

호스트 앱에서 [주소 → 밖에 있는 사람 들이기] 에 이 주소를 적고 켜면 된다.

### 지금 뭐가 돌고 있나

```bash
curl -s https://relay.ranode.net/healthz
# {"ok":true,"version":"0.1.0-702cd60","assets":"7c4ef25dda183e7f","hosts":0,"uptimeSeconds":27}
```

`assets` 는 **참가자 화면의 지문**이다. 화면은 이미지에 구워져 있어서, 앱의
`assets/web` 을 고치고 이미지를 다시 굽지 않으면 **밖에서 온 사람만** 조용히
옛 화면을 받는다 — 증상이 "들어와지는데 뭔가 이상하다" 라 원인 찾기가 아주
나쁘다. 호스트 앱도 붙을 때 이 값을 읽어 `partyroom relay` 에 싣는다.

### 화면을 고쳤을 때 (재빌드)

**정본은 CI 다.** `packages/party_room_relay/**` 나
`apps/game-party-room-app/assets/web/**` 이 main 에 들어가면
`build-party-room-relay` 잡이 자동으로 굽고 `0.1.0-<커밋sha>` 로 민다.
따로 굽고 싶으면 파이프라인에 `BUILD_IMAGES=party-room` 을 주고 돌린다.

급할 때의 폴백(맥에서 직접):

```bash
packages/party_room_relay/tools/build-and-push.sh
```

커밋 sha 로 태그를 붙이고 harbor 에 민 뒤, 다음에 할 일을 알려준다 —
`kubernetes-infra` 의 `clusters/10.0.50.0/k3s-prod/apps/party-room-relay/values.yaml`
에서 `image.tag` 를 바꾸고 MR. ArgoCD 가 굴린다.

### 실물 확인

```bash
# party_room_server 에서
dart test test/live_relay_manual_test.dart -t live --run-skipped
dart test test/live_relay_restart_test.dart -t live-disruptive --run-skipped  # 혼자 돌릴 것
```

재시작 견딤은 확인돼 있다 — 파드를 갈아 끼워도 방 코드가 유지되고 호스트가
스스로 돌아온다. 업그레이드가 곧 파드 재시작이라, 이게 안 되면 파티 중에는
손도 못 댄다는 뜻이다.

> **replicas 를 1 에서 올리지 말 것.** 방 코드→호스트 소켓 매핑이 메모리에
> 있어서, 파드가 둘이면 참가자가 그 코드를 모르는 파드로 갈 수 있다.

## 직접 띄우기

```bash
# 참가자 화면을 함께 준다 (앱의 assets/web 을 그대로 복사)
cp -R ../../apps/game-party-room-app/assets/web ./web

dart run bin/relay.dart --port 8080 --web ./web --base https://party.example.com

# 배포는 바이너리 하나
dart compile exe bin/relay.dart -o relay
./relay --port 8080 --web ./web --base https://party.example.com
```

`--base` 는 참가자에게 알려 줄 바깥 주소다. TLS 는 앞단(Caddy·nginx·Cloudflare)이
맡는다 — **https 라야** 브라우저가 secure context 를 열어 준다.

```
party.example.com {
  reverse_proxy 127.0.0.1:8080
}
```

## 호스트 쪽

앱에서 [주소 → 밖에 있는 사람 들이기] 에 이 서버 주소를 적고 켜면, 호스트가
**바깥으로 나가서** 붙는다. 인바운드 포트도 포트 포워딩도 방화벽 예외도 필요 없다.
받은 네 글자 방 코드로 참가자용 QR 이 만들어진다.

코드 글자는 `0/O`·`1/I/l`·`2/Z`·`5/S`·`8/B` 를 뺀 25자다 — 이 코드는 사람이
불러 주고 받아 적는다.

## 이 서버가 모르는 것

게임 규칙, 방 구조, 참가자가 누구인지. 프레임은 통째로 지나간다. 그래서 파티룸이
바뀌어도 릴레이는 그대로 돌고, 프로토콜 판(`relayProtocolVersion`)이 어긋날 때만
붙자마자 거절한다.

방 코드를 되찾는 열쇠(`secret`)는 호스트가 갖고 있다. 남의 비밀로는 남의 코드를
못 가져간다 — 안 그러면 아무나 남의 파티를 가로챌 수 있다.
