#ifndef __HOOK_H__
#define __HOOK_H__

// Redirects target to replacement. When original is not null it receives a trampoline
// that runs the unmodified target. Picks the right backend for the build's ABI.
bool InstallHook(void* target, void* replacement, void** original = nullptr);

#endif
