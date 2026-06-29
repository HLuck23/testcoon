Config = {}

-- Presets Configuration
-- name: Display name
-- description: Short description
-- dict: Animation dictionary
-- anim: Animation name
-- blendIn: Blend in speed (higher = smoother transition)
-- blendOut: Blend out speed (negative = keep anim after duration)
-- duration: Animation duration in ms
-- playbackRate: Speed multiplier (2.0 = 2x fast, 0.5 = half speed)
-- pvpReady: Tag for PvP optimization

Config.Presets = {
    {
        name = "Default",
        description = "Pistol draw animation",
        dict = "rcmjosh4",
        anim = "josh_leadout_cop2",
        blendIn = 8.0,
        blendOut = -8.0,
        duration = 700,
        playbackRate = 1.5,
        pvpReady = false
    },
    {
          name = "Default",
        description = "Pistol draw animation",
        dict = "rcmjosh4",
        anim = "josh_leadout_cop2",
        blendIn = 8.0,
        blendOut = -8.0,
        duration = 700,
        playbackRate = 1.5,
        pvpReady = false
    }
}