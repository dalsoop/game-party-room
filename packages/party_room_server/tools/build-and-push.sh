#!/usr/bin/env bash
# 헤드리스 방 서버 이미지를 다시 굽고 레지스트리에 올린다.
#
# **정본은 CI 다.** main 에 들어가면 `.gitlab-ci.yml` 의 build-party-room-* 잡이
# 같은 Dockerfile 로 굽고 커밋 sha 로 태그한다 — 거기서는 커밋이 곧 출처다.
# 이 스크립트는 **급할 때의 폴백**이다(CI 를 안 기다리고 지금 굽고 싶을 때).
# 손으로 구운 이미지는 어느 소스였는지 git 에 안 남으니, 그 태그를 배포에
# 박아 두지는 말 것.
#
# 상시로 도는 방 서버(party.ranode.net)의 이미지다. 서버 코드나 참가자 화면
# (`apps/game-party-room-app/assets/web`)을 고쳤으면 이걸 다시 돌려야 한다.
#
# 경로 의존(`packages/party_room_relay`)도 함께 보낸다 — 없으면 pub 이 못 푼다.
#
# 빌드는 50서버에서 한다(맥에 docker 데몬이 없고, harbor 로그인도 거기 있다).
# 50서버에는 GitLab 자격증명이 없어서 소스는 여기서 rsync 로 보낸다.
#
#   packages/party_room_server/tools/build-and-push.sh            # 커밋 sha 로 태그
#   packages/party_room_server/tools/build-and-push.sh 0.2.0      # 태그 지정
set -euo pipefail

PVE="${PVE_HOST:-root@192.168.2.50}"
REPO="${IMAGE_REPO:-harbor.50.internal.kr/library/party-room-server}"
CTX="/opt/build/prs-ctx"

cd "$(dirname "$0")/../../.."   # 저장소 루트
ROOT="$(pwd)"
[ -d "$ROOT/packages/party_room_server" ] || { echo "저장소 루트를 못 찾았습니다"; exit 1; }

SHA="$(git rev-parse --short HEAD)"
DIRTY=""
git diff --quiet || DIRTY="-dirty"
VERSION="${1:-0.1.0}-${SHA}${DIRTY}"

if [ -n "$DIRTY" ]; then
  # 커밋 안 한 변경으로 구우면, 나중에 이 이미지가 어느 소스였는지 못 찾는다.
  echo "⚠️  커밋 안 된 변경이 있습니다 — 태그에 -dirty 가 붙습니다: $VERSION"
fi

echo "▶ 소스 보내기 → $PVE:$CTX"
ssh "$PVE" "rm -rf $CTX && mkdir -p $CTX/packages $CTX/apps/game-party-room-app/assets"
rsync -a --delete --exclude '.dart_tool' --exclude 'build' \
  "$ROOT/packages/party_room_server" "$ROOT/packages/party_room_relay" "$PVE:$CTX/packages/"
rsync -a --delete \
  "$ROOT/apps/game-party-room-app/assets/web" "$PVE:$CTX/apps/game-party-room-app/assets/"

echo "▶ 빌드 · 밀기 — $REPO:$VERSION"
ssh "$PVE" "cd $CTX && DOCKER_BUILDKIT=1 docker build \
  -f packages/party_room_server/Dockerfile \
  -t '$REPO:$VERSION' . >/dev/null && docker push -q '$REPO:$VERSION'"

echo
echo "✓ $REPO:$VERSION"
echo
echo "  다음: kubernetes-infra 의"
echo "    clusters/10.0.50.0/k3s-prod/apps/party-room-server/values.yaml"
echo "  에서 image.tag 를 '$VERSION' 으로 바꾸고 MR → ArgoCD 가 굴립니다."
echo "  확인: curl -sI https://party.ranode.net/"
