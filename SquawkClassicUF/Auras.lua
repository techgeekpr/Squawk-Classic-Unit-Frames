--[[ Raid frame aura watching: buffs you can give that are missing, and
     debuffs you can remove.

	Whether an addon may read auras at all on this client is not documented
	anywhere I can find, and it may differ in and out of combat, so every read
	goes through readAuras, which reports failure instead of throwing.  When
	reads are blocked the indicators simply stay hidden; /cuf auradiag says
	which it is.
]]

local CUF = SquawkClassicUF
local Auras = {}
CUF.Auras = Auras

-- Buffs each class can hand out, with the icon hardcoded so no spell lookup
-- API is involved.  A unit missing every name in a group counts as missing
-- that buff -- which is how one entry covers rank upgrades and the greater
-- or group versions.
Auras.ClassBuffs = {
	MAGE = {
		{ label = "Arcane Intellect", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
		  names = { "Arcane Intellect", "Arcane Brilliance" } },
	},
	PRIEST = {
		{ label = "Fortitude", icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
		  names = { "Power Word: Fortitude", "Prayer of Fortitude" } },
		{ label = "Divine Spirit", icon = "Interface\\Icons\\Spell_Holy_DivineSpirit",
		  names = { "Divine Spirit", "Prayer of Spirit" }, optional = true },
	},
	DRUID = {
		{ label = "Mark of the Wild", icon = "Interface\\Icons\\Spell_Nature_Regeneration",
		  names = { "Mark of the Wild", "Gift of the Wild" } },
		{ label = "Thorns", icon = "Interface\\Icons\\Spell_Nature_Thorns",
		  names = { "Thorns" }, optional = true },
	},
	PALADIN = {
		-- Any blessing counts; which one is the paladin's business.
		{ label = "Blessing", icon = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings",
		  prefix = { "Blessing of", "Greater Blessing of" } },
	},
	WARRIOR = {
		{ label = "Battle Shout", icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
		  names = { "Battle Shout" }, optional = true },
	},
}

-- What each class can remove, by the dispel type the aura reports.
Auras.ClassDispels = {
	PRIEST  = { Magic = true, Disease = true },
	PALADIN = { Magic = true, Poison = true, Disease = true },
	DRUID   = { Curse = true, Poison = true },
	MAGE    = { Curse = true },
	SHAMAN  = { Poison = true, Disease = true },
}

Auras.DispelColors = {
	Magic   = { 0.20, 0.60, 1.00 },
	Curse   = { 0.60, 0.00, 1.00 },
	Disease = { 0.60, 0.40, 0.00 },
	Poison  = { 0.00, 0.60, 0.00 },
}

Auras.readable = nil   -- nil until the first attempt tells us

-- ---------------------------------------------------------------------------
-- guarded aura reading
-- ---------------------------------------------------------------------------

-- Walks a unit's auras, calling fn(name, dispelType, icon, count, index,
-- spellId) for each.  The index is the aura's real slot, which the tooltip
-- needs, and is not the same as the position it ends up drawn in.
-- Returns false if this client refused the read.
local function readAuras(unit, filter, fn)
	local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if byIndex then
		for index = 1, 40 do
			local ok, data = pcall(byIndex, unit, index, filter)
			if not ok then return false end
			if not data then return true end

			-- Any of these fields could be a secret; touching one throws.
			local readOk, name, dispel, icon, count, spellId = pcall(function()
				return tostring(data.name), data.dispelName, data.icon,
					data.applications, data.spellId
			end)
			if not readOk then return false end
			if fn(name, dispel, icon, count, index, spellId) then return true end
		end
		return true
	end

	if type(UnitAura) == "function" then
		for index = 1, 40 do
			local ok, name, icon, count, dispel, _, _, _, _, _, spellId =
				pcall(UnitAura, unit, index, filter)
			if not ok then return false end
			if not name then return true end
			if fn(tostring(name), dispel, icon, count, index, spellId) then return true end
		end
		return true
	end

	return false
end

-- Shared with the target frame's buff and debuff row.
-- fn(name, dispelType, icon, count); return true from fn to stop early.
function Auras:ForEach(unit, filter, fn)
	return readAuras(unit, filter, fn)
end

function Auras:CanRead(unit)
	local worked = readAuras(unit or "player", "HELPFUL", function() return false end)
	Auras.readable = worked
	return worked
end

-- ---------------------------------------------------------------------------
-- what this character can do
-- ---------------------------------------------------------------------------

function Auras:PlayerClass()
	if not Auras.class then
		local _, class = UnitClass("player")
		Auras.class = class
	end
	return Auras.class
end

