/*
 * Grand RP - roleplay gamemode for open.mp (works with SA-MP Android clients)
 *
 * Features:
 *   - Firstname_Lastname names, register/login dialogs, SQLite accounts
 *   - Levels, experience and hourly paycheck
 *   - Proximity chat and RP commands (/me /do /b /s /w)
 *   - Bank with deposit/withdraw/transfer
 *   - Jobs: trucker, taxi driver, mechanic and pizza delivery
 *   - Factions: LSPD and medics, with ranks, duty and radio chat
 *   - Gangs: Grove Street and Ballas, with turfs on the map and turf wars (/capture)
 *   - Houses: buy, sell, lock and enter, created in-game by admins
 *   - Phone: every character has a number for /call and /sms
 *   - Car dealership with personal, saved and lockable vehicles
 *   - Admin levels and basic moderation tools
 */

#include <open.mp>

// Salted SHA-256 keeps the gamemode plugin free; switch to the bcrypt plugin before going public
#pragma warning disable 234

#define SERVER_NAME             "Grand RP"
#define DB_FILE                 "grand_rp.db"

#define MAX_PASSWORD_LEN        64
#define MIN_PASSWORD_LEN        6
#define MAX_LOGIN_ATTEMPTS      3
#define PAYDAY_INTERVAL         (60 * 60 * 1000)
#define START_MONEY             5000
#define START_BANK              10000
#define MAX_OWNED_VEHICLES      3

#define CHAT_RANGE              20.0
#define SHOUT_RANGE             40.0
#define WHISPER_RANGE           3.0

#define COLOR_WHITE             0xFFFFFFFF
#define COLOR_GREY              0xAFAFAFFF
#define COLOR_ERROR             0xFF6347FF
#define COLOR_INFO              0x33CCFFFF
#define COLOR_SUCCESS           0x9ACD32FF
#define COLOR_PURPLE            0xC2A2DAFF
#define COLOR_RADIO             0x8D8DFFFF
#define COLOR_ADMIN             0xFFA500FF
#define COLOR_OOC               0xE6E6E6FF

#define DIALOG_REGISTER         1
#define DIALOG_LOGIN            2
#define DIALOG_DEALERSHIP       3
#define DIALOG_HELP             4

#define MAX_HOUSES              200
#define HOUSE_VW_BASE           1000
#define PHONE_BASE              100000
#define TURF_CAPTURE_TIME       120
#define TURF_COOLDOWN           600
#define TURF_REWARD             2000

#define JOB_NONE                0
#define JOB_TRUCKER             1
#define JOB_TAXI                2
#define JOB_MECHANIC            3
#define JOB_PIZZA               4
#define MAX_JOBS                5

#define FACTION_NONE            0
#define FACTION_LSPD            1
#define FACTION_MEDIC           2
#define FACTION_GROVE           3
#define FACTION_BALLAS          4
#define MAX_FACTIONS            5
#define MAX_RANK                6

// Locations
#define SPAWN_X                 1742.9
#define SPAWN_Y                 -1861.6
#define SPAWN_Z                 13.6
#define SPAWN_A                 0.0

#define BANK_X                  1481.0
#define BANK_Y                  -1771.0
#define BANK_Z                  18.8

#define JOBS_X                  1366.0
#define JOBS_Y                  -1279.0
#define JOBS_Z                  13.5

#define DEALER_X                557.0
#define DEALER_Y                -1285.0
#define DEALER_Z                17.2

#define DEALER_SPAWN_X          545.0
#define DEALER_SPAWN_Y          -1268.0
#define DEALER_SPAWN_Z          17.0
#define DEALER_SPAWN_A          215.0

#define TRUCK_DEPOT_X           2211.0
#define TRUCK_DEPOT_Y           -2240.0
#define TRUCK_DEPOT_Z           13.5

#define GARAGE_X                2063.0
#define GARAGE_Y                -1831.0
#define GARAGE_Z                13.5

#define PIZZA_X                 2105.5
#define PIZZA_Y                 -1806.5
#define PIZZA_Z                 13.5

enum E_PLAYER
{
    pID,
    pPassHash[65],
    pSalt[17],
    pAdmin,
    pLevel,
    pExp,
    pMoney,
    pBank,
    pSkin,
    pJob,
    pFaction,
    pRank,
    Float:pPosX,
    Float:pPosY,
    Float:pPosZ,
    Float:pPosA,
    pInterior,
    pVW,
    // Session only
    bool:pLoggedIn,
    pLoginAttempts,
    bool:pOnDuty,
    pDeliveryStage,
    pDeliveryRoute,
    pFareRate,
    pCallPartner,               // playerid + 1 of the other phone, 0 when not calling
    bool:pCallActive,
    bool:pCallRinging           // someone is calling this player
};
new Player[MAX_PLAYERS][E_PLAYER];

enum E_OWNED_VEHICLE
{
    ovDBID,
    ovOwner,
    ovModel,
    bool:ovLocked
};
new OwnedVehicle[MAX_VEHICLES][E_OWNED_VEHICLE];

enum E_DEALER_CAR
{
    dcModel,
    dcName[24],
    dcPrice
};
new const DealerCars[][E_DEALER_CAR] =
{
    {462, "Faggio",    4000},
    {404, "Perennial", 12000},
    {418, "Moonbeam",  15000},
    {426, "Premier",   28000},
    {579, "Huntley",   45000},
    {560, "Sultan",    75000},
    {411, "Infernus",  180000}
};

enum E_ROUTE
{
    rtName[32],
    Float:rtX,
    Float:rtY,
    Float:rtZ,
    rtPay
};
new const TruckRoutes[][E_ROUTE] =
{
    {"Los Santos Market",  1145.0, -1366.0, 13.5, 900},
    {"Las Venturas Strip", 2105.0, 1003.0,  10.8, 2600},
    {"San Fierro Docks",  -1732.0,  103.0,   3.5, 2900},
    {"Montgomery Farm",    1310.0,  275.0,  19.5, 1600},
    {"Angel Pine",        -2145.0, -2453.0, 30.6, 2200}
};

new const PizzaRoutes[][E_ROUTE] =
{
    {"Grove Street",       2495.0, -1680.0, 13.3, 450},
    {"Unity Station",      1772.0, -1900.0, 13.5, 350},
    {"Jefferson Motel",    2228.0, -1159.0, 25.8, 550},
    {"Glen Park",          1968.0, -1180.0, 20.0, 500},
    {"Idlewood gas station", 1940.0, -1772.0, 13.4, 300},
    {"East Los Santos",    2440.0, -1300.0, 24.0, 600}
};

new const FactionNames[MAX_FACTIONS][] =
    {"Civilian", "Los Santos Police", "Los Santos Medics", "Grove Street Families", "Ballas"};
new const FactionRanks[MAX_FACTIONS][MAX_RANK + 1][16] =
{
    {"", "", "", "", "", "", ""},
    {"", "Cadet", "Officer", "Sergeant", "Lieutenant", "Captain", "Chief"},
    {"", "Intern", "Paramedic", "Doctor", "Surgeon", "Head Doctor", "Director"},
    {"", "Youngster", "Hustler", "Homie", "Soldier", "OG", "Big Smoke"},
    {"", "Youngster", "Hustler", "Thug", "Soldier", "OG", "Ballas King"}
};
new const FactionSkins[MAX_FACTIONS] = {0, 280, 274, 105, 102};
new const FactionColours[MAX_FACTIONS] = {0xFFFFFF00, 0x0000FFFF, 0xFF8282FF, 0x00C000FF, 0xC000C0FF};
new const JobNames[MAX_JOBS][] = {"Unemployed", "Trucker", "Taxi driver", "Mechanic", "Pizza delivery"};

enum E_HOUSE_INTERIOR
{
    hiName[16],
    hiInterior,
    Float:hiX,
    Float:hiY,
    Float:hiZ
};
new const HouseInteriors[][E_HOUSE_INTERIOR] =
{
    {"Small",   1, 223.20, 1287.08, 1082.14},
    {"Medium",  3, 2496.05, -1692.08, 1014.74},
    {"Large",   8, 2365.31, -1135.60, 1050.88},
    {"Villa",   9, 2317.89, -1026.76, 1050.22},
    {"Mansion", 5, 140.17, 1366.07, 1083.86}
};

enum E_HOUSE
{
    hDBID,
    hOwner,                     // account id, 0 when for sale
    hOwnerName[MAX_PLAYER_NAME + 1],
    hPrice,
    hType,
    Float:hX,
    Float:hY,
    Float:hZ,
    bool:hLocked,
    hPickup,                    // pickup id + 1, 0 when none
    Text3D:hLabel,
    bool:hHasLabel
};
new House[MAX_HOUSES][E_HOUSE];

enum E_TURF
{
    tName[24],
    Float:tMinX,
    Float:tMinY,
    Float:tMaxX,
    Float:tMaxY,
    tDefaultOwner
};
new const Turfs[][E_TURF] =
{
    {"Grove Street",  2380.0, -1730.0, 2540.0, -1620.0, FACTION_GROVE},
    {"Ganton Gym",    2200.0, -1780.0, 2340.0, -1650.0, FACTION_GROVE},
    {"Idlewood",      1960.0, -1800.0, 2160.0, -1650.0, FACTION_GROVE},
    {"Jefferson",     2040.0, -1340.0, 2240.0, -1100.0, FACTION_BALLAS},
    {"East Los Santos", 2380.0, -1400.0, 2600.0, -1200.0, FACTION_BALLAS},
    {"Glen Park",     1860.0, -1300.0, 2040.0, -1130.0, FACTION_BALLAS}
};
new TurfOwner[sizeof Turfs], TurfZone[sizeof Turfs], TurfAttacker[sizeof Turfs], TurfTimeLeft[sizeof Turfs],
    TurfCooldown[sizeof Turfs];

new DB:gDB;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

stock PlayerName(playerid)
{
    new name[MAX_PLAYER_NAME + 1];
    GetPlayerName(playerid, name, sizeof name);
    return name;
}

// Name without the underscore, used in RP chat
stock RPName(playerid)
{
    new name[MAX_PLAYER_NAME + 1];
    GetPlayerName(playerid, name, sizeof name);
    for (new i = 0; name[i] != EOS; i++)
    {
        if (name[i] == '_') name[i] = ' ';
    }
    return name;
}

stock bool:IsValidRPName(const name[])
{
    new len = strlen(name), underscore = -1;
    if (len < 5) return false;
    for (new i = 0; i < len; i++)
    {
        if (name[i] == '_')
        {
            if (underscore != -1) return false;
            underscore = i;
        }
        else if (!(('a' <= name[i] <= 'z') || ('A' <= name[i] <= 'Z')))
        {
            return false;
        }
    }
    if (underscore < 2 || underscore > len - 3) return false;
    if (!('A' <= name[0] <= 'Z') || !('A' <= name[underscore + 1] <= 'Z')) return false;
    return true;
}

// Splits the next whitespace separated token off a command string
stock strtok(const string[], &index)
{
    new length = strlen(string);
    while ((index < length) && (string[index] <= ' ')) index++;

    new offset = index, result[64];
    while ((index < length) && (string[index] > ' ') && ((index - offset) < (sizeof(result) - 1)))
    {
        result[index - offset] = string[index];
        index++;
    }
    result[index - offset] = EOS;
    return result;
}

// Remainder of a command string after the current index
stock strrest(const string[], &index)
{
    new length = strlen(string);
    while ((index < length) && (string[index] <= ' ')) index++;

    new result[128];
    strmid(result, string, index, length, sizeof result);
    return result;
}

stock bool:IsNumeric(const string[])
{
    if (string[0] == EOS) return false;
    for (new i = 0; string[i] != EOS; i++)
    {
        if (!('0' <= string[i] <= '9')) return false;
    }
    return true;
}

// Accepts a player id or the start of a player name
stock FindPlayer(const input[])
{
    if (input[0] == EOS) return INVALID_PLAYER_ID;
    if (IsNumeric(input))
    {
        new id = strval(input);
        if (IsPlayerConnected(id)) return id;
        return INVALID_PLAYER_ID;
    }
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (IsPlayerConnected(i) && strfind(PlayerName(i), input, true) == 0) return i;
    }
    return INVALID_PLAYER_ID;
}

stock SendError(playerid, const message[])
{
    new msg[144];
    format(msg, sizeof msg, "[Error] {FFFFFF}%s", message);
    return SendClientMessage(playerid, COLOR_ERROR, msg);
}

