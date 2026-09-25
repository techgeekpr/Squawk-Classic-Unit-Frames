--[[ Classic skin for Blizzard's action buttons.

	This only restyles Blizzard's own buttons -- it never replaces them.  Bar
	paging, keybinds, drag and drop, macros and click handling all stay in
	Blizzard's secure code, which matters here because secure snippets do not
	compile on this client, so a replacement bar addon could not page at all.

	The border values come from Classic's own ActionButtonTemplate:
	UI-Quickslot2 at 40x40, cropped to 0.1875..0.796875, centred on a 36x36
	button.  The gryphon end caps are already Classic on this client (the
	ui-hud-actionbar-gryphon atlases), so they are left alone.
]]

local CUF = SquawkClassicUF
local Bars = {}
CUF.ActionBars = Bars

local ART = {
	normal    = "Interface\\Buttons\\UI-Quickslot2",
	empty     = "Interface\\Buttons\\UI-Quickslot",
	pushed    = "Interface\\Buttons\\UI-Quickslot-Depress",
	highlight = "Interface\\Buttons\\ButtonHilight-Square",
	checked   = "Interface\\Buttons\\CheckButtonHilight",
	border    = "Interface\\Buttons\\UI-ActionButton-Border",
}

local BORDER_COORDS = { 0.1875, 0.796875, 0.1875, 0.796875 }
local BORDER_SCALE = 40 / 36    -- border is slightly larger than the button

-- Modern decoration that has no Classic equivalent.
local MODERN_PARTS = {
	"SlotArt", "SlotBackground", "IconMask", "RightDivider", "BottomDivider",
	"TopDivider", "NewActionTexture", "SpellHighlightTexture",
}

Bars.buttons = {}

-- ---------------------------------------------------------------------------
-- which buttons exist
-- ---------------------------------------------------------------------------

