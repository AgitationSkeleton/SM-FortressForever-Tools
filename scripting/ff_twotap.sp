/**
 * ff_twotap - two-tap grenades on Fortress Forever 2.0.
 *
 * FF 2.0 throws grenades two ways, both client binds:
 *   +gren1 / +gren2              hold to prime, release to throw
 *   +togglegren1 / +togglegren2  tap to prime, tap again to throw ("two-tap")
 * Old FF and TFC configs use the server commands toggleone / toggletwo / primeone / primetwo /
 * throwgren, which FF 2.0 no longer has, so those binds silently do nothing.
 *
 * This plugin:
 *   - adds toggleone, toggletwo, primeone, primetwo and throwgren back: each presses FF's
 *     two-tap grenade button for one user command, so old binds work again;
 *   - !twotap (sm_twotap): makes the player's +gren1 / +gren2 binds two-tap for him (saved with
 *     clientprefs when it is loaded);
 *   - answers players who ask about two-tap grenades in chat (this replaces
 *     ff_twotap_grenade_reminder).
 *
 * Grenade buttons are handled in CFFPlayer::PreThink from the user command's buttons, which
 * OnPlayerRunCmd may change. That needs the PlayerRunCmd offset from this repository's
 * gamedata (FF 2.0: 428); with SourceMod's own FF gamedata OnPlayerRunCmd never runs.
 *
 * Client prediction: the player's own client predicts grenades from the keys he pressed. With
 * !twotap on, releasing +gren1 makes his client predict a throw that the server does not do, so
 * the HUD grenade timer can blink until the server's grenade state reaches him; the grenade is
 * still primed, and the next tap throws it.
 */
#include <sourcemod>
#include <sdktools>
#undef REQUIRE_EXTENSIONS
#include <clientprefs>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"

#define IN_TOGGLEGRENADE1  (1 << 25)
#define IN_TOGGLEGRENADE2  (1 << 26)

#define GREN_NONE 0

public Plugin myinfo =
{
	name = "FF Two-Tap Grenades",
	author = "AgitationSkeleton",
	description = "Old two-tap grenade commands, a per-player two-tap mode and a chat helper",
	version = PLUGIN_VERSION,
	url = "https://github.com/AgitationSkeleton/SM-FortressForever-Tools"
};

ConVar g_cvCommands, g_cvMode, g_cvModeDefault, g_cvHelp, g_cvHelpCooldown, g_cvHelpText;
Cookie g_hCookie;
bool g_bTwoTap[MAXPLAYERS + 1];
int g_iInject[MAXPLAYERS + 1];
int g_iInjectCmds[MAXPLAYERS + 1];

// a tap holds the button for this many user commands (about 60 ms at 66 tick), then releases it
#define TAP_CMDS 4
float g_flNextHelp[MAXPLAYERS + 1];
float g_flNextHelpAll;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	char folder[32];
	GetGameFolderName(folder, sizeof(folder));
	if (!StrEqual(folder, "fortressforever", false))
	{
		strcopy(error, err_max, "ff_twotap.smx only runs on Fortress Forever");
		return APLRes_Failure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("ff_twotap_version", PLUGIN_VERSION, "FF Two-Tap Grenades version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvCommands = CreateConVar("ff_twotap_commands", "1", "Accept toggleone/toggletwo/primeone/primetwo/throwgren", _, true, 0.0, true, 1.0);
	g_cvMode = CreateConVar("ff_twotap_mode", "1", "Allow players to make +gren1/+gren2 two-tap with !twotap", _, true, 0.0, true, 1.0);
	g_cvModeDefault = CreateConVar("ff_twotap_mode_default", "0", "!twotap state for players who never chose", _, true, 0.0, true, 1.0);
	g_cvHelp = CreateConVar("ff_twotap_help", "1", "Answer chat questions about two-tap grenades (0 = off, 1 = to the asker, 2 = to everyone)", _, true, 0.0, true, 2.0);
	g_cvHelpCooldown = CreateConVar("ff_twotap_help_cooldown", "60", "Seconds before the same player gets the chat answer again (everyone: a third of it)", _, true, 0.0);
	g_cvHelpText = CreateConVar("ff_twotap_help_text",
		"[FF] Two-tap grenades: bind a key to +togglegren1 / +togglegren2, or type !twotap to make your +gren1/+gren2 keys two-tap. Old toggleone/toggletwo binds work here too.",
		"Chat answer about two-tap grenades");
	AutoExecConfig(true, "ff_twotap");

	static const char cmds[][] = { "toggleone", "toggletwo", "primeone", "primetwo", "throwgren" };
	for (int i = 0; i < sizeof(cmds); i++)
		RegConsoleCmd(cmds[i], Cmd_Grenade);
	RegConsoleCmd("sm_twotap", Cmd_TwoTap, "Toggle two-tap mode for your +gren1/+gren2 binds");

	if (LibraryExists("clientprefs"))
		OnLibraryAdded("clientprefs");
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			OnClientPutInServer(i);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "clientprefs") && g_hCookie == null)
	{
		g_hCookie = new Cookie("ff_twotap", "FF two-tap mode for +gren1/+gren2 (1/0)", CookieAccess_Protected);
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i) && AreClientCookiesCached(i))
				OnClientCookiesCached(i);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "clientprefs"))
		g_hCookie = null;
}