stock SendUsage(playerid, const usage[])
{
    new msg[144];
    format(msg, sizeof msg, "[Usage] {FFFFFF}%s", usage);
    return SendClientMessage(playerid, COLOR_GREY, msg);
}

stock SendNearbyMessage(playerid, Float:range, colour, const message[])
{
    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);
    new vw = GetPlayerVirtualWorld(playerid);
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (IsPlayerConnected(i) && Player[i][pLoggedIn] && GetPlayerVirtualWorld(i) == vw
            && IsPlayerInRangeOfPoint(i, range, x, y, z))
        {
            SendClientMessage(i, colour, message);
        }
    }
}

stock SendFactionMessage(factionid, colour, const message[])
{
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (IsPlayerConnected(i) && Player[i][pLoggedIn] && Player[i][pFaction] == factionid)
        {
            SendClientMessage(i, colour, message);
        }
    }
}

stock SendAdminMessage(colour, const message[])
{
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (IsPlayerConnected(i) && Player[i][pAdmin] > 0) SendClientMessage(i, colour, message);
    }
}

// Money is tracked server side; the client display is only a mirror
stock GiveMoney(playerid, amount)
{
    Player[playerid][pMoney] += amount;
    ResetPlayerMoney(playerid);
    GivePlayerMoney(playerid, Player[playerid][pMoney]);
}

stock ExpForNextLevel(playerid)
{
    return Player[playerid][pLevel] * 4;
}

stock GenerateSalt(salt[], size = sizeof salt)
{
    for (new i = 0; i < size - 1; i++) salt[i] = 'a' + random(26);
    salt[size - 1] = EOS;
}

stock bool:IsGang(faction)
{
    return faction == FACTION_GROVE || faction == FACTION_BALLAS;
}

stock PhoneNumber(playerid)
{
    return PHONE_BASE + Player[playerid][pID];
}

stock FindPhone(number)
{
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (IsPlayerConnected(i) && Player[i][pLoggedIn] && PhoneNumber(i) == number) return i;
    }
    return INVALID_PLAYER_ID;
}

