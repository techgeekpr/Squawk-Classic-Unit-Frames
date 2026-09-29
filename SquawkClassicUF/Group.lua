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
Group.partyPets = {}        -- partypet1..4 beside the Classic party frames (bar style)
Group.partyClassicPets = {} -- partypet1..4 as vanilla's small frame under the portrait
Group.partyCompactPets = {} -- pet, partypet1..4 under the raid-style party
Group.raidPets = {}         -- raidpet1..40

-- Pet boxes are half the height of a member's box, like Blizzard's.
local function petHeight(settings)
	return math.max(math.floor(settings.height / 2), 14)
end

-- Classic PartyMemberFrame geometry
-- The classic party frame on Blizzard's 120x53 PartyMemberFrame
-- geometry: the classic art hangs 10px down, the
-- bars sit on a black plate, and the debuffs run in a row underneath.
local PARTY = {
	width = 120, height = 53,
	artWidth = 128, artHeight = 64, artX = 0, artY = -10,
	flashX = -3, flashY = -6,
	portraitSize = 37, portraitX = 7, portraitY = -14,
	backdropWidth = 72, backdropHeight = 20, backdropX = 45, backdropY = -19,
	barWidth = 70, barHeight = 8,
	healthX = 47, healthY = -22,
	manaX = 47, manaY = -31,
	nameX = 49, nameY = -7,          -- TOPLEFT
	leaderX = 0, leaderY = -8,
	-- Blizzard's AuraFrameContainer: 15px icons, 2px apart, up to 4 debuffs
	auraX = 48, auraY = -43, auraSize = 15, auraSpacing = 2, auraCount = 4,
	-- Blizzard spaces the party 10px apart, 26 while party pets show
	petSpacing = 16,
}

-- See Units.lua: a secret class name cannot be used as a table key.
local function classColor(unit)
	if CUF.SafeFlag(UnitIsPlayer(unit)) == false then return nil end

	local _, raw = UnitClass(unit)
	local class = CUF.SafeText(raw)
	if not class then return nil end
	return CUF.ClassColors[class]
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
	if CUF.SafeFlag(UnitIsConnected(unit)) == false then
		frame.Health:SetStatusBarColor(0.5, 0.5, 0.5)
	elseif CUF.db.classColorHealth and color then
		frame.Health:SetStatusBarColor(color[1], color[2], color[3])
	else
		local green = CUF.HealthGreen
		frame.Health:SetStatusBarColor(green[1], green[2], green[3])
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

	if frame.PowerText then
		frame.PowerText:SetText(CUF.PowerText(unit, CUF.db.powerText))
	end

	-- Blizzard's threat glow on the member
	if frame.Flash then
		local status
		if CUF.db.threatGlow and type(UnitThreatSituation) == "function" then
			local ok, value = pcall(UnitThreatSituation, unit)
			status = ok and CUF.SafeNumber(value) or nil
		end
		if status and status > 0 then
			local r, g, b = 1, 0, 0
			if type(GetThreatStatusColor) == "function" then
				local got, cr, cg, cb = pcall(GetThreatStatusColor, status)
				if got and CUF.SafeNumber(cr) then r, g, b = cr, cg, cb end
			end
			frame.Flash:SetVertexColor(r, g, b)
			frame.Flash:Show()
		else
			frame.Flash:Hide()
		end
	end

	-- the member's debuffs, up to four, as Blizzard's party frame shows them
	if frame.PartyAuras then
		local petFrame = Group.partyClassicPets and Group.partyClassicPets[tonumber(unit:match("%d") or "")]
		Group:PlacePartyAuras(frame, petFrame and petFrame:IsShown() and UnitExists(petFrame.unit))
		local shown = 0
		if CUF.Auras then
			CUF.Auras:ForEach(unit, "HARMFUL", function(_, dispelType, texture, count, index, spellId, data)
				if not texture then return false end
				shown = shown + 1
				local icon = frame.PartyAuras[shown]
				if not icon then return true end
				CUF.Units.ShowAura(icon, unit, "HARMFUL", texture, count, index, spellId, dispelType, data)
				return shown >= #frame.PartyAuras
			end)
		end
		for slot = shown + 1, #frame.PartyAuras do frame.PartyAuras[slot]:Hide() end
	end

	CUF:UpdateRaidTargetIcon(frame)

	if frame.HealthText then
		frame.HealthText:SetText(CUF.HealthText(unit, CUF.db.healthText))
	end

	if frame.Portrait then
		if CUF.db.showPortraits then
			CUF.Units:ApplyPortraitMask(frame)
			frame.Portrait:Show()
			pcall(SetPortraitTexture, frame.Portrait, unit)
		else
			frame.Portrait:Hide()
		end
	end

	if frame.LeaderIcon then
		local shown = false
		if CUF.db.showLeader and type(UnitIsGroupLeader) == "function" then
			local ok, leader = pcall(UnitIsGroupLeader, unit)
			shown = ok and CUF.SafeFlag(leader) == true
		end
		frame.LeaderIcon:SetShown(shown)
	end

	if frame.StatusText then
		-- Secret booleans throw on a truth test, so an unreadable answer must
		-- fall through to "nothing to say" rather than claim someone is dead.
		if CUF.SafeFlag(UnitIsDeadOrGhost(unit)) == true then
			frame.StatusText:SetText("Dead")
			frame.StatusText:Show()
		elseif CUF.SafeFlag(UnitIsConnected(unit)) == false then
			frame.StatusText:SetText("Offline")
			frame.StatusText:Show()
		else
			frame.StatusText:Hide()
		end
	end
