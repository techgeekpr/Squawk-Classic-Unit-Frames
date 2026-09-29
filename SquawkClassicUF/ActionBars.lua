--[[ The vanilla action bars, on Blizzard's own bars.

	Only art is changed -- Blizzard's buttons stay Blizzard's, so paging,
	keybinds, drag and drop, macros and Edit Mode all keep working.  That
	matters here more than anywhere: secure snippets do not compile on this
	client, so a replacement bar addon could not page at all.

	  * Buttons: vanilla's square UI-Quickslot2 frame (the dark UI-Quickslot
	    square on an empty slot of a bar without art), the UI-Quickslot-Depress
	    pushed art, the square highlight and checked glows, the red attack
	    flash and the green equipped border, all at vanilla's proportions --
	    a 66x66 frame on a 36px icon (54x54 on the 30px pet / stance buttons),
	    the icon inset to vanilla's 36-in-42 so the frames fit between the
	    buttons.  The rounded icon mask comes off, so icons are square again.
	  * The bar: the modern plate and dividers behind the main bar give way to
	    the embossed gryphon cells of vanilla's UI-MainMenuBar-Dwarf strip,
	    one cell per button, so Edit Mode's rows, padding and orientation keep
	    working and "hide bar art" hides it as it hides Blizzard's.
	  * The page arrows get vanilla's UI-MainMenu-Scroll*Button art.
	  * The gryphons: vanilla's stone gryphons (UI-MainMenuBar-EndCap-Dwarf)
	    at both ends -- vanilla showed them to both factions.

	Blizzard puts its own art back from each button's UpdateButtonArt and
	Update, and re-creates the dividers in UpdateDividers; those are hooked
	and the vanilla art re-applied after them.  Only textures are touched, so
	the protected buttons are never moved.  Blizzard's art cannot be put back
	from every one of those paths while playing, so switching the buttons off
	needs a reload; the gryphons switch live.
]]

local CUF = SquawkClassicUF
local Bars = {}
CUF.ActionBars = Bars

local SetFile = CUF.SetFile

local ART = {
	strip       = "Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf",
	quickslot2  = "Interface\\Buttons\\UI-Quickslot2",
	quickslot   = "Interface\\Buttons\\UI-Quickslot",
	pushed      = "Interface\\Buttons\\UI-Quickslot-Depress",
	highlight   = "Interface\\Buttons\\ButtonHilight-Square",
	checked     = "Interface\\Buttons\\CheckButtonHilight",
	flash       = "Interface\\Buttons\\UI-QuickslotRed",
	equipped    = "Interface\\Buttons\\UI-ActionButton-Border",
	pageUp      = "Interface\\MainMenuBar\\UI-MainMenu-ScrollUpButton-",   -- + Up / Down / Disabled / Highlight
	pageDown    = "Interface\\MainMenuBar\\UI-MainMenu-ScrollDownButton-",
	gryphon     = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf",
}
Bars.ART = ART

