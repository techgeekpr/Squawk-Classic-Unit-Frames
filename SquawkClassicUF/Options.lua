--[[ Options panel.

	Laid out as one page per subject: a header with
	the title and the quick buttons, gold section titles over a faint rule,
	and one option per striped row -- its name and a line of explanation on
	the left, its control on the right.  Categories run down a sidebar
	rather than across tabs, so none can fall off the edge.

	Nothing here has a fixed width.  Every row is measured after its text is
	wrapped to the space it really has, rows that do not apply are left out
	(the Quartz settings while the Classic cast bar is picked, and so on), and
	the page is exactly as tall as what is on it, so the last row can always
	be scrolled to.  Controls are built by hand rather than from Blizzard's
	option templates, which move around between UI versions.
]]

local CUF = SquawkClassicUF
local Options = {}
CUF.Options = Options

local SIDEBAR_WIDTH = 152
local HEADER_HEIGHT = 74
local FOOTER_HEIGHT = 40
local BANNER_HEIGHT = 32
local ROW_PAD = 8          -- inner padding of a row, top and bottom
local ROW_GAP = 2
local SECTION_GAP = 14
local SCROLLBAR_WIDTH = 16

local GOLD = { 1, 0.82, 0 }

local function db() return CUF.db end

local function apply()
	CUF:RunProtected(function() CUF:ApplyAll() end)
end

-- ---------------------------------------------------------------------------
-- value lists
-- ---------------------------------------------------------------------------

local HEALTH_TEXT = {
	{ "none", "Hidden" },
	{ "current", "Current" },
	{ "currentmax", "Current / max" },
	{ "percent", "Percent" },
}
local BAR_TEXTURE = { { "classic", "Classic" }, { "flat", "Flat" } }
local LEVEL_STYLE = { { "classic", "In the circle" }, { "centered", "Under the name" } }
local CAST_STYLE = { { "quartz", "Quartz" }, { "classic", "Classic" } }
local SIDE = { { "below", "Below the frame" }, { "above", "Above the frame" } }
local PET_STYLE = { { "classic", "Under the portrait" }, { "bar", "Bar beside the frame" } }
local PLACEMENT = { { "blizzard", "Blizzard's spot" }, { "custom", "Custom" } }

local TOOLTIP_ANCHOR = {}
for _, entry in ipairs(CUF.TooltipAnchors) do
	TOOLTIP_ANCHOR[#TOOLTIP_ANCHOR + 1] = { entry[1], entry[2] }
end
local RAID_TEXTURE = {}
for _, entry in ipairs(CUF.RaidTextures) do
	RAID_TEXTURE[#RAID_TEXTURE + 1] = { entry[1], entry[2] }
end

-- ---------------------------------------------------------------------------
-- small widgets
-- ---------------------------------------------------------------------------

local BUTTON_ART = "Interface\\Buttons\\UI-Panel-Button-"

-- A classic red panel button drawn from the three state textures, so it looks
-- the same whatever template this client's UIPanelButtonTemplate is.
local function button(parent, text, width, height, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, height or 22)
	for _, state in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
		local file = BUTTON_ART .. (state == "Normal" and "Up" or state == "Pushed" and "Down"
			or state == "Disabled" and "Disabled" or "Highlight")
		local texture = b:CreateTexture(nil, state == "Highlight" and "HIGHLIGHT" or "BACKGROUND")
		texture:SetTexture(file)
		texture:SetTexCoord(0, 0.625, 0, 0.6875)
		texture:SetAllPoints(b)
		if state == "Highlight" then texture:SetBlendMode("ADD") end
		b["Set" .. state .. "Texture"](b, texture)
	end
	local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", b, "LEFT", 6, 1)
	label:SetPoint("RIGHT", b, "RIGHT", -6, 1)
	label:SetJustifyH("CENTER")
	pcall(label.SetWordWrap, label, false)
	label:SetText(text)
	b.Label = label
	function b:SetLabel(value) label:SetText(value) end
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

local CARD_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Off | On, a two-sided switch: the chosen side lit.
local function switch(parent, onChange)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(104, 22)
	local sides = {}
	for index, value in ipairs({ false, true }) do
		local side = CreateFrame("Button", nil, holder)
		side:SetSize(52, 22)
		side:SetPoint("LEFT", holder, "LEFT", (index - 1) * 52, 0)
		side.Art = side:CreateTexture(nil, "BACKGROUND")
		side.Art:SetAllPoints(side)
		side.Art:SetTexCoord(0, 0.625, 0, 0.6875)
		local glow = side:CreateTexture(nil, "HIGHLIGHT")
		glow:SetTexture(BUTTON_ART .. "Highlight")
		glow:SetTexCoord(0, 0.625, 0, 0.6875)
		glow:SetAllPoints(side)
		glow:SetBlendMode("ADD")
		side.Text = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		side.Text:SetPoint("CENTER", side, "CENTER", 0, 1)
		side.Text:SetText(value and "On" or "Off")
		side:SetScript("OnClick", function() onChange(value) end)
		sides[index] = side
	end
	function holder:SetValue(on)
		for index, side in ipairs(sides) do
			local active = (index == 2) == (on and true or false)
			side.Art:SetTexture(BUTTON_ART .. (active and "Up" or "Disabled"))
			side.Text:SetFontObject(active and "GameFontHighlightSmall" or "GameFontDisableSmall")
		end
	end
	return holder
end

-- [-] value [+]
local function stepper(parent, get, set, step, minimum, maximum, format)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(104, 22)

	local value = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	value:SetPoint("CENTER", holder, "CENTER", 0, 0)
	value:SetWidth(52)
	value:SetJustifyH("CENTER")

	local function refresh() value:SetText(CUF.SafeFormat(format or "%.2f", get())) end
	local function nudge(direction)
		local current = get() + direction * step
		current = math.max(minimum, math.min(maximum, current))
		set(math.floor(current * 100 + 0.5) / 100)   -- tidy 1.05000000001
		refresh()
	end

	local minus = button(holder, "-", 24, 22, function() nudge(-1) end)
	minus:SetPoint("LEFT", holder, "LEFT", 0, 0)
	local plus = button(holder, "+", 24, 22, function() nudge(1) end)
	plus:SetPoint("RIGHT", holder, "RIGHT", 0, 0)

	holder:EnableMouseWheel(true)
	holder:SetScript("OnMouseWheel", function(_, delta) nudge(delta > 0 and 1 or -1) end)
	holder.Refresh = refresh
	return holder
end

-- One list serves every dropdown; it closes when anything else is clicked.
local dropList, dropBlocker

local function closeDropdown()
	if dropList then dropList:Hide() end
	if dropBlocker then dropBlocker:Hide() end
end

local function openDropdown(owner, values, current, onPick)
	if not dropList then
		dropBlocker = CreateFrame("Button", nil, UIParent)
		dropBlocker:SetAllPoints(UIParent)
		dropBlocker:SetFrameStrata("FULLSCREEN_DIALOG")
		dropBlocker:SetScript("OnClick", closeDropdown)
		dropBlocker:Hide()

		dropList = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		dropList:SetFrameStrata("FULLSCREEN_DIALOG")
		dropList:SetFrameLevel(dropBlocker:GetFrameLevel() + 10)
		dropList:SetBackdrop(CARD_BACKDROP)
		dropList:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
		dropList:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.8)
		dropList:SetClampedToScreen(true)
		dropList.items = {}
		dropList:Hide()
	end

	local width = math.max(owner:GetWidth(), 120)
	for index, entry in ipairs(values) do
		local item = dropList.items[index]
		if not item then
			item = CreateFrame("Button", nil, dropList)
			item:SetHeight(20)
			local glow = item:CreateTexture(nil, "HIGHLIGHT")
			glow:SetAllPoints(item)
			glow:SetColorTexture(1, 0.82, 0, 0.18)
			item.Check = item:CreateTexture(nil, "OVERLAY")
			item.Check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			item.Check:SetSize(16, 16)
			item.Check:SetPoint("LEFT", item, "LEFT", 4, 0)
			item.Text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			item.Text:SetPoint("LEFT", item, "LEFT", 22, 0)
			item.Text:SetPoint("RIGHT", item, "RIGHT", -6, 0)
			item.Text:SetJustifyH("LEFT")
			dropList.items[index] = item
		end
		item:ClearAllPoints()
		item:SetPoint("TOPLEFT", dropList, "TOPLEFT", 4, -4 - (index - 1) * 20)
		item:SetPoint("RIGHT", dropList, "RIGHT", -4, 0)
		item.Text:SetText(entry[2])
		item.Check:SetShown(entry[1] == current)
		item:SetScript("OnClick", function()
			closeDropdown()
			onPick(entry[1])
		end)
		item:Show()
	end
	for index = #values + 1, #dropList.items do dropList.items[index]:Hide() end

	dropList:SetSize(width, #values * 20 + 8)
	dropList:ClearAllPoints()
	dropList:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	dropBlocker:Show()
	dropList:Show()
end

local function dropdown(parent, values, get, onPick)
	local box = CreateFrame("Button", nil, parent, "BackdropTemplate")
	box:SetSize(180, 22)
	box:SetBackdrop(CARD_BACKDROP)
	box:SetBackdropColor(0, 0, 0, 0.75)
	box:SetBackdropBorderColor(0.55, 0.55, 0.55)

	box.Text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	box.Text:SetPoint("LEFT", box, "LEFT", 8, 0)
	box.Text:SetPoint("RIGHT", box, "RIGHT", -22, 0)
	box.Text:SetJustifyH("LEFT")
	pcall(box.Text.SetWordWrap, box.Text, false)

	local arrow = box:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetSize(12, 12)
	arrow:SetPoint("RIGHT", box, "RIGHT", -7, 0)
	arrow:SetRotation(-math.pi / 2)

	box:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3]) end)
	box:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.55, 0.55, 0.55) end)
	box:SetScript("OnClick", function(self)
		if dropList and dropList:IsShown() then closeDropdown() return end
		openDropdown(self, values, get(), onPick)
	end)

	function box:Refresh()
		local value = get()
		local text = tostring(value)
		for _, entry in ipairs(values) do
			if entry[1] == value then text = entry[2] break end
		end
		self.Text:SetText(text)
	end
	return box
