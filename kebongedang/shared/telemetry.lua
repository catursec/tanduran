--[[ telemetry.lua — Kirim heartbeat & inventory ke Discord Webhook.
     Data yang dikirim sama seperti versi API, tapi tujuannya ke Discord. ]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

----------------------------------------------------------------- CONFIG
local WEBHOOK_URL = "https://discord.com/api/webhooks/1547669429477838968/AoH8_C5jvnD36F6uEnf_pThQfYnlF29Femi8O2noNUGtH7pDeQq1A9buA7P-30oXqn_O"  -- ⭐ ISI DENGAN URL WEBHOOK DISCORD KAMU
local HEARTBEAT_INTERVAL = 5    -- detik
local INVENTORY_INTERVAL = 90   -- detik
local API_KEY = ""              -- kosongkan, tidak dipakai lagi
local SCRIPT_NAME = "CeszParadiseHub"
local SCRIPT_VERSION = "1.0.0"

----------------------------------------------------------------- state
local sessionStart = os.time()
local stats = {
    heartbeats = 0,
    inventoryReports = 0,
    errors = 0,
    disconnects = 0,
}

----------------------------------------------------------------- util
local function getExecutor()
    if syn then return "Synapse"
    elseif fluxus then return "Fluxus"
    elseif secure_call then return "Script-Ware"
    elseif KRNL_LOADED then return "Krnl"
    elseif is_sirhurt_closure then return "SirHurt"
    elseif getexecutorname then return getexecutorname()
    else return "Unknown"
    end
end

-- Kirim payload ke Discord (via executor request)
local function sendWebhook(payload)
    if not WEBHOOK_URL or WEBHOOK_URL == "" then return false end

    local reqFn = (syn and syn.request) or (http and http.request) or http_request or request
    if not reqFn then
        warn("[Telemetry] Executor tidak support HTTP request")
        return false
    end

    local body = HttpService:JSONEncode(payload)

    -- Coba langsung dulu, kalau gagal pakai proxy
    local urls = {
        WEBHOOK_URL,
        WEBHOOK_URL:gsub("discord.com/api/webhooks/", "webhook.lewis.es/api/webhooks/")
    }

    for _, url in ipairs(urls) do
        local ok, res = pcall(function()
            return reqFn({
                Url = url,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body,
            })
        end)
        if ok and res and (res.StatusCode == 200 or res.StatusCode == 204) then
            return true
        end
    end
    return false
end

----------------------------------------------------------------- payload builder
local function baseFields()
    return {
        { name = "👤 Profile :", value = ("> Username: `%s`\n> UserId: `%s`\n> Display: `%s`"):format(
            LP.Name, tostring(LP.UserId), LP.DisplayName), inline = false },
        { name = "🎮 Server :", value = ("> PlaceId: `%s`\n> JobId: `%s`\n> Executor: `%s`"):format(
            tostring(game.PlaceId), tostring(game.JobId), getExecutor()), inline = false },
        { name = "⚙️ Script :", value = ("> Name: `%s`\n> Version: `%s`\n> Branch: `%s`"):format(
            SCRIPT_NAME, SCRIPT_VERSION, (getgenv and getgenv().GAG_BRANCH) or "main"), inline = false },
    }
end

local function buildHeartbeatPayload()
    local fields = baseFields()
    table.insert(fields, {
        name = "💓 Heartbeat :",
        value = ("> Session: `%s`\n> Heartbeats: `%d`\n> Errors: `%d`\n> Disconnects: `%d`"):format(
            ("%dh %dm %ds"):format(
                math.floor((os.time() - sessionStart) / 3600),
                math.floor(((os.time() - sessionStart) % 3600) / 60),
                (os.time() - sessionStart) % 60
            ),
            stats.heartbeats, stats.errors, stats.disconnects),
        inline = false
    })

    return {
        username = SCRIPT_NAME .. " Telemetry",
        avatar_url = "https://i.pinimg.com/736x/52/0e/d5/520ed52b650b318e20e9460eca77ced8.jpg",
        embeds = {{
            title = "💓 Heartbeat",
            color = 3447003, -- biru
            fields = fields,
            footer = { text = os.date("%B %d | %I:%M %p") },
        }}
    }
end

local function buildInventoryPayload()
    -- Ambil data inventory
    local petCount, eggCount, itemCount = 0, 0, 0
    local petsList = {}
    local eggsList = {}
    local bp = LP:FindFirstChildOfClass("Backpack")
    local char = LP.Character

    local function scan(container)
        if not container then return end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                if tool:GetAttribute("PET_UUID") then
                    petCount = petCount + 1
                    local petName = tool:GetAttribute("f") or tool.Name
                    petsList[petName] = (petsList[petName] or 0) + 1
                elseif tool.Name:find("Egg") then
                    eggCount = eggCount + 1
                    local _, cnt = tool.Name:match("^(.-)%s*x(%d+)$")
                    local qty = tonumber(cnt) or 1
                    local base = tool.Name:gsub("%s*x%d+$", "")
                    eggsList[base] = (eggsList[base] or 0) + qty
                else
                    itemCount = itemCount + 1
                end
            end
        end
    end

    scan(bp)
    scan(char)

    -- Format daftar pet
    local petLines = {}
    local petKeys = {}
    for k in pairs(petsList) do petKeys[#petKeys + 1] = k end
    table.sort(petKeys)
    for _, k in ipairs(petKeys) do
        petLines[#petLines + 1] = ("• %s x%d"):format(k, petsList[k])
    end
    local petText = #petLines > 0 and table.concat(petLines, "\n"):sub(1, 1000) or "*Tidak ada pet*"

    -- Format daftar egg
    local eggLines = {}
    local eggKeys = {}
    for k in pairs(eggsList) do eggKeys[#eggKeys + 1] = k end
    table.sort(eggKeys)
    for _, k in ipairs(eggKeys) do
        eggLines[#eggLines + 1] = ("• %s x%d"):format(k, eggsList[k])
    end
    local eggText = #eggLines > 0 and table.concat(eggLines, "\n"):sub(1, 1000) or "*Tidak ada egg*"

    local fields = baseFields()
    table.insert(fields, {
        name = "🎒 Inventory :",
        value = ("> Pets: `%d`\n> Eggs: `%d`\n> Items: `%d`"):format(petCount, eggCount, itemCount),
        inline = false
    })
    table.insert(fields, {
        name = "🐾 Pets :",
        value = petText,
        inline = false
    })
    table.insert(fields, {
        name = "🥚 Eggs :",
        value = eggText,
        inline = false
    })

    return {
        username = SCRIPT_NAME .. " Telemetry",
        avatar_url = "https://i.pinimg.com/736x/52/0e/d5/520ed52b650b318e20e9460eca77ced8.jpg",
        embeds = {{
            title = "🎒 Inventory Report",
            color = 3066993, -- hijau
            fields = fields,
            footer = { text = os.date("%B %d | %I:%M %p") },
        }}
    }
end

----------------------------------------------------------------- events
local function reportDisconnect(reason)
    stats.disconnects = stats.disconnects + 1
    local fields = baseFields()
    table.insert(fields, {
        name = "⚠️ Disconnect :",
        value = ("> Reason: `%s`\n> Total Disconnects: `%d`"):format(tostring(reason), stats.disconnects),
        inline = false
    })
    sendWebhook({
        username = SCRIPT_NAME .. " Telemetry",
        embeds = {{
            title = "⚠️ Disconnect Detected",
            color = 15158332, -- merah
            fields = fields,
            footer = { text = os.date("%B %d | %I:%M %p") },
        }}
    })
end

local function reportError(err)
    stats.errors = stats.errors + 1
    local fields = baseFields()
    table.insert(fields, {
        name = "❌ Error :",
        value = ("> Error: `%s`\n> Total Errors: `%d`"):format(tostring(err):sub(1, 500), stats.errors),
        inline = false
    })
    sendWebhook({
        username = SCRIPT_NAME .. " Telemetry",
        embeds = {{
            title = "❌ Error Report",
            color = 15158332,
            fields = fields,
            footer = { text = os.date("%B %d | %I:%M %p") },
        }}
    })
end

----------------------------------------------------------------- loops
local function startHeartbeat()
    task.spawn(function()
        while true do
            stats.heartbeats = stats.heartbeats + 1
            pcall(function() sendWebhook(buildHeartbeatPayload()) end)
            task.wait(HEARTBEAT_INTERVAL)
        end
    end)
end

local function startInventoryReporter()
    task.spawn(function()
        while true do
            stats.inventoryReports = stats.inventoryReports + 1
            pcall(function() sendWebhook(buildInventoryPayload()) end)
            task.wait(INVENTORY_INTERVAL)
        end
    end)
end

local function watchDisconnect()
    pcall(function()
        local GuiService = game:GetService("GuiService")
        GuiService.ErrorMessageChanged:Connect(function()
            task.wait(1)
            reportDisconnect("ErrorMessageChanged")
        end)
    end)
end

----------------------------------------------------------------- PUBLIC API
local telemetry = {}

function telemetry.start()
    if not WEBHOOK_URL or WEBHOOK_URL == "" then
        warn("[Telemetry] WEBHOOK_URL kosong, telemetry tidak aktif.")
        return
    end
    startHeartbeat()
    startInventoryReporter()
    watchDisconnect()
    -- Kirim laporan awal
    pcall(function() sendWebhook(buildHeartbeatPayload()) end)
end

function telemetry.reportError(err)
    pcall(function() reportError(err) end)
end

function telemetry.reportDisconnect(reason)
    pcall(function() reportDisconnect(reason) end)
end

function telemetry.setWebhookUrl(url)
    WEBHOOK_URL = url
end

-- ⭐ Bungkus jadi function biar cocok dengan pemanggilan di init.lua
-- init.lua memanggil: tchunk()(target)
return function(target)
    -- target = "garden" / "trade"
    telemetry.start()
    return telemetry
end
