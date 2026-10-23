#ifndef __RPC_H__
#define __RPC_H__

enum
{
	RPC_SetPlayerPos = 12,
	RPC_SetPlayerHealth = 14,
	RPC_TogglePlayerControllable = 15,
	RPC_GivePlayerMoney = 18,
	RPC_SetPlayerFacingAngle = 19,
	RPC_ResetPlayerMoney = 20,
	RPC_ClientJoin = 25,
	RPC_ServerCommand = 50,
	RPC_Spawn = 52,
	RPC_Death = 53,
	RPC_DialogResponse = 62,
	RPC_SetSpawnInfo = 68,
	RPC_TogglePlayerSpectating = 124,
	RPC_RequestClass = 128,
	RPC_RequestSpawn = 129,
	RPC_SetPlayerSkin = 153,
	RPC_SetPlayerInterior = 156,
	RPC_SetCameraBehindPlayer = 162,
	RPC_WorldPlayerAdd = 32,
	RPC_ScrPlayAudioStream = 41,
	RPC_ScrDialogBox = 61,
	RPC_ScrGameText = 73,
	RPC_ScrInitMenu = 76,
	RPC_ClientMessage = 93,
	RPC_Chat = 101,
	RPC_ConnectionRejected = 130,
	RPC_ServerJoin = 137,
	RPC_ServerQuit,
	RPC_InitGame,
	RPC_UpdateScoresPingsIPs = 155,
	RPC_WorldPlayerRemove = 163,
	RPC_WorldVehicleAdd,
	RPC_WorldVehicleRemove,
	RPC_WorldPlayerDeath,
};

void ServerJoin(RPCParameters *rpcParams);
void ServerQuit(RPCParameters *rpcParams);
void InitGame(RPCParameters *rpcParams);
void WorldPlayerAdd(RPCParameters *rpcParams);
void WorldPlayerDeath(RPCParameters *rpcParams);
void WorldPlayerRemove(RPCParameters *rpcParams);
void WorldVehicleAdd(RPCParameters *rpcParams);
void WorldVehicleRemove(RPCParameters *rpcParams);
void ConnectionRejected(RPCParameters *rpcParams);
void ClientMessage(RPCParameters *rpcParams);
void Chat(RPCParameters *rpcParams);
void UpdateScoresPingsIPs(RPCParameters *rpcParams);
void ScrInitMenu(RPCParameters *rpcParams);
void ScrDialogBox(RPCParameters *rpcParams);
void ScrGameText(RPCParameters *rpcParams);
void ScrPlayAudioStream(RPCParameters *rpcParams);
void SetSpawnInfo(RPCParameters *rpcParams);
void TogglePlayerSpectating(RPCParameters *rpcParams);
void RequestClass(RPCParameters *rpcParams);
void RequestSpawn(RPCParameters *rpcParams);
void SetPlayerPos(RPCParameters *rpcParams);
void SetPlayerFacingAngle(RPCParameters *rpcParams);
void SetPlayerSkin(RPCParameters *rpcParams);
void SetPlayerHealth(RPCParameters *rpcParams);
void SetPlayerInterior(RPCParameters *rpcParams);
void TogglePlayerControllable(RPCParameters *rpcParams);
void GivePlayerMoney(RPCParameters *rpcParams);
void ResetPlayerMoney(RPCParameters *rpcParams);
void SetCameraBehindPlayer(RPCParameters *rpcParams);
void RegisterRPCs(RakClientInterface *pRakClient);


#endif