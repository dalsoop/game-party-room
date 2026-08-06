#!/usr/bin/env bash
# 파티룸 배포판 만들기 — 서명·공증·DMG.
#
# 개발 중에는 adhoc 서명(`codesign --sign -`)으로 충분하다. 내 맥에서만
# 도니까. 하지만 **남에게 주는 순간 그건 안 통한다** — Gatekeeper 가
# "확인되지 않은 개발자" 로 막고, 산 사람은 앱이 고장 난 줄 안다.
#
# 그래서 배포판은 셋을 갖춰야 한다:
#   1) Developer ID 로 서명 (누가 만들었는지)
#   2) Hardened Runtime (공증의 전제 조건)
#   3) 애플 공증 + 스테이플 (인터넷 없이도 검증되게)
#
# 쓰기:
#   tools/release.sh              # 빌드 → 서명 → 공증 → DMG
#   tools/release.sh --skip-build # 이미 빌드된 것을 쓴다
set -euo pipefail

APP_NAME="PartyRoom"
DEV_ID="Developer ID Application: Jeonghan Yun (V2Z46YY386)"
KEY_ID="4LFD993V8Q"
ISSUER="4bf22fb0-bc95-4e2d-8fed-68e3cdb103fe"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILT="$ROOT/build/macos/Build/Products/Release/$APP_NAME.app"
OUT="$ROOT/build/release"
ENTITLEMENTS="$ROOT/macos/Runner/Release.entitlements"

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# ---- 준비물 확인 — 없으면 여기서 끝내는 편이 낫다 --------------------------
security find-identity -v -p codesigning | grep -q "$DEV_ID" \
  || die "Developer ID 인증서가 없습니다: $DEV_ID"
[ -f "$KEY_PATH" ] || die "공증 키가 없습니다: $KEY_PATH"
[ -f "$ENTITLEMENTS" ] || die "entitlements 가 없습니다: $ENTITLEMENTS"

# ---- 1. 빌드 ---------------------------------------------------------------
if [ "${1:-}" != "--skip-build" ]; then
  step "빌드"
  flutter build macos --release
fi
[ -d "$BUILT" ] || die "빌드 산출물이 없습니다: $BUILT"

mkdir -p "$OUT"
STAGE="$OUT/$APP_NAME.app"
rm -rf "$STAGE"
cp -R "$BUILT" "$STAGE"

# ---- 2. 서명 ---------------------------------------------------------------
# `--deep` 은 쓰지 않는다. 애플이 권하지 않을뿐더러, 중첩 코드에 잘못된
# entitlements 를 덧씌워 공증이 거절되는 원인이 된다. 안쪽부터 하나씩 한다.
step "서명 (Hardened Runtime)"
while IFS= read -r -d '' item; do
  codesign --force --timestamp --options runtime --sign "$DEV_ID" "$item"
done < <(find "$STAGE/Contents/Frameworks" -maxdepth 1 \
           \( -name "*.framework" -o -name "*.dylib" \) -print0 2>/dev/null)

codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" --sign "$DEV_ID" "$STAGE"

codesign --verify --deep --strict --verbose=2 "$STAGE" 2>&1 | tail -2

# ---- 3. DMG ----------------------------------------------------------------
# 공증은 앱 하나로도 되지만, 파는 것은 DMG 다. DMG 를 공증하고 스테이플하면
# 받는 사람이 마운트하는 순간 검증이 끝난다.
step "DMG 만들기"
DMG="$OUT/$APP_NAME.dmg"
rm -f "$DMG"
STAGING="$OUT/dmg"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$STAGE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # 끌어다 놓는 자리
# 출력을 삼키지 않는다 — 한 번 삼켰다가 "왜 DMG 가 없지" 로 헤맸다.
# 같은 이름의 볼륨이 남아 있으면 여기서 걸린다.
hdiutil detach "/Volumes/$APP_NAME" -quiet 2>/dev/null || true
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
codesign --force --timestamp --sign "$DEV_ID" "$DMG"

# ---- 4. 공증 ---------------------------------------------------------------
step "공증 (몇 분 걸린다)"
xcrun notarytool submit "$DMG" \
  --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER" \
  --wait --timeout 30m

step "스테이플"
# 스테이플이 있어야 **인터넷 없이도** 검증된다. 파티 현장에서 Wi-Fi 만
# 있고 인터넷이 없는 것이 이 앱의 기본 상황이라 특히 중요하다.
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# ---- 5. 받는 사람 입장에서 확인 --------------------------------------------
step "Gatekeeper 판정"
spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | tail -3

printf '\n\033[32m✓ 배포판: %s\033[0m\n' "$DMG"
printf '  받는 사람은 마운트 → 앱을 Applications 로 끌어다 놓으면 끝입니다.\n'
