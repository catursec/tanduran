--[[ booth.lua — logika booth: kepemilikan, claim terdekat, pindah dekat portal, token.
     Mengisi: ctx.getTokens, ctx.myPlayerId, ctx.weightOf,
              ctx.ownsBooth, ctx.tryClaimNearest, ctx.ensureBooth,
              ctx.autoSwitchBoothPortal ]]
return function(ctx)
	local LP                = ctx.LP
	local CollectionService = ctx.Services.CollectionService
	local RR                = ctx.deps.RR
	local DataService       = ctx.deps.DataService
	local TradeBoothsData   = ctx.deps.TradeBoothsData
	local ClaimBooth        = ctx.deps.ClaimBooth
	local RemoveBooth       = ctx.deps.RemoveBooth
	local CFG               = ctx.CFG
	local function log(msg) ctx.log(msg) end

	local function getTokens()
		local ok, data = pcall(function() return DataService:GetData() end)
		if ok and type(data) == "table" and type(data.TradeData) == "table" then
			return data.TradeData.Tokens or 0
		end
		return 0
	end

	local function myPlayerId() return TradeBoothsData.getPlayerId(LP) end

	local function weightOf(petType, pd)
		return pd.BaseWeight or 0
	end

	local function ownsBooth()
		local ok, data = pcall(function() return RR.new("Booths"):GetDataAsync() end)
		if not ok or not data then return false, nil, nil end
		local id = myPlayerId()
		local playerRecord = data.Players and data.Players[id]
		local boothName = playerRecord and playerRecord.Booth
		return boothName ~= nil, data, boothName
	end

	local function tryClaimNearest()
		local owns, data = ownsBooth()
		if owns then return true end
		if not data then return false end
		local charPos
		local char = LP.Character
		if char and char:FindFirstChild("HumanoidRootPart") then charPos = char.HumanoidRootPart.Position end
		local list = {}
		for _, inst in ipairs(CollectionService:GetTagged("TradeBooth")) do
			local b = data.Booths and data.Booths[inst.Name]
			if (b == nil) or (b.Owner == nil) then
				local dist = 999999
				if charPos then
					local ok2, piv = pcall(function() return inst:GetPivot().Position end)
					if ok2 then dist = (piv - charPos).Magnitude end
				end
				list[#list + 1] = { inst = inst, dist = dist }
			end
		end
		if #list == 0 then log("Tidak ada booth kosong."); return false end
		table.sort(list, function(a, b) return a.dist < b.dist end)
		local pick = list[1]

		if char and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = pick.inst:GetPivot() * CFrame.new(0, 3, 3)
			task.wait(0.25)
		end

		pcall(function() ClaimBooth:FireServer(pick.inst) end)
		log(("Claim booth terdekat (%dstud, %d kosong)..."):format(math.floor(pick.dist), #list))
		return false
	end

	local function ensureBooth()
		local owns = ownsBooth()
		if owns then return true end
		if CFG.autoClaim then return tryClaimNearest() end
		return false
	end

	-- Auto Switch to Booth Near Portal
	local function autoSwitchBoothPortal()
		if not CFG.autoSwitchPortal then return end
		local owns, data, boothName = ownsBooth()
		if not owns or not data or not boothName then return end
		-- Cari portal Trade World (bukan lobby)
		local tradeWorld = workspace:FindFirstChild("TradeWorld")
		local portal = nil
		if tradeWorld then
			local pp = tradeWorld:FindFirstChild("PortalPetePlatform")
			if pp then portal = pp:FindFirstChild("Portal") or pp end
			if not portal then portal = tradeWorld:FindFirstChild("Portal Pete", true) end
		end
		if not portal then
			portal = workspace:FindFirstChild("Portal Pete", true) or workspace:FindFirstChild("Portal", true)
		end
		local portalPos = portal and portal:GetPivot().Position or Vector3.new(0, 0, 0)

		local myBoothInst = nil
		for _, inst in ipairs(CollectionService:GetTagged("TradeBooth")) do
			if inst.Name == boothName then myBoothInst = inst; break end
		end
		if not myBoothInst then return end

		local myDist = (myBoothInst:GetPivot().Position - portalPos).Magnitude
		local bestBooth = nil
		local bestDist = myDist

		for _, inst in ipairs(CollectionService:GetTagged("TradeBooth")) do
			local b = data.Booths and data.Booths[inst.Name]
			if (b == nil) or (b.Owner == nil) then
				local pDist = (inst:GetPivot().Position - portalPos).Magnitude
				if pDist < bestDist - 8 then -- harus lebih dekat minimal 8 stud agar worth-it pindah
					bestDist = pDist
					bestBooth = inst
				end
			end
		end

		if bestBooth then
			log(("Pindah ke booth lebih dekat portal (Lama: %dstud, Baru: %dstud)"):format(math.floor(myDist), math.floor(bestDist)))
			pcall(function() RemoveBooth:FireServer() end)
			task.wait(0.5)

			local char = LP.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				char.HumanoidRootPart.CFrame = bestBooth:GetPivot() * CFrame.new(0, 3, 3)
				task.wait(0.25)
			end

			pcall(function() ClaimBooth:FireServer(bestBooth) end)
		end
	end

	ctx.getTokens             = getTokens
	ctx.myPlayerId            = myPlayerId
	ctx.weightOf              = weightOf
	ctx.ownsBooth             = ownsBooth
	ctx.tryClaimNearest       = tryClaimNearest
	ctx.ensureBooth           = ensureBooth
	ctx.autoSwitchBoothPortal = autoSwitchBoothPortal
end
