#include <thread>
#include <stdio.h>
#include <string.h>
#include <string>
#include <sys/time.h>
#include <time.h>
#include <stdlib.h>

#include "CNetGame.h"
#include "RPC.h"
#include "AuthTable.h"
#include "utils.h"
#include "CChat.h"

CNetGame* CNetGame::m_SingletonInstance = nullptr;

CNetGame::CNetGame()
{
	m_rakClientInterface = RakNetworkFactory::GetRakClientInterface();	
	RegisterRPCs(m_rakClientInterface);	
	
	m_PlayerPool = new CPlayerPool();
	
	// Seeds the random input of the connection serial, otherwise every phone sends the same one
	srand(time(nullptr));
	
	LoadSettings();
}

CNetGame::~CNetGame()
{
	RakNetworkFactory::DestroyRakClientInterface(m_rakClientInterface);
	
	if(m_PlayerPool)
	{
		delete m_PlayerPool;
		m_PlayerPool = nullptr;
	}
}

// Defaults baked into the library. tools/make_apk.py finds the magic and rewrites the
// fields, so a server can ship an APK that already points at it.
struct DefaultSettings
{
	char magic[16];
	char host[64];
	char port[8];
	char name[25];
};
extern "C" __attribute__((used)) volatile DefaultSettings g_DefaultSettings =
	{ "SAMP_DEFAULTS_1", "127.0.0.1", "7777", "Android_Player" };

static void CopyField(char* dest, const volatile char* src, size_t size)
{
	size_t i = 0;
	for(; i < size - 1 && src[i]; i++)
		dest[i] = src[i];
	dest[i] = 0;
}

// Name of this app's package, from /proc/self/cmdline
static bool GetPackageName(char* out, size_t size)
{
	FILE* f = fopen("/proc/self/cmdline", "r");
	if(!f)
		return false;
	
	bool ok = fgets(out, size, f) != nullptr;
	fclose(f);
	
	// Strip a ":process" suffix
	if(ok)
		out[strcspn(out, ":")] = 0;
	return ok && out[0];
}

static FILE* OpenSettingsFile(char* path, size_t size)
{
	// The game's own data folder is readable on every Android version; /sdcard/SAMP needs legacy storage
	char package[128];
	if(GetPackageName(package, sizeof(package)))
	{
		snprintf(path, size, "/sdcard/Android/data/%s/files/SAMP/settings.ini", package);
		if(FILE* f = fopen(path, "r"))
			return f;
	}
	
	snprintf(path, size, "%s", SAMP_SETTINGS_FILE);
	return fopen(path, "r");
}

void CNetGame::LoadSettings()
{
	char port[8];
	CopyField(m_szHost, g_DefaultSettings.host, sizeof(m_szHost));
	CopyField(port, g_DefaultSettings.port, sizeof(port));
	CopyField(m_szNickName, g_DefaultSettings.name, sizeof(m_szNickName));
	m_usPort = (unsigned short) atoi(port);
	
	// Optional override file, one "key=value" per line: host, port, name
	char path[256];
	FILE* f = OpenSettingsFile(path, sizeof(path));
	if(!f)
	{
		log("No settings.ini, using built-in server %s:%d", m_szHost, m_usPort);
		return;
	}
	log("Reading %s", path);
	
	char line[128];
	while(fgets(line, sizeof(line), f))
	{
		line[strcspn(line, "\r\n")] = 0;
		char* value = strchr(line, '=');
		if(!value)
			continue;
		*value++ = 0;
		
		if(!strcmp(line, "host"))
			strncpy(m_szHost, value, sizeof(m_szHost) - 1);
		else if(!strcmp(line, "port"))
			m_usPort = (unsigned short) atoi(value);
		else if(!strcmp(line, "name") && strlen(value) >= 3)
			strncpy(m_szNickName, value, sizeof(m_szNickName) - 1);
	}
	fclose(f);
}

void CNetGame::Connect()
{
	log("Connecting to %s:%d as %s", m_szHost, m_usPort, m_szNickName);
	CChat::AddInfoMessage("Connecting to %s:%d...", m_szHost, m_usPort);
	m_rakClientInterface->Connect(m_szHost, m_usPort, 0, 0, 0);
}

