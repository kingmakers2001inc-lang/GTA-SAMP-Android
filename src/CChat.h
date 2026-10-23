#ifndef __CCHAT_H__
#define __CCHAT_H__

#include <stdint.h>

#define CHAT_MAX_LINES		100
#define CHAT_VISIBLE_LINES	8
#define CHAT_LINE_LEN		160

class CChat
{
public:
	// rgba is the SA-MP 0xRRGGBBAA colour; text may contain {RRGGBB} embeds
	static void AddMessage(uint32_t rgba, const char* text);
	static void AddChatMessage(const char* name, uint32_t nameRgba, const char* text);
	// Client-side notices (connection state etc.)
	static void AddInfoMessage(const char* format, ...);

	static void Render();
	static bool OnTouch(int type, int num, float x, float y);
};

#endif
