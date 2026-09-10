--[[ automation_sprinkler.lua — Auto Sprinkler + Sprinkler Shovel (Farm).
     Pasang sprinkler:  equip tool sprinkler -> SprinklerService:FireServer("Create", CFrame)
     Cabut sprinkler:   equip Shovel        -> DeleteObject:FireServer(sprinklerModel)
     Sprinkler & jumlah dari Backpack tool "<Nama> Sprinkler x<jumlah>".
     Posisi pasang: kalau "Sprinkler Plants" dipilih -> di posisi plant itu;
                    kalau kosong -> Position mode (Random / Player Position).
     Fungsi: ctx.getSprinklerOptions / ctx.getSprinklerPlantOptions /
             ctx.getShovelSprinklerOptions / ctx.startSprinkler / ctx.startShovelSprinkler ]]
return function(ctx)
	local LP  = ctx.LP
	local CFG = ctx.CFG
	local RS  = game:GetService("ReplicatedStorage")
	local GE  = RS:WaitForChild("GameEvents")
	local SprinklerService = GE:WaitForChild("SprinklerService")
	local DeleteObject     = GE:WaitForChild("DeleteObject")
	local function setStatus(s) ctx.setStatus(s) end

	local function myFarm()
		local ok, GetFarm = pcall(function() return require(RS.Modules.GetFarm) end)
		if ok and GetFarm then local ok2, f = pcall(function() return GetFarm(LP) end); if ok2 then return f end end
		return nil
	end
	local function important() local f = myFarm(); return f and f:FindFirstChild("Important") end
	local function plantsFolder() local imp = important(); return imp and imp:FindFirstChild("Plants_Physical") end
	local function objectsFolder() local imp = important(); return imp and imp:FindFirstChild("Objects_Physical") end
	local function canPlantParts()
		local imp = important(); local pl = imp and imp:FindFirstChild("Plant_Locations")
		local parts = {}
		if pl then for _, p in ipairs(pl:GetChildren()) do if p:IsA("BasePart") then parts[#parts + 1] = p end end end
		return parts
	end

	----------------------------------------------------------------- inventory sprinkler
	local function sprinklerBase(t) return t:IsA("Tool") and t.Name:match("^(.- Sprinkler) x%d+") or nil end
	-- name -> jumlah (dari Backpack + Character)
	local function sprinklerInventory()
		local out = {}
		for _, where in ipairs({ LP:FindFirstChild("Backpack"), LP.Character }) do
			if where then for _, t in ipairs(where:GetChildren()) do
				local b = sprinklerBase(t)
				if b then out[b] = (out[b] or 0) + (tonumber(t.Name:match("x(%d+)$")) or 0) end
			end end
		end
		return out
	end
	local function sprinklerOptions()
		local inv = sprinklerInventory()
		-- prune sprinkler terpilih yg stok-nya udah 0
		local sel = CFG.sprinklerNames
		if type(sel) == "table" then
			local changed = false
			for nm in pairs(sel) do if (inv[nm] or 0) <= 0 then sel[nm] = nil; changed = true end end
			if changed and ctx.persistState then pcall(ctx.persistState) end
		end
		local names = {}
		for n, q in pairs(inv) do if q > 0 then names[#names + 1] = n end end
		table.sort(names)
		local out = {}
		for _, n in ipairs(names) do out[#out + 1] = { value = n, display = ("%s (%d)"):format(n, inv[n]) } end
		return out
	end
	ctx.getSprinklerOptions = sprinklerOptions

	-- jenis plant unik di garden (buat "place near plants") + "All"
	function ctx.getSprinklerPlantOptions()
		local out = { { value = "All", display = "All (semua plant)" } }
		local pf = plantsFolder()
		if pf then
			local seen, names = {}, {}
			for _, m in ipairs(pf:GetChildren()) do if m.Name and not seen[m.Name] then seen[m.Name] = true; names[#names + 1] = m.Name end end
			table.sort(names)
			for _, n in ipairs(names) do out[#out + 1] = { value = n, display = n } end
		end
		return out
	end

	-- Opsi shovel: gabungan jenis sprinkler yg kamu punya (inventory) + yg lagi
	-- terpasang, + "All". Daftar dari inventory bikin stabil (ga ilang pas objek
	-- expire). Sekalian prune pilihan yg jenisnya udah ga ada sama sekali.
	function ctx.getShovelSprinklerOptions()
		local set = {}
		for n in pairs(sprinklerInventory()) do set[n] = true end
		local of = objectsFolder()
		if of then for _, o in ipairs(of:GetChildren()) do
			local ty = o:GetAttribute("OBJECT_TYPE") or o.Name
			if ty then set[ty] = true end
		end end
		local sel = CFG.shovelSprinklerNames
		if type(sel) == "table" then
			local changed = false
			for nm in pairs(sel) do if nm ~= "All" and not set[nm] then sel[nm] = nil; changed = true end end
			if changed and ctx.persistState then pcall(ctx.persistState) end
		end
		local names = {}
		for n in pairs(set) do names[#names + 1] = n end
		table.sort(names)
		local out = { { value = "All", display = "All (semua terpasang)" } }
		for _, n in ipairs(names) do out[#out + 1] = { value = n, display = n } end
		return out
	end

	----------------------------------------------------------------- equip helper
	local function heldName() local c = LP.Character; local t = c and c:FindFirstChildOfClass("Tool"); return t and t.Name end
	local function equipByPredicate(pred)
		local c = LP.Character
		if c then for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") and pred(t) then return true end end end
		local bp = LP:FindFirstChild("Backpack")
		if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") and pred(t) then
			local hum = c and c:FindFirstChildOfClass("Humanoid"); if hum then pcall(function() hum:EquipTool(t) end) end
			break
		end end end
		if c then for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") and pred(t) then return true end end end
		return false
	end
	local function equipSprinkler(name) return equipByPredicate(function(t) return sprinklerBase(t) == name end) end
	local function equipShovel() return equipByPredicate(function(t) return t.Name == "Shovel [Destroy Plants]" or t.Name:match("^Shovel") end) end

	----------------------------------------------------------------- posisi
	local function randomPos()
		local parts = canPlantParts(); if #parts == 0 then return nil end
		local p = parts[math.random(1, #parts)]
		local hx, hz = p.Size.X / 2 - 1, p.Size.Z / 2 - 1
		return Vector3.new(p.Position.X + (math.random() * 2 - 1) * hx, p.Position.Y, p.Position.Z + (math.random() * 2 - 1) * hz)
	end
	local function playerPos()
		local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart"); if not hrp then return nil end
		local parts = canPlantParts(); local y = parts[1] and parts[1].Position.Y or 0
		return Vector3.new(hrp.Position.X, y, hrp.Position.Z)
	end
	-- posisi plant yg tipenya dipilih (buat "place near plants")
	local function plantPositions(sel)
		local out = {}
		local pf = plantsFolder(); if not pf then return out end
		local all = sel["All"]
		for _, m in ipairs(pf:GetChildren()) do
			if all or sel[m.Name] then
				local piv = m:GetPivot(); out[#out + 1] = Vector3.new(piv.X, piv.Y, piv.Z)
			end
		end
		return out
	end

	----------------------------------------------------------------- loop PASANG
	local function sprinklerLoop(myId)
		ctx.elevate()
		while CFG.sprinklerEnabled and ctx.alive() and ctx.state.sprinklerId == myId do
			local selSpr = CFG.sprinklerNames or {}
			local inv = sprinklerInventory()
			-- daftar tipe sprinkler terpilih yg masih ada stok (urut stabil)
			local types = {}
			for n in pairs(selSpr) do if (inv[n] or 0) > 0 then types[#types + 1] = n end end
			table.sort(types)
			if #types == 0 then
				setStatus("Sprinkler: pilih sprinkler (stok kosong?)")
			else
				-- posisi target
				local plantsSel = CFG.sprinklerPlantNames or {}
				local positions
				if next(plantsSel) then
					positions = plantPositions(plantsSel)
				else
					local mode = CFG.sprinklerPosition == "Player Position" and "Player Position" or "Random"
					positions = { mode == "Player Position" and playerPos() or randomPos() }
				end
				local placed = 0
				for _, pos in ipairs(positions) do
					if not CFG.sprinklerEnabled or ctx.state.sprinklerId ~= myId then break end
					if pos then
						-- rotasi 1-1 antar tipe, indeks persist antar-siklus (biar ga tipe pertama terus)
						ctx.state.sprRotIdx = (ctx.state.sprRotIdx or 0) % #types + 1
						local name = types[ctx.state.sprRotIdx]
						if equipSprinkler(name) then
							pcall(function() SprinklerService:FireServer("Create", CFrame.new(pos)) end)
							placed = placed + 1
							task.wait(tonumber(CFG.sprinklerDelay) or 0)
						end
					end
				end
				setStatus(("Sprinkler: pasang %d"):format(placed))
			end
			task.wait(1)
		end
	end
	function ctx.startSprinkler()
		ctx.state.sprinklerId = (ctx.state.sprinklerId or 0) + 1
		local myId = ctx.state.sprinklerId
		task.spawn(function() sprinklerLoop(myId) end)
	end

	----------------------------------------------------------------- loop CABUT (shovel)
	local function shovelLoop(myId)
		ctx.elevate()
		while CFG.shovelSprinklerEnabled and ctx.alive() and ctx.state.shovelSprId == myId do
			local sel = CFG.shovelSprinklerNames or {}
			local of = objectsFolder()
			if of and next(sel) then
				local all = sel["All"]
				equipShovel()
				local removed = 0
				for _, o in ipairs(of:GetChildren()) do
					if not CFG.shovelSprinklerEnabled or ctx.state.shovelSprId ~= myId then break end
					local ty = o:GetAttribute("OBJECT_TYPE") or o.Name
					if all or sel[ty] then
						pcall(function() DeleteObject:FireServer(o) end)
						removed = removed + 1
						task.wait(tonumber(CFG.shovelSprinklerDelay) or 0)
					end
				end
				setStatus(("Shovel Sprinkler: cabut %d"):format(removed))
			else
				setStatus("Shovel Sprinkler: pilih sprinkler dulu")
			end
			task.wait(1)
		end
	end
	function ctx.startShovelSprinkler()
		ctx.state.shovelSprId = (ctx.state.shovelSprId or 0) + 1
		local myId = ctx.state.shovelSprId
		task.spawn(function() shovelLoop(myId) end)
	end
end
