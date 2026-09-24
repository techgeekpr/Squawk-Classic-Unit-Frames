--[[ Party and raid frames.

	Both are plain secure unit buttons on fixed tokens (party1..4, raid1..40),
	not secure group headers -- headers depend on secure snippets, which do not
	compile on this client.  Fixed tokens need no snippet, and RegisterUnitWatch
	handles showing and hiding.

	Anything that moves a frame is wrapped in CUF:RunProtected, because a
	protected frame cannot be repositioned during combat.
]]

local CUF = SquawkClassicUF
local Group = {}
CUF.Group = Group

local Art = CUF.Art

Group.party = {}          -- Classic 128x53 party frames
Group.partyCompact = {}   -- the same party, drawn as raid-style boxes
Group.raid = {}

-- Classic PartyMemberFrame geometry
local PARTY = {
	width = 128, height = 53,
	artWidth = 128, artHeight = 64, artX = 0, artY = -2,
	portraitSize = 37, portraitX = 7, portraitY = -6,
	barWidth = 70, barHeight = 8,
	healthX = 47, healthY = -12,
	manaX = 47, manaY = -22,
	nameX = 50, nameY = 43,
}

local function classColor(unit)
	if not UnitIsPlayer(unit) then return nil end
	local _, class = UnitClass(unit)
	return class and CUF.ClassColors[class]
end

-- ---------------------------------------------------------------------------
-- shared updates.  Bars receive secret values directly; only text is guarded.
-- ---------------------------------------------------------------------------

local function updateFrame(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end

	frame.Health:SetMinMaxValues(0, UnitHealthMax(unit))
	frame.Health:SetValue(UnitHealth(unit))

	local color = classColor(unit)
	if CUF.db.classColorHealth and color then
		frame.Health:SetStatusBarColor(color[1], color[2], color[3])
	else
		frame.Health:SetStatusBarColor(0.1, 0.8, 0.1)
	end

	if frame.Power then
		frame.Power:SetMinMaxValues(0, UnitPowerMax(unit))
		frame.Power:SetValue(UnitPower(unit))
		local power = CUF.PowerColors[UnitPowerType(unit)] or CUF.PowerColors[0]
		frame.Power:SetStatusBarColor(power[1], power[2], power[3])
	end

	if frame.Name then
		frame.Name:SetText(UnitName(unit) or "")
		if frame.compact then
			frame.Name:SetTextColor(1, 1, 1, 1)   -- white with a shadow
		else
			frame.Name:SetTextColor(1, 0.82, 0)   -- Classic gold
		end
	end

	if frame.compact and CUF.Auras then
		CUF.Auras:Update(frame)
	end

	if frame.HealthText then
		frame.HealthText:SetText(CUF.HealthText(unit, CUF.db.healthText))
	end

	if frame.Portrait then
		if CUF.db.showPortraits then
			frame.Portrait:Show()
			pcall(SetPortraitTexture, frame.Portrait, unit)
		else
			frame.Portrait:Hide()
		end
	end

	if frame.StatusText then
		if UnitIsDeadOrGhost(unit) then
			frame.StatusText:SetText("Dead")
			frame.StatusText:Show()
		elseif not UnitIsConnected(unit) then
			frame.StatusText:SetText("Offline")
			frame.StatusText:Show()
		else
			frame.StatusText:Hide()
		end
	end
end

local function registerEvents(frame)
	frame:SetScript("OnEvent", function(self) updateFrame(self) end)
	for _, event in ipairs({
		"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
		"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE",
		"UNIT_CONNECTION", "UNIT_AURA",
	}) do
		pcall(frame.RegisterUnitEvent, frame, event, frame.unit)
	end
end

local function createBar(parent, width, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(width, height)
	bar:SetStatusBarTexture(CUF:BarTexture())
	bar:SetMinMaxValues(0, 100)
	bar:SetValue(100)
	bar.Background = bar:CreateTexture(nil, "BACKGROUND")
	bar.Background:SetAllPoints(bar)
	bar.Background:SetColorTexture(0, 0, 0, 0.6)
	return bar
end

local function makeUnitButton(name, unit)
	local frame = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
	frame.unit = unit
	frame:SetAttribute("unit", unit)
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "togglemenu")
	frame:RegisterForClicks("AnyUp")
	return frame
end

-- ---------------------------------------------------------------------------
-- party
-- ---------------------------------------------------------------------------

function Group:CreatePartyFrame(index)
	local frame = makeUnitButton("SquawkClassicUF_Party" .. index, "party" .. index)
	frame:SetSize(PARTY.width, PARTY.height)

	frame.Portrait = frame:CreateTexture(nil, "BORDER")
	frame.Portrait:SetSize(PARTY.portraitSize, PARTY.portraitSize)
	frame.Portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY.portraitX, PARTY.portraitY)

	frame.Health = createBar(frame, PARTY.barWidth, PARTY.barHeight)
	frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY.healthX, PARTY.healthY)

	frame.Power = createBar(frame, PARTY.barWidth, PARTY.barHeight)
	frame.Power:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY.manaX, PARTY.manaY)

	frame.ArtFrame = CreateFrame("Frame", nil, frame)
	frame.ArtFrame:SetAllPoints(frame)
	frame.ArtFrame:SetFrameLevel(frame:GetFrameLevel() + 3)

	frame.Art = frame.ArtFrame:CreateTexture(nil, "ARTWORK")
	frame.Art:SetTexture(Art.partyFrame)
	frame.Art:SetSize(PARTY.artWidth, PARTY.artHeight)
	frame.Art:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY.artX, PARTY.artY)

	frame.Name = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Name:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PARTY.nameX, PARTY.nameY)
	frame.Name:SetJustifyH("LEFT")

	frame.HealthText = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.HealthText:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)

	frame.StatusText = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.StatusText:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
	frame.StatusText:SetTextColor(1, 0.2, 0.2)
	frame.StatusText:Hide()

	CUF:AttachTooltip(frame)
	registerEvents(frame)
	return frame
