--[[ Cast bars, in two styles.

	Quartz: a slim bar with a one pixel black border, the spell icon sitting
	just outside on the left, the spell name inside the bar on the left, the
	countdown inside on the right, a latency zone shaded at the end of the
	bar, and a red flash reading "Interrupted" when a cast is stopped.

	Classic: vanilla's cast bar, restored on this client -- the plain
	UI-StatusBar fill tinted
	yellow for a cast and green for a channel, the UI-CastingBar-Border art
	around a 195x13 bar (the small border around the 150x10 target bar), the
	spark riding the end of the fill, and on completion the bar turns green,
	flashes white and fades out.  An interrupted cast turns red.

	Timing is the awkward part on this client.  Cast times are secret values,
	so the bar is filled by handing a Duration object to SetTimerDuration and
	letting the engine animate it.  Channels drain from the readable remaining
	time, and everything degrades to a static bar rather than throwing.  The
	classic spark is anchored to the end of the fill texture, so it follows
	the engine's animation without ever reading a value.
]]

local CUF = SquawkClassicUF
local Cast = {}
CUF.Cast = Cast

local Art = CUF.Art
local FLAT = "Interface\\Buttons\\WHITE8X8"

-- vanilla's cast bar colours
local YELLOW = { 1.0, 0.7, 0.0 }
local GREEN  = { 0.0, 1.0, 0.0 }
local GRAY   = { 0.7, 0.7, 0.7 }
local RED    = { 1.0, 0.0, 0.0 }

-- Quartz colours
local QUARTZ_CAST    = { 1.0, 0.7, 0.0 }
local QUARTZ_CHANNEL = { 0.2, 0.7, 1.0 }
local QUARTZ_FAIL    = { 0.85, 0.15, 0.15 }

local FADE_TIME = 0.5     -- classic fade after a cast ends
local FAIL_HOLD = 0.8     -- how long "Interrupted" stays up

Cast.bars = {}

local function classic()
	return CUF.db.castbar.style == "classic"
end

-- ---------------------------------------------------------------------------
-- reading the cast
-- ---------------------------------------------------------------------------

local function castInfo(unit)
	local ok, name, text, texture, startTime, endTime, _, _, notInterruptible =
		pcall(UnitCastingInfo, unit)
	if ok and name then
		return name, text, texture, startTime, endTime, notInterruptible, false
	end
	local ok2, cname, ctext, ctexture, cstart, cend, _, cnot = pcall(UnitChannelInfo, unit)
	if ok2 and cname then
		return cname, ctext, ctexture, cstart, cend, cnot, true
	end
	return nil
end

-- width, height for this bar in the current style
local function sizeFor(unit)
	local settings = CUF.db.castbar
	if classic() then
		if unit ~= "player" then return settings.classicTargetWidth or 150, 10 end
		return settings.classicWidth or 195, 13
	end
	if unit ~= "player" then
		return settings.targetWidth or 200, settings.targetHeight or 16
	end
	return settings.width, settings.height
end

-- ---------------------------------------------------------------------------
-- building a bar (every piece of both styles; the layout shows one set)
-- ---------------------------------------------------------------------------

