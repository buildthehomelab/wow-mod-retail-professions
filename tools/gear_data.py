"""
mod-retail-professions: profession equipment items and the recipes that craft them.

This file is the single source of truth for the classic (vanilla) tier of profession gear.
tools/build_gear_patch.py reads it to write the client patch rows (Spell.dbc, SkillLineAbility.dbc,
Item.dbc) and the world SQL (item_template, item_dbc, spell_dbc, skilllineability_dbc,
mod_retail_professions_gear). Change it here, then run the builder again; don't edit the
generated SQL.

IDs (checked free on the live z80 and in every module, 2026-10-30; see docs/profession-gear.md):
- items 90800-90879 (70 used: 90800-90869)
- recipe spells and their SkillLineAbility rows 90820-90899 (70 used: 90820-90889)

Every profession that has equipment slots gets a tool and two accessories (Cooking: a tool and
one accessory) in two tiers:
- green "journeyman", usable at skill 75: tool +5 skill and one stat at 3; accessory two stats
  at 2/2.
- blue "artisan", usable at skill 225: tool +10 skill and one stat at 5; accessory +5 skill and
  two stats at 3/3.
Stats are percentage points (columns of mod_retail_professions_gear). Crafting professions and
Cooking use multicraft/resourcefulness/speed, gathering professions finesse/perception/deftness.
Which stat sits on which item rotates by profession, so each tier offers different choices.

The gear is crafted by other professions, retail-style, but only by vanilla ones (no
Jewelcrafting or Inscription crafters). A recipe is learned automatically when the crafter's
skill reaches the recipe's level (SkillLineAbility AcquireMethod 1, MinSkillLineRank = level).
"""

# --- Skill lines ---------------------------------------------------------------------------

ALCHEMY = 171
BLACKSMITHING = 164
ENCHANTING = 333
ENGINEERING = 202
HERBALISM = 182
INSCRIPTION = 773
JEWELCRAFTING = 755
LEATHERWORKING = 165
MINING = 186
SKINNING = 393
TAILORING = 197
COOKING = 185

SKILL_NAMES = {
    ALCHEMY: "Alchemy", BLACKSMITHING: "Blacksmithing", ENCHANTING: "Enchanting",
    ENGINEERING: "Engineering", HERBALISM: "Herbalism", INSCRIPTION: "Inscription",
    JEWELCRAFTING: "Jewelcrafting", LEATHERWORKING: "Leatherworking", MINING: "Mining",
    SKINNING: "Skinning", TAILORING: "Tailoring", COOKING: "Cooking",
}

# Order of the professions = order of the skill auras 90800-90811 and of the item ids here.
PROFESSIONS = [ALCHEMY, BLACKSMITHING, ENCHANTING, ENGINEERING, HERBALISM, INSCRIPTION,
               JEWELCRAFTING, LEATHERWORKING, MINING, SKINNING, TAILORING, COOKING]

GATHERING = {HERBALISM, MINING, SKINNING}
CRAFTERS = {BLACKSMITHING, ENCHANTING, ENGINEERING, LEATHERWORKING, TAILORING}

ITEM_FIRST, ITEM_LAST = 90800, 90879
SPELL_FIRST, SPELL_LAST = 90820, 90899
AURA_FIRST, AURA_LAST = 90800, 90812  # the skill auras (schema SQL _00 and _02, not this file)

TOOL, ACCESSORY = 0, 1
GREEN, BLUE = "green", "blue"

# --- Tiers -----------------------------------------------------------------------------------

TIERS = {
    #       quality  usable at  item level  sell price (copper): tool, accessory
    GREEN: dict(quality=2, rank=75, item_level=30, sell={TOOL: 2000, ACCESSORY: 1500}),
    BLUE: dict(quality=3, rank=225, item_level=55, sell={TOOL: 10000, ACCESSORY: 7500}),
}


def trivial(tier, learn):
    """(yellow, grey) of a recipe learned at `learn`: orange until yellow, green from the
    midpoint, grey at grey (the core's SkillGainChance uses TrivialSkillLineRankLow as yellow
    and TrivialSkillLineRankHigh as grey). Same spacing as nearby stock recipes: Hillman's
    Leather Gloves 145 -> 170/195, Truesilver Breastplate 245 -> 265/285, Blight 250 -> 275/300."""
    return (learn + 25, learn + 50) if tier == GREEN else (learn + 20, learn + 40)


# --- Stats -----------------------------------------------------------------------------------