end

-- ---------------------------------------------------------------------------
-- the pages, as data
-- ---------------------------------------------------------------------------

-- Row fields:
--   kind     toggle | dropdown | stepper | unit | button | note
--   label    the option's name
--   text     one line saying what it does (wrapped to fit)
--   get/set  read and write the setting
--   reload   true when the change needs a reload to show
--   shown    function; the row is left out while it answers false
--   after    extra work after the setting changes

local function unitRow(key, label)
	return {
		kind = "unit", label = label,
		get = function() return db().units[key].enabled end,
		set = function(v) db().units[key].enabled = v end,
		scaleGet = function() return db().units[key].scale end,
		scaleSet = function(v) db().units[key].scale = v end,
		reload = true,
	}
end

local function quartz() return db().castbar.style ~= "classic" end
local function classicCast() return db().castbar.style == "classic" end

local PAGES = {
	{
		name = "General",
		sections = {
			{
				title = "Look",
				text = "The finishing touches of the vanilla frames.",
				rows = {
					{ kind = "toggle", label = "Round portraits",
						text = "Vanilla's circular portraits on every frame.",
						get = function() return db().roundPortraits end,
						set = function(v) db().roundPortraits = v end },
					{ kind = "toggle", label = "Show portraits",
						get = function() return db().showPortraits end,
						set = function(v) db().showPortraits = v end },
					{ kind = "dropdown", label = "Bar texture", values = BAR_TEXTURE,
						text = "Classic is vanilla's UI-StatusBar; Flat is a plain fill.",
						get = function() return db().barTexture end,
						set = function(v) db().barTexture = v end },
					{ kind = "toggle", label = "Class-coloured health",
						text = "Players' health bars in their class colour instead of vanilla's green.",
						get = function() return db().classColorHealth end,
						set = function(v) db().classColorHealth = v end },
					{ kind = "toggle", label = "Colour NPC health by reaction",
						text = "Red for hostile, yellow for neutral. Vanilla kept every bar green and showed the reaction behind the name.",
						get = function() return db().reactionHealth end,
						set = function(v) db().reactionHealth = v end },
					{ kind = "dropdown", label = "Health text", values = HEALTH_TEXT,
						text = "The client hides these numbers in combat; the bars stay accurate.",
						get = function() return db().healthText end,
						set = function(v) db().healthText = v end },
					{ kind = "dropdown", label = "Power text", values = HEALTH_TEXT,
						get = function() return db().powerText end,
						set = function(v) db().powerText = v end },
				},
			},
			{
				title = "Indicators",
				rows = {
					{ kind = "toggle", label = "Resting icon",
						text = "The Zzz beside your portrait while resting.",
						get = function() return db().showRestIcon end,
						set = function(v) db().showRestIcon = v end },
					{ kind = "toggle", label = "Combat icon",
						text = "Crossed swords beside your portrait, and in the corner of a target or focus in combat.",
						get = function() return db().combatIcon end,
						set = function(v) db().combatIcon = v end },
					{ kind = "toggle", label = "Rest and combat glow",
						text = "Your frame glows yellow while resting and red in combat.",
						get = function() return db().statusGlow end,
						set = function(v) db().statusGlow = v end },
					{ kind = "toggle", label = "Threat glow",
						text = "The red glow around your frame, a target's or a party member's while you are on its threat list.",
						get = function() return db().threatGlow end,
						set = function(v) db().threatGlow = v end },
					{ kind = "toggle", label = "Group leader crown",
						get = function() return db().showLeader end,
						set = function(v) db().showLeader = v end },
					{ kind = "toggle", label = "Raid group number",
						text = "\"Group 3\" over your frame while you are in a raid.",
						get = function() return db().showGroupNumber end,
						set = function(v) db().showGroupNumber = v end },
					{ kind = "toggle", label = "Raid target marks",
						text = "The star, circle, diamond and so on, on every frame.",
						get = function() return db().showRaidIcons end,
						set = function(v) db().showRaidIcons = v end },
					{ kind = "stepper", label = "Mark size", step = 0.1, min = 0.5, max = 2, format = "%.1f",
						shown = function() return db().showRaidIcons end,
						get = function() return db().raidIconScale end,
						set = function(v) db().raidIconScale = v end },
					{ kind = "toggle", label = "Pet happiness",
						text = "The hunter pet's mood beside the pet frame. Hover it for the damage and loyalty.",
						get = function() return db().petHappiness end,
						set = function(v) db().petHappiness = v end },
					{ kind = "stepper", label = "Pet happiness size", step = 2, min = 16, max = 64, format = "%d",
						shown = function() return db().petHappiness end,
						get = function() return db().petHappinessSize end,
						set = function(v) db().petHappinessSize = v end },
				},
			},
			{
				title = "Blizzard's frames",
				rows = {
					{ kind = "toggle", label = "Hide Blizzard's unit frames",
						text = "Put away out of combat. Turning this off needs a reload.",
						get = function() return db().hideBlizzard end,
						set = function(v) db().hideBlizzard = v end,
						after = function(v) if v then CUF:HideBlizzardFrames() else Options:NeedReload() end end },
				},
			},
		},
	},
	{
		name = "Player & target",
		sections = {
			{
				title = "Frames",
				text = "Switch a frame on or off, and set its size.",
				rows = {
					unitRow("player", "Player"),
					unitRow("target", "Target"),
					unitRow("targettarget", "Target of target"),
					unitRow("focus", "Focus"),
					unitRow("pet", "Pet"),
					{ kind = "toggle", label = "Target of target on the target frame",
						text = "Hung off the target frame's lower right, as Blizzard places it. Dragging it while unlocked frees it.",
						shown = function() return db().units.targettarget.enabled end,
						get = function() return db().units.targettarget.attached end,
						set = function(v) db().units.targettarget.attached = v end },
					{ kind = "toggle", label = "Pet under the player frame",
						text = "Where Blizzard's own pet frame sits. Dragging it while unlocked frees it.",
						shown = function() return db().units.pet.enabled end,
						get = function() return db().units.pet.attached end,
						set = function(v) db().units.pet.attached = v end },
				},
			},
			{
				title = "Target details",
				rows = {
					{ kind = "toggle", label = "Name background",
						text = "Vanilla's plate behind a target's name, coloured by how it feels about you.",
						get = function() return db().nameBackground end,
						set = function(v) db().nameBackground = v end },
					{ kind = "toggle", label = "Level in difficulty colour",
						text = "A target's level coloured grey to red by difficulty, and a skull when it is too high to read.",
						get = function() return db().levelColors end,
						set = function(v) db().levelColors = v end },
					{ kind = "toggle", label = "Show level",
						get = function() return db().showLevel end,
						set = function(v) db().showLevel = v end },
					{ kind = "dropdown", label = "Level position", values = LEVEL_STYLE,
						shown = function() return db().showLevel end,
						get = function() return db().levelStyle end,
						set = function(v) db().levelStyle = v end },
					{ kind = "stepper", label = "Nudge level left / right", step = 1, min = -40, max = 40, format = "%d",
						shown = function() return db().showLevel and db().levelStyle == "classic" end,
						get = function() return db().levelNudgeX end,
						set = function(v) db().levelNudgeX = v end },
					{ kind = "stepper", label = "Nudge level up / down", step = 1, min = -40, max = 40, format = "%d",
						shown = function() return db().showLevel and db().levelStyle == "classic" end,
						get = function() return db().levelNudgeY end,
						set = function(v) db().levelNudgeY = v end },
					{ kind = "toggle", label = "Combo points on the target",
						text = "Down the right side of the target's portrait, as in vanilla.",
						get = function() return db().comboPoints end,
						set = function(v) db().comboPoints = v end, reload = true },
				},
			},
			{
				title = "Target and focus buffs and debuffs",
				text = "Blizzard's own layout: under the frame, 17px icons (21px for yours), a hostile target's debuffs first and a friendly one's buffs first.",
				rows = {
					{ kind = "toggle", label = "Show buffs and debuffs",
						get = function() return db().targetAuras.enabled end,
						set = function(v) db().targetAuras.enabled = v end, reload = true },
					{ kind = "stepper", label = "Most buffs shown", step = 1, min = 0, max = 32, format = "%d",
						text = "Blizzard shows up to 32.",
						shown = function() return db().targetAuras.enabled end,
						get = function() return db().targetAuras.buffs end,
						set = function(v) db().targetAuras.buffs = v end },
					{ kind = "stepper", label = "Most debuffs shown", step = 1, min = 0, max = 16, format = "%d",
						text = "Blizzard shows up to 16.",
						shown = function() return db().targetAuras.enabled end,
						get = function() return db().targetAuras.debuffs end,
						set = function(v) db().targetAuras.debuffs = v end },
				},
			},
		},
	},
	{
		name = "Party",
		sections = {
			{
				title = "Party",
				rows = {
					{ kind = "toggle", label = "Party frames",
						get = function() return db().party.enabled end,
						set = function(v) db().party.enabled = v end, reload = true },
					{ kind = "toggle", label = "Raid-style party",
						text = "The compact boxes the raid uses, at the raid frame size, instead of the classic party frames.",
						shown = function() return db().party.enabled end,
						get = function() return db().party.useRaidStyle end,
						set = function(v) db().party.useRaidStyle = v end },
					{ kind = "toggle", label = "Include yourself",
						text = "Your own box among the raid-style party.",
						shown = function() return db().party.enabled and db().party.useRaidStyle end,
						get = function() return db().party.includePlayer end,
						set = function(v) db().party.includePlayer = v end },
					{ kind = "toggle", label = "Keep the party in a raid",
						shown = function() return db().party.enabled end,
						get = function() return db().party.showInRaid end,
						set = function(v) db().party.showInRaid = v end },
					{ kind = "toggle", label = "Party pets",
						shown = function() return db().party.enabled end,
						get = function() return db().party.showPetFrames end,
						set = function(v) db().party.showPetFrames = v end },
					{ kind = "dropdown", label = "Party pet style", values = PET_STYLE,
						text = "Vanilla hung a small frame under each member's portrait.",
						shown = function() return db().party.enabled and db().party.showPetFrames and not db().party.useRaidStyle end,
						get = function() return db().party.petStyle or "classic" end,
						set = function(v) db().party.petStyle = v end },
					{ kind = "stepper", label = "Party scale", step = 0.05, min = 0.5, max = 2, format = "%.2f",
						shown = function() return db().party.enabled end,
						get = function() return db().party.scale end,
						set = function(v) db().party.scale = v end },
					{ kind = "stepper", label = "Space between members", step = 1, min = 0, max = 60, format = "%d",
						text = "Blizzard's is 10. Classic party pets add 16 more, as Blizzard does.",
						shown = function() return db().party.enabled end,
						get = function() return db().party.spacing end,
						set = function(v) db().party.spacing = v end },
				},
			},
		},
	},
	{
		name = "Raid",
		sections = {
			{
				title = "Raid",
				rows = {
					{ kind = "toggle", label = "Raid frames",
						get = function() return db().raid.enabled end,
						set = function(v) db().raid.enabled = v end, reload = true },
					{ kind = "toggle", label = "Only while in a raid",
						shown = function() return db().raid.enabled end,
						get = function() return db().raid.showOnlyInRaid end,
						set = function(v) db().raid.showOnlyInRaid = v end },
					{ kind = "toggle", label = "Arrange by raid group",
						shown = function() return db().raid.enabled end,
						get = function() return db().raid.groupByGroup end,
						set = function(v) db().raid.groupByGroup = v end },
					{ kind = "toggle", label = "Raid pets",
						text = "Half-height boxes in their own columns after the groups.",
						shown = function() return db().raid.enabled end,
						get = function() return db().raid.showPets end,
						set = function(v) db().raid.showPets = v end },
					{ kind = "toggle", label = "Fade members out of range",
						shown = function() return db().raid.enabled end,
						get = function() return db().raid.rangeCheck end,
						set = function(v) db().raid.rangeCheck = v end,
						after = function() CUF.Group:UpdateRange() end },
					{ kind = "dropdown", label = "Bar texture", values = RAID_TEXTURE,
						shown = function() return db().raid.enabled end,
						get = function() return db().raid.texture end,
						set = function(v) db().raid.texture = v end },
				},
			},
			{
				title = "Buff and debuff watch",
				rows = {
					{ kind = "toggle", label = "Missing buffs you can cast",
						text = "A red icon in the corner when someone lacks a buff your class provides.",
						get = function() return db().raid.showMissingBuffs end,
						set = function(v) db().raid.showMissingBuffs = v end },
					{ kind = "toggle", label = "Also watch optional buffs",
						text = "Divine Spirit, Thorns and Battle Shout, which are talented or situational.",
						shown = function() return db().raid.showMissingBuffs end,
						get = function() return db().raid.watchOptionalBuffs end,
						set = function(v) db().raid.watchOptionalBuffs = v end },
					{ kind = "toggle", label = "Debuffs you can dispel",
						text = "The frame's border in the debuff's colour, with its icon.",
						get = function() return db().raid.showDispellable end,
						set = function(v) db().raid.showDispellable = v end },
				},
			},
			{
				title = "Size and layout",
				rows = {
					{ kind = "stepper", label = "Raid scale", step = 0.05, min = 0.5, max = 2, format = "%.2f",
						get = function() return db().raid.scale end,
						set = function(v) db().raid.scale = v end },
					{ kind = "stepper", label = "Box width", step = 2, min = 40, max = 200, format = "%d",
						get = function() return db().raid.width end,
						set = function(v) db().raid.width = v end },
					{ kind = "stepper", label = "Box height", step = 2, min = 16, max = 100, format = "%d",
						get = function() return db().raid.height end,
						set = function(v) db().raid.height = v end },
					{ kind = "stepper", label = "Space between boxes", step = 1, min = 0, max = 30, format = "%d",
						get = function() return db().raid.spacing end,
						set = function(v) db().raid.spacing = v end },
					{ kind = "stepper", label = "Rows per column", step = 1, min = 1, max = 40, format = "%d",
						get = function() return db().raid.perColumn end,
						set = function(v) db().raid.perColumn = v end },
				},
			},
		},
	},
	{
		name = "Cast bars",
		sections = {
			{
				title = "Style",
				text = "Quartz is a slim modern bar. Classic is vanilla's bar with its border, spark and finishing flash.",
				rows = {
					{ kind = "dropdown", label = "Cast bar style", values = CAST_STYLE,
						get = function() return db().castbar.style end,
						set = function(v) db().castbar.style = v end },
					{ kind = "button", label = "Try it", text = "Shows both bars mid-cast, then plays the ending.",
						buttonText = "Test cast bars", onClick = function() CUF.Cast:Test() end },
				},
			},
			{
				title = "Bars",
				rows = {
					{ kind = "toggle", label = "Player cast bar",
						get = function() return db().castbar.enabled end,
						set = function(v) db().castbar.enabled = v end },
					{ kind = "toggle", label = "Target cast bar",
						shown = function() return db().castbar.enabled end,
						get = function() return db().castbar.showTarget end,
						set = function(v) db().castbar.showTarget = v end },
					{ kind = "toggle", label = "Focus cast bar",
						text = "Placed on the focus frame the same way as the target's.",
						shown = function() return db().castbar.enabled and db().units.focus.enabled end,
						get = function() return db().castbar.showFocus end,
						set = function(v) db().castbar.showFocus = v end, reload = true },
					{ kind = "stepper", label = "Scale", step = 0.05, min = 0.5, max = 2, format = "%.2f",
						shown = function() return db().castbar.enabled end,
						get = function() return db().castbar.scale end,
						set = function(v) db().castbar.scale = v end },
				},
			},
			{
				title = "Quartz style",
				shown = function() return db().castbar.enabled and quartz() end,
				rows = {
					{ kind = "toggle", label = "Spell icon",
						get = function() return db().castbar.showIcon end,
						set = function(v) db().castbar.showIcon = v end },
					{ kind = "toggle", label = "Timer",
						get = function() return db().castbar.showTime end,
						set = function(v) db().castbar.showTime = v end },
					{ kind = "toggle", label = "Show the total time too",
						text = "Writes the timer as \"1.2 / 2.5\" instead of just the time left.",
						shown = function() return db().castbar.showTime end,
						get = function() return db().castbar.showTotal end,
						set = function(v) db().castbar.showTotal = v end },
					{ kind = "toggle", label = "Latency zone",
						text = "Shades the end of your bar by your latency, so you know when it is safe to move.",
						get = function() return db().castbar.showLatency end,
						set = function(v) db().castbar.showLatency = v end },
					{ kind = "stepper", label = "Width", step = 5, min = 100, max = 400, format = "%d",
						get = function() return db().castbar.width end,
						set = function(v) db().castbar.width = v end },
					{ kind = "stepper", label = "Height", step = 1, min = 8, max = 40, format = "%d",
						get = function() return db().castbar.height end,
						set = function(v) db().castbar.height = v end },
					{ kind = "stepper", label = "Target bar width", step = 5, min = 60, max = 400, format = "%d",
						shown = function() return db().castbar.showTarget end,
						get = function() return db().castbar.targetWidth end,
						set = function(v) db().castbar.targetWidth = v end },
					{ kind = "stepper", label = "Target bar height", step = 1, min = 6, max = 40, format = "%d",
						shown = function() return db().castbar.showTarget end,
						get = function() return db().castbar.targetHeight end,
						set = function(v) db().castbar.targetHeight = v end },
				},
			},
			{
				title = "Classic style",
				text = "The art is drawn for fixed heights, so only the width can change.",
				shown = function() return db().castbar.enabled and classicCast() end,
				rows = {
					{ kind = "toggle", label = "Spell icon on your bar",
						text = "Vanilla's own bar had none.",
						get = function() return db().castbar.classicIcon end,
						set = function(v) db().castbar.classicIcon = v end },
					{ kind = "toggle", label = "Spell icon on the target's bar",
						shown = function() return db().castbar.showTarget end,
						get = function() return db().castbar.classicTargetIcon end,
						set = function(v) db().castbar.classicTargetIcon = v end },
					{ kind = "toggle", label = "Timer",
						text = "The time left, at the right end of the bar.",
						get = function() return db().castbar.classicTime end,
						set = function(v) db().castbar.classicTime = v end },
					{ kind = "toggle", label = "Spark",
						text = "The bright tip riding the end of the fill.",
						get = function() return db().castbar.classicSpark end,
						set = function(v) db().castbar.classicSpark = v end },
					{ kind = "toggle", label = "Flash when a cast completes",
						get = function() return db().castbar.classicFlash end,
						set = function(v) db().castbar.classicFlash = v end },
					{ kind = "stepper", label = "Width", step = 5, min = 120, max = 350, format = "%d",
						get = function() return db().castbar.classicWidth end,
						set = function(v) db().castbar.classicWidth = v end },
					{ kind = "stepper", label = "Target bar width", step = 5, min = 80, max = 300, format = "%d",
						shown = function() return db().castbar.showTarget end,
						get = function() return db().castbar.classicTargetWidth end,
						set = function(v) db().castbar.classicTargetWidth = v end },
				},
			},
			{
				title = "Target and focus bar placement",
				shown = function() return db().castbar.enabled and (db().castbar.showTarget or db().castbar.showFocus) end,
				rows = {
					{ kind = "toggle", label = "Attach to the frame",
						text = "Hangs the bar off the target or focus frame.",
						get = function() return db().castbar.targetAttached end,
						set = function(v) db().castbar.targetAttached = v end },
					{ kind = "dropdown", label = "Placement", values = PLACEMENT,
						text = "Blizzard's own spot: under the frame, under the buffs and debuffs when there are any, and clear of the target of target.",
						shown = function() return db().castbar.targetAttached end,
						get = function() return db().castbar.targetPlacement or "blizzard" end,
						set = function(v) db().castbar.targetPlacement = v end },
					{ kind = "dropdown", label = "Side", values = SIDE,
						shown = function() return db().castbar.targetAttached and db().castbar.targetPlacement == "custom" end,
						get = function() return db().castbar.targetAnchor end,
						set = function(v) db().castbar.targetAnchor = v end },
					{ kind = "stepper", label = "Nudge left / right", step = 2, min = -250, max = 250, format = "%d",
						shown = function() return db().castbar.targetAttached and db().castbar.targetPlacement == "custom" end,
						get = function() return db().castbar.targetOffsetX end,
						set = function(v) db().castbar.targetOffsetX = v end },
					{ kind = "stepper", label = "Distance from the frame", step = 2, min = 0, max = 250, format = "%d",
						shown = function() return db().castbar.targetAttached and db().castbar.targetPlacement == "custom" end,
						get = function() return db().castbar.targetGap end,
						set = function(v) db().castbar.targetGap = v end },
				},
			},
		},
	},
	{
		name = "Tooltips",
		sections = {
			{
				title = "Tooltips",
				rows = {
					{ kind = "toggle", label = "Unit tooltips on hover",
						text = "Hovering any of these frames shows that unit's tooltip.",
						get = function() return db().tooltips end,
						set = function(v) db().tooltips = v end },
					{ kind = "toggle", label = "Add the guild",
						shown = function() return db().tooltips end,
						get = function() return db().tooltipGuild end,
						set = function(v) db().tooltipGuild = v end },
					{ kind = "toggle", label = "Hide in combat",
						shown = function() return db().tooltips end,
						get = function() return db().hideTooltipsInCombat end,
						set = function(v) db().hideTooltipsInCombat = v end },
					{ kind = "dropdown", label = "Position", values = TOOLTIP_ANCHOR,
						shown = function() return db().tooltips end,
						get = function() return db().tooltipAnchor end,
						set = function(v) db().tooltipAnchor = v end },
				},
			},
		},
	},
	{
		name = "Action bars",
		sections = {
			{
				title = "Classic button skin",
				text = "Blizzard's own buttons keep working underneath, so paging, keybinds and macros are untouched.",
				rows = {
					{ kind = "toggle", label = "Skin the action buttons",
						text = "The classic border and fonts on Blizzard's action buttons.",
						get = function() return db().actionBars.enabled end,
						set = function(v) db().actionBars.enabled = v end },
					{ kind = "toggle", label = "Keybind text",
						shown = function() return db().actionBars.enabled end,
						get = function() return db().actionBars.showHotkeys end,
						set = function(v) db().actionBars.showHotkeys = v end },
					{ kind = "toggle", label = "Macro names",
						shown = function() return db().actionBars.enabled end,
						get = function() return db().actionBars.showMacroNames end,
						set = function(v) db().actionBars.showMacroNames = v end },
					{ kind = "note", text = "The gryphon end caps on this client are already the classic ones, so they are left alone. /cuf bars re-applies the skin and reports what it found." },
				},
			},
		},
	},
	{
		name = "About",
		sections = {
			{
				title = "Squawk ClassicUF",
				rows = {
					{ kind = "note", text = "Classic 1.12-style player, target, party and raid frames for WoW: Forever, made by Avoid Me of <Squawk>." },
					{ kind = "note", text = "Every piece of art, bar, icon and number sits where vanilla and Blizzard's own frames put it, with Blizzard's aura and cast bar placement." },
				},
			},
			{
				title = "Commands",
				rows = {
					{ kind = "note", text = "/cuf opens this page.  /cuf unlock and /cuf lock move the frames.  /cuf scale 1.2 sizes every frame at once.  /cuf casttest shows the cast bars.  /cuf castdiag, /cuf marks, /cuf pet and /cuf auradiag report what the client allows.  /cuf reset puts every setting back." },
				},
			},
		},
	},
}

