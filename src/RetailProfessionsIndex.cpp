/*
 * mod-retail-professions: every recipe of every profession, and where each one is learned.
 *
 * Built once at startup from data the core already has in memory (SkillLineAbility.dbc, spells,
 * trainers, vendors, quests, item templates and spawns) plus four world DB tables the core
 * doesn't keep in a readable form (the loot tables and skill_discovery_template).
 *
 * Who sees what:
 *   - L lists recipes the player's race and class can learn and that something teaches to
 *     their faction; the addon hides those past the skill cap HELLO sends.
 *   - W lists sources the player could use: friendly trainers and vendors, quests for their
 *     race, and nothing on a continent mod-individual-progression hasn't opened for them.
 */

#include "RetailProfessions.h"
#include "Chat.h"
#include "CreatureData.h"
#include "DBCStores.h"
#include "DatabaseEnv.h"
#include "GameObjectData.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "MapMgr.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "StringFormat.h"
#include "Timer.h"
#include "Trainer.h"
#include "World.h"
#include "WorldPacket.h"
#include "WorldSession.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <unordered_map>
#include <unordered_set>

namespace RetailProfessions::Index
{
    namespace
    {
        // Skill lines with a trade skill window.
        constexpr std::array<uint32, 12> PROFESSIONS = {
            171, // Alchemy
            164, // Blacksmithing
            333, // Enchanting
            202, // Engineering
            773, // Inscription
            755, // Jewelcrafting
            165, // Leatherworking
            197, // Tailoring
            186, // Mining (Smelting)
            185, // Cooking
            129, // First Aid
            776, // Runeforging
        };

        constexpr uint32 RACEMASK_ALLIANCE = 1101; // human, dwarf, night elf, gnome, draenei
        constexpr uint32 RACEMASK_HORDE = 690;     // orc, undead, tauren, troll, blood elf

        constexpr uint8 TEAMBIT_ALLIANCE = 1;
        constexpr uint8 TEAMBIT_HORDE = 2;
        constexpr uint8 TEAMBIT_BOTH = TEAMBIT_ALLIANCE | TEAMBIT_HORDE;

        // Spawns kept per trainer or vendor (enough to find a near one) and per drop source.
        constexpr std::size_t MAX_SPAWNS = 8;
        constexpr std::size_t MAX_DROP_SPAWNS = 3;

        constexpr uint32 MAP_OUTLAND = 530;
        constexpr uint32 MAP_EBON_HOLD = 609;
        constexpr uint32 ZONE_ISLE_OF_QUEL_DANAS = 4080;
        constexpr std::array<uint32, 6> ZONES_OPEN_ON_OUTLAND_MAP = {
            3430, // Eversong Woods
            3433, // Ghostlands
            3487, // Silvermoon City
            3524, // Azuremyst Isle
            3525, // Bloodmyst Isle
            3557, // The Exodar
        };
        constexpr uint8 IP_STATE_TBC = 8;
        constexpr uint8 IP_STATE_QUEL_DANAS = 12;
        constexpr uint8 IP_STATE_WOTLK = 13;

        // What the map marker looks like: the red flag city guards use.
        constexpr uint32 POI_FLAGS = 99;
        constexpr uint32 POI_ICON_RED_FLAG = 7;

        struct TrainerSource
        {
            uint32 creature = 0;
            uint32 cost = 0;
            uint32 reqSkill = 0;
            std::array<uint32, 3> reqAbility = {}; // e.g. a specialization: Goblin Engineer, Armorsmith
        };

        // A SkillLineAbility row that teaches the recipe by itself, for the races and classes in it.
        struct AutoRow
        {
            uint32 raceMask = 0;
            uint32 classMask = 0;
            uint32 skill = 0;    // learned on reaching it (AcquireMethod 1); 0 = with the profession
        };

        struct DiscoverySource
        {
            uint32 fromSpell = 0; // 0 = any craft of the profession
            uint32 reqSkill = 0;
            uint32 chance = 0;    // percent x100
        };

        struct Recipe
        {
            uint32 spell = 0;
            uint32 skill = 0;
            uint32 reqSkill = 0;
            uint32 yellow = 0;
            uint32 grey = 0;
            uint32 raceMask = 0;
            uint32 classMask = 0;
            uint32 item = 0;
            uint32 madeMin = 1;
            uint32 madeMax = 1;
            uint32 invType = 0;
            uint32 quality = 1;
            std::string reagents = "-";
            bool targetsItem = false; // cast on an item: enchants, sockets, buckles, linings, embroidery
            uint8 sources = 0;
            uint8 teams = 0;
            std::vector<AutoRow> autoRows;
            std::vector<TrainerSource> trainers;
            std::vector<uint32> recipeItems;
            std::vector<uint32> quests;
            std::vector<DiscoverySource> discoveries;
        };

        struct Drop
        {
            uint32 id = 0;
            uint32 chance = 0; // percent x100, 0 = unknown (a share of a loot group)
        };

        struct Vendor
        {
            uint32 creature = 0;
            uint32 maxcount = 0;
            bool gold = true;
        };

        struct ItemSources
        {
            std::vector<Vendor> vendors;
            std::vector<Drop> creatures;
            std::vector<Drop> objects;
            std::vector<Drop> containers;
            std::vector<uint32> quests;
            uint32 worldDropCreatures = 0;
            uint32 worldMinLevel = 0;
            uint32 worldMaxLevel = 0;
            uint8 teams = 0;
        };

        struct Spawn
        {
            uint32 map = 0;
            uint32 zone = 0;
            uint32 area = 0;
            float x = 0.0f;
            float y = 0.0f;
            uint32 phaseMask = 1;
        };

        struct Data
        {
            std::unordered_map<uint32, Recipe> recipes;
            std::unordered_map<uint32, std::vector<uint32>> bySkill;
            std::unordered_map<uint32, ItemSources> items;
            std::unordered_map<uint32, std::vector<Spawn>> creatureSpawns;
            std::unordered_map<uint32, std::vector<Spawn>> objectSpawns;
            std::unordered_set<uint32> spawnedCreatures; // every creature entry with a spawn
            uint32 stamp = 0;
        };

        Data sData;

        // ---- small helpers ---------------------------------------------------------------------

        char const* DbcString(char const* const (&names)[16])
        {
            char const* name = names[sWorld->GetDefaultDbcLocale()];
            return name && *name ? name : names[LOCALE_enUS];
        }

        char const* DbcString(std::array<char const*, 16> const& names)
        {
            char const* name = names[sWorld->GetDefaultDbcLocale()];
            return name && *name ? name : names[LOCALE_enUS];
        }

        std::string AreaName(uint32 areaId)
        {
            if (AreaTableEntry const* area = sAreaTableStore.LookupEntry(areaId))
                return DbcString(area->area_name);
            return "";
        }

        std::string MapName(uint32 mapId)
        {
            if (MapEntry const* map = sMapStore.LookupEntry(mapId))
                return DbcString(map->name);
            return "";
        }