stock bool:CheckAdmin(playerid, level)
{
    if (Player[playerid][pAdmin] >= level) return true;
    SendError(playerid, "You are not authorized to use this command.");
    return false;
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

stock InitDatabase()
{
    gDB = DB_Open(DB_FILE);
    if (gDB == DB:0)
    {
        print("[Grand RP] Could not open the database!");
        return;
    }

    DB_FreeResultSet(DB_ExecuteQuery(gDB, "PRAGMA journal_mode = WAL"));
    DB_FreeResultSet(DB_ExecuteQuery(gDB,
        "CREATE TABLE IF NOT EXISTS accounts (\
            id INTEGER PRIMARY KEY AUTOINCREMENT,\
            name TEXT NOT NULL UNIQUE COLLATE NOCASE,\
            hash TEXT NOT NULL, salt TEXT NOT NULL,\
            admin INTEGER DEFAULT 0, level INTEGER DEFAULT 1, exp INTEGER DEFAULT 0,\
            money INTEGER DEFAULT 0, bank INTEGER DEFAULT 0, skin INTEGER DEFAULT 26,\
            job INTEGER DEFAULT 0, faction INTEGER DEFAULT 0, rank INTEGER DEFAULT 0,\
            x REAL DEFAULT 0, y REAL DEFAULT 0, z REAL DEFAULT 0, a REAL DEFAULT 0,\
            interior INTEGER DEFAULT 0, vw INTEGER DEFAULT 0,\
            registered INTEGER DEFAULT (strftime('%%s','now')))"));
    DB_FreeResultSet(DB_ExecuteQuery(gDB,
        "CREATE TABLE IF NOT EXISTS vehicles (\
            id INTEGER PRIMARY KEY AUTOINCREMENT,\
            owner INTEGER NOT NULL REFERENCES accounts(id),\
            model INTEGER NOT NULL,\
            x REAL, y REAL, z REAL, a REAL,\
            colour1 INTEGER DEFAULT 1, colour2 INTEGER DEFAULT 1)"));
    DB_FreeResultSet(DB_ExecuteQuery(gDB,
        "CREATE TABLE IF NOT EXISTS bans (\
            name TEXT PRIMARY KEY COLLATE NOCASE, reason TEXT, admin TEXT,\
            date INTEGER DEFAULT (strftime('%%s','now')))"));
    DB_FreeResultSet(DB_ExecuteQuery(gDB,
        "CREATE TABLE IF NOT EXISTS houses (\
            id INTEGER PRIMARY KEY AUTOINCREMENT,\
            owner INTEGER DEFAULT 0, price INTEGER NOT NULL, type INTEGER DEFAULT 0,\
            x REAL, y REAL, z REAL, locked INTEGER DEFAULT 1)"));
    DB_FreeResultSet(DB_ExecuteQuery(gDB,
        "CREATE TABLE IF NOT EXISTS turfs (id INTEGER PRIMARY KEY, owner INTEGER NOT NULL)"));
    print("[Grand RP] Database ready.");
}

stock SavePlayer(playerid)
{
    if (!Player[playerid][pLoggedIn]) return;

    if (GetPlayerState(playerid) != PLAYER_STATE_WASTED && GetPlayerState(playerid) != PLAYER_STATE_NONE)
    {
        GetPlayerPos(playerid, Player[playerid][pPosX], Player[playerid][pPosY], Player[playerid][pPosZ]);
        GetPlayerFacingAngle(playerid, Player[playerid][pPosA]);
        Player[playerid][pInterior] = GetPlayerInterior(playerid);
        Player[playerid][pVW] = GetPlayerVirtualWorld(playerid);
    }

    DB_FreeResultSet(DB_ExecuteQuery(gDB,
        "UPDATE accounts SET admin=%d, level=%d, exp=%d, money=%d, bank=%d, skin=%d, job=%d, faction=%d, rank=%d,\
         x=%f, y=%f, z=%f, a=%f, interior=%d, vw=%d WHERE id=%d",
        Player[playerid][pAdmin], Player[playerid][pLevel], Player[playerid][pExp],
        Player[playerid][pMoney], Player[playerid][pBank], Player[playerid][pSkin],
        Player[playerid][pJob], Player[playerid][pFaction], Player[playerid][pRank],
        Player[playerid][pPosX], Player[playerid][pPosY], Player[playerid][pPosZ], Player[playerid][pPosA],
        Player[playerid][pInterior], Player[playerid][pVW], Player[playerid][pID]));
}

stock LoadPlayerVehicles(playerid)
{
    new DBResult:result = DB_ExecuteQuery(gDB,
        "SELECT id, model, x, y, z, a, colour1, colour2 FROM vehicles WHERE owner=%d", Player[playerid][pID]);
    if (!result) return;

    if (DB_GetRowCount(result))
    {
        do
        {
            new vehicleid = CreateVehicle(DB_GetFieldIntByName(result, "model"),
                DB_GetFieldFloatByName(result, "x"), DB_GetFieldFloatByName(result, "y"),
                DB_GetFieldFloatByName(result, "z"), DB_GetFieldFloatByName(result, "a"),
                DB_GetFieldIntByName(result, "colour1"), DB_GetFieldIntByName(result, "colour2"), -1);
            if (vehicleid == INVALID_VEHICLE_ID) continue;

            OwnedVehicle[vehicleid][ovDBID] = DB_GetFieldIntByName(result, "id");
            OwnedVehicle[vehicleid][ovOwner] = Player[playerid][pID];
            OwnedVehicle[vehicleid][ovModel] = DB_GetFieldIntByName(result, "model");
            OwnedVehicle[vehicleid][ovLocked] = true;
            SetVehicleParamsEx(vehicleid, false, false, false, true, false, false, false);
            SetVehicleNumberPlate(vehicleid, "GRAND");
        }
        while (DB_SelectNextRow(result));
    }
    DB_FreeResultSet(result);
}

stock UnloadPlayerVehicles(playerid)
{
    for (new v = 1; v < MAX_VEHICLES; v++)
    {
        if (OwnedVehicle[v][ovDBID] && OwnedVehicle[v][ovOwner] == Player[playerid][pID])
        {
            DestroyVehicle(v);
            OwnedVehicle[v][ovDBID] = 0;
            OwnedVehicle[v][ovOwner] = 0;
        }
    }
}

stock CountOwnedVehicles(playerid)
{
    new DBResult:result = DB_ExecuteQuery(gDB, "SELECT COUNT(*) FROM vehicles WHERE owner=%d", Player[playerid][pID]);
    new count = DB_GetFieldInt(result, 0);
    DB_FreeResultSet(result);
    return count;
}

// ---------------------------------------------------------------------------
// Houses
// ---------------------------------------------------------------------------

stock RefreshHouse(h)
{
    if (House[h][hPickup]) DestroyPickup(House[h][hPickup] - 1);
    House[h][hPickup] = CreatePickup(House[h][hOwner] ? 1272 : 1273, 1, House[h][hX], House[h][hY], House[h][hZ], 0) + 1;

    new text[160];
    if (House[h][hOwner])
    {
        format(text, sizeof text, "{33CCFF}%s house\n{FFFFFF}Owner: %s\n%s\n{AFAFAF}/enter",
            HouseInteriors[House[h][hType]][hiName], House[h][hOwnerName], House[h][hLocked] ? "{FF6347}Locked" : "{9ACD32}Open");
    }
    else
    {
        format(text, sizeof text, "{9ACD32}House for sale\n{FFFFFF}%s - $%d\n{AFAFAF}/buyhouse  /enter to look inside",
            HouseInteriors[House[h][hType]][hiName], House[h][hPrice]);
    }
    if (!House[h][hHasLabel])
    {
        House[h][hLabel] = Create3DTextLabel(text, COLOR_WHITE, House[h][hX], House[h][hY], House[h][hZ] + 0.7, 15.0, 0, true);
        House[h][hHasLabel] = true;
    }
    else
    {
        Update3DTextLabelText(House[h][hLabel], COLOR_WHITE, text);
    }
}

stock LoadHouses()
{
    new DBResult:result = DB_ExecuteQuery(gDB,
        "SELECT h.id, h.owner, h.price, h.type, h.x, h.y, h.z, h.locked, IFNULL(a.name, '') AS name \
         FROM houses h LEFT JOIN accounts a ON a.id = h.owner ORDER BY h.id LIMIT %d", MAX_HOUSES);
    new count;
    if (result && DB_GetRowCount(result))
    {
        do
        {
            new h = count++;
            House[h][hDBID] = DB_GetFieldIntByName(result, "id");
            House[h][hOwner] = DB_GetFieldIntByName(result, "owner");
            House[h][hPrice] = DB_GetFieldIntByName(result, "price");
            House[h][hType] = clamp(DB_GetFieldIntByName(result, "type"), 0, sizeof HouseInteriors - 1);
            House[h][hX] = DB_GetFieldFloatByName(result, "x");
            House[h][hY] = DB_GetFieldFloatByName(result, "y");
            House[h][hZ] = DB_GetFieldFloatByName(result, "z");
            House[h][hLocked] = DB_GetFieldIntByName(result, "locked") != 0;
            DB_GetFieldStringByName(result, "name", House[h][hOwnerName], MAX_PLAYER_NAME + 1);
            if (House[h][hOwnerName][0] == EOS) House[h][hOwner] = 0;
            RefreshHouse(h);
        }
        while (DB_SelectNextRow(result) && count < MAX_HOUSES);
    }
    DB_FreeResultSet(result);
    printf("[Grand RP] %d houses loaded.", count);
}

stock SaveHouse(h)
{
    DB_FreeResultSet(DB_ExecuteQuery(gDB, "UPDATE houses SET owner=%d, price=%d, type=%d, locked=%d WHERE id=%d",
        House[h][hOwner], House[h][hPrice], House[h][hType], House[h][hLocked], House[h][hDBID]));
}

// House whose door the player is standing at, or -1
stock HouseAtDoor(playerid)
{
    if (GetPlayerVirtualWorld(playerid) != 0) return -1;
    for (new h = 0; h < MAX_HOUSES; h++)
    {
        if (House[h][hDBID] && IsPlayerInRangeOfPoint(playerid, 2.5, House[h][hX], House[h][hY], House[h][hZ])) return h;
    }
    return -1;
}

// House the player is inside, or -1
stock HouseInside(playerid)
{
    new h = GetPlayerVirtualWorld(playerid) - HOUSE_VW_BASE;
    if (h < 0 || h >= MAX_HOUSES || !House[h][hDBID]) return -1;
    return h;
}

stock bool:OwnsAHouse(playerid)
{
    for (new h = 0; h < MAX_HOUSES; h++)
    {
        if (House[h][hDBID] && House[h][hOwner] == Player[playerid][pID]) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Gang turfs
// ---------------------------------------------------------------------------

stock TurfColour(t)
{
    return (FactionColours[TurfOwner[t]] & 0xFFFFFF00) | 0x80;
}

stock LoadTurfs()
{
    for (new t = 0; t < sizeof Turfs; t++)
    {
        TurfOwner[t] = Turfs[t][tDefaultOwner];
        new DBResult:result = DB_ExecuteQuery(gDB, "SELECT owner FROM turfs WHERE id=%d", t);
        if (result && DB_GetRowCount(result))
        {
            new owner = DB_GetFieldInt(result, 0);
            if (IsGang(owner)) TurfOwner[t] = owner;
        }
        DB_FreeResultSet(result);
        TurfZone[t] = GangZoneCreate(Turfs[t][tMinX], Turfs[t][tMinY], Turfs[t][tMaxX], Turfs[t][tMaxY]);
    }
}

stock ShowTurfs(playerid)
{
    for (new t = 0; t < sizeof Turfs; t++) GangZoneShowForPlayer(playerid, TurfZone[t], TurfColour(t));
}

stock bool:IsPlayerInTurf(playerid, t)
{
    if (GetPlayerVirtualWorld(playerid) != 0 || GetPlayerInterior(playerid) != 0) return false;
    new Float:x, Float:y, Float:z;
    GetPlayerPos(playerid, x, y, z);
    return x >= Turfs[t][tMinX] && x <= Turfs[t][tMaxX] && y >= Turfs[t][tMinY] && y <= Turfs[t][tMaxY];
}

stock TurfAt(playerid)
{
    for (new t = 0; t < sizeof Turfs; t++)
    {
        if (IsPlayerInTurf(playerid, t)) return t;
    }
    return -1;
}

stock EndTurfWar(t)
{
    GangZoneStopFlashForAll(TurfZone[t]);
    GangZoneShowForAll(TurfZone[t], TurfColour(t));
    TurfAttacker[t] = FACTION_NONE;
    TurfCooldown[t] = gettime() + TURF_COOLDOWN;
}

forward TurfTick();
public TurfTick()
{
    for (new t = 0; t < sizeof Turfs; t++)
    {
        new attacker = TurfAttacker[t];
        if (attacker == FACTION_NONE) continue;

        new attackers, defenders;
        for (new i = 0; i < MAX_PLAYERS; i++)
        {
            if (!IsPlayerConnected(i) || !Player[i][pLoggedIn] || GetPlayerState(i) == PLAYER_STATE_WASTED) continue;
            if (!IsPlayerInTurf(i, t)) continue;
            if (Player[i][pFaction] == attacker) attackers++;
            else if (Player[i][pFaction] == TurfOwner[t]) defenders++;
        }

        new msg[144];
        if (!attackers)
        {
            format(msg, sizeof msg, "The %s attack on %s failed.", FactionNames[attacker], Turfs[t][tName]);
            SendFactionMessage(attacker, COLOR_ERROR, msg);
            SendFactionMessage(TurfOwner[t], COLOR_SUCCESS, msg);
            EndTurfWar(t);
            continue;
        }
        // Defenders on the turf hold the clock
        if (defenders) continue;
        if (--TurfTimeLeft[t] > 0) continue;

        new loser = TurfOwner[t];
        TurfOwner[t] = attacker;
        DB_FreeResultSet(DB_ExecuteQuery(gDB, "INSERT OR REPLACE INTO turfs (id, owner) VALUES (%d, %d)", t, attacker));
        for (new i = 0; i < MAX_PLAYERS; i++)
        {
            if (IsPlayerConnected(i) && Player[i][pLoggedIn] && Player[i][pFaction] == attacker && IsPlayerInTurf(i, t))
            {
                GiveMoney(i, TURF_REWARD);
                GiveExp(i, 1);
            }
        }
        format(msg, sizeof msg, "%s took %s from %s!", FactionNames[attacker], Turfs[t][tName], FactionNames[loser]);
        SendClientMessageToAll(FactionColours[attacker], msg);
        EndTurfWar(t);
    }
    return 1;
}

// ---------------------------------------------------------------------------
// Phone
// ---------------------------------------------------------------------------

stock EndCall(playerid, const reason[])
{
    new partner = Player[playerid][pCallPartner] - 1;
    Player[playerid][pCallPartner] = 0;
    Player[playerid][pCallActive] = false;
    Player[playerid][pCallRinging] = false;
    if (partner >= 0 && IsPlayerConnected(partner) && Player[partner][pCallPartner] - 1 == playerid)
    {
        Player[partner][pCallPartner] = 0;
        Player[partner][pCallActive] = false;
        Player[partner][pCallRinging] = false;
        SendClientMessage(partner, COLOR_GREY, reason);
    }
}

// ---------------------------------------------------------------------------
// Account flow
// ---------------------------------------------------------------------------

stock ResetPlayerData(playerid)
{
    static const empty[E_PLAYER];
    Player[playerid] = empty;
    Player[playerid][pLevel] = 1;
    Player[playerid][pSkin] = 26;
}

stock ShowRegisterDialog(playerid, const error[] = "")
{
    new text[256];
    format(text, sizeof text,
        "{FFFFFF}Welcome to {33CCFF}" SERVER_NAME "{FFFFFF}, %s!\n\nThis name is not registered yet.\nChoose a password (%d-%d characters):\n\n{FF6347}%s",
        RPName(playerid), MIN_PASSWORD_LEN, MAX_PASSWORD_LEN, error);
    ShowPlayerDialog(playerid, DIALOG_REGISTER, DIALOG_STYLE_PASSWORD, "Registration", text, "Register", "Quit");
}

stock ShowLoginDialog(playerid, const error[] = "")
{
    new text[256];
    format(text, sizeof text,
        "{FFFFFF}Welcome back to {33CCFF}" SERVER_NAME "{FFFFFF}, %s!\n\nEnter your password:\n\n{FF6347}%s",
        RPName(playerid), error);
    ShowPlayerDialog(playerid, DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, "Login", text, "Login", "Quit");
}

stock LoadAccount(playerid, DBResult:result)
{
    Player[playerid][pID] = DB_GetFieldIntByName(result, "id");
    Player[playerid][pAdmin] = DB_GetFieldIntByName(result, "admin");
    Player[playerid][pLevel] = DB_GetFieldIntByName(result, "level");
    Player[playerid][pExp] = DB_GetFieldIntByName(result, "exp");
    Player[playerid][pMoney] = DB_GetFieldIntByName(result, "money");
    Player[playerid][pBank] = DB_GetFieldIntByName(result, "bank");
    Player[playerid][pSkin] = DB_GetFieldIntByName(result, "skin");
    Player[playerid][pJob] = DB_GetFieldIntByName(result, "job");
    Player[playerid][pFaction] = DB_GetFieldIntByName(result, "faction");
    Player[playerid][pRank] = DB_GetFieldIntByName(result, "rank");
    Player[playerid][pPosX] = DB_GetFieldFloatByName(result, "x");
    Player[playerid][pPosY] = DB_GetFieldFloatByName(result, "y");
    Player[playerid][pPosZ] = DB_GetFieldFloatByName(result, "z");
    Player[playerid][pPosA] = DB_GetFieldFloatByName(result, "a");
    Player[playerid][pInterior] = DB_GetFieldIntByName(result, "interior");
    Player[playerid][pVW] = DB_GetFieldIntByName(result, "vw");
}

stock OnPlayerLoggedIn(playerid)
{
    Player[playerid][pLoggedIn] = true;

    new msg[144];
    format(msg, sizeof msg, "Welcome, %s! Level %d. Type /help to get started.", RPName(playerid), Player[playerid][pLevel]);
    SendClientMessage(playerid, COLOR_SUCCESS, msg);

    LoadPlayerVehicles(playerid);
    ShowTurfs(playerid);
    SetPlayerScore(playerid, Player[playerid][pLevel]);
    ResetPlayerMoney(playerid);
    GivePlayerMoney(playerid, Player[playerid][pMoney]);

    // New characters (or ones saved at 0,0,0) start at the station
    if (Player[playerid][pPosX] == 0.0 && Player[playerid][pPosY] == 0.0)
    {
        SetSpawnInfo(playerid, NO_TEAM, Player[playerid][pSkin], SPAWN_X, SPAWN_Y, SPAWN_Z, SPAWN_A);
    }
    else
    {
        SetSpawnInfo(playerid, NO_TEAM, Player[playerid][pSkin],
            Player[playerid][pPosX], Player[playerid][pPosY], Player[playerid][pPosZ], Player[playerid][pPosA]);
    }
    // Leaving spectator mode spawns the player with the spawn info above
    TogglePlayerSpectating(playerid, false);
}

// ---------------------------------------------------------------------------
// Gamemode callbacks
// ---------------------------------------------------------------------------

main()
{
    print("\n----------------------------------");
    print(" " SERVER_NAME " gamemode loaded");
    print("----------------------------------\n");
}

public OnGameModeInit()
{
    SetGameModeText("Grand RP v0.2");
    InitDatabase();

    UsePlayerPedAnims();
    DisableInteriorEnterExits();
    EnableStuntBonusForAll(false);
    ShowPlayerMarkers(PLAYER_MARKERS_MODE_STREAMED);
    SetNameTagDrawDistance(20.0);
    ManualVehicleEngineAndLights();
    AddPlayerClass(26, SPAWN_X, SPAWN_Y, SPAWN_Z, SPAWN_A);

    // Points of interest
    CreatePickup(1274, 1, BANK_X, BANK_Y, BANK_Z);
    Create3DTextLabel("{33CCFF}Bank\n{FFFFFF}/deposit /withdraw /transfer", COLOR_WHITE, BANK_X, BANK_Y, BANK_Z + 0.5, 15.0, 0);
    CreatePickup(1210, 1, JOBS_X, JOBS_Y, JOBS_Z);
    Create3DTextLabel("{33CCFF}Job Center\n{FFFFFF}/jobs /takejob /quitjob", COLOR_WHITE, JOBS_X, JOBS_Y, JOBS_Z + 0.5, 15.0, 0);
    CreatePickup(1239, 1, DEALER_X, DEALER_Y, DEALER_Z);
    Create3DTextLabel("{33CCFF}Car Dealership\n{FFFFFF}/buycar", COLOR_WHITE, DEALER_X, DEALER_Y, DEALER_Z + 0.5, 15.0, 0);
    CreatePickup(1239, 1, TRUCK_DEPOT_X, TRUCK_DEPOT_Y, TRUCK_DEPOT_Z);
    Create3DTextLabel("{33CCFF}Truck Depot\n{FFFFFF}/deliver", COLOR_WHITE, TRUCK_DEPOT_X, TRUCK_DEPOT_Y, TRUCK_DEPOT_Z + 0.5, 15.0, 0);
    CreatePickup(1239, 1, GARAGE_X, GARAGE_Y, GARAGE_Z);
    Create3DTextLabel("{33CCFF}Idlewood Garage\n{FFFFFF}Mechanics: tow trucks here, /repair", COLOR_WHITE, GARAGE_X, GARAGE_Y, GARAGE_Z + 0.5, 15.0, 0);
    CreatePickup(1582, 1, PIZZA_X, PIZZA_Y, PIZZA_Z);
    Create3DTextLabel("{33CCFF}Well Stacked Pizza\n{FFFFFF}/pizza on a pizza bike", COLOR_WHITE, PIZZA_X, PIZZA_Y, PIZZA_Z + 0.5, 15.0, 0);

    LoadHouses();
    LoadTurfs();

    // Job vehicles
    for (new i = 0; i < 4; i++)
    {
        CreateVehicle(499, TRUCK_DEPOT_X + 6.0 + (i * 4.0), TRUCK_DEPOT_Y + 8.0, TRUCK_DEPOT_Z, 0.0, 1, 1, 300);
        CreateVehicle(420, 1777.0 + (i * 4.0), -1890.0, 13.4, 270.0, 6, 1, 300);
        CreateVehicle(448, PIZZA_X + 4.0 + (i * 2.0), PIZZA_Y - 6.0, PIZZA_Z, 90.0, 3, 6, 300);
    }
    for (new i = 0; i < 2; i++)
    {
        CreateVehicle(525, GARAGE_X + 6.0 + (i * 5.0), GARAGE_Y + 6.0, GARAGE_Z, 0.0, 1, 1, 300);
    }

    // Faction vehicles
    for (new i = 0; i < 3; i++)
    {
        CreateVehicle(596, 1536.0 + (i * 4.0), -1675.0 + (i * 0.0), 13.4, 90.0, 0, 1, 300, true);
        CreateVehicle(416, 1178.0 + (i * 5.0), -1308.0, 13.9, 270.0, 1, 3, 300, true);
    }

    SetTimer("PayDay", PAYDAY_INTERVAL, true);
    SetTimer("AutoSave", 5 * 60 * 1000, true);
    SetTimer("TurfTick", 1000, true);
    return 1;
}

public OnGameModeExit()
{
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (IsPlayerConnected(i)) SavePlayer(i);
    }
    DB_Close(gDB);
    return 1;
}

public OnPlayerConnect(playerid)
{
    ResetPlayerData(playerid);

    new name[MAX_PLAYER_NAME + 1];
    GetPlayerName(playerid, name, sizeof name);

    if (!IsValidRPName(name))
    {
        SendClientMessage(playerid, COLOR_ERROR, "Your name must be in the format Firstname_Lastname (e.g. John_Smith).");
        SendClientMessage(playerid, COLOR_ERROR, "Change your name in the launcher settings and reconnect.");
        SetTimerEx("DelayedKick", 500, false, "i", playerid);
        return 1;
    }

    new DBResult:ban = DB_ExecuteQuery(gDB, "SELECT reason FROM bans WHERE name='%q'", name);
    if (DB_GetRowCount(ban))
    {
        new reason[64], msg[144];
        DB_GetFieldStringByName(ban, "reason", reason);
        format(msg, sizeof msg, "You are banned from this server. Reason: %s", reason);
        SendClientMessage(playerid, COLOR_ERROR, msg);
        DB_FreeResultSet(ban);
        SetTimerEx("DelayedKick", 500, false, "i", playerid);
        return 1;
    }
    DB_FreeResultSet(ban);

    new DBResult:result = DB_ExecuteQuery(gDB, "SELECT hash, salt FROM accounts WHERE name='%q'", name);
    if (DB_GetRowCount(result))
    {
        DB_GetFieldStringByName(result, "hash", Player[playerid][pPassHash], 65);
        DB_GetFieldStringByName(result, "salt", Player[playerid][pSalt], 17);
        ShowLoginDialog(playerid);
    }
    else
    {
        ShowRegisterDialog(playerid);
    }
    DB_FreeResultSet(result);
    return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
    if (Player[playerid][pLoggedIn])
    {
        SavePlayer(playerid);
        UnloadPlayerVehicles(playerid);
        EndCall(playerid, "The line went dead.");

        new msg[144];
        static const reasons[][] = {"Timeout", "Quit", "Kicked"};
        format(msg, sizeof msg, "(( %s left the server: %s ))", RPName(playerid), reasons[reason > 2 ? 2 : reason]);
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_GREY, msg);
    }
    ResetPlayerData(playerid);
    return 1;
}

public OnPlayerRequestClass(playerid, classid)
{
    // Skip class selection - the account decides the character
    if (Player[playerid][pLoggedIn])
    {
        SpawnPlayer(playerid);
    }
    else
    {
        TogglePlayerSpectating(playerid, true);
    }
    return 1;
}

public OnPlayerRequestSpawn(playerid)
{
    return Player[playerid][pLoggedIn] ? 1 : 0;
}

public OnPlayerSpawn(playerid)
{
    if (!Player[playerid][pLoggedIn])
    {
        Kick(playerid);
        return 1;
    }

    SetPlayerInterior(playerid, Player[playerid][pInterior]);
    SetPlayerVirtualWorld(playerid, Player[playerid][pVW]);
    SetPlayerSkin(playerid, Player[playerid][pOnDuty] ? FactionSkins[Player[playerid][pFaction]] : Player[playerid][pSkin]);
    SetPlayerColor(playerid, Player[playerid][pOnDuty] ? FactionColours[Player[playerid][pFaction]] : 0xFFFFFF00);
    ResetPlayerMoney(playerid);
    GivePlayerMoney(playerid, Player[playerid][pMoney]);

    // Respawns after death go to the hospital, positions saved before that are consumed
    Player[playerid][pInterior] = 0;
    Player[playerid][pVW] = 0;
    return 1;
}

public OnPlayerDeath(playerid, killerid, WEAPON:reason)
{
    Player[playerid][pOnDuty] = false;
    Player[playerid][pDeliveryStage] = 0;
    DisablePlayerCheckpoint(playerid);

    // Hospital bill
    new bill = Player[playerid][pMoney] >= 500 ? 500 : Player[playerid][pMoney];
    GiveMoney(playerid, -bill);
    SetSpawnInfo(playerid, NO_TEAM, Player[playerid][pSkin], 1172.0, -1323.0, 15.4, 270.0);

    new msg[96];
    format(msg, sizeof msg, "You were treated at All Saints hospital. Bill: $%d", bill);
    SendClientMessage(playerid, COLOR_INFO, msg);
    return 1;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
    switch (dialogid)
    {
        case DIALOG_REGISTER:
        {
            if (!response) return Kick(playerid);

            new len = strlen(inputtext);
            if (len < MIN_PASSWORD_LEN || len > MAX_PASSWORD_LEN)
            {
                ShowRegisterDialog(playerid, "Invalid password length.");
                return 1;
            }

            GenerateSalt(Player[playerid][pSalt], 17);
            SHA256_PassHash(inputtext, Player[playerid][pSalt], Player[playerid][pPassHash], 65);

            DB_FreeResultSet(DB_ExecuteQuery(gDB,
                "INSERT INTO accounts (name, hash, salt, money, bank) VALUES ('%q', '%q', '%q', %d, %d)",
                PlayerName(playerid), Player[playerid][pPassHash], Player[playerid][pSalt], START_MONEY, START_BANK));

            new DBResult:result = DB_ExecuteQuery(gDB, "SELECT * FROM accounts WHERE name='%q'", PlayerName(playerid));
            LoadAccount(playerid, result);
            DB_FreeResultSet(result);

            SendClientMessage(playerid, COLOR_SUCCESS, "Account created. Welcome to Los Santos!");
            OnPlayerLoggedIn(playerid);
            return 1;
        }
        case DIALOG_LOGIN:
        {
            if (!response) return Kick(playerid);

            new hash[65];
            SHA256_PassHash(inputtext, Player[playerid][pSalt], hash, sizeof hash);
            if (strcmp(hash, Player[playerid][pPassHash]) != 0)
            {
                if (++Player[playerid][pLoginAttempts] >= MAX_LOGIN_ATTEMPTS)
                {
                    SendClientMessage(playerid, COLOR_ERROR, "Too many failed login attempts.");
                    SetTimerEx("DelayedKick", 500, false, "i", playerid);
                    return 1;
                }
                ShowLoginDialog(playerid, "Wrong password.");
                return 1;
            }

            new DBResult:result = DB_ExecuteQuery(gDB, "SELECT * FROM accounts WHERE name='%q'", PlayerName(playerid));
            LoadAccount(playerid, result);
            DB_FreeResultSet(result);
            OnPlayerLoggedIn(playerid);
            return 1;
        }
        case DIALOG_DEALERSHIP:
        {
            if (!response) return 1;
            BuyDealerCar(playerid, listitem);
            return 1;
        }
    }
    return 0;
}

public OnPlayerText(playerid, text[])
{
    if (!Player[playerid][pLoggedIn]) return 0;

    new msg[144];
    if (Player[playerid][pCallActive])
    {
        new partner = Player[playerid][pCallPartner] - 1;
        format(msg, sizeof msg, "(Phone) %s: %s", RPName(playerid), text);
        SendClientMessage(partner, 0xFFFF00FF, msg);
        format(msg, sizeof msg, "%s says (phone): %s", RPName(playerid), text);
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_WHITE, msg);
        return 0;
    }
    if (IsPlayerInAnyVehicle(playerid))
    {
        format(msg, sizeof msg, "%s says (vehicle): %s", RPName(playerid), text);
        SendNearbyMessage(playerid, 5.0, COLOR_WHITE, msg);
    }
    else
    {
        format(msg, sizeof msg, "%s says: %s", RPName(playerid), text);
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_WHITE, msg);
    }
    SetPlayerChatBubble(playerid, text, COLOR_WHITE, CHAT_RANGE, 5000);
    return 0;
}

