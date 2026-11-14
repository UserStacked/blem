--!nocheck
--[[
    Sari Sari Toolkit  ·  v1.0.0
    An original hub for "Run a Sari Sari Store" (Roblox), styled like the
    Toolkit hub: dark glass window, sidebar tabs, profile card, toggle cards.

    RUN IT
      Paste this whole file into your executor and execute, or host it raw
      (GitHub, Pastebin, ...) and run:
          loadstring(game:HttpGet("https://raw.githubusercontent.com/<you>/<repo>/main/SariSariToolkit.lua"))()

    CONTROLS
      RightControl ...... show / hide the window (change it in Settings)
      "-" button ........ minimise to a floating "T" button (drag it anywhere)
      "x" button ........ unload the toolkit

    HOW IT TALKS TO THE GAME
      The Main tab (checkout, utang, KashG, beggar/singer) is wired to the
      game's own remotes in ReplicatedStorage.SariSariStore.Remotes:
        CheckoutData -> SubmitChange(change)      exact change at the register
        UtangAsk     -> UtangDecide(true/false)    credit requests
        KashGAsk     -> KashGDecide(true/false)    real/fake decided by image id
        BeggarRequest-> BeggarGive(amount | 0)     0 = "Wala" (decline)
      The other tabs use the keyword RULES below. If one of those does
      nothing in-game, use Settings > Developer ("Dump Game Info" /
      "Remote Logger") and adjust RULES.
]]

---------------------------------------------------------------------------
-- GAME: values taken from the game's own client scripts / DataConfig.
-- The KashG ids are re-read from DataConfig at runtime when possible.
---------------------------------------------------------------------------
local GAME = {
    KashGReal = "103309130318504", -- DataConfig.KASHG_SCREEN_REAL
    KashGFake = "88156526996593",  -- DataConfig.KASHG_SCREEN_FAKE
}

---------------------------------------------------------------------------
-- RULES: lower-case Lua patterns used to recognise the game's dialogs,
-- buttons and proximity prompts for the keyword-driven features.
---------------------------------------------------------------------------
local RULES = {
    -- Restocking shelves
    Restock = {
        prompt = { "restock", "refill", "re%-stock", "stock shelf", "lagyan" },
    },
    -- Buying stock from the supplier menu
    Supplier = {
        context = { "supplier", "wholesale", "grocery", "palengke", "stock" },
        buy     = { "buy", "purchase", "bili", "restock" },
    },
    -- Hiring workers
    Hire = {
        context = { "hire", "worker", "applicant", "employee", "staff", "trabahador", "aplikante" },
        hire    = { "hire", "accept", "recruit", "tanggap" },
        skip    = { "skip", "reject", "decline", "next", "pass", "reroll" },
    },
    -- Paying salaries
    Salary = {
        context = { "salary", "sahod", "suweldo", "sweldo", "wage", "payroll" },
        pay     = { "pay", "bayad", "give" },
    },
    -- Shoplifters
    Thief = {
        prompt = { "catch", "thief", "magnanakaw", "shoplift", "huli", "chase", "arrest" },
        npc    = { "thief", "magnanakaw", "shoplifter", "robber", "snatcher" },
    },
    -- Halloween event
    Halloween = {
        collect = { "candy", "kendi", "pumpkin", "kalabasa", "treat" },
        context = { "trick", "treat", "halloween" },
        give    = { "give", "treat", "candy", "bigay" },
    },
}

-- Worker rarities, lowest to highest.
local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

---------------------------------------------------------------------------
-- Services / environment
---------------------------------------------------------------------------
if not game:IsLoaded() then game.Loaded:Wait() end

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local TextService       = game:GetService("TextService")
local HttpService       = game:GetService("HttpService")
local GuiService        = game:GetService("GuiService")
local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local ENV = (typeof(getgenv) == "function" and getgenv()) or _G
if type(ENV.SariToolkit) == "table" and type(ENV.SariToolkit.Destroy) == "function" then
    pcall(ENV.SariToolkit.Destroy, ENV.SariToolkit) -- unload a previous copy first
end

-- Executor functions differ between executors; pick whatever exists.
local function pick(...)
    for i = 1, select("#", ...) do
        local f = select(i, ...)
        if type(f) == "function" then return f end
    end
    return nil
end

local X = {
    gethui              = pick(gethui, get_hidden_gui),
    protectGui          = pick(syn and syn.protect_gui, protect_gui),
    writefile           = pick(writefile),
    readfile            = pick(readfile),
    isfile              = pick(isfile),
    isfolder            = pick(isfolder),
    makefolder          = pick(makefolder),
    listfiles           = pick(listfiles),
    delfile             = pick(delfile),
    setclipboard        = pick(setclipboard, toclipboard, set_clipboard, syn and syn.write_clipboard),
    fireproximityprompt = pick(fireproximityprompt),
    fireclickdetector   = pick(fireclickdetector),
    firetouchinterest   = pick(firetouchinterest),
    firesignal          = pick(firesignal),
    getconnections      = pick(getconnections, get_signal_cons),
    hookmetamethod      = pick(hookmetamethod),
    getnamecallmethod   = pick(getnamecallmethod),
    newcclosure         = pick(newcclosure),
    checkcaller         = pick(checkcaller),
}

---------------------------------------------------------------------------
-- Look & feel
---------------------------------------------------------------------------
local Theme = {
    Window          = Color3.fromRGB(17, 17, 17),
    WindowAlpha     = 0.04,
    WindowStroke    = Color3.fromRGB(62, 62, 62),
    Card            = Color3.fromRGB(22, 22, 22),
    CardAlpha       = 0.1,
    CardStroke      = Color3.fromRGB(64, 64, 64),
    Divider         = Color3.fromRGB(46, 46, 46),
    Text            = Color3.fromRGB(245, 245, 245),
    SubText         = Color3.fromRGB(168, 168, 168),
    Muted           = Color3.fromRGB(115, 115, 115),
    Icon            = Color3.fromRGB(200, 200, 200),
    TabText         = Color3.fromRGB(180, 180, 180),
    TabActive       = Color3.fromRGB(36, 36, 36),
    TabStroke       = Color3.fromRGB(72, 72, 72),
    Field           = Color3.fromRGB(30, 30, 30),
    FieldHover      = Color3.fromRGB(44, 44, 44),
    FieldStroke     = Color3.fromRGB(72, 72, 72),
    ToggleOff       = Color3.fromRGB(30, 30, 30),
    ToggleOffStroke = Color3.fromRGB(150, 150, 150),
    ToggleOn        = Color3.fromRGB(100, 100, 100),
    ToggleOnStroke  = Color3.fromRGB(125, 125, 125),
    KnobOff         = Color3.fromRGB(205, 205, 205),
    KnobOn          = Color3.fromRGB(255, 255, 255),
    Premium = { Bg = Color3.fromRGB(20, 48, 33), Stroke = Color3.fromRGB(60, 185, 105), Text = Color3.fromRGB(125, 228, 160) },
    Hot     = { Bg = Color3.fromRGB(58, 28, 15), Stroke = Color3.fromRGB(232, 108, 48), Text = Color3.fromRGB(255, 148, 92) },
}

local FONT = {
    Regular = Enum.Font.Gotham,
    Medium  = Enum.Font.GothamMedium,
    Bold    = Enum.Font.GothamBold,
    Black   = Enum.Font.GothamBlack,
}

-- Lucide icons (48px spritesheets): { assetId, {w, h}, {x, y} }
local ICONS = {
    ["store"]              = {16898613777, {48, 48}, {404, 967}},
    ["package"]            = {16898613613, {48, 48}, {918, 196}},
    ["package-plus"]       = {16898613613, {48, 48}, {661, 918}},
    ["users"]              = {16898613869, {48, 48}, {967, 98}},
    ["user-plus"]          = {16898613869, {48, 48}, {918, 355}},
    ["user-x"]             = {16898613869, {48, 48}, {710, 820}},
    ["shield"]             = {16898613777, {48, 48}, {869, 0}},
    ["ghost"]              = {16898613353, {48, 48}, {869, 906}},
    ["settings"]           = {16898613777, {48, 48}, {771, 257}},
    ["archive"]            = {16898612629, {48, 48}, {918, 49}},
    ["circle-x"]           = {16898613044, {48, 48}, {820, 306}},
    ["circle-check"]       = {16898612819, {48, 48}, {869, 955}},
    ["wallet"]             = {16898613869, {48, 48}, {147, 967}},
    ["music"]              = {16898613613, {48, 48}, {967, 563}},
    ["crown"]              = {16898613044, {48, 48}, {404, 918}},
    ["flame"]              = {16898613353, {48, 48}, {967, 306}},
    ["minus"]              = {16898613613, {48, 48}, {771, 196}},
    ["x"]                  = {16898613869, {48, 48}, {869, 906}},
    ["hand-coins"]         = {16898613509, {48, 48}, {257, 869}},
    ["coins"]              = {16898613044, {48, 48}, {869, 612}},
    ["banknote"]           = {16898612629, {48, 48}, {453, 967}},
    ["bell"]               = {16898612819, {48, 48}, {820, 257}},
    ["keyboard"]           = {16898613509, {48, 48}, {453, 820}},
    ["save"]               = {16898613699, {48, 48}, {918, 453}},
    ["folder-open"]        = {16898613353, {48, 48}, {820, 759}},
    ["trash-2"]            = {16898613869, {48, 48}, {257, 918}},
    ["refresh-cw"]         = {16898613699, {48, 48}, {404, 869}},
    ["clock"]              = {16898613044, {48, 48}, {771, 661}},
    ["siren"]              = {16898613777, {48, 48}, {771, 147}},
    ["candy"]              = {16898612819, {48, 48}, {771, 759}},
    ["gift"]               = {16898613353, {48, 48}, {820, 955}},
    ["timer"]              = {16898613869, {48, 48}, {918, 0}},
    ["sliders-horizontal"] = {16898613777, {48, 48}, {820, 355}},
    ["chevron-down"]       = {16898612819, {48, 48}, {196, 918}},
    ["check"]              = {16898612819, {48, 48}, {710, 869}},
    ["info"]               = {16898613509, {48, 48}, {612, 869}},
    ["shopping-cart"]      = {16898613777, {48, 48}, {869, 257}},
    ["boxes"]              = {16898612819, {48, 48}, {196, 771}},
    ["gauge"]              = {16898613353, {48, 48}, {771, 955}},
    ["gem"]                = {16898613353, {48, 48}, {918, 857}},
    ["power"]              = {16898613699, {48, 48}, {820, 147}},
    ["eye"]                = {16898613353, {48, 48}, {771, 563}},
    ["file-text"]          = {16898613353, {48, 48}, {869, 355}},
    ["receipt"]            = {16898613699, {48, 48}, {869, 147}},
    ["copy"]               = {16898613044, {48, 48}, {918, 612}},
    ["sparkles"]           = {16898613777, {48, 48}, {918, 49}},
}