end

local function registerEvents(frame)
	frame:SetScript("OnEvent", function(self) updateFrame(self) end)
	-- Not a unit event: marking anyone fires it for every frame.
	frame:RegisterEvent("RAID_TARGET_UPDATE")
	for _, event in ipairs({
		"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
		"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE",
		"UNIT_CONNECTION", "UNIT_AURA", "UNIT_PORTRAIT_UPDATE",
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

	-- the threat glow behind the frame
	frame.Flash = frame:CreateTexture(nil, "BACKGROUND")
	frame.Flash:SetDrawLayer("BACKGROUND", -7)
	frame.Flash:SetTexture(Art.partyFlash)
	frame.Flash:SetSize(128, 64)
	frame.Flash:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY.flashX, PARTY.flashY)
	frame.Flash:Hide()

	frame.Backdrop = frame:CreateTexture(nil, "BACKGROUND")
	frame.Backdrop:SetSize(PARTY.backdropWidth, PARTY.backdropHeight)
	frame.Backdrop:SetColorTexture(0, 0, 0, 0.5)
	frame.Backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY.backdropX, PARTY.backdropY)

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
	frame.Name:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY.nameX, PARTY.nameY)
	frame.Name:SetJustifyH("LEFT")

	frame.HealthText = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.HealthText:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
	frame.PowerText = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.PowerText:SetPoint("CENTER", frame.Power, "CENTER", 0, 0)

	-- the debuff row underneath
	frame.PartyAuras = {}
	for slot = 1, PARTY.auraCount do
		local icon = CUF.Units:CreateAuraButton(frame, true)
		icon:SetSize(PARTY.auraSize, PARTY.auraSize)
		frame.PartyAuras[slot] = icon
	end
	Group:PlacePartyAuras(frame, false)

	frame.StatusText = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.StatusText:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
	frame.StatusText:SetTextColor(1, 0.2, 0.2)
	frame.StatusText:Hide()

	CUF:CreateRaidTargetIcon(frame, frame.ArtFrame, 16)
	frame.RaidIcon:SetPoint("CENTER", frame.Portrait, "TOP", 0, 0)

	-- the leader's crown in the top-left corner (vanilla: TOPLEFT 0,0)
	frame.LeaderIcon = frame.ArtFrame:CreateTexture(nil, "OVERLAY")
	frame.LeaderIcon:SetSize(16, 16)
	frame.LeaderIcon:SetTexture(CUF.Art.leaderIcon)
	frame.LeaderIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY.leaderX, PARTY.leaderY)
	frame.LeaderIcon:Hide()

	CUF:AttachTooltip(frame)
	registerEvents(frame)
	frame:RegisterEvent("PARTY_LEADER_CHANGED")
	frame:RegisterEvent("GROUP_ROSTER_UPDATE")
	pcall(frame.RegisterUnitEvent, frame, "UNIT_THREAT_SITUATION_UPDATE", frame.unit)
	return frame
end

-- The debuff row starts at Blizzard's (48, -43); a classic party pet sits at
-- (23, -43) and would cover it, so while one is out the row starts past it.
function Group:PlacePartyAuras(frame, petShown)
	local x = petShown and (23 + 64 + 4) or PARTY.auraX
	for slot, icon in ipairs(frame.PartyAuras or {}) do
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", frame, "TOPLEFT",
			x + (slot - 1) * (PARTY.auraSize + PARTY.auraSpacing), PARTY.auraY)
	end
end

-- Vanilla's party pet: the party frame art at half size, a small round
-- portrait and a thin health bar, hung under the member's portrait
-- (PartyMemberPetFrame, on the member).
-- Blizzard's PartyMemberPetFrame (64x23 at the member's 23,-43) with
-- the classic art on it: the party art at half size at 0,-1, the
-- 18px portrait at 3,-3, the name above and a 35x4 health bar at 23,-6.
local CLASSIC_PET = {
	width = 64, height = 23,
	portraitSize = 18, portraitX = 3, portraitY = -3,
	barWidth = 35, barHeight = 4, barX = 23, barY = -6,
	nameX = 25, nameY = 21,
	x = 23, y = -43,
}

