-- AUTO-GENERATED oleh tools/bundle.js — JANGAN edit manual.
-- Edit modul-nya langsung, terus run `node tools/bundle.js`.
-- 14 modul, di-generate 2026-09-11T12:13:25.140Z
return {
	["app.lua"] = [=[
--[[ app.lua — inisialisasi akhir: default page, supervisor auto-claim, auto-resume. ]]
return function(ctx)
	local CFG     = ctx.CFG
	local pages   = ctx.ui.pages
	local tabBtns = ctx.ui.tabBtns
	local C       = ctx.C
	local function log(msg) ctx.log(msg) end

	------------------------------------------------------------------ Default page
	pages["Sell"].Visible = true
	tabBtns["Sell"].btn.BackgroundTransparency = 0.86
	tabBtns["Sell"].btn.TextColor3 = C.txt
	tabBtns["Sell"].line.Visible = true

	log("CeszParadise GAG Seller v1.2.5 dimuat.")
	pcall(function()
		local Players = ctx.Services.Players or game:GetService("Players")
		log(("Masuk server: %d/%d pemain."):format(#Players:GetPlayers(), Players.MaxPlayers))
	end)
	ctx.renderInventory()

	------------------------------------------------------------------ Anti-AFK
	-- Roblox nendang setelah ~20 menit idle. Event LocalPlayer.Idled fire tepat sebelum kick;
	-- kita simulasi input (VirtualUser) buat reset timer idle-nya -> nggak ke-kick.
	pcall(function()
		local VirtualUser = game:GetService("VirtualUser")
		ctx.LP.Idled:Connect(function()
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new())
			end)
			log("Anti-AFK: reset idle timer.")
		end)
		log("Anti-AFK aktif.")
	end)

	------------------------------------------------------------------ Auto-Reconnect
	-- Kalau ke-kick / DC / error (dialog Roblox muncul) -> otomatis rejoin ke game yg sama,
	-- lalu hub di-load ulang di server baru (via queue_on_teleport). Ikut branch aktif.
	pcall(function()
		local GuiService = game:GetService("GuiService")
		local TeleportService = game:GetService("TeleportService")
		local branch = (getgenv and getgenv().GAG_BRANCH) or "main"
		local RECON = ("getgenv().GAG_BRANCH='%s';loadstring(game:HttpGet('https://raw.githubusercontent.com/catursec/tanduran/%s/kebongedang/init.lua'))()"):format(branch, branch)
		local reconnecting = false
		local function reconnect()
			if reconnecting or CFG.autoReconnect == false then return end -- cek toggle real-time
			reconnecting = true
			log("Ke-DC/kick terdeteksi — auto reconnect...")
			local q = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
			if q then pcall(function() q(RECON) end) end
			task.wait(3)
			pcall(function() TeleportService:Teleport(game.PlaceId, ctx.LP) end)
			-- fallback: kalau teleport gagal (place instance), coba matchmaking biasa
			task.wait(8)
			pcall(function() TeleportService:Teleport(game.PlaceId, ctx.LP) end)
		end
		GuiService.ErrorMessageChanged:Connect(reconnect)
		log("Auto-Reconnect aktif.")
	end)

	------------------------------------------------------------------ Auto Claim Supervisor Loop
	task.spawn(function()
		ctx.elevate()
		local lastState
		while ctx.alive() do
			local delay = 3
			local ok, err = pcall(function()
				if CFG.autoClaim then
					local owns, data, boothName = ctx.ownsBooth()
					if owns then
						if lastState ~= "own" then log("Booth aman: " .. tostring(boothName)); lastState = "own" end
						ctx.autoSwitchBoothPortal()
						delay = 6
					else
						if lastState ~= "hunt" then log("Booth hilang, mencari terdekat..."); lastState = "hunt" end
						ctx.tryClaimNearest()
						delay = 5
					end
				else
					lastState = nil
					delay = 1
				end
			end)
			if not ok then log("claim-loop err: " .. tostring(err)) end
			task.wait(delay)
		end
	end)

	------------------------------------------------------------------ Auto Resume
	-- Tunggu web sync PULL config dulu (max ~10s) biar setting web (autoSell) ke-apply
	-- sebelum loop nyala, lalu cek ULANG CFG.autoSell.
	task.spawn(function()
		local t = 0
		while not ctx.state.webSyncReady and t < 10 do task.wait(0.3); t = t + 0.3 end
		task.wait(1.0)
		if CFG.autoSell then
			ctx.state.running = true
			if ctx.ui.rAutoToggle then ctx.ui.rAutoToggle() end
			task.spawn(ctx.mainLoop)
			log("Auto-resume: loop dinyalakan.")
		end
	end)
end
]=],
	["modules/buy/sniper.lua"] = [=[
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
]=],
	["modules/core/config.lua"] = [=[
--[[ config.lua — konfigurasi default + persist/load state ke JSON.
     Mengisi: ctx.NUM_PROFILES, ctx.NUM_LISTINGS, ctx.CFG,
              ctx.persistState, ctx.loadState ]]
return function(ctx)
    local HttpService = ctx.Services.HttpService

    local NUM_PROFILES = 3
    local NUM_LISTINGS = 3
    local NUM_SNIPE    = 5

    local CFG = {
        autoSell         = false,
        autoClaim        = true,
        autoSwitchPortal = false,
        autoReconnect    = true,  -- auto rejoin kalau ke-kick/DC
        boothSkin        = "Default",
        profiles         = {},
        webhookUrl       = "",
        webhookEnabled   = false,
        relocateEnabled    = false,
        relocateIdleMin    = 20,
        relocateMinPlayers = 10,
        relocatePreferred  = 20,
        -- sniper / auto-buy
        snipeEnabled       = false,
        snipeHop           = true,  -- master enable hop
        snipeHopIndex      = true,  -- filter: hop by index (FindSellers / cari seller)
        snipeHopPlayer     = true,  -- filter: hop by player (server berdasarkan Min Players)
        snipeMinPop        = 25,   -- hop by player: server dgn pemain >= ini (set 1 = semua server)
        snipeRevisitSec    = 120,  -- jeda sebelum boleh balik ke server yang sama (detik)
        snipeProfiles      = {},
    }
    for i = 1, NUM_SNIPE do
        CFG.snipeProfiles[i] = { pets = {}, muts = {}, maxPrice = 0 }
    end
    for i = 1, NUM_PROFILES do
        CFG.profiles[i] = { listings = {} }
        for j = 1, NUM_LISTINGS do
            CFG.profiles[i].listings[j] = { pets = {}, muts = {}, minW = 0, maxW = 0, maxList = 0, price = 100 }
        end
    end

    -- Pastikan LocalPlayer dan UserId sudah siap (hindari nil)
    local Players = ctx.Services.Players or game:GetService("Players")
    local localPlayer = Players.LocalPlayer
    while not localPlayer do
        Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        localPlayer = Players.LocalPlayer
    end
    local userId = localPlayer.UserId

    -- Setiap clone punya file terpisah (contoh: trade_state_12345.json)
    local STATE_FILE = "trade_state_" .. tostring(userId) .. ".json"

    -- 1. Simpan langsung ke file akun ini saja
    local function persistState()
        pcall(function()
            if type(writefile) == "function" then
                writefile(STATE_FILE, HttpService:JSONEncode(CFG))
            end
        end)
    end

    -- 2. Muat langsung dari file akun ini saja
    local function loadState()
        if type(isfile) == "function" and isfile(STATE_FILE) then
            local ok, data = pcall(function()
                return HttpService:JSONDecode(readfile(STATE_FILE))
            end)
            if ok and type(data) == "table" then
                return data
            end
        end
        return nil
    end

    ----------------------------------------------------------------- restore
    do
        local st = loadState()
        if st then
            if st.autoClaim ~= nil then CFG.autoClaim = st.autoClaim end
            if st.autoSwitchPortal ~= nil then CFG.autoSwitchPortal = st.autoSwitchPortal end
            if st.autoReconnect ~= nil then CFG.autoReconnect = st.autoReconnect end
            CFG.boothSkin       = st.boothSkin or "Default"
            CFG.autoSell        = st.autoSell or false
            CFG.webhookUrl      = st.webhookUrl or ""
            CFG.webhookEnabled  = st.webhookEnabled or false
            CFG.relocateEnabled    = st.relocateEnabled or false
            if st.relocateIdleMin    ~= nil then CFG.relocateIdleMin    = tonumber(st.relocateIdleMin) or 20 end
            if st.relocateMinPlayers ~= nil then CFG.relocateMinPlayers = tonumber(st.relocateMinPlayers) or 10 end
            if st.relocatePreferred  ~= nil then CFG.relocatePreferred  = tonumber(st.relocatePreferred) or 20 end
            CFG.snipeEnabled = st.snipeEnabled or false
            if st.snipeHop ~= nil then CFG.snipeHop = st.snipeHop end
            if st.snipeHopIndex ~= nil then CFG.snipeHopIndex = st.snipeHopIndex end
            if st.snipeHopPlayer ~= nil then CFG.snipeHopPlayer = st.snipeHopPlayer end
            if st.snipeMinPop ~= nil then CFG.snipeMinPop = tonumber(st.snipeMinPop) or 25 end
            if st.snipeRevisitSec ~= nil then CFG.snipeRevisitSec = tonumber(st.snipeRevisitSec) or 120 end
            if type(st.snipeProfiles) == "table" then
                for i = 1, NUM_SNIPE do
                    local sp = st.snipeProfiles[i] or st.snipeProfiles[tostring(i)]
                    if type(sp) == "table" then
                        CFG.snipeProfiles[i].pets     = (type(sp.pets) == "table") and sp.pets or {}
                        CFG.snipeProfiles[i].muts     = (type(sp.muts) == "table") and sp.muts or {}
                        CFG.snipeProfiles[i].maxPrice = tonumber(sp.maxPrice) or 0
                    end
                end
            end
            if type(st.profiles) == "table" then
                for i = 1, NUM_PROFILES do
                    local sp = st.profiles[i] or st.profiles[tostring(i)]
                    if type(sp) == "table" and type(sp.listings) == "table" then
                        for j = 1, NUM_LISTINGS do
                            local sl = sp.listings[j] or sp.listings[tostring(j)]
                            if type(sl) == "table" then
                                CFG.profiles[i].listings[j].pets    = (type(sl.pets) == "table") and sl.pets or {}
                                CFG.profiles[i].listings[j].muts    = (type(sl.muts) == "table") and sl.muts or {}
                                CFG.profiles[i].listings[j].minW    = tonumber(sl.minW) or 0
                                CFG.profiles[i].listings[j].maxW    = tonumber(sl.maxW) or 0
                                CFG.profiles[i].listings[j].maxList = tonumber(sl.maxList) or 0
                                CFG.profiles[i].listings[j].price   = tonumber(sl.price) or 100
                            end
                        end
                    end
                end
            end
        end
    end

    ctx.NUM_PROFILES = NUM_PROFILES
    ctx.NUM_LISTINGS = NUM_LISTINGS
    ctx.NUM_SNIPE    = NUM_SNIPE
    ctx.CFG          = CFG
    ctx.persistState = persistState
    ctx.loadState    = loadState
end
]=],
	["modules/core/registry.lua"] = [=[
--[[ registry.lua — bangun opsi dropdown dari data game.
     Mengisi: ctx.reg = { comboKey, mutDisplay, PET_OPTIONS, MUT_OPTIONS, SKIN_OPTIONS } ]]
return function(ctx)
	local PetEggs   = ctx.deps.PetEggs
	local PetList   = ctx.deps.PetList or {}
	local EnumToMut = ctx.deps.EnumToMut
	local SkinsReg  = ctx.deps.SkinsReg

	-- Map nama pet -> asset id icon (dari PetList[pet].Icon = "rbxassetid://123").
	local PET_ICONS = {}
	for petName, d in pairs(PetList) do
		if type(d) == "table" and d.Icon then
			local id = tostring(d.Icon):match("(%d+)")
			if id then PET_ICONS[tostring(petName)] = id end
		end
	end

	-- opsi dropdown = kombinasi "Pet - Egg"
	local function comboKey(petType, egg)
		return tostring(petType) .. " - " .. tostring(egg)
	end

	----------------------------------------------------------------- PET_OPTIONS
	local PET_OPTIONS = {}
	do
		local seen = {}
		for eggName, egg in pairs(PetEggs) do
			local items = egg.RarityData and egg.RarityData.Items
			if items then
				for petName in pairs(items) do
					if not tostring(petName):match("^Egg/") then
						local nameStr = tostring(petName)
						if not seen[nameStr] then
							seen[nameStr] = true
							PET_OPTIONS[#PET_OPTIONS + 1] = nameStr
						end
					end
				end
			end
		end
		table.sort(PET_OPTIONS)
	end

	----------------------------------------------------------------- PET_COMBO_OPTIONS (Pet - Egg)
	-- Bedakan pet per egg (premium vs biasa). Dipakai snipe biar bisa target spesifik.
	local PET_COMBO_OPTIONS = {}
	do
		local seen = {}
		for eggName, egg in pairs(PetEggs) do
			local items = egg.RarityData and egg.RarityData.Items
			if items then
				for petName in pairs(items) do
					if not tostring(petName):match("^Egg/") then
						local k = comboKey(petName, eggName)
						if not seen[k] then seen[k] = true; PET_COMBO_OPTIONS[#PET_COMBO_OPTIONS + 1] = k end
					end
				end
			end
		end
		table.sort(PET_COMBO_OPTIONS)
	end

	----------------------------------------------------------------- MUT_OPTIONS
	local MUT_OPTIONS, seenMut = { "None" }, { None = true }
	for _, name in pairs(EnumToMut) do
		if name ~= "Normal" and not seenMut[name] then
			seenMut[name] = true
			MUT_OPTIONS[#MUT_OPTIONS + 1] = name
		end
	end
	table.sort(MUT_OPTIONS)

	----------------------------------------------------------------- SKIN_OPTIONS
	local SKIN_OPTIONS = {}
	for name, data in pairs(SkinsReg) do
		SKIN_OPTIONS[#SKIN_OPTIONS + 1] = { name = name, display = data.DisplayName or name }
	end
	table.sort(SKIN_OPTIONS, function(a, b) return a.display < b.display end)

	----------------------------------------------------------------- mutDisplay
	local function mutDisplay(code)
		if code == nil or code == "" or code == "m" or code == "None" or code == "Normal" then
			return "None"
		end
		return EnumToMut[code] or code
	end

	ctx.reg = {
		comboKey          = comboKey,
		mutDisplay        = mutDisplay,
		PET_OPTIONS       = PET_OPTIONS,
		PET_COMBO_OPTIONS = PET_COMBO_OPTIONS,
		PET_ICONS         = PET_ICONS,
		MUT_OPTIONS       = MUT_OPTIONS,
		SKIN_OPTIONS      = SKIN_OPTIONS,
	}
end
]=],
	["modules/core/services.lua"] = [=[
--[[ services.lua — game services + require semua module game (deps).
     Mengisi: ctx.Services, ctx.LP, ctx.deps ]]
return function(ctx)
	local Players           = game:GetService("Players")
	local RS                = game:GetService("ReplicatedStorage")
	local HttpService       = game:GetService("HttpService")
	local UserInputService  = game:GetService("UserInputService")
	local CollectionService = game:GetService("CollectionService")

	if not game:IsLoaded() then game.Loaded:Wait() end
	repeat task.wait() until Players.LocalPlayer
	local LP = Players.LocalPlayer

	ctx.Services = {
		Players           = Players,
		RS                = RS,
		HttpService       = HttpService,
		UserInputService  = UserInputService,
		CollectionService = CollectionService,
	}
	ctx.LP = LP

	----------------------------------------------------------------- deps
	local RR              = require(RS.Modules.ReplicationReciever)
	local DataService     = require(RS.Modules.DataService)
	local TradeBoothsData = require(RS.Data.TradeBoothsData)
	local PU              = require(RS.Modules.PetServices.PetUtilities)
	local PetEggs         = require(RS.Data.PetRegistry.PetEggs)
	local MutReg          = require(RS.Data.PetRegistry.PetMutationRegistry)
	local okPL, PetList   = pcall(function() return require(RS.Data.PetRegistry.PetList) end)
	if not okPL then PetList = {} end
	local SkinsReg        = require(RS.Data.TradeBoothSkinRegistry)

	local Booths = RS.GameEvents.TradeEvents.Booths
	-- TokenRAPs (buat sniper cari seller lintas server) — akses defensif biar ga bikin
	-- seluruh hub error kalau path berubah.
	local TradeEvents = RS.GameEvents:FindFirstChild("TradeEvents")
	local TokenRAPs   = TradeEvents and TradeEvents:FindFirstChild("TokenRAPs")
	local okTRU, TokenRAPUtil = pcall(function() return require(RS.Modules.TradeTokens.TokenRAPUtil) end)

	ctx.deps = {
		RR              = RR,
		DataService     = DataService,
		TradeBoothsData = TradeBoothsData,
		PU              = PU,
		PetEggs         = PetEggs,
		PetList         = PetList,
		MutReg          = MutReg,
		SkinsReg        = SkinsReg,
		EnumToMut       = MutReg.EnumToPetMutation,

		Booths          = Booths,
		ClaimBooth      = Booths.ClaimBooth,
		CreateListing   = Booths.CreateListing,
		RemoveBooth     = Booths.RemoveBooth,
		RemoveListing   = Booths.RemoveListing,
		AddToHistory    = Booths.AddToHistory,
		BuyListing      = Booths.BuyListing,
		EquipSkin       = RS.GameEvents.TradeBoothSkinService.Equip,

		-- sniper (auto-buy dari booth pemain lain + cari seller lintas server)
		FindSellers       = TokenRAPs and TokenRAPs:FindFirstChild("FindSellers"),
		TeleportToListing = TokenRAPs and TokenRAPs:FindFirstChild("TeleportToListing"),
		TokenRAPUtil      = okTRU and TokenRAPUtil or nil,
	}
end
]=],
	["modules/core/webhook.lua"] = [=[
--[[ webhook.lua — Discord webhook + listener transaksi (notif terjual).
     Mengisi: ctx.sendWebhook
     Efek samping: connect AddToHistory.OnClientEvent ]]
return function(ctx)
	local LP          = ctx.LP
	local HttpService = ctx.Services.HttpService
	local CFG         = ctx.CFG
	local AddToHistory = ctx.deps.AddToHistory

	----------------------------------------------------------------- sender
	local function sendWebhook(payload)
		if not CFG.webhookEnabled or CFG.webhookUrl == "" then return end
		if type(payload) == "table" then
			if not payload.username then payload.username = "CeszParadise" end
			if not payload.avatar_url then payload.avatar_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png" end
		end
		task.spawn(function()
			local reqFn = (syn and syn.request) or (http and http.request) or http_request or request
			if not reqFn then return end
			pcall(reqFn, {
				Url = CFG.webhookUrl, Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode(payload),
			})
		end)
	end
	ctx.sendWebhook = sendWebhook

	----------------------------------------------------------------- history ke dashboard
	-- Kirim transaksi (buy/sell) ke Laravel buat History tab. Non-blocking, best-effort.
	local EVENT_URL = "https://api.allegiaant.my.id/api/event"
	local EVENT_KEY = "ae3858d4a2def3306d6cbff26ff2bd72eee9319b1aae27d1"
	local function reportEvent(kind, data)
		task.spawn(function()
			local reqFn = (syn and syn.request) or (http and http.request) or http_request or request
			if not reqFn then return end
			data = data or {}
			data.kind = kind
			data.userId = LP.UserId
			pcall(reqFn, {
				Url = EVENT_URL, Method = "POST",
				Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = EVENT_KEY },
				Body = HttpService:JSONEncode(data),
			})
		end)
	end
	ctx.reportEvent = reportEvent

	----------------------------------------------------------------- sell listener
	-- Dedup GLOBAL (persist antar-reload). ctx.state di-reset tiap reload, jadi
	-- kalau pakai tabel per-ctx, listener lama (yg bocor) + listener baru punya
	-- tabel dedup masing-masing -> kirim double/triple. Tabel global bikin listener
	-- mana pun yg duluan proses tx.id nge-block sisanya.
	local lastProcessedTx = _G.__AH_SellTx
	if type(lastProcessedTx) ~= "table" then
		lastProcessedTx = {}
		_G.__AH_SellTx = lastProcessedTx
	end
	ctx.state.lastProcessedTx = lastProcessedTx

	-- Disconnect listener dari eksekusi/reload sebelumnya biar nggak numpuk.
	if _G.__AH_SellConn then pcall(function() _G.__AH_SellConn:Disconnect() end) end

	_G.__AH_SellConn = AddToHistory.OnClientEvent:Connect(function(tx)
		if not CFG.webhookEnabled or CFG.webhookUrl == "" then return end
		if not tx or type(tx) ~= "table" then return end
		if lastProcessedTx[tx.id] then return end
		lastProcessedTx[tx.id] = true

		-- Cek apakah kita adalah penjual (seller) dan transaksinya sukses
		local myId = ctx.myPlayerId()
		local isSeller = (myId == tx.seller.userId) or (LP.UserId == tx.seller.userId)
		local isSuccess = tx.status and tx.status.result ~= "Failed"

		if isSeller and isSuccess then
			-- Dapatkan detail item
			local itemType = tx.item and tx.item.type or "Unknown"
			local petType = "Unknown"
			local petName = "-"
			local petAge = "-"
			local petWeight = "-"

			local sellW, sellAge, sellMut = nil, nil, nil
			if itemType == "Pet" and tx.item.data then
				local d = tx.item.data
				petType = d.PetType or "Unknown"
				if d.PetData then
					petName = d.PetData.Name or petType
					if petName == "" then petName = petType end
					petAge = tostring(d.PetData.Level or 0)
					petWeight = ("%.2f kg"):format(d.PetData.BaseWeight or 0)
					sellW = d.PetData.BaseWeight or 0
					sellAge = d.PetData.Level or 0
					local okm, m = pcall(function() return ctx.reg.mutDisplay(d.PetData.MutationType) end)
					if okm and m and m ~= "None" and m ~= "Normal" then sellMut = m end
				end
			else
				-- Fallback jika bukan pet
				if tx.item.data then
					if tx.item.data.ItemData then
						petType = tx.item.data.ItemData.ItemName or "Unknown"
					else
						petType = tx.item.data.PetType or tx.item.data.SkinID or "Unknown"
					end
					petName = petType
				end
			end

			local price = tx.price or 0
			local priceWithFee = price - math.ceil(price / 100)

			local currentTokens = tostring(ctx.getTokens())
			local formattedTokens = currentTokens
			local numTokens = tonumber(currentTokens)
			if numTokens then
				local formatted = tostring(numTokens)
				local k
				while true do
					formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1.%2')
					if k == 0 then break end
				end
				formattedTokens = formatted
			end

			local embed = {
				title = "✦ CeszParadise — Sell Notification",
				color = 16738670, -- Soft vibrant rose
				fields = {
					{
						name = "**Profile :**",
						value = ("> Username : **%s**\n> Buyer : `%s`"):format(tostring(tx.seller.username), tostring(tx.buyer.username)),
						inline = false
					},
					{
						name = "**Item Sold :**",
						value = ("> Item Type : `%s`\n> Pet Type : `%s`\n> Pet Name : `%s`\n> Pet Age : `%s`\n> Pet Weight : `%s`\n> Price : **%s Token**\n> Price (With Fee) : `%s Token`"):format(
							tostring(itemType),
							tostring(petType),
							tostring(petName),
							tostring(petAge),
							tostring(petWeight),
							tostring(price),
							tostring(priceWithFee)
						),
						inline = false
					},
					{
						name = "**Current Tokens :**",
						value = ("> **%s Token**"):format(tostring(formattedTokens)),
						inline = false
					}
				},
				footer = {
					text = ("CeszParadise Trade • %s"):format(os.date("%B %d | %I:%M %p")),
					icon_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png"
				}
			}

			sendWebhook({
				username = "CeszParadise",
				avatar_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png",
				embeds = { embed }
			})

			reportEvent("sell", {
				pet = petType,
				mutation = sellMut,
				weight = sellW,
				age = sellAge,
				price = tonumber(price) or 0,
				counterpart = tostring(tx.buyer and tx.buyer.username or "?"),
			})
		end
	end)
end
]=],
	["modules/core/websync.lua"] = [=[
--[[ websync.lua — sinkron opsi/config trade ke dashboard web (AllegiaantHUB Monitor).

     STEP 1: push OPTIONS (pet/mutasi/skin) -> dropdown web sama persis in-game.
     STEP 2: sync CONFIG DUA ARAH per-akun:
        - Web -> Script : poll GET /api/config/:userId tiap 5s, apply kalau beda + start/stop automation.
        - Script -> Web : bungkus ctx.persistState -> tiap setting diubah in-game, auto PUT ke web.
        - Baseline `lastApplied` (serialize deterministik) cegah gema/apply berulang.

     Semua HTTP di THREAD TERPISAH + pcall = non-blocking, ga ganggu automation. ]]
return function(ctx)
	local WEB_BASE = "https://api.allegiaant.my.id"
	local API_KEY  = "ae3858d4a2def3306d6cbff26ff2bd72eee9319b1aae27d1"
	local POLL_EVERY = 10  -- detik (hemat invocation Vercel; config/command telat max ~10s)

	local HttpService = game:GetService("HttpService")
	local Players     = game:GetService("Players")
	local LP          = ctx.LP or Players.LocalPlayer
	local httpReq     = (syn and syn.request) or (http and http.request) or http_request or request

	----------------------------------------------------------------- STEP 1: options
	local function buildOptions()
		local reg = ctx.reg or {}
		local skins = {}
		for _, s in ipairs(reg.SKIN_OPTIONS or {}) do
			skins[#skins + 1] = (type(s) == "table" and s.name) or tostring(s) -- CFG.boothSkin = nama internal
		end
		return {
			pets     = reg.PET_OPTIONS or {},
			petCombo = reg.PET_COMBO_OPTIONS or {},
			petIcons = reg.PET_ICONS or {},   -- nama pet -> asset id icon (buat gambar di web)
			muts     = reg.MUT_OPTIONS or {},
			skins    = skins,
		}
	end

	function ctx.webPushOptions()
		if not httpReq then return end
		task.spawn(function()
			pcall(function()
				httpReq({
					Url = WEB_BASE .. "/api/options",
					Method = "POST",
					Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = API_KEY },
					Body = HttpService:JSONEncode(buildOptions()),
				})
			end)
		end)
	end

	----------------------------------------------------------------- STEP 2: config sync
	-- Field config yang di-sync (nama identik CFG <-> web TradeConfig).
	local function setKeys(s)
		if type(s) ~= "table" then return "" end
		local k = {}
		for key, v in pairs(s) do if v then k[#k + 1] = tostring(key) end end
		table.sort(k)
		return table.concat(k, ",")
	end

	-- Serialize deterministik buat bandingin config (lokal vs web). Field-nya sama, urutan tetap.
	local function serialize(c)
		c = c or {}
		local t = {}
		local function add(v) t[#t + 1] = tostring(v) end
		add(c.autoSell); add(c.autoClaim); add(c.autoSwitchPortal); add(c.autoReconnect); add(c.boothSkin)
		add(c.relocateEnabled); add(c.relocateIdleMin); add(c.relocateMinPlayers); add(c.relocatePreferred)
		add(c.snipeEnabled); add(c.snipeHop); add(c.snipeHopIndex); add(c.snipeHopPlayer); add(c.snipeMinPop); add(c.snipeRevisitSec)
		add(c.webhookEnabled); add(c.webhookUrl)
		local profs = c.profiles or {}
		for i = 1, (ctx.NUM_PROFILES or 3) do
			local p = profs[i] or profs[tostring(i)] or {}
			local ls = p.listings or {}
			for j = 1, (ctx.NUM_LISTINGS or 3) do
				local l = ls[j] or ls[tostring(j)] or {}
				add(setKeys(l.pets)); add(setKeys(l.muts)); add(l.minW); add(l.maxW); add(l.maxList); add(l.price)
			end
		end
		local sps = c.snipeProfiles or {}
		for i = 1, (ctx.NUM_SNIPE or 5) do
			local p = sps[i] or sps[tostring(i)] or {}
			add(setKeys(p.pets)); add(setKeys(p.muts)); add(p.maxPrice)
		end
		return table.concat(t, "|")
	end

	-- Snapshot CFG -> tabel yang match web TradeConfig (buat PUT).
	local function snapshot()
		local CFG = ctx.CFG
		return {
			autoSell = CFG.autoSell == true, autoClaim = CFG.autoClaim == true,
			autoSwitchPortal = CFG.autoSwitchPortal == true, autoReconnect = CFG.autoReconnect ~= false,
			boothSkin = CFG.boothSkin or "Default",
			relocateEnabled = CFG.relocateEnabled == true, relocateIdleMin = CFG.relocateIdleMin or 20,
			relocateMinPlayers = CFG.relocateMinPlayers or 10, relocatePreferred = CFG.relocatePreferred or 20,
			snipeEnabled = CFG.snipeEnabled == true, snipeHop = CFG.snipeHop ~= false,
			snipeHopIndex = CFG.snipeHopIndex ~= false, snipeHopPlayer = CFG.snipeHopPlayer ~= false,
			snipeMinPop = CFG.snipeMinPop or 25, snipeRevisitSec = CFG.snipeRevisitSec or 120,
			webhookEnabled = CFG.webhookEnabled == true, webhookUrl = CFG.webhookUrl or "",
			profiles = CFG.profiles, snipeProfiles = CFG.snipeProfiles,
		}
	end

	local lastApplied = nil            -- string serialize terakhir yg udah sinkron
	local ready = false                -- true setelah PULL pertama (web=master) selesai
	local origPersist = ctx.persistState

	-- PUT config ke web (script -> web). Set baseline biar poll balik ga apply ulang.
	local function pushConfigNow()
		if not httpReq or not (LP and LP.UserId) then return end
		local snap = snapshot()
		lastApplied = serialize(snap)
		task.spawn(function()
			pcall(function()
				httpReq({
					Url = WEB_BASE .. "/api/config/" .. tostring(LP.UserId),
					Method = "PUT",
					Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = API_KEY },
					Body = HttpService:JSONEncode(snap),
				})
			end)
		end)
	end

	-- Debounce push (kumpulin perubahan beruntun jadi 1 PUT).
	local pushPending = false
	local function schedulePush()
		if pushPending then return end
		pushPending = true
		task.spawn(function()
			task.wait(1.5)
			pushPending = false
			pushConfigNow()
		end)
	end

	-- Bungkus persistState: tiap perubahan in-game -> simpan file + auto push ke web.
	ctx.persistState = function(...)
		origPersist(...)
		-- Cuma push kalau: bukan lagi apply dari web (hindari gema) DAN sudah pull awal
		-- (cegah config lokal stale ke-push pas boot sebelum web di-apply).
		if not ctx.__websyncApplying and ready then schedulePush() end
	end

	-- Salin isi SelSet (pets/muts) ke tabel tujuan IN-PLACE (clear lalu copy), JANGAN ganti
	-- referensi tabelnya. Dropdown GUI & loop listing pegang referensi tabel yg sama —
	-- kalau di-replace, mereka baca tabel lama (mutasi/pet ga ke-sync).
	local function copyInto(dst, src)
		if type(dst) ~= "table" then return end
		for k in pairs(dst) do dst[k] = nil end
		if type(src) == "table" then for k, v in pairs(src) do dst[k] = v end end
	end

	-- Terapkan nested (profiles / snipeProfiles) dari web ke CFG in-place.
	local function applyProfiles(w)
		local CFG = ctx.CFG
		if type(w.profiles) == "table" then
			for i = 1, (ctx.NUM_PROFILES or 3) do
				local sp = w.profiles[i] or w.profiles[tostring(i)]
				if type(sp) == "table" and type(sp.listings) == "table" then
					for j = 1, (ctx.NUM_LISTINGS or 3) do
						local sl = sp.listings[j] or sp.listings[tostring(j)]
						local dst = CFG.profiles[i] and CFG.profiles[i].listings[j]
						if type(sl) == "table" and dst then
							copyInto(dst.pets, sl.pets)
							copyInto(dst.muts, sl.muts)
							dst.minW    = tonumber(sl.minW) or 0
							dst.maxW    = tonumber(sl.maxW) or 0
							dst.maxList = tonumber(sl.maxList) or 0
							dst.price   = tonumber(sl.price) or 100
						end
					end
				end
			end
		end
		if type(w.snipeProfiles) == "table" then
			for i = 1, (ctx.NUM_SNIPE or 5) do
				local sp = w.snipeProfiles[i] or w.snipeProfiles[tostring(i)]
				local dst = CFG.snipeProfiles[i]
				if type(sp) == "table" and dst then
					copyInto(dst.pets, sp.pets)
					copyInto(dst.muts, sp.muts)
					dst.maxPrice = tonumber(sp.maxPrice) or 0
				end
			end
		end
	end

	-- Apply config dari web (web -> script) + start/stop automation yg toggle-nya berubah.
	local function applyWebConfig(w)
		local CFG = ctx.CFG
		local old = {
			autoSell = CFG.autoSell, relocate = CFG.relocateEnabled,
			snipe = CFG.snipeEnabled, skin = CFG.boothSkin,
		}

		if w.autoSell ~= nil then CFG.autoSell = w.autoSell == true end
		if w.autoClaim ~= nil then CFG.autoClaim = w.autoClaim == true end
		if w.autoSwitchPortal ~= nil then CFG.autoSwitchPortal = w.autoSwitchPortal == true end
		if w.autoReconnect ~= nil then CFG.autoReconnect = w.autoReconnect == true end
		if w.boothSkin ~= nil then CFG.boothSkin = tostring(w.boothSkin) end
		if w.relocateEnabled ~= nil then CFG.relocateEnabled = w.relocateEnabled == true end
		if w.relocateIdleMin ~= nil then CFG.relocateIdleMin = tonumber(w.relocateIdleMin) or CFG.relocateIdleMin end
		if w.relocateMinPlayers ~= nil then CFG.relocateMinPlayers = tonumber(w.relocateMinPlayers) or CFG.relocateMinPlayers end
		if w.relocatePreferred ~= nil then CFG.relocatePreferred = tonumber(w.relocatePreferred) or CFG.relocatePreferred end
		if w.snipeEnabled ~= nil then CFG.snipeEnabled = w.snipeEnabled == true end
		if w.snipeHop ~= nil then CFG.snipeHop = w.snipeHop == true end
		if w.snipeHopIndex ~= nil then CFG.snipeHopIndex = w.snipeHopIndex == true end
		if w.snipeHopPlayer ~= nil then CFG.snipeHopPlayer = w.snipeHopPlayer == true end
		if w.snipeMinPop ~= nil then CFG.snipeMinPop = tonumber(w.snipeMinPop) or CFG.snipeMinPop end
		if w.snipeRevisitSec ~= nil then CFG.snipeRevisitSec = tonumber(w.snipeRevisitSec) or CFG.snipeRevisitSec end
		if w.webhookEnabled ~= nil then CFG.webhookEnabled = w.webhookEnabled == true end
		if w.webhookUrl ~= nil then CFG.webhookUrl = tostring(w.webhookUrl) end
		applyProfiles(w)

		-- simpan ke file TANPA memicu push balik (hindari gema)
		ctx.__websyncApplying = true
		pcall(function() origPersist() end)
		ctx.__websyncApplying = false

		-- reconcile automation berdasar transisi toggle
		if old.autoSell ~= CFG.autoSell then
			if CFG.autoSell then
				if not ctx.state.running then ctx.state.running = true; task.spawn(ctx.mainLoop) end
			else
				ctx.state.running = false
			end
			if ctx.setStatus then ctx.setStatus(CFG.autoSell and "active" or "idle") end
		end
		if old.relocate ~= CFG.relocateEnabled then
			if CFG.relocateEnabled then if ctx.startRelocate then ctx.startRelocate() end
			else if ctx.stopRelocate then ctx.stopRelocate() end end
		end
		if old.snipe ~= CFG.snipeEnabled then
			if CFG.snipeEnabled then if ctx.startSnipe then ctx.startSnipe() end
			else if ctx.stopSnipe then ctx.stopSnipe() end end
			if ctx.refreshSnipeStatus then pcall(ctx.refreshSnipeStatus) end
		end
		if old.skin ~= CFG.boothSkin then
			pcall(function() if ctx.deps.EquipSkin then ctx.deps.EquipSkin:FireServer(CFG.boothSkin) end end)
		end

		-- re-render tampilan GUI (kalau hub kebuka): toggle + input/dropdown
		if ctx.state.toggleRenders then
			for _, r in ipairs(ctx.state.toggleRenders) do pcall(r) end
		end
		if ctx.state.uiRefreshers then
			for _, r in ipairs(ctx.state.uiRefreshers) do pcall(r) end
		end
		-- (log "Config di-sync" dihapus biar console ga spam)
	end

	-- Satu kali poll: GET config, apply kalau beda dari baseline.
	local function pollOnce()
		if not httpReq or not (LP and LP.UserId) then return end
		local res
		pcall(function()
			res = httpReq({
				Url = WEB_BASE .. "/api/config/" .. tostring(LP.UserId),
				Method = "GET",
				Headers = { ["x-api-key"] = API_KEY },
			})
		end)
		if not (res and res.Body) then return end
		local ok, j = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if not (ok and type(j) == "table" and j.ok and type(j.config) == "table") then return end
		local webStr = serialize(j.config)
		if webStr ~= lastApplied then
			applyWebConfig(j.config)
			lastApplied = serialize(snapshot())
		end
	end

	----------------------------------------------------------------- STEP 3: commands
	-- Eksekusi 1 aksi dari web. Handler-nya udah ada di app trade.
	local function runAction(action)
		if action == "unlistAll" then
			if ctx.unlistAll then pcall(ctx.unlistAll) end
		elseif action == "unclaimBooth" then
			pcall(function() if ctx.deps.RemoveBooth then ctx.deps.RemoveBooth:FireServer() end end)
		elseif action == "relocateNow" then
			if ctx.relocateNow then pcall(ctx.relocateNow) end
		else
			return
		end
		if ctx.log then pcall(function() ctx.log("Command dari web: " .. tostring(action)) end) end
	end

	-- Ambil antrian command (GET = baca + buang di server) lalu jalankan berurutan.
	local function pollCommands()
		if not httpReq or not (LP and LP.UserId) then return end
		local res
		pcall(function()
			res = httpReq({
				Url = WEB_BASE .. "/api/command/" .. tostring(LP.UserId),
				Method = "GET",
				Headers = { ["x-api-key"] = API_KEY },
			})
		end)
		if not (res and res.Body) then return end
		local ok, j = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if not (ok and type(j) == "table" and j.ok and type(j.commands) == "table") then return end
		for _, cmd in ipairs(j.commands) do
			if type(cmd) == "table" and cmd.action then runAction(cmd.action) end
		end
	end

	-- Gabungan config+command dalam 1 request (GET /api/sync) — hemat invocation Vercel.
	local function pollSync()
		if not httpReq or not (LP and LP.UserId) then return end
		local res
		pcall(function()
			res = httpReq({
				Url = WEB_BASE .. "/api/sync/" .. tostring(LP.UserId),
				Method = "GET",
				Headers = { ["x-api-key"] = API_KEY },
			})
		end)
		if not (res and res.Body) then return end
		local ok, j = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if not (ok and type(j) == "table" and j.ok) then return end
		if type(j.config) == "table" then
			local webStr = serialize(j.config)
			if webStr ~= lastApplied then
				applyWebConfig(j.config)
				lastApplied = serialize(snapshot())
			end
		end
		if type(j.commands) == "table" then
			for _, cmd in ipairs(j.commands) do
				if type(cmd) == "table" and cmd.action then runAction(cmd.action) end
			end
		end
	end

	----------------------------------------------------------------- boot
	ctx.state.webSyncReady = false
	task.spawn(function()
		-- WEB = MASTER. PULL config PALING AWAL (sebelum automation auto-resume/hop), biar
		-- setting web (mis. snipe=off) ke-apply duluan. Auto-resume snipe nungguin flag ini.
		task.wait(0.5)
		pcall(pollSync)
		ready = true                  -- mulai sekarang, perubahan GUI in-game boleh push ke web
		ctx.state.webSyncReady = true -- sinyal ke auto-resume: config web udah ke-apply
		ctx.webPushOptions()          -- options nyusul (ga urgent buat dropdown web)
		while ctx.alive() and Players.LocalPlayer == LP do
			task.wait(POLL_EVERY)
			pcall(pollSync)           -- config + command sekaligus
		end
	end)
end
]=],
	["modules/sell/booth.lua"] = [=[
--[[ booth.lua — logika booth: kepemilikan, claim terdekat, pindah dekat portal, token.
     Mengisi: ctx.getTokens, ctx.myPlayerId, ctx.weightOf,
              ctx.ownsBooth, ctx.tryClaimNearest, ctx.ensureBooth,
              ctx.autoSwitchBoothPortal ]]
return function(ctx)
	local LP                = ctx.LP
	local CollectionService = ctx.Services.CollectionService
	local RR                = ctx.deps.RR
	local DataService       = ctx.deps.DataService
	local TradeBoothsData   = ctx.deps.TradeBoothsData
	local ClaimBooth        = ctx.deps.ClaimBooth
	local RemoveBooth       = ctx.deps.RemoveBooth
	local CFG               = ctx.CFG
	local function log(msg) ctx.log(msg) end

	local function getTokens()
		local ok, data = pcall(function() return DataService:GetData() end)
		if ok and type(data) == "table" and type(data.TradeData) == "table" then
			return data.TradeData.Tokens or 0
		end
		return 0
	end

	local function myPlayerId() return TradeBoothsData.getPlayerId(LP) end

	local function weightOf(petType, pd)
		return pd.BaseWeight or 0
	end

	local function ownsBooth()
		local ok, data = pcall(function() return RR.new("Booths"):GetDataAsync() end)
		if not ok or not data then return false, nil, nil end
		local id = myPlayerId()
		local playerRecord = data.Players and data.Players[id]
		local boothName = playerRecord and playerRecord.Booth
		return boothName ~= nil, data, boothName
	end

	local function tryClaimNearest()
		local owns, data = ownsBooth()
		if owns then return true end
		if not data then return false end
		local charPos
		local char = LP.Character
		if char and char:FindFirstChild("HumanoidRootPart") then charPos = char.HumanoidRootPart.Position end
		local list = {}
		for _, inst in ipairs(CollectionService:GetTagged("TradeBooth")) do
			local b = data.Booths and data.Booths[inst.Name]
			if (b == nil) or (b.Owner == nil) then
				local dist = 999999
				if charPos then
					local ok2, piv = pcall(function() return inst:GetPivot().Position end)
					if ok2 then dist = (piv - charPos).Magnitude end
				end
				list[#list + 1] = { inst = inst, dist = dist }
			end
		end
		if #list == 0 then log("Tidak ada booth kosong."); return false end
		table.sort(list, function(a, b) return a.dist < b.dist end)
		local pick = list[1]

		if char and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = pick.inst:GetPivot() * CFrame.new(0, 3, 3)
			task.wait(0.25)
		end

		pcall(function() ClaimBooth:FireServer(pick.inst) end)
		log(("Claim booth terdekat (%dstud, %d kosong)..."):format(math.floor(pick.dist), #list))
		return false
	end

	local function ensureBooth()
		local owns = ownsBooth()
		if owns then return true end
		if CFG.autoClaim then return tryClaimNearest() end
		return false
	end

	-- Auto Switch to Booth Near Portal
	local function autoSwitchBoothPortal()
		if not CFG.autoSwitchPortal then return end
		local owns, data, boothName = ownsBooth()
		if not owns or not data or not boothName then return end
		-- Cari portal Trade World (bukan lobby)
		local tradeWorld = workspace:FindFirstChild("TradeWorld")
		local portal = nil
		if tradeWorld then
			local pp = tradeWorld:FindFirstChild("PortalPetePlatform")
			if pp then portal = pp:FindFirstChild("Portal") or pp end
			if not portal then portal = tradeWorld:FindFirstChild("Portal Pete", true) end
		end
		if not portal then
			portal = workspace:FindFirstChild("Portal Pete", true) or workspace:FindFirstChild("Portal", true)
		end
		local portalPos = portal and portal:GetPivot().Position or Vector3.new(0, 0, 0)

		local myBoothInst = nil
		for _, inst in ipairs(CollectionService:GetTagged("TradeBooth")) do
			if inst.Name == boothName then myBoothInst = inst; break end
		end
		if not myBoothInst then return end

		local myDist = (myBoothInst:GetPivot().Position - portalPos).Magnitude
		local bestBooth = nil
		local bestDist = myDist

		for _, inst in ipairs(CollectionService:GetTagged("TradeBooth")) do
			local b = data.Booths and data.Booths[inst.Name]
			if (b == nil) or (b.Owner == nil) then
				local pDist = (inst:GetPivot().Position - portalPos).Magnitude
				if pDist < bestDist - 8 then -- harus lebih dekat minimal 8 stud agar worth-it pindah
					bestDist = pDist
					bestBooth = inst
				end
			end
		end

		if bestBooth then
			log(("Pindah ke booth lebih dekat portal (Lama: %dstud, Baru: %dstud)"):format(math.floor(myDist), math.floor(bestDist)))
			pcall(function() RemoveBooth:FireServer() end)
			task.wait(0.5)

			local char = LP.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				char.HumanoidRootPart.CFrame = bestBooth:GetPivot() * CFrame.new(0, 3, 3)
				task.wait(0.25)
			end

			pcall(function() ClaimBooth:FireServer(bestBooth) end)
		end
	end

	ctx.getTokens             = getTokens
	ctx.myPlayerId            = myPlayerId
	ctx.weightOf              = weightOf
	ctx.ownsBooth             = ownsBooth
	ctx.tryClaimNearest       = tryClaimNearest
	ctx.ensureBooth           = ensureBooth
	ctx.autoSwitchBoothPortal = autoSwitchBoothPortal
end
]=],
	["modules/sell/listing.lua"] = [=[
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
]=],
	["modules/sell/relocate.lua"] = [=[
--[[ relocate.lua — Automation Relocate Sell (Trade World).
     Pindah server otomatis kalau booth idle (ga ada pembeli sekian menit) ATAU
     server terlalu sepi, ke server yang jumlah pemainnya paling dekat dengan
     'Preferred Lobby Size'. Timer idle di-reset tiap ada transaksi jual sukses.
       - Idle Timeout (menit)  -> pindah kalau ga ada pembeli sekian lama
       - Min Player Threshold  -> pindah kalau pemain < ambang (0 = mati)
       - Preferred Lobby Size  -> cari server dengan pemain paling dekat angka ini
     Mengisi: ctx.relocateNow, ctx.startRelocate, ctx.stopRelocate ]]
return function(ctx)
	local TeleportService = game:GetService("TeleportService")
	local Players     = ctx.Services.Players or game:GetService("Players")
	local HttpService = ctx.Services.HttpService
	local LP          = ctx.LP
	local CFG         = ctx.CFG
	local AddToHistory = ctx.deps.AddToHistory
	local function log(m) ctx.log(m) end
	local function setStatus(s) ctx.setStatus(s) end

	local ROUTER = "loadstring(game:HttpGet('https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/init.lua'))()"

	-- waktu jual terakhir; reset tiap ada yang beli dari kita -> penanda booth aktif.
	ctx.state.lastSaleAt = os.time()
	local loadedAt = os.time()

	-- listener transaksi (independen dari webhook) buat reset timer idle.
	pcall(function()
		AddToHistory.OnClientEvent:Connect(function(tx)
			if type(tx) ~= "table" or not tx.seller then return end
			local myId = ctx.myPlayerId and ctx.myPlayerId()
			local isSeller = (myId and myId == tx.seller.userId) or (LP.UserId == tx.seller.userId)
			local isSuccess = tx.status and tx.status.result ~= "Failed"
			if isSeller and isSuccess then ctx.state.lastSaleAt = os.time() end
		end)
	end)

	-- queue hub biar auto-load lagi setelah landing di server baru.
	local function queueHub()
		local q = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
		if q then pcall(function() q(ROUTER) end) end
	end

	-- daftar server publik. game:HttpGet ke roblox.com diblok Roblox, jadi pakai
	-- fungsi request executor (bisa hit games.roblox.com).
	local function fetchServers()
		local reqFn = (syn and syn.request) or (http and http.request) or http_request or request
		if not reqFn then return nil end
		local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100"):format(game.PlaceId)
		local ok, res = pcall(reqFn, { Url = url, Method = "GET" })
		if not ok or not res or not res.Body then return nil end
		local ok2, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if not ok2 or type(data) ~= "table" or type(data.data) ~= "table" then return nil end
		return data.data
	end

	-- pilih server: ada slot kosong, bukan server ini, 'playing' paling dekat preferred.
	local function pickServer(preferred)
		local servers = fetchServers()
		if not servers then return nil end
		local best, bestDiff
		for _, s in ipairs(servers) do
			local playing = tonumber(s.playing) or 0
			local maxp = tonumber(s.maxPlayers) or 30
			if s.id ~= game.JobId and playing < maxp then
				local diff = math.abs(playing - preferred)
				if not bestDiff or diff < bestDiff then best, bestDiff = s, diff end
			end
		end
		return best
	end

	local function doRelocate(reason)
		local preferred = math.max(1, math.floor(tonumber(CFG.relocatePreferred) or 20))
		_G.__AH_reloActive = true -- tandai lagi proses pindah (buat retry handler)
		setStatus("Relocate: " .. reason .. " -> cari server...")
		log("Relocate: " .. reason)
		queueHub()
		local target = pickServer(preferred)
		if target and target.id then
			log(("Pindah ke server (%d/%d pemain)"):format(tonumber(target.playing) or 0, tonumber(target.maxPlayers) or 30))
			pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, target.id, LP) end)
		else
			log("List server gagal/kosong -> teleport acak.")
			pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
		end
	end
	function ctx.relocateNow() task.spawn(function() doRelocate("manual") end) end

	-- Handle gagal teleport: retry otomatis (Flooded=20s, gagal lain=6s).
	-- Semua kondisi (idle/sepi/manual) lewat doRelocate yang sama, jadi ke-cover.
	-- Guard _G biar ga double-connect walau hub ke-load ulang.
	if not _G.__AH_reloTpHandler then
		_G.__AH_reloTpHandler = true
		pcall(function()
			TeleportService.TeleportInitFailed:Connect(function(_, result)
				if not CFG.relocateEnabled or not _G.__AH_reloActive then return end
				local wait = (result == Enum.TeleportResult.Flooded) and 20 or 6
				setStatus(("Relocate: teleport gagal (%s), retry %ds..."):format(tostring(result), wait))
				log(("Teleport gagal (%s), retry %ds..."):format(tostring(result), wait))
				task.wait(wait)
				if CFG.relocateEnabled and _G.__AH_reloActive then doRelocate("retry") end
			end)
		end)
	end

	local function loop()
		ctx.state.relocateId = (ctx.state.relocateId or 0) + 1
		local myId = ctx.state.relocateId
		ctx.elevate()
		task.wait(15) -- grace: tunggu server settle + data pemain kebaca dulu
		while CFG.relocateEnabled and ctx.alive() and ctx.state.relocateId == myId do
			local players = #Players:GetPlayers()
			local idleFor = os.time() - (ctx.state.lastSaleAt or loadedAt)
			local idleLimit = math.max(1, math.floor(tonumber(CFG.relocateIdleMin) or 20)) * 60
			local minPlayers = math.floor(tonumber(CFG.relocateMinPlayers) or 0)

			if minPlayers > 0 and players < minPlayers then
				doRelocate(("server sepi (%d<%d)"):format(players, minPlayers))
				return
			elseif idleFor >= idleLimit then
				doRelocate(("idle %d menit tanpa pembeli"):format(math.floor(idleFor / 60)))
				return
			else
				local remain = math.max(0, idleLimit - idleFor)
				setStatus(("Relocate ON | idle %02d:%02d | pemain %d"):format(math.floor(remain / 60), remain % 60, players))
			end
			task.wait(5)
		end
	end

	function ctx.startRelocate()
		ctx.state.lastSaleAt = os.time()
		task.spawn(loop)
	end
	function ctx.stopRelocate()
		ctx.state.relocateId = (ctx.state.relocateId or 0) + 1
		_G.__AH_reloActive = false -- batalkan retry yang mungkin tertunda
		setStatus("Relocate: dimatikan")
	end

	-- auto-resume kalau sebelumnya aktif (mis. baru landing dari hop).
	if CFG.relocateEnabled then task.spawn(ctx.startRelocate) end
end
]=],
	["ui/components.lua"] = [=[
--[[ components.lua — kontrol UI trade PINK ROYALE:
     Ukuran font besar & sangat jelas dibaca, dropdown lapang (mudah memilih opsi & pet),
     toggle pill modern, input box dengan focus glow, accordion ber-aksen bar. ]]
return function(ctx)
	local TS = game:GetService("TweenService")
	local C  = ctx.C
	local F  = ctx.F
	local mk, corner, stroke, pad, grad = ctx.mk, ctx.corner, ctx.stroke, ctx.pad, ctx.grad

	local function labels(parent, title, desc, rightPad)
		local txts = mk("Frame", {
			Size = UDim2.new(1, -(rightPad or 160), 1, 0),
			BackgroundTransparency = 1,
		}, parent)
		pad(txts, 4, 0, 0, 0)

		local tLbl = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, desc and 4 or 16),
			BackgroundTransparency = 1,
			Text = title,
			Font = F.bold,
			TextSize = 16.5,
			TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, txts)

		if desc and desc ~= "" then
			local dLbl = mk("TextLabel", {
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.fromOffset(0, 30),
				BackgroundTransparency = 1,
				Text = desc,
				Font = F.reg,
				TextSize = 13.5,
				TextColor3 = C.sub,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, txts)
		end
	end

	----------------------------------------------------------------- Modern Toggle Pill
	local function makeToggle(parent, title, desc, getv, setv, order)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		labels(row, title, desc, 80)

		local pill = mk("TextButton", {
			Size = UDim2.fromOffset(48, 26),
			Position = UDim2.new(1, -56, 0.5, -13),
			BackgroundColor3 = C.rowAlt,
			Text = "",
			AutoButtonColor = false,
		}, row)
		corner(pill, 13)
		local pStroke = stroke(pill, C.strokeSub, 1.2, 0.5)

		local thumb = mk("Frame", {
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.fromOffset(3, 3),
			BackgroundColor3 = C.sub,
			BorderSizePixel = 0,
		}, pill)
		corner(thumb, 10)

		local function update(state, anim)
			local dur = anim and 0.22 or 0
			if state then
				TS:Create(pill, TweenInfo.new(dur), { BackgroundColor3 = C.acc }):Play()
				TS:Create(pStroke, TweenInfo.new(dur), { Color = C.accSoft, Transparency = 0.2 }):Play()
				TS:Create(thumb, TweenInfo.new(dur, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.fromOffset(25, 3),
					BackgroundColor3 = Color3.new(1, 1, 1),
				}):Play()
			else
				TS:Create(pill, TweenInfo.new(dur), { BackgroundColor3 = C.rowAlt }):Play()
				TS:Create(pStroke, TweenInfo.new(dur), { Color = C.strokeSub, Transparency = 0.5 }):Play()
				TS:Create(thumb, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromOffset(3, 3),
					BackgroundColor3 = C.sub,
				}):Play()
			end
		end

		local on = getv()
		update(on, false)

		pill.MouseButton1Click:Connect(function()
			on = not on
			setv(on)
			update(on, true)
		end)

		ctx.state.uiRefreshers = ctx.state.uiRefreshers or {}
		table.insert(ctx.state.uiRefreshers, function()
			local cur = getv()
			if cur ~= on then on = cur; update(on, false) end
		end)

		return pill
	end

	----------------------------------------------------------------- Input Box (Focus Glow)
	local function makeInput(parent, title, desc, getv, setv, order)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		labels(row, title, desc, 130)

		local boxFrame = mk("Frame", {
			Size = UDim2.fromOffset(120, 36),
			Position = UDim2.new(1, -126, 0.5, -18),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
		}, row)
		corner(boxFrame, 8)
		local bStroke = stroke(boxFrame, C.strokeSub, 1, 0.4)

		local box = mk("TextBox", {
			Size = UDim2.new(1, -16, 1, 0),
			Position = UDim2.fromOffset(9, 0),
			BackgroundTransparency = 1,
			Text = tostring(getv()),
			Font = F.bold,
			TextSize = 14,
			TextColor3 = C.txt,
			PlaceholderColor3 = C.sub,
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, boxFrame)

		box.Focused:Connect(function()
			TS:Create(bStroke, TweenInfo.new(0.2), { Color = C.acc, Transparency = 0 }):Play()
			TS:Create(boxFrame, TweenInfo.new(0.2), { BackgroundColor3 = C.rowAlt }):Play()
		end)
		box.FocusLost:Connect(function()
			TS:Create(bStroke, TweenInfo.new(0.2), { Color = C.strokeSub, Transparency = 0.4 }):Play()
			TS:Create(boxFrame, TweenInfo.new(0.2), { BackgroundColor3 = C.panel }):Play()
			setv(box.Text)
			box.Text = tostring(getv())
		end)
		box:GetPropertyChangedSignal("Text"):Connect(function()
			setv(box.Text)
		end)

		ctx.state.uiRefreshers = ctx.state.uiRefreshers or {}
		table.insert(ctx.state.uiRefreshers, function() box.Text = tostring(getv()) end)

		return box
	end

	----------------------------------------------------------------- Multi Dropdown (Lapang & Jelas)
	local function makeDropdown(parent, title, desc, options, selSet, onChange, order)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, row)

		local head = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 1,
		}, row)
		labels(head, title, desc, 250)

		local pillBadge = mk("Frame", {
			Size = UDim2.fromOffset(230, 40),
			Position = UDim2.new(1, -236, 0.5, -20),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
		}, head)
		corner(pillBadge, 10)
		stroke(pillBadge, C.strokeSub, 1.2, 0.5)
		pad(pillBadge, 12, 10, 0, 0)

		local valLbl = mk("TextLabel", {
			Size = UDim2.new(1, -26, 1, 0),
			BackgroundTransparency = 1,
			Text = "Pilih",
			Font = F.bold,
			TextSize = 14.5,
			TextColor3 = C.sub,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, pillBadge)

		local chevron = mk("TextLabel", {
			Size = UDim2.fromOffset(18, 18),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			BackgroundTransparency = 1,
			Text = "▼",
			Font = F.bold,
			TextSize = 13,
			TextColor3 = C.acc,
		}, pillBadge)

		local function updateSummary()
			local sel = {}
			for _, o in ipairs(options) do
				if selSet[o] then sel[#sel + 1] = o end
			end
			if #sel == 0 then
				valLbl.Text = "Pilih"
				valLbl.TextColor3 = C.sub
			else
				local txt = table.concat(sel, ", ")
				if #txt > 20 then txt = (#sel) .. " dipilih ✦" end
				valLbl.Text = txt
				valLbl.TextColor3 = C.accSoft
			end
		end

		local listFrame = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 250),
			BackgroundColor3 = C.panel,
			Visible = false,
			LayoutOrder = 2,
		}, row)
		corner(listFrame, 10)
		stroke(listFrame, C.stroke, 1.4, 0.3)

		local searchBox = mk("TextBox", {
			Size = UDim2.new(1, -16, 0, 36),
			Position = UDim2.fromOffset(8, 8),
			BackgroundColor3 = C.row,
			PlaceholderText = "🔍 Cari opsi...",
			PlaceholderColor3 = C.sub,
			Text = "",
			Font = F.bold,
			TextSize = 14,
			TextColor3 = C.txt,
			ClearTextOnFocus = false,
		}, listFrame)
		corner(searchBox, 8)
		stroke(searchBox, C.strokeSub, 1, 0.5)
		pad(searchBox, 12, 8, 0, 0)

		local scroll = mk("ScrollingFrame", {
			Size = UDim2.new(1, -16, 1, -54),
			Position = UDim2.fromOffset(8, 50),
			BackgroundTransparency = 1,
			ScrollBarThickness = 5,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = "Y",
			ScrollBarImageColor3 = C.acc,
		}, listFrame)
		mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

		local built = false
		local optBtns = {}

		local function reorder()
			local i = 0
			for _, opt in ipairs(options) do
				if selSet[opt] and optBtns[opt] then i = i + 1; optBtns[opt].LayoutOrder = i end
			end
			for _, opt in ipairs(options) do
				if not selSet[opt] and optBtns[opt] then i = i + 1; optBtns[opt].LayoutOrder = i end
			end
		end

		local function build()
			if built then return end; built = true
			for _, opt in ipairs(options) do
				local ob = mk("TextButton", {
					Size = UDim2.new(1, 0, 0, 38),
					BackgroundColor3 = C.row,
					Text = "      " .. opt,
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = F.semi,
					TextSize = 14,
					TextColor3 = C.txt,
					AutoButtonColor = false,
				}, scroll)
				corner(ob, 8)
				local obStroke = stroke(ob, C.strokeSub, 1, 0.7)

				local checkBadge = mk("TextLabel", {
					Size = UDim2.fromOffset(20, 24),
					Position = UDim2.new(1, -22, 0.5, -12),
					BackgroundTransparency = 1,
					Text = "",
					Font = F.bold,
					TextSize = 12,
					TextColor3 = C.green,
				}, ob)

				local function rend()
					local isSel = selSet[opt] == true
					checkBadge.Text = isSel and "✓" or ""
					ob.BackgroundColor3 = isSel and C.rowAlt or C.row
					ob.TextColor3 = isSel and C.accSoft or C.txt
					ob.Font = isSel and F.bold or F.semi
					obStroke.Color = isSel and C.acc or C.strokeSub
					obStroke.Transparency = isSel and 0.3 or 0.7
				end

				ob.MouseEnter:Connect(function()
					if not selSet[opt] then ob.BackgroundColor3 = C.rowHover end
				end)
				ob.MouseLeave:Connect(function()
					if not selSet[opt] then ob.BackgroundColor3 = C.row end
				end)

				ob.MouseButton1Click:Connect(function()
					if selSet[opt] then selSet[opt] = nil else selSet[opt] = true end
					rend(); updateSummary(); reorder(); if onChange then onChange() end
				end)

				rend()
				optBtns[opt] = ob
			end
			reorder()
		end

		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local q = searchBox.Text:lower()
			for opt, ob in pairs(optBtns) do
				ob.Visible = (q == "" or opt:lower():find(q, 1, true) ~= nil)
			end
		end)

		head.MouseButton1Click:Connect(function()
			if not built then build() end
			listFrame.Visible = not listFrame.Visible
			chevron.Text = listFrame.Visible and "▲" or "▼"
			if listFrame.Visible then reorder() end
		end)

		updateSummary()
		return updateSummary
	end

	----------------------------------------------------------------- Single Dropdown (Lapang & Jelas)
	local function makeSingleDropdown(parent, title, desc, options, getv, setv, order)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, row)

		local head = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 1,
		}, row)
		labels(head, title, desc, 250)

		local pillBadge = mk("Frame", {
			Size = UDim2.fromOffset(230, 40),
			Position = UDim2.new(1, -236, 0.5, -20),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
		}, head)
		corner(pillBadge, 10)
		stroke(pillBadge, C.strokeSub, 1.2, 0.5)
		pad(pillBadge, 12, 10, 0, 0)

		local valLbl = mk("TextLabel", {
			Size = UDim2.new(1, -26, 1, 0),
			BackgroundTransparency = 1,
			Text = getv() ~= "" and getv() or "Pilih Opsi",
			Font = F.bold,
			TextSize = 14.5,
			TextColor3 = C.accSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, pillBadge)

		local chevron = mk("TextLabel", {
			Size = UDim2.fromOffset(18, 18),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			BackgroundTransparency = 1,
			Text = "▼",
			Font = F.bold,
			TextSize = 13,
			TextColor3 = C.acc,
		}, pillBadge)

		local listFrame = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 250),
			BackgroundColor3 = C.panel,
			Visible = false,
			LayoutOrder = 2,
		}, row)
		corner(listFrame, 10)
		stroke(listFrame, C.stroke, 1.4, 0.3)

		local searchBox = mk("TextBox", {
			Size = UDim2.new(1, -16, 0, 36),
			Position = UDim2.fromOffset(8, 8),
			BackgroundColor3 = C.row,
			PlaceholderText = "🔍 Cari opsi...",
			PlaceholderColor3 = C.sub,
			Text = "",
			Font = F.bold,
			TextSize = 14,
			TextColor3 = C.txt,
			ClearTextOnFocus = false,
		}, listFrame)
		corner(searchBox, 8)
		stroke(searchBox, C.strokeSub, 1, 0.5)
		pad(searchBox, 12, 8, 0, 0)

		local scroll = mk("ScrollingFrame", {
			Size = UDim2.new(1, -16, 1, -52),
			Position = UDim2.fromOffset(8, 48),
			BackgroundTransparency = 1,
			ScrollBarThickness = 4,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = "Y",
			ScrollBarImageColor3 = C.acc,
		}, listFrame)
		mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

		local optBtns = {}
		local function rebuild()
			for _, b in pairs(optBtns) do b:Destroy() end
			optBtns = {}
			local cur = getv()
			local raw = options or {}
			local ordered, rest = {}, {}
			for _, opt in ipairs(raw) do
				local display = type(opt) == "table" and opt.display or opt
				local code    = type(opt) == "table" and opt.name or opt
				if display == cur or code == cur then ordered[#ordered + 1] = opt else rest[#rest + 1] = opt end
			end
			for _, opt in ipairs(rest) do ordered[#ordered + 1] = opt end

			for _, opt in ipairs(ordered) do
				local display = type(opt) == "table" and opt.display or opt
				local code    = type(opt) == "table" and opt.name or opt
				local isSel   = (display == cur or code == cur)

				local ob = mk("TextButton", {
					Size = UDim2.new(1, 0, 0, 34),
					BackgroundColor3 = isSel and C.rowAlt or C.row,
					Text = (isSel and "   ✓  " or "      ") .. display,
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = isSel and F.bold or F.semi,
					TextSize = 13,
					TextColor3 = isSel and C.accSoft or C.txt,
					AutoButtonColor = false,
				}, scroll)
				corner(ob, 7)
				stroke(ob, isSel and C.acc or C.strokeSub, 1, isSel and 0.2 or 0.7)

				ob.MouseEnter:Connect(function()
					if not isSel then ob.BackgroundColor3 = C.rowHover end
				end)
				ob.MouseLeave:Connect(function()
					if not isSel then ob.BackgroundColor3 = C.row end
				end)

				ob.MouseButton1Click:Connect(function()
					setv(code)
					valLbl.Text = display
					listFrame.Visible = false
					chevron.Text = "▼"
				end)
				optBtns[#optBtns + 1] = ob
			end
		end

		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local q = searchBox.Text:lower()
			for _, ob in ipairs(optBtns) do
				ob.Visible = (q == "" or ob.Text:lower():find(q, 1, true) ~= nil)
			end
		end)

		head.MouseButton1Click:Connect(function()
			listFrame.Visible = not listFrame.Visible
			chevron.Text = listFrame.Visible and "▲" or "▼"
			if listFrame.Visible then rebuild() end
		end)

		return head
	end

	----------------------------------------------------------------- Button
	local function makeButton(parent, title, color, onClick, order)
		local base = color or C.acc
		local isRed = (color == C.red)

		local btn = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundColor3 = base,
			Text = title .. " ✦",
			Font = F.bold,
			TextSize = 14,
			TextColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = false,
			LayoutOrder = order,
		}, parent)
		corner(btn, 10)
		if not isRed then
			grad(btn, 0, C.acc, C.acc2)
		end
		stroke(btn, isRed and C.red or C.accSoft, 1.2, 0.3)

		btn.MouseEnter:Connect(function()
			TS:Create(btn, TweenInfo.new(0.15), { TextColor3 = Color3.fromRGB(255, 240, 255) }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TS:Create(btn, TweenInfo.new(0.15), { TextColor3 = Color3.new(1, 1, 1) }):Play()
		end)

		btn.MouseButton1Click:Connect(function()
			TS:Create(btn, TweenInfo.new(0.08), { Size = UDim2.new(1, -6, 0, 35) }):Play()
			task.delay(0.08, function()
				TS:Create(btn, TweenInfo.new(0.12), { Size = UDim2.new(1, 0, 0, 38) }):Play()
			end)
			if onClick then onClick() end
		end)

		return btn
	end

	----------------------------------------------------------------- Luxury Accordion
	local function makeAccordion(parent, title, order)
		local container = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.row,
			BorderSizePixel = 0,
			LayoutOrder = order,
			ClipsDescendants = false,
		}, parent)
		corner(container, 12)
		local cardStroke = stroke(container, C.strokeSub, 1.2, 0.4)
		mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 0) }, container)

		local head = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 1,
		}, container)
		corner(head, 12)
		pad(head, 14, 14, 0, 0)

		local accentBar = mk("Frame", {
			Size = UDim2.new(0, 5, 0, 28),
			Position = UDim2.new(0, 0, 0.5, -14),
			BackgroundColor3 = C.acc,
			BorderSizePixel = 0,
		}, head)
		corner(accentBar, 2)
		grad(accentBar, 90, C.acc, C.acc2)

		local titleLabel = mk("TextLabel", {
			Size = UDim2.new(1, -40, 1, 0),
			Position = UDim2.fromOffset(14, 0),
			BackgroundTransparency = 1,
			Text = title,
			Font = F.bold,
			TextSize = 17,
			TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, head)

		local chevron = mk("TextLabel", {
			Size = UDim2.fromOffset(20, 20),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			BackgroundTransparency = 1,
			Text = "▼",
			Font = F.bold,
			TextSize = 13,
			TextColor3 = C.acc,
		}, head)

		local line = mk("Frame", {
			Size = UDim2.new(1, -28, 0, 1),
			Position = UDim2.fromOffset(14, 0),
			BackgroundColor3 = C.strokeSub,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			LayoutOrder = 2,
			Visible = false,
		}, container)
		grad(line, 0, C.strokeSub, C.acc)

		local body = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Visible = false,
			LayoutOrder = 3,
		}, container)
		pad(body, 14, 14, 10, 14)
		mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, body)

		local open = false
		local function setOpen(v)
			open = v
			body.Visible = open
			line.Visible = open
			chevron.Text = open and "▲" or "▼"
			TS:Create(cardStroke, TweenInfo.new(0.2), {
				Color = open and C.stroke or C.strokeSub,
				Transparency = open and 0.1 or 0.4,
			}):Play()
		end

		head.MouseButton1Click:Connect(function() setOpen(not open) end)
		head.MouseEnter:Connect(function()
			TS:Create(titleLabel, TweenInfo.new(0.15), { TextColor3 = C.accSoft }):Play()
		end)
		head.MouseLeave:Connect(function()
			TS:Create(titleLabel, TweenInfo.new(0.15), { TextColor3 = C.txt }):Play()
		end)

		return body, setOpen, container
	end

	----------------------------------------------------------------- Page + Tab
	local function selectTab(name)
		local pages   = ctx.ui.pages
		local tabBtns = ctx.ui.tabBtns
		for n, p in pairs(pages) do p.Visible = (n == name) end
		for n, b in pairs(tabBtns) do
			local on = (n == name)
			if b.setActive then
				b.setActive(on)
			else
				TS:Create(b.btn, TweenInfo.new(0.18), { BackgroundTransparency = on and 0.2 or 1 }):Play()
				b.btn.TextColor3 = on and C.txt or C.sub
				b.line.Visible = on
			end
		end
	end
	ctx.selectTab = selectTab

	local function makePage(name, titleText, iconLabel, order)
		local tabButtonsFrame = ctx.ui.tabButtonsFrame
		local content         = ctx.ui.content
		local pages           = ctx.ui.pages
		local tabBtns         = ctx.ui.tabBtns

		local btn = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = C.row,
			BackgroundTransparency = 1,
			Text = "    " .. (iconLabel or "✦") .. "   " .. name,
			Font = F.bold,
			TextSize = 15,
			TextColor3 = C.sub,
			LayoutOrder = order,
			AutoButtonColor = false,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, tabButtonsFrame)
		corner(btn, 10)

		local line = mk("Frame", {
			Size = UDim2.new(0, 4, 0, 26),
			Position = UDim2.new(0, 4, 0.5, -13),
			BackgroundColor3 = C.acc,
			Visible = false,
			BorderSizePixel = 0,
		}, btn)
		corner(line, 2)
		grad(line, 90, C.acc, C.acc2)

		local function setActive(isActive)
			if isActive then
				TS:Create(btn, TweenInfo.new(0.18), {
					BackgroundTransparency = 0.15,
					BackgroundColor3 = C.rowAlt,
					TextColor3 = C.txt,
				}):Play()
				line.Visible = true
			else
				TS:Create(btn, TweenInfo.new(0.18), {
					BackgroundTransparency = 1,
					BackgroundColor3 = C.row,
					TextColor3 = C.sub,
				}):Play()
				line.Visible = false
			end
		end

		btn.MouseEnter:Connect(function()
			if not line.Visible then
				TS:Create(btn, TweenInfo.new(0.15), { BackgroundTransparency = 0.6, BackgroundColor3 = C.rowHover, TextColor3 = C.txt }):Play()
			end
		end)
		btn.MouseLeave:Connect(function()
			if not line.Visible then
				TS:Create(btn, TweenInfo.new(0.15), { BackgroundTransparency = 1, TextColor3 = C.sub }):Play()
			end
		end)

		tabBtns[name] = { btn = btn, line = line, setActive = setActive }

		local pg = mk("ScrollingFrame", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Visible = false,
			ScrollBarThickness = 4,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = "Y",
			ScrollBarImageColor3 = C.acc,
		}, content)
		pad(pg, 4, 10, 2, 10)
		mk("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, pg)
		pages[name] = pg

		local headerFrame = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 46),
			BackgroundTransparency = 1,
			LayoutOrder = 0,
		}, pg)

		local tTitle = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			Text = (iconLabel or "✦") .. "  " .. titleText,
			Font = F.title,
			TextSize = 26,
			TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, headerFrame)

		local underline = mk("Frame", {
			Size = UDim2.new(0, 65, 0, 3),
			Position = UDim2.new(0, 0, 1, -4),
			BackgroundColor3 = C.acc,
			BorderSizePixel = 0,
		}, headerFrame)
		corner(underline, 2)
		grad(underline, 0, C.acc, C.acc2)

		btn.MouseButton1Click:Connect(function() selectTab(name) end)
		return pg
	end

	ctx.makeToggle         = makeToggle
	ctx.makeInput          = makeInput
	ctx.makeDropdown       = makeDropdown
	ctx.makeSingleDropdown = makeSingleDropdown
	ctx.makeButton         = makeButton
	ctx.makeAccordion      = makeAccordion
	ctx.makePage           = makePage