local function addButton(name)
	local button = _G[name]
	if button then Bars.buttons[#Bars.buttons + 1] = button end
end

function Bars:Collect()
	wipe(Bars.buttons)

	for index = 1, 12 do
		for _, prefix in ipairs({
			"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
			"MultiBarRightButton", "MultiBarLeftButton",
			"MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
		}) do
			addButton(prefix .. index)
		end
	end

	for index = 1, 10 do
		addButton("PetActionButton" .. index)
		addButton("StanceButton" .. index)
		addButton("ShapeshiftButton" .. index)
	end

	for index = 1, 6 do
		addButton("OverrideActionBarButton" .. index)
		addButton("PossessButton" .. index)
	end

	return #Bars.buttons
end

-- ---------------------------------------------------------------------------
-- skinning one button
-- ---------------------------------------------------------------------------

local function region(button, key)
	local value = button[key]
	if value then return value end
	local name = button.GetName and button:GetName()
	return name and _G[name .. key] or nil
end

-- The Classic shapes -- button.NormalTexture and _G[name.."NormalTexture"]
-- -- do not exist on this client.  GetNormalTexture is the accessor that does,
-- and if the button has no normal texture at all, setting one creates it.
local function normalTexture(button)
	local found = region(button, "NormalTexture")
	if found then return found, "region" end

	if button.GetNormalTexture then
		local ok, texture = pcall(button.GetNormalTexture, button)
		if ok and texture then return texture, "GetNormalTexture" end
	end

	if button.SetNormalTexture and button.GetNormalTexture then
		pcall(button.SetNormalTexture, button, ART.normal)
		local ok, texture = pcall(button.GetNormalTexture, button)
		if ok and texture then return texture, "created" end
	end
	return nil, "none"
end

local function skinFonts(button)
	local hotkey = region(button, "HotKey")
	if hotkey then
		if CUF.db.actionBars.showHotkeys then
			hotkey:Show()
			hotkey:ClearAllPoints()
			hotkey:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
			hotkey:SetJustifyH("RIGHT")
			local file, _, flags = hotkey:GetFont()
			if file then hotkey:SetFont(file, 12, "OUTLINE") end
		else
			hotkey:Hide()
		end
	end

	local macro = region(button, "Name")
	if macro then
		if CUF.db.actionBars.showMacroNames then
			macro:Show()
			macro:ClearAllPoints()
			macro:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
			local file, _, flags = macro:GetFont()
			if file then macro:SetFont(file, 10, "OUTLINE") end
		else
			macro:Hide()
		end
	end

	local count = region(button, "Count")
	if count then
		count:ClearAllPoints()
		count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
		local file, _, flags = count:GetFont()
		if file then count:SetFont(file, 13, "OUTLINE") end
	end
end

function Bars:SkinButton(button)
	if not button or not button.GetName then return end

	local width = button:GetWidth() or 36
	local border, source = normalTexture(button)
	button.cufBorderSource = source
	if border then
		-- An atlas set by the modern template overrides SetTexture and brings
		-- its own coordinates, so clear it before drawing the Classic border.
		if border.SetAtlas then pcall(border.SetAtlas, border, nil) end
		border:SetTexture(ART.normal)
		border:SetTexCoord(unpack(BORDER_COORDS))
		border:SetSize(width * BORDER_SCALE, width * BORDER_SCALE)
		border:ClearAllPoints()
		border:SetPoint("CENTER", button, "CENTER", 0, 0)
		border:SetAlpha(1)
		border:SetVertexColor(1, 1, 1)
		border:SetDrawLayer("OVERLAY")
	end

	if button.SetPushedTexture then pcall(button.SetPushedTexture, button, ART.pushed) end
	if button.SetHighlightTexture then pcall(button.SetHighlightTexture, button, ART.highlight) end
	if button.SetCheckedTexture then pcall(button.SetCheckedTexture, button, ART.checked) end

	-- Classic shows the whole icon; the modern bars crop and mask it.
	local icon = region(button, "Icon") or region(button, "icon")
	if icon then
		icon:SetTexCoord(0, 1, 0, 1)
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
		icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		if icon.RemoveMaskTexture and button.IconMask then
			pcall(icon.RemoveMaskTexture, icon, button.IconMask)
		end
	end

	-- Hide() alone is not enough: Blizzard re-shows these from update paths we
	-- may not have hooked, and a Show() undoes it.  Clearing the texture and
	-- the alpha as well leaves nothing to draw even if it is shown again.
	for _, key in ipairs(MODERN_PARTS) do
		local part = region(button, key)
		if part then
			if part.SetAtlas then pcall(part.SetAtlas, part, nil) end
			if part.SetTexture then pcall(part.SetTexture, part, nil) end
			if part.SetAlpha then pcall(part.SetAlpha, part, 0) end
			if part.Hide then pcall(part.Hide, part) end
		end
	end

	skinFonts(button)
	button.cufSkinned = true
end

function Bars:SkinAll()
	if not CUF.db.actionBars.enabled then return end
	local count = Bars:Collect()
	for _, button in ipairs(Bars.buttons) do
		pcall(Bars.SkinButton, Bars, button)
	end
	return count
end

-- ---------------------------------------------------------------------------
-- keeping the skin on
--
-- Blizzard repaints a button whenever its contents change, which would undo
-- the border, so re-skin from whichever update hook this client exposes.
-- ---------------------------------------------------------------------------

local function hookUpdates()
	local hooked = {}

	local function hookMixin(name, method)
		local mixin = _G[name]
		if type(mixin) == "table" and type(mixin[method]) == "function" then
			local ok = pcall(hooksecurefunc, mixin, method, function(button)
				if CUF.db.actionBars.enabled then pcall(Bars.SkinButton, Bars, button) end
			end)
			if ok then hooked[#hooked + 1] = name .. ":" .. method end
		end
	end

	-- Each is guarded by existence, so listing the ones this client might use
	-- costs nothing and catches the repaint that washes the skin off.
	for _, mixin in ipairs({
		"ActionBarActionButtonMixin", "BaseActionButtonMixin", "ActionButtonMixin",
	}) do
		for _, method in ipairs({
			"Update", "UpdateButtonArt", "UpdateSlotArt", "UpdateVisuals",
			"UpdateIcon", "UpdateUsable",
		}) do
			hookMixin(mixin, method)
		end
	end

	for _, name in ipairs({ "ActionButton_Update", "ActionButton_UpdateHotkeys" }) do
		if type(_G[name]) == "function" then
			local ok = pcall(hooksecurefunc, name, function(button)
				if CUF.db.actionBars.enabled then pcall(Bars.SkinButton, Bars, button) end
			end)
			if ok then hooked[#hooked + 1] = name end
		end
	end

	Bars.hooks = hooked
	return hooked
end

-- ---------------------------------------------------------------------------
-- setup
-- ---------------------------------------------------------------------------

function Bars:Initialize()
	if not CUF.db.actionBars.enabled then return end

	hookUpdates()

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("UPDATE_BINDINGS")
	events:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
	events:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
	events:RegisterEvent("PET_BAR_UPDATE")
	events:SetScript("OnEvent", function() Bars:SkinAll() end)

	-- Bars are built late and Edit Mode can rebuild them again, so sweep a few
	-- times after login rather than assuming one pass catches everything.
	for _, delay in ipairs({ 0, 1, 3, 8 }) do
		C_Timer.After(delay, function() Bars:SkinAll() end)
	end
end

function Bars:ApplySettings()
	if CUF.db.actionBars.enabled then
		Bars:SkinAll()
	else
		CUF:Print("reload to put Blizzard's own button art back")
	end
end

function Bars:Diagnostics()
	CUF:Print("---- action bars ----")
	local count = Bars:Collect()
	CUF:Print(("buttons found: %d"):format(count))
	CUF:Print(("update hooks: %s"):format(
		(Bars.hooks and #Bars.hooks > 0) and table.concat(Bars.hooks, ", ")
			or "|cffff0000none - the skin may wash off when buttons change|r"))
	local sample = Bars.buttons[1]
	if not sample then return end

	CUF:Print(("first button: %s  (%.0f wide, skinned=%s)"):format(
		sample:GetName() or "?", sample:GetWidth() or 0, tostring(sample.cufSkinned)))

	local border, source = normalTexture(sample)
	CUF:Print(("  normal texture: %s via |cffffd100%s|r"):format(
		border and "|cff00ff00found|r" or "|cffff0000MISSING|r", tostring(source)))
	if border then
		local path = border.GetTexture and select(1, border:GetTexture())
		local atlas = border.GetAtlas and border:GetAtlas()
		CUF:Print(("  texture=%s  atlas=%s  shown=%s"):format(
			tostring(path), tostring(atlas), tostring(border:IsShown())))
	end

	-- Which of the parts this skin touches actually exist on this client.
	local parts = {}
	for _, key in ipairs({ "Icon", "icon", "HotKey", "Count", "Name", "Border",
		"SlotArt", "SlotBackground", "IconMask" }) do
		if region(sample, key) then parts[#parts + 1] = key end
	end
	CUF:Print(("  regions present: %s"):format(
		#parts > 0 and table.concat(parts, ", ") or "|cffff0000none|r"))

	-- The decoration that draws over the Classic border if it survives.
	local loud = {}
	for _, key in ipairs(MODERN_PARTS) do
		local part = region(sample, key)
		if part then
			local shown = part.IsShown and part:IsShown()
			local alpha = part.GetAlpha and part:GetAlpha() or 0
			if shown and alpha > 0 then
				loud[#loud + 1] = ("%s(a=%.1f)"):format(key, alpha)
			end
		end
	end
	CUF:Print(("  modern art still drawing: %s"):format(
		#loud > 0 and ("|cffff0000" .. table.concat(loud, ", ") .. "|r") or "|cff00ff00none|r"))
end