function Group:CreateClassicPartyPet(index)
	local frame = makeUnitButton("SquawkClassicUF_PartyPetClassic" .. index, "partypet" .. index)
	frame:SetSize(CLASSIC_PET.width, CLASSIC_PET.height)
	frame.isPet = true

	frame.Portrait = frame:CreateTexture(nil, "BORDER")
	frame.Portrait:SetSize(CLASSIC_PET.portraitSize, CLASSIC_PET.portraitSize)
	frame.Portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", CLASSIC_PET.portraitX, CLASSIC_PET.portraitY)

	frame.Health = createBar(frame, CLASSIC_PET.barWidth, CLASSIC_PET.barHeight)
	frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", CLASSIC_PET.barX, CLASSIC_PET.barY)

	frame.ArtFrame = CreateFrame("Frame", nil, frame)
	frame.ArtFrame:SetAllPoints(frame)
	frame.ArtFrame:SetFrameLevel(frame:GetFrameLevel() + 3)

	frame.Art = frame.ArtFrame:CreateTexture(nil, "ARTWORK")
	frame.Art:SetTexture(Art.partyFrame)
	frame.Art:SetSize(64, 32)
	frame.Art:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -1)

	frame.Name = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Name:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CLASSIC_PET.nameX, CLASSIC_PET.nameY)
	frame.Name:SetJustifyH("LEFT")
	pcall(frame.Name.SetWordWrap, frame.Name, false)

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

	CUF:CreateRaidTargetIcon(frame, frame.Overlay, 14)
	frame.RaidIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)

	CUF:AttachTooltip(frame)
	registerEvents(frame)
	return frame
end

function Group:CreateRaidFrame(index)
	return Group:CreateCompactFrame("SquawkClassicUF_Raid" .. index, "raid" .. index)
end

-- Classic hung a small pet bar off each party member; this one sits to the
-- right of the frame so it never collides with the next member below.
local PARTY_PET = { width = 70, height = 16, x = 2, y = -10 }

function Group:CreatePetFrame(name, unit)
	local frame = Group:CreateCompactFrame(name, unit)
	frame.isPet = true
	return frame
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
	local classicPets = settings.showPetFrames and (settings.petStyle or "classic") == "classic"
	local step = PARTY.height + settings.spacing + (classicPets and PARTY.petSpacing or 0)
	for index, frame in ipairs(Group.party) do
		frame:SetScale(settings.scale or 1)
		anchorTo(frame, settings, 0, -(index - 1) * step)
	end
	for index, pet in ipairs(Group.partyPets) do
		pet:SetScale(settings.scale or 1)
		pet:SetSize(PARTY_PET.width, PARTY_PET.height)
		pet.Health:SetSize(PARTY_PET.width - 4, PARTY_PET.height - 4)
		pet:ClearAllPoints()
		pet:SetPoint("TOPLEFT", Group.party[index], "TOPRIGHT", PARTY_PET.x, PARTY_PET.y)
	end
	-- the classic pet hangs off its owner, so it follows the owner's scale
	for index, pet in ipairs(Group.partyClassicPets) do
		pet:SetScale(1)
		pet:ClearAllPoints()
		pet:SetPoint("TOPLEFT", Group.party[index], "TOPLEFT", CLASSIC_PET.x, CLASSIC_PET.y)
	end
end

