--[[ window.lua — jendela utama garden PINK ROYALE:
     Sidebar modern, player profile card, glowing title bar, responsive auto-scaling,
     modal konfirmasi close, floating maximize jewel. ]]
return function(ctx)
	local Players          = ctx.Services.Players
	local UserInputService = ctx.Services.UserInputService
	local TS               = game:GetService("TweenService")
	local LP  = ctx.LP
	local C   = ctx.C
	local F   = ctx.F
	local mk, corner, stroke, pad, grad = ctx.mk, ctx.corner, ctx.stroke, ctx.pad, ctx.grad

	ctx.ui.pages   = {}
	ctx.ui.tabBtns = {}

	----------------------------------------------------------------- bersihkan GUI lama
	pcall(function()
		local host = (gethui and gethui()) or game:GetService("CoreGui")
		for _, nm in ipairs({ "GAGGarden", "CeszParadiseGarden", "AllegiaanGarden" }) do
			local old = host:FindFirstChild(nm); if old then old:Destroy() end
			local pg = LP:FindFirstChild("PlayerGui")
			if pg and pg:FindFirstChild(nm) then pg[nm]:Destroy() end
		end
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "CeszParadiseGarden"
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

	-- Glow ring di belakang floating button
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
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromScale(0, 0),
				BackgroundTransparency = 1,
				Image = logo,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 101,
			}, maxIcon)
			corner(img, 25)
		end
	end)

	-- Draggable maximize icon
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

	----------------------------------------------------------------- Main Window (Compact & Ultra-Legible for Mobile/Android)
	local main = mk("Frame", {
		Size = UDim2.fromOffset(610, 375),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		Active = true,
	}, gui)
	corner(main, 14)
	stroke(main, C.stroke, 1.8, 0.25)

	-- Inner ambient glow
	local innerAmbient = mk("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = C.acc,
		BackgroundTransparency = 0.94,
		BorderSizePixel = 0,
	}, main)
	corner(innerAmbient, 14)

	-- Auto-scale responsif (layar HP Android 10/Arceus X/tablet/desktop)
	local uiScale = Instance.new("UIScale"); uiScale.Parent = main
	local function fitScale()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local w, h = main.Size.X.Offset, main.Size.Y.Offset
		-- Margin hanya 16px agar di layar HP muat maksimal tanpa mengecil berlebihan
		local s = math.min(1, (vp.X - 16) / w, (vp.Y - 16) / h)
		uiScale.Scale = math.max(0.62, s)
	end
	fitScale()
	pcall(function()
		local cam = workspace.CurrentCamera
		if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale) end
	end)

	----------------------------------------------------------------- Modern Title Bar
	local titleBar = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, main)
	corner(titleBar, 16)

	-- Subtle gradient overlay on title bar
	local titleGrad = mk("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = C.acc,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, titleBar)
	corner(titleGrad, 16)
	grad(titleGrad, 0)

	-- Bottom border accent line under title bar
	local titleLine = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 2),
		Position = UDim2.new(0, 0, 1, -2),
		BackgroundColor3 = C.acc,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, titleBar)
	grad(titleLine, 0, C.acc, C.acc2)

	-- Emblem & Title Label
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

	-- Subtitle Pill
	local subPill = mk("Frame", {
		Size = UDim2.fromOffset(116, 24),
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
		Text = "❖ Grow a Garden",
		Font = F.bold,
		TextSize = 10.5,
		TextColor3 = C.accSoft,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 9,
	}, subPill)

	-- Draggable Title Bar
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

	-- Title Bar Buttons (Minimize & Close)
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

	local minBtn   = makeTitleBtn("—", -76, false)
	local closeBtn = makeTitleBtn("✕", -38, true)

	minBtn.MouseButton1Click:Connect(function()
		TS:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.2, function()
			main.Visible = false
			maxIcon.Visible = true
		end)
	end)

	maxIcon.MouseButton1Click:Connect(function()
		maxIcon.Visible = false
		main.Visible = true
		main.Size = UDim2.fromOffset(0, 0)
		fitScale()
		TS:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(610, 375),
			BackgroundTransparency = 0.04,
		}):Play()
	end)

	-- Floating FPS Pill
	local fpsPill = mk("Frame", {
		Size = UDim2.fromOffset(72, 24),
		Position = UDim2.new(1, -156, 0, 12),
		BackgroundColor3 = C.row,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, titleBar)
	corner(fpsPill, 12)
	stroke(fpsPill, C.strokeSub, 1, 0.6)

	local fpsDot = mk("Frame", {
		Size = UDim2.fromOffset(6, 6),
		Position = UDim2.fromOffset(8, 9),
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
		local lastUpdate = tick()
		RunService.RenderStepped:Connect(function()
			frameCount += 1
			local now = tick()
			if now - lastUpdate >= 1 then
				local fps = math.round(frameCount / (now - lastUpdate))
				fpsLabel.Text = fps .. " FPS"
				if fps >= 45 then
					fpsDot.BackgroundColor3 = C.green
					fpsLabel.TextColor3 = C.txt
				elseif fps >= 25 then
					fpsDot.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
					fpsLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
				else
					fpsDot.BackgroundColor3 = C.red
					fpsLabel.TextColor3 = C.red
				end
				frameCount = 0
				lastUpdate = now
			end
		end)
	end

	-- Confirm Close Dialog (Modal)
	local function confirmClose()
		local overlay = mk("TextButton", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 50,
		}, gui)

		local box = mk("Frame", {
			Size = UDim2.fromOffset(320, 160),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
			ZIndex = 51,
		}, overlay)
		corner(box, 14)
		stroke(box, C.acc, 1.5, 0.3)

		local boxShine = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 3),
			BackgroundColor3 = C.acc,
			BorderSizePixel = 0,
			ZIndex = 52,
		}, box)
		corner(boxShine, 14)
		grad(boxShine, 0, C.acc, C.acc2)

		mk("TextLabel", {
			Size = UDim2.new(1, -24, 0, 36),
			Position = UDim2.fromOffset(12, 18),
			BackgroundTransparency = 1,
			Text = "✦ Close CeszParadiseHub?",
			Font = F.title,
			TextSize = 17,
			TextColor3 = C.accSoft,
			ZIndex = 52,
		}, box)

		mk("TextLabel", {
			Size = UDim2.new(1, -24, 0, 24),
			Position = UDim2.fromOffset(12, 54),
			BackgroundTransparency = 1,
			Text = "Apakah kamu yakin ingin menutup hub ini?",
			Font = F.reg,
			TextSize = 13,
			TextColor3 = C.sub,
			ZIndex = 52,
		}, box)

		local noBtn = mk("TextButton", {
			Size = UDim2.fromOffset(130, 40),
			Position = UDim2.new(0, 20, 1, -52),
			BackgroundColor3 = C.row,
			Text = "Batal",
			Font = F.bold,
			TextSize = 14,
			TextColor3 = C.txt,
			ZIndex = 52,
			AutoButtonColor = false,
		}, box)
		corner(noBtn, 10)
		stroke(noBtn, C.strokeSub, 1, 0.5)

		local yesBtn = mk("TextButton", {
			Size = UDim2.fromOffset(130, 40),
			Position = UDim2.new(1, -150, 1, -52),
			BackgroundColor3 = C.red,
			Text = "Ya, Tutup",
			Font = F.bold,
			TextSize = 14,
			TextColor3 = Color3.new(1, 1, 1),
			ZIndex = 52,
			AutoButtonColor = false,
		}, box)
		corner(yesBtn, 10)
		stroke(yesBtn, C.red, 1.2, 0.2)

		noBtn.MouseEnter:Connect(function() noBtn.BackgroundColor3 = C.rowHover end)
		noBtn.MouseLeave:Connect(function() noBtn.BackgroundColor3 = C.row end)
		noBtn.MouseButton1Click:Connect(function() overlay:Destroy() end)
		yesBtn.MouseButton1Click:Connect(function() gui:Destroy() end)
	end
	closeBtn.MouseButton1Click:Connect(confirmClose)

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

	-- Sidebar Header Tag
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

	-- Tab Buttons Scrolling List
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

	-- Player Profile Luxury Card
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
		Text = "Online ✦",
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

	----------------------------------------------------------------- Resize Grip (Smooth & Subtle)
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

	----------------------------------------------------------------- Status Footer Pill
	local statusText = mk("TextLabel", {
		Size = UDim2.new(1, -214, 0, 20),
		Position = UDim2.new(0, 202, 1, -24),
		BackgroundTransparency = 1,
		Text = "● Status: Idle",
		Font = F.bold,
		TextSize = 11,
		TextColor3 = C.sub,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
	}, main)

	function ctx.setStatus(s)
		local isActive = tostring(s):lower():find("active") ~= nil or tostring(s):lower():find("jalan") ~= nil
		statusText.Text = (isActive and "● " or "○ ") .. "Status: " .. tostring(s)
		statusText.TextColor3 = isActive and C.green or C.sub
	end

	----------------------------------------------------------------- Logger
	local logLines = ctx.state.logLines
	function ctx.log(msg)
		table.insert(logLines, os.date("%H:%M:%S ") .. msg)
		while #logLines > 12 do table.remove(logLines, 1) end
		if ctx.ui.logBox then ctx.ui.logBox.Text = table.concat(logLines, "\n") end
	end

	ctx.ui.main            = main
	ctx.ui.maxIcon         = maxIcon
	ctx.ui.content         = content
	ctx.ui.tabButtonsFrame = tabButtonsFrame
	ctx.ui.statusText      = statusText
end
