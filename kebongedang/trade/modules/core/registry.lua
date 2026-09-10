--[[ registry.lua — bangun opsi dropdown dari data game.
     Mengisi: ctx.reg = { comboKey, mutDisplay, PET_OPTIONS, MUT_OPTIONS, SKIN_OPTIONS } ]]
return function(ctx)
	local PetEggs   = ctx.deps.PetEggs
	local PetList   = ctx.deps.PetList or {}
	local EnumToMut = ctx.deps.EnumToMut
	local SkinsReg  = ctx.deps.SkinsReg

	-- Map nama pet -> asset id icon (dari PetList[pet].Icon = "rbxassetid://123").
	local PET_ICONS = {}
	for petName, d in pairs(PetList) do
		if type(d) == "table" and d.Icon then
			local id = tostring(d.Icon):match("(%d+)")
			if id then PET_ICONS[tostring(petName)] = id end
		end
	end

	-- opsi dropdown = kombinasi "Pet - Egg"
	local function comboKey(petType, egg)
		return tostring(petType) .. " - " .. tostring(egg)
	end

	----------------------------------------------------------------- PET_OPTIONS
	local PET_OPTIONS = {}
	do
		local seen = {}
		for eggName, egg in pairs(PetEggs) do
			local items = egg.RarityData and egg.RarityData.Items
			if items then
				for petName in pairs(items) do
					if not tostring(petName):match("^Egg/") then
						local nameStr = tostring(petName)
						if not seen[nameStr] then
							seen[nameStr] = true
							PET_OPTIONS[#PET_OPTIONS + 1] = nameStr
						end
					end
				end
			end
		end
		table.sort(PET_OPTIONS)
	end

	----------------------------------------------------------------- PET_COMBO_OPTIONS (Pet - Egg)
	-- Bedakan pet per egg (premium vs biasa). Dipakai snipe biar bisa target spesifik.
	local PET_COMBO_OPTIONS = {}
	do
		local seen = {}
		for eggName, egg in pairs(PetEggs) do
			local items = egg.RarityData and egg.RarityData.Items
			if items then
				for petName in pairs(items) do
					if not tostring(petName):match("^Egg/") then
						local k = comboKey(petName, eggName)
						if not seen[k] then seen[k] = true; PET_COMBO_OPTIONS[#PET_COMBO_OPTIONS + 1] = k end
					end
				end
			end
		end
		table.sort(PET_COMBO_OPTIONS)
	end

	----------------------------------------------------------------- MUT_OPTIONS
	local MUT_OPTIONS, seenMut = { "None" }, { None = true }
	for _, name in pairs(EnumToMut) do
		if name ~= "Normal" and not seenMut[name] then
			seenMut[name] = true
			MUT_OPTIONS[#MUT_OPTIONS + 1] = name
		end
	end
	table.sort(MUT_OPTIONS)

	----------------------------------------------------------------- SKIN_OPTIONS
	local SKIN_OPTIONS = {}
	for name, data in pairs(SkinsReg) do
		SKIN_OPTIONS[#SKIN_OPTIONS + 1] = { name = name, display = data.DisplayName or name }
	end
	table.sort(SKIN_OPTIONS, function(a, b) return a.display < b.display end)

	----------------------------------------------------------------- mutDisplay
	local function mutDisplay(code)
		if code == nil or code == "" or code == "m" or code == "None" or code == "Normal" then
			return "None"
		end
		return EnumToMut[code] or code
	end

	ctx.reg = {
		comboKey          = comboKey,
		mutDisplay        = mutDisplay,
		PET_OPTIONS       = PET_OPTIONS,
		PET_COMBO_OPTIONS = PET_COMBO_OPTIONS,
		PET_ICONS         = PET_ICONS,
		MUT_OPTIONS       = MUT_OPTIONS,
		SKIN_OPTIONS      = SKIN_OPTIONS,
	}
end
