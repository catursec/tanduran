--[[ registry.lua — opsi dropdown pet type & mutation. ]]
return function(ctx)
	local PetEggs   = ctx.deps.PetEggs
	local EnumToMut = ctx.deps.EnumToMut

	-- Daftar pet type unik (nama saja, tanpa egg) untuk filter trade.
	-- + peta pet->egg (buat label "Pet - Egg" di filter sell).
	local PET_OPTIONS = {}
	local petEggMap = {}   -- petType -> eggName (egg pertama yg punya pet ini)
	do
		local seen = {}
		for eggName, egg in pairs(PetEggs) do
			local items = egg.RarityData and egg.RarityData.Items
			if items then
				-- skip egg catch-all/admin (mis. "Fake Egg" isi 431 pet) dari peta pet->egg
				local cnt = 0; for _ in pairs(items) do cnt = cnt + 1 end
				local realEgg = eggName ~= "Fake Egg" and cnt <= 40
				for petName in pairs(items) do
					local s = tostring(petName):match("([^/]+)$") or tostring(petName)
					if not tostring(petName):match("^Egg/") and not seen[s] then
						seen[s] = true
						PET_OPTIONS[#PET_OPTIONS + 1] = s
					end
					if realEgg and not petEggMap[s] then petEggMap[s] = eggName end
				end
			end
		end
		table.sort(PET_OPTIONS)
	end

	-- Opsi filter sell: "Pet - Egg". Label = value (dipakai sbg key filter).
	local PET_EGG_OPTIONS = {}
	for _, pt in ipairs(PET_OPTIONS) do
		local egg = petEggMap[pt]
		PET_EGG_OPTIONS[#PET_EGG_OPTIONS + 1] = egg and (pt .. " - " .. egg) or pt
	end
	local function petEggLabel(pt)
		local egg = petEggMap[pt]
		return egg and (pt .. " - " .. egg) or pt
	end

	-- CUMA pet yang punya egg asli (format "Pet - Egg"). Buat filter yang wajib ada egg-nya
	-- (Special Pets, Universal, Pet to Sell) — pet tanpa egg tidak ditampilkan.
	local PET_EGG_ONLY = {}
	for _, pt in ipairs(PET_OPTIONS) do
		if petEggMap[pt] then PET_EGG_ONLY[#PET_EGG_ONLY + 1] = pt .. " - " .. petEggMap[pt] end
	end

	local MUT_OPTIONS, seenMut = { "None" }, { None = true }
	for _, name in pairs(EnumToMut) do
		if name ~= "Normal" and not seenMut[name] then
			seenMut[name] = true
			MUT_OPTIONS[#MUT_OPTIONS + 1] = name
		end
	end
	table.sort(MUT_OPTIONS)

	-- Mutasi yang bisa dari mesin: MachineMutationTypes (base) + Level500MutationTypes (500 only).
	local MACHINE_MUT_OPTIONS = { "None" }
	do
		local ok, MutReg = pcall(function()
			return require(game:GetService("ReplicatedStorage").Data.PetRegistry.PetMutationRegistry)
		end)
		local names, seen = {}, {}
		if ok and MutReg then
			for _, src in ipairs({ MutReg.MachineMutationTypes, MutReg.Level500MutationTypes }) do
				if type(src) == "table" then
					for name in pairs(src) do
						local n = tostring(name)
						if not seen[n] then seen[n] = true; names[#names + 1] = n end
					end
				end
			end
			-- Ice Golem-exclusive dari Mutation Machine (via passive Cold Gears): ada di
			-- PetMutationRegistry tapi bukan di MachineMutationTypes/Level500 -> tambah manual.
			for _, n in ipairs({ "ChristmasRally", "JollyDecorator", "MerryNursery", "GiantGolem" }) do
				local pmr = MutReg.PetMutationRegistry
				if type(pmr) == "table" and pmr[n] and not seen[n] then
					seen[n] = true; names[#names + 1] = n
				end
			end
		end
		if #names > 0 then
			table.sort(names)
			for _, n in ipairs(names) do MACHINE_MUT_OPTIONS[#MACHINE_MUT_OPTIONS + 1] = n end
		else
			MACHINE_MUT_OPTIONS = MUT_OPTIONS -- fallback: semua mutasi
		end
	end

	local function mutDisplay(code)
		if code == nil or code == "" or code == "m" or code == "None" or code == "Normal" then return "None" end
		return EnumToMut[code] or code
	end

	ctx.reg = {
		PET_OPTIONS = PET_OPTIONS,
		PET_EGG_OPTIONS = PET_EGG_OPTIONS,
		PET_EGG_ONLY = PET_EGG_ONLY,
		petEggLabel = petEggLabel,
		MUT_OPTIONS = MUT_OPTIONS,
		MACHINE_MUT_OPTIONS = MACHINE_MUT_OPTIONS,
		mutDisplay = mutDisplay,
	}
end
