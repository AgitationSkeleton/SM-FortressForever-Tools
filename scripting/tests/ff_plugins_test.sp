/**
 * Test helper for ff_pipetint, ff_jetpack, ff_twotap, ff_civilian_anywhere and ff_targets
 * (bots only; run each command from the server console / RCON).
 *
 *   sm_fft_targets            every @target against a manual count
 *   sm_fft_pipes <seconds>    log the skin and colour of each Demoman projectile
 *   sm_fft_jetpack            jetpack allow / infinite / spawn-fuel checks on a Pyro
 *   sm_fft_twotap             primeone / throwgren / toggleone on a bot
 *   sm_fft_civ                Civilian limits per team
 */
#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#include <fortressforever>

public Plugin myinfo = { name = "FF plugins test", author = "AgitationSkeleton", description = "", version = "1.0", url = "" };

float g_flPipesUntil;
int g_iPass, g_iFail;

int g_iCmds[MAXPLAYERS + 1], g_iToggle[MAXPLAYERS + 1];

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	g_iCmds[client]++;
	OnPlayerRunCmdPost_dbg(client, buttons);
	if (buttons & ((1 << 25) | (1 << 26)))
		g_iToggle[client]++;
}

int g_iForce, g_iForceLeft, g_iForceClient;

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (client == g_iForceClient && g_iForceLeft > 0)
	{
		g_iForceLeft--;
		buttons |= g_iForce;
		PrintToServer("[fft] force pre %x", buttons);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public void OnPlayerRunCmdPost_dbg(int client, int buttons)
{
	if (client == g_iForceClient && g_iForceLeft > -12)
	{
		PrintToServer("[fft] force post %x state %d gren %d", buttons, GetEntProp(client, Prop_Send, "m_iGrenadeState"), GetEntProp(client, Prop_Send, "m_iPrimary"));
		if (g_iForceLeft <= 0) g_iForceLeft--;
	}
}

public Action Cmd_Force(int args)
{
	g_iForceClient = FindClass(args >= 2 ? view_as<FFClass>(GetCmdArgInt(2)) : FFClass_Soldier);
	g_iForce = GetCmdArgInt(1);
	g_iForceLeft = args >= 3 ? GetCmdArgInt(3) : 3;
	return Plugin_Handled;
}

public Action Cmd_Debug(int args)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && g_iCmds[i])
			PrintToServer("[fft] %N cmds %d toggles %d state %d gren %d/%d", i, g_iCmds[i], g_iToggle[i], GetEntProp(i, Prop_Send, "m_iGrenadeState"), GetEntProp(i, Prop_Send, "m_iPrimary"), GetEntProp(i, Prop_Send, "m_iSecondary"));
	return Plugin_Handled;
}

public Action Cmd_Cmd(int args)
{
	int b = FindClass(args >= 2 ? view_as<FFClass>(GetCmdArgInt(2)) : FFClass_Soldier);
	if (b == -1) return Plugin_Handled;
	char c[32];
	GetCmdArg(1, c, sizeof(c));
	FakeClientCommand(b, "%s", c);
	CreateTimer(0.3, Timer_State, GetClientUserId(b));
	return Plugin_Handled;
}

public Action Timer_State(Handle t, int uid)
{
	int b = GetClientOfUserId(uid); if (!b) return Plugin_Stop;
	PrintToServer("[fft] %N state %d gren %d/%d", b, GetEntProp(b, Prop_Send, "m_iGrenadeState"), GetEntProp(b, Prop_Send, "m_iPrimary"), GetEntProp(b, Prop_Send, "m_iSecondary"));
	return Plugin_Stop;
}

public Action Cmd_Rate(int args)
{
	int p = FindClass(FFClass_Pyro);
	if (p == -1) return Plugin_Handled;
	FF_SetJetpackFuel(p, 20);
	CreateTimer(1.0, R1, GetClientUserId(p));
	return Plugin_Handled;
}

public Action R1(Handle t, int uid)
{
	int p = GetClientOfUserId(uid); if (!p) return Plugin_Stop;
	PrintToServer("[fft] rate: fuel 20 -> %d after 1 s (scale %.1f, jetpacking %d, onground %d)", FF_GetJetpackFuel(p), FindConVar("ff_jetpack_recharge_scale").FloatValue, FF_IsJetpacking(p), (GetEntityFlags(p) & FL_ONGROUND) != 0);
	return Plugin_Stop;
}