end
]=],
	["ui/pages.lua"] = [=[
--[[ pages.lua — membangun halaman: Sell, Profile 1..N, Inventory, Misc.
     Mengisi: ctx.renderInventory, ctx.ui.logBox, ctx.ui.rAutoToggle ]]
return function(ctx)
	local LP  = ctx.LP
	local CFG = ctx.CFG
	local C   = ctx.C
	local F   = ctx.F
	local mk, corner, stroke, pad = ctx.mk, ctx.corner, ctx.stroke, ctx.pad
	local NUM_PROFILES = ctx.NUM_PROFILES
	local NUM_LISTINGS = ctx.NUM_LISTINGS
	local NUM_SNIPE    = ctx.NUM_SNIPE
	local reg          = ctx.reg
	local persistState = ctx.persistState
	local EquipSkin    = ctx.deps.EquipSkin
	local RemoveBooth  = ctx.deps.RemoveBooth
	local function log(msg) ctx.log(msg) end

	local makePage           = ctx.makePage
	local makeAccordion      = ctx.makeAccordion
	local makeSingleDropdown = ctx.makeSingleDropdown
	local makeToggle         = ctx.makeToggle
	local makeButton         = ctx.makeButton
	local makeDropdown       = ctx.makeDropdown
	local makeInput          = ctx.makeInput

	------------------------------------------------------------------ SELL PAGE
	local sellPage = makePage("Sell", "Sell Settings", "🛒", 1)

	-- Enable Auto List (dipindah dari Misc) — toggle utama di atas
	local autoListCard = mk("Frame", { Size = UDim2.new(1, 0, 0, 60), BackgroundColor3 = C.row, LayoutOrder = 1 }, sellPage)
	corner(autoListCard, 8); stroke(autoListCard); pad(autoListCard, 12, 12, 0, 0)
	local rAutoToggle = makeToggle(autoListCard, "Enable Auto List", "Periodically scan inventory and list matching pets",
		function() return CFG.autoSell end,
		function(v)
			CFG.autoSell = v; persistState(); ctx.setStatus(v and "active" or "idle")
			if v and not ctx.state.running then ctx.state.running = true; task.spawn(ctx.mainLoop)
			elseif not v then ctx.state.running = false end
		end, 1)
	ctx.ui.rAutoToggle = rAutoToggle

	-- Accordion: Booth Settings
	local boothBody = makeAccordion(sellPage, "Booth Settings", 2)
	makeSingleDropdown(boothBody, "Booth Skin", "Equip skins you own in Trade Plaza", reg.SKIN_OPTIONS,
		function() return CFG.boothSkin or "Default" end,
		function(name)
			CFG.boothSkin = name; persistState()
			pcall(function() EquipSkin:FireServer(name) end)
			log("Memasang skin booth: " .. name)
		end, 1)

	makeToggle(boothBody, "Auto Claim Booth", "Automatically claim an unclaimed booth",
		function() return CFG.autoClaim end,
		function(v) CFG.autoClaim = v; persistState() end, 2)

	makeToggle(boothBody, "Auto Switch to Booth Near Portal", "Switch to a booth closer to the lobby portal",
		function() return CFG.autoSwitchPortal end,
		function(v) CFG.autoSwitchPortal = v; persistState() end, 3)

	-- Accordion: Unlist Utilities (di bawah Profile 3)
	local unlistBody = makeAccordion(sellPage, "Unlist Pets Utilities", 20)
	makeButton(unlistBody, "Unlist All Pets", C.red, ctx.unlistAll, 1)
	makeButton(unlistBody, "Unclaim Booth", C.row, function() pcall(function() RemoveBooth:FireServer() end) log("Unclaim booth dikirim.") end, 2)

	-- Accordion: Automation Relocate Sell (di bawah Profile 3)
	local reloBody = makeAccordion(sellPage, "Automation Relocate Sell", 21)
	makeInput(reloBody, "Idle Timeout (Minutes)", "Move server if no buyers within this duration",
		function() return CFG.relocateIdleMin or 20 end,
		function(txt) local n = tonumber(txt); CFG.relocateIdleMin = (n and n >= 1) and math.floor(n) or 20; persistState() end, 1)
	makeInput(reloBody, "Min Player Threshold", "Relocate if server has fewer players (0 = off)",
		function() return CFG.relocateMinPlayers or 0 end,
		function(txt) local n = tonumber(txt); CFG.relocateMinPlayers = (n and n >= 0) and math.floor(n) or 0; persistState() end, 2)
	makeInput(reloBody, "Preferred Lobby Size", "Find server closest to this player count",
		function() return CFG.relocatePreferred or 20 end,
		function(txt) local n = tonumber(txt); CFG.relocatePreferred = (n and n >= 1) and math.floor(n) or 20; persistState() end, 3)
	makeToggle(reloBody, "Automation Relocate Sell", "Automatically move to busier server when booth is idle",
		function() return CFG.relocateEnabled end,
		function(v)
			CFG.relocateEnabled = v; persistState()
			if v then ctx.startRelocate() else ctx.stopRelocate() end
		end, 4)
	makeButton(reloBody, "Relocate Now", C.acc, function() ctx.relocateNow() end, 5)

	------------------------------------------------------------------ LISTING PROFILES (accordion di Sell)
	-- simpan fungsi buka accordion + container biar bisa dinavigasi dari klik card Inventory
	local profileOpen, profileCont, listingOpen = {}, {}, {}
	ctx.ui.profileOpen, ctx.ui.profileCont, ctx.ui.listingOpen = profileOpen, profileCont, listingOpen
	for i = 1, NUM_PROFILES do
		local prof = CFG.profiles[i]
		local profBody, profSetOpen, profContainer = makeAccordion(sellPage, "Profile " .. i, 4 + i)
		profileOpen[i], profileCont[i], listingOpen[i] = profSetOpen, profContainer, {}

		local clearers = {} -- reset tiap listing (dipakai tombol Clear All)

		for j = 1, NUM_LISTINGS do
			local sub = prof.listings[j]
			local listBody, listSetOpen = makeAccordion(profBody, "Listing " .. j, j)
			listingOpen[i][j] = listSetOpen

			local petRefresh = makeDropdown(listBody, "Pet Types [Listing " .. j .. "]", "Select pet types to list", reg.PET_OPTIONS, sub.pets, function() persistState() end, 1)
			local mutRefresh = makeDropdown(listBody, "Mutation [Listing " .. j .. "]", "Empty = non-mutated only, select = must have mutation", reg.MUT_OPTIONS, sub.muts, function() persistState() end, 2)
			local minWBox = makeInput(listBody, "Min Weight [Listing " .. j .. "]", "Minimum weight filter (KG)", function() return sub.minW or 0 end, function(txt) local n = tonumber(txt); sub.minW = (n and n >= 0) and n or 0; persistState() end, 3)
			local maxWBox = makeInput(listBody, "Max Weight [Listing " .. j .. "]", "Maximum weight filter (KG)", function() return sub.maxW or 0 end, function(txt) local n = tonumber(txt); sub.maxW = (n and n >= 0) and n or 0; persistState() end, 4)
			local maxListBox = makeInput(listBody, "Max Listings [Listing " .. j .. "]", "Maximum number of listings for this profile", function() return sub.maxList or 0 end, function(txt) local n = tonumber(txt); sub.maxList = (n and n >= 0) and math.floor(n) or 0; persistState() end, 5)
			local priceBox = makeInput(listBody, "Price [Listing " .. j .. "]", "Price per listing (Tokens)", function() return sub.price or 100 end, function(txt) local n = tonumber(txt); sub.price = (n and n >= 0) and math.floor(n) or 0; persistState() end, 6)

			clearers[#clearers + 1] = function()
				for k in pairs(sub.pets) do sub.pets[k] = nil end
				for k in pairs(sub.muts) do sub.muts[k] = nil end
				sub.minW, sub.maxW, sub.maxList, sub.price = 0, 0, 0, 100
				petRefresh(); mutRefresh()
				minWBox.Text = tostring(sub.minW)
				maxWBox.Text = tostring(sub.maxW)
				maxListBox.Text = tostring(sub.maxList)
				priceBox.Text = tostring(sub.price)
			end
		end

		makeButton(profBody, "Clear All (Profile " .. i .. ")", C.red, function()
			for _, clr in ipairs(clearers) do clr() end
			persistState()
			log(("Profile %d dibersihkan."):format(i))
		end, NUM_LISTINGS + 1)
	end

	------------------------------------------------------------------ BUY PAGE (Auto Snipe)
	local buyPage = makePage("Buy", "Auto Snipe", "🎯", 2)

	-- Status snipe
	local snipeStatusCard = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.row, LayoutOrder = 1 }, buyPage)
	corner(snipeStatusCard, 8); stroke(snipeStatusCard); pad(snipeStatusCard, 12, 12, 10, 10)
	mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, snipeStatusCard)
	mk("TextLabel", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = "🎯  Snipe Status", Font = F.bold, TextSize = 13, TextColor3 = C.txt, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }, snipeStatusCard)
	local snipeStatusLbl = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = "", Font = F.reg, TextSize = 12, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, LineHeight = 1.3, LayoutOrder = 2 }, snipeStatusCard)
	local function refreshSnipeStatus()
		local ok, s = pcall(function() return ctx.getSnipeStatus() end)
		if ok and s then snipeStatusLbl.Text = ("Status: %s\n%s"):format(s.on and "ON" or "OFF", s.lines) end
	end
	ctx.refreshSnipeStatus = refreshSnipeStatus

	-- Auto Snipe toggle
	local snipeToggleCard = mk("Frame", { Size = UDim2.new(1, 0, 0, 60), BackgroundColor3 = C.row, LayoutOrder = 2 }, buyPage)
	corner(snipeToggleCard, 8); stroke(snipeToggleCard); pad(snipeToggleCard, 12, 12, 0, 0)
	makeToggle(snipeToggleCard, "Auto Snipe Pet", "Scan & beli pet cocok dari booth pemain (profil 1-5)",
		function() return CFG.snipeEnabled end,
		function(v)
			CFG.snipeEnabled = v; persistState(); refreshSnipeStatus()
			if v then ctx.startSnipe() else ctx.stopSnipe() end
		end, 1)

	-- Accordion: Hop Server (1 enable + filter metode hop)
	local hopAcc = makeAccordion(buyPage, "Hop Server", 3)
	makeToggle(hopAcc, "Auto Server Hop", "Enable hop antar-server (master)",
		function() return CFG.snipeHop end,
		function(v) CFG.snipeHop = v; persistState() end, 1)
	makeToggle(hopAcc, "Filter: By Index (Find Seller)", "Cari seller lintas server via index game",
		function() return CFG.snipeHopIndex end,
		function(v) CFG.snipeHopIndex = v; persistState() end, 2)
	makeToggle(hopAcc, "Filter: By Player (Min Players)", "Hop ke server berdasarkan jumlah player",
		function() return CFG.snipeHopPlayer end,
		function(v) CFG.snipeHopPlayer = v; persistState() end, 3)
	makeInput(hopAcc, "Min Players", "By Player: hop ke server dgn pemain >= ini (1 = semua server)",
		function() return CFG.snipeMinPop or 25 end,
		function(txt) local n = tonumber(txt); CFG.snipeMinPop = (n and n >= 1) and math.floor(n) or 25; persistState() end, 4)
	makeInput(hopAcc, "Revisit Cooldown (detik)", "Jeda sebelum boleh balik ke server yang sama",
		function() return CFG.snipeRevisitSec or 120 end,
		function(txt) local n = tonumber(txt); CFG.snipeRevisitSec = (n and n >= 5) and math.floor(n) or 120; persistState() end, 5)

	-- 5 profil snipe (accordion; urutan = prioritas)
	for i = 1, NUM_SNIPE do
		local prof = CFG.snipeProfiles[i]
		local body = makeAccordion(buyPage, "Snipe " .. i, 6 + i)
		makeDropdown(body, "Pet Types [Snipe " .. i .. "]", "Pilih pet per egg (premium/biasa). Urutan profil = prioritas", reg.PET_COMBO_OPTIONS, prof.pets, function() persistState(); refreshSnipeStatus() end, 1)
		makeDropdown(body, "Mutation [Snipe " .. i .. "]", "Kosong = semua mutasi", reg.MUT_OPTIONS, prof.muts, function() persistState() end, 2)
		makeInput(body, "Max Price [Snipe " .. i .. "]", "0 = tanpa batas harga (Tokens)", function() return prof.maxPrice or 0 end, function(txt) local n = tonumber(txt); prof.maxPrice = (n and n >= 0) and math.floor(n) or 0; persistState(); refreshSnipeStatus() end, 3)
	end
	refreshSnipeStatus()

	------------------------------------------------------------------ INVENTORY PAGE
	local invPage = makePage("Inventory", "Inventory Tracker", "🎒", 5)

	-- format angka dgn pemisah ribuan (1234567 -> 1.234.567)
	local function fmt(n)
		local s = tostring(math.floor(tonumber(n) or 0))
		local k
		while true do s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1.%2"); if k == 0 then break end end
		return s
	end

	-- === Stat cards (Target Pets + Saldo Token) ===
	local statRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 88), BackgroundTransparency = 1, LayoutOrder = 1 }, invPage)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, statRow)

	local function statCard(order, icon, title, accent)
		local card = mk("Frame", { Size = UDim2.new(0.5, -6, 1, 0), BackgroundColor3 = C.row, LayoutOrder = order, ClipsDescendants = true }, statRow)
		corner(card, 12); stroke(card)
		local glow = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = accent, BackgroundTransparency = 0.9, BorderSizePixel = 0 }, card)
		corner(glow, 12)
		mk("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.82), NumberSequenceKeypoint.new(1, 1) }) }, glow)
		mk("TextLabel", { Size = UDim2.new(1, -32, 0, 16), Position = UDim2.fromOffset(16, 14), BackgroundTransparency = 1, Text = icon .. "  " .. title, Font = F.semi, TextSize = 11, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left }, card)
		return mk("TextLabel", { Size = UDim2.new(1, -32, 0, 36), Position = UDim2.fromOffset(16, 36), BackgroundTransparency = 1, Text = "0", Font = F.bold, TextSize = 26, TextColor3 = accent, TextXAlignment = Enum.TextXAlignment.Left }, card)
	end

	local targetVal = statCard(1, "🎯", "TARGET PETS", C.acc)
	local tokenVal  = statCard(2, "💰", "SALDO TOKEN", C.green)

	-- === Breakdown per tipe pet ===
	local listCard = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.row, LayoutOrder = 2 }, invPage)
	corner(listCard, 12); stroke(listCard); pad(listCard, 14, 14, 12, 14)
	mk("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, listCard)
	mk("TextLabel", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = "📋  Target Breakdown", Font = F.bold, TextSize = 13, TextColor3 = C.txt, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }, listCard)
	local rowsHolder = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, listCard)
	mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, rowsHolder)
	local emptyLbl = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Text = "Belum ada pet target dipilih.", Font = F.reg, TextSize = 12, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }, rowsHolder)

	-- cari (profil, listing) tempat pet type ini dikonfigurasi (ambil yg pertama ketemu)
	local function findListing(pt)
		for i = 1, NUM_PROFILES do
			local prof = CFG.profiles[i]
			if prof and type(prof.listings) == "table" then
				for j = 1, NUM_LISTINGS do
					local sub = prof.listings[j]
					if sub and type(sub.pets) == "table" then
						for petKey in pairs(sub.pets) do
							if ((string.split(petKey, " - ")[1]) or petKey) == pt then return i, j end
						end
					end
				end
			end
		end
	end

	-- klik card -> pindah ke tab Sell, buka Profile+Listing pet itu, scroll ke situ
	local function gotoListing(pt)
		local i, j = findListing(pt)
		if not i then return end
		if ctx.selectTab then ctx.selectTab("Sell") end
		local po = ctx.ui.profileOpen and ctx.ui.profileOpen[i]
		if po then po(true) end
		local lo = ctx.ui.listingOpen and ctx.ui.listingOpen[i] and ctx.ui.listingOpen[i][j]
		if lo then lo(true) end
		-- scroll accordion Profile ke atas viewport (tunggu 1 frame biar layout update)
		task.spawn(function()
			local sf = ctx.ui.pages and ctx.ui.pages["Sell"]
			local cont = ctx.ui.profileCont and ctx.ui.profileCont[i]
			if sf and cont then
				game:GetService("RunService").Heartbeat:Wait()
				local ok = pcall(function()
					local y = cont.AbsolutePosition.Y - sf.AbsolutePosition.Y + sf.CanvasPosition.Y
					sf.CanvasPosition = Vector2.new(0, math.max(0, y - 8))
				end)
				return ok
			end
		end)
	end

	local petRows = {}
	local function renderInventory()
		local counts = ctx.inventoryCounts()
		local types  = ctx.selectedPetTypes()
		local total = 0
		for _, pt in ipairs(types) do total = total + (counts[pt] or 0) end
		targetVal.Text = fmt(total)
		tokenVal.Text  = fmt(ctx.getTokens())

		for _, r in ipairs(petRows) do r:Destroy() end
		petRows = {}
		emptyLbl.Visible = (#types == 0)
		for i, pt in ipairs(types) do
			local c = counts[pt] or 0
			local row = mk("TextButton", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.panel, LayoutOrder = i + 1, Text = "", AutoButtonColor = false }, rowsHolder)
			corner(row, 8)
			mk("Frame", { Size = UDim2.fromOffset(3, 16), Position = UDim2.new(0, 10, 0.5, -8), BackgroundColor3 = (c > 0 and C.acc or C.stroke), BorderSizePixel = 0 }, row)
			mk("TextLabel", { Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(22, 0), BackgroundTransparency = 1, Text = pt, Font = F.semi, TextSize = 12, TextColor3 = C.txt, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, row)
			local pill = mk("Frame", { Size = UDim2.fromOffset(54, 22), Position = UDim2.new(1, -82, 0.5, -11), BackgroundColor3 = (c > 0 and C.acc or C.stroke), BorderSizePixel = 0 }, row)
			corner(pill, 11)
			mk("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = tostring(c), Font = F.bold, TextSize = 12, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center }, pill)
			-- chevron penanda bisa diklik -> ke listing profile
			local chev = mk("TextLabel", { Size = UDim2.fromOffset(14, 34), Position = UDim2.new(1, -18, 0, 0), BackgroundTransparency = 1, Text = "›", Font = F.bold, TextSize = 16, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Center }, row)
			row.MouseEnter:Connect(function() row.BackgroundColor3 = C.row; chev.TextColor3 = C.acc end)
			row.MouseLeave:Connect(function() row.BackgroundColor3 = C.panel; chev.TextColor3 = C.sub end)
			row.MouseButton1Click:Connect(function() gotoListing(pt) end)
			petRows[#petRows + 1] = row
		end
	end
	ctx.renderInventory = renderInventory

	-- auto-refresh tiap tab Inventory diklik (tombol manual dihapus, redundan)
	ctx.ui.tabBtns["Inventory"].btn.MouseButton1Click:Connect(renderInventory)

	------------------------------------------------------------------ MISC PAGE
	local miscPage = makePage("Misc", "Miscellaneous Settings", "⚙️", 6)

	-- Auto-Reconnect toggle
	local reconCard = mk("Frame", { Size = UDim2.new(1, 0, 0, 60), BackgroundColor3 = C.row, LayoutOrder = 0 }, miscPage)
	corner(reconCard, 8); stroke(reconCard); pad(reconCard, 12, 12, 0, 0)
	makeToggle(reconCard, "Auto Reconnect", "Rejoin otomatis kalau ke-kick / disconnect",
		function() return CFG.autoReconnect ~= false end,
		function(v) CFG.autoReconnect = v; persistState() end, 1)

	local webhookCard = mk("Frame", { Size = UDim2.new(1, 0, 0, 128), BackgroundColor3 = C.row, LayoutOrder = 1 }, miscPage)
	corner(webhookCard, 8); stroke(webhookCard); pad(webhookCard, 12, 12, 8, 8)
	mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, webhookCard)

	makeToggle(webhookCard, "Enable Webhook Notifications", "Post listings to Discord Webhook",
		function() return CFG.webhookEnabled end,
		function(v) CFG.webhookEnabled = v; persistState() end, 1)

	local whBox = mk("TextBox", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.panel, PlaceholderText = "https://discord.com/api/webhooks/...", Text = CFG.webhookUrl, Font = F.reg, TextSize = 11, TextColor3 = C.acc, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ClipsDescendants = true, LayoutOrder = 2 }, webhookCard)
	corner(whBox, 6); stroke(whBox); pad(whBox, 6, 6, 0, 0)
	whBox.FocusLost:Connect(function() CFG.webhookUrl = whBox.Text; persistState() end)

	makeButton(webhookCard, "Test Webhook Connection", C.acc, function()
		if CFG.webhookUrl == "" then log("Webhook URL kosong."); return end
		local prev = CFG.webhookEnabled; CFG.webhookEnabled = true
		ctx.sendWebhook({
			username = "CeszParadise",
			avatar_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png",
			embeds = {{
				title = "🔔 Test Sukses",
				description = "Seller Webhook berhasil terhubung ke CeszParadise!",
				color = 10181046,
				footer = {
					text = "Player: " .. LP.Name,
					icon_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png"
				}
			}}
		})
		CFG.webhookEnabled = prev
		log("Test webhook terkirim.")
	end, 3)

	-- Logger Panel
	local loggerCard = mk("Frame", { Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = C.row, LayoutOrder = 3 }, miscPage)
	corner(loggerCard, 8); stroke(loggerCard); pad(loggerCard, 12, 12, 8, 8)
	mk("TextLabel", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = "Console Log", Font = F.bold, TextSize = 13, TextColor3 = C.txt, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }, loggerCard)

	local logBox = mk("TextLabel", { Size = UDim2.new(1, 0, 1, -22), BackgroundColor3 = C.panel, Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Code, TextSize = 10, TextColor3 = C.sub, TextWrapped = true, LayoutOrder = 2 }, loggerCard)
	corner(logBox, 6); stroke(logBox); pad(logBox, 6, 6, 6, 6)
	ctx.ui.logBox = logBox
	-- tampilkan log yang mungkin sudah ter-buffer sebelum logBox dibuat
	logBox.Text = table.concat(ctx.state.logLines, "\n")
