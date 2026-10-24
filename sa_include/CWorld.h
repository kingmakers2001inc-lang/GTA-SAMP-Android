#ifndef __CWORLD_H__
#define __CWORLD_H__

class CWorld
{
public:
	static signed char PlayerInFocus;	// 1 byte in both the 2.00 and 2.11 builds
	
	static CPed* Players[202]; //83 is a special pad. 101 is 2nd, 202 is 3rd player ped.

	static void Add(CEntity *);
	static void Remove(CEntity *);
};

#endif