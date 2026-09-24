--[[ Player, target, target-of-target, focus and pet frames. ]]

local CUF = ClassicUF
local Units = {}
CUF.Units = Units

local G = CUF.Geometry
local Art = CUF.Art

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
}

local function unitClassColor(unit)
	if not UnitIsPlayer(unit) then return nil end
	local _, class = UnitClass(unit)
	return class and CUF.ClassColors[class]
end

local function applyHealthColor(frame)
	local unit = frame.unit
	local color = CUF.db.classColorHealth and unitClassColor(unit)
	if color then
		frame.Health:SetStatusBarColor(color[1], color[2], color[3])
	elseif UnitIsPlayer(unit) or UnitPlayerControlled(unit) then
		frame.Health:SetStatusBarColor(0.1, 0.8, 0.1)
	else
		-- Reaction colouring is a plain lookup, no secret values involved.
		local reaction = UnitReaction(unit, "player")
		if reaction and reaction <= 3 then
			frame.Health:SetStatusBarColor(0.8, 0.15, 0.15)
		elseif reaction == 4 then
			frame.Health:SetStatusBarColor(0.9, 0.8, 0.2)
		else
			frame.Health:SetStatusBarColor(0.1, 0.8, 0.1)
		end
	end
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
		if CUF.db.showLevel then
			local level = UnitLevel(unit)
			frame.Level:SetText((level and level > 0) and tostring(level) or "??")
			frame.Level:Show()
		else
			frame.Level:Hide()
		end
	end
end

local function updatePortrait(frame)
	if not frame.Portrait then return end
	if not CUF.db.showPortraits then
		frame.Portrait:Hide()
		return
	end
	frame.Portrait:Show()
	if UnitExists(frame.unit) then
		pcall(SetPortraitTexture, frame.Portrait, frame.unit)
	end
end

local function updateClassification(frame)
	if not frame.mirrored or not frame.Art then return end
	local key = CLASSIFICATION_ART[UnitClassification(frame.unit) or ""]
	frame.Art:SetTexture(key and Art[key] or Art.frame)
	local coords = CUF.Geometry.targetArtCoords
	frame.Art:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
end

local function updatePvP(frame)
	local icon = frame.PvPIcon
	if not icon then return end
	local unit = frame.unit
	if not UnitExists(unit) or not UnitIsPlayer(unit) then
		icon:Hide()
		return
	end

	if UnitIsPVPFreeForAll(unit) then
		icon:SetTexture(Art.pvpFFA)
		icon:Show()
	elseif UnitIsPVP(unit) then
		local faction = UnitFactionGroup(unit)
		if faction == "Alliance" then
			icon:SetTexture(Art.pvpAlliance)
			icon:Show()
		elseif faction == "Horde" then
			icon:SetTexture(Art.pvpHorde)
			icon:Show()
		else
			icon:Hide()
		end
	else
		icon:Hide()
	end
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
	updateAuras(frame)
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

local function restorePosition(frame)
	local settings = frame.settings
	if not settings then return end
	local scale = frame:GetScale()
	frame:ClearAllPoints()
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

