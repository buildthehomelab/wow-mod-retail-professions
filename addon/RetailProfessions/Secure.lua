-- Opening a profession means casting its spell, which only a secure button may do. Secure
-- buttons can't be shown, hidden or moved in combat, and neither can the frames they sit in,
-- so ours belong to UIParent and lie invisibly over the drawn tabs and buttons of our windows.
-- The windows themselves stay ordinary frames that open and close at any time. The buttons
-- follow the windows out of combat and step aside when combat starts.

local RPF = RetailProfessions

local buttons = {}
-- Set from PLAYER_REGEN_DISABLED on: InCombatLockdown() is still false while that event is
-- handled, and nothing may show the buttons again until combat ends.
local combat = false

-- A clickable area that casts `spell` (a localized name) over `region` while `region` shows.
function RPF.CreateSpellButton(name)
	local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("type", "spell")
	b:Hide()
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(b)
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")
	b:SetScript("OnEnter", function (self) if self.onEnter then self.onEnter(self) end end)
	b:SetScript("OnLeave", function () GameTooltip:Hide() end)
	table.insert(buttons, b)
	return b
end

-- Points a button at a region and a spell; nil spell or region retires it. `host` is the window
-- the region belongs to: the button takes its strata and sits just above it, so anything opened
-- over the window covers the button too.
function RPF.BindSpellButton(b, region, spell, host)
	b.region, b.spell, b.host = region, spell, host
	RPF.SyncSpellButtons()
end

local function place(b)
	local region = b.region
	local scale = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, top = region:GetLeft(), region:GetTop()
	if not (left and top) then return false end
	if b.host then b:SetFrameStrata(b.host:GetFrameStrata()) end
	b:SetFrameLevel(region:GetFrameLevel() + 3)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * scale, top * scale)
	b:SetSize(region:GetWidth() * scale, region:GetHeight() * scale)
	return true
end

function RPF.SyncSpellButtons()
	if combat or InCombatLockdown() then return end
	for _, b in ipairs(buttons) do
		if b.region and b.spell and b.region:IsVisible() and place(b) then
			b:SetAttribute("spell", b.spell)
			b:Show()
		else
			b:Hide()
		end
	end
end

RPF.On("COMBAT", function (entering)
	if entering then
		-- PLAYER_REGEN_DISABLED is the last moment before the lockdown.
		combat = true
		for _, b in ipairs(buttons) do b:Hide() end
		RPF.Fire("SECURE_STATE", false)
	else
		combat = false
		RPF.SyncSpellButtons()
		RPF.Fire("SECURE_STATE", true)
	end
end)

-- A window rises above others when clicked (SetToplevel); its buttons have to rise with it.
function RPF.FollowRaises(window)
	window:HookScript("OnMouseDown", function () RPF.Debounce("secure", 0.05, RPF.SyncSpellButtons) end)
end

function RPF.InCombat()
	return combat or InCombatLockdown()
end
