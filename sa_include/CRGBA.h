#ifndef __CRGBA_H__
#define __CRGBA_H__

class CRGBA
{
public:
	unsigned char r;
	unsigned char g;
	unsigned char b;
	unsigned char a;
	
public:
	CRGBA(unsigned char, unsigned char, unsigned char, unsigned char);
#if !defined(__aarch64__)
	// The 32-bit build declares a destructor, which makes CRGBA pass by reference; the 64-bit build has none
	~CRGBA();
#endif
};

#endif