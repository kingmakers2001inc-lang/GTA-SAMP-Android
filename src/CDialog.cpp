#include <string.h>

#include "CDialog.h"
#include "CGUI.h"
#include "CKeyboard.h"
#include "CNetGame.h"
#include "utils.h"

#define DIALOG_FONT_SCALE	1.0f
#define DIALOG_MAX_LINES	64
#define DIALOG_MAX_COLUMNS	4
#define DIALOG_LIST_ROWS	8

enum
{
	PART_NONE = 0,
	PART_BUTTON1,
	PART_BUTTON2,
	PART_INPUT,
	PART_LIST
};

static bool		s_bOpen = false;
static int		s_iID = -1;
static int		s_iStyle = DIALOG_STYLE_MSGBOX;
static char		s_szTitle[64];
static char		s_szBody[DIALOG_MAX_BODY + 1];
static char		s_szButton1[32];
static char		s_szButton2[32];
static char		s_szInput[KEYBOARD_MAX_INPUT + 1];

// s_szBody split into lines in place
static char*	s_pLines[DIALOG_MAX_LINES];
static int		s_iLineCount = 0;

static int		s_iSelected = 0;
static int		s_iScroll = 0;
static int		s_iPressedPart = PART_NONE;
static int		s_iPressedPointer = -1;
static float	s_fPressY = 0.0f;
static int		s_iPressScroll = 0;
static bool		s_bDragged = false;

static bool IsList()
{
	return s_iStyle == DIALOG_STYLE_LIST || s_iStyle == DIALOG_STYLE_TABLIST || s_iStyle == DIALOG_STYLE_TABLIST_HEADERS;
}

static bool HasInput()
{
	return s_iStyle == DIALOG_STYLE_INPUT || s_iStyle == DIALOG_STYLE_PASSWORD;
}

// For tablist headers the first line is the header row, not an item
static int FirstItem()
{
	return s_iStyle == DIALOG_STYLE_TABLIST_HEADERS ? 1 : 0;
}

static int ItemCount()
{
	int count = s_iLineCount - FirstItem();
	return count > 0 ? count : 0;
}

struct Layout
{
	float x, y, w, h;
	float lineHeight;
	float titleHeight;
	float bodyY;
	float listY, rowHeight;
	int rows;
	float inputY, inputHeight;
	float buttonY, buttonWidth, buttonHeight;
	float button1X, button2X;
};

static void ComputeLayout(Layout& l)
{
	GUI::SetFont(DIALOG_FONT_SCALE);

	float pad = GUI::ScreenHeight() * 0.02f;
	l.lineHeight = GUI::LineHeight();
	l.w = GUI::ScreenWidth() * 0.6f;
	l.titleHeight = l.lineHeight + pad * 2;
	l.buttonHeight = GUI::ScreenHeight() * 0.08f;
	l.buttonWidth = l.w * 0.3f;
	l.inputHeight = GUI::ScreenHeight() * 0.07f;
	l.rowHeight = l.lineHeight + pad;

	float content;
	if(IsList())
	{
		l.rows = ItemCount() < DIALOG_LIST_ROWS ? ItemCount() : DIALOG_LIST_ROWS;
		content = (FirstItem() ? l.lineHeight + pad : 0) + l.rows * l.rowHeight;
	}
	else
	{
		l.rows = 0;
		content = s_iLineCount * l.lineHeight;
		if(HasInput())
			content += pad + l.inputHeight;
	}

	l.h = l.titleHeight + pad + content + pad + l.buttonHeight + pad;
	if(l.h > GUI::ScreenHeight() * 0.95f)
		l.h = GUI::ScreenHeight() * 0.95f;

	l.x = (GUI::ScreenWidth() - l.w) / 2.0f;
	l.y = (GUI::ScreenHeight() - l.h) / 2.0f;

	l.bodyY = l.y + l.titleHeight + pad;
	l.listY = l.bodyY + (FirstItem() ? l.lineHeight + pad : 0);
	l.inputY = l.bodyY + s_iLineCount * l.lineHeight + pad;
	l.buttonY = l.y + l.h - pad - l.buttonHeight;

	if(s_szButton2[0])
	{
		l.button1X = l.x + l.w / 2.0f - pad / 2.0f - l.buttonWidth;
		l.button2X = l.x + l.w / 2.0f + pad / 2.0f;
	}
	else
	{
		l.button1X = l.x + (l.w - l.buttonWidth) / 2.0f;
		l.button2X = 0.0f;
	}
}

// Draws one tab-separated row in evenly spaced columns
static void DrawColumns(float x, float y, float width, const char* line, uint32_t rgba)
{
	int columns = 1;
	for(const char* p = line; *p; p++)
	{
		if(*p == '\t' && columns < DIALOG_MAX_COLUMNS)
			columns++;
	}

	float columnWidth = width / columns;
	char cell[256];
	const char* start = line;
	for(int i = 0; i < columns; i++)
	{
		const char* end = strchr(start, '\t');
		int len = end ? end - start : strlen(start);
		if(len > (int) sizeof(cell) - 1)
			len = sizeof(cell) - 1;
		memcpy(cell, start, len);
		cell[len] = 0;
		GUI::DrawText(x + i * columnWidth, y, cell, rgba);
		if(!end)
			break;
		start = end + 1;
	}
}