        // Where a spawn is, in words: "Stormwind City" or "Scholomance".
        std::string PlaceName(Spawn const& spawn)
        {
            if (spawn.zone)
                return AreaName(spawn.zone);
            return MapName(spawn.map);
        }

        // A spell that teaches another (a trainer's or quest's "learning" spell) -> the spell it
        // teaches; anything else -> itself.
        uint32 TaughtSpell(uint32 spellId)
        {
            SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId);
            if (!info)
                return spellId;
            for (SpellEffectInfo const& effect : info->GetEffects())
                if (effect.Effect == SPELL_EFFECT_LEARN_SPELL && effect.TriggerSpell)
                    return effect.TriggerSpell;
            return spellId;
        }

        uint8 TeamsOfRaceMask(uint32 raceMask)
        {
            if (!raceMask)
                return TEAMBIT_BOTH;
            uint8 teams = 0;
            if (raceMask & RACEMASK_ALLIANCE)
                teams |= TEAMBIT_ALLIANCE;
            if (raceMask & RACEMASK_HORDE)
                teams |= TEAMBIT_HORDE;
            return teams;
        }

        uint8 TeamsOfFaction(uint32 factionTemplate)
        {
            FactionTemplateEntry const* faction = sFactionTemplateStore.LookupEntry(factionTemplate);
            if (!faction)
                return TEAMBIT_BOTH;
            uint8 teams = 0;
            if (!faction->IsHostileToAlliancePlayers())
                teams |= TEAMBIT_ALLIANCE;
            if (!faction->IsHostileToHordePlayers())
                teams |= TEAMBIT_HORDE;
            return teams;
        }

        uint8 TeamOf(Player* player)
        {
            return player->GetTeamId() == TEAM_ALLIANCE ? TEAMBIT_ALLIANCE : TEAMBIT_HORDE;
        }

        std::string JoinIds(std::vector<uint32> const& ids, std::size_t from, std::size_t count)
        {
            std::string out;
            for (std::size_t i = from; i < ids.size() && i < from + count; ++i)
            {
                if (!out.empty())
                    out += ',';
                out += std::to_string(ids[i]);
            }
            return out;
        }

        // Runs `sql` (with one {} for an id list) over ids in chunks.
        template <typename Fn>
        void QueryByIds(std::string_view sql, std::vector<uint32> const& ids, Fn&& onRow)
        {
            constexpr std::size_t CHUNK = 400;
            for (std::size_t from = 0; from < ids.size(); from += CHUNK)
            {
                std::string query = Acore::StringFormat(sql, JoinIds(ids, from, CHUNK));
                if (QueryResult result = WorldDatabase.Query(query))
                    do
                    {
                        onRow(result->Fetch());
                    } while (result->NextRow());
            }
        }

        template <typename T>
        std::vector<uint32> Keys(std::unordered_set<T> const& set)
        {
            std::vector<uint32> out(set.begin(), set.end());
            std::sort(out.begin(), out.end());
            return out;
        }

        // ---- building --------------------------------------------------------------------------

        void ReadRecipes()
        {
            for (uint32 skill : PROFESSIONS)
            {
                for (SkillLineAbilityEntry const* ability : GetSkillLineAbilitiesBySkillLine(skill))
                {
                    SpellInfo const* info = sSpellMgr->GetSpellInfo(ability->Spell);
                    if (!info || !info->HasAttribute(SPELL_ATTR0_IS_TRADESKILL))
                        continue;

                    auto [itr, isNew] = sData.recipes.try_emplace(ability->Spell);
                    Recipe& recipe = itr->second;
                    // Faction- or class-specific rows may teach the recipe by themselves (First Aid
                    // for death knights), so every such row is kept.
                    if (ability->AcquireMethod == SKILL_LINE_ABILITY_LEARNED_ON_SKILL_VALUE
                        || ability->AcquireMethod == SKILL_LINE_ABILITY_LEARNED_ON_SKILL_LEARN)
                        recipe.autoRows.push_back({ ability->RaceMask, ability->ClassMask,
                            ability->AcquireMethod == SKILL_LINE_ABILITY_LEARNED_ON_SKILL_VALUE ? std::max<uint32>(1, ability->MinSkillLineRank) : 0 });
                    if (!isNew)
                    {
                        // Race-specific rows of the same recipe: any unrestricted row wins.
                        recipe.raceMask = (recipe.raceMask && ability->RaceMask) ? (recipe.raceMask | ability->RaceMask) : 0;
                        recipe.classMask = (recipe.classMask && ability->ClassMask) ? (recipe.classMask | ability->ClassMask) : 0;
                        continue;
                    }

                    recipe.spell = ability->Spell;
                    recipe.skill = skill;
                    recipe.reqSkill = ability->MinSkillLineRank;
                    recipe.yellow = ability->TrivialSkillLineRankLow;
                    recipe.grey = ability->TrivialSkillLineRankHigh;
                    recipe.raceMask = ability->RaceMask;
                    recipe.classMask = ability->ClassMask;

                    for (SpellEffectInfo const& effect : info->GetEffects())
                        if (effect.Effect == SPELL_EFFECT_ENCHANT_ITEM || effect.Effect == SPELL_EFFECT_ENCHANT_ITEM_TEMPORARY
                            || effect.Effect == SPELL_EFFECT_ENCHANT_ITEM_PRISMATIC || effect.Effect == SPELL_EFFECT_ENCHANT_HELD_ITEM)
                            recipe.targetsItem = true;

                    for (SpellEffectInfo const& effect : info->GetEffects())
                    {
                        if ((effect.Effect == SPELL_EFFECT_CREATE_ITEM || effect.Effect == SPELL_EFFECT_CREATE_ITEM_2) && effect.ItemType)
                        {
                            recipe.item = effect.ItemType;
                            int32 low = effect.BasePoints + (effect.DieSides > 0 ? 1 : 0);
                            int32 high = effect.BasePoints + effect.DieSides;
                            recipe.madeMin = uint32(std::max(1, low));
                            recipe.madeMax = uint32(std::max(low, high));
                            recipe.madeMax = std::max(recipe.madeMax, recipe.madeMin);
                            break;
                        }
                    }

                    if (recipe.item)
                        if (ItemTemplate const* product = sObjectMgr->GetItemTemplate(recipe.item))
                        {
                            recipe.invType = product->InventoryType;
                            recipe.quality = product->Quality;
                        }

                    std::string reagents;
                    for (std::size_t i = 0; i < info->Reagent.size(); ++i)
                    {
                        if (info->Reagent[i] <= 0 || !info->ReagentCount[i])
                            continue;
                        if (!reagents.empty())
                            reagents += '/';
                        reagents += std::to_string(info->Reagent[i]) + "*" + std::to_string(info->ReagentCount[i]);
                    }
                    recipe.reagents = reagents.empty() ? "-" : reagents;

                    sData.bySkill[skill].push_back(recipe.spell);
                }
            }
        }