local function createBar(key, unit, label)
	local width, height = sizeFor(unit)
	local frame = CreateFrame("Frame", "SquawkClassicUF_CastBar_" .. key, UIParent)
	frame:SetSize(width, height)
	frame.unit = unit
	frame.label = label
	frame.small = unit ~= "player"
	frame:Hide()

	frame.Bar = CreateFrame("StatusBar", nil, frame)
	frame.Bar:SetAllPoints(frame)
	frame.Bar:SetStatusBarTexture(Art.statusBar)
	frame.Bar:SetMinMaxValues(0, 1)
	frame.Bar:SetValue(0)

	frame.Background = frame:CreateTexture(nil, "BACKGROUND")
	frame.Background:SetAllPoints(frame)

	-- The latency zone: how much of the end of the cast is already spent
	-- waiting on the server.  Quartz shades it so you know when you can move.
	frame.Latency = frame.Bar:CreateTexture(nil, "ARTWORK")
	frame.Latency:SetColorTexture(1, 0.2, 0.2, 0.45)
	frame.Latency:SetDrawLayer("ARTWORK", 2)
	frame.Latency:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	frame.Latency:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	frame.Latency:Hide()

	-- classic spark: rides the right edge of the fill texture
	frame.Spark = frame.Bar:CreateTexture(nil, "OVERLAY")
	frame.Spark:SetTexture(Art.castSpark)
	frame.Spark:SetBlendMode("ADD")
	frame.Spark:SetSize(32, 32)
	local fill = frame.Bar:GetStatusBarTexture()
	if fill then frame.Spark:SetPoint("CENTER", fill, "RIGHT", 0, 0) end
	frame.Spark:Hide()

	frame.Overlay = CreateFrame("Frame", nil, frame)
	frame.Overlay:SetAllPoints(frame)
	frame.Overlay:SetFrameLevel(frame.Bar:GetFrameLevel() + 5)

	-- Quartz: a crisp one pixel border
	frame.Edge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	frame.Edge:SetPoint("TOPLEFT", -1, 1)
	frame.Edge:SetPoint("BOTTOMRIGHT", 1, -1)
	frame.Edge:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
	frame.Edge:SetBackdropBorderColor(0, 0, 0, 1)
	frame.Edge:SetFrameLevel(frame.Overlay:GetFrameLevel() + 1)

	-- Classic: the frame art, the flash and the uninterruptible shield
	frame.Border = frame.Overlay:CreateTexture(nil, "ARTWORK")
	frame.Border:SetTexture(frame.small and Art.castBorderSmall or Art.castBorder)
	frame.Border:Hide()

	frame.Shield = frame.Overlay:CreateTexture(nil, "ARTWORK")
	frame.Shield:SetDrawLayer("ARTWORK", 1)
	frame.Shield:SetTexture(Art.castShieldSmall)
	frame.Shield:Hide()

	frame.Flash = frame.Overlay:CreateTexture(nil, "OVERLAY")
	frame.Flash:SetTexture(frame.small and Art.castFlashSmall or Art.castFlash)
	frame.Flash:SetBlendMode("ADD")
	frame.Flash:Hide()

	frame.Text = frame.Overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Text:SetShadowColor(0, 0, 0, 1)
	frame.Text:SetShadowOffset(1, -1)

	frame.Time = frame.Overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Time:SetJustifyH("RIGHT")
	frame.Time:SetShadowColor(0, 0, 0, 1)
	frame.Time:SetShadowOffset(1, -1)

	frame.Icon = frame.Overlay:CreateTexture(nil, "OVERLAY")
	frame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	frame.IconBorder = frame.Overlay:CreateTexture(nil, "BACKGROUND")
	frame.IconBorder:SetColorTexture(0, 0, 0, 1)

	return frame
end

-- ---------------------------------------------------------------------------
-- layout, per style
-- ---------------------------------------------------------------------------

-- A FontString given an explicit width WRAPS, so a long spell name broke onto
-- a second line and overlapped the bar.  Both sides are anchored instead and
-- wrapping is off, so a long name is truncated with an ellipsis.
local function singleLine(text)
	text:SetWidth(0)
	pcall(text.SetWordWrap, text, false)
	pcall(text.SetMaxLines, text, 1)
	pcall(text.SetNonSpaceWrap, text, false)
end

local function showsIcon(frame)
	local settings = CUF.db.castbar
	if classic() then
		if frame.small then return settings.classicTargetIcon and true or false end
		return settings.classicIcon and true or false
	end
	return settings.showIcon and true or false
end

local function showsTime()
	local settings = CUF.db.castbar
	if classic() then return settings.classicTime and true or false end
	return settings.showTime and true or false
end

