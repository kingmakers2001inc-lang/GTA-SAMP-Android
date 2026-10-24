#include <dlfcn.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <ucontext.h>

#include "crashlog.h"

static int s_iFile = -1;

static const char* const LOG_PATHS[] = {
	"/sdcard/Download/samp_log.txt",
	"/storage/emulated/0/Download/samp_log.txt",
	"/sdcard/Android/data/com.rockstargames.gtasa/files/samp_log.txt",
};

static const int CRASH_SIGNALS[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT };
static struct sigaction s_OldActions[sizeof(CRASH_SIGNALS) / sizeof(CRASH_SIGNALS[0])];

void CrashLog_Write(const char* line)
{
	if(s_iFile < 0)
		return;
	write(s_iFile, line, strlen(line));
	write(s_iFile, "\n", 1);
}

// Signal-safe enough for a dying process: snprintf into a stack buffer, then write()
static void WriteAddress(const char* label, uintptr_t addr)
{
	char line[256];
	Dl_info info;
	if(addr && dladdr((void*) addr, &info) && info.dli_fname)
	{
		const char* name = strrchr(info.dli_fname, '/');
		snprintf(line, sizeof(line), "  %s %p  %s+0x%lx  %s", label, (void*) addr, name ? name + 1 : info.dli_fname,
			(unsigned long) (addr - (uintptr_t) info.dli_fbase), info.dli_sname ? info.dli_sname : "");
	}
	else
	{
		snprintf(line, sizeof(line), "  %s %p", label, (void*) addr);
	}
	CrashLog_Write(line);
}

static void OnCrash(int sig, siginfo_t* info, void* context)
{
	char line[128];
	snprintf(line, sizeof(line), "*** CRASH: signal %d, fault address %p", sig, info ? info->si_addr : nullptr);
	CrashLog_Write(line);

	ucontext_t* uc = (ucontext_t*) context;
#if defined(__aarch64__)
	uintptr_t pc = uc->uc_mcontext.pc, lr = uc->uc_mcontext.regs[30], fp = uc->uc_mcontext.regs[29];
#else
	uintptr_t pc = uc->uc_mcontext.arm_pc, lr = uc->uc_mcontext.arm_lr, fp = uc->uc_mcontext.arm_fp;
#endif
	WriteAddress("pc", pc);
	WriteAddress("lr", lr);

	// Frame pointer chain: [fp] = caller's fp, [fp + word] = return address
	for(int i = 0; i < 24 && fp && (fp & (sizeof(void*) - 1)) == 0; i++)
	{
		uintptr_t* frame = (uintptr_t*) fp;
		uintptr_t ret = frame[1];
		if(!ret)
			break;
		WriteAddress("at", ret);
		if(frame[0] <= fp)
			break;
		fp = frame[0];
	}
	CrashLog_Write("*** end of crash report");

	// Hand the signal to whoever had it before (the system's crash reporter)
	for(size_t i = 0; i < sizeof(CRASH_SIGNALS) / sizeof(CRASH_SIGNALS[0]); i++)
	{
		if(CRASH_SIGNALS[i] == sig)
		{
			sigaction(sig, &s_OldActions[i], nullptr);
			break;
		}
	}
	raise(sig);
}

void CrashLog_Init()
{
	for(const char* path : LOG_PATHS)
	{
		s_iFile = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
		if(s_iFile >= 0)
			break;
	}

	char line[96];
	time_t now = time(nullptr);
	strftime(line, sizeof(line), "=== SA-MP client started %Y-%m-%d %H:%M:%S ===", localtime(&now));
	CrashLog_Write(line);

	static char altStack[64 * 1024];
	stack_t ss;
	ss.ss_sp = altStack;
	ss.ss_size = sizeof(altStack);
	ss.ss_flags = 0;
	sigaltstack(&ss, nullptr);

	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = OnCrash;
	sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
	sigemptyset(&sa.sa_mask);
	for(size_t i = 0; i < sizeof(CRASH_SIGNALS) / sizeof(CRASH_SIGNALS[0]); i++)
		sigaction(CRASH_SIGNALS[i], &sa, &s_OldActions[i]);
}
