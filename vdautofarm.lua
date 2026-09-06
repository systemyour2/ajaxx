pcall(function()
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
end)

local safeWait = (task and task.wait) or wait
local safeSpawn = (task and task.spawn) or spawn

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = workspace or game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    LocalPlayer = Players.LocalPlayer
    safeWait(0.1)
end

local PlaceId = game.PlaceId
local CurrentJobId = game.JobId

-- [1] LOAD KEZODX UI LIBRARY & ADDONS
local repo = "https://raw.githubusercontent.com/kezodxyz/KezodX/refs/heads/main/"

local function safeHttpGet(url)
    local success, res = pcall(function()
        return game:HttpGet(url)
    end)
    if success and res and #res > 0 then
        return res
    end
    return nil
end

local libSource = safeHttpGet(repo .. "Library.lua")
if not libSource then
    warn("[GanKunZ Hub] Failed to download KezodX Library!")
    return
end

local Library = loadstring(libSource)()
local ThemeManager = loadstring(safeHttpGet(repo .. "addons/ThemeManager.lua") or "")()
local SaveManager = loadstring(safeHttpGet(repo .. "addons/SaveManager.lua") or "")()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

-- [2] CREATE WINDOW (EXACT SETTINGS FROM DUMPED BYTECODE)
local Window = Library:CreateWindow({
    Title = "GanKunZ Hub",
    Footer = "New Auto Farm Vd | TikTok : GanKunZ",
    Icon = "1462874790",
    IconSize = UDim2.fromOffset(50, 50),
    NotifySide = "Right",
    EnableSidebarResize = true,
    EnableCompacting = true,
    SidebarCompacted = false, -- Set to false or auto so tabs are 100% visible on mobile executors
    Size = UDim2.fromOffset(480, 340),
    AutoShow = true,
    CornerRadius = 20
})

pcall(function()
    Window:SetSidebarWidth(120)
end)

-- [3] CREATE TABS (MATCHING DUMPED.JSON STRUCTURE)
local Tabs = {
    AutoFarm = Window:AddTab("Auto Farm", "bot"),
    Settings = Window:AddTab("Settings", "settings")
}

-- Mobile & Delta Safeguard: Ensure tab Canvas is visible & transparent 0
pcall(function()
    for tabName, tab in pairs(Tabs) do
        if tab.Canvas then
            tab.Canvas.GroupTransparency = 0
            tab.Canvas.Visible = true
        end
    end
end)

-- [4] AUTO FARM TAB: LEFT GROUPBOX ("Auto Farm")
local AutoFarmGroup = Tabs.AutoFarm:AddLeftGroupbox("Auto Farm", "zap")

AutoFarmGroup:AddToggle("AutoFarm", {
    Text = "Auto Farm",
    Default = true,
    Tooltip = "Aktifkan otomatisasi escape gerbang dan teleport",
    Callback = function(Value)
        print("[GanKunZ Hub] Auto Farm:", Value)
    end
})

AutoFarmGroup:AddToggle("DisableKillerChance", {
    Text = "Disable Killer Chance",
    Default = true,
    Tooltip = "Mencegah karakter terpilih sebagai Killer",
    Callback = function(Value)
        print("[GanKunZ Hub] Disable Killer Chance:", Value)
    end
})

AutoFarmGroup:AddToggle("HopIfKiller", {
    Text = "Hop Server When Killer",
    Default = true,
    Tooltip = "Pindah server langsung jika terpilih jadi Killer",
    Callback = function(Value)
        print("[GanKunZ Hub] Hop If Killer:", Value)
    end
})

AutoFarmGroup:AddToggle("AutoExecuteOnHop", {
    Text = "Auto Execute On Hop",
    Default = true,
    Tooltip = "Menjalankan script otomatis saat teleport server baru",
    Callback = function(Value)
        print("[GanKunZ Hub] Auto Execute On Hop:", Value)
    end
})

AutoFarmGroup:AddSlider("GateTweenSpeed", {
    Text = "Gate Tween Speed",
    Default = 100,
    Min = 20,
    Max = 300,
    Rounding = 0,
    Compact = false,
    Callback = function(Value)
        print("[GanKunZ Hub] Tween Speed:", Value)
    end
})

AutoFarmGroup:AddSlider("MinPlayers", {
    Text = "Min Players (Server Hop)",
    Default = 2,
    Min = 1,
    Max = 8,
    Rounding = 0,
    Compact = false
})

AutoFarmGroup:AddSlider("MaxPlayers", {
    Text = "Max Players (Server Hop)",
    Default = 4,
    Min = 1,
    Max = 8,
    Rounding = 0,
    Compact = false
})

-- [5] AUTO FARM TAB: RIGHT GROUPBOX ("Webhook")
local WebhookGroup = Tabs.AutoFarm:AddRightGroupbox("Webhook", "webhook")

WebhookGroup:AddInput("WebhookURL", {
    Default = "",
    Numeric = false,
    Finished = false,
    Text = "Discord Webhook URL",
    Placeholder = "https://discord.com/api/webhooks/...",
    Callback = function(Value)
        print("[GanKunZ Hub] Webhook URL updated")
    end
})

