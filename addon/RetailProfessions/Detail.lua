-- The selected recipe: what it makes, how likely it is to raise your skill (a bar showing where
-- it turns yellow, green and grey and where you are), tools and cooldown, the reagents with
-- what you have, and for a recipe you haven't learned, where to learn it.

local RPF = RetailProfessions
local M = RPF.Model

local pane = RPF.detailPane
local PAD = 14
local GAUGE_WIDTH = 470
local MAX_REAGENTS = 8
local MAX_SOURCES = 9

local function label(parent, font, r, g, b)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	if r then fs:SetTextColor(r, g, b) end
	return fs
end

local function sectionTitle(parent, text)
	local fs = label(parent, "GameFontNormal")
	fs:SetText(text)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetTexture(1, 0.82, 0, 0.25)
	rule:SetHeight(1)
	rule:SetPoint("LEFT", fs, "RIGHT", 8, 0)
	rule:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
	fs.rule = rule
	return fs
end

local function itemTooltip(owner, link)
	if not link then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(link)
	GameTooltip:Show()
end

local function linkOrNothing(link)
	if link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(link) return true end
	return false
end

-----------------------------------------
-- top: icon, name, what it makes

local icon = RPF.CreateItemButton(pane, 42)
icon:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -PAD)
icon:SetScript("OnEnter", function (self) itemTooltip(self, self.link) end)
icon:SetScript("OnLeave", function () GameTooltip:Hide() end)
icon:SetScript("OnClick", function (self) linkOrNothing(self.link) end)

local nameText = label(pane, "GameFontNormalLarge")
nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
nameText:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)

local subText = label(pane, "GameFontHighlightSmall")
subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
subText:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)

local description = label(pane, "GameFontHighlightSmall", 0.85, 0.85, 0.85)
description:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
description:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)

local empty = label(pane, "GameFontDisable")
empty:SetPoint("CENTER", pane, "CENTER")
empty:SetText("Pick a recipe on the left.")

-----------------------------------------
-- skill-up

local skillTitle = sectionTitle(pane, "Skill-up")
skillTitle:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -10)

local skillLine = label(pane, "GameFontHighlight")
skillLine:SetPoint("TOPLEFT", skillTitle, "BOTTOMLEFT", 0, -6)
skillLine:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)

local gauge = CreateFrame("Frame", nil, pane)
gauge:SetSize(GAUGE_WIDTH, 10)
gauge:SetPoint("TOPLEFT", skillLine, "BOTTOMLEFT", 0, -18)
gauge.bg = gauge:CreateTexture(nil, "BACKGROUND")
gauge.bg:SetAllPoints(gauge)
gauge.bg:SetTexture(0, 0, 0, 0.6)
gauge.segments = {}
for i = 1, 4 do
	local seg = gauge:CreateTexture(nil, "ARTWORK")
	seg:SetHeight(10)
	gauge.segments[i] = seg
end
gauge.ticks = {}
for i = 1, 4 do
	local t = label(gauge, "GameFontHighlightSmall")
	t:SetJustifyH("CENTER")
	gauge.ticks[i] = t
end
gauge.marker = gauge:CreateTexture(nil, "OVERLAY")
gauge.marker:SetTexture(1, 1, 1, 1)
gauge.marker:SetSize(2, 18)
gauge.you = label(gauge, "GameFontHighlightSmall")
gauge.you:SetJustifyH("CENTER")

local SEGMENT_COLORS = {
	M.DIFFICULTY_COLOR.optimal, M.DIFFICULTY_COLOR.medium, M.DIFFICULTY_COLOR.easy, M.DIFFICULTY_COLOR.trivial,
}

local function hexColor(c)
	return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-- Bars from the skill the recipe needs up to a bit past grey, split where its colour changes.
