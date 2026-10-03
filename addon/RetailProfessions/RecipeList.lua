-- The recipe list on the left: collapsible groups, and per recipe a skill-up meter (three bars,
-- like signal strength: three = a sure skill-up, none = no skill-up), its name and how many
-- you can make.

local RPF = RetailProfessions
local M = RPF.Model

local ROW_HEIGHT = 18

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

		b.band = solid(b, "BACKGROUND", 0, 0, 0, 0.45)
		b.band:SetAllPoints(b)
		b.rule = solid(b, "BORDER", 1, 0.82, 0, 0.25)
		b.rule:SetHeight(1)
		b.rule:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT")
		b.rule:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
		b.selected = solid(b, "BORDER", 0.25, 0.55, 1, 0.3)
		b.selected:SetAllPoints(b)
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(b)
		hl:SetTexture(1, 1, 1, 0.08)

		-- group header parts
		b.toggle = b:CreateTexture(nil, "ARTWORK")
		b.toggle:SetSize(14, 14)
		b.toggle:SetPoint("LEFT", b, "LEFT", 4, 0)

		-- recipe parts: the meter
		b.bars = {}
		for k = 1, 3 do
			local bar = b:CreateTexture(nil, "ARTWORK")
			bar:SetSize(3, 3 + k * 3)
			bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 10 + (k - 1) * 4, 4)
			b.bars[k] = bar
		end
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(ROW_HEIGHT - 3, ROW_HEIGHT - 3)
		b.icon:SetPoint("LEFT", b, "LEFT", 26, 0)
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

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
				b.band:Show(); b.rule:Show(); b.selected:Hide()
				b.toggle:Show()
				b.toggle:SetTexture(row.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
				for _, bar in ipairs(b.bars) do bar:Hide() end
				b.icon:Hide(); b.tracked:Hide()
				b.text:ClearAllPoints()
				b.text:SetPoint("LEFT", b.toggle, "RIGHT", 4, 0)
				b.text:SetPoint("RIGHT", b.count, "LEFT", -4, 0)
				b.text:SetFontObject(GameFontNormalSmall)
				b.text:SetText(row.header)
				b.text:SetTextColor(1, 0.82, 0)
				b.count:SetText("|cff9d9d9d" .. (row.extra and (row.extra .. "  ") or "") .. row.count .. "|r")
				b:Show()
			else
				local r = row.recipe
				b.band:Hide(); b.rule:Hide(); b.toggle:Hide()
				if spec.isSelected(r) then b.selected:Show() else b.selected:Hide() end

				local difficulty = M.DifficultyAt(r, rank) or "trivial"
				local color = M.DIFFICULTY_COLOR[difficulty] or M.DIFFICULTY_COLOR.trivial
				local lit = M.ARROWS[difficulty] or 0
				local dim = not r.learned and 0.45 or 1
				for k, bar in ipairs(b.bars) do
					if k <= lit then
						bar:SetTexture(color[1], color[2], color[3], dim)
					else
						bar:SetTexture(0.3, 0.3, 0.3, 0.5 * dim)
					end
					bar:Show()
				end

				b.icon:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
				b.icon:SetDesaturated(not r.learned)
				b.icon:Show()

				b.text:ClearAllPoints()
				b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
				b.text:SetFontObject(GameFontHighlightSmall)
				b.text:SetText(r.name)
				if not r.learned then
					b.text:SetTextColor(0.55, 0.55, 0.55)
				elseif difficulty == "trivial" then
					b.text:SetTextColor(0.62, 0.62, 0.62)
				else
					b.text:SetTextColor(1, 1, 1)
				end

				if r.learned then
					local bags, withBank = M.Craftable(r)
					local extra = RetailProfessionsDB.countBank and withBank - bags or 0
					if bags > 0 or extra > 0 then
						b.count:SetText((bags > 0 and ("|cffffffff" .. bags .. "|r") or "|cff9d9d9d0|r")
							.. (extra > 0 and (" |cff4fc3f7+" .. extra .. "|r") or ""))
					else
						b.count:SetText("")
					end
				else
					local need = r.reqSkill or 0
					b.count:SetText((need > rank and "|cffff4040" or "|cff9d9d9d") .. need .. "|r")
				end

				if spec.isTracked and spec.isTracked(r) then
					b.tracked:ClearAllPoints()
					b.tracked:SetPoint("RIGHT", b.count, "LEFT", -3, 0)
					b.tracked:Show()
					b.text:SetPoint("RIGHT", b.tracked, "LEFT", -2, 0)
				else
					b.tracked:Hide()
					b.text:SetPoint("RIGHT", b.count, "LEFT", -4, 0)
				end
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
