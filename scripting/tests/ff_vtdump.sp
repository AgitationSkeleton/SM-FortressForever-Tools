/**
 * Prints the vtable function pointers of a player, three weapons and a few other entities,
 * for tools/vtcheck.py, which compares them with FF's Linux server.so symbols.
 *   sm_ffvt_dump [last slot]     (default 480)
 * Run it with no other plugin hooking these entities (unload ff_gamedata_test first):
 * SDKHooks/DHooks replace hooked slots with their own thunks.
 */
#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = { name = "FF vtable dump", author = "AgitationSkeleton", description = "Dumps vtables for tools/vtcheck.py", version = "1.0", url = "https://github.com/AgitationSkeleton/SM-FortressForever-Tools" };

public void OnPluginStart()
{
	RegAdminCmd("sm_ffvt_dump", Cmd_VTables, ADMFLAG_ROOT);
}

int Bot()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) >= 2)
			return i;
	return 0;
}

// sm_ffvt_dump: "VT <netclass|classname> <entindex> <slot>:<addr> ..." 16 slots per line, slots 0..max
public Action Cmd_VTables(int client, int args)
{
	int maxslot = args >= 1 ? GetCmdArgInt(1) : 480;
	char want[][] = { "player", "ff_weapon_shotgun", "ff_weapon_crowbar", "ff_weapon_rpg", "prop_dynamic", "info_target",
		"math_counter", "ff_team_manager", "ff_gamerules", "prop_physics_multiplayer", "worldspawn" };
	int made[sizeof(want)];
	for (int i = 0; i < sizeof(want); i++)
	{
		int e = -1;
		if (StrEqual(want[i], "player"))
			e = Bot();
		else if (StrEqual(want[i], "worldspawn"))
			e = 0;
		else
			e = FindEntityByClassname(-1, want[i]);
		if (e == -1 && !StrEqual(want[i], "ff_team_manager") && !StrEqual(want[i], "ff_gamerules"))
		{
			e = CreateEntityByName(want[i]);
			made[i] = e;
		}
		if (e < 0)
			continue;
		Address a = GetEntityAddress(e);
		if (a == Address_Null)
			continue;
		Address vt = view_as<Address>(LoadFromAddress(a, NumberType_Int32));
		char line[1024];
		FormatEx(line, sizeof(line), "VT %s %d", want[i], e);
		for (int slot = 0; slot <= maxslot; slot++)
		{
			int fn = LoadFromAddress(vt + view_as<Address>(slot * 4), NumberType_Int32);
			Format(line, sizeof(line), "%s %d:%08x", line, slot, fn);
			if (slot % 16 == 15 || slot == maxslot)
			{
				PrintToServer("%s", line);
				FormatEx(line, sizeof(line), "VT %s %d", want[i], e);
			}
		}
	}
	for (int i = 0; i < sizeof(want); i++)
		if (made[i] > 0 && IsValidEntity(made[i]))
			RemoveEntity(made[i]);
	ReplyToCommand(client, "VT done");
	return Plugin_Handled;
}
