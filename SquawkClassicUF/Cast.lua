--[[ Cast bars, in the Quartz style.

	Quartz's look: a slim bar with a one pixel black border, the spell icon
	sitting just outside on the left, the spell name inside the bar on the
	left, the countdown inside on the right, a latency zone shaded at the end
	of the bar, and a red flash reading "Interrupted" when a cast is stopped.
	The Classic cast bar art is kept as an alternative style.

	Timing is the awkward part on this client.  Cast times are secret values,
	so the bar is filled by handing a Duration object to SetTimerDuration and
	letting the engine animate it.  Channels drain from the readable remaining
	time, and everything degrades to a static bar rather than throwing.
]]

local CUF = SquawkClassicUF
local Cast = {}
CUF.Cast = Cast

local CLASSIC_BORDER = CUF.Art.castBorder
local CLASSIC_FILL = CUF.Art.castFill
local FLAT = "Interface\\Buttons\\WHITE8X8"

Cast.bars = {}

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

local function sizeFor(unit)
	local settings = CUF.db.castbar
	if unit == "target" then
		return settings.targetWidth or 200, settings.targetHeight or 16
	end
	return settings.width, settings.height
end

-- ---------------------------------------------------------------------------
-- building a bar
-- ---------------------------------------------------------------------------

local function barTexture()
	if CUF.db.castbar.style == "classic" and CUF:TextureExists(CLASSIC_FILL) then
		return CLASSIC_FILL
	end
	-- Quartz bars are flat; the Classic fill is missing on this client anyway.
	return CUF.db.castbar.style == "classic" and CUF.Art.statusBar or FLAT
end

local function createBar(key, unit, label)
	local width, height = sizeFor(unit)
	local frame = CreateFrame("Frame", "SquawkClassicUF_CastBar_" .. key, UIParent)
	frame:SetSize(width, height)
	frame.unit = unit
	frame.label = label
	frame:Hide()

	frame.Bar = CreateFrame("StatusBar", nil, frame)
	frame.Bar:SetAllPoints(frame)
	frame.Bar:SetStatusBarTexture(barTexture())
	frame.Bar:SetMinMaxValues(0, 1)
	frame.Bar:SetValue(0)

	frame.Background = frame:CreateTexture(nil, "BACKGROUND")
	frame.Background:SetAllPoints(frame)
	frame.Background:SetColorTexture(0, 0, 0, 0.7)

	-- The latency zone: how much of the end of the cast is already spent
	-- waiting on the server.  Quartz shades it so you know when you can move.
	frame.Latency = frame.Bar:CreateTexture(nil, "ARTWORK")
	frame.Latency:SetColorTexture(1, 0.2, 0.2, 0.45)
	frame.Latency:SetDrawLayer("ARTWORK", 2)
	frame.Latency:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	frame.Latency:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	frame.Latency:Hide()

	frame.Overlay = CreateFrame("Frame", nil, frame)
	frame.Overlay:SetAllPoints(frame)
	frame.Overlay:SetFrameLevel(frame.Bar:GetFrameLevel() + 5)

	frame.Text = frame.Overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Text:SetJustifyH("LEFT")
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

	-- Quartz: a crisp one pixel border.  Classic: the old cast bar frame art.
	frame.Edge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	frame.Edge:SetPoint("TOPLEFT", -1, 1)
	frame.Edge:SetPoint("BOTTOMRIGHT", 1, -1)
	frame.Edge:SetBackdrop({
		edgeFile = FLAT, edgeSize = 1,
	})
	frame.Edge:SetBackdropBorderColor(0, 0, 0, 1)
	frame.Edge:SetFrameLevel(frame.Overlay:GetFrameLevel() + 1)

	if CUF:TextureExists(CLASSIC_BORDER) then
		frame.ClassicArt = frame.Overlay:CreateTexture(nil, "OVERLAY")
		frame.ClassicArt:SetTexture(CLASSIC_BORDER)
		frame.ClassicArt:SetDrawLayer("OVERLAY", 2)
		frame.ClassicArt:Hide()
	end

	return frame
end

-- ---------------------------------------------------------------------------
-- layout, per style
-- ---------------------------------------------------------------------------

