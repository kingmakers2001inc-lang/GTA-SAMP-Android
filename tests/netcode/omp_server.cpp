// Test server for tests/netcode/run.sh: open.mp RakNet and NetCode serializers, with the same connect checks as legacy_network_impl.cpp.
#include <raknet/RakNetworkFactory.h>
#include <raknet/RakServerInterface.h>
#include <raknet/RakPeer.h>
#include <raknet/PacketEnumerations.h>
#include "SAMPRakNet.hpp"
#include <packet.hpp>
#include <NetCode/core.hpp>
#include <NetCode/dialog.hpp>
#include <NetCode/class.hpp>
#include <ttmath/ttmath.h>
#include <cstdio>
#include <unistd.h>

using namespace RakNet;
static RakServerInterface* srv;
static int checks_passed = 0;
static int spawns = 0;
static bool dead = false;
static PlayerID client;

#define TOTAL_CHECKS 10

static void Check(bool ok, const char* what)
{
	printf("[server] %s %s\n", ok ? "PASS" : "FAIL", what);
	if (ok) checks_passed++;
}

// Query is only used for query packets; not exercised here
Span<const char> Query::handleQuery(Span<const char>, uint32_t, const sockaddr_in&, int) { return Span<const char>(); }

template <class T> static void Send(const T& pkt, PlayerID to)
{
	NetworkBitStream bs;
	pkt.write(bs);
	srv->RPC((RPCID)T::PacketID, (const char*)bs.GetData(), bs.GetNumberOfBitsUsed(), HIGH_PRIORITY, RELIABLE_ORDERED, 0, to, false, false, UNASSIGNED_NETWORK_ID, nullptr);
}

template <class T> static std::string Str(const T& h) { return std::string(h.data(), h.length()); }

static NetworkBitStream Bits(RPCParameters* p)
{
	NetworkBitStream bs(p->input, (p->numberOfBitsOfData + 7) / 8, false);
	bs.SetWriteOffset(p->numberOfBitsOfData);
	return bs;
}

static void OnPlayerConnect(RPCParameters* p, void*)
{
	auto* rs = srv->GetRemoteSystemFromPlayerID(p->sender);
	printf("[server] PlayerConnect RPC, authType=%d (1 = player auth key OK)\n", rs ? (int)rs->sampData.authType : -1);
	Check(rs && rs->sampData.authType == SAMPRakNet::AuthType_Player, "auth key");

	NetworkBitStream bs = Bits(p);
	NetCode::RPC::PlayerConnect c;
	if (!c.read(bs)) { printf("[server] FAIL: could not parse PlayerConnect\n"); return; }

	// Same serial check as legacy_network_impl.cpp
	ttmath::UInt<100> serial;
	ttmath::uint rem = 0;
	serial.FromString(std::string(c.Key.data(), c.Key.length()), 16);
	serial.DivInt(1001, rem);
	bool serialOk = rem == 0 && serial.ToString(16).size() < 50 && serial.ToString(16).size() != 0;
	bool versionOk = c.VersionNumber == 4057 && SAMPRakNet::GetToken() == (c.ChallengeResponse ^ 4057);
	printf("[server] name=%.*s version=%u (%.*s) serialOk=%d versionOk=%d\n", (int)c.Name.length(), c.Name.data(),
		c.VersionNumber, (int)c.VersionString.length(), c.VersionString.data(), serialOk, versionOk);
	Check(serialOk, "serial");
	Check(versionOk, "version and challenge");
	client = p->sender;
	if (!serialOk || !versionOk) return;

	NetCode::RPC::PlayerInit init {};
	init.LimitGlobalChatRadius = 200.0f;
	init.SetNameTagDrawDistance = 70.0f;
	init.PlayerID = 0;
	init.SetGravity = 0.008f;
	init.OnFootRate = 40;
	init.InCarRate = 40;
	init.WeaponRate = 40;
	init.Multiplier = 10;
	init.ServerName = "Grand RP test";
	Send(init, p->sender);

	NetCode::RPC::SendClientMessage msg;
	msg.Col = Colour::FromRGBA(0x33CCFFFF);
	msg.Message = "Welcome {FF0000}John{FFFFFF}, this is a colour test";
	Send(msg, p->sender);

	NetCode::RPC::ShowDialog dialog;
	dialog.ID = 2;
	dialog.Style = 3;
	dialog.Title = "Login";
	dialog.FirstButton = "Login";
	dialog.SecondButton = "Quit";
	dialog.Body = "{FFFFFF}Welcome back to {33CCFF}Grand RP{FFFFFF}!\n\nEnter your password:";
	Send(dialog, p->sender);
}

static void OnDialogResponse(RPCParameters* p, void*)
{
	NetworkBitStream bs = Bits(p);
	NetCode::RPC::OnPlayerDialogResponse r;
	bool ok = r.read(bs);
	printf("[server] DialogResponse ok=%d id=%d response=%d listitem=%d text='%.*s'\n", ok, r.ID, r.Response, r.ListItem, (int)r.Text.length(), r.Text.data());
	Check(ok && r.ID == 2 && r.Response == 1 && r.ListItem == -1 && Str(r.Text) == "secret123", "login dialog response");

	// Like grand_rp.pwn after a login: spawn info, then leave spectator mode
	NetCode::RPC::SetSpawnInfo info(false);
	info.TeamID = 255;
	info.ModelID = 26;
	info.Unknown1 = 0;
	info.Spawn = Vector3(1742.9f, -1861.6f, 13.6f);
	info.ZAngle = 90.0f;
	info.Weapons = { 0, 0, 0 };
	info.Ammos = { 0, 0, 0 };
	Send(info, p->sender);

	NetCode::RPC::TogglePlayerSpectating spec;
	spec.Enable = false;
	Send(spec, p->sender);
}

