--[[ The vanilla bag slots on Blizzard's bags bar.

	Vanilla's backpack and bag slots were equal square item buttons as large
	as its action slots (37px icons, 5px apart, on the bar strip's 42px
	cells).  The modern bar draws a large round backpack and small round bag
	slots, so every slot is sized to an action button (45px) with a square
	icon inset to vanilla's 37-in-42, inside the UI-Quickslot2 item frame,
	with the pushed art, the square highlight and the checked glow of an open
	bag.  The backpack gets vanilla's Button-Backpack-Up icon and an empty
	slot the paper doll's empty bag icon.  Each slot sits on a gryphon cell of
	the bar strip, and the key ring gets vanilla's UI-Button-KeyRing art in a
	narrow cell, spaced from the bags as the bags are from each other.

	Blizzard puts its round art back from each slot's UpdateTextures and
	re-lays the bar out from BagsBar:Layout; both are hooked.  The bag
	buttons are only resized out of combat, and switching this off needs a
	reload.
]]

local CUF = SquawkClassicUF
local BagsBar = {}
CUF.BagsBar = BagsBar

local SetFile = CUF.SetFile

local ART = {
	backpack        = "Interface\\Buttons\\Button-Backpack-Up",
	emptyBag        = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag",
	keyRing         = "Interface\\Buttons\\UI-Button-KeyRing",
	keyRingPushed   = "Interface\\Buttons\\UI-Button-KeyRing-Down",
	keyRingGlow     = "Interface\\Buttons\\UI-Button-KeyRing-Highlight",
}

local SLOT_SIZE = 45
local ICON_RATIO = 37 / 42
local NORMAL_RATIO = 64 / 37           -- ItemButtonTemplate's frame to icon
local FRAME_ART_BIAS = 0.5 / 64
local COUNT_X, COUNT_Y = 1, -7         -- the backpack's free slots, 7px under the icon's centre
-- UI-Button-KeyRing: an 18x39 ring in the top left of a 32x64 file
local KEYRING_WIDTH, KEYRING_HEIGHT = 18, 39
local KEYRING_COORDS = { 0, 18 / 32, 0, 39 / 64 }

local cells = setmetatable({}, { __mode = "k" })
local keyRingCell

local function round(x) return math.floor(x + 0.5) end
local function iconSize() return round(SLOT_SIZE * ICON_RATIO) end

local function fillIcon(texture, button)
	if not texture then return end
	texture:ClearAllPoints()
	texture:SetAllPoints(button.icon)
end

-- After Blizzard's UpdateTextures, which puts the round art back on every
-- icon or bag change.
local function applySlotArt(button)
	local art = CUF.ActionBars.ART
	local icon = button.icon
	if button == _G.MainMenuBarBackpackButton then
		icon:SetTexture(ART.backpack)
		icon:Show()
	elseif not GetInventoryItemTexture("player", button:GetID()) then
		icon:SetTexture(ART.emptyBag)
		icon:Show()
	end

	local normal = button:GetNormalTexture()
	if normal then
		local size = round(iconSize() * NORMAL_RATIO)
		local shift = size * FRAME_ART_BIAS
		SetFile(normal, art.quickslot2)
		normal:ClearAllPoints()
		normal:SetSize(size, size)
		normal:SetPoint("CENTER", icon, "CENTER", shift, -shift)
	end
	local pushed = button:GetPushedTexture()
	if pushed then
		SetFile(pushed, art.pushed)
		fillIcon(pushed, button)
	end
	local highlight = button:GetHighlightTexture()
	if highlight then
		SetFile(highlight, art.highlight)
		highlight:SetBlendMode("ADD")
		highlight:SetAlpha(1)
		fillIcon(highlight, button)
	end
	-- shown while the bag is open, where vanilla checked its button
	local open = button.SlotHighlightTexture
	if open then
		SetFile(open, art.checked)
		open:SetBlendMode("ADD")
		fillIcon(open, button)
	end
end

local function fitContextOverlay(button)
	fillIcon(button.ItemContextOverlay, button)
end

local function skinSlot(button, index)
	local icon = button.icon
	if not icon then return end

	button:SetSize(SLOT_SIZE, SLOT_SIZE)
	CUF.StripMask(button.CircleMask, icon, button.searchOverlay, button.ItemContextOverlay)
	CUF.StripMask(button.SquareMask, icon)
	local size = iconSize()
	icon:ClearAllPoints()
	icon:SetSize(size, size)
	icon:SetPoint("CENTER", button, "CENTER", 0, 0)
	fillIcon(button.searchOverlay, button)
	fillIcon(button.ItemContextOverlay, button)
	fillIcon(button.AnimIcon, button)
	if button == _G.MainMenuBarBackpackButton and button.Count then
		button.Count:ClearAllPoints()
		button.Count:SetPoint("CENTER", icon, "CENTER", COUNT_X, COUNT_Y)
	end

	cells[button] = CUF.ActionBars.CreateStripCell(button, index)

	CUF.Hook(button, "UpdateTextures", applySlotArt)
	CUF.Hook(button, "UpdateItemContextOverlayTextures", fitContextOverlay)
	applySlotArt(button)
