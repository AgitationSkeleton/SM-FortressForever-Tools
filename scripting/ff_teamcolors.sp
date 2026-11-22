/**
 * Fortress Forever: yellow team chat colour fix.
 *
 * FF 2.0's client shows a Yellow player's name in RED in chat when hud_newteamcolors is 1
 * (the default): client/ff/hud/ff_hud_chat.cpp, GetCustomClientColor(), returns
 * NEW_TEAM_COLOR_RED for TEAM_YELLOW. hud_newteamcolors is a client convar the server
 * cannot set.
 *
 * FF sends every player chat line as a SayText2 user message, one per recipient, with the
 * format "FF_Chat_All" ("\x03%s1\x01 : %s2") or "FF_Chat_Team" ("\x01(TEAM) \x03%s1\x01 : %s2").
 * \x03 means "the sender's team colour", which is where the client goes wrong. This plugin
 * intercepts those messages when the sender is on Yellow, blocks them, and sends the same
 * message to the same recipients one frame later with \x03 replaced by an explicit colour
 * code (\x07RRGGBB): FF's new yellow (255,178,0) for recipients using hud_newteamcolors 1,
 * FF's classic yellow (202,173,33) for recipients using 0. Everything else is untouched:
 * FF still decides who receives the line (team chat goes to the team and its allies,
 * ignore lists, Lua player_onchat), and the text, %-commands and ^-colour codes are FF's.
 *
 * Green is not affected: the same function returns the correct colour for TEAM_GREEN.
 * The kill feed, scoreboard-style name colours and voice status icons call the same
 * client function and cannot be fixed from the server (see the README for the one-line
 * client fix).
 *
 *   ff_teamcolors_enable 1   turn the fix on/off
 *   ff_teamcolors_debug 0    log each rewritten message to the server console
 */
#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"
#define TEAM_YELLOW 4

public Plugin myinfo =
{
	name = "FF Team Colours",
	author = "AgitationSkeleton",
	description = "Shows Yellow players' names in yellow in Fortress Forever chat",
	version = PLUGIN_VERSION,
	url = "https://github.com/AgitationSkeleton/SM-FortressForever-Tools"
};

