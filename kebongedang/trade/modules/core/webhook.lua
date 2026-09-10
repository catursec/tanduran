--[[ webhook.lua — Discord webhook + listener transaksi (notif terjual).
     Mengisi: ctx.sendWebhook
     Efek samping: connect AddToHistory.OnClientEvent ]]
return function(ctx)
	local LP          = ctx.LP
	local HttpService = ctx.Services.HttpService
	local CFG         = ctx.CFG
	local AddToHistory = ctx.deps.AddToHistory

	----------------------------------------------------------------- sender
	local function sendWebhook(payload)
		if not CFG.webhookEnabled or CFG.webhookUrl == "" then return end
		if type(payload) == "table" then
			if not payload.username then payload.username = "CeszParadise" end
			if not payload.avatar_url then payload.avatar_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png" end
		end
		task.spawn(function()
			local reqFn = (syn and syn.request) or (http and http.request) or http_request or request
			if not reqFn then return end
			pcall(reqFn, {
				Url = CFG.webhookUrl, Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode(payload),
			})
		end)
	end
	ctx.sendWebhook = sendWebhook

	----------------------------------------------------------------- history ke dashboard
	-- Kirim transaksi (buy/sell) ke Laravel buat History tab. Non-blocking, best-effort.
	local EVENT_URL = "https://api.allegiaant.my.id/api/event"
	local EVENT_KEY = "ae3858d4a2def3306d6cbff26ff2bd72eee9319b1aae27d1"
	local function reportEvent(kind, data)
		task.spawn(function()
			local reqFn = (syn and syn.request) or (http and http.request) or http_request or request
			if not reqFn then return end
			data = data or {}
			data.kind = kind
			data.userId = LP.UserId
			pcall(reqFn, {
				Url = EVENT_URL, Method = "POST",
				Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = EVENT_KEY },
				Body = HttpService:JSONEncode(data),
			})
		end)
	end
	ctx.reportEvent = reportEvent

	----------------------------------------------------------------- sell listener
	-- Dedup GLOBAL (persist antar-reload). ctx.state di-reset tiap reload, jadi
	-- kalau pakai tabel per-ctx, listener lama (yg bocor) + listener baru punya
	-- tabel dedup masing-masing -> kirim double/triple. Tabel global bikin listener
	-- mana pun yg duluan proses tx.id nge-block sisanya.
	local lastProcessedTx = _G.__AH_SellTx
	if type(lastProcessedTx) ~= "table" then
		lastProcessedTx = {}
		_G.__AH_SellTx = lastProcessedTx
	end
	ctx.state.lastProcessedTx = lastProcessedTx

	-- Disconnect listener dari eksekusi/reload sebelumnya biar nggak numpuk.
	if _G.__AH_SellConn then pcall(function() _G.__AH_SellConn:Disconnect() end) end

	_G.__AH_SellConn = AddToHistory.OnClientEvent:Connect(function(tx)
		if not CFG.webhookEnabled or CFG.webhookUrl == "" then return end
		if not tx or type(tx) ~= "table" then return end
		if lastProcessedTx[tx.id] then return end
		lastProcessedTx[tx.id] = true

		-- Cek apakah kita adalah penjual (seller) dan transaksinya sukses
		local myId = ctx.myPlayerId()
		local isSeller = (myId == tx.seller.userId) or (LP.UserId == tx.seller.userId)
		local isSuccess = tx.status and tx.status.result ~= "Failed"

		if isSeller and isSuccess then
			-- Dapatkan detail item
			local itemType = tx.item and tx.item.type or "Unknown"
			local petType = "Unknown"
			local petName = "-"
			local petAge = "-"
			local petWeight = "-"

			local sellW, sellAge, sellMut = nil, nil, nil
			if itemType == "Pet" and tx.item.data then
				local d = tx.item.data
				petType = d.PetType or "Unknown"
				if d.PetData then
					petName = d.PetData.Name or petType
					if petName == "" then petName = petType end
					petAge = tostring(d.PetData.Level or 0)
					petWeight = ("%.2f kg"):format(d.PetData.BaseWeight or 0)
					sellW = d.PetData.BaseWeight or 0
					sellAge = d.PetData.Level or 0
					local okm, m = pcall(function() return ctx.reg.mutDisplay(d.PetData.MutationType) end)
					if okm and m and m ~= "None" and m ~= "Normal" then sellMut = m end
				end
			else
				-- Fallback jika bukan pet
				if tx.item.data then
					if tx.item.data.ItemData then
						petType = tx.item.data.ItemData.ItemName or "Unknown"
					else
						petType = tx.item.data.PetType or tx.item.data.SkinID or "Unknown"
					end
					petName = petType
				end
			end

			local price = tx.price or 0
			local priceWithFee = price - math.ceil(price / 100)

			local currentTokens = tostring(ctx.getTokens())
			local formattedTokens = currentTokens
			local numTokens = tonumber(currentTokens)
			if numTokens then
				local formatted = tostring(numTokens)
				local k
				while true do
					formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1.%2')
					if k == 0 then break end
				end
				formattedTokens = formatted
			end

			local embed = {
				title = "✦ CeszParadise — Sell Notification",
				color = 16738670, -- Soft vibrant rose
				fields = {
					{
						name = "**Profile :**",
						value = ("> Username : **%s**\n> Buyer : `%s`"):format(tostring(tx.seller.username), tostring(tx.buyer.username)),
						inline = false
					},
					{
						name = "**Item Sold :**",
						value = ("> Item Type : `%s`\n> Pet Type : `%s`\n> Pet Name : `%s`\n> Pet Age : `%s`\n> Pet Weight : `%s`\n> Price : **%s Token**\n> Price (With Fee) : `%s Token`"):format(
							tostring(itemType),
							tostring(petType),
							tostring(petName),
							tostring(petAge),
							tostring(petWeight),
							tostring(price),
							tostring(priceWithFee)
						),
						inline = false
					},
					{
						name = "**Current Tokens :**",
						value = ("> **%s Token**"):format(tostring(formattedTokens)),
						inline = false
					}
				},
				footer = {
					text = ("CeszParadise Trade • %s"):format(os.date("%B %d | %I:%M %p")),
					icon_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png"
				}
			}

			sendWebhook({
				username = "CeszParadise",
				avatar_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png",
				embeds = { embed }
			})

			reportEvent("sell", {
				pet = petType,
				mutation = sellMut,
				weight = sellW,
				age = sellAge,
				price = tonumber(price) or 0,
				counterpart = tostring(tx.buyer and tx.buyer.username or "?"),
			})
		end
	end)
end
