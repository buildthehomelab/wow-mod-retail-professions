# Retail Professions

An [AzerothCore](https://www.azerothcore.org/) (WotLK 3.3.5a) module and addon that replace the
old trade skill window with a **retail-style profession window**, in the spirit of WoW Forever's:
one clear window with search, filters and skill-up odds, recipes you haven't learned yet and
where to get them, a recipe tracker and a professions book on **K**.

Crafting itself doesn't change. Every craft is the client's own `DoTradeSkill`, so skill-ups,
cooldowns, discoveries and other modules' hooks behave as before.

## What players get

**The profession window**
- **Profession tabs** down the left edge: switch between your professions without the spellbook.
- **Skill bar** with your rank (Apprentice ... Grand Master), and a **chat link** button that
  shows everyone your recipes.
- **Search** that matches recipe names and **reagents** ("silk" finds everything made from silk).
- **Filters**: Have materials, Has skill-up, Slot (head, chest, weapon ...), Show unlearned
  recipes, Only ones I can learn now, Count the reagent bank, plus expand / collapse all.
- Each recipe has a **skill-up meter**: three bars for a sure skill-up (orange), two for likely
  (yellow), one for unlikely (green), none for no skill-up (grey). The count on the right is how
  many you can make, with what the reagent bank adds in blue.
- **Unlearned recipes**, greyed, grouped by skill tier (Journeyman, Expert ...) with the skill
  they need.

**The recipe**
- What it makes, how many, tools and cooldown.
- **Chance to raise your skill**, exactly as the server works it out, and a bar showing where the
  recipe turns yellow, green and grey and where you are on it. With `SkillGain.Crafting` above 1
  it says how many points a skill-up gives.
- **Reagents** with what you have (green / red), plus what's in the reagent bank.
- **Create**, **Create All** and an amount box. For enchants, an **Enchant** slot: drop the item
  on it once and every cast goes straight onto that item, no clicking the item each time.
- For a recipe you haven't learned: **where to learn it**. Trainers (nearest first, with the
  cost), vendors (price, limited stock, reputation needed), drops (creature, zone, level,
  chance), world drops (how many creatures, level range), chests, containers, quests and
  discoveries. **Map** puts a flag on the trainer or vendor.

**Tracking**
- Right-click a recipe (or tick **Track recipe**) to put it on a list on your screen, like a
  tracked quest. It shows every reagent you still need for the number of crafts you want (right-
  click it: make 1, 2, 3, 5, 10, 20), turns green when you have it all and counts the reagent
  bank. Click a tracked recipe to show it in the window. Drag the title to move the list.

**Professions book (K)**
- Every profession and secondary skill with its rank and skill bar, an **Open** button, the
  gathering action where there is one (Find Herbs, Find Minerals, Smelting, Fishing) and
  **Unlearn**. The addon binds **K** the first time, if K is free; otherwise set it under
  Key Bindings > Retail Professions. `/prof` also opens it.

**Other**
- `/prof classic` switches back to the old Blizzard window, `/prof retail` returns.
- `/prof reset` puts the windows back where they started.
- With [DragonUI](https://github.com/NeticSoul/DragonUI) the window wears DragonUI's retail
  art; without it, a dark style of its own.
- With [mod-reagent-bank-account](https://github.com/buildthehomelab/mod-reagent-bank-account)'s
  ReagentBankUI, its sidebar docks to this window as it does to the old one.

## Individual progression

With [mod-individual-progression](https://github.com/ZhengPeiRu21/mod-individual-progression):
- Unlearned recipes are listed up to skill **300** before Outland opens for the player and
  **375** before Northrend, by skill tier and never by profession.
- Trainers, vendors and drops on a continent (or in a dungeon of an expansion) the player hasn't
  reached are left out.

## How it works

The addon reads learned recipes from the client, as the old window does. The module adds what the
client can't know. At startup it indexes every recipe of every profession from
`SkillLineAbility.dbc`, with:
- its skill thresholds;
- trainers (`trainer_spell`);
- recipe items and who sells them, quest rewards and loot tables (with references, collapsing
  shared world-drop tables);
- `skill_discovery_template`;
- and the zones of the spawns involved.

The addon asks through addon whispers to itself (prefix `RPR`, like
[mod-retail-ah](https://github.com/buildthehomelab/wow-mod-retail-ah)'s `RAH`). It caches a
profession's list per data version, so the list travels once.

Without the module the window still works, minus unlearned recipes, exact odds and sources.

## Install

Server:
```
cd azerothcore-wotlk/modules
git clone https://github.com/buildthehomelab/wow-mod-retail-professions.git mod-retail-professions
```
Re-run CMake, rebuild, and copy `conf/mod_retail_professions.conf.dist` next to your
`worldserver.conf`. There's no SQL to import.

Client: copy `addon/RetailProfessions` into `Interface/AddOns`. On realms using Portalkeeper,
`sql/portalkeeper_addon.sql` (run by hand against `acore_world`) makes it a required addon.

The first start works out zones for the trainers, vendors and drops it needs and, with
`RetailProfessions.SaveZoneData = 1`, saves them to `creature`/`gameobject`, so later starts are
quicker.

## Configuration

See `conf/mod_retail_professions.conf.dist`: master switch, the era skill cap, hiding locked
continents, how many sources per kind, the world-drop threshold and saving zones.

## Development

`lua tools/addon_smoke_test.lua addon/RetailProfessions` loads the addon against a stubbed
3.3.5a API and a fake server and walks through opening a profession, filters, crafting, where to
learn a recipe, tracking, the book, combat and the classic switch.

## License

MIT
