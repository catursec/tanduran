--[[ accept.lua — Automation Accept.
     * Accept Gifts : gift pet LANGSUNG (tanpa trade/tiket). Remote GiftPet masuk,
                      dijawab AcceptPetGift:FireServer(true, giftId).
     * Accept Trades: auto-terima AJAKAN trade masuk (RespondRequest true) [menyusul].
     Dua hal berbeda — gift ≠ trade. ]]
return function(ctx)
	local CFG            = ctx.CFG
	local SendRequest    = ctx.deps.SendRequest
	local RespondRequest = ctx.deps.RespondRequest
	local GiftPet        = ctx.deps.GiftPet
	local AcceptPetGift  = ctx.deps.AcceptPetGift
	local TC             = ctx.deps.TradingController
	local Accept         = ctx.deps.Accept
	local Confirm        = ctx.deps.Confirm
	local function log(m) ctx.log(m) end

	----------------------------------------------------------------- AUTO ACCEPT GIFT
	-- GiftPet.OnClientEvent(giftId, petDescription, senderName)
	-- UI notif dibuat game di PlayerGui.Gift_Notification.Frame (tiap gift = 1 clone,
	-- tombolnya di notif.Holder.Frame.Accept). Kita picu klik tombol itu supaya
	-- handler asli jalan (destroy UI + fire AcceptPetGift) -> UI ikut hilang.
	local LP = ctx.LP

	local function clickAcceptButtons()
		local pg = LP:FindFirstChild("PlayerGui")
		local gn = pg and pg:FindFirstChild("Gift_Notification")
		local frame = gn and gn:FindFirstChild("Frame")
		if not frame then return 0 end
		local n = 0
		for _, notif in ipairs(frame:GetChildren()) do
			local holder = notif:FindFirstChild("Holder")
			local inner  = holder and holder:FindFirstChild("Frame")
			local accept = inner and inner:FindFirstChild("Accept")
			if accept then
				local fired = false
				if type(getconnections) == "function" then
					for _, c in ipairs(getconnections(accept.MouseButton1Click)) do
						pcall(function() c:Fire() end); fired = true
					end
				end
				if fired then n += 1 end
			end
		end
		return n
	end

	if GiftPet and AcceptPetGift then
		GiftPet.OnClientEvent:Connect(function(giftId, petDesc, sender)
			if not CFG.acceptGifts then return end
			if type(giftId) ~= "string" then return end
			log(("Gift masuk dari %s: %s"):format(tostring(sender), tostring(petDesc)))
			task.wait(0.5) -- kasih waktu game bikin UI notif-nya dulu
			local clicked = clickAcceptButtons()
			if clicked > 0 then
				log("Gift diterima ✓ (via tombol, UI ditutup)")
			else
				-- fallback: fire remote langsung + coba hapus notif
				pcall(function() AcceptPetGift:FireServer(true, giftId) end)
				local pg = LP:FindFirstChild("PlayerGui")
				local gn = pg and pg:FindFirstChild("Gift_Notification")
				local frame = gn and gn:FindFirstChild("Frame")
				if frame then for _, c in ipairs(frame:GetChildren()) do c:Destroy() end end
				log("Gift diterima ✓ (fallback remote)")
			end
		end)
	else
		warn("[CeszParadise] GiftPet/AcceptPetGift remote tidak ketemu — auto accept gift nonaktif.")
	end

	----------------------------------------------------------------- AUTO ACCEPT TRADE
	-- 1) Terima AJAKAN masuk: SendRequest.OnClientEvent(reqId, sender) -> RespondRequest(reqId,true)
	if SendRequest and RespondRequest then
		pcall(function()
			SendRequest.OnClientEvent:Connect(function(requestId, senderPlayer)
				if not CFG.acceptTrades then return end
				log("Auto-terima ajakan trade dari " .. tostring(senderPlayer and senderPlayer.Name or "?"))
				task.wait(0.3)
				pcall(function() RespondRequest:FireServer(requestId, true) end)
			end)
		end)
	end

	-- 2) Di window trade masuk: auto Accept (pas cooldown habis) -> tunggu lawan -> Confirm.
	--    Penerima ngasih kosong. Guard: jangan ganggu Automation Trade kita sendiri.
	if TC and TC.OnTradeCreated and Accept and Confirm then
		TC.OnTradeCreated:Connect(function()
			if not CFG.acceptTrades then return end
			if ctx.state.tradeRunning then return end -- kita lagi jadi pengirim, jangan diganggu
			task.spawn(function()
				log("Window trade masuk — auto accept + confirm.")
				-- auto accept: spam pelan sampai status KITA jadi Accepted (cooldown habis)
				local myOk, a0 = false, os.clock()
				repeat
					pcall(function() Accept:FireServer() end)
					task.wait(1)
					local s = ctx.myState and ctx.myState(ctx.replicatorData())
					if s == "Accepted" or s == "Confirmed" then myOk = true; break end
				until (not (TC and TC.CurrentTradeReplicator)) or (os.clock() - a0) > 20
				if not myOk or not (TC and TC.CurrentTradeReplicator) then return end

				-- tunggu lawan accept
				local t0 = os.clock()
				local otherOk = false
				repeat
					task.wait(0.5)
					if ctx.otherAccepted and ctx.otherAccepted(ctx.replicatorData()) then otherOk = true; break end
				until (not (TC and TC.CurrentTradeReplicator)) or (os.clock() - t0) > 60
				if not otherOk or not (TC and TC.CurrentTradeReplicator) then return end

				-- confirm sampai trade tertutup
				t0 = os.clock()
				repeat
					pcall(function() Confirm:FireServer() end)
					task.wait(1.5)
				until (not (TC and TC.CurrentTradeReplicator)) or (os.clock() - t0) > 15
				log("Trade masuk selesai (confirmed).")
			end)
		end)
	end
end
