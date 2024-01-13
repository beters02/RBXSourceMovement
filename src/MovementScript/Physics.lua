--!strict

local Physics = {}

function Physics.init(shared)
    Physics.__index = shared
    Physics.currentAirFriction = 0
end

function Physics:ApplyFriction(multiplier: number, decel: number): Vector3
    local currentVelocity: Vector3 = self.movementVelocity.Velocity
	local currentSpeed: number = currentVelocity.Magnitude
	
	-- if we're not moving, don't apply friction
    if currentSpeed <= 0 then
        return currentVelocity
    end

    local drop: number = 0
	local fric: number = self.config.friction
	decel = decel or self.config.groundDeccelerate

    local newSpeed: number
	local control: number

	-- apply friction
	control = currentSpeed < decel and decel or currentSpeed
	drop = control * fric * self.currentDT * multiplier

	-- ????????????
	newSpeed = math.max(currentSpeed - drop, 0)
	if currentSpeed > 0 and newSpeed > 0 then
		newSpeed /= currentSpeed
	end

	-- apply
	self.movementVelocity.Velocity = currentVelocity * newSpeed
end

function Physics:ApplyGroundVelocity(groundNormal: Vector3)
    -- update accel dir for sticking
	local accelDir = self:GetAccelerationDirection(groundNormal)

	-- friction
	if self.currentAirFriction > 0 then
		local sub = self.config.airMaxSpeedFrictionDecrease * self.currentDT * 60
		local curr = self.currentAirFriction
		local fric = curr - sub
		if fric < 0 then
			fric = curr + fric
		end

		self:ApplyFriction(math.max(1, fric/self.friction))
		self.currentAirFriction = math.max(0, curr - sub)
	else
		self:ApplyFriction(1)
	end

	-- set the target speed of the player
	local wishSpeed = accelDir.Magnitude
	wishSpeed *= (self.groundMaxSpeed + self.maxSpeedAdd + self.equippedWeaponPenalty)
	
	-- apply acceleration
	self:ApplyGroundAcceleration(accelDir, wishSpeed)

	self:ApplyAntiSticking(self.movementVelocity.Velocity)

	-- calculate slope movement
	local forwardVelocity: Vector3 = groundNormal:Cross(CFrame.Angles(0,math.rad(90),0).LookVector * Vector3.new(self.movementVelocity.Velocity.X, 0, self.movementVelocity.Velocity.Z))
	local yVel = forwardVelocity.Unit.Y * Vector3.new(self.movementVelocity.Velocity.X, 0, self.movementVelocity.Velocity.Z).Magnitude

	-- apply slope movement
	self.movementVelocity.Velocity = Vector3.new(self.movementVelocity.Velocity.X, yVel * (accelDir.Y < 0 and 1.2 or 1), self.movementVelocity.Velocity.Z)
end

function Physics:ApplyAirVelocity()
    
end