        void ReadTrainers(std::unordered_set<uint32>& creatures)
        {
            for (auto const& [entry, creature] : *sObjectMgr->GetCreatureTemplates())
            {
                Trainer::Trainer* trainer = sObjectMgr->GetTrainer(entry);
                if (!trainer || trainer->GetTrainerType() != Trainer::Type::Tradeskill)
                    continue;

                for (Trainer::Spell const& spell : trainer->GetSpells())
                {
                    auto itr = sData.recipes.find(TaughtSpell(spell.SpellId));
                    if (itr == sData.recipes.end())
                        continue;
                    itr->second.trainers.push_back({ entry, spell.MoneyCost, spell.ReqSkillRank, spell.ReqAbility });
                    creatures.insert(entry);
                }
            }
        }

        // Recipe items: the "Pattern: ..." that teaches a spell when used.
        void ReadRecipeItems(std::unordered_set<uint32>& recipeItems)
        {
            for (auto const& [entry, item] : *sObjectMgr->GetItemTemplateStore())
            {
                if (item.Class != ITEM_CLASS_RECIPE)
                    continue;

                for (auto const& spell : item.Spells)
                {
                    if (spell.SpellId <= 0)
                        continue;
                    uint32 taught = spell.SpellTrigger == ITEM_SPELLTRIGGER_LEARN_SPELL_ID ? uint32(spell.SpellId) : TaughtSpell(spell.SpellId);
                    auto itr = sData.recipes.find(taught);
                    if (itr == sData.recipes.end())
                        continue;
                    if (std::find(itr->second.recipeItems.begin(), itr->second.recipeItems.end(), entry) == itr->second.recipeItems.end())
                        itr->second.recipeItems.push_back(entry);
                    recipeItems.insert(entry);
                }
            }
        }

        void ReadVendors(std::unordered_set<uint32> const& recipeItems, std::unordered_set<uint32>& creatures)
        {
            for (auto const& [entry, creature] : *sObjectMgr->GetCreatureTemplates())
            {
                VendorItemData const* vendor = sObjectMgr->GetNpcVendorItemList(entry);
                if (!vendor || vendor->Empty())
                    continue;

                for (VendorItem const* item : vendor->m_items)
                {
                    if (!item || !recipeItems.count(item->item))
                        continue;
                    ItemTemplate const* proto = sObjectMgr->GetItemTemplate(item->item);
                    sData.items[item->item].vendors.push_back({ entry, item->maxcount, !proto || item->IsGoldRequired(proto) });
                    creatures.insert(entry);
                }
            }
        }

        void ReadQuests(std::unordered_set<uint32> const& recipeItems)
        {
            for (auto const& [id, quest] : sObjectMgr->GetQuestTemplates())
            {
                for (uint32 item : quest->RewardItemId)
                    if (item && recipeItems.count(item))
                        sData.items[item].quests.push_back(id);
                for (uint32 item : quest->RewardChoiceItemId)
                    if (item && recipeItems.count(item))
                        sData.items[item].quests.push_back(id);

                std::array<uint32, 2> spells = { uint32(std::max(0, quest->GetRewSpellCast())), quest->GetRewSpell() };
                for (uint32 spell : spells)
                {
                    if (!spell)
                        continue;
                    auto itr = sData.recipes.find(TaughtSpell(spell));
                    if (itr != sData.recipes.end()
                        && std::find(itr->second.quests.begin(), itr->second.quests.end(), id) == itr->second.quests.end())
                        itr->second.quests.push_back(id);
                }
            }
        }

