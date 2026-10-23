#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "CChat.h"
#include "CGUI.h"
#include "CKeyboard.h"
#include "CNetGame.h"
#include "utils.h"

#define CHAT_FONT_SCALE		0.9f
#define CHAT_INFO_COLOR		0x88AA62FF

struct ChatLine
{
	char		text[CHAT_LINE_LEN];
	uint32_t	rgba;
};

static ChatLine	s_Lines[CHAT_MAX_LINES];
static int		s_iLineCount = 0;
static int		s_iNextLine = 0;
static int		s_iPressedPointer = -1;

static float ChatLeft()
{
	return GUI::ScreenWidth() * 0.02f;
}

static float ChatTop()
{
	return GUI::ScreenHeight() * 0.03f;
}

static float ChatWidth()
{
	return GUI::ScreenWidth() * 0.45f;
}

static void ChatButton(float* x, float* y, float* w, float* h)
{
	GUI::SetFont(CHAT_FONT_SCALE);
	*x = ChatLeft();
	*y = ChatTop() + CHAT_VISIBLE_LINES * GUI::LineHeight() + GUI::ScreenHeight() * 0.01f;
	*w = GUI::ScreenWidth() * 0.08f;
	*h = GUI::ScreenHeight() * 0.05f;
}

static void PushLine(const char* text, uint32_t rgba)
{
	ChatLine& line = s_Lines[s_iNextLine];
	strncpy(line.text, text, CHAT_LINE_LEN - 1);
	line.text[CHAT_LINE_LEN - 1] = 0;
	line.rgba = rgba;

	s_iNextLine = (s_iNextLine + 1) % CHAT_MAX_LINES;
	if(s_iLineCount < CHAT_MAX_LINES)
		s_iLineCount++;
}

void CChat::AddMessage(uint32_t rgba, const char* text)
{
	log("[CHAT] %s", text);

	// Word-wrap to the chat width; continuation lines keep the last {RRGGBB} colour
	GUI::SetFont(CHAT_FONT_SCALE);

	char line[CHAT_LINE_LEN];
	char lastEmbed[9] = "";
	const char* p = text;

	while(*p)
	{
		int len = strlen(p);
		if(len >= CHAT_LINE_LEN - 9)
			len = CHAT_LINE_LEN - 10;

		// Longest prefix that fits, preferring to break at a space
		int fit = len;
		strcpy(line, lastEmbed);
		int prefix = strlen(line);
		while(fit > 1)
		{
			memcpy(line + prefix, p, fit);
			line[prefix + fit] = 0;
			if(GUI::TextWidth(line) <= ChatWidth())
				break;

			int space = fit - 1;
			while(space > 0 && p[space] != ' ')
				space--;
			fit = (space > 0) ? space : fit - 1;
		}
		memcpy(line + prefix, p, fit);
		line[prefix + fit] = 0;
		PushLine(line, rgba);

		// Remember the colour in effect at the break
		for(int i = 0; i < fit; i++)
		{
			if(p[i] == '{' && i + 7 < len && p[i + 7] == '}')
			{
				memcpy(lastEmbed, p + i, 8);
				lastEmbed[8] = 0;
			}
		}

		p += fit;
		while(*p == ' ')
			p++;
	}
}

void CChat::AddChatMessage(const char* name, uint32_t nameRgba, const char* text)
{
	char message[CHAT_LINE_LEN * 2];
	snprintf(message, sizeof(message), "%s: {FFFFFF}%s", name, text);
	AddMessage(nameRgba | 0xFF, message);
}

void CChat::AddInfoMessage(const char* format, ...)
{
	char message[CHAT_LINE_LEN * 2];
	va_list args;
	va_start(args, format);
	vsnprintf(message, sizeof(message), format, args);
	va_end(args);
	AddMessage(CHAT_INFO_COLOR, message);
}

static void OnChatSubmit(const char* text)
{
	if(text[0] == 0)
		return;

	if(text[0] == '/')
		CNetGame::Instance()->SendCommand(text);
	else
		CNetGame::Instance()->SendChatMessage(text);
}

void CChat::Render()
{
	GUI::SetFont(CHAT_FONT_SCALE);
	float lineHeight = GUI::LineHeight();

	int visible = s_iLineCount < CHAT_VISIBLE_LINES ? s_iLineCount : CHAT_VISIBLE_LINES;
	for(int i = 0; i < visible; i++)
	{
		int index = (s_iNextLine - visible + i + CHAT_MAX_LINES) % CHAT_MAX_LINES;
		float y = ChatTop() + (CHAT_VISIBLE_LINES - visible + i) * lineHeight;
		GUI::DrawText(ChatLeft(), y, s_Lines[index].text, s_Lines[index].rgba);
	}

	if(!CNetGame::Instance()->m_isInGame)
		return;

	float x, y, w, h;
	ChatButton(&x, &y, &w, &h);
	GUI::DrawRect(x, y, w, h, s_iPressedPointer != -1 ? GUI_COLOR_PRESSED : GUI_COLOR_BUTTON);
	GUI::DrawText(x + (w - GUI::TextWidth("Chat")) / 2.0f, y + (h - lineHeight) / 2.0f, "Chat", GUI_COLOR_WHITE);
}

bool CChat::OnTouch(int type, int num, float x, float y)
{
	if(!CNetGame::Instance()->m_isInGame)
		return false;

	float bx, by, bw, bh;
	ChatButton(&bx, &by, &bw, &bh);

	if(type == TOUCH_PRESS)
	{
		if(!GUI::Inside(x, y, bx, by, bw, bh))
			return false;
		s_iPressedPointer = num;
		return true;
	}

	if(num != s_iPressedPointer)
		return false;

	if(type == TOUCH_RELEASE)
	{
		s_iPressedPointer = -1;
		if(GUI::Inside(x, y, bx, by, bw, bh))
			CKeyboard::Open(OnChatSubmit, nullptr, false);
	}
	return true;
}
