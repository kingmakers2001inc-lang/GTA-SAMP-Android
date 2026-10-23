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
	~CRGBA();
};

#endif