STAT_COLUMNS = ["multicraft", "resourcefulness", "speed", "finesse", "perception", "deftness"]
STAT_LABELS = {"multicraft": "Multicraft", "resourcefulness": "Resourcefulness",
               "speed": "Crafting Speed", "finesse": "Finesse", "perception": "Perception",
               "deftness": "Deftness"}
M, R, S = "multicraft", "resourcefulness", "speed"
F, P, D = "finesse", "perception", "deftness"


def stats_of(kind, tier, names):
    """Stat values of an item: a tool has one stat, an accessory two."""
    if kind == TOOL:
        assert len(names) == 1
        return {names[0]: 3 if tier == GREEN else 5}
    assert len(names) == 2 and names[0] != names[1]
    value = 2 if tier == GREEN else 3
    return {names[0]: value, names[1]: value}


def skill_bonus_of(kind, tier):
    if kind == TOOL:
        return 5 if tier == GREEN else 10
    return 0 if tier == GREEN else 5


# --- Recipe tools the stat tools stand in for --------------------------------------------------
#
# item_template.TotemCategory of each profession's stat tool. The core's
# Player::IsTotemCategoryCompatiableWith accepts an item for a required category when both have
# the same TotemCategoryType and the item's TotemCategoryMask contains the required mask (and the
# item's RequiredSkill/RequiredSkillRank are met). TotemCategory rows (3.3.5 ids, from the
# TotemCategory DB2 of 3.4.3.54261):
#   12 Philosopher's Stone (type 22, mask 1)     14 Arclight Spanner (24, 1)
#   121 Virtuoso Inking Set (24, 0x80000000)     162 Blacksmith Hammer (24, 4)
#   165 Mining Pick (24, 8)                      166 Skinning Knife (24, 16)
#   Runed rods, type 3: 6 Copper (mask 1), 7 Silver (3), 8 Golden (7), 9 Truesilver (15),
#   10 Arcanite (31), 41 Fel Iron (63), 62 Adamantite (127), 63 Eternium (255), 190 Titanium (1023)
# Enchanting: the green rod is a Runed Golden Rod (mask 7 covers Copper, Silver and Golden rod
# recipes, every rod requirement below skill 200), the best rod an enchanter of the green
# recipe's level can make (Runed Golden Rod is learned at 150, Truesilver at 200). The blue rod is
# a Runed Arcanite Rod (mask 31 covers every classic rod).
# Jewelcrafting recipes need exact Totem items (Jeweler's Kit 20815, Simple Grinder 20824), not
# categories, so the JC tools carry counts_as = 20815 in mod_retail_professions_gear instead.

TOOL_TOTEM_CATEGORY = {
    ALCHEMY: {GREEN: 12, BLUE: 12},
    BLACKSMITHING: {GREEN: 162, BLUE: 162},
    ENCHANTING: {GREEN: 8, BLUE: 10},
    ENGINEERING: {GREEN: 14, BLUE: 14},
    INSCRIPTION: {GREEN: 121, BLUE: 121},
    MINING: {GREEN: 165, BLUE: 165},
    SKINNING: {GREEN: 166, BLUE: 166},
}
TOTEM_CATEGORY_NAMES = {12: "Philosopher's Stone", 14: "Arclight Spanner", 121: "Virtuoso Inking Set",
                        162: "Blacksmith Hammer", 165: "Mining Pick", 166: "Skinning Knife",
                        8: "Runed Golden Rod", 10: "Runed Arcanite Rod"}
TOOL_COUNTS_AS = {JEWELCRAFTING: 20815}  # Jeweler's Kit
COUNTS_AS_NAMES = {20815: "Jeweler's Kit"}

# --- Recipe templates ----------------------------------------------------------------------------
#
# Each recipe's Spell.dbc row starts as a copy of a stock recipe of the crafter and tier (cast
# time, visual, icon, attributes, and Blacksmithing's anvil), then gets its own id, name,
# reagents and created item. Their tools are cleared.

RECIPE_TEMPLATES = {
    BLACKSMITHING: {GREEN: 3333, BLUE: 9974},     # Silvered Bronze Gauntlets, Truesilver Breastplate
    LEATHERWORKING: {GREEN: 3764, BLUE: 10632},   # Hillman's Leather Gloves, Helm of Fire
    TAILORING: {GREEN: 6690, BLUE: 12092},        # Lesser Wizard's Robe, Dreamweave Circlet
    ENGINEERING: {GREEN: 3956, BLUE: 12622},      # Green Tinted Goggles, Green Lens (no anvil)
    ENCHANTING: {GREEN: 13628, BLUE: 20051},      # Runed Golden Rod, Runed Arcanite Rod
}

