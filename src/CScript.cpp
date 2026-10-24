#include <stdarg.h>
#include <string.h>
#include <GTASA.h>

#include "CScript.h"
#include "utils.h"

// Mobile CRunningScript layout (from ProcessOneCommand, UpdateCompareFlag and
// GetPointerToLocalVariable in libGTASA.so). The and/or counter, NOT flag and mission
// flag must stay zero, which the memset below guarantees.
#if defined(__aarch64__)
// 2.11.311 libGame.so: IP from ProcessOneCommand, locals and mission flag (0x12C) from
// GetPointerToLocalVariable, compare flag, and/or counter (0x120) and NOT flag (0x122)
// from UpdateCompareFlag, name from Init
#define SCRIPT_LAYOUT_KNOWN			1
#define SCRIPT_OFFSET_NAME			0x10
#define SCRIPT_OFFSET_IP			0x20
#define SCRIPT_OFFSET_LOCALS		0x6C
#define SCRIPT_OFFSET_COMPARE_FLAG	0x115
#else
#define SCRIPT_LAYOUT_KNOWN			1
#define SCRIPT_OFFSET_NAME			0x08
#define SCRIPT_OFFSET_IP			0x14	// and/or counter 0xF0, NOT flag 0xF2, mission flag 0xFC
#define SCRIPT_OFFSET_LOCALS		0x3C
#define SCRIPT_OFFSET_COMPARE_FLAG	0xE5
#endif
#define SCRIPT_SIZE					0x200

// SCM parameter type tags
#define SCM_INT32		0x01
#define SCM_LOCAL_VAR	0x03
#define SCM_FLOAT		0x06

#define MAX_RESULTS		8

static unsigned char	s_Script[SCRIPT_SIZE] __attribute__((aligned(8)));
static unsigned char	s_Code[256];

bool ScriptCommand(unsigned short opcode, const char* format, ...)
{
	if(!SCRIPT_LAYOUT_KNOWN)
	{
		static bool warned = false;
		if(!warned)
			log("Script commands are not supported on this build yet");
		warned = true;
		return false;
	}
	
	memset(s_Script, 0, sizeof(s_Script));
	strcpy((char*) s_Script + SCRIPT_OFFSET_NAME, "samp");
	
	unsigned char* p = s_Code;
	*(unsigned short*) p = opcode;
	p += 2;
	
	int* results[MAX_RESULTS];
	int resultCount = 0;
	
	va_list args;
	va_start(args, format);
	for(const char* f = format; *f; f++)
	{
		switch(*f)
		{
			case 'i':
				*p++ = SCM_INT32;
				*(int*) p = va_arg(args, int);
				p += 4;
				break;
			
			case 'f':
				*p++ = SCM_FLOAT;
				*(float*) p = (float) va_arg(args, double);
				p += 4;
				break;
			
			case 'v':
				if(resultCount < MAX_RESULTS)
				{
					*p++ = SCM_LOCAL_VAR;
					*(unsigned short*) p = (unsigned short) resultCount;
					p += 2;
					results[resultCount++] = va_arg(args, int*);
				}
				break;
		}
	}
	va_end(args);
	
	*(unsigned char**) (s_Script + SCRIPT_OFFSET_IP) = s_Code;
	((CRunningScript*) s_Script)->ProcessOneCommand();
	
	int* locals = (int*) (s_Script + SCRIPT_OFFSET_LOCALS);
	for(int i = 0; i < resultCount; i++)
		*results[i] = locals[i];
	
	return s_Script[SCRIPT_OFFSET_COMPARE_FLAG] != 0;
}
