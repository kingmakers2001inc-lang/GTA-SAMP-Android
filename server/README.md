# Grand RP server

Roleplay gamemode for [open.mp](https://open.mp), the server the Android client in this repo connects to.

## What's in the gamemode

| System | Details |
| --- | --- |
| Accounts | `Firstname_Lastname` names, register/login dialogs, salted SHA-256 passwords, SQLite (`scriptfiles/grand_rp.db`), autosave every 5 minutes |
| Progression | Levels and experience, hourly PayDay (salary + bank interest) |
| Roleplay chat | Proximity chat, `/me`, `/do`, `/b`, `/s`, `/w`, chat bubbles |
| Economy | Server-side money, bank (`/deposit`, `/withdraw`, `/transfer`), `/pay`, hospital bills |
| Jobs | Trucker (`/deliver`, 5 routes across San Andreas), Taxi driver (`/fare`) |
| Factions | LSPD and Medics with 6 ranks, `/duty`, `/f` radio, `/invite`, `/uninvite`, `/setrank`, `/cuff`, `/heal` |
| Vehicles | Dealership (`/buycar`), up to 3 saved cars per player, `/lock`, `/park`, `/engine`, job and faction vehicle restrictions |
| Admin | Levels 1-5, `/a`, `/goto`, `/gethere`, `/kick`, `/ban`, `/unban`, `/makeadmin`, `/makeleader`, `/setmoney`, `/veh` |

## Running it

1. Download the open.mp server for your OS from https://github.com/openmultiplayer/open.mp/releases.
2. Copy `gamemodes/grand_rp.pwn` and `config.json` into the server folder.
3. Compile with the bundled Pawn compiler (`qawno/pawncc`):
   ```
   pawncc gamemodes/grand_rp.pwn -iqawno/include -ogamemodes/grand_rp.amx -d1 -O1 -;+ -(+
   ```
4. Set a real `rcon.password` in `config.json`, then start `omp-server`.
5. Join, log in to RCON (`/rcon login <password>`) and give yourself staff: `/makeadmin <your id> 5`.

## Pointing the Android client at it

Easiest: bake your server into the APK with `tools/make_apk.py --host your.server.ip` (see
`docs/CLIENT.md`). Players can still override it with a `settings.ini` in
`/sdcard/Android/data/com.rockstargames.gtasa/files/SAMP/` (or `/sdcard/SAMP/`):

```
host=your.server.ip
port=7777
name=John_Smith
```

The name must be `Firstname_Lastname` or the server rejects it.

## Before going public

- Swap `SHA256_PassHash` for the bcrypt plugin.
- Move from SQLite to MySQL (the `mysql` plugin) once you run more than one server or need a website/donate shop to read player data.
- Put the server behind a DDoS-protected host; RP servers are frequent targets.
