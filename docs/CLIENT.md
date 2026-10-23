# Android client (libSAMP.so)

`libSAMP.so` is loaded into GTA: San Andreas for Android. It hooks the engine and speaks the
SA-MP 0.3.7 protocol, which is what open.mp servers (and the `server/` gamemode) expect.

## Building

With a current Android NDK (Linux or macOS):

```
NDK=/path/to/android-ndk ./build.sh                  # out/armeabi-v7a/libSAMP.so
NDK=/path/to/android-ndk ABI=arm64-v8a ./build.sh    # out/arm64-v8a/libSAMP.so
```

The original Windows toolchain (`build.bat` + `Makefile`) still builds the 32-bit library.

## Game builds

| Game build | ABI | Status |
| --- | --- | --- |
| Early build in `libs/libGTASA.so` | armeabi-v7a | Reverse engineered; everything in this file applies |
| 2.11 (current Play Store) | arm64-v8a | Port in progress: builds and links, engine layouts not verified yet |

What the 64-bit port has so far:

- Hooks go through `src/hook.*`, using And64InlineHook (`inlinehook/arm64/`) on arm64.
- The 2D render hook calls the game's own function and draws on top, instead of replacing it.
- Without a 64-bit `libGTASA.so` in `libs/arm64-v8a/`, `build.sh` links against a stand-in made
  from the client's imports (`obj-ndk/arm64-v8a/engine_imports.txt`). The real game library is used at runtime.
- Still to verify against the 2.11 binary: that it exports every import, the `CRunningScript`
  layout (script commands are disabled on arm64 until then), `AND_TouchEvent`, and the ped
  class layout used for remote players. Check exports with:
  `python3 tools/engine_stub.py check --symbols obj-ndk/arm64-v8a/engine_imports.txt --lib path/to/libGTASA.so`

## Making the APK

The game is not in this repository and must never be distributed with it. `tools/make_apk.py`
turns **your own** GTA: San Andreas APK into the multiplayer APK:

```
python3 tools/make_apk.py --apk gta_sa.apk --host your.server.ip --port 7777
```

It adds `out/<abi>/libSAMP.so` for each ABI the game ships, makes the game load it right after
`libGTASA.so`, bakes in the server address (optional), then rebuilds, aligns and signs the APK as
`GTA-SAMP.apk`. Before building it checks that the game's `libGTASA.so` exports everything the
client imports, so an APK that would fail to start is never produced. It needs Java,
[apktool](https://apktool.org) and `zipalign` + `apksigner` from the Android SDK build-tools
(found through `ANDROID_HOME`, or pass `--build-tools`).

Things to know before installing:

- The script only accepts game builds listed in `KNOWN_GAME_BUILDS` (today the early 32-bit build,
  SHA-256 `59e7198de1916d5f7d22037233f385983099fd53cfab07c707ca25b9d7a834d7`). `--force` builds a
  test APK for other builds, which may crash.
- Play Store installs come as split APKs (`base.apk` + `split_config.*.apk`). Export the installed
  game with an APK extractor (for example ML Manager) as a bundle and pass it directly
  (`--apk GTA.apks`), or pass `--apk base.apk --split split_config.arm64_v8a.apk ...`. The output
  is then `GTA-SAMP.apks`: install it with SAI (Split APKs Installer). Every piece is re-signed with
  the same key, and `libSAMP.so` is added to the split that holds the game library, uncompressed
  and page-aligned.
- Uninstall the original game first (the signature differs) and keep its data files
  (`Android/obb/com.rockstargames.gtasa`).
- Android 14+ blocks installing apps that target very old Android versions. If you get that error,
  install from a PC with `adb install --bypass-low-target-sdk-block GTA-SAMP.apk`.
- Client logs: `adb logcat -s SA_HACK_LOG`.

## Connecting

The server baked in by `make_apk.py` is used unless a `settings.ini` overrides it. The client looks
in `/sdcard/Android/data/com.rockstargames.gtasa/files/SAMP/settings.ini` first (readable on every
Android version), then `/sdcard/SAMP/settings.ini`:

```
host=your.server.ip
port=7777
name=John_Smith
```

Connection progress, server messages and errors (wrong version, bad name, full server) show in the chat window.

## In-game UI

| Part | Files | Notes |
| --- | --- | --- |
| Drawing helpers, touch routing | `src/CGUI.*` | `{RRGGBB}` colour embeds, layout scaled to screen height (1.0 = 1080p) |
| Chat | `src/CChat.*` | Last 8 lines top-left with word wrap; the **Chat** button opens the keyboard; text starting with `/` is sent as a command |
| Dialogs | `src/CDialog.*` | All six SA-MP styles; drag to scroll lists, tap the selected item again to confirm |
| Keyboard | `src/CKeyboard.*` | Letters/symbols layers, one-shot shift, password masking |

## Spawning

After `InitGame` the client requests class 0. Servers that gate spawning behind a login (like
`server/`) put the player in spectator mode; `TogglePlayerSpectating(false)` or `SpawnPlayer()`
then spawns them at the spawn info the server sent. After a death the client reports it and asks
to spawn again once the engine revives the ped.

Position, heading, skin, health, interior, money and controls are applied by running single SCM
opcodes through the engine's interpreter (`src/CScript.*`), like the PC SA-MP client does, rather
than writing to struct offsets.

Touches the UI accepts never reach the game. Dialogs and the keyboard are modal while open.

Sizes, colours and the font scale are constants at the top of each file. They were chosen without a
device to test on, so expect to tune them on a real phone.

## Netcode test

```
tests/netcode/run.sh
```

Builds open.mp's server RakNet (pinned commit) and the client's networking + UI code for the host,
then runs a full session: connect, auth, login dialog typed on the touch keyboard, spawn, chat, a command,
death and respawn. Engine calls are recorded instead of run, so the test also checks what the client
told the engine to do (spawn point, skin, money, controls).
It needs only `git`, `g++` and `python3`, and it is the quickest way to catch protocol regressions.
