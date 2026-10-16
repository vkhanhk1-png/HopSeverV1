-- Hop Sever V1
-- Run in an executor that supports loadstring, game:HttpGet, and (optionally)
-- queue_on_teleport for automatic reactivation after a successful teleport.

local SCRIPT_SOURCE = [====[
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlaceId = game.PlaceId
local CurrentJobId = game.JobId
local ExecutorEnv = (getgenv and getgenv()) or _G
local SCRIPT_SOURCE = ExecutorEnv.__HOP_SOURCE
local IsResume = ExecutorEnv.__HOP_RESUME == true
ExecutorEnv.__HOP_RESUME = false

local MAX_RETRIES = 4
local RETRY_DELAY = 2
local IsBusy = false
local IsHopPending = false
local RetryScheduled = false
local CurrentAttempt = 1
local FoundServerId = nil

local Colors = {
    background = Color3.fromRGB(12, 18, 31),
    panel = Color3.fromRGB(19, 29, 46),
    panelLight = Color3.fromRGB(24, 38, 57),
    blue = Color3.fromRGB(67, 153, 255),
    cyan = Color3.fromRGB(75, 220, 230),
    mint = Color3.fromRGB(123, 238, 205),
    white = Color3.fromRGB(235, 243, 252),
    muted = Color3.fromRGB(139, 157, 181),
    error = Color3.fromRGB(255, 133, 151),
}

local function make(className, parent, properties)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function addCorner(parent, radius)
    return make("UICorner", parent, {
        CornerRadius = UDim.new(0, radius),
    })
end

local function addStroke(parent, color, transparency, thickness)
    return make("UIStroke", parent, {
        Color = color,
        Transparency = transparency,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function tween(object, duration, properties, style, direction)
    local animation = TweenService:Create(
        object,
        TweenInfo.new(
            duration,
            style or Enum.EasingStyle.Quart,
            direction or Enum.EasingDirection.Out
        ),
        properties
    )
    animation:Play()
    return animation
end

if CoreGui:FindFirstChild("ServerScannerMini") then
    CoreGui.ServerScannerMini:Destroy()
end

local ScreenGui = make("ScreenGui", nil, {
    Name = "ServerScannerMini",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 1000,
})

local parentSuccess = pcall(function()
    ScreenGui.Parent = CoreGui
end)
if not parentSuccess then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local Shadow = make("Frame", ScreenGui, {
    Name = "SoftShadow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 5),
    Size = UDim2.new(0, 326, 0, 302),
    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
    BackgroundTransparency = 0.48,
    BorderSizePixel = 0,
    ZIndex = 1,
})
addCorner(Shadow, 19)

local MainFrame = make("Frame", ScreenGui, {
    Name = "MainFrame",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, 320, 0, 296),
    BackgroundColor3 = Colors.background,
    BorderSizePixel = 0,
    Active = true,
    ClipsDescendants = true,
    ZIndex = 2,
})
addCorner(MainFrame, 17)

make("UIGradient", MainFrame, {
    Rotation = 135,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 29, 47)),
        ColorSequenceKeypoint.new(0.52, Colors.background),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 31, 48)),
    }),
})

local MainStroke = addStroke(MainFrame, Colors.cyan, 0.42, 1.25)
make("UIGradient", MainStroke, {
    Rotation = 25,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Colors.blue),
        ColorSequenceKeypoint.new(0.54, Colors.cyan),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 182, 255)),
    }),
})

local Accent = make("Frame", MainFrame, {
    Name = "TopAccent",
    Position = UDim2.new(0, 18, 0, 0),
    Size = UDim2.new(0, 74, 0, 3),
    BackgroundColor3 = Colors.cyan,
    BorderSizePixel = 0,
    ZIndex = 4,
})
addCorner(Accent, 3)
make("UIGradient", Accent, {
    Color = ColorSequence.new(Colors.blue, Colors.mint),
})

local DragHandle = make("Frame", MainFrame, {
    Name = "DragHandle",
    Position = UDim2.new(0, 0, 0, 0),
    Size = UDim2.new(1, 0, 0, 70),
    BackgroundTransparency = 1,
    Active = true,
    ZIndex = 3,
})

