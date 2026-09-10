--[[ automation_beanstalk.lua — Automation Beanstalk Event (NPC Jack).
     Beanstalk minta 1 TRAIT tanaman (mis. "Vegetable"), refresh tiap jam. Feed plant
     yang trait-nya cocok -> naikin Beanstalk Growth global (mis. 0/900) & dapat reward.
     Craving DIBACA dari billboard "We need <trait> Plants" (selalu akurat, ga nebak RNG).

     Flow (tiap sub-toggle bisa nyala sendiri, jalan 1 loop):
       Auto Plant   : tanam seed yang trait-nya == craving, sampai target N (input).
       Auto Collect : panen fruit yang trait-nya == craving (ke backpack).
       Auto Submit  : equip tiap produce tool trait==craving -> SubmitHeldPlant.
                      SENGAJA per-plant (bukan SubmitAllPlant) biar crop lain (non-craving,
                      mahal) TIDAK ikut kefeed. Aman.

     Remote:
       Plant_RE:FireServer(pos, seedName)
       GameEvents.Crops.Collect:FireServer({fruitModels})
       GameEvents.Events.BeanstalkEvent.BeanstalkRESubmitHeldPlant:FireServer()
]]
return function(ctx)
	local LP          = ctx.LP
	local CFG         = ctx.CFG
	local RS          = game:GetService("ReplicatedStorage")
	local GE          = RS:WaitForChild("GameEvents")
	local DataService = ctx.deps.DataService
	local function setStatus(s) ctx.setStatus(s) end

	local Plant_RE = GE:WaitForChild("Plant_RE")
	local Collect  = GE:WaitForChild("Crops"):WaitForChild("Collect")
	local BeanEv   = GE:WaitForChild("Events"):WaitForChild("BeanstalkEvent")
	local SubmitHeld = BeanEv:WaitForChild("BeanstalkRESubmitHeldPlant")
	local SubmitAll  = BeanEv:WaitForChild("BeanstalkRESubmitAllPlant")
	local SellInventory = GE:FindFirstChild("Sell_Inventory") -- jual SEMUA isi backpack (NPC Steven)
	local IS; pcall(function() IS = require(RS.Modules.InventoryService) end)
	local function backpackFull()
		if not IS then return false end
		local ok, full = pcall(function() return IS:IsMaxInventory() end)
		return ok and full == true
	end

	local PlantTraits
	pcall(function() PlantTraits = require(RS.Modules.PlantTraitsData) end)
	local ALL_TRAITS = { "Berry", "Flower", "Fruit", "Leafy", "Vegetable", "Woody", "Prickly", "Stalky", "Tropical" }
	pcall(function()
		local cfg = require(RS.Data.Events.BeanstalkEvent.BeanstalkEventConfig)
		if type(cfg.Traits) == "table" and #cfg.Traits > 0 then ALL_TRAITS = cfg.Traits end
	end)

	local function hasTrait(name, trait)
		if not name or name == "" or not trait then return false end
		if PlantTraits and PlantTraits.HasTrait then
			local ok, res = pcall(function() return PlantTraits.HasTrait(name, trait) end)
			if ok then return res == true end
		end
		return false
	end

	----------------------------------------------------------------- craving (baca billboard)
	local function beanModel() return workspace:FindFirstChild("Interaction") and workspace.Interaction:FindFirstChild("BeanstalkEventModel") end
	-- Buang tag rich-text lalu cari trait yang cocok di ALL_TRAITS.
	local function parseTrait(txt)
		if not txt then return nil end
		local clean = txt:gsub("<[^>]->", "")
		for _, tr in ipairs(ALL_TRAITS) do
			if clean:find(tr, 1, true) then return tr end
		end
		return nil
	end
	-- craving trait sekarang (nil kalau event ga aktif / label ga ketemu)
	local function currentCraving()
		local m = beanModel(); if not m then return nil end
		for _, g in ipairs(m:GetDescendants()) do
			if g:IsA("TextLabel") and g.Text:find("need") then
				local tr = parseTrait(g.Text)
				if tr then return tr end
			end
		end
		return nil
	end
	-- progress growth global "X/Y" dari billboard (buat status)
	local function growthText()
		local m = beanModel(); if not m then return nil end
		for _, g in ipairs(m:GetDescendants()) do
			if g:IsA("TextLabel") then
				local a, b = g.Text:match("^(%d+)%s*/%s*(%d+)$")
				if a and b then return a .. "/" .. b end
			end
		end
		return nil
	end
	-- Event aktif = model ada DAN billboard nampilin UI event (craving / growth / decay).
	-- CATATAN: attribute workspace "ActivateBeanstalk" TERNYATA ga reliable (bisa false pas
	-- event jelas jalan), jadi JANGAN dipakai. Billboard = sumber kebenaran.
	-- Beanstalk PENUH (growth mentok a>=b): setor lebih lanjut percuma, tunggu reset.
	-- CATATAN: label "Beanstalk Decays in:" itu timer decay NORMAL yg SELALU muncul selama
	-- event jalan (bukan penanda cooldown), jadi JANGAN dipakai — cukup cek growth mentok.
	local function isDecaying()
		local m = beanModel(); if not m then return false end
		for _, g in ipairs(m:GetDescendants()) do
			if g:IsA("TextLabel") then
				local a, b = g.Text:match("^(%d+)%s*/%s*(%d+)$")
				if a and b and tonumber(a) >= tonumber(b) then return true end
			end
		end
		return false
	end
	local function isActive()
		if beanModel() == nil then return false end
		return currentCraving() ~= nil or growthText() ~= nil or isDecaying()
	end

	----------------------------------------------------------------- seed inventory (per trait)
	local function seedInventory()
		local out = {}
		local ok, d = pcall(function() return DataService:GetData() end)
		if ok and d and type(d.InventoryData) == "table" then
			for _, v in pairs(d.InventoryData) do
				if type(v) == "table" and v.ItemType == "Seed" and v.ItemData then
					local nm = v.ItemData.ItemName
					local q = tonumber(v.ItemData.Quantity) or 0
					if nm then out[nm] = (out[nm] or 0) + q end
				end
			end
		end
		return out
	end

	----------------------------------------------------------------- farm helpers (plant)
	local function myFarm()
		local ok, GetFarm = pcall(function() return require(RS.Modules.GetFarm) end)
		if ok and GetFarm then
			local ok2, f = pcall(function() return GetFarm(LP) end)
			if ok2 then return f end
		end
		return nil
	end
	local function canPlantParts()
		local f = myFarm()
		local imp = f and f:FindFirstChild("Important")
		local pl = imp and imp:FindFirstChild("Plant_Locations")
		local parts = {}
		if pl then for _, p in ipairs(pl:GetChildren()) do if p:IsA("BasePart") then parts[#parts + 1] = p end end end
		return parts
	end
	local function randomPos()
		local parts = canPlantParts()
		if #parts == 0 then return nil end
		local p = parts[math.random(1, #parts)]
		local hx, hz = p.Size.X / 2 - 1, p.Size.Z / 2 - 1
		local x = p.Position.X + (math.random() * 2 - 1) * hx
		local z = p.Position.Z + (math.random() * 2 - 1) * hz
		return Vector3.new(x, p.Position.Y, z)
	end
	-- equip seed tool "<Nama> Seed [Xn]" (server wajib megang pas Plant_RE)
	local function seedBase(t) return t:IsA("Tool") and t.Name:match("^(.-) Seed %[X%d+%]") or nil end
	local function holdingSeed(name)
		local ch = LP.Character
		if ch then for _, t in ipairs(ch:GetChildren()) do if seedBase(t) == name then return true end end end
		return false
	end
	local function equipSeed(name)
		if holdingSeed(name) then return true end
		local bp = LP:FindFirstChild("Backpack")
		local tool
		if bp then for _, t in ipairs(bp:GetChildren()) do if seedBase(t) == name then tool = t; break end end end
		if tool then
			local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
			if hum then pcall(function() hum:EquipTool(tool) end) end
		end
		return holdingSeed(name)
	end

	----------------------------------------------------------------- fruit di farm (collect)
	-- PENTING: cuma sentuh kebun MILIK SENDIRI. Semua garden namanya "Farm", dibedain lewat
	-- Important.Data.Owner. Dulu cuma skip CommunityGarden -> kesapu kebun pemain lain (bug).
	local function myGarden()
		local f = myFarm()            -- via GetFarm(LP), paling akurat
		if f then return f end
		local Farm = workspace:FindFirstChild("Farm"); if not Farm then return nil end
		for _, g in ipairs(Farm:GetChildren()) do
			local d = g:FindFirstChild("Important") and g.Important:FindFirstChild("Data")
			local o = d and d:FindFirstChild("Owner")
			if o and o.Value == LP.Name then return g end
		end
		return nil
	end
	local function myPlantsPhysical()
		local g = myGarden(); local imp = g and g:FindFirstChild("Important")
		return imp and imp:FindFirstChild("Plants_Physical")
	end
	local function eachFruit(fn)
		local pp = myPlantsPhysical(); if not pp then return end
		for _, plant in ipairs(pp:GetChildren()) do
			local fr = plant:FindFirstChild("Fruits")
			if fr then for _, f in ipairs(fr:GetChildren()) do fn(f) end end
		end
	end

	-- iterasi tiap plant (model) yang lagi tumbuh di kebun SENDIRI
	local function eachPlant(fn)
		local pp = myPlantsPhysical(); if not pp then return end
		for _, plant in ipairs(pp:GetChildren()) do
			if plant:IsA("Model") then fn(plant) end
		end
	end
	-- cache nama tanaman -> set trait (biar HasTrait ga dipanggil berulang)
	local nameTraitCache = {}
	local function traitsOf(name)
		local c = nameTraitCache[name]
		if c then return c end
		c = {}
		for _, tr in ipairs(ALL_TRAITS) do if hasTrait(name, tr) then c[tr] = true end end
		nameTraitCache[name] = c
		return c
	end
	-- jumlah plant tumbuh per SEMUA trait (1x pass). return map trait->count
	local function plantedByTrait()
		local counts = {}
		for _, tr in ipairs(ALL_TRAITS) do counts[tr] = 0 end
		eachPlant(function(p)
			for tr in pairs(traitsOf(p.Name)) do counts[tr] = (counts[tr] or 0) + 1 end
		end)
		return counts
	end
	-- jumlah plant 1 trait yang sudah ketanam (+ breakdown per nama)
	local function plantedInfo(trait)
		local total, byName = 0, {}
		eachPlant(function(p)
			if hasTrait(p.Name, trait) then
				total = total + 1
				byName[p.Name] = (byName[p.Name] or 0) + 1
			end
		end)
		return total, byName
	end

	----------------------------------------------------------------- produce tool di backpack (submit)
	-- Tool hasil panen: punya child "Item_String" (nama tanaman), bukan pet (PET_UUID), bukan seed.
	local function produceName(t)
		if not t:IsA("Tool") then return nil end
		if t:GetAttribute("PET_UUID") then return nil end
		if t.Name:match("Seed %[X%d+%]") then return nil end
		local is = t:FindFirstChild("Item_String")
		if is and is.Value ~= "" then return is.Value end
		return nil
	end
	-- daftar produce tool di backpack yang cocok trait
	local function cravingProduceTools(trait)
		local out = {}
		local bp = LP:FindFirstChild("Backpack"); if not bp then return out end
		for _, t in ipairs(bp:GetChildren()) do
			local nm = produceName(t)
			if nm and hasTrait(nm, trait) then out[#out + 1] = t end
		end
		return out
	end

	----------------------------------------------------------------- status summary buat GUI
	function ctx.getBeanstalkSummary()
		local craving = currentCraving()
		local res = { active = isActive(), craving = craving, traits = ALL_TRAITS }
		res.growth = growthText() or "-"
		local ok, d = pcall(function() return DataService:GetData() end)
		res.contributed = (ok and d and d.BeanstalkEvent and d.BeanstalkEvent.EventsContributed) or 0
		res.target = tonumber(CFG.beanstalkPlantCount) or 0
		-- ketanam per SEMUA trait (buat display "Vegetable 50/20, Flower 0/20, ...")
		local counts = plantedByTrait()
		res.perTrait = {}
		for _, tr in ipairs(ALL_TRAITS) do
			res.perTrait[#res.perTrait + 1] = { trait = tr, planted = counts[tr] or 0, target = res.target, craving = (tr == craving) }
		end
		if craving then
			res.ready = #cravingProduceTools(craving)               -- produce craving siap setor
			res.planted = counts[craving] or 0                      -- ketanam trait craving
			local seeds, seedTotal = seedInventory(), 0
			for nm, q in pairs(seeds) do if q > 0 and hasTrait(nm, craving) then seedTotal = seedTotal + q end end
			res.seeds = seedTotal
		else
			res.ready, res.seeds, res.planted = 0, 0, 0
		end
		return res
	end

	----------------------------------------------------------------- aksi tunggal (reusable)
	-- FOKUS 1 TRAIT per panggilan: pilih trait pertama (urutan ALL_TRAITS) yang masih < target
	-- DAN ada seed-nya, tanam persis sampai target (ga lebih). Count dihitung ulang tiap siklus
	-- jadi ga overshoot. return jumlahBaru, namaTrait.
	function ctx.beanstalkPlantOnce(target)
		target = tonumber(target) or 0; if target <= 0 then return 0, nil end
		local counts = plantedByTrait()
		local inv = seedInventory()
		for _, trait in ipairs(ALL_TRAITS) do
			local need = target - (counts[trait] or 0)
			if need > 0 then
				local names = {}
				for nm, q in pairs(inv) do if q > 0 and hasTrait(nm, trait) then names[#names + 1] = nm end end
				table.sort(names)
				if #names > 0 then
					local planted = 0
					for _, name in ipairs(names) do
						while (inv[name] or 0) > 0 and planted < need do
							if not CFG.beanstalkPlantEnabled or not ctx.alive() then return planted, trait end
							if equipSeed(name) then
								local pos = randomPos()
								if pos then
									pcall(function() Plant_RE:FireServer(pos, name) end)
									planted = planted + 1; inv[name] = inv[name] - 1
								else break end
							else break end
							task.wait(tonumber(CFG.beanstalkDelay) or 0.2)
						end
						if planted >= need then break end
					end
					return planted, trait  -- selesai 1 trait dulu, sisanya siklus berikut
				end
			end
		end
		return 0, nil
	end

	-- Panen fruit craving ke backpack. return jumlah dikirim, atau -1 kalau backpack penuh (dijeda).
	function ctx.beanstalkCollectOnce(trait)
		trait = trait or currentCraving(); if not trait then return 0 end
		if backpackFull() then return -1 end   -- penuh: jeda collect (ga spam)
		local batch = {}
		eachFruit(function(f) if hasTrait(f.Name, trait) then batch[#batch + 1] = f end end)
		local n = 0
		for i = 1, #batch, 40 do
			if not ctx.alive() then break end
			local chunk = {}
			for j = i, math.min(i + 39, #batch) do chunk[#chunk + 1] = batch[j] end
			pcall(function() Collect:FireServer(chunk) end)
			n = n + #chunk
			task.wait(0.1)
		end
		return n
	end

	-- Setor SEMUA plant sekaligus (BeanstalkRESubmitAllPlant, 1 call). Server hanya kredit
	-- plant yang sesuai craving. return jumlah produce craving yang ada saat setor (perkiraan).
	function ctx.beanstalkSubmitOnce(trait)
		trait = trait or currentCraving(); if not trait then return 0 end
		local n = #cravingProduceTools(trait)
		if n <= 0 then return 0 end
		pcall(function() SubmitAll:FireServer() end)
		task.wait(0.5)
		return n
	end

	-- Claim reward: tiap RewardPoint yang ProximityPrompt-nya Enabled -> fireproximityprompt.
	-- Itu memicu handler client asli (BeanstalkGrowController) yang FireServer ClaimReward(i)
	-- dengan index BENAR, jadi ga usah nebak index. return jumlah reward yang di-claim.
	local function rewardPrompts()
		local m = beanModel(); if not m then return {} end
		local bs = m:FindFirstChild("BeanStalk2")
		local root = bs and bs:FindFirstChild("Root")
		local rp = root and root:FindFirstChild("RewardPoints")
		local out = {}
		if rp then
			for _, pt in ipairs(rp:GetChildren()) do
				local pp = pt:FindFirstChildWhichIsA("ProximityPrompt", true)
				if pp and pp.Enabled then out[#out + 1] = pp end
			end
		end
		return out
	end
	function ctx.beanstalkClaimOnce()
		if type(fireproximityprompt) ~= "function" then return 0 end
		local prompts = rewardPrompts()
		local n = 0
		for _, pp in ipairs(prompts) do
			if not ctx.alive() then break end
			pcall(function() fireproximityprompt(pp) end)
			n = n + 1
			task.wait(0.2)
		end
		return n
	end

	local function claimLoop()
		ctx.state.beanClaimId = (ctx.state.beanClaimId or 0) + 1
		local myId = ctx.state.beanClaimId
		ctx.elevate()
		while CFG.beanstalkClaimEnabled and ctx.alive() and ctx.state.beanClaimId == myId do
			if isActive() then
				local c = ctx.beanstalkClaimOnce()
				if c > 0 then setStatus(("Beanstalk: claim %d reward"):format(c)) end
			end
			task.wait(3)
		end
	end
	function ctx.startBeanstalkClaim()
		if not CFG.beanstalkClaimEnabled then return end
		task.spawn(claimLoop)
	end
	function ctx.stopBeanstalkClaim() ctx.state.beanClaimId = (ctx.state.beanClaimId or 0) + 1 end

	-- Jual SEMUA isi backpack (recovery pas mentok: backpack penuh trait salah). Return true kalau di-fire.
	function ctx.beanstalkSellAll()
		if not SellInventory then return false end
		pcall(function() SellInventory:FireServer() end)
		return true
	end

	----------------------------------------------------------------- loop utama (1 loop, semua toggle)
	local function anyOn() return CFG.beanstalkPlantEnabled or CFG.beanstalkCollectEnabled or CFG.beanstalkSubmitEnabled or false end
	ctx.beanstalkAnyOn = anyOn

	local function beanstalkLoop()
		ctx.state.beanstalkId = (ctx.state.beanstalkId or 0) + 1
		local myId = ctx.state.beanstalkId
		ctx.elevate()
		while anyOn() and ctx.alive() and ctx.state.beanstalkId == myId do
			if not isActive() then
				setStatus("Beanstalk: event ga aktif, tunggu...")
				task.wait(5)
			else
				-- Auto Plant: top-up SEMUA trait, ga butuh craving (pre-stock).
				if CFG.beanstalkPlantEnabled then
					local p, tr = ctx.beanstalkPlantOnce(CFG.beanstalkPlantCount)
					if p > 0 then setStatus(("Beanstalk: tanam %d %s"):format(p, tr or "")) end
				end
				local trait = currentCraving()
				if not trait then
					if not CFG.beanstalkPlantEnabled then setStatus("Beanstalk: craving ga kebaca, tunggu...") end
					task.wait(3)
				else
					if isDecaying() then
						-- growth penuh: setor ditolak (CD). Cukup nunggu refresh, jangan setor/jual/collect.
						setStatus("Beanstalk: growth penuh (CD) — nunggu refresh")
					else
						-- 1) SUBMIT dulu: kredit produce craving + kosongin slot-nya di backpack.
						if CFG.beanstalkSubmitEnabled then
							local s = ctx.beanstalkSubmitOnce(trait)
							if s > 0 then setStatus(("Beanstalk: setor %d %s"):format(s, trait))
							else setStatus(("Beanstalk: nunggu %s plant (craving)"):format(trait)) end
						end
						-- 2) Backpack MASIH penuh setelah submit = keisi trait salah (clog).
						--    Jual semua biar lega (kalau toggle Auto Sell ON). Produce craving udah
						--    kesetor di langkah 1, jadi yang kejual cuma sisa trait lain.
						local full = backpackFull()
						if full and CFG.beanstalkAutoSellEnabled and #cravingProduceTools(trait) == 0 then
							if ctx.beanstalkSellAll() then
								setStatus("Beanstalk: backpack mentok (trait salah) — jual semua")
								task.wait(1); full = backpackFull()
							end
						end
						-- 3) COLLECT fruit craving (isi backpack buat disetor siklus berikut).
						if CFG.beanstalkCollectEnabled then
							local c = ctx.beanstalkCollectOnce(trait)
							if c > 0 then setStatus(("Beanstalk: panen %d %s"):format(c, trait))
							elseif c < 0 then setStatus("Beanstalk: backpack penuh — collect dijeda"..(CFG.beanstalkAutoSellEnabled and "" or " (nyalain Auto Sell)")) end
						end
					end
					task.wait(math.max(0.5, tonumber(CFG.beanstalkDelay) or 0.5) + 0.5)
				end
			end
		end
	end

	function ctx.startBeanstalk()
		if not anyOn() then return end
		task.spawn(beanstalkLoop)
	end
	function ctx.stopBeanstalk() ctx.state.beanstalkId = (ctx.state.beanstalkId or 0) + 1 end

	----------------------------------------------------------------- Beanstalk Event Shop (auto-buy)
	-- Shop beanstalk = "Goliath's Goods" (Main) + "Goliath's Friends Deals" (Friendship).
	-- Beli: GameEvents.BuyEventShopStock:FireServer(item, shopName). Currency Sheckles.
	local SHOP_LIST = { "Goliath's Goods", "Goliath's Friends Deals" }
	local BuyEventShopStock = GE:FindFirstChild("BuyEventShopStock")
	local function eventShopData()
		local ok, ESD = pcall(function() return require(RS.Data.EventShopData) end)
		return ok and ESD or {}
	end
	-- Tampilkan SEMUA item yang di-display shop (TANPA filter harga). Item mahal (Price >= 1e9
	-- kayak Gnome, Pet Shard GiantBean) itu harga Sheckle valid, dibeli via BuyEventShopStock;
	-- FallbackPrice/PurchaseID cuma opsi Robux. Cuma skip DisplayInShop==false.
	local function shopBuyable(v)
		return type(v) == "table" and v.DisplayInShop ~= false
	end
	local function shopStock(shop, item)
		local ok, d = pcall(function() return DataService:GetData() end)
		local s = ok and d and d.EventShopStock and d.EventShopStock[shop]
		local st = s and s.Stocks and s.Stocks[item]
		return st and tonumber(st.Stock) or 0
	end

	-- opsi dropdown item shop (gabungan 2 shop, "All" di atas)
	function ctx.getBeanstalkShopOptions()
		local ESD = eventShopData()
		local out = { { value = "All", display = "All (semua item)" } }
		local seen = {}
		for _, shop in ipairs(SHOP_LIST) do
			local cat = ESD[shop]
			if cat then
				local names = {}
				for name, v in pairs(cat) do if shopBuyable(v) and not seen[name] then seen[name] = true; names[#names + 1] = name end end
				table.sort(names)
				for _, n in ipairs(names) do out[#out + 1] = { value = n, display = n } end
			end
		end
		return out
	end

	local function buyShopLoop()
		ctx.state.beanShopId = (ctx.state.beanShopId or 0) + 1
		local myId = ctx.state.beanShopId
		ctx.elevate()
		while CFG.buyBeanstalkShopEnabled and ctx.alive() and ctx.state.beanShopId == myId do
			local sel = CFG.buyBeanstalkShopNames or {}
			if next(sel) and BuyEventShopStock then
				local ESD = eventShopData()
				local bought = 0
				for _, shop in ipairs(SHOP_LIST) do
					local cat = ESD[shop]
					if cat then
						for name, v in pairs(cat) do
							if shopBuyable(v) and (sel["All"] or sel[name]) then
								local n = shopStock(shop, name)
								for _ = 1, n do
									if not CFG.buyBeanstalkShopEnabled or ctx.state.beanShopId ~= myId then break end
									pcall(function() BuyEventShopStock:FireServer(name, shop) end)
									bought = bought + 1
									task.wait(0.15)
								end
							end
						end
					end
				end
				if bought > 0 then setStatus(("Beanstalk Shop: beli %d item"):format(bought)) end
			end
			task.wait(2)
		end
	end
	function ctx.startBuyBeanstalkShop() task.spawn(buyShopLoop) end
	function ctx.stopBuyBeanstalkShop() ctx.state.beanShopId = (ctx.state.beanShopId or 0) + 1 end
end
