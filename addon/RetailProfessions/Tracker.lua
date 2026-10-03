-- Tracked recipes: a shopping list on screen, like tracked quests. Each recipe shows the
-- reagents you still need for the number of crafts you want, counting your bags and (when the
-- setting is on) the reagent bank, and turns green when you have it all.
--
-- Right-click a recipe in the profession window (or tick "Track recipe") to track it. In the
-- tracker, click a recipe to show it in the window, right-click it for the amount or to stop
-- tracking. Drag the title to move the list.

local RPF = RetailProfessions
local M = RPF.Model

local MAX_TRACKED = 8
local WIDTH = 240
local LINE_HEIGHT = 15

local tracker = CreateFrame("Frame", "RetailProfessionsTracker", UIParent)
tracker:SetSize(WIDTH, 20)
tracker:SetMovable(true)
tracker:SetClampedToScreen(true)
tracker:SetFrameStrata("LOW")
tracker:Hide()

local function placeTracker()
	tracker:ClearAllPoints()
	local p = RetailProfessionsDB and RetailProfessionsDB.trackerPosition
	if p then
		tracker:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		tracker:SetPoint("TOPRIGHT", UIParent, "RIGHT", -70, 40)
	end
end

local header = CreateFrame("Button", nil, tracker)
header:SetHeight(18)
header:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, 0)
header:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, 0)
header:RegisterForDrag("LeftButton")
header:RegisterForClicks("LeftButtonUp")
header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
header.text:SetPoint("LEFT", header, "LEFT", 0, 0)
header.text:SetText(TRADE_SKILLS or "Professions")
header.toggle = header:CreateTexture(nil, "ARTWORK")
header.toggle:SetSize(14, 14)
header.toggle:SetPoint("RIGHT", header, "RIGHT", 0, 0)
header:SetScript("OnDragStart", function () tracker:StartMoving() end)
header:SetScript("OnDragStop", function ()
	tracker:StopMovingOrSizing()
	local point, _, relativePoint, x, y = tracker:GetPoint(1)
	RetailProfessionsDB.trackerPosition = { point, relativePoint, x, y }
end)
header:SetScript("OnClick", function ()
	RetailProfessionsCharDB.trackerCollapsed = not RetailProfessionsCharDB.trackerCollapsed or nil
	RPF.Fire("TRACKED")
end)
header:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Tracked recipes")
	GameTooltip:AddLine("Click to fold, drag to move.", 1, 1, 1)
	GameTooltip:Show()
end)
header:SetScript("OnLeave", function () GameTooltip:Hide() end)

RPF.On("RESET_POSITION", function ()
	RetailProfessionsDB.trackerPosition = nil
	placeTracker()
end)

local menu = CreateFrame("Frame", "RetailProfessionsTrackerMenu", UIParent, "UIDropDownMenuTemplate")

local function trackedMenu(spell)
	local entry = RetailProfessionsCharDB.tracked[spell]
	if not entry then return end
	local items = { { text = entry.name, isTitle = true, notCheckable = true } }
	for _, n in ipairs({ 1, 2, 3, 5, 10, 20 }) do
		table.insert(items, { text = "Make " .. n, checked = (entry.count or 1) == n, func = function ()
			entry.count = n
			RPF.Fire("TRACKED")
		end })
	end
	table.insert(items, { text = "Stop tracking", notCheckable = true, func = function ()
		RetailProfessionsCharDB.tracked[spell] = nil
		RPF.Fire("TRACKED")
	end })
	return items
end

-- Clicks: a recipe line shows the recipe or opens its menu, a reagent line links the item.
local function onLineClick(self, button)
	if self.spell then
		if button == "RightButton" then
			EasyMenu(trackedMenu(self.spell), menu, "cursor", 0, 0, "MENU")
		elseif IsModifiedClick("CHATLINK") and GetSpellLink then
			ChatEdit_InsertLink(GetSpellLink(self.spell))
		elseif not (RPF.frame:IsShown() and RPF.SelectSpell(self.spell)) then
			local entry = RetailProfessionsCharDB.tracked[self.spell]
			local p = entry and RPF.Profession(entry.skill)
			RPF.Print("open " .. (p and p.localName or "the profession") .. " to make " .. (entry and entry.name or "it") .. ".")
		end
	elseif self.link and IsModifiedClick("CHATLINK") then
		local info = RPF.Item(tonumber(self.link:match("item:(%d+)")))
		if info then ChatEdit_InsertLink(info.link) end
	end
end