local function layoutQuartz(frame, width, height)
	frame.Bar:SetStatusBarTexture(FLAT)
	frame.Background:SetColorTexture(0, 0, 0, 0.7)
	frame.Edge:Show()
	frame.Border:Hide()
	frame.Shield:Hide()
	frame.Flash:Hide()
	frame.Spark:Hide()

	frame.Icon:SetSize(height, height)
	frame.Icon:ClearAllPoints()
	frame.Icon:SetPoint("RIGHT", frame, "LEFT", -3, 0)
	frame.IconBorder:ClearAllPoints()
	frame.IconBorder:SetPoint("TOPLEFT", frame.Icon, "TOPLEFT", -1, 1)
	frame.IconBorder:SetPoint("BOTTOMRIGHT", frame.Icon, "BOTTOMRIGHT", 1, -1)

	-- timer first, because the name is bounded by it
	frame.Time:ClearAllPoints()
	frame.Time:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
	frame.Text:ClearAllPoints()
	singleLine(frame.Text)
	frame.Text:SetPoint("LEFT", frame, "LEFT", 3, 0)
	frame.Text:SetPoint("RIGHT", frame.Time, "LEFT", -6, 0)
	frame.Text:SetJustifyH("LEFT")

	local file = frame.Text:GetFont()
	if file then
		local size = math.max(9, math.min(height - 4, 14))
		frame.Text:SetFont(file, size, "")
		frame.Time:SetFont(file, size, "")
	end
end

local function anchorSpark(frame)
	local fill = frame.Bar:GetStatusBarTexture()
	frame.Spark:ClearAllPoints()
	if fill then frame.Spark:SetPoint("CENTER", fill, "RIGHT", 0, 0) end
end

local function layoutClassic(frame, width, height)
	frame.Bar:SetStatusBarTexture(Art.statusBar)
	anchorSpark(frame)
	frame.Background:SetColorTexture(0, 0, 0, 0.5)
	frame.Edge:Hide()
	frame.Border:Show()

	frame.Border:ClearAllPoints()
	frame.Flash:ClearAllPoints()
	frame.Shield:ClearAllPoints()
	if frame.small then
		-- UI-CastingBar-Border-Small stretches: 23px of art past each end
		frame.Border:SetHeight(49)
		frame.Border:SetPoint("TOPLEFT", frame, "TOPLEFT", -23, 20)
		frame.Border:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 23, 20)
		frame.Flash:SetHeight(49)
		frame.Flash:SetPoint("TOPLEFT", frame, "TOPLEFT", -23, 20)
		frame.Flash:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 23, 20)
		frame.Shield:SetHeight(49)
		frame.Shield:SetPoint("TOPLEFT", frame, "TOPLEFT", -28, 20)
		frame.Shield:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 18, 20)
		frame.Spark:SetSize(32, 32)
	else
		-- UI-CastingBar-Border is drawn for a 195px bar; stretch it with the bar
		local stretch = width / 195
		frame.Border:SetSize(256 * stretch, 64)
		frame.Border:SetPoint("TOP", frame, "TOP", 0, 28)
		frame.Flash:SetSize(256 * stretch, 64)
		frame.Flash:SetPoint("TOP", frame, "TOP", 0, 28)
		frame.Spark:SetSize(32, 32)
	end
	frame.Flash:Hide()

	-- The border overhangs the bar, so the icon sits outside the art.
	local overhang = frame.small and 23 or math.floor((256 * width / 195 - width) / 2)
	local iconSize = frame.small and 16 or 20
	frame.Icon:SetSize(iconSize, iconSize)
	frame.Icon:ClearAllPoints()
	frame.Icon:SetPoint("RIGHT", frame, "LEFT", -(overhang + 2), 0)
	frame.IconBorder:ClearAllPoints()
	frame.IconBorder:SetPoint("TOPLEFT", frame.Icon, "TOPLEFT", -1, 1)
	frame.IconBorder:SetPoint("BOTTOMRIGHT", frame.Icon, "BOTTOMRIGHT", 1, -1)

	-- Vanilla centred the name on the bar.  With the timer on, the name gives
	-- it room on the right instead of running underneath it.
	frame.Time:ClearAllPoints()
	frame.Time:SetPoint("RIGHT", frame, "RIGHT", -2, frame.small and 0 or 1)
	frame.Text:ClearAllPoints()
	singleLine(frame.Text)
	frame.Text:SetJustifyH("CENTER")
	local top = frame.small and 4 or 5
	frame.Text:SetHeight(16)
	frame.Text:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, top)
	if showsTime() then
		frame.Text:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, top)
	else
		frame.Text:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, top)
	end

	frame.Text:SetFontObject(frame.small and "SystemFont_Shadow_Small" or "GameFontHighlight")
	frame.Time:SetFontObject("GameFontHighlightSmall")
