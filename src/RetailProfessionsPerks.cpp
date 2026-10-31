/*
 * mod-retail-professions: what knowing a recipe well gives you, after retail's crafting stats.
 *
 *   Multicraft       a chance that a craft makes a second batch (things that stack only, and
 *                    never Enchanting)
 *   Resourcefulness  a chance that a craft gives back part of its reagents
 *   Crafting speed   a shorter cast
 *
 * Retail gets these from gear and specializations. Here they come from skill: nothing while a
 * recipe is orange, rising in a straight line from where it turns yellow to where it turns
 * grey, and full from then on. So a recipe that still teaches you is slow and single, and one
 * you've outgrown is quick to make in bulk.
 *
 * Three kinds of recipe get speed only:
 *   - ones the core already rolls extra items for (skill_extra_item_template: the alchemy
 *     masteries). Their own proc stands in for Multicraft.
 *   - ones on a loop, where what a recipe makes can be crafted back into what it used
 *     (elemental and eternal transmutes). A proc there would mint materials out of nothing.
 *   - ones made only from what vendors sell without limit: a second batch of those would be
 *     gold out of nothing as soon as the product sells for most of what it cost.
 *
 * The core has no hook where a cast time can be changed, so the speed is applied right after
 * Spell::prepare: the cast is shortened and its start sent to the client again. The same place
 * fixes a core gap first: many recipes get quicker as the profession skill rises (the client
 * shows it), but the core always casts them at their base time.
 *
 * Which craft made an item is read from the spell the core is executing for the player
 * (Player::m_spellModTakingSpell, set around a spell's effects), never remembered between calls.
 */

#include "RetailProfessions.h"
#include "DBCStores.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Random.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "Spell.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "StringFormat.h"
#include "Timer.h"
#include "WorldSession.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <unordered_map>
#include <unordered_set>

namespace RetailProfessions::Perks
{
    namespace
    {
        // Skill lines whose recipes are crafted (no Runeforging: it makes nothing and costs nothing).
        constexpr std::array<uint32, 11> CRAFTS = {
            SKILL_ALCHEMY, SKILL_BLACKSMITHING, SKILL_ENCHANTING, SKILL_ENGINEERING, SKILL_INSCRIPTION, SKILL_JEWELCRAFTING,
            SKILL_LEATHERWORKING, SKILL_TAILORING, SKILL_MINING, SKILL_COOKING, SKILL_FIRST_AID,
        };

        constexpr uint32 MIN_CAST_TIME = 250;

        struct Craft
        {
            uint32 skill = 0;
            uint32 yellow = 0;
            uint32 grey = 0;
            uint32 item = 0;  // what it makes, 0 for an enchant
            uint8 flags = 0;  // PerkFlags
        };

        std::unordered_map<uint32, Craft> sCrafts; // by spell

        // ---- which recipes loop -----------------------------------------------------------------

        // Strongly connected components of "this item is crafted from that one" (Tarjan).
        struct Loops
        {
            std::unordered_map<uint32, std::vector<uint32>> madeFrom; // reagent -> products
            std::unordered_map<uint32, uint32> index, low, component;
            std::unordered_set<uint32> onStack;
            std::vector<uint32> stack;
            uint32 next = 0, components = 0;

            void Visit(uint32 item)
            {
                index[item] = low[item] = ++next;
                stack.push_back(item);
                onStack.insert(item);

                auto itr = madeFrom.find(item);
                if (itr != madeFrom.end())
                    for (uint32 product : itr->second)
                    {
                        if (!index.count(product))
                        {
                            Visit(product);
                            low[item] = std::min(low[item], low[product]);
                        }
                        else if (onStack.count(product))
                            low[item] = std::min(low[item], index[product]);
                    }

                if (low[item] != index[item])
                    return;
                ++components;
                while (true)
                {
                    uint32 member = stack.back();
                    stack.pop_back();
                    onStack.erase(member);
                    component[member] = components;
                    if (member == item)
                        break;
                }
            }

            void Run()
            {
                std::vector<uint32> items;
                for (auto const& [reagent, products] : madeFrom)
                    items.push_back(reagent);
                for (uint32 item : items)
                    if (!index.count(item))
                        Visit(item);
            }

            // True when the product can be crafted back into the reagent.
            bool Same(uint32 reagent, uint32 product) const
            {
                auto a = component.find(reagent);
                auto b = component.find(product);
                return a != component.end() && b != component.end() && a->second == b->second;
            }
        };

        // ---- odds ------------------------------------------------------------------------------

