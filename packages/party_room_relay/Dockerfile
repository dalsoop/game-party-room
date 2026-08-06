# 파티룸 랑데부 서버 이미지.
#
# 빌드 컨텍스트는 **저장소 루트**다 — 서버 코드(`packages/party_room_relay`)와
# 참가자 화면(`apps/game-party-room-app/assets/web`)이 서로 다른 자리에 있고,
# 둘이 함께 있어야 이 서버가 제 일을 한다. 릴레이가 화면을 못 주면 다른 망의
# 폰은 열 페이지 자체가 없다.
#
#   docker build -f packages/party_room_relay/Dockerfile -t <이미지> .

FROM dart:stable AS build

WORKDIR /src

# 의존성 먼저 — 코드만 바뀌면 이 층이 캐시된다.
COPY packages/party_room_relay/pubspec.yaml ./
RUN dart pub get

COPY packages/party_room_relay/ ./
RUN dart pub get --offline
RUN dart analyze
RUN dart compile exe bin/relay.dart -o /relay

# 참가자 화면. 이미지에 굽는 이유: 릴레이가 주는 화면과 호스트 앱이 말하는
# 프로토콜이 **같은 판이어야** 한다. 따로 두면 어느 순간 어긋나고, 그때
# 증상은 "들어와지는데 화면이 안 바뀐다" 라 원인을 찾기 어렵다.
# 그래서 앱을 고치면 이 이미지도 다시 만든다.
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# 루트로 돌 이유가 없다.
RUN useradd --system --uid 10001 --create-home relay
USER 10001

COPY --from=build /relay /usr/local/bin/relay
COPY --chown=10001:10001 apps/game-party-room-app/assets/web /web

# 이 이미지가 어느 소스에서 나왔는가. `/healthz` 로 나온다 —
# "지금 뭐가 돌고 있지" 는 뭔가 이상할 때 나오는 질문이고, 그때 답을 못
# 하면 되돌릴 지점도 못 찾는다.
ARG RELAY_VERSION=dev
ENV RELAY_VERSION=$RELAY_VERSION

EXPOSE 8080
ENV PORT=8080

# `--base` 는 배포 때 주입한다 — 참가자에게 알려 줄 바깥 주소는 이 이미지가
# 알 수 없다. TLS 는 앞단(traefik·Cloudflare)이 맡는다.
ENTRYPOINT ["/usr/local/bin/relay"]
CMD ["--web", "/web"]