local AdminBadge = make("Frame", MainFrame, {
    Name = "AdminBadge",
    Position = UDim2.new(0, 18, 0, 10),
    Size = UDim2.new(0, 49, 0, 18),
    BackgroundColor3 = Colors.blue,
    BorderSizePixel = 0,
    ZIndex = 4,
})
addCorner(AdminBadge, 6)
make("UIGradient", AdminBadge, {
    Color = ColorSequence.new(Colors.blue, Colors.cyan),
})
make("TextLabel", AdminBadge, {
    Name = "AdminBadgeText",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    Text = "ADMIN",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    TextSize = 8,
    Font = Enum.Font.GothamBlack,
    ZIndex = 5,
})

local AdminLabel = make("TextLabel", MainFrame, {
    Name = "AdminLabel",
    Position = UDim2.new(0, 75, 0, 9),
    Size = UDim2.new(0, 92, 0, 20),
    BackgroundTransparency = 1,
    Text = "RIVEN",
    TextColor3 = Colors.white,
    TextSize = 13,
    Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4,
})

make("TextLabel", MainFrame, {
    Name = "TikTokPrefix",
    Position = UDim2.new(0, 18, 0, 32),
    Size = UDim2.new(0, 41, 0, 13),
    BackgroundTransparency = 1,
    Text = "TIKTOK",
    TextColor3 = Colors.cyan,
    TextSize = 8,
    Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4,
})

local TikTokLabel = make("TextLabel", MainFrame, {
    Name = "TikTokLabel",
    Position = UDim2.new(0, 61, 0, 31),
    Size = UDim2.new(0, 140, 0, 14),
    BackgroundTransparency = 1,
    Text = "@rivenxadr",
    TextColor3 = Colors.white,
    TextSize = 10,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4,
})

local TitleLabel = make("TextLabel", MainFrame, {
    Name = "TitleLabel",
    Position = UDim2.new(0, 18, 0, 49),
    Size = UDim2.new(1, -36, 0, 21),
    BackgroundTransparency = 1,
    Text = "HOP SERVER V1",
    TextColor3 = Colors.white,
    TextSize = 16,
    Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4,
})

local LiveDot = make("Frame", MainFrame, {
    Name = "LiveDot",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -19, 0, 53),
    Size = UDim2.new(0, 7, 0, 7),
    BackgroundColor3 = Colors.mint,
    BorderSizePixel = 0,
    ZIndex = 4,
})
addCorner(LiveDot, 4)

local function makeCard(name, position, size, fillColor)
    local card = make("Frame", MainFrame, {
        Name = name,
        Position = position,
        Size = size,
        BackgroundColor3 = fillColor,
        BorderSizePixel = 0,
        ZIndex = 3,
    })
    addCorner(card, 11)
    addStroke(card, Color3.fromRGB(78, 116, 154), 0.78, 1)
    return card
end

local CurrentCard = makeCard(
    "CurrentServerCard",
    UDim2.new(0, 15, 0, 80),
    UDim2.new(1, -30, 0, 46),
    Colors.panel
)

local CurrentLabel = make("TextLabel", CurrentCard, {
    Name = "CurrentLabel",
    Position = UDim2.new(0, 12, 0, 8),
    Size = UDim2.new(1, -94, 0, 11),
    BackgroundTransparency = 1,
    Text = "SERVER HIỆN TẠI",
    TextColor3 = Colors.muted,
    TextSize = 8,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4,
})

local CurrentText = make("TextLabel", CurrentCard, {
    Name = "CurrentText",
    Position = UDim2.new(0, 12, 0, 21),
    Size = UDim2.new(1, -24, 0, 16),
    BackgroundTransparency = 1,
    Text = "Đang cập nhật...",
    TextColor3 = Colors.white,
    TextSize = 11,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4,
})

local CurrentBadge = make("TextLabel", CurrentCard, {
    Name = "CurrentBadge",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -12, 0.5, 0),
    Size = UDim2.new(0, 53, 0, 21),
    BackgroundColor3 = Color3.fromRGB(27, 47, 67),
    BorderSizePixel = 0,
    Text = "LIVE",
    TextColor3 = Colors.cyan,
    TextSize = 8,
    Font = Enum.Font.GothamBold,
    ZIndex = 4,
})
addCorner(CurrentBadge, 7)

