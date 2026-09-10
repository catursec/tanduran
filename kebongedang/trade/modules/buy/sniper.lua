--[[ sniper.lua — Auto Snipe / Auto Buy pet dari booth pemain lain (Trade World).
     5 profil (pet types + mutation + max price, urutan = prioritas). Scan listing
     booth, beli otomatis kalau cocok & seller hadir. Kalau ga ada target -> cari
     seller lintas server (FindSellers) lalu TeleportToListing (auto server-hop).
     Beli: TradeEvents.Booths.BuyListing:InvokeServer(ownerPlayer, listingUUID).
     Mengisi: ctx.startSnipe, ctx.stopSnipe, ctx.getSnipeStatus ]]
return function(ctx)
	local RS              = ctx.Services.RS
	local Players         = ctx.Services.Players
	local HttpService     = ctx.Services.HttpService
	local TeleportService = game:GetService("TeleportService")
	local LP  = ctx.LP
	local CFG = ctx.CFG
	local RR                = ctx.deps.RR
	local DataService       = ctx.deps.DataService
	local BuyListing        = ctx.deps.BuyListing
	local FindSellers       = ctx.deps.FindSellers
	local TeleportToListing = ctx.deps.TeleportToListing
	local TokenRAPUtil      = ctx.deps.TokenRAPUtil
	local comboKey   = ctx.reg.comboKey
	local mutDisplay = ctx.reg.mutDisplay
	local NUM = ctx.NUM_SNIPE or 5
	local function log(m) ctx.log(m) end
	local function setStatus(s) ctx.setStatus(s) end
	-- running = toggle ON DAN GUI instance ini masih hidup. Cek ctx.alive() penting:
	-- kalau hub ke-load 2x (auto-exec + queue_on_teleport), instance lama yang GUI-nya
	-- di-destroy langsung berhenti -> ga ada dobel sniper.
	local function running() return ctx.state.snipeRunning == true and ctx.alive() end

	local ROUTER = "loadstring(game:HttpGet('https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/init.lua'))()"

	------------------------------------------------------------------ helpers
	local function buildItemData(petType)
		if TokenRAPUtil and TokenRAPUtil.GetDefaultItemData then
			local ok, d = pcall(function() return TokenRAPUtil.GetDefaultItemData("Pet", petType) end)
			if ok and d then return d end
		end
		return { PetType = petType, PetData = { MutationType = "Normal", Level = 0, LevelProgress = 0, Hunger = 0, BaseWeight = 1, Boosts = {} }, PetAbility = {} }
	end

	local function getTokens()
		local ok, data = pcall(function() return DataService:GetData() end)
		if ok and type(data) == "table" and type(data.TradeData) == "table" then
			return data.TradeData.Tokens or 0
		end
		return math.huge
	end
	local function ownerToUserId(owner) return tonumber((tostring(owner):gsub("Player_", ""))) end

	-- cari target dari data booth, cocokkan ke profil (index profil = prioritas)
	local function collectTargets()
		local ok, data = pcall(function() return RR.new("Booths"):GetDataAsync() end)
		local targets = {}
		if not ok or not data then return targets end
		for _, b in pairs(data.Booths or {}) do
			local owner = b.Owner
			local pd = owner and data.Players and data.Players[owner]
			if pd and pd.Listings then
				for lid, l in pairs(pd.Listings) do
					local it = pd.Items and pd.Items[l.ItemId]
					local p  = it and it.PetData
					if p and it.PetType then
						local disp = mutDisplay(p.MutationType)
						local key  = comboKey(it.PetType, p.HatchedFrom or "?")
						for pi = 1, NUM do
							local prof = CFG.snipeProfiles[pi]
							-- match by kombinasi Pet - Egg (bedakan egg premium vs biasa)
							if prof and next(prof.pets) and prof.pets[key] then
								local mutOK   = (not next(prof.muts)) or prof.muts[disp]
								local priceOK = (prof.maxPrice or 0) <= 0 or l.Price <= prof.maxPrice
								if mutOK and priceOK then
									local ply = Players:GetPlayerByUserId(ownerToUserId(owner))
									targets[#targets + 1] = {
										profile = pi, pet = it.PetType, name = p.Name,
										mut = disp, price = l.Price, uuid = lid,
										owner = ply, present = ply ~= nil,
									}
									break -- profil prioritas tertinggi menang
								end
							end
						end
					end
				end
			end
		end
		table.sort(targets, function(a, b)
			if a.profile ~= b.profile then return a.profile < b.profile end
			return a.price < b.price
		end)
		return targets
	end

	------------------------------------------------------------------ webhook notif beli
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
	local function snipeSelectedTypes()
		local set, order = {}, {}
		for pi = 1, NUM do
			for petKey in pairs(CFG.snipeProfiles[pi].pets) do
				local pt = (string.split(petKey, " - ")[1]) or petKey -- ambil nama pet dari kombo
				if not set[pt] then set[pt] = true; order[#order + 1] = pt end
			end
		end
		table.sort(order)
		return order
	end
	local function buildSnipeSummary()
		local counts = inventoryCounts()
		local lines, total = {}, 0
		for _, pt in ipairs(snipeSelectedTypes()) do
			local c = counts[pt] or 0
			total = total + c
			lines[#lines + 1] = ("%s: %d"):format(pt, c)
		end
		return (#lines > 0 and table.concat(lines, "\n") or "-"), total
	end
	local function notifyBuy(t)
		if not ctx.sendWebhook then return end
		local seller = (t.owner and (t.owner.DisplayName or t.owner.Name)) or "?"
		local summary, total = buildSnipeSummary()
		local tok = getTokens(); tok = (tok == math.huge) and "?" or tostring(tok)
		ctx.sendWebhook({
			username = "CeszParadise GAG Sniper",
			embeds = {{
				title = "✅ Pet Sniped!",
				color = 3066993,
				fields = {
					{ name = "Pet",      value = tostring(t.pet),   inline = true },
					{ name = "Mutation", value = tostring(t.mut),   inline = true },
					{ name = "Price",    value = tostring(t.price) .. " Tokens", inline = true },
					{ name = "Nickname", value = tostring(t.name),  inline = true },
					{ name = "Profile",  value = "Snipe " .. t.profile, inline = true },
					{ name = "Seller",   value = "@" .. seller,     inline = true },
					{ name = ("📊 Total Punya (%d)"):format(total), value = summary, inline = false },
					{ name = "💰 Sisa Token", value = tok .. " Tokens", inline = false },
				},
				footer = { text = "JobId: " .. tostring(game.JobId) },
			}},
		})
		if ctx.reportEvent then
			ctx.reportEvent("buy", {
				pet = tostring(t.pet),
				mutation = (t.mut and t.mut ~= "None" and t.mut ~= "Normal") and tostring(t.mut) or nil,
				price = tonumber(t.price) or 0,
				counterpart = tostring(seller),
			})
		end
	end

	------------------------------------------------------------------ server hop (cari seller)
	local HUB_FOLDER = "AllegiaantHUB"
	local function ensureHubFolder()
		if type(makefolder) == "function" and (type(isfolder) ~= "function" or not isfolder(HUB_FOLDER)) then
			pcall(function() makefolder(HUB_FOLDER) end)
		end
	end
	ensureHubFolder()
	local HOP_FILE = HUB_FOLDER .. "/snipehops.json"
	local function revisitTTL() return math.max(5, math.floor(tonumber(CFG.snipeRevisitSec) or 120)) end
	local visited  = {}
	do
		if type(isfile) == "function" and isfile(HOP_FILE) then
			local ok, d = pcall(function() return HttpService:JSONDecode(readfile(HOP_FILE)) end)
			if ok and type(d) == "table" then
				local now, ttl = os.time(), revisitTTL()
				for job, ts in pairs(d) do if type(ts) == "number" and (now - ts) < ttl then visited[job] = ts end end
			end
		end
	end
	local function saveVisited() pcall(function() writefile(HOP_FILE, HttpService:JSONEncode(visited)) end) end
	local function markVisited(job) if job and job ~= "" then visited[job] = os.time(); saveVisited() end end
	-- Kalau kita SALAH MENDARAT di server yg udah divisit (taksi/matchmaking bawa balik),
	-- JANGAN reset timestamp -> CD tetap dihitung dari kunjungan PERTAMA. Landing pertama
	-- (belum ada di visited) baru dicatat.
	local reLanded = visited[game.JobId] ~= nil
	if not reLanded then markVisited(game.JobId) end
	ctx.state.snipeReLanded = reLanded

	-- Prune TTL secara real-time (bukan cuma saat load) -> "semua visited" self-heal
	-- setelah 2 menit walau ga reload, jadi server lama bisa dikunjungi lagi.
	local function pruneVisited()
		local now, ttl = os.time(), revisitTTL()
		for job, ts in pairs(visited) do
			if type(ts) ~= "number" or (now - ts) >= ttl then visited[job] = nil end
		end
	end

	-- Ambil BANYAK server publik (paginate) + CACHE ke file (TTL 45s) biar ga fetch tiap
	-- hop -> request ke games.roblox.com turun drastis -> ga kena rate-limit 429.
	local SLIST_FILE, SLIST_TTL = HUB_FOLDER .. "/serverlist.json", 45
	local function fetchAllServers()
		-- 1. pakai cache kalau masih fresh (< TTL)
		if type(isfile) == "function" and isfile(SLIST_FILE) then
			local ok, c = pcall(function() return HttpService:JSONDecode(readfile(SLIST_FILE)) end)
			if ok and type(c) == "table" and type(c.servers) == "table"
				and (os.time() - (tonumber(c.time) or 0)) < SLIST_TTL and #c.servers > 0 then
				return c.servers
			end
		end
		-- 2. fetch fresh (paginate)
		local reqFn = (syn and syn.request) or (http and http.request) or http_request or request
		if not reqFn then return nil end
		local all, cursor, tries = {}, nil, 0
		repeat
			local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100"):format(game.PlaceId)
			if cursor then url = url .. "&cursor=" .. cursor end
			local ok, res = pcall(reqFn, { Url = url, Method = "GET" })
			if not ok or not res or not res.Body then break end
			local ok2, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
			if not ok2 or type(data) ~= "table" or type(data.data) ~= "table" then break end
			-- simpan super-ringkas: cuma id+playing (maxPlayers default 30 di getBusyServerList)
			for _, s in ipairs(data.data) do all[#all + 1] = { id = s.id, playing = s.playing } end
			cursor = data.nextPageCursor
			tries = tries + 1
		until not cursor or tries >= 5 or #all >= 400
		if #all > 0 then
			pcall(function() writefile(SLIST_FILE, HttpService:JSONEncode({ time = os.time(), servers = all })) end)
			return all
		end
		return nil
	end

	-- Pilih server acak: prioritas pemain >= minPop; kalau ga ada, ambil APA PUN yang
	-- belum divisit & ada slot (biar selalu gerak, ga nyangkut/ngulang server sama).
	-- SLOT_BUFFER: minimal slot kosong biar ga keburu penuh pas teleport (kurangi 771 "penuh").
	local SLOT_BUFFER = 1 -- cuma buang server BENER-BENER penuh (30/30); terima 29/30 (771 udah dihandle)
	-- Fetch server list SEKALI, balik daftar kandidat (acak). Dipakai buat retry banyak
	-- server tanpa re-fetch tiap kali (hindari rate-limit API).
	local function getBusyServerList(minPop, n)
		local servers = fetchAllServers()
		if not servers then return {} end
		local busy, any = {}, {}
		for _, s in ipairs(servers) do
			local playing = tonumber(s.playing) or 0
			local maxp = tonumber(s.maxPlayers) or 30
			if s.id ~= game.JobId and not visited[s.id] and playing <= (maxp - SLOT_BUFFER) then
				any[#any + 1] = s.id
				if playing >= minPop then busy[#busy + 1] = s.id end
			end
		end
		local pool = (#busy > 0) and busy or any
		-- acak (Fisher-Yates) lalu ambil n teratas
		for i = #pool, 2, -1 do local j = math.random(1, i); pool[i], pool[j] = pool[j], pool[i] end
		local out = {}
		for i = 1, math.min(n or 5, #pool) do out[i] = pool[i] end
		return out
	end

	local function queueResume()
		local q = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
		if q then pcall(function() q(ROUTER) end) end
		-- Kabari agent Termux lagi hop (biar ga di-relaunch pas telemetry di server baru
		-- belum sempet load). Ini jalan tiap hop, ga nunggu telemetry — lebih reliable.
		pcall(function()
			local req = (syn and syn.request) or (http and http.request) or http_request or request
			if not req then return end
			req({
				Url = "https://api.allegiaant.my.id/api/agent/suppress",
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = "ae3858d4a2def3306d6cbff26ff2bd72eee9319b1aae27d1" },
				Body = game:GetService("HttpService"):JSONEncode({
					userId = game:GetService("Players").LocalPlayer.UserId,
					seconds = 120,
				}),
			})
		end)
	end

	local hopInProgress = false
	local function serverHop()
		if not CFG.snipeHop or hopInProgress then return end
		hopInProgress = true
		queueResume()

		local searchTargets, seen = {}, {}
		for pi = 1, NUM do
			for petKey in pairs(CFG.snipeProfiles[pi].pets) do
				local pt = (string.split(petKey, " - ")[1]) or petKey -- FindSellers butuh nama pet
				if not seen[pt] then seen[pt] = true; searchTargets[#searchTargets + 1] = pt end
			end
		end

		local function findJobId(tbl)
			if type(tbl) ~= "table" then return nil end
			for _, v in pairs(tbl) do
				if type(v) == "string" and v:match("^%w+-%w+-%w+-%w+-%w+$") then return v
				elseif type(v) == "table" then local r = findJobId(v); if r then return r end end
			end
			return nil
		end

		-- Deteksi teleport gagal (mis. 771 = server ga tersedia) biar cepat coba server lain.
		local tpFailed, failStreak = false, 0
		local conn = TeleportService.TeleportInitFailed:Connect(function(plr, _, msg)
			if plr == LP then tpFailed = true; log("Snipe: teleport gagal (" .. tostring(msg) .. "), coba server lain") end
		end)

		-- Seller hop: pakai teleport resmi game (robust, jarang 771). Cek visited udah di caller.
		-- Landing kadang beda dari jobId (revisit CD harmless), tapi ga bikin dialog 771.
		local function hopViaListing(tpData, jobId)
			tpFailed = false
			if jobId then markVisited(jobId) end
			task.wait(0.35) -- flush writefile sebelum teleport
			pcall(function() TeleportToListing:InvokeServer(tpData, true) end)
			local t0 = os.clock()
			repeat task.wait(0.25) until (not running()) or tpFailed or (os.clock() - t0) >= 4
			return not tpFailed
		end

		-- Busy hop: teleport ke instance spesifik (kontrol populasi). Gagal cepat -> coba lain.
		-- Gagal terus -> matchmaking (ga kena 771).
		local function hopTo(jobId)
			tpFailed = false
			markVisited(jobId)
			task.wait(0.35) -- flush writefile dulu (emulator lambat) sebelum teleport
			pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LP) end)
			local t0 = os.clock()
			repeat task.wait(0.25) until (not running()) or tpFailed or (os.clock() - t0) >= 4
			if tpFailed then
				failStreak = failStreak + 1
				if failStreak >= 3 then -- join instance gagal terus -> matchmaking biasa (ga 771)
					failStreak = 0
					setStatus("Snipe: join gagal terus, teleport matchmaking...")
					pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
					local t2 = os.clock()
					repeat task.wait(0.5) until (not running()) or (os.clock() - t2) >= 8
				end
			end
			return not tpFailed
		end

		local function attempt()
			while running() do
				pruneVisited() -- TTL real-time: server lama kadaluarsa walau ga reload
				for i = #searchTargets, 2, -1 do
					local j = math.random(1, i); searchTargets[i], searchTargets[j] = searchTargets[j], searchTargets[i]
				end
				-- FILTER 1: Hop by Index (FindSellers / cari seller lintas server)
				if CFG.snipeHopIndex and #searchTargets > 0 then
					setStatus("Snipe: cari seller online...")
					-- GAME batasi FindSellers ~5 detik/panggilan ("Please wait Xs before finding
					-- another seller"). Jadi panggil CUMA 1 pet/hop (di-acak, semua kebagian lintas
					-- hop). Sisanya andalkan scan booth lokal + busy hop (ga ada cooldown).
					for idx, petType in ipairs(searchTargets) do
						if idx > 1 then break end
						if not running() then return end
						setStatus(("Snipe: cari seller %s"):format(petType))
						local itemData = buildItemData(petType)
						local ok, success, tpData = pcall(function()
							return FindSellers:InvokeServer("Pet", itemData)
						end)
						if ok and success and tpData then
							local targetJobId = (type(tpData) == "string" and tpData) or findJobId(tpData)
							if targetJobId == game.JobId then
								-- seller di server ini (harga > limit) -> lewati
							elseif targetJobId and visited[targetJobId] then
								-- sudah dikunjungi dalam TTL -> skip
							elseif targetJobId then
								setStatus(("Snipe: seller ketemu! TP (%s)..."):format(petType))
								hopViaListing(tpData, targetJobId) -- taksi game (robust); sukses -> unload
								if not running() then return end
							end
						end
						if not running() then return end
						-- cuma 1 FindSellers/hop -> ga perlu jeda anti rate-limit besar
					end
				end
				if not running() then return end
				-- FILTER 2: Hop by Player (server berdasarkan Min Players; set 1 = semua server).
				-- Tetap hormati revisit CD (getBusyServer exclude visited).
				local hopped = false
				if CFG.snipeHopPlayer then
					local minPop = math.max(1, math.floor(tonumber(CFG.snipeMinPop) or 25))
					-- Fetch daftar server SEKALI (hindari rate-limit), coba kandidat satu-satu:
					-- gagal (full/771) -> langsung server berikutnya. Sukses -> game unload.
					local candidates = getBusyServerList(minPop, 5)
					for _, busy in ipairs(candidates) do
						if not running() then return end
						setStatus(("Snipe: hop by player (>=%d)..."):format(minPop))
						hopTo(busy) -- sukses -> unload; gagal (~0.5s) -> kandidat berikutnya
						hopped = true
					end
				end
				if not running() then return end
				if not hopped then
					if CFG.snipeHopPlayer then
						-- pool kosong (semua kevisit/penuh) -> matchmaking biar ga stall 3s.
						setStatus("Snipe: server habis/kevisit, teleport matchmaking...")
						pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
						local t0 = os.clock()
						repeat task.wait(0.5) until (not running()) or (os.clock() - t0) >= 8
					else
						setStatus("Snipe: hop mati, tunggu 3s...")
						task.wait(3)
					end
				end
			end
		end

		attempt()
		if conn then conn:Disconnect() end
		hopInProgress = false
	end

	------------------------------------------------------------------ core loop
	local function anyProfileActive()
		for i = 1, NUM do if next(CFG.snipeProfiles[i].pets) then return true end end
		return false
	end
	local function buyPass()
		local targets = collectTargets()
		local buyable, bought = 0, 0
		for _, t in ipairs(targets) do
			if not running() then break end
			if t.present then
				buyable = buyable + 1
				if getTokens() >= t.price then
					local ok, success, m = pcall(function() return BuyListing:InvokeServer(t.owner, t.uuid) end)
					if ok and success then
						bought = bought + 1
						log(("BUY %s [%s] @%d (Snipe %d)"):format(t.pet, t.mut, t.price, t.profile))
						notifyBuy(t)
					else
						log(("FAIL %s @%d (%s)"):format(t.pet, t.price, tostring(m or success)))
					end
					task.wait(0.6)
				end
			end
		end
		return #targets, buyable, bought
	end

	local function mainLoop()
		while running() do
			if not anyProfileActive() then
				setStatus("Snipe: pilih pet di profil dulu")
				task.wait(2)
			else
				setStatus(("Snipe: scan... Token:%s"):format(tostring(getTokens())))
				local total, buyable, bought = buyPass()
				if not running() then break end
				setStatus(("Snipe: target %d beli %d Token:%s"):format(total, bought, tostring(getTokens())))
				if buyable > 0 and bought > 0 then
					task.wait(3)
				elseif CFG.snipeHop then
					setStatus("Snipe: ga ada target, hop...")
					task.wait(0.5); serverHop(); break -- pre-hop dipangkas 2s -> 0.5s
				else
					task.wait(3)
				end
			end
		end
	end

	------------------------------------------------------------------ status utk GUI
	function ctx.getSnipeStatus()
		local parts = {}
		for i = 1, NUM do
			local pr = CFG.snipeProfiles[i]
			if next(pr.pets) then
				local first; for pt in pairs(pr.pets) do first = pt; break end
				parts[#parts + 1] = ("[P%d] %s | Max %s"):format(i, first or "?", (pr.maxPrice or 0) > 0 and pr.maxPrice or "∞")
			end
		end
		return {
			on = CFG.snipeEnabled == true,
			lines = #parts > 0 and table.concat(parts, "\n") or "No profile set",
		}
	end

	function ctx.startSnipe()
		if running() then return end
		ctx.state.snipeRunning = true
		hopInProgress = false
		task.spawn(mainLoop)
	end
	function ctx.stopSnipe()
		ctx.state.snipeRunning = false
		hopInProgress = false
	end

	-- auto-resume setelah hop / rejoin.
	-- Tunggu web sync PULL config dulu (max ~10s) biar setting web (mis. snipe di-OFF-in)
	-- ke-apply sebelum snipe nyala & hop lagi. Tanpa ini, hop cepat bikin config web ga
	-- pernah ke-apply. Habis nunggu, cek ULANG CFG.snipeEnabled (bisa udah jadi false dari web).
	if CFG.snipeEnabled then
		task.spawn(function()
			local t = 0
			while not ctx.state.webSyncReady and t < 10 do task.wait(0.3); t = t + 0.3 end
			task.wait(1.0)
			if CFG.snipeEnabled then
				ctx.startSnipe()
				log("Auto-resume: Snipe ON.")
			else
				log("Snipe di-OFF dari web — tidak auto-resume.")
			end
		end)
	end
end
