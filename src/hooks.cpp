#include <errno.h>
#include <GTASA.h>
#include "CNetGame.h"
#include "utils.h"
#include "CGUI.h"
#include "hook.h"

#define MAX_TOUCH_POINTERS	16

int CRunningScript__Process_hook(void* p)
{
	static bool l_bProcessed =	false;
	
	if(l_bProcessed == false)
	{
		l_bProcessed = true;
		log("first script tick: creating the local player");
		
		CNetGame* 	l_pNetGame = CNetGame::Instance();
		CPlayerPed*	l_pLocalPlayer = l_pNetGame->getPlayerPool()->GetLocalPlayer()->CreateGTAPlayer();
		log("local player ped %p", l_pLocalPlayer);
		
		// Teleport is the same CPed vtable slot in the 2.00 and 2.11.311 builds
		if(l_pLocalPlayer)
		{
			l_pLocalPlayer->Teleport(CVector(0.0f, 0.0f, 3.0f), 0);
			log("teleported");
		}
		
		CNetGame::Instance()->Connect();
		log("connecting");
	}
	
	CNetGame::Instance()->Process();
	
	return 0;
}

int CPopCycle__Update_hook()
{
	// we do nothing !
	return 0;
}

static void (*LoadingScreen_orig)(char const*, char const*, char const*) = nullptr;

void LoadingScreen_hook(char const* a1, char const* a2, char const* a3)
{
	log("LoadingScreen_hook(%s, %s, %s)", a1 ? a1 : "", a2 ? a2 : "", a3 ? a3 : "");
	
#if defined(__aarch64__)
	// 2.11 may do more here than draw, so let the game run its own loading screen
	if(LoadingScreen_orig)
	{
		LoadingScreen_orig(a1, a2, a3);
		return;
	}
#endif
	CLoadingScreen::NewChunkLoaded();
}

