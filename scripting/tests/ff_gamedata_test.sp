/**
 * Checks the Fortress Forever 2.0 SDKTools/SDKHooks gamedata
 * (gamedata/sdktools.games/custom and gamedata/sdkhooks.games/custom).
 *
 *   sm_ffgd_step <n>    run one check against the first living bot (0 = list the steps)
 *   sm_ffgd_hooks       counts of SDKHooks / OnPlayerRunCmd / entity-listener callbacks since load
 *
 * One step per command, so a wrong offset crashes on a known call.
 */
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = { name = "FF gamedata test", author = "AgitationSkeleton", description = "Exercises the FF 2.0 SDKTools/SDKHooks offsets", version = "1.0", url = "https://github.com/AgitationSkeleton/SM-FortressForever-Tools" };

#define TEST_MODEL "models/items/healthkit.mdl"

enum
{
	H_RunCmd, H_TakeDamage, H_TakeDamageAlive, H_TraceAttack, H_Spawn, H_Think, H_PreThink, H_PostThink,
	H_Transmit, H_ShouldCollide, H_StartTouch, H_Touch, H_EndTouch, H_FireBullets, H_GetMaxHealth,
	H_GroundEnt, H_WCanUse, H_WEquip, H_WDrop, H_WSwitch, H_WCanSwitch, H_Use, H_VPhysics, H_Reload,
	H_Blocked, H_Created, H_Destroyed, H_Output, H_COUNT
};
char g_sHookNames[H_COUNT][] = {
	"runcmd", "takedamage", "takedamage_alive", "traceattack", "spawn", "think", "prethink", "postthink",
	"settransmit", "shouldcollide", "starttouch", "touch", "endtouch", "firebullets", "getmaxhealth",
	"groundentchanged", "weaponcanuse", "weaponequip", "weapondrop", "weaponswitch", "weaponcanswitchto", "use",
	"vphysicsupdate", "reload", "blocked", "entitycreated", "entitydestroyed", "output"
};
int g_iHits[H_COUNT];
bool g_bLate;
Handle g_hGetVelocity, g_hSetOwner;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	RegAdminCmd("sm_ffgd_step", Cmd_Step, ADMFLAG_ROOT);
	RegAdminCmd("sm_ffgd_hooks", Cmd_Hooks, ADMFLAG_ROOT);

	GameData gc = new GameData("sdktools.games");
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gc, SDKConf_Virtual, "GetVelocity");
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, 0, VENCODE_FLAG_COPYBACK);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, 0, VENCODE_FLAG_COPYBACK);
	g_hGetVelocity = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gc, SDKConf_Virtual, "SetOwnerEntity");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL);
	g_hSetOwner = EndPrepSDKCall();

	delete gc;

	if (g_bLate)
	{
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i))
				OnClientPutInServer(i);
		char cls[64];
		for (int e = MaxClients + 1; e < GetMaxEntities(); e++)
			if (IsValidEntity(e) && GetEntityClassname(e, cls, sizeof(cls)))
				HookEntity(e, cls);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_TakeDamage);
	SDKHook(client, SDKHook_OnTakeDamageAlive, Hook_TakeDamageAlive);
	SDKHook(client, SDKHook_TraceAttack, Hook_TraceAttack);
	SDKHook(client, SDKHook_SpawnPost, Hook_Spawn);
	SDKHook(client, SDKHook_PreThink, Hook_PreThink);
	SDKHook(client, SDKHook_PostThink, Hook_PostThink);
	SDKHook(client, SDKHook_SetTransmit, Hook_Transmit);
	SDKHook(client, SDKHook_ShouldCollide, Hook_ShouldCollide);
	SDKHook(client, SDKHook_StartTouch, Hook_StartTouch);
	SDKHook(client, SDKHook_Touch, Hook_Touch);
	SDKHook(client, SDKHook_EndTouch, Hook_EndTouch);
	SDKHook(client, SDKHook_FireBulletsPost, Hook_FireBullets);
	SDKHook(client, SDKHook_GetMaxHealth, Hook_GetMaxHealth);
	SDKHook(client, SDKHook_GroundEntChangedPost, Hook_GroundEnt);
	SDKHook(client, SDKHook_WeaponCanUse, Hook_WCanUse);
	SDKHook(client, SDKHook_WeaponEquipPost, Hook_WEquip);
	SDKHook(client, SDKHook_WeaponDropPost, Hook_WDrop);
	SDKHook(client, SDKHook_WeaponSwitchPost, Hook_WSwitch);
	SDKHook(client, SDKHook_WeaponCanSwitchTo, Hook_WCanSwitch);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	g_iHits[H_Created]++;
	HookEntity(entity, classname);
}

