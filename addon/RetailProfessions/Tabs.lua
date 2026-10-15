-- Profession tabs down the right edge of the window, like the spellbook's: Home (Home.lua) at
-- the top, one per profession you know that has a window, so you can switch without the
-- spellbook, and under them one for Milling and one for Prospecting when you know them.

local RPF = RetailProfessions
local M = RPF.Model

local frame = RPF.frame
local dragon = RPF.Dragon() and true or false
-- Every profession with a window, should one character know them all.
local MAX_TABS = 12
-- The column runs from under the title bar to just above the window's bottom edge. A tab is an
-- icon on a plate, PITCH apart; with more tabs than fit at that size (a dozen professions and
-- both refine tabs), they all shrink until the column fits.
local COLUMN_TOP, COLUMN_BOTTOM = 36, 14
local PITCH, MIN_PITCH = 42, 24
local PAD, GAP = 3, 4
local REFINE_GAP = 8
local HOME_GAP = 8
-- Under DragonUI the plate's left edge goes beneath the metal frame (whose outer edge lies
-- about 4 inside the window's own), so the tab grows out of the window. The stock dialog border
-- is drawn by the window itself, under its children, so there the plate stops short of it.
local TAB_X = dragon and -1 or 1
local TUCK = dragon and 3 or 0

local PLATE = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 10,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- A tab is drawn here and clicked through the secure button lying over it, which casts the
-- spell that opens the profession. Where nothing has to be cast (the profession is already
-- open and only the view changes), the button steps aside and the tab takes the click itself.
local function createTab(buttonName, tip)
	local tab = CreateFrame("Button", nil, frame)
	tab:SetFrameLevel(frame:GetFrameLevel() + 2)
	tab.plate = CreateFrame("Frame", nil, tab)
	tab.plate:SetFrameLevel(frame:GetFrameLevel() + 1)
	tab.plate:SetPoint("TOPLEFT", tab, "TOPLEFT", -PAD - TUCK, PAD)
	tab.plate:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", PAD, -PAD)
	tab.plate:SetBackdrop(PLATE)
	tab.plate:SetBackdropColor(0.03, 0.03, 0.03, 0.92)
	tab.icon = tab:CreateTexture(nil, "ARTWORK")
	tab.icon:SetAllPoints(tab)
	-- Without the bevel painted into every icon.
	tab.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	tab.checked = tab:CreateTexture(nil, "OVERLAY")
	tab.checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	tab.checked:SetBlendMode("ADD")
	tab.checked:SetAllPoints(tab)
	-- For the clicks the tab takes itself; the secure button has a highlight of its own.
	local hl = tab:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")
	hl:SetAllPoints(tab)
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
	return tab
end

-- The tab of what the window shows has a gold edge and its icon lit; the others stand back.
local function setChecked(tab, on)
	if on then
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
	local size = pitch - GAP - 2 * PAD
	tab:SetSize(size, size)
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

-- Home: what to do next and what earns most, across every profession. Nothing to cast: the
-- window is already open.
local homeTab = createTab("RetailProfessionsHomeTab", function ()
	GameTooltip:SetText("Home")
	GameTooltip:AddLine("What to do next and your most profitable crafts, across every profession.", 1, 1, 1, true)
	return true
end)
homeTab.onClick = function () RPF.Home.SetActive(true) end

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

local function refresh()
	local home = RPF.Home.Active()
	local viewing = not home and RPF.Refine.Active()
	local open, shown = {}, {}
	if RetailProfessionsDB then
		for _, known in ipairs(RPF.KnownProfessions()) do
			local p = known.profession
			-- GetSpellInfo by name only answers for spells you know.
			if p.openName and GetSpellInfo(p.openName) and #open < MAX_TABS then
				table.insert(open, known)
				shown[p.id] = p
			end
		end
	end
	local refining = 0
	for _, tab in ipairs(refineTabs) do
		local kind = RPF.Refine.Known(tab.code)
		tab.kind = kind and shown[kind.skill] and kind or nil
		if tab.kind then refining = refining + 1 end
	end
	-- Home sits over the professions, for your own only.
	local hasHome = #open > 0 and not M.linked
	local top = hasHome and 1 or 0
	local drop = hasHome and HOME_GAP or 0
	local pitch = pitchFor(top + #open + refining, drop + (refining > 0 and REFINE_GAP or 0))
	if hasHome then
		place(homeTab, 0, pitch, 0)
		homeTab.icon:SetTexture(RPF.Home.ICON)
		setChecked(homeTab, home)
		homeTab:Show()
	else
		homeTab:Hide()
	end

	for i, tab in ipairs(tabs) do
		local known = open[i]
		if known then
			local p = known.profession
			tab.profession, tab.rank, tab.maxRank = p, known.rank, known.maxRank
			place(tab, top + i - 1, pitch, drop)
			tab.icon:SetTexture(p.texture)
			local current = M.profession == p and not M.linked
			setChecked(tab, current and not viewing and not home)
			tab.icon:SetDesaturated(RPF.InCombat())
			tab:Show()
			if current and (viewing or home) then
				-- Already open, showing Home or its herbs or ore: the tab goes back to the recipes.
				tab.onClick = function ()
					RPF.Home.SetActive(false)
					RPF.Refine.SetView(nil)
				end
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
RPF.On("READY", function () if frame:IsShown() then refresh() end end)
RPF.On("MOVED", refresh)
RPF.On("HIDDEN", RPF.SyncSpellButtons)
RPF.On("SECURE_STATE", function (on)
	for _, tab in ipairs(tabs) do tab.icon:SetDesaturated(not on) end
	homeTab.icon:SetDesaturated(false)
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
