--[[ automation_water.lua — Auto Water Fruits.
     Siram plant terpilih pakai Watering Can. Mekanisme (dari remote spy):
       Water_RE:FireServer(plant:GetPivot().Position)
     Ga perlu equip can — server auto-decrement uses dari Watering Can di inventory.
     Loop tiap CFG.waterDelay detik, cuma siram plant yang tipenya ada di CFG.waterFruitNames
     (atau "All"). Plant ada di workspace.Farm.<garden>.Important.Plants_Physical (nama = tipe fruit). ]]
return function(ctx)
	local RS  = game:GetService("ReplicatedStorage")
	local CFG = ctx.CFG
	local LP  = ctx.LP
	local Water = RS:WaitForChild("GameEvents"):WaitForChild("Water_RE")

	-- cari Watering Can (prioritas regular = uses banyak; fallback Super/Sugar/apapun)
	local function findCan()
		local best, fallback
		for _, where in ipairs({ LP.Character, LP:FindFirstChildOfClass("Backpack") }) do
			if where then
				for _, t in ipairs(where:GetChildren()) do
					local n = tostring(t.Name)
					if t:IsA("Tool") and n:find("Watering Can") then
						if not n:find("Super") and not n:find("Sugar") then best = best or t
						else fallback = fallback or t end
					end
				end
			end
		end
		return best or fallback
	end

	local function heldCan()
		local char = LP.Character
		if not char then return nil end
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and tostring(t.Name):find("Watering Can") then return t end
		end
	end
	-- pastiin Watering Can ke-equip (server nyiram cuma pas can dipegang)
	local function equipCan()
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return false end
		if heldCan() then return true end
		local can = findCan()
		if not can then return false end
		pcall(function() hum:EquipTool(can) end)
		task.wait(0.2)
		return heldCan() ~= nil
	end

	-- Guard (mirip reclaimer): selama auto water aktif, Watering Can WAJIB tetap kepegang.
	-- Kalau user pindah manual ke tool lain, langsung equip ulang (cek 0.25s).
	local guardRunning = false
	local function ensureGuard()
		if guardRunning then return end
		guardRunning = true
		task.spawn(function()
			while CFG.waterEnabled and ctx.alive() do
				if not heldCan() then equipCan() end
				task.wait(0.25)
			end
			guardRunning = false
		end)
	end

	-- opsi fruit = katalog seed (semua yang bisa ditanam). Format sama kayak shop.
	local function optionsFrom(names)
		local out = { { value = "All", display = "All (siram semua)" } }
		for _, n in ipairs(names) do out[#out + 1] = { value = n, display = n } end
		return out
	end
	function ctx.getWaterFruitOptions()
		local ok, t = pcall(function() return require(RS.Data.SeedShopData) end)
		local names = {}
		if ok and type(t) == "table" then
			for k in pairs(t) do
				local n = tostring(k)
				if n ~= "RefreshTime" and n ~= "Gear" then names[#names + 1] = n end
			end
			table.sort(names)
		end
		return optionsFrom(names)
	end

	-- iterasi plant di kebun MILIK SENDIRI. Semua garden namanya "Farm", dibedain lewat
	-- Important.Data.Owner -> skip-CommunityGarden aja kesapu kebun pemain lain (bug).
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

	local function waterLoop()
		ctx.state.waterId = (ctx.state.waterId or 0) + 1
		local myId = ctx.state.waterId
		ctx.elevate()
		while CFG.waterEnabled and ctx.alive() and ctx.state.waterId == myId do
			local sel = CFG.waterFruitNames or {}
			local all = sel["All"]
			local n = 0
			-- equip can dulu; kalau ga ada, kasih tau & tunggu
			if not equipCan() then
				ctx.setStatus("Auto Water: Watering Can ga ada / gagal equip")
				task.wait(math.max(1, tonumber(CFG.waterDelay) or 1))
			else
			eachPlant(function(plant)
				if not CFG.waterEnabled or ctx.state.waterId ~= myId then return end
				if all or sel[plant.Name] then
					local ok, pos = pcall(function() return plant:GetPivot().Position end)
					if ok and pos then
						pcall(function() Water:FireServer(pos) end)
						n = n + 1
						task.wait(0.05) -- jeda antar-fire biar ga flood remote
					end
				end
			end)
				ctx.setStatus(("Auto Water: siram %d plant"):format(n))
				task.wait(math.max(0.5, tonumber(CFG.waterDelay) or 1))
			end
		end
	end

	function ctx.startWater() equipCan(); ensureGuard(); task.spawn(waterLoop) end
	function ctx.stopWater() ctx.state.waterId = (ctx.state.waterId or 0) + 1 end
end
