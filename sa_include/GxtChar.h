#ifndef __GXTCHAR_H__
#define __GXTCHAR_H__

// Engine text character: unsigned short in the 32-bit 2.00 build, short in the 64-bit 2.11 build
#if defined(__aarch64__)
typedef short GxtChar;
#else
typedef unsigned short GxtChar;
#endif

#endif
