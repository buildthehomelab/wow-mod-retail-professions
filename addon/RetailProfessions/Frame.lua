-- The profession window, laid out like retail's (and WoW Forever's): the profession's portrait
-- and a full-width skill bar with the chat link on top, the recipe list with its search and
-- filter on the left, the selected recipe on the right (Detail.lua) with Create All, the amount
-- and Create under it. A stock Blizzard dialog frame, skinned by DragonUI when it's loaded.
-- Drag it by the title bar; it remembers where it was put.

local RPF = RetailProfessions
local M = RPF.Model

local WIDTH, HEIGHT = 740, 560
local LIST_WIDTH = 276
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

local dragon, contentTop = RPF.DressWindow(frame, {
	portrait = true,
	closeName = "RetailProfessionsFrameCloseButton",
	onMoved = function ()
		local point, _, relativePoint, x, y = frame:GetPoint(1)
		RetailProfessionsDB.position = { point, relativePoint, x, y }
		RPF.Fire("MOVED")
	end,
})
local title = frame.title

local content = CreateFrame("Frame", nil, frame)
content:SetPoint("TOPLEFT", frame, "TOPLEFT", dragon and 10 or 14, contentTop)
content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", dragon and -10 or -14, dragon and 10 or 14)

-----------------------------------------
-- header: the skill bar across the window, and the chat link

local header = CreateFrame("Frame", nil, content)
header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
header:SetHeight(26)

-- The stock frame has no portrait ring, so its icon sits beside the bar instead.
local profIcon = header:CreateTexture(nil, "ARTWORK")
profIcon:SetSize(22, 22)
profIcon:SetPoint("LEFT", header, "LEFT", 2, 0)
profIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
if frame.portrait then profIcon:Hide() end

local linkButton = CreateFrame("Button", nil, header)
linkButton:SetSize(28, 28)
linkButton:SetPoint("RIGHT", header, "RIGHT", -2, 2)
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

-- The stock skill bar look (the character window's skill bars).
local skillBar = CreateFrame("StatusBar", nil, header)
skillBar:SetHeight(15)
skillBar:SetPoint("LEFT", header, "LEFT", frame.portrait and 54 or 30, 0)
skillBar:SetPoint("RIGHT", linkButton, "LEFT", -6, -2)
skillBar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
skillBar:SetStatusBarColor(0.95, 0.6, 0.1)
do
	local bg = skillBar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(skillBar)
	bg:SetTexture(0, 0, 0, 0.65)
	local border = CreateFrame("Frame", nil, skillBar)
	border:SetPoint("TOPLEFT", skillBar, "TOPLEFT", -4, 4)
	border:SetPoint("BOTTOMRIGHT", skillBar, "BOTTOMRIGHT", 4, -4)
	border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
	border:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
end
local skillText = skillBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
skillText:SetPoint("CENTER", skillBar, "CENTER", 0, 1)
skillBar:EnableMouse(true)
skillBar:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:SetText((M.skillName or "") .. " - " .. RPF.RankTitle(M.maxRank))
	GameTooltip:AddLine(string.format("Skill %d of %d", M.rank or 0, M.maxRank or 0), 1, 1, 1)
	GameTooltip:Show()
end)
skillBar:SetScript("OnLeave", function () GameTooltip:Hide() end)

-----------------------------------------
-- left: search, filter, list

local left = RPF.CreateInset(content)
left:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
left:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
left:SetWidth(LIST_WIDTH)