-- The 232x100 Classic frame: player layout, or mirrored for the target.
function Units:CreateLargeFrame(key, unit, mirrored, label)
	local name = "ClassicUF_" .. key
	local frame = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
	frame:SetSize(G.frameWidth, G.frameHeight)
	frame.unit = unit
	frame.label = label
	frame.settings = CUF.db.units[key]

	frame:SetAttribute("unit", unit)
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "togglemenu")
	frame:RegisterForClicks("AnyUp")

	-- dark plate behind the bars, exactly where Blizzard puts it
	frame.Backdrop = frame:CreateTexture(nil, "BACKGROUND")
	frame.Backdrop:SetSize(G.backdropWidth, G.backdropHeight)
	frame.Backdrop:SetColorTexture(0, 0, 0, 0.5)
	if mirrored then
		frame.Backdrop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -G.backdropOffsetX, G.backdropOffsetY)
	else
		frame.Backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", G.backdropOffsetX, G.backdropOffsetY)
	end

	frame.Portrait = frame:CreateTexture(nil, "BORDER")
	frame.Portrait:SetSize(G.portraitSize, G.portraitSize)
	if mirrored then
		frame.Portrait:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -G.portraitOffsetX, G.portraitOffsetY)
	else
		frame.Portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", G.portraitOffsetX, G.portraitOffsetY)
	end

	frame.Health = createBar(frame, G.barWidth, G.barHeight)
	if mirrored then
		frame.Health:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -G.healthOffsetX, G.healthOffsetY)
	else
		frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", G.healthOffsetX, G.healthOffsetY)
	end

	frame.Power = createBar(frame, G.barWidth, G.barHeight)
	if mirrored then
		frame.Power:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -G.manaOffsetX, G.manaOffsetY)
	else
		frame.Power:SetPoint("TOPLEFT", frame, "TOPLEFT", G.manaOffsetX, G.manaOffsetY)
	end

	-- the ornate border sits on top of everything
	frame.ArtFrame = CreateFrame("Frame", nil, frame)
	frame.ArtFrame:SetAllPoints(frame)
	frame.ArtFrame:SetFrameLevel(frame:GetFrameLevel() + 3)

	frame.mirrored = mirrored
	frame.Art = frame.ArtFrame:CreateTexture(nil, "ARTWORK")
	frame.Art:SetTexture(Art.frame)
	if mirrored then
		frame.Art:SetSize(G.targetArtWidth, G.targetArtHeight)
		frame.Art:SetPoint("CENTER", frame, "CENTER", G.targetArtX, G.targetArtY)
	else
		frame.Art:SetSize(G.artWidth, G.artHeight)
		frame.Art:SetPoint("CENTER")
	end
	local coords = mirrored and G.targetArtCoords or G.playerArtCoords
	frame.Art:SetTexCoord(coords[1], coords[2], coords[3], coords[4])

	-- PvP flag: drawn over the frame art, on a sublevel below the name and
	-- level text so it can never cover them.
	frame.PvPIcon = frame.ArtFrame:CreateTexture(nil, "OVERLAY")
	frame.PvPIcon:SetDrawLayer("OVERLAY", -2)
	frame.PvPIcon:SetSize(G.pvpIconSize, G.pvpIconSize)
	if mirrored then
		frame.PvPIcon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", G.pvpIconMirroredX, G.pvpIconY)
	else
		frame.PvPIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", G.pvpIconX, G.pvpIconY)
	end
	frame.PvPIcon:Hide()

	frame.Name = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Name:SetSize(100, 12)
	frame.Name:SetPoint("CENTER", frame, "CENTER", mirrored and -34 or 34, 15)

	frame.Level = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	frame.Level:SetJustifyH("CENTER")
	frame.Level:SetJustifyV("MIDDLE")
	Units:PlaceLevel(frame, mirrored)

	frame.HealthText = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.HealthText:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)

	frame.PowerText = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.PowerText:SetPoint("CENTER", frame.Power, "CENTER", 0, 0)

	frame.Dead = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Dead:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
	frame.Dead:SetText("Dead")
	frame.Dead:SetTextColor(1, 0.2, 0.2)
	frame.Dead:Hide()

	frame.UpdateAll = updateAll
	CUF:AttachTooltip(frame)
	makeMovable(frame)
	return frame
end

-- The level sits in the small circle at the outer edge of the Classic art.
-- "Centered" instead tucks it under the name, which reads better when the
-- circle in this client's art does not line up with the Classic one.
-- The level sits in the small circle at the outer edge of the frame art.
-- Blizzard anchors the text's CENTER to (35.25, 30) from the frame's bottom
-- corner -- and anchors the "??" skull to that same centre, which is what
-- proves the point is the middle of the circle, not its edge.  The nudge
-- exists because this client's art is not guaranteed to line up with Classic's
-- to the pixel.
function Units:PlaceLevel(frame, mirrored)
	local level = frame.Level
	if not level then return end

	level:ClearAllPoints()
	level:SetWidth(0)              -- auto width, so CENTER really centres
	level:SetJustifyH("CENTER")
	level:SetJustifyV("MIDDLE")

	if CUF.db.levelStyle == "classic" then
		local base = G.levelX or 38
		local x = (mirrored and (G.frameWidth - base) or base) + (CUF.db.levelNudgeX or 0)
		local y = (G.levelY or 31) + (CUF.db.levelNudgeY or 0)
		level:SetPoint("CENTER", frame, "BOTTOMLEFT", x, y)
	else
		level:SetPoint("TOP", frame.Name, "BOTTOM", 0, -1)
	end