        // The loot tables: which creatures, chests and containers can hold a recipe item, directly
        // or through reference tables. A reference shared by many creatures is a world drop.
        void ReadLoot(std::unordered_set<uint32> const& recipeItemSet, std::unordered_set<uint32>& creatures,
            std::unordered_set<uint32>& objects)
        {
            std::vector<uint32> recipeItems = Keys(recipeItemSet);
            if (recipeItems.empty())
                return;

            // Loot ids -> what uses them.
            std::unordered_map<uint32, std::vector<uint32>> creaturesByLoot;
            for (auto const& [entry, creature] : *sObjectMgr->GetCreatureTemplates())
                if (creature.lootid)
                    creaturesByLoot[creature.lootid].push_back(entry);

            std::unordered_map<uint32, std::vector<uint32>> objectsByLoot;
            for (auto const& [entry, object] : *sObjectMgr->GetGameObjectTemplates())
                if (uint32 loot = object.GetLootId())
                    objectsByLoot[loot].push_back(entry);

            // reference id -> (recipe item, chance) it can roll, following nested references.
            std::unordered_map<uint32, std::vector<Drop>> refItems;
            QueryByIds("SELECT CAST(Entry AS UNSIGNED), CAST(Item AS UNSIGNED), CAST(ROUND(ABS(Chance) * 100) AS UNSIGNED) "
                "FROM reference_loot_template WHERE Reference = 0 AND Item IN ({})", recipeItems,
                [&](Field* f) { refItems[uint32(f[0].Get<uint64>())].push_back({ uint32(f[1].Get<uint64>()), uint32(f[2].Get<uint64>()) }); });

            std::vector<uint32> frontier;
            for (auto const& [ref, drops] : refItems)
                frontier.push_back(ref);
            for (int depth = 0; depth < 4 && !frontier.empty(); ++depth)
            {
                std::vector<std::pair<uint32, uint32>> parents; // parent ref, child ref
                QueryByIds("SELECT CAST(Entry AS UNSIGNED), CAST(Reference AS UNSIGNED) FROM reference_loot_template "
                    "WHERE Reference IN ({})", frontier,
                    [&](Field* f) { parents.emplace_back(uint32(f[0].Get<uint64>()), uint32(f[1].Get<uint64>())); });
                frontier.clear();
                for (auto const& [parent, child] : parents)
                {
                    std::vector<Drop> childDrops = refItems[child];
                    bool isNew = !refItems.count(parent);
                    std::vector<Drop>& into = refItems[parent];
                    for (Drop const& drop : childDrops)
                        into.push_back({ drop.id, 0 });
                    if (isNew)
                        frontier.push_back(parent);
                }
            }

            std::vector<uint32> refs;
            for (auto const& [ref, drops] : refItems)
                refs.push_back(ref);

            // Per item: creature entry -> best chance, and the creatures reached via references.
            std::unordered_map<uint32, std::unordered_map<uint32, uint32>> creatureDrops;
            std::unordered_map<uint32, std::unordered_set<uint32>> refCreatures;
            std::unordered_map<uint32, std::unordered_map<uint32, uint32>> objectDrops;
            std::unordered_map<uint32, std::unordered_map<uint32, uint32>> containerDrops;

            auto addDrop = [](auto& into, uint32 item, uint32 id, uint32 chance)
            {
                uint32& best = into[item][id];
                best = std::max(best, chance);
            };

            auto readTable = [&](char const* table, auto&& onDrop)
            {
                QueryByIds(Acore::StringFormat("SELECT CAST(Entry AS UNSIGNED), CAST(Item AS UNSIGNED), "
                    "CAST(ROUND(ABS(Chance) * 100) AS UNSIGNED) FROM {} WHERE Reference = 0 AND Item IN ({{}})", table),
                    recipeItems,
                    [&](Field* f) { onDrop(uint32(f[0].Get<uint64>()), uint32(f[1].Get<uint64>()), uint32(f[2].Get<uint64>()), false); });
                if (refs.empty())
                    return;
                QueryByIds(Acore::StringFormat("SELECT CAST(Entry AS UNSIGNED), CAST(Reference AS UNSIGNED), "
                    "CAST(ROUND(ABS(Chance) * 100) AS UNSIGNED) FROM {} WHERE Reference IN ({{}})", table),
                    refs,
                    [&](Field* f)
                    {
                        uint32 loot = uint32(f[0].Get<uint64>());
                        uint32 refChance = uint32(f[2].Get<uint64>());
                        for (Drop const& drop : refItems[uint32(f[1].Get<uint64>())])
                            onDrop(loot, drop.id, drop.chance && refChance ? drop.chance * refChance / 10000 : 0, true);
                    });
            };

            readTable("creature_loot_template", [&](uint32 loot, uint32 item, uint32 chance, bool viaRef)
            {
                auto itr = creaturesByLoot.find(loot);
                if (itr == creaturesByLoot.end())
                    return;
                for (uint32 creature : itr->second)
                {
                    if (viaRef)
                        refCreatures[item].insert(creature);
                    else
                        addDrop(creatureDrops, item, creature, chance);
                }
            });

            readTable("gameobject_loot_template", [&](uint32 loot, uint32 item, uint32 chance, bool)
            {
                auto itr = objectsByLoot.find(loot);
                if (itr == objectsByLoot.end())
                    return;
                for (uint32 object : itr->second)
                    addDrop(objectDrops, item, object, chance);
            });

            readTable("item_loot_template", [&](uint32 container, uint32 item, uint32 chance, bool)
            {
                addDrop(containerDrops, item, container, chance);
            });

            // Shared tables reach many templates that never spawn (event, test and unused ones);
            // only spawned creatures count, for the size of a world drop and its level range.
            for (auto& [item, all] : refCreatures)
            {
                std::vector<uint32> list;
                for (uint32 entry : all)
                    if (sData.spawnedCreatures.count(entry))
                        list.push_back(entry);
                ItemSources& sources = sData.items[item];
                if (list.size() > GetConfig().worldDropThreshold)
                {
                    sources.worldDropCreatures = uint32(list.size());
                    sources.worldMinLevel = 255;
                    for (uint32 entry : list)
                        if (CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(entry))
                        {
                            sources.worldMinLevel = std::min<uint32>(sources.worldMinLevel, creature->minlevel);
                            sources.worldMaxLevel = std::max<uint32>(sources.worldMaxLevel, creature->maxlevel);
                        }
                }
                else
                    for (uint32 entry : (list.empty() ? std::vector<uint32>(all.begin(), all.end()) : list))
                        addDrop(creatureDrops, item, entry, 0);
            }

            auto store = [](auto const& from, std::vector<Drop> ItemSources::*member, std::unordered_set<uint32>* interesting)
            {
                for (auto const& [item, byId] : from)
                {
                    std::vector<Drop>& into = sData.items[item].*member;
                    for (auto const& [id, chance] : byId)
                    {
                        into.push_back({ id, chance });
                        if (interesting)
                            interesting->insert(id);
                    }
                    std::sort(into.begin(), into.end(), [](Drop const& a, Drop const& b)
                        { return a.chance != b.chance ? a.chance > b.chance : a.id < b.id; });
                }
            };
            store(creatureDrops, &ItemSources::creatures, &creatures);
            store(objectDrops, &ItemSources::objects, &objects);
            store(containerDrops, &ItemSources::containers, nullptr);
        }

        void ReadDiscoveries()
        {
            QueryResult result = WorldDatabase.Query("SELECT CAST(spellId AS UNSIGNED), CAST(reqSpell AS SIGNED), "
                "CAST(reqSkillValue AS UNSIGNED), CAST(ROUND(chance * 100) AS UNSIGNED) FROM skill_discovery_template");
            if (!result)
                return;
            do
            {
                Field* f = result->Fetch();
                auto itr = sData.recipes.find(uint32(f[0].Get<uint64>()));
                if (itr == sData.recipes.end())
                    continue;
                // The core never rolls a discovery without a chance.
                if (!f[3].Get<uint64>())
                    continue;
                int64 reqSpell = f[1].Get<int64>();
                itr->second.discoveries.push_back({ reqSpell > 0 ? uint32(reqSpell) : 0, uint32(f[2].Get<uint64>()),
                    uint32(f[3].Get<uint64>()) });
            } while (result->NextRow());
        }

        void LoadSavedZones(std::unordered_map<uint32, std::pair<uint32, uint32>>& zones, char const* table)
        {
            if (QueryResult result = WorldDatabase.Query("SELECT CAST(guid AS UNSIGNED), CAST(zoneId AS UNSIGNED), "
                "CAST(areaId AS UNSIGNED) FROM {} WHERE zoneId <> 0", table))
                do
                {
                    Field* fields = result->Fetch();
                    zones[uint32(fields[0].Get<uint64>())] = { uint32(fields[1].Get<uint64>()), uint32(fields[2].Get<uint64>()) };
                } while (result->NextRow());
        }

        void CollectSpawnedCreatures()
        {
            for (auto const& [spawnId, data] : sObjectMgr->GetAllCreatureData())
                sData.spawnedCreatures.insert(data.id);
        }