local TargetCard = makeCard(
    "TargetServerCard",
    UDim2.new(0, 15, 0, 137),
    UDim2.new(1, -30, 0, 58),
    Colors.panelLight
)
make("UIGradient", TargetCard, {
    Rotation = 0,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 42, 59)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(21, 34, 51)),
    }),
})
local TargetStroke = addStroke(TargetCard, Colors.blue, 0.65, 1)
make("UIGradient", TargetStroke, {
    Color = ColorSequence.new(Colors.cyan, Colors.blue),
})

local TargetLabel = make("TextLabel", TargetCard, {
    Name = "TargetLabel",
    Position = UDim2.new(0, 12, 0, 9),
    Size = UDim2.new(1, -24, 0, 12),
    BackgroundTransparency = 1,
    Text = "SERVER ÍT NGƯỜI NHẤT",
    TextColor3 = Colors.cyan,
    TextSize = 8,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 4,
})

local TargetInfo = make("TextLabel", TargetCard, {
    Name = "TargetInfo",
    Position = UDim2.new(0, 12, 0, 25),
    Size = UDim2.new(1, -24, 0, 21),
    BackgroundTransparency = 1,
    Text = "Đang chuẩn bị quét server...",
    TextColor3 = Colors.white,
    TextSize = 11,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    ZIndex = 4,
})

local LoaderRow = make("Frame", MainFrame, {
    Name = "LoaderRow",
    Position = UDim2.new(0, 17, 0, 203),
    Size = UDim2.new(1, -34, 0, 18),
    BackgroundTransparency = 1,
    ZIndex = 4,
})

local Spinner = make("Frame", LoaderRow, {
    Name = "Spinner",
    Position = UDim2.new(0, 1, 0.5, -9),
    Size = UDim2.new(0, 18, 0, 18),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 5,
    Visible = false,
})

for index = 1, 8 do
    local angle = math.rad((index - 1) * 45)
    local radius = 6.3
    local dot = make("Frame", Spinner, {
        Name = "Dot" .. index,
        Position = UDim2.new(
            0.5,
            math.cos(angle) * radius - 1.5,
            0.5,
            math.sin(angle) * radius - 1.5
        ),
        Size = UDim2.new(0, 3, 0, 3),
        BackgroundColor3 = index <= 3 and Colors.cyan or Colors.blue,
        BackgroundTransparency = 0.13 + (index - 1) * 0.095,
        BorderSizePixel = 0,
        ZIndex = 6,
    })
    addCorner(dot, 2)
end

local SpinnerTween = TweenService:Create(
    Spinner,
    TweenInfo.new(1.1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
    { Rotation = 360 }
)

local StatusLabel = make("TextLabel", LoaderRow, {
    Name = "StatusLabel",
    Position = UDim2.new(0, 26, 0, 0),
    Size = UDim2.new(1, -78, 1, 0),
    BackgroundTransparency = 1,
    Text = "SẴN SÀNG",
    TextColor3 = Colors.muted,
    TextSize = 8,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    ZIndex = 5,
})

local ProgressPercent = make("TextLabel", LoaderRow, {
    Name = "ProgressPercent",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 0, 0, 0),
    Size = UDim2.new(0, 43, 1, 0),
    BackgroundTransparency = 1,
    Text = "0%",
    TextColor3 = Colors.cyan,
    TextSize = 10,
    Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Right,
    ZIndex = 5,
})

local ProgressTrack = make("Frame", MainFrame, {
    Name = "ProgressTrack",
    Position = UDim2.new(0, 17, 0, 226),
    Size = UDim2.new(1, -34, 0, 4),
    BackgroundColor3 = Color3.fromRGB(35, 51, 71),
    BackgroundTransparency = 0.25,
    BorderSizePixel = 0,
    ZIndex = 4,
})
addCorner(ProgressTrack, 2)

local ProgressFill = make("Frame", ProgressTrack, {
    Name = "ProgressFill",
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = Colors.cyan,
    BorderSizePixel = 0,
    ZIndex = 5,
})
addCorner(ProgressFill, 2)
make("UIGradient", ProgressFill, {
    Color = ColorSequence.new(Colors.blue, Colors.mint),
})

