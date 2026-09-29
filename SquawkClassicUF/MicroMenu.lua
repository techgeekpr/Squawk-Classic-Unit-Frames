--[[ The classic micro menu on Blizzard's own micro buttons.

	  * Each button gets its Interface\Buttons\UI-MicroButton-<name> Up / Down
	    / Disabled files and the UI-MicroButton-Hilight glow over it, and the
	    character button the empty UI-MicroButtonCharacter frame with your
	    portrait in it.
	  * Buttons map to the classic button of the same window: spellbook,
	    talents, achievements, quest log, socials for the guild, the group
	    finder eye, mounts for collections, the dungeon journal, the shop,
	    help and the main menu.  This client only ships the later redraws of
	    the main menu, quest log and socials pictures, so those three show
	    them.  Professions and housing never had a micro button; they get the
	    empty portrait frame with an icon in it.
	  * The alert pulse flashes the classic Micro-Highlight glow.
	  * The buttons sit on the flat stone panel of the vanilla bar strip,
	    closed by its plain column at both ends, in place of the modern plate.
	    It follows Edit Mode's orientation and size and hides while a vehicle
	    or pet battle bar borrows the menu.

	Blizzard sets the art through the buttons' Set*Atlas methods (on load,
	on press and release, and every second on the main menu button), which
	are hooked so the classic file goes back each time.  Switching this off
	needs a reload.
]]

local CUF = SquawkClassicUF
local Micro = {}
CUF.MicroMenu = Micro

local SetFile = CUF.SetFile

local ART = {
	button     = "Interface\\Buttons\\UI-MicroButton-",           -- + <name>-Up / -Down / -Disabled
	frame      = "Interface\\Buttons\\UI-MicroButtonCharacter-",  -- + Up / Down: the empty portrait frame
	highlight  = "Interface\\Buttons\\UI-MicroButton-Hilight",
	flash      = "Interface\\Buttons\\Micro-Highlight",
	professions = "Interface\\Icons\\Trade_BlackSmithing",
	housing    = "Interface\\Icons\\INV_Misc_Rune_01",
}

local BUTTONS = {
	CharacterMicroButton    = { portrait = true },
	ProfessionMicroButton   = { icon = ART.professions },
	PlayerSpellsMicroButton = { file = "Talents" },
	SpellbookMicroButton    = { file = "Spellbook" },
	TalentMicroButton       = { file = "Talents" },
	AchievementMicroButton  = { file = "Achievement" },
	LegacyMicroButton       = { file = "Achievement" },
	QuestLogMicroButton     = { file = "Quest" },
	HousingMicroButton      = { icon = ART.housing },
	GuildMicroButton        = { file = "Socials" },
	LFDMicroButton          = { file = "LFG" },
	CollectionsMicroButton  = { file = "Mounts" },
	EJMicroButton           = { file = "EJ" },
	HelpMicroButton         = { file = "Help" },
	StoreMicroButton        = { file = "BStore" },
	MainMenuMicroButton     = { file = "MainMenu" },
}

-- The 32x64 files hold a 32x41 button in their bottom rows.  Vanilla drew
-- them 29px wide and 26px apart; the modern buttons are 27px apart, so the
-- art is drawn at 30px to keep vanilla's overlap between neighbours.
local ART_TOP = 23 / 64
local ART_SCALE = 30 / 32
local ART_WIDTH, ART_HEIGHT = 32 * ART_SCALE, 41 * ART_SCALE
-- vanilla's portrait: 18x25, 28px below the top of its 29x58 button
local FILE_SCALE = 32 / 29
local INSET_WIDTH = 18 * FILE_SCALE * ART_SCALE
local INSET_HEIGHT = 25 * FILE_SCALE * ART_SCALE
local INSET_Y = ART_HEIGHT / 2 - (28 * FILE_SCALE - 23) * ART_SCALE
local PORTRAIT_COORDS = { 0.2, 0.8, 0.0666, 0.9 }
local ICON_COORDS = { 0.2, 0.8, 0.1, 0.92 }
local PUSHED_SHIFT = 0.0666
local FLASH_SCALE = ART_WIDTH / 29

local specs = setmetatable({}, { __mode = "k" })
local insets = setmetatable({}, { __mode = "k" })

local function placeArt(texture, button)
	texture:SetTexCoord(0, 1, ART_TOP, 1)
	texture:SetVertexColor(1, 1, 1)   -- the guild button is tinted with the tabard colour
	texture:ClearAllPoints()
	texture:SetSize(ART_WIDTH, ART_HEIGHT)
	texture:SetPoint("CENTER", button, "CENTER", 0, 0)
end

local function applyNormal(button)
	button:SetNormalTexture(specs[button].up)
	local texture = button:GetNormalTexture()
	if texture then placeArt(texture, button) end
end

