--[[ TODO ]]
--[[

	- Add particles for walking/landing/dashing

]]

local MOVEMENT_INIT_ANCHOR_LENGTH = 0
local RUN_VOLUME_CLIENT = 0.5
local RUN_VOLUME_SERVER = 2

-- [[ Services ]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService('UserInputService')
local RunService = game:GetService("RunService")
local Framework = require(ReplicatedStorage:WaitForChild("Framework"))
local SoundModule = require(Framework.Module.Sound)
local Strings = require(Framework.Module.lib.fc_strings)
--local instanceLib = require(Framework.Module.lib.fc_instance)

-- [[ Define Local Variables ]]
local Inputs
local Events = script:WaitForChild("Events")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hum = character:WaitForChild("Humanoid")
local camera = workspace.CurrentCamera
local collider = character:WaitForChild("HumanoidRootPart")
local head = character:WaitForChild("Head")
local runv = RUN_VOLUME_CLIENT

-- lets anchor the character while he loads so we dont fall through the ground lol
collider.Anchored = true

local cameraLook = Vector3.new()
local cameraYaw = Vector3.new()
local currentInputSum = {Forward = 0, Side = 0}
local currentDT = 1/60

local playerGrounded = false
local jumping = false
local crouching = false
local walking = false
local jumpCooldown = false
local inAir = false
local landing = false
local inAirMovementState = false
local onGroundMovementState = false
local playerVelocity = Vector3.zero
local landed = Events:WaitForChild("Landed")
local dashModule = require(ReplicatedStorage.Services.AbilityService.Ability.Dash)

local runningAnimation = hum.Animator:LoadAnimation(hum.Animations.Run)
local jumpingAnimation = hum.Animator:LoadAnimation(hum.Animations.Jump)
local crouchingAnimation = hum.Animator:LoadAnimation(hum.Animations.Crouch)

--[[
	Movement Scope
]]
local Movement = {
	
	-- constants
	player = player,
	character = character,
	humanoid = character:WaitForChild("Humanoid"),
	camera = camera,
	collider = collider,
	currentDT = currentDT,
	head = head,
	
	-- mut
	rayYLength = nil,
	rayXLength = 0.4,
	
	movementPosition = nil,
	movementPositionD = 125,
	movementPositionP = 14000,
	movementPositionForce = 400000,
	
	movementVelocity = nil,
	movementVelocityP = 1500,
	movementVelocityForce = 300000,

	dashing = false,
	currentAirFriction = 0,
	sliding = false
}
Movement.__index = Movement

Movement.Sounds = {
	runDefault = Movement.collider.Run_Tile, -- mut
	runTile = Movement.collider.Run_Tile,
	runMetal = Movement.collider.Run_Metal,
	runWood = Movement.collider.Run_Wood,

	landDefault = Movement.collider.Land_Tile,
	landTile = Movement.collider.Land_Tile,
	landMetal = Movement.collider.Land_Metal,
	landWood = Movement.collider.Land_Wood
}



Movement.Sounds.runDefault.Volume = runv

Movement.GetIgnoreDescendantInstances = function()
	return {player.Character, workspace.CurrentCamera, workspace.Temp, workspace.MovementIgnore}
end

--[[
	Init Movement Extrensic Module Functions & Configuration
	
	This will set all of the Modules functions variables into this "Movement" space.
	Variables will replicate as long as the function is called with ":". (Movement:GetMovementVelocity)
]]

-- extract configuration variables and put them in the scope
--[[local config = require(script.Configuration)
for i, v in pairs(config) do
	Movement[i] = v
end]]

local config = require(script.Config)

--[[ init estrictions ]]
--[[local Restrictions = require(script:WaitForChild("Restrictions"))
Restrictions.Init(config)]]

for i, v in pairs(config) do
	Movement[i] = v
end

--create YLength after config variables are added
Movement.rayYLength = Movement.playerTorsoToGround + Movement.movementStickDistance

-- Total max speed add modifier (for weapon slowing)
Movement.maxSpeedAdd = 0
Movement.equippedWeaponPenalty = 0

-- update camera height
hum.CameraOffset = Vector3.new(0, Movement.defaultCameraHeight, 0)

-- extract movement functions and put them in the Movement scope
for i, v in pairs(setmetatable(require(script.Functions), Movement)) do
	if not Movement[i] then
		Movement[i] = v
	end
end

-- extract children of functions
for i, v in pairs(script.Functions:GetChildren()) do
	if not Movement[v.Name] then
		Movement[v.Name] = require(v)
	end
end

-- extract physics functions
for i, v in pairs(setmetatable(require(script.Physics), Movement)) do
	if not Movement[i] then
		Movement[i] = v
	end
end

--[[ Process Movement Functions ]]

--[[
	@title  		- Movement.Air

	@summary
]]

function Movement.Air()
	Movement.movementPosition.maxForce = Vector3.new()
	Movement:ApplyAirVelocity()
	Movement.movementVelocity.maxForce = Movement:GetMovementVelocityAirForce()
	local runsnd = Movement.Sounds.runDefault
	if runsnd.IsPlaying then
		SoundModule.StopReplicated(runsnd)
	end
end

--[[
	@title  		- Movement.Run

	@summary
]]

local PlayerActionsState = States.State("PlayerActions")
function Movement.Run(hitPosition, hitNormal, hitMaterial)
	Movement.movementPosition.position = hitPosition + Vector3.new(0, Movement.playerTorsoToGround, 0)
	Movement.movementPosition.maxForce = Vector3.new(0, Movement.movementPositionForce, 0)
	Movement:ApplyGroundVelocity(hitNormal)
	Movement.movementVelocity.maxForce = Movement:GetMovementVelocityForce()
	Movement.movementVelocity.P = Movement.movementVelocityP

	-- get current run sound
	Movement.RegisterGroundMaterialSounds(hitMaterial)

	local runsnd = Movement.Sounds.runDefault

	if jumpingAnimation.IsPlaying then
		jumpingAnimation:Stop(0.1)
	end

	-- Running Sounds
	if Movement.movementVelocity.Velocity.Magnitude > Movement.walkNoiseSpeed + PlayerActionsState:get(player, "currentEquipPenalty") then
		if not runsnd.IsPlaying then SoundModule.PlayReplicated(runsnd, serverRunVolume) end
	else
		if runsnd.IsPlaying then SoundModule.StopReplicated(runsnd) end
	end

	-- Running Animations
	if Movement.movementVelocity.Velocity.Magnitude > 1 then
		if not runningAnimation.IsPlaying then runningAnimation:Play(0.2) end
	else
		if runningAnimation.IsPlaying then runningAnimation:Stop(0.2) end
	end

	if not onGroundMovementState then
		onGroundMovementState = true
		MovementState:set(player, "grounded", true)
	end

end

--[[
	@title  		- Movement.Jump

	@summary
]]

local connectViewmodelJump = true
local vmScript

function Movement.Jump(velocity)
	Movement.jumpGrace = tick() + Movement.jumpTimeBeforeGroundRegister -- This is how i saved the glitchy mousewheel jump
	collider.Velocity = Vector3.new(collider.Velocity.X, velocity, collider.Velocity.Z)
	Movement.Air()

	--if hudCharClass.animations.running.isPlaying then hudCharClass.animations.running:Stop(0.2) end
	if runningAnimation.IsPlaying then runningAnimation:Stop(0.1) end

	--hudCharClass.animations.jumping:Play(0.1)
	jumpingAnimation:Play()

	if connectViewmodelJump then
		if not vmScript then vmScript = require(Framework.GetCharacterScript(player.Character, "m_viewmodel")) end
		vmScript:jumpSway(Movement.currentDT)
	end
end

--[[
	@title 			- Movement.Land
	@summary
					- Produces a movement decrease for a specified time and decrease amount.
					- Uses tweens to constantly apply friction for a set amount of time.
	
	@param[opt]		- {number} fric - Amount of friction to apply at tween's peak.
					- default: Movement.landingMovementDecreaseFriction

	@param[opt]		- {number} waitTime - Total length of speed decrease.
					- default: Movement.landingMovementDecreaseLength

	@param[opt]		- {number} iterations - Total loop iterations
					- default: 12

	@return			- {void}
]]

local ctween
local cconn
local landProcessing = false
local cnumval = Instance.new("NumberValue", RepTemp)

function landFinish()
	ctween[1]:Destroy()
	ctween[2]:Destroy()
	cconn:Disconnect()
	landProcessing = false
	landing = false
	MovementState:set(player, "landing", false)
end

function Movement.Land(fric: number, waitTime: number, hitMaterial)

	MovementState:set(player, "landing", true)

	fric = fric or (Movement.dashing and dashModule.Options.landingMovementDecreaseFriction) or Movement.landingMovementDecreaseFriction
	waitTime = waitTime or (Movement.dashing and dashModule.Options.landingMovementDecreaseLength) or Movement.landingMovementDecreaseLength
	hitMaterial = hitMaterial or Enum.Material.Concrete
	landing = true
	Movement.sliding = false

	Movement.RegisterGroundMaterialSounds(hitMaterial)

	local landsnd = Movement.Sounds.landDefault
	local runsnd = Movement.Sounds.runDefault
	runsnd.Volume = 0
	if not landsnd.IsPlaying then
		SoundModule.PlayReplicated(landsnd)
		task.delay(0.1, function()
			SoundModule.StopReplicated(landsnd)
			runsnd.Volume = runv
		end)
	end

	if landProcessing then
		ctween[1]:Destroy()
		ctween[2]:Destroy()
		cconn:Disconnect()
	end

	landProcessing = true
	cnumval.Value = 0
	local startLand = tick() + Movement.landingMovementJumpGrace

	ctween = {
		TweenService:Create(cnumval, TweenInfo.new(waitTime/2), {Value = fric}),
		TweenService:Create(cnumval, TweenInfo.new(waitTime), {Value = 0})
	}

	ctween[1].Completed:Once(function()
		ctween[2]:Play()
		ctween[2].Completed:Once(function()
			landFinish()
		end)
	end)

	cconn = RunService.RenderStepped:Connect(function(dt)
		if tick() < startLand or not landProcessing then
			return
		end
		if jumping or inAir then
			landFinish()
			return
		end
		Movement:ApplyFriction(cnumval.Value)
	end)

	-- play friction tween
	ctween[1]:Play()
end

--[[
	@title  		- Movement.Crouch

	@summary
]]

local crouchDebounce = false

function Movement.Crouch(crouch: boolean)

	if crouch then
		
		if crouchDebounce then return not crouch end

		crouchDebounce = true
		task.delay(0.07, function() crouchDebounce = false end)

		-- slow player
		
		Movement.SetFrictionVars("crouch")
		task.wait()
		
		-- play crouching animation
		crouchingAnimation:Play(0.3)

		-- lower camera height
		hum.CameraOffset = Vector3.new(0, -Movement.crouchDownAmount, 0)

		-- movement state
		MovementState:set(player, "crouching", true)
		Movement.crouching = true

	else
	
		-- unslow player
		Movement.SetFrictionVars("run")
		task.wait()

		-- stop crouching animation
		crouchingAnimation:Stop(0.5)

		-- raise camera height
		hum.CameraOffset = Vector3.new(0, Movement.defaultCameraHeight, 0)

		-- movement state
		MovementState:set(player, "crouching", false)
		Movement.crouching = false

	end
	
	return crouch
end

--[[
	@title  		- Movement.Walk

	@summary
]]

local walkDebounce = false

function Movement.Walk(walk: boolean)
	if walk then
		if walkDebounce then return not walk end

		walkDebounce = true
		task.delay(0.07, function() walkDebounce = false end)

		-- slow player
		Movement.SetFrictionVars("walk")
		Movement.walking = true
		task.wait()
	else
		-- unslow player
		Movement.SetFrictionVars("run")
		Movement.walking = false
		task.wait()
	end

	return walk
end

function Movement.SetFrictionVars(frictionVarKey: string)
	if not Movement.LastFrictionVar then Movement.LastFrictionVar = "run" end
	if frictionVarKey == "crouch" then
		Movement.LastFrictionVar = "crouch"
		Movement.maxSpeedAdd -= (Movement.groundMaxSpeed - Movement.crouchMoveSpeed)
		Movement.groundAccelerate = Movement.crouchAccelerate
		Movement.friction = Movement.crouchFriction
	elseif frictionVarKey == "walk" then
		Movement.LastFrictionVar = "walk"
		Movement.maxSpeedAdd -= (Movement.groundMaxSpeed - Movement.walkMoveSpeed)
		Movement.groundAccelerate = Movement.walkAccelerate
		Movement.friction = Movement.crouchFriction
	elseif frictionVarKey == "run" then
		local sub = (Movement.LastFrictionVar == "crouch" and Movement.crouchMoveSpeed) or (Movement.LastFrictionVar == "walk" and Movement.walkMoveSpeed) or 0
		Movement.LastFrictionVar = "run"
		Movement.maxSpeedAdd += (Movement.groundMaxSpeed - sub)
		Movement.groundAccelerate = Movement.defGroundAccelerate
		Movement.friction = Movement.defFriction
	end
end

function _SetGroundSound(runSound, landSound)
	if Movement.Sounds.runDefault ~= runSound then
		if Movement.Sounds.runDefault.isPlaying then
			SoundModule.StopReplicated(Movement.Sounds.runDefault)
		end
	
		Movement.Sounds.runDefault = runSound
		Movement.Sounds.landDefault = landSound
	end
end

function Movement.RegisterGroundMaterialSounds(hitMaterial)
	if hitMaterial == Enum.Material.Metal or hitMaterial == Enum.Material.CorrodedMetal then
		_SetGroundSound(Movement.Sounds.runMetal, Movement.Sounds.landMetal)
	elseif hitMaterial == Enum.Material.Wood or hitMaterial == Enum.Material.WoodPlanks then
		_SetGroundSound(Movement.Sounds.runWood, Movement.Sounds.landWood)
	else
		_SetGroundSound(Movement.Sounds.runTile, Movement.Sounds.landTile)
	end
end

--[[
	Movement Abilities
]]

function Movement.RegisterDashVariables(strength, upstrength, upstrengthmod)
	dashVariables.strength = strength
	dashVariables.upstrength = upstrength
	dashVariables.jumpupstrengthmod = upstrengthmod
	dashVariables.direction = collider.CFrame.LookVector

	if currentInputSum.Forward ~= 0 or currentInputSum.Side ~= 0 then
		local fordir = currentInputSum.Forward ~= 0 and (currentInputSum.Forward > 0 and collider.CFrame.LookVector or -collider.CFrame.LookVector) or 1
		local sidedir = currentInputSum.Side ~= 0 and (currentInputSum.Side > 0 and -collider.CFrame.RightVector or collider.CFrame.RightVector) or 1

		dashVariables.direction = (fordir * sidedir).Unit
	end

	dashVariables.trigger = true
end

function Movement.Dash()
	Movement.dashing = true
	
	Movement.Jump(dashVariables.upstrength * (not playerGrounded and dashVariables.jumpupstrengthmod or 1))

	task.wait()
	
	local newVel = (dashVariables.direction * dashVariables.strength)
	Movement.movementVelocity.Velocity = Vector3.new(newVel.X, Movement.movementVelocity.Velocity.Y, newVel.Z)

	Movement.Air()
	
	playerGrounded = false
	inAir = tick()
	
	task.wait(0.01)
	
	task.spawn(function()
		landed.Event:Wait()
		Movement.dashing = false
	end)
	
	--Movement.Land(0.6)
end

function Movement.Satchel(force)
	print(force)
	Movement.dashing = true
	Movement.Jump(force.Y)
	task.wait()
	
	local velocity = Movement.movementVelocity.Velocity + Vector3.new(force.X, 0, force.Z)
	Movement.movementVelocity.Velocity = velocity
	Movement.Air()
	playerGrounded = false
	inAir = tick()
	task.wait()

	Movement.dashing = false
end

--[[
	Processing
]]

local processCrouch
local processWalk
local lastSavedHitPos

-- THE FIX IS RIGHT HERE BABY!***
-- This fixes the Crouching in corners bugs. Thank god. Be sure to apply it to collider and movementVelocity
local function fixVel(vel)
	local currVel = vel
	if not currVel.X or currVel.X ~= currVel.X then vel = Vector3.new(0,0,0)
	elseif not currVel.Y or currVel.Y ~= currVel.Y then vel = Vector3.new(0,0,0)
	elseif not currVel.Z or currVel.Z ~= currVel.Z then vel = Vector3.new(0,0,0) end
	return vel
end

function getMoveSum()
	return math.abs(currentInputSum.Forward) + math.abs(currentInputSum.Side)
end

function Movement.ProcessMovement()
	cameraYaw = Movement:GetYaw()
	cameraLook = cameraYaw.lookVector
	Movement.cameraYaw = cameraYaw
	Movement.cameraLook = cameraLook
	
	if cameraLook == nil then print('NILLAGE') return end

	-- THIS IS THE FIX!***
	Movement.movementVelocity.Velocity = fixVel(Movement.movementVelocity.Velocity)
	Movement.collider.Velocity = fixVel(Movement.collider.Velocity)

	local hitPart, hitPosition, hitNormal, yRatio, zRatio, ladderTable = Movement:FindCollisionRay()
	playerGrounded = hitPart and true or false
	if not playerGrounded or not hitPosition or not hitPart then
		local params = instanceLib.New("RaycastParams", {
			FilterType = Enum.RaycastFilterType.Exclude,
			FilterDescendantsInstances = {player.Character, RunService:IsClient() and workspace.CurrentCamera or {}},
			CollisionGroup = "PlayerMovement"
		})
	
		local result = workspace:Blockcast(
			CFrame.new(player.Character.HumanoidRootPart.CFrame.Position + Vector3.new(0, -3.25 + (Movement.crouching and Movement.crouchDownAmount or 0), 0)),
			Vector3.new(1.5,1.5,1),
			Vector3.new(0, -1, 0),
			params
		)
	
		if result then
			hitPart = result.Instance
			hitPosition = result.Position
			hitNormal = result.Normal
		end
	end

	playerVelocity = collider.Velocity - Vector3.new(0, collider.Velocity.y, 0)
	
	if Movement.jumpGrace and tick() < Movement.jumpGrace and collider.Velocity.Y > 0 then
		playerGrounded = false
	end

	if not playerGrounded then
		if Movement.sliding then Movement.sliding = false end
	elseif playerGrounded and hitNormal.Y < Movement.surfSlopeAngle and hitNormal.Y ~= 0 then
		playerGrounded = false
		Movement.sliding = true
		Movement.slideNormal = hitNormal
	end

	if Movement.sliding and hitNormal.Magnitude == 0 then
		Movement.sliding = false
		playerGrounded = false
	end

	if not playerGrounded and not inAir then
		inAir = tick()
	end

	-- attempt resolve players flying out of the map
	if Movement.movementVelocity.Velocity.Magnitude > 100 or Movement.collider.Velocity.Magnitude > 100 then
		Movement.movementVelocity.Velocity = Vector3.zero
		Movement.collider.Velocity = Vector3.zero
	else
		lastSavedHitPos = hitPosition
	end
	
	-- [[ LANDING REGISTRATION ]]
	if playerGrounded and inAir and (not Movement.jumpGrace or tick() >= Movement.jumpGrace) then
		local a = inAir
		inAir = false
		inAirMovementState = false

		-- only register land after given time in air
		if tick() >= a + Movement.minInAirTimeRegisterLand and not landing then
			Movement.Land(false, false, hitPart.Material)
			landed:Fire()
		else
			Movement.Run(hitPosition, hitNormal, hitPart.Material)
			return
		end

	end
	
	-- [[ JUMP & CROUCH INPUT REGISTRATION ]]

	if Inputs.FormattedKeys[Inputs.Keys.Jump[1]] > 0 then
		jumping = true
	else
		jumping = false
		if playerGrounded and jumpCooldown then
			jumpCooldown = false
		end
	end

	processCrouch = Inputs.FormattedKeys[Inputs.Keys.Crouch[1]] > 0
	processWalk = Inputs.FormattedKeys[Inputs.Keys.Walk[1]] > 0

	if processCrouch then

		-- cancel walk when crouching
		-- we dont need to do the same for
		-- walk since you cant crouch and
		-- walk at the same time
		processWalk = false

		if walking then
			walking = false
			Movement.Walk(false)
		end

		if not crouching then
			crouching = true
			Movement.Crouch(true)
		end

	elseif crouching then
		crouching = false
		Movement.Crouch(false)
	end

	if processWalk then

		-- do not process walk while crouching
		if not crouching and not walking then
			walking = true
			Movement.Walk(true)
		end

	elseif walking then
		walking = false
		Movement.Walk(false)
	end

	task.wait()

	-- resolve crouch/walk friction
	if not walking and not crouching then
		if Movement.LastFrictionVar and Movement.LastFrictionVar ~= "run" then
			Movement.SetFrictionVars("run")
		end
	end
	
	-- set rotation
	Movement:SetCharacterRotation()
	
	-- [[ GROUND MOVEMENT ]]
	if playerGrounded then
		if jumping then
			-- call ground movement if on jump cooldown and trying to jump
			if jumpCooldown or inAir or Movement.dashing then
				Movement.Run(hitPosition, hitNormal, hitPart.Material)
			else
				-- [[ JUMP MOVEMENT ]]
				if not Movement.autoBunnyHop and Inputs.Keys.Jump[1] ~= "MouseWheel" then --jump cooldown start
					jumpCooldown = true
				end

				Movement.Jump(Movement.jumpVelocity)
				inAir = tick()
			end
		else
			-- [[ RUN MOVEMENT ]]
			Movement.Run(hitPosition, hitNormal, hitPart.Material)
		end
		if Movement.dashing then Movement.dashing = false end
	else
		-- [[ AIR MOVEMENT ]]
		
		-- set inAir to current time if this is first instance of being in the air (start falling)
		if not inAir then
			inAir = tick()
			if not inAirMovementState then
				inAirMovementState = true
				onGroundMovementState = false
			end
		end

		-- get velocity
		Movement.Air()
	end
end

--[[
	Inputs
]]

Inputs = {}
Inputs.Keys = {
	Forward = {"W", false},
	Backward = {"S", false},
	Left = {"A", false},
	Right = {"D", false},
	--Jump = {"Space", false}
	Jump = {"MouseWheel", false},
	Crouch = {"C", false},
	Walk = {"LeftShift", false}
}

Inputs.FormattedKeys = {
	W = 0,
	S = 0,
	A = 0,
	D = 0,
	C = 0,
	--Space = 0
	MouseWheel = 0,
	LeftShift = 0
}

-- Changes the Inputs.Keys and Inputs.Formatted keys values and will update the old ones.
-- This is the proper way to change a keybind!
function Inputs.ChangeKey(key: string, value: string)
	local _cap = Strings.firstToUpper(key)
	Inputs.FormattedKeys[Inputs.Keys[_cap][1]] = nil -- remove current formatted key
	Inputs.Keys[_cap][1] = value					 -- set Inputs.Keys value
	Inputs.FormattedKeys[Inputs.Keys[_cap][1]] = 0   -- add key to formatted
end

function Inputs.FormatKeys()
	Inputs.FormattedKeys = {}
	for _, v in pairs(Inputs.Keys) do
		Inputs.FormattedKeys[v[1]] = v[2]
	end
end

function Inputs.OnInput(input) -- began and end
	if player:GetAttribute("Typing") then return end
	
	local inputState
	if input.UserInputState == Enum.UserInputState.Begin then
		inputState = true
	elseif input.UserInputState == Enum.UserInputState.End then
		inputState = false
	else
		return
	end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		--direct key name
		local key = input.KeyCode.Name
		if Inputs.FormattedKeys[key] ~= nil then
			Inputs.FormattedKeys[key] = inputState and 1 or 0
		end
	end
end

local function RegisterMouseWheelInput()
	Inputs.FormattedKeys[Inputs.Keys.Jump[1]] = 1
	task.wait()
	Inputs.FormattedKeys[Inputs.Keys.Jump[1]] = 0
end

function Inputs.OnInputChange(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel and Inputs.Keys.Jump[1] == "MouseWheel" then
		RegisterMouseWheelInput()
	end
end

function Inputs.UpdateMovementSum()
	currentInputSum.Forward = Inputs.FormattedKeys[Inputs.Keys.Forward[1]] + -Inputs.FormattedKeys[Inputs.Keys.Backward[1]]
	currentInputSum.Side = Inputs.FormattedKeys[Inputs.Keys.Left[1]] + -Inputs.FormattedKeys[Inputs.Keys.Right[1]]
	Movement.currentInputSum = currentInputSum
end

--[[
	Communication (Only property changed right now)
]]

local Communicate = require(script:WaitForChild("Communicate"))

local function listenForPropertyChanged()
	local newproptab = Communicate._listenForChanges(Movement)
	if not newproptab then return end

	for i, v in pairs(newproptab) do
		Movement[i] = v
	end
	return
end


--[[
	Main Scope
]]

local prevUpdateTime = nil
local updateDT = 1/60

function Update(dt)
	if not hum or (hum and hum.Health <= 0) then return end
	currentDT = dt
	Movement.currentDT = dt

	Inputs.UpdateMovementSum()
	Movement.ProcessMovement()
	listenForPropertyChanged()
end

function SetDeltaTime() --seconds
	local UpdateTime = tick() 
	if prevUpdateTime ~= nil then
		updateDT = (UpdateTime - prevUpdateTime)
	else
		updateDT = 1/60
	end
	prevUpdateTime = UpdateTime
end

function UpdateLoop()
	SetDeltaTime()
	Update(updateDT)
end

function Main()
	local a = player.Character:FindFirstChildOfClass("Humanoid") or player.Character:WaitForChild("Humanoid")
	a.PlatformStand = true

	InitMovers()

	-- connect key bind change listener
	Inputs.InitKeys()
	Inputs.ListenForKeyBindChanges()

	-- connect script connections
	UserInputService.InputBegan:Connect(Inputs.OnInput)
	UserInputService.InputEnded:Connect(Inputs.OnInput)
	UserInputService.InputChanged:Connect(Inputs.OnInputChange)
	RunService:BindToRenderStep("updateLoop", 100, UpdateLoop)

	-- connect movement abilities
	script.Events.Dash.Event:Connect(Movement.RegisterDashVariables)
	script.Events.Satchel.Event:Connect(Movement.Satchel)

	script.Events.Get.OnInvoke = function()
		return playerGrounded
	end

	local function _init()
		if hum.Health > 0 then
			if not player:GetAttribute("Loaded") then
				repeat task.wait() until player:GetAttribute("Loaded")
			end
			collider.Anchored = false
			Movement.movementVelocity.Velocity = Vector3.zero
			collider.Velocity = Vector3.zero
		end
	end

	if MOVEMENT_INIT_ANCHOR_LENGTH > 0 then
		task.delay(MOVEMENT_INIT_ANCHOR_LENGTH, function()
			_init()
		end)
	else
		_init()
	end
end

function InitMovers()
	local movementPosition = Instance.new("BodyPosition", collider)
	movementPosition.Name = "movementPosition"
	movementPosition.D = Movement.movementPositionD
	movementPosition.P = Movement.movementPositionP
	movementPosition.maxForce = Vector3.new()
	movementPosition.position = Vector3.new()
	Movement.movementPosition = movementPosition
	local movementVelocity = Instance.new("BodyVelocity", collider)
	movementVelocity.Name = "movementVelocity"
	movementVelocity.P = Movement.movementVelocityP
	movementVelocity.maxForce = Vector3.new()
	movementVelocity.velocity = Vector3.new()
	Movement.movementVelocity = movementVelocity
	local gravityForce = Instance.new("BodyForce", collider)
	gravityForce.Name = "gravityForce"
	gravityForce.force = Vector3.new(0, (1-Movement.gravity)*196.2, 0) * Movement.mass
	Movement.gravityForce = gravityForce
end

Main()