addStroke(ProgressTrack, Color3.fromRGB(81, 119, 158), 0.75, 1)
local ProgressValue = make("NumberValue", MainFrame, {
    Name = "ProgressValue",
    Value = 0,
})
local ProgressTween = nil

ProgressValue:GetPropertyChangedSignal("Value"):Connect(function()
    local value = math.clamp(ProgressValue.Value, 0, 100)
    ProgressFill.Size = UDim2.new(value / 100, 0, 1, 0)
    ProgressPercent.Text = string.format("%d%%", math.floor(value + 0.5))
end)

local function beginProgress()
    if ProgressTween then
        ProgressTween:Cancel()
    end
    ProgressValue.Value = 0
    ProgressTween = TweenService:Create(
        ProgressValue,
        TweenInfo.new(1.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        { Value = 88 }
    )
    ProgressTween:Play()
end

local function finishProgress()
    if ProgressTween then
        ProgressTween:Cancel()
    end
    ProgressTween = TweenService:Create(
        ProgressValue,
        TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        { Value = 100 }
    )
    ProgressTween:Play()
end

local HopButton = make("TextButton", MainFrame, {
    Name = "HopButton",
    Position = UDim2.new(0, 15, 0, 242),
    Size = UDim2.new(1, -30, 0, 40),
    BackgroundColor3 = Colors.blue,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "CHUYỂN SERVER  ›",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    TextSize = 11,
    Font = Enum.Font.GothamBlack,
    Active = true,
    ZIndex = 4,
})
addCorner(HopButton, 10)
local ButtonGradient = make("UIGradient", HopButton, {
    Rotation = 0,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(48, 117, 255)),
        ColorSequenceKeypoint.new(0.54, Color3.fromRGB(23, 173, 233)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(39, 221, 190)),
    }),
})
local ButtonGlow = addStroke(HopButton, Colors.cyan, 0.82, 4)
local ButtonStroke = addStroke(HopButton, Color3.fromRGB(180, 249, 255), 0.4, 1.3)

local ButtonShimmer = TweenService:Create(
    ButtonGradient,
    TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
    { Rotation = 360 }
)
ButtonShimmer:Play()

local ButtonScale = make("UIScale", HopButton, {
    Scale = 1,
})

local FooterLabel = make("TextLabel", MainFrame, {
    Name = "FooterLabel",
    Position = UDim2.new(0, 15, 0, 286),
    Size = UDim2.new(1, -30, 0, 8),
    BackgroundTransparency = 1,
    Text = "PUBLIC SERVER  ·  AUTO SCAN",
    TextColor3 = Color3.fromRGB(99, 121, 148),
    TextSize = 7,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Center,
    ZIndex = 4,
})

MainFrame.Size = UDim2.new(0, 304, 0, 280)
MainFrame.BackgroundTransparency = 1
Shadow.Size = UDim2.new(0, 310, 0, 286)
Shadow.BackgroundTransparency = 1
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 12)
tween(MainFrame, 0.55, {
    Size = UDim2.new(0, 320, 0, 296),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    BackgroundTransparency = 0,
}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
tween(Shadow, 0.55, {
    Size = UDim2.new(0, 326, 0, 302),
    BackgroundTransparency = 0.48,
})

local Dragging = false
local DragStart = nil
local StartPosition = nil

DragHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        Dragging = true
        DragStart = input.Position
        StartPosition = MainFrame.Position
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        Dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not Dragging or not DragStart or not StartPosition then
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - DragStart
        local nextPosition = UDim2.new(
            StartPosition.X.Scale,
            StartPosition.X.Offset + delta.X,
            StartPosition.Y.Scale,
            StartPosition.Y.Offset + delta.Y
        )
        MainFrame.Position = nextPosition
        Shadow.Position = nextPosition + UDim2.new(0, 0, 0, 5)
    end
end)

HopButton.MouseEnter:Connect(function()
    if not IsBusy and not RetryScheduled then
        tween(ButtonScale, 0.16, { Scale = 1.025 })
        tween(ButtonStroke, 0.16, { Transparency = 0.16 })
        tween(ButtonGlow, 0.16, { Transparency = 0.58 })
    end
end)

HopButton.MouseLeave:Connect(function()
    tween(ButtonScale, 0.18, { Scale = 1 })
    tween(ButtonStroke, 0.18, { Transparency = 0.4 })
    tween(ButtonGlow, 0.18, { Transparency = 0.82 })
end)

