#ifndef __UTILS_H__
#define __UTILS_H__

int log(const char *format, ...);
#if !defined(__aarch64__)
int memcpy_protect(void* to, void* from, int len);
void ARMCALL(void* from, void* to);
void ARMJMP(void* from, void* to);
void ARMBIGJMP(void* from, void* to);
#endif

#endif