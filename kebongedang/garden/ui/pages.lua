--[[ pages.lua — halaman garden. Tab: Pet, Elephant, Growth, Leveling, Mutation, Event, Inventory, Shop, Misc.
     Isi utama ada di tab Inventory (Automation Trade + Automation Accept + Automation Favourite). ]]
return function(ctx)
	local C = ctx.C
	local F = ctx.F
	local CFG = ctx.CFG
	local mk, corner, stroke, pad = ctx.mk, ctx.corner, ctx.stroke, ctx.pad
	local persist = ctx.persistState
	local reg = ctx.reg
	local function log(m) ctx.log(m) end

	-- True kalau GuiObject benar-benar kelihatan di layar (tab aktif + accordion kebuka
	-- + window ga diminimize). Dipakai supaya loop status berhenti hitung/redraw label
	-- yang lagi nggak dilihat — cegah layout-thrashing yang bikin CPU naik.
	local function onScreen(o)
		while o and o ~= game do
			if o:IsA("GuiObject") and not o.Visible then return false end
			o = o.Parent
		end
		return o == game
	end

	local makePage = ctx.makePage
	local makeAccordion = ctx.makeAccordion
	local makeToggle = ctx.makeToggle
	local makeInput = ctx.makeInput
	local makeSingleDropdown = ctx.makeSingleDropdown
	local makeMultiDropdown = ctx.makeMultiDropdown
	local makeMultiDropdownDyn = ctx.makeMultiDropdownDyn
	local makeButton = ctx.makeButton

	-- sidebar tabs (urut sesuai referensi)
	local TABS = {
		{ "Pet", "Pet", "🐾" },
		{ "Farm", "Farm", "🌾" },
		{ "Elephant", "Elephant", "🐘" },
		{ "Growth", "Growth", "🌱" },
		{ "Hatch", "Hatch", "🥚" },
		{ "Leveling", "Leveling", "⚡" },
		{ "Mutation", "Mutation", "🧪" },
		{ "Event", "Event", "☀️" },
		{ "Inventory", "Inventory", "🎒" },
		{ "Shop", "Shop", "🛒" },
		{ "Misc", "Misc", "⚙️" },
	}
	local pageRef = {}
	for i, t in ipairs(TABS) do
		pageRef[t[1]] = makePage(t[1], t[2], t[3], i)
	end

	-- placeholder untuk tab yang belum diisi
	local function placeholder(page)
		local box = mk("Frame", { Size = UDim2.new(1, 0, 0, 90), BackgroundColor3 = C.row, LayoutOrder = 1 }, page)
		corner(box, 8); stroke(box); pad(box, 14, 14, 12, 12)
		mk("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "Fitur untuk tab ini belum tersedia.", Font = F.reg, TextSize = 13, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, box)
	end
	------------------------------------------------------------------ FARM
	do
		local farmPage = pageRef["Farm"]

		-- Automation Plants (fitur aktif): pilih seed + posisi + delay + toggle
		local plAcc = makeAccordion(farmPage, "Automation Plants", 1, false)
		makeMultiDropdownDyn(plAcc, "Select Seeds", "Pilih seed dari inventory (angka = jumlah).",
			function() return ctx.getPlantSeedOptions() end, CFG.plantSeedNames, function() persist() end, 1)
		makeSingleDropdown(plAcc, "Select Position", "Lokasi tanam di farm.",
			function() return { "Random", "Player Position" } end,
			function() return CFG.plantPosition end,
			function(v) CFG.plantPosition = v; persist() end, 2)
		makeInput(plAcc, "Delay To Plants", "Extra delay (detik) tiap tanam seed.",
			function() return tostring(CFG.plantDelay) end,
			function(t) CFG.plantDelay = tonumber(t) or 0; persist() end, 3)
		makeToggle(plAcc, "Auto Plants Seed", "Tanam seed terpilih otomatis.",
			function() return CFG.plantSeedEnabled end,
			function(v) CFG.plantSeedEnabled = v; persist(); if v and ctx.startPlant then ctx.startPlant() end end, 4)

		-- Automation Sprinkler (fitur aktif): pasang sprinkler + shovel sprinkler
		local sprAcc = makeAccordion(farmPage, "Automation Sprinkler", 2, false)
		makeMultiDropdownDyn(sprAcc, "Select Sprinkler", "Sprinkler yg mau dipasang (angka = jumlah).",
			function() return ctx.getSprinklerOptions() end, CFG.sprinklerNames, function() persist() end, 1)
		makeMultiDropdownDyn(sprAcc, "Select Sprinkler Plants", "Pasang dekat plant ini. Kosong = pakai Position.",
			function() return ctx.getSprinklerPlantOptions() end, CFG.sprinklerPlantNames, function() persist() end, 2)
		makeSingleDropdown(sprAcc, "Select Sprinkler Position", "Lokasi pasang kalau Plants kosong.",
			function() return { "Random", "Player Position" } end,
			function() return CFG.sprinklerPosition end,
			function(v) CFG.sprinklerPosition = v; persist() end, 3)
		makeInput(sprAcc, "Delay To Sprinkler", "Extra delay (detik) tiap pasang.",
			function() return tostring(CFG.sprinklerDelay) end,
			function(t) CFG.sprinklerDelay = tonumber(t) or 0; persist() end, 4)
		makeToggle(sprAcc, "Auto Sprinkler", "Pasang sprinkler terpilih otomatis.",
			function() return CFG.sprinklerEnabled end,
			function(v) CFG.sprinklerEnabled = v; persist(); if v and ctx.startSprinkler then ctx.startSprinkler() end end, 5)

		-- sub-accordion: Sprinkler Shovel (cabut sprinkler terpasang, butuh Shovel)
		local shAcc = makeAccordion(sprAcc, "Sprinkler Shovel", 6, false)
		makeMultiDropdownDyn(shAcc, "Select Shovel Sprinkler", "Jenis sprinkler terpasang yg mau dicabut. 'All' = semua.",
			function() return ctx.getShovelSprinklerOptions() end, CFG.shovelSprinklerNames, function() persist() end, 1)
		makeInput(shAcc, "Delay To Shovel Sprinkler", "Extra delay (detik) tiap cabut.",
			function() return tostring(CFG.shovelSprinklerDelay) end,
			function(t) CFG.shovelSprinklerDelay = tonumber(t) or 0; persist() end, 2)
		makeToggle(shAcc, "Auto Shovel Sprinkler", "Cabut sprinkler terpilih otomatis (equip Shovel).",
			function() return CFG.shovelSprinklerEnabled end,
			function(v) CFG.shovelSprinklerEnabled = v; persist(); if v and ctx.startShovelSprinkler then ctx.startShovelSprinkler() end end, 3)

		-- Automation Water (fitur aktif): siram plant terpilih pakai Watering Can (Water_RE)
		local watAcc = makeAccordion(farmPage, "Automation Water", 3, false)
		makeMultiDropdownDyn(watAcc, "Select Water Fruits", "Pilih fruit/plant yang mau disiram. 'All' = semua.",
			function() return ctx.getWaterFruitOptions() end, CFG.waterFruitNames, function() persist() end, 1)
		makeInput(watAcc, "Delay to Water", "Extra delay (detik) tiap siklus siram.",
			function() return tostring(CFG.waterDelay) end,
			function(t) CFG.waterDelay = tonumber(t) or 1; persist() end, 2)
		makeToggle(watAcc, "Auto Water Fruits", "Siram fruit terpilih otomatis.",
			function() return CFG.waterEnabled end,
			function(v) CFG.waterEnabled = v; persist(); if v and ctx.startWater then ctx.startWater() end end, 3)

		-- Automation Shovel (fitur aktif): shovel tree/plant + shovel fruit (filter)
		local shvAcc = makeAccordion(farmPage, "Automation Shovel", 4, false)
		makeMultiDropdownDyn(shvAcc, "Select Tree", "Pilih tree/plant yang mau di-shovel. 'All' = semua.",
			function() return ctx.getShovelTreeOptions() end, CFG.shovelTreeNames, function() persist() end, 1)
		makeInput(shvAcc, "Delay To Shovel Tree", "Extra delay (detik) tiap siklus shovel tree.",
			function() return tostring(CFG.shovelTreeDelay) end,
			function(t) CFG.shovelTreeDelay = tonumber(t) or 0; persist() end, 2)
		makeToggle(shvAcc, "Auto Shovel Tree", "Shovel tree/plant terpilih otomatis.",
			function() return CFG.shovelTreeEnabled end,
			function(v) CFG.shovelTreeEnabled = v; persist(); if v and ctx.startShovelTree then ctx.startShovelTree() end end, 3)

		-- sub: Fruits Shovel (shovel plant kalau fruit-nya cocok filter)
		local frShv = makeAccordion(shvAcc, "Fruits Shovel", 4, false)
		makeMultiDropdownDyn(frShv, "Select Shovel Fruits", "Tipe fruit yang mau di-shovel. 'All' = semua.",
			function() return ctx.getShovelFruitOptions() end, CFG.shovelFruitNames, function() persist() end, 1)
		makeMultiDropdownDyn(frShv, "Select Shovel Mutation", "Filter mutasi. Kosong/'All' = abaikan.",
			function() return ctx.getShovelMutationOptions() end, CFG.shovelFruitMuts, function() persist() end, 2)
		makeMultiDropdownDyn(frShv, "Select Shovel Variant", "Filter variant (Gold/Rainbow/dll). Kosong/'All' = abaikan.",
			function() return ctx.getShovelVariantOptions() end, CFG.shovelFruitVariants, function() persist() end, 3)
		makeSingleDropdown(frShv, "Select Shovel Threshold Mode", "Cara banding berat fruit.",
			function() return ctx.getShovelModeOptions() end,
			function() return CFG.shovelFruitMode end,
			function(v) CFG.shovelFruitMode = v; persist() end, 4)
		makeInput(frShv, "Shovel Weight Threshold", "Kalau ga mau pakai, isi '0'.",
			function() return tostring(CFG.shovelFruitWeight) end,
			function(t) CFG.shovelFruitWeight = tonumber(t) or 0; persist() end, 5)
		makeInput(frShv, "Delay To Shovel Fruit", "Extra delay (detik) tiap siklus shovel fruit.",
			function() return tostring(CFG.shovelFruitDelay) end,
			function(t) CFG.shovelFruitDelay = tonumber(t) or 0; persist() end, 6)
		makeToggle(frShv, "Auto Shovel Fruits", "Shovel plant yang fruit-nya cocok filter.",
			function() return CFG.shovelFruitEnabled end,
			function(v) CFG.shovelFruitEnabled = v; persist(); if v and ctx.startShovelFruit then ctx.startShovelFruit() end end, 7)

		-- Accordion yg masih kerangka (belum diisi)
		-- Automation Collection (fitur aktif): auto harvest fruit (3 mode whitelist)
		local colAcc = makeAccordion(farmPage, "Automation Collection", 5, false)
		makeInput(colAcc, "Delay To Collect", "Extra delay (detik) tiap siklus collect.",
			function() return tostring(CFG.collectDelay) end,
			function(t) CFG.collectDelay = tonumber(t) or 0; persist() end, 1)
		makeToggle(colAcc, "Stop Collect If Backpack Is Full Max", "Stop collect pas backpack penuh.",
			function() return CFG.collectStopIfFull end,
			function(v) CFG.collectStopIfFull = v; persist() end, 2)
		makeToggle(colAcc, "Auto Sell Fruit If Backpack Full", "Jual semua fruit pas backpack penuh.",
			function() return CFG.collectAutoSellIfFull end,
			function(v) CFG.collectAutoSellIfFull = v; persist() end, 3)

		-- sub: Whitelist Fruit
		local colWf = makeAccordion(colAcc, "Collect Whitelist Fruit", 4, false)
		makeMultiDropdownDyn(colWf, "Select Whitelist Fruit", "Pilih tipe fruit yang mau di-collect.",
			function() return ctx.getCollectFruitOptions() end, CFG.collectWlFruitNames, function() persist() end, 1)
		makeToggle(colWf, "Auto Collect Whitelisted Fruits", "Collect cuma tipe fruit yang di-whitelist.",
			function() return CFG.collectWlFruitEnabled end,
			function(v) CFG.collectWlFruitEnabled = v; persist(); if v and ctx.startCollect then ctx.startCollect() end end, 2)

		-- sub: Whitelist Mutation
		local colWm = makeAccordion(colAcc, "Collect Whitelist Mutation", 5, false)
		makeMultiDropdownDyn(colWm, "Select Whitelist Mutations", "Pilih mutasi yang mau di-collect.",
			function() return ctx.getCollectMutationOptions() end, CFG.collectWlMutNames, function() persist() end, 1)
		makeToggle(colWm, "Auto Collect Whitelisted Mutations", "Collect cuma fruit dgn mutasi yang di-whitelist.",
			function() return CFG.collectWlMutEnabled end,
			function(v) CFG.collectWlMutEnabled = v; persist(); if v and ctx.startCollect then ctx.startCollect() end end, 2)

		-- sub: Combined (semua kriteria)
		local colCb = makeAccordion(colAcc, "Collect Whitelist Combined", 6, false)
		makeMultiDropdownDyn(colCb, "Select Combined Fruits", "Filter by fruit type.",
			function() return ctx.getCollectFruitOptions() end, CFG.collectCombFruitNames, function() persist() end, 1)
		makeMultiDropdownDyn(colCb, "Select Combined Mutation", "Filter by mutation type.",
			function() return ctx.getCollectMutationOptions() end, CFG.collectCombMutNames, function() persist() end, 2)
		makeMultiDropdownDyn(colCb, "Select Combined Variant", "Filter by variant type.",
			function() return ctx.getCollectVariantOptions() end, CFG.collectCombVariants, function() persist() end, 3)
		makeSingleDropdown(colCb, "Whitelist Weight Mode", "Cara banding berat fruit.",
			function() return ctx.getCollectModeOptions() end,
			function() return CFG.collectCombMode end,
			function(v) CFG.collectCombMode = v; persist() end, 4)
		makeInput(colCb, "Whitelist Weight", "Kalau ga dipakai, isi '0'.",
			function() return tostring(CFG.collectCombWeight) end,
			function(t) CFG.collectCombWeight = tonumber(t) or 0; persist() end, 5)
		makeToggle(colCb, "Auto Collect Fruits", "Collect fruit yang cocok SEMUA kriteria combined.",
			function() return CFG.collectCombEnabled end,
			function(v) CFG.collectCombEnabled = v; persist(); if v and ctx.startCollect then ctx.startCollect() end end, 6)

		-- Automation Favorite (fitur aktif): favorite/unfavorite fruit via Favorite Tool
		local favAcc = makeAccordion(farmPage, "Automation Favorite", 6, false)
		makeMultiDropdownDyn(favAcc, "Select Fruits", "Tipe fruit di garden buat di-favorite (kosong = any).",
			function() return ctx.getFavFruitOptions() end, CFG.favFruitNames, function() persist() end, 1)
		makeMultiDropdownDyn(favAcc, "Filter Mutations", "Mutasi yang diperluin (kosong = mutasi apapun OK).",
			function() return ctx.getFavMutationOptions() end, CFG.favMutNames, function() persist() end, 2)
		makeSingleDropdown(favAcc, "Weight Mode", "Banding berat fruit (kosong = off).",
			function() return ctx.getFavModeOptions() end,
			function() return CFG.favMode end,
			function(v) CFG.favMode = v; persist() end, 3)
		makeInput(favAcc, "Weight Value", "Threshold berat (0 = off).",
			function() return tostring(CFG.favWeight) end,
			function(t) CFG.favWeight = tonumber(t) or 0; persist() end, 4)
		makeInput(favAcc, "Delay To Favorite", "Detik tiap siklus scan favorite.",
			function() return tostring(CFG.favDelay) end,
			function(t) CFG.favDelay = tonumber(t) or 1; persist() end, 5)
		makeToggle(favAcc, "Auto Favorite Fruits", "Favorite fruit garden yang cocok filter.",
			function() return CFG.favEnabled end,
			function(v) CFG.favEnabled = v; persist(); if v and ctx.startFavorite then ctx.startFavorite() end end, 6)
		makeToggle(favAcc, "Auto Unfavorite Fruits", "Unfavorite fruit garden yang cocok filter.",
			function() return CFG.unfavEnabled end,
			function(v) CFG.unfavEnabled = v; persist(); if v and ctx.startFavorite then ctx.startFavorite() end end, 7)

		-- Automation Reclaimer (fitur aktif): pilih plant + toggle auto reclaim
		local recAcc = makeAccordion(farmPage, "Automation Reclaimer", 7, false)
		makeMultiDropdownDyn(recAcc, "Select Plants", "Pilih plant yg mau di-reclaim. 'All' = semua.",
			function() return ctx.getReclaimPlantOptions() end, CFG.reclaimPlantNames, function() persist() end, 1)
		makeToggle(recAcc, "Auto Reclaimer Plants", "Auto reclaim plant terpilih pakai tool Reclaimer",
			function() return CFG.reclaimEnabled end,
			function(v) CFG.reclaimEnabled = v; persist(); if v and ctx.startReclaim then ctx.startReclaim() end end, 2)
	end

	------------------------------------------------------------------ GROWTH (pipeline batch per-step)
	do
		local growthPage = pageRef["Growth"]
		local FLOW_OPTS = { { name = "none", display = "None (kosong)" }, { name = "elephant", display = "Elephant" }, { name = "mutation", display = "Mutation" }, { name = "leveling", display = "Leveling" }, { name = "leveling_p1", display = "Leveling Phase 1" }, { name = "leveling_p2", display = "Leveling Phase 2" } }
		local function capStep(s) for _, o in ipairs(FLOW_OPTS) do if o.name == s then return o.display end end return "Select" end

		-- Growth Control (status + target + enable)
		local gCtrl = makeAccordion(growthPage, "Growth Control", 1, true)
		local gLbl = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = "Loading...", Font = F.reg, TextSize = 13, TextColor3 = C.txt, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, LineHeight = 1.35, RichText = true, LayoutOrder = 0 }, gCtrl)
		mk("Frame", { Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, LayoutOrder = 1 }, gCtrl)
		task.spawn(function()
			while ctx.alive() do
				if not onScreen(growthPage) then task.wait(1) continue end
				local ok, s = pcall(function() return ctx.getGrowthSummary() end)
				if ok and s then
					local col = s.status == "ACTIVE" and "#5acc78" or "#dc5050"
					local steps = ""
					for _, st in ipairs({ "elephant", "mutation", "leveling" }) do
						local ps = s.perStep[st]
						if ps then steps = steps .. ("%s: <font color=\"#8c929e\">%d/%d</font>\n"):format(st, ps.done, ps.total) end
					end
					gLbl.Text = string.format(
						"Status: <font color=\"%s\"><b>%s</b></font>  |  <font color=\"#f5c82d\">%s</font>\n" ..
						"Flow: <font color=\"#8c929e\">%s</font>\nTarget: <font color=\"#8c929e\">%s</font>\n\n%s\n" ..
						"Team Elephant: <font color=\"#8c929e\">%s</font>\n" ..
						"Team Mutation: <font color=\"#8c929e\">%s</font>\n" ..
						"Team Leveling P1: <font color=\"#8c929e\">%s</font>\n" ..
						"Team Leveling P2: <font color=\"#8c929e\">%s</font>",
						col, s.status, s.step, s.flow, s.types, steps,
						s.teamElephant or "-", s.teamMutation or "-", s.teamLevP1 or "-", s.teamLevP2 or "-")
				end
				task.wait(1.5)
			end
		end)
		makeMultiDropdown(gCtrl, "Growth Target Pet Types (Default)", "Target default; dipakai step yg target per-method-nya kosong",
			reg.PET_OPTIONS, CFG.growthPetTypes, function() persist() end, 2)
		makeToggle(gCtrl, "Enable Growth", "Jalankan pipeline (batch per-step sesuai flow)",
			function() return CFG.growthEnabled end,
			function(v) CFG.growthEnabled = v; persist(); if v then ctx.startGrowth() else ctx.stopGrowth() end end, 3)

		-- Configuration Auto Elephant
		local gEle = makeAccordion(growthPage, "Configuration Auto Elephant", 2, true)
		makeMultiDropdown(gEle, "Elephant Target Pet Types", "Target khusus step Elephant (kosong = pakai Default)",
			reg.PET_OPTIONS, CFG.growthPetTypesElephant, function() persist() end, 0)
		makeMultiDropdownDyn(gEle, "Elephant Pet Team", "Team aura buat grow weight",
			function() return ctx.inventoryPetOptions(CFG.growthElephantTeam) end, CFG.growthElephantTeam, function() persist() end, 1)
		makeInput(gEle, "Target Weight (KG)", "Berat target sebelum lanjut step berikutnya (mis. 5.5)",
			function() return tostring(CFG.growthElephantWeight) end, function(t) CFG.growthElephantWeight = tonumber(t) or 5.5; persist() end, 2)
		makeInput(gEle, "Max Target Pets", "Max pet target di garden (step Elephant)",
			function() return tostring(CFG.growthElephantMax) end, function(t) CFG.growthElephantMax = tonumber(t) or 2; persist() end, 3)

		-- Configuration Auto Mutation
		local gMut = makeAccordion(growthPage, "Configuration Auto Mutation", 3, true)
		makeMultiDropdown(gMut, "Mutation Target Pet Types", "Target khusus step Mutation (kosong = pakai Default)",
			reg.PET_OPTIONS, CFG.growthPetTypesMutation, function() persist() end, 0)
		makeMultiDropdownDyn(gMut, "Mutation Pet Team", "Team aura pemberi mutasi",
			function() return ctx.inventoryPetOptions(CFG.growthMutationTeam) end, CFG.growthMutationTeam, function() persist() end, 1)
		makeMultiDropdown(gMut, "Target Mutations", "Mutasi yang diinginkan (mutasi salah -> auto cleanse)",
			reg.MUT_OPTIONS, CFG.growthMutationTargets, function() persist() end, 2)
		makeInput(gMut, "Max Target Pets", "Max pet target di garden (step Mutation)",
			function() return tostring(CFG.growthMutationMax) end, function(t) CFG.growthMutationMax = tonumber(t) or 2; persist() end, 3)

		-- Configuration Auto Leveling (2 phase)
		local gLev = makeAccordion(growthPage, "Configuration Auto Leveling", 4, true)
		makeMultiDropdown(gLev, "Leveling Target Pet Types", "Target khusus step Leveling (kosong = pakai Default)",
			reg.PET_OPTIONS, CFG.growthPetTypesLeveling, function() persist() end, 0)
		makeMultiDropdownDyn(gLev, "Leveling Phase 1 Pet Team", "Team for Phase 1 (Age 1 to Phase 1 Target)",
			function() return ctx.inventoryPetOptions(CFG.growthLevP1Team) end, CFG.growthLevP1Team, function() persist() end, 1)
		makeInput(gLev, "Leveling Phase 1 Target", "End of Phase 1 / start of Phase 2 (default 40)",
			function() return tostring(CFG.growthLevP1Target) end, function(t) CFG.growthLevP1Target = tonumber(t) or 40; persist() end, 2)
		makeInput(gLev, "Leveling Phase 1 Max Pets", "Max target pets in garden during Phase 1",
			function() return tostring(CFG.growthLevP1Max) end, function(t) CFG.growthLevP1Max = tonumber(t) or 3; persist() end, 3)
		makeMultiDropdownDyn(gLev, "Leveling Phase 2 Pet Team", "Team for Phase 2 (Phase 1 Target to Final Target)",
			function() return ctx.inventoryPetOptions(CFG.growthLevP2Team) end, CFG.growthLevP2Team, function() persist() end, 4)
		makeInput(gLev, "Leveling Phase 2 Target", "Final target level (default 500 = max age)",
			function() return tostring(CFG.growthLevP2Target) end, function(t) CFG.growthLevP2Target = tonumber(t) or 500; persist() end, 5)
		makeInput(gLev, "Leveling Phase 2 Max Pets", "Max target pets in garden during Phase 2",
			function() return tostring(CFG.growthLevP2Max) end, function(t) CFG.growthLevP2Max = tonumber(t) or 1; persist() end, 6)

		-- Configuration Flow (Step 1/2/3)
		local gFlow = makeAccordion(growthPage, "Configuration Flow", 5, true)
		local stepDesc = { "First step in growth flow", "Second step in growth flow", "Third step in growth flow", "Fourth step in growth flow", "Fifth step in growth flow", "Sixth step in growth flow", }
		for i = 1, 6 do
			makeSingleDropdown(gFlow, "Step " .. i, stepDesc[i],
				function() return FLOW_OPTS end,
				function() return capStep((CFG.growthFlow or {})[i]) end,
				function(code) CFG.growthFlow = CFG.growthFlow or {}; CFG.growthFlow[i] = code; persist() end, i)
		end
	end

	------------------------------------------------------------------ HATCH (auto hatch + auto sell)
	do
		local hatchPage = pageRef["Hatch"]

		-- Status & Control
		local hCtrl = makeAccordion(hatchPage, "Status & Control", 1, false)
		local hLbl = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = "Loading...", Font = F.reg, TextSize = 13, TextColor3 = C.txt, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, LineHeight = 1.35, RichText = true, LayoutOrder = 0 }, hCtrl)
		mk("Frame", { Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, LayoutOrder = 1 }, hCtrl)
		task.spawn(function()
			while ctx.alive() do
				if not onScreen(hatchPage) then task.wait(1) continue end
				local ok, s = pcall(function() return ctx.getHatchSummary() end)
				if ok and s then
					local col = s.status == "RUNNING" and "#5acc78" or "#dc5050"
					local gr = "#b8bdc7"
					hLbl.Text = string.format(
						"<b>Live Status</b>\n" ..
						"Status: <font color=\"%s\"><b>%s</b></font>\nPhase: <font color=\"#f5c82d\">%s</font>\n\n" ..
						"Core Team: <font color=\"%s\">%s</font>\nHatch Team: <font color=\"%s\">%s</font>\n" ..
						"Bronto Team: <font color=\"%s\">%s</font>\nSell Team: <font color=\"%s\">%s</font>\n\n" ..
						"Pet on Backpack: <font color=\"%s\">%d/%d</font>\n\n" ..
						"Current Egg: <font color=\"%s\">%s</font>\nEgg Before: <font color=\"%s\">%d</font>\n" ..
						"Current Amount: <font color=\"%s\">%d</font>\nPlaced: <font color=\"%s\">%d/%d</font>\n" ..
						"Eggs Hatched: <font color=\"%s\">%d</font>\nSell Cycle: <font color=\"%s\">%d/%d</font>\n\n" ..
						"<b>Recovery Stat (dari Team)</b>\n" ..
						"Koi (hatch): <font color=\"%s\">%d ekor \226\134\146 %.1f%%</font>\n" ..
						"Seal (sell): <font color=\"%s\">%d ekor \226\134\146 %.1f%%</font>",
						col, s.status, s.phase,
						gr, s.core, gr, s.hatch, gr, s.bronto, gr, s.sell,
						gr, s.backpack, s.maxBackpack,
						gr, s.currentEgg, gr, s.eggBefore, gr, s.currentAmount, gr, s.placed, s.maxPlaced,
						gr, s.eggsHatched, gr, s.cycleProg, s.cycleTarget,
						gr, (s.proc or {}).koiCount or 0, (s.proc or {}).koiPct or 0,
						gr, (s.proc or {}).sealCount or 0, (s.proc or {}).sealPct or 0)
				end
				task.wait(1.0)
			end
		end)
		makeToggle(hCtrl, "Auto Hatch", "Start/Stop auto hatching (equip Hatch team + hatch egg ready)",
			function() return CFG.hatchEnabled end,
			function(v) CFG.hatchEnabled = v; persist(); if v then ctx.startHatch() else ctx.stopHatch() end end, 2)
		makeToggle(hCtrl, "Auto Sell", "Auto jual pet pas backpack penuh (filter + favorite proteksi)",
			function() return CFG.autoSellEnabled end, function(v) CFG.autoSellEnabled = v; persist() end, 3)

		-- Teams
		local hTeam = makeAccordion(hatchPage, "Teams (Core / Hatch / Bronto / Sell)", 2, true)
		makeMultiDropdownDyn(hTeam, "Core Team", "Percepat egg (incubation speed)",
			function() return ctx.inventoryPetOptions(CFG.hatchCoreTeam) end, CFG.hatchCoreTeam, function() persist() end, 1)
		makeMultiDropdownDyn(hTeam, "Hatch Team", "Hatch egg ready (Koi = balikin egg)",
			function() return ctx.inventoryPetOptions(CFG.hatchHatchTeam) end, CFG.hatchHatchTeam, function() persist() end, 2)
		makeMultiDropdownDyn(hTeam, "Bronto Team", "+30% berat pet pas hatch (Brontosaurus)",
			function() return ctx.inventoryPetOptions(CFG.hatchBrontoTeam) end, CFG.hatchBrontoTeam, function() persist() end, 3)
		makeMultiDropdownDyn(hTeam, "Sell Team", "Jual + balikin pet jadi egg (Seal the Deal)",
			function() return ctx.inventoryPetOptions(CFG.hatchSellTeam) end, CFG.hatchSellTeam, function() persist() end, 4)

		-- Egg Configuration
		local hEgg = makeAccordion(hatchPage, "Egg Configuration", 3, true)
		makeSingleDropdown(hEgg, "Egg to Hatch", "Egg dari backpack yg di-place & di-hatch (+ jumlah)",
			function() return ctx.getEggBackpackOptions() end,
			function() return tostring(CFG.hatchEggName or "") end,
			function(code) CFG.hatchEggName = code; persist() end, 1)
		makeSingleDropdown(hEgg, "Placement Pattern", "Pola taro egg: Grid (rapih) / Random (sebar acak)",
			function() return { "Grid", "Random" } end,
			function() return CFG.hatchPlacePattern or "Grid" end,
			function(code) CFG.hatchPlacePattern = code; persist() end, 2)
		makeInput(hEgg, "Max Placed", "Maksimal egg ke-place di garden",
			function() return tostring(CFG.hatchMaxPlaced) end, function(t) CFG.hatchMaxPlaced = tonumber(t) or 9; persist() end, 3)
		makeInput(hEgg, "Hatch Team Delay (sec)", "Tunggu abis swap team sebelum hatch",
			function() return tostring(CFG.hatchTeamDelay or 3) end, function(t) CFG.hatchTeamDelay = tonumber(t) or 3; persist() end, 4)

		-- Bronto Configuration (kapan pakai Bronto team buat +30% berat)
		local hBr = makeAccordion(hatchPage, "Bronto Configuration", 4, true)
		makeMultiDropdown(hBr, "Special Pets", "Pet yg WAJIB di-hatch pakai Bronto team",
			reg.PET_EGG_ONLY, CFG.brontoSpecialPets, function() persist() end, 1)
		makeInput(hBr, "Special Pets Weight Filter", "Special cuma kalau weight > ini (0 = ga difilter)",
			function() return tostring(CFG.brontoSpecialWeight) end, function(t) CFG.brontoSpecialWeight = tonumber(t) or 0; persist() end, 2)
		makeMultiDropdown(hBr, "Universal Weight Pet Types", "Tipe pet buat aturan universal (kosong = semua). Tampil dgn tipe egg-nya.",
			reg.PET_EGG_ONLY, CFG.brontoUniversalTypes, function() persist() end, 3)
		makeInput(hBr, "Universal Weight Threshold", "Pakai Bronto team kalau weight > ini (0 = off)",
			function() return tostring(CFG.brontoUniversalWeight) end, function(t) CFG.brontoUniversalWeight = tonumber(t) or 0; persist() end, 4)
		makeToggle(hBr, "Don't Hatch Special Pets", "Skip special pet sama sekali (jangan di-hatch)",
			function() return CFG.brontoSkipSpecial end, function(v) CFG.brontoSkipSpecial = v; persist() end, 5)
		makeInput(hBr, "Bronto Team Delay (sec)", "Tunggu abis swap team sebelum hatch bronto",
			function() return tostring(CFG.brontoTeamDelay or 5) end, function(t) CFG.brontoTeamDelay = tonumber(t) or 5; persist() end, 6)

		-- Sell Configuration
		local hSell = makeAccordion(hatchPage, "Sell Configuration", 5, true)
		makeMultiDropdown(hSell, "Pets to Sell", "Tipe pet yg DIJUAL (sisanya difavoritin biar aman)",
			reg.PET_EGG_OPTIONS, CFG.sellPetTypes, function() persist() end, 1)
		makeInput(hSell, "Sell Weight Threshold", "Jual kalau base weight < ini",
			function() return tostring(CFG.sellWeightThreshold) end, function(t) CFG.sellWeightThreshold = tonumber(t) or 4; persist() end, 2)
		makeInput(hSell, "Sell Age Threshold", "Jual kalau age < ini",
			function() return tostring(CFG.sellAgeThreshold) end, function(t) CFG.sellAgeThreshold = tonumber(t) or 3; persist() end, 3)
		makeMultiDropdown(hSell, "Special Pets to Sell", "Pet spesial (jual by weight)",
			reg.PET_EGG_ONLY, CFG.sellSpecialTypes, function() persist() end, 4)
		makeInput(hSell, "Special Pet Weight Threshold", "Jual pet spesial dgn weight < ini (0=off)",
			function() return tostring(CFG.sellSpecialWeight) end, function(t) CFG.sellSpecialWeight = tonumber(t) or 10; persist() end, 5)
		local SELLMODE = { { name = "Cycle", display = "Cycle" }, { name = "Backpack", display = "Backpack" } }
		makeSingleDropdown(hSell, "Sell Mode", "Kapan trigger jual",
			function() return SELLMODE end, function() return CFG.sellMode or "Cycle" end,
			function(code) CFG.sellMode = code; persist() end, 6)
		local SELLSTYLE = { { name = "All at Once", display = "All at Once" }, { name = "One by One", display = "One by One" } }
		makeSingleDropdown(hSell, "Sell Style", "All at Once = jual semua matched sekaligus",
			function() return SELLSTYLE end, function() return CFG.sellStyle or "All at Once" end,
			function(code) CFG.sellStyle = code; persist() end, 7)
		makeInput(hSell, "Sell Every N Cycles", "Jual tiap N cycle hatch",
			function() return tostring(CFG.sellEveryNCycles) end, function(t) CFG.sellEveryNCycles = tonumber(t) or 1; persist() end, 8)
		makeInput(hSell, "Sell When Pets Reach", "Jual kalau backpack pet >= ini",
			function() return tostring(CFG.sellWhenReach) end, function(t) CFG.sellWhenReach = tonumber(t) or 100; persist() end, 9)
		makeInput(hSell, "Sell Team Delay (sec)", "Tunggu abis swap team sebelum jual",
			function() return tostring(CFG.sellTeamDelay) end, function(t) CFG.sellTeamDelay = tonumber(t) or 5; persist() end, 10)
		makeToggle(hSell, "Auto Boost Before Sell", "Boost pet aktif pakai toy sebelum jual",
			function() return CFG.autoBoostBeforeSell end, function(v) CFG.autoBoostBeforeSell = v; persist() end, 11)
		makeButton(hSell, "Sell Now (manual)", "Jalankan sell sekali sekarang",
			function() task.spawn(function() pcall(ctx.hatchDoSell) end) end, 12)
	end

	------------------------------------------------------------------ SHOP
	do
		local shopPage = pageRef["Shop"]

		local seedAcc = makeAccordion(shopPage, "Automation Buy Seed", 1, false)
		makeMultiDropdownDyn(seedAcc, "Select Seeds to Buy", "Pilih seed buat auto-beli (stock realtime)",
			function() return ctx.getSeedShopOptions(CFG.buySeedNames) end, CFG.buySeedNames, function() persist() end, 1)
		makeToggle(seedAcc, "Enable Automation Buy Seed", "Auto-beli seed terpilih tiap ada stock",
			function() return CFG.buySeedEnabled end,
			function(v) CFG.buySeedEnabled = v; persist(); if v then ctx.startBuySeed() end end, 2)

		local eggAcc = makeAccordion(shopPage, "Automation Buy Egg", 2, false)
		makeMultiDropdownDyn(eggAcc, "Select Eggs to Buy", "Pilih egg buat auto-beli (stock realtime)",
			function() return ctx.getEggShopOptions(CFG.buyEggNames) end, CFG.buyEggNames, function() persist() end, 1)
		makeToggle(eggAcc, "Enable Automation Buy Egg", "Auto-beli egg terpilih tiap ada stock",
			function() return CFG.buyEggEnabled end,
			function(v) CFG.buyEggEnabled = v; persist(); if v then ctx.startBuyEgg() end end, 2)

		local gearAcc = makeAccordion(shopPage, "Automation Buy Gear", 3, false)
		makeMultiDropdownDyn(gearAcc, "Select Gear to Buy", "Pilih gear buat auto-beli (stock realtime)",
			function() return ctx.getGearShopOptions(CFG.buyGearNames) end, CFG.buyGearNames, function() persist() end, 1)
		makeToggle(gearAcc, "Enable Automation Buy Gear", "Auto-beli gear terpilih tiap ada stock",
			function() return CFG.buyGearEnabled end,
			function(v) CFG.buyGearEnabled = v; persist(); if v then ctx.startBuyGear() end end, 2)

		-- Automation Buy Merchant (Traveling Merchant — 1 merchant aktif per waktu)
		local merAcc = makeAccordion(shopPage, "Automation Buy Merchant", 4, false)
		local merStatus = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, Text = "Loading...",
			Font = F.reg, TextSize = 13, TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
			LineHeight = 1.35, RichText = true, LayoutOrder = 0
		}, merAcc)
		mk("Frame", { Size = UDim2.new(1, 0, 0, 10), BackgroundTransparency = 1, LayoutOrder = 1 }, merAcc)
		task.spawn(function()
			while ctx.alive() do
				if not onScreen(shopPage) then task.wait(1) continue end
				local ok, s = pcall(function() return ctx.getMerchantSummary() end)
				if ok and s then
					local lines = {}
					if s.activeMerchant then
						lines[#lines + 1] = "Traveling aktif: <font color=\"#5acc78\"><b>" .. s.activeMerchant .. "</b></font>"
					else
						lines[#lines + 1] = "Traveling aktif: <font color=\"#dc5050\">Tidak Ada</font>"
					end
					if s.mode == "all" then
						lines[#lines + 1] = "Mode: <font color=\"#f5c82d\"><b>Beli SEMUA item (All)</b></font>"
					elseif s.mode == "best" then
						lines[#lines + 1] = "Mode: <font color=\"#f5c82d\"><b>Beli item TERMAHAL (Best)</b></font>"
					elseif s.picks and #s.picks > 0 then
						lines[#lines + 1] = "Item dipilih buat dibeli:"
						for _, p in ipairs(s.picks) do
							local function shortNum(n)
								local a = math.abs(n)
								local s
								if a >= 1e9 then s = string.format("%.2f", n / 1e9):gsub("%.?0+$", "") .. "b"
								elseif a >= 1e6 then s = string.format("%.2f", n / 1e6):gsub("%.?0+$", "") .. "m"
								elseif a >= 1e3 then s = string.format("%.2f", n / 1e3):gsub("%.?0+$", "") .. "k"
								else s = tostring(n) end
								return s
							end
							local parts = {}
							for _, it in ipairs(p.items) do
								if it.price then
									parts[#parts + 1] = string.format("%s (%s)", it.name, shortNum(it.price))
								else
									parts[#parts + 1] = it.name
								end
							end
							lines[#lines + 1] = string.format(
								"- <font color=\"#5acc78\"><b>%s</b></font>: <font color=\"#f5c82d\">%s</font>",
								p.title, table.concat(parts, ", "))
						end
					else
						lines[#lines + 1] = "<font color=\"#dc5050\">Belum ada item dipilih.</font> Pilih di 'Select Items per Merchant' atau nyalakan Auto Buy All/Best."
					end
					merStatus.Text = table.concat(lines, "\n")
				end
				task.wait(2)
			end
		end)
		-- Pilih item — dipisah: Traveling Merchant vs Event Shop (biar rapih). Set duluan.
		-- Dua-duanya 1 path/buy toggle yang sama (Auto Buy Merchant/All/Best).
		local merSel = makeAccordion(merAcc, "Select Items per Merchant", 2, false)
		local evtSel = makeAccordion(merAcc, "Select Items per Event Shop", 3, false)
		do
			local iM, iE = 0, 0
			for _, m in ipairs(ctx.getMerchantList()) do
				local id = m.id
				if m.kind == "travel" then
					iM = iM + 1
					makeMultiDropdownDyn(merSel, m.title .. " Merchant", "Item dari " .. m.title .. " merchant. 'All' = semua.",
						function() return ctx.getMerchantItemOptions(id) end, ctx.merchantSelFor(id), function() persist() end, iM)
				else
					iE = iE + 1
					makeMultiDropdownDyn(evtSel, m.title, "Item dari " .. m.title .. ". 'All' = semua.",
						function() return ctx.getMerchantItemOptions(id) end, ctx.merchantSelFor(id), function() persist() end, iE)
				end
			end
		end
		-- Toggle bisa nyala barengan; target-nya digabung (union). Berlaku utk merchant & event shop.
		makeToggle(merAcc, "Auto Buy Merchant", "Beli item terpilih (merchant & event shop) tiap muncul / restock",
			function() return CFG.merchantBuyEnabled end,
			function(v) CFG.merchantBuyEnabled = v; persist(); if v then ctx.startBuyMerchant() end end, 4)
		makeToggle(merAcc, "Auto Buy All Merchant", "Beli SEMUA item yang ada stock",
			function() return CFG.merchantBuyAll end,
			function(v) CFG.merchantBuyAll = v; persist(); if v then ctx.startBuyMerchant() end end, 5)
		makeToggle(merAcc, "Auto Buy Best Merchant", "Beli 1 item TERMAHAL yang ada stock",
			function() return CFG.merchantBuyBest end,
			function(v) CFG.merchantBuyBest = v; persist(); if v then ctx.startBuyMerchant() end end, 6)

		-- Open Shop UI (event/night shop — tampilkan UI shop tanpa NPC)
		local merUi = makeAccordion(merAcc, "Open Shop UI", 7, false)
		makeSingleDropdown(merUi, "Merchant UI to Open", "Event shop yang mau dibuka UI-nya (1 shop per waktu)",
			function() return ctx.getEventShopOptions() end,
			function() return ctx.getMerchantUiDisplay() end,
			function(code) CFG.merchantUiShop = code; persist(); if ctx.openEventShopUI then ctx.openEventShopUI(code) end end, 1)
		makeButton(merUi, "Open Shop UI Now", "Buka UI shop terpilih sekarang (kalau shop lagi aktif)",
			function() if ctx.openEventShopUI then ctx.openEventShopUI() end end, 2)
		makeToggle(merUi, "Auto Open UI", "Jaga UI shop terpilih tetap kebuka (buka ulang otomatis, tanpa NPC)",
			function() return CFG.merchantAutoOpenUI end,
			function(v) CFG.merchantAutoOpenUI = v; persist()
				if v then ctx.startAutoOpenUI() elseif ctx.stopAutoOpenUI then ctx.stopAutoOpenUI() end end, 3)

		-- Premium Shop (dev-product: Robux / Token + Gift)
		local premAcc = makeAccordion(shopPage, "Premium Shop", 5, false)
		makeSingleDropdown(premAcc, "Select Item", "Select gamepass/product to purchase",
			function() return ctx.getPremiumItemOptions() end,
			function()
				for _, o in ipairs(ctx.getPremiumItemOptions()) do if o.name == CFG.premiumItem then return o.display end end
				return "Select Option"
			end,
			function(code) CFG.premiumItem = code; persist(); if ctx.premiumShowPrice then ctx.premiumShowPrice() end end, 1)
		makeSingleDropdown(premAcc, "Payment Method", "Robux atau Token",
			function() return ctx.getPremiumPayOptions() end,
			function() return CFG.premiumPay == "token" and "Token" or "Robux" end,
			function(code) CFG.premiumPay = code; persist() end, 2)
		makeButton(premAcc, "Purchase Item", "Beli item terpilih dengan payment method di atas",
			function() if ctx.premiumBuy then ctx.premiumBuy() end end, 3)
		makeButton(premAcc, "Gift to Player", "Beli varian Gift item ini (kalau tersedia)",
			function() if ctx.premiumGift then ctx.premiumGift() end end, 4)
	end

	------------------------------------------------------------------ ELEPHANT (V1)
	do
		local elephantPage = pageRef["Elephant"]
		local acc = makeAccordion(elephantPage, "Automation Elephant V1", 1, true)

		-- Status (live)
		local statusLbl = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, Text = "Loading stats...",
			Font = F.reg, TextSize = 13, TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
			LineHeight = 1.35, RichText = true, LayoutOrder = 0
		}, acc)
		mk("Frame", { Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, LayoutOrder = 1 }, acc)
		task.spawn(function()
			while ctx.alive() do
				if not onScreen(elephantPage) then task.wait(1) continue end
				local ok, s = pcall(function() return ctx.getElephantSummary() end)
				if ok and s then
					local col = s.status == "ACTIVE" and "#5acc78" or "#dc5050"
					statusLbl.Text = string.format(
						"Automation Status: <font color=\"%s\"><b>%s</b></font>\n\n" ..
						"Elephant Team: <font color=\"#8c929e\">%s</font>\n" ..
						"Target Types: <font color=\"#f5c82d\">%s</font>\n" ..
						"Target Pets Ready: <font color=\"#8c929e\">%s</font>\n" ..
						"Pets at Max KG: <font color=\"#8c929e\">%s</font>\n\n" ..
						"Max Target Pets: <font color=\"#8c929e\">%s</font>\n" ..
						"Target Weight: <font color=\"#f5c82d\"><b>%s</b></font>",
						col, s.status, s.team, s.types, s.ready, s.maxKg, s.maxTarget, s.targetWeight)
				end
				task.wait(1.5)
			end
		end)

		-- Settings (dalam accordion yang sama)
		makeMultiDropdownDyn(acc, "V1 Pet Team", "Select elephant pet team (tetap di garden)",
			function() return ctx.inventoryPetOptions(CFG.elephantTeamUuids) end, CFG.elephantTeamUuids, function() persist() end, 2)
		makeMultiDropdown(acc, "V1 Target Pet Types", "Select pet types to auto-elephant (semua pet di game)",
			reg.PET_OPTIONS, CFG.elephantPetTypes, function() persist() end, 3)
		makeInput(acc, "Target Weight (KG)", "Berat max sebelum diganti (mis. 5.5)",
			function() return tostring(CFG.elephantTargetWeight) end,
			function(txt) CFG.elephantTargetWeight = tonumber(txt) or 5.5; persist() end, 4)
		makeInput(acc, "Max Target Pets", "Jumlah pet target aktif barengan",
			function() return tostring(CFG.elephantMaxPets) end,
			function(txt) CFG.elephantMaxPets = tonumber(txt) or 2; persist() end, 5)
		makeToggle(acc, "Enable Automation Elephant", "Rotasi pet target otomatis. OFF = cabut semua pet dari garden.",
			function() return CFG.elephantEnabled end,
			function(v)
				CFG.elephantEnabled = v; persist()
				if v then ctx.startElephant() else ctx.stopElephant() end
			end, 6)

		-- ===================== ELEPHANT V2 (swap gajah on lvl 40) =====================
		local acc2 = makeAccordion(elephantPage, "Automation Elephant V2", 2, false)

		local v2Lbl = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, Text = "Loading...",
			Font = F.reg, TextSize = 13, TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
			LineHeight = 1.35, RichText = true, LayoutOrder = 0
		}, acc2)
		mk("Frame", { Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, LayoutOrder = 1 }, acc2)
		task.spawn(function()
			while ctx.alive() do
				if not onScreen(elephantPage) then task.wait(1) continue end
				local ok, s = pcall(function() return ctx.getElephantV2Summary() end)
				if ok and s then
					local col = s.status == "ACTIVE" and "#5acc78" or "#dc5050"
					v2Lbl.Text = string.format(
						"Automation Status: <font color=\"%s\"><b>%s</b></font>  |  <font color=\"#f5c82d\">%s</font>\n\n" ..
						"Elephant Team: <font color=\"#8c929e\">%s</font>\n" ..
						"Target Types: <font color=\"#f5c82d\">%s</font>\n" ..
						"Target Pets Ready: <font color=\"#8c929e\">%s</font>\n" ..
						"Pets at Max KG: <font color=\"#8c929e\">%s</font>\n" ..
						"Max Target Pets: <font color=\"#8c929e\">%s</font>  |  Target Weight: <font color=\"#f5c82d\"><b>%s</b></font>\n\n" ..
						"Gajah: <font color=\"#8c929e\">%s</font>\n" ..
						"Switch: <font color=\"#8c929e\">%s</font>\n" ..
						"Gajah masuk saat target Age >= <font color=\"#f5c82d\"><b>%s</b></font>",
						col, s.status, s.info, s.team, s.types, s.ready, s.maxKg, s.maxTarget, s.targetWeight, s.gajah, s.switch, s.level)
				end
				task.wait(0.5)
			end
		end)

		makeMultiDropdownDyn(acc2, "V2 Elephant Team", "Team standby di garden (sumber pilihan Pet Switch)",
			function() return ctx.inventoryPetOptions(CFG.elephantV2Team) end, CFG.elephantV2Team, function() persist() end, 2)
		makeMultiDropdown(acc2, "V2 Target Pet Types", "Tipe pet target yg dipantau levelnya (yg di-level PNP)",
			reg.PET_OPTIONS, CFG.elephantV2Types, function() persist() end, 3)
		makeSingleDropdown(acc2, "Pet Gajah", "Pet booster berat yg di-swap masuk pas target lvl 40",
			function() return ctx.elephantV2GajahOptions() end,
			function() return ctx.elephantV2Label(CFG.elephantV2Gajah) end,
			function(uuid) CFG.elephantV2Gajah = uuid; persist() end, 4)
		makeSingleDropdown(acc2, "Pet Switch", "Pet team yg ditukar sama gajah (dari V2 Elephant Team)",
			function() return ctx.elephantV2SwitchOptions() end,
			function() return ctx.elephantV2Label(CFG.elephantV2Switch) end,
			function(uuid) CFG.elephantV2Switch = uuid; persist() end, 5)
		makeInput(acc2, "Target Weight (KG)", "Berat max target sebelum dilepas (mis. 5.5)",
			function() return tostring(CFG.elephantV2Weight) end,
			function(txt) CFG.elephantV2Weight = tonumber(txt) or 5.5; persist() end, 6)
		makeInput(acc2, "Max Target Pets", "Jumlah pet target aktif barengan di garden",
			function() return tostring(CFG.elephantV2MaxPets) end,
			function(txt) CFG.elephantV2MaxPets = tonumber(txt) or 3; persist() end, 7)
		makeInput(acc2, "Trigger Level", "Level target buat masukin gajah (default 40)",
			function() return tostring(CFG.elephantV2Level) end,
			function(txt) CFG.elephantV2Level = tonumber(txt) or 40; persist() end, 8)
		makeToggle(acc2, "Enable Elephant V2", "Rotasi target + swap gajah otomatis saat target lvl 40. Jalan barengan PNP.",
			function() return CFG.elephantV2Enabled end,
			function(v)
				CFG.elephantV2Enabled = v; persist()
				if v then ctx.startElephantV2() else ctx.stopElephantV2() end
			end, 9)
	end

	------------------------------------------------------------------ LEVELING
	local levelingPage = pageRef["Leveling"]
	do
		-- Automation Leveling V1 — status + settings jadi satu accordion
		local levAcc = makeAccordion(levelingPage, "Automation Leveling V1", 1, true)

		local statusLbl = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = "Loading stats...",
			Font = F.reg,
			TextSize = 13,
			TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			LineHeight = 1.35,
			RichText = true,
			LayoutOrder = 0
		}, levAcc)
		-- spacer pemisah status & settings
		mk("Frame", { Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, LayoutOrder = 1 }, levAcc)

		task.spawn(function()
			while ctx.alive() do
				if not onScreen(levelingPage) then task.wait(1) continue end
				local ok, s = pcall(function() return ctx.getLevelingSummary() end)
				if ok and s then
					local statusColor = s.status == "ACTIVE" and "#5acc78" or "#dc5050"
					statusLbl.Text = string.format(
						"Automation Status: <font color=\"%s\"><b>%s</b></font>\n\n" ..
						"<b>Current Settings:</b>\n" ..
						"Pet Team: <font color=\"#8c929e\">%s</font>\n" ..
						"Target Types: <font color=\"#f5c82d\">%s</font>\n" ..
						"Pets Ready to Level: <font color=\"#8c929e\">%s</font>\n" ..
						"Pets at Max Level: <font color=\"#8c929e\">%s</font>\n" ..
						"Max in Garden: <font color=\"#8c929e\">%s</font>\n\n" ..
						"Target Level: <font color=\"#f5c82d\"><b>%s</b></font>\n\n" ..
						"Ready: Settings configured",
						statusColor, s.status,
						s.team,
						s.types,
						s.ready,
						s.maxLvl,
						s.maxInGarden,
						s.targetLevel
					)
				end
				task.wait(1.5)
			end
		end)

		-- Settings (di accordion yang sama, setelah status + spacer)
		-- Leveling Pet Team (Multi-dropdown UUIDs)
		makeMultiDropdownDyn(levAcc, "Leveling Pet Team", "Select pets to keep in garden while leveling",
			function() return ctx.inventoryPetOptions(CFG.levelingTeamUuids) end, CFG.levelingTeamUuids, function() persist() end, 2)

		-- Leveling Pet Types (semua pet di game, bukan cuma yang di inventory)
		makeMultiDropdown(levAcc, "Leveling Pet Types", "Select pet types to auto-level (semua pet di game)",
			reg.PET_OPTIONS, CFG.levelingPetTypes, function() persist() end, 3)

		-- Target Level (Input)
		makeInput(levAcc, "Target Level", "Target level to reach before un-equipping",
			function() return tostring(CFG.levelingTargetLevel) end,
			function(txt) CFG.levelingTargetLevel = tonumber(txt) or 500; persist() end, 4)

		-- Max Pets in Garden (Input)
		makeInput(levAcc, "Max Pets in Garden", "Maximum active leveling pets allowed in garden",
			function() return tostring(CFG.levelingMaxPets) end,
			function(txt) CFG.levelingMaxPets = tonumber(txt) or 2; persist() end, 5)

		-- Enable Automation Leveling (Toggle)
		makeToggle(levAcc, "Enable Automation Leveling", "Equip and rotate pets automatically based on settings",
			function() return CFG.levelingEnabled end,
			function(v)
				CFG.levelingEnabled = v; persist()
				if v then ctx.startLeveling() else ctx.stopLeveling() end
			end, 6)

		---------------------------------------------------------- Automation Leveling V2 (2 phase)
		local lv2 = makeAccordion(levelingPage, "Automation Leveling V2", 2, true)

		local lv2Lbl = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
			Text = "Loading...", Font = F.reg, TextSize = 13, TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, LineHeight = 1.35, RichText = true, LayoutOrder = 0
		}, lv2)
		mk("Frame", { Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, LayoutOrder = 1 }, lv2)
		task.spawn(function()
			while ctx.alive() do
				if not onScreen(levelingPage) then task.wait(1) continue end
				local ok, s = pcall(function() return ctx.getLevelingV2Summary() end)
				if ok and s then
					local col = s.status == "ACTIVE" and "#5acc78" or "#dc5050"
					lv2Lbl.Text = string.format(
						"Automation Status: <font color=\"%s\"><b>%s</b></font>  |  <font color=\"#f5c82d\">%s</font>\n\n" ..
						"<b>Target Types:</b> <font color=\"#8c929e\">%s</font>\n\n" ..
						"<b>Phase 1</b> (→%s): team <font color=\"#8c929e\">%d</font> | antre <font color=\"#f5c82d\">%d</font> pet\n" ..
						"<b>Phase 2</b> (→%s): team <font color=\"#8c929e\">%d</font> | antre <font color=\"#f5c82d\">%d</font> pet\n" ..
						"<b>Pet at Max Level:</b> <font color=\"#5acc78\">%d</font> pet",
						col, s.status, s.phase, s.types,
						tostring(s.p1target), s.p1team, s.p1queue,
						tostring(s.p2target), s.p2team, s.p2queue,
						s.maxLvl or 0)
				end
				task.wait(1.5)
			end
		end)

		-- Target Pet Types (semua pet di game)
		makeMultiDropdown(lv2, "Leveling Target Pet Types", "Pet types to level up (semua pet di game)",
			reg.PET_OPTIONS, CFG.levelingV2PetTypes, function() persist() end, 2)

		-- Phase 1
		makeMultiDropdownDyn(lv2, "Leveling Phase 1 Pet Team", "Team for Phase 1 (Age 1 to Phase 1 Target)",
			function() return ctx.inventoryPetOptions(CFG.levelingV2P1Team) end, CFG.levelingV2P1Team, function() persist() end, 3)
		makeInput(lv2, "Leveling Phase 1 Target", "End of Phase 1 / start of Phase 2 (default 40)",
			function() return tostring(CFG.levelingV2P1Target) end,
			function(txt) CFG.levelingV2P1Target = tonumber(txt) or 40; persist() end, 4)
		makeInput(lv2, "Leveling Phase 1 Max Pets", "Max target pets in garden during Phase 1",
			function() return tostring(CFG.levelingV2P1Max) end,
			function(txt) CFG.levelingV2P1Max = tonumber(txt) or 3; persist() end, 5)

		-- Phase 2
		makeMultiDropdownDyn(lv2, "Leveling Phase 2 Pet Team", "Team for Phase 2 (Phase 1 Target to Final Target)",
			function() return ctx.inventoryPetOptions(CFG.levelingV2P2Team) end, CFG.levelingV2P2Team, function() persist() end, 6)
		makeInput(lv2, "Leveling Phase 2 Target", "Final target level (default 500 = max age)",
			function() return tostring(CFG.levelingV2P2Target) end,
			function(txt) CFG.levelingV2P2Target = tonumber(txt) or 500; persist() end, 7)
		makeInput(lv2, "Leveling Phase 2 Max Pets", "Max target pets in garden during Phase 2",
			function() return tostring(CFG.levelingV2P2Max) end,
			function(txt) CFG.levelingV2P2Max = tonumber(txt) or 1; persist() end, 8)

		-- Enable
		makeToggle(lv2, "Enable Automation Leveling V2", "Level pet 2 tahap (Phase 1 team -> Phase 2 team)",
			function() return CFG.levelingV2Enabled end,
			function(v)
				CFG.levelingV2Enabled = v; persist()
				if v then ctx.startLevelingV2() else ctx.stopLevelingV2() end
			end, 9)
	end

	------------------------------------------------------------------ MUTATION
	local mutationPage = pageRef["Mutation"]
	do
		-- 1. Status Accordion
		local statusAcc = makeAccordion(mutationPage, "Automation Mutation Machine", 1, true)
		
		local statusLbl = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = "Loading stats...",
			Font = F.reg,
			TextSize = 13,
			TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			LineHeight = 1.35,
			RichText = true,
			LayoutOrder = 0
		}, statusAcc)
		mk("Frame", { Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, LayoutOrder = 1 }, statusAcc)

		task.spawn(function()
			while ctx.alive() do
				if not onScreen(mutationPage) then task.wait(1) continue end
				local ok, s = pcall(function() return ctx.getMutationSummary() end)
				if ok and s then
					local statusColor = s.status == "ACTIVE" and "#5acc78" or "#dc5050"
					statusLbl.Text = string.format(
						"Status: <font color=\"%s\"><b>%s</b></font>\n" ..
						"Phase: <b>%s</b>\n\n" ..
						"EXP Team: <font color=\"#8c929e\">%d pets</font>\n" ..
						"Boost Team: <font color=\"#8c929e\">%d pets</font>\n" ..
						"Phoenix Team: <font color=\"#8c929e\">%d pets</font>\n\n" ..
						"Target Types: <font color=\"#f5c82d\">%s</font>\n" ..
						"Keep Mutations: <font color=\"#f5c82d\">%s</font>\n" ..
						"Target Age: <font color=\"#f5c82d\"><b>%s</b></font>\n\n" ..
						"Machine: <font color=\"#85d0ff\"><b>%s</b></font>\n\n" ..
						"Target Pets Ready: <font color=\"#8c929e\">%d pets</font>\n" ..
						"Target Pets Done: <font color=\"#5acc78\"><b>%d pets</b></font>",
						statusColor, s.status,
						s.phase,
						s.expCount,
						s.boostCount,
						s.phoenixCount,
						s.types,
						s.mutations,
						tostring(s.targetAge),
						s.machine,
						s.readyCount,
						s.doneCount
					)
				end
				task.wait(1.5)
			end
		end)

		-- Settings (dalam accordion yang sama dengan status)
		local settingsAcc = statusAcc

		-- EXP Team (Multi-dropdown UUIDs)
		makeMultiDropdownDyn(settingsAcc, "EXP Team (Leveling)", "Pets for leveling target to age 50/500",
			function() return ctx.inventoryPetOptions(CFG.mutationExpTeam) end, CFG.mutationExpTeam, function() persist() end, 2)

		-- Boost Team (Machine) (Multi-dropdown UUIDs)
		makeMultiDropdownDyn(settingsAcc, "Boost Team (Machine)", "Pets for boosting mutation machine speed",
			function() return ctx.inventoryPetOptions(CFG.mutationBoostTeam) end, CFG.mutationBoostTeam, function() persist() end, 3)

		-- Phoenix Team (Claim) (Multi-dropdown UUIDs)
		makeMultiDropdownDyn(settingsAcc, "Phoenix Team (Claim)", "Pets for claiming mutated pet",
			function() return ctx.inventoryPetOptions(CFG.mutationPhoenixTeam) end, CFG.mutationPhoenixTeam, function() persist() end, 4)

		-- Target Pet Types (semua pet di game, bukan cuma yang di inventory)
		makeMultiDropdown(settingsAcc, "Target Pet Types", "Pet types to mutate (semua pet di game)",
			reg.PET_OPTIONS, CFG.mutationTargetTypes, function() persist() end, 5)

		-- Target Mutations (Multi-dropdown Mutations)
		makeMultiDropdown(settingsAcc, "Target Mutations (Machine)", "Stop when pet gets these mutations (hanya mutasi mesin)",
			ctx.reg.MACHINE_MUT_OPTIONS or ctx.reg.MUT_OPTIONS or {"None"}, CFG.mutationTargetMutations, function() persist() end, 6)

		-- Target Age (Input)
		makeInput(settingsAcc, "Target Age", "Level to reach before submitting (e.g. 50 or 500)",
			function() return tostring(CFG.mutationTargetAge) end,
			function(txt) CFG.mutationTargetAge = tonumber(txt) or 50; persist() end, 7)

		-- Delay Auto Claim (Input)
		makeInput(settingsAcc, "Delay Auto Claim (sec)", "Wait before claiming mutated pet from machine",
			function() return tostring(CFG.mutationDelayAutoClaim) end,
			function(txt) CFG.mutationDelayAutoClaim = tonumber(txt) or 0.5; persist() end, 8)

		-- Enable Auto Mutation Machine (Toggle)
		ctx.state.mutationToggleRender = makeToggle(settingsAcc, "Enable Auto Mutation Machine", "Submit, start, and claim mutated pets automatically",
			function() return CFG.mutationEnabled end,
			function(v)
				CFG.mutationEnabled = v; persist()
				if v then ctx.startMutation() else ctx.stopMutation() end
			end, 9)

		-- Accordion: Automation Mutation (mutasi via aura + cleanse)
		local cleanseAcc = makeAccordion(mutationPage, "Automation Mutation", 2, false)

		-- Status (live)
		local cleanseLbl = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, Text = "Loading stats...",
			Font = F.reg, TextSize = 13, TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
			LineHeight = 1.35, RichText = true, LayoutOrder = 0
		}, cleanseAcc)
		mk("Frame", { Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, LayoutOrder = 1 }, cleanseAcc)
		task.spawn(function()
			while ctx.alive() do
				if not onScreen(mutationPage) then task.wait(1) continue end
				local ok, s = pcall(function() return ctx.getCleanseSummary() end)
				if ok and s then
					local col = s.status == "ACTIVE" and "#5acc78" or "#dc5050"
					local alreadyLines = ""
					for _, k in ipairs(s.keepOrder) do
						alreadyLines = alreadyLines .. string.format("- Already %s: <font color=\"#8c929e\">%d pets</font>\n", k, s.already[k] or 0)
					end
					cleanseLbl.Text = string.format(
						"Automation Status: <font color=\"%s\"><b>%s</b></font>\n\n" ..
						"Mutation Team: <font color=\"#8c929e\">%d pets</font>\n" ..
						"Target Types: <font color=\"#f5c82d\">%s</font>\n" ..
						"Mutations to Keep: <font color=\"#f5c82d\">%s</font>\n\n" ..
						"Pet Statistics:\n" ..
						"- Pets Ready to Mutation: <font color=\"#8c929e\">%d pets</font>\n" ..
						"%s\n" ..
						"Max in Garden: <font color=\"#8c929e\">%d pets</font>\n\n" ..
						"Status: <font color=\"#85d0ff\">%s</font>",
						col, s.status, s.team, s.types, s.keep, s.ready, alreadyLines, s.maxPets, s.phase)
				end
				task.wait(1.5)
			end
		end)

		makeMultiDropdownDyn(cleanseAcc, "Pet Team for Mutation", "Pet aura pemberi mutasi (tetap di garden)",
			function() return ctx.inventoryPetOptions(CFG.cleanseTeamUuids) end, CFG.cleanseTeamUuids, function() persist() end, 2)
		makeMultiDropdown(cleanseAcc, "Pet Types for Mutation", "Tipe pet target yang mau dimutasi (semua pet di game)",
			reg.PET_OPTIONS, CFG.cleansePetTypes, function() persist() end, 3)
		makeMultiDropdown(cleanseAcc, "Mutations to Keep", "Mutasi ini disimpan (won't be cleansed)",
			ctx.reg.MUT_OPTIONS or {"None"}, CFG.cleanseKeepMutations, function() persist() end, 4)
		makeInput(cleanseAcc, "Max Pets in Garden", "Max pet target di garden barengan",
			function() return tostring(CFG.cleanseMaxPets) end,
			function(txt) CFG.cleanseMaxPets = tonumber(txt) or 2; persist() end, 5)
		makeToggle(cleanseAcc, "Enable Auto Mutation", "Mutasi target via aura; cleanse mutasi salah, simpan mutasi keep",
			function() return CFG.cleanseEnabled end,
			function(v)
				CFG.cleanseEnabled = v; persist()
				if v then ctx.startCleanse() else ctx.stopCleanse() end
			end, 6)
	end

	------------------------------------------------------------------ EVENT
	local eventPage = pageRef["Event"]
	do
		-- Accordion pembungkus: Automation Beanstalk Event (NPC Jack)
		local beanAcc = makeAccordion(eventPage, "Automation Beanstalk Event", 1, true)

		-- Status live: craving trait, growth global, contributed, ready/seeds/target
		local beanLbl = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, Text = "Beanstalk: loading...",
			Font = F.reg, TextSize = 13, TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
			LineHeight = 1.35, RichText = true, LayoutOrder = 0
		}, beanAcc)
		mk("Frame", { Size = UDim2.new(1, 0, 0, 8), BackgroundTransparency = 1, LayoutOrder = 1 }, beanAcc)
		task.spawn(function()
			while ctx.alive() do
				if not onScreen(eventPage) then task.wait(1) continue end
				local ok, s = pcall(function() return ctx.getBeanstalkSummary() end)
				if ok and s then
					if not s.active then
						beanLbl.Text = "Beanstalk: <font color=\"#dc5050\"><b>EVENT TIDAK AKTIF</b></font>"
					else
						local cv = s.craving or "-"
						-- daftar semua trait yang mungkin diminta; yang aktif di-highlight
						-- ketanam per jenis: "Vegetable 50/20" (hijau kalau udah >= target, kuning kalau kurang)
						-- yang lagi diminta ditandai bintang.
						local rows = {}
						for _, e in ipairs(s.perTrait or {}) do
							local reached = e.target > 0 and e.planted >= e.target
							local col = reached and "#5acc78" or "#f5c82d"
							local star = e.craving and " *" or ""
							rows[#rows + 1] = ("%s <font color=\"%s\"><b>%d/%d</b></font>%s"):format(e.trait, col, e.planted, e.target, star)
						end
						beanLbl.Text = string.format(
							"Sekarang minta: <font color=\"#5acc78\"><b>%s</b></font> Plant   Growth: <font color=\"#f5c82d\"><b>%s</b></font>   Kontribusi: <font color=\"#8c929e\">%s</font>\n%s",
							cv, tostring(s.growth or "-"), tostring(s.contributed or 0),
							table.concat(rows, "   "))
					end
				end
				task.wait(1)
			end
		end)

		-- Input: jumlah tanam per siklus
		makeInput(beanAcc, "Jumlah Plant", "Target tanam per jenis trait. 0 = ga nanam.",
			function() return tostring(CFG.beanstalkPlantCount) end,
			function(txt) CFG.beanstalkPlantCount = tonumber(txt) or 0; persist() end, 2)

		-- Toggle 1: Auto Plant — top-up SEMUA trait ke target (pre-stock)
		makeToggle(beanAcc, "Auto Plant (Semua Trait)", "Tanam tiap trait sampai target, 1 jenis per giliran.",
			function() return CFG.beanstalkPlantEnabled end,
			function(v)
				CFG.beanstalkPlantEnabled = v; persist()
				if v then if ctx.startBeanstalk then ctx.startBeanstalk() end elseif not ctx.beanstalkAnyOn() then ctx.stopBeanstalk() end
			end, 3)

		-- Toggle 2: Auto Collect fruit sesuai craving
		makeToggle(beanAcc, "Auto Collect (Craving)", "Panen HANYA fruit yang sesuai craving ke backpack.",
			function() return CFG.beanstalkCollectEnabled end,
			function(v)
				CFG.beanstalkCollectEnabled = v; persist()
				if v then if ctx.startBeanstalk then ctx.startBeanstalk() end elseif not ctx.beanstalkAnyOn() then ctx.stopBeanstalk() end
			end, 4)

		-- Toggle 3: Auto Submit (setor bulk, per-plant, aman)
		makeToggle(beanAcc, "Auto Submit ke Beanstalk", "Setor semua produce craving (bulk).",
			function() return CFG.beanstalkSubmitEnabled end,
			function(v)
				CFG.beanstalkSubmitEnabled = v; persist()
				if v then if ctx.startBeanstalk then ctx.startBeanstalk() end elseif not ctx.beanstalkAnyOn() then ctx.stopBeanstalk() end
			end, 5)

		-- Toggle 4: Auto Claim Reward (loop sendiri, ga butuh plant/collect/submit)
		makeToggle(beanAcc, "Auto Claim Reward", "Claim reward point yg udah kebuka.",
			function() return CFG.beanstalkClaimEnabled end,
			function(v)
				CFG.beanstalkClaimEnabled = v; persist()
				if v then if ctx.startBeanstalkClaim then ctx.startBeanstalkClaim() end else if ctx.stopBeanstalkClaim then ctx.stopBeanstalkClaim() end end
			end, 6)

		-- Toggle 5: Auto Jual saat mentok (backpack penuh trait salah -> Sell_Inventory SEMUA)
		makeToggle(beanAcc, "Auto Sell Backpack at Full", "Jual semua tanaman yang ada di backpack.",
			function() return CFG.beanstalkAutoSellEnabled end,
			function(v) CFG.beanstalkAutoSellEnabled = v; persist() end, 7)

		-- Toggle 6: Auto Server Hop (cari server growth < 900, join-check-hop)
		makeToggle(beanAcc, "Auto Hop Server (Growth < 900)", "Pindah server sampai nemu beanstalk belum penuh.",
			function() return CFG.beanstalkHopEnabled end,
			function(v)
				CFG.beanstalkHopEnabled = v; persist()
				if v then if ctx.startBeanstalkHop then ctx.startBeanstalkHop() end else if ctx.stopBeanstalkHop then ctx.stopBeanstalkHop() end end
			end, 8)

		------------------------------------------------------------------ Beanstalk Event Shop (auto buy)
		local beanShopAcc = makeAccordion(eventPage, "Beanstalk Event Shop", 2, false)
		makeMultiDropdownDyn(beanShopAcc, "Pilih Item", "'All' = beli semua yg ada stock.",
			function() return ctx.getBeanstalkShopOptions() end, CFG.buyBeanstalkShopNames, function() persist() end, 1)
		makeToggle(beanShopAcc, "Enable Auto Buy Beanstalk Shop", "Auto-beli item terpilih tiap ada stock.",
			function() return CFG.buyBeanstalkShopEnabled end,
			function(v) CFG.buyBeanstalkShopEnabled = v; persist(); if v and ctx.startBuyBeanstalkShop then ctx.startBuyBeanstalkShop() elseif ctx.stopBuyBeanstalkShop then ctx.stopBuyBeanstalkShop() end end, 2)
	end

	------------------------------------------------------------------ PET (PNP)
	local pet = pageRef["Pet"]
	local v1Render, v2Render -- buat sync visual mutual-exclusion

	------------------------------------------------------------------ PnP V1 (polling)
	local pnp = makeAccordion(pet, "Automation Pickup Pet V1", 1, true)
	makeMultiDropdownDyn(pnp, "Select Pets for Pickup [V1]", "Pilih pet dari backpack (kosong = semua yg di garden)",
		function() return ctx.inventoryPetOptions(CFG.pnpUuids) end, CFG.pnpUuids, function() persist() end, 1)
	makeInput(pnp, "Pickup Delay (Seconds) [V1]", "Jeda tiap siklus (idealnya = saat skill ready)",
		function() return CFG.pickupDelay end,
		function(txt) CFG.pickupDelay = tonumber(txt) or 0.4; persist() end, 2)
	makeInput(pnp, "Equip Delay (Seconds) [V1]", "Jeda antara unequip -> equip",
		function() return CFG.equipDelay end,
		function(txt) CFG.equipDelay = tonumber(txt) or 0.02; persist() end, 3)
	makeInput(pnp, "Scan Interval (Seconds) [V1]", "Frekuensi cek cooldown (kecil = makin ketat, min 0.01)",
		function() return CFG.pnpScanInterval end,
		function(txt) CFG.pnpScanInterval = math.max(0.01, tonumber(txt) or 0.05); persist() end, 4)
	v1Render = makeToggle(pnp, "Enable Automation Pickup V1", "Polling GetPetCooldown (lama). Nyalain ini matiin V2.",
		function() return CFG.pnpEnabled end,
		function(v)
			CFG.pnpEnabled = v; persist()
			if v then
				CFG.pnpV2Enabled = false; persist()
				if ctx.stopPnpV2 then ctx.stopPnpV2() end
				if v2Render then v2Render() end -- sync visual toggle V2 -> OFF
				if ctx.startPnpV1 then ctx.startPnpV1() end
			else
				if ctx.stopPnpV1 then ctx.stopPnpV1() end
			end
		end, 5)

	------------------------------------------------------------------ PnP V2 (event-driven)
	local pnp2 = makeAccordion(pet, "Automation Pickup Pet V2", 2, false)
	makeMultiDropdownDyn(pnp2, "Select Pets for Pickup [V2]", "Pilih pet dari backpack (kosong = semua yg di garden)",
		function() return ctx.inventoryPetOptions(CFG.pnpV2Uuids) end, CFG.pnpV2Uuids, function() persist() end, 1)
	makeInput(pnp2, "Pickup Delay (Seconds) [V2]", "Jeda sebelum tiap pickup",
		function() return CFG.pnpV2PickupDelay end,
		function(txt) CFG.pnpV2PickupDelay = tonumber(txt) or 0.05; persist() end, 2)
	makeInput(pnp2, "Equip Delay (Seconds) [V2]", "Jeda antara unequip -> equip",
		function() return CFG.pnpV2EquipDelay end,
		function(txt) CFG.pnpV2EquipDelay = tonumber(txt) or 0.03; persist() end, 3)
	makeInput(pnp2, "Scan Interval (Seconds) [V2]", "Frekuensi cek cd dari cache event (min 0.02)",
		function() return CFG.pnpV2ScanInterval end,
		function(txt) CFG.pnpV2ScanInterval = math.max(0.02, tonumber(txt) or 0.05); persist() end, 4)
	v2Render = makeToggle(pnp2, "Enable Automation Pickup V2", "Event-driven (PetCooldownsUpdated), stabil. Nyalain ini matiin V1.",
		function() return CFG.pnpV2Enabled end,
		function(v)
			CFG.pnpV2Enabled = v; persist()
			if v then
				CFG.pnpEnabled = false; persist()
				if ctx.stopPnpV1 then ctx.stopPnpV1() end
				if v1Render then v1Render() end -- sync visual toggle V1 -> OFF
				if ctx.startPnpV2 then ctx.startPnpV2() end
			else
				if ctx.stopPnpV2 then ctx.stopPnpV2() end
			end
		end, 5)

	-- Accordion: Automation Boost Pet
	local boostAcc = makeAccordion(pet, "Automation Boost Pet", 3, false)
	makeMultiDropdownDyn(boostAcc, "Select Pets to Boost", "Pilih pet yang mau di-boost (aktif di garden)",
		function() return ctx.inventoryPetOptions(CFG.boostPetUuids) end, CFG.boostPetUuids, function() persist() end, 1)
	makeMultiDropdownDyn(boostAcc, "Select Boost Items", "Pilih item boost (Pet Toy) yang dipakai",
		function() return ctx.getBoostItemOptions(CFG.boostItemNames) end, CFG.boostItemNames, function() persist() end, 2)
	makeToggle(boostAcc, "Enable Automation Boost", "Auto apply boost item ke pet, re-apply pas boost habis",
		function() return CFG.boostEnabled end,
		function(v)
			CFG.boostEnabled = v; persist()
			if v then ctx.startBoostPet() end
		end, 3)

	------------------------------------------------------------------ INVENTORY
	local inv = pageRef["Inventory"]

	-- Accordion: Automation Trade
	local at = makeAccordion(inv, "Automation Trade", 1, true)

	local targetOptions = function()
		local out = {}
		for _, n in ipairs(ctx.getPlayers()) do out[#out + 1] = n end
		return out
	end
	makeSingleDropdown(at, "Target Player", "Select player to trade with", targetOptions,
		function() return CFG.targetPlayer end,
		function(v) CFG.targetPlayer = v; persist() end, 1)

	makeMultiDropdown(at, "Pet Types to Trade", "Filter pets by type (empty = all non-favorite)",
		reg.PET_OPTIONS, CFG.petTypes, function() persist() end, 2)

	makeInput(at, "Weight Filter (KG)", "pakai berat tampilan game | 0=off | +6 = min 6kg | -6 = max 6kg",
		function() return CFG.weightFilter end,
		function(txt) CFG.weightFilter = tonumber(txt) or 0; persist() end, 3)

	makeInput(at, "Age Filter", "0 = off | +50 = at least age 50 | -50 = at most age 50",
		function() return CFG.ageFilter end,
		function(txt) CFG.ageFilter = tonumber(txt) or 0; persist() end, 4)

	makeInput(at, "Pets Per Trade", "Number of pets to add each trade",
		function() return CFG.petsPerTrade end,
		function(txt) local n = tonumber(txt); CFG.petsPerTrade = (n and n > 0) and math.floor(n) or 1; persist() end, 5)

	makeInput(at, "Total Trades", "How many trades to perform",
		function() return CFG.totalTrades end,
		function(txt) local n = tonumber(txt); CFG.totalTrades = (n and n >= 0) and math.floor(n) or 0; persist() end, 6)

	makeToggle(at, "Auto Unfavorite [Trade]", "Remove favorite before trading",
		function() return CFG.autoUnfavorite end,
		function(v) CFG.autoUnfavorite = v; persist() end, 7)

	-- Trade Status (di paling atas)
	local stFrame = mk("Frame", { Size = UDim2.new(1, 0, 0, 66), BackgroundTransparency = 1, LayoutOrder = 0 }, at)
	mk("TextLabel", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 4), BackgroundTransparency = 1, Text = "Trade Status", Font = F.bold, TextSize = 14, TextColor3 = C.txt, TextXAlignment = Enum.TextXAlignment.Left }, stFrame)
	local stLbl = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 22), BackgroundTransparency = 1, Text = "Completed: 0 / 0\nPet cocok filter: -\nStatus: IDLE", Font = F.reg, TextSize = 11, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, RichText = true }, stFrame)
	function ctx.refreshTradeStatus()
		local avail = ctx.countMatchingPets and ctx.countMatchingPets() or 0
		local availCol = avail > 0 and "#5acc78" or "#dc5050"
		stLbl.Text = ("Completed: %d / %d\nPet cocok filter: <font color=\"%s\"><b>%d</b></font>\nStatus: %s"):format(
			ctx.state.completed, CFG.totalTrades, availCol, avail, ctx.state.status)
	end
	-- refresh live tiap 2 detik biar jumlah pet update walau filter berubah
	task.spawn(function()
		while ctx.alive() do
			if not onScreen(stLbl) then task.wait(2) continue end
			pcall(function() ctx.refreshTradeStatus() end)
			task.wait(2)
		end
	end)

	-- Enable Automation Trade
	makeToggle(at, "Enable Automation Trade", "Send trade, add pets, wait for accept, confirm",
		function() return CFG.tradeEnabled end,
		function(v)
			CFG.tradeEnabled = v; persist()
			if v then
				ctx.state.completed = 0
				ctx.startTrade()
			else
				ctx.stopTrade()
			end
			ctx.refreshTradeStatus()
		end, 9)

	-- Accordion: Automation Accept
	local acc = makeAccordion(inv, "Automation Accept", 2, false)
	makeToggle(acc, "Automation Accept Gifts", "Automation accept incoming gifts",
		function() return CFG.acceptGifts end,
		function(v) CFG.acceptGifts = v; persist() end, 1)
	makeToggle(acc, "Automation Accept Trades", "Automation accept incoming trades",
		function() return CFG.acceptTrades end,
		function(v) CFG.acceptTrades = v; persist() end, 2)

	-- Accordion: Automation Favourite Pets
	local fav = makeAccordion(inv, "Automation Favourite Pets", 3, false)
	makeToggle(fav, "Auto Favourite Pets", "Automatically favorite selected pet types",
		function() return CFG.autoFavorite end,
		function(v) CFG.autoFavorite = v; persist(); if v then ctx.startAutoFavorite() else ctx.stopAutoFavorite() end end, 1)
	makeMultiDropdown(fav, "Favourite Pet Types", "Pet types to keep favorited",
		reg.PET_OPTIONS, CFG.favoritePetTypes, function() persist() end, 2)

	------------------------------------------------------------------ MISC (log & webhooks)
	local misc = pageRef["Misc"]

	-- Player Accordion (Noclip / Walk Speed / Infinity Jump)
	local plAcc = makeAccordion(misc, "Player", 0, false)
	makeToggle(plAcc, "Noclip", "Walk through walls and obstacles",
		function() return CFG.noclipEnabled end,
		function(v) if ctx.setNoclip then ctx.setNoclip(v) end; persist() end, 1)
	makeInput(plAcc, "Walk Speed", "Player walk speed (default 16)",
		function() return tostring(CFG.walkSpeed) end,
		function(t) CFG.walkSpeed = tonumber(t) or 16; if ctx.applyWalkSpeed then ctx.applyWalkSpeed() end; persist() end, 2)
	makeToggle(plAcc, "Enable Walk Speed", "Apply custom walk speed",
		function() return CFG.walkSpeedEnabled end,
		function(v) if ctx.setWalkSpeed then ctx.setWalkSpeed(v) end; persist() end, 3)
	makeToggle(plAcc, "Infinity Jump", "Jump in mid-air infinitely",
		function() return CFG.infJumpEnabled end,
		function(v) if ctx.setInfJump then ctx.setInfJump(v) end; persist() end, 4)

	-- ESP Label Accordion
	local espAcc = makeAccordion(misc, "ESP Label (Pet & Egg)", 1, false)
	makeToggle(espAcc, "Enable ESP Label", "Label melayang di atas pet (nama+berat) & egg (nama+waktu hatch)",
		function() return CFG.espEnabled end,
		function(v)
			CFG.espEnabled = v; persist()
			if v then ctx.startEsp() else ctx.stopEsp() end
		end, 1)

	-- ESP Base Weight (Inventory) Accordion
	local espInvAcc = makeAccordion(misc, "ESP Base Weight (Inventory)", 2, false)
	makeToggle(espInvAcc, "Enable ESP Base Weight", "Tampilkan Base Weight di tiap slot pet saat buka inventory",
		function() return CFG.espInvEnabled end,
		function(v)
			CFG.espInvEnabled = v; persist()
			if v then ctx.startEspInv() else ctx.stopEspInv() end
		end, 1)
	local espInvModeOpts = { { name = "base", display = "Base Weight Only" }, { name = "age", display = "Base + Age" }, { name = "max", display = "Base + Max" } }
	makeSingleDropdown(espInvAcc, "Tampilan", "Pilih data yang tampil di label pet.",
		function() return espInvModeOpts end,
		function() for _, o in ipairs(espInvModeOpts) do if o.name == CFG.espInvMode then return o.display end end return "Base + Age" end,
		function(code) CFG.espInvMode = code; persist() end, 2)

	-- Automation Reconnect Accordion
	local rcAcc = makeAccordion(misc, "Automation Reconnect", 3, false)
	-- countdown live di paling atas
	local rcLbl = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		Text = "Reconnect: OFF", Font = F.bold, TextSize = 15,
		TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0,
	}, rcAcc)
	mk("Frame", { Size = UDim2.new(1, 0, 0, 8), BackgroundTransparency = 1, LayoutOrder = 0 }, rcAcc)
	task.spawn(function()
		while ctx.alive() do
			if CFG.reconnectEnabled then
				local rem = ctx.state.reconnectRemaining
				if rem then
					rcLbl.Text = ("⏱ Reconnect in: %d:%02d"):format(math.floor(rem / 60), rem % 60)
				else
					rcLbl.Text = "⏱ Reconnect: ON"
				end
				rcLbl.TextColor3 = C.acc
			else
				rcLbl.Text = "Reconnect: OFF"
				rcLbl.TextColor3 = C.sub
			end
			task.wait(0.5)
		end
	end)
	makeInput(rcAcc, "Interval (menit)", "Auto reconnect/rejoin tiap sekian menit (mis. 1 = tiap 1 menit).",
		function() return tostring(CFG.reconnectInterval) end,
		function(t) CFG.reconnectInterval = tonumber(t) or 5; persist() end, 1)
	makeToggle(rcAcc, "Auto Reconnect", "Automatically rejoin server on disconnect",
		function() return CFG.reconnectEnabled end,
		function(v) CFG.reconnectEnabled = v; persist(); if v and ctx.startReconnect then ctx.startReconnect() end end, 2)

	-- Webhook Settings Accordion
	local whAcc = makeAccordion(misc, "Discord Webhook Settings", 4, true)

	-- Discord Webhook URL Input
	makeInput(whAcc, "Discord Webhook URL", "Webhook URL for automation updates (Leveling, Mutation & Elephant)",
		function() return CFG.webhookUrl end,
		function(txt) CFG.webhookUrl = txt; persist() end, 1)

	-- Test Webhook Connection (Button)
	makeButton(whAcc, "Test Webhook Connection", "Send a test notification to your Discord channel",
		function()
			if not CFG.webhookUrl or CFG.webhookUrl == "" then
				ctx.log("[Webhook Test] Gagal: Webhook URL kosong!")
				return
			end
			ctx.log("[Webhook Test] Mengirim test payload...")
			task.spawn(function()
				local sendWebhook = ctx.sendWebhook
				if sendWebhook then
					pcall(function()
						sendWebhook(CFG.webhookUrl, {
							embeds = {
								{
									title = "Webhook Connection Test",
									description = "Koneksi Discord Webhook berhasil tersambung dengan CeszParadise Garden!",
									color = 3066993, -- Green
									fields = {
										{
											name = "Profile :",
											value = string.format("> Username : ||%s||", ctx.LP.Name),
											inline = false
										}
									},
									footer = {
										text = os.date("%B %d | %I:%M %p"),
										icon_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png"
									}
								}
							}
						}, ctx)
					end)
				else
					ctx.log("[Webhook Test] Gagal meload modul sender.")
				end
			end)
		end, 2)

	-- Performance / Graphics Optimization Accordion
	local perfAcc = makeAccordion(misc, "Performance", 5, false)
	makeToggle(perfAcc, "Hide My Garden Plants", "Hide plants on your own farm for better FPS",
		function() return CFG.hideMyPlants end,
		function(v) if ctx.setHidePlants then ctx.setHidePlants("mine", v) end; persist() end, 1)
	makeToggle(perfAcc, "Hide Other Gardens Plants", "Hide plants on other players' farms",
		function() return CFG.hideOtherPlants end,
		function(v) if ctx.setHidePlants then ctx.setHidePlants("other", v) end; persist() end, 2)
	makeToggle(perfAcc, "Auto Remove Spider Web FX", "Continuously remove spider web particle effects",
		function() return CFG.autoRemoveWebFx end,
		function(v) if ctx.setAutoRemoveWeb then ctx.setAutoRemoveWeb(v) end; persist() end, 3)
	mk("TextLabel", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Text = "- [ Graphics Optimization ] -", Font = F.bold, TextSize = 12, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 4 }, perfAcc)
	makeSingleDropdown(perfAcc, "Performance Mode", "Off: normal. Low: matiin shadow. Extreme: matiin semua efek partikel.",
		function() return ctx.getPerfModeOptions() end,
		function() local m = CFG.perfMode or "off"; for _, o in ipairs(ctx.getPerfModeOptions()) do if o.name == m then return o.display end end return "Off" end,
		function(code) if ctx.setPerfMode then ctx.setPerfMode(code) end; persist() end, 5)
	makeToggle(perfAcc, "Disable 3D Rendering", "Stop rendering the 3D world (huge FPS, black screen)",
		function() return CFG.disable3d end,
		function(v) if ctx.setDisable3d then ctx.setDisable3d(v) end; persist() end, 6)

	ctx.refreshTradeStatus()
end