-- ---------------------------------------------------------------------------
-- building a page
-- ---------------------------------------------------------------------------

local pages = {}          -- built pages, by index
local controls = {}       -- everything with a Refresh

local function refreshAll()
	for _, control in ipairs(controls) do
		if control.Refresh then control:Refresh() end
	end
end

-- Called after any change: save, apply, and re-flow the page in case a row
-- appeared or went away.
local function changed(row, value)
	if row.reload then Options:NeedReload() end
	if row.after then row.after(value) end
	apply()
	refreshAll()
	Options:Layout()
end

local function controlFor(row, parent)
	if row.kind == "toggle" then
		local control = switch(parent, function(value)
			row.set(value)
			changed(row, value)
		end)
		control.Refresh = function(self) self:SetValue(row.get()) end
		return control
	elseif row.kind == "dropdown" then
		return dropdown(parent, row.values, row.get, function(value)
			row.set(value)
			changed(row, value)
		end)
	elseif row.kind == "stepper" then
		local control = stepper(parent, row.get, function(value)
			row.set(value)
			changed(row, value)
		end, row.step, row.min, row.max, row.format)
		return control
	elseif row.kind == "unit" then
		local holder = CreateFrame("Frame", nil, parent)
		holder:SetSize(104 + 10 + 104, 22)
		local toggle = switch(holder, function(value)
			row.set(value)
			changed(row, value)
		end)
		toggle:SetPoint("LEFT", holder, "LEFT", 0, 0)
		local scale = stepper(holder, row.scaleGet, function(value)
			row.scaleSet(value)
			changed({}, value)
		end, 0.05, 0.5, 2.0, "%.2f")
		scale:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
		holder.Refresh = function()
			toggle:SetValue(row.get())
			scale:Refresh()
		end
		return holder
	elseif row.kind == "button" then
		return button(parent, row.buttonText, 150, 22, row.onClick)
	end
	return nil