end

-- ---------------------------------------------------------------------------
-- raid
-- ---------------------------------------------------------------------------

-- The compact box used by raid frames, and by party frames when they are set
-- to the raid style.
function Group:CreateCompactFrame(name, unit)
	local settings = CUF.db.raid
	local frame = makeUnitButton(name, unit)
	frame:SetSize(settings.width, settings.height)

	local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	backdrop:SetPoint("TOPLEFT", -2, 2)
	backdrop:SetPoint("BOTTOMRIGHT", 2, -2)
	backdrop:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	backdrop:SetBackdropColor(0, 0, 0, 0.8)
	backdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	backdrop:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
	frame.BackdropFrame = backdrop

	frame.compact = true
	frame.Health = createBar(frame, settings.width - 4, settings.height - 4)
	frame.Health:SetPoint("CENTER")
	frame.Health:SetStatusBarTexture(CUF:RaidBarTexture())

	-- A StatusBar is a child frame, so it draws over any text belonging to its
	-- parent.  Text goes on an overlay above the bar instead.
	frame.Overlay = CreateFrame("Frame", nil, frame)
	frame.Overlay:SetAllPoints(frame)
	frame.Overlay:SetFrameLevel(frame.Health:GetFrameLevel() + 5)

	frame.Name = frame.Overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Name:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
	frame.Name:SetJustifyH("CENTER")
	-- Plain white with a shadow reads over any bar colour.
	frame.Name:SetTextColor(1, 1, 1, 1)
	frame.Name:SetShadowColor(0, 0, 0, 1)
	frame.Name:SetShadowOffset(1, -1)

	frame.StatusText = frame.Overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.StatusText:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
	frame.StatusText:SetTextColor(1, 0.2, 0.2)
	frame.StatusText:Hide()

	-- aura indicators: a missing buff you could cast, and a debuff you could
	-- remove.  The glow borders the whole frame in the debuff's colour.
	frame.DispelGlow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	frame.DispelGlow:SetPoint("TOPLEFT", -3, 3)
	frame.DispelGlow:SetPoint("BOTTOMRIGHT", 3, -3)
	frame.DispelGlow:SetBackdrop({
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
	})
	frame.DispelGlow:SetFrameLevel(frame.Overlay:GetFrameLevel() - 1)
	frame.DispelGlow:Hide()

	frame.MissingIcon = frame.Overlay:CreateTexture(nil, "OVERLAY")
	frame.MissingIcon:SetSize(12, 12)
	frame.MissingIcon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)
	frame.MissingIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.MissingIcon:SetDesaturated(true)
	frame.MissingIcon:SetVertexColor(1, 0.4, 0.4)
	frame.MissingIcon:Hide()

	frame.DispelIcon = frame.Overlay:CreateTexture(nil, "OVERLAY")
	frame.DispelIcon:SetSize(14, 14)
	frame.DispelIcon:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
	frame.DispelIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.DispelIcon:Hide()

	CUF:AttachTooltip(frame)
	registerEvents(frame)
	return frame
end

function Group:CreateRaidFrame(index)
	return Group:CreateCompactFrame("SquawkClassicUF_Raid" .. index, "raid" .. index)
end

-- ---------------------------------------------------------------------------
-- layout
-- ---------------------------------------------------------------------------

