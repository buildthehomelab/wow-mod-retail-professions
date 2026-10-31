-- Profession tabs down the right edge of the window, like the spellbook's: Training and Profit
-- (Home.lua) at the top, one per profession you know that has a window, so you can switch
-- without the spellbook, and under them one for Milling and one for Prospecting when you know
-- them. Archaeology (ArchaeologyUI's research window) gets one among the professions too: a
-- page of this window (Pages.lua) when that ArchaeologyUI takes one.

local RPF = RetailProfessions
local M = RPF.Model

local frame = RPF.frame
local dragon = RPF.Dragon() and true or false
-- Without DragonUI, the spellbook's skill line tabs (SpellBookSkillLineTabTemplate).
local stock = not dragon
-- With DragonUI's professions art, its side tabs: the icon in a plate with a bronze edge that
-- lies over the window's metal, gold edged when it's the open one.
local art = frame.profArt
-- Every profession with a window (and Archaeology), should one character know them all.
local MAX_TABS = 13
-- The column runs from under the title bar to just above the window's bottom edge. A tab is an
-- icon on a plate, PITCH apart; with more tabs than fit at that size (a dozen professions and
-- both refine tabs), they all shrink until the column fits.
local COLUMN_TOP, COLUMN_BOTTOM = art and 60 or 36, 14
local PITCH, MIN_PITCH = art and 52 or stock and 49 or 42, 24
local PAD, GAP = (art or stock) and 0 or 3, art and 2 or 4
local REFINE_GAP = 8
local HOME_GAP = 8
-- Under DragonUI the plate's left edge goes beneath the metal frame (whose outer edge lies
-- about 4 inside the window's own), so the tab grows out of the window. The stock dialog border
-- is drawn by the window itself, under its children, so there the tab's art only just meets it.
local TAB_X = art and 0 or dragon and -1 or 1
local TUCK = dragon and 3 or 0
-- DragonUI's tab art is 55 x 60 round a 55 square tab; its icon shows through a 45 x 44 hole.
local ART_TAB = 55
local ICON_X, ICON_Y, ICON_W, ICON_H = 2, -5.5, 45, 44
local ICON_L, ICON_R, ICON_T, ICON_B = 0.096875, 0.940625, 0.0875, 0.9125
-- The stock tab is a 32 square, 17 apart, its 64 square art 3 left of it and 11 above; all of
-- it shrinks with the pitch.
local STOCK_TAB, STOCK_ART, STOCK_ART_X, STOCK_ART_Y = 32, 64, -3, 11

local PLATE = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 10,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- A tab is drawn here and clicked through the secure button lying over it, which casts the
-- spell that opens the profession. Where nothing has to be cast (the profession is already
-- open and only the view changes), the button steps aside and the tab takes the click itself.
-- One of DragonUI's tab pieces, centred on the tab.
local function artPiece(tab, layer, name)
	local t = tab:CreateTexture(nil, layer)
	art.Art.Set(t, name)
	t:SetPoint("CENTER", tab, "CENTER", 0, 0)
	table.insert(tab.pieces, t)
	return t
end

local function createArtTab(tab)
	-- Over the metal frame, as DragonUI's lie.
	tab:SetFrameLevel(frame:GetFrameLevel() + 32)
	tab.pieces = {}
	artPiece(tab, "BACKGROUND", "sidetab")
	tab.icon = tab:CreateTexture(nil, "BORDER")
	tab.icon:SetTexCoord(ICON_L, ICON_R, ICON_T, ICON_B)
	artPiece(tab, "ARTWORK", "sidetab-border")
	tab.checked = artPiece(tab, "OVERLAY", "sidetab-selected")
	artPiece(tab, "HIGHLIGHT", "sidetab-hover")
	-- The secure button over the tab takes the mouse, so it lights the tab through this copy.
	tab.hoverLock = artPiece(tab, "OVERLAY", "sidetab-hover")
	tab.hoverLock:Hide()
end

local function createTab(buttonName, tip)
	local tab = CreateFrame("Button", nil, frame)
	if art then
		createArtTab(tab)
	else
		tab:SetFrameLevel(frame:GetFrameLevel() + 2)
		if stock then
			tab.art = tab:CreateTexture(nil, "BACKGROUND")
			tab.art:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
		else
			tab.plate = CreateFrame("Frame", nil, tab)
			tab.plate:SetFrameLevel(frame:GetFrameLevel() + 1)
			tab.plate:SetPoint("TOPLEFT", tab, "TOPLEFT", -PAD - TUCK, PAD)
			tab.plate:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", PAD, -PAD)
			tab.plate:SetBackdrop(PLATE)
			tab.plate:SetBackdropColor(0.03, 0.03, 0.03, 0.92)
		end
		tab.icon = tab:CreateTexture(nil, "ARTWORK")
		tab.icon:SetAllPoints(tab)
		if not stock then
			-- Without the bevel painted into every icon.
			tab.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		end
		tab.checked = tab:CreateTexture(nil, "OVERLAY")
		tab.checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		tab.checked:SetBlendMode("ADD")
		tab.checked:SetAllPoints(tab)
		-- For the clicks the tab takes itself; the secure button has a highlight of its own.
		local hl = tab:CreateTexture(nil, "HIGHLIGHT")
		hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
		hl:SetBlendMode("ADD")
		hl:SetAllPoints(tab)
	end
	tab:Hide()

	local function onEnter(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if tip(tab) then GameTooltip:Show() end
	end
	tab:SetScript("OnEnter", onEnter)
	tab:SetScript("OnLeave", function () GameTooltip:Hide() end)
	tab:SetScript("OnClick", function () if tab.onClick then tab.onClick() end end)
	tab.button = RPF.CreateSpellButton(buttonName)
	tab.button.onEnter = onEnter
	if art then
		-- The tab's own hover art instead of the button's square.
		tab.button.highlight:SetAlpha(0)
		tab.button.onEnter = function (self)
			tab.hoverLock:Show()
			onEnter(self)
		end
		tab.button.onLeave = function () tab.hoverLock:Hide() end
	end
	return tab
end

-- The tab of what the window shows has a gold edge and its icon lit; the others stand back.
-- The spellbook's tabs only light the open one.
local function setChecked(tab, on)
	if art or stock then
		if on then tab.checked:Show() else tab.checked:Hide() end
	elseif on then
		tab.checked:Show()
		tab.plate:SetBackdropBorderColor(1, 0.82, 0, 1)
		tab.icon:SetVertexColor(1, 1, 1)
	else
		tab.checked:Hide()
		tab.plate:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
		tab.icon:SetVertexColor(0.8, 0.8, 0.8)
	end
end

-- How far apart `count` tabs go: PITCH, or less when that many don't fit in the column with
-- `gaps` of space between its groups.
local function pitchFor(count, gaps)
	local room = frame:GetHeight() - COLUMN_TOP - COLUMN_BOTTOM - gaps
	return math.max(MIN_PITCH, math.min(PITCH, math.floor(room / math.max(count, 1))))
end

-- Puts a tab on the column's nth row (from 0), `drop` further down.
local function place(tab, row, pitch, drop)
	local size = stock and math.floor(pitch * STOCK_TAB / PITCH) or pitch - GAP - 2 * PAD
	tab:SetSize(size, size)
	if stock then
		local k = size / STOCK_TAB
		tab.art:SetSize(STOCK_ART * k, STOCK_ART * k)
		tab.art:ClearAllPoints()
		tab.art:SetPoint("TOPLEFT", tab, "TOPLEFT", STOCK_ART_X * k, STOCK_ART_Y * k)
	elseif art then
		-- DragonUI's art and icon hole, scaled to the tab.
		local k = size / ART_TAB
		for _, t in ipairs(tab.pieces) do t:SetSize(ART_TAB * k, 60 * k) end
		tab.icon:SetSize(ICON_W * k, ICON_H * k)
		tab.icon:ClearAllPoints()
		tab.icon:SetPoint("TOPLEFT", tab, "TOPLEFT", ICON_X * k, ICON_Y * k)
		-- A secure button that went away under the mouse never said so.
		tab.hoverLock:Hide()
	end
	tab:ClearAllPoints()
	tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", TAB_X, -COLUMN_TOP - PAD - row * pitch - drop)
end

local tabs = {}
for i = 1, MAX_TABS do
	tabs[i] = createTab("RetailProfessionsTab" .. i, function (tab)
		local p = tab.profession
		if not p then return false end
		GameTooltip:SetText(p.localName)
		if tab.rank then GameTooltip:AddLine(tab.rank .. " / " .. tab.maxRank, 1, 1, 1) end
		return true
	end)
end

-- Training (what to do next) and Profit (what earns most), across every profession. Nothing to
-- cast: the window is already open.
local viewTabs = {}
for _, key in ipairs(RPF.Home.ORDER) do
	local view = RPF.Home.VIEWS[key]
	local name = "RetailProfessions" .. view.title .. "Tab"
	local tab = createTab(name, function ()
		GameTooltip:SetText(view.title)
		GameTooltip:AddLine(view.tip, 1, 1, 1, true)
		return true
	end)
	tab.view = key
	tab.onClick = function () RPF.Home.SetActive(key) end
	table.insert(viewTabs, tab)
end

-- Milling and Prospecting (Refine.lua) get a tab each under the professions: the herbs or ore
-- you have, what they give, and Mill All.
local refineTabs = {}
for _, code in ipairs({ "M", "P" }) do
	local tab = createTab("RetailProfessionsRefineTab" .. code, function (tab)
		local kind = tab.kind
		if not kind then return false end
		GameTooltip:SetText(kind.name)
		GameTooltip:AddLine(string.format("Your %s, what each gives, and %s.", code == "M" and "herbs" or "ore", kind.all),
			1, 1, 1, true)
		return true
	end)
	tab.code = code
	table.insert(refineTabs, tab)
end

-- Archaeology's tab has nothing to cast: ArchaeologyUI's research view opens as a page of this
-- window, the profession staying open behind it. An older ArchaeologyUI has only its own
-- window, which takes this one's place, as the professions book's Open does; in combat this one
-- stays then, its secure buttons can't be put away until it ends.
local function openArchaeology()
	if not RPF.Pages.Has("archaeology") and not RPF.InCombat() then frame:Hide() end
	RPF.OpenArchaeology()
end

-- Back to the open profession's recipes, from a page, Training, Profit or its herbs or ore.
local function backToRecipes()
	RPF.Pages.Close()
	RPF.Home.SetActive(false)
	RPF.Refine.SetView(nil)
end

local function refresh()
	-- In DragonUI's window its side tabs carry ours (Host.lua).
	if RPF.hosting then
		for _, tab in ipairs(viewTabs) do
			tab:Hide()
			RPF.BindSpellButton(tab.button, nil, nil, nil, true)
		end
		for _, tab in ipairs(tabs) do
			tab:Hide()
			RPF.BindSpellButton(tab.button, nil, nil, nil, true)
		end
		for _, tab in ipairs(refineTabs) do
			tab:Hide()
			RPF.BindSpellButton(tab.button, nil, nil, nil, true)
		end
		RPF.SyncSpellButtons()
		return
	end
	local home = RPF.Home.Active()
	local page = RPF.Pages.Current()
	local viewing = not home and not page and RPF.Refine.Active()
	local open, shown, windows = {}, {}, 0
	if RetailProfessionsDB then
		for _, known in ipairs(RPF.KnownProfessions()) do
			local p = known.profession
			-- GetSpellInfo by name only answers for spells you know. KnownProfessions only lists
			-- Archaeology with ArchaeologyUI loaded.
			if #open < MAX_TABS and (p.archaeology or p.openName and GetSpellInfo(p.openName)) then
				table.insert(open, known)
				shown[p.id] = p
				if not p.archaeology then windows = windows + 1 end
			end
		end
	end
	local refining = 0
	for _, tab in ipairs(refineTabs) do
		local kind = RPF.Refine.Known(tab.code)
		tab.kind = kind and shown[kind.skill] and kind or nil
		if tab.kind then refining = refining + 1 end
	end
	-- Training, Profit and Equipment sit over the professions, for your own only, with one open
	-- (not on a page with none behind it). Equipment only on a realm with profession gear.
	local hasHome = windows > 0 and not M.linked and RPF.IsOpen()
	local top = 0
	if hasHome then
		for _, tab in ipairs(viewTabs) do
			if RPF.Home.Shown(tab.view) then top = top + 1 end
		end
	end
	local drop = hasHome and HOME_GAP or 0
	local pitch = pitchFor(top + #open + refining, drop + (refining > 0 and REFINE_GAP or 0))
	local viewRow = 0
	for _, tab in ipairs(viewTabs) do
		if hasHome and RPF.Home.Shown(tab.view) then
			place(tab, viewRow, pitch, 0)
			viewRow = viewRow + 1
			tab.icon:SetTexture(RPF.Home.VIEWS[tab.view].icon)
			setChecked(tab, home == tab.view)
			tab:Show()
		else
			tab:Hide()
		end
	end

	for i, tab in ipairs(tabs) do
		local known = open[i]
		if known then
			local p = known.profession
			tab.profession, tab.rank, tab.maxRank = p, known.rank, known.maxRank
			place(tab, top + i - 1, pitch, drop)
			tab.icon:SetTexture(p.texture)
			local current = M.profession == p and not M.linked and RPF.IsOpen()
			if p.archaeology then
				setChecked(tab, page == "archaeology")
			else
				setChecked(tab, current and not viewing and not home and not page)
			end
			tab.icon:SetDesaturated(RPF.InCombat() and not p.archaeology)
			tab:Show()
			if p.archaeology then
				tab.onClick = openArchaeology
				RPF.BindSpellButton(tab.button, nil, nil)
			elseif current and (viewing or home or page) then
				-- Already open, behind a page or showing Training, Profit or its herbs or ore: the
				-- tab goes back to the recipes.
				tab.onClick = backToRecipes
				RPF.BindSpellButton(tab.button, nil, nil)
			else
				tab.onClick = nil
				RPF.BindSpellButton(tab.button, tab, p.openName, frame)
			end
		else
			tab:Hide()
			tab.profession = nil
			RPF.BindSpellButton(tab.button, nil, nil)
		end
	end

	local row = top + #open
	for _, tab in ipairs(refineTabs) do
		local kind = tab.kind
		if kind then
			local p = shown[kind.skill]
			place(tab, row, pitch, drop + REFINE_GAP)
			row = row + 1
			tab.icon:SetTexture(kind.texture or p.texture)
			setChecked(tab, viewing == kind)
			tab:Show()
			if RPF.Refine.IsOpen(kind) then
				tab.icon:SetDesaturated(false)
				tab.onClick = function ()
					RPF.Pages.Close()
					RPF.Home.SetActive(false)
					RPF.Refine.SetView(kind.code)
				end
				RPF.BindSpellButton(tab.button, nil, nil)
			else
				-- Another profession is open: open this one's, on its herbs or ore.
				tab.icon:SetDesaturated(RPF.InCombat())
				tab.onClick = nil
				tab.button.preClick = function () RPF.Refine.Pend(kind.code) end
				RPF.BindSpellButton(tab.button, tab, p.openName, frame)
			end
		else
			tab:Hide()
			RPF.BindSpellButton(tab.button, nil, nil)
		end
	end
	RPF.SyncSpellButtons()
end

RPF.On("TRADE_SKILL_UPDATE", function () if frame:IsShown() then refresh() end end)
RPF.On("SKILLS", function () if frame:IsShown() then refresh() end end)
RPF.On("VIEW", function () if frame:IsShown() then refresh() end end)
RPF.On("PAGE", function () if frame:IsShown() then refresh() end end)
RPF.On("READY", function () if frame:IsShown() then refresh() end end)
-- Equipment's tab comes and goes with the realm's profession gear.
local gearShown
RPF.On("GEAR", function ()
	local shown = RPF.Home.Shown("equipment")
	if shown == gearShown then return end
	gearShown = shown
	if frame:IsShown() then refresh() end
end)
RPF.On("MOVED", refresh)
RPF.On("HIDDEN", RPF.SyncSpellButtons)
RPF.On("SECURE_STATE", function (on)
	-- Archaeology's tab opens ArchaeologyUI's window, which works in combat too.
	for _, tab in ipairs(tabs) do
		tab.icon:SetDesaturated(not on and not (tab.profession and tab.profession.archaeology))
	end
	for _, tab in ipairs(viewTabs) do tab.icon:SetDesaturated(false) end
	-- A tab that only changes the view works in combat too.
	for _, tab in ipairs(refineTabs) do tab.icon:SetDesaturated(not on and tab.onClick == nil) end
end)
frame:HookScript("OnShow", refresh)
RPF.FollowRaises(frame)

-- This window has ReagentBankUI's profession controls built in (Frame.lua), and ReagentBankUI
-- dropped its sidebar for that. One from before still docks it here, over the tabs: hide it
-- after each dock.
RPF.On("LOGIN", function ()
	local RB = _G.ReagentBankUI
	if not (RB and RB.DockTradeSkillPanel and hooksecurefunc) then return end
	hooksecurefunc(RB, "DockTradeSkillPanel", function (self)
		local panel = self.tradeSkillPanel
		local host = self.GetTradeSkillControlsHost and self:GetTradeSkillControlsHost()
		if panel and host == frame then panel:Hide() end
	end)
end)
