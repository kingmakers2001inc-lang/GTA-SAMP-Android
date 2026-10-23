#ifndef __CDIALOG_H__
#define __CDIALOG_H__

#define DIALOG_STYLE_MSGBOX				0
#define DIALOG_STYLE_INPUT				1
#define DIALOG_STYLE_LIST				2
#define DIALOG_STYLE_PASSWORD			3
#define DIALOG_STYLE_TABLIST			4
#define DIALOG_STYLE_TABLIST_HEADERS	5

#define DIALOG_MAX_BODY		4096

// SA-MP ShowPlayerDialog window
class CDialog
{
public:
	static void Show(int id, int style, const char* title, const char* body, const char* button1, const char* button2);
	static void Hide();
	static bool IsOpen();

	static void Render();
	static bool OnTouch(int type, int num, float x, float y);
};

#endif
