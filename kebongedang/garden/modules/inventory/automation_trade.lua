--[[ trade.lua — inti Automation Trade.
     Alur per-trade: SendRequest -> tunggu window kebuka -> AddItem pets -> Accept
                     -> tunggu lawan accept -> Confirm -> tunggu selesai.
     Mengisi: ctx.getPlayers, ctx.getData, ctx.matchingPetUuids,
              ctx.startTrade, ctx.stopTrade ]]
return function(ctx)
	local Players     = ctx.Services.Players
	local LP          = ctx.LP
	local CFG         = ctx.CFG
	local DataService = ctx.deps.DataService
	local TC          = ctx.deps.TradingController
	local SendRequest = ctx.deps.SendRequest
	local AddItem     = ctx.deps.AddItem
	local Accept      = ctx.deps.Accept
	local Confirm     = ctx.deps.Confirm
	local Decline     = ctx.deps.Decline
	local FavoriteItem = ctx.deps.FavoriteItem
	local function log(m) ctx.log(m) end
	local function setStatus(s) ctx.setStatus(s) end

	----------------------------------------------------------------- data helpers
	local function getData()
		local ok, d = pcall(function() return DataService:GetData() end)
		if ok then return d end
		return nil
	end
	ctx.getData = getData

	local function getPlayers()
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP then list[#list + 1] = p.Name end
		end
		table.sort(list)
		return list
	end
	ctx.getPlayers = getPlayers

	-- cek pet cocok dengan filter CFG
	local function petPasses(v)
		local pt = v.PetType
		local pd = v.PetData
		if not (pt and pd) then return false end
		-- filter type (kosong = semua)
		if next(CFG.petTypes) and not CFG.petTypes[pt] then return false end
		-- weight: berat TAMPIL di game = BaseWeight + 0.5 (pakai angka tampilan di filter)
		local w = (pd.BaseWeight or 0) + 0.5
		local wf = CFG.weightFilter or 0
		if wf > 0 and w < wf then return false end
		if wf < 0 and w > -wf then return false end
		-- age (Level)
		local age = pd.Level or 0
		local af = CFG.ageFilter or 0
		if af > 0 and age < af then return false end
		if af < 0 and age > -af then return false end
		return true
	end

	-- kumpulkan uuid pet yang cocok (maksimal `limit`)
	local function matchingPetUuids(limit)
		local out = {}
		local d = getData()
		local pinv = d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data
		if not pinv then return out end
		-- pet yang lagi di-equip jangan di-trade
		local equipped = {}
		if d.PetsData.EquippedPets then for _, u in ipairs(d.PetsData.EquippedPets) do equipped[u] = true end end
		for uuid, v in pairs(pinv) do
			if #out >= limit then break end
			if not equipped[uuid] and petPasses(v) then
				local fav = v.PetData.IsFavorite
				if (not fav) or CFG.autoUnfavorite then
					out[#out + 1] = { uuid = uuid, fav = fav, petType = v.PetType }
				end
			end
		end
		return out
	end
	ctx.matchingPetUuids = matchingPetUuids

	-- Hitung SEMUA pet yang cocok filter (tanpa limit) untuk status GUI.
	function ctx.countMatchingPets()
		local n = 0
		local d = getData()
		local pinv = d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data
		if not pinv then return 0 end
		local equipped = {}
		if d.PetsData.EquippedPets then for _, u in ipairs(d.PetsData.EquippedPets) do equipped[u] = true end end
		for uuid, v in pairs(pinv) do
			if not equipped[uuid] and petPasses(v) then
				local fav = v.PetData.IsFavorite
				if (not fav) or CFG.autoUnfavorite then n = n + 1 end
			end
		end
		return n
	end

	-- PRE-PASS: unfavorite SEMUA pet favorite yang lolos filter dulu (dipanggil di awal
	-- trade). Biar ga ke-race pas add item (unfav satu-satu tiap batch rawan gagal).
	local function unfavoriteAllMatching()
		if not (CFG.autoUnfavorite and FavoriteItem) then return end
		local d = getData()
		local pinv = d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data
		if not pinv then return end
		local equipped = {}
		if d.PetsData.EquippedPets then for _, u in ipairs(d.PetsData.EquippedPets) do equipped[u] = true end end
		local favSet, favCount = {}, 0
		for uuid, v in pairs(pinv) do
			if not equipped[uuid] and petPasses(v) and v.PetData.IsFavorite then
				favSet[uuid] = true; favCount = favCount + 1
			end
		end
		if favCount == 0 then return end
		setStatus(("Unfavorite %d pet target dulu..."):format(favCount))
		local Favorite_Item_BE = game:GetService("ReplicatedStorage").GameEvents:FindFirstChild("Favorite_Item_BE")
		local done = 0
		for _, src in ipairs({ LP:FindFirstChildOfClass("Backpack"), LP.Character }) do
			if src then for _, t in ipairs(src:GetChildren()) do
				local u = t:IsA("Tool") and t:GetAttribute("PET_UUID")
				if u and favSet[u] then
					pcall(function() FavoriteItem:FireServer(t) end)
					if Favorite_Item_BE then pcall(function() Favorite_Item_BE:Fire(t) end) end
					favSet[u] = nil; done = done + 1
					task.wait(0.1)
				end
			end end
		end
		if done > 0 then task.wait(0.5) end -- kasih waktu sync sebelum mulai trade
	end
	ctx.unfavoriteAllMatching = unfavoriteAllMatching

	----------------------------------------------------------------- trade-state read
	local function replicatorData()
		if not (TC and TC.CurrentTradeReplicator) then return nil end
		local rep = TC.CurrentTradeReplicator
		local ok, d = pcall(function() return rep:GetDataAsync() end)
		if ok and d then return d end
		ok, d = pcall(function() return rep:GetData() end)
		if ok then return d end
		return nil
	end

	ctx.replicatorData = replicatorData

	-- Skema (dari remote-spy): d.players = {p1,p2}, d.states = {[1]="None"/"Accepted", [2]=...}
	-- state index sejajar dengan players. Lawan dianggap accept kalau statenya "Accepted"/"Confirmed".
	local function stateOf(d, wantSelf)
		if type(d) ~= "table" then return nil end
		local players = d.players or d.Players
		local states  = d.states or d.States
		if type(players) ~= "table" or type(states) ~= "table" then return nil end
		local idx
		for i, p in ipairs(players) do
			if wantSelf then if p == LP then idx = i end
			else if p ~= LP then idx = i end end
		end
		if not idx then return nil end
		return states[idx]
	end
	local function otherState(d) return stateOf(d, false) end
	local function myState(d) return stateOf(d, true) end
	ctx.myState = myState
	local function otherAccepted(d)
		local s = otherState(d)
		return s == "Accepted" or s == "Confirmed"
	end
	ctx.otherAccepted = otherAccepted

	-- Trade cuma bisa dikirim kalau kita lagi MEGANG Trading Ticket.
	local function equipTradingTicket()
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return false end
		-- sudah megang tiket?
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and t.Name:find("Trading Ticket") then return true end
		end
		local bp = LP:FindFirstChild("Backpack")
		if not bp then return false end
		for _, t in ipairs(bp:GetChildren()) do
			if t:IsA("Tool") and t.Name:find("Trading Ticket") then
				pcall(function() hum:EquipTool(t) end)
				task.wait(0.3)
				return true
			end
		end
		return false
	end
	ctx.equipTradingTicket = equipTradingTicket

	----------------------------------------------------------------- one trade
	local function doOneTrade(target)
		-- pegang tiket dulu, wajib biar panel trade kebuka
		if not equipTradingTicket() then
			log("Trading Ticket tidak ada / gagal di-equip. Stop.")
			ctx.state.tradeRunning = false
			return false
		end
		setStatus("Kirim ajakan ke " .. target.Name)
		pcall(function() SendRequest:FireServer(target) end)

		-- tunggu window trade kebuka (lawan accept request)
		local t0 = os.clock()
		repeat task.wait(0.3) until (not ctx.state.tradeRunning) or (TC and TC.CurrentTradeReplicator) or (os.clock() - t0) > 20
		if not ctx.state.tradeRunning then return false end
		if not (TC and TC.CurrentTradeReplicator) then
			log("Timeout: " .. target.Name .. " tidak accept ajakan.")
			return false
		end

		-- kumpulkan pet
		local pets = matchingPetUuids(CFG.petsPerTrade)
		if #pets == 0 then
			log("Tidak ada pet cocok filter. Batalkan trade.")
			pcall(function() Decline:FireServer() end)
			return false
		end

		-- auto unfavorite dulu kalau perlu.
		-- PENTING: Favorite_Item butuh TOOL object (bukan uuid). Cari tool di Backpack/Character.
		if CFG.autoUnfavorite and FavoriteItem then
			local Favorite_Item_BE = game:GetService("ReplicatedStorage").GameEvents:FindFirstChild("Favorite_Item_BE")
			local function findToolByUuid(uuid)
				local bp = LP:FindFirstChildOfClass("Backpack")
				if bp then for _, t in ipairs(bp:GetChildren()) do
					if t:IsA("Tool") and t:GetAttribute("PET_UUID") == uuid then return t end
				end end
				if LP.Character then for _, t in ipairs(LP.Character:GetChildren()) do
					if t:IsA("Tool") and t:GetAttribute("PET_UUID") == uuid then return t end
				end end
				return nil
			end
			for _, p in ipairs(pets) do
				if p.fav then
					local tool = findToolByUuid(p.uuid)
					if tool then
						pcall(function() FavoriteItem:FireServer(tool) end)
						if Favorite_Item_BE then pcall(function() Favorite_Item_BE:Fire(tool) end) end
						task.wait(0.15)
					end
				end
			end
			task.wait(0.3)
		end

		-- add item
		log(("Cocok %d pet. Contoh uuid=%s"):format(#pets, tostring(pets[1] and pets[1].uuid)))
		setStatus(("Menambah %d pet..."):format(#pets))
		for _, p in ipairs(pets) do
			if not ctx.state.tradeRunning then break end
			pcall(function() AddItem:FireServer("Pet", p.uuid) end)
			task.wait(0.3)
		end

		-- verifikasi berapa pet yang benar-benar masuk ke offer kita
		task.wait(0.5)
		do
			local d = replicatorData()
			local myIdx
			if d and d.players then for i, pl in ipairs(d.players) do if pl == LP then myIdx = i end end end
			local n = 0
			if d and myIdx and d.offers and d.offers[myIdx] then
				for _ in pairs(d.offers[myIdx].items or {}) do n += 1 end
			end
			log(("Pet masuk ke offer: %d/%d"):format(n, #pets))
			if n == 0 then
				log("AddItem tidak masuk — cek: pet favorit? equipped? uuid?")
			end
		end

		-- Auto-accept: game punya cooldown anti-scam sebelum tombol Accept aktif.
		-- Daripada nebak durasinya, kita spam Accept pelan sampai status KITA jadi
		-- "Accepted" (artinya cooldown sudah habis & Accept kebaca). Otomatis nunggu pas.
		setStatus("Accept (nunggu cooldown game)...")
		local myOk = false
		local a0 = os.clock()
		repeat
			pcall(function() Accept:FireServer() end)
			task.wait(1)
			local s = myState(replicatorData())
			if s == "Accepted" or s == "Confirmed" then myOk = true; break end
		until (not ctx.state.tradeRunning) or (not (TC and TC.CurrentTradeReplicator)) or (os.clock() - a0) > 20
		if not ctx.state.tradeRunning or not (TC and TC.CurrentTradeReplicator) then return false end
		if not myOk then
			log("Accept kita belum kebaca setelah 20s. Batalkan.")
			pcall(function() Decline:FireServer() end)
			return false
		end
		log("Accept kita OK.")
		setStatus("Menunggu lawan accept...")

		-- tunggu lawan accept
		t0 = os.clock()
		local accepted = false
		repeat
			task.wait(0.5)
			if otherAccepted(replicatorData()) then accepted = true; break end
		until (not ctx.state.tradeRunning) or (not (TC and TC.CurrentTradeReplicator)) or (os.clock() - t0) > 30
		if not ctx.state.tradeRunning then return false end
		if not (TC and TC.CurrentTradeReplicator) then
			log("Trade ditutup sebelum selesai.")
			return false
		end
		if not accepted then
			log("Lawan tidak accept (timeout). Batalkan.")
			pcall(function() Decline:FireServer() end)
			return false
		end

		-- confirm (retry sampai trade tertutup)
		setStatus("Confirm... menunggu selesai")
		t0 = os.clock()
		repeat
			pcall(function() Confirm:FireServer() end)
			task.wait(1.5)
		until (not (TC and TC.CurrentTradeReplicator)) or (not ctx.state.tradeRunning) or (os.clock() - t0) > 15
		if TC and TC.CurrentTradeReplicator then
			log("Confirm terkirim tapi trade belum tertutup.")
			return false
		end
		return true
	end

	----------------------------------------------------------------- loop
	local function tradeLoop()
		ctx.elevate()
		unfavoriteAllMatching() -- unfav semua target favorite dulu, baru mulai trade
		while ctx.state.tradeRunning do
			if ctx.state.completed >= CFG.totalTrades then
				ctx.state.status = "DONE"
				setStatus(("Selesai %d/%d trade."):format(ctx.state.completed, CFG.totalTrades))
				ctx.state.tradeRunning = false
				if ctx.refreshTradeStatus then ctx.refreshTradeStatus() end
				break
			end
			-- Stop kalau pet cocok filter sudah habis -> jangan kirim trade lagi.
			if ctx.countMatchingPets() == 0 then
				ctx.state.status = "DONE"
				setStatus("Pet habis (sesuai filter). Trade dihentikan.")
				ctx.state.tradeRunning = false
				CFG.tradeEnabled = false
				if ctx.persistState then ctx.persistState() end
				if ctx.refreshTradeStatus then ctx.refreshTradeStatus() end
				break
			end

			local target = CFG.targetPlayer ~= "" and Players:FindFirstChild(CFG.targetPlayer) or nil
			if not target then
				setStatus("Target player tidak ada / belum dipilih.")
				task.wait(2)
			else
				ctx.state.status = "RUNNING"
				if ctx.refreshTradeStatus then ctx.refreshTradeStatus() end
				local ok = doOneTrade(target)
				if ok then
					ctx.state.completed += 1
					log(("Trade sukses (%d/%d)"):format(ctx.state.completed, CFG.totalTrades))
					if ctx.notifyTrade then ctx.notifyTrade(target, #matchingPetUuids(CFG.petsPerTrade)) end
				end
				if ctx.refreshTradeStatus then ctx.refreshTradeStatus() end
				task.wait(1.5)
			end
		end
	end

	function ctx.startTrade()
		if ctx.state.tradeRunning then return end
		ctx.state.tradeRunning = true
		ctx.state.status = "RUNNING"
		task.spawn(tradeLoop)
	end

	function ctx.stopTrade()
		ctx.state.tradeRunning = false
		ctx.state.status = "IDLE"
	end
end