end

local function applySize(frame)
	local width, height = sizeFor(frame.unit)
	frame:SetSize(width, height)
	if classic() then
		layoutClassic(frame, width, height)
	else
		layoutQuartz(frame, width, height)
	end
	local icon = showsIcon(frame)
	frame.Icon:SetShown(icon)
	frame.IconBorder:SetShown(icon and not classic())
	if not showsTime() then frame.Time:SetText("") end
end

-- Where Blizzard hangs the target's spell bar (TargetSpellBarMixin:
-- AdjustPosition), adjusted for the classic art, all measured from the
-- unit frame:
--   under the aura block, when the auras run below the frame  (18+2, -10-5)
--   otherwise under the frame itself                          (43+2, ...)
--     with the target of target showing                        -46+22
--     around an elite / rare dragon                            5-14
--     plain                                                    5-2
-- With the target of target showing, the bar only drops under the auras
-- once there are more than two rows of them (the first two are narrowed to
-- clear it and the bar sits beside them).
local function blizzardSpot(frame, parent)
	local rows = parent.auraRows or 0
	local tot = false
	if frame.unit == "target" and CUF.db.units.targettarget.attached then
		tot = CUF.Units.frames.targettarget ~= nil and UnitExists("targettarget") and true or false
	end
	local underAuras = parent.AuraBlock and rows > 0 and (not tot or rows > 2)
	if underAuras then
		return parent.AuraBlock, 20, -15
	end
	local y = 3
	if tot then
		y = -24
	elseif parent.haveElite then
		y = -9
	end
	return parent, 45, y
end

local function position(frame)
	local settings = CUF.db.castbar
	frame:SetScale(settings.scale or 1)
	frame:ClearAllPoints()
	local scale = frame:GetScale()

	local parent = frame.unit ~= "player" and CUF.Units and CUF.Units.frames
		and CUF.Units.frames[frame.unit]
	if parent and settings.targetAttached then
		-- offsets are in the unit frame's own scale
		local ratio = parent:GetScale() / scale

		if (settings.targetPlacement or "blizzard") == "blizzard" then
			local anchor, x, y = blizzardSpot(frame, parent)
			frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x * ratio, y * ratio)
			return
		end

		-- custom: a side of the frame, a gap, and a nudge
		local side = settings.targetAnchor or "below"
		local gap = settings.targetGap or 8
		if classic() then gap = gap + 20 end   -- the art rises 20px above the bar
		local x = (settings.targetOffsetX or 0) * ratio
		if side == "above" then
			frame:SetPoint("BOTTOM", parent, "TOP", x, gap * ratio)
		else
			local below = parent.AuraBlock and (parent.auraRows or 0) > 0 and parent.AuraBlock or parent
			frame:SetPoint("TOP", below, "BOTTOM", below == parent and x or x, -gap * ratio)
		end
		return
	end

	if frame.unit == "player" then
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", settings.x / scale, settings.y / scale)
	elseif frame.unit == "focus" then
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", settings.x / scale, (settings.y + 120) / scale)
	else
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", settings.x / scale, (settings.y + 60) / scale)
	end
end

-- Called by the unit frames whenever their auras, classification or target
-- of target change, since each moves the bar.  Plain frames, so combat is fine.
function Cast:Reposition(unit)
	local frame = Cast.bars[unit]
	if frame then position(frame) end
end

-- ---------------------------------------------------------------------------
-- latency
-- ---------------------------------------------------------------------------

