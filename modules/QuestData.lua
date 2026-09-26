-- Quest definitions only.
-- Add future quests here without growing Main.lua.

return {
    QUESTS = {
        ["3 Bandits - Krue"] = {
            questText = "Ill take 3 bandits",
            npcRegion = "Windy Peak",
            npcName = "Krue",
            targetRegion = "Windy Peak",
            targetName = "Bandit",
            requiredKills = 3,
            uiPanelName = "Defeat 3 bandits",
            npcYOffset = 5,
            npcForwardOffset = -1.5
        },

        ["Bandit Boss Lv7 - Krue"] = {
            questText = "Ill take the bandit boss(Lv 7)",
            npcRegion = "Windy Peak",
            npcName = "Krue",
            targetRegion = "Windy Peak",
            targetName = "Zuko",
            requiredKills = 1,
            uiPanelName = "Defeat The Bandit Boss",
            npcYOffset = 5,
            npcForwardOffset = -1.5
        },

        ["Bear Cubs Lv10 - Tom"] = {
            questText = "Ill drive the bears back(Lv 10)",
            npcRegion = "Bamboo Grove",
            npcName = "Tom",
            targetRegion = "Bamboo Grove",
            targetName = "Bear Cub",
            requiredKills = 4,
            uiPanelName = "Hunt the Bears",
            npcYOffset = 5,
            npcForwardOffset = -1.5
        },

        ["Mother Bear Lv18 - Tom"] = {
            questText = "Ill fell the Mother Bear(Lv 18)",
            npcRegion = "Bamboo Grove",
            npcName = "Tom",
            targetRegion = "Bamboo Grove",
            targetName = "Mother Bear",
            requiredKills = 1,
            uiPanelName = "Fell the Mother Bear",
            npcYOffset = 5,
            npcForwardOffset = -1.5
        }
    },

    ORDER = {
        "3 Bandits - Krue",
        "Bandit Boss Lv7 - Krue",
        "Bear Cubs Lv10 - Tom",
        "Mother Bear Lv18 - Tom"
    }
}
