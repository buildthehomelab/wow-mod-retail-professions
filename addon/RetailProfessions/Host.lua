-- With DragonUI's professions window, this addon lives in it instead of opening its own: DragonUI
-- keeps the window (its art, rank bar, profession tabs and Overview), and our recipe list, the
-- recipe card, the craft controls and the proc log button go where its own would be. Home is
-- one of its pages, Milling and Prospecting are side tabs, tracked recipes go in its objective
-- tracker and the professions book (K) is its Overview. Without DragonUI (or with one that
-- can't host) the window of our own is used as before. /prof classic shows DragonUI's own
-- crafting page instead.

local RPF = RetailProfessions
local M = RPF.Model

local HOME_PAGE = "retailprofessions-home"

-- DragonUI's host (DragonUI.Professions.Host), when this DragonUI has one.
local function api()
	local D = _G.DragonUI
	local P = D and D.Professions
	local H = P and P.Host
	if H and (H.VERSION or 0) >= 1 and H.Enabled and H.Register then return H end
	return nil
end

-- DragonUI's window, when it has the professions (with us in it, or on /prof classic).
function RPF.HostAPI()
	return (RPF.hosting or RPF.hostClassic) and api() or nil
end

-- The window the player sees; secure buttons over it take its strata.
function RPF.Window()
	if RPF.hosting and TradeSkillFrame then return TradeSkillFrame end
	return RPF.frame
end

-----------------------------------------
-- what goes into DragonUI's window

local pieces, logHolder
local bankRegistered = false
local provider = {}

function provider.list(parent)
	pieces.list:SetParent(parent)
	return pieces.list
end

function provider.card(parent)
	pieces.card:SetParent(parent)
	RPF.HostLayout(true)
	-- ReagentBankUI follows DragonUI's window from now on: it is built by now.
	if not bankRegistered and TradeSkillFrame then
		bankRegistered = true
		RPF.RegisterBankProvider(TradeSkillFrame)
		-- Our secure buttons (Home's lines) rise with the window when it's clicked.
		RPF.FollowRaises(TradeSkillFrame)
	end
	return pieces.card
end

function provider.controls(parent)
	pieces.controls:SetParent(parent)
	return pieces.controls
end

function provider.header(parent)
	logHolder = logHolder or CreateFrame("Frame")
	logHolder:SetParent(parent)
	logHolder:SetSize(23, 23)
	pieces.log:SetParent(logHolder)
	pieces.log:ClearAllPoints()
	pieces.log:SetPoint("LEFT", logHolder, "LEFT", 0, 0)
	return logHolder
end

-- Milling, Prospecting or someone's linked profession; Blizzard's title otherwise.
function provider.title()
	return M.skillName and RPF.TitleText() or nil
end

function provider.onShow() RPF.HostOpened() end
function provider.onHide() RPF.HostClosed() end

function provider.onPage(page)
	local home = page == HOME_PAGE
	if RPF.Home.active ~= home then RPF.Home.SetActive(home) end
end

-- The open profession's own tab: back to its recipes.
function provider.onCraftingTab()
	RPF.Home.SetActive(false)
	RPF.Refine.SetView(nil)
end

-- Home on, or back to the recipes (Home.lua).
function RPF.ShowHostPage(on)
	local H = api()
	if not H then return end
	if on then
		if H.Page() ~= HOME_PAGE then H.SetPage(HOME_PAGE) end
	elseif H.Page() == HOME_PAGE then
		H.SetPage("crafting")
	end
end

local homePage
local function addHome(H)
	H.AddPage(HOME_PAGE, {
		title = "Home",
		portrait = RPF.Home.ICON,
		build = function (parent)
			if not homePage then
				homePage = CreateFrame("Frame", nil, parent)
				local panel = RPF.Home.panel
				panel:SetParent(homePage)
				panel:ClearAllPoints()
				panel:SetPoint("TOPLEFT", homePage, "TOPLEFT", 10, -40)
				panel:SetPoint("BOTTOMRIGHT", homePage, "BOTTOMRIGHT", -10, 10)
			end
			homePage:SetParent(parent)
			return homePage
		end,
	})
	H.AddTab({
		key = HOME_PAGE, label = "Home", icon = RPF.Home.ICON, after = "overview", page = HOME_PAGE,
		shown = function () return not M.linked and #RPF.KnownProfessions() > 0 end,
	})
end

-- The spell that opens the profession a herb or ore kind belongs to, when you know it.
local function openSpell(kind)
	local p = kind and RPF.Profession(kind.skill)
	return p and p.openName and GetSpellInfo(p.openName) and p.openName or nil
end

local function addRefineTabs(H)
	for _, code in ipairs({ "M", "P" }) do
		H.AddTab({
			key = "retailprofessions-refine-" .. code, after = "professions",
			label = function () local kind = RPF.Refine.Known(code) return kind and kind.name or "" end,
			icon = function () local kind = RPF.Refine.Known(code) return kind and kind.texture end,
			shown = function () return openSpell(RPF.Refine.Known(code)) ~= nil end,
			-- Another profession is open: cast this one's, on its herbs or ore.
			spell = function ()
				local kind = RPF.Refine.Known(code)
				if not kind or RPF.Refine.IsOpen(kind) then return nil end
				return openSpell(kind)
			end,
			onDown = function () RPF.Refine.Pend(code) end,
			onClick = function ()
				RPF.Home.SetActive(false)
				RPF.Refine.SetView(code)
				-- From the Overview too.
				local H = api()
				if H and H.Page() ~= "crafting" then H.SetPage("crafting") end
			end,
			selected = function (page)
				return page == "crafting" and RPF.Refine.Active() ~= nil and RPF.Refine.Active() == RPF.Refine.Kind(code)
			end,
		})
	end
end

-----------------------------------------
-- tracked recipes in DragonUI's objective tracker

local catcherIds = {}

local function trackedEntry(block)
	return RetailProfessionsCharDB and RetailProfessionsCharDB.tracked[block.ref]
end

local function trackedMenu(block)
	local spell = block.ref
	local entry = trackedEntry(block)
	if not entry then return {} end
	local items = {}
	for _, n in ipairs({ 1, 2, 3, 5, 10, 20 }) do
		local mark = (entry.count or 1) == n and "|cffffd200>|r " or "    "
		table.insert(items, { text = mark .. "Make " .. n, func = function ()
			entry.count = n
			RPF.Fire("TRACKED")
		end })
	end
	table.insert(items, { text = OBJECTIVES_STOP_TRACKING or "Stop tracking", func = function ()
		RetailProfessionsCharDB.tracked[spell] = nil
		RPF.Fire("TRACKED")
	end })
	return items
end

-- With its profession open a click shows the recipe; otherwise the catcher below casts the
-- profession first and the recipe is picked once it has opened (Home's pending pick).
local function onBlockClick(block, button)
	local spell = block.ref
	if IsModifiedClick("CHATLINK") and GetSpellLink then
		ChatEdit_InsertLink(GetSpellLink(spell))
	elseif RPF.IsOpen() and RPF.SelectSpell(spell) then
		RPF.Home.SetActive(false)
	elseif RPF.InCombat() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "You can't do that in combat.", 1, 0.1, 0.1, 1)
	end
end

local function onBlockEnter(block)
	local H = api()
	local entry = trackedEntry(block)
	local p = entry and RPF.Profession(entry.skill)
	local spell = p and p.openName
	if not (H and spell) or RPF.InCombat() or (RPF.IsOpen() and M.skill == entry.skill and not M.linked) then return end
	local id = catcherIds[block]
	if not id then
		id = H.NewCatcherId()
		catcherIds[block] = id
	end
	H.Catchers.Bind(id, block, spell, {
		onEnter = function () H.HighlightBlock(block, true) end,
		onLeave = function () H.HighlightBlock(block, false) end,
		onDown = function (_, button)
			if button == "LeftButton" and not IsModifiedClick("CHATLINK") then
				RPF.Home.Pend({ skill = entry.skill, spell = block.ref })
			end
		end,
		onUp = function (_, button)
			if button == "RightButton" or IsModifiedClick("CHATLINK") then H.ClickBlock(block, button) end
		end,
	}, { ["shift-type1"] = "none" })
	H.Catchers.ArmFor(block)
end

local function collect(blocks)
	if not (RPF.hosting and RetailProfessionsCharDB) then return end
	for _, t in ipairs(RPF.TrackedList()) do
		local entry = t.entry
		local want = entry.count or 1
		local lines = {}
		for _, rg in ipairs(entry.reagents or {}) do
			local need = rg.n * want
			local have, bags, bank = RPF.HaveCount(rg.id)
			local info = rg.id and RPF.Item(rg.id)
			local name = (info and info.name) or rg.name or ("Item #" .. tostring(rg.id))
			table.insert(lines, { text = RPF.TrackedHaveText(have, bags, bank, need) .. " " .. name })
		end
		table.insert(blocks, { kind = "recipe", title = entry.name .. (want > 1 and (" x" .. want) or ""),
			icon = entry.icon, lines = lines, ref = t.spell, menu = trackedMenu,
			onClick = onBlockClick, onEnter = onBlockEnter })
	end
end

-- Whether tracked recipes go in DragonUI's tracker (its quest tracker module is on).
function RPF.HostTracksRecipes()
	local H = RPF.hosting and api()
	return H and H.TrackerEnabled() and RPF.hostTracker or false
end

function RPF.RefreshHostTracker()
	local H = api()
	if H then H.RefreshTracker() end
end

-----------------------------------------
-- starting and stopping

-- At login (Core.lua) and on /prof retail: true when DragonUI's window has the professions,
-- with us in it or (on /prof classic) without.
function RPF.StartHosting()
	local H = api()
	if not (H and H.Enabled()) then return false end
	if RetailProfessionsDB.classic then
		RPF.hostClassic = true
		return true
	end
	RPF.hostClassic = nil
	RPF.hosting = true
	pieces = pieces or RPF.HostPieces()
	addHome(H)
	addRefineTabs(H)
	if RPF.hostTracker == nil then RPF.hostTracker = H.AddTrackerCollector(collect) and true or false end
	H.Register(provider)
	-- Switched back while a profession is open: fill the window now.
	if TradeSkillFrame and TradeSkillFrame:IsShown() then
		RPF.HostOpened()
		RPF.active = true
		RPF.Fire("SHOW")
	end
	RPF.Fire("TRACKED")
	return true
end

-- /prof classic: DragonUI's own crafting page.
function RPF.StopHosting()
	local H = api()
	if not (RPF.hosting and H) then return end
	RPF.HostClosed()
	RPF.hosting = false
	RPF.hostClassic = true
	H.Unregister(provider)
	RPF.HostLayout(false)
	RPF.Fire("TRACKED")
	H.RefreshTracker()
end

-- The tabs follow what the window shows and what you know.
for _, event in ipairs({ "VIEW", "SKILLS", "READY" }) do
	RPF.On(event, function ()
		local H = RPF.hosting and api()
		if H then H.RefreshTabs() end
	end)
end