local search = RPF.CreateEditBox(left, LIST_WIDTH - 108)
search:SetPoint("TOPLEFT", left, "TOPLEFT", 14, -8)
search:SetTextInsets(16, 4, 0, 0)
do
	local glass = search:CreateTexture(nil, "OVERLAY")
	glass:SetTexture("Interface\\Minimap\\Tracking\\None")
	glass:SetSize(14, 14)
	glass:SetPoint("LEFT", search, "LEFT", 0, 0)
	glass:SetVertexColor(0.7, 0.7, 0.7)
	local hint = search:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("LEFT", search, "LEFT", 17, 0)
	hint:SetText("Search recipes or reagents")
	hint:SetTextColor(0.6, 0.6, 0.6)
	search.hint = hint
	-- DragonUI's skin turns the input border into a plain dark field; give the box an edge so
	-- it reads as something to type in.
	if dragon then
		local edge = CreateFrame("Frame", nil, search)
		edge:SetPoint("TOPLEFT", search, "TOPLEFT", -6, 3)
		edge:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", 2, -3)
		edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
		edge:SetBackdropBorderColor(0.75, 0.6, 0.25, 1)
		edge:EnableMouse(false)
	end
end

local filterButton = RPF.CreateButton(left, FILTER or "Filter", 78, 22)
filterButton:SetPoint("LEFT", search, "RIGHT", 6, 0)
do
	local arrow = filterButton:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetSize(10, 12)
	arrow:SetPoint("RIGHT", filterButton, "RIGHT", -6, 0)
end

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
	isFavorite = function (r) return RPF.IsFavorite(r.spell) end,
	onTrackToggle = function (r) RPF.ToggleTracked(r) end,
})
list:SetPoint("TOPLEFT", left, "TOPLEFT", 6, -34)
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
-- right: the recipe, Track recipe inside it, and Create All / amount / Create under it

local right = RPF.CreateInset(content)
right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
right:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 30)
RPF.detailPane = right

local controls = CreateFrame("Frame", nil, content)
controls:SetPoint("TOPLEFT", right, "BOTTOMLEFT", 0, -4)
controls:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

local createAllButton = RPF.CreateButton(controls, CREATE_ALL or "Create All", 110, 22)
createAllButton:SetPoint("LEFT", controls, "LEFT", 0, 0)

local createButton = RPF.CreateButton(controls, CREATE or "Create", 110, 22)
createButton:SetPoint("RIGHT", controls, "RIGHT", 0, 0)

local quantity = RPF.CreateEditBox(controls, 32, true)
quantity:SetPoint("CENTER", controls, "CENTER", 0, 0)
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

local plus = CreateFrame("Button", nil, controls)
plus:SetSize(22, 22)
plus:SetPoint("LEFT", quantity, "RIGHT", 2, 0)
plus:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
plus:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
plus:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
plus:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

local trackCheck = RPF.CreateCheck(right, "Track Recipe")
trackCheck:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 8, 6)
trackCheck:SetScript("OnClick", function ()
	if RPF.selected then RPF.ToggleTracked(RPF.selected) end
end)

-- With ReagentBankUI: craft straight from the reagent bank. Create takes what the bags lack
-- out of the bank first (ReagentBankUI's Withdraw Needed, which also puts leftovers back when
-- the window closes, if that's ticked there), then crafts once it has arrived.
local bankCheck = RPF.CreateCheck(right, "Use reagent bank")
bankCheck:SetPoint("LEFT", trackCheck.label, "RIGHT", 14, 0)
bankCheck:SetScript("OnClick", function (self)
	RetailProfessionsDB.autoWithdraw = self:GetChecked() and true or false
	RPF.Fire("BAGS")
end)
bankCheck:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Use reagent bank")
	GameTooltip:AddLine("Create and Create All take whatever your bags are missing out of the reagent bank, then craft.", 1, 1, 1, true)
	GameTooltip:Show()
end)
bankCheck:SetScript("OnLeave", function () GameTooltip:Hide() end)

local function bankWithdrawAvailable()
	local RB = _G.ReagentBankUI
	return RB and RB.WithdrawNeededForSelectedRecipe and RPF.HasReagentBank() and true or false
end

local function usingBank()
	return bankWithdrawAvailable() and RetailProfessionsDB.autoWithdraw ~= false
end

