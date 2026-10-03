# Retail Professions

An [AzerothCore](https://www.azerothcore.org/) (WotLK 3.3.5a) module and addon that replace the
old trade skill window with a **retail-style profession window**, in the spirit of WoW Forever's:
one clear window with search, filters and skill-up odds, recipes you haven't learned yet and
where to get them, a recipe tracker and a professions book on **K**.

Crafting itself doesn't change. Every craft is the client's own `DoTradeSkill`, so skill-ups,
cooldowns, discoveries and other modules' hooks behave as before.

## What players get

**The profession window**
- **Profession tabs** down the right edge, like the spellbook: switch between your professions without the spellbook.
- The profession's **portrait**, a **skill bar** across the window ("Blacksmithing 24/75"; hover it
  for your rank) and a **chat link** button that shows everyone your recipes.
- **Search** (the box at the top of the list) matches recipe names and **reagents** ("silk" finds
  everything made from silk).
- **Filters**: Have materials, Has skill-up, Slot (head, chest, weapon ...), Show unlearned
  recipes, Only ones I can learn now, Count the reagent bank, plus expand / collapse all.
- Recipes sit under gold category bars that fold. Each has a **skill-up chevron** in its colour
  (orange = sure, yellow = likely, green = unlikely, none = no more skill-ups) and how many you
  can make in brackets, with what the reagent bank adds in blue: `Copper Bracers [3+2]`.
- **Favorites**: the star beside a recipe's name puts it in a Favorites group at the top.
- **Unlearned recipes**, greyed, grouped by skill tier (Journeyman, Expert ...) with the skill
  they need.

**The recipe**
- A round icon, the name, a favorite star and what it **requires** (tools, a forge, a fire; red
  when you don't have it), what it makes and any cooldown.
- Hover a recipe (in the list, or its icon) for the **chance to raise your skill**, exactly as the
  server works it out, and the skill where it turns yellow, green and grey. With
  `SkillGain.Crafting` above 1 it says how many points a skill-up gives.
- **Reagents** as `have/need Name` (red when short), plus what's in the reagent bank.
- **Track Recipe**, and under the recipe **Create All [n]**, the amount and **Create**. For
  enchants, an **Enchant** slot: drop the item on it once and every cast goes straight onto that
  item, no clicking the item each time. **Shift-click** Enchant to also skip the "replace the
  enchant?" and "binds it to you" questions for that cast (handy for enchanting skill-ups).
- **Use reagent bank** (with ReagentBankUI, on by default): Create and Create All count the bank
  and take whatever your bags are missing out of it before crafting, through ReagentBankUI's
  Withdraw Needed (so its *Auto-deposit leftovers* puts the rest back when you close the window).
  If the game insists on a click to start the craft once the reagents have arrived, it says so.
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
- The windows are stock Blizzard frames (dialog frame, buttons, checkboxes, scroll bars). With
  [DragonUI](https://github.com/NeticSoul/DragonUI) installed they wear DragonUI's retail skin:
  the metal frame with the round portrait, red buttons and gold category bars.
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
