#!/bin/sh
# 파티룸 CLI 설치.
#
# `dart compile exe` 는 Flutter 번들 SDK 에 gen_snapshot 이 없어 못 쓴다.
# 커널 스냅샷(~150ms 기동)을 앱 지원 폴더에 두고 얇은 래퍼를 PATH 에 건다 —
# 저장소를 옮겨도 CLI 는 계속 돈다.
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
LIB="$HOME/Library/Application Support/PartyRoom"
BIN="${1:-/opt/homebrew/bin}"

command -v dart >/dev/null 2>&1 || { echo "dart 가 없습니다"; exit 1; }
mkdir -p "$LIB" "$BIN"

dart compile kernel "$SRC/bin/partyroom.dart" -o "$LIB/partyroom.dill" >/dev/null
DART="$(command -v dart)"

cat > "$BIN/partyroom" <<WRAP
#!/bin/sh
exec "$DART" "$LIB/partyroom.dill" "\$@"
WRAP
chmod +x "$BIN/partyroom"

echo "설치됨: $BIN/partyroom"
"$BIN/partyroom" version
