--[[ Player, target, target-of-target, focus and pet frames.

	The finishing touches restore the vanilla frames in full: round
	portraits, the reaction-coloured plate behind a target's name, the level
	in its difficulty colour (a skull when it is unknown), the "minus" frame
	for trivial mobs, the player's pulsing rest / combat glow with the vanilla
	Zzz and crossed-swords icons, the leader crown, the raid group plate and
	combo points down the side of the target's portrait.

	Positions come from vanilla's XML.  Our art is cropped and centred rather
	than drawn from the frame's corner, so a vanilla offset (x, y) from the
	player frame's top-left lands at (x - 17.5, y + 3.5) here, and the target
	frame is its mirror image, measured from the top-right.
]]

local CUF = SquawkClassicUF
local Units = {}
CUF.Units = Units

local G = CUF.Geometry
local Art = CUF.Art

-- Every position below lays the classic art onto Blizzard's own 232x100
-- PlayerFrame / TargetFrame geometry.  Our frames are the same size: the art
-- hangs 19px left of the player frame and 20px right of the target frame,
-- 4px down.
local GEO = {
	player = {
		art = { x = -19, y = -4, coords = { 1, 0.09375, 0, 0.78125 } },
		flash = { w = 242, h = 93, x = -6, y = -4, coords = { 0.9453125, 0, 0, 0.181640625 } },
		status = { x = 16, y = -12 },
		backdrop = { x = 87, y = -26 },
		health = { x = 87, y = -45 },
		power = { x = 87, y = -56 },
		portrait = { x = 23, y = -16 },
		name = { x = 97, y = -30 },            -- TOPLEFT, 100 wide, centred
		level = { x = -81, y = -21 },          -- from the frame's centre
		leader = { x = 21, y = -16 },
		group = { x = 78, y = -24 },           -- plate's BOTTOMLEFT to the frame's TOPLEFT
		pvp = { Alliance = { 8, -24 }, Horde = { -1, -22 } },
	},
	target = {
		art = { x = 20, y = -4, coords = { 0.09375, 1, 0, 0.78125 } },
		flash = { w = 242, h = 93, x = -4, y = -4, coords = { 0, 0.9453125, 0, 0.181640625 } },
		eliteFlash = { w = 242, h = 112, x = -2, y = 5, coords = { 0, 0.9453125, 0.181640625, 0.400390625 } },
		backdrop = { x = -86, y = -26 },       -- TOPRIGHT
		health = { x = -86, y = -45 },
		power = { x = -86, y = -56 },
		portrait = { x = -22, y = -16 },
		name = { x = -30, y = 15 },            -- centre, from the frame's centre
		level = { x = 81, y = -21 },
		raidIcon = { x = -53, y = -18 },       -- centre, from the frame's TOPRIGHT
		leader = { x = -24, y = -14 },
		quest = { x = -100, y = -16 },         -- TOPLEFT, from the frame's TOPRIGHT
		auras = { x = 25, y = -72 },           -- TOPLEFT: the art's bottom-left, 5 in, 32 up
		pvp = { Alliance = { -4, -24 }, Horde = { 3, -22 } },
	},
}
Units.GEO = GEO

Units.frames = {}
CUF.MovableFrames = CUF.MovableFrames or {}

-- ---------------------------------------------------------------------------
-- shared helpers
-- ---------------------------------------------------------------------------

-- The dragon around the portrait: gold for elites and world bosses, silver
-- for rares.  Same size and coords as the plain frame, which is what
-- Blizzard's geometry was picked to allow.
local CLASSIFICATION_ART = {
	worldboss = "elite",
	elite     = "elite",
	rareelite = "rareElite",
	rare      = "rare",
	minus     = "minus",
}

-- vanilla's resting / combat glow colours for PlayerStatusTexture
local REST_GLOW = { 1.0, 0.88, 0.25 }
local COMBAT_GLOW = { 1.0, 0.0, 0.0 }

-- The class name arrives as a secret string, and using one as a table key
-- throws just as comparing one does.  It has to be laundered before it can
-- look anything up.
local function unitClassColor(unit)
	if CUF.SafeFlag(UnitIsPlayer(unit)) == false then return nil end

	local _, raw = UnitClass(unit)
	local class = CUF.SafeText(raw)
	if not class then return nil end
	return CUF.ClassColors[class]
end

-- Vanilla drew every health bar the same flat green and put the reaction on
-- the plate behind the name instead; colouring NPC bars by reaction is an
-- option on top of that.
local function applyHealthColor(frame)
	local unit = frame.unit
	local green = CUF.HealthGreen

	if CUF.SafeFlag(UnitIsConnected(unit)) == false then
		frame.Health:SetStatusBarColor(0.5, 0.5, 0.5)
		return
	end

	local color = CUF.db.classColorHealth and unitClassColor(unit)
	if color then
		frame.Health:SetStatusBarColor(color[1], color[2], color[3])
		return
	end

	local npc = CUF.SafeFlag(UnitIsPlayer(unit)) == false
		and CUF.SafeFlag(UnitPlayerControlled(unit)) == false
	if CUF.db.reactionHealth and npc then
		local reaction = CUF.SafeNumber(UnitReaction(unit, "player"))
		if reaction and reaction <= 3 then
			frame.Health:SetStatusBarColor(1, 0, 0)
			return
		elseif reaction == 4 then
			frame.Health:SetStatusBarColor(1, 1, 0)
			return
		end
	end
	frame.Health:SetStatusBarColor(green[1], green[2], green[3])
end

-- Bars take the secret values straight from the API; nothing here reads them.
local function updateHealth(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) then return end
	frame.Health:SetMinMaxValues(0, UnitHealthMax(unit))
	frame.Health:SetValue(UnitHealth(unit))
	applyHealthColor(frame)
	if frame.HealthText then
		frame.HealthText:SetText(CUF.HealthText(unit, CUF.db.healthText))
	end
	if frame.Dead then
		frame.Dead:SetShown(UnitIsDeadOrGhost(unit) and true or false)
	end
end

local function updatePower(frame)
	local unit = frame.unit
	if not unit or not UnitExists(unit) or not frame.Power then return end
	frame.Power:SetMinMaxValues(0, UnitPowerMax(unit))
	frame.Power:SetValue(UnitPower(unit))
	local color = CUF.PowerColors[UnitPowerType(unit)] or CUF.PowerColors[0]
	frame.Power:SetStatusBarColor(color[1], color[2], color[3])
	if frame.PowerText then
		frame.PowerText:SetText(CUF.PowerText(unit, CUF.db.powerText))
	end
end

local function updateName(frame)
	local unit = frame.unit
	if not unit or not frame.Name then return end
	local name = UnitName(unit) or ""
	frame.Name:SetText(name)
	frame.Name:SetTextColor(1, 0.82, 0)

	if frame.Level then
		local level = CUF.SafeNumber(UnitLevel(unit))
		local known = level and level > 0
		local skull = CUF.db.showLevel and CUF.db.levelColors and frame.mirrored and not known
		if frame.Skull then frame.Skull:SetShown(skull and true or false) end

		if CUF.db.showLevel and not skull then
			frame.Level:SetText(known and tostring(level) or "??")
			-- a target's level in its difficulty colour, as vanilla did
			local r, g, b = 1, 0.82, 0
			if frame.mirrored and CUF.db.levelColors and known then
				local getter = _G.GetCreatureDifficultyColor or _G.GetQuestDifficultyColor
				local ok, color = pcall(getter, level)
				if ok and type(color) == "table" and color.r then
					r, g, b = color.r, color.g, color.b
				end
			end
			frame.Level:SetTextColor(r, g, b)
			frame.Level:Show()
		else
			frame.Level:Hide()
		end
	end

	if frame.NameBackground then
		local show = CUF.db.nameBackground and UnitExists(unit)
		frame.NameBackground:SetShown(show and true or false)
		if show then
			-- the colours can be secret; the texture takes them as they are
			local ok, r, g, b = pcall(UnitSelectionColor, unit)
			if not ok or not r or not pcall(frame.NameBackground.SetVertexColor, frame.NameBackground, r, g, b) then
				frame.NameBackground:SetVertexColor(0.5, 0.5, 0.5)
			end
		end
	end
end