#define PrintLine(line, ...) \
{ \
	char Buffer[200]; \
	sprintf(Buffer, line, ##__VA_ARGS__); \
	GxtChar GxtCharBuffer[200]; \
	AsciiToGxtChar(Buffer, GxtCharBuffer); \
	CFont::PrintString(5.0f, 5.0f + l * CFont::GetHeight(false), GxtCharBuffer); \
	++l; \
}

unsigned int GetTickCount();
extern unsigned int lastOnFootSyncTick;
extern int g_iNetModeNormalOnfootSendRate;

// Debug overlay with the local player's position, enable with -DSAMP_DEBUG_OVERLAY
void RenderDebugOverlay()
{
	CPlayerPed* ped = FindPlayerPed(-1);
	if(!ped)
		return;
	
	CFont::SetFontStyle(1);
	CFont::SetBackground(0, 0);
	CFont::SetWrapx(500.0f);
	CFont::SetProportional(1);
	CFont::SetColor(CRGBA(0xFF, 0xFF, 0xFF, 0xFF));
	CFont::SetEdge(1);
	CFont::SetDropColor(CRGBA(0x00, 0x00, 0x00, 0xFF));
	CFont::SetScale(0.77);
	CFont::SetOrientation(1);
	
	float l = 0;
	PrintLine("X: %.1f Y: %.1f Z: %.1f A: %.1f", ped->m_Placement.pos.x, ped->m_Placement.pos.y, ped->m_Placement.pos.z, ped->m_Placement.angle);
	
	if (ped->m_pMatrix)
	{
		PrintLine("");
		PrintLine("right: X: %.1f Y: %.1f Z: %.1f", ped->m_pMatrix->m_RwMatrix.right.x, ped->m_pMatrix->m_RwMatrix.right.y, ped->m_pMatrix->m_RwMatrix.right.z);
		PrintLine("flags: %X", ped->m_pMatrix->m_RwMatrix.flags);
		PrintLine("up: X: %.1f Y: %.1f Z: %.1f", ped->m_pMatrix->m_RwMatrix.up.x, ped->m_pMatrix->m_RwMatrix.up.y, ped->m_pMatrix->m_RwMatrix.up.z);
		PrintLine("at: X: %.1f Y: %.1f Z: %.1f", ped->m_pMatrix->m_RwMatrix.at.x, ped->m_pMatrix->m_RwMatrix.at.y, ped->m_pMatrix->m_RwMatrix.at.z);
		PrintLine("pos: X: %.1f Y: %.1f Z: %.1f", ped->m_pMatrix->m_RwMatrix.pos.x, ped->m_pMatrix->m_RwMatrix.pos.y, ped->m_pMatrix->m_RwMatrix.pos.z);
	}
	
	// CPlayer * player = CNetGame::Instance()->getPlayerPool()->GetPlayer(1);
	// if (player)
	// {
		// PrintLine("");
		// PrintLine("X: %.1f Y: %.1f Z: %.1f", player->m_onFootSyncData.position.x, player->m_onFootSyncData.position.y, player->m_onFootSyncData.position.z);
	// }
	
	PrintLine("");
	PrintLine("Tick: %i, lastOnFootSyncTick: %i", GetTickCount(), lastOnFootSyncTick);
	PrintLine("g_iNetModeNormalOnfootSendRate: %i", g_iNetModeNormalOnfootSendRate);
}

#if defined(__aarch64__)
static void (*Render2dStuffAfterFade_orig)() = nullptr;

// Newer game builds draw more here (touch controls etc.), so run theirs and draw on top
void Render2dStuffAfterFade_hook()
{
	static bool first = true;
	if(first)
		log("first 2D render");
	Render2dStuffAfterFade_orig();
	GUI::Render();
	if(first)
		log("first UI frame drawn");
	first = false;
}
#else
void Render2dStuffAfterFade_hook()
{
	CHud::DrawAfterFade();
	TemporaryFPSVisualization();
	emu_GammaSet(1);
	CMessages::Display(0);
	CFont::RenderFontBuffer();
#ifdef SAMP_DEBUG_OVERLAY
	RenderDebugOverlay();
	CFont::RenderFontBuffer();
#endif
	GUI::Render();
	CCredits::Render();
	emu_GammaSet(0);
}
#endif

static void (*AND_TouchEvent_orig)(int, int, int, int) = nullptr;
static bool s_bTouchCaptured[MAX_TOUCH_POINTERS];

// Touches the UI accepts on press stay with the UI until release, so the game never sees half a gesture
void AND_TouchEvent_hook(int type, int num, int x, int y)
{
	bool captured = false;
	
	if(num >= 0 && num < MAX_TOUCH_POINTERS)
	{
		if(type == TOUCH_PRESS)
		{
			s_bTouchCaptured[num] = GUI::OnTouch(type, num, (float) x, (float) y);
			captured = s_bTouchCaptured[num];
		}
		else if(s_bTouchCaptured[num])
		{
			GUI::OnTouch(type, num, (float) x, (float) y);
			captured = true;
			if(type == TOUCH_RELEASE)
				s_bTouchCaptured[num] = false;
		}
	}
	
	if(!captured)
		AND_TouchEvent_orig(type, num, x, y);
}

// Address of a non-virtual member function (the first word of an ARM member pointer)
template<typename T> void* MemberAddress(T func)
{
	union { T func; void* addr; } u;
	u.func = func;
	return u.addr;
}

void InitHooks()
{
	// Remove script processing
	if(!InstallHook(MemberAddress(&CRunningScript::Process), (void *)(CRunningScript__Process_hook)))
		log("Failed to hook CRunningScript::Process");
	
	// Remove population spawning
	if(!InstallHook((void *)(CPopCycle::Update), (void *)(CPopCycle__Update_hook)))
		log("Failed to hook CPopCycle::Update");
	
	// Hook the loading screen function
	if(!InstallHook((void *)(LoadingScreen), (void *)(LoadingScreen_hook), (void **) &LoadingScreen_orig))
		log("Failed to hook LoadingScreen");
	
	// Hook render
#if defined(__aarch64__)
	if(!InstallHook((void *)(Render2dStuffAfterFade), (void *)(Render2dStuffAfterFade_hook), (void **) &Render2dStuffAfterFade_orig))
		log("Failed to hook Render2dStuffAfterFade, no UI");
#else
	InstallHook((void *)(Render2dStuffAfterFade), (void *)(Render2dStuffAfterFade_hook));
#endif
	
	// Touch input for chat and dialogs. This hook calls the original
	if(!InstallHook((void *) AND_TouchEvent, (void *) AND_TouchEvent_hook, (void **) &AND_TouchEvent_orig))
	{
		log("Failed to hook AND_TouchEvent, touch UI disabled");
	}
}