HopButton.MouseButton1Down:Connect(function()
    if not IsBusy and not RetryScheduled then
        tween(ButtonScale, 0.09, { Scale = 0.985 }, Enum.EasingStyle.Quad)
    end
end)

local function showWorking(message, buttonText)
    Spinner.Visible = true
    if SpinnerTween.PlaybackState ~= Enum.PlaybackState.Playing then
        SpinnerTween:Play()
    end
    StatusLabel.Text = string.upper(message)
    StatusLabel.TextColor3 = Colors.cyan
    HopButton.Text = buttonText or "ĐANG XỬ LÝ..."
    HopButton.Active = false
    HopButton.TextTransparency = 0.12
end

local function showIdle(message, color)
    Spinner.Visible = false
    SpinnerTween:Pause()
    StatusLabel.Text = string.upper(message)
    StatusLabel.TextColor3 = color or Colors.muted
    HopButton.Text = "CHUYỂN SERVER  ›"
    HopButton.Active = true
    HopButton.TextTransparency = 0
    tween(ButtonScale, 0.18, { Scale = 1 })
end

local function setTarget(server)
    if not server then
        FoundServerId = nil
        TargetInfo.Text = "Chưa tìm thấy server phù hợp"
        TargetInfo.TextColor3 = Colors.muted
        return
    end
    FoundServerId = server.id
    TargetInfo.Text = string.format(
        "Tìm thấy  %d / %d người chơi",
        server.playing,
        server.maxPlayers
    )
    TargetInfo.TextColor3 = Colors.mint
end

local function findLowestRealServer()
    local url = string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
        PlaceId
    )
    local response = game:HttpGet(url)
    local data = HttpService:JSONDecode(response)
    if type(data) ~= "table" or type(data.data) ~= "table" then
        error("Phản hồi API không hợp lệ")
    end

    local lowestServer = nil
    local minPlayers = math.huge
    for _, server in ipairs(data.data) do
        if server.id ~= CurrentJobId
            and server.playing < server.maxPlayers
            and server.playing > 0
            and server.playing < minPlayers then
            minPlayers = server.playing
            lowestServer = server
        end
    end
    return lowestServer
end

local function queueReactivation()
    if type(SCRIPT_SOURCE) ~= "string" or SCRIPT_SOURCE == "" then
        return false, "Không tìm thấy mã nguồn để tự chạy lại"
    end

    local queueFunction = queue_on_teleport or queueonteleport
    if type(queueFunction) ~= "function" then
        local synApi = syn
        local fluxusApi = fluxus
        if type(synApi) == "table" and type(synApi.queue_on_teleport) == "function" then
            queueFunction = synApi.queue_on_teleport
        elseif type(fluxusApi) == "table" and type(fluxusApi.queue_on_teleport) == "function" then
            queueFunction = fluxusApi.queue_on_teleport
        end
    end
    if type(queueFunction) ~= "function" then
        return false, "Executor không hỗ trợ tự chạy lại sau teleport"
    end

    local queuedCode = string.format(
        "local e=(getgenv and getgenv()) or _G; e.__HOP_SOURCE=%q; e.__HOP_RESUME=true; local f=loadstring or load; local c=f(e.__HOP_SOURCE); if c then c() end",
        SCRIPT_SOURCE
    )
    local callSuccess, queueResult = pcall(queueFunction, queuedCode)
    local queued = callSuccess and queueResult ~= false
    if not queued then
        return false, "Không thể xếp hàng tự chạy lại"
    end
    return true, nil
end

local performHop

local function scheduleRetry(nextAttempt, message)
    IsHopPending = false
    if nextAttempt > MAX_RETRIES then
        IsBusy = false
        RetryScheduled = false
        FoundServerId = nil
        setTarget(nil)
        showIdle(message or "Không thể chuyển server. Hãy thử lại.", Colors.error)
        return
    end

    IsBusy = false
    RetryScheduled = true
    CurrentAttempt = nextAttempt
    showWorking(
        string.format("%s  Thử lại sau %d giây", message, RETRY_DELAY),
        "ĐANG THỬ LẠI..."
    )
    task.delay(RETRY_DELAY, function()
        if not ScreenGui.Parent then
            return
        end
        RetryScheduled = false
        if not IsBusy then
            performHop(nextAttempt)
        end
    end)