local function applyPushed(button)
	button:SetPushedTexture(specs[button].down)
	local texture = button:GetPushedTexture()
	if texture then placeArt(texture, button) end
end

local function applyDisabled(button)
	local spec = specs[button]
	button:SetDisabledTexture(spec.disabled)
	local texture = button:GetDisabledTexture()
	if texture then
		placeArt(texture, button)
		texture:SetDesaturated(spec.desaturate)
	end
end

local function applyHighlight(button)
	button:SetHighlightTexture(ART.highlight, "ADD")
	local texture = button:GetHighlightTexture()
	if texture then placeArt(texture, button) end
end

-- The portrait / icon in the frame's window; pressed, it shifts and dims
-- like vanilla's.
local function updateInset(button)
	local inset = insets[button]
	if not inset then return end
	local l, r, t, b = unpack(specs[button].coords)
	if button:GetButtonState() == "PUSHED" then
		inset:SetTexCoord(l + PUSHED_SHIFT, r + PUSHED_SHIFT, t - PUSHED_SHIFT, b - PUSHED_SHIFT)
		inset:SetAlpha(0.5)
	else
		inset:SetTexCoord(l, r, t, b)
		inset:SetAlpha(1)
	end
	inset:ClearAllPoints()
	inset:SetSize(INSET_WIDTH, INSET_HEIGHT)
	inset:SetPoint("TOP", button, "CENTER", 0, INSET_Y)
end

-- Blizzard dims the highlight while the button is down; the classic glow
-- stays full.
local function onButtonState(button)
	local highlight = button:GetHighlightTexture()
	if highlight then highlight:SetAlpha(1) end
	updateInset(button)
end

local function applyAll(button)
	applyNormal(button)
	applyPushed(button)
	applyDisabled(button)
	applyHighlight(button)
	onButtonState(button)
end

local function hideRegion(region)
	if region then region:SetAlpha(0) end
end

local function skinFlash(button)
	local flash = button.FlashBorder
	if flash then
		SetFile(flash, ART.flash)
		flash:SetBlendMode("ADD")
		flash:ClearAllPoints()
		flash:SetSize(64 * FLASH_SCALE, 64 * FLASH_SCALE)
		flash:SetPoint("TOPLEFT", button, "CENTER", -ART_WIDTH / 2 - 2 * FLASH_SCALE, ART_HEIGHT / 2 + 2 * FLASH_SCALE)
	end
	if button.FlashContent then button.FlashContent:SetTexture(nil) end
end

local function createIcon(button, file)
	local icon = button:CreateTexture(nil, "OVERLAY")
	icon:SetTexture(file)
	-- classic greyed out a disabled button's picture
	button:HookScript("OnEnable", function() icon:SetDesaturated(false) end)
	button:HookScript("OnDisable", function() icon:SetDesaturated(true) end)
	icon:SetDesaturated(not button:IsEnabled())
	return icon
end

local function skinButton(button, entry)
	local spec = {}
	if entry.file then
		local prefix = ART.button .. entry.file
		if not CUF:TextureExists(prefix .. "-Up") then return end
		spec.up, spec.down, spec.disabled = prefix .. "-Up", prefix .. "-Down", prefix .. "-Disabled"
		spec.desaturate = false
	else
		spec.up, spec.down, spec.disabled = ART.frame .. "Up", ART.frame .. "Down", ART.frame .. "Up"
		spec.desaturate = true
	end
	specs[button] = spec

	hideRegion(button.Background)
	hideRegion(button.PushedBackground)
	hideRegion(button.Shadow)
	hideRegion(button.PushedShadow)
	hideRegion(button.Emblem)
	hideRegion(button.HighlightEmblem)
	skinFlash(button)

	if entry.portrait and button.Portrait then
		CUF.StripMask(button.PortraitMask, button.Portrait)
		button.Portrait:SetDrawLayer("OVERLAY")
		insets[button] = button.Portrait
		spec.coords = PORTRAIT_COORDS
	elseif entry.icon then
		insets[button] = createIcon(button, entry.icon)
		spec.coords = ICON_COORDS
	end

	CUF.Hook(button, "SetNormalAtlas", applyNormal)
	CUF.Hook(button, "SetPushedAtlas", applyPushed)
	CUF.Hook(button, "SetDisabledAtlas", applyDisabled)
	CUF.Hook(button, "SetHighlightAtlas", applyHighlight)
	CUF.Hook(button, "SetPushed", onButtonState)
	CUF.Hook(button, "SetNormal", onButtonState)
	CUF.Hook(button, "UpdateTabard", applyAll)
	-- the modern hover hides the normal picture; the classic glow goes over it
	button:HookScript("OnEnter", function(self)
		local normal = self:GetNormalTexture()
		if normal then normal:SetAlpha(1) end
	end)
	applyAll(button)
	Micro.count = (Micro.count or 0) + 1
