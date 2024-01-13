local config = {
    MOVEMENT_INIT_ANCHOR_LENGTH = 0,
    RUN_VOLUME_CLIENT = 0.5,
    RUN_VOLUME_SERVER = 2,

    --[[ General Settings ]]
    mass = 16, -- def 8.85
    gravity = 0.6, -- 0.3
    friction = 6,
    maxVelocity = 50,
    maxMovementPitch = 0.6,
    surfSlopeAngle = 0.58,

    --[[Sound Settings]]
    walkNoiseSpeed = 15.5,

    --[[ Ground Settings ]]
    groundAccelerate = 9,
    groundDeccelerate = 8, -- the lower this number is, the longer it takes to decel btw
    groundMaxSpeed = 21.5,

    walkMoveSpeed = 14,
    walkAccelerate = 12,

    crouchMoveSpeed = 10,
    crouchFriction = 6,
    crouchAccelerate = 19,
    crouchDecelerate = 10,

    --[[ Air Settings ]]
    airAccelerate = 40,
    airSpeed = 6,
    airMaxSpeed = 36, -- 34
    airMaxSpeedFriction = 6,
    airMaxSpeedFrictionDecrease = .5, -- amount of times per 1/60sec to decrease air fric

    --[[ Jump Settings ]]
    jumpVelocity = 31,
    jumpTimeBeforeGroundRegister = 0.1,

    --[[ Land Settings ]]
    minInAirTimeRegisterLand = 0.1,
    landingMovementJumpGrace = 0.06,
    landingMovementDecreaseLength = 0.27,
    landingMovementDecreaseFriction = 0.70,

    --[[ Bhop Settings ]]
    --missedBhopDecrease = 0.6,
    autoBunnyHop = false,

    --[[ Character Settings ]]
    playerTorsoToGround = 4.65,
    movementStickDistance = 0.8,
    crouchDownAmount = 1.6,
    defaultCameraHeight = -0.5,

    --[[ Keybinds ]]
    keybinds = {
        Forward = "W",
        Backward = "S",
        Left = "A",
        Right = "D",
        Jump = "Space"
    }
}

config.defGroundAccelerate = config.groundAccelerate
config.defGroundDeccelerate = config.groundDeccelerate
config.defFriction = config.friction

return config