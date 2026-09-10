--[[ webhook/elephant.lua — Discord webhook untuk Automation Elephant.
     Konsep:
       - sendEnabled: kirim 1 pesan (Boosting Statistics KOSONG), tangkap message id.
       - onFinished:  tiap pet target selesai (>= max KG), tambah ke tally lalu
                      EDIT pesan yang sama (boosting stats keisi bertahap).
     Pakai executor request() langsung (POST ?wait=true buat dapat id, PATCH buat edit). ]]
local HttpService = game:GetService("HttpService")
local elephantWebhook = {}

local USERNAME = "CeszParadise"
local AVATAR = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png"

local function bracketLabel(w)
	local lo = math.floor(w * 10) / 10
	return string.format("%.2f-%.2f KG", lo + 0.01, lo + 0.09)
end

-- Format durasi detik -> "Xh Ym Zs" / "Xm Ys" / "Ys". nil/false -> "-" (start ga kecatat).
local function fmtDuration(sec)
	if sec == nil then return "-" end
	sec = math.max(0, math.floor(tonumber(sec) or 0))
	if sec >= 3600 then return string.format("%dh %dm %ds", math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60) end
	if sec >= 60 then return string.format("%dm %ds", math.floor(sec / 60), sec % 60) end
	return string.format("%ds", sec)
end

local function reqFn()
	return (syn and syn.request) or (http and http.request) or http_request or request
end

-- Sumber config: override Growth (ctx.state.elephantCfgOverride) kalau ada, else CFG standalone.
local function ecfg(ctx)
	local o = ctx.state and ctx.state.elephantCfgOverride
	if o then return o.team or {}, o.types or {}, o.weight or 5.5 end
	local CFG = ctx.CFG
	return CFG.elephantTeamUuids or {}, CFG.elephantPetTypes or {}, CFG.elephantTargetWeight or 5.5
end