-- Vanilla's portraits were circles.  The mask is the one Blizzard's own
-- frames use (TempPortraitAlphaMask), so the edge matches the frame art.
function Units:ApplyPortraitMask(frame)
	local portrait = frame.Portrait
	if not portrait or not portrait.AddMaskTexture then return end
	if not frame.PortraitMask then
		local ok, mask = pcall(frame.CreateMaskTexture, frame)
		if not ok or not mask then return end
		mask:SetTexture(Art.portraitMask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(portrait)
		frame.PortraitMask = mask
	end
	local wanted = CUF.db.roundPortraits and true or false
	if wanted ~= frame.portraitMasked then
		if wanted then
			pcall(portrait.AddMaskTexture, portrait, frame.PortraitMask)
		else
			pcall(portrait.RemoveMaskTexture, portrait, frame.PortraitMask)
		end
		frame.portraitMasked = wanted
	end
end

local function updatePortrait(frame)
	if not frame.Portrait then return end
	if not CUF.db.showPortraits then
		frame.Portrait:Hide()
		return
	end
	Units:ApplyPortraitMask(frame)
	frame.Portrait:Show()
	if UnitExists(frame.unit) then
		pcall(SetPortraitTexture, frame.Portrait, frame.unit)
	end
end

local function updateClassification(frame)
	if not frame.mirrored or not frame.Art then return end
	-- Same trap: the classification is a string from the client, so it cannot
	-- index the table until it has been laundered.
	local key = CLASSIFICATION_ART[CUF.SafeText(UnitClassification(frame.unit)) or ""]
	if key and not CUF:TextureExists(Art[key]) then key = nil end
	frame.Art:SetTexture(key and Art[key] or Art.frame)
	local coords = CUF.Geometry.targetArtCoords
	frame.Art:SetTexCoord(coords[1], coords[2], coords[3], coords[4])

	-- Trivial mobs get vanilla's short frame: no power bar, and the dark
	-- plate only behind the health bar.
	local minus = key == "minus"
	frame.haveElite = key ~= nil and key ~= "minus"
	if frame.Flash and frame.geo then
		Units:PlaceFlash(frame, key == "elite" or key == "rareElite")
	end
	if frame.Power then frame.Power:SetShown(not minus) end
	if frame.PowerText then frame.PowerText:SetShown(not minus) end
	-- the minus frame's backdrop is only the health bar (119x12 at -45)
	if frame.Backdrop and frame.geo then
		frame.Backdrop:ClearAllPoints()
		frame.Backdrop:SetHeight(minus and 12 or 41)
		frame.Backdrop:SetPoint("TOPRIGHT", frame, "TOPRIGHT",
			frame.geo.backdrop.x, minus and frame.geo.health.y or frame.geo.backdrop.y)
	end
end

-- Blizzard's own PvP flags.  They are atlases drawn at their own size, and
-- the spots below are for them:
-- the Alliance and Horde flags each have their own, the FFA flag stays where
-- Blizzard puts it.  A client without the atlases gets the classic 64x64
-- textures instead, placed where vanilla drew them on this art.
local PVP_ATLAS = {
	Alliance = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon",
	Horde    = "UI-HUD-UnitFrame-Player-PVP-HordeIcon",
	FFA      = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",
}
local PVP_CLASSIC = { Alliance = Art.pvpAlliance, Horde = Art.pvpHorde, FFA = Art.pvpFFA }

local function updatePvP(frame)
	local icon = frame.PvPIcon
	if not icon then return end
	local unit = frame.unit
	if not UnitExists(unit) or not UnitIsPlayer(unit) then
		icon:Hide()
		return
	end

	-- Both of these can be secret booleans; unreadable means no banner rather
	-- than an error.
	local kind
	if CUF.SafeFlag(UnitIsPVPFreeForAll(unit)) == true then
		kind = "FFA"
	elseif CUF.SafeFlag(UnitIsPVP(unit)) == true then
		local faction = CUF.SafeText(UnitFactionGroup(unit))
		if faction == "Alliance" or faction == "Horde" then kind = faction end
	end
	if not kind then
		icon:Hide()
		return
	end

	local corner = frame.mirrored and "TOPRIGHT" or "TOPLEFT"
	icon:ClearAllPoints()

	local atlas = icon.SetAtlas and pcall(icon.SetAtlas, icon, PVP_ATLAS[kind], true)
	if atlas then
		if kind == "FFA" then
			-- Blizzard's own spot: TOP to (25, -50) on the player, (-26, -50) on the target
			icon:SetPoint("TOP", frame, corner, frame.mirrored and -26 or 25, -50)
		else
			local spot = frame.geo.pvp[kind]
			icon:SetPoint(corner, frame, corner, spot[1], spot[2])
		end
	else
		pcall(icon.SetTexCoord, icon, 0, 1, 0, 1)
		icon:SetTexture(PVP_CLASSIC[kind])
		icon:SetSize(G.pvpIconSize, G.pvpIconSize)
		icon:SetPoint(corner, frame, corner, frame.mirrored and 21 or 0, -24)
	end
	icon:Show()
end

-- The quest badge on a mob your quests want dead.
local function updateQuest(frame)
	local icon = frame.QuestIcon
	if not icon then return end
	local ok, quest = false, nil
	if type(UnitIsQuestBoss) == "function" then ok, quest = pcall(UnitIsQuestBoss, frame.unit) end
	icon:SetShown(ok and CUF.SafeFlag(quest) == true)
end

-- Blizzard's threat glow: the player frame lights up when anything has you
-- on its threat list, a target's frame when you are on its.  The state can
-- be secret; unreadable means no glow rather than a wrong one.
local function updateThreat(frame)
	local flash = frame.Flash
	if not flash then return end
	if not CUF.db.threatGlow or type(UnitThreatSituation) ~= "function" or not UnitExists(frame.unit) then
		flash:Hide()
		return
	end
	local ok, status
	if frame.unit == "player" then
		ok, status = pcall(UnitThreatSituation, "player")
	else
		ok, status = pcall(UnitThreatSituation, "player", frame.unit)
	end
	status = ok and CUF.SafeNumber(status) or nil
	if status and status > 0 then
		local r, g, b = 1, 0, 0
		if type(GetThreatStatusColor) == "function" then
			local got, cr, cg, cb = pcall(GetThreatStatusColor, status)
			if got and CUF.SafeNumber(cr) then r, g, b = cr, cg, cb end
		end
		flash:SetVertexColor(r, g, b)
		flash:Show()
	else
		flash:Hide()
	end
end

-- UnitAffectingCombat can hand back a secret boolean on this client, and
-- testing one throws outright.  Read it when the client allows; otherwise let
-- the widget consume the secret without the addon ever learning the answer.
local function showFromFlag(texture, value)
	local readable, result = pcall(function() return value and true or false end)
	if readable then
		texture:SetAlpha(1)
		texture:SetShown(result and true or false)
		return
	end

	if texture.SetAlphaFromBoolean then
		texture:Show()
		if pcall(texture.SetAlphaFromBoolean, texture, value, 1, 0) then return end
	end
	texture:Hide()
end

-- Classic packs both states into one file: crossed swords on the right half,
-- the resting zzz on the left.
local COMBAT_COORDS = { 0.5, 1.0, 0.0, 0.484375 }
local REST_COORDS = { 0.0, 0.5, 0.0, 0.421875 }

-- The player's own frame: vanilla's Zzz and crossed swords beside the
-- portrait, each with its glow, and the whole frame glowing yellow while
-- resting or red in combat.  InCombatLockdown is always readable for the
-- player, unlike UnitAffectingCombat.
local function updatePlayerState(frame)
	local resting = false
	if CUF.db.showRestIcon and type(IsResting) == "function" then
		local ok, value = pcall(IsResting)
		resting = ok and CUF.SafeFlag(value) == true
	end
	-- InCombatLockdown is still false while PLAYER_REGEN_DISABLED is being
	-- handled, so the event itself is tracked as well.
	local inCombat = Units.inCombat
	if inCombat == nil then inCombat = InCombatLockdown() end
	local fighting = CUF.db.combatIcon and inCombat and true or false
	if fighting then resting = false end   -- combat wins, as in vanilla

	frame.RestIcon:SetShown(resting)
	frame.RestGlow:SetShown(resting)
	frame.AttackIcon:SetShown(fighting)
	frame.AttackGlow:SetShown(fighting)
	frame.AttackBackground:SetShown(fighting)

	local glow = CUF.db.statusGlow and (resting or fighting)
	frame.StatusTexture:SetShown(glow and true or false)
	if glow then
		local color = fighting and COMBAT_GLOW or REST_GLOW
		frame.StatusTexture:SetVertexColor(color[1], color[2], color[3])
	end
	frame.Pulse:SetShown(resting or fighting)
end

local function updateState(frame)
	if frame.RestIcon then
		updatePlayerState(frame)
		return
	end

	local icon = frame.StateIcon
	if not icon then return end

	local unit = frame.unit
	if not unit or not UnitExists(unit) then
		icon:Hide()
		return
	end

	-- Combat wins over resting: you cannot be both, and combat is the one you
	-- need to see at a glance.
	if CUF.db.combatIcon then
		local ok, inCombat = pcall(UnitAffectingCombat, unit)
		if ok then
			icon:SetTexCoord(COMBAT_COORDS[1], COMBAT_COORDS[2], COMBAT_COORDS[3], COMBAT_COORDS[4])
			showFromFlag(icon, inCombat)
			if icon:IsShown() and (icon:GetAlpha() or 0) > 0 then return end
		end
	end

	-- Resting is the player's own business; no other unit reports it.
	if unit == "player" and CUF.db.showRestIcon and type(IsResting) == "function" then
		local ok, resting = pcall(IsResting)
		if ok then
			icon:SetTexCoord(REST_COORDS[1], REST_COORDS[2], REST_COORDS[3], REST_COORDS[4])
			showFromFlag(icon, resting)
			return
		end
	end

	icon:Hide()
end

-- Hunter pet mood.  GetPetHappiness returns 1 unhappy, 2 content, 3 happy,
-- plus the damage penalty and the loyalty rate.  It answers nil for a warlock
-- pet or any pet without a mood, which is not an error -- there is simply
-- nothing to draw.
--
-- The three faces sit side by side in one file, each 0.1875 wide, so the
-- slice runs from (happiness - 1) to happiness.
local HAPPINESS_LABEL = { "Unhappy", "Content", "Happy" }
local HAPPINESS_COLOR = { { 1, 0.3, 0.3 }, { 1, 0.82, 0 }, { 0.3, 1, 0.3 } }

-- GetPetHappiness is gone from this client -- it went with Cataclysm -- but
-- the mood did not.  It moved onto the pet frame's happiness indicator:
-- PetFrameHappiness:GetHappinessStats(), from PetHappinessIndicatorMixin.
-- That is a real query, not a reading of what happens to be on screen, so it
-- is correct even when Blizzard's own frame is hidden.
local function moodFromIndicator()
	local frame = _G.PetFrameHappiness
	if not frame or type(frame.GetHappinessStats) ~= "function" then return nil end

	local ok, happiness, damage, loyalty = pcall(frame.GetHappinessStats, frame)
	if not ok then return nil end

	local level = CUF.SafeNumber(happiness)
	if not level or level < 1 or level > 3 then return nil end
	return level, CUF.SafeNumber(damage), CUF.SafeNumber(loyalty)
end

-- Last resort: read the face the game is already drawing.  The three are
-- 0.1875 wide, so the left edge gives the level back.  This only reflects
-- what has been drawn, so it is behind the other two rather than beside them.
local function moodFromDisplay()
	local frame = _G.PetFrameHappiness
	local texture = frame and frame.Texture
	if not texture or type(texture.GetTexCoord) ~= "function" then return nil end

	local ok, left = pcall(texture.GetTexCoord, texture)
	if not ok then return nil end

	local edge = CUF.SafeNumber(left)
	if not edge then return nil end

	local level = math.floor(edge / 0.1875 + 0.5) + 1
	if level < 1 or level > 3 then return nil end
	return level
end

local function petMood()
	-- The original API first, for any client that still has it.
	if type(GetPetHappiness) == "function" then
		local ok, happiness, damage, loyalty = pcall(GetPetHappiness)
		if ok then
			local level = CUF.SafeNumber(happiness)
			if level and level >= 1 and level <= 3 then
				return level, CUF.SafeNumber(damage), CUF.SafeNumber(loyalty)
			end
		end
	end

	local level, damage, loyalty = moodFromIndicator()
	if level then return level, damage, loyalty end

	return moodFromDisplay()
end

local function updateHappiness(frame)
	local icon = frame.Happiness
	if not icon then return end

	if not CUF.db.petHappiness or not UnitExists(frame.unit) then
		icon:Hide()
		return
	end

	local level, damage, loyalty = petMood()
	if not level then
		icon:Hide()
		return
	end

	-- Mirror what the game is drawing, whole.  Copying only the texture
	-- coordinates was not enough: this client does not slice a three-face
	-- atlas the way Classic did, so its coordinates span the entire file and
	-- copying them showed all three faces at once.  The face is chosen by the
	-- texture (or atlas) itself, so that has to come across too.
	local copied = false
	local source = _G.PetFrameHappiness
	local sourceTexture = source and source.Texture

	if sourceTexture then
		-- SetTexture does NOT clear the texture coordinates, so a slice left
		-- over from a previous attempt would crop whatever is set next -- which
		-- showed as an icon with the face cut away entirely.  Reset first.
		pcall(icon.Texture.SetTexCoord, icon.Texture, 0, 1, 0, 1)

		-- Refresh first: a hidden frame's texture can be stale, and a stale
		-- face is worse than a computed one.
		if type(source.UpdateHappiness) == "function" then
			pcall(source.UpdateHappiness, source)
		end

		-- An atlas carries its own coordinates, so it is all-or-nothing.
		local atlas = (type(sourceTexture.GetAtlas) == "function")
			and select(2, pcall(sourceTexture.GetAtlas, sourceTexture)) or nil
		if atlas then
			copied = pcall(icon.Texture.SetAtlas, icon.Texture, atlas)
		end

		if not copied and type(sourceTexture.GetTexture) == "function" then
			local got, file = pcall(sourceTexture.GetTexture, sourceTexture)
			if got and file then
				copied = pcall(icon.Texture.SetTexture, icon.Texture, file)
				if copied and type(sourceTexture.GetTexCoord) == "function" then
					local ok, ulx, uly, llx, lly, urx, ury, lrx, lry =
						pcall(sourceTexture.GetTexCoord, sourceTexture)
					-- Only worth copying if it describes an actual area; a
					-- degenerate slice would hide the face rather than crop it.
					local wide = ok and ulx and urx and math.abs(urx - ulx) > 0.01
					local tall = ok and uly and lly and math.abs(lly - uly) > 0.01
					if wide and tall then
						pcall(icon.Texture.SetTexCoord, icon.Texture,
							ulx, uly, llx, lly, urx, ury, lrx, lry)
					end
				end
			end
		end
	end

	-- Nothing to mirror: fall back to Classic's own layout of the file.
	if not copied then
		if CUF:TextureExists(Art.petHappiness) then
			icon.Texture:SetTexture(Art.petHappiness)
		end
		pcall(icon.Texture.SetTexCoord, icon.Texture, 0, 1, 0, 1)
		icon.Texture:SetTexCoord((level - 1) * 0.1875, level * 0.1875, 0, 0.359375)
	end

	local size = CUF.db.petHappinessSize or 30
	icon:SetSize(size, size)

	icon.level, icon.damage, icon.loyalty = level, damage, loyalty
	icon:Show()
end

-- The crown on whoever leads the group.
local function updateLeader(frame)
	local icon = frame.LeaderIcon
	if not icon then return end
	if not CUF.db.showLeader or not UnitExists(frame.unit) or type(UnitIsGroupLeader) ~= "function" then
		icon:Hide()
		return
	end
	local ok, leader = pcall(UnitIsGroupLeader, frame.unit)
	if ok then showFromFlag(icon, leader) else icon:Hide() end
end

-- "Group 3" over your frame while you are in a raid, on vanilla's parchment.
local function updateGroupNumber(frame)
	local plate = frame.GroupPlate
	if not plate then return end
	local number
	if CUF.db.showGroupNumber and IsInRaid and IsInRaid() then
		for index = 1, 40 do
			local unit = "raid" .. index
			if UnitExists(unit) and CUF.SafeFlag(UnitIsUnit(unit, "player")) == true then
				local _, _, subgroup = GetRaidRosterInfo(index)
				number = CUF.SafeNumber(subgroup)
				break
			end
		end
	end
	if not number then
		plate:Hide()
		return
	end
	plate.Text:SetText(CUF.SafeFormat(_G.GROUP_NUMBER or "Group %d", number))
	plate:SetWidth((plate.Text:GetStringWidth() or 40) + 40)
	plate:Show()
end

local updateAuras   -- defined with the target aura row, below

local function updateAll(frame)
	if not frame.unit or not UnitExists(frame.unit) then return end
	updateName(frame)
	updateHealth(frame)
	updatePower(frame)
	updatePortrait(frame)
	updateClassification(frame)
	updatePvP(frame)
	updateState(frame)
	updateHappiness(frame)
	updateLeader(frame)
	updateGroupNumber(frame)
	updateQuest(frame)
	updateThreat(frame)
	CUF:UpdateRaidTargetIcon(frame)
	updateAuras(frame)
	if frame.mirrored and CUF.Cast and CUF.Cast.Reposition then CUF.Cast:Reposition(frame.unit) end
end

-- ---------------------------------------------------------------------------
-- dragging
-- ---------------------------------------------------------------------------

local function savePosition(frame)
	local settings = frame.settings
	if not settings then return end
	local scale = frame:GetScale()
	local fx, fy = frame:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not fx or not ux then return end
	settings.x = fx * scale - ux
	settings.y = fy * scale - uy
end

-- The pet and the target of target hang off their owners where Blizzard and
-- Blizzard puts them, unless they have been dragged somewhere else.
local ATTACH = {
	pet = { owner = "player", point = "TOPLEFT", relative = "TOPLEFT", spec = "PET" },
	targettarget = { owner = "target", point = "TOPRIGHT", relative = "BOTTOMRIGHT", spec = "TOT" },
}

local function restorePosition(frame)
	local settings = frame.settings
	if not settings then return end
	local scale = frame:GetScale()
	frame:ClearAllPoints()

	local key = frame.settingsKey
	local attach = key and ATTACH[key]
	local owner = attach and Units.frames[attach.owner]
	if attach and settings.attached and owner then
		local spec = Units[attach.spec]
		local ownerScale = owner:GetScale()
		frame:SetPoint(attach.point, owner, attach.relative,
			spec.attachX * ownerScale / scale, spec.attachY * ownerScale / scale)
		return
	end
	frame:SetPoint("CENTER", UIParent, "CENTER", settings.x / scale, settings.y / scale)
end

local function makeMovable(frame)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)

	frame.DragOverlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	frame.DragOverlay:SetAllPoints(frame)
	frame.DragOverlay:SetFrameStrata("HIGH")
	frame.DragOverlay:EnableMouse(true)
	frame.DragOverlay:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	frame.DragOverlay:SetBackdropColor(0, 0.6, 1, 0.25)
	frame.DragOverlay:SetBackdropBorderColor(0, 0.7, 1, 1)
	frame.DragOverlay:Hide()

	frame.DragOverlay.Label = frame.DragOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.DragOverlay.Label:SetPoint("CENTER")
	frame.DragOverlay.Label:SetText(frame.label or "")

	frame.DragOverlay:SetScript("OnMouseDown", function(self)
		-- moving an attached frame by hand unhooks it from its owner
		if frame.settings and frame.settings.attached then frame.settings.attached = false end
		frame:StartMoving()
		frame.isMoving = true
	end)
	frame.DragOverlay:SetScript("OnMouseUp", function(self)
		if frame.isMoving then
			frame:StopMovingOrSizing()
			frame.isMoving = false
			savePosition(frame)
			restorePosition(frame)
		end
	end)

	-- While unlocked every frame is forced visible, otherwise you could never
	-- position the target, pet or target-of-target frames: they are hidden
	-- whenever their unit does not exist, which is most of the time you are
	-- standing still arranging your UI.
	function frame:SetMovableState(movable)
		local watched = self.unit and self.unit ~= "player"
		if movable then
			if watched and not InCombatLockdown() then
				UnregisterUnitWatch(self)
				self:Show()
			end
			self.DragOverlay:Show()
		else
			self.DragOverlay:Hide()
			if watched and not InCombatLockdown() then
				RegisterUnitWatch(self)
				if not UnitExists(self.unit) then self:Hide() end
			end
		end
	end

	CUF.MovableFrames[#CUF.MovableFrames + 1] = frame
end

-- ---------------------------------------------------------------------------
-- frame construction
-- ---------------------------------------------------------------------------

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

-- The 232x100 classic frame, on Blizzard's PlayerFrame (player) and
-- TargetFrame (target, focus) geometry.
function Units:CreateLargeFrame(key, unit, mirrored, label)
	local name = "SquawkClassicUF_" .. key
	local frame = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
	frame:SetSize(232, 100)
	frame.unit = unit
	frame.label = label
	frame.settings = CUF.db.units[key]
	frame.mirrored = mirrored
	local F = mirrored and GEO.target or GEO.player
	frame.geo = F

	frame:SetAttribute("unit", unit)
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "togglemenu")
	frame:RegisterForClicks("AnyUp")

	-- a point measured from the frame's top-left (player) or top-right (target)
	local side = mirrored and "TOPRIGHT" or "TOPLEFT"
	local function place(region, spec)
		region:SetPoint(side, frame, side, spec.x, spec.y)
	end

	-- the threat glow behind everything (Blizzard's Flash / FrameFlash)
	frame.Flash = frame:CreateTexture(nil, "BACKGROUND")
	frame.Flash:SetDrawLayer("BACKGROUND", -7)
	frame.Flash:SetTexture(Art.flash)
	frame.Flash:Hide()
	Units:PlaceFlash(frame, false)

	-- the black backdrop behind the name, health and power (ns.C.BACKDROP)
	frame.Backdrop = frame:CreateTexture(nil, "BACKGROUND")
	frame.Backdrop:SetDrawLayer("BACKGROUND", -6)
	frame.Backdrop:SetSize(119, 41)
	frame.Backdrop:SetColorTexture(0, 0, 0, 0.5)
	place(frame.Backdrop, F.backdrop)

	frame.Portrait = frame:CreateTexture(nil, "BORDER")
	frame.Portrait:SetSize(64, 64)
	place(frame.Portrait, F.portrait)

	-- the reaction-coloured plate behind a target's name, under the art
	if mirrored then
		frame.NameBackground = frame:CreateTexture(nil, "BACKGROUND")
		frame.NameBackground:SetDrawLayer("BACKGROUND", -5)
		frame.NameBackground:SetTexture(Art.levelBg)
		frame.NameBackground:SetSize(119, 19)
		place(frame.NameBackground, F.backdrop)
		frame.NameBackground:Hide()
	end

	frame.Health = createBar(frame, 119, 12)
	place(frame.Health, F.health)
	frame.Power = createBar(frame, 119, 12)
	place(frame.Power, F.power)

	-- the art sits on top of the bars
	frame.ArtFrame = CreateFrame("Frame", nil, frame)
	frame.ArtFrame:SetAllPoints(frame)
	frame.ArtFrame:SetFrameLevel(frame:GetFrameLevel() + 3)

	frame.Art = frame.ArtFrame:CreateTexture(nil, "ARTWORK")
	frame.Art:SetTexture(Art.frame)
	frame.Art:SetSize(232, 100)
	frame.Art:SetPoint("TOPLEFT", frame, "TOPLEFT", F.art.x, F.art.y)
	frame.Art:SetTexCoord(F.art.coords[1], F.art.coords[2], F.art.coords[3], F.art.coords[4])

	-- PvP flag, below the name and level text
	frame.PvPIcon = frame.ArtFrame:CreateTexture(nil, "OVERLAY")
	frame.PvPIcon:SetDrawLayer("OVERLAY", -2)
	frame.PvPIcon:SetSize(G.pvpIconSize, G.pvpIconSize)
	frame.PvPIcon:Hide()

	if not mirrored then Units:CreatePlayerStatus(frame) end

	frame.LeaderIcon = frame.ArtFrame:CreateTexture(nil, "OVERLAY")
	frame.LeaderIcon:SetDrawLayer("OVERLAY", 5)
	frame.LeaderIcon:SetSize(16, 16)
	frame.LeaderIcon:SetTexture(Art.leaderIcon)
	place(frame.LeaderIcon, F.leader)
	frame.LeaderIcon:Hide()

	-- the raid marker: the target's own spot, on the player the portrait's top
	CUF:CreateRaidTargetIcon(frame, frame.ArtFrame, 26)
	if mirrored then
		frame.RaidIcon:SetPoint("CENTER", frame, "TOPRIGHT", F.raidIcon.x, F.raidIcon.y)
	else
		frame.RaidIcon:SetPoint("CENTER", frame.Portrait, "TOP", 0, 0)
	end

	if mirrored then
		frame.QuestIcon = frame.ArtFrame:CreateTexture(nil, "OVERLAY")
		frame.QuestIcon:SetSize(32, 32)
		frame.QuestIcon:SetTexture(Art.questBadge)
		frame.QuestIcon:SetPoint("TOPLEFT", frame, "TOPRIGHT", F.quest.x, F.quest.y)
		frame.QuestIcon:Hide()
	end

	frame.Name = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Name:SetWidth(100)
	frame.Name:SetJustifyH("CENTER")
	pcall(frame.Name.SetWordWrap, frame.Name, false)
	if mirrored then
		frame.Name:SetPoint("CENTER", frame, "CENTER", F.name.x, F.name.y)
	else
		frame.Name:SetPoint("TOPLEFT", frame, "TOPLEFT", F.name.x, F.name.y)
	end

	frame.Level = frame.ArtFrame:CreateFontString(nil, "OVERLAY",
		_G.GameNormalNumberFont and "GameNormalNumberFont" or "NumberFontNormal")
	frame.Level:SetJustifyH("CENTER")
	frame.Level:SetJustifyV("MIDDLE")
	if mirrored then
		frame.Skull = frame.ArtFrame:CreateTexture(nil, "OVERLAY")
		frame.Skull:SetSize(16, 16)
		frame.Skull:SetTexture(Art.skull)
		frame.Skull:Hide()
	end
	Units:PlaceLevel(frame, mirrored)

	-- Blizzard's status text: "current / max" in the middle of each bar
	frame.HealthText = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.HealthText:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
	frame.PowerText = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.PowerText:SetPoint("CENTER", frame.Power, "CENTER", 0, 0)

	frame.Dead = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Dead:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
	frame.Dead:SetText(_G.DEAD or "Dead")
	frame.Dead:SetTextColor(1, 0.2, 0.2)
	frame.Dead:Hide()

	frame.UpdateAll = updateAll
	CUF:AttachTooltip(frame)
	makeMovable(frame)
	return frame
end

-- The threat glow: the plain one, or the taller one around an elite's dragon.
function Units:PlaceFlash(frame, elite)
	local spec = frame.geo.flash
	if elite and frame.geo.eliteFlash then spec = frame.geo.eliteFlash end
	frame.Flash:ClearAllPoints()
	frame.Flash:SetSize(spec.w, spec.h)
	frame.Flash:SetPoint("TOPLEFT", frame, "TOPLEFT", spec.x, spec.y)
	frame.Flash:SetTexCoord(spec.coords[1], spec.coords[2], spec.coords[3], spec.coords[4])
end

-- The level number in the circle: its centre is anchored to the
-- frame's centre, (-81, -21) on the player and (81, -21) on the target.
-- The nudges are there for a client whose art lands a pixel off.
function Units:PlaceLevel(frame, mirrored)
	local level = frame.Level
	if not level then return end

	level:ClearAllPoints()
	level:SetWidth(0)
	level:SetJustifyH("CENTER")
	level:SetJustifyV("MIDDLE")

	if CUF.db.levelStyle == "classic" then
		local spec = frame.geo.level
		level:SetPoint("CENTER", frame, "CENTER",
			spec.x + (CUF.db.levelNudgeX or 0), spec.y + (CUF.db.levelNudgeY or 0))
	else
		level:SetPoint("TOP", frame.Name, "BOTTOM", 0, -1)
	end

	if frame.Skull then
		frame.Skull:ClearAllPoints()
		frame.Skull:SetPoint("CENTER", level, "CENTER", 0, 0)
	end
end

-- The player frame's vanilla status pieces:
-- the Zzz bubble and crossed swords at the portrait's lower left, where the
-- level circle is -- vanilla let the Zzz cover the number while resting --
-- and PlayerStatusTexture, the glow over the name area.
function Units:CreatePlayerStatus(frame)
	local portrait = frame.Portrait

	-- the glows pulse together, so they share one frame whose alpha breathes
	frame.Pulse = CreateFrame("Frame", nil, frame.ArtFrame)
	frame.Pulse:SetAllPoints(frame)
	frame.Pulse:SetFrameLevel(frame.ArtFrame:GetFrameLevel() + 1)
	frame.Pulse.elapsed = 0
	frame.Pulse:SetScript("OnUpdate", function(self, delta)
		self.elapsed = self.elapsed + delta
		-- vanilla swung the alpha back and forth about once a second
		self:SetAlpha(0.3 + 0.7 * math.abs(math.sin(self.elapsed * math.pi)))
	end)
	frame.Pulse:Hide()

	frame.StatusTexture = frame.Pulse:CreateTexture(nil, "OVERLAY")
	frame.StatusTexture:SetTexture(Art.playerStatus)
	frame.StatusTexture:SetTexCoord(0, 0.74609375, 0, 0.53125)
	frame.StatusTexture:SetSize(190, 66)
	frame.StatusTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", GEO.player.status.x, GEO.player.status.y)
	frame.StatusTexture:SetBlendMode("ADD")
	frame.StatusTexture:Hide()

	-- the icons sit above the level number, the glows pulse over them
	local icons = CreateFrame("Frame", nil, frame.ArtFrame)
	icons:SetAllPoints(frame)
	icons:SetFrameLevel(frame.ArtFrame:GetFrameLevel() + 2)
	frame.StatusIcons = icons

	local function piece(parent, layer, width, height, file, l, r, t, b)
		local texture = parent:CreateTexture(nil, layer)
		texture:SetSize(width, height)
		texture:SetTexture(file)
		texture:SetTexCoord(l, r, t, b)
		texture:Hide()
		return texture
	end

	frame.RestIcon = piece(icons, "OVERLAY", 31, 31, Art.stateIcon, 0, 0.5, 0, 0.421875)
	frame.RestIcon:SetPoint("TOPLEFT", portrait, "TOPLEFT", -3, -38)

	frame.AttackIcon = piece(icons, "OVERLAY", 32, 31, Art.stateIcon, 0.5, 1, 0, 0.484375)
	frame.AttackIcon:SetPoint("TOPLEFT", frame.RestIcon, "TOPLEFT", 1, 1)

	frame.AttackBackground = piece(icons, "ARTWORK", 32, 32, Art.attackBg, 0, 1, 0, 1)
	frame.AttackBackground:SetVertexColor(0.8, 0.1, 0.1)
	frame.AttackBackground:SetAlpha(0.4)
	frame.AttackBackground:SetPoint("TOPLEFT", frame.AttackIcon, "TOPLEFT", -3, -1)

	-- the glows live on the pulsing frame, stacked over the icons
	local glowFrame = CreateFrame("Frame", nil, frame.Pulse)
	glowFrame:SetAllPoints(frame)
	glowFrame:SetFrameLevel(icons:GetFrameLevel() + 1)

	frame.RestGlow = piece(glowFrame, "OVERLAY", 32, 32, Art.stateIcon, 0, 0.5, 0.5, 1)
	frame.RestGlow:SetBlendMode("ADD")
	frame.RestGlow:SetPoint("TOPLEFT", frame.RestIcon, "TOPLEFT")

	frame.AttackGlow = piece(glowFrame, "OVERLAY", 32, 32, Art.stateIcon, 0.5, 1, 0.5, 1)
	frame.AttackGlow:SetVertexColor(1, 0, 0)
	frame.AttackGlow:SetBlendMode("ADD")
	frame.AttackGlow:SetPoint("TOPLEFT", frame.AttackIcon, "TOPLEFT")

	-- "Group 3" on vanilla's faded parchment over the top of the frame
	-- (PlayerFrameGroupIndicator, BOTTOMLEFT to 97,-20)
	local plate = CreateFrame("Frame", nil, frame.ArtFrame)
	plate:SetHeight(16)
	plate:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", GEO.player.group.x, GEO.player.group.y)
	plate:SetFrameLevel(frame.ArtFrame:GetFrameLevel() + 2)
	local left = piece(plate, "BACKGROUND", 24, 16, Art.groupIndicator, 0, 0.1875, 0, 1)
	left:SetPoint("LEFT", plate, "LEFT")
	local right = piece(plate, "BACKGROUND", 24, 16, Art.groupIndicator, 0.53125, 0.71875, 0, 1)
	right:SetPoint("RIGHT", plate, "RIGHT")
	local middle = plate:CreateTexture(nil, "BACKGROUND")
	middle:SetHeight(16)
	middle:SetTexture(Art.groupIndicator)
	middle:SetTexCoord(0.1875, 0.53125, 0, 1)
	middle:SetPoint("LEFT", left, "RIGHT")
	middle:SetPoint("RIGHT", right, "LEFT")
	for _, texture in ipairs({ left, right, middle }) do
		texture:SetAlpha(0.3)
		texture:Show()
	end
	plate.Text = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	plate.Text:SetPoint("LEFT", plate, "LEFT", 20, -2)
	plate:Hide()
	frame.GroupPlate = plate
end

-- Combo points belong to the target in vanilla, and ran down the right-hand
-- side of the target's portrait.  Blizzard's own ComboFrame (and its art,
-- fading and show / hide logic) is kept and simply moved onto our target
-- frame; the offsets are vanilla's.
local COMBO_POINTS = {
	{ -9, 6 }, { 0, 0 }, { 7, -8 }, { 12, -19 }, { 14, -30 },
	{ 12, -41 }, { 24, -33 }, { 24, -22 }, { 20, -12 },
}

function Units:AttachComboPoints(frame)
	local combo = _G.ComboFrame
	if not combo or not CUF.db.comboPoints then return end

	local function anchor()
		if not CUF.db.comboPoints then return end
		pcall(function()
			combo:SetParent(frame.ArtFrame)
			combo:SetFrameLevel(frame.ArtFrame:GetFrameLevel() + 4)
			combo:ClearAllPoints()
			combo:SetPoint("TOPRIGHT", frame.Portrait, "CENTER", 30, 35)
		end)
	end

	for index, point in ipairs(combo.ComboPoints or {}) do
		local offset = COMBO_POINTS[index]
		if offset then
			pcall(function()
				point:ClearAllPoints()
				point:SetPoint("TOPRIGHT", combo, "TOPRIGHT", offset[1], offset[2])
			end)
		end
	end
	anchor()
	-- Blizzard re-anchors the frame at the end of every update
	if type(_G.ComboFrame_ApplyOverrides) == "function" then
		hooksecurefunc("ComboFrame_ApplyOverrides", anchor)
	end
	Units.comboAttached = true
end

-- Target of target: Blizzard's 120x49 frame with the classic layout on it
-- (UI-TargetofTargetFrame at 93x45 in the corner), hung off the target
-- frame's bottom-right.
local TOT = {
	width = 120, height = 49,
	artWidth = 93, artHeight = 45,
	artCoords = { 0.015625, 0.7265625, 0, 0.703125 },
	portraitSize = 35, portraitX = 5, portraitY = -5,
	barWidth = 46, barHeight = 7,
	healthX = -29, healthY = -15,
	manaX = -29, manaY = -23,
	nameX = 42, nameY = 7,
	backdropWidth = 46, backdropHeight = 15, backdropX = 45, backdropY = 20,
	deadX = 48, deadY = 3,
	-- its four debuffs, 12x12, beside the frame (TOPLEFT to its TOPRIGHT)
	debuffs = { { -23, -8 }, { -10, -8 }, { -23, -21 }, { -10, -21 } },
	attachX = 12, attachY = 31,   -- TOPRIGHT to the target's BOTTOMRIGHT
}

-- Pet: the 128x53 small targeting frame, below the player frame where
-- Blizzard's bottom-managed container puts it.
local PET = {
	width = 128, height = 53,
	artWidth = 128, artHeight = 64, artX = 0, artY = -2,
	portraitSize = 37, portraitX = 7, portraitY = -6,
	barWidth = 69, barHeight = 8,
	healthX = 47, healthY = -22,
	manaX = 47, manaY = -29,
	nameX = 52, nameY = 33,
	backdropWidth = 69, backdropHeight = 15,
	-- PlayerBottomManagedFrameContainer: TOP to the player's BOTTOM (30, 25),
	-- 160 wide, and the pet 15 in from its left edge
	attachX = 81, attachY = -75,
}
Units.TOT, Units.PET = TOT, PET

function Units:CreateToTFrame(key, unit, label)
	local frame = CreateFrame("Button", "SquawkClassicUF_" .. key, UIParent, "SecureUnitButtonTemplate")
	frame:SetSize(TOT.width, TOT.height)
	frame.unit = unit
	frame.label = label
	frame.settings = CUF.db.units[key]

	frame:SetAttribute("unit", unit)
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "togglemenu")
	frame:RegisterForClicks("AnyUp")

	frame.Backdrop = frame:CreateTexture(nil, "BACKGROUND")
	frame.Backdrop:SetSize(TOT.backdropWidth, TOT.backdropHeight)
	frame.Backdrop:SetColorTexture(0, 0, 0, 0.5)
	frame.Backdrop:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", TOT.backdropX, TOT.backdropY)

	frame.Portrait = frame:CreateTexture(nil, "BORDER")
	frame.Portrait:SetSize(TOT.portraitSize, TOT.portraitSize)
	frame.Portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", TOT.portraitX, TOT.portraitY)

	frame.Health = createBar(frame, TOT.barWidth, TOT.barHeight)
	frame.Health:SetPoint("TOPRIGHT", frame, "TOPRIGHT", TOT.healthX, TOT.healthY)

	frame.Power = createBar(frame, TOT.barWidth, TOT.barHeight)
	frame.Power:SetPoint("TOPRIGHT", frame, "TOPRIGHT", TOT.manaX, TOT.manaY)

	frame.ArtFrame = CreateFrame("Frame", nil, frame)
	frame.ArtFrame:SetAllPoints(frame)
	frame.ArtFrame:SetFrameLevel(frame:GetFrameLevel() + 3)

	frame.Art = frame.ArtFrame:CreateTexture(nil, "ARTWORK")
	frame.Art:SetTexture(Art.totFrame)
	frame.Art:SetSize(TOT.artWidth, TOT.artHeight)
	frame.Art:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	frame.Art:SetTexCoord(TOT.artCoords[1], TOT.artCoords[2], TOT.artCoords[3], TOT.artCoords[4])

	frame.Name = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Name:SetWidth(100)
	frame.Name:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", TOT.nameX, TOT.nameY)
	frame.Name:SetJustifyH("LEFT")
	pcall(frame.Name.SetWordWrap, frame.Name, false)

	frame.Dead = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Dead:SetPoint("LEFT", frame, "LEFT", TOT.deadX, TOT.deadY)
	frame.Dead:SetText(_G.DEAD or "Dead")
	frame.Dead:SetTextColor(1, 0.2, 0.2)
	frame.Dead:Hide()

	-- its own four debuffs
	frame.SmallDebuffs = {}
	for index, offset in ipairs(TOT.debuffs) do
		local icon = Units:CreateAuraButton(frame, true)
		icon:SetSize(12, 12)
		icon:SetPoint("TOPLEFT", frame, "TOPRIGHT", offset[1], offset[2])
		frame.SmallDebuffs[index] = icon
	end

	frame.UpdateAll = updateAll
	CUF:CreateRaidTargetIcon(frame, frame.ArtFrame, 14)
	frame.RaidIcon:SetPoint("CENTER", frame.Portrait, "TOP", 0, 0)

	CUF:AttachTooltip(frame)
	makeMovable(frame)
	return frame
