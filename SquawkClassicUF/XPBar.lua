--[[ The vanilla experience and reputation bars, on Blizzard's own bars.

	  * The frame: vanilla's segmented XP bar frame, the rows between the
	    action bar strip's pieces in UI-MainMenuBar-Dwarf, over half-clear
	    black.
	  * Experience: the flat UI-StatusBar fill in vanilla's purple (blue while
	    rested), the rested stretch past it at 15% and the UI-ExhaustionTick
	    diamond where rest runs out.
	  * Reputation: the same fill in the standing's vanilla colour (blue for
	    renown factions).  While the XP bar shows too, it gets the thinner
	    UI-ReputationWatchBar frame, as vanilla drew it; at max level it takes
	    the XP bar's frame, as vanilla's did.
	  * Other tracked bars (honor and the like) keep Blizzard's fill inside the
	    classic frame.

	The bars keep Blizzard's size and place (Edit Mode's position and Size,
	the stacking above the action bars).  Blizzard's fill re-applies its art
	on every rest / standing change and plays flares, so for XP and
	reputation the whole StatusBar is faded and the classic fill drawn on a
	copy following its min / max / value.  Nothing here is secure, and every
	change is recorded and put back, so it switches live.
]]

local CUF = SquawkClassicUF
local XP = {}
CUF.XPBar = XP

local SetFile = CUF.SetFile

local ART = {
	strip       = "Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf",
	watch       = "Interface\\PaperDollInfoFrame\\UI-ReputationWatchBar",
	tick        = "Interface\\MainMenuBar\\UI-ExhaustionTickNormal",
	tickGlow    = "Interface\\MainMenuBar\\UI-ExhaustionTickHighlight",
	fill        = "Interface\\TargetingFrame\\UI-StatusBar",
}

-- The two frames, four pieces left to right, each `height` rows from the
-- given top row, the fill showing through the middle `fill` rows.
local STYLES = {
	xp    = { file = ART.strip, fileHeight = 256, rows = { 203, 139, 75, 11 }, height = 12, fill = 8 },
	watch = { file = ART.watch, fileHeight = 64,  rows = { 2, 14, 26, 38 },    height = 9,  fill = 5 },
}

local XP_COLOR     = { 0.58, 0, 0.55 }
local RESTED_COLOR = { 0, 0.39, 0.88 }
local RESTED_FILL_ALPHA = 0.15
-- 1.12's FACTION_BAR_COLORS, Hated to Exalted
local STANDING_COLORS = {
	{ 0.8, 0.3, 0.22 }, { 0.8, 0.3, 0.22 }, { 0.75, 0.27, 0 }, { 0.9, 0.7, 0 },
	{ 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 },
}
local FRIENDLY = 5
local TICK_SIZE = 32

local enabled = false
local hasWatchArt, hasTickArt = false, false
local skins = {}
local hookedContainers = {}
local original = setmetatable({}, { __mode = "k" })

local function remember(region)
	if original[region] then return end
	local state = {
		atlas = region:GetAtlas(), color = { region:GetVertexColor() },
		width = region:GetWidth(), height = region:GetHeight(), points = {},
	}
	for i = 1, region:GetNumPoints() do
		local point, relativeTo, relativePoint, x, y = region:GetPoint(i)
		state.points[i] = { point, relativeTo, relativePoint, x, y }
	end
	original[region] = state
end

local function restore(region)
	local state = region and original[region]
	if not state then return end
	if state.atlas then region:SetAtlas(state.atlas) end
	region:SetVertexColor(unpack(state.color))
	region:ClearAllPoints()
	if #state.points == 0 then
		region:SetAllPoints(region:GetParent())
	else
		for _, p in ipairs(state.points) do region:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
	end
	region:SetSize(state.width, state.height)
end

local function kindOf(bar)
	if not bar.StatusBar then return "other" end
	if bar.isExpBar then return "xp" end
	local bars = _G.StatusTrackingBarInfo and _G.StatusTrackingBarInfo.BarsEnum
	if bars and bars.Reputation and bar.barIndex == bars.Reputation then return "rep" end
	return "other"
end

local function createArt(skin, level)
	local bar = skin.bar
	local art = CreateFrame("Frame", nil, bar)
	art:SetFrameLevel(level)
	art:SetPoint("LEFT", bar, "LEFT", 0, 0)
	art:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	local pieces = {}
	for i = 1, 4 do
		local piece = art:CreateTexture(nil, "OVERLAY")
		local previous = pieces[i - 1]
		if previous then
			piece:SetPoint("TOPLEFT", previous, "TOPRIGHT", 0, 0)
			piece:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", 0, 0)
		else
			piece:SetPoint("TOPLEFT", art, "TOPLEFT", 0, 0)
			piece:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", 0, 0)
		end
		pieces[i] = piece
	end
	local function sizePieces(width)
		for _, piece in ipairs(pieces) do piece:SetWidth(width / 4) end
	end
	art:SetScript("OnSizeChanged", function(_, width) sizePieces(width) end)
	sizePieces(bar:GetWidth())
	skin.art, skin.pieces = art, pieces
