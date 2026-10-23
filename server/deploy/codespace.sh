#!/usr/bin/env bash
# Runs Grand RP in a GitHub Codespace (or any x86_64 Linux box without systemd) and,
# with a playit.gg secret, makes it reachable from the internet through a free UDP tunnel.
#
#   ./server/deploy/codespace.sh                          # install + start the server
#   PLAYIT_SECRET=xxxxx ./server/deploy/codespace.sh      # ...and start the playit.gg tunnel
#   UPDATE=1 ./server/deploy/codespace.sh                 # reinstall after a git pull
#   DISCORD=discord.gg/xxxx ./server/deploy/codespace.sh  # show a Discord button in the launcher
#
# Codespaces are for development and testing: they stop when idle, so this isn't 24/7 hosting.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="${INSTALL_DIR:-$HOME/grand-rp}"
SUDO=""
[ "$(id -u)" = 0 ] || SUDO="sudo"

if [ ! -x "$DIR/omp-server" ] || [ -n "${UPDATE:-}" ]; then
	echo "==> Installing the server in $DIR"
	$SUDO env NO_SERVICE=1 INSTALL_DIR="$DIR" SERVER_NAME="${SERVER_NAME:-Kingmakers RP | Test}" \
		bash "$REPO/server/deploy/install.sh" | grep -v "Start it with" || true
	$SUDO chown -R "$(id -u):$(id -g)" "$DIR"
	# The server list would get the codespace's address, which players can't use
	python3 - "$DIR/config.json" <<'PY'
import json, sys
path = sys.argv[1]
config = json.load(open(path))
config["announce"] = False
json.dump(config, open(path, "w"), indent=4)
PY
fi
[ -x "$DIR/omp-server" ] || { echo "Install failed." >&2; exit 1; }

# Discord invite and website are sent to the launcher with the server info
if [ -n "${DISCORD:-}" ] || [ -n "${WEBSITE:-}" ]; then
	python3 - "$DIR/config.json" <<'PY'
import json, os, sys
path = sys.argv[1]
config = json.load(open(path))
if os.environ.get("DISCORD"):
    config.setdefault("discord", {})["invite"] = os.environ["DISCORD"]
if os.environ.get("WEBSITE"):
    config["website"] = os.environ["WEBSITE"]
json.dump(config, open(path, "w"), indent=4)
PY
fi

echo "==> Starting the server"
# By process name: it was started as ./omp-server, so a full-path pattern never matches
pkill -x omp-server 2> /dev/null || true
while pgrep -x omp-server > /dev/null; do sleep 1; done
cd "$DIR"
nohup ./omp-server < /dev/null > server.log 2>&1 &
disown
cd - > /dev/null
for _ in $(seq 1 30); do
	grep -q "Legacy Network started" "$DIR/server.log" 2> /dev/null && break
	sleep 1
done
if ! grep -q "Legacy Network started" "$DIR/server.log"; then
	echo "The server didn't start; see $DIR/server.log" >&2
	tail -20 "$DIR/server.log" >&2
	exit 1
fi
echo "    Server running on UDP port 7777 (log: $DIR/server.log)"
echo "    RCON password: $(cat "$DIR/rcon-password.txt")"

if [ -n "${PLAYIT_SECRET:-}" ]; then
	umask 077
	printf '%s\n' "$PLAYIT_SECRET" > "$DIR/playit-secret"
fi
if [ ! -s "$DIR/playit-secret" ]; then
	cat <<MSG

The server only runs inside this codespace for now. To let players join:
  1. On your phone, open https://playit.gg, sign up (free, no card) and add an agent.
     Pick the Docker / secret key setup and copy the secret key it shows.
  2. Run:  PLAYIT_SECRET=<that key> ./server/deploy/codespace.sh
MSG
	exit 0
fi

if [ ! -x "$DIR/playit" ]; then
	echo "==> Downloading the playit.gg agent"
	curl -fsSL -o "$DIR/playit" https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64
	chmod +x "$DIR/playit"
fi

echo "==> Starting the playit.gg tunnel"
pkill -f "$DIR/playit " 2> /dev/null || true
nohup "$DIR/playit" --secret "$(cat "$DIR/playit-secret")" --socket-path "$DIR/playitd.sock" -l "$DIR/playit.log" < /dev/null > "$DIR/playit.out" 2>&1 &
disown
sleep 8
if ! pgrep -f "$DIR/playit " > /dev/null; then
	echo "The playit.gg agent stopped:" >&2
	tail -3 "$DIR/playit.out" >&2
	echo "Fix the key with: PLAYIT_SECRET=<key> ./server/deploy/codespace.sh" >&2
	exit 1
fi
cat <<MSG
    Agent running (log: $DIR/playit.log)

Last step, on https://playit.gg:
  Tunnels -> Create tunnel -> type "UDP" (or the SA-MP preset), local address 127.0.0.1, port 7777.
  playit.gg then shows a public address such as something.ply.gg:12345.
  Put that in the Kingmakers RP launcher with "+ Add server".

Keep this codespace open in your browser; it stops after a while without activity.
MSG
