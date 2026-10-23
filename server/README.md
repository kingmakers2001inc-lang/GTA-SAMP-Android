# Grand RP server

Roleplay gamemode for [open.mp](https://open.mp), the server the Android client in this repo connects to.

## What's in the gamemode

| System | Details |
| --- | --- |
| Accounts | `Firstname_Lastname` names, register/login dialogs, salted SHA-256 passwords, SQLite (`scriptfiles/grand_rp.db`), autosave every 5 minutes |
| Progression | Levels and experience, hourly PayDay (salary + bank interest) |
| Roleplay chat | Proximity chat, `/me`, `/do`, `/b`, `/s`, `/w`, chat bubbles |
| Economy | Server-side money, bank (`/deposit`, `/withdraw`, `/transfer`), `/pay`, hospital bills |
| Jobs | Trucker (`/deliver`, 5 routes across San Andreas), Taxi driver (`/fare`), Mechanic (`/repair`, tow trucks at the Idlewood garage), Pizza delivery (`/pizza`, bikes at Well Stacked Pizza) |
| Factions | LSPD and Medics with 6 ranks, `/duty`, `/f` radio, `/invite`, `/uninvite`, `/setrank`, `/cuff`, `/heal` |
| Gangs | Grove Street Families and Ballas (same rank and invite commands as factions), 6 turfs shown on the map, turf wars with `/capture`: hold the turf for 2 minutes with no defenders on it to take it ($2000 each); `/turfs` lists owners, which are saved |
| Houses | Admins place them with `/createhouse [price] [1-5]` at the door (small to mansion interiors) and remove them with `/deletehouse`; players use `/buyhouse`, `/sellhouse` (half price back), `/enter`, `/exit`, `/lockhouse`; one house per player |
| Phone | Every character has a number (`/number`, also in `/stats`): `/call`, `/pickup`, `/hangup` (talk in normal chat during a call), `/sms` |
| Vehicles | Dealership (`/buycar`), up to 3 saved cars per player, `/lock`, `/park`, `/engine`, job and faction vehicle restrictions |
| Admin | Levels 1-5, `/a`, `/goto`, `/gethere`, `/kick`, `/ban`, `/unban`, `/makeadmin`, `/makeleader` (3 = Grove, 4 = Ballas), `/setmoney`, `/veh`, `/createhouse`, `/deletehouse` |

## Running it

On an Ubuntu/Debian x86_64 server: `./server/deploy/install.sh` sets everything up as a service.
See [`deploy/README.md`](deploy/README.md) for hosting options, firewall and admin setup.

Tested with open.mp 1.6.7.3218: the gamemode compiles with the bundled compiler and the mobile
client's networking code registers, spawns, chats, runs commands and respawns on it.

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
