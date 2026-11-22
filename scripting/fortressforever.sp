/**
 * Fortress Forever 2.0 tools for SourceMod: natives and a forward for FF's classes, teams,
 * armour, grenades, Spy state and buildings (library "fortressforever", see
 * scripting/include/fortressforever.inc).
 *
 * Pure SourcePawn. Values are read from and written to FF's networked properties; class
 * changes, respawns, refills, disguises and class limits go through FF's own map Lua API
 * (the lua_dostring server command), so they behave exactly as when a map script does them.
 *
 *   sm_ff_status            show what the plugin found (team entities, Lua availability)
 *   sm_ff_class <target> <class> [0|1]   set a class (1 = respawn, default)
 *   sm_ff_respawn <target>  respawn players
 *   sm_ff_regen <target>    refill players
 */
#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define FORTRESSFOREVER_PROVIDER
#include <fortressforever>

#define PLUGIN_VERSION "1.0.0"

public Plugin myinfo =
{
	name = "Fortress Forever Tools",
	author = "AgitationSkeleton",
	description = "Natives and forwards for Fortress Forever 2.0",
	version = PLUGIN_VERSION,
	url = "https://github.com/AgitationSkeleton/SM-FortressForever-Tools"
};

static const char g_sClassAT[][] = { "", "Scout", "Sniper", "Soldier", "Demoman", "Medic", "HWGuy", "Pyro", "Spy", "Engineer", "Civilian" };

GlobalForward g_hClassChanged;
int g_iTeamEnt[6] = { -1, ... };
int g_iClassesOffset = -1;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	char folder[32];
	GetGameFolderName(folder, sizeof(folder));
	if (!StrEqual(folder, "fortressforever", false))
	{
		strcopy(error, err_max, "fortressforever.smx only runs on Fortress Forever");
		return APLRes_Failure;
	}
	RegPluginLibrary("fortressforever");

	CreateNative("FF_GetClass", N_GetClass);
	CreateNative("FF_SetClass", N_SetClass);
	CreateNative("FF_RespawnPlayer", N_RespawnPlayer);
	CreateNative("FF_RegeneratePlayer", N_RegeneratePlayer);
	CreateNative("FF_GetArmor", N_GetArmor);
	CreateNative("FF_SetArmor", N_SetArmor);
	CreateNative("FF_GetMaxArmor", N_GetMaxArmor);
	CreateNative("FF_SetMaxArmor", N_SetMaxArmor);
	CreateNative("FF_GetGrenades", N_GetGrenades);
	CreateNative("FF_SetGrenades", N_SetGrenades);
	CreateNative("FF_GetDisguise", N_GetDisguise);
	CreateNative("FF_SetDisguise", N_SetDisguise);
	CreateNative("FF_RemoveDisguise", N_RemoveDisguise);
	CreateNative("FF_IsCloaked", N_IsCloaked);
	CreateNative("FF_GetBuilding", N_GetBuilding);
	CreateNative("FF_GetTeamEntity", N_GetTeamEntity);
	CreateNative("FF_GetClassLimit", N_GetClassLimit);
	CreateNative("FF_SetClassLimit", N_SetClassLimit);
	CreateNative("FF_GetTeamAllies", N_GetTeamAllies);
	CreateNative("FF_SetTeamAllies", N_SetTeamAllies);
	CreateNative("FF_AreTeamsAllied", N_AreTeamsAllied);
	CreateNative("FF_IsTeamActive", N_IsTeamActive);
	CreateNative("FF_GetTeamMaxPlayers", N_GetTeamMaxPlayers);
	CreateNative("FF_SetTeamMaxPlayers", N_SetTeamMaxPlayers);
	CreateNative("FF_IsTeamFFA", N_IsTeamFFA);
	CreateNative("FF_SetTeamFFA", N_SetTeamFFA);
	CreateNative("FF_RunLua", N_RunLua);
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("fortressforever_tools_version", PLUGIN_VERSION, "Fortress Forever Tools version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_hClassChanged = new GlobalForward("FF_OnPlayerClassChanged", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	HookEvent("player_changeclass", Event_ChangeClass);

	g_iClassesOffset = FindSendPropInfo("CFFTeam", "m_iClasses");

	RegAdminCmd("sm_ff_status", Cmd_Status, ADMFLAG_GENERIC, "Fortress Forever Tools status");
	RegAdminCmd("sm_ff_class", Cmd_Class, ADMFLAG_SLAY, "sm_ff_class <target> <class> [respawn 0|1]");
	RegAdminCmd("sm_ff_respawn", Cmd_Respawn, ADMFLAG_SLAY, "sm_ff_respawn <target>");
	RegAdminCmd("sm_ff_regen", Cmd_Regen, ADMFLAG_CHEATS, "sm_ff_regen <target>");
	LoadTranslations("common.phrases");
}

