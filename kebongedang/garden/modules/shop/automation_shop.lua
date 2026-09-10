--[[ shop.lua — Automation Buy Seed / Egg / Gear.
     Opsi dropdown diambil dari REGISTRY katalog shop (bukan stock), jadi semua
     item tampil walau lagi habis; item baru dari update game auto masuk.
       Seed -> SeedShopData
       Gear -> GearShopData.Gear
       Egg  -> PetEggData
     Ada opsi "All" = beli semua yang lagi ada stock.
     Remote:
       BuySeedStock:FireServer("Shop", seedName)
       BuyGearStock:FireServer(gearName)
       BuyPetEgg:FireServer(eggIndex) ]]
return function(ctx)
	local DataService = ctx.deps.DataService
	local CFG = ctx.CFG
	local RS = game:GetService("ReplicatedStorage")
	local GE = RS:WaitForChild("GameEvents")
	local BuySeedStock = GE:WaitForChild("BuySeedStock")
	local BuyGearStock = GE:WaitForChild("BuyGearStock")
	local BuyPetEgg    = GE:WaitForChild("BuyPetEgg")
	local function setStatus(s) ctx.setStatus(s) end

	local function getData()
		local ok, d = pcall(function() return DataService:GetData() end)
		return ok and d or nil
	end

	-- Ambil daftar nama dari registry katalog; buang key non-item (RefreshTime, Gear).
	local function catalogNames(getTbl)
		local ok, t = pcall(getTbl)
		local out = {}
		if ok and type(t) == "table" then
			for k in pairs(t) do
				local n = tostring(k)
				if n ~= "RefreshTime" and n ~= "Gear" then out[#out + 1] = n end
			end
			table.sort(out)
		end
		return out
	end

	local function optionsFrom(names, sel)
		local out = { { value = "All", display = "All (beli semua)" } }
		for _, n in ipairs(names) do out[#out + 1] = { value = n, display = n } end
		return out
	end

	function ctx.getSeedShopOptions(sel)
		return optionsFrom(catalogNames(function() return require(RS.Data.SeedShopData) end), sel)
	end
	function ctx.getGearShopOptions(sel)
		return optionsFrom(catalogNames(function() return require(RS.Data.GearShopData).Gear end), sel)
	end
	function ctx.getEggShopOptions(sel)
		return optionsFrom(catalogNames(function() return require(RS.Data.PetEggData) end), sel)
	end

	----------------------------------------------------------------- loop beli
	-- Poll = cek marker restock (cuma BACA, bukan beli -> murah, ga lag).
	-- Beli tetap hanya saat marker berubah (restock). 2s biar deteksi cepat (minim miss).
	local POLL = 2

	local function buySeedLoop()
		ctx.state.buySeedId = (ctx.state.buySeedId or 0) + 1
		local myId = ctx.state.buySeedId
		ctx.elevate()
		local lastMarker
		while CFG.buySeedEnabled and ctx.alive() and ctx.state.buySeedId == myId do
			local d = getData()
			-- Game mindahin stok seed ke d.SeedStocks.Shop (d.SeedStock singular udah BEKU:
			-- markernya ga update lagi -> loop lama cuma beli sekali terus stuck "nunggu restock").
			-- Prefer path baru; fallback ke singular biar aman kalau server balikin lagi.
			local shop = d and ((d.SeedStocks and d.SeedStocks.Shop) or d.SeedStock)
			local marker = shop and shop.Seed
			if marker ~= lastMarker then -- restock baru (atau pertama jalan) -> beli
				lastMarker = marker
				local st = shop and shop.Stocks or {}
				local sel = CFG.buySeedNames or {}
				local all = sel["All"]
				local bought = 0
				for name, v in pairs(st) do
					if all or sel[name] then
						local stock = type(v) == "table" and v.Stock or 0
						for _ = 1, stock do
							if not CFG.buySeedEnabled or ctx.state.buySeedId ~= myId then break end
							pcall(function() BuySeedStock:FireServer("Shop", name) end)
							bought = bought + 1; task.wait(0.15)
						end
					end
				end
				setStatus(("Buy Seed: restock -> beli %d"):format(bought))
			else
				setStatus("Buy Seed: nunggu restock")
			end
			task.wait(POLL)
		end
	end

	local function buyGearLoop()
		ctx.state.buyGearId = (ctx.state.buyGearId or 0) + 1
		local myId = ctx.state.buyGearId
		ctx.elevate()
		local lastMarker
		while CFG.buyGearEnabled and ctx.alive() and ctx.state.buyGearId == myId do
			local d = getData()
			local marker = d and d.GearStock and d.GearStock.Gear
			if marker ~= lastMarker then
				lastMarker = marker
				local st = d and d.GearStock and d.GearStock.Stocks or {}
				local sel = CFG.buyGearNames or {}
				local all = sel["All"]
				local bought = 0
				for name, v in pairs(st) do
					if all or sel[name] then
						local stock = type(v) == "table" and v.Stock or 0
						for _ = 1, stock do
							if not CFG.buyGearEnabled or ctx.state.buyGearId ~= myId then break end
							pcall(function() BuyGearStock:FireServer(name) end)
							bought = bought + 1; task.wait(0.15)
						end
					end
				end
				setStatus(("Buy Gear: restock -> beli %d"):format(bought))
			else
				setStatus("Buy Gear: nunggu restock")
			end
			task.wait(POLL)
		end
	end

	local function buyEggLoop()
		ctx.state.buyEggId = (ctx.state.buyEggId or 0) + 1
		local myId = ctx.state.buyEggId
		ctx.elevate()
		local lastMarker
		while CFG.buyEggEnabled and ctx.alive() and ctx.state.buyEggId == myId do
			local d = getData()
			local marker = d and d.PetEggStock and d.PetEggStock.Egg
			if marker ~= lastMarker then
				lastMarker = marker
				local st = d and d.PetEggStock and d.PetEggStock.Stocks or {}
				local sel = CFG.buyEggNames or {}
				local all = sel["All"]
				local bought = 0
				for index, v in pairs(st) do
					local nm = type(v) == "table" and v.EggName
					local stock = type(v) == "table" and v.Stock or 0
					if nm and (all or sel[nm]) then
						for _ = 1, stock do
							if not CFG.buyEggEnabled or ctx.state.buyEggId ~= myId then break end
							pcall(function() BuyPetEgg:FireServer(index) end)
							bought = bought + 1; task.wait(0.15)
						end
					end
				end
				setStatus(("Buy Egg: restock -> beli %d"):format(bought))
			else
				setStatus("Buy Egg: nunggu restock")
			end
			task.wait(POLL)
		end
	end

	function ctx.startBuySeed() task.spawn(buySeedLoop) end
	function ctx.startBuyGear() task.spawn(buyGearLoop) end
	function ctx.startBuyEgg() task.spawn(buyEggLoop) end
end