local function showLatency(frame, totalSeconds)
	frame.Latency:Hide()
	if classic() or not CUF.db.castbar.showLatency or frame.unit ~= "player" then return end
	totalSeconds = CUF.SafeNumber(totalSeconds)
	if not totalSeconds or totalSeconds <= 0 then return end

	local ok, _, _, lagHome, lagWorld = pcall(GetNetStats)
	if not ok then return end
	local lag = math.max(lagHome or 0, lagWorld or 0) / 1000
	if lag <= 0 then return end

	local fraction = math.min(lag / totalSeconds, 1)
	frame.Latency:SetWidth(math.max(1, frame:GetWidth() * fraction))
	frame.Latency:Show()
end

-- ---------------------------------------------------------------------------
-- starting, stopping, failing
-- ---------------------------------------------------------------------------

-- The guides name this Enum.StatusBarFillDirection.Reverse; this client calls
-- it Enum.StatusBarFillStyle.Reverse, so look for whatever exists.
local reverseFill, reverseFillName
local function findReverseFill()
	if reverseFill ~= nil then return reverseFill end
	if type(Enum) ~= "table" then return nil end
	for name, members in pairs(Enum) do
		if type(name) == "string" and name:find("Fill") and type(members) == "table" then
			for key, value in pairs(members) do
				if type(key) == "string" and key:lower():find("reverse") then
					reverseFill, reverseFillName = value, name .. "." .. key
					return reverseFill
				end
			end
		end
	end
	return nil
end

function CUF.GetReverseFillName()
	findReverseFill()
	return reverseFillName
end

local function attachDuration(frame, channeling)
	local bar = frame.Bar
	frame.attachNote = nil

	if not bar.SetTimerDuration then
		frame.attachNote = "StatusBar has no SetTimerDuration"
		return false
	end

	local getter, getterName
	if channeling then
		getter, getterName = _G.UnitChannelDuration, "UnitChannelDuration"
	else
		getter, getterName = _G.UnitCastingDuration, "UnitCastingDuration"
	end
	if type(getter) ~= "function" then
		frame.attachNote = getterName .. " missing"
		return false
	end

	local ok, duration = pcall(getter, frame.unit)
	if not ok or not duration then
		frame.attachNote = getterName .. " returned nothing"
		return false
	end

	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)

	-- A channel should drain.  When the remaining time is readable we drive it
	-- ourselves, which is exact; otherwise ask the engine for a reversed fill.
	if channeling and duration.GetRemainingDuration then
		local readable, raw = pcall(duration.GetRemainingDuration, duration)
		-- type(secret number) is still "number"; only arithmetic gives it away.
		local remaining = readable and CUF.SafeNumber(raw) or nil
		if remaining and remaining > 0 then
			frame.channelTotal = remaining
			frame.manualDrain = true
			frame.duration = duration
			frame.engineTimed = false
			frame.startTime, frame.endTime = nil, nil
			bar:SetMinMaxValues(0, remaining)
			bar:SetValue(remaining)
			frame.attachNote = "draining from GetRemainingDuration"
			frame.lastPath = "channel drain"
			return true, remaining
		end
	end

	local reverse = findReverseFill()
	local applied = false
	if channeling then
		if reverse then applied = pcall(bar.SetTimerDuration, bar, duration, reverse) end
		if not applied then applied = pcall(bar.SetTimerDuration, bar, duration, true) end
	end
	if not applied then applied = pcall(bar.SetTimerDuration, bar, duration) end
	if not applied then
		frame.attachNote = "SetTimerDuration rejected the duration"
		return false
	end

	frame.duration = duration
	frame.engineTimed = true
	frame.manualDrain = false
	frame.startTime, frame.endTime = nil, nil
	frame.attachNote = getterName .. " attached"
	frame.lastPath = "engine timed"

	local total
	if duration.GetRemainingDuration then
		local ok2, raw = pcall(duration.GetRemainingDuration, duration)
		if ok2 then total = CUF.SafeNumber(raw) end   -- plain number or nil
	end
	return true, total
end