local function onLineEnter(self)
	if self.link then
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetHyperlink(self.link)
		GameTooltip:Show()
	elseif self.spell then
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetHyperlink("spell:" .. self.spell)
		GameTooltip:AddLine("Click to show it, right-click for the amount or to stop tracking.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end
end

local lines = {}
local function line(i)
	if lines[i] then return lines[i] end
	local b = CreateFrame("Button", nil, tracker)
	b:SetHeight(LINE_HEIGHT)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
	b.text:SetJustifyH("LEFT")
	b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.count:SetPoint("RIGHT", b, "RIGHT", 0, 0)
	b.count:SetJustifyH("RIGHT")
	b.text:SetPoint("RIGHT", b.count, "LEFT", -4, 0)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(LINE_HEIGHT - 2, LINE_HEIGHT - 2)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(b)
	hl:SetTexture(1, 1, 1, 0.06)
	b:SetScript("OnClick", onLineClick)
	b:SetScript("OnEnter", onLineEnter)
	b:SetScript("OnLeave", function () GameTooltip:Hide() end)
	lines[i] = b
	return b
end

-- Ordered by when they were tracked.
local function trackedList()
	local list = {}
	for spell, entry in pairs(RetailProfessionsCharDB.tracked) do
		table.insert(list, { spell = spell, entry = entry })
	end
	table.sort(list, function (a, b) return (a.entry.added or 0) < (b.entry.added or 0) end)
	return list
end

local function haveText(have, bags, bank, need)
	local color = bags >= need and "|cff40ff40" or (have >= need and "|cffffd200" or "|cffff6060")
	local text = color .. math.min(have, need) .. "/" .. need .. "|r"
	if bank > 0 and bags < need and RetailProfessionsDB.countBank then text = text .. " |cff4fc3f7bank|r" end
	return text
end

local function refresh()
	if not RetailProfessionsCharDB then return end
	local list = trackedList()
	if #list == 0 then
		tracker:Hide()
		return
	end
	placeTracker()
	tracker:Show()

	local collapsed = RetailProfessionsCharDB.trackerCollapsed
	header.toggle:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
	header.text:SetText((TRADE_SKILLS or "Professions") .. (collapsed and (" |cff9d9d9d(" .. #list .. ")|r") or ""))

	local n, y = 0, -20
	if not collapsed then
		for _, t in ipairs(list) do
			local entry = t.entry
			local want = entry.count or 1
			local ready = true
			local reagentLines = {}
			for _, rg in ipairs(entry.reagents or {}) do
				local need = rg.n * want
				local have, bags, bank = RPF.HaveCount(rg.id)
				if have < need then ready = false end
				table.insert(reagentLines, { rg = rg, need = need, have = have, bags = bags, bank = bank })
			end

			n = n + 1
			local b = line(n)
			b.spell, b.link = t.spell, nil
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, y)
			b:SetPoint("RIGHT", tracker, "RIGHT", 0, 0)
			b.icon:SetTexture(entry.icon)
			b.icon:ClearAllPoints()
			b.icon:SetPoint("LEFT", b, "LEFT", 0, 0)
			b.icon:Show()
			b.text:SetPoint("LEFT", b, "LEFT", LINE_HEIGHT + 2, 0)
			b.text:SetFontObject(GameFontNormalSmall)
			b.text:SetText((ready and "|cff40ff40" or "|cffffffff") .. entry.name .. "|r")
			b.count:SetText(want > 1 and ("|cff9d9d9dx" .. want .. "|r") or "")
			b:Show()
			y = y - LINE_HEIGHT - 1

			for _, r in ipairs(reagentLines) do
				n = n + 1
				local rb = line(n)
				rb.spell = nil
				rb.link = r.rg.id and ("item:" .. r.rg.id) or nil
				rb:ClearAllPoints()
				rb:SetPoint("TOPLEFT", tracker, "TOPLEFT", 10, y)
				rb:SetPoint("RIGHT", tracker, "RIGHT", 0, 0)
				rb.icon:Hide()
				rb.text:SetPoint("LEFT", rb, "LEFT", 6, 0)
				rb.text:SetFontObject(GameFontHighlightSmall)
				local info = r.rg.id and RPF.Item(r.rg.id)
				local name = (info and info.name) or r.rg.name or ("Item #" .. tostring(r.rg.id))
				rb.text:SetText((r.have >= r.need and "|cff9d9d9d" or "|cffd0d0d0") .. "- " .. name .. "|r")
				rb.count:SetText(haveText(r.have, r.bags, r.bank, r.need))
				rb:Show()
				y = y - LINE_HEIGHT
			end
			y = y - 4
		end
	end
	for i = n + 1, #lines do lines[i]:Hide() end
	tracker:SetHeight(-y)
end

-----------------------------------------
-- tracking

function RPF.IsTracked(r)
	return r and r.spell and RetailProfessionsCharDB.tracked[r.spell] ~= nil
end

function RPF.ToggleTracked(r)
	if not (r and r.spell) then return end
	local tracked = RetailProfessionsCharDB.tracked
	if tracked[r.spell] then
		tracked[r.spell] = nil
	else
		local count = 0
		for _ in pairs(tracked) do count = count + 1 end
		if count >= MAX_TRACKED then
			RPF.Status("You can track " .. MAX_TRACKED .. " recipes at a time.", true)
			return
		end
		local reagents = {}
		for _, rg in ipairs(r.reagents) do
			if rg.id then table.insert(reagents, { id = rg.id, n = rg.n, name = M.ReagentName(rg) }) end
		end
		tracked[r.spell] = { name = r.name, icon = r.icon, skill = M.skill, count = math.max(1, RPF.GetQuantity and RPF.GetQuantity() or 1),
			reagents = reagents, added = time() }
	end
	RPF.Fire("TRACKED")
end

RPF.On("TRACKED", refresh)
RPF.On("BAGS", refresh)
RPF.On("ITEM_INFO", refresh)
RPF.On("LOGIN", function () RPF.After(1, refresh) end)
