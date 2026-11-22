# Fortress Forever Tools

SourceMod support for **Fortress Forever 2.0** (the Source SDK 2013 release, game folder
`fortressforever`, Windows x86 dedicated server).

This repository contains:

| Part | What it does |
|---|---|
| `gamedata/` | Correct SDKTools and SDKHooks offsets for FF 2.0. SourceMod's own FF gamedata is for the old Fortress Forever 2.4 and is wrong for 2.0 in almost every entry, so `AcceptEntityInput`, `TeleportEntity`, `GivePlayerItem`, `OnPlayerRunCmd`, every SDKHooks hook and more do nothing, do the wrong thing or crash on an FF 2.0 server. |
| `fortressforever.smx` (library `fortressforever`) | Natives and a forward for FF: classes, class limits, teams and alliances, armour, grenades, Spy disguise and cloak, buildings, respawn and refill. |
| `ff_teamcolors.smx` | Fixes Yellow players' names showing in **red** in chat (an FF client bug), for `say` and `say_team`. |
| `ff_targets.smx` | `@team` and `@class` targets for admin commands: `sm_slay @yellow`, `sm_freeze @engineers`, `sm_beacon @redsnipers`. |
| `ff_pipetint.smx` | Colours the Demoman's grenades and pipebombs in his team's colour (pipebombs a darker shade) instead of always blue and yellow. |
| `ff_jetpack.smx` | Pyro jetpack control: on/off, infinite fuel, recharge rate, spawn fuel, per-player admin overrides. Needs `fortressforever.smx`. |
| `ff_twotap.smx` | Two-tap grenades: old `toggleone`/`toggletwo`/`primeone`/`primetwo`/`throwgren` binds work again, `!twotap` makes `+gren1`/`+gren2` two-tap per player, and a chat helper. Needs this gamedata. |
| `ff_civilian_anywhere.smx` | Allows the Civilian on every map except Hunted, ff_training and maps you list. Needs `fortressforever.smx`. |

Everything is pure SourcePawn and text: no extra extensions. The plugins are compiled with
SourceMod 1.11's compiler, so they load on 1.11 and newer. It was tested on a LAN copy
of an FF 2.0 server (version 2.0.0.6) with SourceMod 1.11.0.6969 and bots.

## Install

1. **Gamedata.** Copy `gamedata/sdktools.games/custom/common.games.txt` and
   `gamedata/sdkhooks.games/custom/common.games.txt` into `addons/sourcemod/gamedata/`
   (keep the same sub-paths). Then **restart the server**: gamedata is only read when the
   server starts. Files in `custom/` are read after SourceMod's own, so they override
   `game.ff.txt` and survive SourceMod updates.
2. **Plugins.** Copy the plugins you want from `plugins/` to `addons/sourcemod/plugins/`.
   `ff_jetpack.smx` and `ff_civilian_anywhere.smx` need `fortressforever.smx`; `ff_twotap.smx`
   needs the gamedata (for `OnPlayerRunCmd`); the others need nothing else. Each writes its
   `cfg/sourcemod/<name>.cfg` on first load.
3. **Plugins that use the natives.** Compile them with `scripting/include/` from this
   repository on the include path and `#include <fortressforever>`.

`ff_teamcolors.smx` needs nothing else: no gamedata, no config. It writes
`cfg/sourcemod/ff_teamcolors.cfg` (`ff_teamcolors_enable 1`) on first load.

## Gamedata

### What was wrong

SourceMod matches its file `game.ff.txt` to FF 2.0 (it is labelled "Fortress Forever 2.4").
Those offsets come from the pre-2013 engine branch. FF 2.0's server is built from Source SDK
2013, whose vtables are longer, so the old numbers point at unrelated functions:

