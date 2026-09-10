--[[ leveling_v2.lua — Automation Leveling V2 (2 phase).
     Konsep sama dengan V1 tapi bertahap:
       Phase 1: pakai Phase 1 Team, level target pet dari age 1 s/d Phase 1 Target,
                max Phase 1 Max Pets di garden.
       Phase 2: setelah semua target pet >= Phase 1 Target, ganti ke Phase 2 Team,
                level s/d Phase 2 Target (final), max Phase 2 Max Pets.
     Team & jumlah pet di garden beda per-phase (mis. cepat di awal, sedikit di akhir). ]]
return function(ctx)
	local DataService = ctx.deps.DataService
	local PetsService = ctx.deps.PetsService
	local CFG = ctx.CFG
	local LP  = ctx.LP
	local RS  = game:GetService("ReplicatedStorage")

	----------------------------------------------------------------- posisi grid
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
		return center + Vector3.new((col - (GRID_COLS - 1) / 2) * GRID_SP, 0, (row - 1) * GRID_SP)
	end

	ctx.state.levelingV2Status = "Idle"

	----------------------------------------------------------------- ringkasan status
	function ctx.getLevelingV2Summary()
		local ok, d = pcall(function() return DataService:GetData() end)
		local inv = ok and d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}
		local types = CFG.levelingV2PetTypes or {}
		local p1t = CFG.levelingV2P1Target or 40
		local p2t = CFG.levelingV2P2Target or 500
		local p1q, p2q, maxq = 0, 0, 0
		for _, v in pairs(inv) do
			if types[v.PetType] and not (v.PetData or {}).IsFavorite then
				local lvl = (v.PetData or {}).Level or 0
				if lvl < p1t then p1q = p1q + 1
				elseif lvl < p2t then p2q = p2q + 1
				else maxq = maxq + 1 end          -- udah >= target final = max level
			end
		end
		local function cnt(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
		local function nm(t) local o = {}; for k in pairs(t or {}) do o[#o + 1] = k end; return #o > 0 and table.concat(o, ", ") or "-" end
		return {
			status = CFG.levelingV2Enabled and "ACTIVE" or "STOPPED",
			phase = ctx.state.levelingV2Phase or "-",
			types = nm(types),
			p1team = cnt(CFG.levelingV2P1Team), p2team = cnt(CFG.levelingV2P2Team),
			p1queue = p1q, p2queue = p2q, maxLvl = maxq,
			p1target = p1t, p2target = p2t,
		}
	end

	----------------------------------------------------------------- core check
	local function checkV2()
		local ok, d = pcall(function() return DataService:GetData() end)
		if not ok or not d then return end
		local petsData = d.PetsData
		if not petsData then return end
		local eq  = petsData.EquippedPets or {}
		local inv = petsData.PetInventory and petsData.PetInventory.Data or {}

		local targetTypes = CFG.levelingV2PetTypes or {}
		local p1Team = CFG.levelingV2P1Team or {}
		local p2Team = CFG.levelingV2P2Team or {}
		local p1Target = CFG.levelingV2P1Target or 40
		local p2Target = CFG.levelingV2P2Target or 500
		local p1Max = CFG.levelingV2P1Max or 3
		local p2Max = CFG.levelingV2P2Max or 1

		-- Tentukan phase aktif: ada target pet < p1Target -> Phase 1, else Phase 2.
		local phase1Work = 0
		for _, v in pairs(inv) do
			if targetTypes[v.PetType] and ((v.PetData or {}).Level or 0) < p1Target and not (v.PetData or {}).IsFavorite then phase1Work = phase1Work + 1 end
		end
		local phase = (phase1Work > 0) and 1 or 2
		ctx.state.levelingV2Phase = "Phase " .. phase
		local team       = (phase == 1) and p1Team or p2Team
		local otherTeam  = (phase == 1) and p2Team or p1Team
		local phaseTarget = (phase == 1) and p1Target or p2Target
		local phaseMin    = (phase == 1) and 0 or p1Target  -- batas bawah level utk phase ini
		local maxPets     = (phase == 1) and p1Max or p2Max

		-- Deteksi TRANSISI phase -> picu pembersihan garden TOTAL.
		if ctx.state.levelingV2LastPhase ~= nil and ctx.state.levelingV2LastPhase ~= phase then
			ctx.state.levelingV2Clearing = true
		end
		ctx.state.levelingV2LastPhase = phase

		local localEq = {}
		for _, uuid in ipairs(eq) do localEq[uuid] = true end

		-- A. First run / TRANSISI phase: bersihin garden TOTAL & pastikan BENAR-BENAR kosong
		-- dulu (verified) sebelum pasang team phase baru. Cegah sisa pet phase 1 nyangkut.
		if ctx.state.levelingV2FirstRun or ctx.state.levelingV2Clearing then
			if #eq > 0 then
				ctx.state.levelingV2Status = ("Phase %d: bersihin garden dulu (%d pet)..."):format(phase, #eq)
				for _, uuid in ipairs(eq) do
					pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
					task.wait(0.2)
				end
				return -- cek ulang cycle berikutnya sampai garden BENAR-BENAR kosong
			end
			-- garden udah kosong -> pembersihan selesai, lanjut pasang team
			ctx.state.levelingV2FirstRun = false
			ctx.state.levelingV2Clearing = false
		end

		-- C. Pasang team phase ini + PASTIKAN LENGKAP dulu sebelum proses target pet.
		-- Cek dari data equipped asli; kalau belum lengkap, equip lalu RETURN (recheck).
		local teamComplete = true
		for uuid in pairs(team) do
			if not localEq[uuid] then
				teamComplete = false
				local pos = getPos(uuid)
				if pos then
					pcall(function() PetsService:FireServer("EquipPet", uuid, CFrame.new(pos)) end)
					task.wait(0.25)
				end
			end
		end
		if not teamComplete then
			ctx.state.levelingV2Status = ("Phase %d: nunggu team lengkap..."):format(phase)
			return -- tunggu team komplit dulu, baru proses target pet
		end

		-- D. Target pet yang lulus phase (level >= phaseTarget) -> lepas
		local active = {}
		for uuid in pairs(localEq) do
			if not team[uuid] and not otherTeam[uuid] then
				local v = inv[uuid]
				if v and targetTypes[v.PetType] then
					local pd  = v.PetData or {}
					local lvl = pd.Level or 0
					if lvl >= phaseTarget then
						-- Webhook HANYA pas phase 2 (pet mencapai target final). Phase 1 = intermediate, skip.
						if phase == 2 then
							local petType  = v.PetType or "Unknown"
							local mutation = pd.MutationType or "Normal"
							local finalAge = pd.Level or phaseTarget
							local duration = 0
							ctx.state.levelingV2StartTime = ctx.state.levelingV2StartTime or {}
							if ctx.state.levelingV2StartTime[uuid] then
								duration = os.time() - ctx.state.levelingV2StartTime[uuid]
								ctx.state.levelingV2StartTime[uuid] = nil
							end
							-- Sisa antrean phase 2 (target type, level dalam [p1Target, p2Target), belum equipped, bukan favorite)
							local remainsQueue = 0
							for ou, ov in pairs(inv) do
								if ou ~= uuid and not localEq[ou] and targetTypes[ov.PetType] then
									local ol = (ov.PetData or {}).Level or 0
									if ol >= p1Target and ol < p2Target and not (ov.PetData or {}).IsFavorite then
										remainsQueue = remainsQueue + 1
									end
								end
							end
							task.spawn(function()
								local W = ctx.webhookLeveling
								if W and W.sendFinished then
									pcall(function() W.sendFinished(ctx, petType, mutation, finalAge, duration, remainsQueue) end)
								end
							end)
						end
						pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
						localEq[uuid] = nil
						task.wait(0.2)
					else
						table.insert(active, uuid)
						-- Catat waktu mulai leveling phase 2 (buat Duration di webhook)
						if phase == 2 then
							ctx.state.levelingV2StartTime = ctx.state.levelingV2StartTime or {}
							if not ctx.state.levelingV2StartTime[uuid] then
								ctx.state.levelingV2StartTime[uuid] = os.time()
							end
						end
					end
				end
			end
		end

		-- E. Tambah target pet baru buat phase ini (level dalam [phaseMin, phaseTarget))
		local needed = maxPets - #active
		if needed > 0 then
			local pool = {}
			for uuid, v in pairs(inv) do
				local lvl = (v.PetData or {}).Level or 0
				if not localEq[uuid] and targetTypes[v.PetType] and lvl >= phaseMin and lvl < phaseTarget and not (v.PetData or {}).IsFavorite then
					table.insert(pool, { uuid = uuid, level = lvl })
				end
			end
			table.sort(pool, function(a, b) return a.level < b.level end) -- level terendah dulu
			for i = 1, math.min(needed, #pool) do
				local pos = getPos(pool[i].uuid)
				if pos then
					pcall(function() PetsService:FireServer("EquipPet", pool[i].uuid, CFrame.new(pos)) end)
					localEq[pool[i].uuid] = true
					table.insert(active, pool[i].uuid)
					-- Catat waktu mulai leveling phase 2 (buat Duration di webhook)
					if phase == 2 then
						ctx.state.levelingV2StartTime = ctx.state.levelingV2StartTime or {}
						ctx.state.levelingV2StartTime[pool[i].uuid] = os.time()
					end
					task.wait(0.25)
				end
			end
		end

		ctx.state.levelingV2Status = ("Phase %d: %d/%d aktif"):format(phase, #active, maxPets)
	end

	----------------------------------------------------------------- loop
	local function loopV2()
		ctx.state.levelingV2Id = (ctx.state.levelingV2Id or 0) + 1
		local myId = ctx.state.levelingV2Id
		ctx.elevate()
		ctx.state.levelingV2FirstRun = true
		ctx.state.levelingV2LastPhase = nil -- reset biar ga false-trigger transisi di cycle pertama
		while CFG.levelingV2Enabled and ctx.alive() and ctx.state.levelingV2Id == myId do
			pcall(checkV2)
			task.wait(3)
		end
		ctx.state.levelingV2Status = "Idle"
	end

	function ctx.startLevelingV2()
		if ctx.cancelClearGarden then ctx.cancelClearGarden() end -- batalkan clear tertunda
		task.spawn(loopV2)
	end
	function ctx.stopLevelingV2()
		ctx.state.levelingV2Id = (ctx.state.levelingV2Id or 0) + 1 -- matikan loop
		if ctx.clearGarden then ctx.clearGarden("Leveling V2") end
	end
end