end

function Units:CreatePetFrame(key, unit, label)
	local frame = CreateFrame("Button", "SquawkClassicUF_" .. key, UIParent, "SecureUnitButtonTemplate")
	frame:SetSize(PET.width, PET.height)
	frame.unit = unit
	frame.label = label
	frame.settings = CUF.db.units[key]

	frame:SetAttribute("unit", unit)
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "togglemenu")
	frame:RegisterForClicks("AnyUp")

	frame.Backdrop = frame:CreateTexture(nil, "BACKGROUND")
	frame.Backdrop:SetSize(PET.backdropWidth, PET.backdropHeight)
	frame.Backdrop:SetColorTexture(0, 0, 0, 0.5)
	frame.Backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", PET.healthX, PET.healthY)

	frame.Portrait = frame:CreateTexture(nil, "BORDER")
	frame.Portrait:SetSize(PET.portraitSize, PET.portraitSize)
	frame.Portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", PET.portraitX, PET.portraitY)

	frame.Health = createBar(frame, PET.barWidth, PET.barHeight)
	frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", PET.healthX, PET.healthY)

	frame.Power = createBar(frame, PET.barWidth, PET.barHeight)
	frame.Power:SetPoint("TOPLEFT", frame, "TOPLEFT", PET.manaX, PET.manaY)

	frame.ArtFrame = CreateFrame("Frame", nil, frame)
	frame.ArtFrame:SetAllPoints(frame)
	frame.ArtFrame:SetFrameLevel(frame:GetFrameLevel() + 3)

	frame.Art = frame.ArtFrame:CreateTexture(nil, "ARTWORK")
	frame.Art:SetTexture(Art.smallFrame)
	frame.Art:SetSize(PET.artWidth, PET.artHeight)
	frame.Art:SetPoint("TOPLEFT", frame, "TOPLEFT", PET.artX, PET.artY)

	frame.Name = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Name:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PET.nameX, PET.nameY)
	frame.Name:SetJustifyH("LEFT")

	frame.HealthText = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.HealthText:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
	frame.PowerText = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.PowerText:SetPoint("CENTER", frame.Power, "CENTER", 0, 0)

	frame.Dead = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Dead:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
	frame.Dead:SetText(_G.DEAD or "Dead")
	frame.Dead:SetTextColor(1, 0.2, 0.2)
	frame.Dead:Hide()

	-- Mood sits to the right of the frame, clear of the art, the way the
	-- Classic pet frame places it.  A Button rather than a Texture so it can
	-- carry the tooltip that explains the damage penalty.
	frame.Happiness = CreateFrame("Button", nil, frame.ArtFrame)
	frame.Happiness:SetSize(CUF.db.petHappinessSize or 30, CUF.db.petHappinessSize or 30)
	frame.Happiness:SetPoint("LEFT", frame, "RIGHT", 0, -4)
	frame.Happiness:SetFrameLevel(frame.ArtFrame:GetFrameLevel() + 2)

	frame.Happiness.Texture = frame.Happiness:CreateTexture(nil, "OVERLAY")
	frame.Happiness.Texture:SetAllPoints(frame.Happiness)
	if CUF:TextureExists(Art.petHappiness) then
		frame.Happiness.Texture:SetTexture(Art.petHappiness)
	end

	frame.Happiness:SetScript("OnEnter", function(self)
		if not self.level then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local colour = HAPPINESS_COLOR[self.level] or { 1, 1, 1 }
		-- PET_HAPPINESS1..3 are the game's own strings, so this follows the
		-- client's language rather than hardcoding English.
		local text = _G["PET_HAPPINESS" .. self.level]
		if type(text) ~= "string" then text = HAPPINESS_LABEL[self.level] or "?" end
		GameTooltip:AddLine(text, colour[1], colour[2], colour[3], 1)
		if self.damage then
			GameTooltip:AddLine(("Damage: %d%% of normal"):format(self.damage), 1, 1, 1, 1)
		end
		if self.loyalty and self.loyalty ~= 0 then
			GameTooltip:AddLine(("Loyalty: %+d"):format(self.loyalty), 1, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	frame.Happiness:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.Happiness:Hide()

	frame.UpdateAll = updateAll
	CUF:CreateRaidTargetIcon(frame, frame.ArtFrame, 14)
	frame.RaidIcon:SetPoint("CENTER", frame.Portrait, "TOP", 0, 0)

	CUF:AttachTooltip(frame)
	makeMovable(frame)
	return frame
end

-- ---------------------------------------------------------------------------
-- target and focus auras
--
-- Blizzard's own TargetFrame aura layout, re-anchored to the classic art:
-- a block starting at the art's bottom-left (5 in, 32 up), rows
-- up to 122px wide (101 for the first two rows while the target of target
-- is showing, so they clear it), 3px between icons and between rows.  Icons
-- are 17px, or 21px when you or your pet cast them.  A friendly target lists
-- buffs first and debuffs on a new row below; a hostile one the other way.
-- Up to 32 buffs and 16 debuffs, as Blizzard allows.
-- ---------------------------------------------------------------------------

local AURA = {
	small = 17, large = 21, spacing = 3,
	lineSize = 122, constrainedLineSize = 101, constrainedLines = 2,
	maxBuffs = 32, maxDebuffs = 16,
}
Units.AURA = AURA

-- vanilla's DebuffTypeColor
local DEBUFF_COLORS = {
	none    = { 0.8, 0.0, 0.0 },
	Magic   = { 0.2, 0.6, 1.0 },
	Curse   = { 0.6, 0.0, 1.0 },
	Disease = { 0.6, 0.4, 0.0 },
	Poison  = { 0.0, 0.6, 0.0 },
}

-- One aura icon: Blizzard's TargetFrameAuraButtonTemplate -- the icon, the
-- stack count in the corner, a cooldown sweep, and for debuffs the
-- UI-Debuff-Overlays border in the debuff's colour.
function Units:CreateAuraButton(parent, isDebuff)
	local icon = CreateFrame("Frame", nil, parent)
	icon:SetSize(AURA.small, AURA.small)
	icon:SetFrameLevel(parent:GetFrameLevel() + 5)

	icon.Icon = icon:CreateTexture(nil, "BACKGROUND")
	icon.Icon:SetAllPoints(icon)

	icon.Count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	icon.Count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, 0)
	icon.Count:SetJustifyH("RIGHT")

	local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, icon, "CooldownFrameTemplate")
	if ok and cooldown then
		cooldown:SetAllPoints(icon)
		pcall(cooldown.SetReverse, cooldown, true)
		pcall(cooldown.SetDrawEdge, cooldown, true)
		pcall(cooldown.SetHideCountdownNumbers, cooldown, true)
		icon.Cooldown = cooldown
	end

	if isDebuff then
		icon.Border = icon:CreateTexture(nil, "OVERLAY")
		icon.Border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
		icon.Border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
		icon.Border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
		icon.Border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
	end

	-- the game's own tooltip for the aura, by its real slot
	icon:EnableMouse(true)
	icon:SetScript("OnEnter", function(self)
		if not self.auraIndex and not self.spellId then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 15, -25)
		local shown = false
		if self.auraIndex and self.auraFilter then
			shown = pcall(GameTooltip.SetUnitAura, GameTooltip,
				self.auraUnit or "target", self.auraIndex, self.auraFilter)
		end
		if not shown and self.spellId then
			shown = pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellId)
		end
		if shown then GameTooltip:Show() else GameTooltip:Hide() end
	end)
	icon:SetScript("OnLeave", function() GameTooltip:Hide() end)

	icon:Hide()
	return icon
