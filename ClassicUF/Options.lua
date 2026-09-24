--[[ Options panel.

	Controls are built by hand (checkbox, stepper, cycler) rather than from
	Blizzard's option templates, which move around between UI versions.

	Four tabs, two columns each.  Sections kept growing until they ran off the
	bottom of the settings canvas, so each subject now gets its own page, and
	each page still scrolls if it outgrows the canvas.
]]

local CUF = ClassicUF
local Options = {}
CUF.Options = Options

local controls = {}

local COLUMN_WIDTH = 300
local COLUMNS = { 20, 350 }
local ROW = 24          -- checkbox row pitch
local WIDE_ROW = 28     -- cycler / stepper row pitch
local SECTION = 36      -- gap before a new header

local function apply()
	CUF:RunProtected(function() CUF:ApplyAll() end)
end

-- ---------------------------------------------------------------------------
-- control factories
-- ---------------------------------------------------------------------------

local function checkbox(parent, x, y, label, get, set, tooltip)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	check:SetSize(22, 22)

	local text = check.Text or _G[(check:GetName() or "") .. "Text"]
	if not text then
		text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("LEFT", check, "RIGHT", 2, 0)
	end
	text:SetFontObject("GameFontHighlightSmall")
	text:SetText(label)
	text:SetWidth(COLUMN_WIDTH - 26)
	text:SetJustifyH("LEFT")

	check:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		apply()
	end)
	if tooltip then
		check:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(label, 1, 0.82, 0, 1)
			GameTooltip:AddLine(tooltip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		check:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	check.Refresh = function(self) self:SetChecked(get() and true or false) end
	controls[#controls + 1] = check
	return check
end

-- label  [-] value [+]  laid out from the right edge of `width`, so a narrow
-- stepper keeps its buttons inside its own column.
local function stepper(parent, x, y, label, get, set, step, minimum, maximum, format, width)
	width = width or COLUMN_WIDTH
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	holder:SetSize(width, 20)

	local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT", holder, "LEFT", 2, 0)
	text:SetJustifyH("LEFT")
	text:SetWidth(math.max(width - 96, 1))

	local plus = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
	plus:SetSize(20, 18)
	plus:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
	plus:SetText("+")

	local value = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	value:SetPoint("RIGHT", plus, "LEFT", -3, 0)
	value:SetWidth(42)
	value:SetJustifyH("CENTER")

	local minus = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
	minus:SetSize(20, 18)
	minus:SetPoint("RIGHT", value, "LEFT", -3, 0)
	minus:SetText("-")

	local function refresh()
		text:SetText(label)
		value:SetText(CUF.SafeFormat(format or "%.2f", get()))
	end

	local function nudge(direction)
		local current = get() + direction * step
		current = math.max(minimum, math.min(maximum, current))
		set(math.floor(current * 100 + 0.5) / 100)   -- tidy 1.05000000001
		refresh()
		apply()
	end

	minus:SetScript("OnClick", function() nudge(-1) end)
	plus:SetScript("OnClick", function() nudge(1) end)

	holder.Refresh = refresh
	controls[#controls + 1] = holder
	return holder
end

local function cycler(parent, x, y, label, values, get, set, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	button:SetSize(width or COLUMN_WIDTH, 22)

	local function currentLabel()
		local value = get()
		for _, entry in ipairs(values) do
			if entry[1] == value then return entry[2] end
		end
		return tostring(value)
	end

	button.Refresh = function(self) self:SetText(label .. ": " .. currentLabel()) end

	button:SetScript("OnClick", function(self)
		local value = get()
		local index = 1
		for i, entry in ipairs(values) do
			if entry[1] == value then index = i break end
		end
		local nextEntry = values[index + 1] or values[1]
		set(nextEntry[1])
		self:Refresh()
		apply()
	end)

	controls[#controls + 1] = button
	return button
end

local function header(parent, x, y, label)
	local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	text:SetText(label)
	return text
end

-- ---------------------------------------------------------------------------
-- value lists
-- ---------------------------------------------------------------------------

local HEALTH_TEXT = {
	{ "none", "Hidden" },
	{ "current", "Current" },
	{ "currentmax", "Current / Max" },
	{ "percent", "Percent" },
}

local BAR_TEXTURE = {
	{ "classic", "Classic" },
	{ "flat", "Flat" },
}

local LEVEL_STYLE = {
	{ "classic", "In the circle" },
	{ "centered", "Under the name" },
}

local CAST_STYLE = {
	{ "quartz", "Quartz" },
	{ "classic", "Classic art" },
}

local AURA_ANCHOR = {
	{ "below", "Below the frame" },
	{ "above", "Above the frame" },
}

local TOOLTIP_ANCHOR = {}
for _, entry in ipairs(CUF.TooltipAnchors) do
	TOOLTIP_ANCHOR[#TOOLTIP_ANCHOR + 1] = { entry[1], entry[2] }
end

local RAID_TEXTURE = {}
for _, entry in ipairs(CUF.RaidTextures) do
	RAID_TEXTURE[#RAID_TEXTURE + 1] = { entry[1], entry[2] }
end

-- ---------------------------------------------------------------------------
-- tabs
-- ---------------------------------------------------------------------------

local TAB_NAMES = { "Appearance", "Unit frames", "Party & raid", "Cast & tooltips", "Action bars" }

function Options:SelectTab(index)
	for i, page in ipairs(Options.Pages) do
		if i == index then
			Options.Scroll:SetScrollChild(page)
			Options.Scroll:SetVerticalScroll(0)
			page:Show()
		else
			page:Hide()
		end
		local tab = Options.TabButtons[i]
		tab:SetNormalFontObject(i == index and "GameFontHighlight" or "GameFontDisable")
	end
	Options.CurrentTab = index
	Options:Refresh()
end

-- ---------------------------------------------------------------------------
-- panel
-- ---------------------------------------------------------------------------

function Options:Initialize()
	local panel = CreateFrame("Frame", "ClassicUF_Options", UIParent, "BackdropTemplate")
	Options.Panel = panel
	panel.name = "Squawk CUF"
	panel:SetSize(700, 540)
	panel:Hide()

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -14)
	title:SetText("Squawk Classic Unit Frames " .. CUF.Version)

	local credit = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	credit:SetPoint("LEFT", title, "RIGHT", 10, 0)
	credit:SetText("|cffffd100Made by: Avoid Me|r |cff82c5ff<Squawk>|r")

	local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	subtitle:SetWidth(660)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetText("Health numbers are hidden by the client during combat; the bars themselves are always accurate.")

	-- tab bar
	Options.TabButtons = {}
	local tabX = 16
	for index, name in ipairs(TAB_NAMES) do
		local tab = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		tab:SetSize(128, 22)
		tab:SetPoint("TOPLEFT", panel, "TOPLEFT", tabX, -56)
		tab:SetText(name)
		tab:SetScript("OnClick", function() Options:SelectTab(index) end)
		Options.TabButtons[index] = tab
		tabX = tabX + 133
	end

	-- one scroll frame, swapping which page is its child
	local scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -84)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 46)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		local target = self:GetVerticalScroll() - delta * 40
		self:SetVerticalScroll(math.max(0, math.min(range, target)))
	end)
	Options.Scroll = scroll

	Options.Pages = {}
	local function newPage()
		local page = CreateFrame("Frame", nil, scroll)
		page:SetSize(690, 420)
		page:Hide()
		Options.Pages[#Options.Pages + 1] = page
		return page
	end

	local db = function() return CUF.db end
	local c1, c2 = COLUMNS[1], COLUMNS[2]
	local top = -12

	-- ======================= 1: appearance ==============================
	local page = newPage()
	local y = top
	header(page, c1, y, "Colours and text")
	y = y - ROW
	checkbox(page, c1, y, "Class colour health bars",
		function() return db().classColorHealth end,
		function(v) db().classColorHealth = v end)

	y = y - ROW
	checkbox(page, c1, y, "Show portraits",
		function() return db().showPortraits end,
		function(v) db().showPortraits = v end)
	y = y - ROW
	checkbox(page, c1, y, "Show level",
		function() return db().showLevel end,
		function(v) db().showLevel = v end)
	y = y - ROW
	checkbox(page, c1, y, "Hide Blizzard's frames",
		function() return db().hideBlizzard end,
		function(v)
			db().hideBlizzard = v
			if v then CUF:HideBlizzardFrames() else CUF:Print("reload to bring Blizzard's frames back") end
		end,
		"Blizzard's frames are put away out of combat. Turning this back off needs a reload.")
	y = y - WIDE_ROW
	cycler(page, c1, y, "Health text", HEALTH_TEXT,
		function() return db().healthText end,
		function(v) db().healthText = v end)
	y = y - WIDE_ROW
	cycler(page, c1, y, "Power text", HEALTH_TEXT,
		function() return db().powerText end,
		function(v) db().powerText = v end)
	y = y - WIDE_ROW
	cycler(page, c1, y, "Bar texture", BAR_TEXTURE,
		function() return db().barTexture end,
		function(v) db().barTexture = v end)

	y = top
	header(page, c2, y, "Level number")
	y = y - WIDE_ROW
	cycler(page, c2, y, "Position", LEVEL_STYLE,
		function() return db().levelStyle end,
		function(v) db().levelStyle = v end)
	y = y - WIDE_ROW
	stepper(page, c2, y, "Nudge left / right",
		function() return db().levelNudgeX end,
		function(v) db().levelNudgeX = v end, 1, -40, 40, "%d")
	y = y - ROW
	stepper(page, c2, y, "Nudge up / down",
		function() return db().levelNudgeY end,
		function(v) db().levelNudgeY = v end, 1, -40, 40, "%d")

	-- ======================= 2: unit frames =============================
	page = newPage()
	y = top
	header(page, c1, y, "Frames and scale")
	y = y - ROW
	for _, entry in ipairs({
		{ "player", "Player" }, { "target", "Target" }, { "targettarget", "Target's target" },
		{ "focus", "Focus" }, { "pet", "Pet" },
	}) do
		local key, label = entry[1], entry[2]
		local check = checkbox(page, c1, y, label,
			function() return db().units[key].enabled end,
			function(v) db().units[key].enabled = v CUF:Print("reload to apply frame changes") end)
		local text = check.Text or _G[(check:GetName() or "") .. "Text"]
		if text then text:SetWidth(120) end

		stepper(page, c1 + 150, y - 2, "scale",
			function() return db().units[key].scale end,
			function(v) db().units[key].scale = v end, 0.05, 0.5, 2.0, "%.2f", 150)
		y = y - ROW
	end

	y = y - SECTION
	header(page, c1, y, "Target debuffs")
	y = y - WIDE_ROW
	cycler(page, c1, y, "Position", AURA_ANCHOR,
		function() return db().targetAuras.debuffAnchor end,
		function(v) db().targetAuras.debuffAnchor = v end)
	y = y - WIDE_ROW
	stepper(page, c1, y, "Nudge left / right",
		function() return db().targetAuras.debuffOffsetX end,
		function(v) db().targetAuras.debuffOffsetX = v end, 1, -250, 250, "%d")
	y = y - ROW
	stepper(page, c1, y, "Distance from frame",
		function() return db().targetAuras.debuffGap end,
		function(v) db().targetAuras.debuffGap = v end, 1, 0, 250, "%d")
	y = y - ROW
	stepper(page, c1, y, "Max debuffs",
		function() return db().targetAuras.debuffs end,
		function(v) db().targetAuras.debuffs = v CUF:Print("reload to apply") end, 1, 0, 16, "%d")

	y = top
	header(page, c2, y, "Target buffs")
	y = y - ROW
	checkbox(page, c2, y, "Show buffs and debuffs",
		function() return db().targetAuras.enabled end,
		function(v) db().targetAuras.enabled = v CUF:Print("reload to apply") end)
	y = y - WIDE_ROW
	cycler(page, c2, y, "Position", AURA_ANCHOR,
		function() return db().targetAuras.buffAnchor end,
		function(v) db().targetAuras.buffAnchor = v end)
	y = y - WIDE_ROW
	stepper(page, c2, y, "Nudge left / right",
		function() return db().targetAuras.buffOffsetX end,
		function(v) db().targetAuras.buffOffsetX = v end, 1, -250, 250, "%d")
	y = y - ROW
	stepper(page, c2, y, "Distance from frame",
		function() return db().targetAuras.buffGap end,
		function(v) db().targetAuras.buffGap = v end, 1, 0, 250, "%d")
	y = y - ROW
	stepper(page, c2, y, "Max buffs",
		function() return db().targetAuras.buffs end,
		function(v) db().targetAuras.buffs = v CUF:Print("reload to apply") end, 1, 0, 16, "%d")
	y = y - SECTION

	header(page, c2, y, "Both rows")
	y = y - WIDE_ROW
	stepper(page, c2, y, "Icon size",
		function() return db().targetAuras.size end,
		function(v) db().targetAuras.size = v end, 1, 10, 40, "%d")
	y = y - ROW
	stepper(page, c2, y, "Icons per row",
		function() return db().targetAuras.perRow end,
		function(v) db().targetAuras.perRow = v end, 1, 1, 16, "%d")

	-- ======================= 3: party and raid ==========================
	page = newPage()
	y = top
	header(page, c1, y, "Party")
	y = y - ROW
	checkbox(page, c1, y, "Party frames",
		function() return db().party.enabled end,
		function(v) db().party.enabled = v CUF:Print("reload to apply frame changes") end)
	y = y - ROW
	checkbox(page, c1, y, "Show party as raid-style frames",
		function() return db().party.useRaidStyle end,
		function(v)
			db().party.useRaidStyle = v
			CUF:RunProtected(function() CUF.Group:UpdateAll() end)
		end,
		"Swaps the Classic party frames for the compact boxes the raid uses, at the raid frame size.")
	y = y - ROW
	checkbox(page, c1, y, "Include yourself in them",
		function() return db().party.includePlayer end,
		function(v)
			db().party.includePlayer = v
			CUF:RunProtected(function() CUF.Group:UpdateAll() end)
		end)
	y = y - ROW
	checkbox(page, c1, y, "Keep party frames while in a raid",
		function() return db().party.showInRaid end,
		function(v) db().party.showInRaid = v end)
	y = y - WIDE_ROW
	stepper(page, c1, y, "Party scale",
		function() return db().party.scale end,
		function(v) db().party.scale = v end, 0.05, 0.5, 2.0, "%.2f")
	y = y - ROW
	stepper(page, c1, y, "Party spacing",
		function() return db().party.spacing end,
		function(v) db().party.spacing = v end, 1, 0, 60, "%d")

	y = top
	header(page, c2, y, "Raid")
	y = y - ROW
	checkbox(page, c2, y, "Raid frames",
		function() return db().raid.enabled end,
		function(v) db().raid.enabled = v CUF:Print("reload to apply frame changes") end)
	y = y - ROW
	checkbox(page, c2, y, "Only while in a raid",
		function() return db().raid.showOnlyInRaid end,
		function(v) db().raid.showOnlyInRaid = v end)
	y = y - ROW
	checkbox(page, c2, y, "Arrange by raid group",
		function() return db().raid.groupByGroup end,
		function(v) db().raid.groupByGroup = v end)
	y = y - ROW
	checkbox(page, c2, y, "Fade members out of range",
		function() return db().raid.rangeCheck end,
		function(v) db().raid.rangeCheck = v CUF.Group:UpdateRange() end)
	y = y - ROW
	checkbox(page, c2, y, "Show missing buffs you can cast",
		function() return db().raid.showMissingBuffs end,
		function(v) db().raid.showMissingBuffs = v end,
		"A red icon in the corner when someone lacks a buff your class provides.")
	y = y - ROW
	checkbox(page, c2, y, "Show debuffs you can dispel",
		function() return db().raid.showDispellable end,
		function(v) db().raid.showDispellable = v end)
	y = y - ROW
	checkbox(page, c2, y, "Also watch optional buffs",
		function() return db().raid.watchOptionalBuffs end,
		function(v) db().raid.watchOptionalBuffs = v end,
		"Divine Spirit, Thorns and Battle Shout, which are talented or situational.")
	y = y - WIDE_ROW
	cycler(page, c2, y, "Raid bar texture", RAID_TEXTURE,
		function() return db().raid.texture end,
		function(v) db().raid.texture = v end)
	y = y - WIDE_ROW
	stepper(page, c2, y, "Raid scale",
		function() return db().raid.scale end,
		function(v) db().raid.scale = v end, 0.05, 0.5, 2.0, "%.2f")
	y = y - ROW
	stepper(page, c2, y, "Frame width",
		function() return db().raid.width end,
		function(v) db().raid.width = v end, 2, 40, 200, "%d")
	y = y - ROW
	stepper(page, c2, y, "Frame height",
		function() return db().raid.height end,
		function(v) db().raid.height = v end, 2, 16, 100, "%d")
	y = y - ROW
	stepper(page, c2, y, "Spacing",
		function() return db().raid.spacing end,
		function(v) db().raid.spacing = v end, 1, 0, 30, "%d")
	y = y - ROW
	stepper(page, c2, y, "Rows per column",
		function() return db().raid.perColumn end,
		function(v) db().raid.perColumn = v end, 1, 1, 40, "%d")

	-- ======================= 4: cast bars and tooltips ==================
	page = newPage()
	y = top
	header(page, c1, y, "Cast bars")
	y = y - WIDE_ROW
	cycler(page, c1, y, "Style", CAST_STYLE,
		function() return db().castbar.style end,
		function(v) db().castbar.style = v end,
		nil)
	y = y - ROW
	checkbox(page, c1, y, "Cast bar",
		function() return db().castbar.enabled end,
		function(v) db().castbar.enabled = v end)
	y = y - ROW
	checkbox(page, c1, y, "Target cast bar",
		function() return db().castbar.showTarget end,
		function(v) db().castbar.showTarget = v end)
	y = y - ROW
	checkbox(page, c1, y, "Cast bar icon",
		function() return db().castbar.showIcon end,
		function(v) db().castbar.showIcon = v end)
	y = y - ROW
	checkbox(page, c1, y, "Cast bar timer",
		function() return db().castbar.showTime end,
		function(v) db().castbar.showTime = v end)
	y = y - ROW
	checkbox(page, c1, y, "Show total cast time",
		function() return db().castbar.showTotal end,
		function(v) db().castbar.showTotal = v end,
		"Writes the timer as \"1.2 / 2.5\" rather than just the time left.")
	y = y - ROW
	checkbox(page, c1, y, "Latency zone",
		function() return db().castbar.showLatency end,
		function(v) db().castbar.showLatency = v end,
		"Shades the end of your cast bar by your current latency, the way Quartz does, so you can see when it is safe to move.")
	y = y - ROW
	checkbox(page, c1, y, "Attach target bar to target frame",
		function() return db().castbar.targetAttached end,
		function(v) db().castbar.targetAttached = v end,
		"Hangs the target's cast bar under the target frame, below the buff and debuff rows.")
	y = y - WIDE_ROW
	stepper(page, c1, y, "Cast bar width",
		function() return db().castbar.width end,
		function(v) db().castbar.width = v end, 5, 100, 400, "%d")
	y = y - ROW
	stepper(page, c1, y, "Target bar width",
		function() return db().castbar.targetWidth end,
		function(v) db().castbar.targetWidth = v end, 5, 60, 400, "%d")
	y = y - ROW
	stepper(page, c1, y, "Target bar height",
		function() return db().castbar.targetHeight end,
		function(v) db().castbar.targetHeight = v end, 1, 6, 40, "%d")
	y = y - WIDE_ROW
	cycler(page, c1, y, "Target bar position", AURA_ANCHOR,
		function() return db().castbar.targetAnchor end,
		function(v) db().castbar.targetAnchor = v end)
	y = y - WIDE_ROW
	stepper(page, c1, y, "Target bar nudge left / right",
		function() return db().castbar.targetOffsetX end,
		function(v) db().castbar.targetOffsetX = v end, 2, -250, 250, "%d")
	y = y - ROW
	stepper(page, c1, y, "Target bar distance",
		function() return db().castbar.targetGap end,
		function(v) db().castbar.targetGap = v end, 2, 0, 250, "%d")

	y = top
	header(page, c2, y, "Tooltips")
	y = y - ROW
	checkbox(page, c2, y, "Unit tooltips on hover",
		function() return db().tooltips end,
		function(v) db().tooltips = v end,
		"Hovering the player, target, pet, party or raid frames shows that unit's tooltip.")
	y = y - ROW
	checkbox(page, c2, y, "Add guild to tooltips",
		function() return db().tooltipGuild end,
		function(v) db().tooltipGuild = v end)
	y = y - ROW
	checkbox(page, c2, y, "Hide tooltips in combat",
		function() return db().hideTooltipsInCombat end,
		function(v) db().hideTooltipsInCombat = v end)
	y = y - WIDE_ROW
	cycler(page, c2, y, "Tooltip position", TOOLTIP_ANCHOR,
		function() return db().tooltipAnchor end,
		function(v) db().tooltipAnchor = v end)

	-- ======================= 5: action bars =============================
	page = newPage()
	y = top
	header(page, c1, y, "Classic button skin")
	y = y - ROW
	checkbox(page, c1, y, "Skin Blizzard's action buttons",
		function() return db().actionBars.enabled end,
		function(v) db().actionBars.enabled = v end,
		"Restyles Blizzard's own buttons with the Classic border and fonts. The buttons stay Blizzard's, so paging, keybinds and macros are untouched.")
	y = y - ROW
	checkbox(page, c1, y, "Show keybind text",
		function() return db().actionBars.showHotkeys end,
		function(v) db().actionBars.showHotkeys = v end)
	y = y - ROW
	checkbox(page, c1, y, "Show macro names",
		function() return db().actionBars.showMacroNames end,
		function(v) db().actionBars.showMacroNames = v end)

	local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", page, "TOPLEFT", c2, top - 24)
	note:SetWidth(COLUMN_WIDTH)
	note:SetJustifyH("LEFT")
	note:SetText("The gryphon end caps on this client are already the Classic ones, so they are left alone.|n|n"
		.. "Bars cannot be replaced outright here: secure snippets do not compile, and that is what drives bar "
		.. "paging and click-casting. Skinning Blizzard's own buttons keeps all of that working.|n|n"
		.. "|cffffd100/cuf bars|r re-applies the skin and reports what it found.")

	-- ---------------- footer ------------------------------------------------
	local unlock = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	unlock:SetSize(150, 22)
	unlock:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 20, 14)
	unlock:SetText("Unlock frames")
	unlock:SetScript("OnClick", function(self)
		CUF.db.locked = not CUF.db.locked
		CUF:SetLocked(CUF.db.locked)
		self:SetText(CUF.db.locked and "Unlock frames" or "Lock frames")
	end)

	local artCheck = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	artCheck:SetSize(150, 22)
	artCheck:SetPoint("LEFT", unlock, "RIGHT", 10, 0)
	artCheck:SetText("Check Classic art")
	artCheck:SetScript("OnClick", function() CUF:ShowArtCheck() end)

	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(150, 22)
	reset:SetPoint("LEFT", artCheck, "RIGHT", 10, 0)
	reset:SetText("Reset to defaults")
	reset:SetScript("OnClick", function() SlashCmdList["CLASSICUF"]("reset") Options:Refresh() end)

	panel:SetScript("OnShow", function() Options:Refresh() end)
	Options:SelectTab(1)

	-- register with whatever settings system exists, else stand alone
	if type(Settings) == "table" and Settings.RegisterCanvasLayoutCategory then
		local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Squawk CUF")
		if ok and category then
			Options.Category = category
			pcall(Settings.RegisterAddOnCategory, category)
			return
		end
	end
	if type(InterfaceOptions_AddCategory) == "function" then
		pcall(InterfaceOptions_AddCategory, panel)
		return
	end

	Options.Standalone = true
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0, 0, 0, 0.92)
	panel:SetScript("OnMouseDown", function(self) self:StartMoving() end)
	panel:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

	local close = CreateFrame("Button", nil, panel)
	close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
	close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
	close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function() panel:Hide() end)
end

function Options:Refresh()
	for _, control in ipairs(controls) do
		if control.Refresh then control:Refresh() end
	end
end

function Options:Open()
	if not Options.Panel then
		CUF:Print("the options panel did not start on this client; use the slash commands instead.")
		return
	end
	if Options.Category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(Options.Category:GetID())
	elseif Options.Standalone then
		Options.Panel:Show()
		Options:Refresh()
	elseif type(InterfaceOptionsFrame_OpenToCategory) == "function" then
		InterfaceOptionsFrame_OpenToCategory(Options.Panel)
		InterfaceOptionsFrame_OpenToCategory(Options.Panel)
	else
		Options.Panel:Show()
	end
end
