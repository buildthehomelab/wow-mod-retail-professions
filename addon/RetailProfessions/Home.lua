-- Home: the tab at the top of the column on the right, in the spirit of TradeSkillMaster's
-- crafting overview. It looks across every profession the character has, not just the open one:
--
--   * a card per profession with its skill bar,
--   * To do: cooldowns that are ready, tracked recipes you now have the materials for, the most
--     gold your bags can turn into, the best recipe to skill up on, recipes waiting at the
--     trainer, the next rank to train, and herbs or ore to mill or prospect,
--   * Most profitable crafts: every recipe you know that makes money at today's auction prices
--     (Profit.lua), sortable by profit, by what your materials make in all, by how many you can
--     make and by how well it sells.
--
-- The client only lists the recipes of the profession that's open, so each visit to a profession
-- leaves a note of the recipes you know (and their cooldowns) per character; the server's recipe
-- list (RPF.RecipeList) fills in the reagents and skill-up thresholds of the others. A profession
-- not opened since this addon came along says so instead.
--
-- Clicking a line opens its recipe. In another profession that means casting the spell that
-- opens it, so those lines carry a secure button (Secure.lua) and the recipe is picked once the
-- window has switched.

local RPF = RetailProfessions
local M = RPF.Model
local P = RPF.Profit
local R = RPF.Refine
local H = {}
RPF.Home = H

local frame = RPF.frame
local floor = math.floor

local TODO_WIDTH = 300
local TODO_ROWS, TODO_HEIGHT = 10, 36
local CRAFT_ROWS, CRAFT_HEIGHT = 18, 18
local CARD_HEIGHT, CARD_GAP, MAX_CARDS = 40, 6, 12
local HOME_ICON = "Interface\\Icons\\INV_Misc_Rune_01"
H.ICON = HOME_ICON

-- The level each rank's trainer asks for (Journeyman ... Grand Master).
local TRAIN_LEVEL = { [150] = 10, [225] = 20, [300] = 35, [375] = 50, [450] = 65 }

local PLATE = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

H.active = false

-- Whether the window shows Home: your own professions only, not someone's linked one.
function H.Active()
	return H.active and frame:IsShown() and not M.linked
end

function H.SetActive(on)
	on = on and true or false
	if H.active == on then return end
	H.active = on
	RPF.Fire("VIEW")
end

local function isOpen(skill)
	return frame:IsShown() and M.skill == skill and not M.linked
end

local function charDB()
	local db = RetailProfessionsCharDB
	db.homeLearned = db.homeLearned or {}
	db.homeCooldowns = db.homeCooldowns or {}
	return db
end

-----------------------------------------
-- what each profession knows, kept from the last visit

-- After every read of the open profession: its learned recipes, and when the ones on cooldown
-- come off it. A cooldown that's over stays as "ready" until the next craft sets it again.
local function snapshot()
	if M.linked or not M.skill or not frame:IsShown() then return end
	local db = charDB()
	local set = {}
	for _, r in ipairs(M.recipes) do
		if r.spell then set[r.spell] = true end
	end
	db.homeLearned[M.skill] = set
	local now = time()
	for _, r in ipairs(M.recipes) do
		local index = r.spell and GetTradeSkillCooldown and M.IndexOf(r)
		local left = index and GetTradeSkillCooldown(index)
		if left and left > 0 then db.homeCooldowns[r.spell] = { at = now + floor(left), skill = M.skill } end
	end
	-- Unlearned (a respec of a profession) or gone: no reminder.
	for spell, cd in pairs(db.homeCooldowns) do
		if cd.skill == M.skill and not set[spell] then db.homeCooldowns[spell] = nil end
	end
end

RPF.On("SCANNED", function () RPF.Debounce("home-snapshot", 0.3, snapshot) end)
RPF.On("COOLDOWN", function () RPF.Debounce("home-snapshot", 0.3, snapshot) end)

local built = {} -- skill -> { set, list, recipes }

-- The recipes you know in a profession, shaped like the model's: the model's own while it's
-- open, otherwise rebuilt from the note of the last visit and the server's list. nil when the
-- profession hasn't been opened yet, or its list is still on its way (RECIPES fires then).
function H.RecipesOf(skill)
	if isOpen(skill) then return M.recipes end
	local set = charDB().homeLearned[skill]
	if not set then return nil end
	local list = RPF.RecipeList(skill)
	if not list then return nil end
	local cached = built[skill]
	if cached and cached.set == set and cached.list == list then return cached.recipes end
	local recipes = {}
	for spell in pairs(set) do
		local info = list[spell]
		if info then
			local name, _, icon = GetSpellInfo(spell)
			local isEnchant = info.targetsItem
			if isEnchant == nil then isEnchant = info.item == 0 and (skill == 333 or skill == 776) end
			local r = {
				spell = spell, name = name or ("#" .. spell), learned = true, skill = skill, item = info.item,
				icon = (info.item > 0 and RPF.ItemIcon(info.item)) or icon, isEnchant = isEnchant, reagents = {},
				madeMin = info.madeMin, madeMax = info.madeMax, reqSkill = info.reqSkill, sources = info.sources,
				yellow = info.yellow, green = info.green, grey = info.grey, perks = info.perks,
			}
			for _, rg in ipairs(info.reagents) do table.insert(r.reagents, { id = rg.id, n = rg.n }) end
			table.insert(recipes, r)
		end
	end
	table.sort(recipes, function (a, b) return a.name < b.name end)
	built[skill] = { set = set, list = list, recipes = recipes }
	return recipes