public void OnPluginStart()
{
	RegServerCmd("sm_fft_debug", Cmd_Debug);
	RegServerCmd("sm_fft_cmd", Cmd_Cmd);
	RegServerCmd("sm_fft_force", Cmd_Force);
	RegServerCmd("sm_fft_rate", Cmd_Rate);
	RegServerCmd("sm_fft_targets", Cmd_Targets);
	RegServerCmd("sm_fft_pipes", Cmd_Pipes);
	RegServerCmd("sm_fft_jetpack", Cmd_Jetpack);
	RegServerCmd("sm_fft_twotap", Cmd_TwoTap);
	RegServerCmd("sm_fft_civ", Cmd_Civ);
}

void Check(bool ok, const char[] fmt, any ...)
{
	char buf[256];
	VFormat(buf, sizeof(buf), fmt, 3);
	if (ok) g_iPass++; else g_iFail++;
	PrintToServer("[fft] %s %s", ok ? "PASS" : "FAIL", buf);
}

int Count(int team, int cls)
{
	int n = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i)) continue;
		if (team && GetClientTeam(i) != team) continue;
		if (cls && view_as<int>(FF_GetClass(i)) != cls) continue;
		n++;
	}
	return n;
}

int Target(const char[] pattern)
{
	int list[MAXPLAYERS];
	char name[64];
	bool ml;
	int n = ProcessTargetString(pattern, 0, list, sizeof(list), COMMAND_FILTER_NO_IMMUNITY, name, sizeof(name), ml);
	return n < 0 ? 0 : n;   // COMMAND_TARGET_NONE etc. are <= 0
}

public Action Cmd_Targets(int args)
{
	g_iPass = g_iFail = 0;
	static const char teams[][] = { "", "spectators", "blue", "red", "yellow", "green" };
	static const char plural[][] = { "", "scouts", "snipers", "soldiers", "demomen", "medics", "hwguys", "pyros", "spies", "engineers", "civilians" };
	static const char single[][] = { "", "scout", "sniper", "soldier", "demoman", "medic", "hwguy", "pyro", "spy", "engineer", "civilian" };
	char p[48];
	for (int t = 2; t <= 5; t++)
	{
		FormatEx(p, sizeof(p), "@%s", teams[t]);
		int want = Count(t, 0), got = Target(p);
		Check(got == want, "%s -> %d (want %d)", p, got, want);
	}
	Check(Target("@spec") == Count(1, 0), "@spec -> %d (want %d)", Target("@spec"), Count(1, 0));
	for (int c = 1; c <= 10; c++)
	{
		FormatEx(p, sizeof(p), "@%s", plural[c]);
		int want = Count(0, c), got = Target(p);
		Check(got == want, "%s -> %d (want %d)", p, got, want);
		FormatEx(p, sizeof(p), "@%s", single[c]);
		got = Target(p);
		Check(got == want, "%s -> %d (want %d)", p, got, want);
		for (int t = 2; t <= 5; t++)
		{
			FormatEx(p, sizeof(p), "@%s%s", teams[t], plural[c]);
			want = Count(t, c); got = Target(p);
			Check(got == want, "%s -> %d (want %d)", p, got, want);
		}
	}
	static const char alias[][] = { "@demo", "@demos", "@heavy", "@heavies", "@hw", "@engi", "@engis", "@engy", "@civ", "@civs" };
	static const int aliasCls[] = { 4, 4, 6, 6, 6, 9, 9, 9, 10, 10 };
	for (int i = 0; i < sizeof(alias); i++)
	{
		int want = Count(0, aliasCls[i]), got = Target(alias[i]);
		Check(got == want, "%s -> %d (want %d)", alias[i], got, want);
	}
	PrintToServer("[fft] targets: %d passed, %d failed", g_iPass, g_iFail);
	return Plugin_Handled;
}

// ---------------------------------------------------------------- pipes

public Action Cmd_Pipes(int args)
{
	g_flPipesUntil = GetGameTime() + (args ? GetCmdArgFloat(1) : 60.0);
	PrintToServer("[fft] logging Demoman projectiles");
	return Plugin_Handled;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (GetGameTime() > g_flPipesUntil)
		return;
	if (StrEqual(classname, "ff_projectile_gl") || StrEqual(classname, "ff_projectile_pl"))
		CreateTimer(0.1, Timer_Pipe, EntIndexToEntRef(entity));
}