---------------------------------------------------------------------------
-- Small UI helpers
---------------------------------------------------------------------------
local Library = {
    Flags       = {},
    Options     = {},
    Connections = {},
    Running     = true,
    Visible     = true,
    Folder      = "SariSariToolkit",
}
local Flags = Library.Flags

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(Library.Connections, c)
    return c
end

local function new(class, props, children)
    local inst = Instance.new(class)
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v else inst[k] = v end
    end
    if children then
        for _, child in ipairs(children) do child.Parent = inst end
    end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function round()
    return new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function stroke(color, thickness, transparency)
    return new("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function pad(t, r, b, l)
    return new("UIPadding", {
        PaddingTop = UDim.new(0, t),
        PaddingRight = UDim.new(0, r or t),
        PaddingBottom = UDim.new(0, b or t),
        PaddingLeft = UDim.new(0, l or r or t),
    })
end

local function tween(obj, t, props)
    if t <= 0 then
        for k, v in pairs(props) do obj[k] = v end
        return nil
    end
    local tw = TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function hover(obj, prop, normal, over)
    connect(obj.MouseEnter, function() tween(obj, 0.15, { [prop] = over }) end)
    connect(obj.MouseLeave, function() tween(obj, 0.15, { [prop] = normal }) end)
end

local function Icon(name, size, color)
    local d = ICONS[name]
    if d then
        return new("ImageLabel", {
            Name = "Icon",
            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(size, size),
            Image = "rbxassetid://" .. d[1],
            ImageRectSize = Vector2.new(d[2][1], d[2][2]),
            ImageRectOffset = Vector2.new(d[3][1], d[3][2]),
            ImageColor3 = color or Theme.Icon,
            ScaleType = Enum.ScaleType.Fit,
        })
    end
    return new("TextLabel", {
        Name = "Icon",
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(size, size),
        Text = "•",
        Font = FONT.Bold,
        TextSize = size,
        TextColor3 = color or Theme.Icon,
    })
end

local function tint(icon, color, t)
    if icon:IsA("ImageLabel") then
        tween(icon, t or 0, { ImageColor3 = color })
    else
        tween(icon, t or 0, { TextColor3 = color })
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local WIN_W, WIN_H = 660, 440

local function guiParent()
    if X.gethui then
        local ok, h = pcall(X.gethui)
        if ok and typeof(h) == "Instance" then return h end
    end
    local probe = Instance.new("ScreenGui")
    local ok = pcall(function() probe.Parent = CoreGui end)
    probe:Destroy()
    if ok then return CoreGui end
    return PlayerGui
end

local Gui = new("ScreenGui", {
    Name = "SariSariToolkit",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 100,
})
if X.protectGui then pcall(X.protectGui, Gui) end
Gui.Parent = guiParent()

local Main = new("Frame", {
    Name = "Window",
    Parent = Gui,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    BackgroundColor3 = Theme.Window,
    BackgroundTransparency = Theme.WindowAlpha,
    BorderSizePixel = 0,
    Active = true,
}, { corner(14), stroke(Theme.WindowStroke, 1) })

local Scale = new("UIScale", { Parent = Main })
local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
local AUTO_SCALE = math.clamp(math.floor(math.min((viewport.X - 24) / WIN_W, (viewport.Y - 24) / WIN_H, 1) * 20) / 20, 0.5, 1)
local baseScale = AUTO_SCALE
Scale.Scale = baseScale

local function currentScale()
    local s = Scale.Scale
    return (s > 0) and s or 1
end

-- Rows size themselves to their wrapped text; keep the fitters so they can be re-run.
local Fitters = {}
local function refitAll()
    for _, fit in ipairs(Fitters) do pcall(fit) end
end

local function bindCanvas(scroller, layout, extra)
    local function update()
        scroller.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y / currentScale() + (extra or 0))
    end
    connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), update)
    update()
end

-- Dragging (mouse + touch). Returns a function telling whether the last press moved.
local function makeDraggable(handle, target)
    local dragging, moved, startInput, startPos = false, false, nil, nil
    connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            startInput, startPos = input.Position, target.Position
            local c
            c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    c:Disconnect()
                end
            end)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - startInput
            if d.Magnitude > 6 then moved = true end
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    return function() return moved end
end

-- Header ------------------------------------------------------------------
local Header = new("Frame", {
    Name = "Header",
    Parent = Main,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 64),
})
makeDraggable(Header, Main)

local Logo = new("Frame", {
    Parent = Header,
    Position = UDim2.fromOffset(14, 12),
    Size = UDim2.fromOffset(40, 40),
    BackgroundColor3 = Color3.fromRGB(8, 8, 8),
}, { corner(10), stroke(Color3.fromRGB(85, 85, 85), 1) })
new("TextLabel", {
    Parent = Logo,
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    Text = "T",
    Font = FONT.Black,
    TextSize = 24,
    TextColor3 = Color3.new(1, 1, 1),
})

new("TextLabel", {
    Parent = Header,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(64, 13),
    Size = UDim2.new(1, -370, 0, 22),
    Text = "Run a Sari Sari Store",
    Font = FONT.Bold,
    TextSize = 18,
    TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
})
new("TextLabel", {
    Parent = Header,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(64, 36),
    Size = UDim2.new(1, -370, 0, 16),
    Text = "Toolkit",
    Font = FONT.Regular,
    TextSize = 14,
    TextColor3 = Theme.SubText,
    TextXAlignment = Enum.TextXAlignment.Left,
})

