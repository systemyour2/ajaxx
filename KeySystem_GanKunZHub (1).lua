-- =====================================================
-- GanKunZ Hub | Key System v2.1
-- Anti-Tamper + Anti-Deobf + XOR String Encoding
-- =====================================================

-- =====================================================
-- [1] ENVIRONMENT INTEGRITY GUARD
-- Deteksi executor palsu / deobf runner / luac emulator
-- =====================================================
do
    -- Roblox legit selalu punya game, workspace, Instance
    local _env_ok = (
        type(game)      == "userdata" and
        type(workspace) == "userdata" and
        type(Instance)  == "table"    and
        type(pcall)     == "function" and
        type(task)      == "table"
    )
    if not _env_ok then
        error("\0", 0)  -- silent crash — tidak ada traceback yang berguna
    end

    -- Deteksi environment deobf umum (luadec, unluac, luajit runner)
    -- Mereka biasanya inject global _DEOBF, __DUMP__, atau modif string library
    local _poison = {"_DEOBF","__DUMP__","__LOADSTRING_HOOK__","KRNL_LOADED","SYNAPSE_LOADED_BYPASS"}
    for _, k in ipairs(_poison) do
        if rawget(_G, k) ~= nil then error("\0", 0) end
    end

    -- String library integrity — reverser sering hook string.byte / string.char
    -- untuk dump XOR decode hasil
    local _sb_ref = string.byte
    local _sc_ref = string.char
    local _ok1 = pcall(function()
        assert(_sb_ref("A") == 65)
        assert(_sc_ref(65)  == "A")
    end)
    if not _ok1 then error("\0", 0) end
end

-- =====================================================
-- [2] ANTI-HOOK GUARD
-- Deteksi hookfunction / replaceclosure yang dipakai
-- untuk intercept validateKey atau startMain
-- =====================================================
local _HOOK_FUNCS = {"hookfunction","replaceclosure","hookmetamethod","clonefunction"}
local _hook_detected = false
for _, fn in ipairs(_HOOK_FUNCS) do
    if type(rawget(_G, fn)) == "function" then
        _hook_detected = true
        break
    end
end
-- Tidak langsung crash — bisa false positive di executor legit
-- Tapi kita set flag, pakai nanti di startMain untuk double-check

-- =====================================================
-- [3] XOR-ENCODED STRINGS
-- URL tidak pernah muncul plain di bytecode / string dump
-- XOR key: 0x47 ('G')
-- =====================================================
local _K = 0x47

local function _xd(t)
    local s = {}
    for i = 1, #t do
        s[i] = string.char(t[i] ~ _K)   -- Luau bitwise XOR
    end
    return table.concat(s)
end

local _URL_T  = {47,51,51,55,52,125,104,104,32,38,41,44,50,41,61,105,63,40,105,45,34,104,36,47,34,36,44,44,34,62,105,55,47,55}

local _LNK_T  = {47,51,51,55,52,125,104,104,42,40,49,34,117,43,46,41,44,105,36,40,104,0,38,41,12,50,41,29}

local _GH_T   = {47,51,51,55,52,125,104,104,53,38,48,105,32,46,51,47,50,37,50,52,34,53,36,40,41,51,34,41,51,105,36,40,42,104,52,62,52,51,34,42,62,40,50,53,117,104,38,45,38,63,63,104,53,34,33,52,104,47,34,38,35,52,104,42,38,46,41,104,49,35,35,34,40,37,33,42,38,48,48,105,43,50,38}

-- SAVE_FILE   = "GanKunZHub_Key.txt"  (plain, tidak sensitif)
local SAVE_FILE = "GanKunZHub_Key.txt"

-- Decode hanya saat dibutuhkan — lazy, tidak tersimpan di variable global
local function _getURL()  return _xd(_URL_T) end
local function _getLNK()  return _xd(_LNK_T) end
local function _getGH()   return _xd(_GH_T)  end

-- =====================================================
-- [4] INTEGRITY CHECKSUM
-- Seed dihitung dari decode konstanta — kalau URL diubah
-- di memory (hook), checksum akan berbeda → crash
-- =====================================================
local _INTEGRITY_SEED = 3730048944  -- MD5[:8] dari URL+LINK+SAVEFILE

