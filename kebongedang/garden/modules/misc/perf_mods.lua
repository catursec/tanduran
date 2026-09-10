--[[ perf_mods.lua — Performance / Graphics Optimization.
     - Hide My/Other Garden Plants : sembunyiin plant (LocalTransparencyModifier) buat FPS.
     - Auto Remove Spider Web FX    : hapus particle/trail/beam efek web terus-menerus.
     - Performance Mode (off/low/extreme) : matiin shadow & (extreme) semua efek partikel.
     - Disable 3D Rendering          : RunService:Set3dRenderingEnabled(false).
     Toggle: CFG.hideMyPlants / hideOtherPlants / autoRemoveWebFx / perfMode / disable3d. ]]
return function(ctx)
	local RS  = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local Lighting = game:GetService("Lighting")
	local LP  = ctx.LP
	local CFG = ctx.CFG

	local function myFarm()
		local f; pcall(function() f = require(RS.Modules.GetFarm)(LP) end)
		return f
	end
	-- iterasi Plants_Physical: which = "mine" / "other"
	local function eachPlantContainer(which, fn)
		local Farm = workspace:FindFirstChild("Farm"); if not Farm then return end
		local mine = myFarm()
		for _, g in ipairs(Farm:GetChildren()) do
			local isMine = (g == mine)
			if (which == "mine" and isMine) or (which == "other" and not isMine) then
				local imp = g:FindFirstChild("Important")
				local pp = imp and imp:FindFirstChild("Plants_Physical")
				if pp then fn(pp) end
			end
		end
	end

	------------------------------------------------------------------- hide plants
	local function applyHide(which, hidden)
		eachPlantContainer(which, function(pp)
			for _, d in ipairs(pp:GetDescendants()) do
				if d:IsA("BasePart") then d.LocalTransparencyModifier = hidden and 1 or 0 end
			end
		end)
	end

	local hideConn
	local function hideLoopActive() return CFG.hideMyPlants or CFG.hideOtherPlants end
	local function ensureHideLoop()
		if hideConn then return end
		hideConn = task.spawn(function()
			while ctx.alive() and hideLoopActive() do
				if CFG.hideMyPlants then applyHide("mine", true) end
				if CFG.hideOtherPlants then applyHide("other", true) end
				task.wait(1) -- catch plant baru; ga perlu tiap frame
			end
			hideConn = nil
		end)
	end
	function ctx.setHidePlants(which, v)
		if which == "mine" then CFG.hideMyPlants = v else CFG.hideOtherPlants = v end
		if v then ensureHideLoop() else applyHide(which, false) end
	end

	------------------------------------------------------------------- spider web FX
	local WEB_MATCH = { "web", "spider", "cobweb" }
	local WEB_CLASS = { ParticleEmitter = true, Trail = true, Beam = true, Decal = true, Texture = true }
	local function isWeb(d)
		if not WEB_CLASS[d.ClassName] then return false end
		local n = d.Name:lower()
		for _, m in ipairs(WEB_MATCH) do if n:find(m) then return true end end
		return false
	end
	local webConn
	function ctx.setAutoRemoveWeb(v)
		CFG.autoRemoveWebFx = v
		if v then
			if webConn then return end
			webConn = task.spawn(function()
				while ctx.alive() and CFG.autoRemoveWebFx do
					for _, d in ipairs(workspace:GetDescendants()) do
						if isWeb(d) then pcall(function() d:Destroy() end) end
					end
					task.wait(1)
				end
				webConn = nil
			end)
		end
	end

	------------------------------------------------------------------- performance mode
	local FX_CLASS = { ParticleEmitter = true, Trail = true, Beam = true, Fire = true, Smoke = true, Sparkles = true, Explosion = true }
	local function setAllFxEnabled(on)
		for _, d in ipairs(workspace:GetDescendants()) do
			if FX_CLASS[d.ClassName] then pcall(function() d.Enabled = on end) end
		end
	end
	local pmConn
	local function stopPmLoop() if pmConn then task.cancel(pmConn); pmConn = nil end end
	function ctx.setPerfMode(mode)
		CFG.perfMode = mode
		stopPmLoop()
		if mode == "off" then
			pcall(function() Lighting.GlobalShadows = true end)
			setAllFxEnabled(true)
		elseif mode == "low" then
			pcall(function() Lighting.GlobalShadows = false end)
		elseif mode == "extreme" then
			pcall(function() Lighting.GlobalShadows = false end)
			-- terus-terusan matiin efek partikel (extreme FPS)
			pmConn = task.spawn(function()
				while ctx.alive() and CFG.perfMode == "extreme" do
					setAllFxEnabled(false)
					task.wait(1.5)
				end
			end)
		end
	end
	function ctx.getPerfModeOptions()
		return { { name = "off", display = "Off" }, { name = "low", display = "Low" }, { name = "extreme", display = "Extreme" } }
	end

	------------------------------------------------------------------- disable 3D
	function ctx.setDisable3d(v)
		CFG.disable3d = v
		ctx.elevate()
		pcall(function() RunService:Set3dRenderingEnabled(not v) end)
	end
end