end

local function buildPage(index)
	local spec = PAGES[index]
	local page = CreateFrame("Frame", nil, Options.Scroll)
	page:SetSize(400, 400)
	page:Hide()
	page.sections = {}

	for _, sectionSpec in ipairs(spec.sections) do
		local section = { spec = sectionSpec, rows = {} }

		section.Title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		section.Title:SetText(sectionSpec.title)
		section.Title:SetJustifyH("LEFT")
		section.Rule = page:CreateTexture(nil, "ARTWORK")
		section.Rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
		section.Rule:SetHeight(1)
		if sectionSpec.text then
			section.Text = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			section.Text:SetJustifyH("LEFT")
			section.Text:SetText(sectionSpec.text)
		end

		for _, rowSpec in ipairs(sectionSpec.rows) do
			local row = CreateFrame("Frame", nil, page)
			row.spec = rowSpec
			row.Stripe = row:CreateTexture(nil, "BACKGROUND")
			row.Stripe:SetAllPoints(row)
			row.Stripe:SetColorTexture(1, 1, 1, 0.035)

			if rowSpec.kind == "note" then
				row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.Label:SetJustifyH("LEFT")
				row.Label:SetText(rowSpec.text)
			else
				row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
				row.Label:SetJustifyH("LEFT")
				row.Label:SetText(rowSpec.label)
				if rowSpec.text then
					row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					row.Text:SetJustifyH("LEFT")
					row.Text:SetTextColor(0.8, 0.8, 0.8)
					row.Text:SetText(rowSpec.text)
				end
				if rowSpec.reload then
					row.Reload = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
					row.Reload:SetText("|cffffd200Needs a reload|r")
				end
				row.Control = controlFor(rowSpec, row)
				if row.Control and row.Control.Refresh then
					controls[#controls + 1] = row.Control
				end
			end
			section.rows[#section.rows + 1] = row
		end
		page.sections[#page.sections + 1] = section
	end
	return page
end

-- Positions everything on the page from the top down.  Called whenever the
-- width changes or a row appears or disappears.
local function layoutPage(page, width)
	local y = -6
	local inner = width - 12
	for _, section in ipairs(page.sections) do
		local sectionShown = not section.spec.shown or section.spec.shown()
		section.Title:SetShown(sectionShown)
		section.Rule:SetShown(sectionShown)
		if section.Text then section.Text:SetShown(sectionShown) end

		if sectionShown then
			section.Title:ClearAllPoints()
			section.Title:SetPoint("TOPLEFT", page, "TOPLEFT", 6, y)
			section.Rule:ClearAllPoints()
			section.Rule:SetPoint("LEFT", section.Title, "RIGHT", 10, 0)
			section.Rule:SetPoint("RIGHT", page, "RIGHT", -6, 0)
			y = y - (section.Title:GetStringHeight() or 16) - 4
			if section.Text then
				section.Text:ClearAllPoints()
				section.Text:SetWidth(inner)
				section.Text:SetPoint("TOPLEFT", page, "TOPLEFT", 6, y)
				y = y - (section.Text:GetStringHeight() or 12) - 4
			end
			y = y - 4
		end

		local stripe = false
		for _, row in ipairs(section.rows) do
			local spec = row.spec
			local shown = sectionShown and (not spec.shown or spec.shown())
			row:SetShown(shown)
			if shown then
				stripe = not stripe
				row.Stripe:SetShown(stripe)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", page, "TOPLEFT", 6, y)
				row:SetWidth(inner)

				-- the text gets whatever the control leaves
				local controlWidth = row.Control and row.Control:GetWidth() or 0
				local textWidth = inner - 16 - (controlWidth > 0 and controlWidth + 16 or 0)
				if row.Reload then
					row.Reload:SetShown(true)
				end

				local height = ROW_PAD
				row.Label:ClearAllPoints()
				row.Label:SetWidth(math.max(textWidth, 60))
				row.Label:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -ROW_PAD)
				height = height + math.max(row.Label:GetStringHeight() or 0, 14)
				if row.Text then
					row.Text:ClearAllPoints()
					row.Text:SetWidth(math.max(textWidth, 60))
					row.Text:SetPoint("TOPLEFT", row.Label, "BOTTOMLEFT", 0, -3)
					height = height + 3 + math.max(row.Text:GetStringHeight() or 0, 12)
				end
				if row.Reload then
					row.Reload:ClearAllPoints()
					row.Reload:SetPoint("TOPLEFT", row.Text or row.Label, "BOTTOMLEFT", 0, -3)
					height = height + 3 + (row.Reload:GetStringHeight() or 12)
				end
				height = math.max(height + ROW_PAD, 22 + 2 * ROW_PAD)
				row:SetHeight(height)

				if row.Control then
					row.Control:ClearAllPoints()
					row.Control:SetPoint("RIGHT", row, "RIGHT", -8, 0)
				end
				y = y - height - ROW_GAP
			end
		end
		if sectionShown then y = y - SECTION_GAP end
	end
	page:SetHeight(math.max(-y, 10))
	return -y
end

-- ---------------------------------------------------------------------------
-- scrolling
-- ---------------------------------------------------------------------------

local function updateScrollBar()
	local scroll, bar = Options.Scroll, Options.ScrollBar
	if not scroll or not bar then return end
	local page = pages[Options.CurrentPage]
	local range = page and math.max(0, page:GetHeight() - scroll:GetHeight()) or 0
	Options.scrollRange = range
	bar:SetMinMaxValues(0, range)
	bar:SetShown(range > 1)
	local current = math.min(scroll:GetVerticalScroll(), range)
	scroll:SetVerticalScroll(current)
	bar:SetValue(current)
end

function Options:Layout()
	local scroll = Options.Scroll
	local page = pages[Options.CurrentPage]
	if not scroll or not page then return end
	local width = scroll:GetWidth()
	if not width or width < 50 then return end
	page:SetWidth(width)
	layoutPage(page, width)
	updateScrollBar()
end

-- ---------------------------------------------------------------------------
-- reload banner
-- ---------------------------------------------------------------------------

function Options:NeedReload()
	Options.needsReload = true
	if Options.Banner and not Options.Banner:IsShown() then
		Options.Banner:Show()
		Options:PlaceScroll()
	end
end

function Options:PlaceScroll()
	local top = HEADER_HEIGHT + ((Options.Banner and Options.Banner:IsShown()) and (BANNER_HEIGHT + 6) or 0)
	Options.Scroll:ClearAllPoints()
	Options.Scroll:SetPoint("TOPLEFT", Options.Panel, "TOPLEFT", SIDEBAR_WIDTH + 14, -top)
	Options.Scroll:SetPoint("BOTTOMRIGHT", Options.Panel, "BOTTOMRIGHT", -(SCROLLBAR_WIDTH + 10), FOOTER_HEIGHT)
end

-- ---------------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------------

function Options:SelectPage(index)
	closeDropdown()
	if not pages[index] then pages[index] = buildPage(index) end
	for i, page in pairs(pages) do
		page:SetShown(i == index)
	end
	Options.Scroll:SetScrollChild(pages[index])
	Options.Scroll:SetVerticalScroll(0)
	Options.CurrentPage = index

	for i, entry in ipairs(Options.Categories) do
		local selected = i == index
		entry.Text:SetFontObject(selected and "GameFontHighlight" or "GameFontNormal")
		entry.Selected:SetShown(selected)
		entry.Mark:SetShown(selected)
	end
	refreshAll()
	Options:Layout()
end

-- ---------------------------------------------------------------------------
-- panel
-- ---------------------------------------------------------------------------

function Options:Initialize()
	local panel = CreateFrame("Frame", "SquawkClassicUF_Options", UIParent, "BackdropTemplate")
	Options.Panel = panel
	panel.name = "Squawk ClassicUF"
	panel:SetSize(760, 560)
	panel:Hide()

	-- header ---------------------------------------------------------------
	local icon = panel:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame")
	icon:SetTexCoord(0.2, 0.42, 0.1, 0.55)
	icon:SetSize(44, 44)
	icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)

	local unlock = button(panel, CUF.db.locked and "Unlock frames" or "Lock frames", 116, 22)
	unlock:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -12)
	unlock:SetScript("OnClick", function(self)
		CUF.db.locked = not CUF.db.locked
		CUF:SetLocked(CUF.db.locked)
		self:SetLabel(CUF.db.locked and "Unlock frames" or "Lock frames")
	end)
	local test = button(panel, "Test cast bars", 116, 22, function() CUF.Cast:Test() end)
	test:SetPoint("TOPRIGHT", unlock, "BOTTOMRIGHT", 0, -4)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
	title:SetText("Squawk ClassicUF")
	local version = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
	version:SetText("v" .. CUF.Version)

	local tagline = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
	tagline:SetPoint("RIGHT", unlock, "LEFT", -14, 0)
	tagline:SetJustifyH("LEFT")
	tagline:SetJustifyV("TOP")
	pcall(tagline.SetMaxLines, tagline, 2)
	tagline:SetText("Classic 1.12 unit frames for WoW: Forever.  |cffffd100Made by Avoid Me|r |cff82c5ff<Squawk>|r")

	local rule = panel:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -(HEADER_HEIGHT - 6))
	rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -(HEADER_HEIGHT - 6))

	-- sidebar --------------------------------------------------------------
	local sidebar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	sidebar:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -HEADER_HEIGHT)
	sidebar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, FOOTER_HEIGHT)
	sidebar:SetWidth(SIDEBAR_WIDTH)
	sidebar:SetBackdrop(CARD_BACKDROP)
	sidebar:SetBackdropColor(0, 0, 0, 0.45)
	sidebar:SetBackdropBorderColor(0.4, 0.4, 0.4)

	Options.Categories = {}
	for index, spec in ipairs(PAGES) do
		local entry = CreateFrame("Button", nil, sidebar)
		entry:SetHeight(24)
		entry:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 5, -6 - (index - 1) * 26)
		entry:SetPoint("RIGHT", sidebar, "RIGHT", -5, 0)
		entry.Selected = entry:CreateTexture(nil, "BACKGROUND")
		entry.Selected:SetAllPoints(entry)
		entry.Selected:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.16)
		entry.Selected:Hide()
		entry.Mark = entry:CreateTexture(nil, "ARTWORK")
		entry.Mark:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
		entry.Mark:SetWidth(2)
		entry.Mark:SetPoint("TOPLEFT", entry, "TOPLEFT")
		entry.Mark:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT")
		entry.Mark:Hide()
		local glow = entry:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints(entry)
		glow:SetColorTexture(1, 1, 1, 0.06)
		entry.Text = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		entry.Text:SetPoint("LEFT", entry, "LEFT", 10, 0)
		entry.Text:SetPoint("RIGHT", entry, "RIGHT", -4, 0)
		entry.Text:SetJustifyH("LEFT")
		pcall(entry.Text.SetWordWrap, entry.Text, false)
		entry.Text:SetText(spec.name)
		entry:SetScript("OnClick", function() Options:SelectPage(index) end)
		Options.Categories[index] = entry
	end

	-- reload banner --------------------------------------------------------
	local banner = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	banner:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDEBAR_WIDTH + 14, -HEADER_HEIGHT)
	banner:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -HEADER_HEIGHT)
	banner:SetHeight(BANNER_HEIGHT)
	banner:SetBackdrop(CARD_BACKDROP)
	banner:SetBackdropColor(0.3, 0.2, 0.02, 0.9)
	banner:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3])
	local reload = button(banner, _G.RELOADUI or "Reload UI", 110, 22, function() ReloadUI() end)
	reload:SetPoint("RIGHT", banner, "RIGHT", -6, 0)
	local bannerText = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bannerText:SetPoint("LEFT", banner, "LEFT", 10, 0)
	bannerText:SetPoint("RIGHT", reload, "LEFT", -8, 0)
	bannerText:SetJustifyH("LEFT")
	pcall(bannerText.SetMaxLines, bannerText, 2)
	bannerText:SetText("Some changes take effect after the interface is reloaded.")
	banner:Hide()
	Options.Banner = banner

	-- content --------------------------------------------------------------
	local scroll = CreateFrame("ScrollFrame", nil, panel)
	Options.Scroll = scroll
	Options:PlaceScroll()
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = Options.scrollRange or 0
		local target = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40))
		self:SetVerticalScroll(target)
		if Options.ScrollBar then Options.ScrollBar:SetValue(target) end
	end)
	scroll:SetScript("OnSizeChanged", function() Options:Layout() end)

	local bar = CreateFrame("Slider", nil, panel, "BackdropTemplate")
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(SCROLLBAR_WIDTH)
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
	bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	bar:SetBackdropColor(0, 0, 0, 0.35)
	bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	local thumb = bar:GetThumbTexture()
	if thumb then thumb:SetSize(SCROLLBAR_WIDTH + 2, 24) end
	bar:SetValueStep(1)
	bar:SetMinMaxValues(0, 0)
	bar:SetValue(0)
	bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
	bar:Hide()
	Options.ScrollBar = bar

	-- footer ---------------------------------------------------------------
	local reset = button(panel, "Reset to defaults", 140, 22, function()
		StaticPopup_Show("SQUAWKCLASSICUF_RESET")
	end)
	reset:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", SIDEBAR_WIDTH + 14, 10)
	local art = button(panel, "Check classic art", 140, 22, function() CUF:ShowArtCheck() end)
	art:SetPoint("LEFT", reset, "RIGHT", 8, 0)

	StaticPopupDialogs["SQUAWKCLASSICUF_RESET"] = {
		text = "Put every Squawk ClassicUF setting back to its default?",
		button1 = _G.YES or "Yes", button2 = _G.NO or "No",
		OnAccept = function()
			SlashCmdList["SQUAWKCLASSICUF"]("reset")
			refreshAll()
			Options:Layout()
		end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}

	panel:SetScript("OnShow", function()
		unlock:SetLabel(CUF.db.locked and "Unlock frames" or "Lock frames")
		refreshAll()
		Options:Layout()
	end)
	panel:SetScript("OnHide", closeDropdown)
	panel:SetScript("OnSizeChanged", function() Options:Layout() end)
	Options:SelectPage(1)

	-- register with whatever settings system exists, else stand alone
	if type(Settings) == "table" and Settings.RegisterCanvasLayoutCategory then
		local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Squawk ClassicUF")
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
	panel:SetClampedToScreen(true)
	panel:SetBackdrop(CARD_BACKDROP)
	panel:SetBackdropColor(0, 0, 0, 0.92)
	panel:SetScript("OnMouseDown", function(self) self:StartMoving() end)
	panel:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

	local close = CreateFrame("Button", nil, panel)
	close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
	close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
	close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() panel:Hide() end)
	-- keep the quick buttons clear of the close button
	unlock:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -30, -12)
end

function Options:Refresh()
	refreshAll()
	Options:Layout()
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
	elseif type(InterfaceOptionsFrame_OpenToCategory) == "function" then
		InterfaceOptionsFrame_OpenToCategory(Options.Panel)
		InterfaceOptionsFrame_OpenToCategory(Options.Panel)
	else
		Options.Panel:Show()
	end
end
