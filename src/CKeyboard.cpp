#include <string.h>

#include "CKeyboard.h"
#include "CGUI.h"

enum
{
	KEY_CHAR = 0,
	KEY_SHIFT,
	KEY_SYMBOLS,
	KEY_SPACE,
	KEY_BACKSPACE,
	KEY_ENTER,
	KEY_HIDE
};

struct Key
{
	float	x, y, w, h;
	int		type;
	char	ch;
};

#define MAX_KEYS	64

static const char* s_LettersLayout[] = { "1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm" };
static const char* s_SymbolsLayout[] = { "1234567890", "@#$%&*-+()", "!?\"':;/_=", ",.<>[]|" };

static bool		s_bOpen = false;
static bool		s_bMasked = false;
static bool		s_bShift = false;
static bool		s_bSymbols = false;
static char		s_szInput[KEYBOARD_MAX_INPUT + 1];
static int		s_iPressedKey = -1;
static int		s_iPressedPointer = -1;

static Key		s_Keys[MAX_KEYS];
static int		s_iKeyCount = 0;

static CKeyboard::SubmitCallback	s_pOnSubmit = nullptr;
static CKeyboard::CancelCallback	s_pOnCancel = nullptr;

static float PanelHeight()
{
	return GUI::ScreenHeight() * 0.45f;
}

static float PanelTop()
{
	return GUI::ScreenHeight() - PanelHeight();
}

static float InputHeight()
{
	return GUI::ScreenHeight() * 0.07f;
}

static void AddKey(float x, float y, float w, float h, int type, char ch)
{
	if(s_iKeyCount >= MAX_KEYS)
		return;

	Key& key = s_Keys[s_iKeyCount++];
	key.x = x;
	key.y = y;
	key.w = w;
	key.h = h;
	key.type = type;
	key.ch = ch;
}

// Lays the keys out for the current screen size and layer
static void BuildLayout()
{
	const char** rows = s_bSymbols ? s_SymbolsLayout : s_LettersLayout;

	s_iKeyCount = 0;

	float gap = GUI::ScreenWidth() * 0.006f;
	float top = PanelTop() + gap;
	float rowHeight = (PanelHeight() - gap) / 5.0f;
	float keyWidth = GUI::ScreenWidth() / 10.0f;

	for(int row = 0; row < 4; row++)
	{
		int count = strlen(rows[row]);
		float y = top + row * rowHeight;
		float x = (GUI::ScreenWidth() - count * keyWidth) / 2.0f;

		if(row == 3)
		{
			AddKey(gap, y, keyWidth * 1.5f - gap * 2, rowHeight - gap, KEY_SHIFT, 0);
			AddKey(GUI::ScreenWidth() - keyWidth * 1.5f + gap, y, keyWidth * 1.5f - gap * 2, rowHeight - gap, KEY_BACKSPACE, 0);
		}

		for(int i = 0; i < count; i++)
		{
			char ch = rows[row][i];
			if(s_bShift && ch >= 'a' && ch <= 'z')
				ch -= 32;
			AddKey(x + i * keyWidth + gap / 2, y, keyWidth - gap, rowHeight - gap, KEY_CHAR, ch);
		}
	}

	float y = top + 4 * rowHeight;
	float h = rowHeight - gap;
	AddKey(gap, y, keyWidth * 1.5f - gap, h, KEY_HIDE, 0);
	AddKey(keyWidth * 1.5f + gap, y, keyWidth * 1.5f - gap, h, KEY_SYMBOLS, 0);
	AddKey(keyWidth * 3.0f + gap, y, keyWidth * 4.5f - gap, h, KEY_SPACE, ' ');
	AddKey(keyWidth * 7.5f + gap, y, keyWidth * 2.5f - gap * 2, h, KEY_ENTER, 0);
}

static const char* KeyLabel(const Key& key)
{
	static char label[2];
	switch(key.type)
	{
		case KEY_SHIFT:		return s_bShift ? "SHIFT" : "shift";
		case KEY_SYMBOLS:	return s_bSymbols ? "abc" : "?123";
		case KEY_SPACE:		return "space";
		case KEY_BACKSPACE:	return "<-";
		case KEY_ENTER:		return "Send";
		case KEY_HIDE:		return "Close";
	}
	label[0] = key.ch;
	label[1] = 0;
	return label;
}

static int KeyAt(float x, float y)
{
	for(int i = 0; i < s_iKeyCount; i++)
	{
		if(GUI::Inside(x, y, s_Keys[i].x, s_Keys[i].y, s_Keys[i].w, s_Keys[i].h))
			return i;
	}
	return -1;
}

