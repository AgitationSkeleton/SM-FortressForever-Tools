/**
 * Self-test for fortressforever.smx (library "fortressforever").
 * Run: sm_fftools_test (needs a living bot on a team). Prints PASS/FAIL per check and
 * "RESULT n/m checks passed". Changes it makes to teams are restored afterwards; the bot
 * it uses ends up as a Spy (respawned).
 */
#include <sourcemod>
#include <sdktools>
#include <fortressforever>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = { name = "FF tools self-test", author = "AgitationSkeleton", description = "", version = "1.0", url = "https://github.com/AgitationSkeleton/SM-FortressForever-Tools" };

int g_iPass, g_iFail, g_iReply, g_iChanged, g_iClient, g_iOther;
FFClass g_iLastNew;

public void OnPluginStart()
{
	RegAdminCmd("sm_fftools_test", Cmd_Test, ADMFLAG_ROOT);
}

public void FF_OnPlayerClassChanged(int client, FFClass oldclass, FFClass newclass)
{
	if (client == g_iClient)
	{
		g_iChanged++;
		g_iLastNew = newclass;
	}
}

void Check(bool ok, const char[] fmt, any ...)
{
	char buf[256], line[300];
	VFormat(buf, sizeof(buf), fmt, 3);
	if (ok) g_iPass++; else g_iFail++;
	FormatEx(line, sizeof(line), "%s  %s", ok ? "PASS" : "FAIL", buf);
	LogMessage("%s", line);
	int to = g_iReply ? GetClientOfUserId(g_iReply) : 0;
	if (to) PrintToConsole(to, "%s", line); else PrintToServer("%s", line);
}

// The Lua-backed natives run through the server command buffer. Inside a console or RCON
// command the buffer is already being executed, so they would only run after this command;
// the checks therefore run on the next frame.
public Action Cmd_Test(int client, int args)
{
	g_iReply = client ? GetClientUserId(client) : 0;
	RequestFrame(Frame_Test);
	ReplyToCommand(client, "running on the next frame; results go to the server console / log");
	return Plugin_Handled;
}