# --- Reagents (item entries, checked against the 2025 world DB) ----------------------------------

COPPER_BAR, BRONZE_BAR, SILVER_BAR, IRON_BAR, STEEL_BAR = 2840, 2841, 2842, 3575, 3859
GOLD_BAR, MITHRIL_BAR, TRUESILVER_BAR, THORIUM_BAR = 3577, 3860, 6037, 12359
MEDIUM_LEATHER, HEAVY_LEATHER, RUGGED_LEATHER = 2319, 4234, 8170
CURED_HEAVY_HIDE, CURED_RUGGED_HIDE = 4236, 15407
BOLT_OF_SILK, BOLT_OF_RUNECLOTH, MOONCLOTH = 4305, 14048, 14342
FINE_THREAD, SILKEN_THREAD, RUNE_THREAD = 2321, 4291, 14341
SPIDERS_SILK = 3182
GREEN_DYE, BLACK_DYE, PURPLE_DYE = 2605, 2325, 4342
BRONZE_TUBE, WHIRRING_BRONZE_GIZMO, SILVER_CONTACT = 4371, 4375, 4404
MITHRIL_CASING, THORIUM_WIDGET = 10561, 15994
COARSE_GRINDING_STONE, HEAVY_GRINDING_STONE, DENSE_GRINDING_STONE = 3478, 3486, 12644
HEAVY_STONE, DENSE_STONE = 2838, 12365
IRON_BUCKLE, STRONG_FLUX = 7071, 3466
MOSS_AGATE, SHADOWGEM, CITRINE, JADE, LESSER_MOONSTONE = 1206, 1210, 3864, 1529, 1705
AQUAMARINE, STAR_RUBY, BLACK_PEARL, IRIDESCENT_PEARL = 7909, 7910, 7971, 5500
LEADED_VIAL, IMBUED_VIAL = 3372, 18256
WILDVINE, HEART_OF_THE_WILD = 8153, 10286
ESSENCE_OF_FIRE, ESSENCE_OF_WATER, ESSENCE_OF_AIR, ESSENCE_OF_EARTH = 7078, 7080, 7082, 7076
SOUL_DUST, ILLUSION_DUST = 11083, 16204
GREATER_ASTRAL_ESSENCE, GREATER_ETERNAL_ESSENCE = 11082, 16203
LARGE_BRILLIANT_SHARD = 14344
GOLDEN_ROD, TRUESILVER_ROD = 11128, 11144

# --- The items -------------------------------------------------------------------------------------
#
# One row per item, in id order (6 per profession, 4 for Cooking; green tool, accessory 1,
# accessory 2, then blue tool, accessory 1, accessory 2). Fields:
#   skill     the profession it serves (RequiredSkill)
#   kind      TOOL or ACCESSORY
#   tier      GREEN or BLUE
#   name      item and recipe name
#   crafter   skill line of the recipe
#   learn     crafter skill the recipe is learned at (yellow/grey from trivial())
#   look      an existing item whose icon (Item.dbc displayId) the new item reuses
#   stats     stat names (values from stats_of())
#   reagents  [(item, count), ...]

