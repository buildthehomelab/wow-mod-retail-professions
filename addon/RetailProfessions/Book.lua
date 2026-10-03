-- The professions book (K): every profession and secondary skill you have, with its rank and
-- skill bar, a button to open it, the gathering or fishing action where there is one, and a
-- way to unlearn it.

local RPF = RetailProfessions

local WIDTH = 420
local ROW_HEIGHT = 58
local MAX_ROWS = 8

local book = CreateFrame("Frame", "RetailProfessionsBook", UIParent)
book:SetSize(WIDTH, 120)
book:EnableMouse(true)
book:SetToplevel(true)
book:SetMovable(true)
book:SetClampedToScreen(true)
book:SetFrameStrata("MEDIUM")
book:Hide()
table.insert(UISpecialFrames, "RetailProfessionsBook")
RPF.book = book

local function placeBook()
	book:ClearAllPoints()
	local p = RetailProfessionsDB and RetailProfessionsDB.bookPosition
	if p then
		book:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		book:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 420, -140)
	end
end

RPF.On("RESET_POSITION", function ()
	RetailProfessionsDB.bookPosition = nil
	placeBook()
	RPF.SyncSpellButtons()
end)

local dragon = RPF.DressWindow(book)

local title = book.chrome:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", book, "TOP", 0, -5)
title:SetText(TRADE_SKILLS or "Professions")

local dragBar = CreateFrame("Frame", nil, book)
dragBar:SetPoint("TOPLEFT", book, "TOPLEFT", 0, 0)
dragBar:SetPoint("TOPRIGHT", book, "TOPRIGHT", -28, 0)
dragBar:SetHeight(24)
dragBar:EnableMouse(true)
dragBar:RegisterForDrag("LeftButton")
dragBar:SetScript("OnDragStart", function () book:StartMoving() end)
dragBar:SetScript("OnDragStop", function ()
	book:StopMovingOrSizing()
	local point, _, relativePoint, x, y = book:GetPoint(1)
	RetailProfessionsDB.bookPosition = { point, relativePoint, x, y }
	RPF.SyncSpellButtons()
end)

local close = CreateFrame("Button", "RetailProfessionsBookCloseButton", book, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", book, "TOPRIGHT", 2, 2)
do
	local _, CP = RPF.Dragon()
	if CP and CP.ModernizeCloseButton then
		CP.ModernizeCloseButton(close, book.chrome, 1, 0)
		close:SetFrameLevel(book.chrome:GetFrameLevel() + 5)
	end
end

local inset = RPF.CreateInset(book)
inset:SetPoint("TOPLEFT", book, "TOPLEFT", 10, dragon and -28 or -30)
inset:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -10, 30)

local hint = book:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("BOTTOM", book, "BOTTOM", 0, 12)

local empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("CENTER", inset, "CENTER")
empty:SetText("You haven't learned a profession yet.\nVisit a trainer in any capital city.")

-----------------------------------------
-- rows

local function actionButton(parent, text, width)
	-- Drawn here, clicked through the secure button lying over it.
	local b = RPF.CreateButton(parent, text, width, 22)
	b:EnableMouse(false)
	b.secure = RPF.CreateSpellButton(nil)
	return b
end

local sectionLabels = {}
local function sectionLabel(i)
	if not sectionLabels[i] then
		local fs = inset:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		sectionLabels[i] = fs
	end
	return sectionLabels[i]
end

local rows = {}
for i = 1, MAX_ROWS do
	local row = CreateFrame("Frame", nil, inset)
	row:SetHeight(ROW_HEIGHT)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(40, 40)
	row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -2)
	row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.rank:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
	row.rank:SetTextColor(0.7, 0.7, 0.7)

	row.bar = CreateFrame("StatusBar", nil, row)
	row.bar:SetSize(180, 12)
	row.bar:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 2)
	row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	row.bar:SetStatusBarColor(0.1, 0.55, 0.15)
	local bg = row.bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(row.bar)
	bg:SetTexture(0, 0, 0, 0.6)
	row.barText = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.barText:SetPoint("CENTER", row.bar, "CENTER", 0, 1)

	row.open = actionButton(row, "Open", 64)
	row.open:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
	row.extra = actionButton(row, "", 96)
	row.extra:SetPoint("TOPRIGHT", row.open, "BOTTOMRIGHT", 0, -2)

	row.unlearn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
	row.unlearn:SetSize(22, 22)
	row.unlearn:SetPoint("RIGHT", row.open, "LEFT", -4, 0)
	row.unlearn:SetScript("OnClick", function (self)
		local known = self:GetParent().known
		if not known then return end
		local dialog = StaticPopup_Show("RETAILPROFESSIONS_UNLEARN", known.profession.localName)
		if dialog then dialog.data = known.profession.localName end
	end)
	row.unlearn:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Unlearn")
		GameTooltip:AddLine("Forget this profession and every recipe in it.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row.unlearn:SetScript("OnLeave", function () GameTooltip:Hide() end)

	local rule = row:CreateTexture(nil, "BORDER")
	rule:SetTexture(1, 1, 1, 0.06)
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 0)
	rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 0)
	row:Hide()
	rows[i] = row
end

