--[[ Squawk ClassicUF for WoW: Forever

	Forever renders Classic content through the Midnight (12.x) UI, so the unit
	frames look like retail.  This rebuilds them in the 1.12 style using the
	Classic art that still ships in the client, at the original geometry taken
	from Blizzard's own Classic FrameXML.

	Two Midnight rules shape the implementation:

	  * Health and power are *secret values*.  They can be handed straight to
	    StatusBar:SetValue and SetMinMaxValues, which is how the bars work, but
	    they cannot be compared, divided or printed.  Every text read goes
	    through SafeNumber, which yields "" rather than throwing.
	  * Frames that target a unit must be secure buttons, and a protected frame
	    cannot be moved, shown or hidden in combat.  Layout changes queue until
	    PLAYER_REGEN_ENABLED.
]]

local ADDON = ...

SquawkClassicUF = {}
local CUF = SquawkClassicUF

CUF.Version = "1.0.0"

-- ---------------------------------------------------------------------------
-- Classic art, paths and geometry straight from Blizzard's Classic FrameXML
-- ---------------------------------------------------------------------------

CUF.Art = {
	frame        = "Interface\\TargetingFrame\\UI-TargetingFrame",
	flash        = "Interface\\TargetingFrame\\UI-TargetingFrame-Flash",
	statusBar    = "Interface\\TargetingFrame\\UI-StatusBar",
	levelBg      = "Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground",
	partyFrame   = "Interface\\TargetingFrame\\UI-PartyFrame",
	totFrame     = "Interface\\TargetingFrame\\UI-TargetofTargetFrame",
	smallFrame   = "Interface\\TargetingFrame\\UI-SmallTargetingFrame",
	elite        = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
	rareElite   = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
	rare        = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
	pvpAlliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
	pvpHorde    = "Interface\\TargetingFrame\\UI-PVP-Horde",
	pvpFFA      = "Interface\\TargetingFrame\\UI-PVP-FFA",
	castFill     = "Interface\\CastingBar\\UI-CastingBar-Fill",
	castBorder   = "Interface\\CastingBar\\UI-CastingBar-Border",
	playerStatus = "Interface\\CharacterFrame\\UI-Player-Status",
	flat         = "Interface\\Buttons\\WHITE8X8",
}

-- UI-TargetingFrame drawn for the player is the target art flipped, which is
-- what the mirrored left/right texture coordinates below do.
CUF.Geometry = {
	frameWidth = 232, frameHeight = 100,
	artWidth = 193, artHeight = 77,
	playerArtCoords = { 0.85546875, 0.1015625, 0.0625, 0.6640625 },
	-- Blizzard's own note: the target's size, anchor and coords are chosen so
	-- the larger Elite texture drops straight in without moving anything.
	targetArtWidth = 230, targetArtHeight = 99,
	targetArtX = 18.5, targetArtY = -4,
	targetArtCoords = { 0.1015625, 1.0, 0.0078125, 0.78125 },
	pvpIconSize = 64, pvpIconX = 2, pvpIconY = -24, pvpIconMirroredX = 19,
	-- Blizzard's XML says 35.25, 30 but re-anchors the level in code, and this
	-- client's art does not land on the same pixel.  Measured against the
	-- circle in a screenshot: interior x 27-47, y 80-97, so its middle is
	-- 38, 31 from the frame's bottom-left corner.
	levelX = 38, levelY = 31,
	portraitSize = 64,
	portraitOffsetX = 24, portraitOffsetY = -16,
	barWidth = 119, barHeight = 12,
	healthOffsetX = 90, healthOffsetY = -45,
	manaOffsetX = 90, manaOffsetY = -56,
	backdropWidth = 119, backdropHeight = 41,
	backdropOffsetX = 89.5, backdropOffsetY = -26,
}