end

-- the ring, scaled with the icons (vanilla drew it beside 37px bag icons)
local function keyRingSize()
	local scale = iconSize() / 37
	return KEYRING_WIDTH * scale, KEYRING_HEIGHT * scale
end

-- The slot is narrowed to the ring plus the bag slots' own margin, which
-- spaces it from the last bag as the bags are spaced from each other.  Runs
-- after Blizzard's UpdateOrientation, which re-sizes it on every layout.
local function sizeKeyRing(button, isHorizontal)
	local width, height = keyRingSize()
	local margin = SLOT_SIZE - iconSize()
	if isHorizontal then
		button:SetSize(width + margin, SLOT_SIZE)
	else
		button:SetSize(SLOT_SIZE, height + margin)
	end
end

-- Blizzard turns the ring sideways in a vertical bar; vanilla's stays upright.
local function applyKeyRingArt(button)
	if button.icon then button.icon:SetAlpha(0) end
	local width, height = keyRingSize()
	for _, entry in ipairs({
		{ button:GetNormalTexture(), ART.keyRing },
		{ button:GetPushedTexture(), ART.keyRingPushed },
		{ button:GetHighlightTexture(), ART.keyRingGlow, true },
		{ button.SlotHighlightTexture, ART.keyRingGlow, true },
	}) do
		local texture = entry[1]
		if texture then
			SetFile(texture, entry[2], unpack(KEYRING_COORDS))
			texture:SetRotation(0)
			if entry[3] then
				texture:SetBlendMode("ADD")
				texture:SetAlpha(1)
			end
			texture:ClearAllPoints()
			texture:SetSize(width, height)
			texture:SetPoint("CENTER", button, "CENTER", 0, 0)
		end
	end
end

local function layoutCells()
	local bar = _G.BagsBar
	local padding = tonumber(bar.bagPadding) or 0
	local vertical = bar.isHorizontal == false
	for button, cell in pairs(cells) do
		CUF.ActionBars.SizeStripCell(cell, button:GetWidth(), padding, vertical)
	end
	if keyRingCell and _G.KeyRingButton then
		CUF.ActionBars.SizeNarrowStripCell(keyRingCell, _G.KeyRingButton, padding, vertical)
	end
end

-- Blizzard measured the bar from the round slots on its first layout; its
-- later layouts measure the new ones.
local function fitBar()
	local bar = _G.BagsBar
	if not (bar.GetBagBarLength and bar.initialHeight) then return end
	local length = bar:GetBagBarLength()
	if bar.isHorizontal == false then
		bar:SetSize(bar.initialHeight, length)
	else
		bar:SetSize(length, bar.initialHeight)
	end
end

local function skin()
	local bar = _G.BagsBar
	-- the bags sit on the modern plate on this client
	if bar.BorderArt then bar.BorderArt:SetAlpha(0) end
	if bar.UpdateDividers then
		CUF.Hook(bar, "UpdateDividers", CUF.ActionBars.HideBarDividers)
		CUF.ActionBars.HideBarDividers(bar)
	end

	for index, button in _G.MainMenuBarBagManager:EnumerateBagButtons() do
		if button == _G.KeyRingButton then
			CUF.Hook(button, "UpdateTextures", applyKeyRingArt)
			CUF.Hook(button, "UpdateOrientation", function(self, isHorizontal)
				sizeKeyRing(self, isHorizontal)
				applyKeyRingArt(self)
			end)
			sizeKeyRing(button, button:GetWidth() < button:GetHeight())
			applyKeyRingArt(button)
			keyRingCell = CUF.ActionBars.CreateNarrowStripCell(button)
		else
			skinSlot(button, index)
		end
	end
	layoutCells()
	fitBar()
	CUF.Hook(bar, "Layout", layoutCells)
	BagsBar.state = "vanilla slots on"
end

function BagsBar:Initialize()
	if not CUF.db.actionBars.bags then
		BagsBar.state = "off"
		return
	end
	if not (_G.BagsBar and _G.MainMenuBarBagManager and _G.MainMenuBarBackpackButton) then
		BagsBar.state = "|cffff0000no bags bar on this client|r"
		return
	end
	local art = CUF.ActionBars.ART
	if not CUF:TextureExists(art.quickslot2) or not CUF:TextureExists(art.strip) then
		BagsBar.state = "|cffff0000vanilla slot art missing|r"
		return
	end
	CUF:RunProtected(skin)
end