public void OnEntityDestroyed(int entity)
{
	g_iHits[H_Destroyed]++;
}

void HookEntity(int entity, const char[] cls)
{
	if (entity <= MaxClients)
		return;
	if (StrContains(cls, "ff_weapon_") == 0)
		SDKHook(entity, SDKHook_Reload, Hook_Reload);
	if (StrContains(cls, "func_door") == 0 || StrContains(cls, "func_movelinear") == 0 || StrContains(cls, "func_rotating") == 0 || StrContains(cls, "func_train") == 0 || StrContains(cls, "func_tracktrain") == 0)
		SDKHook(entity, SDKHook_Blocked, Hook_Blocked);
	SDKHook(entity, SDKHook_Think, Hook_Think);
}

public Action Hook_TakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) { g_iHits[H_TakeDamage]++; return Plugin_Continue; }
public Action Hook_TakeDamageAlive(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) { g_iHits[H_TakeDamageAlive]++; return Plugin_Continue; }
public Action Hook_TraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup) { g_iHits[H_TraceAttack]++; return Plugin_Continue; }
public void Hook_Spawn(int client) { g_iHits[H_Spawn]++; }
public void Hook_Think(int entity) { g_iHits[H_Think]++; }
public void Hook_PreThink(int client) { g_iHits[H_PreThink]++; }
public void Hook_PostThink(int client) { g_iHits[H_PostThink]++; }
public Action Hook_Transmit(int entity, int client) { g_iHits[H_Transmit]++; return Plugin_Continue; }
public bool Hook_ShouldCollide(int entity, int collisiongroup, int contentsmask, bool originalResult) { g_iHits[H_ShouldCollide]++; return originalResult; }
public Action Hook_StartTouch(int entity, int other) { g_iHits[H_StartTouch]++; return Plugin_Continue; }
public Action Hook_Touch(int entity, int other) { g_iHits[H_Touch]++; return Plugin_Continue; }
public Action Hook_EndTouch(int entity, int other) { g_iHits[H_EndTouch]++; return Plugin_Continue; }
public void Hook_FireBullets(int client, int shots, const char[] weaponname) { g_iHits[H_FireBullets]++; }
public Action Hook_GetMaxHealth(int entity, int &maxhealth) { g_iHits[H_GetMaxHealth]++; return Plugin_Continue; }
public void Hook_GroundEnt(int entity) { g_iHits[H_GroundEnt]++; }
public Action Hook_WCanUse(int client, int weapon) { g_iHits[H_WCanUse]++; return Plugin_Continue; }
public void Hook_WEquip(int client, int weapon) { g_iHits[H_WEquip]++; }
public void Hook_WDrop(int client, int weapon) { g_iHits[H_WDrop]++; }
public void Hook_WSwitch(int client, int weapon) { g_iHits[H_WSwitch]++; }
public Action Hook_WCanSwitch(int client, int weapon) { g_iHits[H_WCanSwitch]++; return Plugin_Continue; }
public Action Hook_Use(int entity, int activator, int caller, UseType type, float value) { g_iHits[H_Use]++; return Plugin_Continue; }
public void Hook_VPhysics(int entity) { g_iHits[H_VPhysics]++; }
public Action Hook_Reload(int weapon) { g_iHits[H_Reload]++; return Plugin_Continue; }
public void Hook_Blocked(int entity, int other) { g_iHits[H_Blocked]++; }
public void Out_Trigger(const char[] output, int caller, int activator, float delay) { g_iHits[H_Output]++; }

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	g_iHits[H_RunCmd]++;
	return Plugin_Continue;
}

