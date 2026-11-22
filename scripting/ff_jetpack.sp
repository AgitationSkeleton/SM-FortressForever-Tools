/**
 * ff_jetpack - server control of the Pyro's jetpack.
 *
 *   ff_jetpack_enable 1           0 = no Pyro can use the jetpack
 *   ff_jetpack_infinite 0         1 = fuel never runs out
 *   ff_jetpack_recharge_scale 1   FF's recharge rate (25 fuel per second) times this; 0 = none
 *   ff_jetpack_spawn_fuel 100     fuel (percent) a Pyro spawns with
 *
 *   sm_ff_jetpack <target> <1|0|reset>   allow / forbid / back to ff_jetpack_enable
 *   sm_ff_jetpack_fuel <target> <0-100>  set fuel (percent)
 *
 * Fuel runs 0..200 (FF_JETPACK_MAXFUEL); a jump needs 2. FF recharges 2 units every 0.08 s and
 * predicts the jetpack on the client, so a changed recharge rate or infinite fuel shows on the
 * HUD with the next network update (the fuel value is networked and the client is corrected).
 */
#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#include <fortressforever>

#define PLUGIN_VERSION "1.0.0"
#define TICK 0.1
#define FF_RECHARGE_PER_SEC 25.0

public Plugin myinfo =
{
	name = "FF Jetpack",
	author = "AgitationSkeleton",
	description = "Server control of the Pyro's jetpack: on/off, infinite fuel, recharge rate, spawn fuel",
	version = PLUGIN_VERSION,
	url = "https://github.com/AgitationSkeleton/SM-FortressForever-Tools"
};

ConVar g_cvEnable, g_cvInfinite, g_cvRecharge, g_cvSpawnFuel;
int g_iOverride[MAXPLAYERS + 1] = { -1, ... };   // -1 = follow ff_jetpack_enable
float g_flAccum[MAXPLAYERS + 1];

public void OnPluginStart()
{
	CreateConVar("ff_jetpack_version", PLUGIN_VERSION, "FF Jetpack version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnable = CreateConVar("ff_jetpack_enable", "1", "Allow Pyros to use the jetpack", _, true, 0.0, true, 1.0);
	g_cvInfinite = CreateConVar("ff_jetpack_infinite", "0", "Jetpack fuel never runs out", _, true, 0.0, true, 1.0);
	g_cvRecharge = CreateConVar("ff_jetpack_recharge_scale", "1.0", "Jetpack fuel recharge rate, times FF's own (0 = no recharge)", _, true, 0.0, true, 20.0);
	g_cvSpawnFuel = CreateConVar("ff_jetpack_spawn_fuel", "100", "Jetpack fuel (percent) a Pyro spawns with", _, true, 0.0, true, 100.0);
	AutoExecConfig(true, "ff_jetpack");
	g_cvEnable.AddChangeHook(OnEnableChanged);

	HookEvent("player_spawn", Event_Spawn);
	RegAdminCmd("sm_ff_jetpack", Cmd_Jetpack, ADMFLAG_SLAY, "sm_ff_jetpack <target> <1|0|reset>");
	RegAdminCmd("sm_ff_jetpack_fuel", Cmd_Fuel, ADMFLAG_SLAY, "sm_ff_jetpack_fuel <target> <0-100>");
	LoadTranslations("common.phrases");
	CreateTimer(TICK, Timer_Tick, _, TIMER_REPEAT);
}

public void OnPluginEnd()
{
	// leave every player with FF's default (jetpack allowed)
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			FF_SetJetpackAllowed(i, true);
}

public void OnClientDisconnect(int client)
{
	g_iOverride[client] = -1;
	g_flAccum[client] = 0.0;
}

public void OnEnableChanged(ConVar cv, const char[] oldValue, const char[] newValue)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			ApplyAllowed(i);
}

bool Allowed(int client)
{
	return g_iOverride[client] == -1 ? g_cvEnable.BoolValue : g_iOverride[client] == 1;
}