-- Enchants: the item to put them on, picked once instead of after every cast. It sits at the
-- bottom right of the recipe pane.
local target = RPF.CreateItemButton(right, 28)
target:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -10, 8)
target:RegisterForClicks("LeftButtonUp", "RightButtonUp")
target.label = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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

local status = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("LEFT", bankCheck.label, "RIGHT", 10, 0)
status:SetPoint("RIGHT", right, "RIGHT", -110, 0)
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

local pendingCraft -- { spell, count, untilTime }: waiting for reagents from the bank

local function updateControls()
	local r = RPF.selected
	local learned = r and r.learned and not M.linked
	local bags, withBank = 0, 0
	if learned then bags, withBank = M.Craftable(r) end
	-- With the bank in use, what the bank holds counts as if it were in the bags.
	if usingBank() then bags = math.max(bags, withBank) end
	if pendingCraft then bags = 0 end
	local onCooldown = learned and r.cooldown and r.cooldown > 0
	local enchant = learned and r.isEnchant

	RPF.SetEnabled(createButton, learned and bags > 0 and not onCooldown)
	RPF.SetEnabled(createAllButton, learned and bags > 0 and not onCooldown and not enchant)
	RPF.SetEnabled(plus, learned and not enchant)
	RPF.SetEnabled(minus, learned and not enchant)
	if enchant then setQuantity(1) end
	createButton:SetText(r and r.learned and r.altVerb or CREATE or "Create")
	createAllButton:SetText((CREATE_ALL or "Create All") .. " [" .. (enchant and 0 or bags) .. "]")

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
	if bankWithdrawAvailable() and not M.linked then
		bankCheck:Show()
		bankCheck:SetChecked(RetailProfessionsDB.autoWithdraw ~= false)
	else
		bankCheck:Hide()
	end
	trackCheck:SetChecked(r and isTracked(r))
	RPF.SetEnabled(trackCheck, r ~= nil)
end
RPF.UpdateControls = updateControls

-- Whether the bags hold every reagent for `count` crafts.
local function bagsCover(r, count)
	for _, rg in ipairs(r.reagents) do
		if rg.id and (GetItemCount(rg.id) or 0) < rg.n * count then return false end
	end
	return true
end

local craftNow

-- Shift-click Enchant with an item in the Enchant slot: the game's "replace the enchant?" and
-- "this binds the item to you" questions for that one cast are answered yes. They come as the
-- REPLACE_ENCHANT and BIND_ENCHANT events, which UIParent turns into popups.
local confirmUntil = 0

local confirmEvents = CreateFrame("Frame")
confirmEvents:RegisterEvent("REPLACE_ENCHANT")
confirmEvents:RegisterEvent("BIND_ENCHANT")
confirmEvents:SetScript("OnEvent", function (self, event, ...)
	if GetTime() > confirmUntil then return end
	confirmUntil = 0
	local popup = event
	local a1, a2 = ...
	if event == "REPLACE_ENCHANT" then ReplaceEnchant() else BindEnchant() end
	-- UIParent may show its popup after us; close it either way.
	StaticPopup_Hide(popup)
	RPF.After(0, function () StaticPopup_Hide(popup) end)
	-- Should the game want a real click for the answer, the cast won't have started: put the
	-- question back so it can be answered by hand.
	RPF.After(0.5, function ()
		if not UnitCastingInfo("player") and not SpellIsTargeting() then
			StaticPopup_Show(popup, a1, a2)
		end
	end)
end)

local function craft(count, noConfirm)
	local r = RPF.selected
	if not (r and r.learned) then return end
	if r.isEnchant then count = 1 end
	-- Short in the bags but the bank has it: fetch it first, craft when it lands.
	if usingBank() and not bagsCover(r, count) then
		local _, withBank = M.Craftable(r)
		if withBank >= count then
			setQuantity(count)
			local ok = pcall(_G.ReagentBankUI.WithdrawNeededForSelectedRecipe, _G.ReagentBankUI)
			if ok then
				pendingCraft = { spell = r.spell, count = count, untilTime = GetTime() + 10, noConfirm = noConfirm }
				RPF.Status("Taking the reagents out of the reagent bank...")
				updateControls()
				RPF.After(10.1, function ()
					if pendingCraft and pendingCraft.untilTime <= GetTime() then
						pendingCraft = nil
						RPF.Status("The reagents didn't arrive from the bank. Is there room in your bags?", true)
						updateControls()
					end
				end)
				return
			end
		end
	end
	craftNow(r, count, noConfirm)
