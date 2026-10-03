-- The profession window: the skill bar and chat link on top, the recipe list with its search
-- and filters on the left, the selected recipe on the right (Detail.lua) and the craft controls
-- under it. Drag it by the title bar; it remembers where it was put.

local RPF = RetailProfessions
local M = RPF.Model

local WIDTH, HEIGHT = 900, 572
local LIST_WIDTH = 330
local LIST_ROWS = 24

local frame = CreateFrame("Frame", "RetailProfessionsFrame", UIParent)
frame:SetSize(WIDTH, HEIGHT)
frame:EnableMouse(true)
frame:SetToplevel(true)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:Hide()
table.insert(UISpecialFrames, "RetailProfessionsFrame")
RPF.frame = frame

local function placeFrame()
	frame:ClearAllPoints()
	local p = RetailProfessionsDB and RetailProfessionsDB.position
	if p then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -104)
	end
end

RPF.On("RESET_POSITION", function ()
	RetailProfessionsDB.position = nil
	placeFrame()
	RPF.Fire("MOVED")
end)

local dragon = RPF.DressWindow(frame)

local title = frame.chrome:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", frame, "TOP", 0, -5)

local dragBar = CreateFrame("Frame", nil, frame)
dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, 0)
dragBar:SetHeight(24)
dragBar:EnableMouse(true)
dragBar:RegisterForDrag("LeftButton")
dragBar:SetScript("OnDragStart", function () frame:StartMoving() end)
dragBar:SetScript("OnDragStop", function ()
	frame:StopMovingOrSizing()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	RetailProfessionsDB.position = { point, relativePoint, x, y }
	RPF.Fire("MOVED")
end)

local close = CreateFrame("Button", "RetailProfessionsFrameCloseButton", frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
do
	local _, CP = RPF.Dragon()
	if CP and CP.ModernizeCloseButton then
		CP.ModernizeCloseButton(close, frame.chrome, 1, 0)
		close:SetFrameLevel(frame.chrome:GetFrameLevel() + 5)
	end
end

local content = CreateFrame("Frame", nil, frame)
content:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, dragon and -28 or -30)
content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)

-----------------------------------------
-- header: profession, skill bar, chat link

local header = CreateFrame("Frame", nil, content)
header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
header:SetHeight(44)

local profIcon = header:CreateTexture(nil, "ARTWORK")
profIcon:SetSize(36, 36)
profIcon:SetPoint("LEFT", header, "LEFT", 4, 0)
profIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local profName = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
profName:SetPoint("TOPLEFT", profIcon, "TOPRIGHT", 8, -1)

local rankText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rankText:SetPoint("LEFT", profName, "RIGHT", 8, -1)
rankText:SetTextColor(0.7, 0.7, 0.7)

local skillBar = CreateFrame("StatusBar", nil, header)
skillBar:SetSize(260, 13)
skillBar:SetPoint("BOTTOMLEFT", profIcon, "BOTTOMRIGHT", 8, 1)
skillBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
skillBar:SetStatusBarColor(0.1, 0.55, 0.15)
do
	local bg = skillBar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(skillBar)
	bg:SetTexture(0, 0, 0, 0.6)
	local border = CreateFrame("Frame", nil, skillBar)
	border:SetPoint("TOPLEFT", skillBar, "TOPLEFT", -3, 3)
	border:SetPoint("BOTTOMRIGHT", skillBar, "BOTTOMRIGHT", 3, -3)
	border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
	border:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
end
local skillText = skillBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
skillText:SetPoint("CENTER", skillBar, "CENTER", 0, 1)

local linkButton = CreateFrame("Button", nil, header)
linkButton:SetSize(30, 30)
linkButton:SetPoint("LEFT", skillBar, "RIGHT", 10, 6)
linkButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
linkButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Down")
linkButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
linkButton:SetScript("OnClick", function ()
	local link = GetTradeSkillListLink and GetTradeSkillListLink()
	if not link then return end
	if not ChatEdit_InsertLink(link) then ChatFrame_OpenChat(link) end
end)
linkButton:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Link this profession")
	GameTooltip:AddLine("Puts a link in chat that shows everyone your recipes.", 1, 1, 1, true)
	GameTooltip:Show()
