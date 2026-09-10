--[[ growth.lua — Growth pipeline (BATCH per-step): jalankan target pet lewat urutan
     step (default Elephant -> Mutation -> Leveling), semua pet kelar 1 step baru lanjut.
     Config TERPISAH dari fitur standalone (growth*).
     Step & kriteria "complete":
       elephant : BaseWeight >= growthElephantWeight
       mutation : dapat salah satu growthMutationTargets (aura team; mutasi salah -> shard)
       leveling : Level >= growthLevP2Target (2 phase: P1 team -> P2 team)
     Saat ganti step/phase: bersihin garden TOTAL dulu -> pasang team baru (lengkap) -> proses. ]]
return function(ctx)
	local DataService = ctx.deps.DataService
	local PetsService = ctx.deps.PetsService
	local CFG = ctx.CFG
	local LP  = ctx.LP
	local RS  = game:GetService("ReplicatedStorage")
	local PetShardService = RS:WaitForChild("GameEvents"):WaitForChild("PetShardService_RE")
	local mutDisplay = (ctx.reg and ctx.reg.mutDisplay) or function(c) return c end

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
	local function getPos(uuid)
		if not slotOf[uuid] then slotOf[uuid] = nextSlot; nextSlot = nextSlot + 1 end
		local center = farmCenter(); if not center then return nil end
		local i = slotOf[uuid]
		return center + Vector3.new((i % 6 - 2.5) * 3, 0, (math.floor(i / 6) - 1) * 3)
	end

	----------------------------------------------------------------- helper mutasi/shard
	-- pet yang di-favorite JANGAN diproses & JANGAN dihitung di step manapun
	-- (elephant/mutation/leveling). Kalau ikut dihitung, pet fav yg ga pernah beres
	-- bikin step "belum semua selesai" selamanya -> growth mandek.
	local function isFav(pd) return (pd or {}).IsFavorite == true end
	-- Flow efektif: buang step kosong/"none" (mis. cuma mau Mutation+Leveling, Step 3 dikosongin).
	local function effFlow()
    	local out = {}
    	local validSteps = {
        	elephant = true,
        	mutation = true,
        	leveling = true,
        	leveling_p1 = true,
        	leveling_p2 = true,
    	}
    	for _, s in ipairs(CFG.growthFlow or {}) do
        	if validSteps[s] then
            	out[#out + 1] = s
        	end
    	end
    	return out
	end
	-- Target pet PER-METHOD: tiap step bisa punya target beda (mis. leveling: Dilo/
	-- Lion/Mimic, mutation: Hotdog/Griffin/Mimic). Kalau set per-step kosong ->
	-- fallback ke growthPetTypes (global). Backward-compatible.
	local function typesFor(step)
    	local per
    	if step == "elephant" then
        	per = CFG.growthPetTypesElephant
    	elseif step == "mutation" then
        	per = CFG.growthPetTypesMutation
    	elseif step == "leveling_p1" then
        	per = CFG.growthPetTypesLeveling
        	if not (per and next(per)) and CFG.growthPetTypesElephant and next(CFG.growthPetTypesElephant) then
            	per = CFG.growthPetTypesElephant
        	end
    	elseif step == "leveling" or step == "leveling_p2" then
        	per = CFG.growthPetTypesLeveling
    	end
    	if per and next(per) then return per end
    	return CFG.growthPetTypes or {}
	end
	-- ada target ke-set di mana pun (global / salah satu per-step)?
	local function anyTypesSet()
		if next(CFG.growthPetTypes or {}) then return true end
		return next(CFG.growthPetTypesElephant or {}) or next(CFG.growthPetTypesMutation or {})
			or next(CFG.growthPetTypesLeveling or {}) or false
	end
	local function mutOf(pd) return mutDisplay((pd or {}).MutationType) end
	local function hasMut(pd)
		local m = (pd or {}).MutationType
		return m ~= nil and m ~= "" and m ~= "None" and m ~= "Normal"
	end
	local function findShard()
		for _, where in ipairs({ LP.Character, LP:FindFirstChildOfClass("Backpack") }) do
			if where then
				for _, t in ipairs(where:GetChildren()) do
					if t:IsA("Tool") and (t:HasTag("PetShardTool") or tostring(t.Name):find("Cleansing Pet Shard")) then return t end
				end
			end
		end
	end
	local function findPetModel(uuid)
		local pm = workspace:FindFirstChild("PetsPhysical")
		if not pm then return nil end
		for _, mover in ipairs(pm:GetChildren()) do
			local m = mover:FindFirstChild(uuid); if m then return m end
		end
	end
	local function cleansePet(uuid)
		local model = findPetModel(uuid); if not model then return end
		local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
		local shard = findShard()
		if hum and shard then pcall(function() hum:EquipTool(shard) end); task.wait(0.3) end
		local held = LP.Character and LP.Character:FindFirstChildWhichIsA("Tool")
		if held and (held:HasTag("PetShardTool") or tostring(held.Name):find("Cleansing Pet Shard")) then
			pcall(function() PetShardService:FireServer("ApplyShard", model) end)
			task.wait(0.3)
		end
	end

	----------------------------------------------------------------- kriteria complete per step
	local function stepDone(step, pd)
    	pd = pd or {}
    	if step == "elephant" then
        	return (pd.BaseWeight or 0) >= (CFG.growthElephantWeight or 3.845)
    	elseif step == "mutation" then
        	local tg = CFG.growthMutationTargets or {}
        	if not next(tg) then return true end
        	return tg[mutOf(pd)] == true
    	elseif step == "leveling" then
        	return (pd.Level or 0) >= (CFG.growthLevP2Target or 500)
    	elseif step == "leveling_p1" then
        	return (pd.Level or 0) >= (CFG.growthLevP1Target or 50)
    	elseif step == "leveling_p2" then
        	return (pd.Level or 0) >= (CFG.growthLevP2Target or 500)
    	end
    	return true
	end

	ctx.state.growthStatus = "Idle"

	----------------------------------------------------------------- ringkasan status
	function ctx.getGrowthSummary()
		local ok, d = pcall(function() return DataService:GetData() end)
		local inv = ok and d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}
		local flow = effFlow()
		local perStep = {}
		for _, s in ipairs(flow) do perStep[s] = { done = 0, total = 0 } end
		for _, v in pairs(inv) do
			if not isFav(v.PetData) and v.PetData then   -- skip pet tanpa PetData
				for _, s in ipairs(flow) do
					if typesFor(s)[v.PetType] then
						perStep[s].total = perStep[s].total + 1
						if stepDone(s, v.PetData) then perStep[s].done = perStep[s].done + 1 end
					end
				end
			end
		end
		local function nm(t) local o = {}; for k in pairs(t or {}) do o[#o + 1] = k end; return #o > 0 and table.concat(o, ", ") or "-" end
		-- label target: kalau ada per-method di-set -> "E:.. | M:.. | L:..", else global.
		local function typesLabel()
			local e, m, l = CFG.growthPetTypesElephant or {}, CFG.growthPetTypesMutation or {}, CFG.growthPetTypesLeveling or {}
			if not (next(e) or next(m) or next(l)) then return nm(CFG.growthPetTypes) end
			return ("E:%s | M:%s | L:%s"):format(nm(typesFor("elephant")), nm(typesFor("mutation")), nm(typesFor("leveling")))
		end
		-- ringkas team: hitung per tipe pet -> "Peacock x3, Dog x2" (biar ga kepanjangan)
		local function teamNm(teamSet)
			local count, order, total = {}, {}, 0
			for uuid in pairs(teamSet or {}) do
				local v = inv[uuid]
				local pt = (v and v.PetType) or "?"
				if not count[pt] then order[#order + 1] = pt end
				count[pt] = (count[pt] or 0) + 1
				total = total + 1
			end
			if total == 0 then return "-" end
			local parts = {}
			for _, pt in ipairs(order) do
				parts[#parts + 1] = count[pt] > 1 and (pt .. " x" .. count[pt]) or pt
			end
			return ("(%d) %s"):format(total, table.concat(parts, ", "))
		end
		return {
			status = CFG.growthEnabled and "ACTIVE" or "STOPPED",
			step = ctx.state.growthStep or "-",
			flow = (#flow > 0) and table.concat(flow, " -> ") or "-",
			types = typesLabel(),
			perStep = perStep,
			teamElephant = teamNm(CFG.growthElephantTeam),
			teamMutation = teamNm(CFG.growthMutationTeam),
			teamLevP1 = teamNm(CFG.growthLevP1Team),
			teamLevP2 = teamNm(CFG.growthLevP2Team),
		}
	end

	----------------------------------------------------------------- core check
	local function checkGrowth()
		local ok, d = pcall(function() return DataService:GetData() end)
		if not ok or not d or not d.PetsData then return end
		local eq  = d.PetsData.EquippedPets or {}
		local inv = d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}
		local flow = effFlow()
		if not anyTypesSet() or #flow == 0 then
			ctx.state.growthStatus = "Growth: set target pet & flow dulu"
			return
		end

		-- STEP AKTIF = step pertama di flow yg belum selesai.
		-- Flow yang umum: leveling_p1 -> elephant -> leveling / mutation
		-- Di tahap elephant, pet levelnya ter-reset (level turun). Setelah semua pet level 50
		-- di-boost elephant dan levelnya reset, elephant tidak ada lagi target siap (level 50).
		-- Jika masih ada target pet yang belum capai target weight, sistem otomatis balik ke leveling_p1.
		local step, stepIdx
		local p1Target = CFG.growthLevP1Target or 50
		local hasElephantInFlow = false
		local hasLevP1InFlow = false
		for _, s in ipairs(flow) do
			if s == "elephant" then hasElephantInFlow = true end
			if s == "leveling_p1" then hasLevP1InFlow = true end
		end

		-- Jika flow mengandung siklus leveling_p1 + elephant:
		if hasElephantInFlow and hasLevP1InFlow then
			local tyEle = typesFor("elephant")
			local tyP1 = typesFor("leveling_p1")

			local anyNeedWeight = false
			local anyReadyLevel50 = false
			local anyNeedLevel50 = false

			for _, v in pairs(inv) do
				if v.PetData and not isFav(v.PetData) then
					local pd = v.PetData
					local lvl = pd.Level or 0
					-- Cek apakah pet target elephant butuh up weight
					if (tyEle[v.PetType] or tyP1[v.PetType]) and not stepDone("elephant", pd) then
						anyNeedWeight = true
						if lvl >= p1Target then
							anyReadyLevel50 = true
						else
							anyNeedLevel50 = true
						end
					end
				end
			end

			-- Tentukan step untuk fase siklus elephant / leveling_p1:
			local cycleStep = nil
			if anyNeedWeight then
				local cyclePhase = ctx.state.growthCyclePhase
				if not cyclePhase then
					-- Initial phase: kalau semua pet target sudah level 50 -> langsung elephant, kalau ada yg belum -> leveling_p1
					if anyReadyLevel50 and not anyNeedLevel50 then
						cyclePhase = "elephant"
					else
						cyclePhase = "leveling_p1"
					end
				end

				if cyclePhase == "leveling_p1" then
					-- Tetap di leveling_p1 sampai SEMUA pet target (yg butuh weight) sudah level >= 50
					if not anyNeedLevel50 then
						-- Selesai semua leveling_p1! Switch ke elephant
						cyclePhase = "elephant"
					end
				elseif cyclePhase == "elephant" then
					-- Tetap di elephant sampai TIDAK ADA LAGI pet level >= 50 (semua sudah ter-reset)
					if not anyReadyLevel50 then
						-- Semua pet level 50 sudah di-boost & ter-reset! Switch balik ke leveling_p1
						cyclePhase = "leveling_p1"
					end
				end
				ctx.state.growthCyclePhase = cyclePhase
				cycleStep = cyclePhase
			else
				ctx.state.growthCyclePhase = nil
			end

			for i, s in ipairs(flow) do
				if s == "leveling_p1" or s == "elephant" then
					if anyNeedWeight then
						-- Masih dalam proses weight: pilih step sesuai status kesiapan
						if s == cycleStep then
							step, stepIdx = s, i
							break
						end
						-- Jika bukan cycleStep, lewati
					else
						-- Weight sudah beres semua! leveling_p1 & elephant dianggap done, lanjut ke step berikutnya (mutation/leveling)
					end
				else
					-- Step lain (mutation, leveling, leveling_p2, dll)
					local ty = typesFor(s)
					local allDone = true
					for _, v in pairs(inv) do
						if ty[v.PetType] and v.PetData and not isFav(v.PetData) and not stepDone(s, v.PetData) then
							allDone = false
							break
						end
					end
					if not allDone then
						step, stepIdx = s, i
						break
					end
				end
			end
		else
			-- Flow standar tanpa kombinasi leveling_p1 + elephant
			for i, s in ipairs(flow) do
				local ty = typesFor(s)
				local allDone = true
				for _, v in pairs(inv) do
					if ty[v.PetType] and v.PetData and not isFav(v.PetData) and not stepDone(s, v.PetData) then
						allDone = false; break
					end
				end
				if not allDone then step, stepIdx = s, i; break end
			end
		end

		if not step then
			ctx.state.growthStep = "SELESAI"
			ctx.state.growthStatus = "Growth: semua step selesai ✓"
			if ctx.state.growthClearKey ~= "__done" then ctx.state.growthClearKey = "__done"; if ctx.clearGarden then ctx.clearGarden("Growth") end end
			return
		end

		-- target pet buat step aktif ini (per-method / fallback global)
		local types = typesFor(step)

		-- team / max / kriteria "masih perlu diproses" untuk step ini (leveling: sub-phase)
		local team, maxPets, needsWork
		local levPhase2 = false  -- true kalau step leveling lagi di Phase 2 (buat catat duration)
		local stepLabel = ("Step %d: %s"):format(stepIdx, step)
		if step == "elephant" then
			local p1Target = CFG.growthLevP1Target or 50
			team, maxPets = CFG.growthElephantTeam or {}, CFG.growthElephantMax or 2
			-- Elephant HANYA boleh ambil pet yang belum target weight DAN level >= p1Target (level 50)
			needsWork = function(pd)
				return not stepDone("elephant", pd) and (pd.Level or 0) >= p1Target
			end
		elseif step == "mutation" then
			team, maxPets = CFG.growthMutationTeam or {}, CFG.growthMutationMax or 2
			needsWork = function(pd) return not stepDone("mutation", pd) end
		elseif step == "leveling_p1" then
			local p1Target = CFG.growthLevP1Target or 50
			team, maxPets = CFG.growthLevP1Team or {}, CFG.growthLevP1Max or 3
			stepLabel = stepLabel .. " (Phase 1 - forced)"
			needsWork = function(pd)
				return (pd.Level or 0) < p1Target and not stepDone("elephant", pd)
			end
		elseif step == "leveling_p2" then
			team, maxPets = CFG.growthLevP2Team or {}, CFG.growthLevP2Max or 1
			stepLabel = stepLabel .. " (Phase 2 - forced)"
			needsWork = function(pd) return (pd.Level or 0) < (CFG.growthLevP2Target or 500) end
			levPhase2 = true
		else -- step == "leveling" (auto phase)
			local p1t = CFG.growthLevP1Target or 50
			local phase1 = false
			for _, v in pairs(inv) do
				if types[v.PetType] and not isFav(v.PetData) and not stepDone("leveling", v.PetData) and ((v.PetData or {}).Level or 0) < p1t then
					phase1 = true
					break
				end
			end
			if phase1 then
				team, maxPets = CFG.growthLevP1Team or {}, CFG.growthLevP1Max or 3
				stepLabel = stepLabel .. " (Phase 1 - auto)"
				needsWork = function(pd) return (pd.Level or 0) < p1t end
			else
				team, maxPets = CFG.growthLevP2Team or {}, CFG.growthLevP2Max or 1
				stepLabel = stepLabel .. " (Phase 2 - auto)"
				needsWork = function(pd) return not stepDone("leveling", pd) end
				levPhase2 = true
			end
		end
		ctx.state.growthStep = stepLabel

		-- Kirim webhook "enabled" SEKALI pas MASUK step baru (mis. enable -> elephant duluan).
		if ctx.state.growthLastStepName ~= step then
			ctx.state.growthLastStepName = step
			if step == "elephant" and ctx.webhookElephant and ctx.webhookElephant.sendEnabled then
				pcall(function() ctx.webhookElephant.sendEnabled(ctx) end)
			end
			-- leveling: TIDAK kirim webhook "enabled" pas masuk step; cuma pas pet beres (sendFinished).
			-- mutation (aura/cleanse) ga punya sendEnabled -> notif cuma per pet dapat mutasi
		end

		local localEq = {}
		for _, uuid in ipairs(eq) do localEq[uuid] = true end

		-- Transisi step/phase -> bersihin garden TOTAL dulu (verified kosong).
		if ctx.state.growthClearKey ~= nil and ctx.state.growthClearKey ~= stepLabel then
			ctx.state.growthClearing = true
		end
		ctx.state.growthClearKey = stepLabel
		if ctx.state.growthFirstRun or ctx.state.growthClearing then
			if #eq > 0 then
				ctx.state.growthStatus = ("%s: bersihin garden (%d pet)..."):format(stepLabel, #eq)
				for _, uuid in ipairs(eq) do
					pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
					task.wait(0.1)
				end
				return
			end
			ctx.state.growthFirstRun = false
			ctx.state.growthClearing = false
		end

		-- Pasang team step ini + PASTIKAN LENGKAP dulu.
		local teamComplete = true
		for uuid in pairs(team) do
			if not localEq[uuid] then
				teamComplete = false
				local pos = getPos(uuid)
				if pos then pcall(function() PetsService:FireServer("EquipPet", uuid, CFrame.new(pos)) end); task.wait(0.15) end
			end
		end
		if not teamComplete then
			ctx.state.growthStatus = stepLabel .. ": nunggu team lengkap..."
			return
		end

		-- Klasifikasi target pet equipped: kalau ga perlu kerja lagi -> lepas.
		-- Khusus mutation: mutasi SALAH (bukan target) -> cleanse (shard) biar coba lagi.
		local active = {}
		for uuid in pairs(localEq) do
			if not team[uuid] then
				local v = inv[uuid]
				if v and types[v.PetType] then
					local pd = v.PetData or {}
					if pd.IsFavorite then
						-- Favorite -> JANGAN cleanse, JANGAN biarin di garden. Keluarkan.
						pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
						localEq[uuid] = nil
						task.wait(0.1)
					elseif needsWork(pd) then
						if step == "mutation" and hasMut(pd) and not (CFG.growthMutationTargets or {})[mutOf(pd)] then
							cleansePet(uuid) -- mutasi salah -> cleanse
						end
						table.insert(active, uuid)
						if step == "elephant" then
							ctx.state.growthElephantStart = ctx.state.growthElephantStart or {}
							if not ctx.state.growthElephantStart[uuid] then
								ctx.state.growthElephantStart[uuid] = os.time()
							end
						elseif step == "leveling" and levPhase2 then
							-- catat mulai leveling Phase 2 (buat Duration di webhook, samain v2)
							ctx.state.growthLevStart = ctx.state.growthLevStart or {}
							if not ctx.state.growthLevStart[uuid] then
								ctx.state.growthLevStart[uuid] = os.time()
							end
						end
					else
						-- pet SELESAI step ini -> kirim webhook (template per-step)
						local pt = v.PetType
						if step == "elephant" and stepDone("elephant", pd) and ctx.webhookElephant and ctx.webhookElephant.onFinished then
							-- Durasi: dari pet masuk garden (equip) sampai lepas; nil kalau ga kecatat
							local dur
							if ctx.state.growthElephantStart and ctx.state.growthElephantStart[uuid] then
								dur = os.time() - ctx.state.growthElephantStart[uuid]
								ctx.state.growthElephantStart[uuid] = nil
							end
							pcall(function() ctx.webhookElephant.onFinished(ctx, pt, pd.BaseWeight or 0) end)
							if ctx.webhookElephant.sendFinished then
								pcall(function() ctx.webhookElephant.sendFinished(ctx, pt, pd.BaseWeight or 0, pd.MutationType, pd.Level or 0, dur) end)
							end
						elseif step == "mutation" and ctx.webhookCleanse and ctx.webhookCleanse.sendObtained then
							-- aura/cleanse webhook (bukan mutasi mesin)
							local remainsM = 0
							for _, iv in pairs(inv) do
								if types[iv.PetType] and not isFav(iv.PetData) and not stepDone("mutation", iv.PetData) then remainsM = remainsM + 1 end
							end
							pcall(function() ctx.webhookCleanse.sendObtained(ctx, pt, mutOf(pd), pd.Level or 0, remainsM) end)
						elseif step == "leveling" and stepDone("leveling", pd)
							and ctx.webhookLeveling and ctx.webhookLeveling.sendFinished then
							-- CUMA Phase 2 (reached final). Phase 1 (P1Target) ga kirim.
							local remains = 0
							for _, iv in pairs(inv) do
								if types[iv.PetType] and not isFav(iv.PetData) and not stepDone("leveling", iv.PetData) then remains = remains + 1 end
							end
							-- Duration: dari pet masuk Phase 2 sampai capai target final (nil = Unknown)
							local dur
							if ctx.state.growthLevStart and ctx.state.growthLevStart[uuid] then
								dur = os.time() - ctx.state.growthLevStart[uuid]
								ctx.state.growthLevStart[uuid] = nil
							end
							pcall(function() ctx.webhookLeveling.sendFinished(ctx, pt, mutOf(pd), pd.Level or 0, dur, remains) end)
						end
						pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
						localEq[uuid] = nil
						task.wait(0.1)
					end
				else
            -- ⭐ INI PERUBAHAN PENTING: Pet bukan team dan bukan target → KELUARKAN!
            		pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
            		localEq[uuid] = nil
           			task.wait(0.1)
				end
			end
		end

		-- Tambah target pet baru yg butuh kerja di step/phase ini, sampai maxPets.
		local needed = maxPets - #active
		if needed > 0 then
			local pool = {}
			for uuid, v in pairs(inv) do
				-- skip pet tanpa PetData agar tidak masuk garden secara salah
				if not localEq[uuid] and types[v.PetType] and v.PetData
					and not v.PetData.IsFavorite and needsWork(v.PetData) then
					local sortKey = v.PetData.Level or 0
					if step == "elephant" then
						sortKey = v.PetData.BaseWeight or 0
					end
					table.insert(pool, { uuid = uuid, key = sortKey })
				end
			end
			table.sort(pool, function(a, b) return a.key < b.key end)
			for i = 1, math.min(needed, #pool) do
				local pos = getPos(pool[i].uuid)
				if pos then
					pcall(function() PetsService:FireServer("EquipPet", pool[i].uuid, CFrame.new(pos)) end)
					localEq[pool[i].uuid] = true
					table.insert(active, pool[i].uuid)
					if step == "elephant" then
						ctx.state.growthElephantStart = ctx.state.growthElephantStart or {}
						ctx.state.growthElephantStart[pool[i].uuid] = os.time()
					elseif step == "leveling" and levPhase2 then
						ctx.state.growthLevStart = ctx.state.growthLevStart or {}
						ctx.state.growthLevStart[pool[i].uuid] = os.time()
					end
					task.wait(0.15)
				end
			end
		end

		ctx.state.growthStatus = ("%s: %d/%d aktif"):format(stepLabel, #active, maxPets)
	end

	----------------------------------------------------------------- loop
	local function growthLoop()
		ctx.state.growthId = (ctx.state.growthId or 0) + 1
		local myId = ctx.state.growthId
		ctx.elevate()
		ctx.state.growthFirstRun = true
		ctx.state.growthClearKey = nil
		while CFG.growthEnabled and ctx.alive() and ctx.state.growthId == myId do
			pcall(checkGrowth)
			-- pas bersihin/transisi -> cek cepat (1s) biar garden cepat bersih & lanjut;
			-- steady (proses grow/level) -> 2s (hemat, toh pet numbuh di server).
			task.wait((ctx.state.growthClearing or ctx.state.growthFirstRun) and 0.5 or 2)
		end
		ctx.state.growthStatus = "Idle"
	end

	function ctx.startGrowth()
		if ctx.cancelClearGarden then ctx.cancelClearGarden() end
		-- override config webhook elephant -> baca config GROWTH (bukan standalone)
		ctx.state.elephantCfgOverride = { team = CFG.growthElephantTeam, types = CFG.growthPetTypes, weight = CFG.growthElephantWeight }
		ctx.state.elephantWebhookPost = true -- Growth: POST pesan baru tiap pet selesai (bukan edit)
		ctx.state.growthLastStepName = nil -- reset biar step pertama kirim webhook "enabled"
		ctx.state.growthCyclePhase = nil
		task.spawn(growthLoop)
	end
	function ctx.stopGrowth()
		ctx.state.growthId = (ctx.state.growthId or 0) + 1
		ctx.state.elephantCfgOverride = nil -- balikin webhook elephant ke config standalone
		ctx.state.elephantWebhookPost = nil -- balikin webhook elephant ke mode edit (standalone)
		ctx.state.growthCyclePhase = nil
		if ctx.clearGarden then ctx.clearGarden("Growth") end
	end
end