/*
 * mod-retail-professions: Milling and Prospecting from the profession window.
 *
 * The client can only mill or prospect by casting the spell on one stack and emptying the loot
 * window, once per five herbs or ore. Here the window asks the server to do it: Y lists what
 * each herb or ore can give (so the window can show it like a recipe), and X starts a job that
 * works through the player's bags at the spell's own cast time, rolling the core's loot tables
 * and putting the results straight into the bags. Moving, fighting, casting or closing the
 * window ends the job.
 *
 * What a job checks is what the spell checks (Spell::CheckCast): the spell is known, the item
 * can be milled or prospected, the skill is high enough and five are in the bags. Unlike the
 * spell, the five may come from more than one stack.
 *
 * A job lives in its player's CustomData: it's only touched while that player is processed,
 * by the world thread for requests and by the player's map thread for updates.
 */

#include "RetailProfessions.h"
#include "DataMap.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "LootMgr.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "SharedDefines.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "StringFormat.h"
#include "Timer.h"
#include "World.h"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <map>
#include <unordered_map>

namespace RetailProfessions::Refine
{
    namespace
    {
        constexpr uint32 SPELL_MILLING = 51005;
        constexpr uint32 SPELL_PROSPECTING = 31252;

        // Both spells take five of the item.
        constexpr uint32 UNITS_PER_CAST = 5;

        constexpr uint32 MIN_CAST_TIME = 250;
        constexpr uint32 FALLBACK_CAST_TIME = 1000;

        constexpr int MAX_REFERENCE_DEPTH = 4;

        char const* const JOB_KEY = "mod-retail-professions:refine";

        struct Kind
        {
            char code;
            uint32 spell;
            uint32 skill;
            ItemFlags itemFlag;
            LootStore const* store;
            LootType lootType;
            char const* table;
        };

        Kind const KINDS[] = {
            { 'M', SPELL_MILLING, SKILL_INSCRIPTION, ITEM_FLAG_IS_MILLABLE, &LootTemplates_Milling, LOOT_MILLING,
                "milling_loot_template" },
            { 'P', SPELL_PROSPECTING, SKILL_JEWELCRAFTING, ITEM_FLAG_IS_PROSPECTABLE, &LootTemplates_Prospecting,
                LOOT_PROSPECTING, "prospecting_loot_template" },
        };

        Kind const* KindOf(std::string_view code)
        {
            if (code.size() == 1)
                for (Kind const& kind : KINDS)
                    if (kind.code == code[0])
                        return &kind;
            return nullptr;
        }

        // ---- what each herb or ore gives -------------------------------------------------------

        // One row of a loot table.
        struct Entry
        {
            uint32 item = 0;
            uint32 reference = 0;
            float chance = 0.0f; // percent; 0 inside a group = an equal share of what's left
            uint8 group = 0;
            uint32 minCount = 1;
            uint32 maxCount = 1;
        };

        using Table = std::unordered_map<uint32, std::vector<Entry>>;

        // One thing a herb or ore can give, summed over every way the table reaches it.
        struct Result
        {
            float miss = 1.0f; // the chance that no path gives it
            uint32 minCount = 0;
            uint32 maxCount = 0;
        };

        using Results = std::map<uint32, Result>;

        struct Source
        {
            uint32 item = 0;
            uint32 reqSkill = 0;
            std::vector<std::string> rows; // its S row, then one R row per result
        };

        // Per kind code, sorted by required skill then name.
        std::unordered_map<char, std::vector<Source>> sSources;

        std::atomic<uint32> sActiveJobs{0};

