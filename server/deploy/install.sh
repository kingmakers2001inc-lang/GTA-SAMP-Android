#!/usr/bin/env bash
# Installs or updates the Grand RP server (open.mp) on Ubuntu/Debian x86_64.
#
#   sudo ./server/deploy/install.sh                # install or update, run as a service
#   sudo SERVER_NAME="My RP" ./server/deploy/install.sh
#
# Re-running updates the gamemode and open.mp but keeps the database and config.
# Options (environment): SERVER_NAME, PORT (7777), MAX_PLAYERS (100), OMP_VERSION,
# INSTALL_DIR (/opt/grand-rp), NO_SERVICE=1 to skip systemd (just install).
set -euo pipefail

SERVER_NAME="${SERVER_NAME:-Grand RP | Mobile Roleplay}"
PORT="${PORT:-7777}"
MAX_PLAYERS="${MAX_PLAYERS:-100}"
OMP_VERSION="${OMP_VERSION:-v1.6.7.3218}"
INSTALL_DIR="${INSTALL_DIR:-/opt/grand-rp}"
SERVICE_USER="${SERVICE_USER:-grandrp}"
REPO_SERVER="$(cd "$(dirname "$0")/.." && pwd)"

[ "$(id -u)" = 0 ] || { echo "Run as root (sudo)." >&2; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo "open.mp needs an x86_64 machine (this is $(uname -m))." >&2; exit 1; }

echo "==> Installing system packages"
# open.mp is a 32-bit program, so it needs the i386 runtime libraries
dpkg --add-architecture i386
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates python3 \
	libc6:i386 libstdc++6:i386 libatomic1:i386 > /dev/null

if [ -z "${NO_SERVICE:-}" ] && ! id "$SERVICE_USER" > /dev/null 2>&1; then
	useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
fi

echo "==> Downloading open.mp $OMP_VERSION"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/omp.tar.gz" "https://github.com/openmultiplayer/open.mp/releases/download/$OMP_VERSION/open.mp-linux-x86.tar.gz"
tar xzf "$TMP/omp.tar.gz" -C "$TMP"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/.new"
# Program files are replaced; the database (scriptfiles), config, bans and RCON password are kept
cp -r "$TMP/Server/." "$INSTALL_DIR/.new"
for keep in scriptfiles config.json bans.json rcon-password.txt .configured; do
	if [ -e "$INSTALL_DIR/$keep" ]; then
		rm -rf "$INSTALL_DIR/.new/$keep"
		mv "$INSTALL_DIR/$keep" "$INSTALL_DIR/.new/$keep"
	fi
done
find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name .new -exec rm -rf {} +
find "$INSTALL_DIR/.new" -mindepth 1 -maxdepth 1 -exec mv -t "$INSTALL_DIR" {} +
rmdir "$INSTALL_DIR/.new"

echo "==> Compiling the gamemode"
cp "$REPO_SERVER/gamemodes/grand_rp.pwn" "$INSTALL_DIR/gamemodes/"
(cd "$INSTALL_DIR" && LD_LIBRARY_PATH=qawno ./qawno/pawncc gamemodes/grand_rp.pwn -iqawno/include \
	-ogamemodes/grand_rp.amx -d1 -O1 '-;+' '-(+') | grep -vE "^Pawn compiler|^$" || true
[ -s "$INSTALL_DIR/gamemodes/grand_rp.amx" ] || { echo "Gamemode failed to compile." >&2; exit 1; }

RCON_NOTE=""
if [ ! -e "$INSTALL_DIR/.configured" ]; then
	echo "==> Writing config.json"
	RCON_PASSWORD=$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)
	python3 - "$REPO_SERVER/config.json" "$INSTALL_DIR/config.json" "$SERVER_NAME" "$PORT" "$MAX_PLAYERS" "$RCON_PASSWORD" <<'PY'
import json, sys
src, dst, name, port, max_players, rcon = sys.argv[1:]
config = json.load(open(src))
config["name"] = name
config["max_players"] = int(max_players)
config.setdefault("network", {})["port"] = int(port)
config["rcon"] = {"enable": True, "password": rcon}
json.dump(config, open(dst, "w"), indent=4)
PY
	echo "$RCON_PASSWORD" > "$INSTALL_DIR/rcon-password.txt"
	chmod 600 "$INSTALL_DIR/rcon-password.txt"
	touch "$INSTALL_DIR/.configured"
	RCON_NOTE="RCON password: $RCON_PASSWORD (saved in $INSTALL_DIR/rcon-password.txt)"
fi

if [ -n "${NO_SERVICE:-}" ]; then
	echo "==> Installed in $INSTALL_DIR (no service). Start it with: cd $INSTALL_DIR && ./omp-server"
	[ -n "$RCON_NOTE" ] && echo "$RCON_NOTE"
	exit 0
fi

chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

echo "==> Setting up the grand-rp service"
cat > /etc/systemd/system/grand-rp.service <<UNIT
[Unit]
Description=Grand RP server (open.mp)
After=network-online.target
Wants=network-online.target

[Service]
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/omp-server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable grand-rp > /dev/null 2>&1
systemctl restart grand-rp

if command -v ufw > /dev/null && ufw status | grep -q "Status: active"; then
	ufw allow "$PORT/udp" > /dev/null
	echo "==> Opened $PORT/udp in ufw"
fi

sleep 3
if systemctl is-active --quiet grand-rp; then
	IP=$(curl -fsS --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')
	echo
	echo "Grand RP is running."
	echo "  Players connect to: $IP:$PORT  (add it in the launcher with + Add server)"
	[ -n "$RCON_NOTE" ] && echo "  $RCON_NOTE"
	echo "  Logs:    journalctl -u grand-rp -f"
	echo "  Restart: systemctl restart grand-rp"
	echo "If players can't connect, open UDP port $PORT in your provider's firewall too."
else
	echo "The service didn't start; check: journalctl -u grand-rp -n 50" >&2
	exit 1
fi
