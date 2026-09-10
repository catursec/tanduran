--[[ esp_inventory.lua — ESP Base Weight di INVENTORY (Pet Items).
     Nempel label kecil "Base X.XX KG" di tiap slot pet di backpack GUI,
     jadi pas buka inventory langsung keliatan BaseWeight tiap pet.
     Mapping: slot.ToolName.Text == Tool.Name -> Tool.PET_UUID ->
              PetData.BaseWeight (dari DataService).
     Toggle: CFG.espInvEnabled. ]]
return function(ctx)
	local RS = game:GetService("ReplicatedStorage")
	local LP = ctx.LP
	local DataService = ctx.deps.DataService

	local GRID_PATH   = { "BackpackGui", "Backpack", "Inventory", "ScrollingFrame", "UIGridFrame" }
	local HOTBAR_PATH = { "BackpackGui", "Backpack", "Hotbar" }
	local LBL_NAME    = "AH_BaseW" -- label yg kita tempel di slot

	local function byPath(path)
		local n = LP:FindFirstChild("PlayerGui")
		for _, seg in ipairs(path) do
			if not n then return nil end
			n = n:FindFirstChild(seg)
		end
		return n
	end
	-- container slot pet: grid inventory + hotbar (bar bawah, termasuk pet yg dipegang).
	local function containers()
		local out = {}
		local g = byPath(GRID_PATH);   if g then out[#out + 1] = g end
		local h = byPath(HOTBAR_PATH); if h then out[#out + 1] = h end
		return out
	end

	-- map Tool.Name -> {base, level} (cuma pet). Dibangun tiap refresh (murah).
	local function buildWeightMap()
		local ok, d = pcall(function() return DataService:GetData() end)
		local inv = ok and d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}
		local byUuid = {}
		for uuid, v in pairs(inv) do
			local pd = v.PetData or {}
			if pd.BaseWeight then byUuid[uuid] = { base = pd.BaseWeight, level = pd.Level or 0 } end
		end
		local byName = {}
		local function scan(where)
			if not where then return end
			for _, t in ipairs(where:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("ItemType") == "Pet" then
					local uuid = t:GetAttribute("PET_UUID")
					local e = uuid and byUuid[uuid]
					if e and byName[t.Name] == nil then byName[t.Name] = e end
				end
			end
		end
		scan(LP.Character)
		scan(LP:FindFirstChildOfClass("Backpack"))
		return byName
	end

	-- Game: Weight = BaseWeight * (1 + 0.1*Level). MAX_LEVEL = umur 500.
	-- Berat "dasar" (level dasar) yg biasa dilihat = BaseWeight * 1.1, di-floor
	-- 1 desimal — persis game (5.5 base -> 6.0, 5.6 -> 6.1). Max = base*(1+0.1*500).
	local WEIGHT_MULT = 1.1
	local MAX_LEVEL   = 500
	local function floor1(n) return math.floor(n * 10) / 10 end
	local function baseKG(bw) return floor1(bw * WEIGHT_MULT) end
	local function maxKG(bw)  return floor1(bw * (1 + 0.1 * MAX_LEVEL)) end

	-- teks label sesuai mode CFG.espInvMode ("base" / "age" / "max").
	local function labelText(e)
		local base = baseKG(e.base)
		local mode = ctx.CFG.espInvMode
		if mode == "max" then
			return ("%.1f \u{2192} %.1f KG"):format(base, maxKG(e.base))
		elseif mode == "base" then
			return ("%.1f KG"):format(base)
		end
		return ("%.1f KG A%d"):format(base, e.level or 0)
	end

	-- tempel/refresh label di slot; hapus dari slot non-pet.
	local function setLabel(slot, e)
		local lbl = slot:FindFirstChild(LBL_NAME)
		if not e then
			if lbl then lbl:Destroy() end
			return
		end
		if not lbl then
			lbl = Instance.new("TextLabel")
			lbl.Name = LBL_NAME
			lbl.AnchorPoint = Vector2.new(0.5, 1)
			lbl.Position = UDim2.new(0.5, 0, 1, 0)
			lbl.Size = UDim2.new(1, 0, 0, 15)
			lbl.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
			lbl.BackgroundTransparency = 0.15
			lbl.Font = Enum.Font.MontserratBold
			lbl.TextSize = 11
			lbl.TextScaled = true -- auto-fit biar muat di slot sempit
			lbl.TextColor3 = Color3.fromRGB(255, 214, 92) -- gold, senada tema
			lbl.TextStrokeTransparency = 0.5
			lbl.ZIndex = 20
			lbl.RichText = false
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 4)
			corner.Parent = lbl
			local con = Instance.new("UITextSizeConstraint")
			con.MaxTextSize = 12
			con.Parent = lbl
			lbl.Parent = slot
		end
		lbl.Text = labelText(e)
	end

	local function clearAll()
		for _, c in ipairs(containers()) do
			for _, slot in ipairs(c:GetChildren()) do
				if slot:IsA("GuiButton") then
					local lbl = slot:FindFirstChild(LBL_NAME)
					if lbl then lbl:Destroy() end
				end
			end
		end
	end

	local function update()
		local cs = containers()
		if #cs == 0 then return end
		local byName = buildWeightMap()
		for _, c in ipairs(cs) do
			for _, slot in ipairs(c:GetChildren()) do
				if slot:IsA("GuiButton") then
					local tn = slot:FindFirstChild("ToolName")
					local name = tn and tn:IsA("TextLabel") and tn.Text or nil
					setLabel(slot, name and byName[name] or nil)
				end
			end
		end
	end

	local loopId = 0
	function ctx.startEspInv()
		loopId = loopId + 1
		local my = loopId
		task.spawn(function()
			while ctx.alive() and ctx.CFG.espInvEnabled and loopId == my do
				pcall(update)
				task.wait(0.5)
			end
			pcall(clearAll)
		end)
	end

	function ctx.stopEspInv()
		loopId = loopId + 1
		pcall(clearAll)
	end
end
