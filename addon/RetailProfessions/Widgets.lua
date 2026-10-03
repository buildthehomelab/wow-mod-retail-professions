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

local FALLBACK_BACKDROP = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- The outer window: DragonUI's metal frame (the one without a portrait ring) on rock, or a dark
-- bordered box.
function RPF.DressWindow(frame)
	local D = RPF.Dragon()
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
		NineSliceUtils.ApplyLayout(chrome, NineSliceUtils.GetLayout("NoPortraitFrameTemplate")
			or NineSliceUtils.GetLayout("PortraitFrameTemplate"))
		frame.chrome = chrome
		return true
	end

	frame:SetBackdrop(FALLBACK_BACKDROP)
	frame:SetBackdropColor(0.05, 0.05, 0.06, 0.96)
	frame:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)
	local band = solid(frame, "BORDER", 0.12, 0.12, 0.14, 1)
	band:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
	band:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	band:SetHeight(20)
	local rule = solid(frame, "BORDER", 1, 0.82, 0, 0.35)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", band, "BOTTOMLEFT")
	rule:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")
	frame.chrome = frame
	return false
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
		pane:SetBackdropColor(0.03, 0.03, 0.04, 0.9)
		pane:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.9)
	end
	return pane
end

-- A FauxScrollFrame's bar: DragonUI's thin one, or a dark track behind the stock one.
function RPF.SkinScrollBar(scroll, scrollName)
	local bar = _G[scrollName .. "ScrollBar"]
	if not bar then return end
	local _, CP = RPF.Dragon()
	if CP and CP.ReskinScrollBar then
		pcall(CP.ReskinScrollBar, scroll, scroll, -7, 18, -7, true)
		return
	end
	-- The stock arrows sit just outside the slider.
	local track = solid(bar, "BACKGROUND", 0, 0, 0, 0.45)
	track:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 18)
	track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -18)
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
	eb:SetAutoFocus(false)
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