-- Takes the bar off the engine's timer and freezes it where we say.
local function detach(frame)
	if frame.engineTimed and frame.Bar.SetTimerDuration then
		pcall(frame.Bar.SetTimerDuration, frame.Bar, nil)
	end
	frame.engineTimed = false
	frame.manualDrain = false
	frame.channelTotal = nil
	frame.duration = nil
	frame.startTime, frame.endTime = nil, nil
end

local function stopCast(frame)
	detach(frame)
	frame.holdUntil = nil
	frame.fadeStart = nil
	frame.stoppedAt = GetTime()
	frame.Latency:Hide()
	frame.Spark:Hide()
	frame.Flash:Hide()
	frame.Shield:Hide()
	frame:SetAlpha(1)
	frame:Hide()
end

local function setColor(frame, color)
	frame.Bar:SetStatusBarColor(color[1], color[2], color[3])
end

-- Classic: the cast completed, so the bar fills, turns green, flashes and
-- fades.  A channel running out just fades.
local function finishCast(frame)
	if not classic() or not frame:IsShown() then
		stopCast(frame)
		return
	end
	local wasChannel = frame.channeling
	detach(frame)
	frame.Latency:Hide()
	frame.Spark:Hide()
	frame.Shield:Hide()
	frame.Bar:SetMinMaxValues(0, 1)
	frame.Bar:SetValue(wasChannel and 0 or 1)
	if not wasChannel then setColor(frame, GREEN) end
	frame.Flash:SetShown(CUF.db.castbar.classicFlash and not wasChannel and true or false)
	frame.Flash:SetAlpha(1)
	frame.Time:SetText("")
	frame.holdUntil = nil
	frame.fadeStart = GetTime()
end

-- Red, with what happened written on it, then gone.
local function failCast(frame, message)
	-- An interrupt can land just after the stop that ended the bar; bring it
	-- back so the red still shows.
	local justStopped = frame.stoppedAt and (GetTime() - frame.stoppedAt) < 0.3
	if not frame:IsShown() and not justStopped then return end

	detach(frame)
	frame.Bar:SetMinMaxValues(0, 1)
	frame.Bar:SetValue(1)
	setColor(frame, classic() and RED or QUARTZ_FAIL)
	frame.Text:SetText(message)
	frame.Time:SetText("")
	frame.Latency:Hide()
	frame.Spark:Hide()
	frame.Flash:Hide()
	frame.Shield:Hide()
	frame:SetAlpha(1)
	frame.fadeStart = nil
	frame.holdUntil = GetTime() + FAIL_HOLD
	frame:Show()
end

