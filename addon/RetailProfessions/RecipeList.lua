-- The recipe list on the left, as retail draws it: gold category bars that fold, and per recipe
-- a skill-up chevron in the recipe's colour (orange, yellow, green; none when it gives no more
-- skill-ups), its name and how many you can make in brackets.

local RPF = RetailProfessions
local M = RPF.Model

local ROW_HEIGHT = 18

local dragon = RPF.Dragon() and true or false

local function solid(host, layer, r, g, b, a)
	local tex = host:CreateTexture(nil, layer)
	tex:SetTexture(r, g, b, a)
	return tex
end

-- spec = { rows = visible rows, onSelect = fn(recipe), onToggle = fn(key), isSelected = fn(recipe),
--          isTracked = fn(recipe), onTrackToggle = fn(recipe) }
function RPF.CreateRecipeList(parent, spec)
	local list = CreateFrame("Frame", nil, parent)
	list.rows = {}
	list:SetHeight(spec.rows * ROW_HEIGHT + 4)

	local scrollName = RPF.UniqueName("RecipeScroll")
	local scroll = CreateFrame("ScrollFrame", scrollName, list, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -2)
	scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -22, 2)
	scroll:SetScript("OnVerticalScroll", function (self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function () list:Refresh() end)
	end)
	RPF.SkinScrollBar(scroll, scrollName)
	list.scroll = scroll

	local buttons = {}
	for i = 1, spec.rows do
		local b = CreateFrame("Button", nil, list)
		b:SetHeight(ROW_HEIGHT)
		b:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -2 - (i - 1) * ROW_HEIGHT)
		b:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		-- category bar: DragonUI gets retail's gold-edged bar, the stock look the plain heading
		-- with a plus or minus button the Blizzard trade skill window has.
		b.band = solid(b, "BACKGROUND", 0.2, 0.14, 0.04, dragon and 0.9 or 0)
		b.band:SetAllPoints(b)
		b.ruleTop = solid(b, "BORDER", 1, 0.82, 0, dragon and 0.55 or 0)
		b.ruleTop:SetHeight(1)
		b.ruleTop:SetPoint("TOPLEFT", b, "TOPLEFT")
		b.ruleTop:SetPoint("TOPRIGHT", b, "TOPRIGHT")
		b.rule = solid(b, "BORDER", 1, 0.82, 0, dragon and 0.55 or 0)
		b.rule:SetHeight(1)
		b.rule:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT")
		b.rule:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
		b.fold = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		b.fold:SetPoint("RIGHT", b, "RIGHT", -6, 1)
		b.toggle = b:CreateTexture(nil, "ARTWORK")
		b.toggle:SetSize(14, 14)
		b.toggle:SetPoint("LEFT", b, "LEFT", 2, 0)

		-- the stock trade skill highlight, for the selection and on hover
		b.selected = b:CreateTexture(nil, "BORDER")
		b.selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		b.selected:SetBlendMode("ADD")
		b.selected:SetVertexColor(1, 0.82, 0, 0.75)
		b.selected:SetAllPoints(b)
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		hl:SetBlendMode("ADD")
		hl:SetVertexColor(1, 1, 1, 0.35)
		hl:SetAllPoints(b)

		-- skill-up chevron: two arrows, stacked
		b.chevrons = {}
		for k = 1, 2 do
			local c = b:CreateTexture(nil, "ARTWORK")
			c:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
			c:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1) -- the arrow points right; turn it up
			c:SetSize(10, 8)
			c:SetPoint("CENTER", b, "LEFT", 12, 3 - (k - 1) * 5)
			b.chevrons[k] = c
		end

		b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.count:SetPoint("RIGHT", b, "RIGHT", -4, 0)
		b.count:SetJustifyH("RIGHT")
		b.tracked = b:CreateTexture(nil, "OVERLAY")
		b.tracked:SetTexture("Interface\\Minimap\\Tracking\\None")
		b.tracked:SetSize(12, 12)

		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetJustifyH("LEFT")
		b.text:SetHeight(ROW_HEIGHT)

		b:SetScript("OnClick", function (self, button)
			local row = self.row
			if not row then return end
			if row.header then
				if spec.onToggle then spec.onToggle(row.key) end
				return
			end
			if button == "RightButton" then
				if spec.onTrackToggle then spec.onTrackToggle(row.recipe) end
			elseif IsModifiedClick("CHATLINK") then
				local link = row.recipe.recipeLink or row.recipe.itemLink
				if not link and row.recipe.spell then link = GetSpellLink and GetSpellLink(row.recipe.spell) end
				if link then ChatEdit_InsertLink(link) end
			else
				spec.onSelect(row.recipe)
			end
			list:Refresh()
		end)
		b:SetScript("OnEnter", function (self)
			local row = self.row
			if not (row and row.recipe) then return end
			local r = row.recipe
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if r.itemLink and r.itemLink:find("item:") then
				GameTooltip:SetHyperlink(r.itemLink)
			elseif r.item and r.item > 0 then
				GameTooltip:SetHyperlink("item:" .. r.item)
			elseif r.spell then
				GameTooltip:SetHyperlink("spell:" .. r.spell)
			end
			if not r.learned then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(string.format("Not learned yet. Requires %s (%d).", M.skillName or "skill", r.reqSkill or 0), 1, 0.3, 0.3, true)
			end
			GameTooltip:AddLine("Right-click to track.", 0.5, 0.5, 0.5)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function () GameTooltip:Hide() end)
		buttons[i] = b
	end

	list.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	list.empty:SetPoint("TOP", list, "TOP", -10, -40)
	list.empty:SetWidth(240)

	function list:SetRows(rows, keepScroll)
		self.rows = rows or {}
		if not keepScroll then FauxScrollFrame_SetOffset(scroll, 0); scroll:SetVerticalScroll(0) end
		self:Refresh()
	end

	function list:SetEmptyText(text)
		self.emptyText = text
	end

	-- Scrolls so a recipe is visible.
	function list:Reveal(recipe)
		for i, row in ipairs(self.rows) do
			if row.recipe == recipe then
				local offset = FauxScrollFrame_GetOffset(scroll)
				if i <= offset or i > offset + spec.rows then
					local target = math.max(0, math.min(i - math.floor(spec.rows / 2), #self.rows - spec.rows))
					FauxScrollFrame_SetOffset(scroll, target)
					scroll:SetVerticalScroll(target * ROW_HEIGHT)
				end
				break
			end
		end
		self:Refresh()
	end

	function list:Refresh()
		local rows = self.rows
		FauxScrollFrame_Update(scroll, #rows, spec.rows, ROW_HEIGHT)
		local offset = FauxScrollFrame_GetOffset(scroll)
		local rank = M.rank or 0
		for i, b in ipairs(buttons) do
			local row = rows[offset + i]
			b.row = row
			if not row then
				b:Hide()
			elseif row.header then
				b.band:Show(); b.ruleTop:Show(); b.rule:Show(); b.selected:Hide()
				for _, c in ipairs(b.chevrons) do c:Hide() end
				b.tracked:Hide()
				b.text:ClearAllPoints()
				if dragon then
					b.toggle:Hide()
					b.fold:SetText(row.collapsed and "+" or "-")
					b.fold:Show()
					b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
				else
					b.fold:Hide()
					b.toggle:SetTexture(row.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
					b.toggle:Show()
					b.text:SetPoint("LEFT", b.toggle, "RIGHT", 4, 0)
				end
				b.text:SetPoint("RIGHT", b.count, "LEFT", -4, 0)
				b.text:SetFontObject(GameFontNormal)
				b.text:SetText(row.header)
				b.text:SetTextColor(1, 0.82, 0)
				b.count:ClearAllPoints()
				b.count:SetPoint("RIGHT", b, "RIGHT", dragon and -20 or -4, 0)
				b.count:SetText(row.extra and ("|cff9d9d9d" .. row.extra .. "|r") or "")
				b:Show()
			else
				local r = row.recipe
				b.band:Hide(); b.ruleTop:Hide(); b.rule:Hide(); b.toggle:Hide(); b.fold:Hide()
				if spec.isSelected(r) then b.selected:Show() else b.selected:Hide() end
				b.count:ClearAllPoints()
				b.count:SetPoint("RIGHT", b, "RIGHT", -4, 0)

				local difficulty = M.DifficultyAt(r, rank) or "trivial"
				local color = M.DIFFICULTY_COLOR[difficulty] or M.DIFFICULTY_COLOR.trivial
				local showChevron = difficulty ~= "trivial"
				for _, c in ipairs(b.chevrons) do
					c:SetVertexColor(color[1], color[2], color[3], r.learned and 1 or 0.5)
					if showChevron then c:Show() else c:Hide() end
				end

				-- name [can make], with what the reagent bank adds in blue
				local name = r.name
				if r.learned then
					local bags, withBank = M.Craftable(r)
					local extra = RetailProfessionsDB.countBank and withBank - bags or 0
					if bags > 0 or extra > 0 then
						name = name .. " [" .. bags .. (extra > 0 and ("|cff4fc3f7+" .. extra .. "|r") or "") .. "]"
					end
				end
				b.text:ClearAllPoints()
				b.text:SetPoint("LEFT", b, "LEFT", 24, 0)
				b.text:SetFontObject(GameFontHighlightSmall)
				b.text:SetText(name)
				if not r.learned then
					b.text:SetTextColor(0.55, 0.55, 0.55)
				elseif difficulty == "trivial" then
					b.text:SetTextColor(0.62, 0.62, 0.62)
				else
					b.text:SetTextColor(1, 1, 1)
				end

				if r.learned then
					b.count:SetText("")
				else
					local need = r.reqSkill or 0
					b.count:SetText((need > rank and "|cffff4040" or "|cff9d9d9d") .. need .. "|r")
				end

				local anchor = b.count
				if spec.isTracked and spec.isTracked(r) then
					b.tracked:ClearAllPoints()
					b.tracked:SetPoint("RIGHT", b.count, "LEFT", -3, 0)
					b.tracked:Show()
					anchor = b.tracked
				else
					b.tracked:Hide()
				end
				if spec.isFavorite and spec.isFavorite(r) then
					b.text:SetText("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12|t " .. b.text:GetText())
				end
				b.text:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
				b:Show()
			end
		end
		if #rows == 0 then
			self.empty:SetText(self.emptyText or "No recipes match.")
			self.empty:Show()
		else
			self.empty:Hide()
		end
	end

	list:SetScript("OnShow", function () list:Refresh() end)
	return list
end
