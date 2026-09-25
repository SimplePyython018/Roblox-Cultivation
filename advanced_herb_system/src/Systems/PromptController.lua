local RunService = game:GetService("RunService")

local PromptController = {}
PromptController.__index = PromptController

function PromptController.new(config, state, detector)
    return setmetatable({
        config = config,
        state = state,
        detector = detector,
        running = false,
    }, PromptController)
end

function PromptController:Validate(record)
    local ok, reason = self.detector:ValidateRecord(record)
    if not ok then
        return false, reason
    end
    if not record.Prompt.Enabled then
        return false, "Prompt disabled"
    end
    return true
end

function PromptController:Interact(record)
    local valid, reason = self:Validate(record)
    if not valid then
        self.state:Set("promptStatus", reason or "INVALID")
        return false, reason
    end

    self.state:Set("promptStatus", "READY")

    -- Integration boundary: invoke the normal, game-owned collection handler.
    -- No exploit-only prompt firing is used here.
    local ok, accepted = pcall(self.config.InteractionHandler, record)
    if not ok then
        self.state:Set("promptStatus", "ERROR")
        return false, accepted
    end

    if accepted then
        self.state:Set("promptStatus", "TRIGGERED")
        return true
    end

    self.state:Set("promptStatus", "NOT ACCEPTED")
    return false, "Collection handler rejected request"
end

function PromptController:WaitUntilAvailable(record, timeout)
    local started = os.clock()
    while os.clock() - started < timeout do
        local valid = self:Validate(record)
        if valid then return true end
        RunService.Heartbeat:Wait()
    end
    return false, "Prompt timeout"
end

function PromptController:Stop()
    self.running = false
end

return PromptController