public void Frame_Test(any unused)
{
	g_iPass = g_iFail = g_iChanged = 0;
	g_iClient = 0;
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) >= 2) { g_iClient = i; break; }
	int c = g_iClient;
	if (!c)
	{
		PrintToServer("no living player");
		return;
	}
	Check(LibraryExists("fortressforever"), "library fortressforever registered");

	// class
	FFClass cls = FF_GetClass(c);
	Check(cls == view_as<FFClass>(GetEntProp(c, Prop_Send, "m_iClassStatus") & 15) && cls != FFClass_Unknown, "FF_GetClass = %d (m_iClassStatus low nibble)", cls);
	FFClass want = cls == FFClass_Soldier ? FFClass_Pyro : FFClass_Soldier;
	bool ok = FF_SetClass(c, want, false);
	Check(ok && FF_GetClass(c) == want && IsPlayerAlive(c), "FF_SetClass(%d, no respawn): class %d, alive %d", want, FF_GetClass(c), IsPlayerAlive(c));
	Check(g_iChanged >= 1 && g_iLastNew == want, "FF_OnPlayerClassChanged fired %d time(s), newclass %d", g_iChanged, g_iLastNew);
	SetEntityHealth(c, 1);
	ok = FF_SetClass(c, FFClass_Spy, true);
	Check(ok && FF_GetClass(c) == FFClass_Spy && IsPlayerAlive(c) && GetClientHealth(c) > 1, "FF_SetClass(spy, respawn): class %d, alive %d, health %d", FF_GetClass(c), IsPlayerAlive(c), GetClientHealth(c));

	// respawn
	ForcePlayerSuicide(c);
	bool dead = !IsPlayerAlive(c);
	ok = FF_RespawnPlayer(c);
	Check(dead && ok && IsPlayerAlive(c) && FF_GetClass(c) == FFClass_Spy, "FF_RespawnPlayer after death: alive %d, class %d", IsPlayerAlive(c), FF_GetClass(c));

	// armour
	int maxarmor = FF_GetMaxArmor(c);
	Check(maxarmor > 0 && maxarmor == GetEntProp(c, Prop_Send, "m_iMaxArmor"), "FF_GetMaxArmor = %d", maxarmor);
	FF_SetArmor(c, 7);
	Check(FF_GetArmor(c) == 7 && GetEntProp(c, Prop_Send, "m_iArmor") == 7, "FF_SetArmor(7) -> %d", FF_GetArmor(c));
	FF_SetMaxArmor(c, maxarmor + 5);
	Check(FF_GetMaxArmor(c) == maxarmor + 5, "FF_SetMaxArmor(%d) -> %d", maxarmor + 5, FF_GetMaxArmor(c));
	FF_SetMaxArmor(c, maxarmor);

	// grenades
	FF_SetGrenades(c, FFGrenade_Primary, 1);
	FF_SetGrenades(c, FFGrenade_Secondary, 2);
	Check(FF_GetGrenades(c, FFGrenade_Primary) == 1 && FF_GetGrenades(c, FFGrenade_Secondary) == 2, "FF_Set/GetGrenades: %d %d (want 1 2)", FF_GetGrenades(c, FFGrenade_Primary), FF_GetGrenades(c, FFGrenade_Secondary));

	// regenerate
	SetEntityHealth(c, 1);
	FF_SetArmor(c, 0);
	FF_SetGrenades(c, FFGrenade_Primary, 0);
	FF_SetGrenades(c, FFGrenade_Secondary, 0);
	ok = FF_RegeneratePlayer(c);
	int maxhp = GetEntProp(c, Prop_Data, "m_iMaxHealth");
	Check(ok && GetClientHealth(c) == maxhp && FF_GetArmor(c) == FF_GetMaxArmor(c) && FF_GetGrenades(c, FFGrenade_Primary) > 0,
		"FF_RegeneratePlayer: health %d/%d armour %d/%d grenades %d %d", GetClientHealth(c), maxhp, FF_GetArmor(c), FF_GetMaxArmor(c),
		FF_GetGrenades(c, FFGrenade_Primary), FF_GetGrenades(c, FFGrenade_Secondary));

	// disguise and cloak
	FFTeam myteam = view_as<FFTeam>(GetClientTeam(c));
	FFTeam other = myteam == FFTeam_Red ? FFTeam_Blue : FFTeam_Red;
	ok = FF_SetDisguise(c, other, FFClass_Medic);
	Check(ok, "FF_SetDisguise(%d, medic) accepted", other);
	g_iOther = view_as<int>(other);
	CreateTimer(0.2, Timer_Part2);
}

