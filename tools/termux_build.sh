#!/data/data/com.termux/files/usr/bin/bash
# One command to build your multiplayer GTA SA on the phone, in Termux:
#   bash ~/GTA-SAMP-Android/tools/termux_build.sh
# It updates this repo, installs the tools it needs, finds your own GTA SA 2.11 backup
# (MT Manager: MT2/apks/GTA_ SA_2.11.*.apks), adds the prebuilt client and writes
# Download/GTA-SAMP.apks for SAI. Set HOST/PORT to bake in another server.
set -eo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DL="$HOME/storage/downloads"
HOST="${HOST:-traded-client.tun.ply.gg}"
PORT="${PORT:-51531}"

# Update first, then run the updated copy of this script
if [ -z "${SAMP_UPDATED:-}" ]; then
	echo "==> Updating $REPO"
	git -C "$REPO" pull --ff-only -q || echo "    (couldn't update, using the copy you have)"
	SAMP_UPDATED=1 exec bash "$REPO/tools/termux_build.sh" "$@"
fi

[ -d "$HOME/storage/shared" ] || termux-setup-storage
missing=""
for tool in java apksigner zipalign python; do
	command -v "$tool" > /dev/null || missing=1
done
if [ -n "$missing" ]; then
	echo "==> Installing build tools"
	pkg install -y aapt openjdk-17 apksigner python
fi
if [ ! -s "$HOME/apktool.jar" ]; then
	echo "==> Downloading apktool"
	curl -fsSL -o "$HOME/apktool.jar" https://github.com/iBotPeaches/Apktool/releases/download/v2.9.3/apktool_2.9.3.jar
fi

GAME="${1:-$(ls -t "$HOME"/storage/shared/MT2/apks/*[Gg][Tt][Aa]*2.11*.apks 2>/dev/null | head -n1 || true)}"
if [ -z "$GAME" ] || [ ! -f "$GAME" ]; then
	echo "No GTA SA 2.11 backup found. In MT Manager: menu > Installed apps > GTA: SA > Extract," >&2
	echo "or pass the path: bash $0 /path/to/GTA.apks" >&2
	exit 1
fi
echo "==> Game: $GAME"

OUT="$DL/GTA-SAMP.apks"
OLD="$DL/GTA-SAMP-old.apks"
reuse=()
if [ -f "$OUT" ]; then
	mv -f "$OUT" "$OLD"
	reuse=(--reuse "$OLD")
fi

echo "==> Building (a minute with a previous build to reuse, several minutes the first time)"
if ! python "$REPO/tools/make_apk.py" --apk "$GAME" --lib "$REPO/prebuilt/arm64-v8a/libSAMP.so" \
	--apktool-jar "$HOME/apktool.jar" --host "$HOST" --port "$PORT" "${reuse[@]}" --out "$OUT" \
	> "$DL/samp_build_log.txt" 2>&1; then
	grep -E "error|warning" "$DL/samp_build_log.txt" >&2 || tail -n 20 "$DL/samp_build_log.txt" >&2
	[ -f "$OLD" ] && mv -f "$OLD" "$OUT"
	echo "Build failed; the full log is Download/samp_build_log.txt" >&2
	exit 1
fi
grep -E "patched|reusing|Done" "$DL/samp_build_log.txt"
rm -f "$OLD"

cat <<MSG

Ready: Download/GTA-SAMP.apks (server $HOST:$PORT)
  1. SAI > Installation > Select file(s) > GTA-SAMP.apks
  2. Start your server, open GTA: SA, Skip Sign in, start a game
  3. Then send the client log:  cat ~/storage/downloads/samp_log.txt
MSG