ConVar g_cvEnable, g_cvDebug;
UserMsg g_msgSayText2;
bool g_bSending;
int g_iNewColors[MAXPLAYERS + 1] = { -1, ... };   // recipient's hud_newteamcolors: -1 unknown (treated as 1)
int g_iRewritten, g_iBlocked;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	char folder[32];
	GetGameFolderName(folder, sizeof(folder));
	if (!StrEqual(folder, "fortressforever", false))
	{
		strcopy(error, err_max, "ff_teamcolors.smx only runs on Fortress Forever");
		return APLRes_Failure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("ff_teamcolors_version", PLUGIN_VERSION, "FF Team Colours version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnable = CreateConVar("ff_teamcolors_enable", "1", "Show Yellow players' names in yellow in chat", _, true, 0.0, true, 1.0);
	g_cvDebug = CreateConVar("ff_teamcolors_debug", "0", "Log each rewritten chat message", _, true, 0.0, true, 1.0);
	AutoExecConfig(true, "ff_teamcolors");

	g_msgSayText2 = GetUserMessageId("SayText2");
	if (g_msgSayText2 == INVALID_MESSAGE_ID)
		SetFailState("SayText2 user message not found");
	HookUserMessage(g_msgSayText2, Hook_SayText2, true);
	RegAdminCmd("sm_ff_teamcolors_stats", Cmd_Stats, ADMFLAG_GENERIC, "Counts of rewritten chat messages");

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			QueryColors(i);
}

public void OnClientPutInServer(int client)
{
	g_iNewColors[client] = -1;
	QueryColors(client);
}

public void OnClientDisconnect(int client)
{
	g_iNewColors[client] = -1;
}

void QueryColors(int client)
{
	if (!IsFakeClient(client))
		QueryClientConVar(client, "hud_newteamcolors", OnColorsQueried);
}

public void OnColorsQueried(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
	if (result == ConVarQuery_Okay)
		g_iNewColors[client] = StringToInt(cvarValue) != 0 ? 1 : 0;
}

public Action Cmd_Stats(int client, int args)
{
	ReplyToCommand(client, "[FF] team colours: %d original messages blocked, %d rewritten messages sent", g_iBlocked, g_iRewritten);
	return Plugin_Handled;
}

public Action Hook_SayText2(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (g_bSending || !g_cvEnable.BoolValue)
		return Plugin_Continue;

	int sender = msg.ReadByte();
	int chat = msg.ReadByte();
	if (!chat || sender < 1 || sender > MaxClients || !IsClientInGame(sender) || GetClientTeam(sender) != TEAM_YELLOW)
		return Plugin_Continue;

	char fmt[64];
	msg.ReadString(fmt, sizeof(fmt));
	bool team = StrEqual(fmt, "FF_Chat_Team");
	if (!team && !StrEqual(fmt, "FF_Chat_All"))
		return Plugin_Continue;

	char name[128], text[512], p3[256], p4[256];
	msg.ReadString(name, sizeof(name));
	msg.ReadString(text, sizeof(text));
	if (msg.BytesLeft > 0) msg.ReadString(p3, sizeof(p3));
	if (msg.BytesLeft > 0) msg.ReadString(p4, sizeof(p4));

	DataPack dp = new DataPack();
	dp.WriteCell(GetClientUserId(sender));
	dp.WriteCell(team);
	dp.WriteCell(reliable);
	dp.WriteString(name);
	dp.WriteString(text);
	dp.WriteString(p3);
	dp.WriteString(p4);
	dp.WriteCell(playersNum);
	for (int i = 0; i < playersNum; i++)
		dp.WriteCell(GetClientUserId(players[i]));
	RequestFrame(Frame_Resend, dp);
	g_iBlocked++;
	return Plugin_Handled;
}

// FF's localised team prefix, by the recipient's SourceMod language (FF ships English and
// Simplified Chinese chat formats; every other language falls back to English).
void TeamPrefix(int client, char[] buffer, int maxlen)
{
	char code[8], name[32];
	GetLanguageInfo(GetClientLanguage(client), code, sizeof(code), name, sizeof(name));
	if (StrEqual(code, "chi"))
		strcopy(buffer, maxlen, "(\xE5\x9B\xA2\xE9\x98\x9F)");   // (团队)
	else
		strcopy(buffer, maxlen, "(TEAM)");
}

public void Frame_Resend(DataPack dp)
{
	dp.Reset();
	int sender = GetClientOfUserId(dp.ReadCell());
	bool team = dp.ReadCell();
	bool reliable = dp.ReadCell();
	char name[128], text[512], p3[256], p4[256];
	dp.ReadString(name, sizeof(name));
	dp.ReadString(text, sizeof(text));
	dp.ReadString(p3, sizeof(p3));
	dp.ReadString(p4, sizeof(p4));
	int n = dp.ReadCell();
	int[] recipients = new int[n];
	for (int i = 0; i < n; i++)
		recipients[i] = GetClientOfUserId(dp.ReadCell());
	delete dp;

	for (int i = 0; i < n; i++)
	{
		int to = recipients[i];
		if (!to || !IsClientInGame(to))
			continue;

		// \x07RRGGBB: FF's NEW_TEAM_COLOR_YELLOW, or TEAM_COLOR_YELLOW with hud_newteamcolors 0
		char color[8], prefix[32], fmt[96];
		strcopy(color, sizeof(color), g_iNewColors[to] == 0 ? "CAAD21" : "FFB200");
		if (team)
		{
			TeamPrefix(to, prefix, sizeof(prefix));
			FormatEx(fmt, sizeof(fmt), "%c%s %c%s%%s1%c : %%s2", 1, prefix, 7, color, 1);
		}
		else
			FormatEx(fmt, sizeof(fmt), "%c%s%%s1%c : %%s2", 7, color, 1);

		int one[1];
		one[0] = to;
		g_bSending = true;
		BfWrite bf = UserMessageToBfWrite(StartMessageEx(g_msgSayText2, one, 1, reliable ? USERMSG_RELIABLE : 0));
		bf.WriteByte(sender);       // 0 if the sender left: the client then colours nothing
		bf.WriteByte(1);
		bf.WriteString(fmt);
		bf.WriteString(name);
		bf.WriteString(text);
		bf.WriteString(p3);
		bf.WriteString(p4);
		EndMessage();
		g_bSending = false;
		g_iRewritten++;

		if (g_cvDebug.BoolValue)
		{
			char shown[96];
			strcopy(shown, sizeof(shown), fmt);
			ReplaceString(shown, sizeof(shown), "\x01", "\\x01");
			ReplaceString(shown, sizeof(shown), "\x07", "\\x07");
			PrintToServer("[ff_teamcolors] to #%d %N: sender %d fmt \"%s\" name \"%s\" text \"%s\"", GetClientUserId(to), to, sender, shown, name, text);
		}
		QueryColors(to);   // refresh the recipient's setting for his next message
	}
}
