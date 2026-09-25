local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local UIController = {}
UIController.__index = UIController

local function make(className, props, parent)
    local obj = Instance.new(className)
    for key, value in pairs(props or {}) do
        obj[key] = value
    end
    obj.Parent = parent
    return obj
end

local function corner(parent, radius)
    return make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent, transparency)
    return make("UIStroke", { Thickness = 1, Transparency = transparency or 0.25 }, parent)
end

local function isPointInside(guiObject, point)
    local p = guiObject.AbsolutePosition
    local s = guiObject.AbsoluteSize
    return point.X >= p.X and point.X <= p.X + s.X and point.Y >= p.Y and point.Y <= p.Y + s.Y
end

function UIController.new(config, state, detector, targets, farm, shutdown)
    return setmetatable({
        config = config,
        state = state,
        detector = detector,
        targets = targets,
        farm = farm,
        shutdown = shutdown,
        gui = nil,
        main = nil,
        herbWindow = nil,
        minimized = nil,
        exitDialog = nil,
        dragConnections = {},
        connections = {},
        selectedRecord = nil,
        searchText = "",
        destroyed = false,
    }, UIController)
end

function UIController:_getPlayerGui()
    local player = Players.LocalPlayer
    return player:WaitForChild("PlayerGui")
end

function UIController:_clamp(guiObject, margin)
    if not guiObject or not guiObject.Parent then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local size = guiObject.AbsoluteSize
    local x = math.clamp(guiObject.Position.X.Offset, margin, math.max(margin, viewport.X - size.X - margin))
    local y = math.clamp(guiObject.Position.Y.Offset, margin, math.max(margin, viewport.Y - size.Y - margin))
    guiObject.Position = UDim2.fromOffset(x, y)
end

function UIController:_center(guiObject)
    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    local size = guiObject.AbsoluteSize
    guiObject.Position = UDim2.fromOffset(
        math.max(12, (viewport.X - size.X) / 2),
        math.max(12, (viewport.Y - size.Y) / 2)
    )
    self:_clamp(guiObject, self.config.UI.SafeMargin)
end

function UIController:_makeDraggable(handle, target, onEnd)
    local dragging = false
    local dragInput
    local dragStart
    local startPos

    local function update(input)
        local delta = input.Position - dragStart
        target.Position = UDim2.fromOffset(startPos.X.Offset + delta.X, startPos.Y.Offset + delta.Y)
        self:_clamp(target, self.config.UI.SafeMargin)
    end

    table.insert(self.dragConnections, handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if onEnd then onEnd() end
                end
            end)
        end
    end))

    table.insert(self.dragConnections, handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    table.insert(self.dragConnections, UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            update(input)
        end
    end))
end

function UIController:_button(parent, text, callback, width)
    local b = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = Color3.fromRGB(27, 31, 39),
        TextColor3 = Color3.fromRGB(235, 240, 248),
        Text = text,
        Font = Enum.Font.GothamSemibold,
        TextSize = 14,
        AutoButtonColor = false,
    }, parent)
    b.Size = width and UDim2.new(0, width, 0, 44) or b.Size
    corner(b, 10)
    stroke(b, 0.45)
    b.MouseButton1Click:Connect(callback)
    return b
end

function UIController:_label(parent, text, size, color)
    return make("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, size or 22),
        Text = text,
        TextColor3 = color or Color3.fromRGB(215, 221, 230),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
    }, parent)
end

