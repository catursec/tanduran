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