static void OnChat(RPCParameters* p, void*)
{
	NetworkBitStream bs = Bits(p);
	NetCode::RPC::PlayerRequestChatMessage m;
	bool ok = m.read(bs);
	printf("[server] Chat ok=%d '%.*s'\n", ok, (int)m.message.length(), m.message.data());
	Check(ok && Str(m.message) == "hello world", "chat message");

	NetCode::RPC::PlayerChatMessage echo;
	echo.PlayerID = 0;
	echo.message = m.message;
	Send(echo, p->sender);
}

static void OnCommand(RPCParameters* p, void*)
{
	NetworkBitStream bs = Bits(p);
	NetCode::RPC::PlayerRequestCommandMessage m;
	bool ok = m.read(bs);
	printf("[server] Command ok=%d '%.*s'\n", ok, (int)m.message.length(), m.message.data());
	Check(ok && Str(m.message) == "/stats", "command");
}

static void OnRequestClass(RPCParameters* p, void*)
{
	NetworkBitStream bs = Bits(p);
	NetCode::RPC::PlayerRequestClass req;
	Check(req.read(bs) && req.Classid == 0, "class request after InitGame");

	// grand_rp.pwn: not logged in yet, so spectate until the login dialog is answered
	NetCode::RPC::TogglePlayerSpectating spec;
	spec.Enable = true;
	Send(spec, p->sender);

	NetCode::RPC::PlayerRequestClassResponse resp(255, 26, 0, Vector3(1742.9f, -1861.6f, 13.6f), 0.0f);
	resp.IsDL = false;
	resp.Selectable = true;
	resp.Unknown1 = 0;
	resp.Weapons = { 0, 0, 0 };
	resp.Ammos = { 0, 0, 0 };
	Send(resp, p->sender);
}

static void OnRequestSpawn(RPCParameters* p, void*)
{
	printf("[server] RequestSpawn (dead=%d)\n", dead);
	NetCode::RPC::PlayerRequestSpawnResponse resp;
	resp.Allow = dead ? 1 : 0;
	Send(resp, p->sender);
}

static void OnSpawn(RPCParameters* p, void*)
{
	spawns++;
	printf("[server] Spawn #%d\n", spawns);
	if (spawns == 1)
	{
		Check(true, "spawn after leaving spectator mode");
		// grand_rp.pwn OnPlayerSpawn sends these
		NetCode::RPC::ResetPlayerMoney reset;
		Send(reset, p->sender);
		NetCode::RPC::GivePlayerMoney money;
		money.Money = 5000;
		Send(money, p->sender);
		NetCode::RPC::SetPlayerSkin skin;
		skin.isDL = false;
		skin.PlayerID = 0;
		skin.Skin = 280;
		Send(skin, p->sender);
	}
	else if (spawns == 2)
	{
		Check(dead, "respawn after death");
		dead = false;
	}
}

static void OnDeath(RPCParameters* p, void*)
{
	NetworkBitStream bs = Bits(p);
	NetCode::RPC::OnPlayerDeath d;
	bool ok = d.read(bs);
	Check(ok && d.KillerID == 0xFFFF, "death report");
	dead = true;
}

int main()
{
	SAMPRakNet::Init(nullptr);
	SAMPRakNet::SeedToken();
	srv = RakNetworkFactory::GetRakServerInterface();
	srv->SetMTUSize(512);
	srv->RegisterAsRemoteProcedureCall(25, OnPlayerConnect, nullptr);
	srv->RegisterAsRemoteProcedureCall(62, OnDialogResponse, nullptr);
	srv->RegisterAsRemoteProcedureCall(101, OnChat, nullptr);
	srv->RegisterAsRemoteProcedureCall(50, OnCommand, nullptr);
	srv->RegisterAsRemoteProcedureCall(128, OnRequestClass, nullptr);
	srv->RegisterAsRemoteProcedureCall(129, OnRequestSpawn, nullptr);
	srv->RegisterAsRemoteProcedureCall(52, OnSpawn, nullptr);
	srv->RegisterAsRemoteProcedureCall(53, OnDeath, nullptr);
	if (!srv->Start(10, 0, 5, 7777, "127.0.0.1")) { printf("[server] start failed\n"); return 1; }
	SAMPRakNet::SetPort(7777);
	SAMPRakNet::SeedCookie();
	printf("[server] listening on 7777\n");
	fflush(stdout);

	for (int t = 0; t < 1500; t++)
	{
		for (Packet* pkt = srv->Receive(); pkt; pkt = srv->Receive())
		{
			printf("[server] packet %d\n", pkt->data[0]);
			srv->DeallocatePacket(pkt);
		}
		if (checks_passed >= TOTAL_CHECKS) { printf("[server] ALL %d CHECKS PASSED\n", checks_passed); fflush(stdout); usleep(300000); return 0; }
		fflush(stdout);
		usleep(10000);
	}
	printf("[server] TIMEOUT, %d/%d checks passed\n", checks_passed, TOTAL_CHECKS);
	return 2;
}
