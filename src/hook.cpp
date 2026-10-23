#include <stdint.h>

#include "hook.h"
#include "utils.h"

#if defined(__aarch64__)
#include "arm64/And64InlineHook.hpp"
#else
#include "inlineHook.h"
#endif

bool InstallHook(void* target, void* replacement, void** original)
{
#if defined(__aarch64__)
	if(!original)
	{
		A64HookFunction(target, replacement, nullptr);
		return true;
	}
	A64HookFunction(target, replacement, original);
	return *original != nullptr;
#else
	// Plain redirects keep the original jump patch; calling the original needs a relocating trampoline
	if(!original)
	{
		ARMBIGJMP(target, replacement);
		return true;
	}
	return registerInlineHook((uint32_t) target, (uint32_t) replacement, (uint32_t**) original) == ELE7EN_OK
		&& inlineHook((uint32_t) target) == ELE7EN_OK;
#endif
}
