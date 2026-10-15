-- Trainer window: keep the recipe you picked. Every skill-up (and every collapse, filter or
-- purchase) fires TRAINER_UPDATE, where the client has already moved its selection to the first
-- learnable service and the stock handler scrolls up to it. We remember the pick by name and rank
-- and put it back afterwards, unless it's gone from the list or was just trained ("used").

local picked  -- { name, subText, kind } of the last service selected in the window

local function findService(want)
	for i = 1, GetNumTrainerServices() do
		local name, subText, kind = GetTrainerServiceInfo(i)
		if name == want.name and (subText or "") == want.subText then
			if kind == "header" or (kind == "used" and want.kind ~= "used") then return nil end
			return i
		end
	end
end

local function hook()
	hooksecurefunc("ClassTrainer_SetSelection", function (id)
		if not id then return end
		local name, subText, kind = GetTrainerServiceInfo(id)
		if name and kind ~= "header" then picked = { name = name, subText = subText or "", kind = kind } end
	end)

	local stock = ClassTrainerFrame:GetScript("OnEvent")
	ClassTrainerFrame:SetScript("OnEvent", function (self, event, ...)
		local want = picked
		local scroll = ClassTrainerListScrollFrameScrollBar:GetValue()
		stock(self, event, ...)
		if event ~= "TRAINER_UPDATE" or not want or not self:IsShown() then return end

		local index = findService(want)
		if not index or index == GetTrainerSelectionIndex() then return end
		ClassTrainerFrame.showSkillDetails = 1
		ClassTrainer_SetSelection(index)
		ClassTrainerFrame_Update()
		-- Stay where the list was, unless that no longer shows the pick.
		local top = math.floor(scroll / CLASS_TRAINER_SKILL_HEIGHT) + 1
		if index < top or index >= top + CLASS_TRAINER_SKILLS_DISPLAYED then
			scroll = (index - 1) * CLASS_TRAINER_SKILL_HEIGHT
		end
		ClassTrainerListScrollFrameScrollBar:SetValue(scroll)
	end)

	-- A new trainer starts fresh.
	ClassTrainerFrame:HookScript("OnHide", function () picked = nil end)
end

if IsAddOnLoaded("Blizzard_TrainerUI") then
	hook()
else
	local waiter = CreateFrame("Frame")
	waiter:RegisterEvent("ADDON_LOADED")
	waiter:SetScript("OnEvent", function (self, event, name)
		if name == "Blizzard_TrainerUI" then
			self:UnregisterEvent("ADDON_LOADED")
			hook()
		end
	end)
end