function Auras:MyBuffs()
	local list = Auras.ClassBuffs[Auras:PlayerClass()] or {}
	local wanted = {}
	for _, buff in ipairs(list) do
		-- Optional buffs (talented or situational) are only watched when the
		-- player turns them on.
		if not buff.optional or CUF.db.raid.watchOptionalBuffs then
			wanted[#wanted + 1] = buff
		end
	end
	return wanted
end

function Auras:MyDispels()
	return Auras.ClassDispels[Auras:PlayerClass()]
end

-- ---------------------------------------------------------------------------
-- per-frame update
-- ---------------------------------------------------------------------------

local function matches(name, buff)
	if buff.names then
		for _, wanted in ipairs(buff.names) do
			if name == wanted then return true end
		end
	end
	if buff.prefix then
		for _, prefix in ipairs(buff.prefix) do
			if name:sub(1, #prefix) == prefix then return true end
		end
	end
	return false
end

function Auras:Update(frame)
	local unit = frame.unit
	if not frame.MissingIcon then return end

	local showMissing = CUF.db.raid.showMissingBuffs
	local showDispel = CUF.db.raid.showDispellable

	if not unit or not UnitExists(unit) or not UnitIsPlayer(unit)
		or UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
		frame.MissingIcon:Hide()
		frame.DispelIcon:Hide()
		frame.DispelGlow:Hide()
		return
	end

	-- buffs present on this unit
	local present, blocked = {}, false
	if showMissing then
		local ok = readAuras(unit, "HELPFUL", function(name)
			present[name] = true
			return false
		end)
		if not ok then blocked = true end
	end

	if showMissing and not blocked then
		local missing
		for _, buff in ipairs(Auras:MyBuffs()) do
			local found = false
			for name in pairs(present) do
				if matches(name, buff) then found = true break end
			end
			if not found then missing = buff break end
		end
		if missing then
			frame.MissingIcon:SetTexture(missing.icon)
			frame.MissingIcon.buffLabel = missing.label
			frame.MissingIcon:Show()
		else
			frame.MissingIcon:Hide()
		end
	else
		frame.MissingIcon:Hide()
	end

	-- debuffs this character can remove
	local dispels = Auras:MyDispels()
	if showDispel and dispels then
		local foundIcon, foundType
		local ok = readAuras(unit, "HARMFUL", function(name, dispelType, icon)
			if dispelType and dispels[dispelType] then
				foundIcon, foundType = icon, dispelType
				return true
			end
			return false
		end)
		if ok and foundType then
			frame.DispelIcon:SetTexture(foundIcon)
			frame.DispelIcon:Show()
			local color = Auras.DispelColors[foundType] or { 1, 1, 1 }
			frame.DispelGlow:SetBackdropBorderColor(color[1], color[2], color[3], 1)
			frame.DispelGlow:Show()
		else
			frame.DispelIcon:Hide()
			frame.DispelGlow:Hide()
		end
	else
		frame.DispelIcon:Hide()
		frame.DispelGlow:Hide()
	end
end

-- ---------------------------------------------------------------------------
-- diagnostics
-- ---------------------------------------------------------------------------

function Auras:Diagnostics()
	CUF:Print("---- auras ----")
	local class = Auras:PlayerClass() or "?"
	CUF:Print(("class: %s"):format(class))

	local readable = Auras:CanRead("player")
	CUF:Print(("aura reads: %s"):format(readable and "|cff00ff00allowed|r"
		or "|cffff0000blocked on this client - indicators cannot work|r"))
	CUF:Print(("C_UnitAuras.GetAuraDataByIndex: %s   UnitAura: %s"):format(
		(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) and "yes" or "no",
		type(UnitAura) == "function" and "yes" or "no"))

	local buffs = Auras:MyBuffs()
	if #buffs == 0 then
		CUF:Print("buffs watched: none for this class")
	else
		local names = {}
		for _, buff in ipairs(buffs) do names[#names + 1] = buff.label end
		CUF:Print("buffs watched: " .. table.concat(names, ", "))
	end

	local dispels = Auras:MyDispels()
	if dispels then
		local types = {}
		for kind in pairs(dispels) do types[#types + 1] = kind end
		table.sort(types)
		CUF:Print("can dispel: " .. table.concat(types, ", "))
	else
		CUF:Print("can dispel: nothing")
	end

	-- what is actually readable right now, on you and on your target
	if readable then
		local count = 0
		readAuras("player", "HELPFUL", function() count = count + 1 return false end)
		CUF:Print(("buffs readable on you right now: %d"):format(count))
	end

	if UnitExists("target") then
		local buffs, buffIcons, debuffs, debuffIcons = 0, 0, 0, 0
		readAuras("target", "HELPFUL", function(_, _, icon)
			buffs = buffs + 1
			if icon then buffIcons = buffIcons + 1 end
			return false
		end)
		readAuras("target", "HARMFUL", function(_, _, icon)
			debuffs = debuffs + 1
			if icon then debuffIcons = debuffIcons + 1 end
			return false
		end)
		CUF:Print(("target: %d buffs (%d with icons), %d debuffs (%d with icons)")
			:format(buffs, buffIcons, debuffs, debuffIcons))
		if buffs + debuffs > 0 and buffIcons + debuffIcons == 0 then
			CUF:Print("|cffff0000auras are listed but their icons are hidden|r - the target rows cannot draw")
		end
	else
		CUF:Print("target: none - target something and run this again")
	end
end