end)
linkButton:SetScript("OnLeave", function () GameTooltip:Hide() end)

local linkedText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
linkedText:SetPoint("RIGHT", header, "RIGHT", -8, 0)
linkedText:SetTextColor(0.6, 0.85, 1)

-----------------------------------------
-- left: search, filters, list

local left = RPF.CreateInset(content)
left:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
left:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
left:SetWidth(LIST_WIDTH)

local search = RPF.CreateEditBox(left, LIST_WIDTH - 110)
search:SetPoint("TOPLEFT", left, "TOPLEFT", 14, -8)
do
	local hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", search, "LEFT", 2, 0)
	hint:SetText("Search recipes or reagents")
	search.hint = hint
end

local filterButton = RPF.CreateButton(left, "Filter", 84, 22)
filterButton:SetPoint("LEFT", search, "RIGHT", 8, 0)

RPF.filter = { text = "", haveMats = false, skillUp = false, slot = nil, learnableOnly = false }
RPF.selected = nil -- the selected recipe (from the model)

local list
local Rebuild

local function isTracked(r)
	return r.spell and RetailProfessionsCharDB.tracked[r.spell] ~= nil
end

list = RPF.CreateRecipeList(left, {
	rows = LIST_ROWS,
	onSelect = function (r) RPF.Select(r) end,
	onToggle = function (key)
		RetailProfessionsCharDB.collapsed[key] = not RetailProfessionsCharDB.collapsed[key] or nil
		Rebuild(true)
	end,
	isSelected = function (r) return RPF.selected == r end,
	isTracked = isTracked,
	onTrackToggle = function (r) RPF.ToggleTracked(r) end,
})
list:SetPoint("TOPLEFT", left, "TOPLEFT", 6, -36)
list:SetPoint("RIGHT", left, "RIGHT", -6, 0)
RPF.list = list

search:SetScript("OnTextChanged", function (self)
	local text = self:GetText() or ""
	if text == "" then self.hint:Show() else self.hint:Hide() end
	if text ~= RPF.filter.text then
		RPF.filter.text = text
		RPF.Debounce("search", 0.15, function () Rebuild() end)
	end
end)
search:SetScript("OnEditFocusGained", function (self) self.hint:Hide() end)
search:SetScript("OnEditFocusLost", function (self) if (self:GetText() or "") == "" then self.hint:Show() end end)

-- filter menu
local menu = CreateFrame("Frame", "RetailProfessionsFilterMenu", UIParent, "UIDropDownMenuTemplate")

local function filterMenu()
	local f = RPF.filter
	local function toggle(key)
		return function ()
			f[key] = not f[key]
			Rebuild()
		end
	end
	local items = {
		{ text = "Filters", isTitle = true, notCheckable = true },
		{ text = "Have materials", checked = f.haveMats, keepShownOnClick = true, isNotRadio = true, func = toggle("haveMats") },
		{ text = "Has skill-up", checked = f.skillUp, keepShownOnClick = true, isNotRadio = true, func = toggle("skillUp") },
	}
	if M.hasServerData then
		table.insert(items, { text = "Show unlearned recipes", checked = RetailProfessionsDB.showUnlearned, keepShownOnClick = true,
			isNotRadio = true, func = function ()
				RetailProfessionsDB.showUnlearned = not RetailProfessionsDB.showUnlearned
				Rebuild()
			end })
		table.insert(items, { text = "    Only ones I can learn now", checked = f.learnableOnly, keepShownOnClick = true,
			isNotRadio = true, disabled = not RetailProfessionsDB.showUnlearned, func = toggle("learnableOnly") })
	end
	if RPF.HasReagentBank() then
		table.insert(items, { text = "Count the reagent bank", checked = RetailProfessionsDB.countBank, keepShownOnClick = true,
			isNotRadio = true, func = function ()
				RetailProfessionsDB.countBank = not RetailProfessionsDB.countBank
				Rebuild(true)
			end })
	end

	local slots = M.SlotsPresent()
	if #slots > 0 then
		local sub = { { text = "All slots", checked = f.slot == nil, func = function () f.slot = nil; CloseDropDownMenus(); Rebuild() end } }
		for _, slot in ipairs(slots) do
			table.insert(sub, { text = M.SlotName(slot), checked = f.slot == slot,
				func = function () f.slot = slot; CloseDropDownMenus(); Rebuild() end })
		end
		table.insert(items, { text = "Slot" .. (f.slot and (": |cffffffff" .. M.SlotName(f.slot) .. "|r") or ""),
			hasArrow = true, notCheckable = true, menuList = sub })
	end

	table.insert(items, { text = "", disabled = true, notCheckable = true })
	table.insert(items, { text = "Expand all", notCheckable = true, func = function ()
		wipe(RetailProfessionsCharDB.collapsed)
		Rebuild(true)
	end })
	table.insert(items, { text = "Collapse all", notCheckable = true, func = function ()
		for _, row in ipairs(M.Rows({ unlearned = RetailProfessionsDB.showUnlearned }, {})) do
			if row.key then RetailProfessionsCharDB.collapsed[row.key] = true end
		end
		Rebuild(true)
	end })
	table.insert(items, { text = "Reset filters", notCheckable = true, func = function ()
		f.haveMats, f.skillUp, f.slot, f.learnableOnly = false, false, nil, false
		search:SetText("")
		Rebuild()
	end })
	return items