public void OnMapStart()
{
	for (int i = 0; i < sizeof(g_iTeamEnt); i++)
		g_iTeamEnt[i] = -1;
}

// ---------------------------------------------------------------- helpers

void CheckClient(int client)
{
	if (client < 1 || client > MaxClients)
		ThrowNativeError(SP_ERROR_INDEX, "Client index %d is invalid", client);
	if (!IsClientInGame(client))
		ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in game", client);
}

int TeamEnt(int team)
{
	if (team < 0 || team >= sizeof(g_iTeamEnt))
		return -1;
	int e = g_iTeamEnt[team];
	if (e > 0 && IsValidEntity(e) && GetEntProp(e, Prop_Send, "m_iTeamNum") == team)
		return e;
	g_iTeamEnt[team] = -1;
	e = -1;
	while ((e = FindEntityByClassname(e, "ff_team_manager")) != -1)
	{
		if (GetEntProp(e, Prop_Send, "m_iTeamNum") == team)
		{
			g_iTeamEnt[team] = e;
			return e;
		}
	}
	return -1;
}

int CheckTeam(any team)
{
	int e = TeamEnt(team);
	if (e == -1)
		ThrowNativeError(SP_ERROR_NATIVE, "Team %d has no ff_team_manager", team);
	return e;
}

int ClassOf(int client)
{
	return GetEntProp(client, Prop_Send, "m_iClassStatus") & 0x0F;
}

// Runs FF map Lua through lua_dostring. ServerExecute() runs it at once, except inside a
// server console / RCON command: the command buffer is then already executing, and the Lua
// runs right after that command. The console parser splits commands at ';' and newlines and
// treats '"' and '//' specially, so code containing them is refused.
bool RunLua(const char[] code)
{
	if (StrContains(code, ";") != -1 || StrContains(code, "\"") != -1 || StrContains(code, "//") != -1
		|| StrContains(code, "\n") != -1 || StrContains(code, "\r") != -1)
		return false;
	ServerCommand("lua_dostring %s", code);
	ServerExecute();
	return true;
}

// ---------------------------------------------------------------- natives

public any N_GetClass(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	return ClassOf(client);
}

public any N_SetClass(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	int cls = GetNativeCell(2);
	bool respawn = GetNativeCell(3);
	if (cls < 1 || cls > 10)
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid class %d", cls);
	if (GetClientTeam(client) < 2)
		return false;
	if (!IsPlayerAlive(client))
		respawn = true;
	char code[256];
	FormatEx(code, sizeof(code), "ApplyToPlayer(CastToPlayer(GetEntity(%d)), { AT.kChangeClass%s%s })",
		client, g_sClassAT[cls], respawn ? ", AT.kRespawnPlayers" : "");
	RunLua(code);
	return ClassOf(client) == cls;
}

public any N_RespawnPlayer(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	if (GetClientTeam(client) < 2)
		return false;
	char code[128];
	FormatEx(code, sizeof(code), "ApplyToPlayer(CastToPlayer(GetEntity(%d)), { AT.kRespawnPlayers })", client);
	RunLua(code);
	return IsPlayerAlive(client);
}

public any N_RegeneratePlayer(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	return Regenerate(client);
}