local HeaderRight = new("Frame", {
    Parent = Header,
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -14, 0.5, 0),
    Size = UDim2.fromOffset(320, 32),
}, {
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

local function Badge(text, iconName, palette, order)
    local b = new("Frame", {
        Parent = HeaderRight,
        LayoutOrder = order,
        BackgroundColor3 = palette.Bg,
        Size = UDim2.fromOffset(0, 28),
        AutomaticSize = Enum.AutomaticSize.X,
    }, {
        corner(7),
        stroke(palette.Stroke, 1),
        pad(0, 12, 0, 10),
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    local ic = Icon(iconName, 14, palette.Text)
    ic.LayoutOrder = 1
    ic.Parent = b
    new("TextLabel", {
        Parent = b,
        LayoutOrder = 2,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(0, 28),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = text,
        Font = FONT.Bold,
        TextSize = 14,
        TextColor3 = palette.Text,
    })
    return b
end
Badge("Premium", "crown", Theme.Premium, 1)
Badge("Hot", "flame", Theme.Hot, 2)
new("Frame", { Parent = HeaderRight, LayoutOrder = 3, BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 1) })

local function CircleButton(iconName, order)
    local b = new("TextButton", {
        Parent = HeaderRight,
        LayoutOrder = order,
        Text = "",
        AutoButtonColor = false,
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = Color3.fromRGB(28, 28, 28),
    }, { round(), stroke(Color3.fromRGB(95, 95, 95), 1) })
    local ic = Icon(iconName, 16, Theme.Text)
    ic.AnchorPoint = Vector2.new(0.5, 0.5)
    ic.Position = UDim2.fromScale(0.5, 0.5)
    ic.Parent = b
    hover(b, "BackgroundColor3", Color3.fromRGB(28, 28, 28), Color3.fromRGB(48, 48, 48))
    return b
end
local MinimizeButton = CircleButton("minus", 4)
local CloseButton = CircleButton("x", 5)

-- Sidebar -----------------------------------------------------------------
local Sidebar = new("Frame", {
    Name = "Sidebar",
    Parent = Main,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(12, 64),
    Size = UDim2.new(0, 182, 1, -76),
})

local TabList = new("ScrollingFrame", {
    Parent = Sidebar,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 1, -62),
    CanvasSize = UDim2.new(),
    ScrollBarThickness = 2,
    ScrollBarImageColor3 = Color3.fromRGB(90, 90, 90),
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, { pad(2, 10, 2, 0) })
local TabListLayout = new("UIListLayout", { Parent = TabList, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
bindCanvas(TabList, TabListLayout, 4)

local Profile = new("Frame", {
    Parent = Sidebar,
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 0, 1, 0),
    Size = UDim2.new(1, -10, 0, 52),
    BackgroundColor3 = Color3.fromRGB(24, 24, 24),
    BackgroundTransparency = 0.1,
}, { corner(10), stroke(Color3.fromRGB(78, 78, 78), 1) })
local Avatar = new("ImageLabel", {
    Parent = Profile,
    Position = UDim2.fromOffset(12, 9),
    Size = UDim2.fromOffset(34, 34),
    BackgroundColor3 = Color3.fromRGB(40, 40, 40),
    Image = "",
}, { round() })
task.spawn(function()
    local ok, img = pcall(Players.GetUserThumbnailAsync, Players, LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
    if ok and Avatar.Parent then Avatar.Image = img end
end)
new("TextLabel", {
    Parent = Profile,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(56, 9),
    Size = UDim2.new(1, -62, 0, 18),
    Text = LocalPlayer.DisplayName,
    Font = FONT.Bold,
    TextSize = 15,
    TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
})
new("TextLabel", {
    Parent = Profile,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(56, 28),
    Size = UDim2.new(1, -62, 0, 16),
    Text = "@" .. LocalPlayer.Name,
    Font = FONT.Regular,
    TextSize = 13,
    TextColor3 = Theme.SubText,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
})

-- Content area ------------------------------------------------------------
local Content = new("Frame", {
    Name = "Content",
    Parent = Main,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(206, 64),
    Size = UDim2.new(1, -218, 1, -76),
    ClipsDescendants = true,
})

-- Floating button shown while minimised -----------------------------------
local Float = new("TextButton", {
    Parent = Gui,
    Visible = false,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 14),
    Size = UDim2.fromOffset(46, 46),
    BackgroundColor3 = Color3.fromRGB(10, 10, 10),
    AutoButtonColor = false,
    Text = "T",
    Font = FONT.Black,
    TextSize = 24,
    TextColor3 = Color3.new(1, 1, 1),
}, { corner(12), stroke(Color3.fromRGB(90, 90, 90), 1) })
local floatWasDragged = makeDraggable(Float, Float)

-- Notifications -----------------------------------------------------------
local NotifyHolder = new("Frame", {
    Parent = Gui,
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -16, 1, -16),
    Size = UDim2.fromOffset(290, 420),
}, {
    new("UIListLayout", {
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})
local notifyCount, liveNotes = 0, {}

local function notify(title, content, duration)
    if Flags.Notifications == false or not Library.Running then return end
    notifyCount += 1
    local card = new("Frame", {
        Parent = NotifyHolder,
        LayoutOrder = notifyCount,
        Size = UDim2.fromOffset(290, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Window,
        BackgroundTransparency = 1,
    }, {
        corner(10),
        pad(12, 14, 12, 14),
        new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    local st = stroke(Theme.WindowStroke, 1, 1)
    st.Parent = card
    local t = new("TextLabel", {
        Parent = card,
        LayoutOrder = 1,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = title or "Toolkit",
        Font = FONT.Bold,
        TextSize = 14,
        TextColor3 = Theme.Text,
        TextTransparency = 1,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    local b = new("TextLabel", {
        Parent = card,
        LayoutOrder = 2,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = content or "",
        Font = FONT.Regular,
        TextSize = 13,
        TextColor3 = Theme.SubText,
        TextTransparency = 1,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Visible = (content ~= nil and content ~= ""),
    })
    local function fade(a, dur)
        tween(card, dur, { BackgroundTransparency = 0.04 + 0.96 * a })
        tween(st, dur, { Transparency = a })
        tween(t, dur, { TextTransparency = a })
        tween(b, dur, { TextTransparency = a })
    end
    fade(0, 0.25)
    table.insert(liveNotes, card)
    if #liveNotes > 5 then
        local oldest = table.remove(liveNotes, 1)
        if oldest then oldest:Destroy() end
    end
    task.delay(duration or 4, function()
        if not card.Parent then return end
        fade(1, 0.3)
        task.wait(0.32)
        local i = table.find(liveNotes, card)
        if i then table.remove(liveNotes, i) end
        card:Destroy()
    end)
end
Library.Notify = function(_, title, content, duration) notify(title, content, duration) end

-- Close confirmation --------------------------------------------------------
local Overlay = new("TextButton", {
    Parent = Main,
    Visible = false,
    ZIndex = 20,
    Text = "",
    AutoButtonColor = false,
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 0.35,
}, { corner(14) })
local Dialog = new("Frame", {
    Parent = Overlay,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(330, 150),
    BackgroundColor3 = Theme.Window,
}, { corner(12), stroke(Theme.WindowStroke, 1) })
new("TextLabel", {
    Parent = Dialog,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(18, 16),
    Size = UDim2.new(1, -36, 0, 22),
    Text = "Close Toolkit?",
    Font = FONT.Bold,
    TextSize = 17,
    TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
})
new("TextLabel", {
    Parent = Dialog,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(18, 42),
    Size = UDim2.new(1, -36, 0, 44),
    Text = "All automations will stop and the window will be removed. Run the script again to reopen it.",
    Font = FONT.Regular,
    TextSize = 13,
    TextColor3 = Theme.SubText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
})
local function DialogButton(text, primary, xOffset)
    local bg = primary and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(34, 34, 34)
    local b = new("TextButton", {
        Parent = Dialog,
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, xOffset, 1, -16),
        Size = UDim2.fromOffset(96, 32),
        AutoButtonColor = false,
        BackgroundColor3 = bg,
        Text = text,
        Font = FONT.Bold,
        TextSize = 14,
        TextColor3 = primary and Color3.fromRGB(15, 15, 15) or Theme.Text,
    }, { corner(8), stroke(Theme.FieldStroke, 1, primary and 1 or 0) })
    return b
end
local CancelClose = DialogButton("Cancel", false, -120)
local ConfirmClose = DialogButton("Close", true, -16)

---------------------------------------------------------------------------
-- Tabs, sections and controls
---------------------------------------------------------------------------
local Tabs = {}
local TabMT = {}
TabMT.__index = TabMT
local SectionMT = {}
SectionMT.__index = SectionMT

local function selectTab(tab)
    for _, t in ipairs(Tabs) do
        local on = (t == tab)
        t.page.Visible = on
        tween(t.button, 0.2, { BackgroundTransparency = on and 0 or 1 })
        tween(t.stroke, 0.2, { Transparency = on and 0 or 1 })
        tween(t.bar, 0.2, { BackgroundTransparency = on and 0 or 1 })
        tween(t.label, 0.2, { TextColor3 = on and Theme.Text or Theme.TabText })
        tint(t.icon, on and Theme.Text or Theme.TabText, 0.2)
    end
    task.defer(refitAll)
end

local function AddTab(title, iconName)
    local index = #Tabs + 1
    local button = new("TextButton", {
        Parent = TabList,
        LayoutOrder = index,
        Text = "",
        AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Theme.TabActive,
        BackgroundTransparency = 1,
    }, { corner(8) })
    local st = stroke(Theme.TabStroke, 1, 1)
    st.Parent = button
    local bar = new("Frame", {
        Parent = button,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(3, 20),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, { corner(2) })
    local ic = Icon(iconName, 18, Theme.TabText)
    ic.AnchorPoint = Vector2.new(0, 0.5)
    ic.Position = UDim2.new(0, 14, 0.5, 0)
    ic.Parent = button
    local label = new("TextLabel", {
        Parent = button,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(44, 0),
        Size = UDim2.new(1, -50, 1, 0),
        Text = title,
        Font = FONT.Bold,
        TextSize = 16,
        TextColor3 = Theme.TabText,
        TextXAlignment = Enum.TextXAlignment.Left,
    })

    local page = new("ScrollingFrame", {
        Name = title,
        Parent = Content,
        Visible = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Color3.fromRGB(110, 110, 110),
        ScrollingDirection = Enum.ScrollingDirection.Y,
    }, { pad(2, 14, 14, 2) })
    local layout = new("UIListLayout", { Parent = page, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder })
    bindCanvas(page, layout, 16)

    local tab = setmetatable({
        button = button, stroke = st, bar = bar, icon = ic, label = label,
        page = page, order = 0,
    }, TabMT)
    table.insert(Tabs, tab)
    connect(button.MouseButton1Click, function() selectTab(tab) end)
    if index == 1 then selectTab(tab) end
    return tab
end

function TabMT:Section(title)
    if title then
        self.order += 1
        new("TextLabel", {
            Parent = self.page,
            LayoutOrder = self.order,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 22),
            Text = title,
            Font = FONT.Bold,
            TextSize = 17,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
    end
    self.order += 1
    local card = new("Frame", {
        Parent = self.page,
        LayoutOrder = self.order,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Card,
        BackgroundTransparency = Theme.CardAlpha,
    }, {
        corner(10),
        stroke(Theme.CardStroke, 1),
        new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    return setmetatable({ card = card, count = 0 }, SectionMT)
end

-- Builds one card row: [icon] title / description ............ [control slot]
local function buildRow(section, o, rightW)
    section.count += 1
    if section.count > 1 then
        new("Frame", {
            Parent = section.card,
            LayoutOrder = section.count * 2 - 1,
            BorderSizePixel = 0,
            BackgroundColor3 = Theme.Divider,
            Size = UDim2.new(1, 0, 0, 1),
        })
    end
    local row = new("Frame", {
        Parent = section.card,
        LayoutOrder = section.count * 2,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    }, { new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })

    local top = new("TextButton", {
        Parent = row,
        LayoutOrder = 1,
        Text = "",
        AutoButtonColor = false,
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 52),
    })
    if not o.NoHover then hover(top, "BackgroundTransparency", 1, 0.97) end

    local leftX, ic = 14, nil
    if o.Icon then
        ic = Icon(o.Icon, 20, Theme.Icon)
        ic.AnchorPoint = Vector2.new(0, 0.5)
        ic.Position = UDim2.new(0, 14, 0.5, 0)
        ic.Parent = top
        leftX = 48
    end
    local rightPad = (rightW > 0) and (rightW + 28) or 14

    local holder = new("Frame", {
        Parent = top,
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, leftX, 0.5, 0),
        Size = UDim2.new(1, -(leftX + rightPad), 0, 18),
    })
    local title = new("TextLabel", {
        Parent = holder,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 18),
        Text = o.Title or "",
        Font = FONT.Bold,
        TextSize = 15,
        TextColor3 = Theme.Text,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    local desc = new("TextLabel", {
        Parent = holder,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        Text = o.Description or "",
        Visible = type(o.Description) == "string" and o.Description ~= "",
        Font = FONT.Regular,
        TextSize = 13,
        TextColor3 = Theme.SubText,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    local slot = new("Frame", {
        Parent = top,
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(rightW, 30),
    })

    local function fit()
        local w = holder.AbsoluteSize.X / currentScale()
        if w < 8 then return end
        local th = math.ceil(TextService:GetTextSize(title.Text, title.TextSize, title.Font, Vector2.new(w, 10000)).Y)
        local h = th
        title.Size = UDim2.new(1, 0, 0, th)
        if desc.Visible then
            local dh = math.ceil(TextService:GetTextSize(desc.Text, desc.TextSize, desc.Font, Vector2.new(w, 10000)).Y)
            desc.Position = UDim2.fromOffset(0, th + 3)
            desc.Size = UDim2.new(1, 0, 0, dh)
            h = th + 3 + dh
        end
        holder.Size = UDim2.new(1, -(leftX + rightPad), 0, h)
        top.Size = UDim2.new(1, 0, 0, math.max(h + 28, 52))
    end
    connect(holder:GetPropertyChangedSignal("AbsoluteSize"), fit)
    table.insert(Fitters, fit)
    task.defer(fit)

    return { row = row, top = top, slot = slot, title = title, desc = desc, icon = ic, fit = fit, indent = leftX }
end

local function register(o, obj)
    obj.NoSave = o.NoSave
    if o.Flag then Library.Options[o.Flag] = obj end
    return obj
end

function SectionMT:Toggle(o)
    local r = buildRow(self, o, 50)
    local track = new("Frame", {
        Parent = r.slot,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(50, 26),
        BackgroundColor3 = Theme.ToggleOff,
    }, { round() })
    local tStroke = stroke(Theme.ToggleOffStroke, 1.5)
    tStroke.Parent = track
    local knob = new("Frame", {
        Parent = track,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 4, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = Theme.KnobOff,
    }, { round() })

    local value = false
    local obj = { Type = "Toggle" }
    local function render(t)
        tween(track, t, { BackgroundColor3 = value and Theme.ToggleOn or Theme.ToggleOff })
        tween(tStroke, t, { Color = value and Theme.ToggleOnStroke or Theme.ToggleOffStroke })
        tween(knob, t, {
            Position = value and UDim2.new(1, -22, 0.5, 0) or UDim2.new(0, 4, 0.5, 0),
            BackgroundColor3 = value and Theme.KnobOn or Theme.KnobOff,
        })
    end
    function obj:Set(v, silent)
        value = v and true or false
        if o.Flag then Flags[o.Flag] = value end
        render(silent and 0 or 0.22)
        if not silent and o.Callback then task.spawn(o.Callback, value) end
    end
    function obj:Get() return value end
    function obj:Serialize() return value end
    function obj:Deserialize(v) self:Set(v == true) end

    connect(r.top.MouseButton1Click, function() obj:Set(not value) end)
    obj:Set(o.Default == true, true)
    if value and o.Callback then task.spawn(o.Callback, value) end
    return register(o, obj)
end

function SectionMT:Slider(o)
    local r = buildRow(self, o, 64)
    local min, max, step = o.Min or 0, o.Max or 100, o.Step or 1
    local valueLabel = new("TextLabel", {
        Parent = r.slot,
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Font = FONT.Bold,
        TextSize = 14,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Right,
        Text = "",
    })
    local extra = new("Frame", {
        Parent = r.row,
        LayoutOrder = 2,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 24),
    })
    local bar = new("TextButton", {
        Parent = extra,
        Text = "",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(r.indent, 0),
        Size = UDim2.new(1, -(r.indent + 14), 0, 16),
    })
    local track = new("Frame", {
        Parent = bar,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = Color3.fromRGB(48, 48, 48),
    }, { round() })
    local fill = new("Frame", {
        Parent = track,
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(225, 225, 225),
    }, { round() })
    local knob = new("Frame", {
        Parent = track,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = Color3.new(1, 1, 1),
    }, { round(), stroke(Color3.fromRGB(25, 25, 25), 2) })

    local decimals = 0
    do
        local s = tostring(step)
        local dot = string.find(s, ".", 1, true)
        if dot then decimals = #s - dot end
    end
    local value
    local obj = { Type = "Slider" }
    local function format(v)
        local num = (decimals > 0) and string.format("%." .. decimals .. "f", v) or tostring(math.floor(v + 0.5))
        return (o.Prefix or "") .. num .. (o.Suffix or "")
    end
    function obj:Set(v, silent)
        v = tonumber(v) or min
        v = math.clamp(v, min, max)
        v = min + math.floor((v - min) / step + 0.5) * step
        v = math.clamp(tonumber(string.format("%.4f", v)), min, max)
        local changed = (v ~= value)
        value = v
        local a = (max > min) and (v - min) / (max - min) or 0
        fill.Size = UDim2.new(a, 0, 1, 0)
        knob.Position = UDim2.new(a, 0, 0.5, 0)
        valueLabel.Text = format(v)
        if o.Flag then Flags[o.Flag] = v end
        if changed and not silent and o.Callback then task.spawn(o.Callback, v) end
    end
    function obj:Get() return value end
    function obj:Serialize() return value end
    function obj:Deserialize(v) self:Set(v) end

    local dragging = false
    local function fromX(x)
        local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        obj:Set(min + a * (max - min))
    end
    connect(bar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            fromX(input.Position.X)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            fromX(input.Position.X)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    obj:Set(o.Default or min, true)
    return register(o, obj)
end

function SectionMT:Dropdown(o)
    local r = buildRow(self, o, o.Width or 150)
    local multi = (o.Multi == true)
    local options = table.clone(o.Options or {})
    local value = multi and {} or nil
    local open = false
    local items = {}
    local obj = { Type = "Dropdown" }

    local box = new("TextButton", {
        Parent = r.slot,
        Text = "",
        AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Field,
    }, { corner(8), stroke(Theme.FieldStroke, 1) })
    hover(box, "BackgroundColor3", Theme.Field, Theme.FieldHover)
    local shown = new("TextLabel", {
        Parent = box,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -34, 1, 0),
        Font = FONT.Medium,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = "",
    })
    local chevron = Icon("chevron-down", 16, Theme.SubText)
    chevron.AnchorPoint = Vector2.new(1, 0.5)
    chevron.Position = UDim2.new(1, -8, 0.5, 0)
    chevron.Parent = box

    local wrap = new("Frame", {
        Parent = r.row,
        LayoutOrder = 2,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        Visible = false,
    })
    local list = new("ScrollingFrame", {
        Parent = wrap,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(r.indent, 0),
        Size = UDim2.new(1, -(r.indent + 14), 1, -12),
        CanvasSize = UDim2.new(),
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Muted,
        ScrollingDirection = Enum.ScrollingDirection.Y,
    })
    local listLayout = new("UIListLayout", { Parent = list, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
    bindCanvas(list, listLayout, 0)

    local function selectedList()
        local out = {}
        for _, opt in ipairs(options) do
            if value[opt] then out[#out + 1] = opt end
        end
        return out
    end
    local function current()
        if multi then return selectedList() end
        return value
    end
    local function display()
        if multi then
            local sel = selectedList()
            shown.Text = (#sel > 0) and table.concat(sel, ", ") or "None"
        else
            shown.Text = (value ~= nil) and tostring(value) or (o.Placeholder or "Select...")
        end
        for opt, it in pairs(items) do
            local on = multi and (value[opt] == true) or (value == opt)
            it.check.Visible = on
            it.label.TextColor3 = on and Theme.Text or Theme.SubText
        end
    end
    local function commit(silent)
        if o.Flag then Flags[o.Flag] = current() end
        display()
        if not silent and o.Callback then task.spawn(o.Callback, current()) end
    end
    local function setOpen(v)
        open = v
        local h = math.max(math.min(#options, 6), 1) * 34
        wrap.Visible = v
        wrap.Size = UDim2.new(1, 0, 0, v and (h + 8) or 0)
        tween(chevron, 0.2, { Rotation = v and 180 or 0 })
    end
    local function rebuild()
        for _, it in pairs(items) do it.button:Destroy() end
        items = {}
        for i, opt in ipairs(options) do
            local b = new("TextButton", {
                Parent = list,
                LayoutOrder = i,
                Text = "",
                AutoButtonColor = false,
                Size = UDim2.new(1, -6, 0, 30),
                BackgroundColor3 = Theme.Field,
            }, { corner(6) })
            hover(b, "BackgroundColor3", Theme.Field, Theme.FieldHover)
            local l = new("TextLabel", {
                Parent = b,
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -40, 1, 0),
                Font = FONT.Medium,
                TextSize = 13,
                TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = tostring(opt),
            })
            local ck = Icon("check", 14, Theme.Text)
            ck.AnchorPoint = Vector2.new(1, 0.5)
            ck.Position = UDim2.new(1, -10, 0.5, 0)
            ck.Visible = false
            ck.Parent = b
            items[opt] = { button = b, label = l, check = ck }
            connect(b.MouseButton1Click, function()
                if multi then
                    value[opt] = (not value[opt]) or nil
                else
                    value = opt
                    setOpen(false)
                end
                commit()
            end)
        end
        if open then setOpen(true) end
        display()
    end

    function obj:Set(v, silent)
        if multi then
            value = {}
            if type(v) == "table" then
                for k, x in pairs(v) do
                    if type(k) == "number" then value[x] = true elseif x then value[k] = true end
                end
            end
        else
            value = v
        end
        commit(silent)
    end
    function obj:Get() return current() end
    function obj:Refresh(newOptions)
        options = table.clone(newOptions or {})
        if not multi and value ~= nil and not table.find(options, value) then value = nil end
        rebuild()
        commit(true)
    end
    function obj:Serialize() return current() end
    function obj:Deserialize(v) self:Set(v) end

    connect(box.MouseButton1Click, function() setOpen(not open) end)
    connect(r.top.MouseButton1Click, function() setOpen(not open) end)

    rebuild()
    obj:Set(o.Default, true)
    return register(o, obj)
end

function SectionMT:Input(o)
    local r = buildRow(self, o, o.Width or 140)
    local box = new("TextBox", {
        Parent = r.slot,
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Field,
        Text = "",
        PlaceholderText = o.Placeholder or "",
        PlaceholderColor3 = Theme.Muted,
        Font = FONT.Medium,
        TextSize = 13,
        TextColor3 = Theme.Text,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClipsDescendants = true,
    }, { corner(8), stroke(Theme.FieldStroke, 1), pad(0, 10, 0, 10) })

    local value = ""
    local obj = { Type = "Input" }
    function obj:Set(v, silent)
        v = tostring(v or "")
        local out = v
        if o.Numeric and v ~= "" then
            out = tonumber(v)
            if not out then box.Text = value return end
            v = tostring(out)
        end
        value = v
        box.Text = v
        if o.Flag then Flags[o.Flag] = out end
        if not silent and o.Callback then task.spawn(o.Callback, out) end
    end
    function obj:Get() return value end
    function obj:Serialize() return value end
    function obj:Deserialize(v) self:Set(v) end

    connect(box.FocusLost, function() obj:Set(box.Text) end)
    connect(r.top.MouseButton1Click, function() box:CaptureFocus() end)
    obj:Set(o.Default or "", true)
    return register(o, obj)
end

function SectionMT:Keybind(o)
    local r = buildRow(self, o, 110)
    local btn = new("TextButton", {
        Parent = r.slot,
        AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Field,
        Font = FONT.Medium,
        TextSize = 13,
        TextColor3 = Theme.Text,
        Text = "None",
    }, { corner(8), stroke(Theme.FieldStroke, 1) })
    hover(btn, "BackgroundColor3", Theme.Field, Theme.FieldHover)

    local key, listening = nil, false
    local obj = { Type = "Keybind" }
    function obj:Set(k, silent)
        if typeof(k) == "EnumItem" then k = k.Name end
        if type(k) ~= "string" then return end
        local ok = pcall(function() return Enum.KeyCode[k] end)
        if not ok then return end
        key = k
        btn.Text = k
        if o.Flag then Flags[o.Flag] = k end
        if not silent and o.Callback then task.spawn(o.Callback, k) end
    end
    function obj:Get() return key end
    function obj:Serialize() return key end
    function obj:Deserialize(v) self:Set(v) end

    local function listen()
        listening = true
        Library.Binding = true
        btn.Text = "Press a key..."
    end
    connect(btn.MouseButton1Click, listen)
    connect(r.top.MouseButton1Click, listen)
    connect(UserInputService.InputBegan, function(input)
        if not listening or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        listening = false
        if input.KeyCode == Enum.KeyCode.Escape then
            btn.Text = key or "None"
        else
            obj:Set(input.KeyCode)
        end
        task.defer(function() Library.Binding = false end)
    end)

    obj:Set(o.Default, true)
    return register(o, obj)
end

function SectionMT:Button(o)
    local text = o.ButtonText or "Run"
    local w = math.ceil(TextService:GetTextSize(text, 13, FONT.Medium, Vector2.new(1000, 30)).X) + 28
    local r = buildRow(self, o, w)
    local pill = new("TextButton", {
        Parent = r.slot,
        AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(38, 38, 38),
        Text = text,
        Font = FONT.Medium,
        TextSize = 13,
        TextColor3 = Theme.Text,
    }, { corner(8), stroke(Theme.FieldStroke, 1) })
    hover(pill, "BackgroundColor3", Color3.fromRGB(38, 38, 38), Color3.fromRGB(56, 56, 56))

    local busy = false
    local function fire()
        if busy or not o.Callback then return end
        busy = true
        task.spawn(function()
            local ok, err = pcall(o.Callback)
            if not ok then warn("[SariToolkit] " .. tostring(o.Title) .. ": " .. tostring(err)) end
            busy = false
        end)
    end
    connect(pill.MouseButton1Click, fire)
    connect(r.top.MouseButton1Click, fire)
    return { Type = "Button" }
end

function SectionMT:Paragraph(o)
    o.NoHover = true
    local r = buildRow(self, o, 0)
    local obj = { Type = "Paragraph" }
    function obj:Set(title, desc)
        if title then r.title.Text = title end
        if desc then
            r.desc.Text = desc
            r.desc.Visible = (desc ~= "")
        end
        r.fit()
    end
    return obj
end

---------------------------------------------------------------------------
-- Window behaviour: show / hide / minimise / close
---------------------------------------------------------------------------
function Library:SetVisible(v)
    Library.Visible = v
    if v then
        Main.Visible = true
        Float.Visible = false
        Scale.Scale = baseScale * 0.96
        local tw = tween(Scale, 0.18, { Scale = baseScale })
        if tw then tw.Completed:Once(refitAll) end
    else
        Main.Visible = false
        Overlay.Visible = false
        Float.Visible = true
    end
end

connect(MinimizeButton.MouseButton1Click, function() Library:SetVisible(false) end)
connect(Float.MouseButton1Click, function()
    if floatWasDragged() then return end
    Library:SetVisible(true)
end)
connect(CloseButton.MouseButton1Click, function() Overlay.Visible = true end)
connect(CancelClose.MouseButton1Click, function() Overlay.Visible = false end)
connect(ConfirmClose.MouseButton1Click, function() Library:Destroy() end)

connect(UserInputService.InputBegan, function(input, processed)
    if processed or Library.Binding then return end
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == (Flags.ToggleKey or "RightControl") then
        Library:SetVisible(not Library.Visible)
    end
end)

---------------------------------------------------------------------------
-- Config files
---------------------------------------------------------------------------
local CONFIG_DIR = Library.Folder .. "/configs"
local AUTOLOAD_FILE = Library.Folder .. "/autoload.txt"

local function fsReady()
    return X.writefile and X.readfile and X.isfile and X.isfolder and X.makefolder and true or false
end

local function ensureDirs()
    if not X.isfolder(Library.Folder) then X.makefolder(Library.Folder) end
    if not X.isfolder(CONFIG_DIR) then X.makefolder(CONFIG_DIR) end
end

local function cleanName(name)
    name = tostring(name or ""):gsub("[^%w%-%_ ]", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name:sub(1, 40)
end

function Library:SaveConfig(name)
    if not fsReady() then return false, "Your executor has no file functions." end
    name = cleanName(name)
    if name == "" then return false, "Type a config name first." end
    ensureDirs()
    local data = {}
    for flag, opt in pairs(Library.Options) do
        if not opt.NoSave and opt.Serialize then data[flag] = opt:Serialize() end
    end
    local ok, err = pcall(X.writefile, CONFIG_DIR .. "/" .. name .. ".json", HttpService:JSONEncode(data))
    if not ok then return false, tostring(err) end
    return true, name
end

function Library:LoadConfig(name)
    if not fsReady() then return false, "Your executor has no file functions." end
    name = cleanName(name)
    local path = CONFIG_DIR .. "/" .. name .. ".json"
    if name == "" or not X.isfile(path) then return false, "Config not found." end
    local ok, data = pcall(function() return HttpService:JSONDecode(X.readfile(path)) end)
    if not ok or type(data) ~= "table" then return false, "That config file is corrupted." end
    for flag, v in pairs(data) do
        local opt = Library.Options[flag]
        if opt and not opt.NoSave and opt.Deserialize then pcall(opt.Deserialize, opt, v) end
    end
    return true, name
end

function Library:DeleteConfig(name)
    if not (fsReady() and X.delfile) then return false, "Your executor can't delete files." end
    name = cleanName(name)
    local path = CONFIG_DIR .. "/" .. name .. ".json"
    if name == "" or not X.isfile(path) then return false, "Config not found." end
    local ok, err = pcall(X.delfile, path)
    return ok, ok and name or tostring(err)
end

function Library:ListConfigs()
    if not (fsReady() and X.listfiles) then return {} end
    pcall(ensureDirs)
    local out = {}
    local ok, files = pcall(X.listfiles, CONFIG_DIR)
    if ok and type(files) == "table" then
        for _, p in ipairs(files) do
            local n = tostring(p):match("([^/\\]+)%.json$")
            if n then out[#out + 1] = n end
        end
    end
    table.sort(out)
    return out
end

local function readAutoload()
    if not fsReady() then return nil end
    local ok, exists = pcall(X.isfile, AUTOLOAD_FILE)
    if not (ok and exists) then return nil end
    local ok2, text = pcall(X.readfile, AUTOLOAD_FILE)
    if not ok2 then return nil end
    text = cleanName(text)
    return (text ~= "") and text or nil
end

local function writeAutoload(name)
    if not fsReady() then return false end
    pcall(ensureDirs)
    return (pcall(X.writefile, AUTOLOAD_FILE, name or ""))
end

---------------------------------------------------------------------------
-- Automation engine
---------------------------------------------------------------------------
local VirtualUser = (function()
    local ok, s = pcall(game.GetService, game, "VirtualUser")
    return ok and s or nil
end)()
local VIM = (function()
    local ok, s = pcall(game.GetService, game, "VirtualInputManager")
    return ok and s or nil
end)()

local Engine = {
    buttons  = setmetatable({}, { __mode = "k" }),
    prompts  = setmetatable({}, { __mode = "k" }),
    clicks   = setmetatable({}, { __mode = "k" }),
    touches  = setmetatable({}, { __mode = "k" }),
    cooldown = setmetatable({}, { __mode = "k" }),
}

local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

local function clean(s)
    s = string.lower(tostring(s or ""))
    s = s:gsub("<[^>]->", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function concat(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, v in ipairs(list) do out[#out + 1] = v end
    end
    return out
end

local function matchAny(text, patterns)
    if not patterns then return false end
    for _, p in ipairs(patterns) do
        local ok, hit = pcall(string.find, text, p)
        if ok and hit then return true end
    end
    return false
end

local function ready(key, seconds)
    local now = os.clock()
    local last = Engine.cooldown[key]
    if last and now - last < seconds then return false end
    Engine.cooldown[key] = now
    return true
end

local function fullName(inst)
    local ok, n = pcall(inst.GetFullName, inst)
    return ok and n or tostring(inst)
end

-- World positions / range ---------------------------------------------------
local function rootPart()
    local c = LocalPlayer.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
end

local function worldPosition(inst)
    local p = inst
    if p:IsA("ProximityPrompt") or p:IsA("ClickDetector") then p = p.Parent end
    if not p then return nil end
    if p:IsA("Attachment") then return p.WorldPosition end
    if p:IsA("BasePart") then return p.Position end
    if p:IsA("Model") then
        local ok, cf = pcall(p.GetPivot, p)
        return ok and cf.Position or nil
    end
    local bp = p:FindFirstAncestorWhichIsA("BasePart")
    return bp and bp.Position or nil
end

local function inRange(inst)
    local hrp = rootPart()
    local pos = hrp and worldPosition(inst)
    if not pos then return false end
    return (pos - hrp.Position).Magnitude <= (Flags.InteractRange or 24)
end

-- Proximity prompts / click detectors / touch parts ----------------------------
local function promptText(pp)
    return clean(table.concat({ pp.ActionText, pp.ObjectText, pp.Name, pp.Parent and pp.Parent.Name or "" }, " "))
end

local function firePrompt(pp)
    if X.fireproximityprompt and pcall(X.fireproximityprompt, pp) then return true end
    return (pcall(function()
        pp:InputHoldBegin()
        task.wait((pp.HoldDuration or 0) + 0.05)
        pp:InputHoldEnd()
    end))
end

local function usePrompts(patterns, opts)
    opts = opts or {}
    local fired = 0
    for pp in pairs(Engine.prompts) do
        if pp.Parent and pp.Enabled then
            local text = promptText(pp)
            if matchAny(text, patterns) and not matchAny(text, opts.exclude) and inRange(pp) and ready(pp, opts.cooldown or 1.5) then
                task.spawn(firePrompt, pp)
                fired += 1
                if opts.max and fired >= opts.max then break end
            end
        end
    end
    return fired
end

local function useClicks(patterns)
    if not X.fireclickdetector then return 0 end
    local fired = 0
    for cd in pairs(Engine.clicks) do
        local parent = cd.Parent
        if parent and matchAny(clean(parent.Name .. " " .. (parent.Parent and parent.Parent.Name or "")), patterns)
            and inRange(cd) and ready(cd, 1.5) then
            pcall(X.fireclickdetector, cd)
            fired += 1
        end
    end
    return fired
end

local function useTouches(patterns)
    if not X.firetouchinterest then return 0 end
    local hrp = rootPart()
    if not hrp then return 0 end
    local fired = 0
    for part in pairs(Engine.touches) do
        if part.Parent and part:FindFirstChildWhichIsA("TouchTransmitter")
            and matchAny(clean(part.Name .. " " .. part.Parent.Name), patterns)
            and inRange(part) and ready(part, 1) then
            pcall(X.firetouchinterest, hrp, part, 0)
            pcall(X.firetouchinterest, hrp, part, 1)
            fired += 1
        end
    end
    return fired
end

-- GUI dialogs ---------------------------------------------------------------
local function isShown(gui)
    local o = gui
    while o do
        if o:IsA("GuiObject") then
            if not o.Visible then return false end
        elseif o:IsA("LayerCollector") then
            return o.Enabled
        end
        o = o.Parent
    end
    return false
end

local function buttonPieces(btn)
    local pieces = { clean(btn.Name) }
    if TEXT_CLASSES[btn.ClassName] and btn.Text ~= "" then pieces[#pieces + 1] = clean(btn.Text) end
    local n = 0
    for _, d in ipairs(btn:GetDescendants()) do
        if TEXT_CLASSES[d.ClassName] and d.Text ~= "" then
            pieces[#pieces + 1] = clean(d.Text)
            n += 1
            if n >= 6 then break end
        end
    end
    return pieces
end

local function buttonMatches(btn, matcher)
    for _, piece in ipairs(buttonPieces(btn)) do
        if type(matcher) == "function" then
            if matcher(piece) then return true end
        elseif matchAny(piece, matcher) then
            return true
        end
    end
    return false
end

-- All visible text inside `node`. With skipButtons, text on buttons is ignored.
local function containerText(node, skipButtons)
    local parts = {}
    if TEXT_CLASSES[node.ClassName] then parts[1] = node.Text end
    local n = 0
    for _, d in ipairs(node:GetDescendants()) do
        if TEXT_CLASSES[d.ClassName] and d.Visible and d.Text ~= "" then
            local onButton = skipButtons and (d:IsA("GuiButton") or d:FindFirstAncestorWhichIsA("GuiButton") ~= nil)
            if not onButton then
                parts[#parts + 1] = d.Text
                n += 1
                if n > 250 then break end
            end
        end
    end
    return clean(table.concat(parts, " | "))
end

-- Finds a visible button whose label matches `matcher` and whose surrounding
-- dialog (up to 5 parents up) mentions one of `context` and none of `exclude`.
local function findButton(context, matcher, exclude)
    for btn in pairs(Engine.buttons) do
        if btn.Parent and isShown(btn) and buttonMatches(btn, matcher) then
            if not context then return btn, btn.Parent end
            local node = btn.Parent
            for _ = 1, 5 do
                if not node or node:IsA("LayerCollector") then break end
                local text = containerText(node)
                if matchAny(text, context) then
                    if not matchAny(text, exclude) then return btn, node end
                    break
                end
                node = node.Parent
            end
        end
    end
    return nil, nil
end

local CLICK_SIGNALS = { "MouseButton1Click", "Activated", "MouseButton1Down", "MouseButton1Up" }

local function clickButton(btn)
    if X.getconnections then
        for _, name in ipairs(CLICK_SIGNALS) do
            local ok, conns = pcall(X.getconnections, btn[name])
            if ok and type(conns) == "table" and #conns > 0 then
                for _, c in ipairs(conns) do
                    pcall(function()
                        if c.Fire then c:Fire() elseif c.Function then task.spawn(c.Function) end
                    end)
                end
                return true
            end
        end
    end
    if X.firesignal then
        local ok = pcall(X.firesignal, btn.MouseButton1Click)
        pcall(X.firesignal, btn.Activated)
        if ok then return true end
    end
    if VIM then
        local pos = btn.AbsolutePosition + btn.AbsoluteSize / 2
        local screen = btn:FindFirstAncestorWhichIsA("ScreenGui")
        if screen and not screen.IgnoreGuiInset then pos += GuiService:GetGuiInset() end
        local ok = pcall(function()
            VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            task.wait(0.03)
            VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
        end)
        return ok
    end
    return false
end

local function press(btn, message)
    if not btn or not ready(btn, 0.8) then return false end
    local ok = clickButton(btn)
    if ok and message and Flags.ActionNotifs ~= false then notify("Toolkit", message, 2.5) end
    return ok
end

-- Tracking ------------------------------------------------------------------
local function onThiefSeen(what)
    if Flags.ThiefAlerts and ready("thiefAlert", 6) then
        notify("Thief alert", what .. " spotted near the store!", 4)
    end
end

local function track(inst)
    local cn = inst.ClassName
    if cn == "ProximityPrompt" then
        Engine.prompts[inst] = true
        task.defer(function()
            if inst.Parent and matchAny(promptText(inst), RULES.Thief.prompt) then onThiefSeen("A shoplifter") end
        end)
    elseif cn == "ClickDetector" then
        Engine.clicks[inst] = true
    elseif cn == "TouchTransmitter" then
        if inst.Parent and inst.Parent:IsA("BasePart") then Engine.touches[inst.Parent] = true end
    elseif cn == "Humanoid" then
        task.defer(function()
            local model = inst.Parent
            if model and matchAny(clean(model.Name), RULES.Thief.npc) then onThiefSeen(model.Name) end
        end)
    elseif cn == "TextButton" or cn == "ImageButton" then
        if not inst:IsDescendantOf(Gui) then Engine.buttons[inst] = true end
    end
end

local function untrack(inst)
    Engine.buttons[inst] = nil
    Engine.prompts[inst] = nil
    Engine.clicks[inst] = nil
    Engine.touches[inst] = nil
end

local function scan(root)
    for i, d in ipairs(root:GetDescendants()) do
        track(d)
        if i % 4000 == 0 then task.wait() end
    end
end

connect(PlayerGui.DescendantAdded, track)
connect(PlayerGui.DescendantRemoving, untrack)
connect(workspace.DescendantAdded, track)
connect(workspace.DescendantRemoving, untrack)
task.spawn(scan, PlayerGui)
task.spawn(scan, workspace)

---------------------------------------------------------------------------
-- Features (each runs on its own interval while its toggle is on)
---------------------------------------------------------------------------
local Features = {}
local function feature(def) table.insert(Features, def) end

-- Keeps keyword features away from the dialogs handled through remotes below.
local SERVE_EXCLUDE = { "utang", "credit", "kashg", "gcash", "beggar", "singer", "donat", "change" }

---------------------------------------------------------------------------
-- Remote-driven features (Main tab)
---------------------------------------------------------------------------
local GameRemotes

local function gameRemote(name)
    return GameRemotes and GameRemotes:FindFirstChild(name)
end

local function digits(s)
    return (tostring(s or ""):gsub("%D", ""))
end

-- Finds a visible button inside one of the game's ScreenGuis.
local function gameButton(guiName, matcher)
    local sg = PlayerGui:FindFirstChild(guiName)
    if not (sg and sg:IsA("LayerCollector") and sg.Enabled) then return nil, sg end
    for _, d in ipairs(sg:GetDescendants()) do
        if d:IsA("GuiButton") and isShown(d) and buttonMatches(d, matcher) then return d, sg end
    end
    return nil, sg
end

-- Answers a request. Pressing the game's own button lets its UI close normally;
-- if that button can't be found or pressed, the remote is fired directly.
local function answer(guiName, matcher, remoteName, ...)
    local btn, sg = gameButton(guiName, matcher)
    if btn and clickButton(btn) then return true end
    local r = gameRemote(remoteName)
    if not r then return false end
    local ok = pcall(r.FireServer, r, ...)
    if ok and sg and sg:IsA("LayerCollector") then sg.Enabled = false end
    return ok
end

local function actionNote(text)
    if Flags.ActionNotifs ~= false then notify("Toolkit", text, 2.5) end
end

local function whoFrom(data)
    if type(data) == "table" then
        return tostring(data.name or data.who or data.customer or "a customer")
    end
    return "a customer"
end

-- Register: CheckoutData carries the exact change the customer is owed.
local function onCheckout(data)
    if not Flags.AutoCheckout or type(data) ~= "table" or type(data.change) ~= "number" then return end
    local submit = gameRemote("SubmitChange")
    if not submit then return end
    -- close the register the same way the game does, then hand over the change
    local close = gameRemote("CloseWorldUI")
    if close and X.firesignal then pcall(X.firesignal, close.OnClientEvent, "register") end
    if pcall(submit.FireServer, submit, data.change) then
        local cashier = PlayerGui:FindFirstChild("CashierGui")
        if cashier and cashier:IsA("LayerCollector") then cashier.Enabled = false end
        pcall(function() UserInputService.ModalEnabled = false end)
        actionNote("Gave ₱" .. data.change .. " change")
    end
end

-- Utang (credit): Reject overrides Accept.
local function onUtang(data)
    if type(data) ~= "table" then return end
    if Flags.AutoRejectCredit then
        if answer("UtangGui", { "^decline", "refuse", "reject", "^no$", "hindi", "deny" }, "UtangDecide", false) then
            actionNote("Rejected utang from " .. whoFrom(data))
        end
    elseif Flags.AutoAcceptCredit then
        if answer("UtangGui", { "^accept", "approve", "^yes", "^oo$", "sige", "grant" }, "UtangDecide", true) then
            actionNote("Accepted utang from " .. whoFrom(data))
        end
    end
end

-- KashG: the game shows either the real or the fake phone-screen image.
local function onKashG(data)
    if not Flags.AutoKashG or type(data) ~= "table" then return end
    local id = digits(data.image)
    local fake = (id == GAME.KashGFake)
    local real = (id == GAME.KashGReal)
    if not (fake or real) then
        notify("KashG", "Unknown payment screen (" .. tostring(data.image) .. "). Left it for you.", 5)
        return
    end
    local ok = answer("KashGGui", real and { "^accept$" } or { "^decline$" }, "KashGDecide", real)
    if ok then
        actionNote((real and "Accepted" or "Declined FAKE") .. " KashG ₱" .. math.floor(tonumber(data.total) or 0) .. " from " .. whoFrom(data))
    end
end

-- Beggar / singers: BeggarGive(amount), 0 = "Wala".
local function onBeggar(data)
    if not Flags.AutoBeggar or type(data) ~= "table" or data.error then return end
    local amount = tonumber(digits(Flags.DonationAmount)) or 0
    local matcher = (amount > 0) and { "^give_" .. amount .. "$" } or { "^walabutton$", "^wala" }
    if answer("BeggarGui", matcher, "BeggarGive", amount) then
        if amount >= 500 then
            -- big amounts open a confirm dialog
            task.wait(0.25)
            local yes = gameButton("BeggarGui", { "^yesbutton$" })
            if yes then clickButton(yes) end
        end
        actionNote(amount > 0 and ("Gave ₱" .. amount .. " to a beggar / singer") or "Said \"Wala\" to a beggar / singer")
    end
end

-- Shoplifters: the game announces them with ShopliftAlert.
local function onShoplift()
    onThiefSeen("A shoplifter")
end

task.spawn(function()
    local root = ReplicatedStorage:WaitForChild("SariSariStore", 30)
    GameRemotes = root and root:WaitForChild("Remotes", 30)
    if not GameRemotes or not Library.Running then
        warn("[SariToolkit] Couldn't find SariSariStore.Remotes. Main tab features are inactive.")
        return
    end
    -- read the live KashG screen ids if the executor can require modules
    pcall(function()
        local cfg = require(root:WaitForChild("Modules"):WaitForChild("DataConfig"))
        if cfg.KASHG_SCREEN_REAL then GAME.KashGReal = digits(cfg.KASHG_SCREEN_REAL) end
        if cfg.KASHG_SCREEN_FAKE then GAME.KashGFake = digits(cfg.KASHG_SCREEN_FAKE) end
    end)
    local hooks = {
        CheckoutData  = onCheckout,
        UtangAsk      = onUtang,
        KashGAsk      = onKashG,
        BeggarRequest = onBeggar,
        ShopliftAlert = onShoplift,
    }
    for name, handler in pairs(hooks) do
        task.spawn(function()
            local r = GameRemotes:WaitForChild(name, 20)
            if not (r and r:IsA("RemoteEvent") and Library.Running) then return end
            connect(r.OnClientEvent, function(...)
                local args = table.pack(...)
                -- give the game's own UI a moment to open first
                task.delay(0.35, function()
                    if not Library.Running then return end
                    local ok, err = pcall(handler, table.unpack(args, 1, args.n))
                    if not ok then warn("[SariToolkit] " .. name .. ": " .. tostring(err)) end
                end)
            end)
        end)
    end
end)

feature({
    name = "Restock",
    interval = function() return Flags.RestockInterval or 3 end,
    enabled = function() return Flags.AutoRestock end,
    run = function()
        local r = RULES.Restock
        local n = usePrompts(r.prompt, { cooldown = Flags.RestockInterval or 3 }) + useClicks(r.prompt)
        if n > 0 and Flags.ActionNotifs ~= false and ready("restockNote", 15) then
            notify("Toolkit", "Restocking shelves...", 2)
        end
    end,
})

feature({
    name = "Supplier",
    interval = function() return Flags.BuyInterval or 2 end,
    enabled = function() return Flags.AutoBuyStock end,
    run = function()
        local r = RULES.Supplier
        press((findButton(r.context, r.buy, SERVE_EXCLUDE)), "Bought stock")
    end,
})

local function rarityRank(text)
    for i = #RARITIES, 1, -1 do
        if string.find(text, string.lower(RARITIES[i]), 1, true) then return i end
    end
    return 1
end

feature({
    name = "Hire",
    interval = 1,
    enabled = function() return Flags.AutoHire end,
    run = function()
        local r = RULES.Hire
        local hire, node = findButton(r.context, r.hire)
        if not hire then return end
        local rank = rarityRank(containerText(node, true))
        local need = table.find(RARITIES, Flags.MinRarity or "Common") or 1
        if rank >= need then
            press(hire, "Hired a " .. RARITIES[rank] .. " worker")
        elseif Flags.AutoSkipWorkers then
            press((findButton(r.context, r.skip)), "Skipped a " .. RARITIES[rank] .. " applicant")
        end
    end,
})

feature({
    name = "Salary",
    interval = 2,
    enabled = function() return Flags.AutoSalary end,
    run = function()
        local r = RULES.Salary
        press((findButton(r.context, r.pay)), "Paid worker salaries")
    end,
})

feature({
    name = "Thief",
    interval = 0.4,
    enabled = function() return Flags.AutoCatchThief end,
    run = function()
        local r = RULES.Thief
        local n = usePrompts(r.prompt, { cooldown = 0.8 }) + useClicks(r.prompt)
        if n > 0 and Flags.ActionNotifs ~= false and ready("catchNote", 5) then
            notify("Toolkit", "Catching a shoplifter!", 2.5)
        end
    end,
})

feature({
    name = "Candy",
    interval = 0.5,
    enabled = function() return Flags.AutoCandy end,
    run = function()
        local r = RULES.Halloween
        usePrompts(r.collect, { cooldown = 1 })
        useClicks(r.collect)
        useTouches(r.collect)
    end,
})

feature({
    name = "Treat",
    interval = 1,
    enabled = function() return Flags.AutoTreat end,
    run = function()
        local r = RULES.Halloween
        press((findButton(r.context, r.give)), "Gave a treat to a trick-or-treater")
    end,
})

task.spawn(function()
    while Library.Running do
        local now = os.clock()
        for _, f in ipairs(Features) do
            if f.enabled() then
                local every = (type(f.interval) == "function") and f.interval() or f.interval
                if now - (f.last or 0) >= every then
                    f.last = now
                    local ok, err = pcall(f.run)
                    if not ok and tostring(err) ~= f.lastError then
                        f.lastError = tostring(err)
                        warn("[SariToolkit] " .. f.name .. ": " .. f.lastError)
                    end
                end
            end
        end
        task.wait(0.1)
    end
end)

-- Anti-AFK
connect(LocalPlayer.Idled, function()
    if Flags.AntiAFK and VirtualUser then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

---------------------------------------------------------------------------
-- Developer tools: game dump + remote logger
---------------------------------------------------------------------------
local function dumpGameInfo()
    local out = {}
    local function add(s) out[#out + 1] = s end
    add("== Sari Sari Toolkit dump ==  PlaceId " .. tostring(game.PlaceId))

    add("")
    add("-- Remotes in ReplicatedStorage --")
    local count = 0
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d.ClassName == "UnreliableRemoteEvent" then
            add(d.ClassName .. "  " .. fullName(d))
            count += 1
            if count >= 400 then add("...") break end
        end
    end

    add("")
    add("-- Proximity prompts (unique ActionText | ObjectText) --")
    local seen = {}
    for pp in pairs(Engine.prompts) do
        if pp.Parent then
            local key = pp.ActionText .. " | " .. pp.ObjectText
            if not seen[key] then
                seen[key] = true
                add(string.format("[%s] [%s]  %s", pp.ActionText, pp.ObjectText, fullName(pp)))
            end
        end
    end

    add("")
    add("-- Click detectors (unique parent names) --")
    seen = {}
    for cd in pairs(Engine.clicks) do
        local p = cd.Parent
        if p and not seen[p.Name] then
            seen[p.Name] = true
            add(fullName(cd))
        end
    end

    add("")
    add("-- Buttons in your PlayerGui (name/text, per ScreenGui) --")
    for _, sg in ipairs(PlayerGui:GetChildren()) do
        if sg:IsA("LayerCollector") then
            local labels, uniq = {}, {}
            for _, d in ipairs(sg:GetDescendants()) do
                if d:IsA("GuiButton") then
                    local key = table.concat(buttonPieces(d), "/")
                    if not uniq[key] then
                        uniq[key] = true
                        labels[#labels + 1] = key
                        if #labels >= 80 then break end
                    end
                end
            end
            if #labels > 0 then add(sg.Name .. ":  " .. table.concat(labels, ",  ")) end
        end
    end
    return table.concat(out, "\n")
end

local Logger = { enabled = false, installed = false, lines = {} }

local function serialize(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "Instance" then return fullName(v) end
    if t == "string" then return string.format("%q", v) end
    if t == "table" then
        if depth >= 2 then return "{...}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n += 1
            if n > 12 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = "[" .. serialize(k, depth + 1) .. "]=" .. serialize(val, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

function Logger.record(remote, method, args)
    local parts = {}
    for i = 1, args.n do parts[i] = serialize(args[i]) end
    local line = string.format("%s  %s:%s(%s)", os.date("%H:%M:%S"), fullName(remote), method, table.concat(parts, ", "))
    table.insert(Logger.lines, line)
    if #Logger.lines > 300 then table.remove(Logger.lines, 1) end
    print("[RemoteLog] " .. line)
end

function Logger.install()
    if Logger.installed then return true end
    if not (X.hookmetamethod and X.getnamecallmethod) then return false end
    local wrap = X.newcclosure or function(f) return f end
    local old
    old = X.hookmetamethod(game, "__namecall", wrap(function(self, ...)
        if Logger.enabled then
            local method = X.getnamecallmethod()
            if (method == "FireServer" or method == "InvokeServer")
                and typeof(self) == "Instance"
                and not (X.checkcaller and X.checkcaller()) then
                task.spawn(Logger.record, self, method, table.pack(...))
            end
        end
        return old(self, ...)
    end))
    Logger.installed = true
    return true
end

local function exportText(text, fileName)
    local where = {}
    if X.setclipboard and pcall(X.setclipboard, text) then where[#where + 1] = "your clipboard" end
    if fsReady() then
        pcall(ensureDirs)
        if pcall(X.writefile, Library.Folder .. "/" .. fileName, text) then
            where[#where + 1] = "workspace/" .. Library.Folder .. "/" .. fileName
        end
    end
    return where
end

---------------------------------------------------------------------------
-- Build the hub
---------------------------------------------------------------------------
-- Main
local MainTab = AddTab("Main", "store")

local Customers = MainTab:Section("Customers")
Customers:Toggle({
    Title = "Auto Checkout (Exact Change)",
    Description = "When you open the register, instantly hands the customer the exact change.",
    Icon = "shopping-cart",
    Flag = "AutoCheckout",
})
Customers:Toggle({
    Title = "Auto-Accept Credit (Utang)",
    Description = "Automatically ACCEPTS all customer credit/utang requests.",
    Icon = "hand-coins",
    Flag = "AutoAcceptCredit",
})
Customers:Toggle({
    Title = "Auto-Reject Credit (Utang)",
    Description = "Automatically REJECTS all customer credit/utang requests. Overrides Accept if both are on.",
    Icon = "circle-x",
    Flag = "AutoRejectCredit",
})
Customers:Toggle({
    Title = "Auto KashG Payment",
    Description = "Verifies GCash payment receipts and automatically rejects fake receipts.",
    Icon = "wallet",
    Flag = "AutoKashG",
})

local Beggars = MainTab:Section("Beggar / Singer")
Beggars:Toggle({
    Title = "Auto Respond to Beggar / Singer",
    Description = "Automatically responds to beggar and singer donation requests with the amount below.",
    Icon = "music",
    Flag = "AutoBeggar",
})
Beggars:Dropdown({
    Title = "Donation Amount",
    Description = "How much to give. Pick Decline to turn them away.",
    Icon = "coins",
    Options = { "Decline", "₱1", "₱5", "₱10", "₱20", "₱50", "₱100" },
    Default = "₱5",
    Width = 120,
    Flag = "DonationAmount",
})

-- Restock
local RestockTab = AddTab("Restock", "package")

local Shelves = RestockTab:Section("Shelves")
Shelves:Toggle({
    Title = "Auto Restock Shelves",
    Description = "Refills your shelves using the restock prompts within your interaction range.",
    Icon = "package-plus",
    Flag = "AutoRestock",
})
Shelves:Slider({
    Title = "Restock Interval",
    Description = "Seconds between restock attempts.",
    Icon = "timer",
    Min = 1, Max = 30, Step = 1, Default = 3, Suffix = "s",
    Flag = "RestockInterval",
})

local Supplier = RestockTab:Section("Supplier")
Supplier:Toggle({
    Title = "Auto Buy Stock",
    Description = "Presses Buy whenever the supplier / stock menu is open.",
    Icon = "boxes",
    Flag = "AutoBuyStock",
})
Supplier:Slider({
    Title = "Buy Interval",
    Description = "Seconds between purchases.",
    Icon = "gauge",
    Min = 1, Max = 20, Step = 1, Default = 2, Suffix = "s",
    Flag = "BuyInterval",
})

-- Workers
local WorkersTab = AddTab("Workers", "users")

local Hiring = WorkersTab:Section("Hiring")
Hiring:Toggle({
    Title = "Auto Hire Workers",
    Description = "Hires applicants that meet the minimum rarity below.",
    Icon = "user-plus",
    Flag = "AutoHire",
})
Hiring:Dropdown({
    Title = "Minimum Rarity",
    Description = "Lowest rarity the auto-hirer will accept.",
    Icon = "gem",
    Options = RARITIES,
    Default = "Rare",
    Width = 130,
    Flag = "MinRarity",
})
Hiring:Toggle({
    Title = "Skip Lower Rarities",
    Description = "Skips / rerolls applicants below the minimum rarity.",
    Icon = "user-x",
    Flag = "AutoSkipWorkers",
})

local Payroll = WorkersTab:Section("Payroll")
Payroll:Toggle({
    Title = "Auto Pay Salaries",
    Description = "Pays your workers whenever the salary prompt appears.",
    Icon = "banknote",
    Flag = "AutoSalary",
})

-- Defense
local DefenseTab = AddTab("Defense", "shield")

local Shoplifters = DefenseTab:Section("Shoplifters")
Shoplifters:Toggle({
    Title = "Auto Catch Thieves",
    Description = "Triggers catch prompts on shoplifters inside your interaction range.",
    Icon = "siren",
    Flag = "AutoCatchThief",
})
Shoplifters:Toggle({
    Title = "Thief Alerts",
    Description = "Shows a notification when a thief shows up.",
    Icon = "bell",
    Default = true,
    Flag = "ThiefAlerts",
})

-- Halloween
local HalloweenTab = AddTab("Halloween", "ghost")

local Event = HalloweenTab:Section("Halloween Event")
Event:Toggle({
    Title = "Auto Collect Candy",
    Description = "Collects candy and pumpkins within your interaction range.",
    Icon = "candy",
    Flag = "AutoCandy",
})
Event:Toggle({
    Title = "Auto Treat Trick-or-Treaters",
    Description = "Gives a treat whenever a trick-or-treater asks.",
    Icon = "gift",
    Flag = "AutoTreat",
})

-- Settings
local SettingsTab = AddTab("Settings", "settings")

local Interface = SettingsTab:Section("Interface")
Interface:Keybind({
    Title = "Toggle UI Key",
    Description = "Shows or hides the toolkit window.",
    Icon = "keyboard",
    Default = "RightControl",
    Flag = "ToggleKey",
})
Interface:Slider({
    Title = "UI Scale",
    Description = "Size of the toolkit window.",
    Icon = "sliders-horizontal",
    Min = 0.5, Max = 1.5, Step = 0.05, Default = AUTO_SCALE, Suffix = "x",
    Flag = "UIScale",
    Callback = function(v)
        baseScale = v
        Scale.Scale = v
        task.defer(refitAll)
    end,
})
Interface:Toggle({
    Title = "Notifications",
    Description = "Show toast notifications in the bottom-right corner.",
    Icon = "bell",
    Default = true,
    Flag = "Notifications",
})
Interface:Toggle({
    Title = "Action Notifications",
    Description = "Show a toast every time the toolkit answers or clicks something for you.",
    Icon = "eye",
    Default = true,
    Flag = "ActionNotifs",
})

local Automation = SettingsTab:Section("Automation")
Automation:Slider({
    Title = "Interaction Range",
    Description = "Only prompts and items this close to your character are used.",
    Icon = "gauge",
    Min = 6, Max = 100, Step = 1, Default = 24, Suffix = " studs",
    Width = 80,
    Flag = "InteractRange",
})
Automation:Toggle({
    Title = "Anti-AFK",
    Description = "Stops Roblox from kicking you for being idle.",
    Icon = "clock",
    Default = true,
    Flag = "AntiAFK",
})

local Developer = SettingsTab:Section("Developer")
Developer:Paragraph({
    Title = "How the features work",
    Description = "Main tab features listen to the game's own remotes. Restock, Workers, Defense and Halloween match prompts and buttons by the keywords in RULES at the top of the script. If one of those doesn't react, dump the game info below and adjust RULES.",
    Icon = "info",
})
Developer:Button({
    Title = "Dump Game Info",
    Description = "Lists remotes, proximity prompts and GUI buttons. Copies it and saves dump.txt.",
    Icon = "file-text",
    ButtonText = "Dump",
    Callback = function()
        local text = dumpGameInfo()
        for line in string.gmatch(text, "[^\n]+") do print(line) end
        local where = exportText(text, "dump.txt")
        notify("Game info dumped", (#where > 0 and ("Saved to " .. table.concat(where, " and ") .. ". ") or "") .. "Also printed to the console (F9).", 6)
    end,
})
Developer:Toggle({
    Title = "Remote Logger",
    Description = "Logs every FireServer / InvokeServer the game makes while you play by hand.",
    Icon = "receipt",
    NoSave = true,
    Callback = function(on)
        if on and not Logger.install() then
            Logger.enabled = false
            notify("Remote Logger", "Your executor doesn't support hookmetamethod.", 5)
            return
        end
        Logger.enabled = on
        if on then notify("Remote Logger", "Logging. Do the action by hand (e.g. reject an utang), then press Copy Log.", 6) end
    end,
})
Developer:Button({
    Title = "Copy Remote Log",
    Description = "Copies the last 300 logged remote calls and saves remote_log.txt.",
    Icon = "copy",
    ButtonText = "Copy",
    Callback = function()
        if #Logger.lines == 0 then
            notify("Remote Logger", "Nothing logged yet.", 3)
            return
        end
        local where = exportText(table.concat(Logger.lines, "\n"), "remote_log.txt")
        notify("Remote Logger", #Logger.lines .. " calls saved to " .. (#where > 0 and table.concat(where, " and ") or "the console only") .. ".", 5)
    end,
})

local Danger = SettingsTab:Section("Toolkit")
Danger:Button({
    Title = "Unload Toolkit",
    Description = "Stops every automation and removes the window.",
    Icon = "power",
    ButtonText = "Unload",
    Callback = function() Library:Destroy() end,
})

-- Config
local ConfigTab = AddTab("Config", "archive")

local Configs = ConfigTab:Section("Configs")
local ConfigName = Configs:Input({
    Title = "Config Name",
    Description = "Name to save your current settings under.",
    Icon = "file-text",
    Placeholder = "my-config",
    NoSave = true,
})
local ConfigList
Configs:Button({
    Title = "Save Config",
    Description = "Saves every toggle, slider, dropdown and keybind.",
    Icon = "save",
    ButtonText = "Save",
    Callback = function()
        local ok, result = Library:SaveConfig(ConfigName:Get())
        if ok then
            ConfigList:Refresh(Library:ListConfigs())
            ConfigList:Set(result, true)
            notify("Config saved", 'Saved "' .. result .. '".', 3)
        else
            notify("Couldn't save", result, 4)
        end
    end,
})
ConfigList = Configs:Dropdown({
    Title = "Saved Configs",
    Description = "Pick a config to load or delete.",
    Icon = "folder-open",
    Options = Library:ListConfigs(),
    Placeholder = "None",
    NoSave = true,
})
Configs:Button({
    Title = "Load Config",
    Description = "Applies the selected config.",
    Icon = "refresh-cw",
    ButtonText = "Load",
    Callback = function()
        local ok, result = Library:LoadConfig(ConfigList:Get())
        notify(ok and "Config loaded" or "Couldn't load", ok and ('Loaded "' .. result .. '".') or result, 3)
    end,
})
Configs:Button({
    Title = "Delete Config",
    Description = "Deletes the selected config file.",
    Icon = "trash-2",
    ButtonText = "Delete",
    Callback = function()
        local ok, result = Library:DeleteConfig(ConfigList:Get())
        if ok then ConfigList:Refresh(Library:ListConfigs()) end
        notify(ok and "Config deleted" or "Couldn't delete", ok and ('Deleted "' .. result .. '".') or result, 3)
    end,
})
Configs:Button({
    Title = "Refresh List",
    Description = "Re-reads the configs folder.",
    Icon = "refresh-cw",
    ButtonText = "Refresh",
    Callback = function() ConfigList:Refresh(Library:ListConfigs()) end,
})

local Startup = ConfigTab:Section("Startup")
local AutoloadInfo = Startup:Paragraph({
    Title = "Auto-load",
    Description = "No config is loaded automatically.",
    Icon = "sparkles",
})
local function showAutoload()
    local name = readAutoload()
    AutoloadInfo:Set(nil, name and ('"' .. name .. '" loads every time the toolkit starts.') or "No config is loaded automatically.")
end
Startup:Button({
    Title = "Auto-load Selected Config",
    Description = "Loads the selected config every time the toolkit starts.",
    Icon = "check",
    ButtonText = "Set",
    Callback = function()
        local name = ConfigList:Get()
        if not name then
            notify("Auto-load", "Select a saved config first.", 3)
            return
        end
        if writeAutoload(name) then showAutoload() end
    end,
})
Startup:Button({
    Title = "Clear Auto-load",
    Description = "Stop loading a config on start.",
    Icon = "circle-x",
    ButtonText = "Clear",
    Callback = function()
        writeAutoload("")
        showAutoload()
    end,
})

---------------------------------------------------------------------------
-- Startup / teardown
---------------------------------------------------------------------------
function Library:Destroy()
    if not Library.Running then return end
    Library.Running = false
    Logger.enabled = false -- the hook (if any) becomes a pass-through
    for _, c in ipairs(Library.Connections) do pcall(function() c:Disconnect() end) end
    table.clear(Library.Connections)
    pcall(function() Gui:Destroy() end)
    if ENV.SariToolkit == Library then ENV.SariToolkit = nil end
end

ENV.SariToolkit = Library

task.defer(function()
    showAutoload()
    local name = readAutoload()
    if name then
        local ok = Library:LoadConfig(name)
        if ok then notify("Config loaded", 'Auto-loaded "' .. name .. '".', 3) end
    end
    notify("Run a Sari Sari Store", "Toolkit loaded. Press " .. tostring(Flags.ToggleKey or "RightControl") .. " to hide or show it.", 5)
end)

return Library