end

-- Target of target: the real 93x45 Classic frame, art and all.
local TOT = {
	width = 93, height = 45,
	artCoords = { 0.015625, 0.7265625, 0, 0.703125 },
	portraitSize = 35, portraitX = 6, portraitY = -6,
	barWidth = 46, barHeight = 7,
	healthX = -2, healthY = -15,
	manaX = -2, manaY = -23,
	nameX = 42, nameY = 2,
	backdropWidth = 46, backdropHeight = 15, backdropX = 42, backdropY = 13,
}

-- Pet: the 128x53 small targeting frame.
local PET = {
	width = 128, height = 53,
	artWidth = 128, artHeight = 64, artX = 0, artY = -2,
	portraitSize = 37, portraitX = 7, portraitY = -6,
	barWidth = 69, barHeight = 8,
	healthX = 47, healthY = -22,
	manaX = 47, manaY = -29,
	nameX = 52, nameY = 33,
}

function Units:CreateToTFrame(key, unit, label)
	local frame = CreateFrame("Button", "ClassicUF_" .. key, UIParent, "SecureUnitButtonTemplate")
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
	frame.Art:SetAllPoints(frame)
	frame.Art:SetTexCoord(TOT.artCoords[1], TOT.artCoords[2], TOT.artCoords[3], TOT.artCoords[4])

	frame.Name = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Name:SetSize(100, 10)
	frame.Name:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", TOT.nameX, TOT.nameY)
	frame.Name:SetJustifyH("LEFT")

	frame.Dead = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Dead:SetPoint("LEFT", frame, "LEFT", 48, 1)
	frame.Dead:SetText("Dead")
	frame.Dead:SetTextColor(1, 0.2, 0.2)
	frame.Dead:Hide()

	frame.UpdateAll = updateAll
	CUF:AttachTooltip(frame)
	makeMovable(frame)
	return frame
end

function Units:CreatePetFrame(key, unit, label)
	local frame = CreateFrame("Button", "ClassicUF_" .. key, UIParent, "SecureUnitButtonTemplate")
	frame:SetSize(PET.width, PET.height)
	frame.unit = unit
	frame.label = label
	frame.settings = CUF.db.units[key]

	frame:SetAttribute("unit", unit)
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "togglemenu")
	frame:RegisterForClicks("AnyUp")

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

	frame.Dead = frame.ArtFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.Dead:SetPoint("CENTER", frame.Health, "CENTER", 0, 0)
	frame.Dead:SetText("Dead")
	frame.Dead:SetTextColor(1, 0.2, 0.2)
	frame.Dead:Hide()

	frame.UpdateAll = updateAll
	CUF:AttachTooltip(frame)
	makeMovable(frame)
	return frame
end

-- ---------------------------------------------------------------------------
-- target auras
--
-- Classic hung the target's buffs and debuffs under the frame; this does the
-- same, through the guarded reader in Auras.lua so a client that hides auras
-- simply shows none.
-- ---------------------------------------------------------------------------