WebhookGroup:AddToggle("EnableWebhook", {
    Text = "Enable Webhook Log",
    Default = false,
    Tooltip = "Kirim laporan hasil escape ke Discord Webhook"
})

-- Forward declaration for ServerHop
local ServerHop

-- [6] ACTION BUTTONS
AutoFarmGroup:AddButton({
    Text = "Server Hop Now",
    Func = function()
        if ServerHop then
            ServerHop()
        end
    end,
    DoubleClick = false,
    Tooltip = "Cari server sepi dan pindah sekarang"
})

local FindExitGate
local EscapeGate

AutoFarmGroup:AddButton({
    Text = "Force Escape Gate",
    Func = function()
        if FindExitGate and EscapeGate then
            local gates = FindExitGate()
            if #gates > 0 then
                EscapeGate(gates[1])
            else
                Library:Notify("Gerbang keluar belum ditemukan di map!", 3)
            end
        end
    end,
    DoubleClick = false,
    Tooltip = "Paksa tween menembus gerbang keluar terdekat"
})

-- [7] SETTINGS TAB (THEMEMANAGER & SAVEMANAGER INTEGRATION)
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

ThemeManager:SetFolder("GanKunZHub")
SaveManager:SetFolder("GanKunZHub/ViolenceDistrict")

SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)

SaveManager:LoadAutoloadConfig()

-- Force show first tab on mobile
pcall(function()
    Tabs.AutoFarm:Show()
    if Tabs.AutoFarm.Canvas then
        Tabs.AutoFarm.Canvas.GroupTransparency = 0
        Tabs.AutoFarm.Canvas.Visible = true
    end
end)

-- [8] QUEUE ON TELEPORT HANDLER
local function QueueScriptExecution()
    if Toggles.AutoExecuteOnHop and Toggles.AutoExecuteOnHop.Value then
        local queue_on_teleport = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
        if queue_on_teleport then
            pcall(function()
                queue_on_teleport([[
                    pcall(function()
                        loadstring(game:HttpGet("https://raw.githubusercontent.com/kezodxyz/KezodX/refs/heads/main/Library.lua"))()
                    end)
                ]])
            end)
        end
    end
end

