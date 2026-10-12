-- Profession tabs down the right edge of the window, like the spellbook's: one per profession
-- you know that has a window, so you can switch without the spellbook, and under them one for
-- Milling and one for Prospecting when you know them.

local RPF = RetailProfessions
local M = RPF.Model

local frame = RPF.frame
local TAB_SIZE = 40
local MAX_TABS = 10

-- A tab is drawn here and clicked through the secure button lying over it, which casts the
-- spell that opens the profession. Where nothing has to be cast (the profession is already
-- open and only the view changes), the button steps aside and the tab takes the click itself.
local function createTab(buttonName, tip)
	local tab = CreateFrame("Button", nil, frame)
	tab:SetSize(TAB_SIZE, TAB_SIZE)
	tab.bg = tab:CreateTexture(nil, "BACKGROUND")
	tab.bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
	tab.bg:SetSize(64, 64)
	tab.bg:SetPoint("TOPLEFT", tab, "TOPLEFT", -4, 11)
	tab.icon = tab:CreateTexture(nil, "ARTWORK")
	tab.icon:SetSize(TAB_SIZE - 6, TAB_SIZE - 6)
	tab.icon:SetPoint("CENTER", tab, "CENTER")
	tab.checked = tab:CreateTexture(nil, "OVERLAY")
	tab.checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	tab.checked:SetBlendMode("ADD")
	tab.checked:SetAllPoints(tab.icon)
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

local function setChecked(tab, on)
	if on then tab.checked:Show() else tab.checked:Hide() end
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
	tabs[i]:SetPoint("TOPLEFT", frame, "TOPRIGHT", -2, -40 - (i - 1) * (TAB_SIZE + 8))
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

local function refresh()
	local n = 0
	local shown = {}
	local viewing = RPF.Refine.Active()
	if RetailProfessionsDB then
		for _, known in ipairs(RPF.KnownProfessions()) do
			local p = known.profession
			-- GetSpellInfo by name only answers for spells you know.
			if p.openName and GetSpellInfo(p.openName) and n < MAX_TABS then
				n = n + 1
				local tab = tabs[n]
				tab.profession, tab.rank, tab.maxRank = p, known.rank, known.maxRank
				tab.icon:SetTexture(p.texture)
				local current = M.profession == p and not M.linked
				setChecked(tab, current and not viewing)
				tab.icon:SetDesaturated(RPF.InCombat())
				tab:Show()
				if current and viewing then
					-- Already open, showing its herbs or ore: the tab goes back to the recipes.
					tab.onClick = function () RPF.Refine.SetView(nil) end
					RPF.BindSpellButton(tab.button, nil, nil)
				else
					tab.onClick = nil
					RPF.BindSpellButton(tab.button, tab, p.openName, frame)
				end
				shown[p.id] = p
			end
		end
	end
	for i = n + 1, MAX_TABS do
		tabs[i]:Hide()
		tabs[i].profession = nil
		RPF.BindSpellButton(tabs[i].button, nil, nil)
	end

	local row = n
	for _, tab in ipairs(refineTabs) do
		local kind = RPF.Refine.Known(tab.code)
		local p = kind and shown[kind.skill]
		if p then
			tab.kind = kind
			tab:ClearAllPoints()
			tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", -2, -40 - row * (TAB_SIZE + 8) - 12)
			row = row + 1
			tab.icon:SetTexture(kind.texture or p.texture)
			setChecked(tab, viewing == kind)
			tab:Show()
			if RPF.Refine.IsOpen(kind) then
				tab.icon:SetDesaturated(false)
				tab.onClick = function () RPF.Refine.SetView(kind.code) end
				RPF.BindSpellButton(tab.button, nil, nil)
			else
				-- Another profession is open: open this one's, on its herbs or ore.
				tab.icon:SetDesaturated(RPF.InCombat())
				tab.onClick = nil
				tab.button.preClick = function () RPF.Refine.Pend(kind.code) end
				RPF.BindSpellButton(tab.button, tab, p.openName, frame)
			end
		else
			tab.kind = nil
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
