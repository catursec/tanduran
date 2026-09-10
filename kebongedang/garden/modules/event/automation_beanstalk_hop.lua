--[[ automation_beanstalk_hop.lua — Auto Server Hop (Beanstalk).
     Tujuan: nyari server yg beanstalk growth-nya BELUM 900 biar bisa terus kontribusi & dapat reward.
     BATASAN: growth = state runtime server, API daftar server Roblox cuma kasih player count,
     JADI ga bisa tau growth sebelum join. Cara kerja: JOIN -> cek growth -> kalau >=900 (penuh/CD)
     hop ke server lain; kalau < 900 STAY & farm (biar toggle plant/collect/submit/claim yg kerja).
     Begitu growth server ini nyampe 900, hop lagi. Tanpa batas hop (sampai nemu yg < 900).

     Teknis: http request (server list) + TeleportToPlaceInstance(jobId) + queueonteleport (re-run hub).
     Config: CFG.beanstalkHopEnabled. Fungsi: ctx.startBeanstalkHop / ctx.stopBeanstalkHop.
]]
return function(ctx)
	local LP  = ctx.LP
	local CFG = ctx.CFG
	local TeleportService = game:GetService("TeleportService")
	local HttpService     = game:GetService("HttpService")
	local function setStatus(s) ctx.setStatus(s) end
	local branch = (getgenv and getgenv().GAG_BRANCH) or _G.GAG_BRANCH or "main"

	-- ref Teleport di-cache biar bypass hook __namecall anti-teleport
	local TeleportFn = TeleportService.Teleport

	-- queue loader hub biar auto jalan lagi abis pindah server (branch dijaga)
	local function queueLoader()
		local q = (syn and syn.queue_on_teleport) or queue_on_teleport
			or (fluxus and fluxus.queue_on_teleport) or (getgenv and getgenv().queue_on_teleport)
		if q then
			local cmd = ('if getgenv then getgenv().GAG_BRANCH=%q end loadstring(game:HttpGet("https://raw.githubusercontent.com/Tirta71/ScriptMarketGAG/%s/GAGSeller/init.lua"))()'):format(branch, branch)
			pcall(function() q(cmd) end)
		end
	end

	local function httpReq()
		return http_request or request or (syn and syn.request) or (http and http.request)
	end

	-- daftar jobId server publik yg masih ada room, exclude server sekarang (max 3 halaman)
	local function fetchServers()
		local req = httpReq(); if not req then return {} end
		local out, cursor = {}, ""
		for _ = 1, 3 do
			local url = ("https://games.roblox.com/v1/games/%d/servers/Public?limit=100&sortOrder=Desc"):format(game.PlaceId)
			if cursor ~= "" then url = url .. "&cursor=" .. cursor end
			local ok, resp = pcall(function() return req({ Url = url, Method = "GET" }) end)
			if not ok or type(resp) ~= "table" or resp.StatusCode ~= 200 then break end
			local ok2, data = pcall(function() return HttpService:JSONDecode(resp.Body) end)
			if not ok2 or type(data) ~= "table" then break end
			for _, s in ipairs(data.data or {}) do
				if s.id ~= game.JobId and (tonumber(s.playing) or 0) < (tonumber(s.maxPlayers) or 0) then
					out[#out + 1] = s.id
				end
			end
			cursor = data.nextPageCursor
			if not cursor or cursor == "" then break end
		end
		return out
	end

	-- pindah ke server lain (acak dari daftar). Fallback: Teleport random kalau daftar kosong/gagal.
	-- Cek CFG.beanstalkHopEnabled di tiap tahap: kalau user matiin di tengah proses (mis. pas
	-- ambil daftar server), langsung batal SEBELUM teleport -> matiin selalu aman & instan.
	local function hop()
		if not CFG.beanstalkHopEnabled then return false end
		queueLoader()
		task.wait(0.4)
		if not CFG.beanstalkHopEnabled then return false end
		local servers = fetchServers()
		if not CFG.beanstalkHopEnabled then return false end
		-- shuffle
		for i = #servers, 2, -1 do local j = math.random(1, i); servers[i], servers[j] = servers[j], servers[i] end
		for _, jobId in ipairs(servers) do
			if not CFG.beanstalkHopEnabled then return false end
			local ok = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LP) end)
			if ok then return true end
			task.wait(0.3)
		end
		if not CFG.beanstalkHopEnabled then return false end
		-- fallback: server random (bisa kebetulan sama, tapi lebih baik drpd stuck)
		pcall(function() TeleportFn(TeleportService, game.PlaceId, LP) end)
		return true
	end

	-- growth beanstalk sekarang dari billboard: return cur, max (nil kalau ga kebaca)
	local function growth()
		local inter = workspace:FindFirstChild("Interaction")
		local m = inter and inter:FindFirstChild("BeanstalkEventModel")
		if not m then return nil end
		for _, g in ipairs(m:GetDescendants()) do
			if g:IsA("TextLabel") then
				local a, b = g.Text:match("^(%d+)%s*/%s*(%d+)$")
				if a and b then return tonumber(a), tonumber(b) end
			end
		end
		return nil
	end

	local function hopLoop()
		ctx.state.beanHopId = (ctx.state.beanHopId or 0) + 1
		local myId = ctx.state.beanHopId
		ctx.elevate()
		local t0 = os.clock() -- buat timeout nunggu event kebaca
		while CFG.beanstalkHopEnabled and ctx.alive() and ctx.state.beanHopId == myId do
			local cur, max = growth()
			if not cur then
				-- event belum kebaca; kasih grace 40s (nunggu map load) sebelum nyerah & hop
				if os.clock() - t0 > 40 then
					setStatus("Beanstalk Hop: event ga kebaca — cari server lain...")
					hop(); return
				end
				setStatus("Beanstalk Hop: nunggu beanstalk kebaca...")
				task.wait(2)
			elseif cur >= max then
				setStatus(("Beanstalk Hop: server penuh (%d/%d) — cari server baru..."):format(cur, max))
				hop(); return -- instance ini ilang setelah teleport
			else
				-- server bagus: stay, biar automation lain yg farming. Cek berkala sampai 900.
				setStatus(("Beanstalk Hop: server OK (%d/%d) — farming"):format(cur, max))
				t0 = os.clock()
				task.wait(15)
			end
		end
	end

	function ctx.startBeanstalkHop()
		if not CFG.beanstalkHopEnabled then return end
		task.spawn(hopLoop)
	end
	function ctx.stopBeanstalkHop() ctx.state.beanHopId = (ctx.state.beanHopId or 0) + 1 end
end