end

local function createMirror(skin, level)
	local bar, source = skin.bar, skin.bar.StatusBar
	local mirror = CreateFrame("StatusBar", nil, bar)
	mirror:SetFrameLevel(level)
	mirror:SetPoint("LEFT", bar, "LEFT", 0, 0)
	mirror:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	mirror:SetStatusBarTexture(ART.fill)
	mirror:SetMinMaxValues(source:GetMinMaxValues())
	mirror:SetValue(source:GetValue())
	source:HookScript("OnMinMaxChanged", function(_, low, high) mirror:SetMinMaxValues(low, high) end)
	source:HookScript("OnValueChanged", function(_, value) mirror:SetValue(value) end)
	local background = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
	background:SetColorTexture(0, 0, 0, 0.5)
	background:SetAllPoints(mirror)
	skin.mirror, skin.background = mirror, background
end

local function setStyle(skin, name)
	if skin.style == name then return end
	skin.style = name
	local style = STYLES[name]
	for i, piece in ipairs(skin.pieces) do
		local top = style.rows[i]
		SetFile(piece, style.file, 0, 1, top / style.fileHeight, (top + style.height) / style.fileHeight)
	end
	skin.art:SetHeight(style.height * skin.scale)
	if skin.mirror then skin.mirror:SetHeight(style.fill * skin.scale) end
end

local function tickTextures(bar)
	local tick = bar.ExhaustionTick
	if not tick then return nil end
	return tick, tick.Normal or tick:GetNormalTexture(), tick.Highlight or tick:GetHighlightTexture()
end

local function restColor(skin, rested)
	local r, g, b = unpack(rested and RESTED_COLOR or XP_COLOR)
	skin.mirror:SetStatusBarColor(r, g, b)
	local fill = skin.bar.ExhaustionLevelFillBar
	if fill then fill:SetVertexColor(r, g, b, RESTED_FILL_ALPHA) end
	local _, _, glow = tickTextures(skin.bar)
	if glow and hasTickArt then glow:SetVertexColor(r, g, b) end
end

local function standingColor(skin, standing, renown)
	local color = renown and RESTED_COLOR or STANDING_COLORS[standing] or STANDING_COLORS[FRIENDLY]
	skin.mirror:SetStatusBarColor(color[1], color[2], color[3])
end

-- The watched faction's standing, for the colour until Blizzard next
-- updates the bar (friendships count as Friendly, renown factions blue).
local function watchedStanding()
	local reputation = _G.C_Reputation
	local data = reputation and reputation.GetWatchedFactionData and reputation.GetWatchedFactionData()
	if not data or not data.factionID or data.factionID == 0 then return nil end
	if reputation.IsMajorFaction and reputation.IsMajorFaction(data.factionID) then return nil, true end
	local gossip = _G.C_GossipInfo
	local friendship = gossip and gossip.GetFriendshipReputation and gossip.GetFriendshipReputation(data.factionID)
	if friendship and (friendship.friendshipFactionID or 0) > 0 then return FRIENDLY end
	return data.reaction
end

local function skinTick(texture, file, tick, size, offset)
	if not texture then return end
	remember(texture)
	SetFile(texture, file)
	texture:ClearAllPoints()
	texture:SetSize(size, size)
	texture:SetPoint("CENTER", tick, "CENTER", 0, -offset)
end

-- Blizzard's rested fill is fitted to the classic fill's height; its tick
-- keeps Blizzard's place and gets vanilla's diamond, centred on the bar.
local function skinRested(skin)
	local bar = skin.bar
	local fill = bar.ExhaustionLevelFillBar
	if fill then
		remember(fill)
		SetFile(fill, ART.fill)
		fill:ClearAllPoints()
		fill:SetPoint("TOPLEFT", skin.mirror, "TOPLEFT", 0, 0)
		fill:SetPoint("BOTTOMLEFT", skin.mirror, "BOTTOMLEFT", 0, 0)
	end
	local tick, normal, glow = tickTextures(bar)
	if tick and hasTickArt then
		local offset = tonumber(tick.yOffset) or tonumber(_G.EXHAUSTION_TICK_OFFSET_Y) or 0
		local size = TICK_SIZE * skin.scale
		skinTick(normal, ART.tick, tick, size, offset)
		skinTick(glow, ART.tickGlow, tick, size, offset)
	end
