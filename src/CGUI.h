#ifndef __CGUI_H__
#define __CGUI_H__

#include <stdint.h>

#define TOUCH_RELEASE	1
#define TOUCH_PRESS		2
#define TOUCH_MOVE		3

// Colours are 0xRRGGBBAA, like SA-MP
#define GUI_COLOR_WHITE		0xFFFFFFFF
#define GUI_COLOR_GREY		0xA9C4E4FF
#define GUI_COLOR_PANEL		0x101418E0
#define GUI_COLOR_TITLE		0x1B2633F0
#define GUI_COLOR_BUTTON	0x2E4A66F0
#define GUI_COLOR_PRESSED	0x4F7FAFF0
#define GUI_COLOR_SELECTED	0x3A6EA5C0
#define GUI_COLOR_FIELD		0x00000090

namespace GUI
{
	float ScreenWidth();
	float ScreenHeight();
	// 1.0 on a 1080p screen
	float Scale();

	void SetFont(float scale);
	float LineHeight();
	// Width of text as drawn, {RRGGBB} colour embeds excluded
	float TextWidth(const char* text);

	void DrawRect(float x, float y, float w, float h, uint32_t rgba);
	// Draws text with SA-MP {RRGGBB} colour embeds, starting in rgba
	void DrawText(float x, float y, const char* text, uint32_t rgba);
	// Flushes buffered text so later rectangles draw above it
	void Flush();

	bool Inside(float px, float py, float x, float y, float w, float h);

	// Touch from the engine, returns true when the UI consumed it
	bool OnTouch(int type, int num, float x, float y);
	void Render();
}

#endif