public Action Timer_Pipe(Handle t, int ref)
{
	int e = EntRefToEntIndex(ref);
	if (e == INVALID_ENT_REFERENCE)
		return Plugin_Stop;
	char cls[32];
	GetEntityClassname(e, cls, sizeof(cls));
	int thrower = GetEntPropEnt(e, Prop_Send, "m_hThrower");
	int team = (thrower > 0 && thrower <= MaxClients && IsClientInGame(thrower)) ? GetClientTeam(thrower) : -1;
	int r, g, b, a;
	GetEntityRenderColor(e, r, g, b, a);
	PrintToServer("[fft] %s team %d skin %d colour %d %d %d", cls, team, GetEntProp(e, Prop_Send, "m_nSkin"), r, g, b);
	return Plugin_Stop;
}

// ---------------------------------------------------------------- jetpack

int FindClass(FFClass c, bool alive = true)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && (!alive || IsPlayerAlive(i)) && FF_GetClass(i) == c)
			return i;
	return -1;
}

public Action Cmd_Jetpack(int args)
{
	g_iPass = g_iFail = 0;
	int p = FindClass(FFClass_Pyro);
	if (p == -1)
	{
		p = FindClass(FFClass_Soldier);
		if (p == -1) { PrintToServer("[fft] no pyro or soldier"); return Plugin_Handled; }
		FF_SetClass(p, FFClass_Pyro, true);
	}
	PrintToServer("[fft] pyro %N", p);
	ConVar en = FindConVar("ff_jetpack_enable");
	en.SetInt(0);
	CreateTimer(0.3, J1, GetClientUserId(p));
	return Plugin_Handled;
}

public Action J1(Handle t, int uid)
{
	int p = GetClientOfUserId(uid); if (!p) return Plugin_Stop;
	Check(!FF_IsJetpackAllowed(p), "ff_jetpack_enable 0 -> m_bCanUseJetpack %d", FF_IsJetpackAllowed(p));
	FindConVar("ff_jetpack_enable").SetInt(1);
	CreateTimer(0.3, J2, uid);
	return Plugin_Stop;
}

public Action J2(Handle t, int uid)
{
	int p = GetClientOfUserId(uid); if (!p) return Plugin_Stop;
	Check(FF_IsJetpackAllowed(p), "ff_jetpack_enable 1 -> m_bCanUseJetpack %d", FF_IsJetpackAllowed(p));
	ServerCommand("sm_ff_jetpack #%d 0", uid);
	CreateTimer(0.3, J3, uid);
	return Plugin_Stop;
}

public Action J3(Handle t, int uid)
{
	int p = GetClientOfUserId(uid); if (!p) return Plugin_Stop;
	Check(!FF_IsJetpackAllowed(p), "sm_ff_jetpack <bot> 0 -> %d", FF_IsJetpackAllowed(p));
	ServerCommand("sm_ff_jetpack #%d reset", uid);
	FF_SetJetpackFuel(p, 10);
	FindConVar("ff_jetpack_infinite").SetInt(1);
	CreateTimer(0.4, J4, uid);
	return Plugin_Stop;
}

public Action J4(Handle t, int uid)
{
	int p = GetClientOfUserId(uid); if (!p) return Plugin_Stop;
	Check(FF_IsJetpackAllowed(p), "reset -> %d", FF_IsJetpackAllowed(p));
	Check(FF_GetJetpackFuel(p) == 200, "infinite -> fuel %d", FF_GetJetpackFuel(p));
	FindConVar("ff_jetpack_infinite").SetInt(0);
	FindConVar("ff_jetpack_recharge_scale").SetFloat(0.0);
	FF_SetJetpackFuel(p, 50);
	CreateTimer(1.0, J5, uid);
	return Plugin_Stop;
}

public Action J5(Handle t, int uid)
{
	int p = GetClientOfUserId(uid); if (!p) return Plugin_Stop;
	int f = FF_GetJetpackFuel(p);
	Check(f <= 54, "recharge 0 -> fuel 50 after 1 s is %d (FF alone: ~75)", f);
	FindConVar("ff_jetpack_recharge_scale").SetFloat(3.0);
	FF_SetJetpackFuel(p, 50);
	CreateTimer(1.0, J6, uid);
	return Plugin_Stop;
}