public void OnClientPutInServer(int client)
{
	g_bTwoTap[client] = g_cvModeDefault.BoolValue;
	g_iInject[client] = 0;
	g_iInjectCmds[client] = 0;
	g_flNextHelp[client] = 0.0;
}

public void OnClientCookiesCached(int client)
{
	if (g_hCookie == null || IsFakeClient(client))
		return;
	char v[4];
	g_hCookie.Get(client, v, sizeof(v));
	if (v[0] != '\0')
		g_bTwoTap[client] = StringToInt(v) != 0;
}

int GrenadeState(int client)
{
	return GetEntProp(client, Prop_Send, "m_iGrenadeState");
}

public Action Cmd_Grenade(int client, int args)
{
	if (!client || !g_cvCommands.BoolValue || !IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Handled;
	char cmd[16];
	GetCmdArg(0, cmd, sizeof(cmd));
	if (g_iInject[client])
		return Plugin_Handled;   // the previous tap is still held
	bool primed = GrenadeState(client) != GREN_NONE;
	if (StrEqual(cmd, "toggleone", false))
		g_iInject[client] |= IN_TOGGLEGRENADE1;
	else if (StrEqual(cmd, "toggletwo", false))
		g_iInject[client] |= IN_TOGGLEGRENADE2;
	else if (StrEqual(cmd, "primeone", false) && !primed)
		g_iInject[client] |= IN_TOGGLEGRENADE1;
	else if (StrEqual(cmd, "primetwo", false) && !primed)
		g_iInject[client] |= IN_TOGGLEGRENADE2;
	else if (StrEqual(cmd, "throwgren", false) && primed)
		g_iInject[client] |= IN_TOGGLEGRENADE1;   // a two-tap press throws whichever grenade is primed
	return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	bool changed = false;
	if (g_bTwoTap[client] && g_cvMode.BoolValue && (buttons & (IN_GRENADE1 | IN_GRENADE2)))
	{
		// hold binds become two-tap: the press primes / throws, the release does nothing
		if (buttons & IN_GRENADE1) buttons |= IN_TOGGLEGRENADE1;
		if (buttons & IN_GRENADE2) buttons |= IN_TOGGLEGRENADE2;
		buttons &= ~(IN_GRENADE1 | IN_GRENADE2);
		changed = true;
	}
	if (g_iInject[client])
	{
		// hold the button down for a few user commands like a real key tap, then release it
		if (g_iInjectCmds[client] == 0)
			g_iInjectCmds[client] = TAP_CMDS;
		buttons |= g_iInject[client];
		if (--g_iInjectCmds[client] == 0)
			g_iInject[client] = 0;
		changed = true;
	}
	return changed ? Plugin_Changed : Plugin_Continue;
}

public Action Cmd_TwoTap(int client, int args)
{
	if (!client)
		return Plugin_Handled;
	if (!g_cvMode.BoolValue)
	{
		ReplyToCommand(client, "[FF] Two-tap mode is disabled on this server. Bind +togglegren1 / +togglegren2 instead.");
		return Plugin_Handled;
	}
	if (args >= 1)
		g_bTwoTap[client] = GetCmdArgInt(1) != 0;
	else
		g_bTwoTap[client] = !g_bTwoTap[client];
	if (g_hCookie != null && AreClientCookiesCached(client))
		g_hCookie.Set(client, g_bTwoTap[client] ? "1" : "0");
	ReplyToCommand(client, g_bTwoTap[client]
		? "[FF] Two-tap ON: tap your +gren1/+gren2 key to prime, tap again to throw. !twotap again to turn it off."
		: "[FF] Two-tap OFF: +gren1/+gren2 are hold to prime, release to throw.");
	return Plugin_Handled;
}

// ---------------------------------------------------------------- chat helper

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	int mode = g_cvHelp.IntValue;
	if (mode == 0 || client < 1 || !IsClientInGame(client) || IsFakeClient(client))
		return;
	char text[256];
	strcopy(text, sizeof(text), sArgs);
	StripQuotes(text);
	for (int i = 0; text[i] != '\0'; i++)
	{
		text[i] = CharToLower(text[i]);
		if (text[i] == '-' || text[i] == '_' || text[i] == '.' || text[i] == ',' || text[i] == '!' || text[i] == '?' || text[i] == '/')
			text[i] = ' ';
	}
	if (!AsksAboutTwoTap(text))
		return;
	float now = GetEngineTime();
	float cd = g_cvHelpCooldown.FloatValue;
	if (now < g_flNextHelp[client] || now < g_flNextHelpAll)
		return;
	g_flNextHelp[client] = now + cd;
	g_flNextHelpAll = now + cd / 3.0;
	char msg[256];
	g_cvHelpText.GetString(msg, sizeof(msg));
	if (mode == 2)
		PrintToChatAll("%s", msg);
	else
		PrintToChat(client, "%s", msg);
}

bool AsksAboutTwoTap(const char[] text)
{
	if (StrContains(text, "togglegren") != -1 || StrContains(text, "toggleone") != -1 || StrContains(text, "toggletwo") != -1)
		return true;
	if (StrContains(text, "gren") == -1 && StrContains(text, "nade") == -1)
		return false;
	static const char keys[][] = { "two tap", "2 tap", "twotap", "2tap", "double tap", "tap twice",
		"not working", "doesnt work", "doesn't work", "dont work", "don't work", "broken" };
	for (int i = 0; i < sizeof(keys); i++)
		if (StrContains(text, keys[i]) != -1)
			return true;
	return false;
}