unsigned int GetTickCount()
{
	struct timeval tv;
	if(gettimeofday(&tv, NULL) != 0)
		return 0;

	return (tv.tv_sec * 1000) + (tv.tv_usec / 1000);
}

unsigned int lastOnFootSyncTick = 0;
extern int g_iNetModeNormalOnfootSendRate;

void CNetGame::Process()
{
	Packet* pPacket = 0;
	while((pPacket = m_rakClientInterface->Receive()))
	{
		int packetId = pPacket->data[0];
		log("Packet received -> %d\n", packetId);
		
		switch(packetId)
		{
			case ID_DISCONNECTION_NOTIFICATION: CChat::AddInfoMessage("Server closed the connection."); m_isInGame = false; break;
			case ID_CONNECTION_LOST: CChat::AddInfoMessage("Lost connection to the server."); m_isInGame = false; break;
			case ID_CONNECTION_BANNED: CChat::AddInfoMessage("You are banned from this server."); break;
			case ID_NO_FREE_INCOMING_CONNECTIONS: CChat::AddInfoMessage("The server is full."); break;
			case ID_INVALID_PASSWORD: CChat::AddInfoMessage("Wrong server password."); break;
			case ID_MODIFIED_PACKET: log("Modified packet!"); break;
			case ID_CONNECTION_ATTEMPT_FAILED: CChat::AddInfoMessage("Could not connect to %s:%d", m_szHost, m_usPort); break;
			case ID_CONNECTION_REQUEST_ACCEPTED: log("Request accepted!"); Packet_ConnectionSucceeded(pPacket); break;
			case ID_AUTH_KEY: log("Auth key!"); Packet_AUTH_KEY(pPacket); break;
			case ID_PLAYER_SYNC: log("PlayerSync packet!"); m_PlayerPool->ProcessPlayerSync(pPacket); break;
		}
	
		m_rakClientInterface->DeallocatePacket(pPacket);	
	}
	
	if (m_isInGame)
		m_PlayerPool->GetLocalPlayer()->Process();
	
	// The server ignores sync from players that haven't spawned
	if (m_isInGame && m_PlayerPool->GetLocalPlayer()->IsSpawned() && g_iNetModeNormalOnfootSendRate > 0 && lastOnFootSyncTick < (GetTickCount() - g_iNetModeNormalOnfootSendRate))
	{
		DoSync();
		
		lastOnFootSyncTick = GetTickCount();
	}
}


RakClientInterface* CNetGame::getRakInterface()
{
	return m_rakClientInterface;
}

CPlayerPool* CNetGame::getPlayerPool()
{
	return m_PlayerPool;
}

void CNetGame::Packet_AUTH_KEY(Packet *p)
{
	const char* auth_key = "";
	unsigned char byteAuthKeyLen = 0;

	for (unsigned int i = 0; i < sizeof(AuthKeyTable) / sizeof(AuthKeyTable[0]); ++i)
	{
		if (strcmp((char*) (p->data + 2), AuthKeyTable[i][0]) == 0)
		{
			auth_key = AuthKeyTable[i][1];
			byteAuthKeyLen = strlen(auth_key);
			break;
		}
	}
	
	RakNet::BitStream bsKey;
	bsKey.Write((unsigned char)ID_AUTH_KEY);
	bsKey.Write(byteAuthKeyLen);
	bsKey.Write(auth_key, byteAuthKeyLen);

	log("AUTH_KEY IN = %s; OUT = %s", (char*) (p->data + 2), auth_key);

	m_rakClientInterface->Send(&bsKey, SYSTEM_PRIORITY, RELIABLE, NULL);
}

#define SEND_RPC(networkObject, functionName, packet) { int rpcid = (RPC_##functionName); (networkObject)->RPC(&rpcid, &packet, HIGH_PRIORITY, RELIABLE, 0, FALSE, UNASSIGNED_NETWORK_ID, NULL); }
#include <ttmathuint.h>
#include <ttmathuint_x86.h>
#include <stdlib.h>