local function applySize(frame)
	local settings = CUF.db.castbar
	local width, height = sizeFor(frame.unit)
	frame:SetSize(width, height)
	frame.Bar:SetStatusBarTexture(barTexture())

	local quartz = settings.style ~= "classic"

	-- icon just outside the bar, square, matching its height
	frame.Icon:SetSize(height, height)
	frame.Icon:ClearAllPoints()
	frame.IconBorder:ClearAllPoints()
	if quartz then
		frame.Icon:SetPoint("RIGHT", frame, "LEFT", -3, 0)
		frame.IconBorder:SetPoint("TOPLEFT", frame.Icon, "TOPLEFT", -1, 1)
		frame.IconBorder:SetPoint("BOTTOMRIGHT", frame.Icon, "BOTTOMRIGHT", 1, -1)
	else
		frame.Icon:SetSize(height + 6, height + 6)
		frame.Icon:SetPoint("RIGHT", frame, "LEFT", -6, 0)
		frame.IconBorder:SetPoint("TOPLEFT", frame.Icon, "TOPLEFT", 0, 0)
		frame.IconBorder:SetPoint("BOTTOMRIGHT", frame.Icon, "BOTTOMRIGHT", 0, 0)
	end

	-- The timer is placed first, because the name is bounded by it.
	frame.Time:ClearAllPoints()
	frame.Time:SetPoint("RIGHT", frame, "RIGHT", -3, 0)

	-- A FontString given an explicit width WRAPS, so a long spell name broke
	-- onto a second line and overlapped the bar.  Anchoring both sides bounds
	-- it by the timer's real position rather than a guessed reserve, and with
	-- wrapping off the name is truncated with an ellipsis instead.
	frame.Text:ClearAllPoints()
	frame.Text:SetWidth(0)
	frame.Text:SetPoint("LEFT", frame, "LEFT", 3, 0)
	frame.Text:SetPoint("RIGHT", frame.Time, "LEFT", -6, 0)
	frame.Text:SetJustifyH("LEFT")
	pcall(frame.Text.SetWordWrap, frame.Text, false)
	pcall(frame.Text.SetMaxLines, frame.Text, 1)
	pcall(frame.Text.SetNonSpaceWrap, frame.Text, false)

	local file = frame.Text:GetFont()
	if file then
		local size = math.max(9, math.min(height - 4, 14))
		frame.Text:SetFont(file, size, "")
		frame.Time:SetFont(file, size, "")
	end

	frame.Edge:SetShown(quartz)
	if frame.ClassicArt then
		frame.ClassicArt:SetShown(not quartz)
		if not quartz then
			local wScale, hScale = width / 195, height / 13
			frame.ClassicArt:SetSize(256 * wScale, 64 * hScale)
			frame.ClassicArt:ClearAllPoints()
			frame.ClassicArt:SetPoint("TOPLEFT", frame, "TOPLEFT", -28 * wScale, 24 * hScale)
		end
	end
end

local function position(frame)
	local settings = CUF.db.castbar
	frame:SetScale(settings.scale or 1)
	frame:ClearAllPoints()
	local scale = frame:GetScale()

	if frame.unit == "target" and settings.targetAttached then
		local targetFrame = CUF.Units and CUF.Units.frames and CUF.Units.frames.target
		if targetFrame then
			local side = settings.targetAnchor or "below"
			local gap = settings.targetGap or 8

			local auras = CUF.db.targetAuras
			if auras and auras.enabled then
				local rows = 0
				if auras.buffAnchor == side then
					rows = rows + math.ceil((auras.buffs or 0) / auras.perRow)
				end
				if auras.debuffAnchor == side then
					rows = rows + math.ceil((auras.debuffs or 0) / auras.perRow)
				end
				if rows > 0 then gap = gap + rows * ((auras.size or 21) + 2) + 4 end
			end

			local x = (settings.targetOffsetX or 0) / scale
			if side == "above" then
				frame:SetPoint("BOTTOM", targetFrame, "TOP", x, gap / scale)
			else
				frame:SetPoint("TOP", targetFrame, "BOTTOM", x, -gap / scale)
			end
			return
		end
	end

	if frame.unit == "player" then
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", settings.x / scale, settings.y / scale)
	else
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", settings.x / scale, (settings.y + 60) / scale)
	end
end

-- ---------------------------------------------------------------------------
-- latency
-- ---------------------------------------------------------------------------

local function showLatency(frame, totalSeconds)
	frame.Latency:Hide()
	if not CUF.db.castbar.showLatency or frame.unit ~= "player" then return end
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

local function stopCast(frame)
	if frame.engineTimed and frame.Bar.SetTimerDuration then
		pcall(frame.Bar.SetTimerDuration, frame.Bar, nil)
	end
	frame.engineTimed = false
	frame.manualDrain = false
	frame.channelTotal = nil
	frame.duration = nil
	frame.startTime, frame.endTime = nil, nil
	frame.holdUntil = nil
	frame.Latency:Hide()
	frame:Hide()
end

