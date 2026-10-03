-- RetailProfessions widgets (from RetailAH): buttons, inputs, panes and item buttons, dressed in DragonUI's retail art
-- when DragonUI is loaded and in a dark retail-like style of their own otherwise.

local RPF = RetailProfessions

local nameCounter = 0
local function uniqueName(base)
	nameCounter = nameCounter + 1
	return "RetailProfessions" .. base .. nameCounter
end
RPF.UniqueName = uniqueName

-----------------------------------------
-- DragonUI, if it's there and new enough to carry the helpers we borrow

function RPF.Dragon()
	local D = _G.DragonUI
	if D and D._dir and D.atlasinfo and D.SafeSetAtlas and D.SkinRedButton and NineSliceUtils
			and D.CharacterPanel and D.CharacterPanel.ReskinTab then
		return D, D.CharacterPanel
	end
end

local function solid(host, layer, r, g, b, a, sublevel)
	local tex = host:CreateTexture(nil, layer, nil, sublevel)
	tex:SetTexture(r, g, b, a)
	return tex
end

local function tiled(host, layer, sublevel, file)
	local tex = host:CreateTexture(nil, layer, nil, sublevel)
	tex:SetTexture(file, "REPEAT", "REPEAT")
	tex:SetHorizTile(true)
	tex:SetVertTile(true)
	return tex
end

-----------------------------------------
-- window chrome and panes

-- Without DragonUI every window is a stock Blizzard dialog frame: the dialog-box border and
-- background with the gold header plate for its title.
local DIALOG_BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

-- Dresses a window and gives it a title (frame.title), a close button (frame.closeButton) and a
-- title bar to drag it by. DragonUI's metal frame on rock when DragonUI is loaded, otherwise the
-- stock dialog frame. opts = { portrait = round portrait top-left (frame.portrait, DragonUI only;
-- set it with RPF.SetPortrait), closeName = global name for the close button, onMoved = fn }.
-- Returns true with DragonUI, and the y offset content starts at.
function RPF.DressWindow(frame, opts)
	opts = opts or {}
	local D, CP = RPF.Dragon()
	local close = CreateFrame("Button", opts.closeName, frame, "UIPanelCloseButton")
	frame.closeButton = close

	if D then
		local rock = tiled(frame, "BACKGROUND", -8, D._dir .. "UI\\ui-background-rock")
		rock:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -21)
		rock:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

		local streaks = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
		if D:SafeSetAtlas(streaks, "_UI-Frame-TopTileStreaks") then
			streaks:SetHorizTile(true)
			streaks:SetHeight(43)
			streaks:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -21)
			streaks:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -21)
		else
			streaks:Hide()
		end

		-- On its own frame above the content, so no child panel draws over the metal.
		local chrome = CreateFrame("Frame", nil, frame)
		chrome:SetAllPoints(frame)
		chrome:SetFrameLevel(frame:GetFrameLevel() + 30)
		chrome:EnableMouse(false)
		local layout = opts.portrait and NineSliceUtils.GetLayout("PortraitFrameTemplate")
			or NineSliceUtils.GetLayout("NoPortraitFrameTemplate") or NineSliceUtils.GetLayout("PortraitFrameTemplate")
		NineSliceUtils.ApplyLayout(chrome, layout)
		frame.chrome = chrome
		if opts.portrait then
			-- Where DragonUI's spellbook puts its portrait, under the frame's ring.
			frame.portrait = chrome:CreateTexture(nil, "ARTWORK")
			frame.portrait:SetSize(58, 58)
			frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 6)
		end

		frame.title = chrome:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.title:SetPoint("TOP", frame, "TOP", 0, -5)
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
		if CP.ModernizeCloseButton then
			CP.ModernizeCloseButton(close, chrome, 1, 0)
			close:SetFrameLevel(chrome:GetFrameLevel() + 5)
		end
	else
		frame:SetBackdrop(DIALOG_BACKDROP)
		frame.chrome = frame
		local header = frame:CreateTexture(nil, "ARTWORK")
		header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
		header:SetSize(320, 64)
		header:SetPoint("TOP", frame, "TOP", 0, 12)
		frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.title:SetPoint("TOP", header, "TOP", 0, -14)
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	end

	local dragBar = CreateFrame("Frame", nil, frame)
	dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, D and 0 or 12)
	dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, 0)
	dragBar:SetHeight(D and 24 or 36)
	dragBar:EnableMouse(true)
	dragBar:RegisterForDrag("LeftButton")
	dragBar:SetScript("OnDragStart", function () frame:StartMoving() end)
	dragBar:SetScript("OnDragStop", function ()
		frame:StopMovingOrSizing()
		if opts.onMoved then opts.onMoved() end
	end)

	return D and true or false, D and -28 or -32