_ROWS = [
    # Alchemy: Engineering / Tailoring / Leatherworking
    (ALCHEMY, TOOL, GREEN, "Gnomish Mortar and Pestle", ENGINEERING, 125, 15454, [M],
     [(BRONZE_TUBE, 2), (WHIRRING_BRONZE_GIZMO, 1), (LEADED_VIAL, 2)]),
    (ALCHEMY, ACCESSORY, GREEN, "Alchemist's Silk Apron", TAILORING, 130, 2981, [M, R],
     [(BOLT_OF_SILK, 3), (FINE_THREAD, 2), (GREEN_DYE, 1)]),
    (ALCHEMY, ACCESSORY, GREEN, "Acid-Stained Gloves", LEATHERWORKING, 135, 1945, [R, S],
     [(HEAVY_LEATHER, 6), (CURED_HEAVY_HIDE, 1), (FINE_THREAD, 2)]),
    (ALCHEMY, TOOL, BLUE, "Thorium Alembic", ENGINEERING, 260, 18256, [R],
     [(THORIUM_WIDGET, 2), (THORIUM_BAR, 4), (IMBUED_VIAL, 2), (ESSENCE_OF_WATER, 1)]),
    (ALCHEMY, ACCESSORY, BLUE, "Runecloth Alchemist's Apron", TAILORING, 260, 6427, [M, S],
     [(BOLT_OF_RUNECLOTH, 4), (RUNE_THREAD, 2), (ESSENCE_OF_WATER, 1)]),
    (ALCHEMY, ACCESSORY, BLUE, "Acid-Proof Gauntlets", LEATHERWORKING, 265, 3965, [M, R],
     [(RUGGED_LEATHER, 8), (CURED_RUGGED_HIDE, 1), (RUNE_THREAD, 2)]),

    # Blacksmithing: Blacksmithing / Blacksmithing / Leatherworking
    (BLACKSMITHING, TOOL, GREEN, "Journeyman's Smithing Hammer", BLACKSMITHING, 130, 5956, [R],
     [(BRONZE_BAR, 8), (SILVER_BAR, 1), (COARSE_GRINDING_STONE, 2), (MEDIUM_LEATHER, 2)]),
    (BLACKSMITHING, ACCESSORY, GREEN, "Heavy Whetstone Kit", BLACKSMITHING, 140, 2871, [R, S],
     [(IRON_BAR, 4), (HEAVY_GRINDING_STONE, 2), (HEAVY_STONE, 4)]),
    (BLACKSMITHING, ACCESSORY, GREEN, "Smith's Leather Apron", LEATHERWORKING, 140, 2470, [M, S],
     [(HEAVY_LEATHER, 8), (CURED_HEAVY_HIDE, 1), (FINE_THREAD, 2), (IRON_BUCKLE, 1)]),
    (BLACKSMITHING, TOOL, BLUE, "Truesilver Forge Hammer", BLACKSMITHING, 265, 2194, [S],
     [(THORIUM_BAR, 8), (TRUESILVER_BAR, 2), (DENSE_GRINDING_STONE, 2), (RUGGED_LEATHER, 2)]),
    (BLACKSMITHING, ACCESSORY, BLUE, "Dense Whetstone Kit", BLACKSMITHING, 270, 12404, [M, R],
     [(THORIUM_BAR, 6), (DENSE_GRINDING_STONE, 3), (DENSE_STONE, 4)]),
    (BLACKSMITHING, ACCESSORY, BLUE, "Fireproof Smithing Apron", LEATHERWORKING, 260, 14042, [R, S],
     [(RUGGED_LEATHER, 8), (CURED_RUGGED_HIDE, 1), (RUNE_THREAD, 1), (ESSENCE_OF_FIRE, 1)]),

    # Enchanting: Enchanting / Tailoring / Engineering
    (ENCHANTING, TOOL, GREEN, "Enchanter's Runed Rod", ENCHANTING, 150, 11130, [S],
     [(GOLDEN_ROD, 1), (IRIDESCENT_PEARL, 1), (GREATER_ASTRAL_ESSENCE, 1), (SOUL_DUST, 2)]),
    (ENCHANTING, ACCESSORY, GREEN, "Silk Enchanter's Hood", TAILORING, 140, 3345, [M, S],
     [(BOLT_OF_SILK, 3), (FINE_THREAD, 2), (SOUL_DUST, 1)]),
    (ENCHANTING, ACCESSORY, GREEN, "Arcane Focusing Lens", ENGINEERING, 145, 5507, [M, R],
     [(BRONZE_TUBE, 1), (JADE, 1), (SILVER_CONTACT, 2)]),
    (ENCHANTING, TOOL, BLUE, "Grand Enchanter's Rod", ENCHANTING, 275, 16207, [M],
     [(TRUESILVER_ROD, 1), (GREATER_ETERNAL_ESSENCE, 1), (ILLUSION_DUST, 4), (LARGE_BRILLIANT_SHARD, 1)]),
    (ENCHANTING, ACCESSORY, BLUE, "Mooncloth Enchanter's Hood", TAILORING, 265, 7470, [R, S],
     [(BOLT_OF_RUNECLOTH, 3), (MOONCLOTH, 1), (RUNE_THREAD, 1), (ILLUSION_DUST, 2)]),
    (ENCHANTING, ACCESSORY, BLUE, "Mithril Focusing Lens", ENGINEERING, 270, 3925, [M, S],
     [(MITHRIL_CASING, 1), (THORIUM_WIDGET, 1), (AQUAMARINE, 2), (TRUESILVER_BAR, 1)]),

    # Engineering: Engineering / Engineering / Leatherworking
    (ENGINEERING, TOOL, GREEN, "Bronze Precision Spanner", ENGINEERING, 130, 6219, [M],
     [(BRONZE_BAR, 6), (WHIRRING_BRONZE_GIZMO, 1), (SILVER_CONTACT, 2)]),
    (ENGINEERING, ACCESSORY, GREEN, "Tinkerer's Magnifying Goggles", ENGINEERING, 145, 10499, [M, R],
     [(HEAVY_LEATHER, 2), (BRONZE_TUBE, 1), (CITRINE, 2)]),
    (ENGINEERING, ACCESSORY, GREEN, "Grease-Stained Work Gloves", LEATHERWORKING, 130, 6732, [R, S],
     [(HEAVY_LEATHER, 6), (CURED_HEAVY_HIDE, 1), (FINE_THREAD, 2)]),
    (ENGINEERING, TOOL, BLUE, "Thorium Precision Spanner", ENGINEERING, 265, 33039, [R],
     [(THORIUM_BAR, 6), (THORIUM_WIDGET, 2), (TRUESILVER_BAR, 1)]),
    (ENGINEERING, ACCESSORY, BLUE, "Thorium Tinker's Helmet", ENGINEERING, 270, 10543, [M, S],
     [(THORIUM_BAR, 4), (THORIUM_WIDGET, 1), (RUGGED_LEATHER, 2), (STAR_RUBY, 1)]),
    (ENGINEERING, ACCESSORY, BLUE, "Insulated Work Gloves", LEATHERWORKING, 260, 4063, [M, R],
     [(RUGGED_LEATHER, 8), (CURED_RUGGED_HIDE, 1), (RUNE_THREAD, 1), (ESSENCE_OF_AIR, 1)]),

    # Herbalism: Blacksmithing / Tailoring / Leatherworking
    (HERBALISM, TOOL, GREEN, "Bronze Herbalist's Sickle", BLACKSMITHING, 125, 1602, [P],
     [(BRONZE_BAR, 6), (COARSE_GRINDING_STONE, 2), (MEDIUM_LEATHER, 2)]),
    (HERBALISM, ACCESSORY, GREEN, "Woven Herb Satchel", TAILORING, 135, 22250, [P, D],
     [(BOLT_OF_SILK, 3), (FINE_THREAD, 2), (GREEN_DYE, 1)]),
    (HERBALISM, ACCESSORY, GREEN, "Herbalist's Gardening Gloves", LEATHERWORKING, 125, 5606, [F, D],
     [(HEAVY_LEATHER, 6), (CURED_HEAVY_HIDE, 1), (FINE_THREAD, 2)]),
    (HERBALISM, TOOL, BLUE, "Thorium Herbalist's Sickle", BLACKSMITHING, 255, 863, [D],
     [(THORIUM_BAR, 8), (TRUESILVER_BAR, 1), (DENSE_GRINDING_STONE, 2), (RUGGED_LEATHER, 2)]),
    (HERBALISM, ACCESSORY, BLUE, "Runecloth Herb Satchel", TAILORING, 255, 22252, [F, P],
     [(BOLT_OF_RUNECLOTH, 4), (RUNE_THREAD, 1), (WILDVINE, 2)]),
    (HERBALISM, ACCESSORY, BLUE, "Thick Herbalist's Gloves", LEATHERWORKING, 255, 7349, [P, D],
     [(RUGGED_LEATHER, 8), (CURED_RUGGED_HIDE, 1), (RUNE_THREAD, 1), (WILDVINE, 2)]),

    # Inscription: Engineering / Tailoring / Leatherworking
    (INSCRIPTION, TOOL, GREEN, "Clockwork Inking Quill", ENGINEERING, 135, 3766, [S],
     [(BRONZE_TUBE, 1), (WHIRRING_BRONZE_GIZMO, 1), (SILVER_CONTACT, 2)]),
    (INSCRIPTION, ACCESSORY, GREEN, "Scribe's Silk Gloves", TAILORING, 135, 6565, [M, S],
     [(BOLT_OF_SILK, 2), (FINE_THREAD, 2), (BLACK_DYE, 1)]),
    (INSCRIPTION, ACCESSORY, GREEN, "Leather Scroll Case", LEATHERWORKING, 140, 4498, [M, R],
     [(HEAVY_LEATHER, 6), (CURED_HEAVY_HIDE, 1), (FINE_THREAD, 2)]),
    (INSCRIPTION, TOOL, BLUE, "Gyromatic Inking Quill", ENGINEERING, 265, 34663, [M],
     [(THORIUM_WIDGET, 2), (TRUESILVER_BAR, 2), (BLACK_PEARL, 1)]),
    (INSCRIPTION, ACCESSORY, BLUE, "Runecloth Scribe's Robe", TAILORING, 265, 6503, [R, S],
     [(BOLT_OF_RUNECLOTH, 4), (RUNE_THREAD, 2), (PURPLE_DYE, 1)]),
    (INSCRIPTION, ACCESSORY, BLUE, "Rugged Scroll Case", LEATHERWORKING, 265, 6446, [M, S],
     [(RUGGED_LEATHER, 8), (CURED_RUGGED_HIDE, 1), (RUNE_THREAD, 1)]),

    # Jewelcrafting: Engineering / Blacksmithing / Leatherworking
    (JEWELCRAFTING, TOOL, GREEN, "Precision Jeweler's Kit", ENGINEERING, 130, 20815, [M],
     [(BRONZE_TUBE, 1), (WHIRRING_BRONZE_GIZMO, 1), (BRONZE_BAR, 4)]),
    (JEWELCRAFTING, ACCESSORY, GREEN, "Bronze-Framed Loupe", BLACKSMITHING, 140, 4393, [M, R],
     [(BRONZE_BAR, 6), (SILVER_BAR, 1), (MOSS_AGATE, 1)]),
    (JEWELCRAFTING, ACCESSORY, GREEN, "Padded Gem Pouch", LEATHERWORKING, 135, 30747, [R, S],
     [(HEAVY_LEATHER, 6), (BOLT_OF_SILK, 1), (FINE_THREAD, 2)]),
    (JEWELCRAFTING, TOOL, BLUE, "Gyromatic Jeweler's Kit", ENGINEERING, 265, 40642, [R],
     [(THORIUM_WIDGET, 2), (MITHRIL_CASING, 1), (TRUESILVER_BAR, 1)]),
    (JEWELCRAFTING, ACCESSORY, BLUE, "Truesilver Loupe", BLACKSMITHING, 265, 1163, [M, S],
     [(THORIUM_BAR, 4), (TRUESILVER_BAR, 2), (AQUAMARINE, 1)]),
    (JEWELCRAFTING, ACCESSORY, BLUE, "Velvet-Lined Gem Pouch", LEATHERWORKING, 260, 24270, [M, R],
     [(RUGGED_LEATHER, 6), (BOLT_OF_RUNECLOTH, 1), (RUNE_THREAD, 1)]),

    # Leatherworking: Blacksmithing / Blacksmithing / Leatherworking
    (LEATHERWORKING, TOOL, GREEN, "Bronze Leatherworker's Knife", BLACKSMITHING, 125, 12259, [R],
     [(BRONZE_BAR, 6), (COARSE_GRINDING_STONE, 2), (MEDIUM_LEATHER, 2)]),
    (LEATHERWORKING, ACCESSORY, GREEN, "Iron Leatherworking Mallet", BLACKSMITHING, 145, 1415, [R, S],
     [(IRON_BAR, 4), (HEAVY_GRINDING_STONE, 1), (HEAVY_LEATHER, 2)]),
    (LEATHERWORKING, ACCESSORY, GREEN, "Tanner's Work Gloves", LEATHERWORKING, 145, 797, [M, S],
     [(HEAVY_LEATHER, 6), (CURED_HEAVY_HIDE, 1), (FINE_THREAD, 2)]),
    (LEATHERWORKING, TOOL, BLUE, "Truesilver Leatherworker's Knife", BLACKSMITHING, 255, 37649, [S],
     [(THORIUM_BAR, 6), (TRUESILVER_BAR, 2), (DENSE_GRINDING_STONE, 2), (RUGGED_LEATHER, 2)]),
    (LEATHERWORKING, ACCESSORY, BLUE, "Thorium Leatherworking Mallet", BLACKSMITHING, 270, 1009, [M, R],
     [(THORIUM_BAR, 6), (DENSE_GRINDING_STONE, 1), (RUGGED_LEATHER, 2)]),
    (LEATHERWORKING, ACCESSORY, BLUE, "Rugged Tanner's Gloves", LEATHERWORKING, 270, 2469, [R, S],
     [(RUGGED_LEATHER, 8), (CURED_RUGGED_HIDE, 1), (RUNE_THREAD, 2)]),

    # Mining: Blacksmithing / Engineering / Leatherworking
    (MINING, TOOL, GREEN, "Sturdy Bronze Pick", BLACKSMITHING, 135, 2901, [D],
     [(BRONZE_BAR, 8), (COARSE_GRINDING_STONE, 2), (MEDIUM_LEATHER, 1)]),
    (MINING, ACCESSORY, GREEN, "Bronze Miner's Headlamp", ENGINEERING, 140, 10542, [F, D],
     [(BRONZE_BAR, 4), (BRONZE_TUBE, 1), (LESSER_MOONSTONE, 1)]),
    (MINING, ACCESSORY, GREEN, "Ore Hauler's Satchel", LEATHERWORKING, 130, 2657, [F, P],
     [(HEAVY_LEATHER, 6), (CURED_HEAVY_HIDE, 1), (FINE_THREAD, 2)]),
    (MINING, TOOL, BLUE, "Truesilver Prospector's Pick", BLACKSMITHING, 260, 40893, [F],
     [(THORIUM_BAR, 8), (TRUESILVER_BAR, 2), (DENSE_GRINDING_STONE, 2), (RUGGED_LEATHER, 1)]),
    (MINING, ACCESSORY, BLUE, "Thorium Miner's Headlamp", ENGINEERING, 255, 9375, [P, D],
     [(THORIUM_BAR, 4), (THORIUM_WIDGET, 1), (STAR_RUBY, 1)]),
    (MINING, ACCESSORY, BLUE, "Rugged Ore Satchel", LEATHERWORKING, 255, 38347, [F, D],
     [(RUGGED_LEATHER, 8), (CURED_RUGGED_HIDE, 1), (RUNE_THREAD, 1)]),

    # Skinning: Blacksmithing / Leatherworking / Leatherworking
    (SKINNING, TOOL, GREEN, "Bronze Skinning Knife", BLACKSMITHING, 125, 7005, [F],
     [(BRONZE_BAR, 6), (COARSE_GRINDING_STONE, 2), (MEDIUM_LEATHER, 1)]),
    (SKINNING, ACCESSORY, GREEN, "Skinner's Gloves", LEATHERWORKING, 130, 239, [F, P],
     [(HEAVY_LEATHER, 6), (CURED_HEAVY_HIDE, 1), (FINE_THREAD, 2)]),
    (SKINNING, ACCESSORY, GREEN, "Hide Hauler's Pack", LEATHERWORKING, 145, 856, [P, D],
     [(HEAVY_LEATHER, 8), (FINE_THREAD, 2), (IRON_BUCKLE, 1)]),
    (SKINNING, TOOL, BLUE, "Truesilver Skinning Knife", BLACKSMITHING, 255, 12709, [P],
     [(THORIUM_BAR, 6), (TRUESILVER_BAR, 2), (DENSE_GRINDING_STONE, 1), (RUGGED_LEATHER, 1)]),
    (SKINNING, ACCESSORY, BLUE, "Rugged Skinner's Gloves", LEATHERWORKING, 255, 2992, [F, D],
     [(RUGGED_LEATHER, 8), (CURED_RUGGED_HIDE, 1), (RUNE_THREAD, 1)]),
    (SKINNING, ACCESSORY, BLUE, "Rugged Hide Pack", LEATHERWORKING, 270, 1685, [F, P],
     [(RUGGED_LEATHER, 10), (RUNE_THREAD, 2), (CURED_RUGGED_HIDE, 1)]),

    # Tailoring: Engineering / Blacksmithing / Tailoring
    (TAILORING, TOOL, GREEN, "Clockwork Sewing Kit", ENGINEERING, 125, 2760, [R],
     [(BRONZE_TUBE, 1), (WHIRRING_BRONZE_GIZMO, 1), (BOLT_OF_SILK, 1)]),
    (TAILORING, ACCESSORY, GREEN, "Steel Sewing Needles", BLACKSMITHING, 135, 27631, [R, S],
     [(STEEL_BAR, 3), (SILVER_BAR, 1), (HEAVY_GRINDING_STONE, 1)]),
    (TAILORING, ACCESSORY, GREEN, "Tailor's Silk Apron", TAILORING, 145, 6241, [M, S],
     [(BOLT_OF_SILK, 3), (SILKEN_THREAD, 2), (SPIDERS_SILK, 1)]),
    (TAILORING, TOOL, BLUE, "Gyromatic Sewing Kit", ENGINEERING, 260, 23774, [S],
     [(THORIUM_WIDGET, 2), (MITHRIL_CASING, 1), (BOLT_OF_RUNECLOTH, 1)]),
    (TAILORING, ACCESSORY, BLUE, "Truesilver Sewing Needles", BLACKSMITHING, 260, 25873, [M, R],
     [(THORIUM_BAR, 3), (TRUESILVER_BAR, 2), (DENSE_GRINDING_STONE, 1)]),
    (TAILORING, ACCESSORY, BLUE, "Mooncloth Tailor's Robe", TAILORING, 275, 7054, [R, S],
     [(BOLT_OF_RUNECLOTH, 4), (MOONCLOTH, 1), (RUNE_THREAD, 2)]),

    # Cooking: Blacksmithing / Tailoring
    (COOKING, TOOL, GREEN, "Iron Kitchen Cleaver", BLACKSMITHING, 130, 1292, [S],
     [(IRON_BAR, 4), (HEAVY_GRINDING_STONE, 1), (MEDIUM_LEATHER, 1)]),
    (COOKING, ACCESSORY, GREEN, "Cook's Silk Apron", TAILORING, 125, 2957, [M, S],
     [(BOLT_OF_SILK, 2), (FINE_THREAD, 2)]),
    (COOKING, TOOL, BLUE, "Thorium Kitchen Knives", BLACKSMITHING, 255, 44464, [M],
     [(THORIUM_BAR, 6), (TRUESILVER_BAR, 1), (DENSE_GRINDING_STONE, 1)]),
    (COOKING, ACCESSORY, BLUE, "Runecloth Chef's Hat", TAILORING, 255, 46349, [R, S],
     [(BOLT_OF_RUNECLOTH, 3), (RUNE_THREAD, 1)]),
]


