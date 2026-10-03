-- The selected recipe, laid out like retail's: a round icon with the name, a favorite star and
-- what it requires (tools, a fire, a forge) beside it, how likely it is to raise your skill (a
-- bar showing where it turns yellow, green and grey and where you are), the reagents with what
-- you have, and for a recipe you haven't learned, where to learn it. A faint picture of the
-- profession sits behind it all.

local RPF = RetailProfessions
local M = RPF.Model

local pane = RPF.detailPane
local PAD = 14
local REAGENT_TEXT_WIDTH = 320
local MAX_REAGENTS = 8
local MAX_SOURCES = 9

local function label(parent, font, r, g, b)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	if r then fs:SetTextColor(r, g, b) end
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

-- The profession's picture, very faint, behind the recipe.
local watermark = pane:CreateTexture(nil, "BACKGROUND", nil, 2)
watermark:SetSize(170, 170)
watermark:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -30, 40)
watermark:SetDesaturated(true)
watermark:SetAlpha(0.07)

-- Round icon with a glow in the item's quality colour.
local icon = CreateFrame("Button", nil, pane)
icon:SetSize(46, 46)
icon:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -PAD)
icon.texture = icon:CreateTexture(nil, "ARTWORK")
icon.texture:SetAllPoints(icon)
icon.glow = icon:CreateTexture(nil, "OVERLAY")
icon.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
icon.glow:SetBlendMode("ADD")
icon.glow:SetSize(84, 84)
icon.glow:SetPoint("CENTER", icon, "CENTER")
icon:SetScript("OnEnter", function (self)
	itemTooltip(self, self.link)
	if RPF.selected then
		RPF.AddSkillUpLines(GameTooltip, RPF.selected)
		GameTooltip:Show()
	end
end)
icon:SetScript("OnLeave", function () GameTooltip:Hide() end)
icon:SetScript("OnClick", function (self) linkOrNothing(self.link) end)

local nameText = label(pane, "GameFontNormalLarge")
nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -4)

-- Favorites go to the top of the list.
local star = CreateFrame("Button", nil, pane)
star:SetSize(16, 16)
star:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
star.texture = star:CreateTexture(nil, "ARTWORK")
star.texture:SetAllPoints(star)
star.texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
star:SetScript("OnClick", function ()
	local r = RPF.selected
	if r and r.spell then RPF.ToggleFavorite(r.spell) end
end)
star:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(RPF.selected and RPF.IsFavorite(RPF.selected.spell) and "Remove from favorites" or "Add to favorites")
	GameTooltip:Show()
end)
star:SetScript("OnLeave", function () GameTooltip:Hide() end)

local subText = label(pane, "GameFontHighlightSmall")
subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -5)
subText:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)

local description = label(pane, "GameFontHighlightSmall", 0.8, 0.8, 0.8)
description:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
description:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)

local empty = label(pane, "GameFontDisable")
empty:SetPoint("CENTER", pane, "CENTER")
empty:SetText("Pick a recipe on the left.")

-- Where the reagents start: under the description.
local reagentAnchor = CreateFrame("Frame", nil, pane)
reagentAnchor:SetSize(1, 1)

-----------------------------------------
-- reagents: two columns of icon, name and have/need

local reagentTitle = label(pane, "GameFontNormalSmall")
reagentTitle:SetText((SPELL_REAGENTS or "Reagents:"):gsub("%s+$", ""))
reagentTitle:SetPoint("TOPLEFT", reagentAnchor, "TOPLEFT", 0, 0)

