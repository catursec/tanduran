--[[ elephant_v2.lua — Automation Elephant V2.
     Sama seperti V1 (equip team + rotasi pet target by BaseWeight, lepas pas
     capai Target Weight, jaga Max Target Pets aktif), TAPI plus swap GAJAH:
     gajah normalnya di luar garden; begitu ada target >= Trigger Level (mis. 40)
     gajah di-swap MASUK nuker 1 pet Switch (tanpa delay), keluar lagi pas ga ada
     target di level itu. Leveling target dilakukan PNP (jalan barengan).

     2 loop terpisah:
       - rotationLoop: pelan (~1.5s) — jaga team + rotasi target (ala V1).
       - swapLoop: cepat (0.1s) — cuma swap gajah <-> switch. ]]
return function(ctx)
	local DataService = ctx.deps.DataService
	local PetsService = ctx.deps.PetsService
	local CFG = ctx.CFG
	local LP  = ctx.LP
	local RS  = game:GetService("ReplicatedStorage")

	local function farmCenter()
		local ok, GetFarm = pcall(function() return require(RS.Modules.GetFarm) end)
		local farm = ok and GetFarm and GetFarm(LP)
		local pa = farm and farm:FindFirstChild("PetArea")
		if pa then return pa.Position end
		local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
		return hrp and hrp.Position or nil
	end
	local slotOf, nextSlot = {}, 0
	local function getPos(uuid)
		if not slotOf[uuid] then slotOf[uuid] = nextSlot; nextSlot = nextSlot + 1 end
		local c = farmCenter(); if not c then return nil end
		local i = slotOf[uuid]
		return c + Vector3.new(((i % 6) - 2.5) * 3, 0, (math.floor(i / 6) - 1) * 3)
	end

	local function snapshot()
		local ok, d = pcall(function() return DataService:GetData() end)
		if not ok or not d or not d.PetsData then return nil, nil end
		return d.PetsData.EquippedPets or {}, (d.PetsData.PetInventory and d.PetsData.PetInventory.Data) or {}
	end
	local function isEquipped(eq, uuid)
		if not uuid or uuid == "" or not eq then return false end
		for _, u in ipairs(eq) do if u == uuid then return true end end
		return false
	end

	----------------------------------------------------- STATUS
	function ctx.getElephantV2Summary()
		local _, inv = snapshot()
		inv = inv or {}
		local teamCount = 0
		for _ in pairs(CFG.elephantV2Team or {}) do teamCount = teamCount + 1 end
		local typesList = {}
		for k in pairs(CFG.elephantV2Types or {}) do table.insert(typesList, k) end
		table.sort(typesList)
		local targetW = CFG.elephantV2Weight or 5.5
		local readyCount, maxKgCount = 0, 0
		for _, v in pairs(inv) do
			if CFG.elephantV2Types[v.PetType] then
				local pd = v.PetData or {}
				if not pd.IsFavorite then
					if (pd.BaseWeight or 0) < targetW then readyCount = readyCount + 1 else maxKgCount = maxKgCount + 1 end
				end
			end
		end
		return {
			status = CFG.elephantV2Enabled and "ACTIVE" or "STOPPED",
			info   = ctx.state.elephantV2Status or "Idle",
			team   = string.format("%d pets", teamCount),
			types  = #typesList > 0 and table.concat(typesList, ", ") or "None",
			ready  = string.format("%d pets", readyCount),
			maxKg  = string.format("%d pets", maxKgCount),
			maxTarget = string.format("%d pets", CFG.elephantV2MaxPets or 3),
			targetWeight = string.format("%.1f KG", targetW),
			gajah  = ctx.elephantV2Label(CFG.elephantV2Gajah),
			switch = ctx.elephantV2Label(CFG.elephantV2Switch),
			level  = tostring(CFG.elephantV2Level or 40),
		}
	end

	----------------------------------------------------- ROTASI (ala V1)
	-- absentSince[uuid] = os.clock() sejak pet TERAKHIR kali kebaca ga ke-equip. Dipakai di
	-- reserved mode: elephant cuma re-equip pet yg absent >= 5 detik (biar ga ngerebut PnP yg
	-- cuma unequip sebentar pas pickup). Reset ke nil begitu pet kebaca ke-equip lagi.
	local absentSince = {}
	local ABSENT_GRACE = 5 -- detik
	local function absentLongEnough(uuid)
		absentSince[uuid] = absentSince[uuid] or os.clock()
		return (os.clock() - absentSince[uuid]) >= ABSENT_GRACE
	end
	local function checkRotation()
		local eq, inv = snapshot()
		if not eq then return end
		local teamSet = CFG.elephantV2Team or {}
		local targetTypes = CFG.elephantV2Types or {}
		local targetW = CFG.elephantV2Weight or 5.5
		local maxPets = CFG.elephantV2MaxPets or 3
		local gajah, switch = CFG.elephantV2Gajah, CFG.elephantV2Switch
		local gajahIn = isEquipped(eq, gajah)

		-- A. FIRST RUN (pas enable): reset garden dulu — TAPI di mode reserved (switch kosong)
		--    reset-all DILEWATI biar pet PnP yg lagi jalan ga ke-wipe. Langsung lanjut naruh team.
		local reserved = (switch == nil or switch == "")
		if ctx.state.elephantV2FirstRun then
			ctx.state.elephantV2FirstRun = false
			if not reserved and #eq > 0 then
				ctx.state.elephantV2Status = "Reset garden (cabut semua pet)..."
				for _, uuid in ipairs(eq) do
					pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
					task.wait(0.2)
				end
				return
			end
			-- reserved: jangan reset, lanjut ke penempatan team di bawah
		end

		local localEq, localEqCount = {}, 0
		for _, uuid in ipairs(eq) do localEq[uuid] = true; localEqCount = localEqCount + 1 end
		-- pet yg lagi ke-equip -> reset timer absent-nya (dia lagi ada)
		for uuid in pairs(localEq) do absentSince[uuid] = nil end

		-- B. PERSISTENSI TEAM: pasang lagi team yg kecabut (skip gajah; skip switch pas gajah in).
		--    RESERVED mode: cuma re-equip kalau udah absent >= 5s -> ga ngerebut PnP yg unequip
		--    sebentar pas pickup (PnP bakal balikin sendiri jauh sebelum 5s).
		for uuid in pairs(teamSet) do
			if uuid ~= gajah and not (gajahIn and uuid == switch) then
				if not localEq[uuid] then
					if (not reserved) or absentLongEnough(uuid) then
						local pos = getPos(uuid)
						if pos then
							pcall(function() PetsService:FireServer("EquipPet", uuid, CFrame.new(pos)) end)
							localEq[uuid] = true; localEqCount = localEqCount + 1
							absentSince[uuid] = nil
							task.wait(0.25)
						end
					end
				end
			end
		end

		-- C. KLASIFIKASI target equipped by BaseWeight (jangan sentuh team & gajah)
		local currentGrowing, finishedMax = {}, {}
		for uuid in pairs(localEq) do
			if not teamSet[uuid] and uuid ~= gajah then
				local pInfo = inv[uuid]
				local pd = pInfo and pInfo.PetData or {}
				local pt = pInfo and pInfo.PetType
				if pt and targetTypes[pt] then
					if (pd.BaseWeight or 0) < targetW then table.insert(currentGrowing, uuid)
					else table.insert(finishedMax, uuid) end
				end
			end
		end

		-- D. LEPAS target yang sudah MAX KG
		for _, uuid in ipairs(finishedMax) do
			pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
			localEq[uuid] = nil; localEqCount = localEqCount - 1
			task.wait(0.2)
		end

		-- E. TAMBAH target baru (BaseWeight terendah dulu) sampai maxPets
		local needed = maxPets - #currentGrowing
		if needed > 0 then
			local pool = {}
			for uuid, v in pairs(inv) do
				local pd = v.PetData or {}
				if not localEq[uuid] and targetTypes[v.PetType] and (pd.BaseWeight or 0) < targetW and not pd.IsFavorite then
					table.insert(pool, { uuid = uuid, weight = pd.BaseWeight or 0 })
				end
			end
			table.sort(pool, function(a, b) return a.weight < b.weight end)
			for i = 1, math.min(needed, #pool) do
				local uuid = pool[i].uuid
				-- RESERVED: skip pet yg baru aja absent (<5s) -> kemungkinan cuma lagi di-PnP
				-- (unequip sebentar). Cuma tambahin yg beneran nganggur/absent lama.
				if (not reserved) or absentLongEnough(uuid) then
					local pos = getPos(uuid)
					if pos then
						pcall(function() PetsService:FireServer("EquipPet", uuid, CFrame.new(pos)) end)
						localEq[uuid] = true; localEqCount = localEqCount + 1
						absentSince[uuid] = nil
						table.insert(currentGrowing, uuid)
						task.wait(0.3)
					end
				end
			end
		end
	end

	----------------------------------------------------- SWAP GAJAH (cepat)
	-- Cuma trigger kalau ada target yang LAGI KE-EQUIP, masih growing (weight < target),
	-- dan level >= ambang. Pet maxed / yang cuma nganggur di inventory TIDAK dihitung.
	local function anyTargetReady(eq, inv)
		local types = CFG.elephantV2Types or {}
		local thr = CFG.elephantV2Level or 40
		local targetW = CFG.elephantV2Weight or 5.5
		for _, u in ipairs(eq) do
			local v = inv[u]
			if v and types[v.PetType] then
				local pd = v.PetData or {}
				if (pd.BaseWeight or 0) < targetW and (pd.Level or 0) >= thr then return true end
			end
		end
		return false
	end
	local function eqCount(eq) return eq and #eq or 0 end

	-- Masukin GAJAH dengan AMAN: gajah HANYA boleh nuker SWITCH, atau pakai slot yang
	-- beneran kosong. Kalau Switch lagi ga ke-equip DAN garden penuh -> SKIP (biar
	-- ga bump pet lain sembarangan). Ini kunci: slot bebas WAJIB dari switch dulu.
	local function swapInGajah(gajah, switch)
		local eq = snapshot()
		if isEquipped(eq, gajah) then return true end
		local pos = farmCenter()
		if isEquipped(eq, switch) then
			-- cabut switch, TUNGGU beneran kecabut (slot bebas), baru masukin gajah
			pcall(function() PetsService:FireServer("UnequipPet", switch) end)
			for _ = 1, 8 do
				task.wait(0.04)
				eq = snapshot()
				if not isEquipped(eq, switch) then break end
			end
			if isEquipped(eq, switch) then return false end -- gagal cabut switch, jangan equip
		elseif eqCount(eq) >= 8 then
			return false -- switch ga ada & garden penuh -> jangan bump pet lain
		end
		-- slot dijamin ada (dari switch / emang kosong)
		if pos then pcall(function() PetsService:FireServer("EquipPet", gajah, CFrame.new(pos)) end) end
		for _ = 1, 3 do task.wait(0.06); if isEquipped(snapshot(), gajah) then return true end end
		return false
	end

	-- Keluarin GAJAH: cabut gajah, balikin SWITCH ke slot yang bebas.
	local function swapOutGajah(gajah, switch)
		local eq = snapshot()
		if not isEquipped(eq, gajah) then return true end
		local pos = farmCenter()
		pcall(function() PetsService:FireServer("UnequipPet", gajah) end)
		for _ = 1, 8 do
			task.wait(0.04)
			eq = snapshot()
			if not isEquipped(eq, gajah) then break end
		end
		-- reserved mode (switch kosong): slot dibiarin kosong, JANGAN equip apa2 (biar PnP aman)
		if switch and switch ~= "" and pos then pcall(function() PetsService:FireServer("EquipPet", switch, CFrame.new(pos)) end) end
		return true
	end

	-- Cari 1 pet target yang lagi ke-equip, tipe cocok, weight < target, level >= ambang.
	-- Return uuid + BaseWeight-nya. Dipakai buat mode reserved (boost by 0.1kg).
	local function getReadyTarget(eq, inv)
		local types = CFG.elephantV2Types or {}
		local thr = CFG.elephantV2Level or 40
		local targetW = CFG.elephantV2Weight or 5.5
		for _, u in ipairs(eq) do
			local v = inv[u]
			if v and types[v.PetType] then
				local pd = v.PetData or {}
				if (pd.BaseWeight or 0) < targetW and (pd.Level or 0) >= thr then return u, (pd.BaseWeight or 0) end
			end
		end
		return nil
	end
	local function baseWOf(inv, uuid)
		local v = inv and inv[uuid]; local pd = v and v.PetData
		return pd and (pd.BaseWeight or 0) or nil
	end

	local function rotationLoop(myId)
		while CFG.elephantV2Enabled and ctx.alive() and ctx.state.elephantV2Id == myId do
			-- Rotasi TETAP jalan (naruh team + rotasi target). Yang dimatiin cuma reset-all pas
			-- reserved (di checkRotation) biar pet PnP ga ke-wipe.
			pcall(checkRotation)
			task.wait(1.5)
		end
	end

	local function swapLoop(myId)
		while CFG.elephantV2Enabled and ctx.alive() and ctx.state.elephantV2Id == myId do
			local gajah, switch = CFG.elephantV2Gajah, CFG.elephantV2Switch
			local reserved = (switch == nil or switch == "")
			if gajah == "" or gajah == nil then
				ctx.state.elephantV2Status = "Pilih Gajah dulu"
				task.wait(1)
			else
				local eq, inv = snapshot()
				if eq then
					local gajahIn = isEquipped(eq, gajah)
					if reserved then
						-- ===== MODE RESERVED: gajah masuk pas ada target lvl 40, keluar pas target +0.1kg =====
						local tUuid = getReadyTarget(eq, inv)
						if not tUuid then
							if gajahIn then
								swapOutGajah(gajah, switch)
								ctx.state.elephantV2TargetUuid = nil
								ctx.state.elephantV2Status = "Standby (ga ada target lvl " .. tostring(CFG.elephantV2Level or 40) .. ")"
							else
								ctx.state.elephantV2Status = "Standby (nunggu target lvl " .. tostring(CFG.elephantV2Level or 40) .. ")"
							end
						else
							if not gajahIn then
								-- masuk pakai slot kosong yang kamu reserve; catat berat target saat masuk
								if swapInGajah(gajah, switch) then
									ctx.state.elephantV2TargetUuid = tUuid
									ctx.state.elephantV2TargetW0 = baseWOf(inv, tUuid)
									ctx.state.elephantV2Status = "Gajah MASUK (boost target)"
								end
							else
								-- gajah in: cek target yg ditrack udah naik 0.1kg? kalau ya -> keluar
								local trackU = ctx.state.elephantV2TargetUuid
								local w0 = ctx.state.elephantV2TargetW0
								local wc = trackU and baseWOf(inv, trackU) or nil
								if (not trackU) or (not wc) or (w0 and wc >= w0 + 0.1) then
									swapOutGajah(gajah, switch)
									ctx.state.elephantV2TargetUuid = nil
									ctx.state.elephantV2Status = "Gajah keluar (target +0.1kg)"
								else
									ctx.state.elephantV2Status = ("Boost... (+%.2f/0.10 kg)"):format(math.max(0, wc - (w0 or wc)))
								end
							end
						end
					else
						-- ===== MODE NORMAL (pakai switch): perilaku lama =====
						local ready = anyTargetReady(eq, inv)
						if ready and not gajahIn then
							swapInGajah(gajah, switch)
							ctx.state.elephantV2Status = "Gajah MASUK (target lvl " .. tostring(CFG.elephantV2Level or 40) .. ")"
						elseif not ready and gajahIn then
							swapOutGajah(gajah, switch)
							ctx.state.elephantV2Status = "Standby (gajah keluar)"
						else
							ctx.state.elephantV2Status = gajahIn and "Gajah aktif" or "Standby"
						end
					end
				end
				task.wait(CFG.elephantV2Interval or 0.1)
			end
		end
	end

	function ctx.startElephantV2()
		ctx.state.elephantV2Id = (ctx.state.elephantV2Id or 0) + 1
		local myId = ctx.state.elephantV2Id
		ctx.state.elephantV2FirstRun = true -- pas enable: reset garden dulu (cabut semua)
		ctx.elevate()
		task.spawn(function() rotationLoop(myId) end)
		task.spawn(function() swapLoop(myId) end)
	end
	function ctx.stopElephantV2()
		ctx.state.elephantV2Id = (ctx.state.elephantV2Id or 0) + 1
		ctx.state.elephantV2FirstRun = false
		ctx.state.elephantV2TargetUuid = nil
		local switch = CFG.elephantV2Switch
		local reserved = (switch == nil or switch == "")
		if reserved then
			-- MODE RESERVED: CUMA cabut gajah, JANGAN sentuh pet lain (PnP tetep aman jalan)
			ctx.state.elephantV2Status = "Cabut gajah..."
			task.spawn(function()
				local gajah = CFG.elephantV2Gajah
				for _ = 1, 5 do
					local eq = snapshot()
					if not eq or not isEquipped(eq, gajah) then break end
					pcall(function() PetsService:FireServer("UnequipPet", gajah) end)
					task.wait(0.12)
				end
				ctx.state.elephantV2Status = "Idle (gajah keluar, PnP jalan terus)"
			end)
			return
		end
		ctx.state.elephantV2Status = "Cabut semua pet (bersihin garden)..."
		-- Cabut SEMUA pet aktif di garden sampai bener2 bersih (multi-pass, kebal delay replikasi)
		task.spawn(function()
			for _ = 1, 5 do
				local eq = snapshot()
				if not eq or #eq == 0 then break end
				for _, uuid in ipairs(eq) do
					pcall(function() PetsService:FireServer("UnequipPet", uuid) end)
					task.wait(0.12)
				end
				task.wait(0.2)
			end
			ctx.state.elephantV2Status = "Idle (garden bersih)"
		end)
	end

	----------------------------------------------------- UI helpers
	local function petLabel(uuid)
		if not uuid or uuid == "" then return "Select" end
		local _, inv = snapshot()
		local v = inv and inv[uuid]
		if not v then return "#" .. tostring(uuid):sub(2, 5) end
		local pd = v.PetData or {}
		local mut = pd.MutationType
		local mutName = (mut and ctx.reg and ctx.reg.mutDisplay) and ctx.reg.mutDisplay(mut) or mut
		local pre = (mut and mut ~= "" and mut ~= "Normal") and (tostring(mutName) .. " ") or ""
		return ("%s%s | Age %s | #%s"):format(pre, v.PetType or "?", tostring(pd.Level or 0), tostring(uuid):sub(2, 5))
	end
	ctx.elephantV2Label = petLabel

	function ctx.elephantV2GajahOptions()
		local out = { { name = "", display = "\u{274C} Kosongkan" } }
		for _, o in ipairs(ctx.inventoryPetOptions and ctx.inventoryPetOptions() or {}) do
			out[#out + 1] = { name = o.value, display = o.display }
		end
		return out
	end
	function ctx.elephantV2SwitchOptions()
		-- Opsi Kosongkan di paling atas (buat mode reserved: slot dibiarin kosong).
		-- Tampilin SEMUA pet inventory (bukan cuma team) biar pilihan selalu keliatan.
		local out = { { name = "", display = "\u{274C} Kosongkan (reserved slot)" } }
		for _, o in ipairs(ctx.inventoryPetOptions and ctx.inventoryPetOptions() or {}) do
			out[#out + 1] = { name = o.value, display = o.display }
		end
		return out
	end
end
