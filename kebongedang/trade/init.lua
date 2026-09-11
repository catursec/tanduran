--[[
	GAG Seller — Trade World (Grow a Garden)  [Refactored / Modular]
	App TRADE WORLD. Biasanya tidak dijalankan langsung — dipanggil oleh router
	GAGSeller/init.lua saat PlaceId == Trade World. Bisa juga dijalankan manual:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/catursec/tanduran/trade/init.lua"))()

	init.lua bertugas:
	  1. Membangun satu tabel `ctx` yang dibagi ke semua modul.
	  2. Me-load tiap modul secara berurutan (HttpGet raw GitHub + loadstring).
	  3. Menjalankan app.lua sebagai langkah terakhir.

	Setiap modul berbentuk:  return function(ctx) ... end
	dan menambahkan field/fungsi ke `ctx` supaya modul lain bisa memakainya.

	Struktur logika 100% sama dengan GAGSeller.lua single-file, hanya dipecah.
--]]

-- Base URL raw GitHub tempat semua modul berada. Branch bisa di-override buat dev:
--   getgenv().GAG_BRANCH = "dev"  (default "main" = production)
local branch = (getgenv and getgenv().GAG_BRANCH) or _G.GAG_BRANCH or "main"
local BASE = "https://raw.githubusercontent.com/catursec/tanduran/" .. branch .. "/kebongedang/trade"

--------------------------------------------------------------------- loader
-- Selalu load dari bundle.lua (1 HttpGet, kilat). Workflow: edit modul ->
-- `node tools/bundle.js` -> push. Fallback per-modul di fungsi fetch kalau
-- bundle gagal / ada modul yg belum ke-bundle.
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
		print("[CeszParadiseHub/trade] ✓ Bundle loaded sukses (Mode Kilat)")
	else
		warn("[CeszParadiseHub/trade] ⚠ Bundle gagal dimuat, beralih ke download per-modul HTTP (lambat)...")
	end
end

local function fetch(relPath)
	if FILES and FILES[relPath] then return FILES[relPath] end
	local ok, src = pcall(function() return game:HttpGet(BASE .. "/" .. relPath) end)
	if ok and type(src) == "string" then return src end
	return nil
end

local function loadModule(relPath)
	local src = fetch(relPath)
	if type(src) ~= "string" or src == "" then
		error(("[GAGSeller] gagal ambil %s"):format(relPath))
	end
	local chunk, err = loadstring(src, "@" .. relPath)
	if not chunk then
		error(("[GAGSeller] gagal compile %s: %s"):format(relPath, tostring(err)))
	end
	local mod = chunk()
	if type(mod) ~= "function" then
		error(("[GAGSeller] modul %s harus 'return function(ctx)'"):format(relPath))
	end
	return mod
end

--------------------------------------------------------------------- context
local ctx = {
	BASE  = BASE,
	state = {
		running        = false,
		gui            = nil,
		listedSet      = {},
		currentLoopId  = 0,
		lastProcessedTx = {},
		logLines       = {},
	},
	ui   = {},   -- referensi elemen GUI (diisi window.lua / pages.lua)
	reg  = {},   -- opsi dropdown (diisi registry.lua)
	deps = {},   -- module require game (diisi services.lua)
}

-- Fungsi util global kecil yang dibutuhkan banyak modul.
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

--------------------------------------------------------------------- boot
-- Urutan load penting: modul bawah bergantung pada modul di atasnya.
-- Modul dikelompokkan per-menu: tiap fitur folder sendiri, infra bersama di core/.
local MODULES = {
	"modules/core/services.lua",  -- game services + deps require
	"modules/core/registry.lua",  -- PET/MUT/SKIN options
	"modules/core/config.lua",    -- CFG default + load/persist state
	"modules/core/websync.lua",   -- sync options/config ke dashboard web (butuh ctx.reg)
	"ui/theme.lua",               -- warna + helper Instance
	"modules/sell/booth.lua",     -- booth claim / tokens
	"modules/core/webhook.lua",   -- webhook + sell listener
	"modules/sell/listing.lua",   -- listPass / mainLoop / util
	"ui/components.lua",          -- toggle/input/dropdown/accordion/tab
	"ui/window.lua",              -- jendela utama + log + status
	"modules/sell/relocate.lua",  -- auto relocate sell (server-hop kalau booth idle)
	"modules/buy/sniper.lua",     -- auto snipe / auto buy (tab Buy)
	"ui/pages.lua",               -- halaman Sell/Buy/Inventory/Misc
	"app.lua",                    -- init akhir + supervisor loop
}

-- Modul kritis yang kalau error harus stop total (GUI belum ada, tidak bisa log ke layar).
local CRITICAL = {
	["modules/core/services.lua"] = true,
	["modules/core/registry.lua"] = true,
	["modules/core/config.lua"]   = true,
	["ui/theme.lua"]              = true,
}

for _, rel in ipairs(MODULES) do
	local ok, err = pcall(function()
		loadModule(rel)(ctx)
	end)
	if not ok then
		warn(("[GAGHub] ❌ error eksekusi %s: %s"):format(rel, tostring(err)))
		if CRITICAL[rel] then
			warn("[GAGHub] modul kritis gagal — hub berhenti.")
			return nil
		end
		-- modul non-kritis: lanjut tapi catat error
	else
		-- Uncomment baris di bawah kalau mau debug detail per modul:
		-- print(("[GAGHub] ✓ %s"):format(rel))
	end
end

return ctx
