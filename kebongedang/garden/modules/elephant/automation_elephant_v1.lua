--[[ elephant.lua — Automation Elephant (V1).
     Sama seperti Leveling, tapi patokan = BERAT (PetData.BaseWeight, KG), bukan Level.
     Passive elephant numbuhin berat pet target; kalau pet sudah mencapai Target Weight
     (mis. 5.5 KG = max), dicabut dan diganti pet target lain yang belum max. ]]
return function(ctx)
	local DataService = ctx.deps.DataService
	local PetsService = ctx.deps.PetsService
	local CFG         = ctx.CFG
	local LP          = ctx.LP
	local RS          = game:GetService("ReplicatedStorage")

	local function farmCenter()
		local GetFarm = require(RS.Modules.GetFarm)
		local farm = GetFarm and GetFarm(LP)
		local pa = farm and farm:FindFirstChild("PetArea")
		if pa then return pa.Position end
		local char = LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		return hrp and hrp.Position or nil
	end

	local slotOf, nextSlot = {}, 0
	local GRID_COLS, GRID_SP = 6, 3
	local function getPos(uuid)
		if not slotOf[uuid] then slotOf[uuid] = nextSlot; nextSlot = nextSlot + 1 end
		local center = farmCenter()
		if not center then return nil end
		local i = slotOf[uuid]
		local col = i % GRID_COLS
		local row = math.floor(i / GRID_COLS)
		local offX = (col - (GRID_COLS - 1) / 2) * GRID_SP
		local offZ = (row - 1) * GRID_SP
		return center + Vector3.new(offX, 0, offZ)
	end

	ctx.state.elephantStatus = "Idle"

	-- Ringkasan statistik untuk UI Status
	function ctx.getElephantSummary()
		local ok, d = pcall(function() return DataService:GetData() end)
		local inv = ok and d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}

		local teamCount = 0
		for _ in pairs(CFG.elephantTeamUuids) do teamCount = teamCount + 1 end

		local typesList = {}
		for k in pairs(CFG.elephantPetTypes) do table.insert(typesList, k) end
		table.sort(typesList)
		local typesStr = #typesList > 0 and table.concat(typesList, ", ") or "None"

		local readyCount, maxKgCount = 0, 0
		local targetW = CFG.elephantTargetWeight or 5.5

		for _, v in pairs(inv) do
			local pt = v.PetType
			if CFG.elephantPetTypes[pt] then
				local pd = v.PetData or {}
				local w = pd.BaseWeight or 0
				if not pd.IsFavorite then
					if w < targetW then readyCount = readyCount + 1 else maxKgCount = maxKgCount + 1 end
				end
			end
		end

		return {
			status = CFG.elephantEnabled and "ACTIVE" or "STOPPED",
			team = string.format("%d pets", teamCount),
			types = typesStr,
			ready = string.format("%d pets", readyCount),
			maxKg = string.format("%d pets", maxKgCount),
			maxTarget = string.format("%d pets", CFG.elephantMaxPets or 2),
			targetWeight = string.format("%.1f KG", targetW),
		}
	end

	local function checkElephant()
		local ok, d = pcall(function() return DataService:GetData() end)
		if not ok or not d then return end
		local petsData = d.PetsData
		if not petsData then return end
		local eq = petsData.EquippedPets or {}
		local inv = petsData.PetInventory and petsData.PetInventory.Data or {}

		local teamSet = CFG.elephantTeamUuids or {}
		local targetTypes = CFG.elephantPetTypes or {}
		local targetW = CFG.elephantTargetWeight or 5.5
		local maxPets = CFG.elephantMaxPets or 2

		-- Lacak equip lokal (kebal delay replikasi)
		local localEq, localEqCount = {}, 0
		for _, uuid in ipairs(eq) do localEq[uuid] = true; localEqCount = localEqCount + 1 end

		-- A. FIRST RUN: cabut semua pet aktif
		if ctx.state.elephantFirstRun then
			ctx.state.elephantFirstRun = false
			if #eq > 0 then
				ctx.state.elephantStatus = "Resetting garden..."
				for _, uuid in ipairs(eq) do
					pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
					localEq[uuid] = nil; localEqCount = localEqCount - 1
					task.wait(0.25)
				end
			end
		end

		-- B. PERSISTENSI TEAM: pasang lagi pet team yang kecabut
		for uuid, _ in pairs(teamSet) do
			if not localEq[uuid] then
				ctx.state.elephantStatus = "Re-equipping team..."
				local pos = getPos(uuid)
				if pos then
					pcall(function() PetsService:FireServer("EquipPet", uuid, CFrame.new(pos)) end)
					localEq[uuid] = true; localEqCount = localEqCount + 1
					task.wait(0.3)
				end
			end
		end

		-- C. KLASIFIKASI pet target yang di-equip (by BaseWeight)
		local currentGrowing = {}  -- weight < target
		local finishedMax = {}     -- weight >= target
		local otherEquipped = {}
		for uuid, _ in pairs(localEq) do
			if not teamSet[uuid] then
				local pInfo = inv[uuid]
				local pt = pInfo and pInfo.PetType
				local pd = pInfo and pInfo.PetData or {}
				local w = pd.BaseWeight or 0
				if targetTypes[pt] then
					if w < targetW then
						table.insert(currentGrowing, uuid)
						-- catat waktu mulai growing (buat Duration di webhook per-pet)
						ctx.state.elephantStartTime = ctx.state.elephantStartTime or {}
						if not ctx.state.elephantStartTime[uuid] then
							ctx.state.elephantStartTime[uuid] = os.time()
						end
					else table.insert(finishedMax, uuid) end
				else
					table.insert(otherEquipped, uuid)
				end
			end
		end

		-- D. LEPAS pet yang sudah MAX KG (+ webhook agregat + kartu per-pet)
		for _, uuid in ipairs(finishedMax) do
			local pInfo = inv[uuid]
			local pd = pInfo and pInfo.PetData or {}
			local pt = pInfo and pInfo.PetType or "?"
			local w = pd.BaseWeight or 0
			-- Durasi: dari mulai growing sampai sekarang; nil kalau start ga kecatat (mis. reload)
			local duration
			if ctx.state.elephantStartTime and ctx.state.elephantStartTime[uuid] then
				duration = os.time() - ctx.state.elephantStartTime[uuid]
				ctx.state.elephantStartTime[uuid] = nil
			end
			pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
			localEq[uuid] = nil; localEqCount = localEqCount - 1
			if ctx.webhookElephant then
				if ctx.webhookElephant.onFinished then
					pcall(function() ctx.webhookElephant.onFinished(ctx, pt, w) end)
				end
				if ctx.webhookElephant.sendFinished then
					pcall(function() ctx.webhookElephant.sendFinished(ctx, pt, w, pd.MutationType, pd.Level or 0, duration) end)
				end
			end
			task.wait(0.25)
		end

		-- E. TAMBAH pet baru dari inventory (BaseWeight terendah dulu)
		local needed = maxPets - #currentGrowing
		if needed > 0 then
			local pool = {}
			for uuid, v in pairs(inv) do
				local pt = v.PetType
				local pd = v.PetData or {}
				local w = pd.BaseWeight or 0
				if not localEq[uuid] and targetTypes[pt] and w < targetW and not pd.IsFavorite then
					table.insert(pool, { uuid = uuid, weight = w })
				end
			end
			table.sort(pool, function(a, b) return a.weight < b.weight end)

			for i = 1, math.min(needed, #pool) do
				local target = pool[i]
				local pos = getPos(target.uuid)
				if pos then
					if localEqCount >= 15 and #otherEquipped > 0 then
						local toRemove = table.remove(otherEquipped)
						pcall(function() PetsService:FireServer("UnequipPet", toRemove) end)
						localEq[toRemove] = nil; localEqCount = localEqCount - 1
						task.wait(0.25)
					end
					pcall(function() PetsService:FireServer("EquipPet", target.uuid, CFrame.new(pos)) end)
					localEq[target.uuid] = true; localEqCount = localEqCount + 1
					table.insert(currentGrowing, target.uuid)
					ctx.state.elephantStartTime = ctx.state.elephantStartTime or {}
					ctx.state.elephantStartTime[target.uuid] = os.time()
					task.wait(0.3)
				end
			end
		end

		ctx.state.elephantStatus = string.format("Elephant: %d/%d aktif", #currentGrowing, maxPets)
	end

	local function elephantLoop()
		ctx.state.elephantId = (ctx.state.elephantId or 0) + 1
		local myId = ctx.state.elephantId
		ctx.elevate()
		ctx.state.elephantFirstRun = true

		-- Webhook saat enable (sama seperti leveling: cukup URL keisi, sender cek URL sendiri)
		task.spawn(function()
			if ctx.webhookElephant then
				pcall(function() ctx.webhookElephant.sendEnabled(ctx) end)
			end
		end)

		while CFG.elephantEnabled and ctx.alive() and ctx.state.elephantId == myId do
			pcall(checkElephant)
			task.wait(3.0)
		end
		ctx.state.elephantStatus = "Idle"
	end

	function ctx.startElephant()
		if ctx.cancelClearGarden then ctx.cancelClearGarden() end -- batalkan clear tertunda dari fitur lain
		ctx.state.elephantCfgOverride = nil -- webhook elephant pakai config standalone (bukan Growth)
		ctx.state.elephantWebhookPost = nil -- standalone: edit pesan (bukan POST tiap selesai)
		task.spawn(elephantLoop)
	end

	-- Matikan: hentikan loop lalu CABUT SEMUA pet dari garden sampai kosong total.
	function ctx.stopElephant()
		ctx.state.elephantId = (ctx.state.elephantId or 0) + 1 -- invalidate loop yang jalan
		task.spawn(function()
			ctx.state.elephantStatus = "Clearing garden..."
			task.wait(0.3)
			for _ = 1, 30 do
				local ok, d = pcall(function() return DataService:GetData() end)
				local eq = ok and d and d.PetsData and d.PetsData.EquippedPets or {}
				if #eq == 0 then break end
				for _, uuid in ipairs(eq) do
					pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
					task.wait(0.2)
				end
				task.wait(0.4)
			end
			ctx.state.elephantStatus = "Idle (garden kosong)"
		end)
	end
end
