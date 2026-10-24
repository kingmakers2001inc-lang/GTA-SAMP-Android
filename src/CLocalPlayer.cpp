#include "CLocalPlayer.h"
#include "CNetGame.h"
#include "CScript.h"
#include "RPC.h"
#include "utils.h"

#define PLAYER_INDEX	0

CLocalPlayer::CLocalPlayer()
{
	
}

CLocalPlayer::~CLocalPlayer()
{
	if(m_GTAPlayerPed)
	{
		/*TODO: Remove the PlayerPed */ 
		m_GTAPlayerPed = nullptr;
	}
}


CPlayerPed* CLocalPlayer::CreateGTAPlayer()
{
	CStreaming::RequestSpecialModel(0, "player", 26);
	CStreaming::LoadAllRequestedModels(true);
	log("player model loaded");
	
	CWorld::PlayerInFocus = 0;
	CPlayerPed::SetupPlayerPed(CWorld::PlayerInFocus);
	log("player ped set up");
	
	m_GTAPlayerPed = FindPlayerPed(-1);
	CClothes::RebuildPlayer(m_GTAPlayerPed, false);
	log("player clothes rebuilt");
	return m_GTAPlayerPed;
}

CPlayerPed* CLocalPlayer::GetGTAPlayer()
{
	return m_GTAPlayerPed;
}

int CLocalPlayer::GetScriptHandle()
{
	if(m_iScriptHandle == -1 && m_GTAPlayerPed)
		ScriptCommand(OP_GET_PLAYER_CHAR, "iv", PLAYER_INDEX, &m_iScriptHandle);
	return m_iScriptHandle;
}

void CLocalPlayer::SetSpawnInfo(const SpawnInfo& a_SpawnInfo)
{
	m_SpawnInfo = a_SpawnInfo;
	m_bHasSpawnInfo = true;
}

void CLocalPlayer::SetSpectating(bool a_bSpectating)
{
	if(a_bSpectating)
	{
		m_bSpectating = true;
		m_bSpawned = false;
		SetControllable(false);
		return;
	}
	
	// Leaving spectator mode spawns the player, like the PC client
	if(m_bSpectating)
	{
		m_bSpectating = false;
		Spawn();
	}
}

void CLocalPlayer::OnClassResponse(bool a_bSelectable, const SpawnInfo& a_SpawnInfo)
{
	if(!a_bSelectable)
		return;
	
	SetSpawnInfo(a_SpawnInfo);
	
	// There is no class selection screen yet: ask to spawn with the offered class.
	// Servers that gate spawning (login first) put us in spectator mode instead.
	if(!m_bSpectating && !m_bSpawned)
		CNetGame::Instance()->SendRequestSpawn();
}

void CLocalPlayer::OnSpawnResponse(unsigned int a_uiAllow)
{
	m_bWaitingForSpawn = false;
	
	// 1 = request accepted, 2 = server-side SpawnPlayer()
	if(a_uiAllow)
		Spawn();
}

void CLocalPlayer::Spawn()
{
	if(!m_GTAPlayerPed || !m_bHasSpawnInfo)
	{
		log("Spawn() without ped or spawn info");
		return;
	}
	
	m_bSpectating = false;
	m_bDead = false;
	
	SetInterior(0);
	SetSkin(m_SpawnInfo.skin);
	SetHealth(100.0f);
	SetPosition(m_SpawnInfo.position);
	SetHeading(m_SpawnInfo.angle);
	SetControllable(true);
	CameraBehind();
	
	m_bSpawned = true;
	CNetGame::Instance()->SendSpawn();
	log("Spawned at %.1f %.1f %.1f (skin %d)", m_SpawnInfo.position.x, m_SpawnInfo.position.y, m_SpawnInfo.position.z, m_SpawnInfo.skin);
}

void CLocalPlayer::Process()
{
	if(!m_bSpawned || !m_GTAPlayerPed)
		return;
	
	int handle = GetScriptHandle();
	if(handle == -1)
		return;
	
	bool dead = ScriptCommand(OP_IS_CHAR_DEAD, "i", handle);
	
	if(dead && !m_bDead)
	{
		m_bDead = true;
		CNetGame::Instance()->SendDeath(255, 0xFFFF);
	}
	else if(!dead && m_bDead && !m_bWaitingForSpawn)
	{
		// The engine revived the ped after the wasted screen: ask the server where to spawn
		m_bWaitingForSpawn = true;
		CNetGame::Instance()->SendRequestSpawn();
	}
}

void CLocalPlayer::SetPosition(const CVector& a_Position)
{
	int handle = GetScriptHandle();
	if(handle != -1)
		ScriptCommand(OP_SET_CHAR_COORDINATES, "ifff", handle, a_Position.x, a_Position.y, a_Position.z);
}

void CLocalPlayer::SetHeading(float a_fAngle)
{
	int handle = GetScriptHandle();
	if(handle != -1)
		ScriptCommand(OP_SET_CHAR_HEADING, "if", handle, a_fAngle);
}

void CLocalPlayer::SetSkin(int a_iSkin)
{
	if(a_iSkin < 0 || a_iSkin > 311)
		return;
	
	ScriptCommand(OP_REQUEST_MODEL, "i", a_iSkin);
	ScriptCommand(OP_LOAD_ALL_MODELS_NOW, "");
	ScriptCommand(OP_SET_PLAYER_MODEL, "ii", PLAYER_INDEX, a_iSkin);
	ScriptCommand(OP_MARK_MODEL_NOT_NEEDED, "i", a_iSkin);
}

void CLocalPlayer::SetHealth(float a_fHealth)
{
	int handle = GetScriptHandle();
	if(handle != -1)
		ScriptCommand(OP_SET_CHAR_HEALTH, "ii", handle, (int) a_fHealth);
}

void CLocalPlayer::SetInterior(int a_iInterior)
{
	int handle = GetScriptHandle();
	ScriptCommand(OP_SET_AREA_VISIBLE, "i", a_iInterior);
	if(handle != -1)
		ScriptCommand(OP_SET_CHAR_AREA_VISIBLE, "ii", handle, a_iInterior);
}

void CLocalPlayer::SetControllable(bool a_bControllable)
{
	ScriptCommand(OP_SET_PLAYER_CONTROL, "ii", PLAYER_INDEX, a_bControllable ? 1 : 0);
}

void CLocalPlayer::GiveMoney(int a_iAmount)
{
	ScriptCommand(OP_ADD_SCORE, "ii", PLAYER_INDEX, a_iAmount);
}

void CLocalPlayer::ResetMoney()
{
	int money = 0;
	ScriptCommand(OP_STORE_SCORE, "iv", PLAYER_INDEX, &money);
	if(money)
		GiveMoney(-money);
}

void CLocalPlayer::CameraBehind()
{
	ScriptCommand(OP_SET_CAMERA_BEHIND_PLAYER, "");
	ScriptCommand(OP_RESTORE_CAMERA_JUMPCUT, "");
}