public Action J6(Handle t, int uid)
{
	int p = GetClientOfUserId(uid); if (!p) return Plugin_Stop;
	int f = FF_GetJetpackFuel(p);
	Check(f >= 105 && f <= 140, "recharge 3 -> fuel 50 after 1 s is %d (want ~125)", f);
	FindConVar("ff_jetpack_recharge_scale").SetFloat(1.0);
	FindConVar("ff_jetpack_spawn_fuel").SetInt(25);
	FF_RespawnPlayer(p);
	CreateTimer(0.5, J7, uid);
	return Plugin_Stop;
}

public Action J7(Handle t, int uid)
{
	int p = GetClientOfUserId(uid); if (!p) return Plugin_Stop;
	int f = FF_GetJetpackFuel(p);
	Check(f >= 50 && f <= 70, "spawn fuel 25%% -> %d after 0.5 s (want 50 + recharge)", f);
	FindConVar("ff_jetpack_spawn_fuel").SetInt(100);
	PrintToServer("[fft] jetpack: %d passed, %d failed", g_iPass, g_iFail);
	return Plugin_Stop;
}

// ---------------------------------------------------------------- two-tap


public Action Cmd_TwoTap(int args)
{
	g_iPass = g_iFail = 0;
	int b = FindClass(FFClass_Soldier);
	if (b == -1) b = FindClass(FFClass_Scout);
	if (b == -1) { PrintToServer("[fft] no soldier/scout"); return Plugin_Handled; }
	FF_RegeneratePlayer(b);
	PrintToServer("[fft] bot %N, state %d, gren1 %d", b, GetEntProp(b, Prop_Send, "m_iGrenadeState"), FF_GetGrenades(b, FFGrenade_Primary));
	FakeClientCommand(b, "primeone");
	CreateTimer(0.3, T1, GetClientUserId(b));
	return Plugin_Handled;
}

public Action T1(Handle t, int uid)
{
	int b = GetClientOfUserId(uid); if (!b) return Plugin_Stop;
	int s = GetEntProp(b, Prop_Send, "m_iGrenadeState");
	Check(s == 1, "primeone -> grenade state %d (want 1)", s);

	FakeClientCommand(b, "throwgren");
	CreateTimer(0.6, T2, uid);
	return Plugin_Stop;
}

public Action T2(Handle t, int uid)
{
	int b = GetClientOfUserId(uid); if (!b) return Plugin_Stop;
	int s = GetEntProp(b, Prop_Send, "m_iGrenadeState");
	Check(s == 0, "throwgren -> grenade state %d (want 0)", s);
	FakeClientCommand(b, "toggletwo");
	CreateTimer(0.3, T3, uid);
	return Plugin_Stop;
}

public Action T3(Handle t, int uid)
{
	int b = GetClientOfUserId(uid); if (!b) return Plugin_Stop;
	int s = GetEntProp(b, Prop_Send, "m_iGrenadeState");
	Check(s == 2, "toggletwo -> grenade state %d (want 2)", s);
	FakeClientCommand(b, "toggletwo");
	CreateTimer(0.6, T4, uid);
	return Plugin_Stop;
}

public Action T4(Handle t, int uid)
{
	int b = GetClientOfUserId(uid); if (!b) return Plugin_Stop;
	int s = GetEntProp(b, Prop_Send, "m_iGrenadeState");
	Check(s == 0, "toggletwo again -> grenade state %d (want 0, thrown)", s);
	PrintToServer("[fft] twotap: %d passed, %d failed", g_iPass, g_iFail);
	return Plugin_Stop;
}

// ---------------------------------------------------------------- civilian

public Action Cmd_Civ(int args)
{
	char map[64];
	GetCurrentMap(map, sizeof(map));
	for (int t = 2; t <= 5; t++)
	{
		FFTeam team = view_as<FFTeam>(t);
		if (FF_GetTeamEntity(team) == -1) continue;
		PrintToServer("[fft] %s team %d active %d civilian limit %d", map, t, FF_IsTeamActive(team), FF_GetClassLimit(team, FFClass_Civilian));
	}
	return Plugin_Handled;
}
