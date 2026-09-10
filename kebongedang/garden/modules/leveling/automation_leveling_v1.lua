--[[ leveling.lua — logika leveling pet otomatis (garden). ]]
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

	ctx.state.levelingStatus = "Idle"

	-- Mendapatkan ringkasan statistik leveling untuk UI
	function ctx.getLevelingSummary()
		local ok, d = pcall(function() return DataService:GetData() end)
		local inv = ok and d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}
		
		local teamCount = 0
		for _ in pairs(CFG.levelingTeamUuids) do teamCount = teamCount + 1 end
		
		local typesList = {}
		for k in pairs(CFG.levelingPetTypes) do table.insert(typesList, k) end
		table.sort(typesList)
		local typesStr = #typesList > 0 and table.concat(typesList, ", ") or "None"
		
		local readyCount = 0
		local maxLvlCount = 0
		local targetLvl = CFG.levelingTargetLevel or 500
		
		for _, v in pairs(inv) do
			local pt = v.PetType
			if CFG.levelingPetTypes[pt] then
				local pd = v.PetData or {}
				local lvl = pd.Level or 0
				if not pd.IsFavorite then
					if lvl < targetLvl then
						readyCount = readyCount + 1
					else
						maxLvlCount = maxLvlCount + 1
					end
				end
			end
		end
		
		return {
			status = CFG.levelingEnabled and "ACTIVE" or "STOPPED",
			team = string.format("%d pets selected", teamCount),
			types = typesStr,
			ready = string.format("%d pets", readyCount),
			maxLvl = string.format("%d pets", maxLvlCount),
			maxInGarden = string.format("%d pets", CFG.levelingMaxPets or 2),
			targetLevel = tostring(targetLvl),
		}
	end

	-- Mendapatkan semua tipe unik pet yang dimiliki di inventory
	function ctx.getInventoryPetTypes(selectedSet)
		local out, seen = {}, {}
		local ok, d = pcall(function() return DataService:GetData() end)
		local inv = ok and d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data
		if inv then
			for _, v in pairs(inv) do
				local pt = v.PetType
				if pt and not seen[pt] then
					seen[pt] = true
					table.insert(out, { value = pt, display = pt })
				end
			end
		end
		-- Selalu tampilkan tipe yang DIPILIH walau stok 0 (biar pilihan ga ilang dari filter).
		if selectedSet then
			for t in pairs(selectedSet) do
				if not seen[t] then
					seen[t] = true
					table.insert(out, { value = t, display = t .. " (0 di inventory)" })
				end
			end
		end
		table.sort(out, function(a, b)
			local selA = selectedSet and selectedSet[a.value] and 1 or 0
			local selB = selectedSet and selectedSet[b.value] and 1 or 0
			if selA ~= selB then
				return selA > selB
			end
			return a.display < b.display
		end)
		return out
	end

	local function checkLeveling()
		local ok, d = pcall(function() return DataService:GetData() end)
		if not ok or not d then return end
		local petsData = d.PetsData
		if not petsData then return end
		local eq = petsData.EquippedPets or {}
		local inv = petsData.PetInventory and petsData.PetInventory.Data or {}

		local teamSet = CFG.levelingTeamUuids or {}
		local targetTypes = CFG.levelingPetTypes or {}
		local targetLvl = CFG.levelingTargetLevel or 500
		local maxLvlPets = CFG.levelingMaxPets or 2

		-- Lacak status equip secara lokal agar kebal dari delay replikasi server
		local localEq = {}
		local localEqCount = 0
		for _, uuid in ipairs(eq) do
			localEq[uuid] = true
			localEqCount = localEqCount + 1
		end

		-- A. DETEKSI FIRST RUN: Cabut semua pet jika ada pet aktif
		if ctx.state.levelingFirstRun then
			ctx.state.levelingFirstRun = false
			if #eq > 0 then
				ctx.state.levelingStatus = "Resetting garden..."
				for _, uuid in ipairs(eq) do
					pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
					localEq[uuid] = nil
					localEqCount = localEqCount - 1
					task.wait(0.25)
				end
			end
		end

		-- B. DETEKSI PERSISTENSI TEAM: Pasang kembali pet team yang dicabut oleh user/game
		for uuid, _ in pairs(teamSet) do
			if not localEq[uuid] then
				ctx.state.levelingStatus = "Re-equipping team..."
				local pos = getPos(uuid)
				if pos then
					pcall(function() PetsService:FireServer("EquipPet", uuid, CFrame.new(pos)) end)
					localEq[uuid] = true
					localEqCount = localEqCount + 1
					task.wait(0.3)
				end
			end
		end

		-- C. KLASIFIKASI PET YANG SEDANG DI-EQUIP (berdasarkan localEq terbaru)
		local currentLeveling = {}   -- list of active leveling uuids (lvl < targetLvl)
		local finishedLeveling = {}  -- list of finished leveling uuids (lvl >= targetLvl)
		local otherEquipped = {}     -- list of other uuids (not team, not target type)

		for uuid, _ in pairs(localEq) do
			if not teamSet[uuid] then
				local pInfo = inv[uuid]
				local pt = pInfo and pInfo.PetType
				local pd = pInfo and pInfo.PetData or {}
				local lvl = pd.Level or 0

				if targetTypes[pt] then
					if lvl < targetLvl then
						table.insert(currentLeveling, uuid)
						-- Catat waktu mulai jika belum ada
						ctx.state.levelingStartTime = ctx.state.levelingStartTime or {}
						if not ctx.state.levelingStartTime[uuid] then
							ctx.state.levelingStartTime[uuid] = os.time()
						end
					else
						table.insert(finishedLeveling, uuid)
					end
				else
					table.insert(otherEquipped, uuid)
				end
			end
		end

		-- D. LEPAS PET LEVELING YANG SUDAH SELESAI (mencapai target level)
		for _, uuid in ipairs(finishedLeveling) do
			local duration = 0
			if ctx.state.levelingStartTime and ctx.state.levelingStartTime[uuid] then
				duration = os.time() - ctx.state.levelingStartTime[uuid]
				ctx.state.levelingStartTime[uuid] = nil
			end

			local pInfo = inv[uuid]
			local petType = pInfo and pInfo.PetType or "Unknown"
			local pd = pInfo and pInfo.PetData or {}
			local mutation = pd.MutationType or "Normal"
			local finalAge = pd.Level or targetLvl

			pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
			localEq[uuid] = nil
			localEqCount = localEqCount - 1
			task.wait(0.25)

			-- Hitung sisa antrean
			local remainsQueue = 0
			for otherUuid, v in pairs(inv) do
				local pt = v.PetType
				if targetTypes[pt] and not localEq[otherUuid] then
					local otherPd = v.PetData or {}
					local otherLvl = otherPd.Level or 0
					if otherLvl < targetLvl and not otherPd.IsFavorite then
						remainsQueue = remainsQueue + 1
					end
				end
			end

			-- Kirim Webhook Finished
			task.spawn(function()
				local WebhookLev = ctx.webhookLeveling
				if WebhookLev then
					pcall(function() WebhookLev.sendFinished(ctx, petType, mutation, finalAge, duration, remainsQueue) end)
				end
			end)
		end

		-- E. TAMBAHKAN PET BARU DARI INVENTORY
		local currentActiveCount = #currentLeveling
		local needed = maxLvlPets - currentActiveCount

		if needed > 0 then
			-- Cari pool pet di inventory yang tidak ter-equip di localEq
			local pool = {}
			for uuid, v in pairs(inv) do
				local pt = v.PetType
				local pd = v.PetData or {}
				local lvl = pd.Level or 0

				if not localEq[uuid] and targetTypes[pt] and lvl < targetLvl and not pd.IsFavorite then
					table.insert(pool, { uuid = uuid, petType = pt, level = lvl })
				end
			end
			table.sort(pool, function(a, b) return a.level < b.level end) -- Prioritaskan level terendah

			for i = 1, math.min(needed, #pool) do
				local target = pool[i]
				local pos = getPos(target.uuid)
				if pos then
					-- Jika total equipped secara lokal penuh (misal >= 15), copot non-team non-leveling
					if localEqCount >= 15 and #otherEquipped > 0 then
						local toRemove = table.remove(otherEquipped)
						pcall(function() PetsService:FireServer("UnequipPet", toRemove) end)
						localEq[toRemove] = nil
						localEqCount = localEqCount - 1
						task.wait(0.25)
					end
					
					pcall(function() PetsService:FireServer("EquipPet", target.uuid, CFrame.new(pos)) end)
					localEq[target.uuid] = true
					localEqCount = localEqCount + 1
					table.insert(currentLeveling, target.uuid)
					-- Catat waktu mulai
					ctx.state.levelingStartTime = ctx.state.levelingStartTime or {}
					ctx.state.levelingStartTime[target.uuid] = os.time()
					task.wait(0.3)
				end
			end
		end

		-- Update status akhir setelah proses
		ctx.state.levelingStatus = string.format("Leveling: %d/%d aktif", #currentLeveling, maxLvlPets)
	end

	local function levelingLoop()
		ctx.state.levelingId = (ctx.state.levelingId or 0) + 1
		local myId = ctx.state.levelingId
		ctx.elevate()
		
		ctx.state.levelingFirstRun = true

		-- Kirim webhook Enabled
		task.spawn(function()
			local WebhookLev = ctx.webhookLeveling
			if WebhookLev then
				local queueList = {}
				local teamList = {}
				local okData, d = pcall(function() return DataService:GetData() end)
				if okData and d and d.PetsData then
					local inv = d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}
					
					-- 1. Antrean pet target
					local targetTypes = CFG.levelingPetTypes or {}
					local targetLvl = CFG.levelingTargetLevel or 500
					for _, v in pairs(inv) do
						local pt = v.PetType
						if targetTypes[pt] then
							local pd = v.PetData or {}
							local lvl = pd.Level or 0
							if lvl < targetLvl then
								table.insert(queueList, { type = pt, level = lvl })
							end
						end
					end

					-- 2. Nama pet dalam EXP team
					local teamUuids = CFG.levelingTeamUuids or {}
					for uuid, _ in pairs(teamUuids) do
						local pInfo = inv[uuid]
						if pInfo then
							table.insert(teamList, pInfo.PetType)
						end
					end
				end
				pcall(function() WebhookLev.sendEnabled(ctx, queueList, teamList) end)
			end
		end)
		
		while CFG.levelingEnabled and ctx.alive() and ctx.state.levelingId == myId do
			pcall(checkLeveling)
			task.wait(3.0)
		end
		ctx.state.levelingStatus = "Idle"
	end

	function ctx.startLeveling()
		if ctx.cancelClearGarden then ctx.cancelClearGarden() end -- batalkan clear tertunda
		task.spawn(levelingLoop) -- loop set firstRun=true -> reset garden + equip team
	end

	-- Batalkan clearGarden yang mungkin lagi jalan (dipanggil saat fitur di-ENABLE lagi,
	-- biar pet team yang baru dipasang ga ke-unequip balik oleh clear yang tertunda).
	function ctx.cancelClearGarden()
		ctx.state.clearGardenId = (ctx.state.clearGardenId or 0) + 1
	end

	-- Lepas SEMUA pet dari garden (dipakai stop leveling/mutation/cleanse, mirror elephant).
	function ctx.clearGarden(label)
		ctx.state.clearGardenId = (ctx.state.clearGardenId or 0) + 1
		local myGen = ctx.state.clearGardenId
		task.spawn(function()
			if ctx.setStatus then ctx.setStatus((label or "Clear") .. ": lepas pet dari garden...") end
			task.wait(0.3)
			for _ = 1, 30 do
				if ctx.state.clearGardenId ~= myGen then return end -- dibatalkan (fitur di-enable lagi)
				local ok, d = pcall(function() return DataService:GetData() end)
				local eq = ok and d and d.PetsData and d.PetsData.EquippedPets or {}
				if #eq == 0 then break end
				for _, uuid in ipairs(eq) do
					if ctx.state.clearGardenId ~= myGen then return end
					pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
					task.wait(0.2)
				end
				task.wait(0.4)
			end
			if ctx.state.clearGardenId == myGen and ctx.setStatus then ctx.setStatus((label or "Clear") .. ": garden kosong.") end
		end)
	end

	function ctx.stopLeveling()
		ctx.state.levelingId = (ctx.state.levelingId or 0) + 1 -- matikan loop
		ctx.clearGarden("Leveling")
	end
end
