--[[ esp.lua — label melayang (BillboardGui) di dunia 3D di atas tiap egg.
     Egg: nama egg + ISI-nya (pet yang bakal menetas + berat) dari
          SaveSlots.AllSlots.<slot>.SavedObjects.<uuid>.Data (Type/BaseWeight),
          fallback sisa waktu hatch / READY.
     Toggle: CFG.espEnabled. ]]
return function(ctx)
	local RS = game:GetService("ReplicatedStorage")
	local LP = ctx.LP
	local DataService = ctx.deps.DataService

	-- Game nampilin berat = BaseWeight * 1.1 (bukan raw BaseWeight).
	local WEIGHT_MULT = 1.1

	local bbFolder
	local billboards = {} -- key -> { gui, lbl }
	local eggSlotKey  -- cache slot aktif yg nyimpen SavedObjects

	local function ensureFolder()
		if bbFolder and bbFolder.Parent then return bbFolder end
		bbFolder = Instance.new("Folder")
		bbFolder.Name = "AllegiaanESP"
		bbFolder.Parent = (gethui and gethui()) or game:GetService("CoreGui")
		return bbFolder
	end

	local function partOf(model)
		if model:IsA("BasePart") then return model end
		if model.PrimaryPart then return model.PrimaryPart end
		for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then return d end end
		return nil
	end

	local function makeBB(key, adornee, offset)
		local bb = Instance.new("BillboardGui")
		bb.Name = "esp_" .. key
		bb.Adornee = adornee
		bb.Size = UDim2.fromOffset(240, 58)
		bb.StudsOffset = Vector3.new(0, offset or 2.5, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 600
		bb.LightInfluence = 0
		bb.ClipsDescendants = false
		bb.Parent = ensureFolder()

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.Font = Enum.Font.MontserratBold
		lbl.TextSize = 14
		lbl.RichText = true
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextStrokeTransparency = 0.2
		lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		lbl.TextYAlignment = Enum.TextYAlignment.Bottom
		lbl.Parent = bb

		local rec = { gui = bb, lbl = lbl }
		billboards[key] = rec
		return rec
	end

	local function acquire(key, adornee, offset)
		local rec = billboards[key]
		if (not rec) or rec.gui.Adornee ~= adornee or not rec.gui.Parent then
			if rec then rec.gui:Destroy(); billboards[key] = nil end
			rec = makeBB(key, adornee, offset)
		end
		return rec
	end

	local function fmtTime(sec)
		sec = math.max(0, math.floor(sec))
		local m = math.floor(sec / 60)
		local s = sec % 60
		if m >= 60 then local h = math.floor(m / 60); m = m % 60; return string.format("%dh %dm", h, m) end
		return string.format("%dm %02ds", m, s)
	end

	-- Data isi egg (pet yg bakal menetas + berat) dari SavedObjects by uuid.
	local function eggDataOf(uuid)
		if not uuid then return nil end
		local ok, d = pcall(function() return DataService:GetData() end)
		local slots = ok and d and d.SaveSlots and d.SaveSlots.AllSlots
		if not slots then return nil end
		-- coba slot yg di-cache dulu
		local s = eggSlotKey and slots[eggSlotKey]
		if s and s.SavedObjects and s.SavedObjects[uuid] then return s.SavedObjects[uuid].Data end
		-- scan semua slot
		for sn, slot in pairs(slots) do
			if type(slot) == "table" and slot.SavedObjects and slot.SavedObjects[uuid] then
				eggSlotKey = sn
				return slot.SavedObjects[uuid].Data
			end
		end
		return nil
	end

	local function eggNameFallback(e)
		local n = e:GetAttribute("EggName")
		if not n or n == "" then
			for _, c in ipairs(e:GetChildren()) do if c:IsA("Model") then n = c.Name; break end end
		end
		return n or "Egg"
	end

	local function update()
		local seen = {}

		-- ===== EGG (nama + isi: pet + berat) =====
		local farm; pcall(function() farm = require(RS.Modules.GetFarm)(LP) end)
		if farm then
			for _, e in ipairs(farm:GetDescendants()) do
				if e:IsA("Model") and e.Name == "PetEgg" and e:GetAttribute("OWNER") == LP.Name then
					local adornee = e:FindFirstChild("PetEgg") or partOf(e)
					if adornee then
						local uuid = e:GetAttribute("OBJECT_UUID")
						local key = "egg_" .. tostring(uuid or e:GetDebugId())
						seen[key] = true
						local rec = acquire(key, adornee, 3)
						local data = eggDataOf(uuid)
						local lines = { ("<font color='#00E676'>%s</font>"):format(eggNameFallback(e)) }
						if data and data.Type then
							lines[#lines + 1] = ("<font color='#FFEB3B'>%s</font>"):format(tostring(data.Type))
							local w = tonumber(data.BaseWeight)
							if w then lines[#lines + 1] = ("<font color='#7CF0FF'>%.2f KG</font>"):format(w * WEIGHT_MULT) end
						end
						local t = tonumber(e:GetAttribute("TimeToHatch")) or (data and tonumber(data.TimeToHatch)) or 0
						if t > 0 then
							lines[#lines + 1] = ("<font color='#FFB450'>\u{23F1} %s</font>"):format(fmtTime(t))
						elseif not (data and data.Type) then
							lines[#lines + 1] = "<font color='#00E676'>READY</font>"
						end
						rec.lbl.Text = table.concat(lines, "\n")
					end
				end
			end
		end

		for key, rec in pairs(billboards) do
			if not seen[key] then rec.gui:Destroy(); billboards[key] = nil end
		end
	end

	local function clearAll()
		for _, rec in pairs(billboards) do pcall(function() rec.gui:Destroy() end) end
		billboards = {}
		if bbFolder then pcall(function() bbFolder:Destroy() end); bbFolder = nil end
	end

	local loopId = 0
	function ctx.startEsp()
		loopId = loopId + 1
		local my = loopId
		task.spawn(function()
			while ctx.alive() and ctx.CFG.espEnabled and loopId == my do
				pcall(update)
				task.wait(0.5)
			end
			clearAll()
		end)
	end

	function ctx.stopEsp()
		loopId = loopId + 1
		clearAll()
	end
end
