#!/usr/bin/env python3
"""Write SourceMod SDKTools / SDKHooks gamedata for Fortress Forever 2.0 (Source SDK 2013).

  python -I gen_gamedata.py <fortressforever/bin/server.so> <output gamedata dir> [server.dll]

Writes <out>/sdktools.games/custom/common.games.txt and
<out>/sdkhooks.games/custom/common.games.txt.

How the offsets are found
-------------------------
FF ships its Linux server.so with symbols. For every gamedata key, SDKTOOLS / SDKHOOKS name the
class whose vtable is read and the exact virtual (method name and argument list). The
Linux slot is its index in that vtable. The Windows slot follows from two MSVC rules
(elfvt.windows_slots):

* MSVC has one destructor slot where GCC has two, so Windows = Linux - 1;
* overloads declared together are reversed on MSVC, which affects DispatchKeyValue*
  (KeyValue x3), SetEntityModel (FF 2.0 added SetModel(const char*, int)),
  CommitSuicide and GroundEntChanged.

With server.dll given, the FireOutput signature (entity output hooks, HookEntityOutput)
is found with find_fireoutput.py and added; SourceMod's FF 2.4 pattern does not match 2.0,
so without it SourceMod disables entity outputs.

The Windows values were then checked on a Windows FF 2.0 server: VERIFIED says how for
each key (scripting/tests/ff_gamedata_test.sp, or tools/vtcheck.py where bots cannot
trigger the function). Linux values come straight from the symbols and have not been run
on a Linux server.

SourceMod's own sdktools.games/game.ff.txt and sdkhooks.games/game.ff.txt are for the
pre-2013 Fortress Forever 2.4 and are wrong for 2.0 (see the README). Files in custom/
are parsed after SourceMod's and survive SourceMod updates.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import elfvt  # noqa: E402

# key -> (class, "Method(args)") ; args exactly as c++filt prints them
SDKTOOLS = [
    ("GiveNamedItem",          "CFFPlayer",     "GiveNamedItem(char const*, int)"),
    ("RemovePlayerItem",       "CFFPlayer",     "RemovePlayerItem(CBaseCombatWeapon*)"),
    ("Weapon_GetSlot",         "CFFPlayer",     "Weapon_GetSlot(int) const"),
    ("Ignite",                 "CFFPlayer",     "Ignite(float, bool, float, bool)"),
    ("Extinguish",             "CFFPlayer",     "Extinguish()"),
    ("Teleport",               "CFFPlayer",     "Teleport(Vector const*, QAngle const*, Vector const*)"),
    ("CommitSuicide",          "CFFPlayer",     "CommitSuicide(bool, bool)"),
    ("GetVelocity",            "CFFPlayer",     "GetVelocity(Vector*, Vector*)"),
    ("EyeAngles",              "CFFPlayer",     "EyeAngles()"),
    ("AcceptInput",            "CBaseEntity",   "AcceptInput(char const*, CBaseEntity*, CBaseEntity*, variant_t, int)"),
    ("DispatchKeyValue",       "CBaseEntity",   "KeyValue(char const*, char const*)"),
    ("DispatchKeyValueFloat",  "CBaseEntity",   "KeyValue(char const*, float)"),
    ("DispatchKeyValueVector", "CBaseEntity",   "KeyValue(char const*, Vector const&)"),
    ("SetEntityModel",         "CBaseEntity",   "SetModel(char const*)"),
    ("WeaponEquip",            "CFFPlayer",     "Weapon_Equip(CBaseCombatWeapon*)"),
    ("Activate",               "CBaseEntity",   "Activate()"),
    ("PlayerRunCmd",           "CFFPlayer",     "PlayerRunCommand(CUserCmd*, IMoveHelper*)"),
    ("SetOwnerEntity",         "CBaseEntity",   "SetOwnerEntity(CBaseEntity*)"),
    ("GiveAmmo",               "CFFPlayer",     "GiveAmmo(int, int, bool)"),
]

SDKHOOKS = [
    ("OnTakeDamage",           "CFFPlayer",     "OnTakeDamage(CTakeDamageInfo const&)"),
    ("OnTakeDamage_Alive",     "CFFPlayer",     "OnTakeDamage_Alive(CTakeDamageInfo const&)"),
    ("TraceAttack",            "CFFPlayer",     "TraceAttack(CTakeDamageInfo const&, Vector const&, CGameTrace*, CDmgAccumulator*)"),
    ("Spawn",                  "CBaseEntity",   "Spawn()"),
    ("Think",                  "CBaseEntity",   "Think()"),
    ("PreThink",               "CFFPlayer",     "PreThink()"),
    ("PostThink",              "CFFPlayer",     "PostThink()"),
    ("SetTransmit",            "CBaseEntity",   "SetTransmit(CCheckTransmitInfo*, bool)"),
    ("ShouldCollide",          "CBaseEntity",   "ShouldCollide(int, int) const"),
    ("Use",                    "CBaseEntity",   "Use(CBaseEntity*, CBaseEntity*, USE_TYPE, float)"),
    ("StartTouch",             "CBaseEntity",   "StartTouch(CBaseEntity*)"),
    ("Touch",                  "CBaseEntity",   "Touch(CBaseEntity*)"),
    ("EndTouch",               "CBaseEntity",   "EndTouch(CBaseEntity*)"),
    ("Blocked",                "CBaseEntity",   "Blocked(CBaseEntity*)"),
    ("FireBullets",            "CFFPlayer",     "FireBullets(FireBulletsInfo_t const&)"),
    ("GetMaxHealth",           "CBaseEntity",   "GetMaxHealth() const"),
    ("VPhysicsUpdate",         "CBaseEntity",   "VPhysicsUpdate(IPhysicsObject*)"),
    ("GroundEntChanged",       "CFFPlayer",     "NetworkStateChanged_m_hGroundEntity(void*)"),
    ("Weapon_CanUse",          "CFFPlayer",     "Weapon_CanUse(CBaseCombatWeapon*)"),
    ("Weapon_Equip",           "CFFPlayer",     "Weapon_Equip(CBaseCombatWeapon*)"),
    ("Weapon_Drop",            "CFFPlayer",     "Weapon_Drop(CBaseCombatWeapon*, Vector const*, Vector const*)"),
    ("Weapon_Switch",          "CFFPlayer",     "Weapon_Switch(CBaseCombatWeapon*, int)"),
    ("Weapon_CanSwitchTo",     "CFFPlayer",     "Weapon_CanSwitchTo(CBaseCombatWeapon*)"),
    ("Reload",                 "CFFWeaponBase", "Reload()"),
]

# How each Windows offset was checked on a Windows FF 2.0 dedicated server (2.0.0.6):
#   "run"     scripting/tests/ff_gamedata_test.sp: the call had its effect / the hook fired
#   "vtable"  only tools/vtcheck.py: the slot splits the sampled entity classes the same way
#             FF's Linux symbols do (no way to trigger it with bots)
# Keys not listed were derived only.
VERIFIED = {
    "GiveNamedItem": "run", "RemovePlayerItem": "run", "Weapon_GetSlot": "run", "Ignite": "run",
    "Extinguish": "run", "Teleport": "run", "CommitSuicide": "run", "GetVelocity": "run",
    "EyeAngles": "run", "AcceptInput": "run", "DispatchKeyValue": "run", "DispatchKeyValueFloat": "run",
    "DispatchKeyValueVector": "run", "SetEntityModel": "run", "WeaponEquip": "run", "Activate": "vtable",
    "PlayerRunCmd": "run", "SetOwnerEntity": "run", "GiveAmmo": "run",
    "OnTakeDamage": "run", "OnTakeDamage_Alive": "run", "TraceAttack": "run", "Spawn": "run", "Think": "run",
    "PreThink": "run", "PostThink": "run", "SetTransmit": "vtable", "ShouldCollide": "run", "Use": "run",
    "StartTouch": "run", "Touch": "run", "EndTouch": "run", "FireBullets": "run", "GetMaxHealth": "run",
    "VPhysicsUpdate": "run", "GroundEntChanged": "run", "Weapon_CanUse": "run", "Weapon_Equip": "run",
    "Weapon_Drop": "run", "Weapon_Switch": "run", "Weapon_CanSwitchTo": "run", "Reload": "run",
}
NOTE = {"run": "", "vtable": "  (checked by vtcheck.py only)", None: "  (derived only, not checked on Windows)"}

HEADER = """/**
 * %s for Fortress Forever 2.0 (Source SDK 2013, game folder fortressforever).
 * Generated by SM-FortressForever-Tools tools/gen_gamedata.py from FF's Linux server.so
 * symbols. Windows offsets were exercised on a Windows FF 2.0 server (2.0.0.6) unless the
 * comment says otherwise; Linux offsets come from the symbols only and were not run.
 * In custom/ so SourceMod updates keep it; it overrides
 * SourceMod's game.ff.txt, which is for the pre-2013 Fortress Forever 2.4.
 */
