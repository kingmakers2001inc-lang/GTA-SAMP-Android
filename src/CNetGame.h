#ifndef __CNETGAME_H__
#define __CNETGAME_H__

#include <RakClient.h>
#include <RakNetworkFactory.h>
#include <PacketEnumerations.h>
#include <StringCompressor.h>

#include "CPlayerPool.h"

#define SAMP_SETTINGS_FILE		"/sdcard/SAMP/settings.ini"

// open.mp only accepts 0.3.7 (4057) and 0.3DL (4062) clients
#define SAMP_NETCODE_VERSION	4057
#define SAMP_VERSION_STRING		"0.3.7"

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
	
	void SendChatMessage(const char* a_szText);
	void SendCommand(const char* a_szCommand);
	void SendDialogResponse(int a_iDialogID, int a_iButton, int a_iListItem, const char* a_szInput);
	
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