# Retail Professions

An [AzerothCore](https://www.azerothcore.org/) (WotLK 3.3.5a) module and addon that replace the
old trade skill window with a **retail-style profession window**, in the spirit of WoW Forever's:
one clear window with search, filters and skill-up odds, recipes you haven't learned yet and
where to get them, a recipe tracker and a professions book on **K**.

Crafting itself doesn't change. Every craft is the client's own `DoTradeSkill`, so skill-ups,
cooldowns, discoveries and other modules' hooks behave as before. The server adds two things
of its own: **Milling and Prospecting** from the window, which the client can only do one stack
and one loot window at a time, and retail's crafting stats, **Multicraft, Resourcefulness and
crafting speed**, earned by skill.

## What players get

**The profession window**
- **Profession tabs** down the right edge, like the spellbook: switch between your professions without the spellbook. With ArchaeologyUI loaded, Archaeology has one too; it opens the research window in place of this one.
- The profession's **portrait**, a **skill bar** across the window ("Blacksmithing 24/75"; hover it
  for your rank) and a **chat link** button that shows everyone your recipes.
- **Search** (the box at the top of the list) matches recipe names and **reagents** ("silk" finds
  everything made from silk); recipes found by name come first, then the ones that use it. Hover
  the box for a reminder.
- **Filters**: Have materials, Has skill-up, Slot (head, chest, weapon ...; for enchants, the
  slot they go on), Show unlearned recipes, Only ones I can learn now, Count the reagent bank, plus expand / collapse all.
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
- Hold **Shift** over a recipe, its icon or a tracked recipe to compare what it makes with what
  you have equipped, as with any other item.
- **Reagents** as `have/need Name` (red when short), plus what's in the reagent bank.
- **Track Recipe**, and under the recipe **Create All [n]**, the amount and **Create**. For
  enchants, an **Enchant** slot: drop the item on it once and every cast goes straight onto that
  item, no clicking the item each time. **Shift-click** Enchant to also skip the "replace the
  enchant?" and "binds it to you" questions for that cast (handy for enchanting skill-ups).
- **Use reagent bank** (with ReagentBankUI, on by default): Create and Create All count the bank
  and take whatever your bags are missing out of it before crafting, through ReagentBankUI's
  Withdraw Needed. If the game insists on a click to start the craft once the reagents have
  arrived, it says so.
- **Deposit leftovers** (with ReagentBankUI): when you close the window, reagents that came out
  of the bank for a craft and weren't used go back into it. What was in your bags before stays.