| Key | SourceMod (FF 2.4) | FF 2.0 Windows | | Key | SourceMod (FF 2.4) | FF 2.0 Windows |
|---|---|---|---|---|---|---|
| `GiveNamedItem` | 337 | **409** | | `OnTakeDamage` | 65 | **67** |
| `RemovePlayerItem` | 235 | **279** | | `OnTakeDamage_Alive` | – | **281** |
| `Weapon_GetSlot` | 233 | **277** | | `TraceAttack` | 63 | **65** |
| `Ignite` | 197 | **218** | | `Spawn` | 25 | **24** |
| `Extinguish` | 198 | **222** | | `Think` | 51 | **52** |
| `Teleport` | 105 | **115** | | `PreThink` / `PostThink` | 282 / 283 | **341 / 342** |
| `CommitSuicide` | 365 | **449** | | `SetTransmit` | 23 | **22** |
| `GetVelocity` | 135 | **149** | | `ShouldCollide` | 17 | **16** |
| `EyeAngles` | 127 | **140** | | `Use` | 94 | **104** |
| `AcceptInput` | 39 | **40** | | `StartTouch` / `Touch` / `EndTouch` | 95 / 96 / 97 | **105 / 106 / 107** |
| `DispatchKeyValue` | 35 | 35 (correct) | | `Blocked` | – | **109** |
| `DispatchKeyValueFloat` | 34 | 34 (correct) | | `FireBullets` | 108 | **119** |
| `DispatchKeyValueVector` | 33 | 33 (correct) | | `GetMaxHealth` | – | **124** |
| `SetEntityModel` | 28 | **27** | | `VPhysicsUpdate` | 151 | **166** |
| `WeaponEquip` | 226 | **270** | | `GroundEntChanged` | – | **186** |
| `Activate` | 36 | **37** | | `Weapon_CanUse` | 225 | **269** |
| `PlayerRunCmd` | 355 | **428** | | `Weapon_Equip` | 226 | **270** |
| `SetOwnerEntity` | – | **17** | | `Weapon_Drop` | 228 | **272** |
| `GiveAmmo` | – | **261** | | `Weapon_Switch` | 229 | **273** |
| `FireOutput` (signature) | does not match | **new signature** | | `Weapon_CanSwitchTo` | 231 | **275** |
| | | | | `Reload` | – | **280** |

"–" means SourceMod has no FF value, so the feature was unavailable. Only the three
`DispatchKeyValue*` offsets were right. Without the FireOutput signature SourceMod logs
"Entity Outputs are disabled" and `HookEntityOutput` fails.

The non-vtable values SourceMod takes from its SDK 2013 engine files (`EntityListeners`,
`sv`, `SetUserCvar`, `SetClientName`, the temp-entity offsets) were already right and are
not overridden. The file also contains Linux values (see below).

### How the offsets were made

FF ships its Linux `server.so` with symbols. The tools in `tools/` read it directly:

* **`elfvt.py`** dumps a class vtable with demangled names, using GNU binutils
  (`readelf`, `c++filt`). It derives the Windows slot from two MSVC rules:
  * MSVC has one destructor slot where GCC has two, so every later slot is one lower;
  * MSVC lays out overloads declared together in reverse order. This matters for
    `DispatchKeyValue*` (three `KeyValue` overloads), `SetEntityModel` (FF 2.0 added a
    `SetModel(const char*, int)` overload, so the one-argument version moved to 27),
    `CommitSuicide` and `GroundEntChanged`.
* **`gen_gamedata.py`** writes both gamedata files. Each key names the exact virtual
  (class, method and argument list), so a renamed or re-ordered function stops the
  generator instead of producing a wrong number. Each entry carries a comment saying how it
  was checked.
* **`find_fireoutput.py`** finds `CBaseEntityOutput::FireOutput` in the Windows
  `server.dll` (the only function that references the output debug string) and builds a
  unique signature with relocated bytes wildcarded.
* **`vtcheck.py`** checks the derived Windows slots against a running server, without
  symbols for the Windows binary: `scripting/tests/ff_vtdump.sp` prints the real vtable
  pointers of a player, three weapons, props, a team entity and others. For every slot,
  the Linux symbols say which of those classes share one implementation (for example
  `SetTransmit`: `CBaseCombatCharacter`'s for the player, `CBaseEntity`'s for the rest), and
  the Windows pointers must group them the same way. 282 informative slots match, 4 match
  weakly (MSVC merged identical functions), and 5 differ. All 5 only split `prop_dynamic`
  from `prop_physics_multiplayer` in the props' own virtuals (slots 230 to 265), which no
  key here uses on a prop.

```
python -I tools/gen_gamedata.py <fortressforever/bin/server.so> gamedata <fortressforever/bin/server.dll>
```

### What was verified

On the Windows server, with `scripting/tests/ff_gamedata_test.sp` (one step per command, so
a wrong offset would crash on a known call; nothing crashed):

