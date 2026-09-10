--[[ automation_pickup_pet_v1.lua — PnP V1 (POLLING).
     Tiap pet target punya thread sendiri: query GetPetCooldown -> kalau ready pickup-place.
     Langsung & simpel, tapi kena JITTER latency server (round-trip tiap cek).
     Config SENDIRI: pnpUuids, pickupDelay, equipDelay, pnpScanInterval, pnpEnabled.
     Fungsi: ctx.startPnpV1 / ctx.stopPnpV1. Juga expose ctx.inventoryPetOptions (dipakai V1 & V2). ]]
return function(ctx)
	local DataService = ctx.deps.DataService
	local PetsService = ctx.deps.PetsService
	local CFG         = ctx.CFG
	local function setStatus(s) ctx.setStatus(s) end

	local RS = game:GetService("ReplicatedStorage")
	local LP = ctx.LP

	local cdMap = ctx.state.cdMap or {}
	ctx.state.cdMap = cdMap
	local READY_TH = 0

	local GetPetCooldown = RS:WaitForChild("GameEvents"):WaitForChild("GetPetCooldown")

	local function readMainCd(uuid)
		local ok, cd = pcall(function() return GetPetCooldown:InvokeServer(uuid) end)
		if not ok or type(cd) ~= "table" then return nil end
		local data, mainCd = {}, 0
		for _, e in ipairs(cd) do
			local t = tonumber(e.Time) or 0
			data[#data + 1] = { Passive = e.Passive, Time = t }
			if not tostring(e.Passive or ""):find("Mutation") then
				if t > mainCd then mainCd = t end
			end
		end
		cdMap[uuid] = { data = data }
		return mainCd
	end

	local function targetPets()
		local out = {}
		local ok, d = pcall(function() return DataService:GetData() end)
		if not ok or not d then return out end
		local eq  = d.PetsData and d.PetsData.EquippedPets
		local inv = d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data
		if not eq then return out end
		local sel = CFG.pnpUuids or {}
		for _, uuid in ipairs(eq) do
			local pt = inv and inv[uuid] and inv[uuid].PetType
			if (not next(sel)) or sel[uuid] then
				out[#out + 1] = { uuid = uuid, petType = pt }
			end
		end
		return out
	end

	-- daftar pet dari INVENTORY buat dropdown Select Pets (SHARED: dipakai V1 & V2, serta semua Team).
	-- HANYA menampilkan pet yang difavoritkan (IsFavorite == true), agar tidak tercampur dengan pet target non-favorit.
	function ctx.inventoryPetOptions(selectedSet)
		local out = {}
		local ok, d = pcall(function() return DataService:GetData() end)
		if not ok or not d then return out end
		local inv = d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data
		if not inv then return out end
		local eq = d.PetsData.EquippedPets or {}
		local eqSet = {}; for _, u in ipairs(eq) do eqSet[u] = true end

		-- Cek apakah ada pet yang difavoritkan di inventory
		local anyFav = false
		for _, v in pairs(inv) do
			if v.PetData and v.PetData.IsFavorite then
				anyFav = true
				break
			end
		end

		for uuid, v in pairs(inv) do
			local pd = v.PetData or {}
			local isFav = (pd.IsFavorite == true)
			-- Filter favorit: jika ada pet favorit, hanya tampilkan yang favorit atau yang sedang terpilih di selectedSet.
			-- Jika belum ada pet favorit sama sekali di inventory, tampilkan semua sebagai fallback.
			if (not anyFav) or isFav or (selectedSet and selectedSet[uuid]) then
				local pt = v.PetType or "?"
				local age = pd.Level or 0
				local mut = pd.MutationType
				local mutName = mut
				if mut and ctx.reg and ctx.reg.mutDisplay then mutName = ctx.reg.mutDisplay(mut) end
				local mutPrefix = (mut and mut ~= "" and mut ~= "Normal") and (tostring(mutName) .. " ") or ""
				local weight = (pd.BaseWeight or 0) * (1 + 0.1 * age)
				local tag = eqSet[uuid] and " [aktif]" or ""
				local favTag = isFav and "⭐ " or ""
				out[#out + 1] = {
					value = uuid,
					display = ("%s%s%s • %.2f KG • Lvl %s • #%s%s"):format(favTag, mutPrefix, pt, weight, tostring(age), uuid:sub(2, 5), tag),
				}
			end
		end
		if selectedSet and next(inv) then
			local valid = {}
			for uuid in pairs(inv) do valid[uuid] = true end
			local changed = false
			for u in pairs(selectedSet) do
				if not valid[u] then selectedSet[u] = nil; changed = true end
			end
			if changed and ctx.persistState then ctx.persistState() end
		end
		table.sort(out, function(a, b)
			local selA = selectedSet and selectedSet[a.value] and 1 or 0
			local selB = selectedSet and selectedSet[b.value] and 1 or 0
			if selA ~= selB then return selA > selB end
			return a.display < b.display
		end)
		return out
	end

	local GetFarm = require(RS.Modules.GetFarm)
	local function placePos()
		local farm = GetFarm and GetFarm(LP)
		local pa = farm and farm:FindFirstChild("PetArea")
		if pa then return pa.Position end
		local char = LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		return hrp and hrp.Position or nil
	end

	----------------------------------------------------------------- loop (polling, paralel per-pet)
	local petThreads = {}
	local function runPetThread(uuid, myId)
		petThreads[uuid] = true
		while CFG.pnpEnabled and ctx.alive() and ctx.state.pnpV1Id == myId do
			local stillTarget = false
			for _, p in ipairs(targetPets()) do
				if p.uuid == uuid then stillTarget = true; break end
			end
			if not stillTarget then break end

			local mainCd = readMainCd(uuid)
			local pos = placePos()
			if pos and mainCd ~= nil and mainCd <= READY_TH then
				if (CFG.pickupDelay or 0) > 0 then task.wait(CFG.pickupDelay) end
				if not (CFG.pnpEnabled and ctx.state.pnpV1Id == myId) then break end
				pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
				task.wait(math.max(0.01, CFG.equipDelay or 0.03))
				if not (CFG.pnpEnabled and ctx.state.pnpV1Id == myId) then break end
				pcall(function() PetsService:FireServer("EquipPet", uuid, CFrame.new(pos)) end)
			end
			task.wait(math.max(0.01, tonumber(CFG.pnpScanInterval) or 0.05))
		end
		petThreads[uuid] = nil
	end

	local function pnpLoop()
		ctx.state.pnpV1Id = (ctx.state.pnpV1Id or 0) + 1
		local myId = ctx.state.pnpV1Id
		ctx.elevate()
		while CFG.pnpEnabled and ctx.alive() and ctx.state.pnpV1Id == myId do
			local pets = targetPets()
			if #pets == 0 then
				setStatus("PNP V1: tidak ada pet target (equip pet dulu)")
			else
				for _, p in ipairs(pets) do
					if not petThreads[p.uuid] then task.spawn(runPetThread, p.uuid, myId) end
				end
				setStatus(("PNP V1 (polling): %d pet"):format(#pets))
			end
			task.wait(1)
		end
	end

	function ctx.startPnpV1() task.spawn(pnpLoop) end
	function ctx.stopPnpV1() ctx.state.pnpV1Id = (ctx.state.pnpV1Id or 0) + 1 end -- bump id -> loop lama mati
end
