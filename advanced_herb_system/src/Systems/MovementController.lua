local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local MovementController = {}
MovementController.__index = MovementController

function MovementController.new(config, state)
    return setmetatable({
        config = config,
        state = state,
        running = false,
        token = 0,
    }, MovementController)
end

local function getCharacterParts()
    local player = Players.LocalPlayer
    local character = player and player.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    return character, humanoid, root
end

function MovementController:Cancel()
    self.token += 1
    self.running = false
end

function MovementController:MoveTo(position, timeout)
    if typeof(position) ~= "Vector3" then
        return false, "Invalid position"
    end

    local _, humanoid, root = getCharacterParts()
    if not humanoid or not root then
        return false, "Character unavailable"
    end

    local myToken = self.token + 1
    self.token = myToken
    self.running = true
    humanoid:MoveTo(position)

    local started = os.clock()
    local reached = false
    while self.running and self.token == myToken do
        local _, currentHumanoid, currentRoot = getCharacterParts()
        if not currentHumanoid or not currentRoot then
            self.running = false
            return false, "Character changed"
        end
        if (currentRoot.Position - position).Magnitude <= 4.5 then
            reached = true
            break
        end
        if os.clock() - started >= (timeout or self.config.Farm.MoveTimeout) then
            break
        end
        RunService.Heartbeat:Wait()
    end

    self.running = false
    if reached then
        return true
    end
    return false, "Movement timeout/cancelled"
end

return MovementController
