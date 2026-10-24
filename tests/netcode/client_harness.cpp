// Client harness for tests/netcode/run.sh: the real CNetGame/RPC/CChat/CDialog/CKeyboard code with engine drawing stubbed.
// Draw calls are recorded so the test can tap on-screen labels like a finger would.
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <string>
#include <vector>

#include "CNetGame.h"
#include "CGUI.h"
#include "CChat.h"
#include "CDialog.h"
#include "CKeyboard.h"
#include "CScript.h"

std::vector<std::string> g_ChatLines;
static void Capture(const char* line) { if(!strncmp(line, "[CHAT] ", 7)) g_ChatLines.push_back(line + 7); }

int log(const char* format, ...)
{
	va_list args;
	va_start(args, format);
	printf("[client] ");
	char buf[1024]; int r = vsnprintf(buf, sizeof(buf), format, args); printf("%s", buf); Capture(buf);
	printf("\n");
	va_end(args);
	return r;
}

// --- Engine-side stubs --------------------------------------------------------
CPlayer::CPlayer() {}
CPlayer::~CPlayer() { delete [] m_pszNickName; }
void CPlayer::setNickName(char* name) { delete [] m_pszNickName; m_pszNickName = new char[strlen(name) + 1]; strcpy(m_pszNickName, name); }
void CPlayer::setNPC(bool) {}
void CPlayer::ProcessPlayerSync(Packet*) {}
void CPlayer::StreamIn(RPCParameters*) {}

// Engine calls made by CLocalPlayer::CreateGTAPlayer
static char g_FakePed[4096];
int CStreaming::RequestSpecialModel(int, const char*, int) { return 0; }
int CStreaming::LoadAllRequestedModels(bool) { return 0; }
signed char CWorld::PlayerInFocus = 0;
void CPlayerPed::SetupPlayerPed(int) {}
CPlayerPed* FindPlayerPed(int) { return (CPlayerPed*) g_FakePed; }
void CClothes::RebuildPlayer(CPlayerPed*, bool) {}

// Script opcodes are recorded instead of run; is_char_dead answers from g_bDead
struct Opcode { unsigned short op; std::vector<double> args; };
static std::vector<Opcode> g_Opcodes;
static bool g_bDead = false;
static int g_iMoney = 0;

bool ScriptCommand(unsigned short opcode, const char* format, ...)
{
	Opcode rec { opcode, {} };
	va_list args;
	va_start(args, format);
	for(const char* f = format; *f; f++)
	{
		if(*f == 'i') rec.args.push_back(va_arg(args, int));
		else if(*f == 'f') rec.args.push_back(va_arg(args, double));
		else if(*f == 'v')
		{
			int* out = va_arg(args, int*);
			*out = (opcode == OP_GET_PLAYER_CHAR) ? 1 : g_iMoney;
		}
	}
	va_end(args);
	
	if(opcode == OP_ADD_SCORE) g_iMoney += (int) rec.args[1];
	if(opcode != OP_IS_CHAR_DEAD) g_Opcodes.push_back(rec);
	return opcode == OP_IS_CHAR_DEAD && g_bDead;
}

// Last recorded call of an opcode, or nullptr
static const Opcode* Last(unsigned short op)
{
	for(int i = g_Opcodes.size() - 1; i >= 0; i--)
		if(g_Opcodes[i].op == op) return &g_Opcodes[i];
	return nullptr;
}

static int g_iClientFailures = 0;
static void ClientCheck(bool ok, const char* what)
{
	printf("[client] %s %s\n", ok ? "PASS" : "FAIL", what);
	if(!ok) g_iClientFailures++;
}

// --- GUI stubs: 1920x1080, fixed-width font ------------------------------------
struct Label { std::string text; float x, y, w, h; };
static std::vector<Label> g_Labels;