def _description(skill, kind, bonus, stats, totem, counts_as):
    parts = []
    if bonus:
        parts.append("+%d skill" % bonus)
    parts += ["+%d%% %s" % (v, STAT_LABELS[k]) for k, v in stats.items()]
    text = "%s %s: %s." % (SKILL_NAMES[skill], "tool" if kind == TOOL else "accessory", ", ".join(parts))
    if totem:
        text += " Counts as a %s." % TOTEM_CATEGORY_NAMES[totem]
    if counts_as:
        text += " Counts as a %s." % COUNTS_AS_NAMES[counts_as]
    return text


def _build():
    items = []
    for n, (skill, kind, tier, name, crafter, learn, look, stat_names, reagents) in enumerate(_ROWS):
        assert crafter in CRAFTERS, name
        assert len(reagents) <= 8, name
        stats = stats_of(kind, tier, stat_names)
        allowed = {F, P, D} if skill in GATHERING else {M, R, S}
        assert set(stats) <= allowed, name
        bonus = skill_bonus_of(kind, tier)
        totem = TOOL_TOTEM_CATEGORY.get(skill, {}).get(tier, 0) if kind == TOOL else 0
        counts_as = TOOL_COUNTS_AS.get(skill, 0) if kind == TOOL else 0
        yellow, grey = trivial(tier, learn)
        t = TIERS[tier]
        items.append(dict(
            entry=ITEM_FIRST + n, spell=SPELL_FIRST + n, skill=skill, kind=kind, tier=tier,
            name=name, crafter=crafter, learn=learn, yellow=yellow, grey=grey, look=look,
            stats={c: stats.get(c, 0) for c in STAT_COLUMNS}, skill_bonus=bonus,
            totem_category=totem, counts_as=counts_as, reagents=list(reagents),
            quality=t["quality"], required_rank=t["rank"], item_level=t["item_level"],
            sell_price=t["sell"][kind], template=RECIPE_TEMPLATES[crafter][tier],
            description=_description(skill, kind, bonus, stats, totem, counts_as),
        ))
    return items


ITEMS = _build()


def _check():
    assert len(ITEMS) == 70
    assert ITEMS[-1]["entry"] <= ITEM_LAST and ITEMS[-1]["spell"] <= SPELL_LAST
    assert len({i["name"] for i in ITEMS}) == len(ITEMS)
    for skill in PROFESSIONS:
        mine = [i for i in ITEMS if i["skill"] == skill]
        want = 4 if skill == COOKING else 6
        assert len(mine) == want, (skill, len(mine))
        for tier in (GREEN, BLUE):
            kinds = sorted(i["kind"] for i in mine if i["tier"] == tier)
            assert kinds == ([TOOL, ACCESSORY] if skill == COOKING else [TOOL, ACCESSORY, ACCESSORY]), (skill, tier)
    for i in ITEMS:
        assert len(i["description"]) <= 255
        lo, hi = (125, 150) if i["tier"] == GREEN else (250, 275)
        assert lo <= i["learn"] <= hi, i["name"]


_check()
