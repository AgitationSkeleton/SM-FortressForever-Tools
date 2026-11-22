/**
 * Test helper for ff_teamcolors.smx. Logs every SayText2 user message the server sends
 * (sender, recipients, format with control characters shown as \xNN, name, text) and makes
 * bots chat.
 *
 *   sm_fftc_say <team 2-5> <say|say_team> <text...>   a bot of that team runs the command
 *                                                    (living bot first, else a dead one)
 *   sm_fftc_say <team> <deadsay|deadsay_team> <text> the same, killing the bot first (dead chat)
 *   sm_fftc_kill <team>                              kill a bot of that team
 *   sm_fftc_count                                    SayText2 messages seen since load
 *
 * Note: FF sends a chat line only to real clients and back to the sender, so with bots
 * only the sender's own copy is sent; that copy goes through the same code as everyone
 * else's.
 */
#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = { name = "FF team colours test", author = "AgitationSkeleton", description = "", version = "1.0", url = "https://github.com/AgitationSkeleton/SM-FortressForever-Tools" };

int g_iSeen;

public void OnPluginStart()
{
	HookUserMessage(GetUserMessageId("SayText2"), Hook_Observe, false);
	RegAdminCmd("sm_fftc_say", Cmd_Say, ADMFLAG_ROOT);
	RegAdminCmd("sm_fftc_kill", Cmd_Kill, ADMFLAG_ROOT);
	RegAdminCmd("sm_fftc_count", Cmd_Count, ADMFLAG_ROOT);
	RegAdminCmd("sm_fftc_teams", Cmd_Teams, ADMFLAG_ROOT);
}

void Escape(const char[] src, char[] out, int maxlen)
{
	out[0] = '\0';
	char piece[8];
	for (int i = 0; src[i] != '\0'; i++)
	{
		int ch = src[i];
		if (ch > 0 && ch < 32)
			FormatEx(piece, sizeof(piece), "\\x%02X", ch);
		else
			FormatEx(piece, sizeof(piece), "%c", src[i]);
		StrCat(out, maxlen, piece);
	}
}

public Action Hook_Observe(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	g_iSeen++;
	int sender = msg.ReadByte();
	int chat = msg.ReadByte();
	char fmt[96], name[64], text[256], efmt[256];
	msg.ReadString(fmt, sizeof(fmt));
	msg.ReadString(name, sizeof(name));
	msg.ReadString(text, sizeof(text));
	Escape(fmt, efmt, sizeof(efmt));
	char to[128];
	for (int i = 0; i < playersNum; i++)
		Format(to, sizeof(to), "%s %d", to, players[i]);
	PrintToServer("SAYTEXT2 #%d sender %d (team %d) chat %d to [%s ] reliable %d fmt \"%s\" name \"%s\" text \"%s\"", g_iSeen, sender,
		sender > 0 && sender <= MaxClients && IsClientInGame(sender) ? GetClientTeam(sender) : -1, chat, to, reliable, efmt, name, text);
	return Plugin_Continue;
}

int BotOf(int team)
{
	int dead = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == team)
		{
			if (IsPlayerAlive(i))
				return i;
			dead = i;
		}
	}
	return dead;
}

public Action Cmd_Say(int client, int args)
{
	char cmd[16], text[192];
	int team = GetCmdArgInt(1);
	GetCmdArg(2, cmd, sizeof(cmd));
	GetCmdArgString(text, sizeof(text));
	int skip = FindCharInString(text, ' ');
	skip += FindCharInString(text[skip + 1], ' ') + 2;
	int b = BotOf(team);
	if (StrEqual(cmd, "deadsay") || StrEqual(cmd, "deadsay_team"))
	{
		// kill the bot and make it talk in the same frame, before FF can respawn it
		if (b && IsPlayerAlive(b))
			ForcePlayerSuicide(b);
		strcopy(cmd, sizeof(cmd), cmd[4]);
	}
	if (!b)
	{
		ReplyToCommand(client, "no bot on team %d", team);
		return Plugin_Handled;
	}
	PrintToServer("FFTC bot %d (%N) team %d alive %d runs: %s %s", b, b, team, IsPlayerAlive(b), cmd, text[skip]);
	FakeClientCommandEx(b, "%s %s", cmd, text[skip]);
	return Plugin_Handled;
}

public Action Cmd_Kill(int client, int args)
{
	int b = BotOf(GetCmdArgInt(1));
	if (b && IsPlayerAlive(b))
		ForcePlayerSuicide(b);
	ReplyToCommand(client, "killed %d", b);
	return Plugin_Handled;
}

public Action Cmd_Count(int client, int args)
{
	ReplyToCommand(client, "SAYTEXT2 seen %d", g_iSeen);
	return Plugin_Handled;
}

public Action Cmd_Teams(int client, int args)
{
	char line[512];
	for (int t = 1; t <= 5; t++)
	{
		FormatEx(line, sizeof(line), "TEAM %d:", t);
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i) && GetClientTeam(i) == t)
				Format(line, sizeof(line), "%s %d", line, i);
		ReplyToCommand(client, "%s", line);
	}
	return Plugin_Handled;
}
