--[[ automation_merchant.lua — Auto Buy Merchant (Traveling Merchant + Event/Night Shop).

     DUA jenis shop, disatuin di UI/loop yang sama:

     1) TRAVELING MERCHANT (kind "travel") — cuma 1 aktif per waktu.
          Katalog: TravelingMerchantData[MerchantType].ShopData
          Stok:    data.TravelingMerchantShopStock.Stocks[itemName].Stock
          Beli:    BuyTravelingMerchantShopStock:FireServer(itemName)               (sheckles)
          MerchantType di-canon-kan (dua "4th July" -> satu "American").

     2) EVENT / NIGHT SHOP (kind "event") — mis. Twilight Shop, Blood Moon Shop.
          Katalog: EventShopData[shopName]
          Stok:    data.EventShopStock[shopName].Stocks[itemName].Stock
          Beli:    BuyEventShopStock:FireServer(itemName, shopName)                 (sheckles)
          Ga perlu UI kebuka — remote diterima langsung selama shop lagi aktif.

     Item terpilih disimpan PER-ENTRI: CFG.merchantItems[id] = { [itemName]=true }.
     Toggle auto-buy (bisa nyala barengan, target di-UNION):
       merchantBuyEnabled -> beli item terpilih utk entri yang lagi ada stok
       merchantBuyAll     -> beli SEMUA item yang ada stock
       merchantBuyBest    -> beli 1 item TERMAHAL yang ada stock (per entri)
     Beli dipicu saat marker restock per-shop berubah, sama pola kayak Buy Seed. ]]