bool GenerateSerial(char* input, char** output, int* output_len, int key)
{
	// Hash the input with SHA-1
	CSHA1 raksha;
	raksha.Update((unsigned char *) input, strlen(input));
	raksha.Final();
	unsigned char sha_hash_bin[20];
	raksha.GetHash(sha_hash_bin);
	
	// Convert binary hash to string
	char sha_hash[41];
	for (int i = 0; i < sizeof(sha_hash_bin); ++i)
		sprintf(sha_hash + i * 2, "%02X", sha_hash_bin[i]);

	log("GenerateSerial() -> Hashed input: %s", sha_hash);

	// The server accepts any serial that is a multiple of 1001
	ttmath::UInt<100> math;
	math.FromString(sha_hash, 16);
	math.MulInt(key);
	std::string result = math.ToString(16);
	
	*output_len = result.length();
	*output = new char[*output_len + 1];
	strcpy(*output, result.c_str());
	return true;
}

void gen_random(char *s, const int len)
{
	static const char alphanum[] =
		"0123456789"
		"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		"abcdefghijklmnopqrstuvwxyz";

	for (int i = 0; i < len; ++i)
		s[i] = alphanum[rand() % (sizeof(alphanum) - 1)];

	s[len] = 0;
}

float* RwMatrixToQuaternion(RwMatrix matrix)
{
#define m00 matrix.right.x
#define m01 matrix.right.y
#define m02 matrix.right.z

#define m10 matrix.up.x
#define m11 matrix.up.y
#define m12 matrix.up.z

#define m20 matrix.at.x
#define m21 matrix.at.y
#define m22 matrix.at.z

	float sum;
	
	sum = 1 + m00 + m11 + m22;
	if (sum < 0.0f)
		sum = 0.0f;
	float qw = sqrt(sum) / 2.0f;
	
	sum = 1 + m00 - m11 - m22;
	if (sum < 0.0f)
		sum = 0.0f;
	float qx = sqrt(sum) / 2.0f;

	sum = 1 - m00 + m11 - m22;
	if (sum < 0.0f)
		sum = 0.0f;
	float qy = sqrt(sum) / 2.0f;

	sum = 1 - m00 - m11 + m22;
	if (sum < 0.0f)
		sum = 0.0f;
	float qz = sqrt(sum) / 2.0f;

	if (qw < 0.0)
		qw = 0.0;

	if (qx < 0.0)
		qx = 0.0;

	if (qy < 0.0)
		qy = 0.0;

	if (qz < 0.0)
		qz = 0.0;

	qx = copysign(qx, m21 - m12);
	qy = copysign(qy, m02 - m20);
	qz = copysign(qz, m10 - m01);

	float* ret = new float[4];
	
	ret[0] = qw;
	ret[1] = qx;
	ret[2] = qy;
	ret[3] = qz;
	
	return ret;
}

void CNetGame::DoSync()
{
	CPlayerPed* ped = getPlayerPool()->GetLocalPlayer()->GetGTAPlayer();
	if(ped && ped->m_pMatrix)
	{
		ON_FOOT_SYNC_t syncData;
		memset(&syncData, 0, sizeof(ON_FOOT_SYNC_t));
		
		syncData.health = 100;
		
		float* asd = RwMatrixToQuaternion(ped->m_pMatrix->m_RwMatrix);
		memcpy(syncData.quaterRotation, asd, 4 * sizeof(float));
		delete [] asd;
		
		syncData.position.x = ped->m_pMatrix->m_RwMatrix.pos.x;
		syncData.position.y = ped->m_pMatrix->m_RwMatrix.pos.y;
		syncData.position.z = ped->m_pMatrix->m_RwMatrix.pos.z;
		
		RakNet::BitStream bsPlayerSync;
		bsPlayerSync.Write((BYTE) ID_PLAYER_SYNC);
		bsPlayerSync.Write((char *) &syncData, sizeof(ON_FOOT_SYNC_t));
		m_rakClientInterface->Send(&bsPlayerSync, HIGH_PRIORITY, UNRELIABLE_SEQUENCED, 0);
	}
}