void ApplyAllowed(int client)
{
	bool want = Allowed(client);
	if (FF_IsJetpackAllowed(client) != want)
		FF_SetJetpackAllowed(client, want);
}

public void Event_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
		RequestFrame(Frame_Spawned, GetClientUserId(client));
}

public void Frame_Spawned(int userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client))
		return;
	ApplyAllowed(client);
	g_flAccum[client] = 0.0;
	if (FF_GetClass(client) == FFClass_Pyro)
		FF_SetJetpackFuel(client, RoundToNearest(g_cvSpawnFuel.FloatValue * FF_JETPACK_MAXFUEL / 100.0));
}

public Action Timer_Tick(Handle timer)
{
	bool infinite = g_cvInfinite.BoolValue;
	float extra = (g_cvRecharge.FloatValue - 1.0) * FF_RECHARGE_PER_SEC * TICK;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		ApplyAllowed(i);
		if (FF_GetClass(i) != FFClass_Pyro)
			continue;
		if (infinite)
		{
			FF_SetJetpackFuel(i, FF_JETPACK_MAXFUEL);
			continue;
		}
		if (extra == 0.0 || FF_IsJetpacking(i))
		{
			g_flAccum[i] = 0.0;
			continue;
		}
		// FF recharges by itself; add (or take away) the difference to reach the scaled rate
		int fuel = FF_GetJetpackFuel(i);
		if (extra > 0.0 && fuel >= FF_JETPACK_MAXFUEL)
			continue;
		g_flAccum[i] += extra;
		int whole = RoundToZero(g_flAccum[i]);
		if (whole != 0)
		{
			g_flAccum[i] -= float(whole);
			FF_SetJetpackFuel(i, fuel + whole);
		}
	}
	return Plugin_Continue;
}

public Action Cmd_Jetpack(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[FF] Usage: sm_ff_jetpack <target> <1|0|reset>");
		return Plugin_Handled;
	}
	char pattern[64], arg[16], tname[MAX_TARGET_LENGTH];
	GetCmdArg(1, pattern, sizeof(pattern));
	GetCmdArg(2, arg, sizeof(arg));
	int value = StrEqual(arg, "reset", false) ? -1 : (StringToInt(arg) != 0 ? 1 : 0);
	int list[MAXPLAYERS];
	bool ml;
	int n = ProcessTargetString(pattern, client, list, sizeof(list), 0, tname, sizeof(tname), ml);
	if (n <= 0)
	{
		ReplyToTargetError(client, n);
		return Plugin_Handled;
	}
	for (int i = 0; i < n; i++)
	{
		g_iOverride[list[i]] = value;
		ApplyAllowed(list[i]);
	}
	ShowActivity2(client, "[FF] ", "%s the jetpack for %s", value == -1 ? "Reset" : (value ? "Allowed" : "Disabled"), tname);
	return Plugin_Handled;
}

public Action Cmd_Fuel(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[FF] Usage: sm_ff_jetpack_fuel <target> <0-100>");
		return Plugin_Handled;
	}
	char pattern[64], tname[MAX_TARGET_LENGTH];
	GetCmdArg(1, pattern, sizeof(pattern));
	float pct = GetCmdArgFloat(2);
	if (pct < 0.0) pct = 0.0;
	if (pct > 100.0) pct = 100.0;
	int list[MAXPLAYERS];
	bool ml;
	int n = ProcessTargetString(pattern, client, list, sizeof(list), COMMAND_FILTER_ALIVE, tname, sizeof(tname), ml);
	if (n <= 0)
	{
		ReplyToTargetError(client, n);
		return Plugin_Handled;
	}
	int done = 0;
	for (int i = 0; i < n; i++)
	{
		if (FF_GetClass(list[i]) != FFClass_Pyro)
			continue;
		FF_SetJetpackFuel(list[i], RoundToNearest(pct * FF_JETPACK_MAXFUEL / 100.0));
		done++;
	}
	ShowActivity2(client, "[FF] ", "Set jetpack fuel to %.0f%% for %s (%d Pyro(s))", pct, tname, done);
	return Plugin_Handled;
}
