/**
 * ff_pipetint - colours the Demoman's grenade-launcher grenades and pipe-launcher pipebombs in
 * the colour of the team that fired them, with the pipebombs a darker shade so the two stay easy
 * to tell apart.
 *
 * Both projectiles use models/projectiles/pipe/w_pipe.mdl, which has three skins:
 *   0  pipe_green   (the yellow texture, pulsing glow)  - FF's pipebombs
 *   1  pipe_blue    (blue texture, steady glow)          - FF's grenades
 *   2  pipe_yellow  (the yellow texture, pulsing glow)
 * so by default every grenade is blue and every pipebomb yellow, whatever the team.
 *
 * The plugin picks the skin whose texture can be tinted to the team's colour (blue for Blue,
 * yellow for the other teams: a tint can only darken or filter a texture's colour, never add one
 * it does not have) and sets the projectile's render colour (m_clrRender), which the client
 * multiplies into the texture.
 *
 * Client quirk it cannot change: FF's client draws pipebombs with skin 2 (yellow) for about half
 * of all players (C_FFProjectilePipebomb::DrawModel, keyed to the parity of the viewer's Steam
 * account ID). Those players see Blue's pipebombs as a darkened yellow instead of dark blue;
 * every other colour looks the same for everyone.
 */
#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"

#define SKIN_BLUE   1
#define SKIN_YELLOW 2

public Plugin myinfo =
{
	name = "FF Pipe Tint",
	author = "AgitationSkeleton",
	description = "Colours Demoman grenades and pipebombs in the firing team's colour",
	version = PLUGIN_VERSION,
	url = "https://github.com/AgitationSkeleton/SM-FortressForever-Tools"
};

enum { Proj_Grenade = 0, Proj_Pipe = 1 }

static const char g_sTeamKey[6][] = { "", "", "blue", "red", "yellow", "green" };

// defaults: grenade, pipebomb (darker) per team; Blue tints the blue skin, the others the yellow one
static const char g_sDefault[6][2][16] =
{
	{ "", "" },
	{ "", "" },
	{ "255 255 255", "140 160 255" },   // blue   (blue skin)
	{ "255 70 50",   "190 30 20" },     // red    (yellow skin)
	{ "255 255 255", "200 170 90" },    // yellow (yellow skin)
	{ "110 255 80",  "60 190 40" }      // green  (yellow skin)
};

ConVar g_cvEnable;
ConVar g_cvColor[6][2];
int g_iColor[6][2][3];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	char folder[32];
	GetGameFolderName(folder, sizeof(folder));
	if (!StrEqual(folder, "fortressforever", false))
	{
		strcopy(error, err_max, "ff_pipetint.smx only runs on Fortress Forever");
		return APLRes_Failure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("ff_pipetint_version", PLUGIN_VERSION, "FF Pipe Tint version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnable = CreateConVar("ff_pipetint_enable", "1", "Colour Demoman grenades and pipebombs by team", _, true, 0.0, true, 1.0);
	char name[64], desc[160];
	for (int t = 2; t <= 5; t++)
	{
		FormatEx(name, sizeof(name), "ff_pipetint_%s_grenade", g_sTeamKey[t]);
		FormatEx(desc, sizeof(desc), "\"R G B\" tint of %s's grenade-launcher grenades (255 255 255 = the skin's own colour)", g_sTeamKey[t]);
		g_cvColor[t][Proj_Grenade] = CreateConVar(name, g_sDefault[t][Proj_Grenade], desc);
		FormatEx(name, sizeof(name), "ff_pipetint_%s_pipe", g_sTeamKey[t]);
		FormatEx(desc, sizeof(desc), "\"R G B\" tint of %s's pipe-launcher pipebombs", g_sTeamKey[t]);
		g_cvColor[t][Proj_Pipe] = CreateConVar(name, g_sDefault[t][Proj_Pipe], desc);
		g_cvColor[t][Proj_Grenade].AddChangeHook(OnColorChanged);
		g_cvColor[t][Proj_Pipe].AddChangeHook(OnColorChanged);
	}
	AutoExecConfig(true, "ff_pipetint");
	ParseColors();
}

public void OnConfigsExecuted()
{
	ParseColors();
}

public void OnColorChanged(ConVar cv, const char[] oldValue, const char[] newValue)
{
	ParseColors();
}

void ParseColors()
{
	char buf[32], parts[3][8];
	for (int t = 2; t <= 5; t++)
	{
		for (int k = 0; k < 2; k++)
		{
			g_cvColor[t][k].GetString(buf, sizeof(buf));
			TrimString(buf);
			int n = ExplodeString(buf, " ", parts, sizeof(parts), sizeof(parts[]));
			for (int c = 0; c < 3; c++)
			{
				int v = (c < n) ? StringToInt(parts[c]) : 255;
				g_iColor[t][k][c] = v < 0 ? 0 : (v > 255 ? 255 : v);
			}
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (entity <= MaxClients || !g_cvEnable.BoolValue)
		return;
	int kind;
	if (StrEqual(classname, "ff_projectile_gl"))
		kind = Proj_Grenade;
	else if (StrEqual(classname, "ff_projectile_pl"))
		kind = Proj_Pipe;
	else
		return;
	// FF spawns the projectile and sets its thrower right after creating it; colour it next frame
	DataPack dp = new DataPack();
	dp.WriteCell(EntIndexToEntRef(entity));
	dp.WriteCell(kind);
	RequestFrame(Frame_Tint, dp);
}

public void Frame_Tint(DataPack dp)
{
	dp.Reset();
	int entity = EntRefToEntIndex(dp.ReadCell());
	int kind = dp.ReadCell();
	delete dp;
	if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity))
		return;
	int thrower = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
	if (thrower < 1 || thrower > MaxClients || !IsClientInGame(thrower))
		thrower = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (thrower < 1 || thrower > MaxClients || !IsClientInGame(thrower))
		return;
	int team = GetClientTeam(thrower);
	if (team < 2 || team > 5)
		return;
	SetEntProp(entity, Prop_Send, "m_nSkin", team == 2 ? SKIN_BLUE : SKIN_YELLOW);
	SetEntityRenderColor(entity, g_iColor[team][kind][0], g_iColor[team][kind][1], g_iColor[team][kind][2], 255);
}