public OnPlayerStateChange(playerid, PLAYER_STATE:newstate, PLAYER_STATE:oldstate)
{
    if (newstate != PLAYER_STATE_DRIVER) return 1;

    new vehicleid = GetPlayerVehicleID(playerid), model = GetVehicleModel(vehicleid);

    if (OwnedVehicle[vehicleid][ovDBID] && OwnedVehicle[vehicleid][ovOwner] != Player[playerid][pID]
        && Player[playerid][pAdmin] == 0)
    {
        SendError(playerid, "This vehicle does not belong to you.");
        RemovePlayerFromVehicle(playerid);
        return 1;
    }
    if (model == 499 && Player[playerid][pJob] != JOB_TRUCKER)
    {
        SendError(playerid, "Only truckers can drive this vehicle. Visit the job center.");
        RemovePlayerFromVehicle(playerid);
        return 1;
    }
    if (model == 420 && Player[playerid][pJob] != JOB_TAXI)
    {
        SendError(playerid, "Only taxi drivers can drive this vehicle. Visit the job center.");
        RemovePlayerFromVehicle(playerid);
        return 1;
    }
    if (model == 525 && Player[playerid][pJob] != JOB_MECHANIC)
    {
        SendError(playerid, "Only mechanics can drive tow trucks. Visit the job center.");
        RemovePlayerFromVehicle(playerid);
        return 1;
    }
    if (model == 448 && Player[playerid][pJob] != JOB_PIZZA)
    {
        SendError(playerid, "Only pizza delivery workers can ride this bike. Visit the job center.");
        RemovePlayerFromVehicle(playerid);
        return 1;
    }
    if (model == 596 && Player[playerid][pFaction] != FACTION_LSPD)
    {
        SendError(playerid, "This vehicle belongs to the LSPD.");
        RemovePlayerFromVehicle(playerid);
        return 1;
    }
    if (model == 416 && Player[playerid][pFaction] != FACTION_MEDIC)
    {
        SendError(playerid, "This vehicle belongs to the medics.");
        RemovePlayerFromVehicle(playerid);
        return 1;
    }
    SendClientMessage(playerid, COLOR_GREY, "Type /engine to start the engine.");
    return 1;
}

public OnPlayerEnterCheckpoint(playerid)
{
    if (Player[playerid][pDeliveryStage] == 2)
    {
        new bike = GetPlayerVehicleID(playerid);
        if (!bike || GetVehicleModel(bike) != 448)
        {
            SendError(playerid, "Bring the pizza on your delivery bike.");
            return 1;
        }
        new stop = Player[playerid][pDeliveryRoute], tip = PizzaRoutes[stop][rtPay] + (Player[playerid][pLevel] * 20) + random(150);
        GiveMoney(playerid, tip);
        GiveExp(playerid, 1);
        DisablePlayerCheckpoint(playerid);
        Player[playerid][pDeliveryStage] = 0;

        new text[128];
        format(text, sizeof text, "Pizza delivered to %s. You earned $%d. Head back for another with /pizza.", PizzaRoutes[stop][rtName], tip);
        SendClientMessage(playerid, COLOR_SUCCESS, text);
        GameTextForPlayer(playerid, "~g~Delivered!", 3000, 1);
        return 1;
    }
    if (Player[playerid][pDeliveryStage] != 1) return 1;

    new vehicleid = GetPlayerVehicleID(playerid);
    if (!vehicleid || GetVehicleModel(vehicleid) != 499)
    {
        SendError(playerid, "You need your delivery truck to drop off the cargo.");
        return 1;
    }

    new route = Player[playerid][pDeliveryRoute], pay = TruckRoutes[route][rtPay] + (Player[playerid][pLevel] * 50);
    GiveMoney(playerid, pay);
    GiveExp(playerid, 1);
    DisablePlayerCheckpoint(playerid);
    Player[playerid][pDeliveryStage] = 0;

    new msg[128];
    format(msg, sizeof msg, "Delivery to %s complete. You earned $%d.", TruckRoutes[route][rtName], pay);
    SendClientMessage(playerid, COLOR_SUCCESS, msg);
    GameTextForPlayer(playerid, "~g~Delivered!", 3000, 1);
    return 1;
}

// ---------------------------------------------------------------------------
// Timers
// ---------------------------------------------------------------------------

