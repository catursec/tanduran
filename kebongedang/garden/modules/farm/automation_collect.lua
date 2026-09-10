--[[ automation_collect.lua — Auto Collect fruit (harvest ke backpack).
     Remote (dari CollectController): GameEvents.Crops.Collect:FireServer({fruitModel,...})
       — batch collect list FRUIT MODEL. Jalan walau jauh (server ga cek proximity).
     Backpack full: require(Modules.InventoryService):IsMaxInventory().
     Auto-sell: GameEvents.SellFood_RE:FireServer().
     3 mode (bisa barengan), collect fruit yang cocok SALAH SATU mode aktif:
       1) Whitelist Fruit   : tipe fruit terpilih
       2) Whitelist Mutation: fruit punya mutasi terpilih
       3) Combined          : fruit + mutasi + variant + berat (SEMUA kriteria) ]]
return function(ctx)
	local RS  = game:GetService("ReplicatedStorage")
	local CFG = ctx.CFG
	local LP  = ctx.LP
	local Collect = RS.GameEvents:WaitForChild("Crops"):WaitForChild("Collect")
	local SellInv = RS.GameEvents:WaitForChild("Sell_Inventory")
	local IS
	pcall(function() IS = require(RS.Modules.InventoryService) end)

	-- Jual semua fruit: HARUS deket NPC jual (Steven) — teleport bentar, jual, balik.
	local function sellAllFruits()
		local char = LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local npcs = workspace:FindFirstChild("NPCS")
		local steven = npcs and npcs:FindFirstChild("Steven")
		local shrp = steven and steven:FindFirstChild("HumanoidRootPart")
		if not shrp then return end
		local orig = hrp.CFrame
		hrp.CFrame = shrp.CFrame * CFrame.new(0, 0, 4) -- deket Steven
		task.wait(0.5)
		pcall(function() SellInv:FireServer() end)
		task.wait(0.8)
		pcall(function() if hrp and hrp.Parent then hrp.CFrame = orig end end) -- balik
	end

	local NOT_MUTATION = {
		FruitVersion = true, MaxAge = true, GrowRateMulti = true, WeightMulti = true,
		DoneGrowTime = true, FruitSpawnIndex = true, OfflineGrowthTarget = true,
		MasteryGrowthMulti = true, MasterySizeMulti = true,
	}

	local function backpackFull()
		if not IS then return false end
		local ok, full = pcall(function() return IS:IsMaxInventory() end)
		return ok and full == true
	end

	-- Cuma kebun MILIK SENDIRI. Semua garden namanya "Farm", dibedain lewat Important.Data.Owner.
	-- Skip-CommunityGarden aja ga cukup -> kesapu kebun pemain lain (bug).
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
	local function eachFruit(fn)
		local g = myGarden(); local imp = g and g:FindFirstChild("Important")
		local pp = imp and imp:FindFirstChild("Plants_Physical")
		if not pp then return end
		for _, plant in ipairs(pp:GetChildren()) do
			local fr = plant:FindFirstChild("Fruits")
			if fr then for _, f in ipairs(fr:GetChildren()) do fn(f) end end
		end
	end

	----------------------------------------------------------------- opsi UI
	local function optionsFrom(names, allLabel)
		local out = { { value = "All", display = allLabel or "All" } }
		for _, n in ipairs(names) do out[#out + 1] = { value = n, display = n } end
		return out
	end
	local function catalog()
		local ok, t = pcall(function() return require(RS.Data.SeedShopData) end)
		local names = {}
		if ok and type(t) == "table" then
			for k in pairs(t) do local n = tostring(k); if n ~= "RefreshTime" and n ~= "Gear" then names[#names + 1] = n end end
			table.sort(names)
		end
		return names
	end
	function ctx.getCollectFruitOptions() return optionsFrom(catalog(), "All (semua fruit)") end
	function ctx.getCollectVariantOptions()
		local set = { Normal = true, Gold = true, Rainbow = true }
		eachFruit(function(f) local v = f:FindFirstChild("Variant"); if v and v.Value ~= "" then set[tostring(v.Value)] = true end end)
		local names = {} for k in pairs(set) do names[#names + 1] = k end; table.sort(names)
		return optionsFrom(names, "All (semua variant)")
	end
	function ctx.getCollectMutationOptions()
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
	function ctx.getCollectModeOptions() return { ">= (berat minimal)", "<= (berat maksimal)" } end

	----------------------------------------------------------------- match per-mode
	local function hasSelMut(f, muts)
		for m in pairs(muts) do if m ~= "All" and f:GetAttribute(m) == true then return true end end
		return false
	end
	local function fruitVariant(f) local v = f:FindFirstChild("Variant"); return v and tostring(v.Value) or "Normal" end
	local function fruitWeight(f) local w = f:FindFirstChild("Weight"); return w and tonumber(w.Value) or 0 end

	-- mode 1: whitelist fruit type
	local function matchWlFruit(f)
		if not CFG.collectWlFruitEnabled then return false end
		local sel = CFG.collectWlFruitNames or {}
		return sel["All"] == true or sel[f.Name] == true
	end
	-- mode 2: whitelist mutation
	local function matchWlMut(f)
		if not CFG.collectWlMutEnabled then return false end
		local muts = CFG.collectWlMutNames or {}
		if muts["All"] then return true end
		return hasSelMut(f, muts)
	end
	-- mode 3: combined (SEMUA kriteria)
	local function matchCombined(f)
		if not CFG.collectCombEnabled then return false end
		local sel  = CFG.collectCombFruitNames or {}
		local muts = CFG.collectCombMutNames or {}
		local vars = CFG.collectCombVariants or {}
		if not (next(sel) == nil or sel["All"] or sel[f.Name]) then return false end
		if not (next(muts) == nil or muts["All"] or hasSelMut(f, muts)) then return false end
		if not (next(vars) == nil or vars["All"] or vars[fruitVariant(f)]) then return false end
		local thr = tonumber(CFG.collectCombWeight) or 0
		if thr > 0 then
			local w = fruitWeight(f)
			if (CFG.collectCombMode or ">="):find("<=") then if not (w <= thr) then return false end
			else if not (w >= thr) then return false end end
		end
		return true
	end

	local function shouldCollect(f)
		return matchWlFruit(f) or matchWlMut(f) or matchCombined(f)
	end
	local function anyEnabled()
		return CFG.collectWlFruitEnabled or CFG.collectWlMutEnabled or CFG.collectCombEnabled
	end

	----------------------------------------------------------------- loop
	local running = false
	local function collectLoop()
		ctx.state.collectId = (ctx.state.collectId or 0) + 1
		local myId = ctx.state.collectId
		ctx.elevate()
		while anyEnabled() and ctx.alive() and ctx.state.collectId == myId do
			-- backpack full handling
			if backpackFull() then
				if CFG.collectAutoSellIfFull then
					ctx.setStatus("Auto Collect: backpack penuh -> jual (ke Steven)")
					sellAllFruits()
					task.wait(0.5)
				elseif CFG.collectStopIfFull then
					ctx.setStatus("Auto Collect: backpack penuh -> stop")
					task.wait(math.max(1, tonumber(CFG.collectDelay) or 0))
					-- lanjut cek lagi (ga collect)
				end
			end
			if not (backpackFull() and CFG.collectStopIfFull and not CFG.collectAutoSellIfFull) then
				-- kumpulin fruit yg cocok
				local batch = {}
				eachFruit(function(f) if shouldCollect(f) then batch[#batch + 1] = f end end)
				-- fire per-chunk (biar payload ga kegedean)
				local n = 0
				for i = 1, #batch, 40 do
					if not anyEnabled() or ctx.state.collectId ~= myId then break end
					local chunk = {}
					for j = i, math.min(i + 39, #batch) do chunk[#chunk + 1] = batch[j] end
					pcall(function() Collect:FireServer(chunk) end)
					n = n + #chunk
					task.wait(0.1)
					if backpackFull() then break end
				end
				ctx.setStatus(("Auto Collect: collect %d fruit"):format(n))
			end
			task.wait(math.max(0.5, tonumber(CFG.collectDelay) or 0) + 0.5)
		end
		running = false
	end

	-- 1 loop dipakai bareng semua mode; idempotent (semua toggle panggil ini).
	function ctx.startCollect()
		if running then return end
		running = true
		task.spawn(collectLoop)
	end
	function ctx.stopCollect() ctx.state.collectId = (ctx.state.collectId or 0) + 1 end
end