public Action Cmd_Hooks(int client, int args)
{
	char line[1024];
	for (int i = 0; i < H_COUNT; i++)
		Format(line, sizeof(line), "%s %s=%d", line, g_sHookNames[i], g_iHits[i]);
	ReplyToCommand(client, "HOOKS%s", line);
	return Plugin_Handled;
}

int Bot()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayerAlive(i) && IsFakeClient(i) && GetClientTeam(i) >= 2)
			return i;
	return 0;
}

int NewProp(const char[] cls)
{
	PrecacheModel(TEST_MODEL);
	int prop = CreateEntityByName(cls);
	if (prop > 0)
	{
		DispatchKeyValue(prop, "model", TEST_MODEL);
		SetEntityModel(prop, TEST_MODEL);
	}
	return prop;
}

public Action Cmd_Step(int client, int args)
{
	int n = GetCmdArgInt(1), b = Bot();
	if (!b && n != 0)
	{
		ReplyToCommand(client, "no living bot");
		return Plugin_Handled;
	}
	char s[128];
	switch (n)
	{
		case 1:
		{
			SetVariantString("targetname ffgd_test_name");
			bool ok = AcceptEntityInput(b, "AddOutput");
			GetEntPropString(b, Prop_Data, "m_iName", s, sizeof(s));
			ReplyToCommand(client, "STEP 1 AcceptInput(AddOutput): ret %d, targetname '%s' (want ffgd_test_name)", ok, s);
			DispatchKeyValue(b, "targetname", "");
		}
		case 2:
		{
			float pos[3], now[3];
			GetClientAbsOrigin(b, pos);
			pos[2] += 64.0;
			TeleportEntity(b, pos, NULL_VECTOR, view_as<float>({ 0.0, 0.0, 0.0 }));
			GetClientAbsOrigin(b, now);
			ReplyToCommand(client, "STEP 2 Teleport: z after %.1f, wanted %.1f", now[2], pos[2]);
		}
		case 3:
		{
			float ang[3];
			GetClientEyeAngles(b, ang);
			ReplyToCommand(client, "STEP 3 EyeAngles: %.1f %.1f %.1f, netprop %.1f %.1f", ang[0], ang[1], ang[2],
				GetEntPropFloat(b, Prop_Send, "m_angEyeAngles[0]"), GetEntPropFloat(b, Prop_Send, "m_angEyeAngles[1]"));
		}
		case 4:
		{
			char line[512];
			for (int slot = 0; slot < 6; slot++)
			{
				int w = GetPlayerWeaponSlot(b, slot);
				s[0] = '\0';
				if (w > 0) GetEntityClassname(w, s, sizeof(s));
				Format(line, sizeof(line), "%s [%d]=%d(%s)", line, slot, w, s);
			}
			ReplyToCommand(client, "STEP 4 Weapon_GetSlot:%s", line);
			line[0] = '\0';
			int size = GetEntPropArraySize(b, Prop_Send, "m_hMyWeapons");
			for (int i = 0; i < size; i++)
			{
				int w = GetEntPropEnt(b, Prop_Send, "m_hMyWeapons", i);
				if (w > 0)
				{
					GetEntityClassname(w, s, sizeof(s));
					Format(line, sizeof(line), "%s %d(%s)", line, w, s);
				}
			}
			ReplyToCommand(client, "STEP 4 m_hMyWeapons:%s", line);
		}
		case 5:
		{
			PrecacheModel(TEST_MODEL);
			int prop = CreateEntityByName("prop_dynamic");
			SetEntityModel(prop, TEST_MODEL);
			GetEntPropString(prop, Prop_Data, "m_ModelName", s, sizeof(s));
			ReplyToCommand(client, "STEP 5 SetEntityModel: '%s' modelindex %d (want %s)", s, GetEntProp(prop, Prop_Send, "m_nModelIndex"), TEST_MODEL);
			RemoveEntity(prop);
		}
		case 6:
		{
			int e = CreateEntityByName("info_target");
			bool ok = DispatchKeyValue(e, "targetname", "ffgd_kv");
			GetEntPropString(e, Prop_Data, "m_iName", s, sizeof(s));
			ReplyToCommand(client, "STEP 6 DispatchKeyValue: ret %d name '%s' (want ffgd_kv)", ok, s);
			RemoveEntity(e);
		}
		case 7:
		{
			int e = CreateEntityByName("info_target");
			bool ok = DispatchKeyValueFloat(e, "targetname", 1.5);
			GetEntPropString(e, Prop_Data, "m_iName", s, sizeof(s));
			ReplyToCommand(client, "STEP 7 DispatchKeyValueFloat: ret %d name '%s' (want 1.500000)", ok, s);
			RemoveEntity(e);
		}
		case 8:
		{
			int e = CreateEntityByName("info_target");
			bool ok = DispatchKeyValueVector(e, "origin", view_as<float>({ 12.0, 34.0, 56.0 }));
			float v[3];
			GetEntPropVector(e, Prop_Data, "m_vecOrigin", v);
			ReplyToCommand(client, "STEP 8 DispatchKeyValueVector: ret %d origin %.0f %.0f %.0f (want 12 34 56)", ok, v[0], v[1], v[2]);
			RemoveEntity(e);
		}
		case 9:
		{
			int e = NewProp("prop_dynamic");
			DispatchSpawn(e);
			ActivateEntity(e);
			ReplyToCommand(client, "STEP 9 Activate: called on prop %d, no crash", e);
			RemoveEntity(e);
		}
		case 10:
		{
			int w = GetPlayerWeaponSlot(b, 0);
			GetEntityClassname(w, s, sizeof(s));
			bool ok = w > 0 && RemovePlayerItem(b, w);
			int owner = w > 0 ? GetEntPropEnt(w, Prop_Send, "m_hOwner") : -2;
			if (ok)
				RemoveEntity(w);
			ReplyToCommand(client, "STEP 10 RemovePlayerItem(slot 0 %s): ret %d, owner after %d, slot 0 now %d", s, ok, owner, GetPlayerWeaponSlot(b, 0));
		}
		case 11:
		{
			int before = g_iHits[H_WCanUse], eq = g_iHits[H_WEquip];
			int w = GivePlayerItem(b, "ff_weapon_crowbar");   // run step 10 first: the bot must not own one
			int owner = w > 0 ? GetEntPropEnt(w, Prop_Send, "m_hOwner") : -2;
			ReplyToCommand(client, "STEP 11 GiveNamedItem(ff_weapon_crowbar): ent %d owner %d (bot %d), WeaponCanUse +%d WeaponEquip +%d",
				w, owner, b, g_iHits[H_WCanUse] - before, g_iHits[H_WEquip] - eq);
		}
		case 12:
		{
			int w = CreateEntityByName("ff_weapon_supershotgun");
			DispatchSpawn(w);
			int eq = g_iHits[H_WEquip];
			EquipPlayerWeapon(b, w);
			ReplyToCommand(client, "STEP 12 WeaponEquip(ff_weapon_supershotgun %d): owner %d (bot %d), WeaponEquip hook +%d",
				w, GetEntPropEnt(w, Prop_Send, "m_hOwner"), b, g_iHits[H_WEquip] - eq);
		}
		case 13:
		{
			IgniteEntity(b, 3.0);
			ReplyToCommand(client, "STEP 13 Ignite: FL_ONFIRE %d (want 1), effect entity %d", (GetEntityFlags(b) & FL_ONFIRE) != 0, GetEntPropEnt(b, Prop_Send, "m_hEffectEntity"));
		}
		case 14:
		{
			ExtinguishEntity(b);
			ReplyToCommand(client, "STEP 14 Extinguish: FL_ONFIRE %d (want 0)", (GetEntityFlags(b) & FL_ONFIRE) != 0);
		}
		case 15:
		{
			float v[3], av[3], p[3];
			SDKCall(g_hGetVelocity, b, v, av);
			GetEntPropVector(b, Prop_Data, "m_vecAbsVelocity", p);
			ReplyToCommand(client, "STEP 15 GetVelocity: %.1f %.1f %.1f, m_vecAbsVelocity %.1f %.1f %.1f", v[0], v[1], v[2], p[0], p[1], p[2]);
		}
		case 16:
		{
			int e = NewProp("prop_dynamic");
			DispatchSpawn(e);
			SDKCall(g_hSetOwner, e, b);
			ReplyToCommand(client, "STEP 16 SetOwnerEntity: m_hOwnerEntity %d (want %d)", GetEntPropEnt(e, Prop_Send, "m_hOwnerEntity"), b);
			RemoveEntity(e);
		}
		case 17:
		{
			int w = GetEntPropEnt(b, Prop_Send, "m_hActiveWeapon");
			int type = w > 0 ? GetEntProp(w, Prop_Send, "m_iPrimaryAmmoType") : -1;
			int before = type >= 0 ? GetEntProp(b, Prop_Send, "m_iAmmo", _, type) : -1;
			if (type >= 0)
				SetEntProp(b, Prop_Send, "m_iAmmo", 0, _, type);
			int got = type >= 0 ? GivePlayerAmmo(b, 5, type, true) : -1;
			int after = type >= 0 ? GetEntProp(b, Prop_Send, "m_iAmmo", _, type) : -1;
			if (type >= 0)
				SetEntProp(b, Prop_Send, "m_iAmmo", before, _, type);
			ReplyToCommand(client, "STEP 17 GiveAmmo: type %d, from 0 gave %d, ammo now %d (want 5)", type, got, after);
		}
		case 18:
		{
			int hp = GetEntProp(b, Prop_Data, "m_iMaxHealth"), mh = g_iHits[H_GetMaxHealth];
			ReplyToCommand(client, "STEP 18 GetMaxHealth hook total %d so far (m_iMaxHealth %d); the game calls it when health is given", mh, hp);
		}
		case 19:
		{
			char old[64];
			GetClientName(b, old, sizeof(old));
			SetClientName(b, "ffgd renamed");
			GetClientName(b, s, sizeof(s));
			SetClientInfo(b, "ffgd_info", "1");
			char info[16];
			GetClientInfo(b, "ffgd_info", info, sizeof(info));
			ReplyToCommand(client, "STEP 19 SetClientName: '%s' (want 'ffgd renamed'), SetClientInfo -> '%s'", s, info);
			SetClientName(b, old);
		}
		case 20:
		{
			int e = CreateEntityByName("math_counter");
			DispatchSpawn(e);
			HookSingleEntityOutput(e, "OutValue", Out_Trigger, true);
			int before = g_iHits[H_Output];
			SetVariantFloat(1.0);
			AcceptEntityInput(e, "Add");
			ReplyToCommand(client, "STEP 20 HookSingleEntityOutput(math_counter OutValue): callback +%d (want 1)", g_iHits[H_Output] - before);
			RemoveEntity(e);
		}
		case 21:
		{
			int hp = GetClientHealth(b), ar = GetEntProp(b, Prop_Send, "m_iArmor");
			int td = g_iHits[H_TakeDamage];
			SDKHooks_TakeDamage(b, 0, 0, 10.0, DMG_GENERIC);
			ReplyToCommand(client, "STEP 21 SDKHooks_TakeDamage(10): health %d->%d armour %d->%d, OnTakeDamage hook +%d", hp, GetClientHealth(b), ar, GetEntProp(b, Prop_Send, "m_iArmor"), g_iHits[H_TakeDamage] - td);
		}
		case 22:
		{
			int w = GetPlayerWeaponSlot(b, 1);
			if (w <= 0) w = GetPlayerWeaponSlot(b, 0);
			int d = g_iHits[H_WDrop];
			if (w > 0)
				SDKHooks_DropWeapon(b, w, NULL_VECTOR, NULL_VECTOR);
			ReplyToCommand(client, "STEP 22 SDKHooks_DropWeapon(%d): owner after %d, WeaponDrop hook +%d", w, w > 0 && IsValidEntity(w) ? GetEntPropEnt(w, Prop_Send, "m_hOwner") : -2, g_iHits[H_WDrop] - d);
			if (w > 0 && IsValidEntity(w) && GetEntPropEnt(w, Prop_Send, "m_hOwner") == -1)
				RemoveEntity(w);
		}
		case 23:
		{
			int e = NewProp("prop_dynamic");
			DispatchSpawn(e);
			SDKHook(e, SDKHook_Use, Hook_Use);
			int u = g_iHits[H_Use];
			AcceptEntityInput(e, "Use", b, b);
			ReplyToCommand(client, "STEP 23 Use input on prop: Use hook +%d (want 1)", g_iHits[H_Use] - u);
			RemoveEntity(e);
		}
		case 24:
		{
			PrecacheModel("models/props_c17/oildrum001.mdl");
			int e = CreateEntityByName("prop_physics_override");
			DispatchKeyValue(e, "model", "models/props_c17/oildrum001.mdl");
			float pos[3];
			GetClientEyePosition(b, pos);
			pos[2] += 48.0;
			DispatchKeyValueVector(e, "origin", pos);
			DispatchSpawn(e);
			SDKHook(e, SDKHook_VPhysicsUpdate, Hook_VPhysics);
			TeleportEntity(e, NULL_VECTOR, NULL_VECTOR, view_as<float>({ 0.0, 0.0, 200.0 }));
			CreateTimer(3.0, Timer_Kill, EntIndexToEntRef(e));
			ReplyToCommand(client, "STEP 24 prop_physics %d dropped above the bot; check sm_ffgd_hooks vphysicsupdate (removed in 3 s)", e);
		}
		case 25:
		{
			ForcePlayerSuicide(b);
			ReplyToCommand(client, "STEP 25 CommitSuicide: alive %d (want 0)", IsPlayerAlive(b));
		}
		case 26:
		{
			int e = FindEntityByClassname(-1, "ff_team_manager"), cnt = 0;
			while (e != -1) { cnt++; e = FindEntityByClassname(e, "ff_team_manager"); }
			ReplyToCommand(client, "STEP 26 FindEntityByClassname(ff_team_manager): %d found", cnt);
		}
		case 27:
		{
			int w = GetEntPropEnt(b, Prop_Send, "m_hActiveWeapon");
			GetEntityClassname(w, s, sizeof(s));
			FakeClientCommand(b, "use ff_weapon_crowbar");
			int sw = g_iHits[H_WSwitch];
			FakeClientCommand(b, "lastinv");
			ReplyToCommand(client, "STEP 27 weapon switch via commands (was %s): WeaponSwitch +%d", s, g_iHits[H_WSwitch] - sw);
		}
		default:
		{
			ReplyToCommand(client, "steps: 1 AcceptInput, 2 Teleport, 3 EyeAngles, 4 Weapon_GetSlot, 5 SetEntityModel, 6 DispatchKeyValue, 7 DispatchKeyValueFloat, 8 DispatchKeyValueVector, 9 Activate, 10 RemovePlayerItem, 11 GiveNamedItem, 12 WeaponEquip, 13 Ignite, 14 Extinguish,");
			ReplyToCommand(client, "  15 GetVelocity, 16 SetOwnerEntity, 17 GiveAmmo, 18 GetMaxHealth count, 19 SetClientName/Info, 20 entity outputs, 21 SDKHooks_TakeDamage, 22 SDKHooks_DropWeapon, 23 Use, 24 VPhysicsUpdate, 25 CommitSuicide, 26 FindEntityByClassname, 27 weapon switch");
		}
	}
	return Plugin_Handled;
}

public Action Timer_Kill(Handle t, int ref)
{
	int e = EntRefToEntIndex(ref);
	if (e > 0)
		RemoveEntity(e);
	return Plugin_Stop;
}