end

-- Fills one icon from an aura the reader handed over.
local function showAura(icon, unit, filter, texture, count, index, spellId, dispelType, data)
	icon.Icon:SetTexture(texture)
	local stacks = CUF.SafeNumber(count)
	icon.Count:SetText((stacks and stacks > 1) and stacks or "")

	if icon.Border then
		local color = DEBUFF_COLORS[CUF.SafeText(dispelType) or "none"] or DEBUFF_COLORS.none
		icon.Border:SetVertexColor(color[1], color[2], color[3])
	end

	if icon.Cooldown then
		icon.Cooldown:Hide()
		if type(data) == "table" then
			local duration = CUF.SafeNumber(data.duration)
			local expires = CUF.SafeNumber(data.expirationTime)
			if duration and expires and duration > 0 then
				pcall(icon.Cooldown.SetCooldown, icon.Cooldown, expires - duration, duration)
				icon.Cooldown:Show()
			elseif data.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDuration
				and icon.Cooldown.SetCooldownFromDurationObject then
				-- the secret-safe route: the engine times it
				local ok, object = pcall(C_UnitAuras.GetAuraDuration, unit, data.auraInstanceID)
				if ok and object and pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, object) then
					icon.Cooldown:Show()
				end
			end
		end
	end

	icon.auraUnit = unit
	icon.auraIndex = index
	icon.auraFilter = filter
	icon.spellId = tonumber(CUF.SafeText(spellId) or "")
	icon:Show()