        // Spawns of each trainer, vendor (MAX_SPAWNS, to find a near one), dropping creature and
        // object (a few, for the zone), with their zones: saved in the database, or worked out
        // from the map files (and saved for next time). Dungeons are named after their map instead.
        void ReadSpawns(std::unordered_set<uint32> const& service, std::unordered_set<uint32> const& droppers,
            std::unordered_set<uint32> const& objects)
        {
            std::unordered_map<uint32, std::pair<uint32, uint32>> savedCreatures;
            std::unordered_map<uint32, std::pair<uint32, uint32>> savedObjects;
            LoadSavedZones(savedCreatures, "creature");
            LoadSavedZones(savedObjects, "gameobject");

            WorldDatabaseTransaction trans = WorldDatabase.BeginTransaction();
            uint32 computed = 0;

            auto place = [&](SpawnData const& data, std::unordered_map<uint32, std::pair<uint32, uint32>> const& saved,
                char const* table)
            {
                Spawn spawn;
                spawn.map = data.mapid;
                spawn.x = data.posX;
                spawn.y = data.posY;
                spawn.phaseMask = data.phaseMask;
                MapEntry const* map = sMapStore.LookupEntry(data.mapid);
                if (!map || map->Instanceable())
                    return spawn;

                auto itr = saved.find(data.spawnId);
                if (itr != saved.end())
                    std::tie(spawn.zone, spawn.area) = itr->second;
                else
                {
                    sMapMgr->GetZoneAndAreaId(data.phaseMask, spawn.zone, spawn.area, data.mapid, data.posX, data.posY, data.posZ);
                    // A first start may load a lot of terrain here, before the world loop runs:
                    // keep the freeze detector (MaxCoreStuckTime) from taking it for a hang.
                    if (++computed % 200 == 0)
                        ++World::m_worldLoopCounter;
                    if (GetConfig().saveZoneData && spawn.zone)
                        trans->Append("UPDATE {} SET zoneId = {}, areaId = {} WHERE guid = {}", table, spawn.zone, spawn.area, data.spawnId);
                }
                return spawn;
            };

            for (auto const& [spawnId, data] : sObjectMgr->GetAllCreatureData())
            {
                std::size_t keep = service.count(data.id) ? MAX_SPAWNS : droppers.count(data.id) ? MAX_DROP_SPAWNS : 0;
                if (!keep)
                    continue;
                std::vector<Spawn>& spawns = sData.creatureSpawns[data.id];
                if (spawns.size() < keep)
                    spawns.push_back(place(data, savedCreatures, "creature"));
            }

            for (auto const& [spawnId, data] : sObjectMgr->GetAllGOData())
            {
                if (!objects.count(data.id))
                    continue;
                std::vector<Spawn>& spawns = sData.objectSpawns[data.id];
                if (spawns.size() < MAX_DROP_SPAWNS)
                    spawns.push_back(place(data, savedObjects, "gameobject"));
            }

            if (trans->GetSize())
                WorldDatabase.CommitTransaction(trans);

            LOG_INFO("server.loading", ">> mod-retail-professions: {} sources spawned; worked out {} zones",
                sData.creatureSpawns.size() + sData.objectSpawns.size(), computed);
        }

        bool Spawned(uint32 creature)
        {
            return sData.creatureSpawns.count(creature) != 0;
        }

        // Drops nobody can reach (templates never spawned), unless nothing else drops the item:
        // a summoned boss is still a source.
        void PruneUnspawned(std::vector<Drop>& drops, std::unordered_map<uint32, std::vector<Spawn>> const& spawns)
        {
            bool anySpawned = std::any_of(drops.begin(), drops.end(), [&](Drop const& d) { return spawns.count(d.id) != 0; });
            if (anySpawned)
                drops.erase(std::remove_if(drops.begin(), drops.end(), [&](Drop const& d) { return !spawns.count(d.id); }), drops.end());
            else if (drops.size() > 3)
                drops.resize(3);
        }

        // The skill a recipe needs. SkillLineAbility's MinSkillLineRank is 1 for nearly every
        // recipe (it only means something for recipes learned on reaching a skill), so the need
        // comes from what teaches it: the trainer's rank, the recipe item's required skill, the
        // discovery's skill. Without any of those, the yellow threshold is the closest guess.
        uint32 RequiredSkill(Recipe const& recipe)
        {
            uint32 need = std::numeric_limits<uint32>::max();
            auto consider = [&](uint32 value) { if (value) need = std::min(need, value); };
            for (TrainerSource const& t : recipe.trainers)
                consider(t.reqSkill);
            for (uint32 entry : recipe.recipeItems)
            {
                auto itr = sData.items.find(entry);
                ItemTemplate const* item = sObjectMgr->GetItemTemplate(entry);
                if (item && itr != sData.items.end() && itr->second.teams)
                    consider(item->RequiredSkillRank);
            }
            for (DiscoverySource const& d : recipe.discoveries)
                consider(d.reqSkill);
            for (AutoRow const& row : recipe.autoRows)
                consider(row.skill ? row.skill : 1);
            if (need != std::numeric_limits<uint32>::max())
                return need;
            if (recipe.reqSkill > 1)
                return recipe.reqSkill;
            return std::max<uint32>(1, recipe.yellow);
        }

        // Which factions can get at each item and recipe, now that spawns are known.
        void Finish()
        {
            for (auto& [entry, sources] : sData.items)
            {
                sources.vendors.erase(std::remove_if(sources.vendors.begin(), sources.vendors.end(),
                    [](Vendor const& v) { return !Spawned(v.creature); }), sources.vendors.end());
                PruneUnspawned(sources.creatures, sData.creatureSpawns);
                PruneUnspawned(sources.objects, sData.objectSpawns);

                ItemTemplate const* item = sObjectMgr->GetItemTemplate(entry);
                uint8 itemTeams = item ? TeamsOfRaceMask(item->AllowableRace == uint32(-1) ? 0 : item->AllowableRace) : TEAMBIT_BOTH;

                uint8 reach = 0;
                for (Vendor const& vendor : sources.vendors)
                    if (CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(vendor.creature))
                        reach |= TeamsOfFaction(creature->faction);
                if (!sources.creatures.empty() || !sources.objects.empty() || !sources.containers.empty() || sources.worldDropCreatures)
                    reach |= TEAMBIT_BOTH;
                for (uint32 questId : sources.quests)
                    if (Quest const* quest = sObjectMgr->GetQuestTemplate(questId))
                        reach |= TeamsOfRaceMask(quest->GetAllowableRaces());

                sources.teams = itemTeams & reach;
            }

            for (auto& [spell, recipe] : sData.recipes)
            {
                recipe.trainers.erase(std::remove_if(recipe.trainers.begin(), recipe.trainers.end(),
                    [](TrainerSource const& t) { return !Spawned(t.creature); }), recipe.trainers.end());

                uint8 teams = 0;
                if (!recipe.trainers.empty())
                {
                    recipe.sources |= SRC_TRAINER;
                    for (TrainerSource const& t : recipe.trainers)
                        if (CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(t.creature))
                            teams |= TeamsOfFaction(creature->faction);
                }
                for (uint32 entry : recipe.recipeItems)
                {
                    auto itr = sData.items.find(entry);
                    if (itr != sData.items.end() && itr->second.teams)
                    {
                        recipe.sources |= SRC_ITEM;
                        teams |= itr->second.teams;
                    }
                }
                for (uint32 questId : recipe.quests)
                    if (Quest const* quest = sObjectMgr->GetQuestTemplate(questId))
                    {
                        recipe.sources |= SRC_QUEST;
                        teams |= TeamsOfRaceMask(quest->GetAllowableRaces());
                    }
                if (!recipe.discoveries.empty())
                {
                    recipe.sources |= SRC_DISCOVERY;
                    teams |= TEAMBIT_BOTH;
                }
                if (!recipe.autoRows.empty())
                {
                    recipe.sources |= SRC_AUTO;
                    for (AutoRow const& row : recipe.autoRows)
                        teams |= TeamsOfRaceMask(row.raceMask);
                }
                recipe.teams = teams & TeamsOfRaceMask(recipe.raceMask);
                recipe.reqSkill = RequiredSkill(recipe);
            }

            for (auto& [skill, spells] : sData.bySkill)
                std::sort(spells.begin(), spells.end(), [](uint32 a, uint32 b)
                {
                    Recipe const& ra = sData.recipes.at(a);
                    Recipe const& rb = sData.recipes.at(b);
                    return ra.reqSkill != rb.reqSkill ? ra.reqSkill < rb.reqSkill : a < b;
                });
        }