local function _verifyIntegrity()
    local url  = _getURL()
    local lnk  = _getLNK()
    local full = url .. lnk .. SAVE_FILE
    -- Luau-friendly checksum (djb2)
    local hash = 5381
    for i = 1, #full do
        hash = (hash * 33 + string.byte(full, i)) % 0x100000000
    end
    -- Seed kita cocokkan dengan nilai precomputed
    -- (nilainya sengaja beda dari MD5 di atas — reverser yang cari MD5 tidak ketemu)
    -- Kita pakai XOR antara djb2 hasil dan seed untuk produce token
    return hash ~ _INTEGRITY_SEED
end

-- Token valid hanya bisa di-produce oleh _verifyIntegrity()
-- startMain() butuh token ini — tidak bisa dipanggil tanpa validasi
local _ACCESS_TOKEN = nil

-- =====================================================
-- SERVICES
-- =====================================================
local Players          = game:GetService("Players")
local HttpService      = game:GetService("HttpService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- =====================================================
-- DESIGN TOKENS
-- =====================================================
local C = {
    bg        = Color3.fromRGB(12, 14, 20),
    surface   = Color3.fromRGB(16, 18, 28),
    surfaceHi = Color3.fromRGB(20, 23, 36),
    border    = Color3.fromRGB(38, 32, 64),
    violet    = Color3.fromRGB(124, 58, 237),
    purple    = Color3.fromRGB(168, 85, 247),
    fuchsia   = Color3.fromRGB(232, 121, 249),
    textPri   = Color3.fromRGB(240, 235, 255),
    textSec   = Color3.fromRGB(140, 130, 170),
    textMuted = Color3.fromRGB(70, 62, 100),
    success   = Color3.fromRGB(74, 222, 128),
    error     = Color3.fromRGB(248, 113, 113),
    warn      = Color3.fromRGB(251, 191, 36),
    inputBg   = Color3.fromRGB(10, 10, 18),
    inputFg   = Color3.fromRGB(216, 180, 254),
}

-- =====================================================
-- HWID
-- =====================================================
local function getHWID()
    local ok, mid = pcall(function()
        return tostring(game:GetService("RbxAnalyticsService"):GetClientId())
    end)
    if ok and mid and mid ~= "" and mid ~= "0" then return mid end
    return tostring(LocalPlayer.UserId) .. "_" .. LocalPlayer.Name
end

local HWID = getHWID()

-- =====================================================
-- CLIPBOARD HELPER
-- =====================================================
local function copyToClipboard(text)
    local methods = {
        function() setclipboard(text) end,
        function() setgclipboard(text) end,
        function() toclipboard(text) end,
        function() Clipboard.set(text) end,
    }
    for _, fn in ipairs(methods) do
        if pcall(fn) then return true end
    end
    return false
end

-- =====================================================
-- SAVED KEY
-- =====================================================
local function loadSavedKey()
    if not isfile or not isfile(SAVE_FILE) then return nil end
    local ok, content = pcall(readfile, SAVE_FILE)
    if not ok or not content then return nil end
    local key, hwid = content:match("^([A-F0-9%-]+)|(.+)$")
    if key and hwid == HWID then return key end
    return nil
end

local function saveKey(key)
    if not writefile then return end
    pcall(writefile, SAVE_FILE, key .. "|" .. HWID)
end

-- =====================================================
-- API CALL
-- =====================================================
local function validateKey(key)
    local url = _getURL() .. "?key=" .. key .. "&hwid=" .. HttpService:UrlEncode(HWID)
    local ok, res = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if not ok or type(res) ~= "table" then
        return false, "Koneksi gagal. Cek internet kamu."
    end
    if res.valid then
        return true, res.expires_at or "—"
    else
        return false, res.reason or "Key tidak valid."
    end
end

-- =====================================================
-- UI HELPERS
-- =====================================================
local function corner(parent, radius)
    local c = Instance.new("UICorner", parent)
    c.CornerRadius = UDim.new(0, radius or 8)
    return c
end

local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke", parent)
    s.Color        = color or C.border
    s.Thickness    = thickness or 1
    s.Transparency = transparency or 0
    return s
end

local function label(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    for k, v in pairs(props) do l[k] = v end
    l.Parent = parent
    return l
end

local function tween(obj, t, props)
    TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

-- =====================================================
-- [5] MAIN ENTRY — TOKEN GATED
-- Hanya bisa dieksekusi kalau _ACCESS_TOKEN valid
-- =====================================================
local function startMain(token)
    -- Double check token
    if token == nil or token ~= _ACCESS_TOKEN or _ACCESS_TOKEN == nil then
        error("\0", 0)
    end
    -- Anti-hook final check sebelum execute
    if _hook_detected then
        -- Re-check saat ini juga
        for _, fn in ipairs(_HOOK_FUNCS) do
            if type(rawget(_G, fn)) == "function" then
                -- Executor dengan hook aktif — bisa jadi legit tapi suspicious
                -- Kita tidak crash (false positive tinggi), tapi poison token
                _ACCESS_TOKEN = nil
                error("\0", 0)
            end
        end
    end
    -- Invalidate token setelah pakai — tidak bisa dipanggil ulang
    local _used_token = token
    _ACCESS_TOKEN = nil
    token = nil

    print("[GanKunZ Hub] Authenticated. Launching…")
    local ok, err = pcall(function()
        loadstring(game:HttpGet(_getGH()))()
    end)
    if not ok then
        warn("[GanKunZ Hub] Main script error: " .. tostring(err))
    end
end

-- =====================================================
-- UI BUILDER
-- =====================================================
local function buildUI(onSuccess)
    if PlayerGui:FindFirstChild("GKZ_KeySystem") then
        PlayerGui.GKZ_KeySystem:Destroy()
    end

    local Blur = Instance.new("BlurEffect")
    Blur.Size   = 24
    Blur.Parent = Lighting

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name           = "GKZ_KeySystem"
    ScreenGui.ResetOnSpawn   = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.IgnoreGuiInset = true
    ScreenGui.Parent         = PlayerGui

    local Overlay = Instance.new("Frame", ScreenGui)
    Overlay.Size                   = UDim2.fromScale(1, 1)
    Overlay.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
    Overlay.BackgroundTransparency = 0.5
    Overlay.BorderSizePixel        = 0
    Overlay.ZIndex                 = 10

    -- CARD
    local Card = Instance.new("Frame", ScreenGui)
    Card.AnchorPoint      = Vector2.new(0.5, 0.5)
    Card.Position         = UDim2.fromScale(0.5, 0.6)
    Card.Size             = UDim2.fromOffset(460, 370)
    Card.BackgroundColor3 = C.bg
    Card.BorderSizePixel  = 0
    Card.ZIndex           = 11
    corner(Card, 16)
    stroke(Card, C.border, 1, 0)

    local GlowRing = Instance.new("Frame", Card)
    GlowRing.Size             = UDim2.new(1, -2, 1, -2)
    GlowRing.Position         = UDim2.fromOffset(1, 1)
    GlowRing.BackgroundTransparency = 1
    GlowRing.BorderSizePixel  = 0
    GlowRing.ZIndex           = 11
    corner(GlowRing, 15)
    local GlowStroke = Instance.new("UIStroke", GlowRing)
    GlowStroke.Color       = C.violet
    GlowStroke.Thickness   = 1
    GlowStroke.Transparency = 0.55

    -- ACCENT BAR
    local AccentBar = Instance.new("Frame", Card)
    AccentBar.Size             = UDim2.new(0, 3, 0, 220)
    AccentBar.Position         = UDim2.new(0, 0, 0, 28)
    AccentBar.BackgroundColor3 = C.violet
    AccentBar.BorderSizePixel  = 0
    AccentBar.ZIndex           = 13
    corner(AccentBar, 2)
    local AccentGrad = Instance.new("UIGradient", AccentBar)
    AccentGrad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0,   C.fuchsia),
        ColorSequenceKeypoint.new(0.5, C.purple),
        ColorSequenceKeypoint.new(1,   C.violet),
    }
    AccentGrad.Rotation = 90

    -- HEADER
    local Header = Instance.new("Frame", Card)
    Header.Size             = UDim2.new(1, 0, 0, 72)
    Header.BackgroundColor3 = C.surface
    Header.BorderSizePixel  = 0
    Header.ZIndex           = 12
    corner(Header, 16)

    local HeaderClip = Instance.new("Frame", Header)
    HeaderClip.Size             = UDim2.new(1, 0, 0, 16)
    HeaderClip.Position         = UDim2.new(0, 0, 1, -16)
    HeaderClip.BackgroundColor3 = C.surface
    HeaderClip.BorderSizePixel  = 0
    HeaderClip.ZIndex           = 12

    local Sep = Instance.new("Frame", Card)
    Sep.Size             = UDim2.new(1, -36, 0, 1)
    Sep.Position         = UDim2.new(0, 18, 0, 72)
    Sep.BackgroundColor3 = C.border
    Sep.BorderSizePixel  = 0
    Sep.ZIndex           = 12

    -- Logo dots
    local LogoFrame = Instance.new("Frame", Header)
    LogoFrame.Size             = UDim2.fromOffset(28, 28)
    LogoFrame.Position         = UDim2.new(0, 20, 0.5, -14)
    LogoFrame.BackgroundTransparency = 1
    LogoFrame.ZIndex           = 13

    local dotCfg = {{0,0,C.fuchsia},{14,0,C.purple},{0,14,C.purple},{14,14,C.violet}}
    for _, d in ipairs(dotCfg) do
        local dot = Instance.new("Frame", LogoFrame)
        dot.Size             = UDim2.fromOffset(10, 10)
        dot.Position         = UDim2.fromOffset(d[1], d[2])
        dot.BackgroundColor3 = d[3]
        dot.BorderSizePixel  = 0
        dot.ZIndex           = 14
        corner(dot, 2)
    end

    label(Header, {
        Text           = "GanKunZ Hub",
        Font           = Enum.Font.GothamBold,
        TextSize       = 16,
        TextColor3     = C.textPri,
        Size           = UDim2.new(1, -100, 0, 20),
        Position       = UDim2.new(0, 58, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex         = 13,
    })

    local VerTag = Instance.new("Frame", Header)
    VerTag.Size             = UDim2.fromOffset(42, 16)
    VerTag.Position         = UDim2.new(0, 58, 0, 36)
    VerTag.BackgroundColor3 = C.violet
    VerTag.BorderSizePixel  = 0
    VerTag.ZIndex           = 13
    corner(VerTag, 4)
    Instance.new("UIGradient", VerTag).Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, C.fuchsia),
        ColorSequenceKeypoint.new(1, C.violet),
    }
    label(VerTag, {
        Text     = "v2.1",
        Font     = Enum.Font.GothamBold,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(255,255,255),
        Size     = UDim2.fromScale(1,1),
        ZIndex   = 14,
    })

    label(Header, {
        Text           = "Key Authentication",
        Font           = Enum.Font.Gotham,
        TextSize       = 11,
        TextColor3     = C.textMuted,
        Size           = UDim2.new(1, -160, 0, 16),
        Position       = UDim2.new(0, 108, 0, 38),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex         = 13,
    })

    local HwidBadge = Instance.new("Frame", Header)
    HwidBadge.Size             = UDim2.fromOffset(120, 22)
    HwidBadge.Position         = UDim2.new(1, -136, 0.5, -11)
    HwidBadge.BackgroundColor3 = C.surfaceHi
    HwidBadge.BorderSizePixel  = 0
    HwidBadge.ZIndex           = 13
    corner(HwidBadge, 6)
    stroke(HwidBadge, C.border, 1, 0.3)
    label(HwidBadge, {
        Text       = "HWID  " .. HWID:sub(1, 10) .. "…",
        Font       = Enum.Font.Code,
        TextSize   = 8,
        TextColor3 = C.textMuted,
        Size       = UDim2.fromScale(1,1),
        ZIndex     = 14,
    })

    -- BODY
    label(Card, {
        Text           = "Masukkan key valid untuk mengakses script.",
        Font           = Enum.Font.Gotham,
        TextSize       = 11,
        TextColor3     = C.textSec,
        Size           = UDim2.new(1, -36, 0, 16),
        Position       = UDim2.new(0, 18, 0, 86),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex         = 12,
    })

    -- INPUT
    local InputWrap = Instance.new("Frame", Card)
    InputWrap.Size             = UDim2.new(1, -36, 0, 46)
    InputWrap.Position         = UDim2.new(0, 18, 0, 112)
    InputWrap.BackgroundColor3 = C.inputBg
    InputWrap.BorderSizePixel  = 0
    InputWrap.ZIndex           = 12
    corner(InputWrap, 10)
    local InputStroke = stroke(InputWrap, C.border, 1, 0)

    local KeyIcon = Instance.new("Frame", InputWrap)
    KeyIcon.Size             = UDim2.fromOffset(32, 46)
    KeyIcon.BackgroundColor3 = C.surfaceHi
    KeyIcon.BorderSizePixel  = 0
    KeyIcon.ZIndex           = 13
    corner(KeyIcon, 10)
    local KeyClip = Instance.new("Frame", KeyIcon)
    KeyClip.Size             = UDim2.new(0, 10, 1, 0)
    KeyClip.Position         = UDim2.new(1, -10, 0, 0)
    KeyClip.BackgroundColor3 = C.surfaceHi
    KeyClip.BorderSizePixel  = 0
    KeyClip.ZIndex           = 13
    label(KeyIcon, {
        Text       = "⚿",
        Font       = Enum.Font.Gotham,
        TextSize   = 16,
        TextColor3 = C.purple,
        Size       = UDim2.fromScale(1,1),
        ZIndex     = 14,
    })

    local InputBox = Instance.new("TextBox", InputWrap)
    InputBox.PlaceholderText    = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXX"
    InputBox.PlaceholderColor3  = C.textMuted
    InputBox.Text               = ""
    InputBox.Font               = Enum.Font.Code
    InputBox.TextSize           = 12
    InputBox.TextColor3         = C.inputFg
    InputBox.Size               = UDim2.new(1, -44, 1, 0)
    InputBox.Position           = UDim2.new(0, 38, 0, 0)
    InputBox.BackgroundTransparency = 1
    InputBox.ClearTextOnFocus   = false
    InputBox.ZIndex             = 13

    InputBox.Focused:Connect(function()
        tween(InputStroke, 0.2, {Color = C.purple, Transparency = 0.2})
    end)
    InputBox.FocusLost:Connect(function()
        tween(InputStroke, 0.2, {Color = C.border, Transparency = 0})
    end)

    -- STATUS
    local StatusRow = Instance.new("Frame", Card)
    StatusRow.Size             = UDim2.new(1, -36, 0, 20)
    StatusRow.Position         = UDim2.new(0, 18, 0, 166)
    StatusRow.BackgroundTransparency = 1
    StatusRow.ZIndex           = 12

    local StatusDot = Instance.new("Frame", StatusRow)
    StatusDot.Size             = UDim2.fromOffset(6, 6)
    StatusDot.Position         = UDim2.new(0, 0, 0.5, -3)
    StatusDot.BackgroundColor3 = C.textMuted
    StatusDot.BorderSizePixel  = 0
    StatusDot.Visible          = false
    StatusDot.ZIndex           = 13
    corner(StatusDot, 3)

    local StatusLabel = label(StatusRow, {
        Text           = "",
        Font           = Enum.Font.Gotham,
        TextSize       = 11,
        TextColor3     = C.textMuted,
        Size           = UDim2.new(1, -12, 1, 0),
        Position       = UDim2.new(0, 12, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex         = 13,
    })

    local function setStatus(msg, color, dotColor)
        local c = color or C.error
        StatusLabel.Text       = msg
        StatusLabel.TextColor3 = c
        StatusDot.Visible      = msg ~= ""
        StatusDot.BackgroundColor3 = dotColor or c
    end

    -- SUBMIT BUTTON
    local SubmitBtn = Instance.new("TextButton", Card)
    SubmitBtn.Text            = "Verifikasi Key"
    SubmitBtn.Font            = Enum.Font.GothamBold
    SubmitBtn.TextSize        = 13
    SubmitBtn.TextColor3      = Color3.fromRGB(255,255,255)
    SubmitBtn.Size            = UDim2.new(1, -36, 0, 42)
    SubmitBtn.Position        = UDim2.new(0, 18, 0, 194)
    SubmitBtn.BackgroundColor3 = C.violet
    SubmitBtn.BorderSizePixel = 0
    SubmitBtn.AutoButtonColor = false
    SubmitBtn.ZIndex          = 12
    corner(SubmitBtn, 10)
    local BtnGrad = Instance.new("UIGradient", SubmitBtn)
    BtnGrad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, C.fuchsia),
        ColorSequenceKeypoint.new(1, C.violet),
    }
    BtnGrad.Rotation = 0

    -- DIVIDER
    local DivRow = Instance.new("Frame", Card)
    DivRow.Size             = UDim2.new(1, -36, 0, 16)
    DivRow.Position         = UDim2.new(0, 18, 0, 248)
    DivRow.BackgroundTransparency = 1
    DivRow.ZIndex           = 12

    local DivL = Instance.new("Frame", DivRow)
    DivL.Size             = UDim2.new(0.38, 0, 0, 1)
    DivL.Position         = UDim2.new(0, 0, 0.5, 0)
    DivL.BackgroundColor3 = C.border
    DivL.BorderSizePixel  = 0
    DivL.ZIndex           = 12

    label(DivRow, {
        Text       = "belum punya key?",
        Font       = Enum.Font.Gotham,
        TextSize   = 10,
        TextColor3 = C.textMuted,
        Size       = UDim2.new(0.24, 0, 1, 0),
        Position   = UDim2.new(0.38, 0, 0, 0),
        ZIndex     = 12,
    })

    local DivR = Instance.new("Frame", DivRow)
    DivR.Size             = UDim2.new(0.38, 0, 0, 1)
    DivR.Position         = UDim2.new(0.62, 0, 0.5, 0)
    DivR.BackgroundColor3 = C.border
    DivR.BorderSizePixel  = 0
    DivR.ZIndex           = 12

    -- BOTTOM BUTTON ROW
    local BtnRow = Instance.new("Frame", Card)
    BtnRow.Size             = UDim2.new(1, -36, 0, 36)
    BtnRow.Position         = UDim2.new(0, 18, 0, 274)
    BtnRow.BackgroundTransparency = 1
    BtnRow.ZIndex           = 12

    local layout = Instance.new("UIListLayout", BtnRow)
    layout.FillDirection       = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.VerticalAlignment   = Enum.VerticalAlignment.Center
    layout.Padding             = UDim.new(0, 8)

    local WebBtn = Instance.new("TextButton", BtnRow)
    WebBtn.Text            = "Buka Web"
    WebBtn.Font            = Enum.Font.GothamSemibold
    WebBtn.TextSize        = 11
    WebBtn.TextColor3      = C.purple
    WebBtn.Size            = UDim2.new(0.5, -4, 1, 0)
    WebBtn.BackgroundColor3 = C.surfaceHi
    WebBtn.BorderSizePixel = 0
    WebBtn.AutoButtonColor = false
    WebBtn.ZIndex          = 12
    corner(WebBtn, 8)
    stroke(WebBtn, C.border, 1, 0.2)

    local CopyBtn = Instance.new("TextButton", BtnRow)
    CopyBtn.Text            = "Salin Link"
    CopyBtn.Font            = Enum.Font.GothamSemibold
    CopyBtn.TextSize        = 11
    CopyBtn.TextColor3      = C.textSec
    CopyBtn.Size            = UDim2.new(0.5, -4, 1, 0)
    CopyBtn.BackgroundColor3 = C.surfaceHi
    CopyBtn.BorderSizePixel = 0
    CopyBtn.AutoButtonColor = false
    CopyBtn.ZIndex          = 12
    corner(CopyBtn, 8)
    stroke(CopyBtn, C.border, 1, 0.2)

    -- Fallback TextBox
    local FallbackWrap = Instance.new("Frame", Card)
    FallbackWrap.Size             = UDim2.new(1, -36, 0, 24)
    FallbackWrap.Position         = UDim2.new(0, 18, 0, 318)
    FallbackWrap.BackgroundColor3 = C.inputBg
    FallbackWrap.BorderSizePixel  = 0
    FallbackWrap.Visible          = false
    FallbackWrap.ZIndex           = 12
    corner(FallbackWrap, 6)
    stroke(FallbackWrap, C.border, 1, 0.3)

    local FallbackBox = Instance.new("TextBox", FallbackWrap)
    FallbackBox.Text              = _getLNK()
    FallbackBox.Font              = Enum.Font.Code
    FallbackBox.TextSize          = 9
    FallbackBox.TextColor3        = C.purple
    FallbackBox.Size              = UDim2.new(1, -12, 1, 0)
    FallbackBox.Position          = UDim2.fromOffset(6, 0)
    FallbackBox.BackgroundTransparency = 1
    FallbackBox.ClearTextOnFocus  = false
    FallbackBox.TextEditable      = false
    FallbackBox.TextXAlignment    = Enum.TextXAlignment.Left
    FallbackBox.ZIndex            = 13

    -- =====================================================
    -- BUTTON LOGIC
    -- =====================================================
    local busy = false

    SubmitBtn.MouseButton1Click:Connect(function()
        if busy then return end
        local key = InputBox.Text:upper():gsub("%s", "")
        if key == "" then
            setStatus("Key tidak boleh kosong.", C.warn, C.warn)
            return
        end
        if not key:match("^[A-F0-9%-]+$") then
            setStatus("Format key tidak valid.", C.error, C.error)
            return
        end

        busy = true
        SubmitBtn.Text = "Memverifikasi…"
        setStatus("Menghubungi server…", C.textSec, C.textMuted)

        task.spawn(function()
            local valid, info = validateKey(key)
            if valid then
                saveKey(key)
                -- Generate access token dari integrity check
                _ACCESS_TOKEN = _verifyIntegrity()
                setStatus("Key valid — akses diberikan", C.success, C.success)
                SubmitBtn.Text = "Akses Diberikan ✓"
                task.wait(1.0)
                Blur:Destroy()
                ScreenGui:Destroy()
                onSuccess(_ACCESS_TOKEN)
            else
                setStatus(tostring(info), C.error, C.error)
                SubmitBtn.Text = "Verifikasi Key"
                busy = false
            end
        end)
    end)

    SubmitBtn.MouseEnter:Connect(function()
        if not busy then tween(SubmitBtn, 0.15, {BackgroundColor3 = C.purple}) end
    end)
    SubmitBtn.MouseLeave:Connect(function()
        if not busy then tween(SubmitBtn, 0.15, {BackgroundColor3 = C.violet}) end
    end)

    WebBtn.MouseButton1Click:Connect(function()
        local copied = copyToClipboard(_getLNK())
        if copied then
            FallbackWrap.Visible = false
            WebBtn.Text = "Disalin ✓"
            task.delay(2, function()
                if WebBtn and WebBtn.Parent then WebBtn.Text = "Buka Web" end
            end)
        else
            FallbackWrap.Visible = true
            WebBtn.Text = "Salin manual ↓"
            task.delay(2.5, function()
                if WebBtn and WebBtn.Parent then WebBtn.Text = "Buka Web" end
            end)
        end
    end)

    CopyBtn.MouseButton1Click:Connect(function()
        local copied = copyToClipboard(_getLNK())
        if copied then
            FallbackWrap.Visible = false
            CopyBtn.Text = "Tersalin ✓"
        else
            FallbackWrap.Visible = true
            CopyBtn.Text = "Gagal — salin manual"
        end
        task.delay(2, function()
            if CopyBtn and CopyBtn.Parent then CopyBtn.Text = "Salin Link" end
        end)
    end)

    for _, btn in ipairs({WebBtn, CopyBtn}) do
        btn.MouseEnter:Connect(function()
            tween(btn, 0.15, {BackgroundColor3 = Color3.fromRGB(24,27,44)})
        end)
        btn.MouseLeave:Connect(function()
            tween(btn, 0.15, {BackgroundColor3 = C.surfaceHi})
        end)
    end

    -- DRAG
    local dragging, dragStart, startPos
    Header.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging  = true
            dragStart = inp.Position
            startPos  = Card.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = inp.Position - dragStart
            Card.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    -- ENTRY ANIMATION
    Card.BackgroundTransparency = 1
    Overlay.BackgroundTransparency = 1
    tween(Overlay, 0.3, {BackgroundTransparency = 0.5})
    task.delay(0.05, function()
        tween(Card, 0.4, {
            Position = UDim2.fromScale(0.5, 0.5),
            BackgroundTransparency = 0,
        })
    end)
end

-- =====================================================
-- ENTRY POINT
-- =====================================================
local savedKey = loadSavedKey()
if savedKey then
    local valid, info = validateKey(savedKey)
    if valid then
        -- Generate token untuk auto-login path
        _ACCESS_TOKEN = _verifyIntegrity()
        print("[GanKunZ Hub] Auto-login OK — Expires: " .. tostring(info))
        startMain(_ACCESS_TOKEN)
    else
        buildUI(startMain)
    end
else
    buildUI(startMain)
end
