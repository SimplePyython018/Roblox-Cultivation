local ShutdownManager = {}
ShutdownManager.__index = ShutdownManager

function ShutdownManager.new(state, farm, targets, detector, movement, prompt)
    return setmetatable({
        state = state,
        farm = farm,
        targets = targets,
        detector = detector,
        movement = movement,
        prompt = prompt,
        done = false,
    }, ShutdownManager)
end

function ShutdownManager:Shutdown()
    if self.done then return end
    self.done = true

    self.state:Set("status", "SHUTDOWN")
    self.state:Set("autoFarm", false)
    self.farm:Stop("SHUTDOWN")
    self.targets:Clear()
    self.detector:Stop()
    self.movement:Cancel()
    self.prompt:Stop()
    self.state:ClearTransient()
    self.state:Set("systemEnabled", false)
end

return ShutdownManager