float GUI::ScreenWidth() { return 1920.0f; }
float GUI::ScreenHeight() { return 1080.0f; }
float GUI::Scale() { return 1.0f; }
void GUI::SetFont(float) {}
float GUI::LineHeight() { return 30.0f; }
float GUI::TextWidth(const char* text) { return strlen(text) * 14.0f; }
void GUI::DrawRect(float, float, float, float, uint32_t) {}
void GUI::DrawText(float x, float y, const char* text, uint32_t) { g_Labels.push_back({text, x, y, TextWidth(text), LineHeight()}); }
void GUI::Flush() {}
bool GUI::Inside(float px, float py, float x, float y, float w, float h) { return px >= x && px <= x + w && py >= y && py <= y + h; }
bool GUI::OnTouch(int type, int num, float x, float y)
{
	if(CKeyboard::IsOpen()) return CKeyboard::OnTouch(type, num, x, y);
	if(CDialog::IsOpen()) return CDialog::OnTouch(type, num, x, y);
	return CChat::OnTouch(type, num, x, y);
}
void GUI::Render()
{
	g_Labels.clear();
	CChat::Render();
	if(CDialog::IsOpen()) CDialog::Render();
	if(CKeyboard::IsOpen()) CKeyboard::Render();
}

// Taps the centre of the most recently drawn label with this exact text
static bool Tap(const char* text)
{
	GUI::Render();
	for(int i = g_Labels.size() - 1; i >= 0; i--)
	{
		const Label& l = g_Labels[i];
		if(l.text == text)
		{
			float x = l.x + l.w / 2, y = l.y + l.h / 2;
			GUI::OnTouch(TOUCH_PRESS, 0, x, y);
			GUI::OnTouch(TOUCH_RELEASE, 0, x, y);
			return true;
		}
	}
	printf("[client] FAIL: no '%s' on screen\n", text);
	return false;
}

static void Type(const char* text)
{
	for(const char* p = text; *p; p++)
	{
		char key[2] = { *p, 0 };
		Tap(key);
	}
}

static void Pump(int ms)
{
	for(int i = 0; i < ms / 10; i++)
	{
		CNetGame::Instance()->Process();
		usleep(10000);
	}
}

int main()
{
	CNetGame* net = CNetGame::Instance();
	strcpy(net->m_szNickName, "John_Smith");
	net->getPlayerPool()->GetLocalPlayer()->CreateGTAPlayer();
	net->Connect();
	
	// Wait for the login dialog
	for(int i = 0; i < 500 && !CDialog::IsOpen(); i++) Pump(10);
	if(!CDialog::IsOpen()) { printf("[client] FAIL: no dialog received\n"); return 1; }
	
	GUI::Render();
	bool hasTitle = false, hasBody = false;
	for(auto& l : g_Labels)
	{
		if(l.text == "Login") hasTitle = true;
		if(l.text.find("Enter your password:") != std::string::npos) hasBody = true;
	}
	printf("[client] dialog rendered: title=%d body=%d\n", hasTitle, hasBody);
	
	// Tap the password field, type on the touch keyboard, press Send
	Tap("Tap to type...");
	printf("[client] keyboard open=%d\n", CKeyboard::IsOpen());
	Type("secret123");
	Tap("Send");
	printf("[client] dialog closed=%d\n", !CDialog::IsOpen());
	Pump(500);
	
	CLocalPlayer* local = net->getPlayerPool()->GetLocalPlayer();
	const Opcode* coords = Last(OP_SET_CHAR_COORDINATES);
	const Opcode* model = Last(OP_SET_PLAYER_MODEL);
	const Opcode* control = Last(OP_SET_PLAYER_CONTROL);
	ClientCheck(local->IsSpawned(), "spawned after login");
	ClientCheck(coords && coords->args.size() == 4 && (int) coords->args[1] == 1742 && (int) coords->args[2] == -1861, "placed at the server spawn point");
	ClientCheck(model && (int) model->args[1] == 280, "skin from SetPlayerSkin applied");
	ClientCheck(control && control->args[1] == 1, "player control enabled");
	ClientCheck(g_iMoney == 5000, "money reset then set to 5000");
	
	// Chat: open with the Chat button, send a message and a command
	Tap("Chat");
	Type("hello");
	Tap("space");
	Type("world");
	Tap("Send");
	Pump(300);
	
	Tap("Chat");
	Tap("?123");
	Tap("/");
	Tap("abc");
	Type("stats");
	Tap("Send");
	Pump(1000);
	
	// Die, then let the "engine" revive the ped: the client must report and respawn
	g_bDead = true;
	Pump(300);
	g_bDead = false;
	Pump(1000);
	ClientCheck(local->IsSpawned(), "spawned again after death");
	
	printf("[client] chat window:\n");
	for(auto& line : g_ChatLines) printf("    | %s\n", line.c_str());
	return g_iClientFailures ? 1 : 0;
}
