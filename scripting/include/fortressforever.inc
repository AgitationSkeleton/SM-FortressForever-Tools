/**
 * Fortress Forever 2.0 natives for SourceMod (library "fortressforever").
 * Provided by plugins/fortressforever.smx from SM-FortressForever-Tools.
 *
 *   #include <fortressforever>
 *
 * The library is optional by default: a plugin compiled against this file still loads
 * when fortressforever.smx is missing, as long as it checks LibraryExists("fortressforever")
 * before calling the natives. Define REQUIRE_PLUGIN before including it to make it required.
 */
#if defined _fortressforever_included
 #endinput
#endif
#define _fortressforever_included

/* Classes: FF's own numbers (the low nibble of CFFPlayer::m_iClassStatus). */
enum FFClass
{
	FFClass_Unknown = 0,
	FFClass_Scout,
	FFClass_Sniper,
	FFClass_Soldier,
	FFClass_Demoman,
	FFClass_Medic,
	FFClass_HWGuy,
	FFClass_Pyro,
	FFClass_Spy,
	FFClass_Engineer,
	FFClass_Civilian
};

enum FFTeam
{
	FFTeam_Unassigned = 0,
	FFTeam_Spectator = 1,
	FFTeam_Blue = 2,
	FFTeam_Red = 3,
	FFTeam_Yellow = 4,
	FFTeam_Green = 5
};

enum FFBuilding
{
	FFBuilding_Dispenser = 0,
	FFBuilding_SentryGun,
	FFBuilding_Detpack,
	FFBuilding_ManCannon     /* jump pad */
};

enum FFGrenade
{
	FFGrenade_Primary = 0,   /* "gren1": frag for most classes */
	FFGrenade_Secondary      /* "gren2": class special (conc, nail, MIRV, ...) */
};

/* Class limit values used by FF: */
#define FF_CLASSLIMIT_UNLIMITED   0
#define FF_CLASSLIMIT_DISABLED    -1

/**
 * Returns a player's class (FFClass_Unknown if he has none yet).
 */
native FFClass FF_GetClass(int client);

/**
 * Changes a player's class at once, the way FF's map Lua does it
 * (ApplyToPlayer with AT.kChangeClass*): it ignores class limits and does not kill him.
 *
 * @param respawn   also respawn him (fresh health, ammo and spawn point); a dead player
 *                  is always respawned
 * @return          true if the player now has that class
 */
native bool FF_SetClass(int client, FFClass class, bool respawn = true);

/**
 * Respawns a player on his team at once (FF's AT.kRespawnPlayers). Fails for spectators.
 */
native bool FF_RespawnPlayer(int client);

/**
 * Refills a living player: health and armour to his class maximum, all ammo and both
 * grenade types to the class maximum, and reloads his clips.
 */
native bool FF_RegeneratePlayer(int client);

/** Armour. FF_SetArmor does not clamp: pass FF_GetMaxArmor() for a normal maximum. */
native int FF_GetArmor(int client);
native void FF_SetArmor(int client, int armor);
native int FF_GetMaxArmor(int client);
native void FF_SetMaxArmor(int client, int maxarmor);

/** Grenade counts. FF_SetGrenades does not clamp to the class maximum (the HUD shows 0-15). */
native int FF_GetGrenades(int client, FFGrenade type);
native void FF_SetGrenades(int client, FFGrenade type, int count);

/**
 * Spy disguise.
 * @return  true if the player is disguised; team and class receive the disguise
 */
native bool FF_GetDisguise(int client, FFTeam &team = FFTeam_Unassigned, FFClass &class = FFClass_Unknown);

/**
 * Disguises a living Spy instantly (FF's own SetDisguise). FF applies it on the player's next
 * think, i.e. within one server tick; FF_GetDisguise reports it from then on.
 * @return  true if FF accepted the disguise (false if the player is not a living Spy)
 */
native bool FF_SetDisguise(int client, FFTeam team, FFClass class);

/** Removes a Spy's disguise. */
native void FF_RemoveDisguise(int client);

/** Whether a Spy is cloaked. */
native bool FF_IsCloaked(int client);

/** The player's building of that type, or -1. */
native int FF_GetBuilding(int client, FFBuilding type);

/** The ff_team_manager entity of a team, or -1. */
native int FF_GetTeamEntity(FFTeam team);

/**
 * Class limit of a team: a count, FF_CLASSLIMIT_UNLIMITED (0) or FF_CLASSLIMIT_DISABLED (-1).
 * This is the effective limit (the map's limit combined with the cr_* convars).
 */
native int FF_GetClassLimit(FFTeam team, FFClass class);

/**
 * Sets a team's class limit the way map Lua does (team:SetClassLimit); the cr_* convars
 * still apply on top of it. Changing the map's limits lasts until the map's Lua sets them again.
 */
