#!/usr/bin/env python3
"""Check the derived Windows vtable slots against a running Windows server.

  python -I vtcheck.py <server.so> <console.log> [key ...]

<console.log> must contain the output of `sm_ffgd_vtables` (scripting/tests/ff_gamedata_test.sp),
which prints the real vtable function pointers of a player, three weapons, a prop_dynamic,
an info_target, a math_counter, ff_team_manager, the game rules proxy, a physics prop and
worldspawn.

For each Linux slot, server.so says which of those entities share one implementation
(for example SetTransmit: CBaseCombatCharacter's for the player, CBaseEntity's for the
others). The Windows slot derived by elfvt.windows_slots() must split the entities the same
way. A split that differs means the slot is wrong. When Windows merges two groups that Linux
keeps apart, MSVC's identical-code folding is the likely reason, so that counts as a weak
match. Slots where every entity shares one implementation say nothing and are skipped.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import elfvt  # noqa: E402
import gen_gamedata  # noqa: E402

LINUX_CLASS = {
    "player": "CFFPlayer", "ff_weapon_shotgun": "CFFWeaponShotgun", "ff_weapon_crowbar": "CFFWeaponCrowbar",
    "ff_weapon_rpg": "CFFWeaponRPG", "prop_dynamic": "CDynamicProp", "info_target": "CPointEntity",
    "math_counter": "CMathCounter", "ff_team_manager": "CFFTeam", "ff_gamerules": "CFFGameRulesProxy",
    "prop_physics_multiplayer": "CPhysicsPropMultiplayer", "worldspawn": "CWorld",
}


def parse_log(path):
    vt = {}
    for line in open(path, errors="replace"):
        m = re.match(r".*?VT (\S+) \d+ (.*)$", line.rstrip())
        if not m:
            continue
        d = vt.setdefault(m.group(1), {})
        for s, a in re.findall(r"(\d+):([0-9a-f]{8})", m.group(2)):
            d[int(s)] = a
    return vt


def module_filter(vt):
    """Drop pointers outside server.dll: SourceHook (SDKHooks/DHooks) replaces hooked slots
    with its own thunks, so a hooked slot says nothing about the original layout."""
    allp = sorted(int(a, 16) for d in vt.values() for a in d.values())
    mid = allp[len(allp) // 2]
    for d in vt.values():
        for s in [s for s, a in d.items() if abs(int(a, 16) - mid) > 0x1000000]:
            del d[s]


def partition(pairs):
    groups = {}
    for ent, key in pairs:
        groups.setdefault(key, set()).add(ent)
    return sorted(sorted(g) for g in groups.values())


def compare(lin_part, win_part):
    if lin_part == win_part:
        return "match"
    # every Windows group must be a union of Linux groups
    for wg in win_part:
        if not all(set(lg) <= set(wg) or not (set(lg) & set(wg)) for lg in lin_part):
            return "MISMATCH"
    return "weak (Windows merges groups)"


def main():
    so, log = sys.argv[1], sys.argv[2]
    only = set(sys.argv[3:])
    elf = elfvt.Elf(so)
    vt = parse_log(log)
    if not vt:
        sys.exit("no VT lines in " + log)
    module_filter(vt)
    tables = {e: elf.vtable(c) for e, c in LINUX_CLASS.items() if e in vt}
    wins = {e: elfvt.windows_slots(n) for e, n in tables.items()}

    # whole-table alignment over every informative slot of the player vtable
    stats = {"match": 0, "weak (Windows merges groups)": 0, "MISMATCH": 0}
    bad = []
    for ls in range(2, len(tables["player"])):
        ents = [e for e in tables if ls < len(tables[e]) and wins[e].get(ls) in vt[e]]
        lin = partition((e, tables[e][ls]) for e in ents)
        if len(lin) < 2:
            continue
        win = partition((e, vt[e][wins[e][ls]]) for e in ents)
        r = compare(lin, win)
        stats[r] += 1
        if r == "MISMATCH":
            bad.append((ls, lin, win))
    print("slots 2..%d of the sampled vtables, informative slots: %s" % (len(tables["player"]) - 1, stats))
    for ls, lin, win in bad[:40]:
        print("  mismatch at linux slot %d: linux groups %s, windows groups %s" % (ls, lin, win))

    print()
    for key, cls, want in gen_gamedata.SDKTOOLS + gen_gamedata.SDKHOOKS:
        if only and key not in only:
            continue
        names = elf.vtable(cls)
        ls = [i for i, d in enumerate(names) if elfvt.method_of(d)[1] == want][0]
        ents = [e for e in tables if ls < len(tables[e]) and wins[e].get(ls) in vt[e]]
        lin = partition((e, tables[e][ls]) for e in ents)
        if len(lin) < 2:
            print("%-24s linux %3d windows %3d  uninformative (one implementation for all %d entities)" % (key, ls, wins["player"][ls], len(ents)))
            continue
        win = partition((e, vt[e][wins[e][ls]]) for e in ents)
        print("%-24s linux %3d windows %3d  %s  (%d implementations)" % (key, ls, wins["player"][ls], compare(lin, win), len(lin)))


if __name__ == "__main__":
    main()