        void ReadTable(char const* table, Table& into)
        {
            QueryResult result = WorldDatabase.Query("SELECT CAST(Entry AS UNSIGNED), CAST(Item AS UNSIGNED), "
                "CAST(ABS(Reference) AS UNSIGNED), CAST(ROUND(Chance * 100) AS SIGNED), CAST(GroupId AS UNSIGNED), "
                "CAST(MinCount AS UNSIGNED), CAST(MaxCount AS UNSIGNED) FROM {} WHERE QuestRequired = 0", table);
            if (!result)
                return;
            do
            {
                Field* f = result->Fetch();
                Entry entry;
                entry.item = uint32(f[1].Get<uint64>());
                entry.reference = uint32(f[2].Get<uint64>());
                entry.chance = float(std::max<int64>(f[3].Get<int64>(), 0)) / 100.0f;
                entry.group = uint8(f[4].Get<uint64>());
                entry.minCount = uint32(f[5].Get<uint64>());
                entry.maxCount = uint32(f[6].Get<uint64>());
                into[uint32(f[0].Get<uint64>())].push_back(entry);
            } while (result->NextRow());
        }

        // The drop rate the core multiplies an ungrouped item's chance by (LootStoreItem::Roll).
        float QualityRate(uint32 item)
        {
            ItemTemplate const* proto = sObjectMgr->GetItemTemplate(item);
            if (!proto)
                return 1.0f;
            switch (proto->Quality)
            {
                case ITEM_QUALITY_POOR:      return sWorld->getRate(RATE_DROP_ITEM_POOR);
                case ITEM_QUALITY_NORMAL:    return sWorld->getRate(RATE_DROP_ITEM_NORMAL);
                case ITEM_QUALITY_UNCOMMON:  return sWorld->getRate(RATE_DROP_ITEM_UNCOMMON);
                case ITEM_QUALITY_RARE:      return sWorld->getRate(RATE_DROP_ITEM_RARE);
                case ITEM_QUALITY_EPIC:      return sWorld->getRate(RATE_DROP_ITEM_EPIC);
                case ITEM_QUALITY_LEGENDARY: return sWorld->getRate(RATE_DROP_ITEM_LEGENDARY);
                case ITEM_QUALITY_ARTIFACT:  return sWorld->getRate(RATE_DROP_ITEM_ARTIFACT);
                default:                     return 1.0f;
            }
        }

        void Collect(std::vector<Entry> const& rows, Table const& references, float weight, int depth, Results& out);

        // An entry that was rolled with probability `weight`: the item itself, or everything the
        // table it refers to gives, once per repeat.
        void Reach(Entry const& entry, Table const& references, float weight, int depth, Results& out)
        {
            if (weight <= 0.0f)
                return;

            if (!entry.reference)
            {
                Result& result = out[entry.item];
                bool first = result.maxCount == 0;
                result.miss *= 1.0f - std::min(weight, 1.0f);
                result.minCount = first ? entry.minCount : std::min(result.minCount, entry.minCount);
                result.maxCount = std::max(result.maxCount, std::max(entry.minCount, entry.maxCount));
                return;
            }

            auto itr = references.find(entry.reference);
            if (itr == references.end() || depth >= MAX_REFERENCE_DEPTH)
                return;
            uint32 repeats = uint32(float(entry.maxCount) * sWorld->getRate(RATE_DROP_ITEM_REFERENCED_AMOUNT));
            for (uint32 i = 0; i < repeats; ++i)
                Collect(itr->second, references, weight, depth + 1, out);
        }

        // Mirrors LootTemplate::Process: ungrouped rows roll on their own, and each group gives
        // one of its rows (the ones with a chance first, the rest sharing what's left).
        void Collect(std::vector<Entry> const& rows, Table const& references, float weight, int depth, Results& out)
        {
            std::map<uint8, std::vector<Entry const*>> groups;
            for (Entry const& entry : rows)
            {
                if (entry.group)
                {
                    groups[entry.group].push_back(&entry);
                    continue;
                }

                float chance = entry.chance;
                if (chance < 100.0f)
                    chance *= entry.reference ? sWorld->getRate(RATE_DROP_ITEM_REFERENCED) : QualityRate(entry.item);
                Reach(entry, references, weight * std::min(chance, 100.0f) / 100.0f, depth, out);
            }

            for (auto const& [id, members] : groups)
            {
                float left = 100.0f;
                std::vector<Entry const*> equal;
                for (Entry const* entry : members)
                {
                    if (entry->chance <= 0.0f)
                    {
                        equal.push_back(entry);
                        continue;
                    }
                    float share = std::min(entry->chance, left);
                    left -= share;
                    Reach(*entry, references, weight * share / 100.0f, depth, out);
                }
                if (left > 0.0f && !equal.empty())
                    for (Entry const* entry : equal)
                        Reach(*entry, references, weight * left / 100.0f / float(equal.size()), depth, out);
            }
        }

