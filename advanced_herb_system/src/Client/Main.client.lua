local Config = require(script.Parent.Config)
local StateManager = require(script.Parent.StateManager)
local HerbDetector = require(script.Parent.HerbDetector)
local TargetManager = require(script.Parent.TargetManager)
local MovementController = require(script.Parent.MovementController)
local PromptController = require(script.Parent.PromptController)
local FarmController = require(script.Parent.FarmController)
local ShutdownManager = require(script.Parent.ShutdownManager)
local UIController = require(script.Parent.UIController)

local state = StateManager.new()
state:Set("alwaysCheck", Config.Detection.AlwaysCheckDefault)
state:Set("targetSelection", Config.Farm.TargetSelectionDefault)
state:Set("targetMode", Config.Farm.TargetModeDefault)
state:Set("priority", Config.Farm.PriorityDefault)
state:Set("autoFarm", Config.Farm.AutoFarmDefault)
state:Set("debug", Config.Debug.EnabledDefault)

local detector = HerbDetector.new(Config, state)
local targets = TargetManager.new(Config, state, detector)
local movement = MovementController.new(Config, state)
local prompt = PromptController.new(Config, state, detector)
local farm = FarmController.new(Config, state, detector, targets, movement, prompt)
local shutdown = ShutdownManager.new(state, farm, targets, detector, movement, prompt)
local ui = UIController.new(Config, state, detector, targets, farm, shutdown)

state:OnChanged("autoFarm", function(enabled)
    if enabled then
        farm:Start()
    else
        farm:Stop("IDLE")
    end
end)

state:OnChanged("alwaysCheck", function(enabled)
    if enabled then
        detector:Start()
    end
end)

state:OnChanged("targetMode", function(mode)
    targets:SetMode(mode)
end)

state:OnChanged("systemEnabled", function(enabled)
    if not enabled then
        farm:Stop("SHUTDOWN")
        detector:Stop()
    end
end)

detector:Start()
ui:Start()

task.spawn(function()
    while state:Get("systemEnabled") do
        task.wait(Config.Detection.RescanInterval)
        if state:Get("alwaysCheck") then
            detector:UpdateContinuousLoop()
            targets:RefreshQueue()
        end
    end
end)

print("[AdvancedHerbSystem] Started")