// Part 2: FF applies a disguise on the player's next think.
public Action Timer_Part2(Handle timer)
{
	int c = g_iClient;
	int client = g_iReply ? GetClientOfUserId(g_iReply) : 0;
	if (!IsClientInGame(c))
	{
		PrintToServer("test player left");
		return Plugin_Stop;
	}
	FFTeam other = view_as<FFTeam>(g_iOther);
	FFTeam myteam = view_as<FFTeam>(GetClientTeam(c));
	bool ok;
	FFTeam dt; FFClass dc;
	bool isd = FF_GetDisguise(c, dt, dc);
	Check(isd && dt == other && dc == FFClass_Medic, "FF_GetDisguise after a tick: disguised %d as team %d class %d", isd, dt, dc);
	FF_RemoveDisguise(c);
	Check(!FF_GetDisguise(c), "FF_RemoveDisguise: disguised %d", FF_GetDisguise(c));
	Check(FF_IsCloaked(c) == (GetEntProp(c, Prop_Send, "m_iCloaked") != 0), "FF_IsCloaked = %d", FF_IsCloaked(c));

	// buildings
	bool bok = true;
	for (int t = 0; t < 4; t++)
	{
		int b = FF_GetBuilding(c, view_as<FFBuilding>(t));
		if (b != -1 && !IsValidEntity(b)) bok = false;
	}
	Check(bok, "FF_GetBuilding: -1 or a valid entity for all 4 types");

	// teams
	int found = 0;
	for (int t = 2; t <= 5; t++)
	{
		int e = FF_GetTeamEntity(view_as<FFTeam>(t));
		if (e > 0 && GetEntProp(e, Prop_Send, "m_iTeamNum") == t) found++;
	}
	Check(found == 4, "FF_GetTeamEntity: %d of 4 teams", found);

	FFTeam tm = myteam;
	int lim = FF_GetClassLimit(tm, FFClass_Sniper);
	int newlim = lim == 3 ? 2 : 3;
	ok = FF_SetClassLimit(tm, FFClass_Sniper, newlim);
	Check(ok && FF_GetClassLimit(tm, FFClass_Sniper) == newlim, "FF_SetClassLimit(team %d sniper %d) -> %d (was %d)", tm, newlim, FF_GetClassLimit(tm, FFClass_Sniper), lim);
	FF_SetClassLimit(tm, FFClass_Sniper, lim);
	Check(FF_GetClassLimit(tm, FFClass_Sniper) == lim, "FF_SetClassLimit restore -> %d", FF_GetClassLimit(tm, FFClass_Sniper));

	int allies = FF_GetTeamAllies(FFTeam_Blue);
	FF_SetTeamAllies(FFTeam_Blue, allies | (1 << 4));
	Check(FF_AreTeamsAllied(FFTeam_Blue, FFTeam_Yellow) && FF_GetTeamAllies(FFTeam_Blue) == (allies | (1 << 4)), "FF_SetTeamAllies(blue, +yellow): allied %d", FF_AreTeamsAllied(FFTeam_Blue, FFTeam_Yellow));
	FF_SetTeamAllies(FFTeam_Blue, allies);
	Check(FF_GetTeamAllies(FFTeam_Blue) == allies && FF_AreTeamsAllied(FFTeam_Red, FFTeam_Red), "FF_SetTeamAllies restore; a team is allied to itself");

	Check(FF_IsTeamActive(myteam), "FF_IsTeamActive(own team %d)", myteam);
	int maxp = FF_GetTeamMaxPlayers(tm);
	FF_SetTeamMaxPlayers(tm, 31);
	Check(FF_GetTeamMaxPlayers(tm) == 31, "FF_SetTeamMaxPlayers(31) -> %d", FF_GetTeamMaxPlayers(tm));
	FF_SetTeamMaxPlayers(tm, maxp);
	bool ffa = FF_IsTeamFFA(tm);
	FF_SetTeamFFA(tm, !ffa);
	Check(FF_IsTeamFFA(tm) == !ffa, "FF_SetTeamFFA(%d) -> %d", !ffa, FF_IsTeamFFA(tm));
	FF_SetTeamFFA(tm, ffa);

	Check(!FF_RunLua("a = 1; b = 2"), "FF_RunLua refuses ';'");
	Check(FF_RunLua("local x = 1 + 1"), "FF_RunLua accepts plain code");

	char name[16];
	Check(FF_GetClassName(FFClass_HWGuy, name, sizeof(name)) && StrEqual(name, "hwguy") && FF_GetClassFromName("heavy") == FFClass_HWGuy, "class name stocks");

	PrintToServer("RESULT %d/%d checks passed", g_iPass, g_iPass + g_iFail);
	LogMessage("RESULT %d/%d checks passed", g_iPass, g_iPass + g_iFail);
	if (client) PrintToConsole(client, "RESULT %d/%d checks passed", g_iPass, g_iPass + g_iFail);
	return Plugin_Stop;
}