CUF.PowerColors = {
	[0] = { 0.00, 0.00, 1.00 },  -- mana
	[1] = { 1.00, 0.00, 0.00 },  -- rage
	[2] = { 1.00, 0.50, 0.25 },  -- focus
	[3] = { 1.00, 1.00, 0.00 },  -- energy
	[6] = { 0.00, 0.82, 1.00 },  -- runic power
}

CUF.ClassColors = {
	WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 },
	HUNTER  = { 0.67, 0.83, 0.45 }, ROGUE   = { 1.00, 0.96, 0.41 },
	PRIEST  = { 1.00, 1.00, 1.00 }, SHAMAN  = { 0.00, 0.44, 0.87 },
	MAGE    = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 },
	DRUID   = { 1.00, 0.49, 0.04 },
}

-- ---------------------------------------------------------------------------
-- Secret-value helpers
-- ---------------------------------------------------------------------------

-- Reading a secret throws, so every numeric read for *text* comes through
-- here.  Bars never use this: they pass the secret straight to SetValue.
function CUF.SafeNumber(value)
	local ok, result = pcall(function() return value + 0 end)
	if ok and type(result) == "number" then return result end
	return nil
end

function CUF.SafeFormat(fmt, ...)
	local ok, text = pcall(string.format, fmt, ...)
	if ok then return text end
	return ""
end

-- "18420", "18420 / 21500", "85%" or "" when the client is hiding the numbers.
-- Every read, comparison and division happens inside the pcall, because any
-- one of them throws if the value turned out to be secret after all.
local function barText(current, maximum, mode)
	if mode == "none" then return "" end
	local ok, text = pcall(function()
		local now, top = current + 0, maximum + 0
		if top <= 0 then return "" end
		if mode == "percent" then
			return string.format("%d%%", math.floor(now / top * 100 + 0.5))
		elseif mode == "current" then
			return string.format("%d", now)
		end
		return string.format("%d / %d", now, top)
	end)
	if ok and type(text) == "string" then return text end
	return ""
end

function CUF.HealthText(unit, mode)
	return barText(UnitHealth(unit), UnitHealthMax(unit), mode)
end

function CUF.PowerText(unit, mode)
	return barText(UnitPower(unit), UnitPowerMax(unit), mode)
end

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

local function copy(t)
	local n = {}
	for k, v in pairs(t) do
		if type(v) == "table" then n[k] = copy(v) else n[k] = v end
	end
	return n
end