bool Regenerate(int client)
{
	if (!IsPlayerAlive(client) || GetClientTeam(client) < 2)
		return false;
	char code[512];
	FormatEx(code, sizeof(code), "local p = CastToPlayer(GetEntity(%d)) if p then p:AddHealth(1000) p:AddArmor(1000) "
		... "for _, a in ipairs({ Ammo.kShells, Ammo.kNails, Ammo.kCells, Ammo.kRockets, Ammo.kDetpack, Ammo.kManCannon, Ammo.kGren1, Ammo.kGren2 }) do p:AddAmmo(a, 1000) end "
		... "p:ReloadClips() end", client);
	RunLua(code);
	return true;
}

public any N_GetArmor(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	return GetEntProp(client, Prop_Send, "m_iArmor");
}

public any N_SetArmor(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	SetEntProp(client, Prop_Send, "m_iArmor", GetNativeCell(2));
	return 0;
}

public any N_GetMaxArmor(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	return GetEntProp(client, Prop_Send, "m_iMaxArmor");
}

public any N_SetMaxArmor(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	SetEntProp(client, Prop_Send, "m_iMaxArmor", GetNativeCell(2));
	return 0;
}

public any N_GetGrenades(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	return GetEntProp(client, Prop_Send, GetNativeCell(2) == FFGrenade_Secondary ? "m_iSecondary" : "m_iPrimary");
}

public any N_SetGrenades(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	int n = GetNativeCell(3);
	if (n < 0) n = 0;
	SetEntProp(client, Prop_Send, GetNativeCell(2) == FFGrenade_Secondary ? "m_iSecondary" : "m_iPrimary", n);
	return 0;
}

public any N_GetDisguise(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	int d = GetEntProp(client, Prop_Send, "m_iSpyDisguise");
	bool disguised = ClassOf(client) == 8 && d != 0;
	SetNativeCellRef(2, disguised ? (d & 0x0F) : 0);
	SetNativeCellRef(3, disguised ? ((d & 0xF0) >> 4) : 0);
	return disguised;
}

public any N_SetDisguise(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	int team = GetNativeCell(2), cls = GetNativeCell(3);
	if (team < 2 || team > 5 || cls < 1 || cls > 10)
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid disguise team %d / class %d", team, cls);
	if (ClassOf(client) != 8 || !IsPlayerAlive(client))
		return false;
	char code[128];
	FormatEx(code, sizeof(code), "local p = CastToPlayer(GetEntity(%d)) if p then p:SetDisguise(%d, %d, true) end", client, team, cls);
	RunLua(code);
	// FF finishes an instant disguise on the player's next think (PreThink), so only the
	// request is visible now: m_iLastSpyDisguise holds the requested disguise.
	return GetEntProp(client, Prop_Send, "m_iLastSpyDisguise") == (team | (cls << 4));
}

public any N_RemoveDisguise(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	if (GetEntProp(client, Prop_Send, "m_iSpyDisguise") == 0)
		return 0;
	char code[96];
	FormatEx(code, sizeof(code), "local p = CastToPlayer(GetEntity(%d)) if p then p:ResetDisguise() end", client);
	RunLua(code);
	return 0;
}

public any N_IsCloaked(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	return GetEntProp(client, Prop_Send, "m_iCloaked") != 0;
}

public any N_GetBuilding(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	CheckClient(client);
	static const char props[][] = { "m_hDispenser", "m_hSentryGun", "m_hDetpack", "m_hManCannon" };
	int t = GetNativeCell(2);
	if (t < 0 || t >= sizeof(props))
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid building type %d", t);
	return GetEntPropEnt(client, Prop_Send, props[t]);
}

public any N_GetTeamEntity(Handle plugin, int numParams)
{
	return TeamEnt(GetNativeCell(1));
}

public any N_GetClassLimit(Handle plugin, int numParams)
{
	int e = CheckTeam(GetNativeCell(1));
	int cls = GetNativeCell(2);
	if (cls < 1 || cls > 10)
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid class %d", cls);
	return GetEntData(e, g_iClassesOffset + 4 * cls);
}