return function(ctx)
	local DataService = ctx.deps.DataService
	local CFG = ctx.CFG
	local RS = game:GetService("ReplicatedStorage")
	local GE = RS:WaitForChild("GameEvents")
	local BuyMerchant  = GE:WaitForChild("BuyTravelingMerchantShopStock")
	local BuyEventShop = GE:WaitForChild("BuyEventShopStock")
	local MerchantData = require(RS.Data.TravelingMerchant.TravelingMerchantData)
	local EventShopData = require(RS.Data.EventShopData)
	local EventShopUI = (function() local ok, m = pcall(function() return require(RS.Modules.EventShopUIController) end); return ok and m or nil end)()
	local UpdateService = (function() local ok, m = pcall(function() return require(RS.Modules.UpdateService) end); return ok and m or nil end)()
	local function setStatus(s) ctx.setStatus(s) end

	-- Event shop yang punya katalog di EventShopData (urutan tetap; UI-nya bisa dibuka).
	local KNOWN_EVENT = {
		"Twilight Shop", "Blood Moon Shop", "Summer Seed Shop", "Tide Token Shop",
		"Honey Coin Shop", "Honey Seed Shop", "Royal Jelly Shop", "Moon Coin Shop",
		"Easter Seed Shop", "Fall Market Seed Shop", "Fall Market Gear Shop",
		"Fall Market Pet Shop", "Fall Market Cosmetic Shop", "Goliath's Goods",
		"Goliath's Friends Deals",
	}

	-- Traveling merchant yang di-gabung jadi 1 entri UI (id canonical + judul rapih).
	local MERGE = {
		["American Traveling Merchant"]      = { id = "American", title = "American" },
		["American Traveling Merchant 2026"] = { id = "American", title = "American" },
	}
	local function canonId(mt) local m = MERGE[mt]; return m and m.id or mt end
	local function keysOf(id) -- id canonical -> daftar merchantType yang tercakup
		local ks = {}
		for key in pairs(MerchantData) do
			if canonId(key) == id then ks[#ks + 1] = key end
		end
		return ks
	end

	local function getData()
		local ok, d = pcall(function() return DataService:GetData() end)
		return ok and d or nil
	end

	-- Katalog + info traveling merchant yang AKTIF. return shopData, merchantType, merchantStock
	local function activeShop(d)
		d = d or getData()
		local ms = d and d.TravelingMerchantShopStock
		local mt = ms and ms.MerchantType
		if not mt or not MerchantData[mt] then return nil, nil, ms end
		return MerchantData[mt].ShopData, mt, ms
	end

	-- id ini traveling merchant? (kalau bukan -> dianggap event shop)
	local function isTravelId(id)
		for k in pairs(MerchantData) do if canonId(k) == id then return true end end
		return false
	end

	-- Semua event shop: KNOWN_EVENT dulu (urut), lalu shop lain yang ADA di EventShopStock
	-- (event lama/musiman yang katalognya ga di EventShopData -> tetap kebawa).
	local function allEventShops(d)
		local out, seen = {}, {}
		for _, s in ipairs(KNOWN_EVENT) do if not seen[s] then seen[s] = true; out[#out + 1] = s end end
		local ess = (d or getData()) and (d or getData()).EventShopStock
		local extra = {}
		if type(ess) == "table" then
			for shop, v in pairs(ess) do
				if shop ~= "" and type(v) == "table" and v.Stocks and not seen[shop] then
					seen[shop] = true; extra[#extra + 1] = shop
				end
			end
		end
		table.sort(extra)
		for _, s in ipairs(extra) do out[#out + 1] = s end
		return out
	end

	-- Katalog event shop: EventShopData kalau ada; else fallback dari stok live (tanpa harga).
	local function eventCatalog(shopName, d)
		local cat = EventShopData[shopName]
		if cat then return cat end
		local ess = (d or getData()) and (d or getData()).EventShopStock
		local s = ess and ess[shopName]
		local out = {}
		if s and type(s.Stocks) == "table" then
			for item in pairs(s.Stocks) do out[item] = { Price = 0, DisplayInShop = true } end
		end
		return out
	end

	-- Tampilkan SEMUA item yang di-display shop (TANPA filter harga). Item mahal (Price >= 1e9
	-- kayak Gnome, Pet Shard, Red Panda dll) itu harga Sheckle valid, dibeli via remote;
	-- PurchaseID/FallbackPrice cuma opsi Robux. Cuma skip DisplayInShop==false (disembunyiin game).
	local function isBuyable(v)
		return type(v) == "table" and v.DisplayInShop ~= false
	end

	-- Entri punya minimal 1 item yang bisa dibeli? (kalau ga ada, entri disembunyiin dari list)
	local function hasShecklesShop(shop)
		if type(shop) ~= "table" then return false end
		for _, v in pairs(shop) do
			if type(v) == "table" and v.DisplayInShop ~= false and isBuyable(v) then return true end
		end
		return false
	end
	local function entryHasSheckles(id, kind)
		if kind == "travel" then
			for _, key in ipairs(keysOf(id)) do
				if hasShecklesShop(MerchantData[key] and MerchantData[key].ShopData) then return true end
			end
			return false
		end
		return hasShecklesShop(eventCatalog(id))
	end

	----------------------------------------------------------------- opsi UI
	-- Daftar entri buat UI (traveling dulu diurut by title, lalu event shop).
	-- Cuma entri yang punya item beli-pakai-sheckles yang ditampilin.
	function ctx.getMerchantList()
		local out, seenId = {}, {}
		for key, m in pairs(MerchantData) do
			local id = canonId(key)
			if not seenId[id] and entryHasSheckles(id, "travel") then
				seenId[id] = true
				out[#out + 1] = { id = id, title = (MERGE[key] and MERGE[key].title) or m.Title or id, kind = "travel" }
			end
		end
		table.sort(out, function(a, b) return a.title < b.title end)
		for _, shopName in ipairs(allEventShops()) do
			if entryHasSheckles(shopName, "event") then
				out[#out + 1] = { id = shopName, title = shopName, kind = "event" }
			end
		end
		return out
	end

	-- Opsi item utk SATU entri (union katalog; item habis tetap tampil).
	function ctx.getMerchantItemOptions(id)
		local out = { { value = "All", display = "All (semua item)" } }
		local names, seen = {}, {}
		local function addFrom(shop)
			if not shop then return end
			for name, v in pairs(shop) do
				if v.DisplayInShop ~= false and isBuyable(v) and not seen[name] then
					seen[name] = true; names[#names + 1] = name
				end
			end
		end
		if isTravelId(id) then
			for _, key in ipairs(keysOf(id)) do addFrom(MerchantData[key] and MerchantData[key].ShopData) end
		else
			addFrom(eventCatalog(id))
		end
		table.sort(names)
		for _, n in ipairs(names) do out[#out + 1] = { value = n, display = n } end
		return out
	end

	-- Set selection utk entri (di-key pakai id).
	function ctx.merchantSelFor(id)
		CFG.merchantItems = CFG.merchantItems or {}
		CFG.merchantItems[id] = CFG.merchantItems[id] or {}
		return CFG.merchantItems[id]
	end

	-- Ada toggle auto-buy yang aktif? (master on/off buat loop)
	local function anyOn()
		return CFG.merchantBuyEnabled or CFG.merchantBuyAll or CFG.merchantBuyBest or false
	end
	ctx.merchantAnyOn = anyOn

	-- Ringkasan buat status live di UI: fokus ke ITEM yang dipilih buat dibeli per shop.
	-- res = { activeMerchant=<nama traveling aktif|nil>, mode="all"|"best"|nil,
	--         picks = { {title=, kind=, items={...}} ... } }  -- entri yang punya pilihan
	function ctx.getMerchantSummary()
		local d = getData()
		local _, mt = activeShop(d)
		local res = {
			activeMerchant = mt and (MerchantData[mt].Title or mt) or nil,
			mode = CFG.merchantBuyAll and "all" or (CFG.merchantBuyBest and "best") or nil,
			picks = {},
		}
		-- Kalau mode global (All/Best) nyala, item pilihan ga relevan.
		if res.mode then return res end
		-- Katalog gabungan buat 1 entri (buat ambil harga sheckles).
		local function catalogOf(id, kind)
			local cat = {}
			if kind == "travel" then
				for _, key in ipairs(keysOf(id)) do
					local sd = MerchantData[key] and MerchantData[key].ShopData
					if sd then for n, v in pairs(sd) do cat[n] = v end end
				end
			else
				cat = eventCatalog(id, d)
			end
			return cat
		end
		for _, m in ipairs(ctx.getMerchantList()) do
			local sel = (CFG.merchantItems and CFG.merchantItems[m.id]) or {}
			local cat = catalogOf(m.id, m.kind)
			local items = {}
			if sel["All"] then
				items = { { name = "All", price = nil } }
			else
				local names = {}
				for name, on in pairs(sel) do if on then names[#names + 1] = name end end
				table.sort(names)
				for _, name in ipairs(names) do
					local v = cat[name]
					items[#items + 1] = { name = name, price = v and v.Price or nil }
				end
			end
			if #items > 0 then
				res.picks[#res.picks + 1] = { title = m.title, kind = m.kind, items = items }
			end
		end
		return res
	end

	----------------------------------------------------------------- pilih target
	-- Toggle bisa nyala barengan; target-nya di-UNION (item ga dobel).
	-- stockOf(name) -> jumlah stock; selKey -> id buat CFG.merchantItems.
	local function pickTargets(catalog, stockOf, selKey)
		local targets, added = {}, {}
		local function add(name, s, price)
			if not added[name] then added[name] = true; targets[#targets + 1] = { name = name, stock = s, price = price } end
		end

		local buyAll   = CFG.merchantBuyAll
		local buySel   = CFG.merchantBuyEnabled
		local buyBest  = CFG.merchantBuyBest
		local sel = (CFG.merchantItems and CFG.merchantItems[selKey]) or {}
		local all = sel["All"]

		local bestName, bestPrice, bestStock = nil, -1, 0
		for name, v in pairs(catalog) do
			if v.DisplayInShop ~= false and isBuyable(v) then
				local s = stockOf(name)
				if s > 0 then
					local price = v.Price or 0
					if buyAll then
						add(name, s, price)
					else
						if buySel and (all or sel[name]) then add(name, s, price) end
					end
					if buyBest and price > bestPrice then bestName, bestPrice, bestStock = name, price, s end
				end
			end
		end
		if buyBest and bestName then add(bestName, bestStock, bestPrice) end
		return targets
	end

	----------------------------------------------------------------- loop beli
	local POLL = 2
	local function buyLoop()
		ctx.state.merchantId = (ctx.state.merchantId or 0) + 1
		local myId = ctx.state.merchantId
		ctx.elevate()
		local lastMarker = {} -- per-source: [srcKey] = markerVal

		-- Proses 1 source: beli target-nya kalau marker restock berubah. return jumlah beli.
		local function processSource(srcKey, marker, catalog, stockOf, selKey, buyFn)
			if lastMarker[srcKey] == marker then return nil end -- belum restock -> skip
			lastMarker[srcKey] = marker
			local targets = pickTargets(catalog, stockOf, selKey)
			local bought = 0
			for _, t in ipairs(targets) do
				for _ = 1, t.stock do
					if not anyOn() or ctx.state.merchantId ~= myId then break end
					pcall(buyFn, t.name)
					bought = bought + 1
					task.wait(0.15)
				end
			end
			return bought
		end

		while anyOn() and ctx.alive() and ctx.state.merchantId == myId do
			local d = getData()
			local acted = {}

			-- (1) Traveling merchant aktif
			local shop, mt, ms = activeShop(d)
			if mt then
				local marker = "travel|" .. tostring(mt) .. "|" .. tostring(ms.MerchantStartTime)
				local stocks = ms.Stocks or {}
				local bought = processSource("travel", marker, shop,
					function(n) return stocks[n] and stocks[n].Stock or 0 end,
					canonId(mt),
					function(n) BuyMerchant:FireServer(n) end)
				if bought then acted[#acted + 1] = ("%s:%d"):format(MerchantData[mt].Title or mt, bought) end
			else
				lastMarker["travel"] = nil -- reset biar pas merchant muncul langsung beli
			end

			-- (2) Event / night shop (Twilight, Blood Moon, event lama, ...)
			local ess = d and d.EventShopStock
			for _, shopName in ipairs(allEventShops(d)) do
				local s = ess and ess[shopName]
				local stocks = s and s.Stocks
				local catalog = eventCatalog(shopName, d)
				if stocks and catalog and next(catalog) then
					local marker = "event|" .. shopName .. "|" .. tostring(s.ShopSeed)
					local bought = processSource("event:" .. shopName, marker, catalog,
						function(n) return stocks[n] and stocks[n].Stock or 0 end,
						shopName,
						function(n) BuyEventShop:FireServer(n, shopName) end)
					if bought then acted[#acted + 1] = ("%s:%d"):format(shopName, bought) end
				else
					lastMarker["event:" .. shopName] = nil
				end
			end

			if #acted > 0 then
				setStatus("Merchant beli -> " .. table.concat(acted, ", "))
			else
				setStatus("Merchant: nunggu restock / merchant muncul")
			end
			task.wait(POLL)
		end
		setStatus("Merchant: idle")
	end

	function ctx.startBuyMerchant() task.spawn(buyLoop) end

	----------------------------------------------------------------- Open Shop UI
	-- Daftar shop buat dropdown "Merchant UI to Open" (event shop yang punya UI controller).
	function ctx.getEventShopOptions()
		local out = {}
		for _, s in ipairs(KNOWN_EVENT) do out[#out + 1] = { name = s, display = s } end
		return out
	end
	function ctx.getMerchantUiDisplay()
		return (CFG.merchantUiShop ~= nil and CFG.merchantUiShop ~= "") and CFG.merchantUiShop or "Select"
	end

	-- Nama ScreenGui event shop = shopName tanpa spasi + "EventShop_UI" (mis. "TwilightShopEventShop_UI").
	local function uiGuiName(shopName) return (shopName:gsub("%s+", "")) .. "EventShop_UI" end
	local function isUiOpen(shopName)
		local pg = ctx.LP and ctx.LP.PlayerGui
		local g = pg and pg:FindFirstChild(uiGuiName(shopName))
		return g and g.Enabled == true
	end
	local function shopActive(shopName)
		if not UpdateService then return true end
		local ok, r = pcall(function() return UpdateService:IsActive(shopName) end)
		return ok and r or false
	end

	-- Buka UI shop 1x (kalau shop aktif). return true kalau kebuka.
	function ctx.openEventShopUI(shopName)
		shopName = shopName or CFG.merchantUiShop
		if not shopName or shopName == "" or not EventShopUI then return false end
		if not shopActive(shopName) then
			setStatus(("Open UI: %s belum aktif"):format(shopName))
			return false
		end
		pcall(function() EventShopUI:Open(shopName) end)
		return true
	end

	-- Auto Open UI: jaga UI shop terpilih tetap kebuka (buka ulang kalau ke-close & shop aktif).
	local function autoOpenLoop()
		ctx.state.merchantUiId = (ctx.state.merchantUiId or 0) + 1
		local myId = ctx.state.merchantUiId
		while CFG.merchantAutoOpenUI and ctx.alive() and ctx.state.merchantUiId == myId do
			local shop = CFG.merchantUiShop
			if shop and shop ~= "" and EventShopUI then
				if shopActive(shop) then
					if not isUiOpen(shop) then pcall(function() EventShopUI:Open(shop) end) end
				end
			end
			task.wait(2)
		end
	end
	function ctx.startAutoOpenUI() task.spawn(autoOpenLoop) end
	function ctx.stopAutoOpenUI() ctx.state.merchantUiId = (ctx.state.merchantUiId or 0) + 1 end
end