end

Units.ShowAura = showAura

-- True when the aura was cast by you, your pet or your vehicle.
local function castByMe(data)
	if type(data) ~= "table" then return false end
	local source = data.sourceUnit
	if source == nil then return false end
	for _, token in ipairs({ "player", "pet", "vehicle" }) do
		local ok, same = pcall(UnitIsUnit, source, token)
		if ok and CUF.SafeFlag(same) == true then return true end
	end
	return false
end

function Units:CreateAuraIcons(frame)
	if not CUF.db.targetAuras.enabled then return end
	-- a plain frame the icons hang in, so the cast bar can hang under it
	frame.AuraBlock = CreateFrame("Frame", nil, frame)
	frame.AuraBlock:SetSize(1, 1)
	frame.AuraBlock:SetPoint("TOPLEFT", frame, "TOPLEFT", GEO.target.auras.x, GEO.target.auras.y)
	frame.BuffIcons, frame.DebuffIcons = {}, {}
	frame.auraRows = 0
end

-- Is the target of target on screen beside this frame?  Only the target
-- has one; the first two aura rows are narrowed to clear it.
local function totShowing(frame)
	if frame.unit ~= "target" then return false end
	local tot = Units.frames.targettarget
	return tot and CUF.db.units.targettarget.attached and UnitExists("targettarget") and true or false