end

local function knows(skill, spell)
	if isOpen(skill) then
		local r = M.bySpell[spell]
		return r and r.learned or false
	end
	local set = charDB().homeLearned[skill]
	return set and set[spell] or false
end

-- Recipes of a profession you don't know yet, from the server's list.
local function unlearnedOf(skill)
	if isOpen(skill) then return M.unlearned end
	local set = charDB().homeLearned[skill]
	local list = set and RPF.RecipeList(skill)
	if not list then return {} end
	local out = {}
	for spell, info in pairs(list) do
		if not set[spell] then
			local name = GetSpellInfo(spell)
			if name then
				table.insert(out, { spell = spell, name = name, reqSkill = info.reqSkill, sources = info.sources })
			end
		end
	end
	return out
end

-- The professions with a window, as the tabs show them. Kept until skills change or a
-- profession opens: reading them opens and folds the Skills headers.
local professionCache
local function professions()
	if professionCache then return professionCache end
	local out = {}
	if not RetailProfessionsDB then return out end
	for _, known in ipairs(RPF.KnownProfessions()) do
		local p = known.profession
		if p.openName and GetSpellInfo(p.openName) then table.insert(out, known) end
	end
	professionCache = out
	return out
end
RPF.On("SKILLS", function () professionCache = nil end)
RPF.On("SHOW", function () professionCache = nil end)
RPF.On("TRADE_SKILL_UPDATE", function () professionCache = nil end)

local function unitsOf(entry)
	return (GetItemCount(entry) or 0) + (RetailProfessionsDB.countBank and RPF.BankCount(entry) or 0)
end

-----------------------------------------
-- the numbers

-- Every recipe you know that makes money, priced, and the items to ask prices for.
local function crafts(profs)
	local rows, entries, seen = {}, {}, {}
	for _, known in ipairs(profs) do
		local skill = known.profession.id
		for _, r in ipairs(H.RecipesOf(skill) or {}) do
			if not r.isEnchant and r.item and r.item > 0 then
				P.EntriesOf(r, entries, seen)
				local a = P.state == "ok" and P.Of(r)
				if a and a.costKnown and a.profit > 0 then
					local n = math.max(0, P.CanMake(r))
					local price = P.Get(r.item)
					table.insert(rows, { recipe = r, skill = skill, profession = known.profession, a = a, have = n,
						total = a.profit * n, sold = price and not price.locked and price.soldUnits or 0 })
				end
			end
		end
	end
	P.Fetch(entries)
	return rows, entries
end

local SORTS = {
	profit = function (x, y) return x.a.profit > y.a.profit end,
	total = function (x, y) return x.total > y.total end,
	have = function (x, y) return x.have > y.have end,
	sold = function (x, y) return x.sold > y.sold end,
}

local function sortCrafts(rows)
	local key = RetailProfessionsDB.homeSort or "profit"
	local by = SORTS[key] or SORTS.profit
	table.sort(rows, function (x, y)
		if by(x, y) then return true end
		if by(y, x) then return false end
		if x.a.profit ~= y.a.profit then return x.a.profit > y.a.profit end
		return x.recipe.name < y.recipe.name
	end)
end

local function hex(c)
	return string.format("|cff%02x%02x%02x", floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255))
end

-- How likely a craft at this skill is to raise it, and the colour the recipe has there.
local FALLBACK_CHANCE = { optimal = 100, medium = 50, easy = 25, trivial = 0 }
local function skillUp(r, rank)
	local chance = RPF.SkillUpChance(rank, r.yellow, r.grey)
	local difficulty
	if r.grey and r.grey > 0 then
		difficulty = rank < r.yellow and "optimal" or rank < r.green and "medium" or rank < r.grey and "easy" or "trivial"
	else
		difficulty = r.difficulty
		chance = chance or FALLBACK_CHANCE[difficulty or ""]
	end
	return chance or 0, difficulty or "trivial"
end

