#ifndef __CKEYBOARD_H__
#define __CKEYBOARD_H__

#define KEYBOARD_MAX_INPUT	128

// On-screen touch keyboard used by the chat and input dialogs
class CKeyboard
{
public:
	typedef void (*SubmitCallback)(const char* text);
	typedef void (*CancelCallback)();

	static void Open(SubmitCallback onSubmit, CancelCallback onCancel, bool masked, const char* initial = "");
	static void Close();
	static bool IsOpen();

	static void Render();
	static bool OnTouch(int type, int num, float x, float y);
};

#endif
