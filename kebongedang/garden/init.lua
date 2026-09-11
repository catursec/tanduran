--[[
	CeszParadiseHub — GARDEN app (loader)
	Dipanggil router GAGSeller/init.lua saat berada di server Garden.
	Pola sama seperti trade/: tiap modul `return function(ctx)`, berbagi tabel ctx.
--]]

local branch = (getgenv and getgenv().GAG_BRANCH) or _G.GAG_BRANCH or "main"
local BASE = "https://raw.githubusercontent.com/catursec/tanduran/" .. branch .. "/kebongedang/garden"

-- Selalu load dari bundle.lua (1 HttpGet, kilat). Workflow: edit modul ->
-- `node tools/bundle.js` -> push. Kalau bundle gagal / ada modul yg belum
-- ke-bundle, fungsi fetch di bawah fallback ambil per-modul dari GitHub.
local FILES
do
	local ok, src = pcall(function() return game:HttpGet(BASE .. "/bundle.lua?t=" .. os.time()) end)
	if ok and type(src) == "string" and #src > 0 then
		local chunk = loadstring(src, "@bundle.lua")
		if chunk then
			local okr, tbl = pcall(chunk)
			if okr and type(tbl) == "table" then FILES = tbl end
		end
	end
	if FILES then
		print("[CeszParadiseHub/garden] ✓ Bundle loaded sukses (Mode Kilat)")
	else
		warn("[CeszParadiseHub/garden] ⚠ Bundle gagal dimuat, beralih ke download per-modul HTTP (lambat)...")
	end
end

-- Ambil source modul: dari bundle (memori) kalau ada, else HttpGet (dev/fallback).
local function fetch(relPath)
	if FILES and FILES[relPath] then return FILES[relPath] end
	local full = BASE .. "/" .. relPath .. "?t=" .. os.time()
	local ok, src = pcall(function() return game:HttpGet(full) end)
	if ok and type(src) == "string" then return src end
	return nil
end

local function loadModule(relPath)
	local src = fetch(relPath)
	if type(src) ~= "string" or src == "" then
		error(("[CeszParadiseHub/garden] gagal ambil %s"):format(relPath))
	end
	local chunk, err = loadstring(src, "@" .. relPath)
	if not chunk then
		error(("[CeszParadiseHub/garden] gagal compile %s: %s"):format(relPath, tostring(err)))
	end
	local mod = chunk()
	if type(mod) ~= "function" then
		error(("[CeszParadiseHub/garden] modul %s harus 'return function(ctx)'"):format(relPath))
	end
	return mod
end

local ctx = {
	BASE  = BASE,
	state = {
		tradeRunning = false,
		completed    = 0,
		status       = "IDLE",
		logLines     = {},
		gui          = nil,
	},
	ui   = {},
	reg  = {},
	deps = {},
}

function ctx.alive()
	return ctx.state.isAlive ~= false
end
function ctx.elevate()
	pcall(function()
		local f = setthreadidentity or setidentity
			or (syn and syn.set_thread_identity)
			or (getgenv and getgenv().setthreadidentity)
		if f then f(7) end
	end)
end

-- Logo AH buat tombol minimize. Download sekali, cache via getcustomasset (fallback: teks "AH").
function ctx.getLogo()
	if _G.__AH_LOGO ~= nil then return _G.__AH_LOGO or nil end
	local asset = false
	pcall(function()
		local gca = getcustomasset or getsynasset or (syn and syn.getcustomasset)
		if not (gca and writefile) then return end
		local path = "CeszParadiseHUB/logo_icon.png"
		if not (isfile and isfile(path)) then
			if makefolder and not (isfolder and isfolder("CeszParadiseHUB")) then makefolder("CeszParadiseHUB") end
			writefile(path, game:HttpGet("https://raw.githubusercontent.com/catursec/tanduran/" .. branch .. "/kebongedang/Logo/logo_icon.png"))
		end
		asset = gca(path) or false
	end)
	_G.__AH_LOGO = asset
	return asset or nil
end

-- Loader untuk file yang BUKAN pola return function(ctx) (mis. webhook helper/formatter).
-- Karena app di-load via HttpGet (bukan ModuleScript), require(script...) nggak jalan —
-- jadi file webhook di-fetch di sini dan hasilnya ditaruh di ctx.
local function loadRaw(relPath)
	local src = fetch(relPath)
	if type(src) ~= "string" then return nil end
	local chunk = loadstring(src, "@" .. relPath)
	if not chunk then return nil end
	local okr, val = pcall(chunk)
	return okr and val or nil
end
ctx.sendWebhook     = loadRaw("modules/core/webhook.lua")     -- function(url, payload, ctx)
ctx.webhookMutation = loadRaw("modules/mutation/webhook.lua") -- table {sendEnabled, sendSubmitted, sendClaimed}
ctx.webhookLeveling = loadRaw("modules/leveling/webhook.lua") -- table leveling webhook
ctx.webhookElephant = loadRaw("modules/elephant/webhook.lua") -- table elephant webhook
ctx.webhookCleanse  = loadRaw("modules/mutation/cleanse_webhook.lua") -- table cleanse/mutation webhook

-- Modul dikelompokkan per-menu: tiap fitur punya folder sendiri (varian = v1/v2),
-- infra bersama di modules/core/. Urutan load tetap dijaga (dependency).
local MODULES = {
	"modules/core/services.lua",
	"modules/core/registry.lua",
	"modules/core/config.lua",
	"ui/theme.lua",
	"modules/inventory/automation_trade.lua",
	"modules/inventory/automation_accept.lua",
	"modules/pet/automation_pickup_pet_v1.lua",
	"modules/pet/automation_pickup_pet_v2.lua",
	"modules/pet/automation_boost_pet.lua",
	"modules/shop/automation_shop.lua",
	"modules/shop/automation_merchant.lua",
	"modules/shop/premium_shop.lua",
	"modules/leveling/automation_leveling_v1.lua",
	"modules/leveling/automation_leveling_v2.lua",
	"modules/elephant/automation_elephant_v1.lua",
	"modules/elephant/automation_elephant_v2.lua",
	"modules/growth/automation_growth.lua",
	"modules/hatch/automation_hatch.lua",
	"modules/event/automation_beanstalk.lua",
	"modules/event/automation_beanstalk_hop.lua",
	"modules/farm/automation_reclaimer.lua",
	"modules/farm/automation_plants.lua",
	"modules/farm/automation_sprinkler.lua",
	"modules/farm/automation_water.lua",
	"modules/farm/automation_shovel.lua",
	"modules/farm/automation_collect.lua",
	"modules/farm/automation_favorite.lua",
	"modules/mutation/automation_mutation_machine.lua",
	"modules/mutation/automation_mutation.lua",
	"ui/components.lua",
	"modules/misc/esp_label.lua",
	"modules/misc/esp_inventory.lua",
	"modules/misc/player_mods.lua",
	"modules/misc/perf_mods.lua",
	"modules/misc/automation_reconnect.lua",
	"ui/window.lua",
	"ui/pages.lua",
	"app.lua",
}

for _, rel in ipairs(MODULES) do
	loadModule(rel)(ctx)
end

return ctx
