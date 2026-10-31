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
| Fishing 356 | 0 = rod |

What may go in a slot of skill S:
- a **gear item** (row in `mod_retail_professions_gear` with `skill = S`): `kind 0` (tool) only in slot 0,
  `kind 1` (accessory) only in slots 1/2;
- a **plain tool** of S: an item that meets one of S's recipe tool requirements (the recipe's
  exact Totem item, or an item whose TotemCategory is compatible with the recipe's category).
  Any slot of S. That is how a recipe needing two tools (Engineering: spanner + hammer or
  micro-adjustor) gets its second one: from an accessory slot, or from the bags as before.
  Also plain tools: a **gathering tool** of Mining (TotemCategory compatible with 165 Mining Pick)
  or Skinning (166 Skinning Knife), and for Fishing a **fishing pole** (weapon subclass 20).

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
- A slotted pick or knife, while mod-gathering-tools is installed (its aura spell 90130/90131
  exists) and its aura isn't up (no tool carried): gathering casts are
  `GatheringTools.ToolGatherSpeed`% shorter (after Deftness) and the skill aura adds
  `GatheringTools.ToolSkillBonus`, which is what that module gives for one in the bags.
- The Fishing aura (90812) adds the slotted rod's fishing skill: Mod Skill 356 from its equip
  spells and from the equip spells of its permanent (line) and temporary (lure) enchantments.
  Only while no rod is in the main hand (that one counts by itself, as worn). Recomputed on
  every change and every 5 s (CHECK_INTERVAL), which also follows rods and picks moving in and
  out of the hands and bags.

## Fishing with the slotted rod

At startup the server records the spells that need exactly a fishing pole
(`EquippedItemClass` 2, `EquippedItemSubClassMask` 1 << 20): **casts** (a Trans Door effect:
Fishing 7620, 7731, 7732, 18248, 33095, 51294) and **enchants** (`Targets` has
TARGET_FLAG_ITEM and effect 0 is Enchant Item or Enchant Item Temporary: the 9 lures and 2
fishing lines). It clears their rod requirement in `SpellInfo`. The client patch clears fields
68-70 on the same rows, and on the enchants also `Targets` (16), and makes effect 0 a Dummy (71)
on the caster (86): the client then casts a lure at once instead of asking for an item. The
server makes the enchants' effect 0 a Dummy in `SpellInfo` too (the core's Enchant Item effects
fail without an item target, `Spell::CheckItems`), and the module puts every lure and line on a
rod itself, after the cast (`OnSpellCast`): the cast bar and the used-up lure stay the core's.

- Fishing needs a rod in the main hand or the Fishing slot, else the client's own "Requires
  Fishing Pole" (SMSG_CAST_FAILED, EQUIPPED_ITEM_CLASS 2 / 1 << 20).
- A lure or line with an item target (an unpatched client, which still asks) must target a rod,
  and goes on it. Without one it goes on the rod in the main hand, else on the slotted rod. On a
  rod in the inventory (or a trade window) the module does what `Spell::EffectEnchantItemTmp` /
  `EffectEnchantItemPerm` do (`ApplyEnchantment` off, `SetEnchantment`, `ApplyEnchantment` on).
  On the slotted rod it writes the enchantment fields itself (not `Item::SetEnchantment`, which
  queues the item for its owner's inventory save), saves the item, and says so in chat. Lure durations as
  `Spell::EffectEnchantItemTmp`: 600 s for the 8 classic lures, else 3600 s.
- With the patched client a lure no longer asks for a rod, so a rod in the bags can't take one
  (as retail: the lure goes on the rod you fish with). The Dummy skips the core's per-effect
  item checks (`Spell::CheckItems`); the one that matters, no soulbound enchantment on a trade
  partner's rod, the module repeats.
- The slotted rod's lure counts down every 5 s while the player is online, saved when it runs
  out and at logout.
- While Fishing is channeled with the slotted rod, the main-hand visible item is the rod (with
  its enchant visuals) and the off hand is empty; the next update after the channel ends puts
  `SetVisibleItemSlot` back for both (and at logout). mod-transmog-plus's outgoing-packet patch
  skips the hand fields while the player channels a spell that summons a fishing bobber with no
  rod in the main hand.
- Druids' Salmon Run (mod-druid-swipe-fishing) uses its own spell and isn't touched.

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

## Addon messages (RPR transport, HELLO flag 0x20 = HELLO_GEAR; 0x40 = HELLO_GEAR_GATHER: the Fishing rod slot and gathering tools)

Wire format as in RetailProfessions.cpp: `<CMD>:<req>:<fields>`; list answers come as rows
`;`-separated, values `,`-separated, names `Escape()`d.

| request | answer |
|---|---|
| `GC:<req>` gear catalog | `GCD:<req>:<rows>` (any number), then `GCE:<req>:<count>`. Row: `entry,skill,kind,skillBonus,multicraft,resourcefulness,speed,finesse,perception,deftness,reqSkill,reqRank` |
| `G:<req>` slotted gear | `GD:<req>:<rows>` (any number), then `GE:<req>:<count>`. Row: `skill,slot,entry,itemGuid` |
| `GQ:<req>:<bag>:<bagSlot>:<skill>:<slot>` equip | `GQ:<req>:ok:<skill>:<slot>` or `ERR:<req>:<code>`. bag 0 = backpack, 1-4 = bags; bagSlot counts from 1 (as GetContainerItemInfo). skill 0 = the item's own profession; slot 9 = first free fitting slot (tool slot for a tool/plain tool, else an empty accessory slot; a full set swaps the tool slot or the first accessory slot) |
| `GU:<req>:<skill>:<slot>` unequip to bags | `GU:<req>:ok` or `ERR:<req>:<code>` |
| `GT:<req>:<skill>` tool requirements (none for the gathering professions and Fishing) | `GTD:<req>:<rows>`, then `GTE:<req>:<count>`. Rows `T,<key>,<name>,<entry>/<entry>/...` define a tool: key `c<category>` or `i<item>`, name escaped, entries = items that meet it (gear items with counts_as included), at most 30. Rows `S,<spell>,<key>[/<key>]` give a recipe's tools. All T rows come before the S rows that use them |

Unasked, after any change (equip, unequip, a profession unlearned, login): `GD:0:...` rows then
`GE:0:<count>`. On a Finesse proc: `PG:0:<skill>:F:<item>*<n>`.

Error codes: `off` (gear disabled), `loading` (slots not read yet), `combat`, `casting`,
`trade`, `bot`, `noitem` (nothing at that bag slot), `notgear` (not gear or a tool of that
profession), `unlearned`, `rank` (skill too low), `slot` (wrong slot for this item),
`dup` (already in another slot of this profession), `bags` (no room to take an item off),
`empty` (nothing in that slot), `busy` (rate limit, retried by the addon).

## IDs (checked free on the live z80 and in every module, 2026-10-30)

- spell_dbc 90800-90811: server-only skill auras (one per profession, in the order of the table above);
  90812 the Fishing aura (SQL _02, checked free on the boaring z80 4b68c47a and in every module, 2026-10-30)
- items 90800-90879: gear items (item_template + Item.dbc via z80)
- spells + SkillLineAbility 90820-90899: the recipes that craft them (Spell.dbc via z80 + spell_dbc + skilllineability_dbc)