end

filterButton:SetScript("OnClick", function (self)
	EasyMenu(filterMenu(), menu, self, 0, 0, "MENU")
end)

local function filtersActive()
	local f = RPF.filter
	return f.haveMats or f.skillUp or f.slot or f.learnableOnly
end

-----------------------------------------
-- right: the recipe, and the craft controls under it

local right = RPF.CreateInset(content)
right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
right:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 40)
RPF.detailPane = right

local controls = CreateFrame("Frame", nil, content)
controls:SetPoint("TOPLEFT", right, "BOTTOMLEFT", 0, -4)
controls:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

local createButton = RPF.CreateButton(controls, CREATE or "Create", 100, 24)
createButton:SetPoint("RIGHT", controls, "RIGHT", -4, 0)

local createAllButton = RPF.CreateButton(controls, CREATE_ALL or "Create All", 96, 24)
createAllButton:SetPoint("RIGHT", createButton, "LEFT", -6, 0)

local plus = CreateFrame("Button", nil, controls)
plus:SetSize(22, 22)
plus:SetPoint("RIGHT", createAllButton, "LEFT", -8, 0)
plus:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
plus:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
plus:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
plus:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

local quantity = RPF.CreateEditBox(controls, 36, true)
quantity:SetPoint("RIGHT", plus, "LEFT", -2, 0)
quantity:SetJustifyH("CENTER")
quantity:SetMaxLetters(3)
quantity:SetText("1")

local minus = CreateFrame("Button", nil, controls)
minus:SetSize(22, 22)
minus:SetPoint("RIGHT", quantity, "LEFT", -6, 0)
minus:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
minus:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
minus:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
minus:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

local trackCheck = RPF.CreateCheck(controls, "Track recipe")
trackCheck:SetPoint("LEFT", controls, "LEFT", 6, 0)
trackCheck:SetScript("OnClick", function ()
	if RPF.selected then RPF.ToggleTracked(RPF.selected) end
end)

-- Enchants: the item to put them on, picked once instead of after every cast.
local target = RPF.CreateItemButton(controls, 30)
target:SetPoint("RIGHT", minus, "LEFT", -16, 0)
target:RegisterForClicks("LeftButtonUp", "RightButtonUp")
target.label = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
target.label:SetPoint("RIGHT", target, "LEFT", -6, 0)
target.label:SetText("Enchant:")
do
	local bg = target:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", target, "TOPLEFT", -2, 2)
	bg:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 2, -2)
	bg:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
	bg:SetTexCoord(0.15, 0.85, 0.15, 0.85)
end
RPF.enchantTarget = nil -- { id = item id, bag, slot } or { id, inv }

local status = controls:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("LEFT", trackCheck.label, "RIGHT", 12, 0)
status:SetPoint("RIGHT", target.label, "LEFT", -10, 0)
status:SetJustifyH("LEFT")
status:SetHeight(28)

