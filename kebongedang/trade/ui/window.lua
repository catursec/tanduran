--[[ window.lua — jendela utama trade PINK ROYALE:
     Sidebar modern, player profile card, glowing title bar, responsive auto-scaling,
     floating maximize jewel, status footer modern. ]]
return function(ctx)
	local Players          = ctx.Services.Players
	local UserInputService = ctx.Services.UserInputService
	local TS               = game:GetService("TweenService")
	local LP  = ctx.LP
	local CFG = ctx.CFG
	local C   = ctx.C
	local F   = ctx.F
	local mk, corner, stroke, pad, grad = ctx.mk, ctx.corner, ctx.stroke, ctx.pad, ctx.grad

	ctx.ui.pages   = {}
	ctx.ui.tabBtns = {}

	----------------------------------------------------------------- bersihkan GUI lama
	pcall(function()
		local host = (gethui and gethui()) or game:GetService("CoreGui")
		local old = host:FindFirstChild("GAGSeller"); if old then old:Destroy() end
		local pg = LP:FindFirstChild("PlayerGui")
		if pg and pg:FindFirstChild("GAGSeller") then pg.GAGSeller:Destroy() end
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "GAGSeller"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = LP:WaitForChild("PlayerGui")
	ctx.state.gui = gui
	ctx.state.isAlive = true
	gui.Destroying:Connect(function()
		ctx.state.isAlive = false
	end)

	----------------------------------------------------------------- Floating Maximize Jewel
	local maxIcon = mk("TextButton", {
		Size = UDim2.fromOffset(50, 50),
		Position = UDim2.new(0, 16, 0.5, -25),
		BackgroundColor3 = C.panel,
		Text = "✦",
		Font = F.bold,
		TextSize = 22,
		TextColor3 = C.acc,
		Visible = false,
		Active = true,
		ZIndex = 100,
	}, gui)
	corner(maxIcon, 25)
	stroke(maxIcon, C.acc, 2, 0.1)

	local maxGlow = mk("Frame", {
		Size = UDim2.new(1, 14, 1, 14),
		Position = UDim2.new(0, -7, 0, -7),
		BackgroundColor3 = C.acc,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ZIndex = 99,
	}, maxIcon)
	corner(maxGlow, 30)

	pcall(function()
		local logo = ctx.getLogo and ctx.getLogo()
		if logo then
			maxIcon.Text = ""
			local img = mk("ImageLabel", {
				Size = UDim2.new(1, -12, 1, -12),
				Position = UDim2.fromOffset(6, 6),
				BackgroundTransparency = 1,
				Image = logo,
				ScaleType = Enum.ScaleType.Fit,
			}, maxIcon)
			corner(img, 19)
		end
	end)

	do
		local dragging, ds, sp
		maxIcon.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = true; ds = i.Position; sp = maxIcon.Position
			end
		end)
		UserInputService.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local d = i.Position - ds
				maxIcon.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
			end
		end)
		UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

	----------------------------------------------------------------- Main Window (Glassmorphic Glow)
	local main = mk("Frame", {
		Size = UDim2.fromOffset(610, 375),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Active = true,
	}, gui)
	corner(main, 16)
	stroke(main, C.stroke, 1.6, 0.25)

	local haloGlow = mk("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = C.acc,
		BackgroundTransparency = 0.94,
		BorderSizePixel = 0,
	}, main)
	corner(haloGlow, 16)

	-- Responsive Auto Scale
	local uiScale = Instance.new("UIScale"); uiScale.Parent = main
	local function fitScale()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local w, h = main.Size.X.Offset, main.Size.Y.Offset
		local s = math.min(1, (vp.X - 30) / w, (vp.Y - 30) / h)
		uiScale.Scale = math.max(0.4, s)
	end
	fitScale()
	pcall(function()
		local cam = workspace.CurrentCamera
		if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale) end
	end)

	----------------------------------------------------------------- Title Bar
	local titleBar = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, main)
	corner(titleBar, 16)

	local titleGrad = mk("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = C.acc,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, titleBar)
	corner(titleGrad, 16)
	grad(titleGrad, 0, C.acc, C.acc2)

	local titleLine = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = C.acc,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, titleBar)
	grad(titleLine, 0, C.acc, C.acc2)

	local titleIcon = mk("TextLabel", {
		Size = UDim2.fromOffset(30, 48),
		Position = UDim2.fromOffset(16, 0),
		BackgroundTransparency = 1,
		Text = "✦",
		Font = F.title,
		TextSize = 20,
		TextColor3 = C.acc,
		ZIndex = 8,
	}, titleBar)

	pcall(function()
		local logo = ctx.getLogo and ctx.getLogo()
		if logo then
			titleIcon.Text = ""
			local tImg = mk("ImageLabel", {
				Size = UDim2.fromOffset(26, 26),
				Position = UDim2.fromOffset(2, 11),
				BackgroundTransparency = 1,
				Image = logo,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 9,
			}, titleIcon)
			corner(tImg, 13)
		end
	end)

	local titleLabel = mk("TextLabel", {
		Size = UDim2.new(0, 120, 1, 0),
		Position = UDim2.fromOffset(46, 0),
		BackgroundTransparency = 1,
		Text = "CeszParadise",
		Font = F.title,
		TextSize = 15,
		TextColor3 = C.txt,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 8,
	}, titleBar)

	local subPill = mk("Frame", {
		Size = UDim2.fromOffset(105, 24),
		Position = UDim2.fromOffset(168, 12),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		ZIndex = 8,
	}, titleBar)
	corner(subPill, 12)
	stroke(subPill, C.acc, 1, 0.5)
	pad(subPill, 6, 6, 0, 0)

	local subLabel = mk("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "❖ GAG Trade",
		Font = F.bold,
		TextSize = 10.5,
		TextColor3 = C.accSoft,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 9,
	}, subPill)

	do
		local dragging, ds, sp
		titleBar.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = true; ds = i.Position; sp = main.Position
			end
		end)
		UserInputService.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local d = i.Position - ds
				main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
			end
		end)
		UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

	local function makeTitleBtn(label, posX, isClose)
		local btn = mk("TextButton", {
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.new(1, posX, 0, 9),
			BackgroundColor3 = C.row,
			Text = label,
			Font = F.bold,
			TextSize = 13,
			TextColor3 = C.txt,
			ZIndex = 10,
			AutoButtonColor = false,
		}, titleBar)
		corner(btn, 8)
		stroke(btn, isClose and C.red or C.strokeSub, 1, 0.4)

		btn.MouseEnter:Connect(function()
			TS:Create(btn, TweenInfo.new(0.15), {
				BackgroundColor3 = isClose and C.red or C.acc,
				TextColor3 = Color3.new(1, 1, 1),
			}):Play()
		end)
		btn.MouseLeave:Connect(function()
			TS:Create(btn, TweenInfo.new(0.15), {
				BackgroundColor3 = C.row,
				TextColor3 = C.txt,
			}):Play()
		end)
		return btn
	end

	local minBtn   = makeTitleBtn("−", -74, false)
	local closeBtn = makeTitleBtn("✕", -38, true)

	-- Live FPS Counter Pill
	local fpsPill = mk("Frame", {
		Size = UDim2.fromOffset(84, 26),
		Position = UDim2.new(1, -166, 0, 11),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, titleBar)
	corner(fpsPill, 13)
	stroke(fpsPill, C.strokeSub, 1, 0.5)

	local fpsDot = mk("Frame", {
		Size = UDim2.fromOffset(8, 8),
		Position = UDim2.new(0, 8, 0.5, -4),
		BackgroundColor3 = C.green,
		BorderSizePixel = 0,
		ZIndex = 11,
	}, fpsPill)
	corner(fpsDot, 4)

	local fpsLabel = mk("TextLabel", {
		Size = UDim2.new(1, -22, 1, 0),
		Position = UDim2.fromOffset(20, 0),
		BackgroundTransparency = 1,
		Text = "60 FPS",
		Font = F.bold,
		TextSize = 11,
		TextColor3 = C.txt,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 11,
	}, fpsPill)

	do
		local RunService = game:GetService("RunService")
		local frameCount = 0
		local lastTime = tick()
		local fpsConn
		fpsConn = RunService.RenderStepped:Connect(function()
			if not ctx.state.isAlive then
				if fpsConn then fpsConn:Disconnect(); fpsConn = nil end
				return
			end
			frameCount = frameCount + 1
			local now = tick()
			local diff = now - lastTime
			if diff >= 0.5 then
				local curFps = math.clamp(math.round(frameCount / diff), 1, 999)
				frameCount = 0
				lastTime = now
				fpsLabel.Text = curFps .. " FPS"
				if curFps >= 50 then
					fpsDot.BackgroundColor3 = C.green
					fpsLabel.TextColor3 = C.txt
				elseif curFps >= 30 then
					fpsDot.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
					fpsLabel.TextColor3 = Color3.fromRGB(255, 220, 140)
				else
					fpsDot.BackgroundColor3 = C.red
					fpsLabel.TextColor3 = C.red
				end
			end
		end)
	end

	minBtn.MouseButton1Click:Connect(function() main.Visible = false; maxIcon.Visible = true end)
	maxIcon.MouseButton1Click:Connect(function() maxIcon.Visible = false; main.Visible = true end)
	closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

	----------------------------------------------------------------- Left Sidebar
	local sidebar = mk("Frame", {
		Size = UDim2.new(0, 154, 1, -54),
		Position = UDim2.fromOffset(8, 48),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, main)
	corner(sidebar, 12)
	stroke(sidebar, C.strokeSub, 1, 0.5)
	pad(sidebar, 6, 6, 6, 6)

	local menuTag = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = "M E N U",
		Font = F.bold,
		TextSize = 11,
		TextColor3 = C.acc,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
	}, sidebar)

	local tabButtonsFrame = mk("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -68),
		Position = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.acc,
		ScrollBarImageTransparency = 0.4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingEnabled = true,
	}, sidebar)
	mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabButtonsFrame)

	local profileCard = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		Position = UDim2.new(0, 0, 1, -46),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
	}, sidebar)
	corner(profileCard, 10)
	stroke(profileCard, C.stroke, 1.2, 0.4)
	pad(profileCard, 6, 6, 4, 4)

	local avatar = mk("ImageLabel", {
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
	}, profileCard)
	corner(avatar, 17)
	stroke(avatar, C.acc, 1.5, 0.2)
	pcall(function()
		avatar.Image = Players:GetUserThumbnailAsync(LP.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
	end)

	local nameLabel = mk("TextLabel", {
		Size = UDim2.new(1, -42, 0, 18),
		Position = UDim2.fromOffset(42, 2),
		BackgroundTransparency = 1,
		Text = LP.DisplayName,
		Font = F.bold,
		TextSize = 12,
		TextColor3 = C.txt,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, profileCard)

	local statusPill = mk("TextLabel", {
		Size = UDim2.new(1, -42, 0, 16),
		Position = UDim2.fromOffset(42, 18),
		BackgroundTransparency = 1,
		Text = "Trade Plaza ✦",
		Font = F.bold,
		TextSize = 10,
		TextColor3 = C.accSoft,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, profileCard)

	----------------------------------------------------------------- Right Content Frame
	local content = mk("Frame", {
		Size = UDim2.new(1, -174, 1, -56),
		Position = UDim2.fromOffset(166, 49),
		BackgroundTransparency = 1,
	}, main)

	----------------------------------------------------------------- Resize Grip
	local grip = mk("TextButton", {
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(1, -24, 1, -24),
		BackgroundTransparency = 1,
		Text = "◢",
		Font = F.bold,
		TextSize = 14,
		TextColor3 = C.strokeSub,
		AutoButtonColor = false,
		Active = true,
		ZIndex = 20,
	}, main)
	grip.MouseEnter:Connect(function() grip.TextColor3 = C.acc end)
	grip.MouseLeave:Connect(function() grip.TextColor3 = C.strokeSub end)
	do
		local rz, ds, ss
		grip.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				rz = true; ds = i.Position; ss = Vector2.new(main.Size.X.Offset, main.Size.Y.Offset)
			end
		end)
		UserInputService.InputChanged:Connect(function(i)
			if rz and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local scale = uiScale.Scale > 0 and uiScale.Scale or 1
				local d = i.Position - ds
				local w = math.clamp(ss.X + d.X / scale, 480, 1600)
				local h = math.clamp(ss.Y + d.Y / scale, 320, 1100)
				main.Size = UDim2.fromOffset(w, h)
				fitScale()
			end
		end)
		UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				rz = false
			end
		end)
	end

	----------------------------------------------------------------- Status Footer
	local statusFooter = mk("Frame", {
		Size = UDim2.new(1, -196, 0, 20),
		Position = UDim2.new(0, 184, 1, -24),
		BackgroundTransparency = 1,
	}, main)
	local statusText = mk("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "○ Status: idle  |  Loop: OFF",
		Font = F.bold,
		TextSize = 11,
		TextColor3 = C.sub,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, statusFooter)

	function ctx.setStatus(s)
		local isActive = tostring(s):lower():find("active") ~= nil or tostring(s):lower():find("on") ~= nil
		statusText.Text = ("%s Status: %s  |  Loop: %s"):format(
			isActive and "●" or "○",
			tostring(s),
			CFG.autoSell and "ON ✦" or "OFF"
		)
		statusText.TextColor3 = isActive and C.green or C.sub
	end

	----------------------------------------------------------------- Logger
	local logLines = ctx.state.logLines
	function ctx.log(msg)
		table.insert(logLines, os.date("%H:%M:%S ") .. msg)
		while #logLines > 10 do table.remove(logLines, 1) end
		if ctx.ui.logBox then ctx.ui.logBox.Text = table.concat(logLines, "\n") end
	end

	ctx.ui.main            = main
	ctx.ui.maxIcon         = maxIcon
	ctx.ui.content         = content
	ctx.ui.tabButtonsFrame = tabButtonsFrame
	ctx.ui.sidebar         = sidebar
	ctx.ui.statusText      = statusText
end