end

performHop = function(attempt)
    if IsBusy or RetryScheduled then
        return
    end
    IsBusy = true
    CurrentAttempt = attempt or 1
    beginProgress()
    showWorking("Đang quét server công khai", "ĐANG QUÉT...")

    task.spawn(function()
        local scanSuccess, result = pcall(findLowestRealServer)
        finishProgress()
        if not scanSuccess then
            scheduleRetry(CurrentAttempt + 1, "Lỗi kết nối. Đang quét lại...")
            return
        end
        if not result then
            setTarget(nil)
            scheduleRetry(CurrentAttempt + 1, "Không có server phù hợp. Đang thử lại...")
            return
        end

        setTarget(result)
        beginProgress()
        showWorking("Đang chuẩn bị chuyển server", "ĐANG CHUYỂN...")

        local queued, queueError = queueReactivation()
        IsHopPending = true
        local teleportSuccess = pcall(function()
            TeleportService:TeleportToPlaceInstance(
                PlaceId,
                result.id,
                LocalPlayer
            )
        end)
        if not teleportSuccess then
            IsHopPending = false
            finishProgress()
            scheduleRetry(CurrentAttempt + 1, "Chuyển server thất bại. Đang quét lại...")
            return
        end

        finishProgress()
        if queued then
            showWorking("Đang chuyển server. Giao diện sẽ tự chạy lại", "ĐANG CHUYỂN...")
        else
            showWorking(
                queueError or "Đang chuyển server",
                "ĐANG CHUYỂN..."
            )
        end
    end)
end

local function scanOnOpen()
    if IsBusy then
        return
    end
    IsBusy = true
    beginProgress()
    showWorking("Đang tìm server ít người chơi", "ĐANG QUÉT...")
    task.spawn(function()
        local success, server = pcall(findLowestRealServer)
        finishProgress()
        IsBusy = false
        if not success then
            setTarget(nil)
            showIdle("Lỗi kết nối API. Nhấn chuyển để thử lại.", Colors.error)
            return
        end
        if server then
            setTarget(server)
            showIdle(
                IsResume and "Đã kích hoạt lại sau teleport" or "Đã quét xong. Sẵn sàng",
                Colors.mint
            )
        else
            setTarget(nil)
            showIdle("Không có server phù hợp. Có thể thử lại.", Colors.muted)
        end
    end)
end

HopButton.Activated:Connect(function()
    if IsBusy or RetryScheduled then
        return
    end
    performHop(1)
end)

local teleportFailedSignal = TeleportService.TeleportInitFailed
if teleportFailedSignal then
    teleportFailedSignal:Connect(function(player, teleportResult, errorMessage)
        if player ~= LocalPlayer or not IsHopPending then
            return
        end
        IsHopPending = false
        local reason = "Teleport lỗi. Đang quét server khác..."
        if errorMessage and errorMessage ~= "" then
            reason = "Teleport lỗi. Đang quét server khác..."
        end
        scheduleRetry(CurrentAttempt + 1, reason)
    end)
end

local function updatePlayerCount()
    if Players and LocalPlayer then
        local count = #Players:GetPlayers()
        local maximum = Players.MaxPlayers
        CurrentText.Text = string.format(
            "Hiện tại  %d / %d người chơi",
            count,
            maximum
        )
    end
end

updatePlayerCount()
Players.PlayerAdded:Connect(updatePlayerCount)
Players.PlayerRemoving:Connect(updatePlayerCount)
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(1)
        updatePlayerCount()
    end
end)

local livePulse = TweenService:Create(
    LiveDot,
    TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
    { BackgroundTransparency = 0.58 }
)
livePulse:Play()

scanOnOpen()

]====]

local ExecutorEnv = (getgenv and getgenv()) or _G
ExecutorEnv.__HOP_SOURCE = SCRIPT_SOURCE
local loader = loadstring or load
if type(loader) ~= "function" then
    error("Executor không hỗ trợ loadstring/load.")
end
local chunk, loadError = loader(SCRIPT_SOURCE)
if not chunk then
    error(loadError or "Không thể nạp Hop Sever V1.")
end
chunk()