static void SendResponse(bool button1)
{
	int listItem = IsList() ? s_iSelected : -1;

	// Like the PC client, list responses send the item's first column as inputtext
	char text[KEYBOARD_MAX_INPUT + 1];
	if(IsList() && ItemCount() > 0)
	{
		const char* item = s_pLines[FirstItem() + s_iSelected];
		int len = strcspn(item, "\t");
		if(len > KEYBOARD_MAX_INPUT)
			len = KEYBOARD_MAX_INPUT;
		memcpy(text, item, len);
		text[len] = 0;
	}
	else
	{
		strcpy(text, s_szInput);
	}

	CNetGame::Instance()->SendDialogResponse(s_iID, button1 ? 1 : 0, listItem, text);
	CDialog::Hide();
}

static void OnInputSubmit(const char* text)
{
	strncpy(s_szInput, text, KEYBOARD_MAX_INPUT);
	s_szInput[KEYBOARD_MAX_INPUT] = 0;

	// "Send" on the keyboard answers the dialog, like pressing Enter on PC
	if(s_bOpen)
		SendResponse(true);
}

static void OpenInputKeyboard()
{
	CKeyboard::Open(OnInputSubmit, nullptr, s_iStyle == DIALOG_STYLE_PASSWORD, s_szInput);
}

void CDialog::Show(int id, int style, const char* title, const char* body, const char* button1, const char* button2)
{
	// A negative id hides the current dialog
	if(id < 0)
	{
		Hide();
		return;
	}

	s_iID = id;
	s_iStyle = style;
	strncpy(s_szTitle, title, sizeof(s_szTitle) - 1);
	s_szTitle[sizeof(s_szTitle) - 1] = 0;
	strncpy(s_szButton1, button1, sizeof(s_szButton1) - 1);
	s_szButton1[sizeof(s_szButton1) - 1] = 0;
	strncpy(s_szButton2, button2, sizeof(s_szButton2) - 1);
	s_szButton2[sizeof(s_szButton2) - 1] = 0;
	strncpy(s_szBody, body, DIALOG_MAX_BODY);
	s_szBody[DIALOG_MAX_BODY] = 0;
	memset(s_szInput, 0, sizeof(s_szInput));

	s_iLineCount = 0;
	char* line = s_szBody;
	while(line && s_iLineCount < DIALOG_MAX_LINES)
	{
		char* next = strchr(line, '\n');
		if(next)
			*next++ = 0;
		// Lists ignore a trailing empty line
		if(*line || !IsList() || next)
			s_pLines[s_iLineCount++] = line;
		line = next;
	}
	if(IsList() && s_iLineCount > 0 && s_pLines[s_iLineCount - 1][0] == 0)
		s_iLineCount--;

	s_iSelected = 0;
	s_iScroll = 0;
	s_iPressedPart = PART_NONE;
	s_iPressedPointer = -1;
	s_bOpen = true;

	CKeyboard::Close();

	log("Dialog %d (style %d): %s", id, style, s_szTitle);
}

void CDialog::Hide()
{
	s_bOpen = false;
	CKeyboard::Close();
}

bool CDialog::IsOpen()
{
	return s_bOpen;
}

