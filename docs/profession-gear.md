# Profession equipment (build spec)

Retail-style profession gear for mod-retail-professions: every profession gets a tool slot and
accessory slots, filled from the profession window. Items in the slots live server-side (they
leave the bags), give skill and crafting/gathering stats, and the tools that recipes require
(Blacksmith Hammer, Arclight Spanner, Jeweler's Kit, rods, ...) count from the slots.

## Slots

| Skill line | Slots |
|---|---|
| Alchemy 171, Blacksmithing 164, Enchanting 333, Engineering 202, Herbalism 182, Inscription 773, Jewelcrafting 755, Leatherworking 165, Mining 186, Skinning 393, Tailoring 197 | 0 = tool, 1 and 2 = accessories |
| Cooking 185 | 0 = tool, 1 = accessory |

Fishing is not supported yet: the Fishing spell needs a pole in the main hand, and lures target the pole.

What may go in a slot of skill S:
- a **gear item** (row in `mod_retail_professions_gear` with `skill = S`): `kind 0` (tool) only in slot 0,
  `kind 1` (accessory) only in slots 1/2;
- a **plain tool** of S: an item that meets one of S's recipe tool requirements (the recipe's
  exact Totem item, or an item whose TotemCategory is compatible with the recipe's category).
  Any slot of S. That is how a recipe needing two tools (Engineering: spanner + hammer or
  micro-adjustor) gets its second one: from an accessory slot, or from the bags as before.

Rules: the player must know the profession. The item's `RequiredSkill`/`RequiredSkillRank`
must be met (pure skill, without gear bonuses). This is how gear is gated by era: IP caps skill
at 300/375. The same entry can't sit in two slots of one profession. No equip or unequip
in combat, while casting, while trading, or for bots.

## Tables

World, `mod_retail_professions_gear` (created by the module's world SQL; the content SQL fills it):

| column | type | meaning |
|---|---|---|
| entry | INT UNSIGNED PK | item_template entry |
| skill | SMALLINT UNSIGNED | skill line it serves |
| kind | TINYINT UNSIGNED | 0 tool, 1 accessory |
| skill_bonus | SMALLINT UNSIGNED | + skill while slotted |
| multicraft, resourcefulness, speed | TINYINT UNSIGNED | crafting stats, percentage points |
| finesse, perception, deftness | TINYINT UNSIGNED | gathering stats, percentage points |
| counts_as | INT UNSIGNED | an item entry this one stands in for as an exact Totem requirement (Jeweler's Kit 20815, Simple Grinder 20824), 0 = none |

Characters, `mod_retail_professions_gear_slot`: `owner_guid, skill, slot, item_guid (PK)`,
unique `(owner_guid, skill, slot)`. The item keeps its `item_instance` row; this row replaces its
`character_inventory` row (mail-style, as mod-gear-vault does).

## Stats

- Skill bonus: a server-only passive aura per profession (spells 90800-90811, Mod Skill), amount = sum of slots.
- Multicraft / Resourcefulness / Speed: added (percentage points) to the chances the Perks code
  already rolls from recipe mastery. Capped at 100 (speed at 90, SPEED_CAP).
- Finesse: chance of one extra copy when looting a primary gathered item (Trade Goods herb 9,
  metal & stone 7, leather 6) from a herb/ore node or a skinned corpse.
- Perception: other (rare) items of a gathered node's or skinned corpse's loot roll at
  chance × (100 + perception)%.
- Deftness: gathering casts (herb/mining open-lock, skinning) are deftness% shorter.

## Tool requirements

At startup the server records every trade skill spell's `Totem[2]` and `TotemCategory[2]`, and
clears them in `SpellInfo`. The client patch clears the same fields (Spell.dbc 50, 51, 222, 223)
on the same spells: every row with `Attributes & 0x20` (SPELL_ATTR0_IS_TRADESKILL) that has any
of them set, except loot crafting (effect 0 is Create Item 2 with an item, and TotemCategory 0
is set, or Totem 0 with icon 1: Darkmoon cards, tarots, Prismatic Black Diamond), whose tool is
what makes the core roll spell_loot_template; those 9 keep their tools and the core checks them.
Before each cast the server checks the recorded tools itself, skipping casts from an item with
no reagent cost (enchanting scrolls), as the core does: a tool counts in the bags (or worn), or
in any slot of the recipe's profession; a gear item with counts_as counts in the bags too.
Another profession's gear can sit in a slot as a plain tool but gives no stats there. A missing tool fails the cast with the client's own
"Requires X" message (an SMSG_CAST_FAILED carrying the recorded ids), then SPELL_FAILED_DONT_REPORT.

## Addon messages (RPR transport, HELLO flag 0x20 = HELLO_GEAR)

Wire format as in RetailProfessions.cpp: `<CMD>:<req>:<fields>`; list answers come as rows
`;`-separated, values `,`-separated, names `Escape()`d.

| request | answer |
|---|---|
| `GC:<req>` gear catalog | `GCD:<req>:<rows>` (any number), then `GCE:<req>:<count>`. Row: `entry,skill,kind,skillBonus,multicraft,resourcefulness,speed,finesse,perception,deftness,reqSkill,reqRank` |
| `G:<req>` slotted gear | `GD:<req>:<rows>` (any number), then `GE:<req>:<count>`. Row: `skill,slot,entry,itemGuid` |
| `GQ:<req>:<bag>:<bagSlot>:<skill>:<slot>` equip | `GQ:<req>:ok:<skill>:<slot>` or `ERR:<req>:<code>`. bag 0 = backpack, 1-4 = bags; bagSlot counts from 1 (as GetContainerItemInfo). skill 0 = the item's own profession; slot 9 = first free fitting slot (tool slot for a tool/plain tool, else an empty accessory slot; a full set swaps the tool slot or the first accessory slot) |
| `GU:<req>:<skill>:<slot>` unequip to bags | `GU:<req>:ok` or `ERR:<req>:<code>` |
| `GT:<req>:<skill>` tool requirements | `GTD:<req>:<rows>`, then `GTE:<req>:<count>`. Rows `T,<key>,<name>,<entry>/<entry>/...` define a tool: key `c<category>` or `i<item>`, name escaped, entries = items that meet it (gear items with counts_as included), at most 30. Rows `S,<spell>,<key>[/<key>]` give a recipe's tools. All T rows come before the S rows that use them |

Unasked, after any change (equip, unequip, a profession unlearned, login): `GD:0:...` rows then
`GE:0:<count>`. On a Finesse proc: `PG:0:<skill>:F:<item>*<n>`.

Error codes: `off` (gear disabled), `loading` (slots not read yet), `combat`, `casting`,
`trade`, `bot`, `noitem` (nothing at that bag slot), `notgear` (not gear or a tool of that
profession), `unlearned`, `rank` (skill too low), `slot` (wrong slot for this item),
`dup` (already in another slot of this profession), `bags` (no room to take an item off),
`empty` (nothing in that slot), `busy` (rate limit, retried by the addon).

## IDs (checked free on the live z80 and in every module, 2026-10-30)

- spell_dbc 90800-90811: server-only skill auras (one per profession, in the order of the table above)
- items 90800-90879: gear items (item_template + Item.dbc via z80)
- spells + SkillLineAbility 90820-90899: the recipes that craft them (Spell.dbc via z80 + spell_dbc + skilllineability_dbc)