end
]=],
	["ui/theme.lua"] = [=[
--[[ theme.lua — palet warna PINK ROYALE ELEGAN + helper pembuat Instance.
     Mengisi: ctx.C (warna), ctx.mk, ctx.corner, ctx.stroke, ctx.pad, ctx.grad ]]
return function(ctx)
	local C = {
		bg        = Color3.fromRGB(18, 10, 24),        -- Deep obsidian midnight plum / velvet rose
		panel     = Color3.fromRGB(28, 15, 36),        -- Dark luxury wine/mauve (sidebar & panel)
		row       = Color3.fromRGB(42, 22, 54),        -- Card container mewah
		rowAlt    = Color3.fromRGB(56, 30, 72),        -- Elevated card / dropdown item
		rowHover  = Color3.fromRGB(70, 36, 90),        -- Hover state card
		stroke    = Color3.fromRGB(255, 75, 155),      -- Radiant rose-pink border
		strokeSub = Color3.fromRGB(110, 52, 118),      -- Subtle border muted
		acc       = Color3.fromRGB(255, 50, 135),      -- Hot Radiant Rose (aksen utama)
		acc2      = Color3.fromRGB(255, 120, 195),     -- Soft Neon Sakura (gradient partner)
		accSoft   = Color3.fromRGB(255, 180, 225),     -- Pastel Rose Shimmer
		glow      = Color3.fromRGB(255, 60, 145),      -- Ambient glow
		txt       = Color3.fromRGB(255, 242, 252),     -- Pearl White Shimmer (teks utama ultra-tajam)
		sub       = Color3.fromRGB(215, 168, 212),     -- Soft Lavender-Rose (deskripsi terbaca jelas)
		green     = Color3.fromRGB(110, 245, 185),     -- Luminous Mint-Emerald
		red       = Color3.fromRGB(255, 65, 110),      -- Passion Crimson Rose
	}

	local F = {
		title = Enum.Font.FredokaOne,       -- Judul / Header / Branding (Modern & Segar, beda total dari Gotham)
		bold  = Enum.Font.MontserratBold,   -- Subheader / Tombol / Label Tebal (Tajam & Elegan)
		semi  = Enum.Font.MontserratMedium, -- Dropdown item / Value pill
		reg   = Enum.Font.Ubuntu,           -- Deskripsi & isi teks (Sangat nyaman dibaca)
		code  = Enum.Font.Code,             -- Console logs
	}

	local function mk(cls, props, parent)
		local o = Instance.new(cls)
		for k, v in pairs(props) do o[k] = v end
		o.Parent = parent
		return o
	end

	local function corner(o, r)
		return mk("UICorner", { CornerRadius = UDim.new(0, r or 10) }, o)
	end

	local function stroke(o, col, thick, trans)
		return mk("UIStroke", {
			Color = col or C.strokeSub,
			Thickness = thick or 1.2,
			Transparency = trans or 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, o)
	end

	local function pad(o, l, r, t, b)
		return mk("UIPadding", {
			PaddingLeft = UDim.new(0, l),
			PaddingRight = UDim.new(0, r),
			PaddingTop = UDim.new(0, t),
			PaddingBottom = UDim.new(0, b),
		}, o)
	end

	local function grad(o, rot, col1, col2)
		return mk("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, col1 or C.acc),
				ColorSequenceKeypoint.new(1, col2 or C.acc2),
			}),
			Rotation = rot or 90,
		}, o)
	end

	ctx.C      = C
	ctx.F      = F
	ctx.mk     = mk
	ctx.corner = corner
	ctx.stroke = stroke
	ctx.pad    = pad
	ctx.grad   = grad
