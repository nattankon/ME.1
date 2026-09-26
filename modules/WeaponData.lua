-- Weapon definitions only.
-- Auto Best priority is resolved in Main.lua from strongest to weakest.

return {
    WEAPONS = {
        ["Cutlass"] = {
            toolbarIndex = 10,
            directCombat = true,
            combatRemoteName = "Regular Katana",
            comboTimings = {
                [1] = 0.12500000000000003,
                [2] = 0.06500000000000003,
                [3] = 0.06500000000000003,
                [4] = 0.1,
                [5] = 0.07500000000000001
            }
        },

        ["Regular Katana"] = {
            price = 500,
            toolbarIndex = 3,
            shopRegion = "Windy Peak",
            shopNpc = "Raze",
            shopName = "Raze's Shop",
            directCombat = true,
            comboTimings = {
                [1] = 0.12500000000000003,
                [2] = 0.06500000000000003,
                [3] = 0.06500000000000003,
                [4] = 0.1,
                [5] = 0.07500000000000001
            }
        },

        ["Fancy Katana"] = {
            price = 1500,
            toolbarIndex = 4,
            shopRegion = "Windy Peak",
            shopNpc = "Raze",
            shopName = "Raze's Shop",
            directCombat = true,
            combatRemoteName = "Regular Katana",
            comboTimings = {
                [1] = 0.12500000000000003,
                [2] = 0.06500000000000003,
                [3] = 0.06500000000000003,
                [4] = 0.1,
                [5] = 0.07500000000000001
            }
        }
    },

    MODES = {
        "Auto Best",
        "Fist",
        "Regular Katana",
        "Fancy Katana",
        "Cutlass"
    }
}
