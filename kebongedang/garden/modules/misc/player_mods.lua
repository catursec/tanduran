--[[ player_mods.lua — utilitas Player: Noclip, Walk Speed, Infinity Jump.
     Semua toggle-able & guarded (auto re-apply tiap frame selama aktif).
     Toggle: CFG.noclipEnabled / CFG.walkSpeedEnabled (+CFG.walkSpeed) / CFG.infJumpEnabled. ]]
return function(ctx)
	local RunService = game:GetService("RunService")
	local UIS = game:GetService("UserInputService")
	local LP  = ctx.LP
	local CFG = ctx.CFG
	local DEFAULT_WS = 16

	local function char() return LP.Character end
	local function hum()
		local c = char()
		return c and c:FindFirstChildOfClass("Humanoid")
	end

	------------------------------------------------------------------- NOCLIP
	local noclipConn
	local function startNoclip()
		if noclipConn then return end
		noclipConn = RunService.Stepped:Connect(function()
			local c = char()
			if not c then return end
			for _, p in ipairs(c:GetDescendants()) do
				if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
			end
		end)
	end
	local function stopNoclip()
		if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
	end
	function ctx.setNoclip(v)
		CFG.noclipEnabled = v
		if v then startNoclip() else stopNoclip() end
	end

	------------------------------------------------------------------- WALK SPEED
	local wsConn
	local function startWS()
		if wsConn then return end
		wsConn = RunService.Stepped:Connect(function()
			local h = hum()
			if h then
				local target = tonumber(CFG.walkSpeed) or DEFAULT_WS
				if h.WalkSpeed ~= target then h.WalkSpeed = target end
			end
		end)
	end
	local function stopWS()
		if wsConn then wsConn:Disconnect(); wsConn = nil end
		local h = hum()
		if h then h.WalkSpeed = DEFAULT_WS end
	end
	function ctx.setWalkSpeed(v)
		CFG.walkSpeedEnabled = v
		if v then startWS() else stopWS() end
	end
	-- dipanggil pas nilai input berubah (biar langsung kepakai kalau lagi ON)
	function ctx.applyWalkSpeed()
		if not CFG.walkSpeedEnabled then return end
		local h = hum()
		if h then h.WalkSpeed = tonumber(CFG.walkSpeed) or DEFAULT_WS end
	end

	------------------------------------------------------------------- INFINITY JUMP
	local jumpConn
	local function startInfJump()
		if jumpConn then return end
		jumpConn = UIS.JumpRequest:Connect(function()
			local h = hum()
			if h then pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end) end
		end)
	end
	local function stopInfJump()
		if jumpConn then jumpConn:Disconnect(); jumpConn = nil end
	end
	function ctx.setInfJump(v)
		CFG.infJumpEnabled = v
		if v then startInfJump() else stopInfJump() end
	end
end
