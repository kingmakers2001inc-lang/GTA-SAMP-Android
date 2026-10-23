# Roadmap: from this repo to a Grand Mobile-style RP game

Games like Grand Mobile, One State RP and Black Russia are built the same way:

1. **Game engine**: GTA San Andreas for Android (`libGTASA.so`), heavily modded.
2. **Multiplayer client**: a SA-MP/CR-MP style library (this repo's `libSAMP.so`) injected into the game. It hooks the engine, syncs players and vehicles over RakNet, and draws a custom HUD and UI.
3. **Launcher APK**: downloads and updates game files, shows the server list, news, and handles login/donations.
4. **Server**: SA-MP/open.mp with a large custom gamemode (jobs, factions, houses, businesses, economy), plus a website and donate shop on the same database.

## Where this repo is today

| Part | State |
| --- | --- |
| Client hooks (scripts, population, render, touch) | Working; touch goes through an inline hook on `AND_TouchEvent` |
| Connection to open.mp / SA-MP 0.3.7 servers | Working: 0.3.7 cipher, connection cookie, auth keys, packet IDs, version 4057. Covered by `tests/netcode/run.sh` |
| Chat window, `/commands`, on-screen keyboard | Implemented, protocol tested; on-device layout needs tuning |
| Dialogs (msgbox, input, password, list, tablist) | Implemented, protocol tested; on-device layout needs tuning |
| Spawn flow, on-foot sync | Basic / not implemented |
| Vehicles, textdraws, checkpoints, pickups | Not implemented |
| Server gamemode | `server/` - accounts, jobs, factions, bank, dealership, admin |
| Launcher APK | Not started |

## Milestones

### 1. Playable multiplayer (client)
- Spawn flow: `RequestClass`/`RequestSpawn`/`Spawn`, `TogglePlayerSpectating`, `SetSpawnInfo` - needed right after the login dialog.
- Core RPCs: `SetPlayerPos`, `GivePlayerMoney`/`ResetPlayerMoney`, `SetPlayerSkin`, `SetPlayerHealth`, `GameText`.
- Remote players: create/destroy peds on stream in/out, interpolate 0.3.7 on-foot sync.
- Vehicles: `WorldVehicleAdd/Remove`, driver and passenger sync.
- Checkpoints and pickups (used by jobs and the dealership).

### 2. Custom mobile UI (what makes it feel like Grand Mobile)
- Touch HUD: health/armour/money/level, speedometer, interaction button instead of typed commands.
- Custom server-driven menus (inventory, phone, bank, dealership) rendered natively instead of SA-MP dialogs.
- Custom models/textures streamed from the launcher (cars, skins, map edits).

### 3. Launcher
- Android app (Kotlin) with server list, news, settings (writes `settings.ini`), and a file updater that downloads your mod files from a CDN.
- Anti-cheat basics: file checksums, signed APK, server-side validation of money/position (the gamemode already keeps money server side).

### 4. Server growth
- Houses and businesses, inventory, phone, gangs and turf wars, driving licenses, more jobs.
- MySQL + website (account panel, donations) on the same database.
- Multiple server instances behind one launcher list.

## Legal note - read before publishing anything

`libGTASA.so` and the game data belong to Rockstar Games / Take-Two. Distributing them (or an APK that bundles them) on Google Play or elsewhere is copyright infringement and is the main reason clones get taken down. The safe model is the one SA-MP itself used: ship only your own client library, launcher, and assets, and require players to install their own legitimately purchased copy of GTA: San Andreas. Do not copy names, logos or art from Grand Mobile or other existing projects - give your project its own brand.
