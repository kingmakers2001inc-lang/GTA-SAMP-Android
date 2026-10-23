# Android client (libSAMP.so)

`libSAMP.so` is loaded into GTA: San Andreas for Android. It hooks the engine and speaks the
SA-MP 0.3.7 protocol, which is what open.mp servers (and the `server/` gamemode) expect.

## Building

With a current Android NDK (Linux or macOS):

```
NDK=/path/to/android-ndk ./build.sh
```

The original Windows toolchain (`build.bat` + `Makefile`) still works the same way.

## Connecting

The client reads `/sdcard/SAMP/settings.ini`:

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

Touches the UI accepts never reach the game. Dialogs and the keyboard are modal while open.

Sizes, colours and the font scale are constants at the top of each file. They were chosen without a
device to test on, so expect to tune them on a real phone.

## Netcode test

```
tests/netcode/run.sh
```

Builds open.mp's server RakNet (pinned commit) and the client's networking + UI code for the host,
then runs a full session: connect, auth, login dialog typed on the touch keyboard, chat and a command.
It needs only `git`, `g++` and `python3`, and it is the quickest way to catch protocol regressions.