-- Pets that exist right now go first so the block has no holes.  A pet
-- summoned mid-combat still shows (the unit watch is secure), just in the
-- slot it was given at the last out-of-combat layout.
local function petOrder(frames)
	local present, absent = {}, {}
	for _, frame in ipairs(frames) do
		if UnitExists(frame.unit) then
			present[#present + 1] = frame
		else
			absent[#absent + 1] = frame
		end
	end
	for _, frame in ipairs(absent) do present[#present + 1] = frame end
	return present
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

	-- pets stack under the members
	local offset = slot * (size.height + size.spacing)
	local height = petHeight(size)
	local index = 0
	for _, frame in ipairs(petOrder(Group.partyCompactPets)) do
		if frame.unit ~= "pet" or settings.includePlayer then
			frame:SetScale(settings.scale or 1)
			frame:SetSize(size.width, height)
			frame.Health:SetSize(size.width - 4, height - 4)
			anchorTo(frame, settings, 0, -(offset + index * (height + size.spacing)))
			index = index + 1
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

	-- Pets get their own columns to the right of the last occupied one.
	local firstColumn = 0
	for index = 1, 40 do
		if UnitExists("raid" .. index) then
			local slot = slots[index] or { column = math.floor((index - 1) / settings.perColumn) }
			firstColumn = math.max(firstColumn, slot.column + 1)
		end
	end
	local height = petHeight(settings)
	local perColumn = settings.perColumn * 2   -- half-height boxes, same column height
	for position, frame in ipairs(petOrder(Group.raidPets)) do
		local column = firstColumn + math.floor((position - 1) / perColumn)
		local row = (position - 1) % perColumn
		frame:SetScale(settings.scale or 1)
		frame:SetSize(settings.width, height)
		frame.Health:SetSize(settings.width - 4, height - 4)
		anchorTo(frame, settings,
			column * (settings.width + settings.spacing),
			-row * (height + settings.spacing))
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

	local raidVisible = CUF.db.raid.enabled and (inRaid or not CUF.db.raid.showOnlyInRaid)
	for _, frame in ipairs(Group.raid) do
		if raidVisible then
			RegisterUnitWatch(frame)
		else
			UnregisterUnitWatch(frame)
			frame:Hide()
		end
	end

	local function watch(frame, wanted)
		if wanted then
			RegisterUnitWatch(frame)
		else
			UnregisterUnitWatch(frame)
			frame:Hide()
		end
	end
	local partyPets = CUF.db.party.showPetFrames
	local classicPets = (CUF.db.party.petStyle or "classic") == "classic"
	for _, frame in ipairs(Group.partyPets) do
		watch(frame, classicStyle and partyPets and not classicPets)
	end
	for _, frame in ipairs(Group.partyClassicPets) do
		watch(frame, classicStyle and partyPets and classicPets)
	end
	for _, frame in ipairs(Group.partyCompactPets) do
		local wanted = boxStyle and inGroup and partyPets
		if frame.unit == "pet" then wanted = wanted and CUF.db.party.includePlayer end
		watch(frame, wanted)
	end
	for _, frame in ipairs(Group.raidPets) do
		watch(frame, raidVisible and CUF.db.raid.showPets)
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
	for _, frame in ipairs(Group.partyPets) do updateRange(frame) end
	for _, frame in ipairs(Group.partyClassicPets) do updateRange(frame) end
	for _, frame in ipairs(Group.partyCompactPets) do updateRange(frame) end
	for _, frame in ipairs(Group.raidPets) do updateRange(frame) end
end

-- every group frame, members and pets
function Group:AllFrames()
	local all = {}
	for _, list in ipairs({ Group.party, Group.partyCompact, Group.raid,
		Group.partyPets, Group.partyClassicPets, Group.partyCompactPets, Group.raidPets }) do
		for _, frame in ipairs(list) do all[#all + 1] = frame end
	end
	return all
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
		-- Pets are built whatever the option says, for the same reason.
		for index = 1, 4 do
			Group.partyPets[index] = Group:CreatePetFrame("SquawkClassicUF_PartyPet" .. index, "partypet" .. index)
			Group.partyClassicPets[index] = Group:CreateClassicPartyPet(index)
		end
		for index, unit in ipairs({ "pet", "partypet1", "partypet2", "partypet3", "partypet4" }) do
			Group.partyCompactPets[index] = Group:CreatePetFrame("SquawkClassicUF_PartyBoxPet" .. index, unit)
		end
	end
	if CUF.db.raid.enabled then
		for index = 1, 40 do
			Group.raid[index] = Group:CreateRaidFrame(index)
		end
		for index = 1, 40 do
			Group.raidPets[index] = Group:CreatePetFrame("SquawkClassicUF_RaidPet" .. index, "raidpet" .. index)
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
	-- A pet summoned, dismissed or killed: the pet frame's unit now points at
	-- a different creature, and the pet slots need re-packing.
	watcher:RegisterEvent("UNIT_PET")
	watcher:SetScript("OnEvent", function()
		for _, frame in ipairs(Group:AllFrames()) do updateFrame(frame) end
		CUF:RunProtected(function()
			Group:LayoutPartyCompact()
			Group:LayoutRaid()
			Group:UpdateVisibility()
			for _, frame in ipairs(Group:AllFrames()) do updateFrame(frame) end
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
		for _, list in ipairs({ Group.partyPets, Group.partyCompactPets, Group.raidPets }) do
			for _, frame in ipairs(list) do
				frame.Health:SetStatusBarTexture(CUF:RaidBarTexture())
				updateFrame(frame)
			end
		end
		for _, frame in ipairs(Group.partyClassicPets) do
			frame.Health:SetStatusBarTexture(CUF:BarTexture())
			updateFrame(frame)
		end
	end)
end
