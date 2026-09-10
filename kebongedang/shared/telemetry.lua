--[[
	telemetry.lua — kirim heartbeat + inventory ke dashboard web (AllegiaantHUB Monitor).
	Dipanggil router (init.lua) dengan: loadstring(...)()(target)
	Jalan di THREAD TERPISAH (task.spawn), semua di-pcall, non-blocking:
	NGGAK ganggu loop PnP / automation lain.

	- Heartbeat tiap HEARTBEAT_EVERY dtk (identitas: userId/username/placeId/jobId).
	- Inventory tiap INVENTORY_EVERY dtk (pets/eggs/items) — cuma relevan di garden.
]]

local REPORT_URL = "https://api.allegiaant.my.id/api/report"
local API_KEY    = "ae3858d4a2def3306d6cbff26ff2bd72eee9319b1aae27d1"
local HEARTBEAT_EVERY = 5    -- detik (payload kecil; biar DC kedeteksi cepet buat auto-reconnect)
local INVENTORY_EVERY = 90   -- detik (kelipatan HEARTBEAT_EVERY biar rapi)

return function(target)
	task.spawn(function()
		local Players     = game:GetService("Players")
		local HttpService = game:GetService("HttpService")
		local RS          = game:GetService("ReplicatedStorage")

		local LP = Players.LocalPlayer
		if not LP then return end

		-- fungsi HTTP executor (POST dgn header custom)
		local httpReq = (syn and syn.request) or (http and http.request) or http_request or request
		if not httpReq then return end

		local DataService
		pcall(function() DataService = require(RS.Modules.DataService) end)

		-- map kode mutasi -> nama proper (mis. "A"->"Nightmare", "c"->"Rainbow")
		local EnumToMut = {}
		pcall(function()
			EnumToMut = require(RS.Data.PetRegistry.PetMutationRegistry).EnumToPetMutation or {}
		end)

		-- RAP (nilai Token pasar) — via TokenRAPController:GetRAPAsync("Pet", entry).
		-- Cuma ada di Trade World. Cache per-id (tipe+mutasi+tier) biar ga spam server.
		local RAPUtil, RAPCtrl
		pcall(function() RAPUtil = require(RS.Modules.TradeTokens.TokenRAPUtil) end)
		pcall(function()
			RAPCtrl = require(RS.Modules.TradeTokens.TokenRAPController)
			if RAPCtrl and RAPCtrl.Start then pcall(function() RAPCtrl:Start() end) end
		end)
		local rapCache = {}   -- id -> { v = number, t = os.clock() }
		local RAP_TTL = 300   -- detik; RAP jarang berubah
		local function getRap(entry)
			if not (RAPUtil and RAPCtrl) then return nil end
			local ok, id = pcall(function() return RAPUtil.GetItemId("Pet", entry) end)
			if not ok or type(id) ~= "string" or id == "Unknown" then return nil end
			local c = rapCache[id]
			if c and (os.clock() - c.t) < RAP_TTL then return c.v end
			local ok2, rap = pcall(function() return RAPCtrl:GetRAPAsync("Pet", entry) end)
			if ok2 and type(rap) == "number" then
				rapCache[id] = { v = rap, t = os.clock() }
				return rap
			end
			return c and c.v or nil
		end

		-- snapshot inventory (best-effort, semua pcall). Relevan di garden.
		local function buildInventory()
			local inv = { pets = {}, eggs = {}, items = {}, stats = {} }

			pcall(function()
				if not DataService then return end
				local d = DataService:GetData(); if not d then return end
				local pd = d.PetsData
				local petInv = pd and pd.PetInventory and pd.PetInventory.Data or {}
				local eq = pd and pd.EquippedPets or {}
				local eqSet = {}; for _, u in ipairs(eq) do eqSet[u] = true end
				local n = 0
				for uuid, v in pairs(petInv) do
					local pdata = v.PetData or {}
					local lvl = pdata.Level or 0
					local mut = pdata.MutationType
					if mut and mut ~= "" then mut = EnumToMut[mut] or mut else mut = nil end
					if mut == "Normal" then mut = nil end
					inv.pets[#inv.pets + 1] = {
						type       = v.PetType or "?",
						weight     = (pdata.BaseWeight or 0) * (1 + 0.1 * lvl), -- berat current (ikut age) buat tampilan
						baseWeight = pdata.BaseWeight or 0,                     -- berat dasar (bebas age) buat filter listing (= weightOf script)
						level      = lvl,
						mutation   = mut,
						equipped   = eqSet[uuid] or false,
						favorite   = pdata.IsFavorite and true or false,
						rap        = getRap(v), -- nilai Token (RAP pasar), nil di garden / kalau gagal
					}
					n = n + 1
				end
				inv.stats.petCount = n
				if pd and pd.MutableStats then
					inv.stats.maxPets = tonumber(pd.MutableStats.MaxPetsInInventory) or nil
				end
				-- saldo Trade Token (koin hijau — UI "Buy Tokens")
				if d.TradeData then inv.stats.tokens = tonumber(d.TradeData.Tokens) or 0 end
			end)

			-- eggs + seeds/gear/crops dari Backpack (Tool, skip pet uuid)
			pcall(function()
				local bp = LP:FindFirstChildOfClass("Backpack"); if not bp then return end
				for _, tool in ipairs(bp:GetChildren()) do
					if tool:IsA("Tool") and not tool:GetAttribute("PET_UUID") then
						local nm = tostring(tool.Name)
						local base, cnt = nm:match("^(.-)%s*x(%d+)$")
						base = base or nm
						cnt = tonumber(cnt) or 1
						if nm:find("Egg") then
							inv.eggs[#inv.eggs + 1] = { name = base, count = cnt, category = "egg" }
						else
							local cat = base:find("Seed") and "seed" or "crop"
							inv.items[#inv.items + 1] = { name = base, count = cnt, category = cat }
						end
					end
				end
			end)

			return inv
		end

		local function post(withInv)
			local body = {
				userId   = LP.UserId,
				username = LP.Name,
				placeId  = game.PlaceId,
				jobId    = game.JobId,
			}
			if withInv then body.inventory = buildInventory() end
			pcall(function()
				httpReq({
					Url = REPORT_URL,
					Method = "POST",
					Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = API_KEY },
					Body = HttpService:JSONEncode(body),
				})
			end)
		end

		-- laporan pertama langsung bawa inventory
		post(true)

		-- Ditandai true begitu kena error/disconnect → STOP heartbeat (biar API liat offline,
		-- ga ketipu "online" padahal Roblox lagi nampilin dialog Disconnected).
		local disconnected = false
		-- kapan terakhir TELEPORT (hop/relocate/snipe). Dipakai buat bedain "hop" vs "disconnect".
		local lastTeleport = -999

		-- Auto-reconnect signal: begitu Roblox nampilin error/disconnect apapun,
		-- lapor ke API biar agent Termux langsung relaunch (semua error → relog).
		-- App masih hidup pas dialog error muncul, jadi request masih bisa kekirim.
		pcall(function()
			local GuiService = game:GetService("GuiService")
			local TeleportService = game:GetService("TeleportService")
			local sent = false
			-- guard: teleport gagal (server full 770, dll) BUKAN disconnect — jangan lapor.
			local lastTeleFail = -999
			pcall(function()
				TeleportService.TeleportInitFailed:Connect(function()
					lastTeleFail = os.clock()
				end)
			end)
			local function reportError(reason)
				-- SELALU stop heartbeat pas ada dialog error → biar DC beneran (288/277/dll)
				-- ke-detect offline. Pas hopping tetep keliatan online krn suppress refresh last_seen,
				-- dan telemetry server baru resume heartbeat. Jadi ini aman buat sniper.
				disconnected = true
				-- Signal (relaunch CEPAT) di-skip kalau barusan teleport (hop sukses/gagal) —
				-- biar sniper yg lagi hop ga ke-relaunch. DC beneran tetep ke-handle via offline+patience.
				if os.clock() - lastTeleFail < 6 then return end
				if os.clock() - lastTeleport < 8 then return end
				if sent then return end
				sent = true
				pcall(function()
					httpReq({
						Url = "https://api.allegiaant.my.id/api/agent/signal",
						Method = "POST",
						Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = API_KEY },
						Body = HttpService:JSONEncode({
							userId = LP.UserId,
							reason = tostring(reason),
						}),
					})
				end)
			end
			-- 1) event resmi: error message berubah (dialog Disconnected muncul)
			pcall(function()
				GuiService.ErrorMessageChanged:Connect(function()
					reportError("ErrorMessageChanged")
				end)
			end)
			-- 2) cadangan: pantau prompt error di CoreGui muncul
			pcall(function()
				local CoreGui = game:GetService("CoreGui")
				CoreGui.DescendantAdded:Connect(function(d)
					local n = tostring(d.Name):lower()
					if n:find("errorprompt") or n:find("errortitle") then
						reportError("CoreGuiErrorPrompt")
					end
				end)
			end)
		end)

		-- Teleport disengaja (relocate/hop/snipe) → kasih tau agent biar SKIP relaunch,
		-- karena putus dari server lama itu normal, bukan DC.
		pcall(function()
			LP.OnTeleport:Connect(function(state)
				if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then
					lastTeleport = os.clock() -- tandai lagi teleport → reportError skip (bukan disconnect)
					pcall(function()
						httpReq({
							Url = "https://api.allegiaant.my.id/api/agent/suppress",
							Method = "POST",
							Headers = { ["Content-Type"] = "application/json", ["x-api-key"] = API_KEY },
							Body = HttpService:JSONEncode({ userId = LP.UserId, seconds = 90 }),
						})
					end)
				end
			end)
		end)

		local elapsed = 0
		while Players.LocalPlayer == LP do
			task.wait(HEARTBEAT_EVERY)
			if Players.LocalPlayer ~= LP then break end
			-- putus (dari hook error di atas) → stop heartbeat biar agent tau offline & relog.
			-- CUMA dari flag `disconnected` (event-driven), JANGAN scan CoreGui (elemen ErrorPrompt
			-- selalu ada walau ke-hide → bikin false stop → relaunch session sehat).
			if disconnected then break end
			elapsed = elapsed + HEARTBEAT_EVERY
			local withInv = elapsed >= INVENTORY_EVERY
			if withInv then elapsed = 0 end
			post(withInv)
		end
	end)
end
