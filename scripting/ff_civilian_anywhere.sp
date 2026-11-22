/**
 * ff_civilian_anywhere - lets players (and bots) pick the Civilian on every Fortress Forever map,
 * except where the Civilian has a special role (Hunted's VIP) or maps you list.
 *
 * Each FF team keeps class limits (-1 = not allowed, 0 = unlimited, n = at most n), set by the
 * map's Lua. Every 2 seconds the plugin sets the Civilian limit of each active team that has it
 * at -1 to ff_civanywhere_limit, through FF's own SetTeamClassLimit (FF_SetClassLimit), so map
 * scripts stay stock and a map script that resets its limits is followed again within 2 s.
 *
 *   sm_civanywhere_enabled 1
 *   sm_civanywhere_exclude "ff_hunted*,hunted*,ff_training"   (trailing * = prefix)
 *   sm_civanywhere_limit 0                                     (0 = unlimited)
 *
 * Needs fortressforever.smx. The cvar names are those of the earlier stand-alone version, so an
 * existing cfg/sourcemod/ff_civilian_anywhere.cfg keeps working.
 */
#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#include <fortressforever>

#define PLUGIN_VERSION "1.1.0"

public Plugin myinfo =
{
	name = "FF Civilian Anywhere",
	author = "AgitationSkeleton",
	description = "Allow the Civilian class on every map except excluded ones",
	version = PLUGIN_VERSION,
	url = "https://github.com/AgitationSkeleton/SM-FortressForever-Tools"
};

ConVar g_cvEnabled, g_cvExclude, g_cvLimit;
bool g_bExcluded;
bool g_bRefused[6];   // FF kept -1 (e.g. a cr_civilian convar): stop asking on this map

public void OnPluginStart()
{
	CreateConVar("ff_civanywhere_version", PLUGIN_VERSION, "FF Civilian Anywhere version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnabled = CreateConVar("sm_civanywhere_enabled", "1", "Allow the Civilian on every map (1) or leave the map's class limits alone (0)", _, true, 0.0, true, 1.0);
	g_cvExclude = CreateConVar("sm_civanywhere_exclude", "ff_hunted*,hunted*,ff_training",
		"Comma-separated map names (trailing * = prefix) where the map's own Civilian rule is kept");
	g_cvLimit = CreateConVar("sm_civanywhere_limit", "0", "Civilian limit per team where this plugin allows it (0 = unlimited)", _, true, 0.0);
	AutoExecConfig(true, "ff_civilian_anywhere");
	g_cvExclude.AddChangeHook(OnSettingChanged);
	g_cvLimit.AddChangeHook(OnSettingChanged);
	CreateTimer(2.0, Timer_Apply, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	ResetMapState();
}

public void OnSettingChanged(ConVar cv, const char[] oldValue, const char[] newValue)
{
	ResetMapState();
}

void ResetMapState()
{
	g_bExcluded = MapExcluded();
	for (int t = 0; t < sizeof(g_bRefused); t++)
		g_bRefused[t] = false;
}

bool MapExcluded()
{
	char map[96], list[512], parts[32][96];
	GetCurrentMap(map, sizeof(map));
	g_cvExclude.GetString(list, sizeof(list));
	int n = ExplodeString(list, ",", parts, sizeof(parts), sizeof(parts[]));
	for (int i = 0; i < n; i++)
	{
		TrimString(parts[i]);
		int len = strlen(parts[i]);
		if (len == 0)
			continue;
		if (parts[i][len - 1] == '*')
		{
			parts[i][len - 1] = '\0';
			if (StrContains(map, parts[i], false) == 0)
				return true;
		}
		else if (StrEqual(map, parts[i], false))
			return true;
	}
	return false;
}

public Action Timer_Apply(Handle timer)
{
	if (!g_cvEnabled.BoolValue || g_bExcluded)
		return Plugin_Continue;
	for (int t = view_as<int>(FFTeam_Blue); t <= view_as<int>(FFTeam_Green); t++)
	{
		FFTeam team = view_as<FFTeam>(t);
		if (g_bRefused[t] || !FF_IsTeamActive(team))
			continue;
		if (FF_GetClassLimit(team, FFClass_Civilian) != FF_CLASSLIMIT_DISABLED)
			continue;
		if (!FF_SetClassLimit(team, FFClass_Civilian, g_cvLimit.IntValue))
		{
			g_bRefused[t] = true;
			LogMessage("FF kept the Civilian disabled for team %d on this map (a cr_* class convar?); not retrying until the next map", t);
		}
	}
	return Plugin_Continue;
}