local function anchorTo(frame, settings, offsetX, offsetY)
	local scale = frame:GetScale()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
		(settings.x + offsetX) / scale, (settings.y + offsetY) / scale)
end

function Group:LayoutParty()
	local settings = CUF.db.party
	for index, frame in ipairs(Group.party) do
		frame:SetScale(settings.scale or 1)
		anchorTo(frame, settings, 0, -(index - 1) * (PARTY.height + settings.spacing))
	end
end

-- Raid-style party frames stack under the party anchor using the raid frame
-- dimensions, so both styles occupy the same corner of the screen.
function Group:LayoutPartyCompact()
	local settings = CUF.db.party
	local size = CUF.db.raid
	local slot = 0
	for _, frame in ipairs(Group.partyCompact) do
		if frame.unit ~= "player" or settings.includePlayer then
			frame:SetScale(settings.scale or 1)
			frame:SetSize(size.width, size.height)
			frame.Health:SetSize(size.width - 4, size.height - 4)
			anchorTo(frame, settings, 0, -slot * (size.height + size.spacing))
			slot = slot + 1
		end
	end
end

function Group:LayoutRaid()
	local settings = CUF.db.raid
	local slots = {}

	-- Placing by subgroup keeps groups in tidy columns the way Classic raid
	-- UIs did; otherwise raid index order is fine.
	if settings.groupByGroup and IsInRaid() then
		local counts = {}
		for index = 1, 40 do
			local _, _, subgroup = GetRaidRosterInfo(index)
			if subgroup then
				counts[subgroup] = (counts[subgroup] or 0) + 1
				slots[index] = { column = subgroup - 1, row = counts[subgroup] - 1 }
			end
		end
	end

	for index, frame in ipairs(Group.raid) do
		local slot = slots[index]
		if not slot then
			slot = {
				column = math.floor((index - 1) / settings.perColumn),
				row = (index - 1) % settings.perColumn,
			}
		end
		frame:SetScale(settings.scale or 1)
		frame:SetSize(settings.width, settings.height)
		frame.Health:SetSize(settings.width - 4, settings.height - 4)
		anchorTo(frame, settings,
			slot.column * (settings.width + settings.spacing),
			-slot.row * (settings.height + settings.spacing))
	end
end

-- Party hides itself in a raid unless asked otherwise; raid frames can be set
-- to appear only when actually in a raid.
function Group:UpdateVisibility()
	local inRaid = IsInRaid()

	local partyVisible = CUF.db.party.enabled and (CUF.db.party.showInRaid or not inRaid)
	local classicStyle = partyVisible and not CUF.db.party.useRaidStyle
	local boxStyle = partyVisible and CUF.db.party.useRaidStyle

	for _, frame in ipairs(Group.party) do
		if classicStyle then
			RegisterUnitWatch(frame)
		else
			UnregisterUnitWatch(frame)
			frame:Hide()
		end
	end

	-- Solo, a lone box for yourself is just clutter, so the block waits for a
	-- group the way the Classic party frames do.
	local inGroup = IsInGroup and IsInGroup()
	for _, frame in ipairs(Group.partyCompact) do
		local wanted = boxStyle and inGroup
		if frame.unit == "player" then
			wanted = wanted and CUF.db.party.includePlayer
		end
		if wanted then
			RegisterUnitWatch(frame)
		else
			UnregisterUnitWatch(frame)
			frame:Hide()
		end
	end

	for _, frame in ipairs(Group.raid) do
		if CUF.db.raid.enabled and (inRaid or not CUF.db.raid.showOnlyInRaid) then
			RegisterUnitWatch(frame)
		else
			UnregisterUnitWatch(frame)
			frame:Hide()
		end
	end
end

-- ---------------------------------------------------------------------------
-- movers
--
-- The frames themselves are protected, so instead of dragging them we drag a
-- plain frame that owns the block's anchor and re-lay the block out on release.
-- ---------------------------------------------------------------------------

