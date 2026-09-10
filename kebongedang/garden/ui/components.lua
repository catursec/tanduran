--[[ components.lua — kontrol UI garden PINK ROYALE:
     Ukuran font besar & sangat jelas dibaca, dropdown lapang (mudah memilih pet team),
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

		if desc then
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

	local function divider(parent)
		local d = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = C.strokeSub,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			LayoutOrder = 9999,
		}, parent)
		grad(d, 0, C.strokeSub, C.acc)
	end

	----------------------------------------------------------------- Modern Toggle Pill
	local function makeToggle(parent, title, desc, getv, setv, order)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		labels(row, title, desc, 84)

		local pill = mk("TextButton", {
			Size = UDim2.fromOffset(56, 30),
			Position = UDim2.new(1, -62, 0.5, -15),
			BackgroundColor3 = C.panel,
			Text = "",
			AutoButtonColor = false,
		}, row)
		corner(pill, 15)
		local pillStroke = stroke(pill, C.strokeSub, 1.2, 0.4)

		local pillGrad = mk("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.acc,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, pill)
		corner(pillGrad, 15)
		grad(pillGrad, 0, C.acc, C.acc2)

		local dot = mk("Frame", {
			Size = UDim2.fromOffset(24, 24),
			Position = UDim2.fromOffset(3, 3),
			BackgroundColor3 = C.sub,
			ZIndex = 3,
		}, pill)
		corner(dot, 12)
		stroke(dot, Color3.new(1, 1, 1), 1, 0.6)

		local function render(animate)
			local on = getv()
			local targetPos = on and UDim2.fromOffset(29, 3) or UDim2.fromOffset(3, 3)
			local targetDotColor = on and Color3.new(1, 1, 1) or C.sub
			local targetPillColor = on and C.acc or C.panel
			local targetGradTrans = on and 0 or 1
			local targetStrokeCol = on and C.accSoft or C.strokeSub

			if animate then
				TS:Create(dot, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = targetPos,
					BackgroundColor3 = targetDotColor,
				}):Play()
				TS:Create(pillGrad, TweenInfo.new(0.2), { BackgroundTransparency = targetGradTrans }):Play()
				TS:Create(pill, TweenInfo.new(0.2), { BackgroundColor3 = targetPillColor }):Play()
				TS:Create(pillStroke, TweenInfo.new(0.2), { Color = targetStrokeCol }):Play()
			else
				dot.Position = targetPos
				dot.BackgroundColor3 = targetDotColor
				pillGrad.BackgroundTransparency = targetGradTrans
				pill.BackgroundColor3 = targetPillColor
				pillStroke.Color = targetStrokeCol
			end
		end

		pill.MouseButton1Click:Connect(function()
			local nv = not getv()
			setv(nv)
			render(true)
			if ctx.log then ctx.log(title .. (nv and " ➔ ON" or " ➔ OFF")) end
		end)

		render(false)
		return function() render(true) end
	end

	----------------------------------------------------------------- Input Box (Focus Glow)
	local function makeInput(parent, title, desc, getv, setv, order)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		labels(row, title, desc, 170)

		local boxFrame = mk("Frame", {
			Size = UDim2.fromOffset(150, 36),
			Position = UDim2.new(1, -158, 0.5, -18),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
		}, row)
		corner(boxFrame, 9)
		local bStroke = stroke(boxFrame, C.strokeSub, 1.2, 0.4)

		local box = mk("TextBox", {
			Size = UDim2.new(1, -18, 1, 0),
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

		return box
	end

	----------------------------------------------------------------- Single Dropdown (Lapang & Jelas)
	local function makeSingleDropdown(parent, title, desc, getOptions, getv, setv, order)
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
			local raw = getOptions()
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
					Size = UDim2.new(1, 0, 0, 38),
					BackgroundColor3 = isSel and C.rowAlt or C.row,
					Text = (isSel and "   ✓  " or "      ") .. display,
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = isSel and F.bold or F.semi,
					TextSize = 14,
					TextColor3 = isSel and C.accSoft or C.txt,
					AutoButtonColor = false,
				}, scroll)
				corner(ob, 8)
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

		return function()
			valLbl.Text = getv() ~= "" and getv() or "Pilih Opsi"
		end
	end

	----------------------------------------------------------------- Multi Dropdown (Lapang & Jelas)
	local function makeMultiDropdown(parent, title, desc, options, selSet, onChange, order)
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

	----------------------------------------------------------------- Dynamic Multi Dropdown (Pet Team / Pick Up: Ekstra Lapang)
	local function makeMultiDropdownDyn(parent, title, desc, getOptions, selSet, onChange, order)
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
			Text = "Pilih (semua)",
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

		local function countSel()
			local n = 0; for _ in pairs(selSet) do n += 1 end; return n
		end

		local function updateSummary()
			local n = countSel()
			if n == 0 then
				valLbl.Text = "Pilih (semua)"
				valLbl.TextColor3 = C.sub
			else
				valLbl.Text = n .. " dipilih ✦"
				valLbl.TextColor3 = C.accSoft
			end
		end

		-- Panel dropdown diperbesar ke 270px (lebih tinggi & lega untuk pet)
		local listFrame = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 270),
			BackgroundColor3 = C.panel,
			Visible = false,
			LayoutOrder = 2,
		}, row)
		corner(listFrame, 12)
		stroke(listFrame, C.stroke, 1.4, 0.3)

		local searchBox = mk("TextBox", {
			Size = UDim2.new(1, -16, 0, 36),
			Position = UDim2.fromOffset(8, 8),
			BackgroundColor3 = C.row,
			PlaceholderText = "🔍 Cari pet (nama / mutasi / ID)...",
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

		local optBtns = {}
		local function rebuild()
			for _, o in ipairs(optBtns) do o.btn:Destroy() end
			optBtns = {}

			local raw = getOptions()
			local ordered, sel, unsel = {}, {}, {}
			for _, o in ipairs(raw) do
				if selSet[o.value] then sel[#sel + 1] = o else unsel[#unsel + 1] = o end
			end
			for _, o in ipairs(sel) do ordered[#ordered + 1] = o end
			for _, o in ipairs(unsel) do ordered[#ordered + 1] = o end

			for _, opt in ipairs(ordered) do
				local value, display = opt.value, opt.display
				local isSel = selSet[value] == true

				-- Tombol pet diperbesar ke 40px tinggi & font 14.5px bold (sangat mudah dibaca & di-tap)
				local ob = mk("TextButton", {
					Size = UDim2.new(1, 0, 0, 40),
					BackgroundColor3 = isSel and C.rowAlt or C.row,
					Text = "     " .. display,
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = isSel and F.bold or F.bold,
					TextSize = 14.5,
					TextColor3 = isSel and C.accSoft or C.txt,
					AutoButtonColor = false,
				}, scroll)
				corner(ob, 8)
				local obStroke = stroke(ob, isSel and C.acc or C.strokeSub, 1.2, isSel and 0.25 or 0.7)

				local checkBadge = mk("TextLabel", {
					Size = UDim2.fromOffset(20, 24),
					Position = UDim2.new(1, -22, 0.5, -12),
					BackgroundTransparency = 1,
					Text = isSel and "✓" or "",
					Font = F.bold,
					TextSize = 12,
					TextColor3 = C.green,
				}, ob)

				local function rend()
					local curSel = selSet[value] == true
					checkBadge.Text = curSel and "✓" or ""
					ob.BackgroundColor3 = curSel and C.rowAlt or C.row
					ob.TextColor3 = curSel and C.accSoft or C.txt
					ob.Font = curSel and F.bold or F.bold
					obStroke.Color = curSel and C.acc or C.strokeSub
					obStroke.Transparency = curSel and 0.25 or 0.7
				end

				ob.MouseEnter:Connect(function()
					if not selSet[value] then ob.BackgroundColor3 = C.rowHover end
				end)
				ob.MouseLeave:Connect(function()
					if not selSet[value] then ob.BackgroundColor3 = C.row end
				end)

				ob.MouseButton1Click:Connect(function()
					if selSet[value] then selSet[value] = nil else selSet[value] = true end
					rend(); updateSummary(); if onChange then onChange() end
				end)

				rend()
				optBtns[#optBtns + 1] = { btn = ob, display = display:lower() }
			end
			updateSummary()
		end

		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local q = searchBox.Text:lower()
			for _, o in ipairs(optBtns) do
				o.btn.Visible = (q == "" or o.display:find(q, 1, true) ~= nil)
			end
		end)

		head.MouseButton1Click:Connect(function()
			listFrame.Visible = not listFrame.Visible
			chevron.Text = listFrame.Visible and "▲" or "▼"
			if listFrame.Visible then rebuild() end
		end)

		updateSummary()
		return updateSummary
	end

	----------------------------------------------------------------- Luxury Accordion
	local function makeAccordion(parent, title, order, openByDefault)
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
			Rotation = openByDefault and 180 or 0,
		}, head)

		local line = mk("Frame", {
			Size = UDim2.new(1, -28, 0, 1),
			Position = UDim2.fromOffset(14, 0),
			BackgroundColor3 = C.strokeSub,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			LayoutOrder = 2,
			Visible = openByDefault or false,
		}, container)
		grad(line, 0, C.strokeSub, C.acc)

		local body = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Visible = openByDefault or false,
			LayoutOrder = 3,
		}, container)
		pad(body, 14, 14, 10, 14)
		mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, body)

		head.MouseEnter:Connect(function()
			TS:Create(cardStroke, TweenInfo.new(0.2), { Color = C.stroke, Transparency = 0.1 }):Play()
			TS:Create(titleLabel, TweenInfo.new(0.2), { TextColor3 = C.accSoft }):Play()
		end)
		head.MouseLeave:Connect(function()
			TS:Create(cardStroke, TweenInfo.new(0.2), { Color = C.strokeSub, Transparency = 0.4 }):Play()
			TS:Create(titleLabel, TweenInfo.new(0.2), { TextColor3 = C.txt }):Play()
		end)

		head.MouseButton1Click:Connect(function()
			body.Visible = not body.Visible
			line.Visible = body.Visible
			local rot = body.Visible and 180 or 0
			TS:Create(chevron, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = rot }):Play()
		end)

		return body
	end

	----------------------------------------------------------------- Sidebar Page/Tab
	local function makePage(name, titleText, icon, order)
		local tabButtonsFrame = ctx.ui.tabButtonsFrame
		local content         = ctx.ui.content
		local pages, tabBtns  = ctx.ui.pages, ctx.ui.tabBtns

		local btn = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = C.row,
			BackgroundTransparency = 1,
			Text = "    " .. (icon or "✦") .. "   " .. name,
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
			Text = (icon or "✦") .. "  " .. titleText,
			Font = F.bold,
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

		btn.MouseButton1Click:Connect(function()
			for n, p in pairs(pages) do p.Visible = (n == name) end
			for n, b in pairs(tabBtns) do
				b.setActive(n == name)
			end
		end)

		return pg
	end

	----------------------------------------------------------------- Gradient Action Button
	local function makeButton(parent, title, desc, onClick, order)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		labels(row, title, desc, 160)

		local btn = mk("TextButton", {
			Size = UDim2.fromOffset(142, 38),
			Position = UDim2.new(1, -150, 0.5, -19),
			BackgroundColor3 = C.acc,
			Text = "Execute ✦",
			Font = F.bold,
			TextSize = 14,
			TextColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = false,
		}, row)
		corner(btn, 10)
		grad(btn, 0, C.acc, C.acc2)
		stroke(btn, C.accSoft, 1.2, 0.3)

		btn.MouseEnter:Connect(function()
			TS:Create(btn, TweenInfo.new(0.15), { TextColor3 = Color3.fromRGB(255, 240, 255) }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TS:Create(btn, TweenInfo.new(0.15), { TextColor3 = Color3.new(1, 1, 1) }):Play()
		end)

		btn.MouseButton1Click:Connect(function()
			TS:Create(btn, TweenInfo.new(0.08), { Size = UDim2.fromOffset(136, 35) }):Play()
			task.delay(0.08, function()
				TS:Create(btn, TweenInfo.new(0.12), { Size = UDim2.fromOffset(142, 38) }):Play()
			end)
			if onClick then onClick() end
		end)

		return btn
	end

	ctx.makeToggle          = makeToggle
	ctx.makeInput           = makeInput
	ctx.makeSingleDropdown  = makeSingleDropdown
	ctx.makeMultiDropdown   = makeMultiDropdown
	ctx.makeMultiDropdownDyn= makeMultiDropdownDyn
	ctx.makeAccordion       = makeAccordion
	ctx.makePage            = makePage
	ctx.makeButton          = makeButton
	ctx.divider             = divider
end