forward DelayedKick(playerid);
public DelayedKick(playerid)
{
    Kick(playerid);
    return 1;
}

forward AutoSave();
public AutoSave()
{
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (IsPlayerConnected(i)) SavePlayer(i);
    }
    return 1;
}

stock GiveExp(playerid, amount)
{
    Player[playerid][pExp] += amount;
    while (Player[playerid][pExp] >= ExpForNextLevel(playerid))
    {
        Player[playerid][pExp] -= ExpForNextLevel(playerid);
        Player[playerid][pLevel]++;
        SetPlayerScore(playerid, Player[playerid][pLevel]);

        new msg[64];
        format(msg, sizeof msg, "Level up! You are now level %d.", Player[playerid][pLevel]);
        SendClientMessage(playerid, COLOR_SUCCESS, msg);
    }
}

forward PayDay();
public PayDay()
{
    for (new i = 0; i < MAX_PLAYERS; i++)
    {
        if (!IsPlayerConnected(i) || !Player[i][pLoggedIn]) continue;

        new salary = 500 + (Player[i][pLevel] * 100), interest = Player[i][pBank] / 1000;
        if (Player[i][pFaction] != FACTION_NONE && !IsGang(Player[i][pFaction])) salary += Player[i][pRank] * 400;
        if (interest > 2000) interest = 2000;

        Player[i][pBank] += salary + interest;
        GiveExp(i, 1);

        new msg[144];
        SendClientMessage(i, COLOR_INFO, "______________ PAYDAY ______________");
        format(msg, sizeof msg, "Salary: $%d | Interest: $%d | Bank balance: $%d", salary, interest, Player[i][pBank]);
        SendClientMessage(i, COLOR_WHITE, msg);
        GameTextForPlayer(i, "~y~PayDay", 4000, 1);
        SavePlayer(i);
    }
    return 1;
}

// ---------------------------------------------------------------------------
// Features
// ---------------------------------------------------------------------------

stock BuyDealerCar(playerid, index)
{
    if (index < 0 || index >= sizeof DealerCars) return;

    if (CountOwnedVehicles(playerid) >= MAX_OWNED_VEHICLES)
    {
        SendError(playerid, "You already own the maximum number of vehicles.");
        return;
    }
    if (Player[playerid][pMoney] < DealerCars[index][dcPrice])
    {
        SendError(playerid, "You can't afford this vehicle.");
        return;
    }

    new colour = random(126);
    new vehicleid = CreateVehicle(DealerCars[index][dcModel], DEALER_SPAWN_X, DEALER_SPAWN_Y, DEALER_SPAWN_Z,
        DEALER_SPAWN_A, colour, colour, -1);
    if (vehicleid == INVALID_VEHICLE_ID)
    {
        SendError(playerid, "The dealership is out of stock, try again later.");
        return;
    }

    GiveMoney(playerid, -DealerCars[index][dcPrice]);
    DB_FreeResultSet(DB_ExecuteQuery(gDB,
        "INSERT INTO vehicles (owner, model, x, y, z, a, colour1, colour2) VALUES (%d, %d, %f, %f, %f, %f, %d, %d)",
        Player[playerid][pID], DealerCars[index][dcModel], DEALER_SPAWN_X, DEALER_SPAWN_Y, DEALER_SPAWN_Z,
        DEALER_SPAWN_A, colour, colour));

    new DBResult:result = DB_ExecuteQuery(gDB, "SELECT last_insert_rowid()");
    OwnedVehicle[vehicleid][ovDBID] = DB_GetFieldInt(result, 0);
    DB_FreeResultSet(result);
    OwnedVehicle[vehicleid][ovOwner] = Player[playerid][pID];
    OwnedVehicle[vehicleid][ovModel] = DealerCars[index][dcModel];
    OwnedVehicle[vehicleid][ovLocked] = false;
    SetVehicleNumberPlate(vehicleid, "GRAND");
    PutPlayerInVehicle(playerid, vehicleid, 0);

    new msg[128];
    format(msg, sizeof msg, "Congratulations on your new %s! Use /park to set where it spawns and /lock to lock it.",
        DealerCars[index][dcName]);
    SendClientMessage(playerid, COLOR_SUCCESS, msg);
    SavePlayer(playerid);
}

stock ShowHelp(playerid)
{
    ShowPlayerDialog(playerid, DIALOG_HELP, DIALOG_STYLE_MSGBOX, SERVER_NAME " - Help",
        "{33CCFF}General:{FFFFFF} /stats /pay /engine /lock /park /mycars\n\
{33CCFF}Chat:{FFFFFF} /me /do /b (OOC) /s (shout) /w (whisper)\n\
{33CCFF}Bank:{FFFFFF} /balance /deposit /withdraw /transfer\n\
{33CCFF}Jobs:{FFFFFF} /jobs /takejob /quitjob /deliver /fare /repair /pizza\n\
{33CCFF}Factions:{FFFFFF} /f /duty /invite /uninvite /setrank /cuff /uncuff\n\
{33CCFF}Gangs:{FFFFFF} /f /turfs /capture\n\
{33CCFF}Houses:{FFFFFF} /buyhouse /sellhouse /enter /exit /lockhouse\n\
{33CCFF}Phone:{FFFFFF} /number /call /pickup /hangup /sms\n\
{33CCFF}Dealership:{FFFFFF} /buycar\n\n\
{AFAFAF}Bank, job center, dealership, garage and pizzeria are marked with pickups around Los Santos.",
        "Close", "");
}