        void BuildKind(Kind const& kind, Table const& references)
        {
            Table table;
            ReadTable(kind.table, table);

            std::vector<Source>& sources = sSources[kind.code];
            sources.clear();
            for (auto const& [item, rows] : table)
            {
                ItemTemplate const* proto = sObjectMgr->GetItemTemplate(item);
                if (!proto || !proto->HasFlag(kind.itemFlag) || !kind.store->HaveLootFor(item))
                    continue;

                Results results;
                Collect(rows, references, 1.0f, 0, results);

                // The likeliest result first; the addon keeps the order.
                std::vector<std::pair<uint32, Result>> ordered(results.begin(), results.end());
                std::stable_sort(ordered.begin(), ordered.end(),
                    [](auto const& a, auto const& b) { return a.second.miss < b.second.miss; });

                Source source;
                source.item = item;
                source.reqSkill = proto->RequiredSkillRank;
                source.rows.push_back(Acore::StringFormat("S,{},{},{}", item, source.reqSkill, Escape(proto->Name1)));
                for (auto const& [resultItem, result] : ordered)
                {
                    uint32 chance = uint32(std::lround((1.0f - result.miss) * 10000.0f));
                    if (!chance || !sObjectMgr->GetItemTemplate(resultItem))
                        continue;
                    source.rows.push_back(Acore::StringFormat("R,{},{},{},{},{}", item, resultItem, result.minCount,
                        result.maxCount, chance));
                }
                if (source.rows.size() > 1)
                    sources.push_back(std::move(source));
            }

            std::sort(sources.begin(), sources.end(), [](Source const& a, Source const& b)
            {
                if (a.reqSkill != b.reqSkill)
                    return a.reqSkill < b.reqSkill;
                return a.item < b.item;
            });
        }

        // ---- jobs ------------------------------------------------------------------------------

        struct Job : public DataMap::Base
        {
            Kind const* kind = nullptr; // nullptr = no job
            std::string req;
            uint32 item = 0;
            uint32 total = 0;
            uint32 done = 0;
            uint32 castTime = FALLBACK_CAST_TIME;
            uint32 elapsed = 0;
        };

        Job* JobOf(Player* player)
        {
            Job* job = player->CustomData.Get<Job>(JOB_KEY);
            return job && job->kind ? job : nullptr;
        }

        void End(Player* player, Job& job, std::string_view reason)
        {
            Send(player, Acore::StringFormat("XE:{}:{}:{}:{}", job.req, job.done, job.total, reason));
            job.kind = nullptr;
            --sActiveJobs;
        }

        uint32 CastTime(Kind const& kind)
        {
            if (uint32 fixed = GetConfig().refineCastTime)
                return std::max(fixed, MIN_CAST_TIME);
            SpellInfo const* spell = sSpellMgr->GetSpellInfo(kind.spell);
            uint32 castTime = spell ? spell->CalcCastTime() : 0;
            return castTime ? std::max(castTime, MIN_CAST_TIME) : FALLBACK_CAST_TIME;
        }