end

-- Blizzard's flow layout, element by element.
local function layoutAuras(frame, groups)
	local constrained = totShowing(frame) and AURA.constrainedLines or 0
	local x, y, line, lineHeight = 0, 0, 1, 0
	local width, placed = 0, 0

	local function lineLimit()
		return (line <= constrained) and AURA.constrainedLineSize or AURA.lineSize
	end
	local function newLine()
		y = y + lineHeight + AURA.spacing
		x, lineHeight = 0, 0
		line = line + 1
	end

	for groupIndex, group in ipairs(groups) do
		if groupIndex > 1 and placed > 0 and #group > 0 and x > 0 then newLine() end
		for _, icon in ipairs(group) do
			local size = icon.auraSize
			if x > 0 and x + size > lineLimit() then newLine() end
			icon:SetSize(size, size)
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", frame.AuraBlock, "TOPLEFT", x, -y)
			x = x + size + AURA.spacing
			lineHeight = math.max(lineHeight, size)
			width = math.max(width, x - AURA.spacing)
			placed = placed + 1
		end
	end

	frame.auraRows = placed > 0 and line or 0
	frame.AuraBlock:SetSize(math.max(width, 1), math.max(placed > 0 and (y + lineHeight) or 0, 1))
end

local function fillGroup(frame, pool, filter, isDebuff, limit, friendly, hostileNPC)
	local list = {}
	if not UnitExists(frame.unit) or not CUF.Auras then return list end
	CUF.Auras:ForEach(frame.unit, filter, function(_, dispelType, texture, count, index, spellId, data)
		if not texture then return false end   -- the client is hiding it
		local mine = castByMe(data)
		-- Blizzard hides other players' debuffs on a hostile NPC
		if isDebuff and hostileNPC and not mine and type(data) == "table"
			and CUF.SafeFlag(data.isFromPlayerOrPlayerPet) == true then
			return false
		end
		local icon = pool[#list + 1]
		if not icon then
			icon = Units:CreateAuraButton(frame, isDebuff)
			pool[#list + 1] = icon
		end
		icon.auraSize = mine and AURA.large or AURA.small
		showAura(icon, frame.unit, filter, texture, count, index, spellId, dispelType, data)
		list[#list + 1] = icon
		return #list >= limit
	end)
	for index = #list + 1, #pool do
		pool[index].auraIndex, pool[index].spellId = nil, nil
		pool[index]:Hide()
	end
	return list
end

-- Assigns the local forward-declared at the top of the file.
function updateAuras(frame)
	-- the target of target's own four debuffs
	if frame.SmallDebuffs then
		local shown = 0
		if UnitExists(frame.unit) and CUF.Auras then
			CUF.Auras:ForEach(frame.unit, "HARMFUL", function(_, dispelType, texture, count, index, spellId, data)
				if not texture then return false end
				shown = shown + 1
				local icon = frame.SmallDebuffs[shown]
				if not icon then return true end
				showAura(icon, frame.unit, "HARMFUL", texture, count, index, spellId, dispelType, data)
				return shown >= #frame.SmallDebuffs
			end)
		end
		for index = shown + 1, #frame.SmallDebuffs do frame.SmallDebuffs[index]:Hide() end
		return
	end

	if not frame.AuraBlock then return end
	local settings = CUF.db.targetAuras
	local unit = frame.unit
	local friendly = CUF.SafeFlag(UnitIsFriend("player", unit)) == true
	local hostileNPC = not friendly and CUF.SafeFlag(UnitIsPlayer(unit)) == false
		and CUF.SafeFlag(UnitPlayerControlled(unit)) ~= true

	local buffs = fillGroup(frame, frame.BuffIcons, "HELPFUL", false,
		math.min(settings.buffs or AURA.maxBuffs, AURA.maxBuffs), friendly, hostileNPC)
	local debuffs = fillGroup(frame, frame.DebuffIcons, "HARMFUL", true,
		math.min(settings.debuffs or AURA.maxDebuffs, AURA.maxDebuffs), friendly, hostileNPC)

	if friendly then
		layoutAuras(frame, { buffs, debuffs })
	else
		layoutAuras(frame, { debuffs, buffs })
	end

	-- the target's cast bar hangs under the auras when there are any
	if CUF.Cast and CUF.Cast.Reposition then CUF.Cast:Reposition(unit) end
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------

local function registerUnitEvents(frame)
	local unit = frame.unit
	frame:SetScript("OnEvent", function(self, event, arg1)
		if event == "PLAYER_REGEN_DISABLED" then
			Units.inCombat = true
		elseif event == "PLAYER_REGEN_ENABLED" then
			Units.inCombat = false
		end

		if event == "PLAYER_ENTERING_WORLD" then
			self:UpdateAll()
		elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED"
			or event == "UNIT_PET" then
			self:UpdateAll()
		elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
			updateHealth(self)
		elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
			or event == "UNIT_DISPLAYPOWER" then
			updatePower(self)
		elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
			updateName(self)
			updateClassification(self)
		elseif event == "UNIT_FACTION" then
			updateName(self)
			updatePvP(self)
		elseif event == "UNIT_CLASSIFICATION_CHANGED" then
			updateClassification(self)
		elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
			updatePortrait(self)
		elseif event == "UNIT_AURA" then
			updateAuras(self)
		elseif event == "RAID_TARGET_UPDATE" then
			CUF:UpdateRaidTargetIcon(self)
		elseif event == "UNIT_HAPPINESS" or event == "PET_UI_UPDATE" then
			updateHappiness(self)
		elseif event == "UNIT_FLAGS" or event == "PLAYER_REGEN_DISABLED"
			or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_UPDATE_RESTING" then
			updateState(self)
		elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
			updateLeader(self)
			updateGroupNumber(self)
		elseif event == "UNIT_CONNECTION" then
			updateHealth(self)
		elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
			updateThreat(self)
		end
	end)
	pcall(frame.RegisterEvent, frame, "UNIT_THREAT_SITUATION_UPDATE")
	pcall(frame.RegisterEvent, frame, "UNIT_THREAT_LIST_UPDATE")

	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	-- Not a unit event: marking anyone fires it for every frame.
	frame:RegisterEvent("RAID_TARGET_UPDATE")

	-- Entering and leaving combat are not unit events, and resting is the
	-- player's alone.
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:RegisterEvent("GROUP_ROSTER_UPDATE")
	pcall(frame.RegisterEvent, frame, "PARTY_LEADER_CHANGED")
	if unit == "player" then
		pcall(frame.RegisterEvent, frame, "PLAYER_UPDATE_RESTING")
	end
	if unit == "pet" then
		pcall(frame.RegisterEvent, frame, "UNIT_HAPPINESS")
		pcall(frame.RegisterEvent, frame, "PET_UI_UPDATE")
	end
	for _, event in ipairs({
		"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
		"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION",
		"UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CLASSIFICATION_CHANGED",
		"UNIT_AURA", "UNIT_FLAGS", "UNIT_CONNECTION",
	}) do
		pcall(frame.RegisterUnitEvent, frame, event, unit)
	end

	if unit == "target" then
		frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	elseif unit == "focus" then
		pcall(frame.RegisterEvent, frame, "PLAYER_FOCUS_CHANGED")
	elseif unit == "pet" then
		frame:RegisterEvent("UNIT_PET")
	elseif unit == "targettarget" then
		frame:RegisterEvent("PLAYER_TARGET_CHANGED")
		-- target-of-target has no event of its own; poll it lightly
		frame.elapsed = 0
		frame:SetScript("OnUpdate", function(self, delta)
			self.elapsed = self.elapsed + delta
			if self.elapsed > 0.25 then
				self.elapsed = 0
				local exists = UnitExists(self.unit) and true or false
				if exists then self:UpdateAll() end
				if exists ~= self.lastExists then
					self.lastExists = exists
					local target = Units.frames.target
					if target and UnitExists("target") then updateAuras(target) end
					if CUF.Cast and CUF.Cast.Reposition then CUF.Cast:Reposition("target") end
				end
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- setup
-- ---------------------------------------------------------------------------

local LAYOUT = {
	{ key = "player",       unit = "player",       style = "large", label = "Player" },
	{ key = "target",       unit = "target",       style = "large", mirrored = true, label = "Target" },
	{ key = "focus",        unit = "focus",        style = "large", mirrored = true, label = "Focus" },
	{ key = "targettarget", unit = "targettarget", style = "tot", label = "Target of target" },
	{ key = "pet",          unit = "pet",          style = "pet", label = "Pet" },
}

function Units:Initialize()
	for _, entry in ipairs(LAYOUT) do
		local settings = CUF.db.units[entry.key]
		if settings and settings.enabled then
			local frame
			if entry.style == "large" then
				frame = Units:CreateLargeFrame(entry.key, entry.unit, entry.mirrored, entry.label)
			elseif entry.style == "tot" then
				frame = Units:CreateToTFrame(entry.key, entry.unit, entry.label)
			else
				frame = Units:CreatePetFrame(entry.key, entry.unit, entry.label)
			end
			frame.settingsKey = entry.key
			if entry.key == "target" or entry.key == "focus" then
				Units:CreateAuraIcons(frame)
			end
			if entry.key == "target" then
				Units:AttachComboPoints(frame)
			end
			Units.frames[entry.key] = frame
			frame:SetScale(settings.scale or 1)
			restorePosition(frame)
			registerUnitEvents(frame)
			frame:UpdateAll()

			-- The player frame is always up; everything else follows its unit.
			if entry.unit ~= "player" then
				RegisterUnitWatch(frame)
			end
			Units.frames[entry.key] = frame
		end
	end
end

function Units:UpdateAll()
	for key, frame in pairs(Units.frames) do
		local settings = CUF.db.units[key]
		if settings then
			frame:SetScale(settings.scale or 1)
			restorePosition(frame)
		end
		frame.Health:SetStatusBarTexture(CUF:BarTexture())
		frame.Power:SetStatusBarTexture(CUF:BarTexture())
		if frame.Level then Units:PlaceLevel(frame, frame.mirrored) end
		if frame.Portrait then updatePortrait(frame) end
		frame:UpdateAll()
	end
end
