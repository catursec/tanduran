--[[ automation_reconnect.lua — Auto Reconnect/Rejoin tiap interval (Misc).
     Tiap X menit: queue loader (biar hub auto jalan lagi abis rejoin) lalu
     teleport ke server yg SAMA (reconnect), fallback server baru kalau gagal.
     Config: CFG.reconnectEnabled (toggle), CFG.reconnectInterval (menit).
     Fungsi: ctx.startReconnect. Auto-resume di app.lua biar loop lanjut tiap masuk. ]]
return function(ctx)
	local LP  = ctx.LP
	local CFG = ctx.CFG
	local TeleportService = game:GetService("TeleportService")
	local function setStatus(s) ctx.setStatus(s) end

	local branch = (getgenv and getgenv().GAG_BRANCH) or _G.GAG_BRANCH or "main"

	-- queue loader hub biar auto jalan lagi setelah rejoin (branch dijaga).
	local function queueLoader()
		local q = (syn and syn.queue_on_teleport) or queue_on_teleport
			or (fluxus and fluxus.queue_on_teleport) or (getgenv and getgenv().queue_on_teleport)
		if q then
			local cmd = ('if getgenv then getgenv().GAG_BRANCH=%q end loadstring(game:HttpGet("https://raw.githubusercontent.com/catursec/tanduran/%s/kebongedang/init.lua"))()'):format(branch, branch)
			pcall(function() q(cmd) end)
		end
	end

	-- Cache reference Teleport SEKARANG (bukan pas dipanggil) biar bypass hook
	-- __namecall yg mungkin dipasang game buat block teleport pihak-3.
	local TeleportFn = TeleportService.Teleport

	local function doReconnect()
		queueLoader()
		task.wait(0.4)
		-- Teleport(placeId, player) via cached-ref. Pas di private server, Roblox
		-- rejoin ke private server juga (bukan publik) -> stay private. Kalau di
		-- server publik, ke publik. TeleportToPlaceInstance JANGAN dipakai (773 +
		-- diblok buat private).
		local ok = pcall(function() TeleportFn(TeleportService, game.PlaceId, LP) end)
		if not ok then
			pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
		end
	end

	local function reconnectLoop(myId)
		while CFG.reconnectEnabled and ctx.alive() and ctx.state.reconnectId == myId do
			local mins = tonumber(CFG.reconnectInterval) or 5
			if mins <= 0 then mins = 5 end
			local total = mins * 60
			local t0 = os.clock()
			while os.clock() - t0 < total do
				if not CFG.reconnectEnabled or ctx.state.reconnectId ~= myId or not ctx.alive() then
					ctx.state.reconnectRemaining = nil; return
				end
				local rem = math.ceil(total - (os.clock() - t0))
				ctx.state.reconnectRemaining = rem
				setStatus(("Reconnect: %d dtk lagi"):format(rem))
				task.wait(1)
			end
			if CFG.reconnectEnabled and ctx.state.reconnectId == myId then
				setStatus("Reconnect: rejoin...")
				doReconnect()
				return -- instance ini bakal ilang setelah teleport
			end
		end
	end

	function ctx.startReconnect()
		ctx.state.reconnectId = (ctx.state.reconnectId or 0) + 1
		local myId = ctx.state.reconnectId
		task.spawn(function() reconnectLoop(myId) end)

		-- Listener DISCONNECT: rejoin pas kena error/kick/server shutdown.
		-- ErrorMessageChanged nyala pas dialog error/disconnect muncul.
		-- Slot global biar ga numpuk antar-reload (disconnect yg lama dulu).
		if _G.__AH_ReconnectDC then pcall(function() _G.__AH_ReconnectDC:Disconnect() end) end
		pcall(function()
			local GuiService = game:GetService("GuiService")
			_G.__AH_ReconnectDC = GuiService.ErrorMessageChanged:Connect(function()
				if CFG.reconnectEnabled then
					setStatus("Reconnect: disconnect kedetect, rejoin...")
					task.wait(1)
					doReconnect()
				end
			end)
		end)
	end
end