-- Quartz turns the bar red and says what happened, then clears.
local function failCast(frame, message)
	if not frame:IsShown() then return end
	if frame.engineTimed and frame.Bar.SetTimerDuration then
		pcall(frame.Bar.SetTimerDuration, frame.Bar, nil)
	end
	frame.engineTimed = false
	frame.manualDrain = false
	frame.startTime, frame.endTime = nil, nil
	frame.duration = nil

	frame.Bar:SetMinMaxValues(0, 1)
	frame.Bar:SetValue(1)
	frame.Bar:SetStatusBarColor(0.85, 0.15, 0.15)
	frame.Text:SetText(message)
	frame.Time:SetText("")
	frame.Latency:Hide()
	frame.holdUntil = GetTime() + 0.8
end

local function startCast(frame)
	local name, text, texture, startTime, endTime, notInterruptible, channeling = castInfo(frame.unit)
	if not name then
		stopCast(frame)
		return
	end

	frame.holdUntil = nil
	frame.channeling = channeling
	frame.engineTimed = false
	frame.manualDrain = false
	frame.duration = nil

	frame.Text:SetText(text or name)
	frame.Icon:SetTexture(texture)
	local showIcon = CUF.db.castbar.showIcon and true or false
	frame.Icon:SetShown(showIcon)
	frame.IconBorder:SetShown(showIcon)

	-- notInterruptible is a *secret boolean* on this client: testing it throws
	-- ("boolean test on a secret boolean value").  Colour from what we know
	-- for certain, then let the widget consume the secret itself to grey out
	-- an uninterruptible cast.
	local r, g, b = 1, 0.7, 0
	if channeling then r, g, b = 0.2, 0.7, 1 end

	frame.Bar:SetStatusBarColor(r, g, b)
	if frame.Fallback then frame.Fallback:SetVertexColor(r, g, b) end

	local fillTexture = frame.Bar:GetStatusBarTexture()
	if fillTexture and fillTexture.SetVertexColorFromBoolean then
		pcall(fillTexture.SetVertexColorFromBoolean, fillTexture, notInterruptible,
			0.6, 0.6, 0.6, r, g, b)
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

	frame.castTotal = CUF.SafeNumber(total)
	showLatency(frame, total)
	frame:Show()
end

local function onUpdate(frame)
	if frame.holdUntil then
		if GetTime() >= frame.holdUntil then stopCast(frame) end
		return
	end

	local settings = CUF.db.castbar
	local function setTime(remaining)
		if not settings.showTime then
			frame.Time:SetText("")
		elseif settings.showTotal and CUF.SafeNumber(frame.castTotal) then
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
				if remaining <= 0 then stopCast(frame) return end
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
	if now >= frame.endTime then stopCast(frame) return end

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
			failCast(self, "Interrupted")
		elseif event == "UNIT_SPELLCAST_FAILED" then
			failCast(self, "Failed")
		elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
			stopCast(self)
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
		for _, frame in pairs(Cast.bars) do frame:Hide() end
		return
	end

	Cast:Initialize()
	for _, frame in pairs(Cast.bars) do
		applySize(frame)
		position(frame)
	end
end

-- Shows both bars filled for a few seconds, so "it never appears" can be told
-- apart from "it appears somewhere I am not looking".
function Cast:Test()
	if not CUF.db.castbar.enabled then
		CUF:Print("|cffff0000the cast bar option is switched off|r - turn \"Cast bar\" back on under Cast & tooltips")
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
		frame.holdUntil = nil
		frame.engineTimed, frame.manualDrain = false, false
		frame.startTime, frame.endTime = nil, nil
		frame.castTotal = 2.5

		frame.Text:SetText(key == "player" and "Test cast" or "Target test cast")
		frame.Time:SetText("1.7")
		frame.Icon:SetTexture("Interface\\Icons\\Spell_Frost_FrostBolt02")
		local showIcon = CUF.db.castbar.showIcon and true or false
		frame.Icon:SetShown(showIcon)
		frame.IconBorder:SetShown(showIcon)
		frame.Bar:SetMinMaxValues(0, 1)
		frame.Bar:SetValue(0.66)
		frame.Bar:SetStatusBarColor(1, 0.7, 0)
		showLatency(frame, 2.5)
		frame:Show()

		CUF:Print(("%s bar test: %dx%d at %d,%d"):format(
			key, frame:GetWidth(), frame:GetHeight(),
			frame:GetLeft() or -1, frame:GetTop() or -1))
	end

	C_Timer.After(5, function()
		for _, frame in pairs(Cast.bars) do stopCast(frame) end
	end)
end