end

-- A round picture of an icon, as portraits and retail's recipe icons are drawn.
function RPF.SetPortrait(texture, path)
	if not texture then return end
	if path and SetPortraitToTexture then
		texture:SetTexCoord(0, 1, 0, 1)
		SetPortraitToTexture(texture, path)
	else
		texture:SetTexture(path)
	end
end

-- A recessed pane (retail's InsetFrameTemplate).
function RPF.CreateInset(parent)
	local pane = CreateFrame("Frame", nil, parent)
	local D = RPF.Dragon()
	if D then
		local bg = tiled(pane, "BACKGROUND", -5, D._dir .. "UI\\ui-background-marble")
		bg:SetAllPoints(pane)
		NineSliceUtils.ApplyLayout(pane, NineSliceUtils.GetLayout("InsetFrameTemplate"))
	else
		pane:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		pane:SetBackdropColor(0, 0, 0, 0.5)
		pane:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	end
	return pane
end

-- A FauxScrollFrame's bar: DragonUI's thin one, or the stock one.
function RPF.SkinScrollBar(scroll, scrollName)
	local bar = _G[scrollName .. "ScrollBar"]
	if not bar then return end
	local _, CP = RPF.Dragon()
	if CP and CP.ReskinScrollBar then
		pcall(CP.ReskinScrollBar, scroll, scroll, -7, 18, -7, true)
	end
	-- Otherwise the stock scroll bar stays as it is.
end

-----------------------------------------
-- controls

function RPF.SetEnabled(control, enabled)
	if enabled then control:Enable() else control:Disable() end
end

function RPF.CreateButton(parent, text, width, height)
	local btn = CreateFrame("Button", uniqueName("Button"), parent, "UIPanelButtonTemplate")
	btn:SetSize(width or 100, height or 22)
	btn:SetText(text or "")
	local D = RPF.Dragon()
	if D then D.SkinRedButton(btn) end
	return btn
end

local function skinInput(eb)
	local D = RPF.Dragon()
	if not D then return end
	local regions = { eb:GetRegions() }
	for i = 1, #regions do
		local r = regions[i]
		if r:GetObjectType() == "Texture" then
			local path = r:GetTexture()
			if type(path) == "string" and path:lower():find("common%-input%-border") then
				r:SetTexture(0, 0, 0, 0.55)
			end
		end
	end
end

function RPF.CreateEditBox(parent, width, numeric)
	local eb = CreateFrame("EditBox", uniqueName("EditBox"), parent, "InputBoxTemplate")
	eb:SetSize(width or 120, 20)
	-- InputBoxTemplate's boxes take the keyboard as soon as they exist; ours only when clicked.
	eb:SetAutoFocus(false)
	eb:ClearFocus()
	if numeric then eb:SetNumeric(true) end
	eb:SetScript("OnEscapePressed", function (self) self:ClearFocus() end)
	eb:SetScript("OnEnterPressed", function (self) self:ClearFocus() end)
	skinInput(eb)
	return eb
end

function RPF.CreateCheck(parent, label)
	local name = uniqueName("Check")
	local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	local text = _G[name .. "Text"]
	text:SetText(label or "")
	text:SetFontObject(GameFontHighlightSmall)
	cb.label = text
	local _, CP = RPF.Dragon()
	if CP and CP.SkinCheckbox then CP.SkinCheckbox(cb) end
	return cb
end

-- A square item button with a quality border.
function RPF.CreateItemButton(parent, size)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(size or 37, size or 37)
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetAllPoints(btn)
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	btn.border = btn:CreateTexture(nil, "OVERLAY")
	btn.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	btn.border:SetBlendMode("ADD")
	btn.border:SetPoint("CENTER", btn, "CENTER")
	btn.border:SetSize((size or 37) * 1.8, (size or 37) * 1.8)
	btn.border:Hide()
	btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
	local hl = btn:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(btn)
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")

	btn.SetItem = function (self, texture, quality, count)
		self.icon:SetTexture(texture)
		if quality and quality >= 2 then
			local r, g, b = RPF.QualityColor(quality)
			self.border:SetVertexColor(r, g, b)
			self.border:Show()
		else
			self.border:Hide()
		end
		self.count:SetText(count and count > 1 and count or "")
	end
	return btn
end
