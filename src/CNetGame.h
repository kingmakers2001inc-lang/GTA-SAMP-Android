#ifndef __CNETGAME_H__
#define __CNETGAME_H__

#include <RakClient.h>
#include <RakNetworkFactory.h>
#include <PacketEnumerations.h>
#include <StringCompressor.h>

#include "CPlayerPool.h"

#define SAMP_SETTINGS_FILE		"/sdcard/SAMP/settings.ini"

class CNetGame
{
/*private*/public: //TODO!!!
	static CNetGame*		m_SingletonInstance;
	RakClientInterface* 	m_rakClientInterface = nullptr;
	CPlayerPool*			m_PlayerPool = nullptr;
	bool					m_isInGame = false;
	
	char					m_szHost[64] = "127.0.0.1";
	unsigned short			m_usPort = 7777;
	char					m_szNickName[25] = "Android_Player";
	
public:
	CNetGame();
	~CNetGame();

	void LoadSettings();
	void Connect();
	void Process();
	
	/* Packets */
	void Packet_AUTH_KEY(Packet *p);
	void Packet_ConnectionSucceeded(Packet *p);
	
	RakClientInterface* getRakInterface();
	CPlayerPool*		getPlayerPool();
	
	void DoSync();
	
	static CNetGame* Instance()
	{
		if(m_SingletonInstance == nullptr)
		{
			m_SingletonInstance = new CNetGame();
		}
		return m_SingletonInstance;
	}
};

#endif