        // Why the player can't mill or prospect this item right now; nullptr when they can.
        char const* Refusal(Player* player, Kind const& kind, uint32 item)
        {
            if (!player->HasSpell(kind.spell))
                return "spell";
            ItemTemplate const* proto = sObjectMgr->GetItemTemplate(item);
            if (!proto || !proto->HasFlag(kind.itemFlag) || !kind.store->HaveLootFor(item))
                return "bad";
            if (proto->RequiredSkillRank > player->GetSkillValue(kind.skill))
                return "skill";
            if (player->GetItemCount(item, false) < UNITS_PER_CAST)
                return "none";
            return nullptr;
        }

        // What ends a job between casts, as the cast itself would be interrupted.
        char const* Interruption(Player* player)
        {
            if (!player->IsAlive())
                return "dead";
            if (player->IsInCombat())
                return "combat";
            if (player->isMoving() || player->IsInFlight() || player->IsBeingTeleported())
                return "moved";
            // A loot window too: the spell itself may have one open on a stack, which takes its
            // five when the window closes. A job must never eat into that stack meanwhile.
            if (player->IsNonMeleeSpellCast(false) || player->GetTradeData() || player->GetLootGUID())
                return "occupied";
            return nullptr;
        }

        // One cast: takes five, rolls the loot table and stores what it gave. Returns false when
        // the job can't go on.
        bool Step(Player* player, Job& job)
        {
            Kind const& kind = *job.kind;
            if (char const* refusal = Refusal(player, kind, job.item))
            {
                End(player, job, refusal);
                return false;
            }
            ItemTemplate const* proto = sObjectMgr->GetItemTemplate(job.item);

            // The core's own switch for skill-ups from these two (SkillChance.Milling/Prospecting).
            bool skillUps = kind.code == 'M' ? sWorld->getBoolConfig(CONFIG_SKILL_MILLING)
                : sWorld->getBoolConfig(CONFIG_SKILL_PROSPECTING);
            if (skillUps)
                player->UpdateGatherSkill(kind.skill, player->GetPureSkillValue(kind.skill), proto->RequiredSkillRank);

            Loot loot;
            loot.loot_type = kind.lootType;
            loot.FillLoot(job.item, *kind.store, player, true);
            player->DestroyItemCount(job.item, UNITS_PER_CAST, true);

            std::string gained;
            bool mailed = false;
            uint32 slots = loot.GetMaxSlotInLootFor(player);
            for (uint32 slot = 0; slot < slots; ++slot)
            {
                LootItem* lootItem = loot.LootItemInSlot(slot, player);
                if (!lootItem || !lootItem->count)
                    continue;

                ItemPosCountVec dest;
                if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, lootItem->itemid, lootItem->count) == EQUIP_ERR_OK)
                {
                    Item* stored = player->StoreNewItem(dest, lootItem->itemid, true, lootItem->randomPropertyId);
                    player->SendNewItem(stored, lootItem->count, false, false);
                    player->UpdateLootAchievements(lootItem, &loot);
                }
                else
                {
                    // No room: nothing is lost, the mailbox has it.
                    player->SendItemRetrievalMail(lootItem->itemid, lootItem->count);
                    mailed = true;
                }

                if (!gained.empty())
                    gained += '/';
                gained += Acore::StringFormat("{}*{}", lootItem->itemid, uint32(lootItem->count));
            }

            ++job.done;
            Send(player, Acore::StringFormat("XP:{}:{}:{}:{}", job.req, job.done, job.total, gained.empty() ? "-" : gained));