end

craftNow = function (r, count, noConfirm)
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
			if noConfirm then confirmUntil = GetTime() + 3 end
			if t.inv then PickupInventoryItem(t.inv) else PickupContainerItem(t.bag, t.slot) end
		end
		return
	end
	DoTradeSkill(index, count)
	-- Typing a number and pressing Create straight away leaves the box focused.
	quantity:ClearFocus()
end

createButton:SetScript("OnClick", function () craft(getQuantity(), IsShiftKeyDown()) end)
createButton:SetScript("OnEnter", function (self)
	local r = RPF.selected
	if not (r and r.isEnchant and r.learned) then return end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(self:GetText())
	GameTooltip:AddLine("Shift-click with an item in the Enchant slot to skip the \"replace enchant\" and \"bind to you\" questions.", 1, 1, 1, true)
	GameTooltip:Show()
end)
createButton:SetScript("OnLeave", function () GameTooltip:Hide() end)
createAllButton:SetScript("OnClick", function ()
	local r = RPF.selected
	if not r then return end
	local bags, withBank = M.Craftable(r)
	if usingBank() then bags = math.max(bags, withBank) end
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
	local texture = p and p.texture or (GetTradeSkillTexture and GetTradeSkillTexture()) or "Interface\\Icons\\INV_Misc_QuestionMark"
	if frame.portrait then RPF.SetPortrait(frame.portrait, texture) else profIcon:SetTexture(texture) end
	-- Someone else's linked profession: their name in the title.
	title:SetText(M.linked and ((M.linkedName or "") .. " - " .. (M.skillName or "")) or (M.skillName or "Professions"))
	skillBar:SetMinMaxValues(0, math.max(1, M.maxRank or 1))
	skillBar:SetValue(M.rank or 0)
	skillText:SetText(string.format("%s %d/%d", M.skillName or "", M.rank or 0, M.maxRank or 0))
	if M.linked then linkButton:Hide() else linkButton:Show() end
	filterButton:SetText(filtersActive() and ("|cff4fc3f7" .. (FILTER or "Filter") .. "|r") or (FILTER or "Filter"))
end

-- Reads the client again (unless only the view changed) and redraws.
Rebuild = function (viewOnly)
	if not frame:IsShown() then return end
	if not viewOnly and not M.Scan() then return end
	local f = RPF.filter
	local state = { text = f.text, haveMats = f.haveMats, skillUp = f.skillUp, slot = f.slot,
		unlearned = RetailProfessionsDB.showUnlearned and not M.linked, learnableOnly = f.learnableOnly,
		favorites = not M.linked and RetailProfessionsCharDB.favorites or nil }
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
	-- The bank's reagents arrived: craft. If the game wants a click for that, say so.
	local p = pendingCraft
	if p and RPF.selected and RPF.selected.spell == p.spell and bagsCover(RPF.selected, p.count) then
		pendingCraft = nil
		local r = RPF.selected
		craftNow(r, p.count, p.noConfirm)
		RPF.After(0.6, function ()
			if not UnitCastingInfo("player") and RPF.selected == r and bagsCover(r, p.count) then
				RPF.Status("The reagents are in your bags. Press " .. (r.altVerb or CREATE or "Create") .. ".")
			end
		end)
	elseif p and RPF.selected and RPF.selected.spell ~= p.spell then
		pendingCraft = nil
	end
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
RPF.On("FAVORITES", function () Rebuild(true) end)
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