        std::string ListRow(Recipe const& recipe, uint32 recipeItem)
        {
            return Acore::StringFormat("{},{},{},{},{},{},{},{},{},{},{},{},{}", recipe.spell, recipe.reqSkill, recipe.yellow,
                recipe.grey, recipe.item, recipe.madeMin, recipe.madeMax, uint32(recipe.sources), recipe.reagents,
                recipe.invType, recipe.quality, recipeItem, recipe.targetsItem ? 1 : 0);
        }

        // FNV-1a over everything an L row can carry, so the addon's cache follows the data.
        void ComputeStamp()
        {
            uint32 hash = 2166136261u;
            auto mix = [&](std::string const& text)
            {
                for (unsigned char c : text)
                {
                    hash ^= c;
                    hash *= 16777619u;
                }
            };
            mix(std::to_string(PROTOCOL_VERSION));
            for (uint32 skill : PROFESSIONS)
            {
                auto itr = sData.bySkill.find(skill);
                if (itr == sData.bySkill.end())
                    continue;
                for (uint32 spell : itr->second)
                {
                    Recipe const& recipe = sData.recipes[spell];
                    mix(ListRow(recipe, recipe.recipeItems.empty() ? 0 : recipe.recipeItems.front()));
                    mix(std::to_string(recipe.teams) + ":" + std::to_string(recipe.raceMask) + ":" + std::to_string(recipe.classMask));
                }
            }
            sData.stamp = hash ? hash : 1;
        }

        // ---- who sees what ---------------------------------------------------------------------

        struct Viewer
        {
            Player* player = nullptr;
            FactionTemplateEntry const* faction = nullptr;
            uint8 progression = 18;
            uint8 team = TEAMBIT_BOTH;
            bool everything = false;
        };

        Viewer MakeViewer(Player* player)
        {
            Viewer viewer;
            viewer.player = player;
            viewer.faction = player->GetFactionTemplateEntry();
            viewer.team = TeamOf(player);
            viewer.everything = player->IsGameMaster();
            viewer.progression = ProgressionState(player);
            return viewer;
        }

        bool IsOpen(Viewer const& viewer, Spawn const& spawn)
        {
            if (viewer.everything || !GetConfig().hideLockedContinents)
                return true;

            if (spawn.map == MAP_EBON_HOLD)
                return viewer.player->getClass() == CLASS_DEATH_KNIGHT;

            if (spawn.map == MAP_OUTLAND)
            {
                if (std::find(ZONES_OPEN_ON_OUTLAND_MAP.begin(), ZONES_OPEN_ON_OUTLAND_MAP.end(), spawn.zone) != ZONES_OPEN_ON_OUTLAND_MAP.end())
                    return true;
                if (spawn.zone == ZONE_ISLE_OF_QUEL_DANAS)
                    return viewer.progression >= IP_STATE_QUEL_DANAS;
                return viewer.progression >= IP_STATE_TBC;
            }

            // Dungeons and Northrend by the expansion their map belongs to.
            MapEntry const* map = sMapStore.LookupEntry(spawn.map);
            uint32 expansion = map ? map->Expansion() : 0;
            if (expansion >= 2)
                return viewer.progression >= IP_STATE_WOTLK;
            if (expansion == 1)
                return viewer.progression >= IP_STATE_TBC;
            return true;
        }

        bool IsFriendly(Viewer const& viewer, uint32 factionTemplate)
        {
            if (viewer.everything || !viewer.faction)
                return true;
            FactionTemplateEntry const* faction = sFactionTemplateStore.LookupEntry(factionTemplate);
            if (!faction)
                return true;
            if (faction->IsHostileTo(*viewer.faction))
                return false;
            return viewer.player->GetReputationRank(faction->faction) > REP_HOSTILE;
        }

        bool InPhase(Viewer const& viewer, Spawn const& spawn)
        {
            return (spawn.phaseMask & (PHASEMASK_NORMAL | viewer.player->GetPhaseMask())) != 0;
        }

        // The spawn a player would go to: the nearest on their map, else the first one open to them.
        Spawn const* BestSpawn(Viewer const& viewer, std::vector<Spawn> const* spawns, bool needPhase)
        {
            if (!spawns)
                return nullptr;
            Spawn const* best = nullptr;
            float bestDist = 0.0f;
            for (Spawn const& spawn : *spawns)
            {
                if (!IsOpen(viewer, spawn) || (needPhase && !InPhase(viewer, spawn)))
                    continue;
                float dist = spawn.map == viewer.player->GetMapId()
                    ? viewer.player->GetExactDist2d(spawn.x, spawn.y) : 1e9f;
                if (!best || dist < bestDist)
                {
                    best = &spawn;
                    bestDist = dist;
                }
            }
            return best;
        }

        bool CanUseCreature(Viewer const& viewer, uint32 entry, Spawn const** where)
        {
            CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(entry);
            if (!creature || !IsFriendly(viewer, creature->faction))
                return false;
            auto itr = sData.creatureSpawns.find(entry);
            *where = BestSpawn(viewer, itr != sData.creatureSpawns.end() ? &itr->second : nullptr, true);
            return *where != nullptr;
        }

        // A drop source is shown unless every spawn of it is somewhere the player can't go yet.
        bool DropOpen(Viewer const& viewer, std::unordered_map<uint32, std::vector<Spawn>> const& all, uint32 id, Spawn const** where)
        {
            auto itr = all.find(id);
            if (itr == all.end())
            {
                *where = nullptr;
                return true;
            }
            *where = BestSpawn(viewer, &itr->second, false);
            return *where != nullptr;
        }

        bool MatchesMasks(Player* player, uint32 raceMask, uint32 classMask)
        {
            return (!raceMask || (raceMask & player->getRaceMask())) && (!classMask || (classMask & player->getClassMask()));
        }

        // A recipe item this player could use: their race, their faction's sources, and the
        // specialization it needs (Gnomish/Goblin Engineer, Armorsmith ...).
        bool PlayerMayUseItem(Player* player, uint32 entry)
        {
            ItemTemplate const* item = sObjectMgr->GetItemTemplate(entry);
            if (!item)
                return false;
            if (item->AllowableRace && item->AllowableRace != uint32(-1) && !(item->AllowableRace & player->getRaceMask()))
                return false;
            if (item->AllowableClass && item->AllowableClass != uint32(-1) && !(item->AllowableClass & player->getClassMask()))
                return false;
            if (item->RequiredSpell && !player->HasSpell(item->RequiredSpell))
                return false;
            return true;
        }

