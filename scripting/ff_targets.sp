/**
 * ff_targets - team and class targets for SourceMod admin commands on Fortress Forever:
 *
 *   sm_slay @yellow      sm_freeze @engineers      sm_beacon @redsnipers
 *
 * Teams:   @blue @red @yellow @green @spectators (@spec)
 * Classes: @scouts @snipers @soldiers @demomen @medics @hwguys @pyros @spies @engineers
 *          @civilians, each also singular (@scout, @demoman, ...) and with the aliases
 *          @demo(s), @heavy/@heavies/@hw, @engi(s)/@engy, @civ(s)
 * Both:    @<team><class plural>, e.g. @bluemedics, @greenhwguys, @yellowcivilians
 *
 * Dead players count, like SourceMod's own team targets (a player's class stays set while he is
 * dead). Commands that need living players filter them out themselves. Class numbers are FF's
 * (the low four bits of CFFPlayer::m_iClassStatus, 1 = Scout ... 10 = Civilian).
 */
#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"

public Plugin myinfo =
{
	name = "FF Team and Class Targets",
	author = "AgitationSkeleton",
	description = "@team and @class targets (@yellow, @engineers, @redsnipers, ...) for admin commands",
	version = PLUGIN_VERSION,
	url = "https://github.com/AgitationSkeleton/SM-FortressForever-Tools"
};

#define MAX_FILTERS 160

// target -> packed (team << 8 | class); 0 = any
StringMap g_hFilters;
char g_sNames[MAX_FILTERS][32];
int g_iNumNames;

static const char g_sTeamName[6][] = { "", "spectators", "blue", "red", "yellow", "green" };
static const char g_sTeamTitle[6][] = { "", "Spectators", "Blue", "Red", "Yellow", "Green" };

// class, plural (main name), title, then extra aliases
static const char g_sClassPlural[11][] = { "", "scouts", "snipers", "soldiers", "demomen", "medics", "hwguys", "pyros", "spies", "engineers", "civilians" };
static const char g_sClassSingle[11][] = { "", "scout", "sniper", "soldier", "demoman", "medic", "hwguy", "pyro", "spy", "engineer", "civilian" };
static const char g_sClassTitle[11][] = { "", "Scouts", "Snipers", "Soldiers", "Demomen", "Medics", "HWGuys", "Pyros", "Spies", "Engineers", "Civilians" };
static const char g_sClassAlias[11][] = { "", "", "", "", "demo,demos", "", "heavy,heavies,hw,hwguy", "", "", "engi,engis,engy", "civ,civs" };

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	char folder[32];
	GetGameFolderName(folder, sizeof(folder));
	if (!StrEqual(folder, "fortressforever", false))
	{
		strcopy(error, err_max, "ff_targets.smx only runs on Fortress Forever");
		return APLRes_Failure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("ff_targets_version", PLUGIN_VERSION, "FF Team and Class Targets version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_hFilters = new StringMap();
	char desc[64], buf[64], alias[8][16];

	for (int t = 1; t <= 5; t++)
	{
		FormatEx(desc, sizeof(desc), "all %s", t == 1 ? "spectators" : g_sTeamTitle[t]);
		if (t == 1)
		{
			Add("@spectators", t, 0, desc);
			Add("@spec", t, 0, desc);
		}
		else
		{
			FormatEx(buf, sizeof(buf), "@%s", g_sTeamName[t]);
			Add(buf, t, 0, desc);
		}
	}
	for (int c = 1; c <= 10; c++)
	{
		FormatEx(desc, sizeof(desc), "all %s", g_sClassTitle[c]);
		FormatEx(buf, sizeof(buf), "@%s", g_sClassPlural[c]);
		Add(buf, 0, c, desc);
		FormatEx(buf, sizeof(buf), "@%s", g_sClassSingle[c]);
		Add(buf, 0, c, desc);
		int n = g_sClassAlias[c][0] ? ExplodeString(g_sClassAlias[c], ",", alias, sizeof(alias), sizeof(alias[])) : 0;
		for (int i = 0; i < n; i++)
		{
			FormatEx(buf, sizeof(buf), "@%s", alias[i]);
			Add(buf, 0, c, desc);
		}
		for (int t = 2; t <= 5; t++)
		{
			FormatEx(desc, sizeof(desc), "%s %s", g_sTeamTitle[t], g_sClassTitle[c]);
			FormatEx(buf, sizeof(buf), "@%s%s", g_sTeamName[t], g_sClassPlural[c]);
			Add(buf, t, c, desc);
		}
	}
	RegAdminCmd("sm_ff_targets", Cmd_List, ADMFLAG_GENERIC, "List the @team / @class targets");
}

void Add(const char[] name, int team, int cls, const char[] desc)
{
	if (g_iNumNames >= MAX_FILTERS || g_hFilters.ContainsKey(name))
		return;
	g_hFilters.SetValue(name, (team << 8) | cls);
	strcopy(g_sNames[g_iNumNames++], sizeof(g_sNames[]), name);
	AddMultiTargetFilter(name, Filter, desc, false);
}

public void OnPluginEnd()
{
	for (int i = 0; i < g_iNumNames; i++)
		RemoveMultiTargetFilter(g_sNames[i], Filter);
}

public bool Filter(const char[] pattern, ArrayList clients)
{
	int packed;
	if (!g_hFilters.GetValue(pattern, packed))
	{
		// SourceMod passes the pattern as typed; the names are lower case
		char lower[32];
		strcopy(lower, sizeof(lower), pattern);
		for (int i = 0; lower[i]; i++)
			lower[i] = CharToLower(lower[i]);
		if (!g_hFilters.GetValue(lower, packed))
			return false;
	}
	int team = packed >> 8, cls = packed & 0xFF;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		if (team && GetClientTeam(i) != team)
			continue;
		if (cls && (GetEntProp(i, Prop_Send, "m_iClassStatus") & 0x0F) != cls)
			continue;
		clients.Push(i);
	}
	return true;
}

public Action Cmd_List(int client, int args)
{
	char line[256];
	for (int i = 0; i < g_iNumNames; i++)
	{
		if (strlen(line) + strlen(g_sNames[i]) + 2 >= sizeof(line))
		{
			ReplyToCommand(client, "%s", line);
			line[0] = '\0';
		}
		Format(line, sizeof(line), "%s%s%s", line, line[0] ? " " : "", g_sNames[i]);
	}
	if (line[0])
		ReplyToCommand(client, "%s", line);
	return Plugin_Handled;
}