local function fill(target, source)
	for k, v in pairs(source) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then target[k] = {} end
			fill(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
	return target
end

CUF.Defaults = {
	enabled = true,
	hideBlizzard = true,
	locked = true,

	tooltips = true,
	tooltipAnchor = "default",      -- default | frame | cursor
	hideTooltipsInCombat = false,
	tooltipGuild = true,

	levelStyle = "classic",         -- classic (in the circle) | centered
	levelNudgeX = 0,                -- fine-tune the circle position
	levelNudgeY = 0,

	classColorHealth = false,
	healthText = "currentmax",     -- none | current | currentmax | percent
	powerText = "none",
	showLevel = true,
	showPortraits = true,
	showRestIcon = true,
	barTexture = "classic",        -- classic | flat
	fontSize = 10,

	units = {
		player = { enabled = true, scale = 1.0, x = -220, y = -180, point = "TOP" },
		target = { enabled = true, scale = 1.0, x = 220,  y = -180, point = "TOP" },
		targettarget = { enabled = true, scale = 1.0, x = 390, y = -210, point = "TOP" },
		focus  = { enabled = true, scale = 1.0, x = -420, y = -300, point = "TOP" },
		pet    = { enabled = true, scale = 1.0, x = -250, y = -272, point = "TOP" },
	},

	party = {
		enabled = true, scale = 1.0, x = 20, y = -220, point = "TOPLEFT",
		spacing = 12, showPets = false, showInRaid = false,
		useRaidStyle = false,   -- draw the party as raid-style boxes
		includePlayer = false,  -- and put yourself in with them
	},

	raid = {
		enabled = true, scale = 1.0, x = 20, y = -300, point = "TOPLEFT",
		width = 76, height = 36, spacing = 3, perColumn = 5, columns = 8,
		groupByGroup = true, showOnlyInRaid = true, showNames = true,
		texture = "classic",
		rangeCheck = true,          -- fade whoever is out of range
		rangeAlpha = 0.45,
		showMissingBuffs = true,    -- buffs you could cast that are missing
		showDispellable = true,     -- debuffs you could remove
		watchOptionalBuffs = false, -- Divine Spirit, Thorns, Battle Shout
	},

	targetAuras = {
		enabled = true,
		buffs = 8,                  -- Classic showed up to 16; 8 is tidier
		debuffs = 8,
		size = 21,
		perRow = 8,

		-- buffs and debuffs are placed independently; "gap" is distance from
		-- the frame in whichever direction the anchor points
		buffAnchor = "below", buffOffsetX = 5, buffGap = 2,
		debuffAnchor = "below", debuffOffsetX = 5, debuffGap = 2,
	},

	actionBars = {
		enabled = true,
		showHotkeys = true,
		showMacroNames = true,
	},

	castbar = {
		enabled = true, scale = 1.0,
		style = "quartz",           -- quartz | classic
		width = 200, height = 18,
		showLatency = true,         -- shade the end of the bar by your latency
		showTotal = false,          -- "1.2 / 2.5" instead of "1.2"
		showTarget = true, showIcon = true, showTime = true,
		x = 0, y = 190, point = "BOTTOM",

		-- the target's bar has its own size, and by default hangs off the
		-- target frame rather than sitting at a fixed spot on screen
		targetAttached = true,
		targetWidth = 200, targetHeight = 16,
		targetAnchor = "below",     -- below | above the target frame
		targetOffsetX = 0,
		targetGap = 8,
	},
}

function CUF:InitDatabase()
	local snapshots = SquawkClassicUF_Restore
	SquawkClassicUF_Restore = nil

	local live = (type(SquawkClassicUFDB) == "table") and SquawkClassicUFDB or nil
	SquawkClassicUFDB = live or {}
	SquawkClassicUFDB.profiles = SquawkClassicUFDB.profiles or {}

	if not live and type(snapshots) == "table" then
		for _, snap in ipairs(snapshots) do
			for key, profile in pairs((type(snap) == "table" and snap.profiles) or {}) do
				if not SquawkClassicUFDB.profiles[key] then SquawkClassicUFDB.profiles[key] = profile end
			end
		end
	end
	-- Carried over from the old ClassicUF name: adopt any profile that has no
	-- counterpart yet, so renaming the addon costs nothing.
	local legacy = SquawkClassicUF_Legacy
	SquawkClassicUF_Legacy = nil
	if type(legacy) == "table" then
		local adopted = 0
		for _, snap in ipairs(legacy) do
			for key, profile in pairs((type(snap) == "table" and snap.profiles) or {}) do
				if not SquawkClassicUFDB.profiles[key] then
					SquawkClassicUFDB.profiles[key] = profile
					adopted = adopted + 1
				end
			end
		end
		CUF.AdoptedProfiles = adopted
	end

	CUF.ClientRestoredSV = live ~= nil

	local key = (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
	CUF.ProfileKey = key
	SquawkClassicUFDB.profiles[key] = SquawkClassicUFDB.profiles[key] or {}
	CUF.db = fill(SquawkClassicUFDB.profiles[key], copy(CUF.Defaults))

	-- The level briefly defaulted to sitting under the name; that value is
	-- already saved in existing profiles, so move it back to the circle once.
	if not CUF.db.levelStyleMigrated then
		CUF.db.levelStyleMigrated = true
		CUF.db.levelStyle = "classic"
	end

	-- Buffs and debuffs used to share one anchor and offset; split them.
	local auras = CUF.db.targetAuras
	if auras.anchor then
		auras.buffAnchor, auras.debuffAnchor = auras.anchor, auras.anchor
		auras.buffOffsetX = auras.offsetX or auras.buffOffsetX
		auras.debuffOffsetX = auras.offsetX or auras.debuffOffsetX
		local gap = math.abs(auras.offsetY or -2)
		auras.buffGap, auras.debuffGap = gap, gap
		auras.anchor, auras.offsetX, auras.offsetY = nil, nil, nil
	end
	-- Cast bars were Classic-sized before the Quartz style arrived; resize
	-- existing profiles once so the new look is not squeezed into old numbers.
	if not CUF.db.castbarStyleMigrated then
		CUF.db.castbarStyleMigrated = true
		if CUF.db.castbar.width == 195 then CUF.db.castbar.width = 200 end
		if CUF.db.castbar.height == 13 then CUF.db.castbar.height = 18 end
		if CUF.db.castbar.targetWidth == 150 then CUF.db.castbar.targetWidth = 200 end
		if CUF.db.castbar.targetHeight == 12 then CUF.db.castbar.targetHeight = 16 end
	end

	if CUF.db.castbar.targetOffsetY then
		CUF.db.castbar.targetGap = math.abs(CUF.db.castbar.targetOffsetY)
		CUF.db.castbar.targetOffsetY = nil
	end
end

function CUF:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Squawk ClassicUF:|r " .. tostring(msg))
end

CUF.RaidTextures = {
	{ "classic", "Classic", "Interface\\TargetingFrame\\UI-StatusBar" },
	{ "raid",    "Blizzard raid", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
	{ "flat",    "Flat", "Interface\\Buttons\\WHITE8X8" },
	{ "tooltip", "Parchment", "Interface\\Tooltips\\UI-Tooltip-Background" },
}

function CUF:RaidBarTexture()
	local wanted = CUF.db.raid.texture or "classic"
	for _, entry in ipairs(CUF.RaidTextures) do
		if entry[1] == wanted then return entry[3] end
	end
	return CUF.RaidTextures[1][3]
end

function CUF:BarTexture()
	return CUF.db.barTexture == "flat" and CUF.Art.flat or CUF.Art.statusBar
end

-- ---------------------------------------------------------------------------
-- Does this client actually ship a texture?
--
-- SetTexture never fails, so a missing file looks identical to a working one
-- until you see the blank on screen.  GetTextureFileID resolves the path and
-- returns nil when there is nothing behind it.
-- ---------------------------------------------------------------------------

local probe
function CUF:TextureExists(path)
	if not path then return false end
	if not probe then probe = UIParent:CreateTexture(nil, "BACKGROUND") probe:Hide() end

	local ok = pcall(probe.SetTexture, probe, path)
	if not ok then return false end

	if probe.GetTextureFileID then
		local id = probe:GetTextureFileID()
		probe:SetTexture(nil)
		return id ~= nil
	end

	local set = probe:GetTexture()
	probe:SetTexture(nil)
	return set ~= nil
end

-- ---------------------------------------------------------------------------
-- Unit tooltips
--
-- Shared by every frame that represents a unit, so hovering one behaves the
-- way hovering Blizzard's did.
-- ---------------------------------------------------------------------------

CUF.TooltipAnchors = {
	{ "default", "Default corner" },
	{ "frame",   "Beside the frame" },
	{ "cursor",  "At the cursor" },
}

function CUF:AttachTooltip(frame)
	frame:SetScript("OnEnter", function(self)
		if not CUF.db.tooltips then return end
		if CUF.db.hideTooltipsInCombat and InCombatLockdown() then return end

		local unit = self.unit
		if not unit or not UnitExists(unit) then return end

		local anchor = CUF.db.tooltipAnchor
		if anchor == "frame" then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		elseif anchor == "cursor" then
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		elseif type(GameTooltip_SetDefaultAnchor) == "function" then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
		else
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		end

		-- SetUnit can refuse on a restricted client; a missing tooltip is
		-- better than an error every time the cursor crosses a frame.
		if pcall(GameTooltip.SetUnit, GameTooltip, unit) then
			CUF:AddGuildLine(unit)
			GameTooltip:Show()
		else
			GameTooltip:Hide()
		end
	end)

	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- Blizzard's unit tooltip usually carries the guild itself, but not on every
-- unit or every build, so add it when it is genuinely absent rather than
-- printing it twice.
function CUF:AddGuildLine(unit)
	if not CUF.db.tooltipGuild or not UnitIsPlayer(unit) then return end
	if type(GetGuildInfo) ~= "function" then return end

	local ok, guild, rank = pcall(GetGuildInfo, unit)
	if not ok or type(guild) ~= "string" or guild == "" then return end

	for i = 1, GameTooltip:NumLines() do
		local line = _G["GameTooltipTextLeft" .. i]
		local text = line and line:GetText()
		if text and text:find(guild, 1, true) then return end
	end

	if type(rank) == "string" and rank ~= "" then
		GameTooltip:AddLine(("<%s>  %s"):format(guild, rank), 0.4, 0.9, 0.4, 1)
	else
		GameTooltip:AddLine(("<%s>"):format(guild), 0.4, 0.9, 0.4, 1)
	end
end

-- ---------------------------------------------------------------------------
-- Combat-safe work queue.  Protected frames refuse to move, show or hide while
-- the player is in combat, so anything layout related queues here.
-- ---------------------------------------------------------------------------

local queue = {}

function CUF:RunProtected(fn)
	if InCombatLockdown() then
		queue[#queue + 1] = fn
	else
		local ok, err = pcall(fn)
		if not ok then CUF:Print("|cffff0000error:|r " .. tostring(err)) end
	end
end

local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function()
	local pending = queue
	queue = {}
	for _, fn in ipairs(pending) do pcall(fn) end
end)

-- ---------------------------------------------------------------------------
-- Getting Blizzard's frames out of the way
-- ---------------------------------------------------------------------------

local hider = CreateFrame("Frame", "SquawkClassicUF_Hidden", UIParent)
hider:Hide()
CUF.Hider = hider

local hidden = {}

function CUF:HideBlizzardFrame(frame)
	if not frame or hidden[frame] then return end
	hidden[frame] = true
	pcall(function()
		frame:UnregisterAllEvents()
		frame:Hide()
		frame:SetParent(hider)
	end)
end

function CUF:HideBlizzardFrames()
	if not CUF.db.hideBlizzard then return end
	CUF:RunProtected(function()
		CUF:HideBlizzardFrame(_G.PlayerFrame)
		CUF:HideBlizzardFrame(_G.TargetFrame)
		CUF:HideBlizzardFrame(_G.FocusFrame)
		CUF:HideBlizzardFrame(_G.PetFrame)
		CUF:HideBlizzardFrame(_G.TargetFrameToT)
		for i = 1, 4 do
			CUF:HideBlizzardFrame(_G["PartyMemberFrame" .. i])
			CUF:HideBlizzardFrame(_G["CompactPartyFrameMember" .. i])
		end
		if _G.PartyFrame then CUF:HideBlizzardFrame(_G.PartyFrame) end
		if CUF.db.raid.enabled and _G.CompactRaidFrameContainer then
			CUF:HideBlizzardFrame(_G.CompactRaidFrameContainer)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Art check.  We cannot ask the client whether a texture file exists, so this
-- puts the candidates on screen and lets the eye decide.
-- ---------------------------------------------------------------------------

function CUF:ShowArtCheck()
	local f = CUF.ArtFrame
	if not f then
		f = CreateFrame("Frame", "SquawkClassicUF_ArtCheck", UIParent, "BackdropTemplate")
		CUF.ArtFrame = f
		f:SetSize(560, 350)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:EnableMouse(true)
		f:SetMovable(true)
		f:SetScript("OnMouseDown", function(self) self:StartMoving() end)
		f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16,
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		f:SetBackdropColor(0, 0, 0, 0.9)

		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", f, "TOP", 0, -12)
		title:SetText("Classic art check - anything blank or green is missing from this client")

		local y = -40
		for _, name in ipairs({ "frame", "statusBar", "partyFrame", "totFrame", "smallFrame", "castFill", "castBorder" }) do
			local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			label:SetPoint("TOPLEFT", f, "TOPLEFT", 16, y - 14)
			label:SetText(name .. ":")
			label:SetWidth(90)
			label:SetJustifyH("LEFT")

			local tex = f:CreateTexture(nil, "ARTWORK")
			tex:SetTexture(CUF.Art[name])
			tex:SetPoint("TOPLEFT", f, "TOPLEFT", 110, y)
			tex:SetSize(200, 40)

			local path = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			path:SetPoint("TOPLEFT", f, "TOPLEFT", 320, y - 14)
			path:SetText((CUF:TextureExists(CUF.Art[name])
				and "|cff00ff00present|r  " or "|cffff0000MISSING|r  ")
				.. CUF.Art[name]:gsub("Interface\\", ""))
			path:SetWidth(230)
			path:SetJustifyH("LEFT")
			y = y - 44
		end

		local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		close:SetSize(80, 22)
		close:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
		close:SetText("Close")
		close:SetScript("OnClick", function() f:Hide() end)
	end
	f:Show()
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

-- What this client offers for timer bars, and what the last cast actually did.
function CUF:CastDiagnostics()
	CUF:Print("---- cast bar ----")
	CUF:Print(("UnitCastingDuration: %s   UnitChannelDuration: %s"):format(
		type(_G.UnitCastingDuration) == "function" and "|cff00ff00yes|r" or "|cffff0000no|r",
		type(_G.UnitChannelDuration) == "function" and "|cff00ff00yes|r" or "|cffff0000no|r"))

	local probe = CreateFrame("StatusBar")
	CUF:Print(("StatusBar:SetTimerDuration: %s   reverse fill constant: %s"):format(
		probe.SetTimerDuration and "|cff00ff00yes|r" or "|cffff0000no|r",
		CUF.GetReverseFillName() or "|cffff0000none found|r - channels drain from the remaining time instead"))

	CUF:Print(("cast bar option: %s, target bar option: %s"):format(
		CUF.db.castbar.enabled and "|cff00ff00on|r" or "|cffff0000OFF - no bars are created|r",
		CUF.db.castbar.showTarget and "|cff00ff00on|r" or "|cffff0000off|r"))
	CUF:Print(("cast art: fill %s, border %s"):format(
		CUF:TextureExists(CUF.Art.castFill) and "|cff00ff00present|r" or "|cffff0000MISSING|r",
		CUF:TextureExists(CUF.Art.castBorder) and "|cff00ff00present|r" or "|cffff0000MISSING|r"))

	for key, frame in pairs(CUF.Cast.bars or {}) do
		local now = frame.engineTimed and "engine timed"
			or (frame.startTime and "manually timed" or "idle")
		CUF:Print(("%s bar: %s, %dx%d at %d,%d, now %s"):format(
			key,
			frame:IsShown() and "|cff00ff00shown|r" or "hidden",
			frame:GetWidth(), frame:GetHeight(),
			frame:GetLeft() or -1, frame:GetTop() or -1,
			now))
		CUF:Print(("   last cast used %s (%s)"):format(
			frame.lastPath == "static" and "|cffff0000static|r"
				or ("|cff00ff00" .. (frame.lastPath or "nothing yet") .. "|r"),
			frame.attachNote or "nothing cast yet"))
	end

	if UnitExists("target") then
		local ok, name = pcall(UnitCastingInfo, "target")
		local ok2, channel = pcall(UnitChannelInfo, "target")
		CUF:Print(("target is casting: %s / channelling: %s"):format(
			(ok and name) and name or "nothing", (ok2 and channel) and channel or "nothing"))
	end
	CUF:Print("cast something, then run this again to see which path it took.")
end

function CUF:ApplyAll()
	CUF.Units:UpdateAll()
	CUF.Group:UpdateAll()
	CUF.Cast:ApplySettings()
	CUF.ActionBars:ApplySettings()
end

local function handleSlash(msg)
	local cmd, rest = (msg or ""):lower():match("^(%S*)%s*(.*)$")

	if cmd == "" or cmd == "config" or cmd == "options" then
		CUF.Options:Open()
	elseif cmd == "unlock" then
		CUF.db.locked = false
		CUF:SetLocked(false)
		CUF:Print("frames unlocked - drag them into place, then /cuf lock")
	elseif cmd == "lock" then
		CUF.db.locked = true
		CUF:SetLocked(true)
		CUF:Print("frames locked")
	elseif cmd == "art" then
		CUF:ShowArtCheck()
	elseif cmd == "castdiag" or cmd == "cast" then
		CUF:CastDiagnostics()
	elseif cmd == "auradiag" or cmd == "auras" then
		CUF.Auras:Diagnostics()
	elseif cmd == "casttest" then
		CUF.Cast:Test()
	elseif cmd == "bars" then
		CUF.ActionBars:SkinAll()
		CUF.ActionBars:Diagnostics()
	elseif cmd == "reset" then
		SquawkClassicUFDB.profiles[CUF.ProfileKey] = {}
		CUF.db = fill(SquawkClassicUFDB.profiles[CUF.ProfileKey], copy(CUF.Defaults))
		CUF:RunProtected(function() CUF:ApplyAll() end)
		CUF:Print("settings reset to defaults")
	elseif cmd == "scale" and tonumber(rest) then
		local scale = math.max(0.5, math.min(2, tonumber(rest)))
		for _, settings in pairs(CUF.db.units) do settings.scale = scale end
		CUF.db.party.scale = scale
		CUF.db.raid.scale = scale
		CUF:RunProtected(function() CUF:ApplyAll() end)
		CUF:Print("scale set to " .. scale)
	else
		CUF:Print("/cuf | unlock | lock | scale <0.5-2> | art | bars | castdiag | casttest | auradiag | reset")
	end
end

SLASH_SQUAWKCLASSICUF1 = "/cuf"
SLASH_SQUAWKCLASSICUF2 = "/squawk"
SLASH_SQUAWKCLASSICUF3 = "/scuf"
SLASH_SQUAWKCLASSICUF4 = "/classicuf"
SlashCmdList["SQUAWKCLASSICUF"] = handleSlash

function CUF:SetLocked(locked)
	for _, frame in pairs(CUF.MovableFrames or {}) do
		if frame.SetMovableState then frame:SetMovableState(not locked) end
	end
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
	CUF:InitDatabase()
	if not CUF.db.enabled then
		CUF:Print("disabled - /cuf config to turn it back on")
		return
	end

	for _, module in ipairs({ "Units", "Group", "Cast", "ActionBars", "Options" }) do
		local ok, err = pcall(function() CUF[module]:Initialize() end)
		if not ok then CUF:Print(("|cffff0000%s failed:|r %s"):format(module, tostring(err))) end
	end

	CUF:HideBlizzardFrames()
	CUF:SetLocked(CUF.db.locked)
	if (CUF.AdoptedProfiles or 0) > 0 then
		CUF:Print(("carried over %d saved profile(s) from the old ClassicUF name.")
			:format(CUF.AdoptedProfiles))
	end
	CUF:Print(("loaded. |cffffd100/squawk|r for options, |cffffd100/squawk unlock|r to move frames.%s")
		:format(CUF.ClientRestoredSV and "" or " Settings are restored by the SavedVariables shim."))
end)