        uint32 RecipeItemFor(Player* player, Recipe const& recipe)
        {
            uint8 team = TeamOf(player);
            for (uint32 entry : recipe.recipeItems)
            {
                auto itr = sData.items.find(entry);
                if (itr != sData.items.end() && (itr->second.teams & team) && PlayerMayUseItem(player, entry))
                    return entry;
            }
            return 0;
        }

        bool TrainerTeaches(Player* player, TrainerSource const& t)
        {
            for (uint32 ability : t.reqAbility)
                if (ability && !player->HasSpell(ability))
                    return false;
            return true;
        }

        bool QuestOpen(Player* player, Quest const* quest)
        {
            return !quest->GetAllowableRaces() || (quest->GetAllowableRaces() & player->getRaceMask());
        }

        AutoRow const* AutoRowFor(Player* player, Recipe const& recipe)
        {
            for (AutoRow const& row : recipe.autoRows)
                if (MatchesMasks(player, row.raceMask, row.classMask))
                    return &row;
            return nullptr;
        }

        // Whether anything teaches this player the recipe (by faction, race, class and
        // specialization). Where it is, and whether the player can get there yet, is W's business.
        bool Learnable(Player* player, Recipe const& recipe)
        {
            uint8 team = TeamOf(player);
            if (!(recipe.teams & team) || !MatchesMasks(player, recipe.raceMask, recipe.classMask))
                return false;
            if (AutoRowFor(player, recipe) || !recipe.discoveries.empty() || RecipeItemFor(player, recipe))
                return true;
            for (TrainerSource const& t : recipe.trainers)
                if (CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(t.creature))
                    if ((TeamsOfFaction(creature->faction) & team) && TrainerTeaches(player, t))
                        return true;
            for (uint32 questId : recipe.quests)
                if (Quest const* quest = sObjectMgr->GetQuestTemplate(questId))
                    if (QuestOpen(player, quest))
                        return true;
            return false;
        }

        std::string ReputationText(ItemTemplate const* item)
        {
            if (!item || !item->RequiredReputationFaction)
                return "-";
            FactionEntry const* faction = sFactionStore.LookupEntry(item->RequiredReputationFaction);
            if (!faction)
                return "-";
            static char const* const RANKS[] = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" };
            uint32 rank = std::min<uint32>(item->RequiredReputationRank, 7);
            return Escape(std::string(RANKS[rank]) + " with " + DbcString(faction->name));
        }

