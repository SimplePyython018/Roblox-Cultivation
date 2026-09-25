local TargetManager = {}
TargetManager.__index = TargetManager

local PRIORITY_ORDER = {
    ["First Detected"] = function(a, b) return a.DetectionTime < b.DetectionTime end,
    ["Nearest"] = function(a, b)
        local character = game:GetService("Players").LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then return a.DetectionTime < b.DetectionTime end
        return (a.Position - root.Position).Magnitude < (b.Position - root.Position).Magnitude
    end,
    ["Rare First"] = function(a, b)
        local rareA = string.find(string.lower(a.Name), "rare") or string.find(string.lower(a.Name), "mystic")
        local rareB = string.find(string.lower(b.Name), "rare") or string.find(string.lower(b.Name), "mystic")
        if rareA ~= rareB then return rareA ~= nil end
        return a.DetectionTime < b.DetectionTime
    end,
    ["Manual"] = function(a, b) return a.DetectionTime < b.DetectionTime end,
}

function TargetManager.new(config, state, detector)
    return setmetatable({
        config = config,
        state = state,
        detector = detector,
        mode = config.Farm.TargetModeDefault,
        priority = config.Farm.PriorityDefault,
        selectedName = nil,
        active = nil,
        queue = {},
        queuedIds = {},
    }, TargetManager)
end

function TargetManager:SetMode(mode)
    if mode ~= "MANUAL" and mode ~= "ALL" then return end
    self.mode = mode
    self.state:Set("targetMode", mode)
    self.active = nil
    table.clear(self.queue)
    table.clear(self.queuedIds)
    self:RefreshQueue()
end

function TargetManager:SetPriority(priority)
    if not PRIORITY_ORDER[priority] then return end
    self.priority = priority
    self.state:Set("priority", priority)
    self:RefreshQueue()
end

function TargetManager:SetManualTarget(record)
    if not record then
        self.selectedName = nil
        self.active = nil
        self.state:Set("activeTargetName", "None")
        return false
    end
    self.selectedName = record.Name
    self.active = record
    self.state:Set("activeTargetName", record.Name)
    return true
end

function TargetManager:IsRecordValid(record)
    local valid = self.detector:ValidateRecord(record)
    return valid
end

function TargetManager:_matchesManual(record)
    return self.selectedName == nil or record.Name == self.selectedName
end

function TargetManager:_enqueue(record)
    if not record or record.State == "REMOVED" or record.State == "COLLECTED" then return end
    if not self:_matchesManual(record) then return end
    if not self:IsRecordValid(record) then
        record.State = "INVALID"
        return
    end
    if self.queuedIds[record.Id] or self.active == record then return end
    record.State = "QUEUED"
    self.queuedIds[record.Id] = true
    table.insert(self.queue, record)
end

function TargetManager:RefreshQueue()
    if self.mode ~= "ALL" then
        self.state:Set("queueCount", 0)
        return
    end

    local records = self.detector:GetValidRecords()
    for _, record in ipairs(records) do
        self:_enqueue(record)
    end

    local sorter = PRIORITY_ORDER[self.priority]
    if sorter then
        table.sort(self.queue, sorter)
    end

    self.state:Set("queueCount", #self.queue)
end

function TargetManager:GetNextTarget()
    if not self.state:Get("targetSelection") then
        return nil
    end

    if self.mode == "MANUAL" then
        if self.active and self:IsRecordValid(self.active) and self.active.Name == self.selectedName then
            return self.active
        end
        return nil
    end

    self:RefreshQueue()
    while #self.queue > 0 do
        local record = table.remove(self.queue, 1)
        self.queuedIds[record.Id] = nil
        if self:IsRecordValid(record) then
            record.State = "ACTIVE"
            self.active = record
            self.state:Set("activeTargetName", record.Name)
            self.state:Set("queueCount", #self.queue)
            return record
        end
        record.State = "INVALID"
    end

    self.state:Set("queueCount", 0)
    return nil
end

function TargetManager:Lock(record)
    if not record or not self:IsRecordValid(record) then return false end
    self.active = record
    record.State = "ACTIVE"
    self.state:Set("activeTargetName", record.Name)
    return true
end

function TargetManager:Complete(record)
    if not record then return end
    record.State = "COLLECTED"
    if self.active == record then
        self.active = nil
        self.state:Set("activeTargetName", "None")
    end
end

function TargetManager:Invalidate(record)
    if not record then return end
    record.State = "INVALID"
    if self.active == record then
        self.active = nil
        self.state:Set("activeTargetName", "None")
    end
end

function TargetManager:Clear()
    self.active = nil
    self.selectedName = nil
    table.clear(self.queue)
    table.clear(self.queuedIds)
    self.state:Set("activeTargetName", "None")
    self.state:Set("queueCount", 0)
end

function TargetManager:GetSelectedName()
    return self.selectedName
end

return TargetManager