local function startCast(frame)
	local name, text, texture, startTime, endTime, notInterruptible, channeling = castInfo(frame.unit)
	if not name then
		stopCast(frame)
		return
	end

	frame.holdUntil = nil
	frame.fadeStart = nil
	frame.channeling = channeling
	frame.engineTimed = false
	frame.manualDrain = false
	frame.duration = nil
	frame:SetAlpha(1)
	frame.Flash:Hide()

	frame.Text:SetText(text or name)
	frame.Icon:SetTexture(texture)
	local icon = showsIcon(frame)
	frame.Icon:SetShown(icon)
	frame.IconBorder:SetShown(icon and not classic())

	-- notInterruptible is a *secret boolean* on this client: testing it throws
	-- ("boolean test on a secret boolean value").  Colour from what we know
	-- for certain, then let the widget consume the secret itself to grey out
	-- an uninterruptible cast.
	local color
	if classic() then
		color = channeling and GREEN or YELLOW
	else
		color = channeling and QUARTZ_CHANNEL or QUARTZ_CAST
	end
	setColor(frame, color)

	local fillTexture = frame.Bar:GetStatusBarTexture()
	if fillTexture and fillTexture.SetVertexColorFromBoolean then
		pcall(fillTexture.SetVertexColorFromBoolean, fillTexture, notInterruptible,
			GRAY[1], GRAY[2], GRAY[3], color[1], color[2], color[3])
	end

	-- the target's shield, shown by the same secret
	frame.Shield:Hide()
	if classic() and frame.small then
		local readable = CUF.SafeFlag(notInterruptible)
		if readable ~= nil then
			frame.Shield:SetShown(readable)
		elseif frame.Shield.SetAlphaFromBoolean then
			frame.Shield:Show()
			if not pcall(frame.Shield.SetAlphaFromBoolean, frame.Shield, notInterruptible, 1, 0) then
				frame.Shield:Hide()
			end
		end
	end

	local attached, total = attachDuration(frame, channeling)
	if not attached then
		local first = CUF.SafeNumber(startTime)
		local last = CUF.SafeNumber(endTime)
		if first and last and last > first then
			frame.lastPath = "manually timed"
			frame.startTime = first / 1000
			frame.endTime = last / 1000
			total = frame.endTime - frame.startTime
			frame.Bar:SetMinMaxValues(0, total)
			frame.Bar:SetValue(channeling and total or 0)
		else
			frame.lastPath = "static"
			frame.startTime, frame.endTime = nil, nil
			frame.Bar:SetMinMaxValues(0, 1)
			frame.Bar:SetValue(1)
			frame.Time:SetText("")
		end
	end

	local sparkRides = not (channeling and frame.engineTimed)
	frame.Spark:SetShown(classic() and CUF.db.castbar.classicSpark and sparkRides and true or false)
	frame.castTotal = CUF.SafeNumber(total)
	showLatency(frame, total)
	frame:Show()
end

local function onUpdate(frame)
	-- the classic fade after a cast ends
	if frame.fadeStart then
		local progress = (GetTime() - frame.fadeStart) / FADE_TIME
		if progress >= 1 then
			stopCast(frame)
		else
			frame:SetAlpha(1 - progress)
		end
		return
	end

	if frame.holdUntil then
		if GetTime() >= frame.holdUntil then
			if classic() then
				frame.holdUntil = nil
				frame.fadeStart = GetTime()
			else
				stopCast(frame)
			end
		end
		return
	end

	local settings = CUF.db.castbar
	local function setTime(remaining)
		if not showsTime() then
			frame.Time:SetText("")
		elseif not classic() and settings.showTotal and CUF.SafeNumber(frame.castTotal) then
			frame.Time:SetText(CUF.SafeFormat("%.1f / %.1f", remaining, frame.castTotal))
		else
			frame.Time:SetText(CUF.SafeFormat("%.1f", remaining))
		end
	end

	if frame.manualDrain and frame.duration then
		local ok, raw = pcall(frame.duration.GetRemainingDuration, frame.duration)
		if ok then
			-- SetValue takes a secret happily; comparing one does not.
			pcall(frame.Bar.SetValue, frame.Bar, raw)
			local remaining = CUF.SafeNumber(raw)
			if remaining then
				if remaining <= 0 then finishCast(frame) return end
				setTime(remaining)
			end
		end
		return
	end

	if frame.engineTimed then
		if frame.duration and frame.duration.GetRemainingDuration then
			local ok, raw = pcall(frame.duration.GetRemainingDuration, frame.duration)
			local remaining = ok and CUF.SafeNumber(raw) or nil
			if remaining then setTime(remaining) else frame.Time:SetText("") end
		else
			frame.Time:SetText("")
		end
		return
	end

	if not frame.startTime or not frame.endTime then return end
	local now = GetTime()
	if now >= frame.endTime then finishCast(frame) return end

	local elapsed = now - frame.startTime
	local total = frame.endTime - frame.startTime
	frame.Bar:SetValue(frame.channeling and (total - elapsed) or elapsed)
	setTime(frame.endTime - now)
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------