function Physics:CollideAndSlide(wishedSpeed, inAir, addSpeed)

	local mod = 1
	
	if wishedSpeed.Magnitude == 0 then
		return wishedSpeed
	end

	-- get input vector
	local inputVec = self.currentInputVec

	local newSpeed = wishedSpeed
	local hrp = self.player.Character.HumanoidRootPart

	-- raycast var
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = self.GetIgnoreDescendantInstances(self.player)
	params.CollisionGroup = "PlayerMovement"
	local rayOffset = Vector3.new(0, -.9, 0) -- y offset

	-- wished speed modifier
	wishedSpeed *= 2

	-- direction amount var
	local dirAmnt = 1.375 * (mod or 1)
	local mainDirAmnt = 1.55 * (mod or 1)

	-- stick var
	local isSticking = false
	local normals = {}
	local stickingDirections = {}
	local ldd = {dir = false, dist = false} -- lowest distance direction
	local partsAlreadyHit = {}

	local lookVecs = {Vector3.new(0, -3.1, 0), Vector3.new(0, 1.5, 0), "Head"}
	for _, v in pairs(lookVecs) do
		local currForDir
		local currSideDir
		local dontAddFor = false
		local values = {}
		local hval = {}
		--local rayPos = hrp.Position + v
		local rayPos = typeof(v) == "Vector3" and hrp.Position + v or Vector3.new(hrp.Position.X, hrp.Parent[v].CFrame.Position, hrp.Position.Z)

		-- right, front, back
		if inputVec.X > 0 then
			currForDir = hrp.CFrame.RightVector
			table.insert(values, currForDir)
			table.insert(hval, hrp.CFrame.LookVector * dirAmnt)
			table.insert(hval, -hrp.CFrame.LookVector * dirAmnt)
		
		-- left, front, back
		elseif inputVec.X < 0 then
			currForDir = -hrp.CFrame.RightVector
			table.insert(values, currForDir)
			table.insert(hval, hrp.CFrame.LookVector * dirAmnt)
			table.insert(hval, -hrp.CFrame.LookVector * dirAmnt)
		end
		
		-- back, left, right
		if inputVec.Z > 0 then
			dontAddFor = true
			currSideDir = -hrp.CFrame.LookVector
			table.insert(values, currSideDir)
			table.insert(hval, hrp.CFrame.RightVector * dirAmnt)
			table.insert(hval, -hrp.CFrame.RightVector * dirAmnt)

		-- front, left, right
		elseif inputVec.Z < 0 then
			currSideDir = hrp.CFrame.LookVector
			table.insert(values, currSideDir)
			table.insert(hval, hrp.CFrame.RightVector * dirAmnt)
			table.insert(hval, -hrp.CFrame.RightVector * dirAmnt)
		end


		if inputVec.Z == 0 and inputVec.X == 0 then
			values[1] = wishedSpeed.Unit
			table.insert(hval, CFrame.new(wishedSpeed.Unit).RightVector * dirAmnt)
			table.insert(hval, -CFrame.new(wishedSpeed.Unit).RightVector * dirAmnt)
		else
			table.insert(values, wishedSpeed.Unit * dirAmnt)
		end
		
		-- middle directions
		if currForDir and currSideDir then
			for diri, dir in pairs(values) do
				values[diri] = dir * mainDirAmnt
			end
			table.insert(values, (currForDir+currSideDir) * mainDirAmnt)
		else
			values[1] *= mainDirAmnt
			table.insert(values, (values[1] + hval[1]).Unit * mainDirAmnt)
			table.insert(values, (values[1] + hval[2]).Unit * mainDirAmnt)
			table.insert(values, hval[1])
			table.insert(values, hval[2])
		end

		for _, b in pairs(values) do
			if not b then continue end
			
			local result = workspace:Raycast(rayPos, b, params)
			if not result then continue end

			if (not ldd.dir or not ldd.dist) or (ldd.dist and ldd.dist < result.Distance) then
				ldd.dir = b
				ldd.dist = result.Distance
			end

			-- don't collide with the same part twice
			if table.find(partsAlreadyHit, result.Instance) then continue end
			table.insert(partsAlreadyHit, result.Instance)

			-- get the movement direction compared to the wall
			local _v =  newSpeed.Unit * result.Normal
			
			-- find active coordinate of comparison
			for _, c in pairs({_v.X, _v.Y, _v.Z}) do
				if math.abs(c) > 0 then
					_v = c
					break
				end
			end

			-- if we are moving AWAY from the normal, (positive)
			-- then do not flatten the vector.

			-- it's not necessary.
			-- you will stick.
			-- stick.

			if type(_v) == "number" and _v > 0 then
				continue
			end

			if not isSticking then isSticking = true end
			newSpeed = flattenVectorAgainstWall(newSpeed, result.Normal)
			newSpeed -= result.Instance.Velocity

			self.movementVelocity.Velocity = newSpeed
			self.collider.Velocity = Vector3.new(newSpeed.X, ((self.sliding or self.crouching) and newSpeed.Y or self.collider.Velocity.Y), newSpeed.Z) -- anti sticking has to be applied on collider velocity as well (resolves head & in air collision)
		end
	end

	return newSpeed, isSticking and normals, isSticking and stickingDirections, isSticking and ldd.dir
end

function flattenVectorAgainstWall(moveVector: Vector3, normal: Vector3)
	-- if magnitudes are 0 then just nevermind
	if moveVector.Magnitude == 0 and normal.Magnitude == 0 then
		return Vector3.zero
	end
	
	-- unit the normal (i its already normalized idk)
	normal = normal.Unit
	
	-- reflect the vector
	local reflected = moveVector - 2 * moveVector:Dot(normal) * normal
	-- add the reflection to the move vector = vector parallel to wall
	local parallel = moveVector + reflected
	
	-- if magnitude 0 NEVERMIND!!!
	if parallel.Magnitude == 0 then
		return Vector3.zero
	end
	
	-- reduce the parallel vector to make sense idk HorseNuggetsXD did all this thank u
	local cropped = parallel.Unit:Dot(moveVector.Unit) * parallel.Unit * moveVector.Magnitude
	return cropped
end

return Physics