local statusToken = 0
function RPF.Status(text, isError)
	statusToken = statusToken + 1
	local mine = statusToken
	status:SetText(text or "")
	if isError then status:SetTextColor(1, 0.25, 0.25) else status:SetTextColor(1, 0.82, 0) end
	RPF.After(8, function () if mine == statusToken then status:SetText("") end end)
end

local function getQuantity()
	return math.max(1, math.min(999, tonumber(quantity:GetText()) or 1))
end

local function setQuantity(n)
	n = math.max(1, math.min(999, math.floor(tonumber(n) or 1)))
	quantity:SetText(tostring(n))
end
RPF.GetQuantity, RPF.SetQuantity = getQuantity, setQuantity

plus:SetScript("OnClick", function () setQuantity(getQuantity() + (IsShiftKeyDown() and 10 or 1)) end)
minus:SetScript("OnClick", function () setQuantity(getQuantity() - (IsShiftKeyDown() and 10 or 1)) end)
quantity:SetScript("OnEditFocusLost", function () setQuantity(getQuantity()) end)

-----------------------------------------
-- enchant target

-- Where an item with this link is: equipped or in the bags.
local function findItem(link)
	for slot = 1, 19 do
		if GetInventoryItemLink("player", slot) == link then return { id = RPF.ItemIdFromLink(link), inv = slot } end
	end
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			if GetContainerItemLink(bag, slot) == link then return { id = RPF.ItemIdFromLink(link), bag = bag, slot = slot } end
		end
	end
	return nil
end

-- The target's current link, or nil once that slot holds something else. Enchanting changes an
-- item's link, so the target is kept by place and item id, not by link.
local function targetLink(t)
	if not t then return nil end
	local link
	if t.inv then link = GetInventoryItemLink("player", t.inv) else link = GetContainerItemLink(t.bag, t.slot) end
	if link and RPF.ItemIdFromLink(link) == t.id then return link end
	return nil
end

local function refreshTarget()
	local link = targetLink(RPF.enchantTarget)
	if not link then RPF.enchantTarget = nil end
	if link then
		local _, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link)
		target:SetItem(texture, quality)
	else
		target:SetItem(nil)
	end
end

local function takeCursorItem()
	local kind, _, link = GetCursorInfo()
	if kind ~= "item" or not link then return false end
	ClearCursor()
	local found = findItem(link)
	if found then
		RPF.enchantTarget = found
		refreshTarget()
	end
	return true
end

target:SetScript("OnReceiveDrag", takeCursorItem)
target:SetScript("OnClick", function (self, button)
	if button == "RightButton" then
		RPF.enchantTarget = nil
		refreshTarget()
	elseif not takeCursorItem() then
		RPF.Status("Drop an item here to enchant it, or leave it empty to pick one after casting.")
	end
end)
target:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local link = targetLink(RPF.enchantTarget)
	if link then
		GameTooltip:SetHyperlink(link)
		GameTooltip:AddLine("Right-click to clear.", 0.5, 0.5, 0.5)
	else
		GameTooltip:SetText("Item to enchant")
		GameTooltip:AddLine("Drop an item from your bags or character window here.", 1, 1, 1, true)
		GameTooltip:AddLine("Without one you pick the item after casting, as usual.", 0.7, 0.7, 0.7, true)
	end
	GameTooltip:Show()
end)
target:SetScript("OnLeave", function () GameTooltip:Hide() end)

-----------------------------------------
-- crafting

local function updateControls()
	local r = RPF.selected
	local learned = r and r.learned and not M.linked
	local bags = learned and M.Craftable(r) or 0
	local onCooldown = learned and r.cooldown and r.cooldown > 0
	local enchant = learned and r.isEnchant

	RPF.SetEnabled(createButton, learned and bags > 0 and not onCooldown)
	RPF.SetEnabled(createAllButton, learned and bags > 0 and not onCooldown and not enchant)
	RPF.SetEnabled(plus, learned and not enchant)
	RPF.SetEnabled(minus, learned and not enchant)
	if enchant then setQuantity(1) end
	createButton:SetText(r and r.learned and r.altVerb or CREATE or "Create")
	createAllButton:SetText((CREATE_ALL or "Create All") .. (bags > 1 and not enchant and (" (" .. bags .. ")") or ""))

	if enchant then
		target:Show(); target.label:Show()
		refreshTarget()
	else
		target:Hide(); target.label:Hide()
	end
	if M.linked then
		trackCheck:Hide()
		minus:Hide(); plus:Hide(); quantity:Hide(); createButton:Hide(); createAllButton:Hide()
	else
		trackCheck:Show()
		minus:Show(); plus:Show(); quantity:Show(); createButton:Show(); createAllButton:Show()
	end
	trackCheck:SetChecked(r and isTracked(r))
	RPF.SetEnabled(trackCheck, r ~= nil)