- **Add to Shopping List** (with ReagentBankUI): set the amount you want to make, and when your
  bags and reagent bank together fall short the recipe says so ("Short for 18  46 Bolt of Woolen
  Cloth - about 5g 94s", priced from the auction house when
  [mod-retail-ah](https://github.com/buildthehomelab/wow-mod-retail-ah) is there) with a button
  that puts the shortfall on your shopping list. Only what isn't on the list yet is added, so
  asking twice doesn't double it (Shift-click adds it all on top, for a second recipe that needs
  the same reagent). RetailAH's Buy tab opens on that list and counts it down as you buy.
  Recipes you haven't learned yet have the amount and the button too, so the materials can be
  bought before the recipe.
- For a recipe you haven't learned: **where to learn it**, written like a guide. Hover a line
  for the details.
  - Trainers, nearest first, with the cost and the skill they teach it at. Death knights' runes
    come from their class trainer.
  - People and objects that teach it through a script (Henry Stern's tea, Knot Thimblejack's
    ogre suit, the teleporter engineers, the books in Blackrock Depths, Gloom'rel's Smelt Dark
    Iron) with what the option asks for: skill, specialization, an item, a quest done first.
  - Vendors: the price in gold or in tokens ("3 Dalaran Cooking Award", badges, honor), limited
    stock, the reputation needed, and the holiday for vendors that only come with one (Winter
    Veil, the Darkmoon Faire).
  - Drops: creature, zone or dungeon, level, chance (a loot group's share when the row has no
    chance of its own), rare spawns and bosses marked. Pickpocketing and skinning too.
  - World drops say where they really drop: "from trash in Black Temple", or the continents.
  - Bags, crates and lockboxes say where they come from: the quest that rewards them (a daily
    or not, and where), the vendor, the creatures, the fishing spot, the mail, or that it's
    locked.
  - Quests show their giver and where they stand (profession quests have no zone of their own),
    the level, the skill they ask for, the quest before them and whether they repeat.
  - Discoveries, and a last line for sources on a continent your progression hasn't opened.
  - The recipe item shows its lowest buyout when RetailAH is on the realm.
  - **Map** puts a flag on a trainer, vendor, teacher, dropping creature, object or quest giver.

**Milling and Prospecting**
- A **Milling** tab (scribes) and a **Prospecting** tab (jewelcrafters) under the profession
  tabs. The professions book has a button for each too.
- Every herb or ore is a row, like a recipe: the ones you have enough of on top with how many
  times you can do it (`Peacebloom [4+2]`, the reagent bank's in blue), the rest greyed below,
  with the skill they need in red when yours is too low.
- The pane shows what five of it give: every pigment or gem with how many and how likely, as the
  server's loot tables have it. Search finds herbs and ore by what they give ("golden pigment").
- **Mill All [n]** / **Prospect All [n]**, or an amount and **Mill** / **Prospect**. The server
  works through your bags at the spell's own cast time and puts the results straight into your
  bags: no clicking a stack, no loot window. Five can come from more than one stack.
- **Stop** ends it. So does moving, combat, casting something else, opening a trade or closing
  the window, like a cast being interrupted. What doesn't fit in your bags is mailed to you.
- **Use reagent bank** works here too: herbs and ore come out of the bank first.
- Same rules as the spells: you need to know Milling or Prospecting and have the skill the herb
  or ore asks for. `SkillChance.Milling` / `SkillChance.Prospecting` skill-ups still apply. The
  spells in the spellbook work as before.

**Multicraft, Resourcefulness and crafting speed**
- Retail's crafting stats, earned by skill instead of gear. A recipe gets nothing while it's
  orange, more from where it turns yellow to where it turns grey, and the most from then on: a
  recipe that still teaches you is slow and single, one you've outgrown is quick to make in bulk.
  - **Multicraft**: a chance that a craft makes a second batch (up to 25%). Only for things that
    stack: bars, bolts, leather, inks, bandages, food, scopes and powders. Not gear, and not cut
    gems (they don't stack).
  - **Resourcefulness**: a chance (up to 20%) to get 30% of the reagents back. A fraction of a
    unit is a roll, so it is 30% on average, and a proc on a recipe that uses one of each can
    give nothing.
  - **Cast**: up to 50% shorter, so a Create All of a grey recipe takes half the time.
- The recipe shows its numbers at your skill ("Multicraft 18%   Resourcefulness 14%   Cast 1.6
  sec"; hover for what they mean), its tooltip too, and the window says when one procs.
- Each proc also shows as scrolling text: in [MikScrollingBattleText](https://www.curseforge.com/wow/addons/mik-scrolling-battle-text)'s
  Notification area when MSBT is loaded, otherwise in the game's floating combat text when
  that's on.
- **Craft procs log** (the note button beside the chat link, or `/prof log`): every Multicraft
  and Resourcefulness with the recipe, the items and what they're worth at auction-house prices,
  plus how often each comes up (procs per craft) for this session and all time on the character.
  Every craft started from a profession window counts, Create All included; the rate only
  counts procs from those crafts. A proc's worth is priced when it happens, so procs before the
  addon has auction prices count as unpriced. A checkbox there turns the scrolling text off.
- Extras that don't fit in your bags are mailed.
- Three kinds of recipe only get the speed:
  - the ones the core already rolls extra items for through an alchemy mastery: most potions,
    elixirs, flasks and transmutes (`skill_extra_item_template`). Their own proc stands in,
    and that holds for an alchemist without the mastery too;
  - recipes that can be crafted back into their own reagents (elemental, primal and eternal
    transmutes, prismatic shards), where a proc would mint materials out of nothing;
  - recipes made only from what vendors sell without limit, where a second batch would be gold
    out of nothing.
- Skill counts with its bonuses (a racial +15), as the window shows it. Bots only get the speed (and the
  skill-scaled cast time below, like everyone).
- Recipes at the very top of an era's skill cap never turn grey, so they get little or nothing.
  `RetailProfessions.Perks.*.Min` gives every recipe a base if you want one.

**Training** and **Profit** (the book and coin tabs at the top of the column on the right)
- Two pages that look across every profession you have, in the spirit of TradeSkillMaster's
  crafting overview, in place of the list and the recipe until you pick a profession tab again.
- **Training**: your professions with their skill bars down the left, and **Next steps** beside
  them, most urgent first:
  - cooldowns that are over (all transmutes on one line, since they share a timer),
  - tracked recipes you now have the materials for,
  - per profession: the next rank to train (from 25 points short of the cap, with the level the
    trainer asks for), new recipes waiting at the trainer, what to make next for skill, and herbs
    to mill or ore to prospect.
- **What to make next** follows the leveling routes of the
  [wow-professions.com WotLK guides](https://www.wow-professions.com/wotlk-classic) (1-450) for
  Alchemy, Blacksmithing, Enchanting, Engineering, Inscription, Jewelcrafting, Leatherworking,
  Tailoring, Cooking and First Aid: "Level Alchemy: 25 Elixir of Healing Power", with how many the
  step still needs. Where the guide offers a choice, a recipe you know and have the materials for
  comes first. A recipe you don't know yet says where it's learned. The tooltip shows the route
  ahead; clicking opens the recipe with the amount set; Shift-click puts its materials on your
  shopping list. Where the guide only describes what to make ("any orange Glyph", "uncommon
  Northrend gems") or has nothing for your skill, the best skill-up you know stands in (one you
  can make now first, then the likeliest skill-up, then the cheapest).
- **Profit**: the most profitable crafts, every recipe you know that makes money at today's prices (priced
  as below), with how many you can make, what that earns in all and how many sold lately. Click
  a column to sort by it; **Can make now** hides the rest; **Refresh** asks for prices again. The
  line under it says what everything your materials make would earn.
- Click a line to go to its recipe. A line in another profession opens that profession first.
  Clicking those doesn't work in combat.
- The client only lists the open profession's recipes, so these pages keep a note of what each
  profession knows (and its cooldowns) whenever you open it. A profession you haven't opened yet
  says "Open ... once".

**Craft for profit** (with [mod-retail-ah](https://github.com/buildthehomelab/wow-mod-retail-ah)'s server)
- The **coin button** beside Filter turns the list into a ranking of the recipes you know, in the
  spirit of TradeSkillMaster: what the item sells for on the auction house (after the house cut)
  minus what the materials cost, best first.
  - **Craft now**: you have the materials, in your bags or the reagent bank (when it's counted).
  - **Buy materials and craft**: still worth it when you buy everything.
  - **Not worth it** and **No price** start folded.
- The search and the filters work as usual, and every row shows its profit per craft. Hover a
  row for the sale price, the materials, the profit and how much you make crafting everything
  you can.
- The recipe pane gets an **Auction house** block: what it sells for and where that price comes
  from, how many are listed and how many sold in the last 14 days, the materials (hover for each
  reagent's price and source) and the profit. It shows for recipes you haven't learned too, so
  you can see whether one is worth learning.
- How it prices:
  - **Selling**: the lowest buyout, or with nothing listed, what it sold for lately. When the AH
    bot buyer pays more (it buys every time it looks), that instead. A vendor's price when that's
    more still. Items that bind on pickup are worth their vendor price only. Your own auctions
    aren't counted.
  - **Materials**: the cheaper of a vendor and the lowest buyout. Materials you already have
    count at that price too, since crafting has to beat selling them as they are. A material
    nothing sells counts at its vendor price if you have enough of it.
- Prices are the auction house of your own faction (the neutral one with two-side trading), from
  anywhere: no need to stand at an auctioneer. They stay good for 3 minutes; Shift-click the coin
  to ask again. Enchants aren't listed, since they make no item.

**Tracking**
- Right-click a recipe (or tick **Track recipe**) to put it on a list on your screen, like a
  tracked quest. It shows every reagent you still need for the number of crafts you want (right-
  click it: make 1, 2, 3, 5, 10, 20), turns green when you have it all and counts the reagent
  bank. Click a tracked recipe to show it in the window. Drag the title to move the list.

**Professions book (K)**
- Every profession and secondary skill with its rank and skill bar, an **Open** button, the
  gathering action where there is one (Find Herbs, Find Minerals, Smelting, Fishing) and
  **Unlearn**. For Inscription and Jewelcrafting, a **Milling** / **Prospecting** button that
  opens the window on your herbs or ore. The addon binds **K** the first time, if K is free; otherwise set it under
  Key Bindings > Retail Professions. `/prof` also opens it.
- **Archaeology** (from [mod-archaeology](https://github.com/buildthehomelab/wow-mod-archaeology)),
  with its ArchaeologyUI addon loaded: a row under Secondary Skills whose **Open** shows its
  research window and **Survey** surveys, and a row in Training's professions column. It shows
  whether or not the client patch makes Archaeology a skill line; it can't be unlearned here.

**Other**
- `/prof classic` switches back to the old Blizzard window, `/prof retail` returns.
- `/prof reset` puts the windows back where they started.
- `/prof log` opens the craft procs log.
- At a profession trainer, the recipe you picked stays picked when you skill up (the stock window
  jumps back to the first one you can learn).
- The windows are stock Blizzard frames (dialog frame, buttons, checkboxes, scroll bars). With
  [DragonUI](https://github.com/NeticSoul/DragonUI) installed they wear DragonUI's retail skin:
  the metal frame with the round portrait, red buttons and gold category bars. The profession
  window goes further when DragonUI has its own professions window: it takes that window's art,
  so it looks like DragonUI's professions overview (the profession's coloured skill bar, the
  list's category bars and skill-up arrows, the recipe on a parchment card with the profession's
  drawing, quality-ringed icons and slots, and its side tabs).
- With a DragonUI that hosts other professions addons (its `Professions.Host`, DragonUI 2.7.0+),
  there is only one window: DragonUI's. The recipe list, the recipe card, the craft controls and
  the proc log button go into it; Training and Profit are pages of it; Milling and Prospecting
  are side tabs; tracked recipes go into its objective tracker; and K (or `/prof`) opens its
  Overview. There, `/prof classic` shows DragonUI's own crafting page and `/prof retail` brings
  this one back.
  Without DragonUI, everything above uses this addon's own window.
- With [mod-reagent-bank-account](https://github.com/buildthehomelab/mod-reagent-bank-account)'s
  ReagentBankUI, everything its old profession sidebar did is in this window: the amount,
  crafting from the bank, Deposit leftovers and Add to Shopping List.

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

Without the module the window still works, minus unlearned recipes, exact odds, sources and the
Milling and Prospecting tabs.

For Milling and Prospecting the module reads `milling_loot_template`, `prospecting_loot_template`
and the reference tables they point to at startup and works out each result's chance (groups,
references and the drop rates included), which is what the window shows. A Mill All is a job on
the server: every cast time it checks what the spell checks (spell known, skill, five in the
bags), takes five, rolls the core's own loot table (`Loot::FillLoot`) and stores the result.

The crafting perks hang on the core's own hooks. Multicraft and Resourcefulness roll when a
craft creates its item (`OnPlayerCreateItem`), from the recipe's yellow and grey skill in
`SkillLineAbility.dbc` and the player's skill. The core has no hook for a cast time, so the
speed is applied right after `Spell::prepare`: the cast is shortened and its start is sent to
the client again. Which recipes loop is worked out at startup from every recipe's reagents and
product.

The same hook fixes a core gap, with the perks on or off. About 1,860 recipes (most Classic
and TBC gear) get quicker as your skill rises: `SpellCastTimes.dbc` has a base time, a step per
level and a floor, and for a recipe the level is your skill / 5. The client shows that time,
but the core only loads the base, so Ruby Pendant of Fire said 8 seconds at 258 Jewelcrafting
and took 25. The module casts at the time the client shows; the speed perk comes off that.

The profit view asks mod-retail-ah's server for prices under that module's `RAH` prefix (its `K`
request, which needs no auctioneer). Without it, or with `RetailAH.CraftPrices = 0`, the view
says there are no auction prices on the realm.

## Requirements

- An [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) WotLK (master) server.
- A WoW 3.3.5a (12340) client with the `RetailProfessions` addon installed.
- Optional: [mod-individual-progression](https://github.com/ZhengPeiRu21/mod-individual-progression)
  (era skill caps and locked continents), [mod-retail-ah](https://github.com/buildthehomelab/wow-mod-retail-ah)
  (craft-for-profit prices), [mod-reagent-bank-account](https://github.com/buildthehomelab/mod-reagent-bank-account)
  with its ReagentBankUI, and [DragonUI](https://github.com/NeticSoul/DragonUI) (skin).

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
continents, how many sources per kind, the world-drop threshold, saving zones, Milling and
Prospecting from the window (`RetailProfessions.Refine.Enable`, `RetailProfessions.Refine.CastTime`),
and the crafting perks (`RetailProfessions.Perks.Enable` and a `Min` / `Max` percent each for
`Perks.Multicraft`, `Perks.Resourcefulness` (plus `Refund`) and `Perks.Speed`).

## Development

`lua tools/addon_smoke_test.lua addon/RetailProfessions` loads the addon against a stubbed
3.3.5a API and a fake server and walks through opening a profession, filters, crafting, where to
learn a recipe, tracking, the book, combat, the profit view (with a fake mod-retail-ah price
server), the Training and Profit tabs (next steps, the leveling guide, the most profitable crafts,
a line opening another profession), shopping for an unlearned recipe, the
crafting perks, milling (its tab, Mill All, Stop, the reagent bank) and the classic switch.

## Troubleshooting

- **The window shows no unlearned recipes or skill-up odds**: the server module isn't running.
  Check that the folder is named `mod-retail-professions`, that CMake was re-run and the server
  rebuilt, and that `RetailProfessions.Enable = 1` in `mod_retail_professions.conf`. Without the
  module the addon only shows what the client knows.
- **The profit view says there are no auction prices**: it needs mod-retail-ah on the same
  server, and `RetailAH.CraftPrices` must not be `0`.
- **K does nothing**: the addon only binds K if it was free. Set a key under Key Bindings >
  Retail Professions, or type `/prof`.
- **You want the old window back**: `/prof classic` switches to it, `/prof retail` returns.
- **A window ended up off screen**: `/prof reset` puts the windows back.

## Credits

Author: [buildthehomelab](https://github.com/buildthehomelab)

## License

MIT, see [LICENSE](LICENSE).
