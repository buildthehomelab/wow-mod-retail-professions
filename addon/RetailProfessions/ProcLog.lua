-- Craft procs: every Multicraft and Resourcefulness the server reports (PK, Core.lua), kept per
-- character with how often they come up, in a small log window (/prof log, or the button beside
-- the chat link). Each proc also goes to scrolling combat text: MikScrollingBattleText's
-- Notification area when MSBT is loaded, otherwise Blizzard's floating combat text when it's on.

local RPF = RetailProfessions
local M = RPF.Model
local P = RPF.Profit

local MAX_ENTRIES = 200
local KINDS = { "M", "R" }
local LABEL = { M = "Multicraft", R = "Resourcefulness" }
local COLOR = { M = { 1, 0.82, 0 }, R = { 0.35, 0.9, 0.55 } }
local HEX = { M = "|cffffd200", R = "|cff59e68c" }
local BIT = { M = RPF.PERK_MULTICRAFT, R = RPF.PERK_RESOURCEFUL }

local L = {}
RPF.ProcLog = L

-- Per kind: procs, items they gave, what those were worth (copper, when priced) and how many
-- crafts could have got one.
local function blank()
	local t = {}
	for _, kind in ipairs(KINDS) do t[kind] = { procs = 0, items = 0, value = 0, crafts = 0 } end
	return t
end

local session = blank()

local function saved()
	local char = RetailProfessionsCharDB
	if not char then return nil end
	char.procLog = char.procLog or { entries = {}, total = blank() }
	return char.procLog
end

local function eachItem(list, fn)
	for id, n in (list or ""):gmatch("(%d+)%*(%d+)") do fn(tonumber(id), tonumber(n)) end
end

local function itemName(id, link)
	local info = RPF.Item(id)
	if not info then return "item " .. id end
	return link and info.link or info.name
end

-- "Multicraft! +2 Bolt of Linen Cloth" / "Resourcefulness! 2 Linen Cloth, 1 Coarse Thread back".
function L.Describe(kind, list)
	local parts = {}
	eachItem(list, function (id, n)
		table.insert(parts, (kind == "M" and "+" or "") .. n .. " " .. itemName(id))
	end)
	local text = LABEL[kind] .. "! " .. table.concat(parts, ", ")
	return kind == "R" and (text .. " back") or text
end

-- One line of the log: time, recipe, what came of it, with item links.
function L.EntryText(e)
	local recipe = e.spell and GetSpellInfo(e.spell) or "?"
	local parts = {}
	eachItem(e.items, function (id, n) table.insert(parts, n .. "x " .. itemName(id, true)) end)
	local text = string.format("|cff888888%s|r %s%s|r %s: %s%s", date("%H:%M", e.t), HEX[e.kind], LABEL[e.kind], recipe,
		e.kind == "M" and "+" or "", table.concat(parts, ", "))
	if (e.value or 0) > 0 then text = text .. " |cff888888(" .. RPF.Money(e.value) .. ")|r" end
	return text
end

-- "Multicraft: 4 in 30 crafts (13%), +9 items, worth 1g 20s"
function L.SummaryText(totals, kind)
	local t = totals[kind]
	local text = HEX[kind] .. LABEL[kind] .. ":|r "
	if t.procs == 0 and t.crafts == 0 then return text .. "|cff888888none yet|r" end
	if t.crafts > 0 then
		text = text .. string.format("%d in %d crafts (%d%%)", t.procs, t.crafts, math.floor(t.procs * 100 / t.crafts + 0.5))
	else
		text = text .. t.procs .. (t.procs == 1 and " proc" or " procs")
	end
	if t.items > 0 then
		text = text .. (kind == "M" and (", +" .. t.items .. " items") or (", " .. t.items .. " reagents back"))
	end
	if t.value > 0 then text = text .. ", worth " .. RPF.Money(t.value) end
	return text
end

function L.Session() return session end
function L.Total() local log = saved() return log and log.total end
function L.Entries() local log = saved() return log and log.entries or {} end

-----------------------------------------
-- scrolling combat text