        // 0 while the recipe is orange, 1 once it's grey, a straight line in between. Skill
        // with its bonuses, as the profession window shows it and colours recipes by.
        float Mastery(Player* player, Craft const& craft)
        {
            uint32 skill = player->GetSkillValue(craft.skill);
            if (skill >= craft.grey)
                return 1.0f;
            if (skill <= craft.yellow || craft.grey <= craft.yellow)
                return 0.0f;
            return float(skill - craft.yellow) / float(craft.grey - craft.yellow);
        }

        float Between(uint32 low, uint32 high, float mastery)
        {
            return float(low) + (float(high) - float(low)) * mastery;
        }

        // Stores what fits in the bags and mails what the bags have no room for. What the
        // player may not carry more of (a unique item) is simply not given.
        void Give(Player* player, uint32 entry, uint32 count, bool created)
        {
            ItemPosCountVec dest;
            uint32 noSpace = 0;
            InventoryResult msg = player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, entry, count, &noSpace);
            if (msg != EQUIP_ERR_OK && msg != EQUIP_ERR_INVENTORY_FULL)
                return;

            uint32 stored = 0;
            if (msg == EQUIP_ERR_OK || (noSpace < count && !dest.empty()))
                if (Item* item = player->StoreNewItem(dest, entry, true))
                {
                    stored = msg == EQUIP_ERR_OK ? count : count - noSpace;
                    player->SendNewItem(item, stored, true, created);
                }
            if (stored < count)
                player->SendItemRetrievalMail(entry, count - stored);
        }