-- Unlearning goes by name: skill line indexes move whenever a skill is added or removed.
StaticPopupDialogs["RETAILPROFESSIONS_UNLEARN"] = {
	text = "Unlearn %s? You lose your skill and every recipe you know in it.",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function (self, name)
		-- A collapsed header hides its skills; open them all first.
		ExpandSkillHeader(0)
		for i = 1, GetNumSkillLines() do
			if GetSkillLineInfo(i) == name then
				AbandonSkill(i)
				return
			end
		end
	end,
	timeout = 0,
	whileDead = 1,
	exclusive = 1,
	hideOnEscape = 1,
}

local function bind(button, spell)
	if spell then
		button:Show()
		RPF.BindSpellButton(button.secure, button, spell, book)
	else
		button:Hide()
		RPF.BindSpellButton(button.secure, nil, nil)
	end
end

local function refresh()
	if not RetailProfessionsDB then return end
	local known = RPF.KnownProfessions()
	for _, fs in pairs(sectionLabels) do fs:Hide() end

	local y = -8
	local lastSection
	local n = 0
	for _, k in ipairs(known) do
		if n >= MAX_ROWS then break end
		local p = k.profession
		local section = p.class and "Class" or p.secondary and "Secondary Skills" or "Professions"
		if section ~= lastSection then
			local fs = sectionLabel(section == "Professions" and 1 or section == "Secondary Skills" and 2 or 3)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, y)
			fs:SetText(section)
			fs:Show()
			y = y - 18
			lastSection = section
		end
		n = n + 1
		local row = rows[n]
		row.known = k
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, y)
		row:SetPoint("RIGHT", inset, "RIGHT", -4, 0)
		y = y - ROW_HEIGHT

		row.icon:SetTexture(p.texture)
		row.name:SetText(p.localName)
		row.rank:SetText(RPF.RankTitle(k.maxRank))
		row.bar:SetMinMaxValues(0, math.max(1, k.maxRank))
		row.bar:SetValue(k.rank)
		row.barText:SetText(k.rank .. " / " .. k.maxRank)

		local openName = p.openName and GetSpellInfo(p.openName) and p.openName or nil
		row.open:SetText(p.id == 186 and (p.openName or "Smelting") or "Open")
		row.open:SetWidth(p.id == 186 and 80 or 64)
		bind(row.open, openName)
		local extraName = p.extraName and GetSpellInfo(p.extraName) and p.extraName or nil
		row.extra:SetText(extraName or "")
		bind(row.extra, extraName)
		if not openName and extraName then
			-- Nothing to open: the action takes the top spot.
			row.extra:ClearAllPoints()
			row.extra:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
			row.unlearn:ClearAllPoints()
			row.unlearn:SetPoint("RIGHT", row.extra, "LEFT", -4, 0)
		else
			row.extra:ClearAllPoints()
			row.extra:SetPoint("TOPRIGHT", row.open, "BOTTOMRIGHT", 0, -2)
			row.unlearn:ClearAllPoints()
			row.unlearn:SetPoint("RIGHT", openName and row.open or row, openName and "LEFT" or "RIGHT", openName and -4 or -8, 0)
		end
		if k.abandonable then row.unlearn:Show() else row.unlearn:Hide() end
		row:Show()
	end
	for i = n + 1, MAX_ROWS do
		rows[i]:Hide()
		rows[i].known = nil
		bind(rows[i].open, nil)
		bind(rows[i].extra, nil)
	end

	if n == 0 then empty:Show() else empty:Hide() end
	book:SetHeight(math.max(140, -y + 8 + (dragon and 28 or 30) + 30))
	local key = GetBindingKey and GetBindingKey("RETAILPROFESSIONS_BOOK")
	hint:SetText(RPF.InCombat() and "|cffff4040Opening professions works again after combat.|r"
		or (key and ("Press " .. key .. " to open or close this window.") or "Type /prof to open or close this window."))
	RPF.SyncSpellButtons()
end

function RPF.ToggleBook()
	if book:IsShown() then book:Hide() else book:Show() end
end

book:SetScript("OnShow", function ()
	PlaySound("igSpellBookOpen")
	placeBook()
	refresh()
end)
book:SetScript("OnHide", function ()
	PlaySound("igSpellBookClose")
	RPF.SyncSpellButtons()
end)

RPF.On("SKILLS", function () if book:IsShown() then refresh() end end)
-- The book steps aside when a profession window opens; it would otherwise sit on top of it.
RPF.On("SHOW", function () if book:IsShown() then book:Hide() end end)
RPF.FollowRaises(book)
RPF.On("SECURE_STATE", function () if book:IsShown() then refresh() end end)

-- Key binding (Bindings.xml), and K for it the first time, when K is free.
BINDING_HEADER_RETAILPROFESSIONS = "Retail Professions"
BINDING_NAME_RETAILPROFESSIONS_BOOK = "Open the professions book"

RPF.On("LOGIN", function ()
	if RetailProfessionsDB.offeredKey then return end
	RetailProfessionsDB.offeredKey = true
	if GetBindingAction("K") == "" then
		SetBinding("K", "RETAILPROFESSIONS_BOOK")
		SaveBindings(GetCurrentBindingSet())
		RPF.Print("press |cffffd200K|r to open your professions.")
	end
end)