end
RPF.UpdateControls = updateControls

local function craft(count)
	local r = RPF.selected
	if not (r and r.learned) then return end
	local index = M.IndexOf(r)
	if not index then
		RPF.Status("That recipe moved in the list; try again.", true)
		Rebuild()
		return
	end
	if r.isEnchant then
		local t = targetLink(RPF.enchantTarget) and RPF.enchantTarget or nil
		DoTradeSkill(index, 1)
		if t and SpellIsTargeting() then
			if t.inv then PickupInventoryItem(t.inv) else PickupContainerItem(t.bag, t.slot) end
		end
		return
	end
	DoTradeSkill(index, count)
	-- Typing a number and pressing Create straight away leaves the box focused.
	quantity:ClearFocus()
end

createButton:SetScript("OnClick", function () craft(getQuantity()) end)
createAllButton:SetScript("OnClick", function ()
	local r = RPF.selected
	if not r then return end
	local bags = M.Craftable(r)
	if bags > 0 then
		setQuantity(bags)
		craft(bags)
	end
end)

-----------------------------------------
-- selection and rebuilding

function RPF.Select(r, reveal)
	RPF.selected = r
	if r and r.learned and r.index and not M.linked then
		local index = M.IndexOf(r)
		if index and SelectTradeSkill then SelectTradeSkill(index) end
	end
	if r then M.Details(r) end
	RPF.Fire("SELECTED", r)
	updateControls()
	if reveal then list:Reveal(r) else list:Refresh() end
end

local function updateHeader()
	local p = M.profession
	profIcon:SetTexture(p and p.texture or (GetTradeSkillTexture and GetTradeSkillTexture()) or "Interface\\Icons\\INV_Misc_QuestionMark")
	profName:SetText(M.skillName or "")
	title:SetText(M.linked and ((M.linkedName or "") .. " - " .. (M.skillName or "")) or (M.skillName or "Professions"))
	rankText:SetText(RPF.RankTitle(M.maxRank))
	skillBar:SetMinMaxValues(0, math.max(1, M.maxRank or 1))
	skillBar:SetValue(M.rank or 0)
	skillText:SetText((M.rank or 0) .. " / " .. (M.maxRank or 0))
	if M.linked then
		linkedText:SetText("Viewing " .. (M.linkedName or "someone") .. "'s recipes")
		linkButton:Hide()
	else
		linkedText:SetText("")
		linkButton:Show()
	end
	filterButton:SetText(filtersActive() and "|cff4fc3f7Filter|r" or "Filter")
end