local function drawGauge(r, rank)
	local lo = math.min(r.reqSkill or r.yellow, r.yellow)
	local hi = r.grey + math.max(10, math.floor((r.grey - lo) * 0.2))
	if hi <= lo then hi = lo + 1 end
	local function x(v) return math.max(0, math.min(GAUGE_WIDTH, (v - lo) / (hi - lo) * GAUGE_WIDTH)) end

	local bounds = { lo, r.yellow, r.green, r.grey, hi }
	for i, seg in ipairs(gauge.segments) do
		local from, to = x(bounds[i]), x(bounds[i + 1])
		local c = SEGMENT_COLORS[i]
		if to - from >= 1 then
			seg:ClearAllPoints()
			seg:SetPoint("LEFT", gauge, "LEFT", from, 0)
			seg:SetWidth(to - from)
			seg:SetTexture(c[1], c[2], c[3], 0.85)
			seg:Show()
		else
			seg:Hide()
		end
	end

	local tickValues = { lo, r.yellow, r.green, r.grey }
	local lastX = -100
	for i, t in ipairs(gauge.ticks) do
		local px = x(tickValues[i])
		-- Thresholds that sit on top of each other share one label.
		if px - lastX >= 26 then
			t:ClearAllPoints()
			t:SetPoint("TOP", gauge, "TOPLEFT", px, -12)
			t:SetText((i == 1 and "|cffffffff" or hexColor(SEGMENT_COLORS[i])) .. tickValues[i] .. "|r")
			t:Show()
			lastX = px
		else
			t:Hide()
		end
	end

	local mx = x(rank)
	gauge.marker:ClearAllPoints()
	gauge.marker:SetPoint("CENTER", gauge, "LEFT", mx, 0)
	gauge.you:ClearAllPoints()
	gauge.you:SetPoint("BOTTOM", gauge, "TOPLEFT", mx, 4)
	gauge.you:SetText("you " .. rank)
	gauge:Show()
end

local DIFFICULTY_TEXT = {
	optimal = "|cffff8040Guaranteed skill-up|r",
	medium = "|cffffff00Likely skill-up|r",
	easy = "|cff40c040Unlikely skill-up|r",
	trivial = "|cff808080No skill-up|r",
}

local function drawSkill(r)
	local rank = M.rank or 0
	local hasThresholds = r.grey and r.grey > 0
	if not r.learned then
		local need = r.reqSkill or 0
		if need > rank then
			skillLine:SetText(string.format("|cffff4040Learn at %d|r - you have %d.", need, rank))
		else
			skillLine:SetText(string.format("You can learn this now (needs %d).", need))
		end
	elseif M.linked then
		skillLine:SetText(DIFFICULTY_TEXT[r.difficulty] or "")
	else
		local chance = hasThresholds and RPF.SkillUpChance(rank, r.yellow, r.grey)
		local difficulty = M.DifficultyAt(r, rank)
		if chance then
			if chance <= 0 then
				skillLine:SetText("|cff808080No more skill-ups from this recipe.|r")
			else
				local c = M.DIFFICULTY_COLOR[difficulty] or M.DIFFICULTY_COLOR.easy
				local gain = (RPF.skillGain or 1) > 1 and string.format("  |cffb0b0b0(+%d skill each time)|r", RPF.skillGain) or ""
				skillLine:SetText(string.format("Chance to raise your skill: %s%d%%|r%s", hexColor(c), chance, gain))
			end
		else
			skillLine:SetText(DIFFICULTY_TEXT[difficulty] or "")
		end
	end
	if hasThresholds then drawGauge(r, rank) else gauge:Hide() end
end

-----------------------------------------
-- tools and cooldown

local requires = label(pane, "GameFontHighlightSmall")
requires:SetPoint("TOPLEFT", gauge, "BOTTOMLEFT", 0, -24)
requires:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)

-----------------------------------------
-- reagents: two columns of icon, name and have/need

local reagentTitle = sectionTitle(pane, "Reagents")

