--[[
	GAG Hub — Router
	Satu entry point untuk dua server berbeda. Jalankan:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/catursec/tanduran//main/GAGSeller/init.lua"))()

	Router mendeteksi PlaceId lalu memuat app yang sesuai:
	  - Trade World  -> GAGSeller/trade/init.lua   (fitur seller sekarang)
	  - selain itu   -> GAGSeller/garden/init.lua  (fitur garden)
--]]

-- Branch: "main" = production. Override buat dev: getgenv().GAG_BRANCH = "dev"
local branch = (getgenv and getgenv().GAG_BRANCH) or _G.GAG_BRANCH or "main"
local ROOT = "https://raw.githubusercontent.com/catursec/tanduran/" .. branch .. "/kebongedang"

-- PlaceId server Trade World.
local TRADE_WORLD_PLACE = 129954712878723

-- Pilih sub-app. Default: apa pun yang BUKAN Trade World dianggap Garden.
local target = (game.PlaceId == TRADE_WORLD_PLACE) and "trade" or "garden"

-- Telemetry ke dashboard web (heartbeat + inventory). Logika di modul terpisah biar loader tetap bersih.
pcall(function()
	local tchunk = loadstring(game:HttpGet(ROOT .. "/shared/telemetry.lua?t=" .. os.time()), "@shared/telemetry.lua")
	if tchunk then tchunk()(target) end
end)

local url = ROOT .. "/" .. target .. "/init.lua?t=" .. os.time()
local ok, src = pcall(function() return game:HttpGet(url) end)
if not ok or type(src) ~= "string" or src == "" then
	warn(("[GAGHub] gagal ambil app '%s' (PlaceId=%s): %s"):format(target, tostring(game.PlaceId), tostring(src)))
	return
end

local chunk, err = loadstring(src, "@" .. target .. "/init.lua")
if not chunk then
	warn(("[GAGHub] gagal compile app '%s': %s"):format(target, tostring(err)))
	return
end

print(("[GAGHub] PlaceId=%s -> memuat app '%s'"):format(tostring(game.PlaceId), target))
return chunk()