* **SDKTools calls, each with its effect checked:** `AcceptEntityInput`, `TeleportEntity`,
  `GetClientEyeAngles` (matches `m_angEyeAngles`), `GetPlayerWeaponSlot` (matches
  `m_hMyWeapons`), `SetEntityModel`, `DispatchKeyValue`, `DispatchKeyValueFloat`,
  `DispatchKeyValueVector`, `RemovePlayerItem`, `GivePlayerItem`, `EquipPlayerWeapon`,
  `IgniteEntity` / `ExtinguishEntity` (`FL_ONFIRE` set and cleared), `GivePlayerAmmo`,
  `ForcePlayerSuicide`, `SetClientName` / `SetClientInfo`, `FindEntityByClassname`, and
  through SDKCall `GetVelocity` and `SetOwnerEntity`. `OnPlayerRunCmd` fires.
* **SDKHooks callbacks that fired:** `OnTakeDamage`, `OnTakeDamageAlive`, `TraceAttack`,
  `SpawnPost`, `Think`, `PreThink`, `PostThink`, `ShouldCollide`, `StartTouch`, `Touch`,
  `EndTouch`, `FireBulletsPost`, `GetMaxHealth`, `GroundEntChangedPost`, `WeaponCanUse`,
  `WeaponEquipPost`, `WeaponSwitchPost`, `WeaponCanSwitchTo`, `Reload`, `Use` and
  `VPhysicsUpdate` (a dropped physics prop);
  `SDKHooks_TakeDamage` and `SDKHooks_DropWeapon` work. `OnEntityCreated` /
  `OnEntityDestroyed` fire.
* **Checked only with `vtcheck.py`:** `SetTransmit` (it is only called for real clients, and
  the test server had bots only) and `Activate` (no visible effect to test).
* **Not checked on Windows:** `Blocked` (no door to block on the test map; `vtcheck.py` has
  nothing to compare because no sampled class overrides it). It sits two slots after the
  verified `EndTouch` in the same block of `CBaseEntity` virtuals.
* **Entity outputs:** with the new `FireOutput` signature SourceMod no longer logs
  "Sigscan for FireOutput failed", and a `HookSingleEntityOutput` callback on a
  `math_counter`'s `OutValue` fired.
* **Linux:** the Linux values come straight from the symbols. They were not run on a
  Linux server.

## fortressforever.smx

Include: `scripting/include/fortressforever.inc`. Classes use FF's numbers
(`FFClass_Scout` = 1 … `FFClass_Engineer` = 9, `FFClass_Civilian` = 10) and teams FF's
(`FFTeam_Blue` 2, `FFTeam_Red` 3, `FFTeam_Yellow` 4, `FFTeam_Green` 5).