local reagentSlots = {}
for i = 1, MAX_REAGENTS do
	local slot = RPF.CreateItemButton(pane, 34)
	local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
	slot:SetPoint("TOPLEFT", reagentTitle, "BOTTOMLEFT", col * 250, -6 - row * 40)
	slot.name = label(pane, "GameFontHighlightSmall")
	slot.name:SetPoint("TOPLEFT", slot, "TOPRIGHT", 6, -3)
	slot.name:SetWidth(200)
	slot.have = label(pane, "GameFontHighlightSmall")
	slot.have:SetPoint("BOTTOMLEFT", slot, "BOTTOMRIGHT", 6, 3)
	slot:SetScript("OnEnter", function (self) itemTooltip(self, self.link) end)
	slot:SetScript("OnLeave", function () GameTooltip:Hide() end)
	slot:SetScript("OnClick", function (self) linkOrNothing(self.link) end)
	slot.Hide2 = function (self) self:Hide(); self.name:Hide(); self.have:Hide() end
	slot.Show2 = function (self) self:Show(); self.name:Show(); self.have:Show() end
	reagentSlots[i] = slot
end

local noReagents = label(pane, "GameFontDisableSmall")
noReagents:SetPoint("TOPLEFT", reagentTitle, "BOTTOMLEFT", 0, -6)
noReagents:SetText("No reagents.")

local function drawReagents(r)
	local shown = 0
	for i, slot in ipairs(reagentSlots) do
		local rg = r.reagents[i]
		if rg then
			shown = i
			local info = rg.id and RPF.Item(rg.id)
			local link = rg.link or (info and info.link) or (rg.id and ("item:" .. rg.id))
			slot.link = link
			slot:SetItem(rg.texture or (info and info.texture) or RPF.ItemIcon(rg.id), info and info.quality, rg.n)
			slot.name:SetText(M.ReagentName(rg) or ("Item #" .. tostring(rg.id or "?")))
			local bags = rg.id and GetItemCount(rg.id) or 0
			local bank = rg.id and RPF.BankCount(rg.id) or 0
			local text
			if bags >= rg.n then
				text = string.format("|cff40ff40%d|r / %d", bags, rg.n)
			elseif bags + bank >= rg.n and RetailProfessionsDB.countBank then
				text = string.format("|cffffd200%d|r / %d", bags, rg.n)
			else
				text = string.format("|cffff4040%d|r / %d", bags, rg.n)
			end
			if bank > 0 then text = text .. string.format("  |cff4fc3f7+%d bank|r", bank) end
			slot.have:SetText(text)
			slot:Show2()
		else
			slot:Hide2()
		end
	end
	if shown == 0 then noReagents:Show() else noReagents:Hide() end
	return math.max(1, math.ceil(shown / 2))
end

-----------------------------------------
-- where to learn it

local sourceTitle = sectionTitle(pane, "Where to learn")

local recipeItemButton = CreateFrame("Button", nil, pane)
recipeItemButton:SetHeight(16)
recipeItemButton:SetPoint("TOPLEFT", sourceTitle, "BOTTOMLEFT", 0, -6)
recipeItemButton:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
recipeItemButton.text = label(recipeItemButton, "GameFontHighlightSmall")
recipeItemButton.text:SetAllPoints(recipeItemButton)
recipeItemButton:SetScript("OnEnter", function (self) itemTooltip(self, self.link) end)
recipeItemButton:SetScript("OnLeave", function () GameTooltip:Hide() end)
recipeItemButton:SetScript("OnClick", function (self) linkOrNothing(self.link) end)

local sourceRows = {}
for i = 1, MAX_SOURCES do
	local row = CreateFrame("Frame", nil, pane)
	row:SetHeight(18)
	row:SetPoint("TOPLEFT", recipeItemButton, "BOTTOMLEFT", 0, -2 - (i - 1) * 18)
	row:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
	row.text = label(row, "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.map = RPF.CreateButton(row, "Map", 44, 18)
	row.map:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.text:SetPoint("RIGHT", row.map, "LEFT", -6, 0)
	row.map:SetScript("OnClick", function (self)
		local src = self:GetParent().source
		if not src then return end
		RPF.ShowOnMap(src.kind, src.id, function (where, err)
			if where then
				RPF.Status(src.name .. ": " .. where .. ". Marked on your map when it's on this continent.")
			else
				RPF.Status("Couldn't find " .. src.name .. " where you can reach it.", true)
			end
		end)
	end)
	sourceRows[i] = row
end

local sourceNote = label(pane, "GameFontDisableSmall")
sourceNote:SetPoint("TOPLEFT", recipeItemButton, "BOTTOMLEFT", 0, -2)
sourceNote:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)