void CNetGame::SendChatMessage(const char* a_szText)
{
	RakNet::BitStream bsSend;
	BYTE byteLen = (BYTE) strlen(a_szText);
	bsSend.Write(byteLen);
	bsSend.Write(a_szText, byteLen);
	SEND_RPC(m_rakClientInterface, Chat, bsSend);
}

void CNetGame::SendCommand(const char* a_szCommand)
{
	RakNet::BitStream bsSend;
	uint32_t len = strlen(a_szCommand);
	bsSend.Write(len);
	bsSend.Write(a_szCommand, len);
	SEND_RPC(m_rakClientInterface, ServerCommand, bsSend);
}

void CNetGame::SendDialogResponse(int a_iDialogID, int a_iButton, int a_iListItem, const char* a_szInput)
{
	RakNet::BitStream bsSend;
	BYTE byteLen = (BYTE) strlen(a_szInput);
	bsSend.Write((int16_t) a_iDialogID);
	bsSend.Write((BYTE) a_iButton);
	bsSend.Write((int16_t) a_iListItem);
	bsSend.Write(byteLen);
	bsSend.Write(a_szInput, byteLen);
	SEND_RPC(m_rakClientInterface, DialogResponse, bsSend);
}

void CNetGame::SendRequestClass(int a_iClassID)
{
	RakNet::BitStream bsSend;
	bsSend.Write((uint16_t) a_iClassID);
	SEND_RPC(m_rakClientInterface, RequestClass, bsSend);
}

void CNetGame::SendRequestSpawn()
{
	RakNet::BitStream bsSend;
	SEND_RPC(m_rakClientInterface, RequestSpawn, bsSend);
}

void CNetGame::SendSpawn()
{
	RakNet::BitStream bsSend;
	SEND_RPC(m_rakClientInterface, Spawn, bsSend);
}

void CNetGame::SendDeath(int a_iReason, int a_iKillerID)
{
	RakNet::BitStream bsSend;
	bsSend.Write((BYTE) a_iReason);
	bsSend.Write((uint16_t) a_iKillerID);
	SEND_RPC(m_rakClientInterface, Death, bsSend);
}

void CNetGame::Packet_ConnectionSucceeded(Packet *p)
{
	RakNet::BitStream bsSuccAuth((unsigned char *)p->data, p->length, false);

	bsSuccAuth.IgnoreBits(8); // ID_CONNECTION_REQUEST_ACCEPTED
	bsSuccAuth.IgnoreBits(32); // binaryAddress
	bsSuccAuth.IgnoreBits(16); // port

	unsigned short myPlayerID;
	bsSuccAuth.Read(myPlayerID);

	// g_myPlayerID = myPlayerID;
	// playerInfo[myPlayerID].iIsConnected = 1;
	// strcpy(playerInfo[myPlayerID].szPlayerName, g_szNickName);

	unsigned int uiChallenge;
	bsSuccAuth.Read(uiChallenge);

	// settings.uiChallange = uiChallenge;

	log("Connected. Joining the game...");

	RakNet::BitStream bsSend;

	int iVersion = SAMP_NETCODE_VERSION;
	bsSend.Write(iVersion);
	
	BYTE byteMod = 1;
	bsSend.Write(byteMod);
	
	BYTE byteNameLen = (BYTE) strlen(m_szNickName);
	bsSend.Write(byteNameLen);
	bsSend.Write(m_szNickName, byteNameLen);
	
	unsigned int uiClientChallengeResponse = uiChallenge ^ iVersion;
	bsSend.Write(uiClientChallengeResponse);
	
	char fucku[129];
	gen_random(fucku, 128);
	char* auth_bs;
	int AuthBSLen;
	GenerateSerial(fucku, &auth_bs, &AuthBSLen, 0x3E9);
	log("Serial: %s", auth_bs);
	bsSend.Write((BYTE) AuthBSLen);
	bsSend.Write(auth_bs, AuthBSLen);
	
	char szClientVer[] = SAMP_VERSION_STRING;
	const BYTE iClientVerLen = (sizeof(szClientVer)-1);
	bsSend.Write(iClientVerLen);
	bsSend.Write(szClientVer, iClientVerLen);


	SEND_RPC(m_rakClientInterface, ClientJoin, bsSend);
	delete[] auth_bs;	
}