local function scrollText(kind, list, icon)
	if RetailProfessionsDB and RetailProfessionsDB.procText == false then return end
	local text, c = L.Describe(kind, list), COLOR[kind]
	if MikSBT and MikSBT.DisplayMessage and not (MikSBT.IsModDisabled and MikSBT.IsModDisabled()) then
		-- MSBT takes colours as 0-255; sticky so it pops like a crit.
		MikSBT.DisplayMessage(text, MikSBT.DISPLAYTYPE_NOTIFICATION or "Notification", true,
			c[1] * 255, c[2] * 255, c[3] * 255, nil, nil, nil, icon)
	elseif CombatText_AddMessage and CombatText_StandardScroll and SHOW_COMBAT_TEXT == "1" then
		CombatText_AddMessage((icon and ("|T" .. icon .. ":0|t ") or "") .. text, CombatText_StandardScroll,
			c[1], c[2], c[3], "sticky")
	end
end

-----------------------------------------
-- counting

RPF.On("PERK", function (spell, kind, list)
	if not LABEL[kind] then return end
	local count, value, first = 0, 0, nil
	eachItem(list, function (id, n)
		count = count + n
		first = first or id
		-- A second batch is worth what it sells for; reagents back, what buying them would cost.
		local unit = kind == "M" and P.SellValue(id) or P.BuyCost(id)
		value = value + (unit or 0) * n
	end)
	if count == 0 then return end

	local log = saved()
	local totals = { session, log and log.total }
	for _, t in pairs(totals) do
		local k = t[kind]
		k.procs, k.items, k.value = k.procs + 1, k.items + count, k.value + value
	end
	if log then
		table.insert(log.entries, { t = time(), spell = spell, kind = kind, items = list, value = value })
		while #log.entries > MAX_ENTRIES do table.remove(log.entries, 1) end
	end
	scrollText(kind, list, RPF.ItemIcon(first))
	L.Refresh()
end)

-- Every finished craft of a recipe that can proc counts towards the rate. The cast only names
-- the spell, so it's matched against the open profession's recipes (crafts made with the window
-- closed, from a macro, aren't counted).
RPF.On("CAST", function (event, spellName)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" or not spellName or not RPF.active or M.linked or not RPF.perks then return end
	local recipe
	for _, r in pairs(M.bySpell) do
		if r.learned and r.name == spellName and (r.perks or 0) > 0 then recipe = r break end
	end
	if not recipe then return end
	local log = saved()
	for _, kind in ipairs(KINDS) do
		if bit.band(recipe.perks, BIT[kind]) ~= 0 then
			session[kind].crafts = session[kind].crafts + 1
			if log then log.total[kind].crafts = log.total[kind].crafts + 1 end
		end
	end
	L.Refresh()
end)

function L.Clear()
	local char = RetailProfessionsCharDB
	if char then char.procLog = nil end
	session = blank()
	L.Refresh()
end

-----------------------------------------
-- the window

local frame = CreateFrame("Frame", "RetailProfessionsProcLog", UIParent)
frame:SetSize(460, 340)
frame:EnableMouse(true)
frame:SetToplevel(true)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:SetFrameStrata("DIALOG")
frame:Hide()
table.insert(UISpecialFrames, "RetailProfessionsProcLog")
L.frame = frame

local function place()
	frame:ClearAllPoints()
	local p = RetailProfessionsDB and RetailProfessionsDB.procLogPosition
	if p then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	end
end

local dragon, contentTop = RPF.DressWindow(frame, {
	closeName = "RetailProfessionsProcLogCloseButton",
	onMoved = function ()
		local point, _, relativePoint, x, y = frame:GetPoint(1)
		RetailProfessionsDB.procLogPosition = { point, relativePoint, x, y }
	end,
})
frame.title:SetText("Craft Procs")

local content = CreateFrame("Frame", nil, frame)
content:SetPoint("TOPLEFT", frame, "TOPLEFT", dragon and 12 or 18, contentTop - 4)
content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", dragon and -12 or -18, dragon and 10 or 16)

local function heading(text, anchor)
	local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	if anchor then fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -8, -8) else fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0) end
	fs:SetText(text)
	return fs
end

