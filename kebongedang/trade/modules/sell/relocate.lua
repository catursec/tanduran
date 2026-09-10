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
