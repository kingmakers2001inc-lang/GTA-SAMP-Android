# Hosting the Grand RP server

You need an **x86_64** Linux machine that stays online, running Ubuntu 22.04/24.04 or Debian 12.
Phones and ARM servers (including Oracle's free ARM instances) can't run open.mp.

| Option | Cost | Notes |
| --- | --- | --- |
| Small VPS (Hetzner, Contabo, DigitalOcean, Vultr…) | ~$4–6/month | Recommended. 1 vCPU / 1–2 GB RAM is plenty to start |
| Google Cloud free tier (e2-micro, US regions) | free | Fine for testing and a few players |
| Your own Linux PC | free | Only online while it's on; forward UDP 7777 on your router |

## Free testing: GitHub Codespaces + playit.gg (no card, works from a phone)

1. Open the repository on GitHub in your browser, switch to this branch, then
   **Code → Codespaces → Create codespace**. Wait for the terminal to appear.
2. In the codespace terminal: `./server/deploy/codespace.sh`. It installs and starts the
   server and prints the RCON password.
3. On https://playit.gg sign up (free, no card), add an agent with the **Docker / secret key**
   setup and copy the secret key. Then in the terminal:
   `PLAYIT_SECRET=<key> ./server/deploy/codespace.sh`
4. On playit.gg: **Tunnels → Create tunnel**, type **UDP** (or the SA-MP preset), local
   address `127.0.0.1`, port `7777`. Put the public address it shows into the launcher.

Codespaces stop after about 30 minutes without activity (raise it to 4 hours in GitHub
Settings → Codespaces) and give around 60 free hours a month. They're meant for development
and testing, so use this to play with friends, not as 24/7 public hosting. When the codespace
restarts, run `./server/deploy/codespace.sh` again (the secret is remembered).

## Install

On the server, as root:

```
apt-get install -y git
git clone -b claude/mobile-gta-rp-game-czwssh https://github.com/kingmakers2001inc-lang/GTA-SAMP-Android
cd GTA-SAMP-Android
SERVER_NAME="Kingmakers RP | Mobile Roleplay" ./server/deploy/install.sh
```

The script installs the 32-bit runtime open.mp needs, downloads open.mp, compiles
`grand_rp.pwn`, writes `config.json` with a random RCON password, and runs the server as the
`grand-rp` service (starts on boot, restarts if it crashes). At the end it prints the address
players use and the RCON password.

Then open **UDP port 7777** in your provider's firewall:

- **Google Cloud:** VPC network → Firewall → Create rule: ingress, targets all instances,
  source `0.0.0.0/0`, protocols `udp:7777`.
- **Hetzner / DigitalOcean / Vultr:** only if you added a cloud firewall; allow inbound UDP 7777.
- **ufw** on the machine itself is handled by the script.

Check it: the server shows a green dot in the launcher (`+ Add server`, `IP:7777`).

## First admin

Join the server, then in chat:

```
/rcon login <RCON password>
/makeadmin <your player id> 5
```

## Day to day

| Task | Command |
| --- | --- |
| Live log | `journalctl -u grand-rp -f` |
| Restart | `systemctl restart grand-rp` |
| Stop / start | `systemctl stop grand-rp` / `systemctl start grand-rp` |
| Update gamemode or open.mp | `git pull && ./server/deploy/install.sh` |
| Back up player data | copy `/opt/grand-rp/scriptfiles/grand_rp.db` |

Updates keep the player database, `config.json`, bans and the RCON password. Edit
`/opt/grand-rp/config.json` (server name, max players, password, Discord link) and restart to
apply.

Options for the script: `SERVER_NAME`, `PORT` (7777), `MAX_PLAYERS` (100), `OMP_VERSION`,
`INSTALL_DIR` (`/opt/grand-rp`), `NO_SERVICE=1` (install without the systemd service).