void CDialog::Render()
{
	Layout l;
	ComputeLayout(l);
	float pad = GUI::ScreenHeight() * 0.02f;

	GUI::DrawRect(l.x, l.y, l.w, l.h, GUI_COLOR_PANEL);
	GUI::DrawRect(l.x, l.y, l.w, l.titleHeight, GUI_COLOR_TITLE);

	if(IsList())
	{
		for(int row = 0; row < l.rows; row++)
		{
			if(s_iScroll + row == s_iSelected)
				GUI::DrawRect(l.x + pad / 2, l.listY + row * l.rowHeight, l.w - pad, l.rowHeight, GUI_COLOR_SELECTED);
		}

		// Scroll bar when items overflow
		if(ItemCount() > l.rows && l.rows > 0)
		{
			float trackHeight = l.rows * l.rowHeight;
			float thumbHeight = trackHeight * l.rows / ItemCount();
			float thumbY = l.listY + (trackHeight - thumbHeight) * s_iScroll / (ItemCount() - l.rows);
			GUI::DrawRect(l.x + l.w - pad / 2, thumbY, pad / 4, thumbHeight, GUI_COLOR_GREY);
		}
	}
	else if(HasInput())
	{
		GUI::DrawRect(l.x + pad, l.inputY, l.w - pad * 2, l.inputHeight,
			s_iPressedPart == PART_INPUT ? GUI_COLOR_PRESSED : GUI_COLOR_FIELD);
	}

	GUI::DrawRect(l.button1X, l.buttonY, l.buttonWidth, l.buttonHeight,
		s_iPressedPart == PART_BUTTON1 ? GUI_COLOR_PRESSED : GUI_COLOR_BUTTON);
	if(s_szButton2[0])
	{
		GUI::DrawRect(l.button2X, l.buttonY, l.buttonWidth, l.buttonHeight,
			s_iPressedPart == PART_BUTTON2 ? GUI_COLOR_PRESSED : GUI_COLOR_BUTTON);
	}

	GUI::SetFont(DIALOG_FONT_SCALE);
	GUI::DrawText(l.x + pad, l.y + pad, s_szTitle, GUI_COLOR_WHITE);

	if(IsList())
	{
		if(FirstItem() && s_iLineCount > 0)
			DrawColumns(l.x + pad, l.bodyY, l.w - pad * 2, s_pLines[0], GUI_COLOR_GREY);

		for(int row = 0; row < l.rows; row++)
		{
			int item = s_iScroll + row;
			if(item >= ItemCount())
				break;
			float y = l.listY + row * l.rowHeight + pad / 2;
			DrawColumns(l.x + pad, y, l.w - pad * 2, s_pLines[FirstItem() + item], GUI_COLOR_WHITE);
		}
	}
	else
	{
		for(int i = 0; i < s_iLineCount; i++)
			GUI::DrawText(l.x + pad, l.bodyY + i * l.lineHeight, s_pLines[i], GUI_COLOR_GREY);

		if(HasInput())
		{
			char shown[KEYBOARD_MAX_INPUT + 1];
			int len = strlen(s_szInput);
			if(s_iStyle == DIALOG_STYLE_PASSWORD)
			{
				memset(shown, '*', len);
				shown[len] = 0;
			}
			else
			{
				strcpy(shown, s_szInput);
			}
			GUI::DrawText(l.x + pad * 1.5f, l.inputY + (l.inputHeight - l.lineHeight) / 2.0f,
				len ? shown : "Tap to type...", len ? GUI_COLOR_WHITE : GUI_COLOR_GREY);
		}
	}

	GUI::DrawText(l.button1X + (l.buttonWidth - GUI::TextWidth(s_szButton1)) / 2.0f,
		l.buttonY + (l.buttonHeight - l.lineHeight) / 2.0f, s_szButton1, GUI_COLOR_WHITE);
	if(s_szButton2[0])
	{
		GUI::DrawText(l.button2X + (l.buttonWidth - GUI::TextWidth(s_szButton2)) / 2.0f,
			l.buttonY + (l.buttonHeight - l.lineHeight) / 2.0f, s_szButton2, GUI_COLOR_WHITE);
	}
}

static int PartAt(const Layout& l, float x, float y)
{
	float pad = GUI::ScreenHeight() * 0.02f;

	if(GUI::Inside(x, y, l.button1X, l.buttonY, l.buttonWidth, l.buttonHeight))
		return PART_BUTTON1;
	if(s_szButton2[0] && GUI::Inside(x, y, l.button2X, l.buttonY, l.buttonWidth, l.buttonHeight))
		return PART_BUTTON2;
	if(HasInput() && GUI::Inside(x, y, l.x + pad, l.inputY, l.w - pad * 2, l.inputHeight))
		return PART_INPUT;
	if(IsList() && GUI::Inside(x, y, l.x, l.listY, l.w, l.rows * l.rowHeight))
		return PART_LIST;
	return PART_NONE;
}

bool CDialog::OnTouch(int type, int num, float x, float y)
{
	Layout l;
	ComputeLayout(l);

	if(type == TOUCH_PRESS)
	{
		s_iPressedPointer = num;
		s_iPressedPart = PartAt(l, x, y);
		s_fPressY = y;
		s_iPressScroll = s_iScroll;
		s_bDragged = false;
	}
	else if(num == s_iPressedPointer && type == TOUCH_MOVE)
	{
		// Drag to scroll long lists
		if(s_iPressedPart == PART_LIST && ItemCount() > l.rows)
		{
			int delta = (int) ((s_fPressY - y) / l.rowHeight);
			if(delta != 0)
				s_bDragged = true;

			int scroll = s_iPressScroll + delta;
			int maxScroll = ItemCount() - l.rows;
			s_iScroll = scroll < 0 ? 0 : (scroll > maxScroll ? maxScroll : scroll);
		}
	}
	else if(num == s_iPressedPointer && type == TOUCH_RELEASE)
	{
		int pressed = s_iPressedPart;
		s_iPressedPart = PART_NONE;
		s_iPressedPointer = -1;

		if(pressed != PartAt(l, x, y))
			return true;

		switch(pressed)
		{
			case PART_BUTTON1:
				SendResponse(true);
				break;

			case PART_BUTTON2:
				SendResponse(false);
				break;

			case PART_INPUT:
				OpenInputKeyboard();
				break;

			case PART_LIST:
				if(!s_bDragged)
				{
					int item = s_iScroll + (int) ((y - l.listY) / l.rowHeight);
					if(item >= 0 && item < ItemCount())
					{
						// Tapping the selected item again confirms it, like a double click on PC
						if(item == s_iSelected)
							SendResponse(true);
						else
							s_iSelected = item;
					}
				}
				break;
		}
	}

	// Dialogs are modal: the game never sees touches while one is open
	return true;
}
