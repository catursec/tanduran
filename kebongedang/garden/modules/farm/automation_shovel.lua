--[[ automation_shovel.lua — Auto Shovel (2 mode):
       1) Shovel Tree/Plant  : hapus plant dari tipe terpilih (CFG.shovelTreeNames).
       2) Shovel Fruit        : hapus plant kalau punya FRUIT yang cocok filter
                                (tipe + mutasi + variant + berat vs threshold).
     Mekanisme (dari remote spy + tes live): Remove_Item:FireServer(plant.PrimaryPart)
     — hapus SELURUH plant. Ga perlu equip Shovel (server terima langsung).
     Plant ada di workspace.Farm.<garden>.Important.Plants_Physical (nama = tipe).
     Tiap plant.Fruits berisi fruit models: child Weight (NumberValue), Variant (StringValue),
     + attribute mutasi boolean (Wet/Twisted/dll). ]]
return function(ctx)
	local RS  = game:GetService("ReplicatedStorage")
	local CFG = ctx.CFG
	local LP  = ctx.LP
	local Remove = RS:WaitForChild("GameEvents"):WaitForChild("Remove_Item")

	-- cari + equip Shovel dulu (server nolak kalau ga pegang shovel)
	local function findShovel()
		for _, where in ipairs({ LP.Character, LP:FindFirstChildOfClass("Backpack") }) do
			if where then
				for _, t in ipairs(where:GetChildren()) do
					if t:IsA("Tool") and tostring(t.Name):find("Shovel") then return t end
				end
			end
		end
	end
	local function heldShovel()
		local char = LP.Character
		if not char then return nil end
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and tostring(t.Name):find("Shovel") then return t end
		end
	end
	local function equipShovel()
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return false end
		if heldShovel() then return true end
		local sh = findShovel()
		if not sh then return false end
		pcall(function() hum:EquipTool(sh) end)
		task.wait(0.2)
		return heldShovel() ~= nil
	end

	-- Guard (mirip reclaimer): selama shovel aktif, Shovel WAJIB tetap kepegang.
	-- Kalau user pindah manual ke tool lain, langsung equip ulang (cek 0.25s).
	local guardRunning = false
	local function ensureGuard()
		if guardRunning then return end
		guardRunning = true
		task.spawn(function()
			while (CFG.shovelTreeEnabled or CFG.shovelFruitEnabled) and ctx.alive() do
				if not heldShovel() then equipShovel() end
				task.wait(0.25)
			end
			guardRunning = false
		end)
	end

	-- attribute fruit yang BUKAN mutasi (metadata) — dibuang pas listing opsi mutasi
	local NOT_MUTATION = {
		FruitVersion = true, MaxAge = true, GrowRateMulti = true, WeightMulti = true,
		DoneGrowTime = true, FruitSpawnIndex = true, OfflineGrowthTarget = true,
		MasteryGrowthMulti = true, MasterySizeMulti = true,
	}

	local function optionsFrom(names, allLabel)
		local out = { { value = "All", display = allLabel or "All" } }
		for _, n in ipairs(names) do out[#out + 1] = { value = n, display = n } end
		return out
	end

	-- iterasi plant di kebun MILIK SENDIRI. KRITIS: shovel nyabut tanaman -> JANGAN sampai
	-- kena kebun pemain lain. Semua garden namanya "Farm", dibedain lewat Important.Data.Owner.
	local function myGarden()
		local ok, GetFarm = pcall(function() return require(RS.Modules.GetFarm) end)
		if ok and GetFarm then local ok2, f = pcall(function() return GetFarm(LP) end); if ok2 and f then return f end end
		local Farm = workspace:FindFirstChild("Farm"); if not Farm then return nil end
		for _, g in ipairs(Farm:GetChildren()) do
			local d = g:FindFirstChild("Important") and g.Important:FindFirstChild("Data")
			local o = d and d:FindFirstChild("Owner")
			if o and o.Value == LP.Name then return g end
		end
		return nil
	end
	local function eachPlant(fn)
		local g = myGarden(); local imp = g and g:FindFirstChild("Important")
		local pp = imp and imp:FindFirstChild("Plants_Physical")
		if not pp then return end
		for _, plant in ipairs(pp:GetChildren()) do fn(plant) end
	end

	-- shovel SELURUH plant (Remove_Item di part plant)
	local function shovel(plant)
		local part = plant.PrimaryPart or plant:FindFirstChildWhichIsA("BasePart")
		if part then pcall(function() Remove:FireServer(part) end) end
	end
	-- shovel 1 BUAH aja (Remove_Item di part buah -> plant tetap)
	local function shovelFruit(fruit)
		local part = fruit.PrimaryPart or fruit:FindFirstChildWhichIsA("BasePart")
		if part then pcall(function() Remove:FireServer(part) end) end
	end

	----------------------------------------------------------------- opsi (buat UI)
	local function catalog()
		local ok, t = pcall(function() return require(RS.Data.SeedShopData) end)
		local names = {}
		if ok and type(t) == "table" then
			for k in pairs(t) do local n = tostring(k); if n ~= "RefreshTime" and n ~= "Gear" then names[#names + 1] = n end end
			table.sort(names)
		end
		return names
	end
	function ctx.getShovelTreeOptions()  return optionsFrom(catalog(), "All (semua plant)") end
	function ctx.getShovelFruitOptions() return optionsFrom(catalog(), "All (semua fruit)") end
	function ctx.getShovelVariantOptions()
		-- kumpulin variant yg ADA di garden + base
		local set = { Normal = true, Gold = true, Rainbow = true }
		eachPlant(function(plant)
			local fr = plant:FindFirstChild("Fruits")
			if fr then for _, f in ipairs(fr:GetChildren()) do
				local v = f:FindFirstChild("Variant"); if v and v.Value ~= "" then set[tostring(v.Value)] = true end
			end end
		end)
		local names = {} for k in pairs(set) do names[#names + 1] = k end; table.sort(names)
		return optionsFrom(names, "All (semua variant)")
	end
	function ctx.getShovelMutationOptions()
		-- daftar LENGKAP semua mutasi buah dari registry (MutationHandler.MutationNames)
		local ok, MH = pcall(function() return require(RS.Modules.MutationHandler) end)
		local names = {}
		if ok and MH and type(MH.MutationNames) == "table" then
			local mn = MH.MutationNames
			if mn[1] ~= nil then for _, v in ipairs(mn) do names[#names + 1] = tostring(v) end
			else for k in pairs(mn) do names[#names + 1] = tostring(k) end end
			table.sort(names)
		end
		return optionsFrom(names, "All (semua mutasi)")
	end
	function ctx.getShovelModeOptions() return { ">= (berat minimal)", "<= (berat maksimal)" } end

	----------------------------------------------------------------- cek fruit cocok filter
	local function fruitMatches(f)
		local sel  = CFG.shovelFruitNames or {}
		local muts = CFG.shovelFruitMuts or {}
		local vars = CFG.shovelFruitVariants or {}
		-- tipe
		if not (next(sel) == nil or sel["All"] or sel[f.Name]) then return false end
		-- variant
		if not (next(vars) == nil or vars["All"]) then
			local fv = f:FindFirstChild("Variant")
			local vn = fv and tostring(fv.Value) or "Normal"
			if not vars[vn] then return false end
		end
		-- mutasi (fruit harus punya salah satu mutasi terpilih)
		if not (next(muts) == nil or muts["All"]) then
			local hit = false
			for m in pairs(muts) do if m ~= "All" and f:GetAttribute(m) == true then hit = true; break end end
			if not hit then return false end
		end
		-- berat vs threshold
		local thr = tonumber(CFG.shovelFruitWeight) or 0
		if thr > 0 then
			local w = f:FindFirstChild("Weight")
			local wv = w and tonumber(w.Value) or 0
			local mode = CFG.shovelFruitMode or ">="
			if mode:find("<=") then if not (wv <= thr) then return false end
			else if not (wv >= thr) then return false end end
		end
		return true
	end

	----------------------------------------------------------------- loop: shovel tree/plant
	local function treeLoop()
		ctx.state.shovelTreeId = (ctx.state.shovelTreeId or 0) + 1
		local myId = ctx.state.shovelTreeId
		ctx.elevate()
		while CFG.shovelTreeEnabled and ctx.alive() and ctx.state.shovelTreeId == myId do
			if not equipShovel() then
				ctx.setStatus("Auto Shovel Tree: Shovel ga ada / gagal equip")
				task.wait(math.max(1, tonumber(CFG.shovelTreeDelay) or 0))
			else
				local sel = CFG.shovelTreeNames or {}
				local all = sel["All"]
				local n = 0
				eachPlant(function(plant)
					if not CFG.shovelTreeEnabled or ctx.state.shovelTreeId ~= myId then return end
					if all or sel[plant.Name] then
						shovel(plant); n = n + 1; task.wait(0.12)
					end
				end)
				ctx.setStatus(("Auto Shovel Tree: cabut %d plant"):format(n))
				task.wait(math.max(0.5, tonumber(CFG.shovelTreeDelay) or 0) + 0.5)
			end
		end
	end

	----------------------------------------------------------------- loop: shovel fruit
	local function fruitLoop()
		ctx.state.shovelFruitId = (ctx.state.shovelFruitId or 0) + 1
		local myId = ctx.state.shovelFruitId
		ctx.elevate()
		while CFG.shovelFruitEnabled and ctx.alive() and ctx.state.shovelFruitId == myId do
			if not equipShovel() then
				ctx.setStatus("Auto Shovel Fruit: Shovel ga ada / gagal equip")
				task.wait(math.max(1, tonumber(CFG.shovelFruitDelay) or 0))
			else
				local n = 0
				eachPlant(function(plant)
					if not CFG.shovelFruitEnabled or ctx.state.shovelFruitId ~= myId then return end
					local fr = plant:FindFirstChild("Fruits")
					if not fr then return end
					-- hapus TIAP buah yg cocok filter (plant tetap ada)
					for _, f in ipairs(fr:GetChildren()) do
						if not CFG.shovelFruitEnabled or ctx.state.shovelFruitId ~= myId then break end
						if fruitMatches(f) then shovelFruit(f); n = n + 1; task.wait(0.12) end
					end
				end)
				ctx.setStatus(("Auto Shovel Fruit: cabut %d buah"):format(n))
				task.wait(math.max(0.5, tonumber(CFG.shovelFruitDelay) or 0) + 0.5)
			end
		end
	end

	function ctx.startShovelTree()  equipShovel(); ensureGuard(); task.spawn(treeLoop) end
	function ctx.stopShovelTree()   ctx.state.shovelTreeId = (ctx.state.shovelTreeId or 0) + 1 end
	function ctx.startShovelFruit() equipShovel(); ensureGuard(); task.spawn(fruitLoop) end
	function ctx.stopShovelFruit()  ctx.state.shovelFruitId = (ctx.state.shovelFruitId or 0) + 1 end
end
