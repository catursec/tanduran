--[[ mutation.lua — logika mesin mutasi pet otomatis (garden). ]]
return function(ctx)
	local DataService = ctx.deps.DataService
	local PetsService = ctx.deps.PetsService
	local CFG         = ctx.CFG
	local LP          = ctx.LP
	local RS          = game:GetService("ReplicatedStorage")
	local TimeHelper  = require(RS.Modules.TimeHelper)
	local PetMutationMachineService_RE = RS:WaitForChild("GameEvents").PetMutationMachineService_RE

	local function farmCenter()
		local GetFarm = require(RS.Modules.GetFarm)
		local farm = GetFarm and GetFarm(LP)
		local pa = farm and farm:FindFirstChild("PetArea")
		if pa then return pa.Position end
		local char = LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		return hrp and hrp.Position or nil
	end

	local function cleanUuid(u)
		if not u then return "" end
		return tostring(u):lower():gsub("[{}]", "")
	end

	local function hasTargetMutation(pd, targetMutations)
		if not pd then return false end
		local mut = pd.MutationType
		local display = ctx.reg.mutDisplay and ctx.reg.mutDisplay(mut) or tostring(mut or "None")
		return targetMutations[display] == true
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

	-- Helper untuk memastikan tim pet terpasang 100% dengan benar (dengan retry loop)
	local function ensureEquippedTeam(targetTeamSet, targetPetUuid)
		local targetActive = {}
		if targetPetUuid then
			targetActive[cleanUuid(targetPetUuid)] = true
		end
		for u, _ in pairs(targetTeamSet) do
			targetActive[cleanUuid(u)] = true
		end

		for attempt = 1, 3 do
			local ok, d = pcall(function() return DataService:GetData() end)
			if not ok or not d or not d.PetsData then break end
			local eq = d.PetsData.EquippedPets or {}
			
			local localEq = {}
			for _, uuid in ipairs(eq) do
				localEq[cleanUuid(uuid)] = true
			end

			-- 1. Lepas pet yang tidak diijinkan berada di garden
			local unequippedAny = false
			for _, uuid in ipairs(eq) do
				local cu = cleanUuid(uuid)
				if not targetActive[cu] then
					pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
					unequippedAny = true
					task.wait(0.1)
				end
			end

			-- 2. Pasang target pet (jika leveling)
			local equippedAny = false
			if targetPetUuid and not localEq[cleanUuid(targetPetUuid)] then
				local pos = getPos(targetPetUuid)
				if pos then
					pcall(function() PetsService:FireServer("EquipPet", targetPetUuid, CFrame.new(pos)) end)
					equippedAny = true
					task.wait(0.1)
				end
			end

			-- 3. Pasang sisa anggota team yang belum terpasang
			for uuid, _ in pairs(targetTeamSet) do
				local cu = cleanUuid(uuid)
				if not localEq[cu] then
					local pos = getPos(uuid)
					if pos then
						pcall(function() PetsService:FireServer("EquipPet", uuid, CFrame.new(pos)) end)
						equippedAny = true
						task.wait(0.1)
					end
				end
			end

			-- Jika tidak ada aktivitas unequip/equip lagi, berarti kebun sudah sinkron
			if not unequippedAny and not equippedAny then
				break
			end
			task.wait(0.3)
		end

		-- Verifikasi kelengkapan: SEMUA anggota target harus benar-benar ke-equip (no miss).
		local ok, d = pcall(function() return DataService:GetData() end)
		local eq = ok and d and d.PetsData and d.PetsData.EquippedPets or {}
		local eqSet = {}
		for _, uuid in ipairs(eq) do eqSet[cleanUuid(uuid)] = true end
		for cu in pairs(targetActive) do
			if not eqSet[cu] then return false end
		end
		return true
	end

	ctx.state.mutationStatus = "Idle"
	ctx.state.mutationPhase = "Idle"

	-- Mendapatkan ringkasan statistik mutation untuk UI
	function ctx.getMutationSummary()
		local ok, d = pcall(function() return DataService:GetData() end)
		local inv = ok and d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}
		local machine = ok and d and d.PetMutationMachine or {}

		local expCount = 0
		for _ in pairs(CFG.mutationExpTeam) do expCount = expCount + 1 end

		local boostCount = 0
		for _ in pairs(CFG.mutationBoostTeam) do boostCount = boostCount + 1 end

		local phoenixCount = 0
		for _ in pairs(CFG.mutationPhoenixTeam) do phoenixCount = phoenixCount + 1 end

		local typesList = {}
		for k in pairs(CFG.mutationTargetTypes) do table.insert(typesList, k) end
		table.sort(typesList)
		local typesStr = #typesList > 0 and table.concat(typesList, ", ") or "None"

		local mutsList = {}
		for k in pairs(CFG.mutationTargetMutations) do table.insert(mutsList, k) end
		table.sort(mutsList)
		local mutsStr = #mutsList > 0 and table.concat(mutsList, ", ") or "None"

		local targetAge = CFG.mutationTargetAge or 50

		-- Info mesin
		local machineStr = "Empty"
		if machine.SubmittedPet then
			local pt = machine.SubmittedPet.PetType or "?"
			local mut = machine.SubmittedPet.PetData and machine.SubmittedPet.PetData.MutationType or "Normal"
			local mutName = ctx.reg.mutDisplay and ctx.reg.mutDisplay(mut) or mut
			machineStr = string.format("%s | %s", pt, mutName)
			if machine.PetReady then
				machineStr = machineStr .. " [Ready]"
			elseif machine.IsRunning or (machine.TimeLeft and machine.TimeLeft > 0) then
				local v2 = TimeHelper:GenerateColonFormatFromTime(machine.TimeLeft) or "00:00"
				machineStr = machineStr .. string.format(" [CD: %s]", v2)
			end
		end

		local readyCount = 0
		local doneCount = 0

		for _, v in pairs(inv) do
			local pt = v.PetType
			if CFG.mutationTargetTypes[pt] then
				local pd = v.PetData or {}
				local lvl = pd.Level or 0
				local mut = pd.MutationType or "Normal"
				local isFav = pd.IsFavorite or false

				if not isFav then
					if hasTargetMutation(pd, CFG.mutationTargetMutations) then
						doneCount = doneCount + 1
					else
						-- Belum punya mutasi target = masih perlu diproses (bakal di-leveling
						-- dulu kalau age belum cukup, lalu di-submit). Hitung semua, lepas dari level.
						readyCount = readyCount + 1
					end
				end
			end
		end

		return {
			status = CFG.mutationEnabled and "ACTIVE" or "STOPPED",
			phase = ctx.state.mutationPhase or "Idle",
			expCount = expCount,
			boostCount = boostCount,
			phoenixCount = phoenixCount,
			types = typesStr,
			mutations = mutsStr,
			targetAge = targetAge,
			machine = machineStr,
			readyCount = readyCount,
			doneCount = doneCount,
		}
	end

	local function checkMutation()
		local ok, d = pcall(function() return DataService:GetData() end)
		if not ok or not d then return end
		local petsData = d.PetsData
		local machine = d.PetMutationMachine
		if not petsData or not machine then return end
		local eq = petsData.EquippedPets or {}
		local inv = petsData.PetInventory and petsData.PetInventory.Data or {}

		local expTeam = CFG.mutationExpTeam or {}
		local boostTeam = CFG.mutationBoostTeam or {}
		local phoenixTeam = CFG.mutationPhoenixTeam or {}
		local targetTypes = CFG.mutationTargetTypes or {}
		local targetMutations = CFG.mutationTargetMutations or {}
		local targetAge = CFG.mutationTargetAge or 50
		local delayClaim = CFG.mutationDelayAutoClaim or 0.5

		-- CATATAN: passing team ASLI (uuid ber-kurawal) ke ensureEquippedTeam. cleanUuid dipakai
		-- HANYA buat matching di dalam fungsi; EquipPet butuh uuid format asli (dengan {}).

		-- A. DETEKSI APAKAH PET READY UNTUK DICLAIM
		if machine.PetReady then
			-- Validasi Phoenix team LENGKAP dulu (no miss) sebelum claim.
			if not ensureEquippedTeam(phoenixTeam) then
				ctx.state.mutationPhase = "Menunggu Phoenix Team lengkap..."
				return
			end
			ctx.state.mutationPhase = "Claiming Pet"

			-- Tunggu delay klaim
			task.wait(delayClaim)
			
			-- 1. Ambil snapshot mutasi pet di inventory sebelum klaim
			local preSnapshot = {}
			local okSnap, snapD = pcall(function() return DataService:GetData() end)
			if okSnap and snapD and snapD.PetsData then
				local invD = snapD.PetsData.PetInventory and snapD.PetsData.PetInventory.Data or {}
				for u, v in pairs(invD) do
					if targetTypes[v.PetType] then
						preSnapshot[u] = v.PetData and v.PetData.MutationType or "Normal"
					end
				end
			end

			-- Kirim remote klaim
			pcall(function() PetMutationMachineService_RE:FireServer("ClaimMutatedPet") end)
			task.wait(1.0)

			-- 2. Tentukan pet hasil klaim.
			-- Sumber UTAMA = machine.SubmittedPet (pet yg barusan diproses) -> reliable, ga
			-- jadi "Unknown" walau data inventory telat sync. Diff inventory dipakai buat
			-- refine (mis. dapat mutasi hasil terbaru) kalau ketemu.
			local sp = machine.SubmittedPet or {}
			local claimedPetType = sp.PetType or "Unknown"
			local outcomeMutation = (sp.PetData and sp.PetData.MutationType) or "Normal"

			local ok3, d3 = pcall(function() return DataService:GetData() end)
			if ok3 and d3 and d3.PetsData then
				local newInv = d3.PetsData.PetInventory and d3.PetsData.PetInventory.Data or {}
				for u, v in pairs(newInv) do
					if targetTypes[v.PetType] then
						local pd = v.PetData or {}
						local mut = pd.MutationType or "Normal"
						if not preSnapshot[u] or preSnapshot[u] ~= mut then
							claimedPetType = v.PetType
							outcomeMutation = mut
							break
						end
					end
				end
			end
			local isMatched = hasTargetMutation({ MutationType = outcomeMutation }, targetMutations)

			-- Durasi proses: dari submit sampai klaim
			local duration = 0
			if ctx.state.mutationSubmitTime then
				duration = os.time() - ctx.state.mutationSubmitTime
				ctx.state.mutationSubmitTime = nil
			end

			-- Kirim Webhook Claimed
			task.spawn(function()
				local WebhookMut = ctx.webhookMutation
				if WebhookMut then
					pcall(function() WebhookMut.sendClaimed(ctx, claimedPetType, outcomeMutation, isMatched, duration) end)
				end
			end)

			if isMatched then
				-- Pet ini dapat mutasi target. JANGAN matikan automation — lanjut proses
				-- pet ready berikutnya (section D sudah auto-skip pet yg sudah hasTargetMutation,
				-- jadi pet ini ga bakal diproses ulang).
				ctx.state.mutationPhase = "Matched! Lanjut next target..."
			else
				ctx.state.mutationPhase = "Non-target, lanjut..."
			end
			return
		end

		-- B. DETEKSI APAKAH MESIN SEDANG BERJALAN
		if machine.IsRunning or (machine.TimeLeft and machine.TimeLeft > 0) then
			-- Validasi Boost team LENGKAP dulu (no miss) baru dianggap boosting.
			if ensureEquippedTeam(boostTeam) then
				ctx.state.mutationPhase = "Boosting Machine"
			else
				ctx.state.mutationPhase = "Menunggu Boost Team lengkap..."
			end
			return
		end

		-- C. DETEKSI PET SUDAH DI-SUBMIT TETAPI BELUM DI-START
		if machine.SubmittedPet and not machine.IsRunning then
			ctx.state.mutationPhase = "Starting Machine"
			pcall(function() PetMutationMachineService_RE:FireServer("StartMachine") end)
			task.wait(0.5)
			return
		end

		-- D. DETEKSI MESIN KOSONG: Cari pet dari inventory untuk dimasukkan ke mesin
		if not machine.SubmittedPet then
			-- Cari pet target yang siap (level >= targetAge)
			local candidateUuid, candidateType
			for uuid, v in pairs(inv) do
				local pt = v.PetType
				local pd = v.PetData or {}
				local lvl = pd.Level or 0
				local mut = pd.MutationType or "Normal"
				local isFav = pd.IsFavorite or false

				-- Hanya pet tipe target, dengan level >= targetAge, bukan favorite, dan belum memiliki mutasi target
				if targetTypes[pt] and lvl >= targetAge and not isFav and not hasTargetMutation(pd, targetMutations) then
					candidateUuid = uuid
					candidateType = pt
					break
				end
			end

			-- Jika ada pet yang siap, submit ke mesin!
			if candidateUuid then
				ctx.state.mutationPhase = "Submitting Target"
				
				-- 1. Pastikan dicopot dari garden dulu sebelum di-submit
				pcall(function() PetsService:FireServer("UnequipPet", candidateUuid) end)
				task.wait(0.25)

				-- 2. Cari tool pet tersebut di Backpack atau Character
				local targetTool
				for _, item in ipairs(LP.Backpack:GetChildren()) do
					if item:IsA("Tool") and cleanUuid(item:GetAttribute("PET_UUID")) == cleanUuid(candidateUuid) then
						targetTool = item
						break
					end
				end
				if not targetTool and LP.Character then
					for _, item in ipairs(LP.Character:GetChildren()) do
						if item:IsA("Tool") and cleanUuid(item:GetAttribute("PET_UUID")) == cleanUuid(candidateUuid) then
							targetTool = item
							break
						end
					end
				end

				-- 3. Equip pet ke tangan lalu VERIFIKASI beneran dipegang sebelum submit.
				--    Cegah submit KOSONG kalau equip gagal/ke-race (mesin nerima submit hampa
				--    -> langsung "ready" tanpa isi). Kalau gagal pegang, JANGAN submit.
				if targetTool then
					local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
					local held
					for _ = 1, 4 do
						pcall(function()
							if hum then hum:EquipTool(targetTool) else targetTool.Parent = LP.Character end
						end)
						task.wait(0.35)
						local h = LP.Character and LP.Character:FindFirstChildWhichIsA("Tool")
						if h and cleanUuid(h:GetAttribute("PET_UUID")) == cleanUuid(candidateUuid) then
							held = h
							break
						end
					end

					if held then
						pcall(function() PetMutationMachineService_RE:FireServer("SubmitHeldPet") end)
						-- Duration: dari mulai EXP leveling kalau pet ini sempat di-level, else dari submit
						ctx.state.mutationStartTime = ctx.state.mutationStartTime or {}
						ctx.state.mutationSubmitTime = ctx.state.mutationStartTime[candidateUuid] or os.time()
						ctx.state.mutationStartTime[candidateUuid] = nil
						task.wait(0.5)

						-- Kirim Webhook Submitted
						task.spawn(function()
							local WebhookMut = ctx.webhookMutation
							if WebhookMut then
								local petLevel = inv[candidateUuid] and inv[candidateUuid].PetData and inv[candidateUuid].PetData.Level or 50
								pcall(function() WebhookMut.sendSubmitted(ctx, candidateType, petLevel) end)
							end
						end)

						-- Jalankan mesin langsung di detik yang sama
						pcall(function() PetMutationMachineService_RE:FireServer("StartMachine") end)
						task.wait(0.3)
					else
						ctx.state.mutationPhase = "Gagal pegang pet, retry..."
					end
				end
				return
			end

			-- Jika tidak ada pet yang siap, cari pet target yang levelnya kurang untuk kita LEVELING!
			local levelUuid, levelType, levelLvl
			for uuid, v in pairs(inv) do
				local pt = v.PetType
				local pd = v.PetData or {}
				local lvl = pd.Level or 0
				local mut = pd.MutationType or "Normal"
				local isFav = pd.IsFavorite or false

				if targetTypes[pt] and lvl < targetAge and not isFav and not hasTargetMutation(pd, targetMutations) then
					-- Prioritaskan level yang paling tinggi tapi masih di bawah targetAge agar cepat jadi!
					if not levelLvl or lvl > levelLvl then
						levelUuid = uuid
						levelType = pt
						levelLvl = lvl
					end
				end
			end

			-- Jika ada pet yang perlu di-leveling:
			if levelUuid then
				-- Validasi EXP team + target pet LENGKAP dulu (no miss).
				if ensureEquippedTeam(expTeam, levelUuid) then
					ctx.state.mutationPhase = "Leveling Target"
					-- Catat mulai proses EXP leveling pet ini (buat Duration total)
					ctx.state.mutationStartTime = ctx.state.mutationStartTime or {}
					if not ctx.state.mutationStartTime[levelUuid] then
						ctx.state.mutationStartTime[levelUuid] = os.time()
					end
				else
					ctx.state.mutationPhase = "Menunggu EXP Team lengkap..."
				end
				return
			end

			-- Jika sama sekali tidak ada pet kandidat
			ctx.state.mutationPhase = "Idle (No Targets)"
		end
	end

	local function mutationLoop()
		ctx.state.mutationId = (ctx.state.mutationId or 0) + 1
		local myId = ctx.state.mutationId
		ctx.elevate()

		-- Kirim Webhook Enabled
		task.spawn(function()
			local WebhookMut = ctx.webhookMutation
			if WebhookMut then
				local expTeamList = {}
				local boostTeamList = {}
				local phoenixTeamList = {}

				local okData, d = pcall(function() return DataService:GetData() end)
				if okData and d and d.PetsData then
					local inv = d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}

					-- 1. EXP Team
					for uuid, _ in pairs(CFG.mutationExpTeam or {}) do
						local pInfo = inv[uuid]
						if pInfo then table.insert(expTeamList, pInfo.PetType) end
					end

					-- 2. Boost Team
					for uuid, _ in pairs(CFG.mutationBoostTeam or {}) do
						local pInfo = inv[uuid]
						if pInfo then table.insert(boostTeamList, pInfo.PetType) end
					end

					-- 3. Phoenix Team
					for uuid, _ in pairs(CFG.mutationPhoenixTeam or {}) do
						local pInfo = inv[uuid]
						if pInfo then table.insert(phoenixTeamList, pInfo.PetType) end
					end
				end

				pcall(function() 
					WebhookMut.sendEnabled(ctx, CFG.mutationTargetTypes, CFG.mutationTargetMutations, CFG.mutationTargetAge, expTeamList, boostTeamList, phoenixTeamList)
				end)
			end
		end)

		while CFG.mutationEnabled and ctx.alive() and ctx.state.mutationId == myId do
			pcall(checkMutation)
			task.wait(3.0)
		end
		ctx.state.mutationStatus = "Idle"
		ctx.state.mutationPhase = "Idle"
	end

	function ctx.startMutation()
		if ctx.cancelClearGarden then ctx.cancelClearGarden() end
		task.spawn(mutationLoop)
	end

	function ctx.stopMutation()
		ctx.state.mutationId = (ctx.state.mutationId or 0) + 1 -- matikan loop
		if ctx.clearGarden then ctx.clearGarden("Mutation") end
	end
end
