--[[ premium_shop.lua — Premium Shop beli via Robux atau Token.
     Sumber katalog: RS.Data.GiftData (sama seperti sc lain, ~394 item, live).
       tiap entry: { Display, NormalId (beli sendiri), GiftId (gift ke player) }.
     Beli:
       Token : GameEvents.TradeEvents.TradeTokens.Purchase:InvokeServer(id)
       Robux : MarketController:PromptPurchaseRobux(id, Enum.InfoType.Product)
     Gift  : pakai GiftId (game handle penerima). ]]
return function(ctx)
	local RS  = game:GetService("ReplicatedStorage")
	local MPS = game:GetService("MarketplaceService")
	local LP  = ctx.LP
	local CFG = ctx.CFG

	local MC; pcall(function() MC = require(RS.Modules.MarketController) end)
	local function giftData()
		local ok, d = pcall(function() return require(RS.Data.GiftData) end)
		return ok and d or {}
	end
	local function ttFolder()
		local ge = RS:FindFirstChild("GameEvents")
		local te = ge and ge:FindFirstChild("TradeEvents")
		return te and te:FindFirstChild("TradeTokens")
	end

	-- entry katalog berdasarkan key CFG.premiumItem.
	local function entryOf(key)
		local d = giftData()
		return key and d[key] or nil
	end

	------------------------------------------------------------- harga (Robux)
	-- Harga token dinamis (RAP), susah/ga stabil -> tampilkan harga Robux dari
	-- GetProductInfo. Di-cache; prefetch pelan di background (hindari rate limit).
	-- id -> number (harga) | false (id ga valid / ga dijual Robux) | nil (belum kebaca)
	-- PENTING: kegagalan karena throttle TIDAK di-cache (biar dicoba lagi), cuma
	-- id==0 / hasil valid-tanpa-harga yg di-cache false permanen.
	-- Cache disimpan di getgenv() biar SELAMAT dari reload script (dalam sesi/
	-- server yg sama) -> reload berikutnya 0 panggilan, harga langsung muncul.
	local priceCache = (getgenv and (getgenv().__AH_PREM_PRICE or (function() getgenv().__AH_PREM_PRICE = {}; return getgenv().__AH_PREM_PRICE end)())) or {}
	-- Tabel harga STATIS (id -> PriceInRobux), di-fetch sekali & ditempel di sini
	-- (kayak shop lain) -> instan selamanya, 0 panggilan walau reload/rejoin.
	-- Nilai 99999/999999999 = penanda off-sale dari game, sengaja tetap disimpan.
	-- Live-fetch tetap jalan buat id yg belum ada di sini (item/harga baru).
	local PRICE = {
		[3248690960]=19,[3248692171]=3,[3248692845]=55,[3248695199]=85,[3248695947]=21,[3248696942]=35,[3248697546]=80,[3248716238]=150,[3248744789]=175,[3249981764]=639,[3250137172]=49,[3250137261]=99,[3250137355]=325,[3250139018]=895,[3253012192]=240,[3259333414]=235,[3260229242]=39,
		[3260940714]=200,[3261009117]=99,[3265889601]=79,[3265889751]=99,[3265889948]=149,[3265927408]=6,[3265927978]=8,[3267528421]=999999999,[3267548052]=999999999,[3267548161]=999999999,[3267580365]=79,[3269001250]=459,[3273005969]=40900,[3273006109]=459,[3273679012]=999999999,[3273973729]=249,[3276346455]=19,[3276346509]=39,[3276346557]=89,[3276346676]=129,
		[3277000452]=149,[3277675404]=255,[3277814538]=575,[3277814625]=1699,[3278426597]=99999,[3281679093]=119,[3282157312]=999999999,[3282157462]=999999999,[3282870834]=205,[3282918403]=59,[3284390402]=715,[3286038236]=149,[3286560171]=119,[3290672626]=199,[3290672712]=575,[3290672848]=1699,[3295548770]=999999999,[3295548781]=1699,[3295548782]=999999999,[3300962946]=8000,
		[3300962950]=8000,[3300962952]=8000,[3300984139]=315,[3301473650]=39,[3301567955]=429,[3301567958]=149,[3301567960]=999999999,[3304968889]=329,[3306352279]=999999999,[3306352283]=999999999,[3306352284]=999999999,[3306767043]=139,[3311112163]=399,[3311388942]=999999999,[3311388948]=999999999,[3311388951]=999999999,[3312005774]=475,[3312007044]=135,[3312008833]=399,[3312011056]=419,
		[3312011732]=529,[3312012483]=589,[3312013208]=599,[3312013874]=679,[3312014286]=629,[3316261725]=99,[3316826714]=280,[3317459182]=99999,[3317459186]=99999,[3317459188]=999999999,[3317729900]=215,[3317730202]=715,[3323657547]=575,[3323657552]=999999999,[3323657553]=999999999,[3329526686]=189,[3329527365]=119,[3329528135]=35,[3330286148]=999999999,[3330286154]=99999,
		[3330286155]=99999,[3330562080]=929,[3338826790]=999999999,[3338826791]=999999999,[3338826792]=999999999,[3345148119]=385,[3345819463]=99999,[3345819470]=999999999,[3345819472]=999999999,[3352931398]=19,[3354130076]=115,[3354839803]=999999999,[3354839817]=999999999,[3354839826]=999999999,[3362680911]=999999999,[3362680916]=999999999,[3362680917]=999999999,[3371226353]=999999999,[3371226360]=999999999,[3371226363]=999999999,
		[3372004188]=395,[3379038152]=999999999,[3379038157]=999999999,[3379038159]=999999999,[3379245220]=139,[3379593726]=99999999,[3387753634]=999999999,[3387753638]=999999999,[3387753641]=199,[3388359799]=939,[3388360759]=897,[3388363071]=768,[3388363390]=839,[3394224231]=999999999,[3394224237]=999999999,[3394224239]=999999999,[3401426983]=149,[3401426984]=1249,[3401426985]=429,[3407391662]=199,
		[3407391663]=575,[3407391666]=1699,[3411693833]=749,[3414035789]=369,[3414586855]=149,[3420021043]=575,[3420021044]=1699,[3420021045]=199,[3426542757]=479,[3427163853]=9999999,[3427163854]=999999999,[3427163857]=999999,[3432380384]=399,[3438653517]=1699,[3438653518]=575,[3438653519]=199,[3444449485]=9999999,[3444449486]=9999999,[3444449487]=9999999,[3445155701]=6,
		[3445164189]=479,[3445262332]=530,[3449810469]=199,[3449810471]=1699,[3449810472]=575,[3455804869]=279,[3456989527]=150,[3460376533]=50,[3460378135]=250,[3460378800]=1000,[3460379424]=5000,[3460379831]=25000,[3460380041]=149,[3460380235]=149,[3460600736]=1699,
		[3460600737]=575,[3460600740]=199,[3461239818]=595,[3467103687]=1249,[3467103688]=429,[3467110142]=429,[3467110145]=1249,[3471911127]=1627,[3472461575]=625,[3472461579]=1899,[3472461584]=7450,[3472461585]=219,[3477922697]=429,[3477922698]=149,[3477922700]=1249,[3478031738]=149,[3478031853]=429,[3478031941]=1249,[3478043835]=4999,[3482199602]=79,
		[3482199918]=230,[3482200241]=679,[3482271454]=1799,[3482980939]=679,[3482982251]=799,[3483801741]=149,[3483801743]=4999,[3483801744]=1249,[3483801745]=429,[3489363338]=429,[3489363342]=1249,[3489363343]=149,[3489363344]=4999,[3490207231]=1299,[3497475839]=149,[3497475843]=4999,[3497475844]=1249,[3497475846]=429,[3498980651]=1799,
		[3512151971]=149,[3512151973]=429,[3512151976]=1249,[3512151977]=4999,[3519865801]=799,[3520430327]=429,[3520430328]=1249,[3520430329]=149,[3520430331]=4999,[3546475721]=1700,[3563674024]=1699,[3568823262]=639,[3568827015]=59,[3568827227]=175,[3568827595]=499,[3570157250]=4999,[3570335691]=6999,[3576524674]=149,[3576524780]=429,[3576524860]=1249,
		[3576525035]=4999,[3584036637]=149,[3584036735]=429,[3584036839]=1249,[3584075576]=639,[3587190661]=4999,[3587239446]=639,[3588292639]=199,[3588293165]=575,[3588293244]=1699,[3588293328]=6999,[3602505965]=149,[3602506028]=429,[3602506064]=1249,[3602506115]=4999,[3602742364]=639,[3603829987]=199,[3603830024]=575,[3603830055]=1699,[3603830077]=6999,
		[3607717721]=59,[3607717736]=175,[3607717758]=499,[3607717778]=1999,[3607717910]=639,[3608858826]=79,[3608858860]=230,[3608858882]=679,[3608858906]=2799,[3610249313]=279,[3611262564]=59,[3611262600]=175,[3611262627]=499,[3612305749]=59,[3612305786]=175,[3612305812]=499,[3612305842]=1999,[3612306093]=639,[3625639161]=79,[3625640337]=230,[3625641435]=679,[3625642643]=2799,[3708088084]=959,
	}
	-- Harga dari MarketplaceService:GetProductInfo(id, Product) — HARUS pakai
	-- InfoType.Product (MC:GetProductInfo cache-nya di-key by id doang, bisa
	-- ketuker sama info Asset). Engine nge-cache hasil per (id,infoType), jadi
	-- id yg udah pernah kefetch (mis. sama shop asli game) balik instan.
	-- RetryPcall manual: throttle ga di-cache -> diulang di pass prefetch berikut.
	local function fetchPrice(id)
		if id == nil or id == 0 then return nil end
		local st = PRICE[id]                     -- tabel statis: instan, 0 panggilan
		if st ~= nil then return st end
		local c = priceCache[id]
		if c ~= nil then return c or nil end
		local ok, info = pcall(function() return MPS:GetProductInfo(id, Enum.InfoType.Product) end)
		if not ok then return nil end           -- throttle/error: jangan cache, coba lagi nanti
		local p = info and info.PriceInRobux
		priceCache[id] = p or false             -- ok tapi ga ada harga = ga dijual Robux
		return p or nil
	end

	local prefetchStarted = false
	-- Prefetch PARALEL (bounded): fetchPrice yield di network, jadi N worker
	-- coroutine bikin ~N request barengan (game aslinya izinin ~36) -> jauh
	-- lebih cepet drpd 1-per-1. Multi-pass buat yg kena throttle (belum ke-cache).
	local WORKERS = 24
	local function startPrefetch(entries)
		if prefetchStarted then return end
		prefetchStarted = true
		task.spawn(function()
			for pass = 1, 6 do
				local idx = 0
				local finished = 0
				for _ = 1, WORKERS do
					task.spawn(function()
						while ctx.alive() do
							idx = idx + 1                 -- coroutine kooperatif: aman antar-yield
							local e = entries[idx]
							if not e then break end
							if e.id ~= 0 and priceCache[e.id] == nil then fetchPrice(e.id) end
						end
						finished = finished + 1
					end)
				end
				while finished < WORKERS and ctx.alive() do task.wait() end
				local remaining = 0
				for _, e in ipairs(entries) do
					if e.id ~= 0 and priceCache[e.id] == nil then remaining = remaining + 1 end
				end
				if remaining == 0 or not ctx.alive() then break end
				task.wait(0.5)                            -- napas sebentar sebelum retry throttle
			end
		end)
	end

	-- prewarm: mulai isi cache harga di background (dipanggil pas hub kebuka),
	-- jadi pas buka Premium Shop harga udah siap. Ringan & ga nge-block.
	function ctx.premiumPrewarm()
		local d = giftData()
		local ids = {}
		for _, v in pairs(d) do
			if type(v) == "table" and v.NormalId and v.NormalId ~= 0 and PRICE[v.NormalId] == nil then
				ids[#ids + 1] = { id = v.NormalId }   -- yg udah di tabel statis ga usah fetch
			end
		end
		startPrefetch(ids)
	end

	-- opsi dropdown item: cuma entry yg BENERAN bisa dibeli (NormalId ~= 0).
	-- Item 0/0 (mis. seed) itu cuma item trade/RAP, ga dijual di shop -> skip.
	-- Display + harga Robux (kalau udah ke-cache). Prefetch jalan di background.
	function ctx.getPremiumItemOptions()
		local d = giftData()
		local out, ids = {}, {}
		for k, v in pairs(d) do
			if type(v) == "table" and v.NormalId and v.NormalId ~= 0 then
				local disp = tostring(v.Display or k)
				local p = PRICE[v.NormalId] or priceCache[v.NormalId]
				if type(p) == "number" then
					disp = disp .. ("  (R$ %d)"):format(p)
				end
				out[#out + 1] = { name = k, display = disp }
				if PRICE[v.NormalId] == nil then ids[#ids + 1] = { id = v.NormalId } end
			end
		end
		table.sort(out, function(a, b) return a.display < b.display end)
		startPrefetch(ids)
		return out
	end
	function ctx.getPremiumPayOptions()
		return { { name = "robux", display = "Robux" }, { name = "token", display = "Token" } }
	end

	-- prompt beli 1 id sesuai payment method (token / robux).
	local function purchaseId(id, label)
		if CFG.premiumPay == "token" then
			local tt = ttFolder()
			if not (tt and tt:FindFirstChild("Purchase")) then ctx.setStatus("Premium Shop: Token remote ga ada"); return end
			local canOk, can = pcall(function() return tt.CanPurchase:InvokeServer(id) end)
			if canOk and can then
				pcall(function() tt.Purchase:InvokeServer(id) end)
				ctx.setStatus("Premium Shop: " .. label .. " via Token…")
			else
				ctx.setStatus("Premium Shop: item ini ga bisa Token, pakai Robux")
			end
		else
			if MC and MC.PromptPurchaseRobux then
				pcall(function() MC:PromptPurchaseRobux(id, Enum.InfoType.Product) end)
			else
				pcall(function() MPS:PromptProductPurchase(LP, id) end)
			end
			ctx.setStatus("Premium Shop: prompt Robux " .. label .. " dibuka")
		end
	end

	-- fetch harga item terpilih & tampilkan di status (dipanggil saat milih item).
	function ctx.premiumShowPrice()
		local e = entryOf(CFG.premiumItem)
		if not (e and e.NormalId) then return end
		local name = tostring(e.Display or CFG.premiumItem)
		local p = fetchPrice(e.NormalId)
		if p then
			ctx.setStatus(("Premium: %s — R$ %d"):format(name, p))
		else
			ctx.setStatus(("Premium: %s"):format(name))
		end
	end

	-- BELI buat diri sendiri (NormalId).
	function ctx.premiumBuy()
		local e = entryOf(CFG.premiumItem)
		if not (e and e.NormalId) then ctx.setStatus("Premium Shop: pilih item dulu"); return end
		purchaseId(e.NormalId, "beli")
	end

	-- GIFT ke player (GiftId). Game yg minta penerima.
	function ctx.premiumGift()
		local e = entryOf(CFG.premiumItem)
		if not (e and e.GiftId) then ctx.setStatus("Premium Shop: item ini ga ada opsi Gift"); return end
		purchaseId(e.GiftId, "gift")
	end
end