public any N_SetClassLimit(Handle plugin, int numParams)
{
	int team = GetNativeCell(1);
	int e = CheckTeam(team);
	int cls = GetNativeCell(2), limit = GetNativeCell(3);
	if (cls < 1 || cls > 10)
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid class %d", cls);
	if (limit < -1)
		limit = -1;
	char code[96];
	FormatEx(code, sizeof(code), "SetTeamClassLimit(%d, %d, %d)", team, cls, limit);
	RunLua(code);
	return GetEntData(e, g_iClassesOffset + 4 * cls) == limit;
}

public any N_GetTeamAllies(Handle plugin, int numParams)
{
	return GetEntProp(CheckTeam(GetNativeCell(1)), Prop_Send, "m_iAllies");
}

public any N_SetTeamAllies(Handle plugin, int numParams)
{
	int team = GetNativeCell(1);
	SetEntProp(CheckTeam(team), Prop_Send, "m_iAllies", GetNativeCell(2) & ~(1 << team));
	return 0;
}

public any N_AreTeamsAllied(Handle plugin, int numParams)
{
	int t1 = GetNativeCell(1), t2 = GetNativeCell(2);
	if (t1 == t2)
		return true;
	int e = TeamEnt(t1);
	return e != -1 && (GetEntProp(e, Prop_Send, "m_iAllies") & (1 << t2)) != 0;
}

public any N_IsTeamActive(Handle plugin, int numParams)
{
	int e = TeamEnt(GetNativeCell(1));
	return e != -1 && GetEntProp(e, Prop_Send, "m_iMaxPlayers") != -1;
}

public any N_GetTeamMaxPlayers(Handle plugin, int numParams)
{
	return GetEntProp(CheckTeam(GetNativeCell(1)), Prop_Send, "m_iMaxPlayers");
}

public any N_SetTeamMaxPlayers(Handle plugin, int numParams)
{
	SetEntProp(CheckTeam(GetNativeCell(1)), Prop_Send, "m_iMaxPlayers", GetNativeCell(2));
	return 0;
}

public any N_IsTeamFFA(Handle plugin, int numParams)
{
	return GetEntProp(CheckTeam(GetNativeCell(1)), Prop_Send, "m_bFFA") != 0;
}

public any N_SetTeamFFA(Handle plugin, int numParams)
{
	SetEntProp(CheckTeam(GetNativeCell(1)), Prop_Send, "m_bFFA", GetNativeCell(2) ? 1 : 0);
	return 0;
}

public any N_RunLua(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(1, len);
	char[] code = new char[len + 1];
	GetNativeString(1, code, len + 1);
	return RunLua(code);
}

// ---------------------------------------------------------------- forward

public void Event_ChangeClass(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client)
		return;
	Call_StartForward(g_hClassChanged);
	Call_PushCell(client);
	Call_PushCell(event.GetInt("oldclass"));
	Call_PushCell(event.GetInt("newclass"));
	Call_Finish();
}

// ---------------------------------------------------------------- commands

public Action Cmd_Status(int client, int args)
{
	ReplyToCommand(client, "[FF] Fortress Forever Tools %s", PLUGIN_VERSION);
	for (int t = 2; t <= 5; t++)
	{
		int e = TeamEnt(t);
		if (e == -1)
		{
			ReplyToCommand(client, "[FF] team %d: no ff_team_manager", t);
			continue;
		}
		char limits[96];
		for (int c = 1; c <= 10; c++)
			Format(limits, sizeof(limits), "%s %d", limits, GetEntData(e, g_iClassesOffset + 4 * c));
		ReplyToCommand(client, "[FF] team %d: ent %d, max players %d, allies 0x%x, ffa %d, class limits%s", t, e,
			GetEntProp(e, Prop_Send, "m_iMaxPlayers"), GetEntProp(e, Prop_Send, "m_iAllies"), GetEntProp(e, Prop_Send, "m_bFFA"), limits);
	}
	return Plugin_Handled;
}

int Targets(int client, const char[] pattern, int[] list, int max)
{
	char name[MAX_TARGET_LENGTH];
	bool ml;
	int n = ProcessTargetString(pattern, client, list, max, 0, name, sizeof(name), ml);
	if (n <= 0)
		ReplyToTargetError(client, n);
	return n;
}

// The admin commands act on the next frame: a Lua call made inside a console/RCON command
// would only run after the command anyway, and this way the reply shows the result.
enum { Act_Class, Act_Respawn, Act_Regen }