static void PressKey(const Key& key)
{
	int len = strlen(s_szInput);

	switch(key.type)
	{
		case KEY_CHAR:
		case KEY_SPACE:
			if(len < KEYBOARD_MAX_INPUT)
			{
				s_szInput[len] = key.ch;
				s_szInput[len + 1] = 0;
			}
			// One-shot shift, like phone keyboards
			if(key.type == KEY_CHAR)
				s_bShift = false;
			break;

		case KEY_BACKSPACE:
			if(len > 0)
				s_szInput[len - 1] = 0;
			break;

		case KEY_SHIFT:
			s_bShift = !s_bShift;
			break;

		case KEY_SYMBOLS:
			s_bSymbols = !s_bSymbols;
			break;

		case KEY_ENTER:
		{
			// Copy first: the callback may reopen the keyboard
			char text[KEYBOARD_MAX_INPUT + 1];
			strcpy(text, s_szInput);
			CKeyboard::SubmitCallback onSubmit = s_pOnSubmit;
			CKeyboard::Close();
			if(onSubmit)
				onSubmit(text);
			break;
		}

		case KEY_HIDE:
		{
			CKeyboard::CancelCallback onCancel = s_pOnCancel;
			CKeyboard::Close();
			if(onCancel)
				onCancel();
			break;
		}
	}
}

void CKeyboard::Open(SubmitCallback onSubmit, CancelCallback onCancel, bool masked, const char* initial)
{
	s_pOnSubmit = onSubmit;
	s_pOnCancel = onCancel;
	s_bMasked = masked;
	s_bShift = false;
	s_bSymbols = false;
	s_iPressedKey = -1;
	s_iPressedPointer = -1;

	strncpy(s_szInput, initial, KEYBOARD_MAX_INPUT);
	s_szInput[KEYBOARD_MAX_INPUT] = 0;

	s_bOpen = true;
}

void CKeyboard::Close()
{
	s_bOpen = false;
	s_pOnSubmit = nullptr;
	s_pOnCancel = nullptr;
	memset(s_szInput, 0, sizeof(s_szInput));
}

bool CKeyboard::IsOpen()
{
	return s_bOpen;
}

void CKeyboard::Render()
{
	BuildLayout();

	float width = GUI::ScreenWidth();
	float gap = width * 0.006f;

	// Input line above the keys
	float inputTop = PanelTop() - InputHeight();
	GUI::DrawRect(0.0f, inputTop, width, InputHeight(), GUI_COLOR_TITLE);
	GUI::DrawRect(0.0f, PanelTop(), width, PanelHeight(), GUI_COLOR_PANEL);

	for(int i = 0; i < s_iKeyCount; i++)
	{
		const Key& key = s_Keys[i];
		GUI::DrawRect(key.x, key.y, key.w, key.h, i == s_iPressedKey ? GUI_COLOR_PRESSED : GUI_COLOR_BUTTON);
	}

	GUI::SetFont(1.0f);

	char shown[KEYBOARD_MAX_INPUT + 2];
	int len = strlen(s_szInput);
	if(s_bMasked)
	{
		memset(shown, '*', len);
		shown[len] = 0;
	}
	else
	{
		strcpy(shown, s_szInput);
	}
	strcat(shown, "_");

	// Keep the end of long input visible
	const char* visible = shown;
	while(*visible && GUI::TextWidth(visible) > width - gap * 4)
		visible++;

	GUI::DrawText(gap * 2, inputTop + (InputHeight() - GUI::LineHeight()) / 2.0f, visible, GUI_COLOR_WHITE);

	for(int i = 0; i < s_iKeyCount; i++)
	{
		const Key& key = s_Keys[i];
		const char* label = KeyLabel(key);
		float labelWidth = GUI::TextWidth(label);
		GUI::DrawText(key.x + (key.w - labelWidth) / 2.0f, key.y + (key.h - GUI::LineHeight()) / 2.0f, label, GUI_COLOR_WHITE);
	}
}

bool CKeyboard::OnTouch(int type, int num, float x, float y)
{
	BuildLayout();

	if(type == TOUCH_PRESS)
	{
		s_iPressedKey = KeyAt(x, y);
		s_iPressedPointer = num;
	}
	else if(type == TOUCH_MOVE && num == s_iPressedPointer)
	{
		s_iPressedKey = KeyAt(x, y);
	}
	else if(type == TOUCH_RELEASE && num == s_iPressedPointer)
	{
		int key = KeyAt(x, y);
		s_iPressedKey = -1;
		s_iPressedPointer = -1;
		if(key != -1)
			PressKey(s_Keys[key]);
	}

	// The keyboard is modal while open
	return true;
}
