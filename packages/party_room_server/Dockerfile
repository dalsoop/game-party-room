# 헤드리스 파티룸 서버 이미지.
#
# **맥 앱과 완전히 같은 서버 코드**다 — `AssetSource`·`StateStore` 만
# 파일시스템 판으로 갈아 끼운다. 그래서 여기서 도는 방과 앱이 여는 방은
# 규칙이 갈리지 않는다.
#
# 빌드 컨텍스트는 저장소 루트다: 서버 코드(`packages/party_room_server`),
# 그 경로 의존(`packages/party_room_relay`), 참가자 화면
# (`apps/game-party-room-app/assets/web`) 셋이 서로 다른 자리에 있다.
#
#   docker build -f packages/party_room_server/Dockerfile -t <이미지> .

FROM dart:stable AS build

WORKDIR /src

# 경로 의존이 있어 pubspec 을 함께 넣어야 resolve 가 된다.
COPY packages/party_room_relay/pubspec.yaml ./packages/party_room_relay/
COPY packages/party_room_server/pubspec.yaml ./packages/party_room_server/
WORKDIR /src/packages/party_room_server
RUN dart pub get

COPY packages/party_room_relay/ /src/packages/party_room_relay/
COPY packages/party_room_server/ /src/packages/party_room_server/
RUN dart pub get --offline
RUN dart analyze
RUN dart compile exe bin/serve.dart -o /serve

FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --system --uid 10001 --create-home party

COPY --from=build /serve /usr/local/bin/serve
# 참가자 화면. `--assets` 가 가리키는 것은 **앱 디렉터리**이고 그 아래
# `assets/web/` 을 찾는다 — 그 구조를 그대로 옮긴다.
COPY apps/game-party-room-app/assets/web /app/assets/web

# 방·참가자·대화가 여기 남는다. 볼륨을 안 물리면 파드가 갈릴 때마다
# **지난 파티가 통째로 사라진다.**
RUN mkdir -p /state && chown 10001:10001 /state
VOLUME ["/state"]

USER 10001

ENV PORT=8765 \
    PARTY_ASSETS=/app \
    PARTY_STATE=/state/rooms.json

EXPOSE 8765

ENTRYPOINT ["/usr/local/bin/serve"]