function Units:CreateAuraIcons(frame)
	local settings = CUF.db.targetAuras
	if not settings.enabled then return end

	frame.BuffIcons = {}
	frame.DebuffIcons = {}

	local function makeIcon(index, isDebuff)
		local icon = CreateFrame("Frame", nil, frame)
		icon:SetSize(settings.size, settings.size)

		icon.Texture = icon:CreateTexture(nil, "ARTWORK")
		icon.Texture:SetAllPoints(icon)
		icon.Texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		-- BACKGROUND, not OVERLAY: this sits *behind* the icon as a border.
		-- On OVERLAY it painted a solid black square over every aura.
		icon.Border = icon:CreateTexture(nil, "BACKGROUND")
		icon.Border:SetPoint("TOPLEFT", -1, 1)
		icon.Border:SetPoint("BOTTOMRIGHT", 1, -1)
		icon.Border:SetColorTexture(0, 0, 0, 1)

		icon.Count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		icon.Count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, 0)

		-- Hovering an aura shows the game's own tooltip for it.  SetUnitAura
		-- needs the aura's real slot, which is why the reader passes it along;
		-- the spell tooltip is the fallback when that call is refused.
		icon:EnableMouse(true)
		icon:SetScript("OnEnter", function(self)
			if not self.auraIndex and not self.spellId then return end
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")

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

	for index = 1, settings.buffs do frame.BuffIcons[index] = makeIcon(index, false) end
	for index = 1, settings.debuffs do frame.DebuffIcons[index] = makeIcon(index, true) end
	Units:LayoutAuraIcons(frame)
end

-- The icons are plain frames, so they can be re-placed at any time, combat
-- included; only their secure parent is restricted.
--
-- Buffs and debuffs each carry their own anchor, horizontal nudge and gap.
-- When both sit on the same side the debuffs automatically clear however many
-- rows of buffs there can be, so the common case still stacks tidily.
function Units:LayoutAuraIcons(frame)
	local settings = CUF.db.targetAuras
	if not frame or not frame.BuffIcons then return end

	local size = settings.size
	local step = size + 2
	local buffRows = math.ceil((settings.buffs or 0) / settings.perRow)

	local function place(icons, anchor, offsetX, gap, rowOffset)
		local above = anchor == "above"
		for index, icon in ipairs(icons) do
			icon:SetSize(size, size)

			local row = math.floor((index - 1) / settings.perRow) + rowOffset
			local column = (index - 1) % settings.perRow
			local x = (offsetX or 5) + column * step
			local distance = (gap or 2) + row * step

			icon:ClearAllPoints()
			if above then
				icon:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", x, distance)
			else
				icon:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", x, -distance)
			end
		end
	end

	place(frame.BuffIcons, settings.buffAnchor, settings.buffOffsetX, settings.buffGap, 0)

	local sameSide = settings.debuffAnchor == settings.buffAnchor
	place(frame.DebuffIcons, settings.debuffAnchor, settings.debuffOffsetX,
		settings.debuffGap, sameSide and buffRows or 0)
end

-- Fills one row from the guarded reader in Auras.lua.
local function fillAuraRow(frame, icons, filter, colorByDispel)
	if not icons then return end
	local shown = 0
	local limit = #icons

	if UnitExists(frame.unit) and CUF.Auras then
		CUF.Auras:ForEach(frame.unit, filter, function(_, dispelType, texture, count, index, spellId)
			-- No readable icon means the client is hiding the aura; showing an
			-- icon anyway leaves an empty black square under the frame.
			if not texture then return true end

			shown = shown + 1
			local icon = icons[shown]
			if not icon then return true end

			icon.Texture:SetTexture(texture)
			if colorByDispel then
				local color = CUF.Auras.DispelColors[dispelType or ""]
				if color then
					icon.Border:SetColorTexture(color[1], color[2], color[3], 1)
				else
					icon.Border:SetColorTexture(0.6, 0, 0, 1)
				end
			end
			local stacks = tonumber(count)
			icon.Count:SetText((stacks and stacks > 1) and stacks or "")

			-- remember where this aura lives so the tooltip can ask for it
			icon.auraUnit = frame.unit
			icon.auraIndex = index
			icon.auraFilter = filter
			icon.spellId = tonumber(spellId)

			icon:Show()
			return shown >= limit
		end)
	end

	for index = shown + 1, limit do
		icons[index].auraIndex = nil
		icons[index].spellId = nil
		icons[index]:Hide()
	end
end

-- Assigns the local forward-declared at the top of the file.
function updateAuras(frame)
	if not frame.BuffIcons then return end
	fillAuraRow(frame, frame.BuffIcons, "HELPFUL", false)
	fillAuraRow(frame, frame.DebuffIcons, "HARMFUL", true)
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------

local function registerUnitEvents(frame)
	local unit = frame.unit
	frame:SetScript("OnEvent", function(self, event, arg1)
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
		end
	end)

	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	for _, event in ipairs({
		"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
		"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION",
		"UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CLASSIFICATION_CHANGED",
		"UNIT_AURA",
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
				if UnitExists(self.unit) then self:UpdateAll() end
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
			if entry.key == "target" then Units:CreateAuraIcons(frame) end
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
		if frame.BuffIcons then Units:LayoutAuraIcons(frame) end
		if frame.Portrait then updatePortrait(frame) end
		frame:UpdateAll()
	end
end