            if (mailed)
            {
                End(player, job, "full");
                return false;
            }
            if (job.done >= job.total)
            {
                End(player, job, "done");
                return false;
            }
            return true;
        }
    }

    void Build()
    {
        uint32 oldMSTime = getMSTime();

        Table references;
        ReadTable("reference_loot_template", references);
        for (Kind const& kind : KINDS)
            BuildKind(kind, references);

        LOG_INFO("server.loading", ">> mod-retail-professions: {} herbs to mill and {} ores to prospect in {} ms",
            sSources['M'].size(), sSources['P'].size(), GetMSTimeDiffToNow(oldMSTime));
    }

    // Y:<req>:<M|P> -> YR:<req>:<kind>:<how many>, YD rows, YE. Two kinds of row, a herb or ore
    // and then what it gives, likeliest first:
    //   S,<item>,<required skill>,<name>
    //   R,<item>,<result item>,<min>,<max>,<chance x100>
    void HandleYields(Player* player, std::string const& req, std::vector<std::string_view> const& args)
    {
        Kind const* kind = args.size() >= 3 ? KindOf(args[2]) : nullptr;
        if (!kind)
        {
            SendError(player, req, "bad");
            return;
        }

        // Like unlearned recipes: nothing past the player's era.
        uint32 cap = player->IsGameMaster() ? 0 : SkillCap(player);
        std::vector<std::string> rows;
        uint32 count = 0;
        // Empty until Build has run (the switch was turned on without a restart).
        auto itr = sSources.find(kind->code);
        if (itr != sSources.end())
            for (Source const& source : itr->second)
            {
                if (cap && source.reqSkill > cap)
                    continue;
                ++count;
                rows.insert(rows.end(), source.rows.begin(), source.rows.end());
            }

        Send(player, Acore::StringFormat("YR:{}:{}:{}", req, kind->code, count));
        SendRows(player, "YD:" + req, rows);
        Send(player, "YE:" + req);
    }

    // X:<req>:<M|P>:<item>:<casts> -> X:<req>:ok:<casts>:<cast time ms>, then XP:<req>:<done>:
    // <casts>:<gained "item*n/item*n" or "-"> after every cast and XE:<req>:<done>:<casts>:<why>
    // at the end: done, stopped, moved, combat, occupied, dead, full (bags; the rest went to the
    // mailbox), none (ran out), skill, spell.
    void HandleStart(Player* player, std::string const& req, std::vector<std::string_view> const& args)
    {
        Kind const* kind = args.size() >= 5 ? KindOf(args[2]) : nullptr;
        uint32 item = 0, casts = 0;
        if (!kind || !ParseUInt(args[3], item) || !ParseUInt(args[4], casts) || !casts)
        {
            SendError(player, req, "bad");
            return;
        }

        if (Job* running = JobOf(player))
            End(player, *running, "stopped");

        char const* refusal = Refusal(player, *kind, item);
        if (!refusal)
            refusal = Interruption(player);
        if (refusal)
        {
            SendError(player, req, refusal);
            return;
        }

        Job* job = player->CustomData.GetDefault<Job>(JOB_KEY);
        job->kind = kind;
        job->req = req;
        job->item = item;
        job->total = std::min(casts, player->GetItemCount(item, false) / UNITS_PER_CAST);
        job->done = 0;
        job->castTime = CastTime(*kind);
        job->elapsed = 0;
        ++sActiveJobs;

        Send(player, Acore::StringFormat("X:{}:ok:{}:{}", req, job->total, job->castTime));
    }

    // XS:<req> -> XS:<req>:ok, after the running job's XE (if one was running).
    void HandleStop(Player* player, std::string const& req)
    {
        if (Job* job = JobOf(player))
            End(player, *job, "stopped");
        Send(player, "XS:" + req + ":ok");
    }

    void Update(Player* player, uint32 diff)
    {
        if (!sActiveJobs.load(std::memory_order_relaxed))
            return;
        Job* job = JobOf(player);
        if (!job)
            return;

        if (char const* why = Interruption(player))
        {
            End(player, *job, why);
            return;
        }

        job->elapsed += diff;
        // A long tick still gives one cast: the pace is the cast time at best.
        if (job->elapsed >= job->castTime)
        {
            job->elapsed = 0;
            Step(player, *job);
        }
    }

    void Forget(Player* player)
    {
        if (Job* job = JobOf(player))
        {
            job->kind = nullptr;
            --sActiveJobs;
        }
    }
}