stock bool:IsLeader(playerid)
{
    return Player[playerid][pFaction] != FACTION_NONE && Player[playerid][pRank] >= MAX_RANK - 1;
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

public OnPlayerCommandText(playerid, cmdtext[])
{
    if (!Player[playerid][pLoggedIn]) return 1;

    new idx, cmd[64], msg[144];
    cmd = strtok(cmdtext, idx);

    // ---- General ----------------------------------------------------------
    if (!strcmp(cmd, "/help", true))
    {
        ShowHelp(playerid);
        return 1;
    }
    if (!strcmp(cmd, "/stats", true))
    {
        format(msg, sizeof msg, "%s | Level: %d (%d/%d exp) | Cash: $%d | Bank: $%d",
            RPName(playerid), Player[playerid][pLevel], Player[playerid][pExp], ExpForNextLevel(playerid),
            Player[playerid][pMoney], Player[playerid][pBank]);
        SendClientMessage(playerid, COLOR_INFO, msg);
        format(msg, sizeof msg, "Job: %s | Faction: %s | Rank: %s",
            JobNames[Player[playerid][pJob]], FactionNames[Player[playerid][pFaction]],
            Player[playerid][pFaction] ? FactionRanks[Player[playerid][pFaction]][Player[playerid][pRank]] : "-");
        SendClientMessage(playerid, COLOR_INFO, msg);
        format(msg, sizeof msg, "Phone: %d | House: %s", PhoneNumber(playerid), OwnsAHouse(playerid) ? "yes" : "no");
        SendClientMessage(playerid, COLOR_INFO, msg);
        return 1;
    }
    if (!strcmp(cmd, "/pay", true))
    {
        new targetid = FindPlayer(strtok(cmdtext, idx)), amount = strval(strtok(cmdtext, idx));
        if (targetid == INVALID_PLAYER_ID || amount <= 0) return SendUsage(playerid, "/pay [player] [amount]");
        if (targetid == playerid) return SendError(playerid, "You can't pay yourself.");
        if (amount > Player[playerid][pMoney]) return SendError(playerid, "You don't have that much cash.");

        new Float:x, Float:y, Float:z;
        GetPlayerPos(targetid, x, y, z);
        if (!IsPlayerInRangeOfPoint(playerid, 5.0, x, y, z)) return SendError(playerid, "That player is not near you.");

        GiveMoney(playerid, -amount);
        GiveMoney(targetid, amount);
        format(msg, sizeof msg, "* %s takes out $%d and hands it to %s.", RPName(playerid), amount, RPName(targetid));
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_PURPLE, msg);
        return 1;
    }

    // ---- Roleplay chat ----------------------------------------------------
    if (!strcmp(cmd, "/me", true))
    {
        new action[128];
        action = strrest(cmdtext, idx);
        if (action[0] == EOS) return SendUsage(playerid, "/me [action]");
        format(msg, sizeof msg, "* %s %s", RPName(playerid), action);
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_PURPLE, msg);
        return 1;
    }
    if (!strcmp(cmd, "/do", true))
    {
        new action[128];
        action = strrest(cmdtext, idx);
        if (action[0] == EOS) return SendUsage(playerid, "/do [description]");
        format(msg, sizeof msg, "* %s (( %s ))", action, RPName(playerid));
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_PURPLE, msg);
        return 1;
    }
    if (!strcmp(cmd, "/b", true))
    {
        new text[128];
        text = strrest(cmdtext, idx);
        if (text[0] == EOS) return SendUsage(playerid, "/b [local OOC text]");
        format(msg, sizeof msg, "(( [%d] %s: %s ))", playerid, RPName(playerid), text);
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_OOC, msg);
        return 1;
    }
    if (!strcmp(cmd, "/s", true) || !strcmp(cmd, "/shout", true))
    {
        new text[128];
        text = strrest(cmdtext, idx);
        if (text[0] == EOS) return SendUsage(playerid, "/s [text]");
        format(msg, sizeof msg, "%s shouts: %s!", RPName(playerid), text);
        SendNearbyMessage(playerid, SHOUT_RANGE, COLOR_WHITE, msg);
        return 1;
    }
    if (!strcmp(cmd, "/w", true) || !strcmp(cmd, "/whisper", true))
    {
        new text[128];
        text = strrest(cmdtext, idx);
        if (text[0] == EOS) return SendUsage(playerid, "/w [text]");
        format(msg, sizeof msg, "%s whispers: %s", RPName(playerid), text);
        SendNearbyMessage(playerid, WHISPER_RANGE, COLOR_GREY, msg);
        return 1;
    }

    // ---- Bank -------------------------------------------------------------
    if (!strcmp(cmd, "/balance", true) || !strcmp(cmd, "/deposit", true)
        || !strcmp(cmd, "/withdraw", true) || !strcmp(cmd, "/transfer", true))
    {
        if (!IsPlayerInRangeOfPoint(playerid, 4.0, BANK_X, BANK_Y, BANK_Z))
            return SendError(playerid, "You need to be at the bank (Pershing Square).");

        if (!strcmp(cmd, "/balance", true))
        {
            format(msg, sizeof msg, "Bank balance: $%d", Player[playerid][pBank]);
            SendClientMessage(playerid, COLOR_INFO, msg);
        }
        else if (!strcmp(cmd, "/deposit", true))
        {
            new amount = strval(strtok(cmdtext, idx));
            if (amount <= 0) return SendUsage(playerid, "/deposit [amount]");
            if (amount > Player[playerid][pMoney]) return SendError(playerid, "You don't have that much cash.");
            GiveMoney(playerid, -amount);
            Player[playerid][pBank] += amount;
            format(msg, sizeof msg, "You deposited $%d. New balance: $%d", amount, Player[playerid][pBank]);
            SendClientMessage(playerid, COLOR_SUCCESS, msg);
        }
        else if (!strcmp(cmd, "/withdraw", true))
        {
            new amount = strval(strtok(cmdtext, idx));
            if (amount <= 0) return SendUsage(playerid, "/withdraw [amount]");
            if (amount > Player[playerid][pBank]) return SendError(playerid, "You don't have that much in the bank.");
            Player[playerid][pBank] -= amount;
            GiveMoney(playerid, amount);
            format(msg, sizeof msg, "You withdrew $%d. New balance: $%d", amount, Player[playerid][pBank]);
            SendClientMessage(playerid, COLOR_SUCCESS, msg);
        }
        else
        {
            new targetid = FindPlayer(strtok(cmdtext, idx)), amount = strval(strtok(cmdtext, idx));
            if (targetid == INVALID_PLAYER_ID || amount <= 0) return SendUsage(playerid, "/transfer [player] [amount]");
            if (targetid == playerid || !Player[targetid][pLoggedIn]) return SendError(playerid, "Invalid player.");
            if (amount > Player[playerid][pBank]) return SendError(playerid, "You don't have that much in the bank.");
            Player[playerid][pBank] -= amount;
            Player[targetid][pBank] += amount;
            format(msg, sizeof msg, "You transferred $%d to %s.", amount, RPName(targetid));
            SendClientMessage(playerid, COLOR_SUCCESS, msg);
            format(msg, sizeof msg, "%s transferred $%d to your bank account.", RPName(playerid), amount);
            SendClientMessage(targetid, COLOR_SUCCESS, msg);
            SavePlayer(targetid);
        }
        SavePlayer(playerid);
        return 1;
    }

    // ---- Jobs -------------------------------------------------------------
    if (!strcmp(cmd, "/jobs", true))
    {
        SendClientMessage(playerid, COLOR_INFO, "Available jobs (use /takejob [id] at the job center):");
        SendClientMessage(playerid, COLOR_WHITE, "1 - Trucker: deliver cargo across San Andreas (/deliver at the Ocean Docks depot)");
        SendClientMessage(playerid, COLOR_WHITE, "2 - Taxi driver: drive players around and charge fares (/fare)");
        SendClientMessage(playerid, COLOR_WHITE, "3 - Mechanic: tow trucks at the Idlewood garage, fix cars for money (/repair)");
        SendClientMessage(playerid, COLOR_WHITE, "4 - Pizza delivery: bikes at Well Stacked Pizza in Idlewood (/pizza)");
        return 1;
    }
    if (!strcmp(cmd, "/takejob", true))
    {
        if (!IsPlayerInRangeOfPoint(playerid, 4.0, JOBS_X, JOBS_Y, JOBS_Z))
            return SendError(playerid, "You need to be at the job center (Market).");
        new job = strval(strtok(cmdtext, idx));
        if (job <= JOB_NONE || job >= MAX_JOBS) return SendUsage(playerid, "/takejob [1-4] (see /jobs)");
        if (Player[playerid][pJob] != JOB_NONE) return SendError(playerid, "Quit your current job first with /quitjob.");
        Player[playerid][pJob] = job;
        format(msg, sizeof msg, "You are now a %s.", JobNames[job]);
        SendClientMessage(playerid, COLOR_SUCCESS, msg);
        SavePlayer(playerid);
        return 1;
    }
    if (!strcmp(cmd, "/quitjob", true))
    {
        if (Player[playerid][pJob] == JOB_NONE) return SendError(playerid, "You don't have a job.");
        Player[playerid][pJob] = JOB_NONE;
        Player[playerid][pDeliveryStage] = 0;
        DisablePlayerCheckpoint(playerid);
        SendClientMessage(playerid, COLOR_SUCCESS, "You quit your job.");
        SavePlayer(playerid);
        return 1;
    }
    if (!strcmp(cmd, "/deliver", true))
    {
        if (Player[playerid][pJob] != JOB_TRUCKER) return SendError(playerid, "You are not a trucker.");
        if (Player[playerid][pDeliveryStage]) return SendError(playerid, "You already have a delivery in progress.");
        new vehicleid = GetPlayerVehicleID(playerid);
        if (!vehicleid || GetVehicleModel(vehicleid) != 499) return SendError(playerid, "You need to be in a delivery truck.");
        if (!IsPlayerInRangeOfPoint(playerid, 25.0, TRUCK_DEPOT_X, TRUCK_DEPOT_Y, TRUCK_DEPOT_Z))
            return SendError(playerid, "Load your cargo at the Ocean Docks depot.");

        new route = random(sizeof TruckRoutes);
        Player[playerid][pDeliveryRoute] = route;
        Player[playerid][pDeliveryStage] = 1;
        SetPlayerCheckpoint(playerid, TruckRoutes[route][rtX], TruckRoutes[route][rtY], TruckRoutes[route][rtZ], 6.0);
        format(msg, sizeof msg, "Cargo loaded. Deliver it to %s (marked on your radar).", TruckRoutes[route][rtName]);
        SendClientMessage(playerid, COLOR_INFO, msg);
        return 1;
    }
    if (!strcmp(cmd, "/fare", true))
    {
        if (Player[playerid][pJob] != JOB_TAXI) return SendError(playerid, "You are not a taxi driver.");
        new targetid = FindPlayer(strtok(cmdtext, idx)), amount = strval(strtok(cmdtext, idx));
        if (targetid == INVALID_PLAYER_ID || amount <= 0 || amount > 1000)
            return SendUsage(playerid, "/fare [passenger] [amount, max $1000]");
        new vehicleid = GetPlayerVehicleID(playerid);
        if (!vehicleid || GetVehicleModel(vehicleid) != 420 || GetPlayerVehicleID(targetid) != vehicleid || targetid == playerid)
            return SendError(playerid, "That player must be a passenger in your taxi.");
        if (Player[targetid][pMoney] < amount) return SendError(playerid, "Your passenger can't afford that fare.");

        GiveMoney(targetid, -amount);
        GiveMoney(playerid, amount);
        GiveExp(playerid, 1);
        format(msg, sizeof msg, "* %s pays the $%d taxi fare.", RPName(targetid), amount);
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_PURPLE, msg);
        return 1;
    }

    if (!strcmp(cmd, "/repair", true))
    {
        if (Player[playerid][pJob] != JOB_MECHANIC) return SendError(playerid, "You are not a mechanic.");
        new targetid = FindPlayer(strtok(cmdtext, idx)), price = strval(strtok(cmdtext, idx));
        if (targetid == INVALID_PLAYER_ID || price < 0 || price > 2000)
            return SendUsage(playerid, "/repair [driver] [price, max $2000]");
        new vehicleid = GetPlayerVehicleID(targetid);
        if (!vehicleid) return SendError(playerid, "That player is not in a vehicle.");
        new Float:x, Float:y, Float:z;
        GetVehiclePos(vehicleid, x, y, z);
        if (!IsPlayerInRangeOfPoint(playerid, 6.0, x, y, z)) return SendError(playerid, "You need to be next to their vehicle.");
        if (targetid != playerid)
        {
            if (Player[targetid][pMoney] < price) return SendError(playerid, "They can't afford that.");
            GiveMoney(targetid, -price);
            GiveMoney(playerid, price);
            GiveExp(playerid, 1);
        }
        RepairVehicle(vehicleid);
        format(msg, sizeof msg, "* %s repairs %s's vehicle for $%d.", RPName(playerid), RPName(targetid), price);
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_PURPLE, msg);
        return 1;
    }
    if (!strcmp(cmd, "/pizza", true))
    {
        if (Player[playerid][pJob] != JOB_PIZZA) return SendError(playerid, "You don't work for Well Stacked Pizza.");
        if (Player[playerid][pDeliveryStage]) return SendError(playerid, "You already have a delivery in progress.");
        new vehicleid = GetPlayerVehicleID(playerid);
        if (!vehicleid || GetVehicleModel(vehicleid) != 448) return SendError(playerid, "You need to be on a pizza bike.");
        if (!IsPlayerInRangeOfPoint(playerid, 25.0, PIZZA_X, PIZZA_Y, PIZZA_Z))
            return SendError(playerid, "Pick up the pizza at Well Stacked Pizza in Idlewood.");

        new stop = random(sizeof PizzaRoutes);
        Player[playerid][pDeliveryRoute] = stop;
        Player[playerid][pDeliveryStage] = 2;
        SetPlayerCheckpoint(playerid, PizzaRoutes[stop][rtX], PizzaRoutes[stop][rtY], PizzaRoutes[stop][rtZ], 4.0);
        format(msg, sizeof msg, "Hot pizza for %s! Deliver it before it gets cold (marked on your radar).", PizzaRoutes[stop][rtName]);
        SendClientMessage(playerid, COLOR_INFO, msg);
        return 1;
    }

    // ---- Houses -----------------------------------------------------------
    if (!strcmp(cmd, "/buyhouse", true))
    {
        new h = HouseAtDoor(playerid);
        if (h == -1) return SendError(playerid, "You are not at a house door.");
        if (House[h][hOwner]) return SendError(playerid, "This house is not for sale.");
        if (OwnsAHouse(playerid)) return SendError(playerid, "You already own a house. Sell it first with /sellhouse.");
        if (Player[playerid][pMoney] < House[h][hPrice]) return SendError(playerid, "You can't afford this house.");

        GiveMoney(playerid, -House[h][hPrice]);
        House[h][hOwner] = Player[playerid][pID];
        format(House[h][hOwnerName], MAX_PLAYER_NAME + 1, "%s", PlayerName(playerid));
        House[h][hLocked] = true;
        SaveHouse(h);
        RefreshHouse(h);
        SavePlayer(playerid);
        format(msg, sizeof msg, "You bought this house for $%d! Use /enter, /exit and /lockhouse.", House[h][hPrice]);
        SendClientMessage(playerid, COLOR_SUCCESS, msg);
        return 1;
    }
    if (!strcmp(cmd, "/sellhouse", true))
    {
        new h = HouseAtDoor(playerid);
        if (h == -1) h = HouseInside(playerid);
        if (h == -1 || House[h][hOwner] != Player[playerid][pID]) return SendError(playerid, "You need to be at your own house.");

        new refund = House[h][hPrice] / 2;
        GiveMoney(playerid, refund);
        House[h][hOwner] = 0;
        House[h][hOwnerName][0] = EOS;
        House[h][hLocked] = true;
        SaveHouse(h);
        RefreshHouse(h);
        SavePlayer(playerid);
        format(msg, sizeof msg, "You sold your house back to the city for $%d.", refund);
        SendClientMessage(playerid, COLOR_SUCCESS, msg);
        return 1;
    }
    if (!strcmp(cmd, "/enter", true))
    {
        new h = HouseAtDoor(playerid);
        if (h == -1) return SendError(playerid, "You are not at a house door.");
        if (IsPlayerInAnyVehicle(playerid)) return SendError(playerid, "Get out of your vehicle first.");
        // Houses for sale can be viewed; owned ones only when open or by the owner
        if (House[h][hOwner] && House[h][hLocked] && House[h][hOwner] != Player[playerid][pID])
        {
            GameTextForPlayer(playerid, "~r~Locked", 2000, 3);
            return 1;
        }
        new type = House[h][hType];
        SetPlayerInterior(playerid, HouseInteriors[type][hiInterior]);
        SetPlayerVirtualWorld(playerid, HOUSE_VW_BASE + h);
        SetPlayerPos(playerid, HouseInteriors[type][hiX], HouseInteriors[type][hiY], HouseInteriors[type][hiZ]);
        SetCameraBehindPlayer(playerid);
        return 1;
    }
    if (!strcmp(cmd, "/exit", true))
    {
        new h = HouseInside(playerid);
        if (h == -1) return SendError(playerid, "You are not inside a house.");
        new type = House[h][hType];
        if (!IsPlayerInRangeOfPoint(playerid, 3.0, HouseInteriors[type][hiX], HouseInteriors[type][hiY], HouseInteriors[type][hiZ]))
            return SendError(playerid, "Go to the front door to leave.");
        SetPlayerInterior(playerid, 0);
        SetPlayerVirtualWorld(playerid, 0);
        SetPlayerPos(playerid, House[h][hX], House[h][hY], House[h][hZ]);
        SetCameraBehindPlayer(playerid);
        return 1;
    }
    if (!strcmp(cmd, "/lockhouse", true))
    {
        new h = HouseAtDoor(playerid);
        if (h == -1) h = HouseInside(playerid);
        if (h == -1 || House[h][hOwner] != Player[playerid][pID]) return SendError(playerid, "You need to be at your own house.");
        House[h][hLocked] = !House[h][hLocked];
        SaveHouse(h);
        RefreshHouse(h);
        GameTextForPlayer(playerid, House[h][hLocked] ? "~r~House locked" : "~g~House unlocked", 2000, 3);
        PlayerPlaySound(playerid, 1145, 0.0, 0.0, 0.0);
        return 1;
    }

    // ---- Phone ------------------------------------------------------------
    if (!strcmp(cmd, "/number", true))
    {
        new tmp[64];
        tmp = strtok(cmdtext, idx);
        new targetid = tmp[0] == EOS ? playerid : FindPlayer(tmp);
        if (targetid == INVALID_PLAYER_ID || !Player[targetid][pLoggedIn]) return SendUsage(playerid, "/number [player]");
        format(msg, sizeof msg, "Phone book: %s - %d", RPName(targetid), PhoneNumber(targetid));
        SendClientMessage(playerid, COLOR_INFO, msg);
        return 1;
    }
    if (!strcmp(cmd, "/sms", true))
    {
        new number = strval(strtok(cmdtext, idx)), text[128];
        text = strrest(cmdtext, idx);
        if (number <= 0 || text[0] == EOS) return SendUsage(playerid, "/sms [number] [message]");
        new targetid = FindPhone(number);
        if (targetid == INVALID_PLAYER_ID) return SendError(playerid, "That number is not reachable right now.");
        format(msg, sizeof msg, "SMS from %d (%s): %s", PhoneNumber(playerid), RPName(playerid), text);
        SendClientMessage(targetid, 0xFFFF00FF, msg);
        PlayerPlaySound(targetid, 1052, 0.0, 0.0, 0.0);
        format(msg, sizeof msg, "SMS to %d: %s", number, text);
        SendClientMessage(playerid, 0xFFFF00FF, msg);
        return 1;
    }
    if (!strcmp(cmd, "/call", true))
    {
        new number = strval(strtok(cmdtext, idx));
        if (number <= 0) return SendUsage(playerid, "/call [number]");
        if (Player[playerid][pCallPartner]) return SendError(playerid, "You are already on a call. /hangup first.");
        new targetid = FindPhone(number);
        if (targetid == INVALID_PLAYER_ID || targetid == playerid) return SendError(playerid, "The number you dialed is not reachable.");
        if (Player[targetid][pCallPartner]) return SendError(playerid, "The line is busy.");

        Player[playerid][pCallPartner] = targetid + 1;
        Player[targetid][pCallPartner] = playerid + 1;
        Player[targetid][pCallRinging] = true;
        format(msg, sizeof msg, "Your phone is ringing: %d (%s). /pickup to answer, /hangup to reject.",
            PhoneNumber(playerid), RPName(playerid));
        SendClientMessage(targetid, 0xFFFF00FF, msg);
        PlayerPlaySound(targetid, 1052, 0.0, 0.0, 0.0);
        format(msg, sizeof msg, "* %s takes out a phone and dials a number.", RPName(playerid));
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_PURPLE, msg);
        SendClientMessage(playerid, COLOR_GREY, "Ringing... (/hangup to cancel)");
        return 1;
    }
    if (!strcmp(cmd, "/pickup", true))
    {
        new caller = Player[playerid][pCallPartner] - 1;
        if (caller < 0 || !Player[playerid][pCallRinging]) return SendError(playerid, "Nobody is calling you.");
        Player[playerid][pCallRinging] = false;
        Player[playerid][pCallActive] = true;
        Player[caller][pCallActive] = true;
        SendClientMessage(playerid, COLOR_SUCCESS, "You answered. Talk in normal chat, /hangup to end the call.");
        SendClientMessage(caller, COLOR_SUCCESS, "They picked up. Talk in normal chat, /hangup to end the call.");
        return 1;
    }
    if (!strcmp(cmd, "/hangup", true))
    {
        if (!Player[playerid][pCallPartner]) return SendError(playerid, "You are not on a call.");
        EndCall(playerid, "They hung up.");
        SendClientMessage(playerid, COLOR_GREY, "You hung up.");
        return 1;
    }

    // ---- Gangs ------------------------------------------------------------
    if (!strcmp(cmd, "/turfs", true))
    {
        for (new t = 0; t < sizeof Turfs; t++)
        {
            format(msg, sizeof msg, "%s - %s%s", Turfs[t][tName], FactionNames[TurfOwner[t]],
                TurfAttacker[t] ? " (under attack!)" : "");
            SendClientMessage(playerid, FactionColours[TurfOwner[t]], msg);
        }
        return 1;
    }
    if (!strcmp(cmd, "/capture", true))
    {
        new gang = Player[playerid][pFaction];
        if (!IsGang(gang)) return SendError(playerid, "Only gang members can capture turfs.");
        new t = TurfAt(playerid);
        if (t == -1) return SendError(playerid, "You are not on a gang turf (see the coloured zones on your map).");
        if (TurfOwner[t] == gang) return SendError(playerid, "Your gang already owns this turf.");
        if (TurfAttacker[t]) return SendError(playerid, "This turf is already under attack.");
        if (gettime() < TurfCooldown[t]) return SendError(playerid, "This turf was fought over recently, try again later.");

        TurfAttacker[t] = gang;
        TurfTimeLeft[t] = TURF_CAPTURE_TIME;
        GangZoneFlashForAll(TurfZone[t], (FactionColours[gang] & 0xFFFFFF00) | 0x80);
        format(msg, sizeof msg, "%s started a turf war for %s! Hold the turf for %d seconds.",
            FactionNames[gang], Turfs[t][tName], TURF_CAPTURE_TIME);
        SendFactionMessage(gang, FactionColours[gang], msg);
        format(msg, sizeof msg, "%s are attacking your turf %s! Get there to defend it.", FactionNames[gang], Turfs[t][tName]);
        SendFactionMessage(TurfOwner[t], COLOR_ERROR, msg);
        return 1;
    }

    // ---- Vehicles ---------------------------------------------------------
    if (!strcmp(cmd, "/engine", true))
    {
        new vehicleid = GetPlayerVehicleID(playerid);
        if (!vehicleid || GetPlayerState(playerid) != PLAYER_STATE_DRIVER) return SendError(playerid, "You are not driving a vehicle.");
        new bool:engine, bool:lights, bool:alarm, bool:doors, bool:bonnet, bool:boot, bool:objective;
        GetVehicleParamsEx(vehicleid, engine, lights, alarm, doors, bonnet, boot, objective);
        SetVehicleParamsEx(vehicleid, !engine, !engine, alarm, doors, bonnet, boot, objective);
        format(msg, sizeof msg, engine ? "* %s turns off the engine." : "* %s starts the engine.", RPName(playerid));
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_PURPLE, msg);
        return 1;
    }
    if (!strcmp(cmd, "/buycar", true))
    {
        if (!IsPlayerInRangeOfPoint(playerid, 4.0, DEALER_X, DEALER_Y, DEALER_Z))
            return SendError(playerid, "You need to be at the car dealership (Rodeo).");
        new list[512];
        list = "Vehicle\tPrice\n";
        for (new i = 0; i < sizeof DealerCars; i++)
        {
            format(list, sizeof list, "%s%s\t{9ACD32}$%d\n", list, DealerCars[i][dcName], DealerCars[i][dcPrice]);
        }
        ShowPlayerDialog(playerid, DIALOG_DEALERSHIP, DIALOG_STYLE_TABLIST_HEADERS, "Car Dealership", list, "Buy", "Cancel");
        return 1;
    }
    if (!strcmp(cmd, "/lock", true))
    {
        new Float:x, Float:y, Float:z;
        for (new v = 1; v < MAX_VEHICLES; v++)
        {
            if (OwnedVehicle[v][ovDBID] == 0 || OwnedVehicle[v][ovOwner] != Player[playerid][pID]) continue;
            GetVehiclePos(v, x, y, z);
            if (!IsPlayerInRangeOfPoint(playerid, 5.0, x, y, z)) continue;

            new bool:engine, bool:lights, bool:alarm, bool:doors, bool:bonnet, bool:boot, bool:objective;
            GetVehicleParamsEx(v, engine, lights, alarm, doors, bonnet, boot, objective);
            OwnedVehicle[v][ovLocked] = !OwnedVehicle[v][ovLocked];
            SetVehicleParamsEx(v, engine, lights, alarm, OwnedVehicle[v][ovLocked], bonnet, boot, objective);
            GameTextForPlayer(playerid, OwnedVehicle[v][ovLocked] ? "~r~Locked" : "~g~Unlocked", 2000, 3);
            PlayerPlaySound(playerid, 1145, 0.0, 0.0, 0.0);
            return 1;
        }
        return SendError(playerid, "You are not near one of your vehicles.");
    }
    if (!strcmp(cmd, "/park", true))
    {
        new vehicleid = GetPlayerVehicleID(playerid);
        if (!vehicleid || OwnedVehicle[vehicleid][ovOwner] != Player[playerid][pID] || OwnedVehicle[vehicleid][ovDBID] == 0)
            return SendError(playerid, "You must be in one of your own vehicles.");
        new Float:x, Float:y, Float:z, Float:a;
        GetVehiclePos(vehicleid, x, y, z);
        GetVehicleZAngle(vehicleid, a);
        DB_FreeResultSet(DB_ExecuteQuery(gDB, "UPDATE vehicles SET x=%f, y=%f, z=%f, a=%f WHERE id=%d",
            x, y, z, a, OwnedVehicle[vehicleid][ovDBID]));
        SendClientMessage(playerid, COLOR_SUCCESS, "Vehicle parked. It will spawn here from now on.");
        return 1;
    }
    if (!strcmp(cmd, "/mycars", true))
    {
        new count;
        for (new v = 1; v < MAX_VEHICLES; v++)
        {
            if (OwnedVehicle[v][ovDBID] == 0 || OwnedVehicle[v][ovOwner] != Player[playerid][pID]) continue;
            new Float:x, Float:y, Float:z;
            GetVehiclePos(v, x, y, z);
            format(msg, sizeof msg, "Vehicle #%d (model %d) - %s", ++count, OwnedVehicle[v][ovModel],
                OwnedVehicle[v][ovLocked] ? "locked" : "unlocked");
            SendClientMessage(playerid, COLOR_INFO, msg);
        }
        if (!count) SendError(playerid, "You don't own any vehicles. Visit the dealership.");
        return 1;
    }

    // ---- Factions ---------------------------------------------------------
    if (!strcmp(cmd, "/f", true))
    {
        if (Player[playerid][pFaction] == FACTION_NONE) return SendError(playerid, "You are not in a faction.");
        new text[128];
        text = strrest(cmdtext, idx);
        if (text[0] == EOS) return SendUsage(playerid, "/f [radio message]");
        format(msg, sizeof msg, "** %s %s: %s **",
            FactionRanks[Player[playerid][pFaction]][Player[playerid][pRank]], RPName(playerid), text);
        SendFactionMessage(Player[playerid][pFaction], COLOR_RADIO, msg);
        return 1;
    }
    if (!strcmp(cmd, "/duty", true))
    {
        new faction = Player[playerid][pFaction];
        if (faction == FACTION_NONE) return SendError(playerid, "You are not in a faction.");

        Player[playerid][pOnDuty] = !Player[playerid][pOnDuty];
        if (Player[playerid][pOnDuty])
        {
            SetPlayerSkin(playerid, FactionSkins[faction]);
            if (faction == FACTION_LSPD)
            {
                SetPlayerColor(playerid, 0x0000FFFF);
                SetPlayerArmour(playerid, 100.0);
                GivePlayerWeapon(playerid, WEAPON_NITESTICK, 1);
                GivePlayerWeapon(playerid, WEAPON_SILENCED, 200);
                GivePlayerWeapon(playerid, WEAPON_SHOTGUN, 50);
            }
            else if (IsGang(faction))
            {
                SetPlayerColor(playerid, FactionColours[faction]);
                GivePlayerWeapon(playerid, WEAPON_BAT, 1);
                GivePlayerWeapon(playerid, WEAPON_COLT45, 60);
            }
            format(msg, sizeof msg, "* %s %s is now on duty.", FactionRanks[faction][Player[playerid][pRank]], RPName(playerid));
        }
        else
        {
            SetPlayerSkin(playerid, Player[playerid][pSkin]);
            SetPlayerColor(playerid, 0xFFFFFF00);
            ResetPlayerWeapons(playerid);
            SetPlayerArmour(playerid, 0.0);
            format(msg, sizeof msg, "* %s %s is now off duty.", FactionRanks[faction][Player[playerid][pRank]], RPName(playerid));
        }
        SendFactionMessage(faction, COLOR_RADIO, msg);
        return 1;
    }
    if (!strcmp(cmd, "/invite", true))
    {
        if (!IsLeader(playerid)) return SendError(playerid, "Only faction leaders can invite members.");
        new targetid = FindPlayer(strtok(cmdtext, idx));
        if (targetid == INVALID_PLAYER_ID || !Player[targetid][pLoggedIn]) return SendUsage(playerid, "/invite [player]");
        if (Player[targetid][pFaction] != FACTION_NONE) return SendError(playerid, "That player is already in a faction.");
        Player[targetid][pFaction] = Player[playerid][pFaction];
        Player[targetid][pRank] = 1;
        format(msg, sizeof msg, "%s has joined %s.", RPName(targetid), FactionNames[Player[playerid][pFaction]]);
        SendFactionMessage(Player[playerid][pFaction], COLOR_RADIO, msg);
        SavePlayer(targetid);
        return 1;
    }
    if (!strcmp(cmd, "/uninvite", true))
    {
        if (!IsLeader(playerid)) return SendError(playerid, "Only faction leaders can remove members.");
        new targetid = FindPlayer(strtok(cmdtext, idx));
        if (targetid == INVALID_PLAYER_ID || Player[targetid][pFaction] != Player[playerid][pFaction] || targetid == playerid)
            return SendUsage(playerid, "/uninvite [member]");
        format(msg, sizeof msg, "%s has been removed from %s.", RPName(targetid), FactionNames[Player[playerid][pFaction]]);
        SendFactionMessage(Player[playerid][pFaction], COLOR_RADIO, msg);
        Player[targetid][pFaction] = FACTION_NONE;
        Player[targetid][pRank] = 0;
        Player[targetid][pOnDuty] = false;
        SetPlayerSkin(targetid, Player[targetid][pSkin]);
        ResetPlayerWeapons(targetid);
        SavePlayer(targetid);
        return 1;
    }
    if (!strcmp(cmd, "/setrank", true))
    {
        if (!IsLeader(playerid)) return SendError(playerid, "Only faction leaders can change ranks.");
        new targetid = FindPlayer(strtok(cmdtext, idx)), rank = strval(strtok(cmdtext, idx));
        if (targetid == INVALID_PLAYER_ID || Player[targetid][pFaction] != Player[playerid][pFaction] || rank < 1 || rank > MAX_RANK)
            return SendUsage(playerid, "/setrank [member] [1-6]");
        if (rank > Player[playerid][pRank]) return SendError(playerid, "You can't give a rank higher than your own.");
        Player[targetid][pRank] = rank;
        format(msg, sizeof msg, "%s is now %s.", RPName(targetid), FactionRanks[Player[playerid][pFaction]][rank]);
        SendFactionMessage(Player[playerid][pFaction], COLOR_RADIO, msg);
        SavePlayer(targetid);
        return 1;
    }
    if (!strcmp(cmd, "/cuff", true) || !strcmp(cmd, "/uncuff", true))
    {
        if (Player[playerid][pFaction] != FACTION_LSPD || !Player[playerid][pOnDuty])
            return SendError(playerid, "You must be an on-duty police officer.");
        new targetid = FindPlayer(strtok(cmdtext, idx));
        if (targetid == INVALID_PLAYER_ID || targetid == playerid) return SendUsage(playerid, "/cuff [player]");
        new Float:x, Float:y, Float:z;
        GetPlayerPos(targetid, x, y, z);
        if (!IsPlayerInRangeOfPoint(playerid, 3.0, x, y, z)) return SendError(playerid, "That player is not near you.");

        new bool:cuff = !strcmp(cmd, "/cuff", true);
        SetPlayerSpecialAction(targetid, cuff ? SPECIAL_ACTION_CUFFED : SPECIAL_ACTION_NONE);
        TogglePlayerControllable(targetid, !cuff);
        format(msg, sizeof msg, cuff ? "* %s puts handcuffs on %s." : "* %s removes the handcuffs from %s.",
            RPName(playerid), RPName(targetid));
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_PURPLE, msg);
        return 1;
    }
    if (!strcmp(cmd, "/heal", true))
    {
        if (Player[playerid][pFaction] != FACTION_MEDIC || !Player[playerid][pOnDuty])
            return SendError(playerid, "You must be an on-duty medic.");
        new targetid = FindPlayer(strtok(cmdtext, idx));
        if (targetid == INVALID_PLAYER_ID) return SendUsage(playerid, "/heal [player]");
        new Float:x, Float:y, Float:z;
        GetPlayerPos(targetid, x, y, z);
        if (!IsPlayerInRangeOfPoint(playerid, 3.0, x, y, z)) return SendError(playerid, "That player is not near you.");
        SetPlayerHealth(targetid, 100.0);
        GiveMoney(playerid, 200);
        format(msg, sizeof msg, "* %s treats %s's wounds.", RPName(playerid), RPName(targetid));
        SendNearbyMessage(playerid, CHAT_RANGE, COLOR_PURPLE, msg);
        return 1;
    }

    // ---- Admin ------------------------------------------------------------
    if (!strcmp(cmd, "/makeadmin", true))
    {
        // RCON admins bootstrap the first server staff
        if (!IsPlayerAdmin(playerid) && !CheckAdmin(playerid, 5)) return 1;
        new targetid = FindPlayer(strtok(cmdtext, idx)), level = strval(strtok(cmdtext, idx));
        if (targetid == INVALID_PLAYER_ID || level < 0 || level > 5) return SendUsage(playerid, "/makeadmin [player] [0-5]");
        Player[targetid][pAdmin] = level;
        format(msg, sizeof msg, "%s set %s's admin level to %d.", PlayerName(playerid), PlayerName(targetid), level);
        SendAdminMessage(COLOR_ADMIN, msg);
        SendClientMessage(targetid, COLOR_ADMIN, msg);
        SavePlayer(targetid);
        return 1;
    }
    if (!strcmp(cmd, "/makeleader", true))
    {
        if (!CheckAdmin(playerid, 3)) return 1;
        new targetid = FindPlayer(strtok(cmdtext, idx)), faction = strval(strtok(cmdtext, idx));
        if (targetid == INVALID_PLAYER_ID || faction < 0 || faction >= MAX_FACTIONS)
            return SendUsage(playerid, "/makeleader [player] [0=none 1=LSPD 2=Medics 3=Grove 4=Ballas]");
        Player[targetid][pFaction] = faction;
        Player[targetid][pRank] = faction ? MAX_RANK : 0;
        format(msg, sizeof msg, "%s made %s leader of %s.", PlayerName(playerid), PlayerName(targetid), FactionNames[faction]);
        SendAdminMessage(COLOR_ADMIN, msg);
        SendClientMessage(targetid, COLOR_ADMIN, msg);
        SavePlayer(targetid);
        return 1;
    }
    if (!strcmp(cmd, "/a", true))
    {
        if (!CheckAdmin(playerid, 1)) return 1;
        new text[128];
        text = strrest(cmdtext, idx);
        if (text[0] == EOS) return SendUsage(playerid, "/a [admin chat]");
        format(msg, sizeof msg, "[Admin %d] %s: %s", Player[playerid][pAdmin], PlayerName(playerid), text);
        SendAdminMessage(COLOR_ADMIN, msg);
        return 1;
    }
    if (!strcmp(cmd, "/goto", true) || !strcmp(cmd, "/gethere", true))
    {
        if (!CheckAdmin(playerid, 1)) return 1;
        new targetid = FindPlayer(strtok(cmdtext, idx));
        if (targetid == INVALID_PLAYER_ID) return SendUsage(playerid, "/goto|/gethere [player]");
        new from = playerid, to = targetid;
        if (!strcmp(cmd, "/gethere", true))
        {
            from = targetid;
            to = playerid;
        }
        new Float:x, Float:y, Float:z;
        GetPlayerPos(to, x, y, z);
        SetPlayerPos(from, x + 1.0, y, z);
        SetPlayerInterior(from, GetPlayerInterior(to));
        SetPlayerVirtualWorld(from, GetPlayerVirtualWorld(to));
        return 1;
    }
    if (!strcmp(cmd, "/kick", true) || !strcmp(cmd, "/ban", true))
    {
        new bool:ban = !strcmp(cmd, "/ban", true);
        if (!CheckAdmin(playerid, ban ? 2 : 1)) return 1;
        new targetid = FindPlayer(strtok(cmdtext, idx)), reason[128];
        reason = strrest(cmdtext, idx);
        if (targetid == INVALID_PLAYER_ID || reason[0] == EOS) return SendUsage(playerid, "/kick|/ban [player] [reason]");
        if (Player[targetid][pAdmin] > Player[playerid][pAdmin]) return SendError(playerid, "You can't do that to a higher admin.");

        if (ban)
        {
            DB_FreeResultSet(DB_ExecuteQuery(gDB, "INSERT OR REPLACE INTO bans (name, reason, admin) VALUES ('%q', '%q', '%q')",
                PlayerName(targetid), reason, PlayerName(playerid)));
        }
        format(msg, sizeof msg, "AdmCmd: %s was %s by %s. Reason: %s", PlayerName(targetid), ban ? "banned" : "kicked",
            PlayerName(playerid), reason);
        SendClientMessageToAll(COLOR_ERROR, msg);
        SetTimerEx("DelayedKick", 500, false, "i", targetid);
        return 1;
    }
    if (!strcmp(cmd, "/unban", true))
    {
        if (!CheckAdmin(playerid, 3)) return 1;
        new name[64];
        name = strtok(cmdtext, idx);
        if (name[0] == EOS) return SendUsage(playerid, "/unban [Firstname_Lastname]");
        DB_FreeResultSet(DB_ExecuteQuery(gDB, "DELETE FROM bans WHERE name='%q'", name));
        format(msg, sizeof msg, "%s unbanned %s.", PlayerName(playerid), name);
        SendAdminMessage(COLOR_ADMIN, msg);
        return 1;
    }
    if (!strcmp(cmd, "/setmoney", true))
    {
        if (!CheckAdmin(playerid, 4)) return 1;
        new targetid = FindPlayer(strtok(cmdtext, idx)), amount = strval(strtok(cmdtext, idx));
        if (targetid == INVALID_PLAYER_ID || amount < 0) return SendUsage(playerid, "/setmoney [player] [amount]");
        GiveMoney(targetid, amount - Player[targetid][pMoney]);
        format(msg, sizeof msg, "%s set %s's cash to $%d.", PlayerName(playerid), PlayerName(targetid), amount);
        SendAdminMessage(COLOR_ADMIN, msg);
        SavePlayer(targetid);
        return 1;
    }
    if (!strcmp(cmd, "/createhouse", true))
    {
        if (!CheckAdmin(playerid, 4)) return 1;
        new price = strval(strtok(cmdtext, idx)), type = strval(strtok(cmdtext, idx)) - 1;
        if (price <= 0 || type < 0 || type >= sizeof HouseInteriors)
            return SendUsage(playerid, "/createhouse [price] [1=small 2=medium 3=large 4=villa 5=mansion] (stand at the door)");
        if (GetPlayerVirtualWorld(playerid) != 0 || GetPlayerInterior(playerid) != 0) return SendError(playerid, "Houses go outside.");
        new h = -1;
        for (new i = 0; i < MAX_HOUSES; i++)
        {
            if (!House[i][hDBID]) { h = i; break; }
        }
        if (h == -1) return SendError(playerid, "The house limit is reached.");

        new Float:x, Float:y, Float:z;
        GetPlayerPos(playerid, x, y, z);
        DB_FreeResultSet(DB_ExecuteQuery(gDB, "INSERT INTO houses (price, type, x, y, z) VALUES (%d, %d, %f, %f, %f)",
            price, type, x, y, z));
        new DBResult:result = DB_ExecuteQuery(gDB, "SELECT last_insert_rowid()");
        House[h][hDBID] = DB_GetFieldInt(result, 0);
        DB_FreeResultSet(result);
        House[h][hOwner] = 0;
        House[h][hOwnerName][0] = EOS;
        House[h][hPrice] = price;
        House[h][hType] = type;
        House[h][hX] = x;
        House[h][hY] = y;
        House[h][hZ] = z;
        House[h][hLocked] = true;
        RefreshHouse(h);
        format(msg, sizeof msg, "%s created a %s house for $%d (house #%d).", PlayerName(playerid), HouseInteriors[type][hiName], price, h);
        SendAdminMessage(COLOR_ADMIN, msg);
        return 1;
    }
    if (!strcmp(cmd, "/deletehouse", true))
    {
        if (!CheckAdmin(playerid, 4)) return 1;
        new h = HouseAtDoor(playerid);
        if (h == -1) return SendError(playerid, "Stand at the house door.");
        DB_FreeResultSet(DB_ExecuteQuery(gDB, "DELETE FROM houses WHERE id=%d", House[h][hDBID]));
        DestroyPickup(House[h][hPickup] - 1);
        Delete3DTextLabel(House[h][hLabel]);
        static const empty[E_HOUSE];
        House[h] = empty;
        format(msg, sizeof msg, "%s deleted house #%d.", PlayerName(playerid), h);
        SendAdminMessage(COLOR_ADMIN, msg);
        return 1;
    }
    if (!strcmp(cmd, "/veh", true))
    {
        if (!CheckAdmin(playerid, 3)) return 1;
        new model = strval(strtok(cmdtext, idx));
        if (model < 400 || model > 611) return SendUsage(playerid, "/veh [model 400-611]");
        new Float:x, Float:y, Float:z, Float:a;
        GetPlayerPos(playerid, x, y, z);
        GetPlayerFacingAngle(playerid, a);
        new vehicleid = CreateVehicle(model, x, y, z + 1.0, a, -1, -1, -1);
        PutPlayerInVehicle(playerid, vehicleid, 0);
        return 1;
    }

    return 0;
}