native bool FF_SetClassLimit(FFTeam team, FFClass class, int limit);

/** Allies of a team as a bit mask: bit (1 << team) for each allied team. */
native int FF_GetTeamAllies(FFTeam team);
native void FF_SetTeamAllies(FFTeam team, int allymask);

/** Whether two teams are allies (or the same team). */
native bool FF_AreTeamsAllied(FFTeam team1, FFTeam team2);

/** Whether a team takes part in the map: FF disables a team with a player limit of -1. */
native bool FF_IsTeamActive(FFTeam team);

/** Team player limit: 0 = no limit, -1 = team disabled. */
native int FF_GetTeamMaxPlayers(FFTeam team);
native void FF_SetTeamMaxPlayers(FFTeam team, int maxplayers);

/** Team "free for all" flag (team members can hurt each other). */
native bool FF_IsTeamFFA(FFTeam team);
native void FF_SetTeamFFA(FFTeam team, bool ffa);

/**
 * Runs a string of FF map Lua in the server's Lua state (FF's lua_dostring command),
 * synchronously. Avoid ';' (use spaces or newlines between statements), '//' and double
 * quotes, which the console command parser treats specially.
 * @return  false if the code contains a character that would break the command
 */
native bool FF_RunLua(const char[] code);

/**
 * Called after a player's class changed (FF's player_changeclass event).
 */
forward void FF_OnPlayerClassChanged(int client, FFClass oldclass, FFClass newclass);

/** Class name as FF's "class" command takes it ("scout", ..., "hwguy", "civilian"). */
stock bool FF_GetClassName(FFClass class, char[] buffer, int maxlen)
{
	static const char names[][] = { "", "scout", "sniper", "soldier", "demoman", "medic", "hwguy", "pyro", "spy", "engineer", "civilian" };
	if (class < FFClass_Unknown || view_as<int>(class) >= sizeof(names))
		return false;
	strcopy(buffer, maxlen, names[view_as<int>(class)]);
	return class != FFClass_Unknown;
}

/** Class from a name ("scout", "hwguy" or "heavy", ...), FFClass_Unknown if not recognised. */
stock FFClass FF_GetClassFromName(const char[] name)
{
	static const char names[][] = { "", "scout", "sniper", "soldier", "demoman", "medic", "hwguy", "pyro", "spy", "engineer", "civilian" };
	for (int i = 1; i < sizeof(names); i++)
		if (StrEqual(name, names[i], false))
			return view_as<FFClass>(i);
	if (StrEqual(name, "heavy", false) || StrEqual(name, "hw", false))
		return FFClass_HWGuy;
	if (StrEqual(name, "demo", false))
		return FFClass_Demoman;
	if (StrEqual(name, "engy", false) || StrEqual(name, "engi", false))
		return FFClass_Engineer;
	if (StrEqual(name, "civ", false))
		return FFClass_Civilian;
	return FFClass_Unknown;
}

#if !defined FORTRESSFOREVER_PROVIDER
public SharedPlugin __pl_fortressforever =
{
	name = "fortressforever",
	file = "fortressforever.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_fortressforever_SetNTVOptional()
{
	MarkNativeAsOptional("FF_GetClass");
	MarkNativeAsOptional("FF_SetClass");
	MarkNativeAsOptional("FF_RespawnPlayer");
	MarkNativeAsOptional("FF_RegeneratePlayer");
	MarkNativeAsOptional("FF_GetArmor");
	MarkNativeAsOptional("FF_SetArmor");
	MarkNativeAsOptional("FF_GetMaxArmor");
	MarkNativeAsOptional("FF_SetMaxArmor");
	MarkNativeAsOptional("FF_GetGrenades");
	MarkNativeAsOptional("FF_SetGrenades");
	MarkNativeAsOptional("FF_GetDisguise");
	MarkNativeAsOptional("FF_SetDisguise");
	MarkNativeAsOptional("FF_RemoveDisguise");
	MarkNativeAsOptional("FF_IsCloaked");
	MarkNativeAsOptional("FF_GetBuilding");
	MarkNativeAsOptional("FF_GetTeamEntity");
	MarkNativeAsOptional("FF_GetClassLimit");
	MarkNativeAsOptional("FF_SetClassLimit");
	MarkNativeAsOptional("FF_GetTeamAllies");
	MarkNativeAsOptional("FF_SetTeamAllies");
	MarkNativeAsOptional("FF_AreTeamsAllied");
	MarkNativeAsOptional("FF_IsTeamActive");
	MarkNativeAsOptional("FF_GetTeamMaxPlayers");
	MarkNativeAsOptional("FF_SetTeamMaxPlayers");
	MarkNativeAsOptional("FF_IsTeamFFA");
	MarkNativeAsOptional("FF_SetTeamFFA");
	MarkNativeAsOptional("FF_RunLua");
}
#endif
#endif
