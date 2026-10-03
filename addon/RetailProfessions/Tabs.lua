-- Profession tabs down the left edge of the window: one per profession you know that has a
-- window, so you can switch without the spellbook.

local RPF = RetailProfessions
local M = RPF.Model

local frame = RPF.frame
local TAB_SIZE = 40
local MAX_TABS = 10

local tabs = {}
for i = 1, MAX_TABS do
	local tab = CreateFrame("Frame", nil, frame)
	tab:SetSize(TAB_SIZE, TAB_SIZE)
	tab:SetPoint("TOPRIGHT", frame, "TOPLEFT", 2, -40 - (i - 1) * (TAB_SIZE + 8))
	tab.bg = tab:CreateTexture(nil, "BACKGROUND")
	tab.bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
	tab.bg:SetSize(64, 64)
	tab.bg:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 4, 11)
	tab.bg:SetTexCoord(1, 0, 0, 1) -- the spellbook's tabs point right; ours hang off the left
	tab.icon = tab:CreateTexture(nil, "ARTWORK")
	tab.icon:SetSize(TAB_SIZE - 6, TAB_SIZE - 6)
	tab.icon:SetPoint("CENTER", tab, "CENTER")
	tab.checked = tab:CreateTexture(nil, "OVERLAY")
	tab.checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	tab.checked:SetBlendMode("ADD")
	tab.checked:SetAllPoints(tab.icon)
	tab:Hide()

	tab.button = RPF.CreateSpellButton("RetailProfessionsTab" .. i)
	tab.button.onEnter = function (self)
		local p = tab.profession
		if not p then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(p.localName)
		if tab.rank then GameTooltip:AddLine(tab.rank .. " / " .. tab.maxRank, 1, 1, 1) end
		GameTooltip:Show()
	end
	tabs[i] = tab
end

local function refresh()
	local n = 0
	if RetailProfessionsDB then
		for _, known in ipairs(RPF.KnownProfessions()) do
			local p = known.profession
			-- GetSpellInfo by name only answers for spells you know.
			if p.openName and GetSpellInfo(p.openName) and n < MAX_TABS then
				n = n + 1
				local tab = tabs[n]
				tab.profession, tab.rank, tab.maxRank = p, known.rank, known.maxRank
				tab.icon:SetTexture(p.texture)
				if M.profession == p and not M.linked then tab.checked:Show() else tab.checked:Hide() end
				tab.icon:SetDesaturated(RPF.InCombat())
				tab:Show()
				RPF.BindSpellButton(tab.button, tab, p.openName, frame)
			end
		end
	end
	for i = n + 1, MAX_TABS do
		tabs[i]:Hide()
		tabs[i].profession = nil
		RPF.BindSpellButton(tabs[i].button, nil, nil)
	end
	RPF.SyncSpellButtons()
end

RPF.On("TRADE_SKILL_UPDATE", function () if frame:IsShown() then refresh() end end)
RPF.On("SKILLS", function () if frame:IsShown() then refresh() end end)
RPF.On("MOVED", refresh)
RPF.On("HIDDEN", RPF.SyncSpellButtons)
RPF.On("SECURE_STATE", function (on)
	for _, tab in ipairs(tabs) do tab.icon:SetDesaturated(not on) end
end)
frame:HookScript("OnShow", refresh)
RPF.FollowRaises(frame)