function UIController:_clear(parent)
    for _, child in ipairs(parent:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
end

function UIController:_renderHerbs()
    local right = self.main.Right
    self:_clear(right)

    self:_label(right, "DETECTED HERBS", 26, Color3.fromRGB(255,255,255)).Font = Enum.Font.GothamBold

    local search = make("TextBox", {
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = Color3.fromRGB(20, 24, 31),
        PlaceholderText = "Search Herbs...",
        Text = self.searchText,
        TextColor3 = Color3.fromRGB(235,240,248),
        PlaceholderColor3 = Color3.fromRGB(130,138,150),
        Font = Enum.Font.Gotham,
        TextSize = 14,
        ClearTextOnFocus = false,
    }, right)
    corner(search, 10)
    stroke(search, 0.5)
    search.FocusLost:Connect(function()
        self.searchText = search.Text
        self:_renderHerbs()
    end)

    local list = make("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, -142),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
    }, right)
    make("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, list)

    local query = string.lower(self.searchText or "")
    local records = self.detector:GetValidRecords()
    for _, record in ipairs(records) do
        if query == "" or string.find(string.lower(record.Name), query, 1, true) then
            local row = make("TextButton", {
                Size = UDim2.new(1, -8, 0, 44),
                BackgroundColor3 = self.selectedRecord == record and Color3.fromRGB(34, 64, 48) or Color3.fromRGB(24, 29, 36),
                Text = "✓  " .. record.Name,
                TextColor3 = Color3.fromRGB(235,240,248),
                Font = Enum.Font.GothamSemibold,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
            }, list)
            corner(row, 9)
            row.MouseButton1Click:Connect(function()
                self.selectedRecord = record
                if self.state:Get("targetMode") == "MANUAL" then
                    self.targets:SetManualTarget(record)
                end
                self:_renderHerbs()
            end)
        end
    end

    local statusFrame = make("Frame", {
        Size = UDim2.new(1, 0, 0, 112),
        BackgroundColor3 = Color3.fromRGB(18, 22, 28),
    }, right)
    corner(statusFrame, 10)
    stroke(statusFrame, 0.5)
    local pad = make("UIPadding", { PaddingTop = UDim.new(0, 9), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, statusFrame)
    local lines = {
        "Detector: " .. (self.state:Get("alwaysCheck") and "ON" or "OFF"),
        "Target Mode: " .. self.state:Get("targetMode"),
        "Active Target: " .. self.state:Get("activeTargetName"),
        "Queue: " .. tostring(self.state:Get("queueCount")),
        "Prompt: " .. self.state:Get("promptStatus"),
        "Farm: " .. self.state:Get("status"),
    }
    for _, line in ipairs(lines) do
        self:_label(statusFrame, line, 16)
    end
end

function UIController:_toggleButton(parent, label, getter, setter)
    local b = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = Color3.fromRGB(26, 31, 38),
        TextColor3 = Color3.fromRGB(228,235,243),
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parent)
    corner(b, 9)
    stroke(b, 0.5)
    local function refresh()
        b.Text = string.format("%s    [%s]", label, getter() and "ON" or "OFF")
        b.BackgroundColor3 = getter() and Color3.fromRGB(31, 59, 44) or Color3.fromRGB(26, 31, 38)
    end
    b.MouseButton1Click:Connect(function()
        setter(not getter())
        refresh()
        self:_renderHerbs()
    end)
    refresh()
    return b
end

function UIController:_renderControls()
    local left = self.main.Left
    self:_clear(left)

    self:_label(left, "HERB SYSTEM", 26, Color3.fromRGB(255,255,255)).Font = Enum.Font.GothamBold
    self:_label(left, "Control / Feature Navigation", 20, Color3.fromRGB(145,154,168))

    self:_toggleButton(left, "Always Check", function() return self.state:Get("alwaysCheck") end, function(value)
        self.state:Set("alwaysCheck", value)
    end)

    self:_toggleButton(left, "Target Selection", function() return self.state:Get("targetSelection") end, function(value)
        self.state:Set("targetSelection", value)
        if not value then
            self.state:Set("autoFarm", false)
            self.farm:Stop("Target Selection OFF")
        end
    end)

    local mode = self:_button(left, "Target Mode   ▼  " .. self.state:Get("targetMode"), function()
        local nextMode = self.state:Get("targetMode") == "MANUAL" and "ALL" or "MANUAL"
        self.targets:SetMode(nextMode)
        self:_renderControls()
        self:_renderHerbs()
    end)
    mode.BackgroundColor3 = Color3.fromRGB(23, 29, 38)

    local priority = self:_button(left, "Priority   " .. self.state:Get("priority"), function()
        local options = {"Nearest", "First Detected", "Rare First", "Manual"}
        local current = self.state:Get("priority")
        local index = 1
        for i, value in ipairs(options) do
            if value == current then index = i break end
        end
        self.targets:SetPriority(options[(index % #options) + 1])
        self:_renderControls()
    end)
    priority.BackgroundColor3 = Color3.fromRGB(23, 29, 38)

    self:_toggleButton(left, "Auto Farm Herbs", function() return self.state:Get("autoFarm") end, function(value)
        if value then
            if not self.state:Get("targetSelection") then
                self.state:Set("lastAction", "Auto Farm blocked: Target Selection OFF")
                return
            end
            local target = self.targets:GetNextTarget()
            if not target then
                self.state:Set("lastAction", "Auto Farm cannot start: No valid target detected.")
                return
            end
            self.targets:Lock(target)
            self.state:Set("autoFarm", true)
            self.farm:Start()
        else
            self.state:Set("autoFarm", false)
            self.farm:Stop("IDLE")
        end
    end)

    local exit = self:_button(left, "EXIT SYSTEM", function()
        self:_showExitDialog()
    end)
    exit.BackgroundColor3 = Color3.fromRGB(63, 31, 36)
end

function UIController:_showExitDialog()
    if self.exitDialog then
        self.exitDialog.Visible = true
        return
    end

    local overlay = make("Frame", {
        Size = UDim2.fromScale(1,1),
        BackgroundColor3 = Color3.fromRGB(0,0,0),
        BackgroundTransparency = 0.35,
        ZIndex = 50,
    }, self.gui)

    local dialog = make("Frame", {
        AnchorPoint = Vector2.new(0.5,0.5),
        Position = UDim2.fromScale(0.5,0.5),
        Size = UDim2.new(0, 330, 0, 180),
        BackgroundColor3 = Color3.fromRGB(20,24,31),
        ZIndex = 51,
    }, overlay)
    corner(dialog, 14)
    stroke(dialog, 0.2)

    self:_label(dialog, "Exit System?", 30, Color3.fromRGB(255,255,255)).Position = UDim2.fromOffset(18,16)
    self:_label(dialog, "Are you sure you want to stop the system?", 42).Position = UDim2.fromOffset(18,54)

    local yes = self:_button(dialog, "YES", function()
        self.shutdown:Shutdown()
        self:Destroy()
    end, 132)
    yes.Position = UDim2.fromOffset(18, 112)
    yes.ZIndex = 52

    local no = self:_button(dialog, "NO", function()
        overlay:Destroy()
        self.exitDialog = nil
    end, 132)
    no.Position = UDim2.fromOffset(180, 112)
    no.ZIndex = 52

    self.exitDialog = overlay
end

function UIController:_createMain()
    local playerGui = self:_getPlayerGui()
    self.gui = make("ScreenGui", {
        Name = "AdvancedHerbSystem",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 100,
    }, playerGui)

    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
    local width = math.clamp(viewport.X * self.config.UI.WidthRatio, self.config.UI.MinWidth, self.config.UI.MaxWidth)
    local height = math.min(self.config.UI.Height, viewport.Y - 24)

    local main = make("Frame", {
        Size = UDim2.fromOffset(width, height),
        Position = UDim2.fromOffset((viewport.X - width)/2, (viewport.Y-height)/2),
        BackgroundColor3 = Color3.fromRGB(14, 17, 22),
        ClipsDescendants = true,
    }, self.gui)
    corner(main, 16)
    stroke(main, 0.18)
    self.main = main

    local header = make("Frame", { Size = UDim2.new(1,0,0,48), BackgroundColor3 = Color3.fromRGB(18,22,28) }, main)
    corner(header, 16)
    local title = make("TextLabel", {
        Size = UDim2.new(1,-90,1,0), Position = UDim2.fromOffset(18,0),
        BackgroundTransparency = 1, Text = "HERB SYSTEM", TextColor3 = Color3.fromRGB(245,248,252),
        Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left,
    }, header)

    local minimize = make("TextButton", { Size = UDim2.fromOffset(40,40), Position = UDim2.new(1,-86,0,4), BackgroundColor3 = Color3.fromRGB(29,34,42), Text = "—", TextColor3 = Color3.fromRGB(235,240,248), Font = Enum.Font.GothamBold, TextSize = 18 }, header)
    corner(minimize, 10)
    local close = make("TextButton", { Size = UDim2.fromOffset(40,40), Position = UDim2.new(1,-42,0,4), BackgroundColor3 = Color3.fromRGB(63,31,36), Text = "×", TextColor3 = Color3.fromRGB(255,235,238), Font = Enum.Font.GothamBold, TextSize = 18 }, header)
    corner(close, 10)

    self:_makeDraggable(header, main)

    local content = make("Frame", { Size = UDim2.new(1,0,1,-48), Position = UDim2.fromOffset(0,48), BackgroundTransparency = 1 }, main)
    local left = make("Frame", { Size = UDim2.new(0, 220,1,-14), Position = UDim2.fromOffset(8,7), BackgroundColor3 = Color3.fromRGB(18,22,28) }, content)
    corner(left, 12)
    make("UIPadding", { PaddingTop = UDim.new(0,10), PaddingLeft = UDim.new(0,10), PaddingRight = UDim.new(0,10), PaddingBottom = UDim.new(0,10) }, left)
    make("UIListLayout", { Padding = UDim.new(0,7), SortOrder = Enum.SortOrder.LayoutOrder }, left)

    local right = make("ScrollingFrame", { Size = UDim2.new(1,-236,1,-14), Position = UDim2.fromOffset(228,7), BackgroundColor3 = Color3.fromRGB(18,22,28), BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5 }, content)
    corner(right, 12)
    make("UIPadding", { PaddingTop = UDim.new(0,10), PaddingLeft = UDim.new(0,10), PaddingRight = UDim.new(0,10), PaddingBottom = UDim.new(0,10) }, right)
    make("UIListLayout", { Padding = UDim.new(0,8), SortOrder = Enum.SortOrder.LayoutOrder }, right)

    self.main.Left = left
    self.main.Right = right

    minimize.MouseButton1Click:Connect(function()
        self:_minimize()
    end)
    close.MouseButton1Click:Connect(function()
        self:_showExitDialog()
    end)

    self:_renderControls()
    self:_renderHerbs()
end

function UIController:_minimize()
    if not self.main or not self.main.Parent then return end
    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
    local orb = self.minimized
    if orb and orb.Parent then
        orb.Visible = true
    else
        orb = make("TextButton", {
            Size = UDim2.fromOffset(58,58),
            Position = UDim2.fromOffset(viewport.X-78, viewport.Y-78),
            BackgroundColor3 = Color3.fromRGB(23,48,38),
            Text = "🌿",
            TextSize = 24,
            ZIndex = 20,
        }, self.gui)
        corner(orb, 29)
        stroke(orb, 0.25)
        self:_makeDraggable(orb, orb)
        orb.MouseButton1Click:Connect(function()
            self.main.Visible = true
            orb.Visible = false
            self:_center(self.main)
            self:_renderControls()
            self:_renderHerbs()
        end)
        self.minimized = orb
    end
    self.main.Visible = false
end

function UIController:Refresh()
    if self.destroyed or not self.main or not self.main.Parent then return end
    self:_renderControls()
    self:_renderHerbs()
    self:_clamp(self.main, self.config.UI.SafeMargin)
    if self.minimized then self:_clamp(self.minimized, self.config.UI.SafeMargin) end
end

function UIController:Start()
    self:_createMain()

    table.insert(self.connections, UserInputService.WindowFocusReleased:Connect(function()
        self:Refresh()
    end))

    table.insert(self.connections, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        if self.main and self.main.Parent then
            local camera = workspace.CurrentCamera
            local viewport = camera.ViewportSize
            local width = math.clamp(viewport.X * self.config.UI.WidthRatio, self.config.UI.MinWidth, self.config.UI.MaxWidth)
            local height = math.min(self.config.UI.Height, viewport.Y - 24)
            self.main.Size = UDim2.fromOffset(width, height)
            self:_clamp(self.main, self.config.UI.SafeMargin)
            if self.minimized then self:_clamp(self.minimized, self.config.UI.SafeMargin) end
        end
    end))

    task.spawn(function()
        while not self.destroyed and self.state:Get("systemEnabled") do
            task.wait(0.5)
            if self.main and self.main.Visible then
                self:_renderHerbs()
            end
        end
    end)
end

function UIController:Destroy()
    self.destroyed = true
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    for _, connection in ipairs(self.dragConnections) do connection:Disconnect() end
    table.clear(self.connections)
    table.clear(self.dragConnections)
    if self.gui then
        self.gui:Destroy()
        self.gui = nil
    end
end

return UIController
