--[[ listing.lua — inti listing: scan inventory, listPass sekuensial, loop utama, util unlist/unequip.
     Mengisi: ctx.inventoryCounts, ctx.selectedPetTypes, ctx.buildSummary,
              ctx.listPass, ctx.anyProfileActive, ctx.mainLoop,
              ctx.unlistAll, ctx.unequipAllPets ]]
return function(ctx)
	local LP                = ctx.LP
	local RS                = ctx.Services.RS
	local CollectionService = ctx.Services.CollectionService
	local DataService       = ctx.deps.DataService
	local CreateListing     = ctx.deps.CreateListing
	local RemoveListing     = ctx.deps.RemoveListing
	local CFG               = ctx.CFG
	local NUM_PROFILES      = ctx.NUM_PROFILES
	local NUM_LISTINGS      = ctx.NUM_LISTINGS
	local comboKey          = ctx.reg.comboKey
	local mutDisplay        = ctx.reg.mutDisplay
	local weightOf          = ctx.weightOf
	local ownsBooth         = ctx.ownsBooth
	local myPlayerId        = ctx.myPlayerId
	local getTokens         = ctx.getTokens
	local ensureBooth       = ctx.ensureBooth
	local function log(msg) ctx.log(msg) end
	local function setStatus(s) ctx.setStatus(s) end

	----------------------------------------------------------------- inventory helpers
	-- list pet di inventory
	local function inventoryCounts()
		local counts = {}
		local ok, data = pcall(function() return DataService:GetData() end)
		if ok and type(data) == "table" and data.PetsData and data.PetsData.PetInventory and data.PetsData.PetInventory.Data then
			for _, v in pairs(data.PetsData.PetInventory.Data) do
				local pt = v and v.PetType
				if pt then counts[pt] = (counts[pt] or 0) + 1 end
			end
		end
		return counts
	end

	local function selectedPetTypes()
		local set, order = {}, {}
		for pi = 1, NUM_PROFILES do
			local prof = CFG.profiles[pi]
			if prof and type(prof.listings) == "table" then
				for li = 1, NUM_LISTINGS do
					local sub = prof.listings[li]
					if sub and type(sub.pets) == "table" then
						for petKey in pairs(sub.pets) do
							local pt = (string.split(petKey, " - ")[1]) or petKey
							if not set[pt] then set[pt] = true; order[#order + 1] = pt end
						end
					end
				end
			end
		end
		table.sort(order)
		return order
	end

	local function buildSummary()
		local counts = inventoryCounts()
		local lines, total = {}, 0
		for _, pt in ipairs(selectedPetTypes()) do
			local c = counts[pt] or 0
			total = total + c
			lines[#lines + 1] = ("%s: %d"):format(pt, c)
		end
		return (#lines > 0 and table.concat(lines, "\n") or "-"), total
	end

	----------------------------------------------------------------- listPass
	-- satu putaran listing: STRICT SEQUENTIAL P1L1→P1L2→P1L3→P2L1→...
	-- Setiap listing harus TEPAT maxList sebelum lanjut ke listing berikutnya
	local function listPass()
		local owns, bData, boothName = ownsBooth()
		if not owns or not boothName then return 0 end

		-- Teleport ke booth jika terlalu jauh agar lolos cek jarak server
		local myBoothInst = nil
		for _, inst in ipairs(CollectionService:GetTagged("TradeBooth")) do
			if inst.Name == boothName then myBoothInst = inst; break end
		end
		if myBoothInst then
			local char = LP.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				local root = char.HumanoidRootPart
				if (root.Position - myBoothInst:GetPivot().Position).Magnitude > 8 then
					root.CFrame = myBoothInst:GetPivot() * CFrame.new(0, 3, 3)
					task.wait(0.25)
				end
			end
		end

		-- Ambil data booth & inventory TERBARU
		local myId = myPlayerId()
		local myRecord = bData.Players and (bData.Players[myId] or bData.Players[tostring(myId)])
		local currentList = myRecord and myRecord.Listings or {}

		-- REBUILD listedSet dari booth aktual (agar pet yang sudah dibeli otomatis hilang)
		local listedSet = {}
		ctx.state.listedSet = listedSet
		for _, l in pairs(currentList) do
			if l.ItemId then listedSet[l.ItemId] = true end
		end

		local ok, data = pcall(function() return DataService:GetData() end)
		if not ok or not (data and data.PetsData and data.PetsData.PetInventory) then return 0 end
		local pets  = data.PetsData.PetInventory.Data
		local locks = (data.TradeData and data.TradeData.TradeLocks and data.TradeData.TradeLocks.Pet) or {}

		local equippedSet = {}
		if data.PetsData and data.PetsData.EquippedPets then
			for _, eqUuid in ipairs(data.PetsData.EquippedPets) do
				equippedSet[eqUuid] = true
			end
		end

		-- Track UUID booth yang sudah di-claim listing sebelumnya (anti double-count)
		local claimedByOther = {}
		local total = 0

		-- Helper: cek pet cocok dengan listing config
		local function petMatches(petType, pd, sub)
			if not (sub.pets[petType] or sub.pets[comboKey(petType, pd.HatchedFrom or "?")]) then return false end
			local mut = mutDisplay(pd.MutationType)
			local mutOK
			if not next(sub.muts) then mutOK = (mut == "None") else mutOK = sub.muts[mut] == true end
			if not mutOK then return false end
			local w    = weightOf(petType, pd)
			-- minW: toleransi -0.5 agar pet tepat di batas tetap lolos (mis. set 3.845 → cek >=3.345)
			local minW = (sub.minW or 0) > 0 and (sub.minW - 0.5) or 0
			-- maxW: STRICT tanpa toleransi — pet melebihi batas harus ditolak
			local maxW = sub.maxW or 0
			-- lolos jika: berat >= minW DAN (maxW tidak di-set ATAU berat <= maxW)
			return (w >= minW) and (maxW <= 0 or w <= maxW)
		end

		-- STRICT SEQUENTIAL: P1L1 → P1L2 → P1L3 → P2L1 → P2L2 → ...
		for pi = 1, NUM_PROFILES do
			local prof = CFG.profiles[pi]
			if prof and type(prof.listings) == "table" then
				for li = 1, NUM_LISTINGS do
					if not ctx.state.running then return total end
					local sub = prof.listings[li]
					if sub and next(sub.pets) and (sub.price or 0) > 0 then
						local cap = (sub.maxList and sub.maxList > 0) and sub.maxList or 0
						if cap <= 0 then -- skip listing tanpa max cap
						else
							-- STEP 1: Hitung berapa pet di booth yang cocok listing ini
							local boothCount = 0
							for _, l in pairs(currentList) do
								local itemUuid = l.ItemId
								if itemUuid and not claimedByOther[itemUuid] then
									local invPet = pets[itemUuid]
									if invPet and invPet.PetType and invPet.PetData then
										if petMatches(invPet.PetType, invPet.PetData, sub) then
											boothCount = boothCount + 1
											claimedByOther[itemUuid] = true
										end
									end
								end
							end

							-- STEP 2: Kalau belum penuh, tambah sampai tepat cap
							local needed = cap - boothCount
							if needed > 0 then
								log(("P%d-L%d: %d/%d di booth, perlu +%d"):format(pi, li, boothCount, cap, needed))
								local added = 0
								for uuid, v in pairs(pets) do
									if not ctx.state.running then return total end
									if added >= needed then break end
									local pd = v.PetData
									if v.PetType and pd and not pd.IsFavorite
										and not locks[uuid] and not listedSet[uuid]
										and not equippedSet[uuid] and not claimedByOther[uuid] then
										if petMatches(v.PetType, pd, sub) then
											local ok2, res = pcall(function() return CreateListing:InvokeServer("Pet", uuid, math.floor(sub.price)) end)
											if ok2 and res then
												listedSet[uuid] = true
												claimedByOther[uuid] = true
												added = added + 1
												total = total + 1
												local mut = mutDisplay(pd.MutationType)
												local w = weightOf(v.PetType, pd)
												log(("LIST %s [%s] %.2fkg @%d (P%d-L%d) [%d/%d]"):format(v.PetType, mut, w, sub.price, pi, li, boothCount + added, cap))

												-- Webhook dipindah ke event beli actual

												task.wait(5)
											else
												log(("FAIL list %s (%s)"):format(v.PetType, tostring(res)))
												task.wait(3) -- tunggu rate limit hilang
											end
										end
									end
								end
								-- Kalau stock habis, SKIP ke listing berikutnya (jangan stuck)
								if boothCount + added < cap then
									log(("P%d-L%d: stock habis, baru %d/%d. Skip ke listing berikutnya."):format(pi, li, boothCount + added, cap))
								end
							end
							-- Kalau sudah penuh (needed <= 0), lanjut ke listing berikutnya ✓
						end
					end
				end
			end
		end
		return total
	end

	----------------------------------------------------------------- main loop
	local function anyProfileActive()
		for i = 1, NUM_PROFILES do
			local prof = CFG.profiles[i]
			if prof and type(prof.listings) == "table" then
				for j = 1, NUM_LISTINGS do
					if next(prof.listings[j].pets) then return true end
				end
			end
		end
		return false
	end

	local function mainLoop()
		ctx.state.currentLoopId = ctx.state.currentLoopId + 1
		local myLoopId = ctx.state.currentLoopId
		ctx.elevate()
		while ctx.state.running and ctx.alive() and ctx.state.currentLoopId == myLoopId do
			if not anyProfileActive() then
				setStatus("Pilih pet di profil listing dulu.")
				task.wait(2)
			else
				local ready = true
				if CFG.autoClaim then ready = ensureBooth() end
				if ready then
					local n = listPass()
					if n > 0 then
						setStatus(("Refill +%d | Token:%s"):format(n, tostring(getTokens())))
						task.wait(2) -- cepat cek lagi karena baru ada perubahan
					else
						setStatus(("Booth OK ✓ | Token:%s"):format(tostring(getTokens())))
						task.wait(3) -- semua penuh, monitoring mode
					end
				else
					setStatus("Menunggu booth ke-claim...")
					task.wait(2.5)
				end
			end
		end
	end

	----------------------------------------------------------------- unlist / unequip
	local function unlistAll()
		local owns, data, boothName = ownsBooth()
		if not owns or not data or not boothName then log("Kamu tidak punya booth."); return end

		-- Temukan booth instance untuk teleportasi (agar lolos cek jarak server)
		local myBoothInst = nil
		for _, inst in ipairs(CollectionService:GetTagged("TradeBooth")) do
			if inst.Name == boothName then myBoothInst = inst; break end
		end
		if myBoothInst then
			local char = LP.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				char.HumanoidRootPart.CFrame = myBoothInst:GetPivot() * CFrame.new(0, 3, 3)
				task.wait(0.25)
			end
		end

		local myId = myPlayerId()
		local pd = data.Players and (data.Players[myId] or data.Players[tostring(myId)])
		local list = pd and pd.Listings or {}
		local count = 0
		for lid, _ in pairs(list) do
			local ok, res = pcall(function() return RemoveListing:InvokeServer(lid) end)
			if ok and res then count += 1; task.wait(0.1) end
		end
		ctx.state.listedSet = {}
		log(("Sukses menghapus %d pajangan."):format(count))
	end

	local function unequipAllPets()
		local ok, PetsService = pcall(require, RS.Modules.PetServices.PetsService)
		if not ok or not PetsService then log("Gagal memuat PetsService."); return end
		local ok2, data = pcall(function() return DataService:GetData() end)
		if ok2 and data and data.PetsData and data.PetsData.EquippedPets then
			local count = 0
			for _, uuid in ipairs(data.PetsData.EquippedPets) do
				local ok3 = pcall(function() PetsService:UnequipPet(uuid) end)
				if ok3 then count += 1 end
			end
			log(("Unequipped %d pets."):format(count))
		else
			log("Tidak ada pet yang aktif terpasang.")
		end
	end

	ctx.inventoryCounts  = inventoryCounts
	ctx.selectedPetTypes = selectedPetTypes
	ctx.buildSummary     = buildSummary
	ctx.listPass         = listPass
	ctx.anyProfileActive = anyProfileActive
	ctx.mainLoop         = mainLoop
	ctx.unlistAll        = unlistAll
	ctx.unequipAllPets   = unequipAllPets
end
