-- The recipe list on the left, as retail draws it: gold category bars that fold, and per recipe
-- a skill-up chevron in the recipe's colour (orange, yellow, green; none when it gives no more
-- skill-ups), its name and how many you can make in brackets.

local RPF = RetailProfessions
local M = RPF.Model

local dragon = RPF.Dragon() and true or false
-- DragonUI's professions art: its category bars, selection and hover glows and skill-up
-- arrows, recipes indented under their category as in its window.
local art = RPF.ProfArt()
local ROW_HEIGHT = art and 20 or 18
local INDENT = 10
local RECIPE_COLOR = { 0.886, 0.863, 0.839 }
local SKILL_UP = { optimal = "skill-high", medium = "skill-medium", easy = "skill-low" }
-- Under the selection glow with the art, as in DragonUI.
local textLayer = art and "ARTWORK" or "OVERLAY"
local headerFont = art and RPF.Dragon().ForeverUI.Fonts and RPF.Dragon().ForeverUI.Fonts.HighlightMedium or GameFontNormal

local function showAll(regions, on)
	for _, region in ipairs(regions) do
		if on then region:Show() else region:Hide() end
	end
end

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
		-- with a plus or minus button the Blizzard trade skill window has. With the professions
		-- art, its own bar (below) instead.
		local bandAlpha = (dragon and not art) and 0.9 or 0
		local ruleAlpha = (dragon and not art) and 0.55 or 0
		b.band = solid(b, "BACKGROUND", 0.2, 0.14, 0.04, bandAlpha)
		b.band:SetAllPoints(b)
		b.ruleTop = solid(b, "BORDER", 1, 0.82, 0, ruleAlpha)
		b.ruleTop:SetHeight(1)
		b.ruleTop:SetPoint("TOPLEFT", b, "TOPLEFT")
		b.ruleTop:SetPoint("TOPRIGHT", b, "TOPRIGHT")
		b.rule = solid(b, "BORDER", 1, 0.82, 0, ruleAlpha)
		b.rule:SetHeight(1)
		b.rule:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT")
		b.rule:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
		b.fold = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		b.fold:SetPoint("RIGHT", b, "RIGHT", -6, 1)
		b.toggle = b:CreateTexture(nil, "ARTWORK")
		b.toggle:SetSize(14, 14)
		b.toggle:SetPoint("LEFT", b, "LEFT", 2, 0)

		if not art then
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
		else
			-- DragonUI's: the header bar (and a lighter copy on hover), and for a recipe the gold
			-- glow of the selection, the grey one on hover and its skill-up arrows.
			local A = art.Art
			b.headerArt = { A.ThreeSlice(b, "BACKGROUND", "header", 8) }
			b.headerHover = { A.ThreeSlice(b, "HIGHLIGHT", "header", 8) }
			for _, t in ipairs(b.headerHover) do
				t:SetBlendMode("ADD")
				t:SetAlpha(0.4)
			end
			-- Text on ARTWORK, the glow over it on OVERLAY, as DragonUI layers them.
			b.selected = b:CreateTexture(nil, "OVERLAY")
			A.Set(b.selected, "recipe-active")
			b.selected:SetHeight(19)
			b.selected:SetPoint("LEFT", b, "LEFT", INDENT, -1)
			b.selected:SetPoint("RIGHT", b, "RIGHT", 0, -1)
			b.hover = b:CreateTexture(nil, "HIGHLIGHT")
			A.Set(b.hover, "recipe-hover")
			b.hover:SetAlpha(0.5)
			b.hover:SetHeight(21)
			b.hover:SetPoint("LEFT", b, "LEFT", INDENT, -1)
			b.hover:SetPoint("RIGHT", b, "RIGHT", 0, -1)
			b.skill = b:CreateTexture(nil, "ARTWORK")
			b.favorite = b:CreateTexture(nil, "ARTWORK")
			A.Set(b.favorite, "favorite")
			b.favorite:SetSize(14, 13)
			b.favorite:SetPoint("LEFT", b, "LEFT", INDENT + 21, 0)
			b.toggle:ClearAllPoints()
			b.toggle:SetPoint("CENTER", b, "RIGHT", -16, 0)
		end

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

		b.count = b:CreateFontString(nil, textLayer, "GameFontHighlightSmall")
		b.count:SetPoint("RIGHT", b, "RIGHT", -4, 0)
		b.count:SetJustifyH("RIGHT")
		b.tracked = b:CreateTexture(nil, "OVERLAY")
		b.tracked:SetTexture("Interface\\Minimap\\Tracking\\None")
		b.tracked:SetSize(12, 12)

		b.text = b:CreateFontString(nil, textLayer, "GameFontHighlightSmall")
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
				if not link and row.recipe.source then link = select(2, GetItemInfo(row.recipe.source)) end
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
			-- A herb to mill or ore to prospect: the item, and what it gives.
			if r.refine then
				GameTooltip:SetHyperlink("item:" .. r.source)
				RPF.Refine.AddTooltipLines(GameTooltip, r)
				RPF.ShowItemTooltip(self)
				return
			end
			if r.itemLink and r.itemLink:find("item:") then
				GameTooltip:SetHyperlink(r.itemLink)
			elseif r.item and r.item > 0 then
				GameTooltip:SetHyperlink("item:" .. r.item)
			elseif r.spell then
				GameTooltip:SetHyperlink("spell:" .. r.spell)
			end
			RPF.AddSkillUpLines(GameTooltip, r)
			if row.right then RPF.Profit.AddTooltipLines(GameTooltip, r) end
			GameTooltip:AddLine("Right-click to track.", 0.5, 0.5, 0.5)
			RPF.ShowItemTooltip(self)
		end)
		b:SetScript("OnLeave", RPF.HideItemTooltip)
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
		local rank = M.baseRank or M.rank or 0
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
				if art then
					showAll(b.headerArt, true)
					showAll(b.headerHover, true)
					b.hover:Hide(); b.skill:Hide(); b.favorite:Hide(); b.fold:Hide()
					art.Art.Set(b.toggle, row.collapsed and "header-plus" or "header-minus", true)
					b.toggle:Show()
					b.text:SetPoint("LEFT", b, "LEFT", 8, 0)
				elseif dragon then
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
				b.text:SetFontObject(headerFont)
				b.text:SetText(row.header)
				b.text:SetTextColor(1, 0.82, 0)
				b.count:ClearAllPoints()
				b.count:SetPoint("RIGHT", b, "RIGHT", art and -30 or dragon and -20 or -4, 0)
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
				local showChevron = difficulty ~= "trivial" and not r.refine
				local favorite = spec.isFavorite and spec.isFavorite(r)
				if art then
					showAll(b.headerArt, false)
					showAll(b.headerHover, false)
					b.hover:Show()
					for _, c in ipairs(b.chevrons) do c:Hide() end
					-- DragonUI's arrows: their right edge 27 in, the guaranteed one a point higher.
					local up = showChevron and SKILL_UP[difficulty]
					if up then
						art.Art.Set(b.skill, up, true)
						b.skill:ClearAllPoints()
						b.skill:SetPoint("RIGHT", b, "LEFT", INDENT + 17, difficulty == "optimal" and 0 or -1)
						b.skill:SetAlpha(r.learned and 1 or 0.5)
						b.skill:Show()
					else
						b.skill:Hide()
					end
					if favorite then b.favorite:Show() else b.favorite:Hide() end
				else
					for _, c in ipairs(b.chevrons) do
						c:SetVertexColor(color[1], color[2], color[3], r.learned and 1 or 0.5)
						if showChevron then c:Show() else c:Hide() end
					end
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
				-- With the art, after the arrows where DragonUI has its names (and its star first).
				local textLeft = art and (INDENT + 21 + (favorite and 16 or 0)) or 24
				b.text:SetPoint("LEFT", b, "LEFT", textLeft, 0)
				b.text:SetFontObject(GameFontHighlightSmall)
				b.text:SetText(name)
				-- DragonUI's names are a soft white; ours stay that way.
				local white = art and RECIPE_COLOR or { 1, 1, 1 }
				if not r.learned then
					b.text:SetTextColor(0.55, 0.55, 0.55)
				elseif r.refine then
					-- White when there's enough to do it now.
					if row.ready then b.text:SetTextColor(white[1], white[2], white[3]) else b.text:SetTextColor(0.55, 0.55, 0.55) end
				elseif difficulty == "trivial" then
					b.text:SetTextColor(0.62, 0.62, 0.62)
				else
					b.text:SetTextColor(white[1], white[2], white[3])
				end

				if row.right then
					b.count:SetText(row.right)
				elseif row.note then
					b.count:SetText(row.note)
				elseif r.learned then
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
				if favorite and not art then
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
