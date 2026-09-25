local RunService = game:GetService("RunService")

local HerbDetector = {}
HerbDetector.__index = HerbDetector

local function getByPath(root, path)
    local current = root
    for _, name in ipairs(path) do
        if not current then return nil end
        current = current:FindFirstChild(name)
    end
    return current
end

local function isAlive(instance)
    return typeof(instance) == "Instance" and instance.Parent ~= nil
end

local function findPrompt(descendantRoot)
    if not isAlive(descendantRoot) then return nil end
    if descendantRoot:IsA("ProximityPrompt") then return descendantRoot end
    return descendantRoot:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function findAssociatedModel(prompt, herbsContainer)
    local current = prompt and prompt.Parent
    local candidate
    while current and current ~= herbsContainer do
        if current:IsA("Model") then
            candidate = current
            break
        end
        current = current.Parent
    end
    return candidate
end

local function findInteractionPart(prompt, model, herbsContainer)
    if prompt and prompt.Parent and prompt.Parent:IsA("BasePart") then
        return prompt.Parent
    end
    if model then
        return model:FindFirstChildWhichIsA("BasePart", true)
    end
    if herbsContainer then
        return herbsContainer:FindFirstChildWhichIsA("BasePart", true)
    end
end

function HerbDetector.new(config, state)
    return setmetatable({
        config = config,
        state = state,
        registry = {},
        byInstance = {},
        herbsContainer = nil,
        connections = {},
        running = false,
        scanQueued = false,
        version = 0,
    }, HerbDetector)
end

function HerbDetector:_clearConnections()
    for _, connection in ipairs(self.connections) do
        connection:Disconnect()
    end
    table.clear(self.connections)
end

function HerbDetector:_resolveContainer()
    return getByPath(workspace, self.config.Detection.HerbsPath)
end

function HerbDetector:_buildRecord(model, prompt, interactionPart)
    if not model or not prompt or not interactionPart then
        return nil
    end

    local position = interactionPart.Position
    local existing = self.byInstance[model]

    if existing then
        existing.Prompt = prompt
        existing.InteractionPart = interactionPart
        existing.Position = position
        if existing.State == "REMOVED" or existing.State == "INVALID" then
            existing.State = "DETECTED"
        end
        return existing
    end

    self.version += 1
    local record = {
        Id = string.format("%s:%d", model:GetFullName(), self.version),
        Name = model.Name,
        Instance = model,
        Model = model,
        InteractionPart = interactionPart,
        Prompt = prompt,
        Position = position,
        DetectionTime = os.clock(),
        LastSeen = os.clock(),
        State = "DETECTED",
        SpawnToken = self.version,
    }

    self.byInstance[model] = record
    table.insert(self.registry, record)
    return record
end

function HerbDetector:_prune()
    for i = #self.registry, 1, -1 do
        local record = self.registry[i]
        if not isAlive(record.Instance) or not record.Instance:IsDescendantOf(self.herbsContainer or workspace) then
            record.State = "REMOVED"
            self.byInstance[record.Instance] = nil
            table.remove(self.registry, i)
        end
    end
end

function HerbDetector:Scan()
    local container = self:_resolveContainer()
    if not container then
        self.herbsContainer = nil
        self.state:Set("lastScan", "No Herbs container")
        return {}
    end

    if self.herbsContainer ~= container then
        self:_clearConnections()
        self.herbsContainer = container
        if self.running then
            self:_connectContainerEvents()
        end
    end

    local previous = {}
    for _, record in ipairs(self.registry) do
        previous[record.Instance] = true
    end

    local discovered = {}
    for _, descendant in ipairs(container:GetDescendants()) do
        local prompt
        if descendant:IsA("ProximityPrompt") then
            prompt = descendant
        end

        if prompt then
            local model = findAssociatedModel(prompt, container)
            local part = findInteractionPart(prompt, model, container)
            if model and part then
                local record = self:_buildRecord(model, prompt, part)
                if record then
                    record.LastSeen = os.clock()
                    record.Position = part.Position
                    discovered[record.Instance] = true
                end
            end
        end
    end

    for _, record in ipairs(self.registry) do
        if discovered[record.Instance] then
            record.LastSeen = os.clock()
        end
    end

    self:_prune()
    self.state:Set("lastScan", string.format("%.1fs ago", 0))
    return self:GetValidRecords()
end

function HerbDetector:_scheduleScan()
    if self.scanQueued or not self.running then return end
    self.scanQueued = true
    task.delay(self.config.Detection.DebounceWindow, function()
        self.scanQueued = false
        if self.running then
            self:Scan()
        end
    end)
end

function HerbDetector:_connectContainerEvents()
    self:_clearConnections()
    if not self.herbsContainer then return end

    table.insert(self.connections, self.herbsContainer.DescendantAdded:Connect(function()
        if self.state:Get("alwaysCheck") then
            self:_scheduleScan()
        end
    end))

    table.insert(self.connections, self.herbsContainer.DescendantRemoving:Connect(function()
        if self.state:Get("alwaysCheck") then
            self:_scheduleScan()
        end
    end))

    table.insert(self.connections, self.herbsContainer.AncestryChanged:Connect(function(_, parent)
        if not parent then
            self.herbsContainer = nil
            self:_scheduleScan()
        end
    end))
end

function HerbDetector:Start()
    if self.running then return end
    self.running = true
    self:Scan()
    self:_connectContainerEvents()
end

function HerbDetector:Stop()
    self.running = false
    self:_clearConnections()
end

function HerbDetector:UpdateContinuousLoop()
    if not self.running then return end
    if not self.state:Get("alwaysCheck") then return end
    self:Scan()
end

function HerbDetector:GetValidRecords()
    local valid = {}
    for _, record in ipairs(self.registry) do
        if typeof(record.Instance) == "Instance"
            and record.Instance.Parent
            and record.Instance:IsDescendantOf(self.herbsContainer or workspace)
            and record.Model
            and record.InteractionPart
            and record.Prompt
            and record.Prompt.Parent
        then
            table.insert(valid, record)
        end
    end
    return valid
end

function HerbDetector:ValidateRecord(record)
    if not record or not record.Instance or not record.Instance.Parent then
        return false, "Instance invalid"
    end
    if not self.herbsContainer or not record.Instance:IsDescendantOf(self.herbsContainer) then
        return false, "Outside Herbs container"
    end
    if not record.InteractionPart or not record.InteractionPart.Parent then
        return false, "Interaction part missing"
    end
    if not record.Prompt or not record.Prompt.Parent then
        return false, "Prompt missing"
    end
    if not record.Model or not record.Model.Parent then
        return false, "Model missing"
    end
    record.Position = record.InteractionPart.Position
    return true
end

function HerbDetector:GetRecords()
    return self.registry
end

return HerbDetector
