#ifndef __CLOCALPLAYER_H__
#define __CLOCALPLAYER_H__

#include "types.h"
#include <GTASA.h>

struct SpawnInfo
{
	unsigned char	team;
	int				skin;
	CVector			position;
	float			angle;
	int				weapons[3];
	int				ammo[3];
};

class CLocalPlayer
{
private:
	CPlayerPed*		m_GTAPlayerPed = nullptr;
	int				m_iScriptHandle = -1;
	
	SpawnInfo		m_SpawnInfo;
	bool			m_bHasSpawnInfo = false;
	bool			m_bSpectating = false;
	bool			m_bSpawned = false;
	bool			m_bDead = false;
	bool			m_bWaitingForSpawn = false;
	
public:
	CLocalPlayer();
	~CLocalPlayer();

	CPlayerPed*			CreateGTAPlayer();
	CPlayerPed* 		GetGTAPlayer();
	
	void				SetSpawnInfo(const SpawnInfo& a_SpawnInfo);
	void				SetSpectating(bool a_bSpectating);
	bool				IsSpectating() { return m_bSpectating; }
	bool				IsSpawned() { return m_bSpawned; }
	
	// Places the ped at the spawn point and tells the server we spawned
	void				Spawn();
	// Death detection and respawn requests, called every frame
	void				Process();
	// Class response or spawn permission from the server
	void				OnClassResponse(bool a_bSelectable, const SpawnInfo& a_SpawnInfo);
	void				OnSpawnResponse(unsigned int a_uiAllow);
	
	// Engine helpers driven by server RPCs
	int					GetScriptHandle();
	void				SetPosition(const CVector& a_Position);
	void				SetHeading(float a_fAngle);
	void				SetSkin(int a_iSkin);
	void				SetHealth(float a_fHealth);
	void				SetInterior(int a_iInterior);
	void				SetControllable(bool a_bControllable);
	void				GiveMoney(int a_iAmount);
	void				ResetMoney();
	void				CameraBehind();
};

#endif