-- Scan inventory live: pisah pet target jadi 'selesai' (>= target KG) dan 'sisa' (< target KG).
-- Yang selesai dikelompokkan per type + bracket berat (byType), plus total maxCount.
-- Sumber angka Boosting Statistics & Pets at Max KG = SEMUA pet target yang sudah max di data,
-- bukan cuma yang selesai selama sesi ini (tahan reload / re-enable).
local function scanTargets(ctx)
	local ok, d = pcall(function() return ctx.deps.DataService:GetData() end)
	local inv = ok and d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}
	local _, tt, tw = ecfg(ctx)
	local byType, maxCount, remains = {}, 0, 0
	for _, v in pairs(inv) do
		if v.PetType and tt[v.PetType] and not (v.PetData or {}).IsFavorite then
			local w = (v.PetData or {}).BaseWeight or 0
			if w < tw then
				remains = remains + 1
			else
				maxCount = maxCount + 1
				local bt = byType[v.PetType]
				if not bt then bt = { total = 0, brackets = {}, order = {} }; byType[v.PetType] = bt end
				bt.total = bt.total + 1
				local lbl = bracketLabel(w)
				if not bt.brackets[lbl] then bt.brackets[lbl] = 0; bt.order[#bt.order + 1] = lbl end
				bt.brackets[lbl] = bt.brackets[lbl] + 1
			end
		end
	end
	return byType, maxCount, remains
end

local function buildPayload(ctx)
	local base = ctx.state.elephantBase or {}
	local byType, maxCount, remains = scanTargets(ctx)

	local typeKeys = {}
	for t in pairs(byType) do typeKeys[#typeKeys + 1] = t end
	table.sort(typeKeys)
	local lines = {}
	for _, t in ipairs(typeKeys) do
		local bt = byType[t]
		lines[#lines + 1] = string.format("**%s:** %d", t, bt.total)
		table.sort(bt.order)
		for _, lbl in ipairs(bt.order) do
			lines[#lines + 1] = string.format("\226\128\162 %s (%s): %d", t, lbl, bt.brackets[lbl])
		end
	end
	local boostText = #lines > 0 and table.concat(lines, "\n") or "*Belum ada pet selesai*"

	local desc = string.format(
		"**Profile :**\n> \240\159\145\164 Username : ||%s||\n\n" ..
		"**Teams :**\n> Elephant Team: `%s`\n\n" ..
		"**Target Types :**\n> `%s`\n\n" ..
		"**Boosting Statistics :**\n%s\n\n" ..
		"**Pets at Max KG :** `%d`\n" ..
		"**Remains Queue :** `%d`",
		ctx.LP.Name, base.teamText or "None", base.typesText or "None",
		boostText, maxCount, remains)
	if #desc > 4000 then desc = desc:sub(1, 3980) .. "\n... (truncated)" end

	return {
		username = USERNAME,
		avatar_url = AVATAR,
		embeds = {
			{
				title = "\240\159\147\138 Growth \226\128\162 Elephant Statistics",
				color = 3066993,
				description = desc,
				footer = { text = os.date("%B %d | %I:%M %p"), icon_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png" },
			}
		}
	}
end

-- Kirim saat enable: reset tally, kirim pesan (boosting kosong), simpan message id.
function elephantWebhook.sendEnabled(ctx)
	local CFG = ctx.CFG
	if not CFG.webhookUrl or CFG.webhookUrl == "" then return end

	-- base info (team + target types)
	local ok, d = pcall(function() return ctx.deps.DataService:GetData() end)
	local inv = ok and d and d.PetsData and d.PetsData.PetInventory and d.PetsData.PetInventory.Data or {}
	local teamSet, typesSet = ecfg(ctx)
	local teamCount, teamOrder = {}, {}
	for uuid in pairs(teamSet) do
		local v = inv[uuid]
		if v then
			local pt = v.PetType or "?"
			local mut = v.PetData and v.PetData.MutationType
			local mutName = (mut and ctx.reg and ctx.reg.mutDisplay) and ctx.reg.mutDisplay(mut) or mut
			local disp = (mut and mut ~= "" and mut ~= "Normal") and (tostring(mutName) .. " " .. pt) or pt
			if not teamCount[disp] then teamCount[disp] = 0; teamOrder[#teamOrder + 1] = disp end
			teamCount[disp] = teamCount[disp] + 1
		end
	end
	table.sort(teamOrder)
	local teamParts = {}
	for _, disp in ipairs(teamOrder) do teamParts[#teamParts + 1] = teamCount[disp] .. " " .. disp end

	local typesList = {}
	for t in pairs(typesSet) do typesList[#typesList + 1] = t end
	table.sort(typesList)

	ctx.state.elephantBase = {
		teamText = #teamParts > 0 and table.concat(teamParts, ", ") or "None",
		typesText = #typesList > 0 and table.concat(typesList, ", ") or "None",
	}
	ctx.state.elephantTally = { byType = {}, maxCount = 0 }
	ctx.state.elephantMsgId = nil

	-- POST ?wait=true buat dapat message id
	local f = reqFn()
	if not f then return end
	local url = CFG.webhookUrl
	local sep = url:find("?", 1, true) and "&" or "?"
	local body = HttpService:JSONEncode(buildPayload(ctx))
	local okReq, res = pcall(function()
		return f({
			Url = url .. sep .. "wait=true", Method = "POST",
			Headers = { ["Content-Type"] = "application/json" }, Body = body,
		})
	end)
	if okReq and res and res.Body then
		local okj, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if okj and type(data) == "table" and data.id then
			ctx.state.elephantMsgId = tostring(data.id)
		end
	end
end

-- Tiap pet target selesai (>= max KG): kirim/EDIT pesan. Angka dihitung live dari
-- data di buildPayload (scanTargets), jadi tidak perlu tally manual lagi.
function elephantWebhook.onFinished(ctx, petType, weight)
	local CFG = ctx.CFG
	if not CFG.webhookUrl or CFG.webhookUrl == "" then return end

	-- Mode POST (Growth: kirim pesan baru tiap pet selesai) ATAU edit pesan (standalone).
	local f = reqFn()
	if not f then return end
	local body = HttpService:JSONEncode(buildPayload(ctx))
	local postMode = ctx.state and ctx.state.elephantWebhookPost
	-- Request HTTP di thread terpisah (non-blocking) biar ga nge-freeze loop automation
	task.spawn(function()
		if ctx.state.elephantMsgId and not postMode then
			pcall(function()
				f({
					Url = CFG.webhookUrl .. "/messages/" .. ctx.state.elephantMsgId, Method = "PATCH",
					Headers = { ["Content-Type"] = "application/json" }, Body = body,
				})
			end)
		elseif ctx.sendWebhook then
			pcall(function() ctx.sendWebhook(CFG.webhookUrl, HttpService:JSONDecode(body), ctx) end)
		end
	end)
end

-- Kartu PER-PET saat 1 pet capai Max KG. Dikirim TIAP pet beres (pesan baru),
-- pelengkap statistik agregat. durationSec = nil -> "Duration: -" (start ga kecatat).
function elephantWebhook.sendFinished(ctx, petType, weight, mutation, age, durationSec)
	local CFG = ctx.CFG
	if not CFG.webhookUrl or CFG.webhookUrl == "" then return end
	local mutDisplay = (ctx.reg and ctx.reg.mutDisplay and ctx.reg.mutDisplay(mutation)) or mutation or "None"
	local _, _, remains = scanTargets(ctx)

	local payload = {
		username = USERNAME,
		avatar_url = AVATAR,
		embeds = {
			{
				title = "\240\159\144\152 Growth \226\128\162 Elephant", -- 🐘
				color = 3066993, -- Green
				fields = {
					{
						name = "Profile :",
						value = string.format("> Username : ||%s||", ctx.LP.Name),
						inline = false
					},
					{
						name = "Max KG Reached",
						value = string.format(
							"> Pet Type: `%s`\n" ..
							"> Mutation: `%s`\n" ..
							"> Weight: `%.2f KG`\n" ..
							"> Age: `%s`\n" ..
							"> Duration: `%s`\n" ..
							"> Remains Queue: `%s`",
							tostring(petType or "?"),
							tostring(mutDisplay),
							tonumber(weight) or 0,
							tostring(age or "-"),
							fmtDuration(durationSec),
							tostring(remains)
						),
						inline = false
					}
				},
				footer = {
					text = os.date("%B %d | %I:%M %p"),
					icon_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png"
				}
			}
		}
	}
	if ctx.sendWebhook then ctx.sendWebhook(CFG.webhookUrl, payload, ctx) end
end

return elephantWebhook