-- [9] SERVER HOPPING SYSTEM
ServerHop = function()
    Library:Notify("Mencari server sepi...", 3)
    QueueScriptExecution()

    local minP = (Options.MinPlayers and Options.MinPlayers.Value) or 2
    local maxP = (Options.MaxPlayers and Options.MaxPlayers.Value) or 4

    local success, response = pcall(function()
        local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100", tostring(PlaceId))
        return game:HttpGet(url)
    end)

    if success and response and type(response) == "string" then
        local decodeOk, data = pcall(function()
            return HttpService:JSONDecode(response)
        end)

        if decodeOk and data and type(data.data) == "table" then
            local validServers = {}
            for _, srv in ipairs(data.data) do
                if type(srv) == "table" and srv.id and srv.id ~= CurrentJobId then
                    local count = tonumber(srv.playing) or tonumber(srv.players) or 0
                    if count >= minP and count <= maxP then
                        table.insert(validServers, srv.id)
                    end
                end
            end

            if #validServers > 0 then
                local chosenServer = validServers[math.random(1, #validServers)]
                Library:Notify("Menghubungkan ke server baru...", 4)
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(PlaceId, chosenServer, LocalPlayer)
                end)
                return
            end
        end
    end

    Library:Notify("Server spesifik tidak ditemukan, melakukan teleport default...", 3)
    pcall(function()
        TeleportService:Teleport(PlaceId, LocalPlayer)
    end)
end

-- [10] ROLE DETECTION
local function GetPlayerRole()
    local role = "Unknown"
    pcall(function()
        if LocalPlayer.Team then
            local tName = tostring(LocalPlayer.Team.Name or ""):lower()
            if tName:find("killer") then return "Killer" end
            if tName:find("survivor") then return "Survivor" end
            if tName:find("spectator") then return "Spectator" end
        end

        local char = LocalPlayer.Character
        if char then
            local tag = char:FindFirstChild("Team") or char:FindFirstChild("TeamTag") or char:FindFirstChild("Role")
            if tag then
                local val = tostring(tag.Value or tag.Name or ""):lower()
                if val:find("killer") then return "Killer" end
                if val:find("survivor") then return "Survivor" end
                if val:find("spectator") then return "Spectator" end
            end
        end
    end)
    return role
end

-- [11] GATE DETECTION & TWEEN ESCAPE
FindExitGate = function()
    local possibleGates = {}
    pcall(function()
        local map = Workspace:FindFirstChild("Map") or Workspace
        for _, obj in ipairs(map:GetDescendants()) do
            if obj:IsA("BasePart") or obj:IsA("Model") then
                local name = tostring(obj.Name or ""):lower()
                if name:find("leftgate") or name:find("rightgate") or name:find("finishline") or name:find("fininshline") or (name:find("gate") and obj:FindFirstChild("Box")) then
                    table.insert(possibleGates, obj)
                end
            end
        end
    end)
    return possibleGates
end

local function GetObjectCFrame(obj)
    if not obj then return nil end
    local cf = nil
    pcall(function()
        if obj:IsA("BasePart") then
            cf = obj.CFrame
        elseif obj:IsA("Model") then
            if obj.PrimaryPart then
                cf = obj.PrimaryPart.CFrame
            elseif obj.GetPivot then
                cf = obj:GetPivot()
            else
                local part = obj:FindFirstChildWhichIsA("BasePart")
                if part then cf = part.CFrame end
            end
        end
    end)
    return cf
end

EscapeGate = function(targetObj)
    local char = LocalPlayer.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp or not hrp:IsA("BasePart") then return false end

    pcall(function()
        for _, part in ipairs(targetObj:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
                part.Transparency = 1
            end
        end
        if targetObj:IsA("BasePart") then
            targetObj.CanCollide = false
            targetObj.Transparency = 1
        end
    end)

    local targetCF = GetObjectCFrame(targetObj)
    if not targetCF then return false end

    local destCFrame = targetCF * CFrame.new(0, 2, 0)
    local dist = (hrp.Position - destCFrame.Position).Magnitude
    local speed = (Options.GateTweenSpeed and Options.GateTweenSpeed.Value) or 100
    local tweenDuration = math.clamp(dist / math.max(10, speed), 0.4, 6)

    Library:Notify("Meluncur menembus gerbang escape...", 3)
    local tweenInfo = TweenInfo.new(tweenDuration, Enum.EasingStyle.Linear)
    local tween = TweenService:Create(hrp, tweenInfo, { CFrame = destCFrame })

    tween:Play()
    tween.Completed:Wait()

    Library:Notify("Berhasil escape dari map!", 3)
    safeWait(2)
    return true
end

-- [12] DISCORD WEBHOOK SENDER
local function SendWebhookNotification()
    if not (Toggles.EnableWebhook and Toggles.EnableWebhook.Value) then return end
    local url = (Options.WebhookURL and Options.WebhookURL.Value) or ""
    if url == "" then return end

    pcall(function()
        local req = (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request) or request
        if not req then return end

        local embedData = {
            ["embeds"] = {{
                ["title"] = "GanKunZ Hub - Match Escaped",
                ["color"] = 65280,
                ["description"] = string.format(
                    "**Player:** %s (%s)\n**Job ID:** `%s`\n**Place:** Violence District",
                    tostring(LocalPlayer.Name),
                    tostring(LocalPlayer.DisplayName),
                    tostring(CurrentJobId)
                ),
                ["footer"] = { ["text"] = "GanKunZ Hub Auto Farm" },
                ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }}
        }

        req({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(embedData)
        })
    end)
end

-- [13] TEST WEBHOOK BUTTON
WebhookGroup:AddButton({
    Text = "Send Test Webhook",
    Func = function()
        local url = (Options.WebhookURL and Options.WebhookURL.Value) or ""
        if url == "" then
            Library:Notify("Masukkan Discord Webhook URL terlebih dahulu!", 3)
            return
        end
        SendWebhookNotification()
        Library:Notify("Test webhook dikirim!", 3)
    end,
    DoubleClick = false
})

-- [14] MAIN AUTO FARM LOOP
safeSpawn(function()
    while true do
        if Toggles.AutoFarm and Toggles.AutoFarm.Value then
            local currentPlayers = #Players:GetPlayers()
            local minP = (Options.MinPlayers and Options.MinPlayers.Value) or 2

            if currentPlayers < minP then
                Library:Notify("Pemain di server kurang dari target (" .. currentPlayers .. " org). Melakukan hop...", 3)
                safeWait(3)
                ServerHop()
                return
            end

            local maxWait = 60
            local waited = 0
            Library:Notify("Menunggu status game dimulai...", 3)

            while waited < maxWait and Toggles.AutoFarm.Value do
                local role = GetPlayerRole()

                if role == "Killer" and Toggles.HopIfKiller and Toggles.HopIfKiller.Value then
                    Library:Notify("Terpilih jadi Killer! Langsung server hop...", 2)
                    safeWait(1.5)
                    ServerHop()
                    return
                end

                if role == "Survivor" then
                    Library:Notify("Role Survivor terdeteksi! Bersiap escape...", 2)
                    safeWait(2)
                    break
                end

                safeWait(1)
                waited = waited + 1
            end

            if Toggles.AutoFarm and Toggles.AutoFarm.Value then
                local gates = FindExitGate()
                if #gates > 0 then
                    local escaped = EscapeGate(gates[1])
                    if escaped then
                        SendWebhookNotification()
                        safeWait(2)
                    end
                else
                    Library:Notify("Gerbang belum terbuka atau tidak ditemukan di map.", 3)
                    safeWait(3)
                end

                Library:Notify("Ronde selesai! Memulai server hop...", 3)
                safeWait(2)
                ServerHop()
                break
            end
        end
        safeWait(1)
    end
end)

Library:Notify("GanKunZ Hub Auto Farm berhasil dimuat!", 4)