local GOLD = "|cffffd200"

local function chanceText(x100)
	x100 = tonumber(x100) or 0
	if x100 <= 0 then return "" end
	local pct = x100 / 100
	return string.format(" - %s%%", pct >= 10 and string.format("%d", math.floor(pct)) or string.format("%.1f", pct))
end

local function where(src)
	return src.zone ~= "" and (" - |cffb0b0b0" .. src.zone .. "|r") or ""
end

local function sourceText(src, r)
	local k = src.kind
	if k == "A" then
		local at = tonumber(src.a) or 0
		return at <= 1 and (GOLD .. "Learned|r with the profession") or string.format("%sLearned|r automatically at skill %d", GOLD, at)
	elseif k == "T" then
		return string.format("%sTrainer|r  %s%s - %s", GOLD, src.name, where(src), RPF.Money(src.a))
	elseif k == "V" then
		local text = string.format("%sVendor|r  %s%s", GOLD, src.name, where(src))
		if (tonumber(src.a) or 0) > 0 then text = text .. " - " .. RPF.Money(src.a) end
		if tostring(src.b) == "1" then text = text .. " |cffb0b0b0(limited)|r" end
		if src.c and src.c ~= "" then text = text .. " |cffff8040" .. src.c .. "|r" end
		return text
	elseif k == "D" then
		return string.format("%sDrop|r  %s |cffb0b0b0(level %s)|r%s%s", GOLD, src.name, tostring(src.b), where(src), chanceText(src.a))
	elseif k == "X" then
		return string.format("%sWorld drop|r from %s creatures, level %s", GOLD, tostring(src.a), tostring(src.b))
	elseif k == "O" then
		return string.format("%sFound in|r  %s%s%s", GOLD, src.name, where(src), chanceText(src.a))
	elseif k == "C" then
		return string.format("%sInside|r  %s%s", GOLD, src.name, chanceText(src.a))
	elseif k == "Q" or k == "R" then
		return string.format("%s%s|r  %s |cffb0b0b0(level %s)|r%s", GOLD, k == "Q" and "Quest" or "Quest reward", src.name,
			tostring(src.a), where(src))
	elseif k == "S" then
		local from = src.name ~= "" and ("while making " .. src.name) or ("from " .. (M.skillName or "") .. " research")
		return string.format("%sDiscovery|r %s at skill %s%s", GOLD, from, tostring(src.b), chanceText(src.a))
	end
	return src.name
end

local whereToken = 0

local function hideSources()
	sourceTitle:Hide(); sourceTitle.rule:Hide()
	recipeItemButton:Hide()
	sourceNote:Hide()
	for _, row in ipairs(sourceRows) do row:Hide() end
end

local function drawSources(r, anchor)
	sourceTitle:ClearAllPoints()
	sourceTitle:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
	sourceTitle:Show(); sourceTitle.rule:Show()
	for _, row in ipairs(sourceRows) do row:Hide() end
	recipeItemButton:Hide()

	if not RPF.Has(RPF.HELLO_RECIPES) then
		sourceNote:SetText("This realm doesn't say where recipes come from.")
		sourceNote:Show()
		return
	end
	sourceNote:SetText("Looking it up...")
	sourceNote:Show()

	whereToken = whereToken + 1
	local mine = whereToken
	RPF.WhereToLearn(r.spell, function (result, err)
		if mine ~= whereToken or RPF.selected ~= r then return end
		if not result then
			sourceNote:SetText(err == "busy" and "The server is busy; pick the recipe again." or "No source known.")
			return
		end
		local recipeItem = result.recipeItem or 0
		if recipeItem > 0 then
			local info = RPF.Item(recipeItem)
			recipeItemButton.link = info and info.link or ("item:" .. recipeItem)
			recipeItemButton.text:SetText(GOLD .. "Recipe item|r  " .. (info and info.link or ("item " .. recipeItem)))
			recipeItemButton:Show()
		else
			recipeItemButton.text:SetText("")
			recipeItemButton:Show()
			recipeItemButton:SetHeight(1)
		end
		recipeItemButton:SetHeight(recipeItem > 0 and 16 or 1)

		local n = 0
		for _, src in ipairs(result.rows) do
			if n >= MAX_SOURCES then break end
			n = n + 1
			local row = sourceRows[n]
			row.source = src
			row.text:SetText(sourceText(src, r))
			if (src.kind == "T" or src.kind == "V") and RPF.Has(RPF.HELLO_MAP_PINS) then row.map:Show() else row.map:Hide() end
			row:Show()
		end
		if n == 0 then
			sourceNote:SetText("Nothing teaches this where you can reach it yet.")
		else
			sourceNote:Hide()
		end
	end)