local function createMover(label, settings, width, height, relayout)
	local mover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	mover:SetSize(width, height)
	mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", settings.x, settings.y)
	mover:SetFrameStrata("HIGH")
	mover:EnableMouse(true)
	mover:SetMovable(true)
	mover:SetClampedToScreen(true)
	mover:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	mover:SetBackdropColor(0, 0.6, 1, 0.25)
	mover:SetBackdropBorderColor(0, 0.7, 1, 1)
	mover:Hide()

	mover.Label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	mover.Label:SetPoint("CENTER")
	mover.Label:SetText(label)

	mover:SetScript("OnMouseDown", function(self) self:StartMoving() end)
	mover:SetScript("OnMouseUp", function(self)
		self:StopMovingOrSizing()
		settings.x = self:GetLeft()
		settings.y = self:GetTop() - UIParent:GetTop()
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", settings.x, settings.y)
		CUF:RunProtected(relayout)
	end)

	function mover:SetMovableState(movable)
		if movable then self:Show() else self:Hide() end
	end

	CUF.MovableFrames[#CUF.MovableFrames + 1] = mover
	return mover
end

-- Out of range members fade.
--
-- UnitInRange returns *secret* booleans on this client: testing one throws
-- ("attempt to perform boolean test on a secret boolean value").  SetAlphaFromBoolean
-- exists precisely for this -- it consumes the secret and sets the alpha
-- itself, so the addon never learns the value.
local function updateRange(frame)
	if not frame or not frame.unit or not frame:IsShown() then return end
	if not CUF.db.raid.rangeCheck then
		frame:SetAlpha(1)
		return
	end
	if not UnitExists(frame.unit) then return end

	local alpha = CUF.db.raid.rangeAlpha or 0.45

	if frame.SetAlphaFromBoolean then
		local ok, inRange = pcall(UnitInRange, frame.unit)
		if ok and pcall(frame.SetAlphaFromBoolean, frame, inRange, 1, alpha) then
			return
		end
	end

	-- Clients that still hand back a plain boolean: the test happens inside
	-- the pcall, so a secret can never escape and throw.
	local ok, faded = pcall(function()
		local inRange, checked = UnitInRange(frame.unit)
		return (checked and not inRange) and true or false
	end)
	frame:SetAlpha((ok and faded) and alpha or 1)
end

function Group:UpdateRange()
	for _, frame in ipairs(Group.party) do updateRange(frame) end
	for _, frame in ipairs(Group.partyCompact) do updateRange(frame) end
	for _, frame in ipairs(Group.raid) do updateRange(frame) end
end

function Group:Initialize()
	if CUF.db.party.enabled then
		for index = 1, 4 do
			Group.party[index] = Group:CreatePartyFrame(index)
		end
		-- Both styles are built up front so the option can switch instantly;
		-- secure frames cannot be created during combat.
		-- Your own box is always built; "include yourself" only decides whether
		-- it is laid out and watched, so the option needs no reload.
		local units = { "player", "party1", "party2", "party3", "party4" }
		for index, unit in ipairs(units) do
			Group.partyCompact[index] = Group:CreateCompactFrame("SquawkClassicUF_PartyBox" .. index, unit)
		end
	end
	if CUF.db.raid.enabled then
		for index = 1, 40 do
			Group.raid[index] = Group:CreateRaidFrame(index)
		end
	end

	Group:LayoutParty()
	Group:LayoutPartyCompact()
	Group:LayoutRaid()
	Group:UpdateVisibility()

	if CUF.db.party.enabled then
		Group.partyMover = createMover("Party", CUF.db.party,
			PARTY.width, PARTY.height * 4 + CUF.db.party.spacing * 3,
			function() Group:LayoutParty() end)
	end
	if CUF.db.raid.enabled then
		local settings = CUF.db.raid
		Group.raidMover = createMover("Raid", settings,
			settings.width * 4, settings.height * settings.perColumn,
			function() Group:LayoutRaid() end)
	end

	-- One ticker for everybody beats forty OnUpdate handlers.
	C_Timer.NewTicker(0.25, function() Group:UpdateRange() end)

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:SetScript("OnEvent", function()
		CUF:RunProtected(function()
			Group:LayoutRaid()
			Group:UpdateVisibility()
			for _, frame in ipairs(Group.party) do updateFrame(frame) end
			for _, frame in ipairs(Group.partyCompact) do updateFrame(frame) end
			for _, frame in ipairs(Group.raid) do updateFrame(frame) end
		end)
	end)
end

function Group:UpdateAll()
	CUF:RunProtected(function()
		Group:LayoutParty()
		Group:LayoutPartyCompact()
		Group:LayoutRaid()
		Group:UpdateVisibility()
		for _, frame in ipairs(Group.party) do
			frame.Health:SetStatusBarTexture(CUF:BarTexture())
			frame.Power:SetStatusBarTexture(CUF:BarTexture())
			updateFrame(frame)
		end
		for _, frame in ipairs(Group.partyCompact) do
			frame.Health:SetStatusBarTexture(CUF:RaidBarTexture())
			updateFrame(frame)
		end
		for _, frame in ipairs(Group.raid) do
			frame.Health:SetStatusBarTexture(CUF:RaidBarTexture())
			updateFrame(frame)
		end
	end)
end
