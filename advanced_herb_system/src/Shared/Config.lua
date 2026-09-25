return {
    UI = {
        WidthRatio = 0.82,
        MaxWidth = 760,
        MinWidth = 520,
        Height = 360,
        SafeMargin = 12,
        TouchSize = 44,
    },

    Detection = {
        AlwaysCheckDefault = true,
        RescanInterval = 1.0,
        DebounceWindow = 0.15,
        HerbsPath = { "Game", "spawn", "Herbs" },
    },

    Farm = {
        TargetSelectionDefault = true,
        AutoFarmDefault = false,
        TargetModeDefault = "MANUAL", -- MANUAL | ALL
        PriorityDefault = "Nearest", -- Nearest | First Detected | Rare First | Manual
        MoveTimeout = 8,
        PromptTimeout = 2.5,
        VerificationTimeout = 2.0,
        RetryLimit = 2,
        RetryDelay = 0.35,
        InteractionCooldown = 0.25,
    },

    Debug = {
        EnabledDefault = false,
    },

    -- Set this to the normal collection implementation used by your own game.
    -- It must return true when the collection request was accepted, false on failure.
    InteractionHandler = function(_record)
        return false
    end,
}