-- The recipe to craft for the next point: one you can make now, the likeliest, the cheapest.
local function bestSkillUp(recipes, rank)
	local best
	for _, r in ipairs(recipes) do
		if not r.refine then
			local chance, difficulty = skillUp(r, rank)
			if chance > 0 then
				local a = P.state == "ok" and P.Of(r) or nil
				local c = { recipe = r, chance = chance, difficulty = difficulty, have = math.max(0, P.CanMake(r)),
					cost = a and a.costKnown and a.cost or nil }
				local better = not best
				if best then
					if (c.have > 0) ~= (best.have > 0) then
						better = c.have > 0
					elseif c.chance ~= best.chance then
						better = c.chance > best.chance
					elseif (c.cost ~= nil) ~= (best.cost ~= nil) then
						better = c.cost ~= nil
					elseif c.cost and c.cost ~= best.cost then
						better = c.cost < best.cost
					else
						better = r.name < best.recipe.name
					end
				end
				if better then best = c end
			end
		end
	end
	return best
end

-- Several cooldown recipes that share one timer (every transmute) come off it together: one line.
local function readyCooldowns(add, byId)
	local now, groups, order = time(), {}, {}
	for spell, cd in pairs(charDB().homeCooldowns) do
		-- The open profession says for itself: a craft a moment ago may not be noted yet.
		local recipe = isOpen(cd.skill) and M.bySpell[spell]
		local index = recipe and recipe.learned and GetTradeSkillCooldown and M.IndexOf(recipe)
		local left = index and GetTradeSkillCooldown(index)
		if left and left > 0 then cd.at = now + floor(left) end
		if cd.at <= now and byId[cd.skill] and knows(cd.skill, spell) then
			local key = cd.skill .. ":" .. floor(cd.at / 120)
			if not groups[key] then
				groups[key] = { skill = cd.skill, list = {} }
				table.insert(order, key)
			end
			local name, _, icon = GetSpellInfo(spell)
			table.insert(groups[key].list, { spell = spell, name = name or ("#" .. spell), icon = icon })
		end
	end
	table.sort(order)
	for _, key in ipairs(order) do
		local g = groups[key]
		table.sort(g.list, function (a, b) return a.name < b.name end)
		local first = g.list[1]
		local prefix = first.name:match("^(.-):")
		for _, e in ipairs(g.list) do
			if prefix and e.name:match("^(.-):") ~= prefix then prefix = nil end
		end
		local text
		if #g.list == 1 then
			text = first.name .. " is ready"
		elseif prefix then
			text = prefix .. " is ready"
		else
			text = string.format("%s and %d more are ready", first.name, #g.list - 1)
		end
		local p = byId[g.skill].profession
		local recipe = isOpen(g.skill) and M.bySpell[first.spell]
		add({ icon = (recipe and recipe.icon) or first.icon or p.texture, text = text,
			sub = p.localName .. " cooldown is over.", action = { skill = g.skill, spell = first.spell } })
	end
end

local function trackedReady(add, byId)
	for spell, t in pairs(RetailProfessionsCharDB.tracked) do
		if t.skill and byId[t.skill] and t.reagents and #t.reagents > 0 and knows(t.skill, spell) then
			local can = math.huge
			for _, rg in ipairs(t.reagents) do can = math.min(can, floor(unitsOf(rg.id) / math.max(1, rg.n))) end
			local want = t.count or 1
			if can >= want then
				add({ icon = t.icon or byId[t.skill].profession.texture, text = "Craft " .. (t.name or "?"),
					sub = string.format("Tracked: you have the materials for %d.", want),
					action = { skill = t.skill, spell = spell } })
			end
		end
	end
end

local function todoFor(add, known)
	local p = known.profession
	local skill, rank, maxRank = p.id, known.rank, known.maxRank
	local cap = math.min(RPF.skillCap or 450, 450)

	-- The next rank: trainers teach it from 25 points short of the cap. Runeforging has none.
	local nextCap = maxRank + 75
	local level = TRAIN_LEVEL[nextCap]
	if level and not p.class and maxRank < cap and known.baseRank >= maxRank - 25 then
		local sub
		if (UnitLevel("player") or 0) < level then
			sub = string.format("From level %d, at a %s trainer. You're at %d/%d.", level, p.localName, known.baseRank, maxRank)
		else
			sub = string.format("At a %s trainer. You're at %d/%d.", p.localName, known.baseRank, maxRank)
		end
		add({ icon = p.texture, text = string.format("Train %s %s", RPF.RankTitle(nextCap), p.localName), sub = sub,
			action = { skill = skill } })
	end

	local recipes = H.RecipesOf(skill)
	if not recipes then
		if not charDB().homeLearned[skill] then
			add({ icon = p.texture, text = "Open " .. p.localName .. " once",
				sub = "So Home knows its recipes and what they earn.", action = { skill = skill } })
		end
		return
	end

	-- Recipes a trainer would teach you now.
	local learnable = {}
	for _, r in ipairs(unlearnedOf(skill)) do
		if bit.band(r.sources or 0, RPF.SRC_TRAINER) ~= 0 and (r.reqSkill or 0) <= rank
				and (not RPF.skillCap or (r.reqSkill or 0) <= RPF.skillCap) then
			table.insert(learnable, r)
		end
	end
	if #learnable > 0 then
		table.sort(learnable, function (a, b)
			if a.reqSkill ~= b.reqSkill then return a.reqSkill > b.reqSkill end
			return a.name < b.name
		end)
		local names = {}
		for i = 1, math.min(2, #learnable) do names[i] = learnable[i].name end
		add({ icon = "Interface\\Icons\\INV_Misc_Book_11",
			text = string.format("%d new %s recipe%s to train", #learnable, p.localName, #learnable == 1 and "" or "s"),
			sub = table.concat(names, ", ") .. (#learnable > 2 and ", ..." or ""),
			action = { skill = skill, spell = learnable[1].spell } })
	end

	-- What to craft for the next skill point.
	if known.baseRank < maxRank then
		-- The core rolls skill-ups on the skill without bonuses; trainers count them.
		local best = bestSkillUp(recipes, known.baseRank)
		if best then
			local color = M.DIFFICULTY_COLOR[best.difficulty] or M.DIFFICULTY_COLOR.easy
			local sub = string.format("%s%d%%|r chance per craft", hex(color), best.chance)
			if best.have > 0 then
				sub = sub .. string.format(", you can make %d", best.have)
			elseif best.cost then
				sub = sub .. ", materials " .. P.Short(best.cost)
			else
				sub = sub .. ", get the materials"
			end
			add({ icon = best.recipe.icon or p.texture, text = string.format("Skill up %s: %s", p.localName, best.recipe.name),
				sub = sub, action = { skill = skill, spell = best.recipe.spell } })
		elseif #learnable == 0 then
			add({ icon = p.texture, text = "No " .. p.localName .. " skill-ups left",
				sub = "Every recipe you know is grey: learn new ones from a trainer, a vendor or a drop.",
				action = { skill = skill } })
		end
	end

	-- Herbs to mill, ore to prospect.
	local kind = p.refine and R.Known(p.refine)
	local sources = kind and R.Sources(p.refine)
	if sources then
		local units, casts = 0, 0
		for _, r in ipairs(sources) do
			if (r.reqSkill or 0) <= rank then
				local n = unitsOf(r.source)
				units = units + n
				casts = casts + floor(n / 5)
			end
		end
		if casts > 0 then
			local noun = p.refine == "M" and "herbs" or "ore"
			add({ icon = kind.texture or p.texture, text = string.format("%s your %s", kind.verb, noun),
				sub = string.format("%d %s, enough to %s %d time%s.", units, noun, kind.verb:lower(), casts, casts == 1 and "" or "s"),
				action = { skill = skill, code = p.refine } })
		end
	end
end

local function todo(profs, craftRows)
	local items = {}
	local function add(item) table.insert(items, item) end
	local byId = {}
	for _, known in ipairs(profs) do byId[known.profession.id] = known end

	readyCooldowns(add, byId)
	trackedReady(add, byId)

	-- The most your materials can earn, in one recipe.
	local best
	for _, row in ipairs(craftRows) do
		if row.have > 0 and (not best or row.total > best.total) then best = row end
	end
	if best then
		add({ icon = best.recipe.icon or best.profession.texture, text = "Craft " .. best.recipe.name,
			sub = string.format("You can make %d for %s in all.", best.have, P.Signed(best.total)),
			action = { skill = best.skill, spell = best.recipe.spell } })
	end

	for _, known in ipairs(profs) do todoFor(add, known) end
	return items
end

-----------------------------------------
-- the panel: under the skill bar, in place of the list and the recipe

local panel = CreateFrame("Frame", nil, RPF.content)
panel:SetPoint("TOPLEFT", RPF.header, "BOTTOMLEFT", 0, -6)
panel:SetPoint("BOTTOMRIGHT", RPF.content, "BOTTOMRIGHT", 0, 0)
panel:Hide()
H.panel = panel

local function showPanel(on)
	for _, pane in ipairs(RPF.panes) do
		if on then pane:Hide() else pane:Show() end
	end
	if on then panel:Show() else panel:Hide() end
end

-- A line that does something: itself when its profession is open, through a secure button
-- that casts the profession's spell when it isn't. The caller syncs the buttons once it's done.
local function bindAction(region, action)
	region.action = action
	local p = action and RPF.Profession(action.skill)
	if action and p and p.openName and not isOpen(action.skill) then
		region.button.preClick = function () H.Pend(action) end
		RPF.BindSpellButton(region.button, region, p.openName, frame, true)
	else
		region.button.preClick = nil
		RPF.BindSpellButton(region.button, nil, nil, nil, true)
	end
end

function H.Run(action)
	if not action then return end
	if not isOpen(action.skill) then
		if RPF.InCombat() then
			UIErrorsFrame:AddMessage("Professions can't be opened in combat.", 1, 0.1, 0.1)
		end
		return
	end
	H.SetActive(false)
	if action.code then
		R.SetView(action.code)
	elseif action.spell then
		RPF.SelectSpell(action.spell)
	else
		R.SetView(nil)
	end
end

local function withSecure(region, name, onEnter)
	region:SetScript("OnEnter", function (self) onEnter(self, self) end)
	region:SetScript("OnLeave", RPF.HideItemTooltip)
	region:SetScript("OnClick", function (self)
		if IsModifiedClick("CHATLINK") and self.link then
			ChatEdit_InsertLink(self.link)
			return
		end
		H.Run(self.action)
	end)
	region.button = RPF.CreateSpellButton(name)
	region.button.onEnter = function (b) onEnter(region, b) end
end

local function rowHighlight(row)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	hl:SetBlendMode("ADD")
	hl:SetVertexColor(1, 1, 1, 0.35)
	hl:SetAllPoints(row)
end

local function clickHint(action)
	if not action then return end
	local p = RPF.Profession(action.skill)
	if isOpen(action.skill) then
		GameTooltip:AddLine(action.spell and "Click to open the recipe." or "Click to go there.", 0.5, 0.5, 0.5)
	elseif p then
		GameTooltip:AddLine("Click to open " .. p.localName .. ".", 0.5, 0.5, 0.5)
	end
end

-- cards

local cardRow = CreateFrame("Frame", nil, panel)
cardRow:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
cardRow:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
cardRow:SetHeight(CARD_HEIGHT)

local function cardEnter(card, owner)
	local known = card.known
	if not known then return end
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	GameTooltip:SetText(known.profession.localName .. " - " .. RPF.RankTitle(known.maxRank))
	GameTooltip:AddLine(string.format("Skill %d of %d", known.rank, known.maxRank), 1, 1, 1)
	clickHint(card.action)
	GameTooltip:Show()
end

local cards = {}
for i = 1, MAX_CARDS do
	local card = CreateFrame("Button", nil, cardRow)
	card:SetHeight(CARD_HEIGHT)
	card:SetBackdrop(PLATE)
	card:SetBackdropColor(0.03, 0.03, 0.03, 0.8)
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(28, 28)
	card.icon:SetPoint("LEFT", card, "LEFT", 6, 0)
	card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 6, -1)
	card.name:SetPoint("RIGHT", card, "RIGHT", -6, 0)
	card.name:SetJustifyH("LEFT")
	card.name:SetWordWrap(false)
	card.bar = CreateFrame("StatusBar", nil, card)
	card.bar:SetHeight(11)
	card.bar:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 6, 1)
	card.bar:SetPoint("RIGHT", card, "RIGHT", -8, 0)
	card.bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
	card.bar:SetStatusBarColor(0.95, 0.6, 0.1)
	local bg = card.bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(card.bar)
	bg:SetTexture(0, 0, 0, 0.65)
	card.rank = card.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.rank:SetPoint("CENTER", card.bar, "CENTER", 0, 1)
	rowHighlight(card)
	withSecure(card, "RetailProfessionsHomeCard" .. i, cardEnter)
	card:Hide()
	cards[i] = card
end

local function drawCards(profs)
	local n = math.min(#profs, MAX_CARDS)
	local width = cardRow:GetWidth()
	if not width or width < 200 then width = 700 end
	local w = math.min(200, floor((width - (n - 1) * CARD_GAP) / math.max(n, 1)))
	for i, card in ipairs(cards) do
		local known = profs[i]
		if known and i <= n then
			local p = known.profession
			card.known = known
			card:SetWidth(w)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", cardRow, "TOPLEFT", (i - 1) * (w + CARD_GAP), 0)
			card.icon:SetTexture(p.texture)
			card.bar:SetMinMaxValues(0, math.max(1, known.maxRank))
			card.bar:SetValue(known.rank)
			-- Narrow cards (a character with many professions) put the numbers where the name
			-- was; the tooltip names it.
			local numbers = known.rank .. "/" .. known.maxRank
			if w < 120 then
				card.name:SetText("|cffffffff" .. numbers .. "|r")
				card.rank:SetText("")
			else
				card.name:SetText(p.localName)
				card.rank:SetText(numbers)
			end
			if isOpen(p.id) then card:SetBackdropBorderColor(1, 0.82, 0, 1) else card:SetBackdropBorderColor(0.45, 0.45, 0.45, 1) end
			card:Show()
			bindAction(card, { skill = p.id })
		else
			card.known = nil
			card:Hide()
			bindAction(card, nil)
		end
	end
end

-- To do

local todoPane = RPF.CreateInset(panel)
todoPane:SetPoint("TOPLEFT", cardRow, "BOTTOMLEFT", 0, -6)
todoPane:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
todoPane:SetWidth(TODO_WIDTH)

do
	local t = todoPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	t:SetPoint("TOPLEFT", todoPane, "TOPLEFT", 10, -9)
	t:SetText("To do")
end

local todoItems = {}
local todoScrollName = RPF.UniqueName("HomeTodoScroll")
local todoScroll = CreateFrame("ScrollFrame", todoScrollName, todoPane, "FauxScrollFrameTemplate")
todoScroll:SetPoint("TOPLEFT", todoPane, "TOPLEFT", 4, -28)
todoScroll:SetPoint("BOTTOMRIGHT", todoPane, "BOTTOMRIGHT", -26, 6)
RPF.SkinScrollBar(todoScroll, todoScrollName)

local todoEmpty = todoPane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
todoEmpty:SetPoint("TOP", todoPane, "TOP", 0, -60)
todoEmpty:SetWidth(TODO_WIDTH - 40)

local function todoEnter(row, owner)
	local item = row.item
	if not item then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(item.text, 1, 1, 1, true)
	GameTooltip:AddLine(item.sub, 0.8, 0.8, 0.8, true)
	clickHint(item.action)
	GameTooltip:Show()
end

local todoRows = {}
for i = 1, TODO_ROWS do
	local row = CreateFrame("Button", nil, todoPane)
	row:SetHeight(TODO_HEIGHT)
	row:SetPoint("TOPLEFT", todoPane, "TOPLEFT", 6, -28 - (i - 1) * TODO_HEIGHT)
	row:SetPoint("RIGHT", todoScroll, "RIGHT", 0, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(26, 26)
	row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
	row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
	row.sub:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.sub:SetJustifyH("LEFT")
	row.sub:SetWordWrap(false)
	rowHighlight(row)
	withSecure(row, "RetailProfessionsHomeTodo" .. i, todoEnter)
	todoRows[i] = row
end

local function drawTodo()
	FauxScrollFrame_Update(todoScroll, #todoItems, TODO_ROWS, TODO_HEIGHT)
	local offset = FauxScrollFrame_GetOffset(todoScroll)
	for i, row in ipairs(todoRows) do
		local item = todoItems[offset + i]
		row.item = item
		if item then
			row.icon:SetTexture(item.icon or HOME_ICON)
			row.text:SetText(item.text)
			row.sub:SetText(item.sub or "")
			row:Show()
		else
			row:Hide()
		end
		bindAction(row, item and item.action)
	end
	if #todoItems == 0 then
		todoEmpty:SetText("Nothing to do right now.")
		todoEmpty:Show()
	else
		todoEmpty:Hide()
	end
end

todoScroll:SetScript("OnVerticalScroll", function (self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, TODO_HEIGHT, function ()
		drawTodo()
		RPF.SyncSpellButtons()
	end)
end)

-- Most profitable crafts

local craftPane = RPF.CreateInset(panel)
craftPane:SetPoint("TOPLEFT", todoPane, "TOPRIGHT", 6, 0)
craftPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

do
	local t = craftPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	t:SetPoint("TOPLEFT", craftPane, "TOPLEFT", 10, -9)
	t:SetText("Most profitable crafts")
end

local craftRows = {}
local lastEntries = {}
local refreshSoon

local refreshButton = RPF.CreateButton(craftPane, "Refresh", 70, 20)
refreshButton:SetPoint("TOPRIGHT", craftPane, "TOPRIGHT", -8, -5)
refreshButton:SetScript("OnClick", function ()
	P.Fetch(lastEntries, true)
	refreshSoon()
end)
refreshButton:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Refresh prices")
	GameTooltip:AddLine("Asks the auction house again for every item your recipes make and use.", 1, 1, 1, true)
	GameTooltip:Show()
end)
refreshButton:SetScript("OnLeave", function () GameTooltip:Hide() end)

local canMakeCheck = RPF.CreateCheck(craftPane, "Can make now")
canMakeCheck:SetPoint("RIGHT", refreshButton, "LEFT", -86, 0)
canMakeCheck:SetScript("OnClick", function (self)
	RetailProfessionsDB.homeCanMake = self:GetChecked() and true or nil
	refreshSoon()
end)
canMakeCheck:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Can make now")
	GameTooltip:AddLine("Only the recipes your bags (and reagent bank, when it's counted) have the materials for.", 1, 1, 1, true)
	GameTooltip:Show()
end)
canMakeCheck:SetScript("OnLeave", function () GameTooltip:Hide() end)

-- Columns, from the right edge of a row: { key, label, right offset, width, tooltip }.
local COLUMNS = {
	{ key = "profit", label = "Profit", right = -4, width = 64, tip = "Profit per craft, after the house cut." },
	{ key = "total", label = "In all", right = -72, width = 64,
		tip = "What crafting everything your materials make would earn." },
	{ key = "have", label = "Have", right = -140, width = 34, tip = "How many you can make from what you have." },
	{ key = "sold", label = "Sold", right = -178, width = 36,
		tip = "How many sold on the auction house lately: a quick seller beats a big number that sits." },
}
local NAME_RIGHT = -218

local craftScrollName = RPF.UniqueName("HomeCraftScroll")
local craftScroll = CreateFrame("ScrollFrame", craftScrollName, craftPane, "FauxScrollFrameTemplate")
craftScroll:SetPoint("TOPLEFT", craftPane, "TOPLEFT", 4, -50)
craftScroll:SetPoint("BOTTOMRIGHT", craftPane, "BOTTOMRIGHT", -26, 28)
RPF.SkinScrollBar(craftScroll, craftScrollName)

local columnBar = CreateFrame("Frame", nil, craftPane)
columnBar:SetHeight(16)
columnBar:SetPoint("TOPLEFT", craftPane, "TOPLEFT", 6, -32)
columnBar:SetPoint("RIGHT", craftScroll, "RIGHT", 0, 0)
do
	local name = columnBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	name:SetPoint("LEFT", columnBar, "LEFT", 38, 0)
	name:SetText("Recipe")
end

local headers = {}
for _, col in ipairs(COLUMNS) do
	local b = CreateFrame("Button", nil, columnBar)
	b:SetSize(col.width, 16)
	b:SetPoint("RIGHT", columnBar, "RIGHT", col.right, 0)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetAllPoints(b)
	b.text:SetJustifyH("RIGHT")
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	b:SetScript("OnClick", function ()
		RetailProfessionsDB.homeSort = col.key
		refreshSoon()
	end)
	b:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(col.label)
		GameTooltip:AddLine(col.tip, 1, 1, 1, true)
		GameTooltip:AddLine("Click to sort by it.", 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function () GameTooltip:Hide() end)
	b.col = col
	table.insert(headers, b)
end

local summary = craftPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
summary:SetPoint("BOTTOMLEFT", craftPane, "BOTTOMLEFT", 10, 10)
summary:SetPoint("RIGHT", craftPane, "RIGHT", -10, 0)
summary:SetJustifyH("LEFT")
summary:SetWordWrap(false)

local craftEmpty = craftPane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
craftEmpty:SetPoint("TOP", craftPane, "TOP", 0, -80)
craftEmpty:SetWidth(320)

local function craftEnter(row, owner)
	local e = row.entry
	if not e then return end
	local r = e.recipe
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink("item:" .. r.item)
	P.AddTooltipLines(GameTooltip, r)
	GameTooltip:AddLine(e.profession.localName, 0.6, 0.6, 0.6)
	clickHint(row.action)
	RPF.ShowItemTooltip(owner)
end

local craftButtons = {}
for i = 1, CRAFT_ROWS do
	local row = CreateFrame("Button", nil, craftPane)
	row:SetHeight(CRAFT_HEIGHT)
	row:SetPoint("TOPLEFT", craftPane, "TOPLEFT", 6, -50 - (i - 1) * CRAFT_HEIGHT)
	row:SetPoint("RIGHT", craftScroll, "RIGHT", 0, 0)
	row.prof = row:CreateTexture(nil, "ARTWORK")
	row.prof:SetSize(14, 14)
	row.prof:SetPoint("LEFT", row, "LEFT", 2, 0)
	row.prof:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", row, "LEFT", 19, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row, "LEFT", 38, 0)
	row.name:SetPoint("RIGHT", row, "RIGHT", NAME_RIGHT, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.cells = {}
	for _, col in ipairs(COLUMNS) do
		local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cell:SetSize(col.width, CRAFT_HEIGHT)
		cell:SetPoint("RIGHT", row, "RIGHT", col.right, 0)
		cell:SetJustifyH("RIGHT")
		row.cells[col.key] = cell
	end
	rowHighlight(row)
	withSecure(row, "RetailProfessionsHomeCraft" .. i, craftEnter)
	craftButtons[i] = row
end

local function drawCrafts()
	FauxScrollFrame_Update(craftScroll, #craftRows, CRAFT_ROWS, CRAFT_HEIGHT)
	local offset = FauxScrollFrame_GetOffset(craftScroll)
	for i, row in ipairs(craftButtons) do
		local e = craftRows[offset + i]
		row.entry = e
		if e then
			local r = e.recipe
			row.prof:SetTexture(e.profession.texture)
			row.icon:SetTexture(r.icon or RPF.ItemIcon(r.item) or "Interface\\Icons\\INV_Misc_QuestionMark")
			local info = RPF.Item(r.item)
			local name = info and info.name or r.name
			if info and info.quality then
				local cr, cg, cb = RPF.QualityColor(info.quality)
				row.name:SetTextColor(cr, cg, cb)
			else
				row.name:SetTextColor(1, 1, 1)
			end
			row.name:SetText(name)
			row.link = info and info.link or nil
			row.cells.profit:SetText(P.Signed(e.a.profit))
			row.cells.total:SetText(e.have > 0 and P.Signed(e.total) or "|cff9d9d9d-|r")
			row.cells.have:SetText(e.have > 0 and tostring(e.have) or "|cff9d9d9d0|r")
			row.cells.sold:SetText(e.sold > 0 and tostring(e.sold) or "|cff9d9d9d-|r")
			row:Show()
		else
			row.link = nil
			row:Hide()
		end
		bindAction(row, e and { skill = e.skill, spell = e.recipe.spell })
	end
	local sort = RetailProfessionsDB.homeSort or "profit"
	for _, b in ipairs(headers) do
		b.text:SetText(b.col.key == sort and ("|cffffffff" .. b.col.label .. "|r") or b.col.label)
	end
end

craftScroll:SetScript("OnVerticalScroll", function (self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, CRAFT_HEIGHT, function ()
		drawCrafts()
		RPF.SyncSpellButtons()
	end)
end)

-----------------------------------------
-- drawing it all

local function priceText(entries, earn, count)
	if P.state == "missing" then
		return "No auction prices on this realm: profits need mod-retail-ah's server with RetailAH.CraftPrices on."
	end
	if P.state ~= "ok" or P.Fetching() then return "Looking up auction prices..." end
	local age = P.Age(entries)
	local when = age and string.format("Prices from %s ago.", RPF.Duration(age)) or ""
	if count > 0 then
		return string.format("What you have makes %s in %d recipe%s. %s", P.Signed(earn), count, count == 1 and "" or "s", when)
	end
	return when
end

local function refresh()
	if not H.Active() then return end
	local profs = professions()
	local rows, entries = crafts(profs)
	lastEntries = entries

	local earn, count = 0, 0
	for _, row in ipairs(rows) do
		if row.have > 0 then
			earn = earn + row.total
			count = count + 1
		end
	end

	todoItems = todo(profs, rows)
	local shown = rows
	if RetailProfessionsDB.homeCanMake then
		shown = {}
		for _, row in ipairs(rows) do if row.have > 0 then table.insert(shown, row) end end
	end
	sortCrafts(shown)
	craftRows = shown

	drawCards(profs)
	drawTodo()
	drawCrafts()
	canMakeCheck:SetChecked(RetailProfessionsDB.homeCanMake and true or false)
	summary:SetText(priceText(entries, earn, count))
	if #entries == 0 then
		-- Nothing to price: no profession opened yet, or their recipes are on their way.
		summary:SetText("")
	end
	if #craftRows == 0 then
		if #entries == 0 then
			craftEmpty:SetText("No recipes that make an item yet. Open each profession once so Home knows its recipes.")
		elseif P.state == "ok" and not P.Fetching() then
			craftEmpty:SetText(RetailProfessionsDB.homeCanMake and "Nothing you can make right now earns money."
				or "Nothing you know earns money at today's prices.")
		else
			craftEmpty:SetText(priceText(entries, 0, 0))
		end
		craftEmpty:Show()
	else
		craftEmpty:Hide()
	end
	RPF.SyncSpellButtons()
end
H.Refresh = refresh
-- For the smoke test.
H.rows = { todo = todoRows, crafts = craftButtons, cards = cards }

refreshSoon = function ()
	if H.Active() then RPF.Debounce("home", 0.1, refresh) end
end

-----------------------------------------
-- events

-- A click on a line in another profession: once the window has switched and read it, pick the
-- recipe. Milling and Prospecting land through the refine view's own pending (Refine.lua).
local pending
function H.Pend(action)
	pending = { action = action, at = GetTime() }
	if action.code then R.Pend(action.code) end
end

RPF.On("SHOW", function ()
	if pending and GetTime() - pending.at > 2 then pending = nil end
	-- A profession opens on its recipes.
	if H.active then
		H.active = false
		RPF.Fire("VIEW")
	end
end)

RPF.On("REBUILT", function ()
	local p = pending
	if not p or M.linked or M.skill ~= p.action.skill then return end
	pending = nil
	if GetTime() - p.at < 5 and p.action.spell then RPF.SelectSpell(p.action.spell) end
end)

RPF.On("VIEW", function ()
	local on = H.Active()
	showPanel(on)
	if on then refresh() end
end)

for _, event in ipairs({ "PRICES", "BAGS", "RECIPES", "SKILLS", "TRACKED", "YIELDS", "ITEM_INFO", "REBUILT" }) do
	RPF.On(event, refreshSoon)
end

-- The window opens on recipes next time.
RPF.On("HIDDEN", function ()
	H.active = false
	showPanel(false)
end)
