-- Pages of other addons in our own window, as DragonUI's professions window takes them (its
-- host's AddPage): ArchaeologyUI's research view, for one. A page keeps the window, its header
-- (the page's title and icon, its skill on the bar) and the side tabs, and has a list column and
-- a card where ours are. Its tab is the profession's own (Tabs.lua). In DragonUI's window
-- (Host.lua) the page goes to DragonUI instead, and with /prof classic to the addon's own window.
--
-- It opens over the open profession, which stays open behind it (its tab goes back to the
-- recipes), or with no profession at all (/arch with the window closed), as DragonUI's does.
--
-- RetailProfessions.Pages:
--   Add(key, spec), spec = {
--       title, icon: a value or a function,
--       skill(): optional, name, rank, maxRank for the skill bar (no rank: no bar),
--       art: optional, DragonUI's art key for the bar's fill and the card's drawing,
--       build(panel): fills panel.list (the column) and panel.card; panel.art is true with
--           DragonUI's professions art, panel.Header(parent, text) makes one of the list's
--           category headings (h.label, h.note); called once, the first time the page opens,
--       onShow(), onHide(): optional }
--   Enabled(): whether our window is the one in use; Has(key): Enabled and added
--   Open(key): shows the window on the page; Toggle(key): on it already, closes the window
--   Close(): back to the profession (or, none open, the window closes)
--   Current(), Shown(key), Refresh(): the header again (the skill moved)

local RPF = RetailProfessions
local frame = RPF.frame

-- RetailProfessions.Pages for the other addons.
local Pages = { VERSION = 1 }
RPF.Pages = Pages

local specs, panels = {}, {}
local current

local function call(fn, ...)
	if not fn then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		geterrorhandler()(a)
		return nil
	end
	return a, b, c
end

local function value(v)
	if type(v) == "function" then return (call(v)) end
	return v
end

function Pages.Add(key, spec)
	specs[key] = spec
end

-- Our window, not DragonUI's (Host.lua) or the classic one.
function Pages.Enabled()
	return not (RPF.hosting or RPF.hostClassic or RetailProfessionsDB and RetailProfessionsDB.classic)
end

function Pages.Has(key)
	return key ~= nil and specs[key] ~= nil and Pages.Enabled()
end

function Pages.Current()
	return current
end

function Pages.Shown(key)
	return current ~= nil and current == key and frame:IsShown()
end

-- What the header shows for the page on show (Frame.lua), or nil.
function Pages.Header()
	local spec = current and specs[current]
	if not spec then return nil end
	local skill, rank, maxRank = call(spec.skill)
	return { title = value(spec.title) or current, icon = value(spec.icon), skill = skill, rank = rank,
		maxRank = maxRank, art = spec.art }
end

function Pages.Refresh()
	if current and frame:IsShown() then RPF.Fire("PAGE", current) end
end

local function panelFor(key)
	local panel = panels[key]
	if panel then return panel end
	panel = RPF.NewPagePanel()
	panel.Header = RPF.CreateListHeader
	panels[key] = panel
	call(specs[key].build, panel)
	return panel
end

-- The page `key` (nil: none) and the panes under it: ours only when neither a page nor Training
-- or Profit (Home.lua) has the window.
local function show(key)
	local was = current
	current = key
	for k, panel in pairs(panels) do
		if k ~= key and panel:IsShown() then
			panel:Hide()
			call(specs[k].onHide)
		end
	end
	if key then
		for _, pane in ipairs(RPF.panes) do pane:Hide() end
		local spec = specs[key]
		local panel = panelFor(key)
		if panel.card.SetCardArt then panel.card:SetCardArt(spec.art, value(spec.icon)) end
		if not panel:IsShown() then
			panel:Show()
			call(spec.onShow)
		end
	elseif not RPF.Home.Active() then
		for _, pane in ipairs(RPF.panes) do pane:Show() end
	end
	if was ~= key then RPF.Fire("PAGE", key) end
end

function Pages.Open(key)
	if not Pages.Has(key) then return false end
	if Pages.Shown(key) then return true end
	-- Training or Profit make way.
	RPF.Home.SetActive(false)
	if not frame:IsShown() then
		RPF.selected = nil
		frame:Show()
	end
	show(key)
	return true
end

function Pages.Toggle(key)
	if not Pages.Has(key) then return false end
	if Pages.Shown(key) then
		-- Its secure buttons can't be put away in combat: the window stays till it ends.
		if not RPF.InCombat() then frame:Hide() end
		return true
	end
	return Pages.Open(key)
end

function Pages.Close()
	if not current then return end
	if RPF.IsOpen() then show(nil) else frame:Hide() end
end

-- A profession opening, or Training or Profit, takes the window from the page.
RPF.On("SHOW", function () if current then show(nil) end end)
RPF.On("VIEW", function () if current and RPF.Home.Active() then show(nil) end end)
-- The trade skill closing behind the page: its tab isn't the open one any more.
RPF.On("CLOSE", function () if current then RPF.Fire("PAGE", current) end end)
RPF.On("HIDDEN", function () if current then show(nil) end end)