        Craft const* CraftOf(uint32 spell)
        {
            auto itr = sCrafts.find(spell);
            return itr != sCrafts.end() ? &itr->second : nullptr;
        }
    }

    void Build()
    {
        uint32 oldMSTime = getMSTime();
        sCrafts.clear();
        Config const& config = GetConfig();

        // Recipes the core rolls extra items for.
        std::unordered_set<uint32> mastered;
        if (QueryResult result = WorldDatabase.Query("SELECT CAST(spellId AS UNSIGNED) FROM skill_extra_item_template"))
            do
            {
                mastered.insert(uint32(result->Fetch()[0].Get<uint64>()));
            } while (result->NextRow());

        // What vendors sell without limit, for gold.
        std::unordered_set<uint32> vendored;
        if (QueryResult result = WorldDatabase.Query("SELECT DISTINCT CAST(item AS UNSIGNED) FROM npc_vendor "
            "WHERE item > 0 AND maxcount = 0 AND ExtendedCost = 0"))
            do
            {
                vendored.insert(uint32(result->Fetch()[0].Get<uint64>()));
            } while (result->NextRow());

        Loops loops;
        for (uint32 skill : CRAFTS)
            for (SkillLineAbilityEntry const* ability : GetSkillLineAbilitiesBySkillLine(skill))
            {
                SpellInfo const* info = sSpellMgr->GetSpellInfo(ability->Spell);
                if (!info || !info->HasAttribute(SPELL_ATTR0_IS_TRADESKILL) || sCrafts.count(ability->Spell))
                    continue;

                Craft craft;
                craft.skill = skill;
                craft.yellow = ability->TrivialSkillLineRankLow;
                craft.grey = ability->TrivialSkillLineRankHigh;
                for (SpellEffectInfo const& effect : info->GetEffects())
                    if ((effect.Effect == SPELL_EFFECT_CREATE_ITEM || effect.Effect == SPELL_EFFECT_CREATE_ITEM_2) && effect.ItemType)
                    {
                        craft.item = effect.ItemType;
                        break;
                    }
                if (craft.item)
                    for (std::size_t i = 0; i < info->Reagent.size(); ++i)
                        if (info->Reagent[i] > 0 && info->ReagentCount[i])
                            loops.madeFrom[uint32(info->Reagent[i])].push_back(craft.item);
                sCrafts.emplace(ability->Spell, craft);
            }
        loops.Run();

        uint32 multicraft = 0, resourceful = 0, looping = 0, fromVendors = 0, alwaysGrey = 0;
        for (auto& [spell, craft] : sCrafts)
        {
            if (!craft.grey)
                ++alwaysGrey;

            SpellInfo const* info = sSpellMgr->GetSpellInfo(spell);
            if (config.speedMax && info->CalcCastTime() > MIN_CAST_TIME)
                craft.flags |= PERK_SPEED;

            ItemTemplate const* product = craft.item ? sObjectMgr->GetItemTemplate(craft.item) : nullptr;
            if (!product)
                continue;

            bool hasReagents = false, loop = false, allVendored = true;
            for (std::size_t i = 0; i < info->Reagent.size(); ++i)
                if (info->Reagent[i] > 0 && info->ReagentCount[i])
                {
                    hasReagents = true;
                    if (loops.Same(uint32(info->Reagent[i]), craft.item))
                        loop = true;
                    if (!vendored.count(uint32(info->Reagent[i])))
                        allVendored = false;
                }
            if (loop)
            {
                ++looping;
                continue;
            }
            if (hasReagents && allVendored)
            {
                ++fromVendors;
                continue;
            }
            if (mastered.count(spell))
                continue;

            if (config.multicraftMax && craft.skill != SKILL_ENCHANTING && product->GetMaxStackSize() > 1)
            {
                craft.flags |= PERK_MULTICRAFT;
                ++multicraft;
            }
            if (config.resourcefulMax && config.resourcefulRefund && hasReagents)
            {
                craft.flags |= PERK_RESOURCEFUL;
                ++resourceful;
            }
        }

        LOG_INFO("server.loading", ">> mod-retail-professions: craft perks for {} recipes ({} multicraft, {} resourcefulness; "
            "{} loops and {} made from vendor goods left out; {} have no grey skill and count as grey) in {} ms",
            sCrafts.size(), multicraft, resourceful, looping, fromVendors, alwaysGrey, GetMSTimeDiffToNow(oldMSTime));
    }

    // As built at startup, whatever the switches say now: the recipe lists and their stamp
    // mustn't change under a client that cached them. HELLO says whether the perks are on.
    uint8 Flags(uint32 spell)
    {
        Craft const* craft = CraftOf(spell);
        return craft ? craft->flags : 0;
    }

    namespace
    {
        bool Active()
        {
            Config const& config = GetConfig();
            return config.enabled && config.perks;
        }

        // SpellCastTimes.dbc rows whose time falls as the profession skill rises (3.3.5a). The
        // core loads only the base time, not the per-level step or the floor. 1,862 recipes use
        // them (Ruby Pendant of Fire is 37); the few other spells on them aren't tradeskills.
        struct SkillScaledCast
        {
            uint32 id;
            int32 base;
            int32 perLevel;
            int32 minimum;
        };

        constexpr std::array<SkillScaledCast, 8> SKILL_SCALED_CASTS = { {
            { 10, 1000, -100, 500 },
            { 11, 2000, -100, 1000 },
            { 12, 5000, -100, 2500 },
            { 13, 30000, -1000, 10000 },
            { 35, 12500, -250, 5000 },
            { 37, 25000, -400, 8000 },
            { 38, 45000, -500, 15000 },
            { 39, 50000, -500, 25000 },
        } };

        // The cast time the client shows for a recipe (tooltip, GetSpellInfo): one level per 5
        // skill in the recipe's profession, counted from the spell's base level, as cmangos and
        // vmangos work it out (Player::GetSpellRank). `full` when the spell doesn't scale.
        int32 SkillCastTime(Player* player, SpellInfo const* info, int32 full)
        {
            if (!info->CastTimeEntry)
                return full;
            auto row = std::find_if(SKILL_SCALED_CASTS.begin(), SKILL_SCALED_CASTS.end(),
                [info](SkillScaledCast const& r) { return r.id == info->CastTimeEntry->ID; });
            // A DBC with other numbers in it isn't the one these were read from.
            if (row == SKILL_SCALED_CASTS.end() || row->base != info->CastTimeEntry->CastTime)
                return full;

            SkillLineAbilityMapBounds bounds = sSpellMgr->GetSkillLineAbilityMapBounds(info->Id);
            if (bounds.first == bounds.second)
                return full;
            int32 rank = player->GetSkillValue(bounds.first->second->SkillLine);
            if (info->MaxLevel && rank >= int32(info->MaxLevel * 5))
                rank = int32(info->MaxLevel * 5);
            int32 castTime = row->base + row->perLevel * (rank / 5 - int32(info->BaseLevel));
            return std::max(castTime, row->minimum);
        }
    }

    // Right after Spell::prepare: the cast bar has been sent with the full time.
    void OnPrepare(Spell* spell, Unit* caster, SpellInfo const* info)
    {
        if (!caster || !info->HasAttribute(SPELL_ATTR0_IS_TRADESKILL) || !caster->IsPlayer())
            return;
        Config const& config = GetConfig();
        if (!config.enabled || spell->getState() != SPELL_STATE_PREPARING)
            return;

        // Only the spell's own cast time: something else changed it already (the Chef's Hat
        // makes cooking half a second) and is left alone.
        int32 full = spell->GetCastTime();
        if (full <= 0 || uint32(full) != info->CalcCastTime())
            return;

        // The core always takes the base time, so a recipe the client says takes 8 seconds
        // takes 25. This applies with the perks off too.
        int32 castTime = SkillCastTime(caster->ToPlayer(), info, full);
        Craft const* craft = Active() ? CraftOf(info->Id) : nullptr;
        if (craft && (craft->flags & PERK_SPEED))
        {
            float faster = std::min(Between(config.speedMin, config.speedMax, Mastery(caster->ToPlayer(), *craft))
                + Gear::Bonus(caster->ToPlayer(), craft->skill, Gear::STAT_SPEED), float(SPEED_CAP));
            castTime = std::max<int32>(int32(float(castTime) * (100.0f - faster) / 100.0f), MIN_CAST_TIME);
        }
        if (castTime == full)
            return;

        // m_casttime is protected and nothing sets it from outside. A class derived from Spell
        // may name the member, and a pointer to it works on any Spell.
        struct Access : Spell { using Spell::m_casttime; };
        spell->*(&Access::m_casttime) = castTime;
        spell->ReSetTimer();
        spell->SendSpellStart();
    }

    // PK:0:<spell>:M:<item>*<n>          a second batch
    // PK:0:<spell>:R:<item>*<n>/...      reagents given back
    void OnCreateItem(Player* player, Item* item, uint32 count)
    {
        if (!Active() || !item || !count)
            return;

        // The spell whose effects the core is handling for this player right now.
        Spell* spell = player->m_spellModTakingSpell;
        if (!spell || spell->GetCaster() != player)
            return;
        SpellInfo const* info = spell->GetSpellInfo();
        Craft const* craft = info->HasAttribute(SPELL_ATTR0_IS_TRADESKILL) ? CraftOf(info->Id) : nullptr;
        if (!craft || !(craft->flags & (PERK_MULTICRAFT | PERK_RESOURCEFUL)))
            return;
        // Nothing was paid for it (a triggered or GM cast): nothing to give on top.
        if (spell->HasTriggeredCastFlag(TRIGGERED_IGNORE_POWER_AND_REAGENT_COST) || player->CanNoReagentCast(info))
            return;
        // Bots have no use for it, and a bot with full bags would fill its mailbox.
        if (player->GetSession()->IsHeadless())
            return;

        // The recipe's own product, or the perfect cut Jewelcrafting made in its place.
        uint32 entry = item->GetEntry();
        ItemTemplate const* product = item->GetTemplate();
        if (entry != craft->item)
        {
            ItemTemplate const* usual = sObjectMgr->GetItemTemplate(craft->item);
            if (!usual || usual->Class != ITEM_CLASS_GEM || product->Class != ITEM_CLASS_GEM)
                return;
        }

        Config const& config = GetConfig();
        float mastery = Mastery(player, *craft);

        // Profession equipment adds its points on top of what mastery gives.
        if ((craft->flags & PERK_MULTICRAFT) && product->GetMaxStackSize() > 1
            && roll_chance_f(Between(config.multicraftMin, config.multicraftMax, mastery) + Gear::Bonus(player, craft->skill, Gear::STAT_MULTICRAFT)))
        {
            Give(player, entry, count, true);
            Send(player, Acore::StringFormat("PK:0:{}:M:{}*{}", info->Id, entry, count));
        }

        if ((craft->flags & PERK_RESOURCEFUL) && config.resourcefulRefund
            && roll_chance_f(Between(config.resourcefulMin, config.resourcefulMax, mastery) + Gear::Bonus(player, craft->skill, Gear::STAT_RESOURCEFULNESS)))
        {
            // A share of each reagent. The fraction left over is a roll, so on average a proc
            // gives back exactly the share, and a proc on a small recipe can give nothing.
            std::string list;
            for (std::size_t i = 0; i < info->Reagent.size(); ++i)
            {
                if (info->Reagent[i] <= 0 || !info->ReagentCount[i])
                    continue;
                float share = float(info->ReagentCount[i]) * float(config.resourcefulRefund) / 100.0f;
                uint32 units = uint32(share);
                if (roll_chance_f((share - float(units)) * 100.0f))
                    ++units;
                units = std::min(units, info->ReagentCount[i]);
                if (!units)
                    continue;
                Give(player, uint32(info->Reagent[i]), units, false);
                if (!list.empty())
                    list += '/';
                list += Acore::StringFormat("{}*{}", info->Reagent[i], units);
            }
            if (!list.empty())
                Send(player, Acore::StringFormat("PK:0:{}:R:{}", info->Id, list));
        }
    }
}