-- The Multicraft and Resourcefulness lines under a heading, indented a little.
local function summaryLines(head)
	local lines = {}
	for i, kind in ipairs(KINDS) do
		local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		if i == 1 then fs:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 8, -3) else fs:SetPoint("TOPLEFT", lines[KINDS[i - 1]], "BOTTOMLEFT", 0, -2) end
		fs:SetPoint("RIGHT", content, "RIGHT", 0, 0)
		fs:SetJustifyH("LEFT")
		lines[kind] = fs
	end
	return lines
end

local sessionLines = summaryLines(heading("This session"))
local totalLines = summaryLines(heading("All time on this character", sessionLines.R))

local inset = RPF.CreateInset(content)
inset:SetPoint("TOPLEFT", totalLines.R, "BOTTOMLEFT", -8, -8)
inset:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 30)

local messages = CreateFrame("ScrollingMessageFrame", nil, inset)
messages:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -6)
messages:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -8, 6)
messages:SetFontObject(GameFontHighlightSmall)
messages:SetJustifyH("LEFT")
messages:SetFading(false)
messages:SetMaxLines(MAX_ENTRIES)
messages:EnableMouse(true)
messages:EnableMouseWheel(true)
if messages.SetHyperlinksEnabled then messages:SetHyperlinksEnabled(true) end
messages:SetScript("OnMouseWheel", function (self, delta)
	if IsShiftKeyDown() then
		if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
	elseif delta > 0 then
		self:ScrollUp()
	else
		self:ScrollDown()
	end
end)
messages:SetScript("OnHyperlinkEnter", function (self, link)
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
	GameTooltip:SetHyperlink(link)
	RPF.ShowItemTooltip(self)
end)
messages:SetScript("OnHyperlinkLeave", function () RPF.HideItemTooltip() end)
-- Shift-click puts the item in chat, as anywhere else.
messages:SetScript("OnHyperlinkClick", function (self, link, text, button) SetItemRef(link, text, button) end)

local empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
empty:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -12)
empty:SetPoint("RIGHT", inset, "RIGHT", -12, 0)
empty:SetJustifyH("LEFT")
empty:SetText("No procs yet. Recipes that can multicraft or give reagents back say so in their tooltip; "
	.. "the closer a recipe is to grey, the more often it happens.")

local textCheck = RPF.CreateCheck(content, "Scrolling text")
textCheck:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", -2, 0)
textCheck:SetScript("OnClick", function (self)
	RetailProfessionsDB.procText = self:GetChecked() and true or false
end)
textCheck:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Scrolling text")
	GameTooltip:AddLine("Shows each proc as it happens: in MikScrollingBattleText's Notification area when MSBT is "
		.. "loaded, otherwise in the game's floating combat text (when that's turned on in Interface options).", 1, 1, 1, true)
	GameTooltip:Show()
end)
textCheck:SetScript("OnLeave", function () GameTooltip:Hide() end)

StaticPopupDialogs.RETAILPROFESSIONS_CLEAR_PROCS = {
	text = "Clear the craft proc log and its all-time counts for this character?",
	button1 = YES or "Yes", button2 = NO or "No",
	OnAccept = function () L.Clear() end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}

local clearButton = RPF.CreateButton(content, "Clear", 80, 22)
clearButton:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 2)
clearButton:SetScript("OnClick", function () StaticPopup_Show("RETAILPROFESSIONS_CLEAR_PROCS") end)

function L.Refresh()
	if not frame:IsShown() then return end
	local total = L.Total() or blank()
	for _, kind in ipairs(KINDS) do
		sessionLines[kind]:SetText(L.SummaryText(session, kind))
		totalLines[kind]:SetText(L.SummaryText(total, kind))
	end
	local entries = L.Entries()
	messages:Clear()
	for i = 1, #entries do messages:AddMessage(L.EntryText(entries[i])) end
	messages:ScrollToBottom()
	if #entries == 0 then empty:Show() else empty:Hide() end
	textCheck:SetChecked(RetailProfessionsDB.procText ~= false)
end

frame:SetScript("OnShow", L.Refresh)
-- Item names arrive late for items the client hasn't seen.
RPF.On("ITEM_INFO", L.Refresh)
RPF.On("RESET_POSITION", function ()
	RetailProfessionsDB.procLogPosition = nil
	place()
end)

function L.Toggle()
	if frame:IsShown() then
		frame:Hide()
	else
		place()
		frame:Show()
	end
end
