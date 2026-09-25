local FarmController = {}
FarmController.__index = FarmController

local STATE = {
    IDLE = "IDLE",
    VALIDATE = "VALIDATE TARGET",
    MOVE = "MOVE TO TARGET",
    INTERACT = "CHECK INTERACTION",
    VERIFY = "VERIFY RESULT",
    COMPLETE = "TARGET COMPLETE",
}

function FarmController.new(config, state, detector, targets, movement, prompt)
    return setmetatable({
        config = config,
        state = state,
        detector = detector,
        targets = targets,
        movement = movement,
        prompt = prompt,
        running = false,
        token = 0,
    }, FarmController)
end

function FarmController:_setStatus(value)
    self.state:Set("status", value)
end

function FarmController:Stop(reason)
    self.token += 1
    self.running = false
    self.movement:Cancel()
    self.prompt:Stop()
    self:_setStatus(reason or "IDLE")
end

function FarmController:_verifyCollected(record)
    local started = os.clock()
    while os.clock() - started < self.config.Farm.VerificationTimeout do
        local ok = self.detector:ValidateRecord(record)
        if not ok or not record.Instance.Parent then
            return true
        end
        task.wait(0.15)
    end
    return false
end

function FarmController:_runOne(record, token)
    if not self.detector:ValidateRecord(record) then
        self.targets:Invalidate(record)
        return false
    end

    self:_setStatus(STATE.MOVE)
    local moved, moveReason = self.movement:MoveTo(record.Position, self.config.Farm.MoveTimeout)
    if not moved or self.token ~= token or not self.running then
        self.targets:Invalidate(record)
        return false, moveReason
    end

    if not self.detector:ValidateRecord(record) then
        self.targets:Invalidate(record)
        return false, "Target invalid after movement"
    end

    self:_setStatus(STATE.INTERACT)
    local promptReady = self.prompt:WaitUntilAvailable(record, self.config.Farm.PromptTimeout)
    if not promptReady then
        self.targets:Invalidate(record)
        return false, "Prompt unavailable"
    end

    local interacted = false
    for attempt = 1, self.config.Farm.RetryLimit + 1 do
        if self.token ~= token or not self.running then return false, "Stopped" end
        if not self.detector:ValidateRecord(record) then
            self.targets:Invalidate(record)
            return false, "Target invalid before interaction"
        end
        local ok = self.prompt:Interact(record)
        if ok then
            interacted = true
            break
        end
        task.wait(self.config.Farm.RetryDelay)
    end

    if not interacted then
        self.targets:Invalidate(record)
        return false, "Interaction failed"
    end

    self:_setStatus(STATE.VERIFY)
    if not self:_verifyCollected(record) then
        record.State = "COLLECTING"
        return false, "Collection not confirmed"
    end

    self:_setStatus(STATE.COMPLETE)
    self.state:Set("lastAction", "Collected " .. record.Name)
    self.targets:Complete(record)
    return true
end

function FarmController:Start()
    if self.running then return false, "Already running" end
    if not self.state:Get("targetSelection") then
        return false, "Target Selection OFF"
    end

    local token = self.token + 1
    self.token = token
    self.running = true

    task.spawn(function()
        while self.running and self.token == token and self.state:Get("autoFarm") do
            self:_setStatus(STATE.VALIDATE)
            local target = self.targets:GetNextTarget()
            if not target then
                self:_setStatus("NO VALID TARGET")
                break
            end

            self.targets:Lock(target)
            local ok = self:_runOne(target, token)
            if not ok and self.running and self.token == token then
                task.wait(self.config.Farm.InteractionCooldown)
            end
        end

        self.running = false
        if self.state:Get("autoFarm") then
            self.state:Set("autoFarm", false)
        end
        if self.state:Get("status") ~= "SHUTDOWN" then
            self:_setStatus("IDLE")
        end
    end)

    return true
end

return FarmController
