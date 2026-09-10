--[[ config.lua — konfigurasi default + persist/load state ke JSON.
     Mengisi: ctx.NUM_PROFILES, ctx.NUM_LISTINGS, ctx.CFG,
              ctx.persistState, ctx.loadState ]]
return function(ctx)
    local HttpService = ctx.Services.HttpService

    local NUM_PROFILES = 3
    local NUM_LISTINGS = 3
    local NUM_SNIPE    = 5

    local CFG = {
        autoSell         = false,
        autoClaim        = true,
        autoSwitchPortal = false,
        autoReconnect    = true,  -- auto rejoin kalau ke-kick/DC
        boothSkin        = "Default",
        profiles         = {},
        webhookUrl       = "",
        webhookEnabled   = false,
        relocateEnabled    = false,
        relocateIdleMin    = 20,
        relocateMinPlayers = 10,
        relocatePreferred  = 20,
        -- sniper / auto-buy
        snipeEnabled       = false,
        snipeHop           = true,  -- master enable hop
        snipeHopIndex      = true,  -- filter: hop by index (FindSellers / cari seller)
        snipeHopPlayer     = true,  -- filter: hop by player (server berdasarkan Min Players)
        snipeMinPop        = 25,   -- hop by player: server dgn pemain >= ini (set 1 = semua server)
        snipeRevisitSec    = 120,  -- jeda sebelum boleh balik ke server yang sama (detik)
        snipeProfiles      = {},
    }
    for i = 1, NUM_SNIPE do
        CFG.snipeProfiles[i] = { pets = {}, muts = {}, maxPrice = 0 }
    end
    for i = 1, NUM_PROFILES do
        CFG.profiles[i] = { listings = {} }
        for j = 1, NUM_LISTINGS do
            CFG.profiles[i].listings[j] = { pets = {}, muts = {}, minW = 0, maxW = 0, maxList = 0, price = 100 }
        end
    end

    -- Pastikan LocalPlayer dan UserId sudah siap (hindari nil)
    local Players = ctx.Services.Players or game:GetService("Players")
    local localPlayer = Players.LocalPlayer
    while not localPlayer do
        Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        localPlayer = Players.LocalPlayer
    end
    local userId = localPlayer.UserId

    -- Setiap clone punya file terpisah (contoh: trade_state_12345.json)
    local STATE_FILE = "trade_state_" .. tostring(userId) .. ".json"

    -- 1. Simpan langsung ke file akun ini saja
    local function persistState()
        pcall(function()
            if type(writefile) == "function" then
                writefile(STATE_FILE, HttpService:JSONEncode(CFG))
            end
        end)
    end

    -- 2. Muat langsung dari file akun ini saja
    local function loadState()
        if type(isfile) == "function" and isfile(STATE_FILE) then
            local ok, data = pcall(function()
                return HttpService:JSONDecode(readfile(STATE_FILE))
            end)
            if ok and type(data) == "table" then
                return data
            end
        end
        return nil
    end

    ----------------------------------------------------------------- restore
    do
        local st = loadState()
        if st then
            if st.autoClaim ~= nil then CFG.autoClaim = st.autoClaim end
            if st.autoSwitchPortal ~= nil then CFG.autoSwitchPortal = st.autoSwitchPortal end
            if st.autoReconnect ~= nil then CFG.autoReconnect = st.autoReconnect end
            CFG.boothSkin       = st.boothSkin or "Default"
            CFG.autoSell        = st.autoSell or false
            CFG.webhookUrl      = st.webhookUrl or ""
            CFG.webhookEnabled  = st.webhookEnabled or false
            CFG.relocateEnabled    = st.relocateEnabled or false
            if st.relocateIdleMin    ~= nil then CFG.relocateIdleMin    = tonumber(st.relocateIdleMin) or 20 end
            if st.relocateMinPlayers ~= nil then CFG.relocateMinPlayers = tonumber(st.relocateMinPlayers) or 10 end
            if st.relocatePreferred  ~= nil then CFG.relocatePreferred  = tonumber(st.relocatePreferred) or 20 end
            CFG.snipeEnabled = st.snipeEnabled or false
            if st.snipeHop ~= nil then CFG.snipeHop = st.snipeHop end
            if st.snipeHopIndex ~= nil then CFG.snipeHopIndex = st.snipeHopIndex end
            if st.snipeHopPlayer ~= nil then CFG.snipeHopPlayer = st.snipeHopPlayer end
            if st.snipeMinPop ~= nil then CFG.snipeMinPop = tonumber(st.snipeMinPop) or 25 end
            if st.snipeRevisitSec ~= nil then CFG.snipeRevisitSec = tonumber(st.snipeRevisitSec) or 120 end
            if type(st.snipeProfiles) == "table" then
                for i = 1, NUM_SNIPE do
                    local sp = st.snipeProfiles[i] or st.snipeProfiles[tostring(i)]
                    if type(sp) == "table" then
                        CFG.snipeProfiles[i].pets     = (type(sp.pets) == "table") and sp.pets or {}
                        CFG.snipeProfiles[i].muts     = (type(sp.muts) == "table") and sp.muts or {}
                        CFG.snipeProfiles[i].maxPrice = tonumber(sp.maxPrice) or 0
                    end
                end
            end
            if type(st.profiles) == "table" then
                for i = 1, NUM_PROFILES do
                    local sp = st.profiles[i] or st.profiles[tostring(i)]
                    if type(sp) == "table" and type(sp.listings) == "table" then
                        for j = 1, NUM_LISTINGS do
                            local sl = sp.listings[j] or sp.listings[tostring(j)]
                            if type(sl) == "table" then
                                CFG.profiles[i].listings[j].pets    = (type(sl.pets) == "table") and sl.pets or {}
                                CFG.profiles[i].listings[j].muts    = (type(sl.muts) == "table") and sl.muts or {}
                                CFG.profiles[i].listings[j].minW    = tonumber(sl.minW) or 0
                                CFG.profiles[i].listings[j].maxW    = tonumber(sl.maxW) or 0
                                CFG.profiles[i].listings[j].maxList = tonumber(sl.maxList) or 0
                                CFG.profiles[i].listings[j].price   = tonumber(sl.price) or 100
                            end
                        end
                    end
                end
            end
        end
    end

    ctx.NUM_PROFILES = NUM_PROFILES
    ctx.NUM_LISTINGS = NUM_LISTINGS
    ctx.NUM_SNIPE    = NUM_SNIPE
    ctx.CFG          = CFG
    ctx.persistState = persistState
    ctx.loadState    = loadState
end