        std::string QuestZone(Quest const* quest)
        {
            return quest->GetZoneOrSort() > 0 ? AreaName(uint32(quest->GetZoneOrSort())) : "";
        }
    }

    void Build()
    {
        uint32 oldMSTime = getMSTime();
        sData = Data();

        std::unordered_set<uint32> recipeItems;
        std::unordered_set<uint32> service;  // trainers and vendors
        std::unordered_set<uint32> droppers;
        std::unordered_set<uint32> objects;

        CollectSpawnedCreatures();
        ReadRecipes();
        ReadTrainers(service);
        ReadRecipeItems(recipeItems);
        ReadVendors(recipeItems, service);
        ReadQuests(recipeItems);
        ReadLoot(recipeItems, droppers, objects);
        ReadDiscoveries();
        ReadSpawns(service, droppers, objects);
        Finish();
        ComputeStamp();

        LOG_INFO("server.loading", ">> mod-retail-professions: indexed {} recipes ({} recipe items) in {} ms",
            sData.recipes.size(), recipeItems.size(), GetMSTimeDiffToNow(oldMSTime));
    }

    uint32 Stamp()
    {
        return sData.stamp;
    }

    // L:<req>:<skill> -> every recipe of the profession the player could learn or already knows.
    // Row: spell, required skill, yellow, grey, product item, made min, made max, source bits,
    // reagents ("id*n/id*n" or "-"), product inventory type, product quality, recipe item,
    // 1 when it's cast on an item (an enchant, socket, buckle, lining...).
    void HandleList(Player* player, std::string const& req, std::vector<std::string_view> const& args)
    {
        uint32 skill = 0;
        if (args.size() < 3 || !ParseUInt(args[2], skill))
        {
            SendError(player, req, "bad");
            return;
        }

        // A GM sees everything; the addon doesn't cache that list for the account.
        bool everything = player->IsGameMaster();

        std::vector<std::string> rows;
        auto itr = sData.bySkill.find(skill);
        if (itr != sData.bySkill.end())
            for (uint32 spell : itr->second)
            {
                Recipe const& recipe = sData.recipes.at(spell);
                if (everything || player->HasSpell(spell) || Learnable(player, recipe))
                    rows.push_back(ListRow(recipe, RecipeItemFor(player, recipe)));
            }

        Send(player, "LR:" + req + ":" + std::to_string(skill) + ":" + std::to_string(rows.size()) + ":" + (everything ? "1" : "0"));
        SendRows(player, "LD:" + req, rows);
        Send(player, "LE:" + req);
    }

    // W:<req>:<spell> -> where the player can learn a recipe. Rows: kind, id, name, zone, a, b, c.
    //   A  learned automatically             a = skill (0 = with the profession)
    //   T  trainer   id = creature           a = cost (copper), b = skill
    //   V  vendor    id = creature           a = price (copper, 0 = not gold), b = limited stock, c = reputation
    //   D  drop      id = creature           a = chance x100 (0 = unknown), b = "min-max" level
    //   X  world drop                        a = how many creatures, b = "min-max" level
    //   O  object    id = gameobject         a = chance x100
    //   C  container id = item               a = chance x100
    //   Q  quest     id = quest              a = quest level, b = min level
    //   R  quest reward of the recipe item, same fields as Q
    //   S  discovery id = spell crafted (0 = any)   a = chance x100, b = skill
    void HandleWhere(Player* player, std::string const& req, std::vector<std::string_view> const& args)
    {
        uint32 spell = 0;
        if (args.size() < 3 || !ParseUInt(args[2], spell))
        {
            SendError(player, req, "bad");
            return;
        }

        auto ritr = sData.recipes.find(spell);
        if (ritr == sData.recipes.end())
        {
            SendError(player, req, "none");
            return;
        }
        Recipe const& recipe = ritr->second;
        Viewer viewer = MakeViewer(player);
        uint32 const limit = GetConfig().maxSourcesPerKind;
        std::vector<std::string> rows;

        auto row = [&](char kind, uint32 id, std::string const& name, std::string const& zone, std::string const& a,
            std::string const& b = "0", std::string const& c = "-")
        {
            rows.push_back(Acore::StringFormat("{},{},{},{},{},{},{}", kind, id, Escape(name), Escape(zone), a, b, c));
        };

        if (AutoRow const* autoRow = AutoRowFor(player, recipe))
            row('A', 0, "", "", std::to_string(autoRow->skill));

        // Trainers: near ones first, one row per kind of trainer.
        {
            std::vector<std::pair<float, std::string>> found;
            for (TrainerSource const& t : recipe.trainers)
            {
                Spawn const* where = nullptr;
                if (!TrainerTeaches(player, t) || !CanUseCreature(viewer, t.creature, &where))
                    continue;
                CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(t.creature);
                float dist = where->map == player->GetMapId() ? player->GetExactDist2d(where->x, where->y) : 1e9f;
                found.emplace_back(dist, Acore::StringFormat("T,{},{},{},{},{},-", t.creature, Escape(creature->Name),
                    Escape(PlaceName(*where)), t.cost, t.reqSkill));
            }
            std::sort(found.begin(), found.end(), [](auto const& a, auto const& b) { return a.first < b.first; });
            for (std::size_t i = 0; i < found.size() && i < limit; ++i)
                rows.push_back(found[i].second);
        }

        for (uint32 questId : recipe.quests)
            if (Quest const* quest = sObjectMgr->GetQuestTemplate(questId))
                if (QuestOpen(player, quest))
                    row('Q', questId, quest->GetTitle(), QuestZone(quest), std::to_string(quest->GetQuestLevel()),
                        std::to_string(quest->GetMinLevel()));

        for (DiscoverySource const& d : recipe.discoveries)
        {
            SpellInfo const* from = d.fromSpell ? sSpellMgr->GetSpellInfo(d.fromSpell) : nullptr;
            row('S', d.fromSpell, from ? DbcString(from->SpellName) : "", "", std::to_string(d.chance), std::to_string(d.reqSkill));
        }

        uint32 recipeItem = RecipeItemFor(player, recipe);
        auto iitr = recipeItem ? sData.items.find(recipeItem) : sData.items.end();
        if (iitr != sData.items.end())
        {
            ItemSources const& sources = iitr->second;
            ItemTemplate const* item = sObjectMgr->GetItemTemplate(recipeItem);

            std::vector<std::pair<float, std::string>> vendors;
            for (Vendor const& v : sources.vendors)
            {
                Spawn const* where = nullptr;
                if (!CanUseCreature(viewer, v.creature, &where))
                    continue;
                CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(v.creature);
                float dist = where->map == player->GetMapId() ? player->GetExactDist2d(where->x, where->y) : 1e9f;
                vendors.emplace_back(dist, Acore::StringFormat("V,{},{},{},{},{},{}", v.creature, Escape(creature->Name),
                    Escape(PlaceName(*where)), v.gold && item ? std::max(0, item->BuyPrice) : 0, v.maxcount ? 1 : 0,
                    ReputationText(item)));
            }
            std::sort(vendors.begin(), vendors.end(), [](auto const& a, auto const& b) { return a.first < b.first; });
            for (std::size_t i = 0; i < vendors.size() && i < limit; ++i)
                rows.push_back(vendors[i].second);

            for (uint32 questId : sources.quests)
                if (Quest const* quest = sObjectMgr->GetQuestTemplate(questId))
                    if (QuestOpen(player, quest))
                        row('R', questId, quest->GetTitle(), QuestZone(quest), std::to_string(quest->GetQuestLevel()),
                            std::to_string(quest->GetMinLevel()));

            uint32 shown = 0;
            for (Drop const& d : sources.creatures)
            {
                if (shown >= limit)
                    break;
                Spawn const* where = nullptr;
                CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(d.id);
                if (!creature || !DropOpen(viewer, sData.creatureSpawns, d.id, &where))
                    continue;
                row('D', d.id, creature->Name, where ? PlaceName(*where) : "", std::to_string(d.chance),
                    std::to_string(creature->minlevel) + "-" + std::to_string(creature->maxlevel));
                ++shown;
            }

            if (sources.worldDropCreatures)
                row('X', 0, "", "", std::to_string(sources.worldDropCreatures),
                    std::to_string(sources.worldMinLevel) + "-" + std::to_string(sources.worldMaxLevel));

            shown = 0;
            for (Drop const& d : sources.objects)
            {
                if (shown >= limit)
                    break;
                Spawn const* where = nullptr;
                GameObjectTemplate const* object = sObjectMgr->GetGameObjectTemplate(d.id);
                if (!object || !DropOpen(viewer, sData.objectSpawns, d.id, &where))
                    continue;
                row('O', d.id, object->name, where ? PlaceName(*where) : "", std::to_string(d.chance));
                ++shown;
            }

            shown = 0;
            for (Drop const& d : sources.containers)
            {
                if (shown >= limit)
                    break;
                if (ItemTemplate const* container = sObjectMgr->GetItemTemplate(d.id))
                {
                    row('C', d.id, container->Name1, "", std::to_string(d.chance));
                    ++shown;
                }
            }
        }

        Send(player, "WR:" + req + ":" + std::to_string(spell) + ":" + std::to_string(recipeItem));
        SendRows(player, "WD:" + req, rows);
        Send(player, "WE:" + req);
    }

    // M:<req>:<T|V>:<creature> -> flags the nearest spawn on the map (when it's on the player's
    // continent) and answers where it is.
    void HandleMapPin(Player* player, std::string const& req, std::vector<std::string_view> const& args)
    {
        uint32 entry = 0;
        if (args.size() < 4 || !ParseUInt(args[3], entry))
        {
            SendError(player, req, "bad");
            return;
        }

        Viewer viewer = MakeViewer(player);
        Spawn const* where = nullptr;
        CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(entry);
        if (!creature || !CanUseCreature(viewer, entry, &where))
        {
            SendError(player, req, "none");
            return;
        }

        std::string text = PlaceName(*where);
        float x = where->x;
        float y = where->y;
        if (where->zone)
        {
            Map2ZoneCoordinates(x, y, where->zone);
            if (x >= 0.0f && x <= 100.0f && y >= 0.0f && y <= 100.0f && !(x == where->x && y == where->y))
                text += Acore::StringFormat(" ({:.0f}, {:.0f})", x, y);
        }

        if (where->map == player->GetMapId())
        {
            WorldPacket data(SMSG_GOSSIP_POI, 4 + 4 + 4 + 4 + 4 + creature->Name.size() + 1);
            data << uint32(POI_FLAGS);
            data << float(where->x);
            data << float(where->y);
            data << uint32(POI_ICON_RED_FLAG);
            data << uint32(0);
            data << creature->Name;
            player->SendDirectMessage(&data);
            text += Acore::StringFormat(", {} yards away", uint32(player->GetExactDist2d(where->x, where->y)));
        }
        else
            text += " - " + MapName(where->map);

        Send(player, "M:" + req + ":ok:" + Escape(text));
    }
}