local function registerEvents(frame)
	frame:SetScript("OnEvent", function(self, event)
		if event == "UNIT_SPELLCAST_INTERRUPTED" then
			failCast(self, _G.INTERRUPTED or "Interrupted")
		elseif event == "UNIT_SPELLCAST_FAILED" then
			failCast(self, _G.FAILED or "Failed")
		elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
			-- A stop straight after an interrupt must not wipe the red.
			if self.holdUntil then return end
			finishCast(self)
		elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
			-- a new target: never finish the old one's cast on the new frame
			stopCast(self)
			startCast(self)
		else
			startCast(self)
		end
	end)

	for _, event in ipairs({
		"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
		"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
		"UNIT_SPELLCAST_CHANNEL_STOP",
	}) do
		pcall(frame.RegisterUnitEvent, frame, event, frame.unit)
	end
	if frame.unit == "target" then
		frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	elseif frame.unit == "focus" then
		pcall(frame.RegisterEvent, frame, "PLAYER_FOCUS_CHANGED")
	end
	frame:SetScript("OnUpdate", onUpdate)
end

-- ---------------------------------------------------------------------------
-- setup
-- ---------------------------------------------------------------------------

function Cast:Initialize()
	if not CUF.db.castbar.enabled then return end

	if not Cast.bars.player then
		Cast.bars.player = createBar("Player", "player", "Cast bar")
		registerEvents(Cast.bars.player)
	end
	if CUF.db.castbar.showTarget and not Cast.bars.target then
		Cast.bars.target = createBar("Target", "target", "Target cast bar")
		registerEvents(Cast.bars.target)
	end
	if CUF.db.castbar.showFocus and CUF.db.units.focus.enabled and not Cast.bars.focus then
		Cast.bars.focus = createBar("Focus", "focus", "Focus cast bar")
		registerEvents(Cast.bars.focus)
	end

	for _, frame in pairs(Cast.bars) do
		applySize(frame)
		position(frame)
	end

	if CUF.db.hideBlizzard then
		CUF:HideBlizzardFrame(_G.CastingBarFrame or _G.PlayerCastingBarFrame)
	end
end

function Cast:ApplySettings()
	if not CUF.db.castbar.enabled then
		for _, frame in pairs(Cast.bars) do stopCast(frame) end
		return
	end

	Cast:Initialize()
	for key, frame in pairs(Cast.bars) do
		if (key == "target" and not CUF.db.castbar.showTarget)
			or (key == "focus" and not CUF.db.castbar.showFocus) then
			stopCast(frame)
		end
		applySize(frame)
		position(frame)
	end
end

-- Shows both bars mid-cast for a few seconds, then plays the ending of the
-- current style, so both the look and the finish can be judged.
function Cast:Test()
	if not CUF.db.castbar.enabled then
		CUF:Print("|cffff0000the cast bar option is switched off|r - turn \"Player cast bar\" back on under Cast bars")
		return
	end
	Cast:Initialize()
	if not next(Cast.bars) then
		CUF:Print("|cffff0000no cast bars exist|r - check for a startup error above")
		return
	end

	for key, frame in pairs(Cast.bars) do
		applySize(frame)
		position(frame)
		detach(frame)
		frame.holdUntil, frame.fadeStart = nil, nil
		frame.channeling = false
		frame.castTotal = 2.5
		frame:SetAlpha(1)

		frame.Text:SetText(key == "player" and "Test cast" or (key == "focus" and "Focus test cast" or "Target test cast"))
		frame.Time:SetText(showsTime() and "1.7" or "")
		frame.Icon:SetTexture("Interface\\Icons\\Spell_Frost_FrostBolt02")
		local icon = showsIcon(frame)
		frame.Icon:SetShown(icon)
		frame.IconBorder:SetShown(icon and not classic())
		frame.Bar:SetMinMaxValues(0, 1)
		frame.Bar:SetValue(0.66)
		setColor(frame, classic() and YELLOW or QUARTZ_CAST)
		frame.Spark:SetShown(classic() and CUF.db.castbar.classicSpark and true or false)
		frame.Flash:Hide()
		frame.Shield:Hide()
		showLatency(frame, 2.5)
		frame:Show()
	end

	C_Timer.After(4, function()
		for _, frame in pairs(Cast.bars) do
			if frame:IsShown() and not frame.engineTimed and not frame.startTime then
				finishCast(frame)
			end
		end
	end)
end