-- ---------------------------------------------------------------------------
-- the vanilla bar strip, shared with the bags bar and the micro menu
--
-- UI-MainMenuBar-Dwarf (256x256) holds the 1024x43 vanilla bar as four
-- 256px pieces, read left to right from the file's rows 213-256, 149-192,
-- 85-128 and 21-64 (the rows between are the XP bar's frame).  The action
-- slots are 42px cells between 3px metal columns; piece 2 holds six whole
-- cells, their columns 2px in.
-- ---------------------------------------------------------------------------

local CELL_WIDTH, CELL_HEIGHT = 42, 43
local CELLS = {}
do
	local top = 149 -- piece 2
	for k = 0, 5 do
		CELLS[k + 1] = { (2 + 42 * k) / 256, (44 + 42 * k) / 256, top / 256, (top + CELL_HEIGHT) / 256 }
	end
end

-- One cell behind a button; the cells differ slightly, so `index` walks them.
function Bars.CreateStripCell(button, index)
	local cell = button:CreateTexture(nil, "BACKGROUND", nil, -3)
	SetFile(cell, ART.strip, unpack(CELLS[(index - 1) % #CELLS + 1]))
	cell:SetPoint("CENTER", button, "CENTER", 0, 0)
	return cell
end

-- A cell sized to its button (keeping the strip's 42:43) plus the bar's
-- padding along the bar, so neighbouring cells meet on their shared column.
function Bars.SizeStripCell(cell, width, padding, vertical)
	local height = width * CELL_HEIGHT / CELL_WIDTH
	if vertical then
		height = height + padding
	else
		width = width + padding
	end
	cell:SetSize(width, height)
end

-- A narrow cell for a button slimmer than the strip's cells (vanilla's key
-- ring had its own narrow slot): the two ends of a cell with a plain slice of
-- its border and dark inside stretched between them.
local NARROW_END = 4
local NARROW_SLICE_X, NARROW_SLICE_Y = 5, 3

function Bars.CreateNarrowStripCell(button)
	local parts = {}
	for i = 1, 3 do
		parts[i] = button:CreateTexture(nil, "BACKGROUND", nil, -3)
		parts[i]:SetTexture(ART.strip)
	end
	return parts
end

function Bars.SizeNarrowStripCell(parts, button, padding, vertical)
	local left, right, top, bottom = unpack(CELLS[1])
	local first, middle, last = parts[1], parts[2], parts[3]
	for _, part in ipairs(parts) do part:ClearAllPoints() end
	if vertical then
		local width = button:GetWidth()
		local height = button:GetHeight() + padding
		local cap = NARROW_END * width / CELL_WIDTH
		local slice = top + (NARROW_SLICE_Y + 0.5) / 256
		first:SetTexCoord(left, right, top, top + NARROW_END / 256)
		middle:SetTexCoord(left, right, slice, slice)
		last:SetTexCoord(left, right, bottom - NARROW_END / 256, bottom)
		first:SetSize(width, cap)
		last:SetSize(width, cap)
		first:SetPoint("TOP", button, "CENTER", 0, height / 2)
		last:SetPoint("BOTTOM", button, "CENTER", 0, -height / 2)
		middle:SetPoint("TOPLEFT", first, "BOTTOMLEFT")
		middle:SetPoint("BOTTOMRIGHT", last, "TOPRIGHT")
	else
		local height = button:GetHeight() * CELL_HEIGHT / CELL_WIDTH
		local width = button:GetWidth() + padding
		local cap = NARROW_END * height / CELL_HEIGHT
		local slice = left + (NARROW_SLICE_X + 0.5) / 256
		first:SetTexCoord(left, left + NARROW_END / 256, top, bottom)
		middle:SetTexCoord(slice, slice, top, bottom)
		last:SetTexCoord(right - NARROW_END / 256, right, top, bottom)
		first:SetSize(cap, height)
		last:SetSize(cap, height)
		first:SetPoint("LEFT", button, "CENTER", -width / 2, 0)
		last:SetPoint("RIGHT", button, "CENTER", width / 2, 0)
		middle:SetPoint("TOPLEFT", first, "TOPRIGHT")
		middle:SetPoint("BOTTOMRIGHT", last, "BOTTOMLEFT")
	end
end

-- Fades every divider Blizzard pooled between a bar's buttons (the pools
-- refill on each layout; alpha sticks to the pooled frames).
function Bars.HideBarDividers(bar)
	for _, key in ipairs({ "HorizontalDividersPool", "VerticalDividersPool" }) do
		local pool = bar[key]
		if pool then
			for divider in pool:EnumerateActive() do divider:SetAlpha(0) end
		end
	end
end

-- ---------------------------------------------------------------------------
-- buttons
-- ---------------------------------------------------------------------------

-- Vanilla's 36px icons sat in the strip's 42px cells with the 66x66 frame
-- (54x54 on the 30px buttons) and the 62x62 equipped border around them.
-- The modern icon fills its whole 45px button and the buttons touch, so the
-- icon is inset to vanilla's proportion and the frames sized from it.
local ICON_RATIO = 36 / 42
local NORMAL_RATIO, NORMAL_RATIO_SMALL = 66 / 36, 54 / 30
local BORDER_RATIO = 62 / 36
-- The frame's 39px ring sits half a file pixel up and left of centre; it is
-- shifted that half pixel back so it is centred on the icon.
local FRAME_ART_BIAS = 0.5 / 64
-- UI-Quickslot fills its square with 60% black, nearly opaque on the 45px
-- buttons; faded so an empty slot reads light.
local EMPTY_SLOT_ALPHA = 0.6

local cells = setmetatable({}, { __mode = "k" })         -- button -> strip cell
local smallButtons = setmetatable({}, { __mode = "k" })  -- pet / stance / possess
Bars.cells = cells

local function round(x) return math.floor(x + 0.5) end
local function iconSize(button) return round(button:GetWidth() * ICON_RATIO) end

local function fillIcon(texture, button)
	if not texture then return end
	texture:SetTexCoord(0, 1, 0, 1)
	texture:ClearAllPoints()
	texture:SetAllPoints(button.icon or button)
end

local function layoutCell(bar, button)
	local cell = cells[button]
	if not cell then return end
	Bars.SizeStripCell(cell, button:GetWidth(), tonumber(bar.buttonPadding) or 0, bar.isHorizontal == false)
end

local function layoutCells(bar)
	for _, button in ipairs(bar.actionButtons or {}) do layoutCell(bar, button) end
end

-- Keybind and macro name, shown or hidden as the options say.
local function applyText(button)
	local hotkey = button.HotKey
	if hotkey then hotkey:SetAlpha(CUF.db.actionBars.showHotkeys and 1 or 0) end
	local macro = button.Name
	if macro then macro:SetAlpha(CUF.db.actionBars.showMacroNames and 1 or 0) end
end

-- Runs after Blizzard's UpdateButtonArt / Update, which put the modern
-- atlases back.  The cell follows Blizzard's own SlotArt, which Edit Mode's
-- "hide bar art" hides.  An empty slot over the bar art keeps only the
-- frame, so the embossed cell shows through as on vanilla's main bar;
-- without bar art it gets vanilla's dark UI-Quickslot square.
local function applyButtonArt(button)
	local cell = cells[button]
	local hasBarArt = button.SlotArt ~= nil and button.SlotArt:IsShown()
	if cell then cell:SetShown(hasBarArt) end

	local size = round(iconSize(button) * (smallButtons[button] and NORMAL_RATIO_SMALL or NORMAL_RATIO))
	local normal = button:GetNormalTexture()
	if normal then
		local empty = not (button.icon and button.icon:IsShown())
		if empty and not hasBarArt then
			SetFile(normal, ART.quickslot)
			normal:SetAlpha(EMPTY_SLOT_ALPHA)
		else
			SetFile(normal, ART.quickslot2)
			normal:SetAlpha(1)
		end
		local shift = size * FRAME_ART_BIAS
		normal:ClearAllPoints()
		normal:SetSize(size, size)
		normal:SetPoint("CENTER", button.icon or button, "CENTER", shift, -shift)
	end
	local pushed = button:GetPushedTexture()
	if pushed then
		SetFile(pushed, ART.pushed)
		fillIcon(pushed, button)
	end
	applyText(button)
end

local function skinButton(bar, button, index, small)
	if not button or cells[button] then return end
	smallButtons[button] = small or nil

	if button.SlotArt then button.SlotArt:SetAlpha(0) end
	if button.SlotBackground then button.SlotBackground:SetAlpha(0) end
	cells[button] = Bars.CreateStripCell(button, index)
	layoutCell(bar, button)
	CUF.StripMask(button.IconMask, button.icon)

	-- the cooldown and the overlays are anchored to the icon and follow it
	if button.icon then
		local size = iconSize(button)
		button.icon:ClearAllPoints()
		button.icon:SetSize(size, size)
		button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
	end

	local highlight = button:GetHighlightTexture()
	if highlight then
		SetFile(highlight, ART.highlight)
		highlight:SetBlendMode("ADD")
		fillIcon(highlight, button)
	end
	local checked = button.GetCheckedTexture and button:GetCheckedTexture()
	if checked then
		SetFile(checked, ART.checked)
		checked:SetBlendMode("ADD")
		fillIcon(checked, button)
	end
	if button.Flash then
		SetFile(button.Flash, ART.flash)
		fillIcon(button.Flash, button)
	end
	if button.Border then
		local size = round(iconSize(button) * BORDER_RATIO)
		SetFile(button.Border, ART.equipped)
		button.Border:SetBlendMode("ADD")
		button.Border:ClearAllPoints()
		button.Border:SetSize(size, size)
		button.Border:SetPoint("CENTER", button.icon or button, "CENTER", 0, 0)
	end
	-- the proc / new-spell pulse would keep its rounded shape otherwise
	if button.SpellHighlightTexture then
		SetFile(button.SpellHighlightTexture, ART.highlight)
		fillIcon(button.SpellHighlightTexture, button)
	end

	CUF.Hook(button, "UpdateButtonArt", applyButtonArt)
	CUF.Hook(button, "Update", applyButtonArt)   -- empty slot <-> filled slot
	applyButtonArt(button)
end

-- bar, and whether its buttons are the 30px small ones
local BAR_LIST = {
	{ "MainActionBar" }, { "MultiBarBottomLeft" }, { "MultiBarBottomRight" },
	{ "MultiBarRight" }, { "MultiBarLeft" }, { "MultiBar5" }, { "MultiBar6" }, { "MultiBar7" },
	{ "PetActionBar", true }, { "StanceBar", true }, { "PossessActionBar", true },
}

local function skinBars()
	local count = 0
	for _, entry in ipairs(BAR_LIST) do
		local bar = _G[entry[1]]
		if bar and type(bar.actionButtons) == "table" then
			for index, button in ipairs(bar.actionButtons) do
				skinButton(bar, button, index, entry[2])
				count = count + 1
			end
			CUF.Hook(bar, "UpdateGridLayout", layoutCells)
		end
	end
	Bars.count = count
end

local function skinPageButton(button, prefix)
	if not button then return end
	button:SetNormalTexture(prefix .. "Up")
	button:SetPushedTexture(prefix .. "Down")
	button:SetDisabledTexture(prefix .. "Disabled")
	button:SetHighlightTexture(prefix .. "Highlight", "ADD")
	-- the 32x32 files carry a 19x17 arrow; the modern buttons are 17x14
	for _, texture in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(),
		button:GetDisabledTexture(), button:GetHighlightTexture() }) do
		texture:ClearAllPoints()
		texture:SetSize(26, 26)
		texture:SetPoint("CENTER", button, "CENTER", 0, 0)
	end
end

local function skinMainBar()
	local bar = _G.MainActionBar
	if bar.BorderArt then bar.BorderArt:SetAlpha(0) end
	if bar.UpdateDividers then
		CUF.Hook(bar, "UpdateDividers", Bars.HideBarDividers)
		Bars.HideBarDividers(bar)
	end
	local page = bar.ActionBarPageNumber
	if page then
		if page.Text and _G.GameFontNormalSmall then page.Text:SetFontObject(_G.GameFontNormalSmall) end
		skinPageButton(page.UpButton, ART.pageUp)
		skinPageButton(page.DownButton, ART.pageDown)
	end
end

-- ---------------------------------------------------------------------------
-- gryphons
--
-- The 128x128 file has its art in rows 52..128 (76px); the modern buttons
-- are 45px where vanilla's were 36, so it is drawn at 1.25x (160x95).  On
-- this client each end cap is an Edit Mode frame holding a .Texture that
-- fills it, so only that texture changes and Edit Mode keeps the position;
-- a client whose caps are bare textures on the bar gets them re-anchored.
-- ---------------------------------------------------------------------------

local ART_TOP = 52 / 128
local CAP_WIDTH, CAP_HEIGHT = 160, 95
local CAP_INSET_X, CAP_OFFSET_Y = 9, -5

local gryphonsOn = false
local gryphonsHooked = false
local modernCaps = setmetatable({}, { __mode = "k" })   -- cap texture -> its modern look

local function getCaps()
	local endCaps = _G.MainActionBar and _G.MainActionBar.EndCaps
	if not endCaps then return nil end
	return endCaps, endCaps.LeftEndCap, endCaps.RightEndCap
end

local function capTexture(cap)
	if not cap then return nil end
	if cap.GetObjectType and cap:GetObjectType() == "Texture" then return cap, true end
	if cap.Texture then return cap.Texture, false end
	return nil
end

local function rememberCap(texture)
	if modernCaps[texture] then return end
	local state = { atlas = texture:GetAtlas(), width = texture:GetWidth(), height = texture:GetHeight(), points = {} }
	for i = 1, texture:GetNumPoints() do
		local point, relativeTo, relativePoint, x, y = texture:GetPoint(i)
		state.points[i] = { point, relativeTo, relativePoint, x, y }
	end
	modernCaps[texture] = state
end

local function classicCap(cap, side)
	local texture, anchored = capTexture(cap)
	if not texture then return end
	rememberCap(texture)
	texture:SetTexture(ART.gryphon)
	if side == "left" then
		texture:SetTexCoord(0, 1, ART_TOP, 1)
	else
		texture:SetTexCoord(1, 0, ART_TOP, 1)
	end
	texture:SetSize(CAP_WIDTH, CAP_HEIGHT)
	texture:ClearAllPoints()
	if anchored then
		local parent = texture:GetParent()
		if side == "left" then
			texture:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", CAP_INSET_X, CAP_OFFSET_Y)
		else
			texture:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", -CAP_INSET_X, CAP_OFFSET_Y)
		end
	else
		-- the art is 6px wider than the 154x95 frame: centred, not stretched
		texture:SetPoint("BOTTOM", cap, "BOTTOM", 0, 0)
	end
end

local function modernCap(cap)
	local texture = capTexture(cap)
	local state = texture and modernCaps[texture]
	if not state then return end
	texture:SetTexCoord(0, 1, 0, 1)
	if state.atlas then texture:SetAtlas(state.atlas) end
	texture:SetSize(state.width, state.height)
	texture:ClearAllPoints()
	if #state.points == 0 then
		texture:SetAllPoints(cap)
	else
		for _, p in ipairs(state.points) do texture:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
	end
end

local function applyGryphons()
	local _, left, right = getCaps()
	if not left then return end
	local wanted = CUF.db.actionBars.gryphons and CUF:TextureExists(ART.gryphon)
	if wanted then
		gryphonsOn = true
		if not gryphonsHooked then
			gryphonsHooked = true
			-- Blizzard puts its own caps back when the bar shows, when Edit
			-- Mode refreshes the bar art and when a faction is picked.
			CUF.Hook(_G.MainActionBar, "UpdateEndCaps", function()
				if gryphonsOn then
					classicCap(select(2, getCaps()), "left")
					classicCap(select(3, getCaps()), "right")
				end
			end)
		end
		classicCap(left, "left")
		classicCap(right, "right")
	elseif gryphonsOn then
		gryphonsOn = false
		modernCap(left)
		modernCap(right)
	end
end

-- ---------------------------------------------------------------------------
-- setup
-- ---------------------------------------------------------------------------

function Bars:Initialize()
	Bars.missing = nil
	if CUF.db.actionBars.enabled and _G.MainActionBar then
		if CUF:TextureExists(ART.strip) and CUF:TextureExists(ART.quickslot2) then
			skinBars()
			skinMainBar()
			Bars.skinned = true
		else
			Bars.missing = true
			CUF:Print("this client does not ship the vanilla action bar art; the modern bars are kept.")
		end
	end
	applyGryphons()
end

function Bars:ApplySettings()
	if Bars.skinned then
		for button in pairs(cells) do applyText(button) end
	end
	applyGryphons()
end

-- /cuf bars
function Bars:SkinAll()
	if Bars.skinned then
		for button in pairs(cells) do pcall(applyButtonArt, button) end
	end
	applyGryphons()
	return Bars.count or 0
end

function Bars:Diagnostics()
	CUF:Print("---- action bars ----")
	CUF:Print(("vanilla strip art: %s   frame art: %s   gryphon art: %s"):format(
		CUF:TextureExists(ART.strip) and "|cff00ff00present|r" or "|cffff0000MISSING|r",
		CUF:TextureExists(ART.quickslot2) and "|cff00ff00present|r" or "|cffff0000MISSING|r",
		CUF:TextureExists(ART.gryphon) and "|cff00ff00present|r" or "|cffff0000MISSING|r"))
	CUF:Print(("buttons skinned: %d   gryphons: %s   end caps found: %s"):format(
		Bars.count or 0, gryphonsOn and "on" or "off", getCaps() and "yes" or "|cffff0000no|r"))
	for _, name in ipairs({ "BagsBar", "MicroMenu", "XPBar" }) do
		local part = CUF[name]
		if part and part.state then CUF:Print(("%s: %s"):format(name, part.state)) end
	end
end