| Native / forward | How |
|---|---|
| `FF_GetClass` | `m_iClassStatus` |
| `FF_SetClass(client, class, respawn = true)` | FF's own `ApplyToPlayer(player, {AT.kChangeClass…})`, the call map scripts use: changes the class at once, without killing; ignores class limits |
| `FF_RespawnPlayer` | `ApplyToPlayer(player, {AT.kRespawnPlayers})`: instant respawn, dead or alive |
| `FF_RegeneratePlayer` | FF's Lua `AddHealth` / `AddArmor` / `AddAmmo` (all ammo and both grenade types, clamped by FF to the class maximum) and `ReloadClips` |
| `FF_Get/SetArmor`, `FF_Get/SetMaxArmor` | `m_iArmor`, `m_iMaxArmor` |
| `FF_Get/SetGrenades(client, FFGrenade_Primary/Secondary)` | `m_iPrimary`, `m_iSecondary` |
| `FF_GetDisguise`, `FF_SetDisguise`, `FF_RemoveDisguise` | `m_iSpyDisguise`; FF's `SetDisguise(team, class, instant)` / `ResetDisguise`. FF applies a disguise on the Spy's next think, one tick later |
| `FF_IsCloaked` | `m_iCloaked` |
| `FF_GetBuilding(client, FFBuilding_…)` | `m_hDispenser`, `m_hSentryGun`, `m_hDetpack`, `m_hManCannon` |
| `FF_GetTeamEntity` | the team's `ff_team_manager` |
| `FF_GetClassLimit`, `FF_SetClassLimit` | `m_iClasses[class]`; setting goes through FF's `SetTeamClassLimit`, so the `cr_*` convars still apply |
| `FF_Get/SetTeamAllies`, `FF_AreTeamsAllied` | `m_iAllies` (bit `1 << team`) |
| `FF_IsTeamActive`, `FF_Get/SetTeamMaxPlayers` | `m_iMaxPlayers` (-1 = team not used on the map) |
| `FF_IsTeamFFA`, `FF_SetTeamFFA` | `m_bFFA` |
| `FF_RunLua(code)` | runs FF map Lua (FF's `lua_dostring` server command) |
| `FF_Get/SetJetpackFuel` | `m_iJetpackFuel` (0 to `FF_JETPACK_MAXFUEL` = 200) |
| `FF_IsJetpackAllowed`, `FF_SetJetpackAllowed`, `FF_IsJetpacking` | `m_bCanUseJetpack`, `m_bJetpacking` |
| `FF_OnPlayerClassChanged(client, old, new)` | FF's `player_changeclass` event |

The Lua-backed natives use FF's `lua_dostring` command followed by `ServerExecute()`, so
they finish before the native returns. The one exception is a native called from inside a
**server console or RCON command**: the command buffer is then already running, and the Lua
runs right after that command. Run such code on the next frame (`RequestFrame`); the plugin's
own admin commands do this.

Admin commands: `sm_ff_status` (team entities, limits, allies), `sm_ff_class <target>
<class> [respawn 0|1]`, `sm_ff_respawn <target>`, `sm_ff_regen <target>`.

**Self-test:** `scripting/tests/ff_tools_test.sp` (`sm_fftools_test`) passes **27 of 27**
checks on FF 2.0.0.6 with a bot: class get/set (with and without respawn), the class-changed
forward, respawn after death, armour, maximum armour, grenades, refill, disguise set/read/
remove, cloak, buildings, team entities, class limits, alliances, team activity, team player
limit, FFA, the Lua runner and the class name helpers. Team changes are restored afterwards.

## ff_teamcolors.smx: Yellow names in chat

### The bug

FF 2.0's client colours names with `GetCustomClientColor()` in
`game/client/ff/hud/ff_hud_chat.cpp`. With `hud_newteamcolors 1`, the default, Yellow gets
Red's colour (a copy-paste error, line 129):

```cpp
case TEAM_YELLOW:
{
    clr = hud_newteamcolors.GetBool() ? NEW_TEAM_COLOR_RED : TEAM_COLOR_YELLOW;
    break;
}
```

`hud_newteamcolors` is a client convar the server cannot change. Green is not affected: its
case returns `NEW_TEAM_COLOR_GREEN`.

### What the plugin does

FF sends each chat line as a `SayText2` user message, one per recipient, with the format
`FF_Chat_All` (`\x03%s1\x01 : %s2`) or `FF_Chat_Team` (`\x01(TEAM) \x03%s1\x01 : %s2`). `\x03`
means "the sender's team colour", which is the colour the client gets wrong. When the sender
is on Yellow, the plugin blocks each of these messages and sends the same message to the same
recipient one frame later, with `\x03` replaced by an explicit colour code: `\x07FFB200`
(FF's `NEW_TEAM_COLOR_YELLOW`, 255 178 0), or `\x07CAAD21` (FF's classic yellow) for players
who set `hud_newteamcolors 0` (the plugin asks each client for the convar).

FF still decides who gets each line: team chat goes to the team and its allies, ignore lists
and the map's Lua `player_onchat` still apply, and the text, `%`-commands and `^`-colour codes
are FF's own. The team prefix follows FF's two chat translations (English `(TEAM)`, Simplified
Chinese `(团队)`); FF has no other translated chat formats.

**Verified on the test server** with bots chatting through `say` and `say_team`
(`scripting/tests/ff_teamcolors_test.sp` logs every `SayText2` the server sends):

| Line | FF sent | Plugin sent |
|---|---|---|
| Yellow, `say`, alive | `FF_Chat_All` to all 22 players | `\x07FFB200%s1\x01 : %s2` to the same 22, once each |
| Yellow, `say_team`, alive | `FF_Chat_Team` to the 6 Yellow players | `\x01(TEAM) \x07FFB200%s1\x01 : %s2` to the same 6 |
| Yellow, `say` / `say_team`, dead | same as alive (FF has no dead prefix) | same as alive |
| Yellow, `say_team`, Yellow allied with Blue | `FF_Chat_Team` to the 11 Yellow and Blue players | the rewritten line to the same 11 |
| Green or Red, `say` / `say_team` | `FF_Chat_All` / `FF_Chat_Team` | nothing: passed through untouched |

The original messages were blocked (`sm_ff_teamcolors_stats` counts one blocked original per
rewritten message). Not verified: how the line looks in a real FF client (the test server had
no human player); the format follows FF's own client code (`hud_basechat.cpp`), which parses
`\x07RRGGBB` the same way as `\x03`. The `hud_newteamcolors 0` and Chinese paths were not run.

### What cannot be fixed from the server

The kill feed (`ff_hud_deathnotice.cpp`), the spectator panel (`SpectatorGUI.cpp`), the
voice-chat icons (`hud_voicestatus.cpp`) and the client-made join/name-change lines
(`clientmode_shared.cpp`) call the same `GetCustomClientColor()` with data the server does not
control, so they stay red for Yellow until the client is fixed. The fix for FF's developers is
one line in `game/client/ff/hud/ff_hud_chat.cpp`:

```diff
 case TEAM_YELLOW:
 {
-    clr = hud_newteamcolors.GetBool() ? NEW_TEAM_COLOR_RED : TEAM_COLOR_YELLOW;
+    clr = hud_newteamcolors.GetBool() ? NEW_TEAM_COLOR_YELLOW : TEAM_COLOR_YELLOW;
     break;
 }
```

With that fix in the client, the plugin's output looks the same as FF's own, so it can stay
installed.

## ff_targets.smx: team and class targets

Adds targets to every SourceMod command that takes a target (`sm_slay`, `sm_freeze`, `sm_burn`,
`sm_beacon`, `sm_ff_class`, ...). Dead players are included, as with SourceMod's own team targets;
commands that need living players filter them out themselves.

| Kind | Targets |
|---|---|
| Teams | `@blue` `@red` `@yellow` `@green` `@spectators` (`@spec`) |
| Classes | `@scouts` `@snipers` `@soldiers` `@demomen` `@medics` `@hwguys` `@pyros` `@spies` `@engineers` `@civilians`, each also singular (`@scout`, `@demoman`, ...) |
| Aliases | `@demo(s)`, `@heavy` / `@heavies` / `@hw`, `@engi(s)` / `@engy`, `@civ(s)` |
| Team and class | `@<team><class plural>`: `@bluemedics`, `@greenhwguys`, `@yellowcivilians`, ... (40) |

`sm_ff_targets` lists them. **Verified** on the test server (`sm_fft_targets` in
`scripting/tests/ff_plugins_test.sp`): every target's player count matched a direct count of
team and class, on ff_2fort and on the four-team ff_flag4sky (75 of 75 both times).

## ff_pipetint.smx: Demoman projectiles in team colours

FF's grenades and pipebombs share `models/projectiles/pipe/w_pipe.mdl`, which has a blue skin and
two skins with a yellow, pulsing texture. FF gives every grenade the blue skin and every pipebomb a
yellow one, whatever the team. The plugin gives each projectile the skin whose texture can be
tinted to the thrower's team (blue for Blue, yellow for the others: a tint can only filter a
texture's colours, never add one) and sets its render colour. Pipebombs get a darker shade.

| Team | Grenade (`ff_pipetint_<team>_grenade`) | Pipebomb (`ff_pipetint_<team>_pipe`) |
|---|---|---|
| Blue | blue skin, `255 255 255` | blue skin, `140 160 255` |
| Red | yellow skin, `255 70 50` | yellow skin, `190 30 20` |
| Yellow | yellow skin, `255 255 255` | yellow skin, `200 170 90` |
| Green | yellow skin, `110 255 80` | yellow skin, `60 190 40` |

`ff_pipetint_enable 0` turns it off. **Verified** on the test server: every grenade of each of the
four teams and a Yellow pipebomb got the skin and colour above. **Not verified:** how the colours
look in a game client. **Client quirk:** FF's client draws pipebombs with the yellow skin for about
half of all players, whatever the server says (`C_FFProjectilePipebomb::DrawModel`, keyed to the
viewer's Steam account ID). Those players see Blue's pipebombs as a darkened yellow instead of dark
blue; the other teams look the same for everyone.

## ff_jetpack.smx: Pyro jetpack control

| Convar | Default | |
|---|---|---|
| `ff_jetpack_enable` | 1 | 0 = no Pyro can use the jetpack |
| `ff_jetpack_infinite` | 0 | fuel never runs out |
| `ff_jetpack_recharge_scale` | 1.0 | FF's recharge rate (about 24 fuel per second) times this; 0 = no recharge |
| `ff_jetpack_spawn_fuel` | 100 | fuel (percent) a Pyro spawns with |

Admin commands: `sm_ff_jetpack <target> <1|0|reset>` (allow, forbid, or back to the convar) and
`sm_ff_jetpack_fuel <target> <0-100>`. The jetpack is predicted by the client, so a changed
recharge rate shows on the player's fuel meter with the next network update. **Verified** on the
test server with a Pyro bot: enable/disable, the per-player override and reset, infinite fuel,
recharge scale 0 / 1 / 3 (fuel 20 after one second: 19 / 44 / 94), spawn fuel.

## ff_twotap.smx: two-tap grenades

FF 2.0 has two grenade binds: `+gren1` / `+gren2` (hold to prime, release to throw) and
`+togglegren1` / `+togglegren2` (tap to prime, tap again to throw). Older FF and TFC configs use
the server commands `toggleone`, `toggletwo`, `primeone`, `primetwo` and `throwgren`, which FF 2.0
no longer has, so those binds do nothing. This plugin:

* adds those five commands back; each presses FF's two-tap grenade button for a short tap;
* **`!twotap`** (`sm_twotap [1|0]`): makes the player's `+gren1` / `+gren2` keys two-tap, saved with
  clientprefs when it is loaded;
* answers chat questions about two-tap grenades (it replaces the older
  `ff_twotap_grenade_reminder` plugin; unload that one).

| Convar | Default | |
|---|---|---|
| `ff_twotap_commands` | 1 | accept the five old commands |
| `ff_twotap_mode` | 1 | allow `!twotap` |
| `ff_twotap_mode_default` | 0 | `!twotap` state for players who never chose |
| `ff_twotap_help` | 1 | chat answer: 0 off, 1 to the asker, 2 to everyone |
| `ff_twotap_help_cooldown` | 60 | seconds per player |
| `ff_twotap_help_text` | | the answer |

It changes the buttons of the player's user commands in `OnPlayerRunCmd`, which only runs with this
repository's gamedata (or another `PlayerRunCmd` 428 override). **Verified** on the test server
with a bot whose AI was paused (the NextBot plugin rewrites its bots' buttons after SourceMod, so
an AI-driven bot cannot be used): `primeone`, `throwgren`, `toggleone` twice, `primetwo`,
`throwgren` and `toggletwo` twice each left the grenade state FF should have; with `!twotap` on, a
tap of `+gren1` primed, the grenade stayed primed after the release, and the next tap threw it.
**Not verified with a real client:** the player's own client predicts grenades from the keys he
presses, so with `!twotap` on it predicts a throw on release that the server does not do, and the
HUD grenade timer may blink until the server's state reaches him.

## ff_civilian_anywhere.smx: Civilian on every map

Every 2 seconds, sets the Civilian limit of each active team whose map disables the Civilian (-1)
to `sm_civanywhere_limit` (default 0 = unlimited), through FF's own `SetTeamClassLimit`, so map
scripts stay stock. `sm_civanywhere_exclude` (default `ff_hunted*,hunted*,ff_training`, trailing
`*` = prefix) keeps the map's own rule; `sm_civanywhere_enabled 0` turns it off. The convars are
those of the stand-alone 1.0.0 version from fortressforever-nextbot, so its config keeps working.
**Verified:** the Civilian limit became 0 for both teams on ff_2fort and for all four on
ff_flag4sky.

## Known gaps

* **`ff_dm2` with many bots can crash the server** with `ED_Alloc: no free edicts`. This is
  not caused by anything here: it happened on the test server without these files too (and
  days before they existed). The map's 79 `point_spotlight`s re-create their `beam` entities
  hundreds of times a second, and when that peaks the engine runs out of edicts it may reuse.
  Testing was finished on `ff_2fort`.
* `Blocked` was derived only (see above).
* Linux offsets are untested.
* `ff_teamcolors.smx` delays a Yellow player's chat line by one server frame (15 ms).

## Requirements

* Fortress Forever 2.0 dedicated server (tested on 2.0.0.6, Windows)
* SourceMod 1.11 or newer (tested on 1.11.0.6969) with SDK Tools; SDK Hooks for plugins that
  use hooks
* Python 3 and GNU binutils, only to regenerate the gamedata

## License

GPL-3.0. The gamedata derives from SourceMod's gamedata format (GPL-3.0). FF's source is
quoted only to explain the client bug.
