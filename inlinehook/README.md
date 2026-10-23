Vendored from https://github.com/ele7enxxh/Android-Inline-Hook (Apache-2.0, see LICENSE),
commit a0de1f9c3d25c35db6d435a9240a07638e670749. Used for armeabi-v7a builds; arm64-v8a
builds use `arm64/` (And64InlineHook).

Local changes: added `#include <unistd.h>` for current NDKs, and building with
`INLINEHOOK_NO_FREEZE` skips the fork + ptrace thread freeze, which modern Android blocks
inside apps. Hooks are installed from JNI_OnLoad before the game threads touch the hooked
functions.
