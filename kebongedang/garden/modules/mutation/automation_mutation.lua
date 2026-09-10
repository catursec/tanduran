--[[ cleanse.lua — Automation Cleanse Mutation (mutasi via aura + auto cleanse).
     - Pet Team for Mutation (aura pemberi mutasi) tetap di garden.
     - Pet target (Pet Types) dirotasi di garden (max = Max Pets in Garden) buat kena aura.
     - Target dapat mutasi di "Keep" -> disimpan (dikeluarkan dari garden).
     - Target dapat mutasi LAIN -> di-cleanse (Cleansing Pet Shard) biar coba lagi.
     Cleanse: pegang shard lalu PetShardService_RE:FireServer("ApplyShard", petModel). ]]
return function(ctx)
	local DataService = ctx.deps.DataService
	local PetsService = ctx.deps.PetsService
	local CFG = ctx.CFG
	local LP = ctx.LP
	local RS = game:GetService("ReplicatedStorage")
	local PetShardService = RS:WaitForChild("GameEvents"):WaitForChild("PetShardService_RE")
	local function setStatus(s) ctx.setStatus(s) end

	local function mutName(code)
		if ctx.reg and ctx.reg.mutDisplay then return ctx.reg.mutDisplay(code) end
		return tostring(code)
	end
	local function cleanUuid(u) return (tostring(u):gsub("[{}]", "")) end

	----------------------------------------------------------------- placement
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
		local center = farmCenter(); if not center then return nil end
		local i = slotOf[uuid]
		local col, row = i % GRID_COLS, math.floor(i / GRID_COLS)
		return center + Vector3.new((col - (GRID_COLS - 1) / 2) * GRID_SP, 0, (row - 1) * GRID_SP)
	end

	----------------------------------------------------------------- shard cleanse
	local function findShard()
		for _, src in ipairs({ LP.Character, LP:FindFirstChildOfClass("Backpack") }) do
			if src then for _, t in ipairs(src:GetChildren()) do
				if t:IsA("Tool") and (t:HasTag("PetShardTool") or tostring(t.Name):find("Cleansing Pet Shard")) then return t end
			end end
		end
		return nil
	end
	local function findPetModel(uuid)
		local pp = workspace:FindFirstChild("PetsPhysical")
		if not pp then return nil end
		for _, d in ipairs(pp:GetDescendants()) do
			if d.Name == uuid then return d end
		end
		return nil
	end
	-- Cleanse pet yang SUDAH equipped (model ada di garden).
	local function cleansePet(uuid)
		local model = findPetModel(uuid)
		if not model then return false, "model tidak ada" end
		local shard = findShard()
		if not shard then return false, "shard habis" end
		local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
		if not hum then return false, "no humanoid" end
		local held
		for _ = 1, 3 do
			pcall(function() hum:EquipTool(shard) end); task.wait(0.3)
			held = LP.Character and LP.Character:FindFirstChildWhichIsA("Tool")
			if held and (held:HasTag("PetShardTool") or tostring(held.Name):find("Cleansing Pet Shard")) then break end
			shard = findShard(); if not shard then break end
		end
		if held and (held:HasTag("PetShardTool") or tostring(held.Name):find("Cleansing Pet Shard")) then
			pcall(function() PetShardService:FireServer("ApplyShard", model) end)
			task.wait(0.4)
			return true
		end
		return false, "gagal pegang shard"
	end

	----------------------------------------------------------------- mutasi helpers
	local function hasMut(pd)
		local m = pd.MutationType
		if not m or m == "" or m == "Normal" or m == "m" then return false end
		return mutName(m) ~= "None"
	end
	local function isKept(pd)
		return hasMut(pd) and CFG.cleanseKeepMutations[mutName(pd.MutationType)] == true
	end

	ctx.state.cleansePhase = "Idle"

	-- Ringkasan status untuk UI
	function ctx.getCleanseSummary()
		local ok, d = pcall(function() return DataService:GetData() end)
		local inv = ok and d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}

		local teamCount = 0
		for _ in pairs(CFG.cleanseTeamUuids or {}) do teamCount = teamCount + 1 end
		local typesList = {}
		for k in pairs(CFG.cleansePetTypes or {}) do typesList[#typesList + 1] = k end
		table.sort(typesList)
		local keepOrder = {}
		for k in pairs(CFG.cleanseKeepMutations or {}) do keepOrder[#keepOrder + 1] = k end
		table.sort(keepOrder)

		local ready, already = 0, {}
		for _, k in ipairs(keepOrder) do already[k] = 0 end
		for _, v in pairs(inv) do
			local pt = v.PetType
			if pt and CFG.cleansePetTypes[pt] then
				local pd = v.PetData or {}
				local disp = hasMut(pd) and mutName(pd.MutationType) or "None"
				if CFG.cleanseKeepMutations[disp] then
					already[disp] = (already[disp] or 0) + 1
				elseif not pd.IsFavorite then
					ready = ready + 1
				end
			end
		end

		return {
			status = CFG.cleanseEnabled and "ACTIVE" or "STOPPED",
			team = teamCount,
			types = #typesList > 0 and table.concat(typesList, ", ") or "None",
			keep = #keepOrder > 0 and table.concat(keepOrder, ", ") or "None",
			ready = ready,
			already = already,
			keepOrder = keepOrder,
			maxPets = CFG.cleanseMaxPets or 2,
			phase = ctx.state.cleansePhase or "Idle",
		}
	end

	----------------------------------------------------------------- loop utama
	local function checkCleanse()
		local ok, d = pcall(function() return DataService:GetData() end)
		if not ok or not d or not d.PetsData then return end
		local eq = d.PetsData.EquippedPets or {}
		local inv = d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}

		local teamSet = CFG.cleanseTeamUuids or {}
		local targetTypes = CFG.cleansePetTypes or {}
		local maxPets = CFG.cleanseMaxPets or 2

		local localEq = {}
		for _, u in ipairs(eq) do localEq[cleanUuid(u)] = u end -- clean->original

		-- A. FIRST RUN: reset garden
		if ctx.state.cleanseFirstRun then
			ctx.state.cleanseFirstRun = false
			for _, uuid in ipairs(eq) do
				pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
				localEq[cleanUuid(uuid)] = nil
				task.wait(0.1)
			end
		end

		-- B. Pasang team aura (persisten)
		for uuid in pairs(teamSet) do
			if not localEq[cleanUuid(uuid)] then
				local pos = getPos(uuid)
				if pos then
					pcall(function() PetsService:FireServer("EquipPet", uuid, CFrame.new(pos)) end)
					localEq[cleanUuid(uuid)] = uuid
					task.wait(0.1)
				end
			end
		end

		-- C. Proses pet target yang equipped
		local activeTargets = 0
		for cu, origUuid in pairs(localEq) do
			if not teamSet[origUuid] and not teamSet["{" .. cu .. "}"] then
				local pInfo = inv[origUuid] or inv["{" .. cu .. "}"]
				local pt = pInfo and pInfo.PetType
				local pd = pInfo and pInfo.PetData or {}
				if pt and targetTypes[pt] then
					if pd.IsFavorite then
						-- Favorite -> JANGAN cleanse (lindungi mutasi). Keluarkan dari garden.
						ctx.state.cleansePhase = "Skip favorite (protected)"
						pcall(function() PetsService:FireServer("UnequipPet", origUuid) end)
						localEq[cu] = nil
						task.wait(0.1)
					elseif isKept(pd) then
						-- Harvest: mutasi bagus -> keluarkan dari garden (disimpan)
						ctx.state.cleansePhase = "Harvest " .. mutName(pd.MutationType)
						pcall(function() PetsService:FireServer("UnequipPet", origUuid) end)
						localEq[cu] = nil
						task.wait(0.15)

						-- Webhook: mutasi didapat
						if ctx.webhookCleanse then
							local gotType, gotMut, gotAge = pt, mutName(pd.MutationType), pd.Level or 0
							local remains = 0
							for _, iv in pairs(inv) do
								local ipt = iv.PetType
								if ipt and targetTypes[ipt] then
									local ipd = iv.PetData or {}
									if not ipd.IsFavorite and not isKept(ipd) then remains = remains + 1 end
								end
							end
							task.spawn(function()
								pcall(function() ctx.webhookCleanse.sendObtained(ctx, gotType, gotMut, gotAge, remains) end)
							end)
						end
					elseif hasMut(pd) then
						-- Mutasi salah -> cleanse (tetap di garden buat coba lagi)
						ctx.state.cleansePhase = "Cleanse " .. mutName(pd.MutationType)
						cleansePet(origUuid)
						activeTargets = activeTargets + 1
					else
						-- Normal -> lagi nunggu aura
						activeTargets = activeTargets + 1
					end
				elseif not (pt and targetTypes[pt]) then
					-- pet lain (bukan team, bukan target) -> keluarkan
					pcall(function() PetsService:FireServer("UnequipPet", origUuid) end)
					localEq[cu] = nil
					task.wait(0.1)
				end
			end
		end

		-- D. Isi garden dengan target baru sampai maxPets (belum punya mutasi keep)
		local needed = maxPets - activeTargets
		if needed > 0 then
			local pool = {}
			for uuid, v in pairs(inv) do
				local pt = v.PetType
				local pd = v.PetData or {}
				if not localEq[cleanUuid(uuid)] and pt and targetTypes[pt] and not pd.IsFavorite and not isKept(pd) then
					pool[#pool + 1] = uuid
				end
			end
			for i = 1, math.min(needed, #pool) do
				local pos = getPos(pool[i])
				if pos then
					pcall(function() PetsService:FireServer("EquipPet", pool[i], CFrame.new(pos)) end)
					localEq[cleanUuid(pool[i])] = pool[i]
					activeTargets = activeTargets + 1
					task.wait(0.15)
				end
			end
		end

		ctx.state.cleansePhase = string.format("Farming: %d/%d target", activeTargets, maxPets)
	end

	local function cleanseLoop()
		ctx.state.cleanseId = (ctx.state.cleanseId or 0) + 1
		local myId = ctx.state.cleanseId
		ctx.elevate()
		ctx.state.cleanseFirstRun = true

		while CFG.cleanseEnabled and ctx.alive() and ctx.state.cleanseId == myId do
			if not next(CFG.cleansePetTypes or {}) then
				setStatus("Cleanse: pilih Pet Types dulu")
				task.wait(3)
			else
				pcall(checkCleanse)
				setStatus("Cleanse " .. tostring(ctx.state.cleansePhase))
				task.wait(3)
			end
		end
		ctx.state.cleansePhase = "Idle"
	end

	function ctx.startCleanse()
		if ctx.cancelClearGarden then ctx.cancelClearGarden() end -- batalkan clear tertunda
		task.spawn(cleanseLoop) -- loop set firstRun=true -> reset garden + equip team aura
	end

	function ctx.stopCleanse()
		ctx.state.cleanseId = (ctx.state.cleanseId or 0) + 1 -- matikan loop
		if ctx.clearGarden then ctx.clearGarden("Auto Mutation") end
	end
end
