#include <stdlib.h>
#include <string.h>
#include <GTASA.h>

#include "CGUI.h"
#include "CChat.h"
#include "CDialog.h"
#include "CKeyboard.h"

#define MAX_TEXT_LEN	256

static float	s_fFontScale = 1.0f;

float GUI::ScreenWidth()
{
	return (float) OS_ScreenGetWidth();
}

float GUI::ScreenHeight()
{
	return (float) OS_ScreenGetHeight();
}

float GUI::Scale()
{
	return ScreenHeight() / 1080.0f;
}

void GUI::SetFont(float scale)
{
	s_fFontScale = scale;

	CFont::SetFontStyle(1);
	CFont::SetBackground(0, 0);
	CFont::SetWrapx(ScreenWidth() * 2.0f);
	CFont::SetProportional(1);
	CFont::SetJustify(0);
	CFont::SetOrientation(1);
	CFont::SetEdge(1);
	CFont::SetDropColor(CRGBA(0x00, 0x00, 0x00, 0xFF));
	CFont::SetScale(scale * Scale());
}

float GUI::LineHeight()
{
	return CFont::GetHeight(false);
}

// Converts to the engine's text format, dropping '~' so server text can't inject font tokens
static void ToGxt(const char* text, int len, unsigned short* out)
{
	char buffer[MAX_TEXT_LEN + 1];
	if(len > MAX_TEXT_LEN)
		len = MAX_TEXT_LEN;

	for(int i = 0; i < len; i++)
		buffer[i] = (text[i] == '~') ? '-' : text[i];
	buffer[len] = 0;

	AsciiToGxtChar(buffer, out);
}

static bool IsHex(char c)
{
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

// Returns true when text starts with {RRGGBB}
static bool ParseColorEmbed(const char* text, uint32_t* rgb)
{
	if(text[0] != '{')
		return false;
	for(int i = 1; i <= 6; i++)
	{
		if(!IsHex(text[i]))
			return false;
	}
	if(text[7] != '}')
		return false;

	char hex[7];
	memcpy(hex, text + 1, 6);
	hex[6] = 0;
	*rgb = (uint32_t) strtoul(hex, nullptr, 16);
	return true;
}

static float SegmentWidth(const char* text, int len)
{
	if(len <= 0)
		return 0.0f;

	unsigned short gxt[MAX_TEXT_LEN + 1];
	ToGxt(text, len, gxt);
	return CFont::GetStringWidth(gxt, 1, 0);
}

float GUI::TextWidth(const char* text)
{
	float width = 0.0f;
	const char* start = text;
	uint32_t rgb;

	for(const char* p = text; ; p++)
	{
		bool embed = ParseColorEmbed(p, &rgb);
		if(embed || *p == 0)
		{
			width += SegmentWidth(start, p - start);
			if(*p == 0)
				break;
			p += 7;
			start = p + 1;
		}
	}
	return width;
}

void GUI::DrawRect(float x, float y, float w, float h, uint32_t rgba)
{
	CRect rect;
	rect.left = x;
	rect.top = y;
	rect.right = x + w;
	rect.bottom = y + h;
	CSprite2d::DrawRect(rect, CRGBA(rgba >> 24, (rgba >> 16) & 0xFF, (rgba >> 8) & 0xFF, rgba & 0xFF));
}

static void DrawSegment(float x, float y, const char* text, int len, uint32_t rgba)
{
	if(len <= 0)
		return;

	unsigned short gxt[MAX_TEXT_LEN + 1];
	ToGxt(text, len, gxt);
	CFont::SetColor(CRGBA(rgba >> 24, (rgba >> 16) & 0xFF, (rgba >> 8) & 0xFF, rgba & 0xFF));
	CFont::PrintString(x, y, gxt);
}

void GUI::DrawText(float x, float y, const char* text, uint32_t rgba)
{
	const char* start = text;
	uint32_t rgb;

	for(const char* p = text; ; p++)
	{
		bool embed = ParseColorEmbed(p, &rgb);
		if(embed || *p == 0)
		{
			DrawSegment(x, y, start, p - start, rgba);
			x += SegmentWidth(start, p - start);
			if(*p == 0)
				break;
			rgba = (rgb << 8) | (rgba & 0xFF);
			p += 7;
			start = p + 1;
		}
	}
}

void GUI::Flush()
{
	CFont::RenderFontBuffer();
}

bool GUI::Inside(float px, float py, float x, float y, float w, float h)
{
	return px >= x && px <= x + w && py >= y && py <= y + h;
}

bool GUI::OnTouch(int type, int num, float x, float y)
{
	// Topmost first: keyboard, then the modal dialog, then the chat
	if(CKeyboard::IsOpen())
		return CKeyboard::OnTouch(type, num, x, y);
	if(CDialog::IsOpen())
		return CDialog::OnTouch(type, num, x, y);
	return CChat::OnTouch(type, num, x, y);
}

void GUI::Render()
{
	CChat::Render();
	Flush();

	if(CDialog::IsOpen())
	{
		CDialog::Render();
		Flush();
	}

	if(CKeyboard::IsOpen())
	{
		CKeyboard::Render();
		Flush();
	}
}
