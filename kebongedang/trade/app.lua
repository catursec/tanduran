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