-- Reads the client again (unless only the view changed) and redraws.
Rebuild = function (viewOnly)
	if not frame:IsShown() then return end
	if not viewOnly and not M.Scan() then return end
	local f = RPF.filter
	local state = { text = f.text, haveMats = f.haveMats, skillUp = f.skillUp, slot = f.slot,
		unlearned = RetailProfessionsDB.showUnlearned and not M.linked, learnableOnly = f.learnableOnly }
	local rows = M.Rows(state, RetailProfessionsCharDB.collapsed)
	if M.skill and not M.hasServerData and RPF.Has(RPF.HELLO_RECIPES) then
		list:SetEmptyText("Loading recipes...")
	else
		list:SetEmptyText((filtersActive() or f.text ~= "") and "No recipes match. Clear the search or filters." or "No recipes.")
	end
	list:SetRows(rows, true)
	updateHeader()

	-- Keep the selection when the recipe still exists (it's a new table after a scan).
	local selected = RPF.selected and RPF.selected.spell and M.bySpell[RPF.selected.spell]
	if not selected and RPF.selected and RPF.selected.learned then
		for _, r in ipairs(M.recipes) do if r.name == RPF.selected.name then selected = r break end end
	end
	if not selected then
		local index = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex() or 0
		for _, r in ipairs(M.recipes) do if r.index == index then selected = r break end end
	end
	if not selected then
		for _, row in ipairs(rows) do if row.recipe then selected = row.recipe break end end
	end
	RPF.Select(selected, RPF.selected == nil)
end
RPF.Rebuild = Rebuild

-- Selects a recipe by spell id (the tracker does this).
function RPF.SelectSpell(spell)
	local r = M.bySpell[spell]
	if not r then return false end
	if not r.learned then RetailProfessionsDB.showUnlearned = true end
	RetailProfessionsCharDB.collapsed["h:" .. (r.header or "")] = nil
	RPF.filter.text = ""
	search:SetText("")
	Rebuild(true)
	RPF.Select(M.bySpell[spell], true)
	return true
end

-----------------------------------------
-- events

RPF.On("SHOW", function ()
	if not frame:IsShown() then
		RPF.selected = nil
		frame:Show()
	end
	M.ResetClientFilters()
	RPF.RequestBankSnapshot()
	RPF.Debounce("tradeskill", 0.05, function () RPF.Fire("TRADE_SKILL_UPDATE") end)
end)

RPF.On("CLOSE", function ()
	if frame:IsShown() then frame:Hide() end
end)

RPF.On("TRADE_SKILL_UPDATE", function () Rebuild() end)
RPF.On("RECIPES", function (skill) if skill == M.skill then Rebuild() end end)
RPF.On("READY", function () if frame:IsShown() then Rebuild() end end)
RPF.On("BAGS", function ()
	if not frame:IsShown() then return end
	list:Refresh()
	if RPF.selected then RPF.Fire("SELECTED", RPF.selected) end
	updateControls()
end)
RPF.On("COOLDOWN", function ()
	if frame:IsShown() and RPF.selected then
		M.Details(RPF.selected)
		RPF.Fire("SELECTED", RPF.selected)
		updateControls()
	end
end)
RPF.On("ITEM_INFO", function ()
	if frame:IsShown() then
		list:Refresh()
		if RPF.selected then RPF.Fire("SELECTED", RPF.selected) end
	end
end)
RPF.On("TRACKED", function ()
	if frame:IsShown() then
		list:Refresh()
		updateControls()
	end
end)

frame:SetScript("OnShow", function ()
	PlaySound("igCharacterInfoOpen")
	placeFrame()
	status:SetText("")
	RPF.Fire("MOVED")
end)

frame:SetScript("OnHide", function ()
	PlaySound("igCharacterInfoClose")
	RPF.Fire("HIDDEN")
	-- Closing the window ends the trade skill session, unless we're handing over to the classic window.
	if RPF.active and not RPF.IsSwitchingToClassic() then
		RPF.active = false
		CloseTradeSkill()
	end
end)

-----------------------------------------
-- ReagentBankUI: its sidebar follows this window the way it follows the stock one

RPF.On("LOGIN", function ()
	local RB = _G.ReagentBankUI
	if not (RB and RB.RegisterRecipeProvider) then return end
	RB:RegisterRecipeProvider({
		name = "RetailProfessions",
		frame = frame,
		GetRecipe = function ()
			local r = RPF.selected
			if not r then return nil, "Select a recipe first." end
			local reagents = {}
			for _, rg in ipairs(r.reagents) do
				if rg.id then
					table.insert(reagents, { itemEntry = rg.id, name = M.ReagentName(rg), requiredPerCraft = rg.n })
				end
			end
			return r.name, reagents
		end,
		GetRepeatCount = getQuantity,
		SetRepeatCount = setQuantity,
	})
end)

-- ReagentBankUI redraws its sidebar on these; tell it the selection changed.
RPF.On("SELECTED", function ()
	local RB = _G.ReagentBankUI
	if RB and RB.NotifyRecipeProviderChanged and frame:IsShown() then pcall(RB.NotifyRecipeProviderChanged, RB) end
end)
