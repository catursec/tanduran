--[[ sender.lua — Helper kirim webhook Discord dengan bypass proxy. ]]
local HttpService = game:GetService("HttpService")

local function sendWebhook(url, payload, ctx)
	if not url or url == "" then return end

	-- Trim leading and trailing whitespace
	local cleanUrl = url:match("^%s*(.-)%s*$")
	if not cleanUrl or cleanUrl == "" then return end

	-- Nama & avatar pengirim webhook (override default). Semua notif tampil "CeszParadiseHub".
	if type(payload) == "table" then
		if not payload.username then payload.username = "CeszParadise" end
		if not payload.avatar_url then payload.avatar_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png" end
	end
	
	-- Gunakan proxy jika menggunakan HttpService standard karena Discord memblokir Roblox UA
	local proxiedUrl = cleanUrl:gsub("discord.com/api/webhooks/", "webhook.lewis.es/api/webhooks/")
	proxiedUrl = proxiedUrl:gsub("discordapp.com/api/webhooks/", "webhook.lewis.es/api/webhooks/")
	
	local jsonPayload = HttpService:JSONEncode(payload)

	-- Kirim di thread TERPISAH (fire-and-forget) supaya request HTTP yg blocking
	-- (~100-500ms) TIDAK nge-freeze loop automation yg manggil -> cegah stutter.
	task.spawn(function()
	local sent = false
	local reqErr = ""

	-- 1. Coba gunakan executor HTTP request (client-side, bypass blocks)
	-- Mendukung baik key uppercase maupun lowercase untuk menjamin kompatibilitas 100% executor
	local reqFn = (syn and syn.request) or (http and http.request) or http_request or request
	if reqFn then
		local success, res = pcall(function()
			return reqFn({
				Url = cleanUrl,
				url = cleanUrl,
				Method = "POST",
				method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
					["content-type"] = "application/json"
				},
				headers = {
					["Content-Type"] = "application/json",
					["content-type"] = "application/json"
				},
				Body = jsonPayload,
				body = jsonPayload
			})
		end)
		if success and res then
			if res.StatusCode == 200 or res.StatusCode == 204 then
				sent = true
			else
				reqErr = "StatusCode: " .. tostring(res.StatusCode) .. " - " .. tostring(res.Body or "No response body")
			end
		else
			reqErr = tostring(res or "Unknown executor request error")
		end
	else
		reqErr = "Executor tidak memiliki fungsi request/http_request"
	end

	-- 2. Fallback ke HttpService:PostAsync (menggunakan proxy) jika executor request gagal atau tidak tersedia
	if not sent then
		local success, err = pcall(function()
			HttpService:PostAsync(proxiedUrl, jsonPayload, Enum.HttpContentType.ApplicationJson)
		end)
		if success then
			sent = true
		else
			local errMsg = "Fallback failed: " .. tostring(err) .. " | Exec error: " .. reqErr
			warn("[AllegiaanGarden Webhook] " .. errMsg)
			if ctx and ctx.log then
				ctx.log("[Webhook Error] " .. errMsg)
			end
		end
	end
	end)
end

return sendWebhook