void Queue(int client, int act, int cls, bool respawn, const int[] list, int n)
{
	DataPack dp = new DataPack();
	dp.WriteCell(client ? GetClientUserId(client) : 0);
	dp.WriteCell(client == 0 || GetCmdReplySource() == SM_REPLY_TO_CONSOLE);
	dp.WriteCell(act);
	dp.WriteCell(cls);
	dp.WriteCell(respawn);
	dp.WriteCell(n);
	for (int i = 0; i < n; i++)
		dp.WriteCell(GetClientUserId(list[i]));
	RequestFrame(Frame_Act, dp);
}

public void Frame_Act(DataPack dp)
{
	dp.Reset();
	int uid = dp.ReadCell();
	bool console = dp.ReadCell();
	int act = dp.ReadCell(), cls = dp.ReadCell();
	bool respawn = dp.ReadCell();
	int n = dp.ReadCell();
	int admin = uid ? GetClientOfUserId(uid) : 0;
	int done = 0;
	char line[128];
	for (int i = 0; i < n; i++)
	{
		int target = GetClientOfUserId(dp.ReadCell());
		if (!target || !IsClientInGame(target) || GetClientTeam(target) < 2)
			continue;
		char code[256];
		switch (act)
		{
			case Act_Class:
			{
				FormatEx(code, sizeof(code), "ApplyToPlayer(CastToPlayer(GetEntity(%d)), { AT.kChangeClass%s%s })",
					target, g_sClassAT[cls], (respawn || !IsPlayerAlive(target)) ? ", AT.kRespawnPlayers" : "");
				RunLua(code);
				if (ClassOf(target) == cls) done++;
			}
			case Act_Respawn:
			{
				FormatEx(code, sizeof(code), "ApplyToPlayer(CastToPlayer(GetEntity(%d)), { AT.kRespawnPlayers })", target);
				RunLua(code);
				if (IsPlayerAlive(target)) done++;
			}
			case Act_Regen:
			{
				if (Regenerate(target)) done++;
			}
		}
	}
	delete dp;
	static const char what[][] = { "class set", "respawned", "refilled" };
	FormatEx(line, sizeof(line), "[FF] %s: %d of %d player(s)", what[act], done, n);
	if (admin && IsClientInGame(admin))
	{
		if (console) PrintToConsole(admin, "%s", line); else PrintToChat(admin, "%s", line);
	}
	else if (!uid)
		PrintToServer("%s", line);
}

public Action Cmd_Class(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[FF] Usage: sm_ff_class <target> <class> [respawn 0|1]");
		return Plugin_Handled;
	}
	char pattern[64], cname[32];
	GetCmdArg(1, pattern, sizeof(pattern));
	GetCmdArg(2, cname, sizeof(cname));
	FFClass cls = FF_GetClassFromName(cname);
	if (cls == FFClass_Unknown)
	{
		ReplyToCommand(client, "[FF] Unknown class '%s'", cname);
		return Plugin_Handled;
	}
	int list[MAXPLAYERS];
	int n = Targets(client, pattern, list, sizeof(list));
	if (n > 0)
		Queue(client, Act_Class, view_as<int>(cls), args < 3 || GetCmdArgInt(3) != 0, list, n);
	return Plugin_Handled;
}

public Action Cmd_Respawn(int client, int args)
{
	char pattern[64] = "@me";
	if (args >= 1)
		GetCmdArg(1, pattern, sizeof(pattern));
	int list[MAXPLAYERS];
	int n = Targets(client, pattern, list, sizeof(list));
	if (n > 0)
		Queue(client, Act_Respawn, 0, true, list, n);
	return Plugin_Handled;
}

public Action Cmd_Regen(int client, int args)
{
	char pattern[64] = "@me";
	if (args >= 1)
		GetCmdArg(1, pattern, sizeof(pattern));
	int list[MAXPLAYERS];
	int n = Targets(client, pattern, list, sizeof(list));
	if (n > 0)
		Queue(client, Act_Regen, 0, true, list, n);
	return Plugin_Handled;
}