-- One column: icon, then "have/need Name", and what the reagent bank holds.
local reagentSlots = {}
for i = 1, MAX_REAGENTS do
	local slot = RPF.CreateItemButton(pane, 30)
	slot:SetPoint("TOPLEFT", reagentTitle, "BOTTOMLEFT", 0, -6 - (i - 1) * 34)
	slot.name = label(pane, "GameFontHighlightSmall")
	slot.name:SetPoint("LEFT", slot, "RIGHT", 8, 0)
	slot.name:SetWidth(REAGENT_TEXT_WIDTH)
	slot.have = slot.name -- one line holds both
	slot:SetScript("OnEnter", function (self) itemTooltip(self, self.link) end)
	slot:SetScript("OnLeave", function () GameTooltip:Hide() end)
	slot:SetScript("OnClick", function (self) linkOrNothing(self.link) end)
	slot.Hide2 = function (self) self:Hide(); self.name:Hide() end
	slot.Show2 = function (self) self:Show(); self.name:Show() end
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
			slot:SetItem(rg.texture or (info and info.texture) or RPF.ItemIcon(rg.id), info and info.quality)
			local reagentName = M.ReagentName(rg) or ("Item #" .. tostring(rg.id or "?"))
			local bags = rg.id and GetItemCount(rg.id) or 0
			local bank = rg.id and RPF.BankCount(rg.id) or 0
			local text
			if bags >= rg.n then
				text = string.format("|cffffffff%d/%d|r", bags, rg.n)
			elseif bags + bank >= rg.n and RetailProfessionsDB.countBank then
				text = string.format("|cffffd200%d/%d|r", bags, rg.n)
			else
				text = string.format("|cffff4040%d/%d|r", bags, rg.n)
			end
			text = text .. " " .. reagentName
			if bank > 0 then text = text .. string.format("  |cff4fc3f7+%d in bank|r", bank) end
			slot.name:SetText(text)
			slot:Show2()
		else
			slot:Hide2()
		end
	end
	if shown == 0 then noReagents:Show() else noReagents:Hide() end
	return math.max(1, shown)
end

-----------------------------------------
-- where to learn it

local sourceTitle = label(pane, "GameFontNormalSmall")
sourceTitle:SetText("Learn it from:")

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
	sourceTitle:Hide()
	recipeItemButton:Hide()
	sourceNote:Hide()
	for _, row in ipairs(sourceRows) do row:Hide() end
end

local function drawSources(r, anchor)
	sourceTitle:ClearAllPoints()
	sourceTitle:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
	sourceTitle:Show()
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

local parts = { icon, nameText, star, subText, description, reagentTitle, watermark }

local function showParts(on)
	for _, p in ipairs(parts) do if on then p:Show() else p:Hide() end end
	if not on then
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
	RPF.SetPortrait(icon.texture, (info and info.texture) or r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	local quality = info and info.quality or r.quality or 1
	if quality >= 2 and not r.isEnchant then
		local qr, qg, qb = RPF.QualityColor(quality)
		icon.glow:SetVertexColor(qr, qg, qb)
		icon.glow:Show()
	else
		icon.glow:Hide()
	end
	local _, _, _, hex = RPF.QualityColor(quality)
	nameText:SetText((r.isEnchant and "|cffffffff" or hex) .. r.name .. "|r")
	star.texture:SetDesaturated(not RPF.IsFavorite(r.spell))
	star.texture:SetAlpha(RPF.IsFavorite(r.spell) and 1 or 0.45)
	local p = M.profession
	watermark:SetTexture(p and p.texture or nil)

	-- Under the name: what it needs (red when you don't have it), else what it makes.
	local sub
	if r.tools and #r.tools > 0 then
		local names = {}
		for _, t in ipairs(r.tools) do table.insert(names, (t.has and "|cffffffff" or "|cffff2020") .. t.name .. "|r") end
		sub = "|cffffd200Requires:|r " .. table.concat(names, ", ")
	elseif r.isEnchant then
		sub = "Enchants an item"
	else
		local lo, hi = r.madeMin or 1, r.madeMax or 1
		sub = lo == hi and ("Makes " .. lo) or string.format("Makes %d-%d", lo, hi)
	end
	if r.cooldown and r.cooldown > 0 then
		sub = sub .. "   |cffff4040Cooldown: " .. RPF.Duration(r.cooldown) .. "|r"
	end
	if not r.learned then
		local need = r.reqSkill or 0
		sub = sub .. string.format("   %sNot learned - needs %d|r", need > (M.rank or 0) and "|cffff4040" or "|cffffd200", need)
	end
	subText:SetText(sub)
	description:SetText(r.description or "")

	reagentAnchor:ClearAllPoints()
	reagentAnchor:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, (r.description or "") ~= "" and -12 or 0)

	local rows = drawReagents(r)
	if r.learned then
		hideSources()
	else
		drawSources(r, reagentSlots[rows])
	end
end

RPF.On("SELECTED", draw)
RPF.On("HIDDEN", function () whereToken = whereToken + 1 end)