"""


def resolve(elf, spec):
    out = []
    for key, cls, want in spec:
        names = elf.vtable(cls)
        win = elfvt.windows_slots(names)
        hits = [i for i, d in enumerate(names) if elfvt.method_of(d)[1] == want]
        if len(hits) != 1:
            sys.exit("%s: %d matches for %s::%s" % (key, len(hits), cls, want))
        i = hits[0]
        out.append((key, win[i], i, names[i]))
    return out


def write(path, what, rows, keys_extra=""):
    lines = [HEADER % what, '"Games"', "{", '\t"fortressforever"', "\t{", '\t\t"Offsets"', "\t\t{"]
    for key, w, l, name in rows:
        tag = NOTE[VERIFIED.get(key)]
        lines += ['\t\t\t/* %s%s */' % (name, tag), '\t\t\t"%s"' % key, "\t\t\t{",
                  '\t\t\t\t"windows"\t"%d"' % w, '\t\t\t\t"linux"\t\t"%d"' % l, "\t\t\t}"]
    lines.append("\t\t}")
    if keys_extra:
        lines.append(keys_extra)
    lines += ["\t}", "}", ""]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print("wrote", path)


def fireoutput_block(dll):
    import subprocess
    r = subprocess.run([sys.executable, "-I", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "find_fireoutput.py"), dll], capture_output=True, text=True)
    sig = r.stdout.strip().splitlines()[-1]
    t = "\t"
    lines = [t * 2 + '"Signatures"', t * 2 + "{",
             t * 3 + "/* CBaseEntityOutput::FireOutput (tools/find_fireoutput.py) */",
             t * 3 + '"FireOutput"', t * 3 + "{",
             t * 4 + '"library"' + t + '"server"',
             t * 4 + '"windows"' + t + '"%s"' % sig,
             t * 4 + '"linux"' + t * 2 + '"@_ZN17CBaseEntityOutput10FireOutputE9variant_tP11CBaseEntityS2_f"',
             t * 3 + "}", t * 2 + "}"]
    return "\n".join(lines)


def main():
    so, out = sys.argv[1], sys.argv[2]
    extra = fireoutput_block(sys.argv[3]) if len(sys.argv) > 3 else ""
    elf = elfvt.Elf(so)
    tools = resolve(elf, SDKTOOLS)
    hooks = resolve(elf, SDKHOOKS)
    for key, w, l, name in tools + hooks:
        print("%-24s windows %4d  linux %4d  %s" % (key, w, l, name))
    write(os.path.join(out, "sdktools.games", "custom", "common.games.txt"), "SDKTools offsets", tools, extra)
    write(os.path.join(out, "sdkhooks.games", "custom", "common.games.txt"), "SDKHooks offsets", hooks)


if __name__ == "__main__":
    main()