end

-----------------------------------------

local parts = { icon, nameText, subText, description, skillTitle, skillTitle.rule, skillLine, requires, reagentTitle,
	reagentTitle.rule }

local function showParts(on)
	for _, p in ipairs(parts) do if on then p:Show() else p:Hide() end end
	if not on then
		gauge:Hide()
		noReagents:Hide()
		for _, slot in ipairs(reagentSlots) do slot:Hide2() end
		hideSources()
	end
end

local function draw(r)
	if not r then
		showParts(false)
		empty:Show()
		return
	end
	empty:Hide()
	showParts(true)

	-- What it makes.
	local itemLink = r.itemLink and r.itemLink:find("item:") and r.itemLink or nil
	local info = r.item and r.item > 0 and RPF.Item(r.item)
	icon.link = itemLink or (info and info.link) or (r.spell and GetSpellLink and GetSpellLink(r.spell)) or r.recipeLink
	icon:SetItem(r.icon or (info and info.texture), info and info.quality or r.quality)
	local _, _, _, hex = RPF.QualityColor(info and info.quality or r.quality or 1)
	nameText:SetText((r.isEnchant and "|cffffffff" or hex) .. r.name .. "|r")

	local sub
	if r.isEnchant then
		sub = "Enchants an item"
	else
		local lo, hi = r.madeMin or 1, r.madeMax or 1
		sub = lo == hi and (lo > 1 and ("Makes " .. lo) or "Makes 1") or string.format("Makes %d-%d", lo, hi)
	end
	if not r.learned then
		sub = sub .. "  |cffff4040Not learned|r"
	elseif r.header then
		sub = sub .. "  |cff9d9d9d" .. r.header .. "|r"
	end
	subText:SetText(sub)
	description:SetText(r.description or "")

	drawSkill(r)

	-- Tools, cooldown, craftable counts.
	local bits = {}
	if r.tools and #r.tools > 0 then
		local names = {}
		for _, t in ipairs(r.tools) do table.insert(names, (t.has and "|cffffffff" or "|cffff4040") .. t.name .. "|r") end
		table.insert(bits, "Requires: " .. table.concat(names, ", "))
	end
	if r.cooldown and r.cooldown > 0 then
		table.insert(bits, "|cffff4040Cooldown: " .. RPF.Duration(r.cooldown) .. "|r")
	end
	if r.learned and not M.linked then
		local bags, withBank = M.Craftable(r)
		local text = "You can make " .. bags
		if withBank > bags then text = text .. string.format(" |cff4fc3f7(%d with the reagent bank)|r", withBank) end
		table.insert(bits, text)
	end
	requires:SetText(table.concat(bits, "     "))
	reagentTitle:ClearAllPoints()
	reagentTitle:SetPoint("TOPLEFT", requires, "BOTTOMLEFT", 0, requires:GetText() ~= "" and -12 or 0)

	local rows = drawReagents(r)
	if r.learned then
		hideSources()
	else
		drawSources(r, rows > 0 and reagentSlots[(rows - 1) * 2 + 1] or reagentTitle)
	end
end

RPF.On("SELECTED", draw)
RPF.On("HIDDEN", function () whereToken = whereToken + 1 end)
