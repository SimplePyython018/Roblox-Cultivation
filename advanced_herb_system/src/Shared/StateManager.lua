local StateManager = {}
StateManager.__index = StateManager

function StateManager.new()
    return setmetatable({
        data = {
            systemEnabled = true,
            herbsOpen = true,
            alwaysCheck = true,
            targetSelection = true,
            targetMode = "MANUAL",
            autoFarm = false,
            priority = "Nearest",
            debug = false,
            status = "IDLE",
            promptStatus = "WAITING",
            activeTargetName = "None",
            queueCount = 0,
            lastAction = "—",
            lastScan = "—",
        },
        listeners = {},
    }, StateManager)
end

function StateManager:Get(key)
    return self.data[key]
end

function StateManager:Set(key, value)
    if self.data[key] == value then
        return
    end
    self.data[key] = value
    local list = self.listeners[key]
    if list then
        for _, callback in ipairs(list) do
            task.spawn(callback, value)
        end
    end
end

function StateManager:OnChanged(key, callback)
    self.listeners[key] = self.listeners[key] or {}
    table.insert(self.listeners[key], callback)
    return function()
        local list = self.listeners[key]
        if not list then return end
        for i, cb in ipairs(list) do
            if cb == callback then
                table.remove(list, i)
                return
            end
        end
    end
end

function StateManager:ClearTransient()
    self:Set("status", "IDLE")
    self:Set("promptStatus", "WAITING")
    self:Set("activeTargetName", "None")
    self:Set("queueCount", 0)
    self:Set("lastAction", "—")
end

return StateManager
