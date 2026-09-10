--[[ components.lua — kontrol UI trade PINK ROYALE:
     Ukuran font besar & sangat jelas dibaca, dropdown lapang (mudah memilih opsi & pet),
     toggle pill modern, input box dengan focus glow, accordion ber-aksen bar. ]]
return function(ctx)
	local TS = game:GetService("TweenService")
	local C  = ctx.C
	local F  = ctx.F
	local mk, corner, stroke, pad, grad = ctx.mk, ctx.corner, ctx.stroke, ctx.pad, ctx.grad

	local function labels(parent, title, desc, rightPad)
		local txts = mk("Frame", {
			Size = UDim2.new(1, -(rightPad or 160), 1, 0),
			BackgroundTransparency = 1,
		}, parent)
		pad(txts, 4, 0, 0, 0)

		local tLbl = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, desc and 4 or 16),
			BackgroundTransparency = 1,
			Text = title,
			Font = F.bold,
			TextSize = 16.5,
			TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, txts)

		if desc and desc ~= "" then
			local dLbl = mk("TextLabel", {
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.fromOffset(0, 30),
				BackgroundTransparency = 1,
				Text = desc,
				Font = F.reg,
				TextSize = 13.5,
				TextColor3 = C.sub,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, txts)
		end
	end

	----------------------------------------------------------------- Modern Toggle Pill
	local function makeToggle(parent, title, desc, getv, setv, order)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		labels(row, title, desc, 80)

		local pill = mk("TextButton", {
			Size = UDim2.fromOffset(48, 26),
			Position = UDim2.new(1, -56, 0.5, -13),
			BackgroundColor3 = C.rowAlt,
			Text = "",
			AutoButtonColor = false,
		}, row)
		corner(pill, 13)
		local pStroke = stroke(pill, C.strokeSub, 1.2, 0.5)

		local thumb = mk("Frame", {
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.fromOffset(3, 3),
			BackgroundColor3 = C.sub,
			BorderSizePixel = 0,
		}, pill)
		corner(thumb, 10)

		local function update(state, anim)
			local dur = anim and 0.22 or 0
			if state then
				TS:Create(pill, TweenInfo.new(dur), { BackgroundColor3 = C.acc }):Play()
				TS:Create(pStroke, TweenInfo.new(dur), { Color = C.accSoft, Transparency = 0.2 }):Play()
				TS:Create(thumb, TweenInfo.new(dur, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.fromOffset(25, 3),
					BackgroundColor3 = Color3.new(1, 1, 1),
				}):Play()
			else
				TS:Create(pill, TweenInfo.new(dur), { BackgroundColor3 = C.rowAlt }):Play()
				TS:Create(pStroke, TweenInfo.new(dur), { Color = C.strokeSub, Transparency = 0.5 }):Play()
				TS:Create(thumb, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromOffset(3, 3),
					BackgroundColor3 = C.sub,
				}):Play()
			end
		end

		local on = getv()
		update(on, false)

		pill.MouseButton1Click:Connect(function()
			on = not on
			setv(on)
			update(on, true)
		end)

		ctx.state.uiRefreshers = ctx.state.uiRefreshers or {}
		table.insert(ctx.state.uiRefreshers, function()
			local cur = getv()
			if cur ~= on then on = cur; update(on, false) end
		end)

		return pill
	end

	----------------------------------------------------------------- Input Box (Focus Glow)
	local function makeInput(parent, title, desc, getv, setv, order)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		labels(row, title, desc, 130)

		local boxFrame = mk("Frame", {
			Size = UDim2.fromOffset(120, 36),
			Position = UDim2.new(1, -126, 0.5, -18),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
		}, row)
		corner(boxFrame, 8)
		local bStroke = stroke(boxFrame, C.strokeSub, 1, 0.4)

		local box = mk("TextBox", {
			Size = UDim2.new(1, -16, 1, 0),
			Position = UDim2.fromOffset(9, 0),
			BackgroundTransparency = 1,
			Text = tostring(getv()),
			Font = F.bold,
			TextSize = 14,
			TextColor3 = C.txt,
			PlaceholderColor3 = C.sub,
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, boxFrame)

		box.Focused:Connect(function()
			TS:Create(bStroke, TweenInfo.new(0.2), { Color = C.acc, Transparency = 0 }):Play()
			TS:Create(boxFrame, TweenInfo.new(0.2), { BackgroundColor3 = C.rowAlt }):Play()
		end)
		box.FocusLost:Connect(function()
			TS:Create(bStroke, TweenInfo.new(0.2), { Color = C.strokeSub, Transparency = 0.4 }):Play()
			TS:Create(boxFrame, TweenInfo.new(0.2), { BackgroundColor3 = C.panel }):Play()
			setv(box.Text)
			box.Text = tostring(getv())
		end)
		box:GetPropertyChangedSignal("Text"):Connect(function()
			setv(box.Text)
		end)

		ctx.state.uiRefreshers = ctx.state.uiRefreshers or {}
		table.insert(ctx.state.uiRefreshers, function() box.Text = tostring(getv()) end)

		return box
	end

	----------------------------------------------------------------- Multi Dropdown (Lapang & Jelas)
	local function makeDropdown(parent, title, desc, options, selSet, onChange, order)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, row)

		local head = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 1,
		}, row)
		labels(head, title, desc, 250)

		local pillBadge = mk("Frame", {
			Size = UDim2.fromOffset(230, 40),
			Position = UDim2.new(1, -236, 0.5, -20),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
		}, head)
		corner(pillBadge, 10)
		stroke(pillBadge, C.strokeSub, 1.2, 0.5)
		pad(pillBadge, 12, 10, 0, 0)

		local valLbl = mk("TextLabel", {
			Size = UDim2.new(1, -26, 1, 0),
			BackgroundTransparency = 1,
			Text = "Pilih",
			Font = F.bold,
			TextSize = 14.5,
			TextColor3 = C.sub,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, pillBadge)

		local chevron = mk("TextLabel", {
			Size = UDim2.fromOffset(18, 18),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			BackgroundTransparency = 1,
			Text = "▼",
			Font = F.bold,
			TextSize = 13,
			TextColor3 = C.acc,
		}, pillBadge)

		local function updateSummary()
			local sel = {}
			for _, o in ipairs(options) do
				if selSet[o] then sel[#sel + 1] = o end
			end
			if #sel == 0 then
				valLbl.Text = "Pilih"
				valLbl.TextColor3 = C.sub
			else
				local txt = table.concat(sel, ", ")
				if #txt > 20 then txt = (#sel) .. " dipilih ✦" end
				valLbl.Text = txt
				valLbl.TextColor3 = C.accSoft
			end
		end

		local listFrame = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 250),
			BackgroundColor3 = C.panel,
			Visible = false,
			LayoutOrder = 2,
		}, row)
		corner(listFrame, 10)
		stroke(listFrame, C.stroke, 1.4, 0.3)

		local searchBox = mk("TextBox", {
			Size = UDim2.new(1, -16, 0, 36),
			Position = UDim2.fromOffset(8, 8),
			BackgroundColor3 = C.row,
			PlaceholderText = "🔍 Cari opsi...",
			PlaceholderColor3 = C.sub,
			Text = "",
			Font = F.bold,
			TextSize = 14,
			TextColor3 = C.txt,
			ClearTextOnFocus = false,
		}, listFrame)
		corner(searchBox, 8)
		stroke(searchBox, C.strokeSub, 1, 0.5)
		pad(searchBox, 12, 8, 0, 0)

		local scroll = mk("ScrollingFrame", {
			Size = UDim2.new(1, -16, 1, -54),
			Position = UDim2.fromOffset(8, 50),
			BackgroundTransparency = 1,
			ScrollBarThickness = 5,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = "Y",
			ScrollBarImageColor3 = C.acc,
		}, listFrame)
		mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

		local built = false
		local optBtns = {}

		local function reorder()
			local i = 0
			for _, opt in ipairs(options) do
				if selSet[opt] and optBtns[opt] then i = i + 1; optBtns[opt].LayoutOrder = i end
			end
			for _, opt in ipairs(options) do
				if not selSet[opt] and optBtns[opt] then i = i + 1; optBtns[opt].LayoutOrder = i end
			end
		end

		local function build()
			if built then return end; built = true
			for _, opt in ipairs(options) do
				local ob = mk("TextButton", {
					Size = UDim2.new(1, 0, 0, 38),
					BackgroundColor3 = C.row,
					Text = "      " .. opt,
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = F.semi,
					TextSize = 14,
					TextColor3 = C.txt,
					AutoButtonColor = false,
				}, scroll)
				corner(ob, 8)
				local obStroke = stroke(ob, C.strokeSub, 1, 0.7)

				local checkBadge = mk("TextLabel", {
					Size = UDim2.fromOffset(20, 24),
					Position = UDim2.new(1, -22, 0.5, -12),
					BackgroundTransparency = 1,
					Text = "",
					Font = F.bold,
					TextSize = 12,
					TextColor3 = C.green,
				}, ob)

				local function rend()
					local isSel = selSet[opt] == true
					checkBadge.Text = isSel and "✓" or ""
					ob.BackgroundColor3 = isSel and C.rowAlt or C.row
					ob.TextColor3 = isSel and C.accSoft or C.txt
					ob.Font = isSel and F.bold or F.semi
					obStroke.Color = isSel and C.acc or C.strokeSub
					obStroke.Transparency = isSel and 0.3 or 0.7
				end

				ob.MouseEnter:Connect(function()
					if not selSet[opt] then ob.BackgroundColor3 = C.rowHover end
				end)
				ob.MouseLeave:Connect(function()
					if not selSet[opt] then ob.BackgroundColor3 = C.row end
				end)

				ob.MouseButton1Click:Connect(function()
					if selSet[opt] then selSet[opt] = nil else selSet[opt] = true end
					rend(); updateSummary(); reorder(); if onChange then onChange() end
				end)

				rend()
				optBtns[opt] = ob
			end
			reorder()
		end

		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local q = searchBox.Text:lower()
			for opt, ob in pairs(optBtns) do
				ob.Visible = (q == "" or opt:lower():find(q, 1, true) ~= nil)
			end
		end)

		head.MouseButton1Click:Connect(function()
			if not built then build() end
			listFrame.Visible = not listFrame.Visible
			chevron.Text = listFrame.Visible and "▲" or "▼"
			if listFrame.Visible then reorder() end
		end)

		updateSummary()
		return updateSummary
	end

	----------------------------------------------------------------- Single Dropdown (Lapang & Jelas)
	local function makeSingleDropdown(parent, title, desc, options, getv, setv, order)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, row)

		local head = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 1,
		}, row)
		labels(head, title, desc, 250)

		local pillBadge = mk("Frame", {
			Size = UDim2.fromOffset(230, 40),
			Position = UDim2.new(1, -236, 0.5, -20),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
		}, head)
		corner(pillBadge, 10)
		stroke(pillBadge, C.strokeSub, 1.2, 0.5)
		pad(pillBadge, 12, 10, 0, 0)

		local valLbl = mk("TextLabel", {
			Size = UDim2.new(1, -26, 1, 0),
			BackgroundTransparency = 1,
			Text = getv() ~= "" and getv() or "Pilih Opsi",
			Font = F.bold,
			TextSize = 14.5,
			TextColor3 = C.accSoft,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, pillBadge)

		local chevron = mk("TextLabel", {
			Size = UDim2.fromOffset(18, 18),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			BackgroundTransparency = 1,
			Text = "▼",
			Font = F.bold,
			TextSize = 13,
			TextColor3 = C.acc,
		}, pillBadge)

		local listFrame = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 250),
			BackgroundColor3 = C.panel,
			Visible = false,
			LayoutOrder = 2,
		}, row)
		corner(listFrame, 10)
		stroke(listFrame, C.stroke, 1.4, 0.3)

		local searchBox = mk("TextBox", {
			Size = UDim2.new(1, -16, 0, 36),
			Position = UDim2.fromOffset(8, 8),
			BackgroundColor3 = C.row,
			PlaceholderText = "🔍 Cari opsi...",
			PlaceholderColor3 = C.sub,
			Text = "",
			Font = F.bold,
			TextSize = 14,
			TextColor3 = C.txt,
			ClearTextOnFocus = false,
		}, listFrame)
		corner(searchBox, 8)
		stroke(searchBox, C.strokeSub, 1, 0.5)
		pad(searchBox, 12, 8, 0, 0)

		local scroll = mk("ScrollingFrame", {
			Size = UDim2.new(1, -16, 1, -52),
			Position = UDim2.fromOffset(8, 48),
			BackgroundTransparency = 1,
			ScrollBarThickness = 4,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = "Y",
			ScrollBarImageColor3 = C.acc,
		}, listFrame)
		mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

		local optBtns = {}
		local function rebuild()
			for _, b in pairs(optBtns) do b:Destroy() end
			optBtns = {}
			local cur = getv()
			local raw = options or {}
			local ordered, rest = {}, {}
			for _, opt in ipairs(raw) do
				local display = type(opt) == "table" and opt.display or opt
				local code    = type(opt) == "table" and opt.name or opt
				if display == cur or code == cur then ordered[#ordered + 1] = opt else rest[#rest + 1] = opt end
			end
			for _, opt in ipairs(rest) do ordered[#ordered + 1] = opt end

			for _, opt in ipairs(ordered) do
				local display = type(opt) == "table" and opt.display or opt
				local code    = type(opt) == "table" and opt.name or opt
				local isSel   = (display == cur or code == cur)

				local ob = mk("TextButton", {
					Size = UDim2.new(1, 0, 0, 34),
					BackgroundColor3 = isSel and C.rowAlt or C.row,
					Text = (isSel and "   ✓  " or "      ") .. display,
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = isSel and F.bold or F.semi,
					TextSize = 13,
					TextColor3 = isSel and C.accSoft or C.txt,
					AutoButtonColor = false,
				}, scroll)
				corner(ob, 7)
				stroke(ob, isSel and C.acc or C.strokeSub, 1, isSel and 0.2 or 0.7)

				ob.MouseEnter:Connect(function()
					if not isSel then ob.BackgroundColor3 = C.rowHover end
				end)
				ob.MouseLeave:Connect(function()
					if not isSel then ob.BackgroundColor3 = C.row end
				end)

				ob.MouseButton1Click:Connect(function()
					setv(code)
					valLbl.Text = display
					listFrame.Visible = false
					chevron.Text = "▼"
				end)
				optBtns[#optBtns + 1] = ob
			end
		end

		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local q = searchBox.Text:lower()
			for _, ob in ipairs(optBtns) do
				ob.Visible = (q == "" or ob.Text:lower():find(q, 1, true) ~= nil)
			end
		end)

		head.MouseButton1Click:Connect(function()
			listFrame.Visible = not listFrame.Visible
			chevron.Text = listFrame.Visible and "▲" or "▼"
			if listFrame.Visible then rebuild() end
		end)

		return head
	end

	----------------------------------------------------------------- Button
	local function makeButton(parent, title, color, onClick, order)
		local base = color or C.acc
		local isRed = (color == C.red)

		local btn = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundColor3 = base,
			Text = title .. " ✦",
			Font = F.bold,
			TextSize = 14,
			TextColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = false,
			LayoutOrder = order,
		}, parent)
		corner(btn, 10)
		if not isRed then
			grad(btn, 0, C.acc, C.acc2)
		end
		stroke(btn, isRed and C.red or C.accSoft, 1.2, 0.3)

		btn.MouseEnter:Connect(function()
			TS:Create(btn, TweenInfo.new(0.15), { TextColor3 = Color3.fromRGB(255, 240, 255) }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TS:Create(btn, TweenInfo.new(0.15), { TextColor3 = Color3.new(1, 1, 1) }):Play()
		end)

		btn.MouseButton1Click:Connect(function()
			TS:Create(btn, TweenInfo.new(0.08), { Size = UDim2.new(1, -6, 0, 35) }):Play()
			task.delay(0.08, function()
				TS:Create(btn, TweenInfo.new(0.12), { Size = UDim2.new(1, 0, 0, 38) }):Play()
			end)
			if onClick then onClick() end
		end)

		return btn
	end

	----------------------------------------------------------------- Luxury Accordion
	local function makeAccordion(parent, title, order)
		local container = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.row,
			BorderSizePixel = 0,
			LayoutOrder = order,
			ClipsDescendants = false,
		}, parent)
		corner(container, 12)
		local cardStroke = stroke(container, C.strokeSub, 1.2, 0.4)
		mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 0) }, container)

		local head = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 1,
		}, container)
		corner(head, 12)
		pad(head, 14, 14, 0, 0)

		local accentBar = mk("Frame", {
			Size = UDim2.new(0, 5, 0, 28),
			Position = UDim2.new(0, 0, 0.5, -14),
			BackgroundColor3 = C.acc,
			BorderSizePixel = 0,
		}, head)
		corner(accentBar, 2)
		grad(accentBar, 90, C.acc, C.acc2)

		local titleLabel = mk("TextLabel", {
			Size = UDim2.new(1, -40, 1, 0),
			Position = UDim2.fromOffset(14, 0),
			BackgroundTransparency = 1,
			Text = title,
			Font = F.bold,
			TextSize = 17,
			TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, head)

		local chevron = mk("TextLabel", {
			Size = UDim2.fromOffset(20, 20),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			BackgroundTransparency = 1,
			Text = "▼",
			Font = F.bold,
			TextSize = 13,
			TextColor3 = C.acc,
		}, head)

		local line = mk("Frame", {
			Size = UDim2.new(1, -28, 0, 1),
			Position = UDim2.fromOffset(14, 0),
			BackgroundColor3 = C.strokeSub,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			LayoutOrder = 2,
			Visible = false,
		}, container)
		grad(line, 0, C.strokeSub, C.acc)

		local body = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Visible = false,
			LayoutOrder = 3,
		}, container)
		pad(body, 14, 14, 10, 14)
		mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, body)

		local open = false
		local function setOpen(v)
			open = v
			body.Visible = open
			line.Visible = open
			chevron.Text = open and "▲" or "▼"
			TS:Create(cardStroke, TweenInfo.new(0.2), {
				Color = open and C.stroke or C.strokeSub,
				Transparency = open and 0.1 or 0.4,
			}):Play()
		end

		head.MouseButton1Click:Connect(function() setOpen(not open) end)
		head.MouseEnter:Connect(function()
			TS:Create(titleLabel, TweenInfo.new(0.15), { TextColor3 = C.accSoft }):Play()
		end)
		head.MouseLeave:Connect(function()
			TS:Create(titleLabel, TweenInfo.new(0.15), { TextColor3 = C.txt }):Play()
		end)

		return body, setOpen, container
	end

	----------------------------------------------------------------- Page + Tab
	local function selectTab(name)
		local pages   = ctx.ui.pages
		local tabBtns = ctx.ui.tabBtns
		for n, p in pairs(pages) do p.Visible = (n == name) end
		for n, b in pairs(tabBtns) do
			local on = (n == name)
			if b.setActive then
				b.setActive(on)
			else
				TS:Create(b.btn, TweenInfo.new(0.18), { BackgroundTransparency = on and 0.2 or 1 }):Play()
				b.btn.TextColor3 = on and C.txt or C.sub
				b.line.Visible = on
			end
		end
	end
	ctx.selectTab = selectTab

	local function makePage(name, titleText, iconLabel, order)
		local tabButtonsFrame = ctx.ui.tabButtonsFrame
		local content         = ctx.ui.content
		local pages           = ctx.ui.pages
		local tabBtns         = ctx.ui.tabBtns

		local btn = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = C.row,
			BackgroundTransparency = 1,
			Text = "    " .. (iconLabel or "✦") .. "   " .. name,
			Font = F.bold,
			TextSize = 15,
			TextColor3 = C.sub,
			LayoutOrder = order,
			AutoButtonColor = false,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, tabButtonsFrame)
		corner(btn, 10)

		local line = mk("Frame", {
			Size = UDim2.new(0, 4, 0, 26),
			Position = UDim2.new(0, 4, 0.5, -13),
			BackgroundColor3 = C.acc,
			Visible = false,
			BorderSizePixel = 0,
		}, btn)
		corner(line, 2)
		grad(line, 90, C.acc, C.acc2)

		local function setActive(isActive)
			if isActive then
				TS:Create(btn, TweenInfo.new(0.18), {
					BackgroundTransparency = 0.15,
					BackgroundColor3 = C.rowAlt,
					TextColor3 = C.txt,
				}):Play()
				line.Visible = true
			else
				TS:Create(btn, TweenInfo.new(0.18), {
					BackgroundTransparency = 1,
					BackgroundColor3 = C.row,
					TextColor3 = C.sub,
				}):Play()
				line.Visible = false
			end
		end

		btn.MouseEnter:Connect(function()
			if not line.Visible then
				TS:Create(btn, TweenInfo.new(0.15), { BackgroundTransparency = 0.6, BackgroundColor3 = C.rowHover, TextColor3 = C.txt }):Play()
			end
		end)
		btn.MouseLeave:Connect(function()
			if not line.Visible then
				TS:Create(btn, TweenInfo.new(0.15), { BackgroundTransparency = 1, TextColor3 = C.sub }):Play()
			end
		end)

		tabBtns[name] = { btn = btn, line = line, setActive = setActive }

		local pg = mk("ScrollingFrame", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Visible = false,
			ScrollBarThickness = 4,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = "Y",
			ScrollBarImageColor3 = C.acc,
		}, content)
		pad(pg, 4, 10, 2, 10)
		mk("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, pg)
		pages[name] = pg

		local headerFrame = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 46),
			BackgroundTransparency = 1,
			LayoutOrder = 0,
		}, pg)

		local tTitle = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			Text = (iconLabel or "✦") .. "  " .. titleText,
			Font = F.title,
			TextSize = 26,
			TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, headerFrame)

		local underline = mk("Frame", {
			Size = UDim2.new(0, 65, 0, 3),
			Position = UDim2.new(0, 0, 1, -4),
			BackgroundColor3 = C.acc,
			BorderSizePixel = 0,
		}, headerFrame)
		corner(underline, 2)
		grad(underline, 0, C.acc, C.acc2)

		btn.MouseButton1Click:Connect(function() selectTab(name) end)
		return pg
	end

	ctx.makeToggle         = makeToggle
	ctx.makeInput          = makeInput
	ctx.makeDropdown       = makeDropdown
	ctx.makeSingleDropdown = makeSingleDropdown
	ctx.makeButton         = makeButton
	ctx.makeAccordion      = makeAccordion
	ctx.makePage           = makePage
end
