/*
 * mod-retail-professions
 *
 * Server half of a retail-style profession window. The RetailProfessions addon replaces the
 * Blizzard trade skill window and reads everything about learned recipes from the client. This
 * module adds what the client can't know: every recipe a profession has (so the window can list
 * the ones the player hasn't learned yet), the exact skill-up thresholds of each, and where an
 * unlearned recipe is taught, sold, dropped or rewarded.
 *
 * It never changes anything about crafting itself; every craft still goes through the core.
 *
 * Released under the MIT License.
 */

#ifndef MOD_RETAIL_PROFESSIONS_H
#define MOD_RETAIL_PROFESSIONS_H

#include "Define.h"
#include <string>
#include <string_view>
#include <vector>

class Player;

namespace RetailProfessions
{
    // Addon message prefix; the client sends "RPR\t<command>" as a whisper to itself.
    constexpr char const* PREFIX = "RPR";

    // Bumped when a message changes shape. The addon refuses the server data on a mismatch.
    constexpr uint32 PROTOCOL_VERSION = 1;

    // Leaves room for the prefix and tab inside the client's 255-byte chat message limit.
    constexpr std::size_t MAX_PAYLOAD = 240;

    // Capability bits in the HELLO answer.
    enum HelloFlags : uint32
    {
        HELLO_RECIPES  = 0x1, // L lists a profession's recipes, W says where one is learned
        HELLO_MAP_PINS = 0x2, // M flags a trainer or vendor on the map
    };

    // Where a recipe can be learned: the source bits of an L row.
    enum SourceFlags : uint8
    {
        SRC_TRAINER   = 0x01,
        SRC_ITEM      = 0x02, // a recipe item: sold, dropped, rewarded or found in a chest
        SRC_QUEST     = 0x04, // a quest teaches the spell itself
        SRC_DISCOVERY = 0x08,
        SRC_AUTO      = 0x10, // learned with the profession, or on reaching a skill level
    };

    struct Config
    {
        bool enabled = true;
        bool skillCapByEra = true;      // hide unlearned recipes past the player's era
        bool progressionEnabled = false; // IndividualProgression.Enable
        bool hideLockedContinents = true;
        uint32 maxSourcesPerKind = 6;
        uint32 worldDropThreshold = 25;  // more droppers than this through a shared loot table = world drop
        bool saveZoneData = true;
    };

    Config& GetConfig();

    // ---- RetailProfessions.cpp: transport ------------------------------------------------------

    void Send(Player* player, std::string const& payload);

    // Sends "<header>:<row>;<row>;..." in as many messages as it takes, never splitting a row.
    void SendRows(Player* player, std::string const& header, std::vector<std::string> const& rows);

    void SendError(Player* player, std::string const& req, std::string_view what);

    bool ParseUInt(std::string_view text, uint32& out);

    // Names travel inside ','/';'/':' separated fields: those, '|' and '%' become %XX, and an
    // empty string becomes "-" (the addon's row parser drops empty values).
    std::string Escape(std::string_view text);

    // mod-individual-progression's state (0-18), or 18 when it isn't running or doesn't apply.
    uint8 ProgressionState(Player* player);

    // The highest skill an unlearned recipe may need to be listed; 0 = no cap.
    uint32 SkillCap(Player* player);

    // ---- RetailProfessionsIndex.cpp: every recipe and its sources ------------------------------

    namespace Index
    {
        // Reads recipes, trainers, vendors, loot, quests and spawns. Only from OnStartup: it
        // works out zones from the map files, which isn't safe once the maps update.
        void Build();

        // Changes whenever the recipe data does, so the addon knows when its cache is stale.
        uint32 Stamp();

        void HandleList(Player* player, std::string const& req, std::vector<std::string_view> const& args);
        void HandleWhere(Player* player, std::string const& req, std::vector<std::string_view> const& args);
        void HandleMapPin(Player* player, std::string const& req, std::vector<std::string_view> const& args);
    }
}

#endif
