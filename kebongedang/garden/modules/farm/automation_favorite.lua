--[[ automation_favorite.lua — Auto Favorite/Unfavorite fruit.
     Favorite = "lock" buah biar ga kejual/keshovel. Pakai Favorite Tool (equip + guard).
     Remote (dari Favorite Tool script): LockToolRemote:InvokeServer(favTool, fruitModel, state)
       state=true -> favorite, false -> unfavorite. RemoteFunction.
     State fruit: fruit:GetAttribute("Favorited") (boolean). Cuma fruit tag "Harvestable".
     Filter: tipe fruit + mutasi (required) + berat (mode + threshold). ]]
return function(ctx)
	local RS  = game:GetService("ReplicatedStorage")
	local CFG = ctx.CFG
	local LP  = ctx.LP
	-- Ambil remote LAZY (jangan WaitForChild di module-load -> bisa nge-block init).
	local function favRemote()
		local GE = RS:FindFirstChild("GameEvents"); if not GE then return nil end
		return GE:FindFirstChild("FavoriteToolRemote") or GE:FindFirstChild("Favorite_Item")
	end
	-- Panggil remote: RemoteFunction -> InvokeServer, RemoteEvent -> FireServer.
	local function doFav(tool, fruit, state)
		local re = favRemote(); if not re then return end
		pcall(function()
			if re:IsA("RemoteFunction") then re:InvokeServer(tool, fruit, state)
			else re:FireServer(tool, fruit, state) end
		end)
	end

	----------------------------------------------------------------- tool equip + guard
	local function findTool()
		for _, where in ipairs({ LP.Character, LP:FindFirstChildOfClass("Backpack") }) do
			if where then for _, t in ipairs(where:GetChildren()) do
				if t:IsA("Tool") and tostring(t.Name):find("Favorite") then return t end
			end end
		end
	end
	local function heldTool()
		local char = LP.Character
		if not char then return nil end
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and tostring(t.Name):find("Favorite") then return t end
		end
	end
	local function equipTool()
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return false end
		if heldTool() then return true end
		local tl = findTool()
		if not tl then return false end
		pcall(function() hum:EquipTool(tl) end)
		task.wait(0.2)
		return heldTool() ~= nil
	end
	local guardRunning = false
	local function ensureGuard()
		if guardRunning then return end
		guardRunning = true
		task.spawn(function()
			while (CFG.favEnabled or CFG.unfavEnabled) and ctx.alive() do
				if not heldTool() then equipTool() end
				task.wait(0.25)
			end
			guardRunning = false
		end)
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
	function ctx.getFavFruitOptions() return optionsFrom(catalog(), "All (semua fruit)") end
	function ctx.getFavMutationOptions()
		local ok, MH = pcall(function() return require(RS.Modules.MutationHandler) end)
		local names = {}
		if ok and MH and type(MH.MutationNames) == "table" then
			local mn = MH.MutationNames
			if mn[1] ~= nil then for _, v in ipairs(mn) do names[#names + 1] = tostring(v) end
			else for k in pairs(mn) do names[#names + 1] = tostring(k) end end
			table.sort(names)
		end
		return optionsFrom(names, "All (mutasi apapun)")
	end
	function ctx.getFavModeOptions() return { ">= (berat minimal)", "<= (berat maksimal)" } end

	----------------------------------------------------------------- match filter
	local function fruitWeight(f) local w = f:FindFirstChild("Weight"); return w and tonumber(w.Value) or 0 end
	local function fruitMatches(f)
		local sel  = CFG.favFruitNames or {}
		local muts = CFG.favMutNames or {}
		-- tipe (kosong = any)
		if not (next(sel) == nil or sel["All"] or sel[f.Name]) then return false end
		-- mutasi required (kosong = any). Fruit harus punya salah satu mutasi terpilih.
		if not (next(muts) == nil or muts["All"]) then
			local hit = false
			for m in pairs(muts) do if m ~= "All" and f:GetAttribute(m) == true then hit = true; break end end
			if not hit then return false end
		end
		-- berat (0 = off)
		local thr = tonumber(CFG.favWeight) or 0
		if thr > 0 then
			local w = fruitWeight(f)
			if (CFG.favMode or ">="):find("<=") then if not (w <= thr) then return false end
			else if not (w >= thr) then return false end end
		end
		return true
	end

	-- kebun MILIK SENDIRI aja. Semua garden namanya "Farm", dibedain lewat Important.Data.Owner
	-- -> skip-CommunityGarden aja kesapu kebun pemain lain (bug).
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
	local function eachHarvestable(fn)
		local g = myGarden(); local imp = g and g:FindFirstChild("Important")
		local pp = imp and imp:FindFirstChild("Plants_Physical")
		if not pp then return end
		for _, plant in ipairs(pp:GetChildren()) do
			local fr = plant:FindFirstChild("Fruits")
			if fr then for _, f in ipairs(fr:GetChildren()) do
				if f:HasTag("Harvestable") then fn(f) end
			end end
		end
	end

	----------------------------------------------------------------- loop
	local function favLoop()
		ctx.state.favId = (ctx.state.favId or 0) + 1
		local myId = ctx.state.favId
		ctx.elevate()
		while (CFG.favEnabled or CFG.unfavEnabled) and ctx.alive() and ctx.state.favId == myId do
			local tool = heldTool() or findTool()
			if not tool then
				ctx.setStatus("Auto Favorite: Favorite Tool ga ada")
			else
				local n = 0
				eachHarvestable(function(f)
					if not (CFG.favEnabled or CFG.unfavEnabled) or ctx.state.favId ~= myId then return end
					if not fruitMatches(f) then return end
					local isFav = f:GetAttribute("Favorited") == true
					if CFG.favEnabled and not isFav then
						doFav(tool, f, true); n = n + 1; task.wait(0.08)
					elseif CFG.unfavEnabled and isFav then
						doFav(tool, f, false); n = n + 1; task.wait(0.08)
					end
				end)
				ctx.setStatus(("Auto Favorite: proses %d buah"):format(n))
			end
			task.wait(math.max(0.5, tonumber(CFG.favDelay) or 1) + 0.5)
		end
	end

	function ctx.startFavorite()
		equipTool(); ensureGuard()
		task.spawn(favLoop)
	end
	function ctx.stopFavorite() ctx.state.favId = (ctx.state.favId or 0) + 1 end
end