end
]=],
	["ui/window.lua"] = [=[
--[[ window.lua — jendela utama trade PINK ROYALE:
     Sidebar modern, player profile card, glowing title bar, responsive auto-scaling,
     floating maximize jewel, status footer modern. ]]
return function(ctx)
	local Players          = ctx.Services.Players
	local UserInputService = ctx.Services.UserInputService
	local TS               = game:GetService("TweenService")
	local LP  = ctx.LP
	local CFG = ctx.CFG
	local C   = ctx.C
	local F   = ctx.F
	local mk, corner, stroke, pad, grad = ctx.mk, ctx.corner, ctx.stroke, ctx.pad, ctx.grad

	ctx.ui.pages   = {}
	ctx.ui.tabBtns = {}

	----------------------------------------------------------------- bersihkan GUI lama
	pcall(function()
		local host = (gethui and gethui()) or game:GetService("CoreGui")
		local old = host:FindFirstChild("GAGSeller"); if old then old:Destroy() end
		local pg = LP:FindFirstChild("PlayerGui")
		if pg and pg:FindFirstChild("GAGSeller") then pg.GAGSeller:Destroy() end
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "GAGSeller"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = LP:WaitForChild("PlayerGui")
	ctx.state.gui = gui
	ctx.state.isAlive = true
	gui.Destroying:Connect(function()
		ctx.state.isAlive = false
	end)

	----------------------------------------------------------------- Floating Maximize Jewel
	local maxIcon = mk("TextButton", {
		Size = UDim2.fromOffset(50, 50),
		Position = UDim2.new(0, 16, 0.5, -25),
		BackgroundColor3 = C.panel,
		Text = "✦",
		Font = F.bold,
		TextSize = 22,
		TextColor3 = C.acc,
		Visible = false,
		Active = true,
		ZIndex = 100,
	}, gui)
	corner(maxIcon, 25)
	stroke(maxIcon, C.acc, 2, 0.1)

	local maxGlow = mk("Frame", {
		Size = UDim2.new(1, 14, 1, 14),
		Position = UDim2.new(0, -7, 0, -7),
		BackgroundColor3 = C.acc,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ZIndex = 99,
	}, maxIcon)
	corner(maxGlow, 30)

	pcall(function()
		local logo = ctx.getLogo and ctx.getLogo()
		if logo then
			maxIcon.Text = ""
			local img = mk("ImageLabel", {
				Size = UDim2.new(1, -12, 1, -12),
				Position = UDim2.fromOffset(6, 6),
				BackgroundTransparency = 1,
				Image = logo,
				ScaleType = Enum.ScaleType.Fit,
			}, maxIcon)
			corner(img, 19)
		end
	end)

	do
		local dragging, ds, sp
		maxIcon.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = true; ds = i.Position; sp = maxIcon.Position
			end
		end)
		UserInputService.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local d = i.Position - ds
				maxIcon.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
			end
		end)
		UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

	----------------------------------------------------------------- Main Window (Glassmorphic Glow)
	local main = mk("Frame", {
		Size = UDim2.fromOffset(610, 375),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Active = true,
	}, gui)
	corner(main, 16)
	stroke(main, C.stroke, 1.6, 0.25)

	local haloGlow = mk("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = C.acc,
		BackgroundTransparency = 0.94,
		BorderSizePixel = 0,
	}, main)
	corner(haloGlow, 16)

	-- Responsive Auto Scale
	local uiScale = Instance.new("UIScale"); uiScale.Parent = main
	local function fitScale()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local w, h = main.Size.X.Offset, main.Size.Y.Offset
		local s = math.min(1, (vp.X - 30) / w, (vp.Y - 30) / h)
		uiScale.Scale = math.max(0.4, s)
	end
	fitScale()
	pcall(function()
		local cam = workspace.CurrentCamera
		if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale) end
	end)

	----------------------------------------------------------------- Title Bar
	local titleBar = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, main)
	corner(titleBar, 16)

	local titleGrad = mk("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = C.acc,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, titleBar)
	corner(titleGrad, 16)
	grad(titleGrad, 0, C.acc, C.acc2)

	local titleLine = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = C.acc,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, titleBar)
	grad(titleLine, 0, C.acc, C.acc2)

	local titleIcon = mk("TextLabel", {
		Size = UDim2.fromOffset(30, 48),
		Position = UDim2.fromOffset(16, 0),
		BackgroundTransparency = 1,
		Text = "✦",
		Font = F.title,
		TextSize = 20,
		TextColor3 = C.acc,
		ZIndex = 8,
	}, titleBar)

	pcall(function()
		local logo = ctx.getLogo and ctx.getLogo()
		if logo then
			titleIcon.Text = ""
			local tImg = mk("ImageLabel", {
				Size = UDim2.fromOffset(26, 26),
				Position = UDim2.fromOffset(2, 11),
				BackgroundTransparency = 1,
				Image = logo,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 9,
			}, titleIcon)
			corner(tImg, 13)
		end
	end)

	local titleLabel = mk("TextLabel", {
		Size = UDim2.new(0, 120, 1, 0),
		Position = UDim2.fromOffset(46, 0),
		BackgroundTransparency = 1,
		Text = "CeszParadise",
		Font = F.title,
		TextSize = 15,
		TextColor3 = C.txt,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 8,
	}, titleBar)

	local subPill = mk("Frame", {
		Size = UDim2.fromOffset(105, 24),
		Position = UDim2.fromOffset(168, 12),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		ZIndex = 8,
	}, titleBar)
	corner(subPill, 12)
	stroke(subPill, C.acc, 1, 0.5)
	pad(subPill, 6, 6, 0, 0)

	local subLabel = mk("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "❖ GAG Trade",
		Font = F.bold,
		TextSize = 10.5,
		TextColor3 = C.accSoft,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 9,
	}, subPill)

	do
		local dragging, ds, sp
		titleBar.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = true; ds = i.Position; sp = main.Position
			end
		end)
		UserInputService.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local d = i.Position - ds
				main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
			end
		end)
		UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

	local function makeTitleBtn(label, posX, isClose)
		local btn = mk("TextButton", {
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.new(1, posX, 0, 9),
			BackgroundColor3 = C.row,
			Text = label,
			Font = F.bold,
			TextSize = 13,
			TextColor3 = C.txt,
			ZIndex = 10,
			AutoButtonColor = false,
		}, titleBar)
		corner(btn, 8)
		stroke(btn, isClose and C.red or C.strokeSub, 1, 0.4)

		btn.MouseEnter:Connect(function()
			TS:Create(btn, TweenInfo.new(0.15), {
				BackgroundColor3 = isClose and C.red or C.acc,
				TextColor3 = Color3.new(1, 1, 1),
			}):Play()
		end)
		btn.MouseLeave:Connect(function()
			TS:Create(btn, TweenInfo.new(0.15), {
				BackgroundColor3 = C.row,
				TextColor3 = C.txt,
			}):Play()
		end)
		return btn
	end

	local minBtn   = makeTitleBtn("−", -74, false)
	local closeBtn = makeTitleBtn("✕", -38, true)

	-- Live FPS Counter Pill
	local fpsPill = mk("Frame", {
		Size = UDim2.fromOffset(84, 26),
		Position = UDim2.new(1, -166, 0, 11),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, titleBar)
	corner(fpsPill, 13)
	stroke(fpsPill, C.strokeSub, 1, 0.5)

	local fpsDot = mk("Frame", {
		Size = UDim2.fromOffset(8, 8),
		Position = UDim2.new(0, 8, 0.5, -4),
		BackgroundColor3 = C.green,
		BorderSizePixel = 0,
		ZIndex = 11,
	}, fpsPill)
	corner(fpsDot, 4)

	local fpsLabel = mk("TextLabel", {
		Size = UDim2.new(1, -22, 1, 0),
		Position = UDim2.fromOffset(20, 0),
		BackgroundTransparency = 1,
		Text = "60 FPS",
		Font = F.bold,
		TextSize = 11,
		TextColor3 = C.txt,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 11,
	}, fpsPill)

	do
		local RunService = game:GetService("RunService")
		local frameCount = 0
		local lastTime = tick()
		local fpsConn
		fpsConn = RunService.RenderStepped:Connect(function()
			if not ctx.state.isAlive then
				if fpsConn then fpsConn:Disconnect(); fpsConn = nil end
				return
			end
			frameCount = frameCount + 1
			local now = tick()
			local diff = now - lastTime
			if diff >= 0.5 then
				local curFps = math.clamp(math.round(frameCount / diff), 1, 999)
				frameCount = 0
				lastTime = now
				fpsLabel.Text = curFps .. " FPS"
				if curFps >= 50 then
					fpsDot.BackgroundColor3 = C.green
					fpsLabel.TextColor3 = C.txt
				elseif curFps >= 30 then
					fpsDot.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
					fpsLabel.TextColor3 = Color3.fromRGB(255, 220, 140)
				else
					fpsDot.BackgroundColor3 = C.red
					fpsLabel.TextColor3 = C.red
				end
			end
		end)
	end

	minBtn.MouseButton1Click:Connect(function() main.Visible = false; maxIcon.Visible = true end)
	maxIcon.MouseButton1Click:Connect(function() maxIcon.Visible = false; main.Visible = true end)
	closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

	----------------------------------------------------------------- Left Sidebar
	local sidebar = mk("Frame", {
		Size = UDim2.new(0, 154, 1, -54),
		Position = UDim2.fromOffset(8, 48),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, main)
	corner(sidebar, 12)
	stroke(sidebar, C.strokeSub, 1, 0.5)
	pad(sidebar, 6, 6, 6, 6)

	local menuTag = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = "M E N U",
		Font = F.bold,
		TextSize = 11,
		TextColor3 = C.acc,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
	}, sidebar)

	local tabButtonsFrame = mk("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -68),
		Position = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.acc,
		ScrollBarImageTransparency = 0.4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingEnabled = true,
	}, sidebar)
	mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabButtonsFrame)

	local profileCard = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		Position = UDim2.new(0, 0, 1, -46),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
	}, sidebar)
	corner(profileCard, 10)
	stroke(profileCard, C.stroke, 1.2, 0.4)
	pad(profileCard, 6, 6, 4, 4)

	local avatar = mk("ImageLabel", {
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
	}, profileCard)
	corner(avatar, 17)
	stroke(avatar, C.acc, 1.5, 0.2)
	pcall(function()
		avatar.Image = Players:GetUserThumbnailAsync(LP.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
	end)

	local nameLabel = mk("TextLabel", {
		Size = UDim2.new(1, -42, 0, 18),
		Position = UDim2.fromOffset(42, 2),
		BackgroundTransparency = 1,
		Text = LP.DisplayName,
		Font = F.bold,
		TextSize = 12,
		TextColor3 = C.txt,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, profileCard)

	local statusPill = mk("TextLabel", {
		Size = UDim2.new(1, -42, 0, 16),
		Position = UDim2.fromOffset(42, 18),
		BackgroundTransparency = 1,
		Text = "Trade Plaza ✦",
		Font = F.bold,
		TextSize = 10,
		TextColor3 = C.accSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, profileCard)

	----------------------------------------------------------------- Right Content Frame
	local content = mk("Frame", {
		Size = UDim2.new(1, -174, 1, -56),
		Position = UDim2.fromOffset(166, 49),
		BackgroundTransparency = 1,
	}, main)

	----------------------------------------------------------------- Resize Grip
	local grip = mk("TextButton", {
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(1, -24, 1, -24),
		BackgroundTransparency = 1,
		Text = "◢",
		Font = F.bold,
		TextSize = 14,
		TextColor3 = C.strokeSub,
		AutoButtonColor = false,
		Active = true,
		ZIndex = 20,
	}, main)
	grip.MouseEnter:Connect(function() grip.TextColor3 = C.acc end)
	grip.MouseLeave:Connect(function() grip.TextColor3 = C.strokeSub end)
	do
		local rz, ds, ss
		grip.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				rz = true; ds = i.Position; ss = Vector2.new(main.Size.X.Offset, main.Size.Y.Offset)
			end
		end)
		UserInputService.InputChanged:Connect(function(i)
			if rz and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local scale = uiScale.Scale > 0 and uiScale.Scale or 1
				local d = i.Position - ds
				local w = math.clamp(ss.X + d.X / scale, 480, 1600)
				local h = math.clamp(ss.Y + d.Y / scale, 320, 1100)
				main.Size = UDim2.fromOffset(w, h)
				fitScale()
			end
		end)
		UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				rz = false
			end
		end)
	end

	----------------------------------------------------------------- Status Footer
	local statusFooter = mk("Frame", {
		Size = UDim2.new(1, -196, 0, 20),
		Position = UDim2.new(0, 184, 1, -24),
		BackgroundTransparency = 1,
	}, main)
	local statusText = mk("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "○ Status: idle  |  Loop: OFF",
		Font = F.bold,
		TextSize = 11,
		TextColor3 = C.sub,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, statusFooter)

	function ctx.setStatus(s)
		local isActive = tostring(s):lower():find("active") ~= nil or tostring(s):lower():find("on") ~= nil
		statusText.Text = ("%s Status: %s  |  Loop: %s"):format(
			isActive and "●" or "○",
			tostring(s),
			CFG.autoSell and "ON ✦" or "OFF"
		)
		statusText.TextColor3 = isActive and C.green or C.sub
	end

	----------------------------------------------------------------- Logger
	local logLines = ctx.state.logLines
	function ctx.log(msg)
		table.insert(logLines, os.date("%H:%M:%S ") .. msg)
		while #logLines > 10 do table.remove(logLines, 1) end
		if ctx.ui.logBox then ctx.ui.logBox.Text = table.concat(logLines, "\n") end
	end

	ctx.ui.main            = main
	ctx.ui.maxIcon         = maxIcon
	ctx.ui.content         = content
	ctx.ui.tabButtonsFrame = tabButtonsFrame
	ctx.ui.sidebar         = sidebar
	ctx.ui.statusText      = statusText
end
]=],
}
