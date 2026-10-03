-- Smoke test for the RetailProfessions addon outside the game: stubs just enough of the 3.3.5a
-- API (frames, skills, the trade skill window), loads the addon in .toc order and answers its
-- requests with a fake mod-retail-professions server (and mod-retail-ah's price lookups).
-- Usage (any Lua 5.3+): lua tools/addon_smoke_test.lua addon/RetailProfessions

local dir = arg[1] or "addon/RetailProfessions"
unpack = table.unpack
bit = {
	band = function (a, b) return math.floor(a) & math.floor(b) end,
	bor = function (a, b) return math.floor(a) | math.floor(b) end,
}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strsplit(sep, text)
	local out = {}
	for part in (text .. sep):gmatch("(.-)" .. sep) do table.insert(out, part) end
	return table.unpack(out)
end

local now = 0
function GetTime() return now end
local clock = 1000
function time() clock = clock + 1 return clock end

local errors = 0
local function report(where, err)
	errors = errors + 1
	print("ERROR in " .. where .. ": " .. tostring(err))
end

-----------------------------------------
-- frames: tables with scripts; unknown methods are no-ops returning nil

local frameMeta = {}
local allFrames = {}
local function newObject(kind, name, parent)
	local o = { __kind = kind, __name = name, __scripts = {}, __shown = true, __text = "", __width = 100, __height = 20,
		__parent = parent, __enabled = true, __attrs = {} }
	setmetatable(o, frameMeta)
	if name then _G[name] = o end
	table.insert(allFrames, o)
	return o
end

local methods = {}
function methods:SetScript(event, fn) self.__scripts[event] = fn end
function methods:GetScript(event) return self.__scripts[event] end
function methods:HookScript(event, fn)
	local old = self.__scripts[event]
	self.__scripts[event] = function (...) if old then old(...) end fn(...) end
end
function methods:Show() local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end end
function methods:Hide() local was = self.__shown; self.__shown = false; if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end end
function methods:IsShown() return self.__shown end
function methods:IsVisible()
	local f = self
	while f do
		if not rawget(f, "__shown") then return false end
		f = rawget(f, "__parent")
	end
	return true
end
function methods:SetText(t) self.__text = t == nil and "" or tostring(t) end
function methods:GetText() return self.__text end
function methods:SetChecked(c) self.__checked = c and 1 or nil end
function methods:GetChecked() return rawget(self, "__checked") end
function methods:GetWidth() return self.__width end
function methods:GetHeight() return self.__height end
function methods:SetWidth(w) self.__width = w end
function methods:SetHeight(h) self.__height = h end
function methods:SetSize(w, h) self.__width, self.__height = w, h end
function methods:GetName() return self.__name end
function methods:GetFrameLevel() return 1 end
function methods:GetObjectType() return self.__kind end
function methods:GetRegions() return end
function methods:CreateTexture() return newObject("Texture", nil, self) end
function methods:CreateFontString() return newObject("FontString", nil, self) end
function methods:Enable() self.__enabled = true end
function methods:Disable() self.__enabled = false end
function methods:IsEnabled() return self.__enabled and 1 or nil end
function methods:GetParent() return rawget(self, "__parent") end
function methods:GetEffectiveScale() return 1 end
function methods:GetLeft() return 100 end
function methods:GetTop() return 500 end
function methods:SetAttribute(k, v)
	if InCombatLockdown() and self.__kind == "Button" and self.__secure then error("SetAttribute on a secure frame in combat") end
	self.__attrs[k] = v
end
function methods:GetAttribute(k) return self.__attrs[k] end
function methods:GetPoint()
	if rawget(self, "__point") then return table.unpack(self.__point) end
	return "TOPLEFT", UIParent, "TOPLEFT", 10, -10
end
function methods:SetPoint(...) self.__point = { ... } end
frameMeta.__index = function (t, k)
	if methods[k] then return methods[k] end
	-- Unknown widget methods (capitalized) are no-ops; unset fields are nil, as in the game.
	if type(k) == "string" and k:match("^%u") then return function () end end
	return nil
end

local combat = false
function InCombatLockdown() return combat end

function CreateFrame(kind, name, parent, template)
	local f = newObject(kind, name, parent)
	if template and template:find("Secure") then f.__secure = true end
	if name and template then
		if template:find("Check") then _G[name .. "Text"] = newObject("FontString", nil, f) end
		if template:find("FauxScroll") then _G[name .. "ScrollBar"] = newObject("Slider", nil, f) end
	end
	-- Secure frames refuse Show/Hide in combat, as in the game.
	if f.__secure then
		f.Show = function (self) if combat then error("Show on a secure frame in combat") end methods.Show(self) end
		f.Hide = function (self) if combat then error("Hide on a secure frame in combat") end methods.Hide(self) end
	end
	return f
end

function FauxScrollFrame_Update() end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_SetOffset() end
function FauxScrollFrame_OnVerticalScroll(self, offset, h, fn) fn() end
function PlaySound() end
function IsModifiedClick() return false end
function IsShiftKeyDown() return false end
function GetCursorInfo() return nil end
function ClearCursor() end
local inserted
function ChatEdit_InsertLink(link) inserted = link return true end
function ChatFrame_OpenChat() end
function StaticPopup_Show(which, text) return { which = which, text = text } end
local lastMenu
function EasyMenu(items) lastMenu = items end
function CloseDropDownMenus() end
function UnitName() return "Tester" end
function UnitRace() return "Human", "Human" end
function UnitClass() return "Mage", "MAGE" end
function GetLocale() return "enUS" end
function SpellIsTargeting() return false end
function GetInventoryItemLink() return nil end
function GetContainerNumSlots() return 0 end
function GetContainerItemLink() return nil end
function GetItemIcon() return "Interface\\Icons\\X" end
local bindings = {}
function GetBindingAction(key) return bindings[key] or "" end
function SetBinding(key, action) bindings[key] = action end
function SaveBindings() end
function GetCurrentBindingSet() return 1 end
function GetBindingKey(action) for k, a in pairs(bindings) do if a == action then return k end end end
local closedTradeSkill, loadedClassic = 0, 0
function CloseTradeSkill() closedTradeSkill = closedTradeSkill + 1 end
function TradeSkillFrame_LoadUI() loadedClassic = loadedClassic + 1 end
function HideUIPanel(f) f:Hide() end
function AbandonSkill() end
function PickupContainerItem() end
function PickupInventoryItem() end
function ExpandSkillHeader() end
function CollapseSkillHeader() end

ITEM_QUALITY_COLORS = {}
for i = 0, 7 do ITEM_QUALITY_COLORS[i] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end
ACCEPT, CANCEL, CREATE, CREATE_ALL, TRADE_SKILLS = "Accept", "Cancel", "Create", "Create All", "Professions"
INVTYPE_CHEST, INVTYPE_FEET = "Chest", "Feet"
NUM_BAG_SLOTS = 4
UIParent = newObject("Frame", "UIParent")
WorldFrame = newObject("Frame", "WorldFrame")
GameTooltip = newObject("GameTooltip", "GameTooltip")
local tipLines = {}
function GameTooltip:SetOwner() tipLines = {} end
function GameTooltip:AddLine(text) table.insert(tipLines, tostring(text)) end
function UnitCastingInfo() return nil end
DEFAULT_CHAT_FRAME = { AddMessage = function (_, m) print("  [chat] " .. m) end }
GameFontHighlightSmall, GameFontNormalSmall = {}, {}
StaticPopupDialogs, SlashCmdList, UISpecialFrames = {}, {}, {}

-----------------------------------------
-- the game data

local items = {
	[2589] = { "Linen Cloth", 1 }, [2320] = { "Coarse Thread", 1 }, [2996] = { "Bolt of Linen Cloth", 1 },
	[2568] = { "Brown Linen Vest", 1, "INVTYPE_CHEST" }, [4308] = { "Green Linen Bracers", 2, "INVTYPE_WRIST" },
	[4355] = { "Pattern: Green Linen Bracers", 2 }, [2321] = { "Fine Thread", 1 },
}
local function itemLink(id) return "|cffffffff|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[" .. items[id][1] .. "]|h|r" end
function GetItemInfo(item)
	local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
	local d = id and items[id]
	if not d then return nil end
	return d[1], itemLink(id), d[2], 10, 1, "Trade Goods", "Cloth", 20, d[3] or "", "Interface\\Icons\\X", 10
end
local bags = { [2589] = 4 }
function GetItemCount(id) return bags[id] or 0 end

local spells = {
	[3908] = "Tailoring", [2259] = "Alchemy", [2575] = "Mining", [2656] = "Smelting", [2580] = "Find Minerals",
	[7620] = "Fishing", [2963] = "Bolt of Linen Cloth", [2385] = "Brown Linen Vest", [3914] = "Green Linen Bracers",
}
local knownSpells = { Tailoring = true, Smelting = true, Mining = true, ["Find Minerals"] = true, Fishing = true }
function GetSpellInfo(spell)
	if type(spell) == "number" then
		return spells[spell], nil, "Interface\\Icons\\S"
	end
	if knownSpells[spell] then return spell, nil, "Interface\\Icons\\S" end
	return nil
end
function GetSpellLink(id) return "|Hspell:" .. id .. "|h[" .. tostring(spells[id]) .. "]|h" end

local skillLines = {
	{ "Professions", true }, { "Tailoring", false, 120, 150 }, { "Mining", false, 50, 75 },
	{ "Secondary Skills", true }, { "Fishing", false, 1, 75 },
}
function GetNumSkillLines() return #skillLines end
function GetSkillLineInfo(i)
	local s = skillLines[i]
	return s[1], s[2], true, s[3] or 0, 0, 0, s[4] or 0, not s[2]
end

-- The trade skill window: one header and two learned recipes.
local tradeSkill = {
	{ "Cloth", "header" },
	{ "Bolt of Linen Cloth", "optimal", 2, spell = 2963, item = 2996, reagents = { { 2589, 2 } } },
	{ "Brown Linen Vest", "medium", 0, spell = 2385, item = 2568, reagents = { { 2589, 3 }, { 2320, 1 } } },
}
local selectedIndex = 0
local crafted = {}
function GetTradeSkillLine() return "Tailoring", 120, 150 end
function GetNumTradeSkills() return #tradeSkill end
function GetTradeSkillInfo(i)
	local t = tradeSkill[i]
	if not t then return nil end
	return t[1], t[2], t[3] or 0, t[2] == "header" and 1 or nil
end
function GetTradeSkillRecipeLink(i) local t = tradeSkill[i] return t.spell and ("|cffffd000|Henchant:" .. t.spell .. "|h[" .. t[1] .. "]|h|r") end
function GetTradeSkillItemLink(i) local t = tradeSkill[i] return t.item and itemLink(t.item) end
function GetTradeSkillIcon() return "Interface\\Icons\\T" end
function GetTradeSkillNumReagents(i) return #(tradeSkill[i].reagents or {}) end
function GetTradeSkillReagentInfo(i, r) local rg = tradeSkill[i].reagents[r] return items[rg[1]][1], "Interface\\Icons\\R", rg[2], bags[rg[1]] or 0 end
function GetTradeSkillReagentItemLink(i, r) return itemLink(tradeSkill[i].reagents[r][1]) end
function GetTradeSkillDescription() return "" end
function GetTradeSkillTools() return end
function GetTradeSkillCooldown() return nil end
function GetTradeSkillNumMade() return 1, 1 end
function SelectTradeSkill(i) selectedIndex = i end
function GetTradeSkillSelectionIndex() return selectedIndex end
function DoTradeSkill(i, n) table.insert(crafted, { i, n }) end
function ExpandTradeSkillSubClass() end
function SetTradeSkillItemNameFilter() end
function SetTradeSkillItemLevelFilter() end
function SetTradeSkillSubClassFilter() end
function SetTradeSkillInvSlotFilter() end
function TradeSkillOnlyShowMakeable() end
function TradeSkillOnlyShowSkillUps() end
function IsTradeSkillLinked() return nil end
function GetTradeSkillListLink() return "|Htrade:3908:120:150|h[Tailoring]|h" end

-- With DRAGON=1, a DragonUI stand-in, so the skinned branches run too.
if os.getenv("DRAGON") == "1" then
	NineSliceUtils = { GetLayout = function () return {} end, ApplyLayout = function () end }
	DragonUI = {
		_dir = "Interface\\AddOns\\DragonUI\\Textures\\", atlasinfo = {},
		SafeSetAtlas = function () return true end, SkinRedButton = function () end,
		CharacterPanel = { ReskinTab = function () end, ModernizeCloseButton = function () end,
			SkinCheckbox = function () end, ReskinScrollBar = function () end },
	}
end
function SetPortraitToTexture(tex, path) tex.__portrait = path end

-- ReagentBankUI, as far as we use it.
local provider, withdrawn
ReagentBankUI = {
	GetCachedBankItemCount = function (_, id) return id == 2589 and 30 or 0 end,
	RegisterRecipeProvider = function (_, p) provider = p return true end,
	RequestBankSnapshot = function () end,
	NotifyRecipeProviderChanged = function () end,
	-- Like the real one: Withdraw Needed fetches for ReagentBankUI's own "Crafts" count.
	prepareCount = 1,
	SetTradeSkillPrepareCount = function (self, n) self.prepareCount = n end,
	WithdrawNeededForSelectedRecipe = function (self)
		local name, reagents = provider.GetRecipe()
		withdrawn = { name = name, count = self.prepareCount, reagents = reagents }
	end,
	GetTradeSkillControlsHost = function () return provider and provider.frame end,
}
local bankPanel
function ReagentBankUI:DockTradeSkillPanel()
	bankPanel = bankPanel or CreateFrame("Frame")
	bankPanel.__point = { "TOPLEFT", self:GetTradeSkillControlsHost(), "TOPRIGHT", -33, -12 }
	self.tradeSkillPanel = bankPanel
end
function hooksecurefunc(t, name, fn)
	local orig = t[name]
	t[name] = function (...) local r = orig(...) fn(...) return r end
end

-----------------------------------------
-- events and the fake server

local outbox = {}
function SendAddonMessage(prefix, msg, channel)
	assert((prefix == "RPR" or prefix == "RAH") and channel == "WHISPER", "bad addon message")
	assert(#prefix + 1 + #msg <= 254, "addon message too long")
	table.insert(outbox, { prefix, msg })
end

local eventFrames = {}
function methods:RegisterEvent(e) eventFrames[e] = eventFrames[e] or {}; table.insert(eventFrames[e], self) end
function methods:UnregisterEvent() end
local function fire(event, ...)
	for _, f in ipairs(eventFrames[event] or {}) do
		local ok, err = pcall(f.__scripts.OnEvent, f, event, ...)
		if not ok then report(event, err) end
	end
end

local function reply(msg) fire("CHAT_MSG_ADDON", "RPR", msg, "WHISPER", "Tester") end

-- mod-retail-ah's K: per item lowest buyout, units, AH bot pays, vendor price, vendor pays,
-- units sold, copper sold, flags.
local ahPrices = {
	[2589] = "10,200,8,0,1,100,1200,0", [2320] = "0,0,0,10,2,0,0,0", [2996] = "60,20,40,0,10,0,0,0",
	[2568] = "300,3,150,0,70,5,1400,0", [4308] = "0,0,0,0,50,0,0,2", [2321] = "0,0,0,30,5,0,0,0",
}
local rahSent, rahDown = {}, false
local function serveAH(msg)
	local cmd, req, rest = msg:match("^([^:]+):([^:]*):?(.*)$")
	table.insert(rahSent, msg)
	print("  RAH -> " .. msg)
	if rahDown then return end
	assert(cmd == "K", "unexpected RAH request " .. msg)
	local rows = {}
	for entry in rest:gmatch("%d+") do
		if ahPrices[tonumber(entry)] then table.insert(rows, entry .. "," .. ahPrices[tonumber(entry)]) end
	end
	fire("CHAT_MSG_ADDON", "RAH", "KR:" .. req .. ":5:14", "WHISPER", "Tester")
	fire("CHAT_MSG_ADDON", "RAH", "KD:" .. req .. ":" .. table.concat(rows, ";"), "WHISPER", "Tester")
	fire("CHAT_MSG_ADDON", "RAH", "KE:" .. req, "WHISPER", "Tester")
end

local sent = {}
local function serve(msg)
	local cmd, req = msg:match("^([^:]+):([^:]*)")
	table.insert(sent, msg)
	print("  -> " .. msg)
	if cmd == "HELLO" then reply("HELLO:" .. req .. ":1:3:777:300:100:0:3")
	elseif cmd == "L" then
		reply("LR:" .. req .. ":197:3:0")
		reply("LD:" .. req .. ":2963,1,25,50,2996,1,1,1,2589*2,0,1,0,0;2385,10,45,70,2568,1,1,1,2589*3/2320*1,5,1,0")
		reply("LD:" .. req .. ":3914,130,155,175,4308,1,1,2,2996*2/2321*1,9,2,4355")
		reply("LE:" .. req)
	elseif cmd == "W" then
		reply("WR:" .. req .. ":3914:4355")
		reply("WD:" .. req .. ":V,1474,Rann Flamespinner,Elwynn Forest,100,1,Friendly with Stormwind;D,100,Gruff Swiftbite,Elwynn%2C Forest,550,10-11,-;X,0,-,-,1234,10-20,-")
		reply("WE:" .. req)
	elseif cmd == "M" then reply("M:" .. req .. ":ok:Elwynn Forest (44%2C 65)")
	else print("  !! unknown command " .. cmd) end
end

local function tick(seconds)
	for _ = 1, math.ceil(seconds / 0.05) do
		now = now + 0.05
		for _, f in ipairs(allFrames) do
			if f.__shown and f.__scripts.OnUpdate then
				local ok, err = pcall(f.__scripts.OnUpdate, f, 0.05)
				if not ok then report("OnUpdate", err) end
			end
		end
		while #outbox > 0 do
			local m = table.remove(outbox, 1)
			if m[1] == "RAH" then serveAH(m[2]) else serve(m[2]) end
		end
	end
end

local function step(name, fn)
	print("== " .. name)
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then errors = errors + 1; print("ERROR: " .. err) end
	tick(0.5)
end

for line in io.lines(dir .. "/RetailProfessions.toc") do
	if line:match("%.lua$") then
		local chunk, err = loadfile(dir .. "/" .. line)
		if not chunk then report("load " .. line, err) else
			local ok, e = pcall(chunk, "RetailProfessions", {})
			if not ok then report("run " .. line, e) end
		end
	end
end

local RPF = RetailProfessions
local M = RPF.Model
local function find(pred)
	for _, f in ipairs(allFrames) do if pred(f) then return f end end
end
local function buttonWithText(text)
	return find(function (f) return f.__kind == "Button" and f.__text == text end)
end
local function textShown(pattern)
	return find(function (f) return f.__kind == "FontString" and f.__text:find(pattern) and f:IsVisible() end)
end

step("login, hello", function ()
	fire("ADDON_LOADED", "RetailProfessions")
	fire("PLAYER_LOGIN")
	tick(4)
	assert(RPF.serverReady, "no HELLO answer")
	assert(RPF.skillCap == 300 and RPF.skillGain == 3, "HELLO fields not read")
	assert(bindings.K == "RETAILPROFESSIONS_BOOK", "K was not bound to the book")
	assert(provider and provider.frame == RetailProfessionsFrame, "not registered with ReagentBankUI")
end)

step("skill-up chance follows the core's straight line", function ()
	assert(RPF.SkillUpChance(40, 45, 70) == 100, "orange")
	assert(RPF.SkillUpChance(57, 45, 70) == 52, "midway: " .. tostring(RPF.SkillUpChance(57, 45, 70)))
	assert(RPF.SkillUpChance(70, 45, 70) == 0, "grey")
end)

step("open tailoring", function ()
	fire("TRADE_SKILL_SHOW")
	tick(0.5)
	assert(RetailProfessionsFrame:IsShown(), "window not shown")
	assert(#M.recipes == 2, "learned recipes: " .. #M.recipes)
	assert(M.hasServerData, "server list not merged")
	assert(#M.unlearned == 1 and M.unlearned[1].spell == 3914, "unlearned recipe missing")
	local vest = M.bySpell[2385]
	assert(vest.yellow == 45 and vest.slot == "INVTYPE_CHEST", "server data not attached")
	assert(RPF.selected, "nothing selected")
	assert(textShown("Unlearned: Journeyman"), "unlearned group header missing")
	-- Two profession tabs: Tailoring and Mining (Smelting); Fishing has no window.
	local tabs = 0
	for i = 1, 10 do local b = _G["RetailProfessionsTab" .. i] if b and b.__shown then tabs = tabs + 1 end end
	assert(tabs == 2, "tabs shown: " .. tabs)
	assert(RetailProfessionsTab1:GetAttribute("spell") == "Tailoring", "tab spell")
end)

step("the list is cached for the next visit", function ()
	local key
	for k in pairs(RetailProfessionsDB.lists) do key = k end
	assert(key and key:find("^777:197:"), "list not saved: " .. tostring(key))
end)

step("search finds reagents too", function ()
	RPF.filter.text = "coarse"
	RPF.Rebuild(true)
	local names = {}
	for _, row in ipairs(RPF.list.rows) do if row.recipe then table.insert(names, row.recipe.name) end end
	assert(#names == 1 and names[1] == "Brown Linen Vest", "search by reagent: " .. table.concat(names, ", "))
	RPF.filter.text = ""
end)

step("have materials counts the reagent bank", function ()
	RPF.filter.haveMats = true
	RPF.Rebuild(true)
	local names = {}
	for _, row in ipairs(RPF.list.rows) do if row.recipe then names[row.recipe.name] = true end end
	assert(names["Bolt of Linen Cloth"] and not names["Brown Linen Vest"], "have-materials filter wrong")
	local bagsOnly, withBank = M.Craftable(M.bySpell[2963])
	assert(bagsOnly == 2 and withBank == 17, "craftable: " .. bagsOnly .. "/" .. withBank)
	RPF.filter.haveMats = false
	RPF.Rebuild(true)
end)

step("slot filter", function ()
	RPF.filter.slot = "INVTYPE_CHEST"
	RPF.Rebuild(true)
	local count = 0
	for _, row in ipairs(RPF.list.rows) do if row.recipe then count = count + 1 end end
	assert(count == 1, "slot filter rows: " .. count)
	RPF.filter.slot = nil
	RPF.Rebuild(true)
	EasyMenu(nil) -- reset
	RetailProfessionsFilterMenu = RetailProfessionsFilterMenu
end)

step("create and create all", function ()
	RetailProfessionsDB.autoWithdraw = false
	RPF.Select(M.bySpell[2963])
	buttonWithText("Create").__scripts.OnClick()
	assert(crafted[#crafted][1] == 2 and crafted[#crafted][2] == 1, "Create did the wrong thing")
	local all = find(function (f) return f.__kind == "Button" and f.__text:find("^Create All") end)
	all.__scripts.OnClick()
	assert(crafted[#crafted][2] == 2, "Create All count: " .. tostring(crafted[#crafted][2]))
	local name, list = provider.GetRecipe()
	assert(name == "Bolt of Linen Cloth" and list[1].itemEntry == 2589 and list[1].requiredPerCraft == 2, "provider recipe")
end)

step("unlearned recipe: where to learn, map pin", function ()
	RPF.Select(M.bySpell[3914])
	tick(0.5)
	assert(textShown("Rann Flamespinner"), "vendor source not shown")
	assert(textShown("World drop"), "world drop not shown")
	assert(textShown("Friendly with Stormwind"), "reputation not shown")
	local map = find(function (f) return f.__kind == "Button" and f.__text == "Map" and f:IsVisible() end)
	map.__scripts.OnClick(map)
	tick(0.5)
	assert(textShown("Elwynn Forest %(44, 65%)"), "map answer not shown")
	assert(textShown("Not learned %- needs 130"), "skill requirement not shown")
end)

step("where-to-learn is asked once, however often the recipe redraws", function ()
	local before = 0
	for _, m in ipairs(sent) do if m:match("^W:") then before = before + 1 end end
	for _ = 1, 3 do fire("BAG_UPDATE"); tick(0.5) end
	RPF.Select(M.bySpell[3914])
	tick(0.5)
	local after = 0
	for _, m in ipairs(sent) do if m:match("^W:") then after = after + 1 end end
	assert(before == 1 and after == 1, "W sent " .. before .. " then " .. after .. " times")
end)

step("favorites go to the top", function ()
	RPF.ToggleFavorite(2385)
	tick(0.2)
	local first = RPF.list.rows[1]
	assert(first.header == "Favorites" and RPF.list.rows[2].recipe.spell == 2385, "favorites group missing")
	RPF.ToggleFavorite(2385)
	tick(0.2)
	assert(RPF.list.rows[1].header ~= "Favorites", "favorites group stayed")
end)

step("skill-up odds live in the tooltip", function ()
	local vest = M.bySpell[2385]
	RPF.AddSkillUpLines(GameTooltip, vest)
	local text = table.concat(tipLines, "\n")
	-- Skill 120 is past the vest's grey (70).
	assert(text:find("No more skill%-ups"), "no skill-up line: " .. text)
	assert(text:find("yellow 45") and text:find("grey 70"), "no thresholds: " .. text)
end)

step("use reagent bank: withdraw, then craft when it arrives", function ()
	RetailProfessionsDB.autoWithdraw = true
	RPF.Select(M.bySpell[2963])
	RPF.SetQuantity(5)
	local before = #crafted
	buttonWithText("Create").__scripts.OnClick()
	assert(withdrawn and withdrawn.count == 5 and withdrawn.name == "Bolt of Linen Cloth", "no withdraw for 5")
	assert(#crafted == before, "crafted before the reagents arrived")
	bags[2589] = 10
	fire("BAG_UPDATE")
	tick(0.5)
	assert(#crafted == before + 1 and crafted[#crafted][2] == 5, "didn't craft 5 after the withdraw")
	local all = find(function (f) return f.__kind == "Button" and f.__text:find("^Create All") end)
	assert(all.__text == "Create All [20]", "Create All doesn't count the bank: " .. all.__text)
	bags[2589] = 4
end)

step("track a recipe", function ()
	RPF.ToggleTracked(M.bySpell[2385])
	assert(RetailProfessionsTracker:IsShown(), "tracker hidden")
	assert(textShown("Brown Linen Vest"), "tracked recipe missing")
	assert(textShown("Coarse Thread"), "tracked reagent missing")
	bags[2320] = 1
	fire("BAG_UPDATE")
	tick(0.5)
end)

step("professions book", function ()
	RPF.ToggleBook()
	assert(RetailProfessionsBook:IsShown(), "book hidden")
	assert(textShown("120 / 150"), "tailoring row missing")
	assert(textShown("Secondary Skills"), "secondary section missing")
	assert(buttonWithText("Find Minerals"), "mining's action missing")
end)

step("combat hides the secure buttons first, then they come back", function ()
	fire("PLAYER_REGEN_DISABLED")
	combat = true
	assert(not RetailProfessionsTab1.__shown, "tab button still shown in combat")
	RPF.ToggleBook()
	RPF.ToggleBook()
	combat = false
	fire("PLAYER_REGEN_ENABLED")
	assert(RetailProfessionsTab1.__shown, "tab button not back after combat")
end)

step("the reagent bank sidebar moves past the tabs", function ()
	ReagentBankUI:DockTradeSkillPanel()
	local _, _, _, x = bankPanel:GetPoint(1)
	assert(x == -33 + 40, "bank sidebar not shifted: " .. tostring(x))
end)

step("shift-click Enchant answers the replace-enchant question", function ()
	RetailProfessionsDB.autoWithdraw = false
	local r = M.bySpell[2963]
	RPF.Select(r)
	r.isEnchant = true
	local replaced, hidden, shown = 0, 0, 0
	function ReplaceEnchant() replaced = replaced + 1 end
	function BindEnchant() end
	local oldHide, oldShow = StaticPopup_Hide, StaticPopup_Show
	StaticPopup_Hide = function () hidden = hidden + 1 end
	StaticPopup_Show = function (...) shown = shown + 1 return oldShow(...) end
	local oldLink, oldTargeting, oldShift = GetContainerItemLink, SpellIsTargeting, IsShiftKeyDown
	GetContainerItemLink = function (bag, slot) if bag == 0 and slot == 1 then return itemLink(2589) end end
	SpellIsTargeting = function () return true end
	RPF.enchantTarget = { id = 2589, bag = 0, slot = 1 }

	-- A plain click leaves the question to the player.
	buttonWithText("Create").__scripts.OnClick()
	fire("REPLACE_ENCHANT", "Old", "New")
	assert(replaced == 0, "answered without Shift")

	IsShiftKeyDown = function () return true end
	buttonWithText("Create").__scripts.OnClick()
	fire("REPLACE_ENCHANT", "Old", "New")
	assert(replaced == 1 and hidden >= 1, "Shift-click didn't answer it")
	UnitCastingInfo = function () return "Enchant" end
	tick(1)
	assert(shown == 0, "popup came back although the cast started")

	r.isEnchant = false
	RPF.enchantTarget = nil
	GetContainerItemLink, SpellIsTargeting, IsShiftKeyDown = oldLink, oldTargeting, oldShift
	StaticPopup_Hide, StaticPopup_Show = oldHide, oldShow
	UnitCastingInfo = function () return nil end
end)

step("the amount follows ReagentBankUI's Crafts box both ways", function ()
	RPF.SetQuantity(7)
	assert(ReagentBankUI.prepareCount == 7, "our amount didn't reach ReagentBankUI")
	provider.SetRepeatCount(3)
	assert(RPF.GetQuantity() == 3, "ReagentBankUI's count didn't reach us")
	assert(ReagentBankUI.prepareCount == 7 or ReagentBankUI.prepareCount == 3, "loop")
end)

step("craft for profit: ranked by auction prices", function ()
	local thread = bags[2320]
	bags[2320] = nil
	RetailProfessionsDB.profitView = true
	RPF.Rebuild(true)
	tick(0.5)
	assert(#rahSent >= 1 and rahSent[#rahSent]:find("^K:p%d+:"), "no price request")
	assert(RPF.Profit.state == "ok", "prices not taken: " .. RPF.Profit.state)
	local rows = RPF.list.rows
	-- Bolt: sells 60 -5% = 57, two linen at 10 = 20, so +37c, and the bags make 2.
	assert(rows[1].header == "Craft now" and rows[2].recipe.spell == 2963, "craft-now group: " .. tostring(rows[1].header))
	assert(rows[2].right:find("+37c", 1, true), "bolt profit: " .. tostring(rows[2].right))
	-- Vest: 300 -5% = 285, three linen 30 + coarse thread from a vendor 10 = 40; no thread in the bags.
	assert(rows[3].header == "Buy materials and craft" and rows[4].recipe.spell == 2385, "buy group: " .. tostring(rows[3].header))
	assert(rows[4].right:find("+2s 45c", 1, true), "vest profit: " .. tostring(rows[4].right))
	RPF.Select(M.bySpell[2385])
	tick(0.2)
	assert(textShown("Sells for"), "price block missing")
	assert(textShown("3 listed, 5 sold in 14 days"), "market line missing")
	assert(textShown("Profit"), "profit line missing")
	local a = RPF.Profit.Of(M.bySpell[2385])
	assert(a.parts[2].how == "vendor" and a.cost == 40, "thread should come from the vendor")
	-- The unlearned bracers bind on pickup: worth their vendor price only.
	RPF.Profit.Fetch({ 4308 })
	tick(0.2)
	local value, how = RPF.Profit.SellValue(4308)
	assert(value == 50 and how == "vendor", "soulbound item valued at " .. tostring(value) .. " " .. tostring(how))
	-- Fresh prices aren't asked for again on every redraw.
	local before = #rahSent
	for _ = 1, 3 do fire("BAG_UPDATE"); tick(0.5) end
	assert(#rahSent == before, "prices asked again: " .. (#rahSent - before))
	-- With a thread in the bags the vest moves up to Craft now, ahead of the bolt.
	bags[2320] = 1
	fire("BAG_UPDATE")
	tick(0.5)
	assert(RPF.list.rows[2].recipe.spell == 2385 and RPF.list.rows[3].recipe.spell == 2963, "vest not in Craft now")
	bags[2320] = thread
end)

step("craft for profit without mod-retail-ah", function ()
	rahDown = true
	-- As on first contact: a realm that answered once isn't given up on for one lost request.
	RPF.Profit.state = "unknown"
	RPF.Profit.Fetch(RPF.Profit.ProfessionEntries(), true)
	tick(7)
	assert(RPF.Profit.state == "missing", "no-server state: " .. RPF.Profit.state)
	RPF.Rebuild(true)
	tick(0.2)
	assert(textShown("needs mod%-retail%-ah"), "no-server note missing")
	rahDown = false
	RetailProfessionsDB.profitView = nil
	RPF.Rebuild(true)
end)

step("the search box doesn't keep the keyboard", function ()
	local search = find(function (f) return f.__kind == "EditBox" and rawget(f, "hint") end)
	local cleared = 0
	search.ClearFocus = function () cleared = cleared + 1 end
	RetailProfessionsFrame.__scripts.OnShow(RetailProfessionsFrame)
	assert(cleared >= 1, "opening the window left the search focused")
	local before = cleared
	local row
	for _, f in ipairs(allFrames) do
		if f.__kind == "Button" and rawget(f, "row") and f.row.recipe then row = f break end
	end
	row.__scripts.OnClick(row, "LeftButton")
	assert(cleared > before, "clicking a recipe left the search focused")
end)

step("a recipe that makes no item isn't an enchant outside Enchanting", function ()
	assert(RPF.RecipeList(197)[2963].targetsItem == false, "server's item-target flag not read")
	-- Like Minor Inscription Research: no item to make, cast on nothing.
	local old = GetTradeSkillItemLink
	GetTradeSkillItemLink = function (i) if i == 2 then return "|cffffd000|Henchant:2963|h[Bolt]|h|r" end return old(i) end
	RPF.ForgetRecipeLists()
	RPF.Rebuild()
	tick(0.2)
	local r = M.bySpell[2963]
	assert(not r.isEnchant, "a no-item Tailoring recipe was taken for an enchant")
	RPF.Select(r)
	local all = find(function (f) return f.__kind == "Button" and f.__text:find("^Create All") end)
	assert(not all.__text:find("%[0%]"), "Create All still says 0: " .. all.__text)
	GetTradeSkillItemLink = old
	RPF.Rebuild()
end)

step("closing the window closes the trade skill", function ()
	local before = closedTradeSkill
	RPF.enchantTarget = { id = 2589, bag = 0, slot = 1 }
	local search = find(function (f) return f.__kind == "EditBox" and rawget(f, "hint") end)
	search:SetText("linen")
	RPF.filter.text = "linen"
	RetailProfessionsFrame:Hide()
	assert(RPF.enchantTarget == nil, "the Enchant slot kept its item after closing")
	assert(search:GetText() == "" and RPF.filter.text == "", "the search kept its text after closing")
	assert(closedTradeSkill == before + 1, "CloseTradeSkill not called")
	fire("TRADE_SKILL_CLOSE")
end)

step("classic switch", function ()
	SlashCmdList.RETAILPROFESSIONS("classic")
	fire("TRADE_SKILL_SHOW")
	assert(loadedClassic > 0 and not RetailProfessionsFrame:IsShown(), "classic window not used")
	SlashCmdList.RETAILPROFESSIONS("retail")
	fire("TRADE_SKILL_CLOSE")
end)

print(errors == 0 and "smoke test passed" or (errors .. " error(s)"))
os.exit(errors == 0 and 0 or 1)
