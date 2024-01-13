local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

type MovementKeyString = "Forward" | "Backward" | "Left" | "Right" | "Jump"

local player = game.Players.LocalPlayer
local char
local collider

local movementPosition
local movementVelocity
local gravityForce

local shared = {
    movementVelocity = false,
    movementPosition = false,
    gravityForce = false,
    config = require(script:WaitForChild("Config")),
    player = player, char = false, collider = false,
    pvar = {running = false, walking = false, jumping = false, crouching = false, inAir = false},

    keys = { -- 0 = no, 1 = yes
        Jump = 0,
        Walk = 0,
        Crouch = 0,
        Forward = 0,
        Backward = 0,
        Left = 0,
        Right = 0
    },

    formatted_keys = {} -- Formatted to {W = "Forward"...}
}

function init()
    char = player.Character or player.CharacterAdded:Wait()
    collider = char:WaitForChild("HumanoidRootPart")
    shared.char = char
    shared.collider = collider

    movementPosition = Instance.new("BodyPosition", collider)
	movementPosition.Name = "movementPosition"
	movementPosition.D = shared.config.movementPositionD
	movementPosition.P = shared.config.movementPositionP
	movementPosition.maxForce = Vector3.new()
	movementPosition.position = Vector3.new()
    shared.movementPosition = movementPosition

	movementVelocity = Instance.new("BodyVelocity", collider)
	movementVelocity.Name = "movementVelocity"
	movementVelocity.P = shared.config.movementVelocityP
	movementVelocity.maxForce = Vector3.new()
	movementVelocity.velocity = Vector3.new()
    shared.movementVelocity = movementVelocity

	gravityForce = Instance.new("BodyForce", collider)
	gravityForce.Name = "gravityForce"
	gravityForce.force = Vector3.new(0, (1-shared.config.gravity)*196.2, 0) * shared.config.mass
    shared.gravityForce = gravityForce

    for str, key in pairs(shared.config.keybinds) do
        shared.formatted_keys[key] = str
    end

    UserInputService.InputBegan = inputBegan
    UserInputService.InputEnded = inputEnded
    UserInputService.InputChanged = inputChanged
end

function update(dt)
    shared.currentDT = dt
end

function inputBegan(input, gp)
    if gp then return end
    if getKey(input.KeyCode.Name) then
        keyDown(input.KeyCode.Name)
    end
end

function inputEnded(input, gp)
    if gp then return end
    if getKey(input.KeyCode.Name) then
        keyUp(input.KeyCode.Name)
    end
end

function inputChanged(input, gp)
    if gp then return end
end

--

function Run(hitPosition: Vector3, hitNormal: Vector3)
    movementPosition.position = hitPosition + Vector3.new(0, shared.config.playerTorsoToGround, 0)
	movementPosition.maxForce = Vector3.new(0, shared.config.movementPositionForce, 0)
	Movement:ApplyGroundVelocity(hitNormal)
	movementVelocity.maxForce = Movement:GetMovementVelocityForce()
	movementVelocity.P = shared.config.movementVelocityP
end

function Land()

end

function Jump()

end

--

function getKey(key) return shared.formatted_keys[key] end
function keyToKeyStr(key): MovementKeyString
    return shared.formatted_keys[key]
end
function keyDown(key) shared.keys[keyToKeyStr(key)] = 1 end
function keyUp(key) shared.keys[keyToKeyStr(key)] = 0 end
function isKeyDown(key) return shared.keys[keyToKeyStr(key)] == 1 end