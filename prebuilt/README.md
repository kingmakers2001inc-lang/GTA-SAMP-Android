# Prebuilt client

`arm64-v8a/libSAMP.so` is the multiplayer client built from this repo with
`ABI=arm64-v8a ./build.sh` for GTA SA 2.11.311, so you can make your APK on a
phone without the Android NDK: `bash tools/termux_build.sh` in Termux.
It contains only this project's code; the game itself is never in this repo.