end

-- ---------------------------------------------------------------------------
-- the stone panel
--
-- UI-MainMenuBar-Dwarf pieces: the flat panel vanilla's micro buttons sat on
-- (piece 3) and the plain column where it ends (piece 4), mirrored for the
-- other end.  Scaled with the art; vanilla's buttons sat 2px above the
-- strip's bottom, 4px below its top and 3px from the column.
-- ---------------------------------------------------------------------------

local PANEL_FLAT = { 40 / 256, 256 / 256, 85 / 256, 128 / 256 }
local PANEL_END = { 82 / 256, 93 / 256, 21 / 256, 64 / 256 }
local STRIP_SCALE = ART_WIDTH / 29
local PANEL_DEPTH = 43 * STRIP_SCALE
local PANEL_END_LENGTH = 11 * STRIP_SCALE
local PANEL_SHIFT = 1 * STRIP_SCALE
local PANEL_MARGIN = 3 * STRIP_SCALE - (32 - ART_WIDTH) / 2

local panel

-- a file region (l > r mirrors it), turned a quarter for a vertical menu
local function stripCoords(texture, coords, mirrored, vertical)
	local l, r, t, b = unpack(coords)
	if mirrored then l, r = r, l end
	if vertical then
		texture:SetTexCoord(l, b, r, b, l, t, r, t)
	else
		texture:SetTexCoord(l, t, l, b, r, t, r, b)
	end
end

local function layoutPanel()
	local menu = _G.MicroMenu
	local shown = menu:GetParent() == _G.MicroMenuContainer
	local flat, first, last = unpack(panel)
	for _, texture in ipairs(panel) do
		texture:SetShown(shown)
		texture:ClearAllPoints()
	end
	if not shown then return end

	local vertical = menu.isHorizontal == false
	stripCoords(flat, PANEL_FLAT, false, vertical)
	stripCoords(first, PANEL_END, true, vertical)
	stripCoords(last, PANEL_END, false, vertical)
	if vertical then
		flat:SetPoint("TOPLEFT", menu, "TOP", PANEL_SHIFT - PANEL_DEPTH / 2, PANEL_MARGIN)
		flat:SetPoint("BOTTOMRIGHT", menu, "BOTTOM", PANEL_SHIFT + PANEL_DEPTH / 2, -PANEL_MARGIN)
		first:SetSize(PANEL_DEPTH, PANEL_END_LENGTH)
		first:SetPoint("BOTTOMLEFT", flat, "TOPLEFT")
		last:SetSize(PANEL_DEPTH, PANEL_END_LENGTH)
		last:SetPoint("TOPLEFT", flat, "BOTTOMLEFT")
	else
		flat:SetPoint("TOPLEFT", menu, "LEFT", -PANEL_MARGIN, PANEL_SHIFT + PANEL_DEPTH / 2)
		flat:SetPoint("BOTTOMRIGHT", menu, "RIGHT", PANEL_MARGIN, PANEL_SHIFT - PANEL_DEPTH / 2)
		first:SetSize(PANEL_END_LENGTH, PANEL_DEPTH)
		first:SetPoint("TOPRIGHT", flat, "TOPLEFT")
		last:SetSize(PANEL_END_LENGTH, PANEL_DEPTH)
		last:SetPoint("TOPLEFT", flat, "TOPRIGHT")
	end
end

local function createPanel()
	local strip = CUF.ActionBars.ART.strip
	if not CUF:TextureExists(strip) then return end
	local menu = _G.MicroMenu
	panel = {}
	for i = 1, 3 do
		local texture = menu:CreateTexture(nil, "BACKGROUND", nil, -8)
		texture:SetTexture(strip)
		panel[i] = texture
	end
	CUF.Hook(menu, "Layout", layoutPanel)
	CUF.Hook(menu, "OverrideMicroMenuPosition", layoutPanel)
	CUF.Hook(menu, "ResetMicroMenuPosition", layoutPanel)
	layoutPanel()
end

function Micro:Initialize()
	if not CUF.db.actionBars.microMenu then
		Micro.state = "off"
		return
	end
	if not _G.MicroMenu then
		Micro.state = "|cffff0000no micro menu on this client|r"
		return
	end
	if not CUF:TextureExists(ART.highlight) or not CUF:TextureExists(ART.frame .. "Up") then
		Micro.state = "|cffff0000classic micro button art missing|r"
		return
	end
	Micro.count = 0
	for name, entry in pairs(BUTTONS) do
		local button = _G[name]
		if type(button) == "table" and button.GetNormalTexture then
			skinButton(button, entry)
		end
	end
	hideRegion(_G.MicroMenu.BorderArt)
	hideRegion(_G.MicroMenu.BackgroundArt)
	createPanel()
	Micro.state = ("%d classic buttons"):format(Micro.count or 0)
end