end

local function hookBar(skin)
	if skin.kind == "xp" then
		CUF.Hook(skin.bar, "UpdateStatusBarTextures", function(_, rested)
			if enabled then restColor(skin, rested) end
		end)
	elseif skin.kind == "rep" then
		CUF.Hook(skin.bar, "UpdateBarTextures", function(_, standing, renown)
			if enabled then standingColor(skin, standing, renown) end
		end)
	end
end

local function createSkin(container, bar)
	local height = container:GetHeight()
	local skin = {
		bar = bar, kind = kindOf(bar),
		scale = (height and height > 0 and height or 17) / STYLES.xp.height,
	}
	local level = (bar.StatusBar or bar):GetFrameLevel()
	if skin.kind ~= "other" then createMirror(skin, level + 1) end
	createArt(skin, level + 2)
	hookBar(skin)
	skins[bar] = skin
	return skin
end

local function applySkin(skin)
	skin.style = nil
	setStyle(skin, "xp")
	skin.art:Show()
	if skin.mirror then
		skin.mirror:Show()
		skin.background:Show()
		skin.bar.StatusBar:SetAlpha(0)
	end
	if skin.kind == "xp" then
		skinRested(skin)
		restColor(skin, GetRestState() == 1)
	elseif skin.kind == "rep" then
		standingColor(skin, watchedStanding())
	end
end

local function removeSkin(skin)
	skin.art:Hide()
	if skin.mirror then
		skin.mirror:Hide()
		skin.background:Hide()
		skin.bar.StatusBar:SetAlpha(1)
	end
	if skin.kind == "xp" then
		restore(skin.bar.ExhaustionLevelFillBar)
		local _, normal, glow = tickTextures(skin.bar)
		restore(normal)
		restore(glow)
	end
end

-- the modern frame and this client's segment dividers give way
local function updateContainer(container)
	if container.BarFrameTexture then container.BarFrameTexture:SetAlpha(enabled and 0 or 1) end
	local pool = container.HorizontalDividersPool
	if pool then
		for divider in pool:EnumerateActive() do divider:SetAlpha(enabled and 0 or 1) end
	end
end

local function xpBarShown()
	for _, container in ipairs(_G.StatusTrackingBarManager.barContainers) do
		local bar = container:IsShown() and container.GetShownBar and container:GetShownBar()
		if bar and bar.isExpBar then return true end
	end
	return false
end

-- vanilla drew reputation thinner over the XP bar, and in its frame once the
-- XP bar was gone
local function refreshStyles()
	if not enabled then return end
	local thin = hasWatchArt and xpBarShown()
	for _, skin in pairs(skins) do
		if skin.kind == "rep" then setStyle(skin, thin and "watch" or "xp") end
	end
end

local function hookContainer(container)
	hookedContainers[container] = true
	CUF.Hook(container, "UpdateDividers", updateContainer)
	CUF.Hook(container, "ApplyPendingBarToShow", refreshStyles)
	CUF.Hook(container, "UpdateShownState", refreshStyles)
end

local function enable()
	local manager = _G.StatusTrackingBarManager
	if not manager or type(manager.barContainers) ~= "table" then
		XP.state = "|cffff0000no XP bar manager on this client|r"
		return
	end
	if not CUF:TextureExists(ART.strip) then
		XP.state = "|cffff0000vanilla XP bar art missing|r"
		return
	end
	hasWatchArt = CUF:TextureExists(ART.watch)
	hasTickArt = CUF:TextureExists(ART.tick) and CUF:TextureExists(ART.tickGlow)
	enabled = true
	for _, container in ipairs(manager.barContainers) do
		if not hookedContainers[container] then hookContainer(container) end
		updateContainer(container)
		for _, bar in pairs(container.bars or {}) do
			applySkin(skins[bar] or createSkin(container, bar))
		end
	end
	refreshStyles()
	XP.state = "vanilla XP and reputation bars on"
end

local function disable()
	enabled = false
	for _, skin in pairs(skins) do removeSkin(skin) end
	for container in pairs(hookedContainers) do updateContainer(container) end
	XP.state = "off"
end

function XP:Initialize()
	if CUF.db.actionBars.xpBar then enable() else XP.state = "off" end
end

function XP:ApplySettings()
	if CUF.db.actionBars.xpBar and not enabled then
		enable()
	elseif not CUF.db.actionBars.xpBar and enabled then
		disable()
	end
end
