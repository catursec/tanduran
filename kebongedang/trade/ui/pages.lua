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
