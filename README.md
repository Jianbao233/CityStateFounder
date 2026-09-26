# City-State Founder

A mod for **Sid Meier's Civilization VI** that lets the player found a real City-State anywhere on the map.

[中文说明 →](README.zh-CN.md)

---

## What it does

Adds one new unit, the **City-State Envoy**. It cannot found a normal city — instead it founds a
**City-State** on the tile it stands on.

The City-State it creates is a genuine engine City-State: normal colours, name, envoys, suzerain
bonus and quests. It is independent — the AI controls it, it does not belong to you.

## How to use

1. Build a **City-State Envoy** (150 production, civilian, land unit).
2. Move it to the tile where you want the City-State to appear.
3. Open the unit panel and click **Found City-State**.
4. A panel lists every City-State available in this game — icon, name and suzerain bonus.
5. Pick one and confirm. That City-State's Settler moves in and founds its city on its own turn.

You gain **1 Envoy** with the new City-State as its founder.

## How many can I found?

The list only shows City-States that **exist in your current game**, because only those can be
created with full mechanics. That count is set by your game setup:

| Map size | City-States |
|---|---|
| Duel | up to 6 |
| Tiny | up to 10 |
| Small | up to 14 |
| Standard | up to 18 |
| Large | up to 22 |
| Huge | up to 24 |

Want more choices? Raise the City-State count when you create the game.

## Requirements

- **Rise and Fall** or **Gathering Storm** (the mod loads under the Expansion 2 ruleset).
- Single player. Not tested in multiplayer.

## Install

Copy the `src/` folder into your Civ6 mods directory and rename it to `CityStateFounder`:

```
Documents\My Games\Sid Meier's Civilization VI\Mods\CityStateFounder\
```

The folder must contain `CityStateFounder.modinfo` at its top level.

## Repository layout

```
src/                  the mod itself (this is what gets uploaded to the Workshop)
  CityStateFounder.modinfo
  Data/               unit definition + map size tweaks
  Lua/                gameplay logic
  UI/                 the founding panel + unit panel button
  Text/               localisation (English / Simplified Chinese)
tools/audit_csf.py    static checker: modinfo refs, XML validity, LOC key usage, Lua scoping
```

## Design notes

A few things worth knowing if you want to modify this mod:

- **City-States are reserved at game start.** On `LoadScreenClose` every City-State that has not
  founded yet is sent off-map, so the player can place them later. That is why the available count
  equals the game's City-State count.
- **Founding does not call `Cities:Create`.** It places that City-State's Settler on the target tile
  and lets the City-State's own AI found the city on its turn. Creating a city directly with
  `Cities:Create` can fail silently and permanently damage the target City-State, so this mod avoids
  it entirely.
- **Creating brand-new City-State players at runtime is not supported.** `WorldBuilder.PlayerManager():AddPlayer`
  produces players the engine's UI layer does not fully know about (no banner colour, broken
  diplomatic state). This was tested extensively and rejected — see the source comments.

## Credits

- Author: **Jianbao**
- The panel reuses Firaxis' own UI styles and textures (`EnhancedToolTip`, `Religion_Panel`,
  `Religion_BeliefButton`, `Controls_HeaderMetal`, …); no third-party assets are included.

## License

MIT — see [LICENSE](LICENSE).
