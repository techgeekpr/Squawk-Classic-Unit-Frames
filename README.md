# Squawk ClassicUF

Classic 1.12 style unit frames for the **World of Warcraft: Forever** beta.

Made by **Avoid Me** of **&lt;Squawk&gt;**.

Forever runs Classic content on the Midnight (12.x) addon API, so the shipped
frames look like retail. This rebuilds them in the original style — player,
target, target of target, focus, pet, party and raid frames, cast bars, and a
Classic skin for Blizzard's action buttons.

Geometry is not estimated. Sizes, offsets and texture coordinates come from
Blizzard's own Classic `FrameXML`: the 232x100 frame, the 193x77 border drawn
from `UI-TargetingFrame` (mirrored for the player through flipped texture
coordinates), the 64x64 portrait at 24,-16, and the 119x12 bars at 90,-45 and
90,-56. Party frames follow `PartyMemberFrameTemplate` at 128x53, and the
target-of-target and pet frames use their real Classic art.

## Features

- **Unit frames** — player, target, target of target, focus and pet, with the
  Classic frame art, portraits, level circle, PvP faction banner and the
  elite / rare-elite / rare dragon around the target's portrait.
- **Party** — Classic 128x53 party frames, or the raid style if you prefer,
  optionally including yourself.
- **Raid** — up to 40 frames, arranged by raid group, with class colours,
  out-of-range fading, and indicators for buffs you can cast that are missing
  and debuffs you can dispel, both filtered to your own class.
- **Cast bars** — Quartz style by default: slim bar, one pixel border, icon
  outside on the left, spell name and countdown inside, a latency zone shaded
  at the end, and a red flash on interrupt. The Classic cast bar art is
  available as an alternative style.
- **Target auras** — the target's buffs and debuffs below (or above) the
  frame, independently placed, with dispel-type colouring, stack counts and
  the game's own tooltips on hover.
- **Action bars** — Blizzard's buttons restyled with the Classic border,
  textures and fonts. The buttons stay Blizzard's, so paging, keybinds,
  macros and drag-and-drop are untouched.
- Unit tooltips on every frame, and an options panel with five tabs.

## Installing

Copy the `SquawkClassicUF` folder into:

```
World of Warcraft\_classic_beta_\Interface\AddOns\
```

Then run `Setup-SavedVariables.ps1` — see below, it matters on this client.

## Settings do not persist without the shim

The Forever beta **writes SavedVariables correctly but never restores them**,
so every addon starts each session with an empty database. This addon works
around it: `SV1`, `SV2` and `SV3` inside the addon folder are directory
junctions pointing at your `WTF\Account\<id>\SavedVariables` folders, and the
TOC loads `SV*\SquawkClassicUF.lua` as ordinary addon files, which puts last
session's settings back before `Core.lua` runs. `Restore1-3.lua` park each
snapshot so the next one cannot clobber it.

`Setup-SavedVariables.ps1` creates those junctions. Run it once, from the
addon folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-SavedVariables.ps1
```

Junctions need no administrator rights. If the client's own restore stage ever
starts working, the shim becomes redundant rather than harmful — `/squawk diag`
reports which one is in use.

## Upgrading from ClassicUF

The addon used to be called ClassicUF. The TOC still reads the old saved file
once and adopts any profile that has no counterpart under the new name, so
nothing is lost: your frame positions, aura placement and cast bar sizes carry
over on the first login. It says so in chat when it happens.

## What this client allows, and what it does not

Three Midnight restrictions shape the whole addon, and they are worth knowing
if you plan to change anything:

**Health and power are secret values.** They cannot be compared, divided or
printed, but `StatusBar:SetValue` and `SetMinMaxValues` accept them directly,
which is how every bar here is driven. Text is different: health numbers
appear out of combat and quietly disappear during it. The bars stay accurate
throughout.

**Cast times are secret too.** The bar is filled by handing a Duration object
from `UnitCastingDuration` to `StatusBar:SetTimerDuration` and letting the
engine animate it. Channels drain from `GetRemainingDuration` when that is
readable. This client has no `Enum.StatusBarFillDirection`; it calls the
constant `Enum.StatusBarFillStyle.Reverse`, which the addon finds by searching
rather than hardcoding.

**Secure snippets do not compile**, which takes secure group headers with
them. Party and raid frames therefore use plain secure unit buttons on fixed
tokens (`party1..4`, `raid1..40`) with `RegisterUnitWatch`, which needs no
snippet. Targeting, menus and macros all keep working. The cost is that a
protected frame cannot be moved, shown or hidden during combat, so every
layout change queues until `PLAYER_REGEN_ENABLED`.

The same rule applies to range checking: `UnitInRange` returns *secret
booleans*, which cannot be tested at all. Fading uses `SetAlphaFromBoolean`,
which consumes the secret without the addon ever reading it.

## Commands

```
/squawk           open the options (also /cuf, /scuf, /classicuf)
/cuf unlock       show drag handles on every frame
/cuf lock         put them away
/cuf scale <n>    set every frame's scale at once (0.5 - 2)
/cuf art          check which Classic textures this client actually ships
/cuf bars         re-apply the action bar skin and report what it found
/cuf castdiag     cast bar diagnostics: APIs, art, and what each bar is doing
/cuf casttest     show both cast bars filled for five seconds
/cuf auradiag     whether this client lets addons read auras, and what it sees
/cuf reset        back to defaults
```

The diagnostics exist because this client is a moving target. If something
looks wrong, they will usually say why in one line.

## Files

| File | Contents |
| --- | --- |
| `Core.lua` | database, restore shim, secret-safe helpers, combat-safe queue, tooltips, art probing |
| `Units.lua` | player, target, target of target, focus and pet frames, target auras |
| `Group.lua` | party and raid frames, layout, movers, range fading |
| `Auras.lua` | guarded aura reading, missing buffs and dispels per class |
| `Cast.lua` | cast bars, Quartz and Classic styles |
| `ActionBars.lua` | Classic skin over Blizzard's action buttons |
| `Options.lua` | five-tab options panel |

## Credits

Written by Avoid Me of &lt;Squawk&gt;.


Geometry and art paths come from Blizzard's Classic `FrameXML`, read from the
[wow-ui-source](https://github.com/Gethe/wow-ui-source) mirror, which carries a
`forever` branch matching this client. The cast bar layout follows the look of
[Quartz](https://www.curseforge.com/wow/addons/quartz).
