-- Managed source file.
-- Future changes should patch only the requested section; do not regenerate the whole script.

local RuntimeEnv =
    (getgenv and getgenv())
    or _G

local Modules =
    RuntimeEnv.__WINDYPEAK_MODULES

assert(
    type(Modules) == "table",
    "WindyPeak modules were not injected by loader.lua"
)

local Config =
    assert(
        Modules.Config,
        "Config module missing"
    )

local QuestData =
    assert(
        Modules.QuestData,
        "QuestData module missing"
    )

local BossData =
    assert(
        Modules.BossData,
        "BossData module missing"
    )

local BossWaypoint =
    assert(
        Modules.BossWaypoint,
        "BossWaypoint module missing"
    )

local WeaponData =
    assert(
        Modules.WeaponData,
        "WeaponData module missing"
    )

local FarmPosition =
    assert(
        Modules.FarmPosition,
        "FarmPosition module missing"
    )

local SkillAutomation =
    assert(
        Modules.SkillAutomation,
        "SkillAutomation module missing"
    )

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

--==================================================
-- NETWORK
--==================================================

local Event = ReplicatedStorage
    :WaitForChild("Communication")
    :WaitForChild("ServerAndClient")
    :WaitForChild("Signals")
    :WaitForChild("SignalEvent")
    :WaitForChild("Event")

--==================================================
-- WORLD PATHS
--==================================================

local HumanoidRegions = workspace
    :WaitForChild("Humanoids")
    :WaitForChild("Regions")

local StationaryRegions = workspace
    :WaitForChild("Debree")
    :WaitForChild("Regions")

--==================================================
-- MODULAR DATA
--==================================================

-- Growing quest/boss/weapon definitions live in separate modules.
-- Main.lua only consumes their exported tables.

--==================================================
-- SETTINGS
--==================================================

local speedEnabled = false
local speed = 150

local noclipEnabled = false
local spaceFloatEnabled = false
local spaceHeld = false
local floatSpeed = 45

local antiAfkEnabled = false

local nearbyFarmEnabled = false
local nearbyFarmRange = 100
local nearbyFarmOrigin = nil
local farmHeight = Config.FARM_HEIGHT
local farmPositionMode = Config.FARM_POSITION_MODE

local questFarmEnabled = false
local selectedQuestName = QuestData.ORDER[1]
local questSelectionVersion = 0

local bossFarmEnabled = false
local selectedBossName = BossData.ORDER[1]
local bossOverrideActive = false
local bossAutoLootEnabled = true
local bossLootBusy = false
local bossLastPosition = nil
local bossResumeCFrame = nil
local bossResumeCharacterVersion = 0
local bossScanReadyAt = 0
local questKillCount = 0
local questNeedsAccept = false
local questAcceptReadyAt = 0
local questBusy = false

-- Quest progress is verified from the replicated quest UI.
-- Humanoid.Died is used only as a signal to re-check server progress.
local questUiWasActive = false
local questProgressSeen = false
local questLastProgress = -1
local questLastTargetDeathAt = 0
local questProgressHoldUntil = 0

local weaponMode = WeaponData.MODES[1]
local autoBuyWeaponEnabled = true
local weaponBusy = false
local currentWeaponName = nil
local weaponPurchaseRetryAt = 0

-- Timing/range constants are supplied by Config.lua.


local target = nil
local targetMode = nil
local targetVersion = 0
local targetReadyAt = 0
local lockFrames = 0
local targetDiedConnection = nil
local targetDeathCounted = false

local combatNoDamageCycles = 0
local combatRecoveryReadyAt = 0
local combatStallEvents = 0

local DoFunction = nil
local originalDo = nil
local capturedArgs = nil

-- Cache one combat argument set per weapon.
-- Switching Fist <-> Katana can reuse it instead of requiring
-- another simulated click every time.
local combatArgsByWeapon = {}

local currentHumanoid = nil
local originalWalkSpeed = 16
local originalCollision = {}

local scriptAlive = true

-- Runtime coordinator. Keep cross-controller state in one table so the
-- status panel can explain why a controller is paused and so explicit
-- movement operations cannot overwrite each other.
local runtime = {
    movementOwner = nil,
    movementSince = 0,
    weaponOperation = "Idle",
    weaponSince = 0,
    characterVersion =
        player.Character and 1 or 0,
    bossSelectionVersion = 0,
    lastEvent = "Init",
    lastEventAt = os.clock()
}

local function markRuntimeEvent(
    message
)
    runtime.lastEvent =
        tostring(message)

    runtime.lastEventAt =
        os.clock()
end

local function acquireMovement(
    owner,
    timeout
)
    local deadline =
        os.clock()
        + (timeout or 0)

    repeat
        if runtime.movementOwner == nil then
            runtime.movementOwner =
                owner

            runtime.movementSince =
                os.clock()

            markRuntimeEvent(
                "Move:" .. owner
            )

            return true
        end

        if (timeout or 0) <= 0 then
            return false
        end

        task.wait(0.03)
    until not scriptAlive
        or os.clock() >= deadline

    return false
end

local function releaseMovement(
    owner
)
    if runtime.movementOwner
        == owner then

        runtime.movementOwner =
            nil

        runtime.movementSince = 0

        markRuntimeEvent(
            "MoveDone:" .. owner
        )
    end
end

local function runMovementOperation(
    owner,
    timeout,
    callback
)
    if not acquireMovement(
        owner,
        timeout
    ) then

        return false,
            nil,
            "movement-busy:"
                .. tostring(
                    runtime.movementOwner
                )
    end

    local packed =
        table.pack(
            pcall(
                callback
            )
        )

    releaseMovement(
        owner
    )

    if not packed[1] then
        warn(
            "[Runtime] Movement operation failed:",
            owner,
            packed[2]
        )

        markRuntimeEvent(
            "MoveError:" .. owner
        )

        return false,
            nil,
            "movement-error"
    end

    return table.unpack(
        packed,
        2,
        packed.n
    )
end

BossWaypoint.StartAutoLearn(
    Config,
    BossData,
    HumanoidRegions,
    function()
        return scriptAlive
    end
)

--==================================================
-- CHARACTER HELPERS
--==================================================

local function getCharacter()
    return player.Character
end

local function getRoot()
    local character = getCharacter()
    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local character = getCharacter()
    if not character then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if humanoid and humanoid ~= currentHumanoid then
        currentHumanoid = humanoid
        originalWalkSpeed = humanoid.WalkSpeed
    end

    return humanoid
end

local function restoreCollision()
    for part, oldValue in pairs(originalCollision) do
        if part and part.Parent then
            part.CanCollide = oldValue
        end
    end

    table.clear(originalCollision)
end

local function getPlayerSlotData()
    local playerService =
        ReplicatedStorage:FindFirstChild(
            "Player_Service"
        )

    local data =
        playerService
        and playerService:FindFirstChild(
            "Data"
        )

    local playerData =
        data
        and data:FindFirstChild(
            player.Name
        )

    local slots =
        playerData
        and playerData:FindFirstChild(
            "slots"
        )

    return slots
        and slots:FindFirstChild(
            "Slot1"
        )
end

local function getWeaponInventory()
    local slot =
        getPlayerSlotData()

    local inventoryFolder =
        slot
        and slot:FindFirstChild(
            "Inventory"
        )

    return inventoryFolder
        and inventoryFolder:FindFirstChild(
            "Inventory"
        )
end

local function getWenValue()
    local slot =
        getPlayerSlotData()

    local wen =
        slot
        and slot:FindFirstChild(
            "Wen"
        )

    if wen
        and wen:IsA("ValueBase") then

        return wen
    end

    return nil
end

local function ownsWeapon(name)
    local inventory =
        getWeaponInventory()

    return inventory ~= nil
        and inventory:FindFirstChild(
            name
        ) ~= nil
end

local function getBestOwnedWeapon()
    if ownsWeapon("Thunder Katana") then
        return "Thunder Katana"
    end

    if ownsWeapon("Cutlass") then
        return "Cutlass"
    end

    if ownsWeapon("Fancy Katana") then
        return "Fancy Katana"
    end

    if ownsWeapon("Regular Katana") then
        return "Regular Katana"
    end

    return "Fist"
end

local function getDesiredWeapon()
    if weaponMode == "Auto Best" then
        return getBestOwnedWeapon()
    end

    if weaponMode == "Fist" then
        return "Fist"
    end

    if WeaponData.WEAPONS[weaponMode]
        and ownsWeapon(weaponMode) then

        return weaponMode
    end

    -- Manual selection is unavailable: keep the best owned weapon
    -- instead of dropping to a weaker weapon unnecessarily.
    return getBestOwnedWeapon()
end

local function weaponHasDirectCombat(
    weaponName
)
    local definition =
        WeaponData.WEAPONS[weaponName]

    return definition ~= nil
        and definition.directCombat == true
        and type(definition.comboTimings)
            == "table"
end

local function weaponHasCapturedCombat(
    weaponName
)
    return combatArgsByWeapon[
        weaponName
    ] ~= nil
end

local function getBestCombatWeapon()
    if ownsWeapon("Thunder Katana")
        and weaponHasDirectCombat(
            "Thunder Katana"
        ) then

        return "Thunder Katana"
    end

    if ownsWeapon("Cutlass")
        and weaponHasDirectCombat(
            "Cutlass"
        ) then

        return "Cutlass"
    end

    if ownsWeapon("Fancy Katana")
        and weaponHasDirectCombat(
            "Fancy Katana"
        ) then

        return "Fancy Katana"
    end

    if ownsWeapon("Regular Katana")
        and weaponHasDirectCombat(
            "Regular Katana"
        ) then

        return "Regular Katana"
    end

    return "Fist"
end

local function getDesiredCombatWeapon()
    if weaponMode == "Auto Best" then
        return getBestCombatWeapon()
    end

    return getDesiredWeapon()
end

local function getHotbarButton(
    slotNumber,
    timeout
)
    local deadline =
        os.clock() + (timeout or 2.00)

    repeat
        local playerGui =
            player:FindFirstChild(
                "PlayerGui"
            )

        local components =
            playerGui
            and playerGui:FindFirstChild(
                "ComponentsHolder"
            )

        local bottomHolder =
            components
            and components:FindFirstChild(
                "BottomHolder"
            )

        local toolbar =
            bottomHolder
            and bottomHolder:FindFirstChild(
                "Toolbar"
            )

        local skillHolder =
            toolbar
            and toolbar:FindFirstChild(
                "SkillHolder"
            )

        local button =
            skillHolder
            and skillHolder:FindFirstChild(
                tostring(slotNumber)
                    .. "_ToolPosition"
            )

        if button
            and button:IsA("GuiButton") then

            return button
        end

        task.wait(0.05)
    until os.clock() >= deadline

    return nil
end

local function getToolAccessories()
    local humanoids =
        workspace:FindFirstChild(
            "Humanoids"
        )

    local playerModel =
        humanoids
        and humanoids:FindFirstChild(
            player.Name
        )

    return playerModel
        and playerModel:FindFirstChild(
            "Tool_Accessories"
        )
end

local function isWeaponActuallyEquipped(
    weaponName
)
    if weaponName == "Fist" then
        return true
    end

    local toolAccessories =
        getToolAccessories()

    if not toolAccessories then
        return false
    end

    local value =
        toolAccessories:GetAttribute(
            "Value"
        )

    if type(value) == "string" then
        local normalized =
            string.lower(value)

        local wanted =
            string.lower(
                weaponName
            )

        if string.find(
            normalized,
            wanted,
            1,
            true
        ) then

            return true
        end
    end

    if weaponName == "Regular Katana"
        and toolAccessories:FindFirstChild(
            "Regular Katana"
        ) then

        return true
    end

    return false
end

local function waitForWeaponDrawn(
    weaponName,
    timeout
)
    local deadline =
        os.clock() + timeout

    repeat
        if isWeaponActuallyEquipped(
            weaponName
        ) then

            return true
        end

        task.wait(0.03)
    until os.clock() >= deadline

    return isWeaponActuallyEquipped(
        weaponName
    )
end

local function fireHotbarConnections(
    connections,
    x,
    y
)
    local fired = 0

    for _, connection in ipairs(
        connections
    ) do
        if type(connection.Fire)
            == "function"
            and connection.Enabled ~= false then

            local ok =
                pcall(function()
                    connection:Fire(
                        x,
                        y
                    )
                end)

            if ok then
                fired += 1
            end
        end
    end

    return fired
end

local function clickHotbarSlot(
    slotNumber,
    weaponName
)
    if type(getconnections)
        ~= "function" then

        warn(
            "[Auto Weapon] getconnections unavailable"
        )

        return false
    end

    local button =
        getHotbarButton(
            slotNumber,
            2.00
        )

    if not button then
        warn(
            "[Auto Weapon] Hotbar button not found:",
            slotNumber
        )

        return false
    end

    -- The real game button was verified to use MouseButton1Down and
    -- MouseButton1Up, not MouseButton1Click/Activated. Call those
    -- preexisting handlers directly, matching the successful v6 test.
    local downConnections =
        getconnections(
            button.MouseButton1Down
        )

    local upConnections =
        getconnections(
            button.MouseButton1Up
        )

    if #downConnections == 0
        or #upConnections == 0 then

        warn(
            "[Auto Weapon] Hotbar handlers not ready:",
            #downConnections,
            "/",
            #upConnections
        )

        return false
    end

    local center =
        button.AbsolutePosition
        + (
            button.AbsoluteSize
            / 2
        )

    local firedDown =
        fireHotbarConnections(
            downConnections,
            center.X,
            center.Y
        )

    task.wait(0.08)

    local firedUp =
        fireHotbarConnections(
            upConnections,
            center.X,
            center.Y
        )

    if firedDown <= 0
        or firedUp <= 0 then

        warn(
            "[Auto Weapon] Hotbar handler fire failed:",
            firedDown,
            "/",
            firedUp
        )

        return false
    end

    return waitForWeaponDrawn(
        weaponName,
        0.80
    )
end

local function drawWeaponFromHotbar(
    weaponName
)
    if isWeaponActuallyEquipped(
        weaponName
    ) then

        return true
    end

    for attempt = 1, 3 do
        if clickHotbarSlot(
            2,
            weaponName
        ) then

            print(
                "[Auto Weapon] Hotbar draw VERIFIED:",
                weaponName,
                "| attempt:",
                attempt
            )

            return true
        end

        task.wait(0.15)
    end

    warn(
        "[Auto Weapon] Hotbar draw NOT verified:",
        weaponName
    )

    return false
end

local function equipWeaponByName(
    weaponName,
    force
)
    local changed =
        currentWeaponName ~= weaponName

    if not force
        and not changed
        and (
            weaponName == "Fist"
            or isWeaponActuallyEquipped(
                weaponName
            )
        ) then

        return true, false
    end

    local ok, err =
        pcall(function()
            if weaponName == "Fist" then
                Event:FireServer(
                    "Item_Equip",
                    1
                )

                return
            end

            local definition =
                WeaponData.WEAPONS[weaponName]

            if not definition then
                error(
                    "Weapon definition not found: "
                    .. tostring(weaponName)
                )
            end

            -- Important: force=true means the game may have sheathed the
            -- weapon or rebuilt the hotbar even though currentWeaponName
            -- still matches. Re-send Toolbar_Equip so slot 2 is rebuilt
            -- before firing the real game click handlers.
            if changed or force then
                Event:FireServer(
                    "Toolbar_Equip",
                    "Two",
                    definition.toolbarIndex
                )

                task.wait(
                    Config.HOTBAR_REBUILD_DELAY
                )
            end

            if not drawWeaponFromHotbar(
                weaponName
            ) then

                -- One hard refresh fixes the old stale-hotbar case where
                -- the visible slot exists but its rebuilt handlers/state
                -- no longer draw the assigned weapon.
                print(
                    "[Auto Weapon] Draw failed; refreshing slot 2:",
                    weaponName
                )

                Event:FireServer(
                    "Toolbar_Equip",
                    "Two",
                    definition.toolbarIndex
                )

                task.wait(
                    Config.HOTBAR_REBUILD_DELAY
                )

                if not drawWeaponFromHotbar(
                    weaponName
                ) then

                    error(
                        "hotbar draw verification failed after slot refresh"
                    )
                end
            end
        end)

    if not ok then
        warn(
            "[Auto Weapon] Equip failed:",
            weaponName,
            err
        )

        return false, false
    end

    currentWeaponName =
        weaponName

    if changed or force then
        capturedArgs =
            combatArgsByWeapon[
                weaponName
            ]

        print(
            "[Auto Weapon] Equipped:",
            weaponName,
            "| Mode:",
            changed
                and "toolbar+real-click"
                or "force-refresh+real-click",
            "| Combat cache:",
            capturedArgs
                and "restored"
                or "not captured yet"
        )
    end

    return true, changed
end

local function ensureEquip(
    force
)
    return equipWeaponByName(
        getDesiredWeapon(),
        force == true
    )
end

local function acquireWeaponOperation(
    label,
    timeout
)
    local deadline =
        os.clock()
        + (timeout or 0)

    repeat
        if not weaponBusy then
            weaponBusy = true

            runtime.weaponOperation =
                label or "Weapon"

            runtime.weaponSince =
                os.clock()

            markRuntimeEvent(
                "Weapon:"
                    .. runtime.weaponOperation
            )

            return true
        end

        if (timeout or 0) <= 0 then
            return false
        end

        task.wait(0.03)
    until not scriptAlive
        or os.clock() >= deadline

    return false
end

local function releaseWeaponOperation()
    local finished =
        runtime.weaponOperation

    weaponBusy = false

    runtime.weaponOperation =
        "Idle"

    runtime.weaponSince = 0

    markRuntimeEvent(
        "WeaponDone:"
            .. tostring(
                finished
            )
    )
end

local function runWeaponOperation(
    label,
    timeout,
    callback
)
    if not acquireWeaponOperation(
        label,
        timeout
    ) then

        return false,
            "weapon-busy:"
                .. tostring(
                    runtime.weaponOperation
                )
    end

    local packed =
        table.pack(
            pcall(
                callback
            )
        )

    releaseWeaponOperation()

    if not packed[1] then
        warn(
            "[Auto Weapon] Operation error:",
            label,
            packed[2]
        )

        markRuntimeEvent(
            "WeaponError:"
                .. tostring(label)
        )

        return false,
            packed[2]
    end

    return table.unpack(
        packed,
        2,
        packed.n
    )
end

local function ensureEquipSerialized(
    force,
    label
)
    return runWeaponOperation(
        label or "Equip",
        Config.WEAPON_SYNC_WAIT_TIMEOUT,
        function()
            return ensureEquip(
                force
            )
        end
    )
end

--==================================================
-- NPC HELPERS
--==================================================

local function getNpcData(container)
    if not container then
        return nil
    end

    local model = nil

    if container:IsA("Model") then
        model = container
    else
        local sameName = container:FindFirstChild(container.Name)

        if sameName and sameName:IsA("Model") then
            model = sameName
        else
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model")
                    and child:FindFirstChildOfClass("Humanoid")
                    and child:FindFirstChild("HumanoidRootPart") then

                    model = child
                    break
                end
            end
        end
    end

    if not model then
        return nil
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")

    if not humanoid
        or not root
        or humanoid.Health <= 0 then

        return nil
    end

    return {
        container = container,
        model = model,
        humanoid = humanoid,
        root = root,
        name = container.Name
    }
end

local function targetAlive()
    return target
        and target.model
        and target.model.Parent
        and target.humanoid
        and target.humanoid.Parent
        and target.humanoid.Health > 0
        and target.root
        and target.root.Parent
end

local function targetDown()
    if not targetAlive() then
        return true
    end

    local humanoid = target.humanoid

    if humanoid.PlatformStand then
        return true
    end

    local state = humanoid:GetState()

    if state == Enum.HumanoidStateType.FallingDown
        or state == Enum.HumanoidStateType.Ragdoll
        or state == Enum.HumanoidStateType.Physics
        or state == Enum.HumanoidStateType.GettingUp
        or state == Enum.HumanoidStateType.Dead then

        return true
    end

    local attributes = {
        "IsDown",
        "Down",
        "Knocked",
        "KnockedDown"
    }

    for _, attributeName in ipairs(attributes) do
        if target.model:GetAttribute(attributeName) == true then
            return true
        end
    end

    local downValue =
        target.model:FindFirstChild("IsDown", true)
        or target.model:FindFirstChild("KnockedDown", true)

    if downValue
        and downValue:IsA("BoolValue")
        and downValue.Value then

        return true
    end

    return false
end

local function clearTarget()
    if targetDiedConnection then
        targetDiedConnection:Disconnect()
        targetDiedConnection = nil
    end

    target = nil
    targetMode = nil
    lockFrames = 0
    combatNoDamageCycles = 0
end

--==================================================
-- TARGET SEARCH
--==================================================

local function isIgnoredNearbyName(name)
    local lowered = string.lower(name)

    if string.find(lowered, "civilian", 1, true) then
        return true
    end

    return false
end

local function findNearestNearbyTarget()
    local root = getRoot()

    if not root or not nearbyFarmOrigin then
        return nil
    end

    local nearest = nil
    local nearestDistance = math.huge

    for _, region in ipairs(HumanoidRegions:GetChildren()) do
        local activeNpcs = region:FindFirstChild("ActiveNpcs")

        if activeNpcs then
            for _, container in ipairs(activeNpcs:GetChildren()) do
                if not isIgnoredNearbyName(container.Name) then
                    local data = getNpcData(container)

                    if data then
                        local originDistance =
                            (data.root.Position - nearbyFarmOrigin).Magnitude

                        if originDistance <= nearbyFarmRange then
                            local currentDistance =
                                (data.root.Position - root.Position).Magnitude

                            if currentDistance < nearestDistance then
                                nearestDistance = currentDistance
                                nearest = data
                            end
                        end
                    end
                end
            end
        end
    end

    return nearest
end

local function findNearestQuestTarget()
    local quest = QuestData.QUESTS[selectedQuestName]

    if not quest then
        return nil
    end

    local region = HumanoidRegions:FindFirstChild(quest.targetRegion)

    if not region then
        return nil
    end

    local activeNpcs = region:FindFirstChild("ActiveNpcs")

    if not activeNpcs then
        return nil
    end

    local root = getRoot()

    if not root then
        return nil
    end

    local nearest = nil
    local nearestDistance = math.huge

    for _, container in ipairs(activeNpcs:GetChildren()) do
        if container.Name == quest.targetName then
            local data = getNpcData(container)

            if data then
                local distance =
                    (data.root.Position - root.Position).Magnitude

                if distance < nearestDistance then
                    nearestDistance = distance
                    nearest = data
                end
            end
        end
    end

    return nearest
end

local function findSelectedBossTarget()
    local boss =
        BossData.BOSSES[selectedBossName]

    if not boss then
        return nil
    end

    local region =
        HumanoidRegions:FindFirstChild(
            boss.region
        )

    local activeNpcs =
        region
        and region:FindFirstChild(
            "ActiveNpcs"
        )

    if not activeNpcs then
        return nil
    end

    for _, container in ipairs(
        activeNpcs:GetChildren()
    ) do
        if container.Name
            == boss.targetName then

            local data =
                getNpcData(
                    container
                )

            if data then
                BossWaypoint.Remember(
                    Config,
                    boss,
                    data.root.CFrame
                )

                return data
            end
        end
    end

    return nil
end

local function activeQuestAlreadyTargetsBoss()
    if not questFarmEnabled
        or questNeedsAccept
        or questBusy then

        return false
    end

    local quest =
        QuestData.QUESTS[selectedQuestName]

    local boss =
        BossData.BOSSES[selectedBossName]

    return quest ~= nil
        and boss ~= nil
        and quest.targetRegion
            == boss.region
        and quest.targetName
            == boss.targetName
end

--==================================================
-- QUEST
--==================================================

-- Temporary quest-state probe.
-- First press: save a baseline while NO quest is active.
-- Accept the quest manually and wait until it appears.
-- Second press: print only player/UI state that changed.
local questProbeBaseline = nil

local function questProbeVisible(object)
    local current = object

    while current do
        if current:IsA("GuiObject")
            and current.Visible == false then

            return false
        end

        if current:IsA("ScreenGui")
            and current.Enabled == false then

            return false
        end

        current = current.Parent

        if current == player then
            break
        end
    end

    return true
end

local function collectQuestProbeState()
    local state = {}

    local objects = {
        player
    }

    for _, object in ipairs(
        player:GetDescendants()
    ) do
        table.insert(objects, object)
    end

    for _, object in ipairs(objects) do
        local path = object:GetFullName()

        if object:IsA("TextLabel")
            or object:IsA("TextButton")
            or object:IsA("TextBox") then

            state[path .. " [Text]"] =
                tostring(object.Text)
                .. " | visible="
                .. tostring(
                    questProbeVisible(object)
                )
        end

        if object:IsA("ValueBase") then
            local ok, value =
                pcall(function()
                    return object.Value
                end)

            if ok then
                state[path .. " [Value]"] =
                    typeof(value)
                    .. ":"
                    .. tostring(value)
            end
        end

        local ok, attributes =
            pcall(function()
                return object:GetAttributes()
            end)

        if ok and attributes then
            for name, value in pairs(attributes) do
                state[
                    path
                    .. " [Attribute:"
                    .. tostring(name)
                    .. "]"
                ] =
                    typeof(value)
                    .. ":"
                    .. tostring(value)
            end
        end
    end

    return state
end

local function runQuestStateProbe()
    local current =
        collectQuestProbeState()

    if not questProbeBaseline then
        questProbeBaseline = current

        print(
            "[Quest Probe] BASELINE SAVED"
        )

        print(
            "[Quest Probe] Now accept the quest MANUALLY, wait until it is visible, then press the probe button again."
        )

        return
    end

    local changes = {}

    for key, value in pairs(current) do
        local oldValue =
            questProbeBaseline[key]

        if oldValue == nil then
            table.insert(
                changes,
                {
                    key = key,
                    kind = "NEW",
                    old = nil,
                    new = value
                }
            )
        elseif oldValue ~= value then
            table.insert(
                changes,
                {
                    key = key,
                    kind = "CHANGED",
                    old = oldValue,
                    new = value
                }
            )
        end
    end

    for key, oldValue in pairs(
        questProbeBaseline
    ) do
        if current[key] == nil then
            table.insert(
                changes,
                {
                    key = key,
                    kind = "REMOVED",
                    old = oldValue,
                    new = nil
                }
            )
        end
    end

    table.sort(
        changes,
        function(a, b)
            local aLower =
                string.lower(
                    a.key
                    .. " "
                    .. tostring(a.new or "")
                )

            local bLower =
                string.lower(
                    b.key
                    .. " "
                    .. tostring(b.new or "")
                )

            local function score(text)
                local value = 0

                if string.find(text, "quest", 1, true) then
                    value += 10
                end

                if string.find(text, "bandit", 1, true) then
                    value += 10
                end

                if string.find(text, "krue", 1, true) then
                    value += 5
                end

                if string.find(text, "defeat", 1, true) then
                    value += 5
                end

                return value
            end

            local aScore = score(aLower)
            local bScore = score(bLower)

            if aScore ~= bScore then
                return aScore > bScore
            end

            return a.key < b.key
        end
    )

    print("")
    print(
        "========== QUEST STATE DIFF =========="
    )

    print(
        "[Quest Probe] Changes:",
        #changes
    )

    for index, data in ipairs(changes) do
        if index > 120 then
            print(
                "[Quest Probe] More changes omitted:",
                #changes - 120
            )
            break
        end

        print("")
        print(
            "#" .. index,
            data.kind,
            data.key
        )

        if data.old ~= nil then
            print(
                "  OLD:",
                data.old
            )
        end

        if data.new ~= nil then
            print(
                "  NEW:",
                data.new
            )
        end
    end

    print(
        "========== END QUEST STATE DIFF =========="
    )

    questProbeBaseline = nil
end

local function getSelectedQuestPanel()
    local quest = QuestData.QUESTS[selectedQuestName]

    if not quest or not quest.uiPanelName then
        return nil
    end

    local playerGui =
        player:FindFirstChild("PlayerGui")

    local components =
        playerGui
        and playerGui:FindFirstChild(
            "ComponentsHolder"
        )

    local leftCenter =
        components
        and components:FindFirstChild(
            "LeftCenterFramesHolder"
        )

    local questsFrame =
        leftCenter
        and leftCenter:FindFirstChild(
            "zQuestsFrame"
        )

    local panel =
        questsFrame
        and questsFrame:FindFirstChild(
            "Panel"
        )

    if not panel then
        return nil
    end

    return panel:FindFirstChild(
        quest.uiPanelName
    )
end

local function isSelectedQuestActive()
    local questPanel =
        getSelectedQuestPanel()

    if not questPanel then
        return false
    end

    if questPanel:IsA("GuiObject")
        and not questPanel.Visible then

        return false
    end

    for _, object in ipairs(
        questPanel:GetDescendants()
    ) do
        if object:IsA("TextLabel")
            or object:IsA("TextButton") then

            local text =
                string.lower(
                    tostring(object.Text)
                )

            local wanted =
                string.lower(
                    QuestData.QUESTS[selectedQuestName].uiPanelName
                )

            if string.find(
                text,
                wanted,
                1,
                true
            ) and questProbeVisible(object) then

                return true
            end
        end
    end

    return true
end

local function waitForSelectedQuestState(
    expectedActive,
    timeout
)
    local deadline =
        os.clock() + timeout

    repeat
        if isSelectedQuestActive()
            == expectedActive then

            return true
        end

        task.wait(
            Config.QUEST_UI_POLL_DELAY
        )
    until os.clock() >= deadline
        or not questFarmEnabled

    return isSelectedQuestActive()
        == expectedActive
end

local function resetQuestProgressTracking()
    questKillCount = 0
    questUiWasActive = false
    questProgressSeen = false
    questLastProgress = -1
    questLastTargetDeathAt = 0
    questProgressHoldUntil = 0
end

local function getSelectedQuestProgress()
    local quest =
        QuestData.QUESTS[selectedQuestName]

    local questPanel =
        getSelectedQuestPanel()

    if not quest
        or not questPanel then

        return nil, nil, nil
    end

    local bestCurrent = nil
    local bestTotal = nil
    local bestText = nil

    local objects = {
        questPanel
    }

    for _, object in ipairs(
        questPanel:GetDescendants()
    ) do
        table.insert(
            objects,
            object
        )
    end

    for _, object in ipairs(objects) do
        if (
            object:IsA("TextLabel")
            or object:IsA("TextButton")
            or object:IsA("TextBox")
        ) and questProbeVisible(object) then

            local text =
                tostring(object.Text)

            for currentText, totalText in string.gmatch(
                text,
                "(%d+)%s*/%s*(%d+)"
            ) do
                local current =
                    tonumber(currentText)

                local total =
                    tonumber(totalText)

                if current
                    and total
                    and total == quest.requiredKills
                    and current <= total
                    and (
                        bestCurrent == nil
                        or current > bestCurrent
                    ) then

                    bestCurrent = current
                    bestTotal = total
                    bestText = text
                end
            end
        end
    end

    return bestCurrent, bestTotal, bestText
end

local function markSelectedQuestComplete(
    source
)
    if questNeedsAccept then
        return
    end

    local quest =
        QuestData.QUESTS[selectedQuestName]

    if not quest then
        return
    end

    questKillCount =
        quest.requiredKills

    questLastProgress =
        quest.requiredKills

    questNeedsAccept = true
    questAcceptReadyAt =
        os.clock()
        + Config.QUEST_COMPLETE_DELAY

    clearTarget()

    print(
        "[Quest Farm] Quest complete VERIFIED by",
        source,
        "|",
        questKillCount,
        "/",
        quest.requiredKills
    )
end

local function syncSelectedQuestProgress()
    if not questFarmEnabled
        or questBusy
        or questNeedsAccept then

        return
    end

    local quest =
        QuestData.QUESTS[selectedQuestName]

    if not quest then
        return
    end

    local active =
        isSelectedQuestActive()

    if active then
        questUiWasActive = true

        local current, total, text =
            getSelectedQuestProgress()

        if current
            and total then

            questProgressSeen = true
            questKillCount = current

            if current
                ~= questLastProgress then

                questLastProgress =
                    current

                print(
                    "[Quest Farm] Server progress:",
                    current,
                    "/",
                    total,
                    "|",
                    text
                )
            end

            if current >= total
                and total
                    == quest.requiredKills then

                markSelectedQuestComplete(
                    "quest UI progress"
                )
            end
        end

        return
    end

    -- Some quests remove their panel immediately on the final kill,
    -- before the client gets a chance to observe 3/3 or 1/1.
    -- Accept that as completion only when the last verified progress
    -- was one kill away (or this is a one-kill quest), and the panel
    -- clears right after a quest target dies.
    local minimumBeforeFinal =
        math.max(
            0,
            quest.requiredKills - 1
        )

    if questUiWasActive
        and questProgressSeen
        and questLastProgress
            >= minimumBeforeFinal
        and questLastTargetDeathAt > 0
        and (
            os.clock()
            - questLastTargetDeathAt
        ) <= Config.QUEST_PANEL_CLEAR_DEATH_WINDOW then

        markSelectedQuestComplete(
            "quest panel cleared after final target"
        )
    end
end

-- Persistent quest-NPC waypoint cache.
-- StreamingEnabled can remove distant StationaryNpcs from the client.
-- Once an NPC has been seen, remember its world CFrame so future
-- sessions can jump into streaming range before resolving the live NPC.
local questNpcWaypoints = {}

local function getQuestWaypointKey(quest)
    return tostring(quest.npcRegion)
        .. "|"
        .. tostring(quest.npcName)
end

local function loadQuestWaypointCache()
    if type(isfile) ~= "function"
        or type(readfile) ~= "function" then

        return
    end

    local ok, decoded =
        pcall(function()
            if not isfile(
                Config.QUEST_WAYPOINT_FILE
            ) then

                return nil
            end

            local HttpService =
                game:GetService(
                    "HttpService"
                )

            return HttpService:JSONDecode(
                readfile(
                    Config.QUEST_WAYPOINT_FILE
                )
            )
        end)

    if ok and type(decoded) == "table" then
        questNpcWaypoints = decoded
    end
end

local function saveQuestWaypointCache()
    if type(writefile) ~= "function" then
        return
    end

    if type(makefolder) == "function" then
        pcall(
            makefolder,
            Config.QUEST_WAYPOINT_FOLDER
        )
    end

    pcall(function()
        local HttpService =
            game:GetService(
                "HttpService"
            )

        writefile(
            Config.QUEST_WAYPOINT_FILE,
            HttpService:JSONEncode(
                questNpcWaypoints
            )
        )
    end)
end

local function cframeToArray(cf)
    return {
        cf:GetComponents()
    }
end

local function arrayToCFrame(values)
    if type(values) ~= "table"
        or #values < 12 then

        return nil
    end

    local ok, cf =
        pcall(function()
            return CFrame.new(
                table.unpack(
                    values,
                    1,
                    12
                )
            )
        end)

    return ok
        and cf
        or nil
end

local function rememberQuestNpc(
    quest,
    npcRoot
)
    if not npcRoot
        or not npcRoot.Parent then

        return
    end

    local key =
        getQuestWaypointKey(quest)

    if questNpcWaypoints[key] then
        return
    end

    questNpcWaypoints[key] =
        cframeToArray(
            npcRoot.CFrame
        )

    saveQuestWaypointCache()

    print(
        "[Quest Waypoint] Learned:",
        key,
        "|",
        tostring(
            npcRoot.Position
        )
    )
end

local function getSavedQuestNpcCFrame(
    quest
)
    -- Optional repo-side seed. Three numbers are enough to jump into
    -- streaming range; once the live NPC appears we reposition exactly.
    if type(quest.npcWaypoint) == "table"
        and #quest.npcWaypoint >= 3 then

        return CFrame.new(
            quest.npcWaypoint[1],
            quest.npcWaypoint[2],
            quest.npcWaypoint[3]
        )
    end

    return arrayToCFrame(
        questNpcWaypoints[
            getQuestWaypointKey(
                quest
            )
        ]
    )
end

loadQuestWaypointCache()

local function getQuestNpcRoot(quest)
    local region =
        StationaryRegions:FindFirstChild(
            quest.npcRegion
        )

    if not region then
        return nil
    end

    local stationaryNpcs =
        region:FindFirstChild(
            "StationaryNpcs"
        )

    if not stationaryNpcs then
        return nil
    end

    local npc =
        stationaryNpcs:FindFirstChild(
            quest.npcName
        )

    if not npc then
        return nil
    end

    local npcRoot =
        npc:FindFirstChild(
            "HumanoidRootPart"
        )
        or npc.PrimaryPart

    if npcRoot then
        rememberQuestNpc(
            quest,
            npcRoot
        )
    end

    return npcRoot
end

-- Learn quest NPC positions whenever Roblox streams them in, even if
-- Quest Farm is currently off. This makes the saved waypoint available
-- for future joins/checkpoints without requiring a special save button.
task.spawn(function()
    while scriptAlive do
        for _, questName in ipairs(
            QuestData.ORDER
        ) do
            local quest =
                QuestData.QUESTS[
                    questName
                ]

            if quest then
                getQuestNpcRoot(
                    quest
                )
            end
        end

        task.wait(2.00)
    end
end)

local function warpToQuestNpcUnlocked(
    quest,
    streamTimeout
)
    local characterVersion =
        runtime.characterVersion

    local root =
        getRoot()

    if not root then
        return false, nil, "player-root"
    end

    local npcRoot =
        getQuestNpcRoot(
            quest
        )

    local npcCFrame =
        npcRoot
        and npcRoot.CFrame
        or getSavedQuestNpcCFrame(
            quest
        )

    if not npcCFrame then
        return false, nil, "no-waypoint"
    end

    root.AssemblyLinearVelocity =
        Vector3.zero

    root.CFrame =
        npcCFrame
        * CFrame.new(
            0,
            quest.npcYOffset or 5,
            quest.npcForwardOffset or -1.5
        )

    if not npcRoot
        and (streamTimeout or 0) > 0 then

        print(
            "[Quest Farm] Waypoint warp; waiting for NPC stream:",
            quest.npcName
        )

        local deadline =
            os.clock()
            + streamTimeout

        repeat
            task.wait(0.10)

            npcRoot =
                getQuestNpcRoot(
                    quest
                )
        until npcRoot
            or os.clock() >= deadline
            or not questFarmEnabled
            or runtime.characterVersion
                ~= characterVersion

        if runtime.characterVersion
            ~= characterVersion then

            return false,
                nil,
                "character-changed"
        end

        if npcRoot then
            root.AssemblyLinearVelocity =
                Vector3.zero

            root.CFrame =
                npcRoot.CFrame
                * CFrame.new(
                    0,
                    quest.npcYOffset or 5,
                    quest.npcForwardOffset or -1.5
                )
        end
    end

    return true, npcRoot, npcRoot
        and "live"
        or "saved"
end

local function warpToQuestNpc(
    quest,
    streamTimeout
)
    return runMovementOperation(
        "QuestNPC",
        Config.MOVEMENT_LOCK_WAIT_TIMEOUT,
        function()
            return warpToQuestNpcUnlocked(
                quest,
                streamTimeout
            )
        end
    )
end

local function acceptSelectedQuest()
    if questBusy
        or weaponBusy then

        return false
    end

    local acceptQuestName =
        selectedQuestName

    local acceptVersion =
        questSelectionVersion

    local quest =
        QuestData.QUESTS[acceptQuestName]

    if not quest then
        warn("[Quest Farm] Quest definition not found")
        return false
    end

    local function selectionChanged()
        return acceptVersion
                ~= questSelectionVersion
            or acceptQuestName
                ~= selectedQuestName
    end

    local function abortForSelectionChange()
        if not selectionChanged() then
            return false
        end

        questBusy = false
        questNeedsAccept = true

        print(
            "[Quest Farm] Quest selection changed; restarting accept for:",
            selectedQuestName
        )

        return true
    end

    questBusy = true
    clearTarget()

    -- Always jump toward the selected quest NPC first.
    -- If the live NPC is not streamed, use the persistent waypoint
    -- to enter streaming range, then resolve the real NPC root.
    warpToQuestNpc(
        quest,
        Config.QUEST_STREAM_WAIT_TIMEOUT
    )

    local now = os.clock()

    if questAcceptReadyAt > now then
        print(
            "[Quest Farm] Waiting at NPC for quest cooldown:",
            string.format(
                "%.1fs",
                questAcceptReadyAt - now
            ),
            "|",
            acceptQuestName
        )

        while questFarmEnabled
            and not selectionChanged()
            and os.clock()
                < questAcceptReadyAt do

            task.wait(0.10)
        end
    end

    if abortForSelectionChange() then
        return false
    end

    if not questFarmEnabled then
        questBusy = false
        return false
    end

    if questKillCount >= quest.requiredKills then
        print(
            "[Quest Farm] Waiting for completed quest UI to clear"
        )

        waitForSelectedQuestState(
            false,
            Config.QUEST_OLD_UI_CLEAR_TIMEOUT
        )

        if abortForSelectionChange() then
            return false
        end
    elseif isSelectedQuestActive() then
        resetQuestProgressTracking()
        questUiWasActive = true
        questNeedsAccept = false
        questAcceptReadyAt = 0
        questBusy = false

        task.defer(
            syncSelectedQuestProgress
        )

        markRuntimeEvent(
            "QuestActive:"
                .. tostring(
                    acceptQuestName
                )
        )

        print(
            "[Quest Farm] Quest already active:",
            acceptQuestName
        )

        return true
    end

    local attempt = 0

    while questFarmEnabled
        and not selectionChanged()
        and not isSelectedQuestActive() do

        attempt += 1

        local warped, npcRoot, warpMode =
            warpToQuestNpc(
                quest,
                Config.QUEST_STREAM_WAIT_TIMEOUT
            )

        if not warped
            or not npcRoot then

            if warpMode == "no-waypoint" then
                warn(
                    "[Quest Farm] NPC is not streamed and no saved waypoint exists yet:",
                    quest.npcName,
                    "| visit this NPC once so its position can be learned"
                )
            else
                warn(
                    "[Quest Farm] Player/NPC root not found during accept"
                )
            end

            task.wait(
                Config.QUEST_ACCEPT_RETRY_DELAY
            )

            continue
        end

        task.wait(
            attempt == 1
                and Config.QUEST_ARRIVE_DELAY
                or 0.05
        )

        -- The dropdown may be changed while we are standing at the NPC.
        -- Never send the old quest remote after a selection change.
        if abortForSelectionChange() then
            return false
        end

        pcall(function()
            Event:FireServer(
                "AddQuest",
                quest.questText
            )
        end)

        task.wait(
            Config.QUEST_AFTER_ACCEPT_DELAY
        )

        if abortForSelectionChange() then
            return false
        end

        pcall(function()
            Event:FireServer(
                "NpcTalking",
                "Ended"
            )
        end)

        print(
            "[Quest Farm] AddQuest attempt:",
            attempt,
            "|",
            acceptQuestName,
            "| verifying UI..."
        )

        if waitForSelectedQuestState(
            true,
            Config.QUEST_VERIFY_TIMEOUT
        ) then
            break
        end

        if abortForSelectionChange() then
            return false
        end

        print(
            "[Quest Farm] Quest UI not active; retry in 1s"
        )

        task.wait(
            Config.QUEST_ACCEPT_RETRY_DELAY
        )
    end

    if abortForSelectionChange() then
        return false
    end

    if questFarmEnabled
        and isSelectedQuestActive() then

        resetQuestProgressTracking()
        questUiWasActive = true
        questNeedsAccept = false
        questAcceptReadyAt = 0
        questBusy = false

        task.defer(
            syncSelectedQuestProgress
        )

        markRuntimeEvent(
            "QuestVerified:"
                .. tostring(
                    acceptQuestName
                )
        )

        print(
            "[Quest Farm] VERIFIED active:",
            acceptQuestName,
            "| attempt:",
            attempt
        )

        return true
    end

    questBusy = false
    return false
end

local function onQuestTargetDied()
    if not questFarmEnabled
        or targetDeathCounted then

        return
    end

    local quest =
        QuestData.QUESTS[selectedQuestName]

    if not quest then
        return
    end

    -- Do not increment questKillCount locally.
    -- The server-updated quest UI is the source of truth.
    targetDeathCounted = true
    questLastTargetDeathAt =
        os.clock()

    questProgressHoldUntil =
        os.clock()
        + Config.QUEST_PROGRESS_DEATH_HOLD

    print(
        "[Quest Farm] Target defeated; waiting for server quest progress"
    )

    task.spawn(function()
        task.wait(0.10)
        syncSelectedQuestProgress()

        if not questNeedsAccept then
            task.wait(0.20)
            syncSelectedQuestProgress()
        end
    end)
end

local function getPromptPosition(
    prompt
)
    local parent =
        prompt and prompt.Parent

    if parent
        and parent:IsA("BasePart") then

        return parent.Position
    end

    local part =
        prompt
        and prompt:FindFirstAncestorWhichIsA(
            "BasePart"
        )

    if part then
        return part.Position
    end

    local model =
        prompt
        and prompt:FindFirstAncestorOfClass(
            "Model"
        )

    if model then
        local modelPart =
            model.PrimaryPart
            or model:FindFirstChildWhichIsA(
                "BasePart",
                true
            )

        if modelPart then
            return modelPart.Position
        end
    end

    return nil
end

local function moveNearPrompt(
    prompt
)
    local root = getRoot()
    local position =
        getPromptPosition(
            prompt
        )

    if not root
        or not position then

        return false
    end

    local maxDistance =
        tonumber(
            prompt.MaxActivationDistance
        )
        or 10

    -- The chest/drop prompts are strict about distance.
    -- Always move very close instead of only moving when we are
    -- barely outside MaxActivationDistance.
    local offsetY =
        math.clamp(
            maxDistance * 0.20,
            0.75,
            1.50
        )

    root.AssemblyLinearVelocity =
        Vector3.zero

    root.AssemblyAngularVelocity =
        Vector3.zero

    root.CFrame =
        CFrame.new(
            position
                + Vector3.new(
                    0,
                    offsetY,
                    0
                ),
            position
        )

    task.wait(0.18)

    local actualDistance =
        (
            root.Position
            - position
        ).Magnitude

    return actualDistance
        <= math.max(
            1.75,
            maxDistance * 0.50
        )
end

local function useProximityPrompt(
    prompt
)
    if not prompt
        or not prompt:IsA(
            "ProximityPrompt"
        )
        or not prompt.Enabled then

        return false
    end

    for attempt = 1, 3 do
        if not prompt.Parent
            or not prompt.Enabled then

            return true
        end

        if not moveNearPrompt(
            prompt
        ) then

            task.wait(0.10)
            continue
        end

        local ok =
            pcall(function()
                prompt:InputHoldBegin()

                task.wait(
                    math.max(
                        0.05,
                        prompt.HoldDuration
                            + 0.05
                    )
                )

                prompt:InputHoldEnd()
            end)

        if not ok then
            task.wait(0.15)
            continue
        end

        -- ChestPrompt becomes disabled after opening.
        -- LootDropPrompt is removed when the item is claimed.
        local verifyDeadline =
            os.clock() + 0.80

        repeat
            if not prompt.Parent
                or not prompt.Enabled then

                return true
            end

            task.wait(0.05)
        until os.clock()
            >= verifyDeadline

        print(
            "[Boss Loot] Prompt still active; retry:",
            attempt
        )
    end

    return false
end

local function findBossChestPrompt(
    origin
)
    local chests =
        workspace:FindFirstChild(
            "Chests"
        )

    if not chests then
        return nil
    end

    local referencePosition =
        origin

    if not referencePosition then
        local root = getRoot()

        referencePosition =
            root and root.Position
    end

    local nearest = nil
    local nearestDistance =
        math.huge

    for _, object in ipairs(
        chests:GetDescendants()
    ) do
        if object:IsA(
            "ProximityPrompt"
        )
            and object.Name
                == "ChestPrompt"
            and object.Enabled then

            local chest =
                object:FindFirstAncestorOfClass(
                    "Model"
                )

            local position =
                getPromptPosition(
                    object
                )

            if position then
                local distance =
                    referencePosition
                    and (
                        position
                        - referencePosition
                    ).Magnitude
                    or math.huge

                local isOpen =
                    chest
                    and chest:GetAttribute(
                        "IsOpen"
                    )

                local state =
                    chest
                    and chest:GetAttribute(
                        "ChestState"
                    )

                if distance
                    <= Config.BOSS_LOOT_CHEST_RADIUS
                    and isOpen ~= true
                    and tostring(state)
                        ~= "Opened"
                    and distance
                        < nearestDistance then

                    nearestDistance =
                        distance

                    nearest =
                        object
                end
            end
        end
    end

    return nearest,
        nearestDistance
end

local function getLootDropContainer(
    object
)
    local current = object

    while current
        and current ~= workspace do

        if current.Name == "LootDrop"
            and current.Parent
            and current.Parent.Name
                == "LootDrops" then

            return current
        end

        current = current.Parent
    end

    return nil
end

local function findOwnedLootPrompts()
    local lootDrops =
        workspace:FindFirstChild(
            "LootDrops"
        )

    local result = {}

    if not lootDrops then
        return result
    end

    local seen = {}

    for _, object in ipairs(
        lootDrops:GetDescendants()
    ) do
        if object:IsA(
            "ProximityPrompt"
        )
            and object.Name
                == "LootDropPrompt"
            and object.Enabled then

            local container =
                getLootDropContainer(
                    object
                )

            if container
                and not seen[
                    container
                ] then

                seen[container] = true

                local owner =
                    container:GetAttribute(
                        "DropOwnerUserId"
                    )

                if owner
                    == player.UserId then

                    table.insert(
                        result,
                        {
                            container =
                                container,
                            prompt =
                                object,
                            itemId =
                                container:GetAttribute(
                                    "DropItemId"
                                )
                        }
                    )
                end
            end
        end
    end

    return result
end

local function claimOwnedLootPass()
    local drops =
        findOwnedLootPrompts()

    local claimed = 0

    for _, entry in ipairs(
        drops
    ) do
        if not bossFarmEnabled
            or not bossAutoLootEnabled then

            break
        end

        print(
            "[Boss Loot] Claiming:",
            tostring(
                entry.itemId
            )
        )

        if useProximityPrompt(
            entry.prompt
        ) then

            claimed += 1
        end

        task.wait(0.15)
    end

    return claimed,
        #drops
end

local function runBossLootSequence(
    origin,
    expectedCharacterVersion
)
    print(
        "[Boss Loot] Waiting for chest/drop:",
        selectedBossName
    )

    local chestDeadline =
        os.clock()
        + Config.BOSS_LOOT_CHEST_WAIT

    local chestOpened = false
    local claimedAny = false
    local lastClaimAt = 0

    while scriptAlive
        and bossFarmEnabled
        and bossAutoLootEnabled
        and runtime.characterVersion
            == expectedCharacterVersion
        and os.clock()
            < chestDeadline do

        local claimed,
            found =
            claimOwnedLootPass()

        if found > 0 then
            claimedAny = true
            lastClaimAt =
                os.clock()

            if claimed > 0 then
                task.wait(0.35)
            end
        end

        local chestPrompt =
            findBossChestPrompt(
                origin
            )

        if chestPrompt then
            print(
                "[Boss Loot] Opening boss chest"
            )

            chestOpened =
                useProximityPrompt(
                    chestPrompt
                )

            print(
                "[Boss Loot] Chest opened:",
                chestOpened
            )

            if chestOpened then
                break
            end
        end

        task.wait(0.10)
    end

    local dropDeadline =
        os.clock()
        + Config.BOSS_LOOT_DROP_WAIT

    while scriptAlive
        and bossFarmEnabled
        and bossAutoLootEnabled
        and runtime.characterVersion
            == expectedCharacterVersion
        and os.clock()
            < dropDeadline do

        local claimed,
            found =
            claimOwnedLootPass()

        if found > 0 then
            claimedAny = true
            lastClaimAt =
                os.clock()

            if claimed > 0 then
                task.wait(0.35)
            end
        elseif claimedAny
            and os.clock()
                - lastClaimAt
                >= Config.BOSS_LOOT_SETTLE_DELAY then

            break
        end

        task.wait(0.10)
    end

    print(
        "[Boss Loot] Finished | chest:",
        chestOpened,
        "| claimedAny:",
        claimedAny
    )
end

local function endBossOverride(
    reason
)
    bossLootBusy = false
    bossOverrideActive = false
    bossLastPosition = nil
    bossResumeCFrame = nil
    bossResumeCharacterVersion = 0

    clearTarget()

    markRuntimeEvent(
        "BossEnd:"
            .. tostring(
                reason or "target unavailable"
            )
    )

    print(
        "[Boss Farm] Override finished:",
        selectedBossName,
        "|",
        reason or "target unavailable"
    )
end

local function finishBossOverride(
    reason
)
    if not bossOverrideActive
        and not bossLootBusy then

        return
    end

    if bossLootBusy then
        return
    end

    local shouldLoot =
        bossAutoLootEnabled
        and bossFarmEnabled
        and (
            reason == "boss defeated"
            or reason
                == "boss target ended"
            or reason
                == "boss no longer available"
        )

    if not shouldLoot then
        endBossOverride(
            reason
        )

        return
    end

    bossLootBusy = true

    local lootOrigin =
        bossLastPosition

    local lootCharacterVersion =
        runtime.characterVersion

    local resumeCFrame =
        bossResumeCFrame

    local resumeCharacterVersion =
        bossResumeCharacterVersion

    clearTarget()

    task.spawn(function()
        local moved =
            runMovementOperation(
                "BossLoot",
                Config.MOVEMENT_LOCK_WAIT_TIMEOUT,
                function()
                    runBossLootSequence(
                        lootOrigin,
                        lootCharacterVersion
                    )

                    return true
                end
            )

        if not moved then
            warn(
                "[Boss Loot] Skipped; movement owned by:",
                runtime.movementOwner
            )
        end

        endBossOverride(
            reason
        )

        if questFarmEnabled
            and resumeCFrame
            and resumeCharacterVersion
                == runtime.characterVersion then

            runMovementOperation(
                "QuestResumePoint",
                Config.MOVEMENT_LOCK_WAIT_TIMEOUT,
                function()
                    local root =
                        getRoot()

                    if not root then
                        return false
                    end

                    root.AssemblyLinearVelocity =
                        Vector3.zero

                    root.CFrame =
                        resumeCFrame

                    return true
                end
            )

            markRuntimeEvent(
                "QuestResumeAfterBoss"
            )

        elseif bossFarmEnabled
            and not questFarmEnabled then

            local boss =
                BossData.BOSSES[
                    selectedBossName
                ]

            if boss then
                runMovementOperation(
                    "BossReturn",
                    Config.MOVEMENT_LOCK_WAIT_TIMEOUT,
                    function()
                        return BossWaypoint.WarpToBoss(
                            Config,
                            HumanoidRegions,
                            boss,
                            getRoot(),
                            farmHeight,
                            Config.BOSS_STREAM_WAIT_TIMEOUT,
                            function()
                                return not scriptAlive
                                    or not bossFarmEnabled
                            end
                        )
                    end
                )
            end
        end
    end)
end

local function setTarget(
    newTarget,
    mode
)
    clearTarget()

    target = newTarget
    targetMode = mode
    targetDeathCounted = false

    if not target then
        targetMode = nil
        return
    end

    targetVersion += 1
    targetReadyAt =
        os.clock() + Config.TARGET_SWITCH_DELAY

    markRuntimeEvent(
        "Target:"
            .. tostring(
                mode or "?"
            )
            .. ":"
            .. tostring(
                target.name or target.model.Name
            )
    )

    lockFrames = 0

    if targetMode == "boss"
        and target.root
        and target.root.Parent then

        bossLastPosition =
            target.root.Position
    end

    if capturedArgs
        and typeof(capturedArgs[1])
            == "Instance" then

        pcall(function()
            capturedArgs[1].Value = 1
        end)
    end

    if targetMode == "quest"
        and questFarmEnabled then

        targetDiedConnection =
            target.humanoid.Died:Connect(
                onQuestTargetDied
            )

    elseif targetMode == "boss" then
        targetDiedConnection =
            target.humanoid.Died:Connect(
                function()
                    if target
                        and target.root
                        and target.root.Parent then

                        bossLastPosition =
                            target.root.Position
                    end

                    task.defer(function()
                        finishBossOverride(
                            "boss defeated"
                        )
                    end)
                end
            )
    end

    print(
        "[Farm] Target:",
        target.model:GetFullName(),
        "| Mode:",
        targetMode or "unknown"
    )
end

--==================================================
-- COMBAT Do DISCOVERY / CAPTURE
--==================================================

for _, fn in ipairs(getgc(true)) do
    if type(fn) == "function" then
        local name = ""
        local source = ""

        pcall(function()
            name = tostring(debug.info(fn, "n"))
            source = tostring(debug.info(fn, "s"))
        end)

        if name == "Do"
            and string.find(
                source,
                "Main_Combat_Script_Client",
                1,
                true
            ) then

            DoFunction = fn
            break
        end
    end
end

if DoFunction then
    originalDo =
        hookfunction(
            DoFunction,
            newcclosure(function(...)
                local weaponKey =
                    currentWeaponName
                    or getDesiredWeapon()
                    or "Fist"

                if not combatArgsByWeapon[
                    weaponKey
                ] then

                    local packed =
                        table.pack(...)

                    combatArgsByWeapon[
                        weaponKey
                    ] = packed

                    capturedArgs =
                        packed

                    print(
                        "[Combat] REAL arguments captured for:",
                        weaponKey
                    )
                elseif not capturedArgs then
                    capturedArgs =
                        combatArgsByWeapon[
                            weaponKey
                        ]
                end

                return originalDo(...)
            end)
        )

    print("[Combat] Do FOUND")
else
    warn("[Combat] Do not found")
end

local function findCombatComboValue()
    local playerScripts =
        player:FindFirstChild(
            "PlayerScripts"
        )

    local cu =
        playerScripts
        and playerScripts:FindFirstChild(
            "CU"
        )

    local combat =
        cu
        and cu:FindFirstChild(
            "Combat"
        )

    local comboValue =
        combat
        and combat:FindFirstChild(
            "ComboValue"
        )

    if comboValue
        and comboValue:IsA("ValueBase") then

        return comboValue
    end

    return nil
end

local function looksLikeCombatConfig(value)
    if type(value) ~= "table" then
        return false
    end

    local ok, matched =
        pcall(function()
            return type(rawget(value, "default_before_swing")) == "number"
                and type(rawget(value, "default_before_hit")) == "number"
                and type(rawget(value, "default")) == "number"
                and type(rawget(value, "final")) == "number"
                and type(rawget(value, "run_swing_remove_on_first")) == "number"
                and type(rawget(value, "AnimSpeed")) == "table"
                and type(rawget(value, "Effects")) == "table"
                and type(rawget(value, "finals")) == "table"
        end)

    return ok and matched
end

local function findCombatConfig()
    for _, value in ipairs(
        getgc(true)
    ) do
        if looksLikeCombatConfig(value) then
            return value
        end
    end

    return nil
end

local function trySimulatedCombatClick()
    if capturedArgs then
        return true
    end

    ensureEquip()

    task.wait(0.30)

    local camera =
        workspace.CurrentCamera

    local viewport =
        camera
        and camera.ViewportSize
        or Vector2.new(
            1280,
            720
        )

    local x =
        math.floor(
            viewport.X * 0.45
        )

    local y =
        math.floor(
            viewport.Y * 0.55
        )

    local function waitForCapture()
        local deadline =
            os.clock() + 0.45

        repeat
            if capturedArgs then
                return true
            end

            task.wait(0.03)
        until os.clock() >= deadline

        return capturedArgs ~= nil
    end

    local nativeMouseOk =
        pcall(function()
            if type(mouse1click) == "function" then
                mouse1click()
                return
            end

            if type(mouse1press) == "function"
                and type(mouse1release) == "function" then

                mouse1press()
                task.wait(0.05)
                mouse1release()
                return
            end

            error("native mouse input unavailable")
        end)

    if nativeMouseOk
        and waitForCapture() then

        return true
    end

    local vimOk =
        pcall(function()
            local virtualInput =
                game:GetService(
                    "VirtualInputManager"
                )

            virtualInput:SendMouseButtonEvent(
                x,
                y,
                0,
                true,
                game,
                0
            )

            task.wait(0.05)

            virtualInput:SendMouseButtonEvent(
                x,
                y,
                0,
                false,
                game,
                0
            )
        end)

    if vimOk
        and waitForCapture() then

        return true
    end

    local vuOk =
        pcall(function()
            VirtualUser:CaptureController()

            VirtualUser:Button1Down(
                Vector2.new(
                    x,
                    y
                ),
                camera
                    and camera.CFrame
                    or CFrame.new()
            )

            task.wait(0.05)

            VirtualUser:Button1Up(
                Vector2.new(
                    x,
                    y
                ),
                camera
                    and camera.CFrame
                    or CFrame.new()
            )
        end)

    if vuOk
        and waitForCapture() then

        return true
    end

    return false
end

local function tryBuildCombatArgs()
    if capturedArgs then
        return true
    end

    local weaponKey =
        currentWeaponName
        or getDesiredWeapon()
        or "Fist"

    -- Reconstructed arguments are verified only for the fist path.
    -- Katana must use arguments captured from the game's real attack
    -- entrypoint; otherwise animation can play without server damage.
    if weaponKey ~= "Fist" then
        return false
    end

    local comboValue =
        findCombatComboValue()

    local combatConfig =
        findCombatConfig()

    if not comboValue
        or not combatConfig then

        return false
    end

    capturedArgs =
        table.pack(
            comboValue,
            combatConfig,
            "Combat",
            nil
        )

    combatArgsByWeapon[
        weaponKey
    ] = capturedArgs

    print(
        "[Combat] Fist fallback initialized from live config"
    )

    return true
end

local function tryAutoCombatBootstrap()
    local equipOk =
        ensureEquip()

    if not equipOk then
        return false
    end

    if currentWeaponName
        and weaponHasDirectCombat(
            currentWeaponName
        ) then

        return true
    end

    if capturedArgs then
        return true
    end

    task.wait(0.25)

    if trySimulatedCombatClick() then
        print(
            "[Combat] Auto initialized by simulated attack"
        )

        return true
    end

    if tryBuildCombatArgs() then
        return true
    end

    if currentWeaponName
        and currentWeaponName ~= "Fist" then

        warn(
            "[Combat] Katana real attack capture failed; synthetic args are disabled to prevent animation-only hits"
        )
    else
        warn(
            "[Combat] Auto initialization failed; manual attack is still available as fallback"
        )
    end

    return false
end

local function combatReady()
    if currentWeaponName
        and weaponHasDirectCombat(
            currentWeaponName
        ) then

        return true
    end

    return originalDo ~= nil
        and capturedArgs ~= nil
        and typeof(capturedArgs[1]) == "Instance"
end

local function getActiveComboValue()
    if capturedArgs
        and typeof(capturedArgs[1])
            == "Instance" then

        return capturedArgs[1]
    end

    return findCombatComboValue()
end

local function doAttack(combo)
    if not combatReady() then
        return false
    end

    if currentWeaponName
        and weaponHasDirectCombat(
            currentWeaponName
        ) then

        local definition =
            WeaponData.WEAPONS[
                currentWeaponName
            ]

        local timing =
            definition.comboTimings[
                combo
            ]

        if timing == nil then
            return false
        end

        local ok, err =
            pcall(function()
                Event:FireServer(
                    "Combat_Service",
                    definition.combatRemoteName
                        or currentWeaponName,
                    combo,
                    false,
                    timing,
                    false
                )
            end)

        if not ok then
            warn(
                "[Combat] Direct Katana error:",
                err
            )

            return false
        end

        return true
    end

    local ok, err =
        pcall(function()
            originalDo(
                table.unpack(
                    capturedArgs,
                    1,
                    capturedArgs.n
                )
            )
        end)

    if not ok then
        warn("[Combat] Error:", err)
        return false
    end

    return true
end

local function syncWeaponForCombatUnlocked(
    forceEquip
)
    local desiredWeapon =
        getDesiredCombatWeapon()

    local ok, changed =
        equipWeaponByName(
            desiredWeapon,
            forceEquip == true
        )

    if not ok then
        return false
    end

    local combatOk = true

    if changed
        or forceEquip
        or not combatReady() then

        -- equipWeaponByName already restores this weapon's cached
        -- arguments when available. Only bootstrap if there is no
        -- usable argument set for the equipped weapon.
        if not combatReady() then
            combatOk =
                tryAutoCombatBootstrap()
        end
    end

    return combatOk
end

local function syncWeaponForCombat(
    forceEquip
)
    return runWeaponOperation(
        forceEquip
            and "CombatForceSync"
            or "CombatSync",
        Config.WEAPON_SYNC_WAIT_TIMEOUT,
        function()
            return syncWeaponForCombatUnlocked(
                forceEquip
            )
        end
    )
end

local function getShopWeaponObject(
    weaponName
)
    local definition =
        WeaponData.WEAPONS[weaponName]

    if not definition then
        return nil
    end

    local region =
        HumanoidRegions:FindFirstChild(
            definition.shopRegion
        )

    local stationaryNpcs =
        region
        and region:FindFirstChild(
            "StationaryNpcs"
        )

    local npc =
        stationaryNpcs
        and stationaryNpcs:FindFirstChild(
            definition.shopNpc
        )

    local shop =
        npc
        and npc:FindFirstChild(
            definition.shopName
        )

    return shop
        and shop:FindFirstChild(
            weaponName
        )
end

local function getWorldCFrame(object)
    if not object then
        return nil
    end

    if object:IsA("Model") then
        local ok, pivot =
            pcall(function()
                return object:GetPivot()
            end)

        if ok then
            return pivot
        end
    end

    if object:IsA("BasePart") then
        return object.CFrame
    end

    local part =
        object:FindFirstChildWhichIsA(
            "BasePart",
            true
        )

    return part
        and part.CFrame
        or nil
end

local function waitForWeaponOwned(
    weaponName,
    timeout
)
    local deadline =
        os.clock() + timeout

    repeat
        if ownsWeapon(weaponName) then
            return true
        end

        task.wait(0.10)
    until os.clock() >= deadline
        or not scriptAlive

    return ownsWeapon(weaponName)
end

local function purchaseWeaponUnlocked(
    weaponName
)
    if ownsWeapon(weaponName) then
        return false
    end

    local definition =
        WeaponData.WEAPONS[weaponName]

    local wen =
        getWenValue()

    if not definition
        or not wen
        or wen.Value < definition.price then

        return false
    end

    local root =
        getRoot()

    local shopObject =
        getShopWeaponObject(
            weaponName
        )

    local shopCFrame =
        getWorldCFrame(
            shopObject
        )

    if not root
        or not shopCFrame then

        warn(
            "[Auto Weapon] Shop object not found:",
            weaponName
        )

        weaponPurchaseRetryAt =
            os.clock()
            + Config.WEAPON_PURCHASE_RETRY_DELAY

        return false
    end

    clearTarget()

    local returnCFrame =
        root.CFrame

    root.AssemblyLinearVelocity =
        Vector3.zero

    root.CFrame =
        shopCFrame
        * CFrame.new(
            0,
            4,
            -3
        )

    task.wait(
        Config.WEAPON_SHOP_ARRIVE_DELAY
    )

    if not scriptAlive then
        if root.Parent then
            root.CFrame =
                returnCFrame
        end

        return false
    end

    print(
        "[Auto Weapon] Buying:",
        weaponName,
        "| Wen:",
        wen.Value
    )

    pcall(function()
        Event:FireServer(
            "PurchaseFromShop",
            weaponName,
            1
        )
    end)

    local purchased =
        waitForWeaponOwned(
            weaponName,
            Config.WEAPON_VERIFY_TIMEOUT
        )

    if purchased then
        print(
            "[Auto Weapon] Purchase VERIFIED:",
            weaponName
        )

        currentWeaponName = nil
        capturedArgs = nil

        task.wait(0.15)

        -- Rebuild combat while still at the shop so the bootstrap click
        -- cannot accidentally finish an active farm target off-screen.
        local combatOk =
            syncWeaponForCombatUnlocked(
                true
            )

        if not combatOk then
            warn(
                "[Auto Weapon] Weapon purchased but combat bootstrap failed:",
                weaponName
            )
        end

        weaponPurchaseRetryAt = 0
    else
        warn(
            "[Auto Weapon] Purchase not verified:",
            weaponName
        )

        weaponPurchaseRetryAt =
            os.clock()
            + Config.WEAPON_PURCHASE_RETRY_DELAY
    end

    if root.Parent then
        root.AssemblyLinearVelocity =
            Vector3.zero

        root.CFrame =
            returnCFrame
    end

    return purchased
end

local function purchaseWeapon(
    weaponName
)
    return runMovementOperation(
        "WeaponShop",
        0,
        function()
            return runWeaponOperation(
                "Purchase:"
                    .. tostring(
                        weaponName
                    ),
                0,
                function()
                    return purchaseWeaponUnlocked(
                        weaponName
                    )
                end
            )
        end
    )
end

--==================================================
-- FARM CONTROLLERS
--==================================================

local function anyFarmEnabled()
    return nearbyFarmEnabled
        or questFarmEnabled
        or bossFarmEnabled
end

local function warpToBossManaged(
    owner,
    boss,
    streamTimeout
)
    return runMovementOperation(
        owner,
        Config.MOVEMENT_LOCK_WAIT_TIMEOUT,
        function()
            return BossWaypoint.WarpToBoss(
                Config,
                HumanoidRegions,
                boss,
                getRoot(),
                farmHeight,
                streamTimeout,
                function()
                    return not scriptAlive
                        or not bossFarmEnabled
                end
            )
        end
    )
end

local function startBossFarm()
    local boss =
        BossData.BOSSES[
            selectedBossName
        ]

    if not boss then
        warn("[Boss Farm] Select a valid boss")
        return false
    end

    bossOverrideActive = false
    bossLootBusy = false
    bossLastPosition = nil
    bossScanReadyAt = 0

    -- Standalone Boss Farm moves to the saved boss area first.
    -- When Quest Farm is also enabled, Quest movement has priority and
    -- Boss Watch stays passive until the boss is actually detected.
    if not questFarmEnabled then
        local warped, bossRoot, warpMode =
            warpToBossManaged(
                "BossStart",
                boss,
                Config.BOSS_STREAM_WAIT_TIMEOUT
            )

        if not bossFarmEnabled
            or warpMode == "cancelled" then

            markRuntimeEvent(
                "BossWarpCancelled"
            )

            return false
        end

        if not warped then
            if warpMode == "no-waypoint" then
                warn(
                    "[Boss Farm] No saved waypoint yet:",
                    selectedBossName,
                    "| visit/stream this boss once so its position can be learned"
                )
            else
                warn(
                    "[Boss Farm] Could not warp to boss point:",
                    selectedBossName,
                    "|",
                    tostring(warpMode)
                )
            end
        else
            print(
                "[Boss Farm] Waypoint warp:",
                selectedBossName,
                "|",
                warpMode,
                "| bossRoot:",
                bossRoot ~= nil
            )
        end
    else
        markRuntimeEvent(
            "BossWatchPassive:Quest"
        )

        print(
            "[Boss Farm] Quest Farm active; boss waypoint warp deferred"
        )
    end

    markRuntimeEvent(
        "BossWatch:"
            .. tostring(
                selectedBossName
            )
    )

    print(
        "[Boss Farm] Watching:",
        selectedBossName
    )

    return true
end

local function startNearbyFarm()
    -- Keep the currently equipped weapon. Auto Weapon only changes it
    -- when the desired weapon actually changes or after a respawn.
    local root = getRoot()

    if not root then
        return false
    end

    questFarmEnabled = false
    nearbyFarmOrigin = root.Position

    clearTarget()

    markRuntimeEvent(
        "NearbyStart"
    )

    print(
        "[Nearby Farm] Origin set:",
        nearbyFarmOrigin,
        "| Range:",
        nearbyFarmRange
    )

    return true
end

local function startQuestFarm()
    local quest =
        QuestData.QUESTS[
            selectedQuestName
        ]

    if not quest then
        warn("[Quest Farm] Select a valid quest")
        return false
    end

    nearbyFarmEnabled = false
    nearbyFarmOrigin = nil

    clearTarget()

    resetQuestProgressTracking()
    questNeedsAccept = true
    questAcceptReadyAt = 0
    questBusy = false

    -- Start by moving toward the selected quest NPC before combat
    -- bootstrap. This makes Start Quest Farm behave consistently even
    -- when the character spawned at a distant checkpoint.
    local warped, _, warpMode =
        warpToQuestNpc(
            quest,
            0
        )

    if not warped
        and warpMode == "no-waypoint" then

        warn(
            "[Quest Farm] No saved NPC waypoint yet:",
            quest.npcName,
            "| the accept loop will learn it automatically once this NPC is streamed"
        )
    end

    -- Do not redraw the same weapon at quest start. Startup/respawn
    -- and a real weapon change are the only normal equip triggers.
    markRuntimeEvent(
        "QuestStart:"
            .. tostring(
                selectedQuestName
            )
    )

    print(
        "[Quest Farm] Started:",
        selectedQuestName
    )

    return true
end

-- Quest accept controller.
-- Keep the controller alive even if a transient UI/path error occurs.
task.spawn(function()
    while scriptAlive do
        if questFarmEnabled
            and questNeedsAccept
            and not questBusy
            and not weaponBusy then

            local ok, accepted =
                pcall(
                    acceptSelectedQuest
                )

            if not ok then
                questBusy = false
                questNeedsAccept = true

                markRuntimeEvent(
                    "QuestAcceptError"
                )

                warn(
                    "[Quest Farm] Accept controller error:",
                    accepted
                )

                task.wait(
                    Config.CONTROLLER_ERROR_RETRY_DELAY
                )

            elseif not accepted then
                task.wait(0.10)
            end
        else
            task.wait(0.05)
        end
    end
end)

-- Server quest-progress monitor.
task.spawn(function()
    while scriptAlive do
        if questFarmEnabled
            and not questBusy
            and not questNeedsAccept then

            local ok, err =
                pcall(
                    syncSelectedQuestProgress
                )

            if not ok then
                markRuntimeEvent(
                    "QuestProgressError"
                )

                warn(
                    "[Quest Farm] Progress controller error:",
                    err
                )

                task.wait(
                    Config.CONTROLLER_ERROR_RETRY_DELAY
                )
            end
        end

        task.wait(
            Config.QUEST_UI_POLL_DELAY
        )
    end
end)

-- Boss spawn monitor.
-- It never removes or changes the active quest. When the selected boss
-- appears, it temporarily replaces the normal farm target, then releases
-- control after the boss dies/despawns.
task.spawn(function()
    while scriptAlive do
        local ok, err =
            pcall(function()
                if bossFarmEnabled
                    and not bossLootBusy
                    and not weaponBusy
                    and runtime.movementOwner == nil
                    and os.clock()
                        >= bossScanReadyAt then

                    bossScanReadyAt =
                        os.clock() + 0.25

                    local questLocked =
                        questFarmEnabled
                        and (
                            questNeedsAccept
                            or questBusy
                        )

                    if not questLocked
                        and not activeQuestAlreadyTargetsBoss() then

                        local bossTarget =
                            findSelectedBossTarget()

                        if bossTarget
                            and not bossOverrideActive then

                            if questFarmEnabled then
                                local root =
                                    getRoot()

                                if root then
                                    bossResumeCFrame =
                                        root.CFrame

                                    bossResumeCharacterVersion =
                                        runtime.characterVersion
                                end
                            else
                                bossResumeCFrame = nil
                                bossResumeCharacterVersion = 0
                            end

                            bossOverrideActive = true

                            setTarget(
                                bossTarget,
                                "boss"
                            )

                            print(
                                "[Boss Farm] SPAWN detected:",
                                selectedBossName,
                                "| overriding current farm target"
                            )

                        elseif bossOverrideActive then
                            if not bossTarget then
                                finishBossOverride(
                                    "boss no longer available"
                                )

                            elseif targetMode ~= "boss"
                                or not targetAlive() then

                                setTarget(
                                    bossTarget,
                                    "boss"
                                )
                            end
                        end
                    end
                end
            end)

        if not ok then
            markRuntimeEvent(
                "BossMonitorError"
            )

            warn(
                "[Boss Farm] Monitor error:",
                err
            )

            task.wait(
                Config.CONTROLLER_ERROR_RETRY_DELAY
            )
        end

        task.wait(0.10)
    end
end)

-- Head lock / target selection.
local farmHeartbeatConnection =
    RunService.Heartbeat:Connect(function()
        if not scriptAlive
            or not anyFarmEnabled()
            or weaponBusy
            or bossLootBusy
            or runtime.movementOwner ~= nil then

            return
        end

        if questFarmEnabled
            and (questNeedsAccept or questBusy)
            and not bossOverrideActive then

            return
        end

        local root = getRoot()

        if not root then
            return
        end

        if questFarmEnabled
            and not bossOverrideActive
            and os.clock()
                < questProgressHoldUntil then

            return
        end

        if targetMode == "boss"
            and target
            and target.root
            and target.root.Parent then

            bossLastPosition =
                target.root.Position
        end

        if target
            and not targetAlive() then

            if targetMode == "boss" then
                finishBossOverride(
                    "boss target ended"
                )

                return

            elseif targetMode == "quest"
                and questFarmEnabled then

                onQuestTargetDied()

                if questNeedsAccept then
                    clearTarget()
                    return
                end

            else
                clearTarget()
            end
        end

        if not targetAlive() then
            if bossOverrideActive then
                setTarget(
                    findSelectedBossTarget(),
                    "boss"
                )

            elseif nearbyFarmEnabled then
                setTarget(
                    findNearestNearbyTarget(),
                    "nearby"
                )

            elseif questFarmEnabled then
                setTarget(
                    findNearestQuestTarget(),
                    "quest"
                )
            end
        end

        if not targetAlive() then
            return
        end

        root.AssemblyLinearVelocity = Vector3.zero

        local farmCFrame =
            FarmPosition.GetCFrame(
                target.root,
                farmPositionMode,
                farmHeight
            )

        if farmCFrame then
            root.CFrame =
                farmCFrame
        end

        local distance =
            (root.Position - target.root.Position).Magnitude

        if distance <= Config.MAX_ATTACK_DISTANCE then
            lockFrames += 1
        else
            lockFrames = 0
        end
    end)

-- Auto combo controller.
-- Track whether either HP or BlockPoints changes across full combo
-- cycles. The watchdog is diagnostic only; it never re-equips weapons.
task.spawn(function()
    while scriptAlive do
        if not anyFarmEnabled()
            or weaponBusy
            or runtime.movementOwner ~= nil
            or not combatReady()
            or not targetAlive() then

            task.wait(0.05)
            continue
        end

        if questFarmEnabled
            and (questNeedsAccept or questBusy) then

            task.wait(0.05)
            continue
        end

        local comboValue =
            getActiveComboValue()

        if not comboValue then
            task.wait(0.05)
            continue
        end

        if os.clock() < targetReadyAt
            or lockFrames < 2 then

            task.wait(0.03)
            continue
        end

        if targetDown() then
            pcall(function()
                comboValue.Value = 1
            end)

            combatNoDamageCycles = 0

            task.wait(0.05)
            continue
        end

        local thisTargetVersion = targetVersion
        local healthBefore =
            target.humanoid.Health

        local blockBefore =
            target.model:GetAttribute(
                "BlockPoints"
            )

        local hitsSent = 0

        for combo = 1, Config.MAX_COMBO_HIT do
            if not anyFarmEnabled()
                or weaponBusy
                or runtime.movementOwner ~= nil
                or not targetAlive()
                or targetVersion ~= thisTargetVersion
                or targetDown() then

                break
            end

            if questFarmEnabled
                and (questNeedsAccept or questBusy) then

                break
            end

            local root = getRoot()

            if not root then
                break
            end

            local distance =
                (root.Position - target.root.Position).Magnitude

            if distance > Config.MAX_ATTACK_DISTANCE then
                break
            end

            comboValue.Value = combo

            if doAttack(combo) then
                hitsSent += 1
            end

            task.wait(Config.HIT_DELAY)
        end

        pcall(function()
            comboValue.Value = 1
        end)

        if SkillAutomation.AnyEnabled()
            and targetVersion
                == thisTargetVersion
            and targetAlive()
            and not targetDown()
            and not weaponBusy
            and runtime.movementOwner == nil then

            local root =
                getRoot()

            if root
                and target.root
                and target.root.Parent then

                local distance =
                    (
                        root.Position
                        - target.root.Position
                    ).Magnitude

                if distance
                    <= Config.AUTO_SKILL_MAX_DISTANCE then

                    local used,
                        keyName =
                        SkillAutomation.Try(
                            Config.AUTO_SKILL_RETRY_DELAY
                        )

                    if used
                        and keyName then

                        markRuntimeEvent(
                            "Skill:"
                                .. keyName
                        )
                    end
                end
            end
        end

        if targetVersion == thisTargetVersion
            and targetAlive()
            and not targetDown() then

            task.wait(Config.COMBO_END_DELAY)

            if hitsSent >= Config.MAX_COMBO_HIT
                and targetVersion == thisTargetVersion
                and targetAlive()
                and not targetDown() then

                local healthAfter =
                    target.humanoid.Health

                local blockAfter =
                    target.model:GetAttribute(
                        "BlockPoints"
                    )

                local healthProgress =
                    healthAfter
                    < healthBefore

                local blockProgress =
                    type(blockBefore) == "number"
                    and type(blockAfter) == "number"
                    and blockAfter < blockBefore

                if healthProgress
                    or blockProgress then

                    combatNoDamageCycles = 0
                else
                    combatNoDamageCycles += 1
                end

                if combatNoDamageCycles
                    >= Config.COMBAT_STALL_COMBO_LIMIT
                    and os.clock()
                        >= combatRecoveryReadyAt then

                    combatRecoveryReadyAt =
                        os.clock()
                        + Config.COMBAT_RECOVERY_COOLDOWN

                    combatNoDamageCycles = 0
                    combatStallEvents += 1

                    print(
                        "[Combat Watchdog] No HP/block progress | keeping target lock"
                    )
                end
            end
        else
            combatNoDamageCycles = 0
            task.wait(0.03)
        end
    end
end)

-- Auto weapon progression controller.
-- Every iteration is protected so one transient UI/inventory error does
-- not permanently kill weapon recovery for the rest of the session.
task.spawn(function()
    while scriptAlive do
        local ok, err =
            pcall(function()
                if weaponMode == "Auto Best"
                    and not weaponBusy
                    and runtime.movementOwner == nil then

                    if anyFarmEnabled() then
                        local desiredWeapon =
                            getBestCombatWeapon()

                        -- During an active farm, never redraw the same
                        -- weapon just because the visual draw state flickers.
                        -- Only a real weapon change (or respawn, handled
                        -- separately) is allowed to trigger another equip.
                        if not questBusy
                            and not questNeedsAccept
                            and desiredWeapon
                                ~= currentWeaponName then

                            syncWeaponForCombat(
                                false
                            )
                        end
                    else
                        local desiredWeapon =
                            getBestOwnedWeapon()

                        if desiredWeapon
                            ~= currentWeaponName then

                            ensureEquipSerialized(
                                false,
                                "IdleAutoBest"
                            )
                        end
                    end
                end

                if autoBuyWeaponEnabled
                    and weaponMode == "Auto Best"
                    and anyFarmEnabled()
                    and not ownsWeapon("Thunder Katana")
                    and not ownsWeapon("Cutlass")
                    and not weaponBusy
                    and not questBusy
                    and not questNeedsAccept
                    and not bossLootBusy
                    and not bossOverrideActive
                    and not targetAlive()
                    and runtime.movementOwner == nil
                    and os.clock() >= weaponPurchaseRetryAt then

                    local wen =
                        getWenValue()

                    if wen then
                        local hasRegular =
                            ownsWeapon(
                                "Regular Katana"
                            )

                        local hasFancy =
                            ownsWeapon(
                                "Fancy Katana"
                            )

                        if not hasFancy then
                            if not hasRegular
                                and wen.Value
                                    >= WeaponData.WEAPONS["Regular Katana"].price then

                                purchaseWeapon(
                                    "Regular Katana"
                                )
                            elseif hasRegular
                                and wen.Value
                                    >= WeaponData.WEAPONS["Fancy Katana"].price then

                                purchaseWeapon(
                                    "Fancy Katana"
                                )
                            end
                        end
                    end
                end
            end)

        if not ok then
            markRuntimeEvent(
                "WeaponControllerError"
            )

            warn(
                "[Auto Weapon] Controller error:",
                err
            )

            task.wait(
                Config.CONTROLLER_ERROR_RETRY_DELAY
            )
        end

        task.wait(0.50)
    end
end)

--==================================================
-- GENERIC PLAYER CONTROL
--==================================================

local function disableEverything()
    speedEnabled = false
    noclipEnabled = false
    spaceFloatEnabled = false
    spaceHeld = false
    antiAfkEnabled = false

    nearbyFarmEnabled = false
    questFarmEnabled = false
    bossFarmEnabled = false
    bossOverrideActive = false
    bossLootBusy = false
    bossLastPosition = nil
    nearbyFarmOrigin = nil

    autoBuyWeaponEnabled = false
    weaponBusy = false

    runtime.weaponOperation = "Idle"
    runtime.weaponSince = 0
    runtime.movementOwner = nil
    runtime.movementSince = 0

    clearTarget()

    local humanoid = getHumanoid()

    if humanoid then
        humanoid.WalkSpeed = originalWalkSpeed
    end

    restoreCollision()
end

--==================================================
-- LINORIA
--==================================================

local repo =
    "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"

local Library =
    loadstring(
        game:HttpGet(
            repo .. "Library.lua"
        )
    )()

local function setupUI()
local Window =
    Library:CreateWindow({
        Title = "Player Control " .. Config.VERSION,
        Center = true,
        AutoShow = true,
        TabPadding = 6,
        MenuFadeTime = 0.12
    })

local MainTab =
    Window:AddTab("Main")

local FarmTab =
    Window:AddTab("Farm")

local CombatTab =
    Window:AddTab("Combat")

local MovementTab =
    Window:AddTab("Movement")

--==================================================
-- SPEED
--==================================================

local SpeedBox =
    MovementTab:AddLeftGroupbox("Speed")

SpeedBox:AddToggle(
    "SpeedEnabled",
    {
        Text = "Enable Speed",
        Default = false
    }
)

SpeedBox:AddSlider(
    "SpeedValue",
    {
        Text = "Walk Speed",
        Default = 150,
        Min = 16,
        Max = 300,
        Rounding = 0
    }
)

Toggles.SpeedEnabled:OnChanged(function()
    speedEnabled =
        Toggles.SpeedEnabled.Value

    if not speedEnabled then
        local humanoid =
            getHumanoid()

        if humanoid then
            humanoid.WalkSpeed =
                originalWalkSpeed
        end
    end
end)

Options.SpeedValue:OnChanged(function()
    speed =
        Options.SpeedValue.Value
end)

--==================================================
-- MOVEMENT
--==================================================

local MovementBox =
    MovementTab:AddRightGroupbox(
        "Movement"
    )

MovementBox:AddToggle(
    "NoclipEnabled",
    {
        Text = "Noclip",
        Default = false
    }
)

MovementBox:AddToggle(
    "SpaceFloatEnabled",
    {
        Text = "Space Float",
        Default = false
    }
)

MovementBox:AddSlider(
    "FloatSpeed",
    {
        Text = "Float Speed",
        Default = 45,
        Min = 5,
        Max = 150,
        Rounding = 0
    }
)

Toggles.NoclipEnabled:OnChanged(function()
    noclipEnabled =
        Toggles.NoclipEnabled.Value

    if not noclipEnabled then
        restoreCollision()
    end
end)

Toggles.SpaceFloatEnabled:OnChanged(function()
    spaceFloatEnabled =
        Toggles.SpaceFloatEnabled.Value
end)

Options.FloatSpeed:OnChanged(function()
    floatSpeed =
        Options.FloatSpeed.Value
end)

--==================================================
-- WEAPON
--==================================================

local WeaponBox =
    CombatTab:AddLeftGroupbox(
        "Weapon"
    )

WeaponBox:AddDropdown(
    "WeaponMode",
    {
        Values = WeaponData.MODES,
        Default = 1,
        Multi = false,
        Text = "Weapon Mode"
    }
)

WeaponBox:AddToggle(
    "AutoBuyWeaponEnabled",
    {
        Text = "Auto Buy Upgrade",
        Default = true
    }
)

WeaponBox:AddLabel(
    "Auto Best: Thunder > Cutlass > Fancy > Regular > Fist"
)

Options.WeaponMode:OnChanged(function()
    weaponMode =
        Options.WeaponMode.Value

    print(
        "[Auto Weapon] Mode:",
        weaponMode
    )

    task.spawn(function()
        if anyFarmEnabled() then
            syncWeaponForCombat(false)
        else
            ensureEquipSerialized(
                false,
                "ModeChange"
            )
        end
    end)
end)

Toggles.AutoBuyWeaponEnabled:OnChanged(function()
    autoBuyWeaponEnabled =
        Toggles.AutoBuyWeaponEnabled.Value
end)

do
    local box =
        CombatTab:AddLeftGroupbox(
            "Auto Skill"
        )

    box:AddToggle(
        "AutoSkillZEnabled",
        {
            Text = "Auto Skill Z",
            Default = false
        }
    )

    box:AddToggle(
        "AutoSkillXEnabled",
        {
            Text = "Auto Skill X",
            Default = false
        }
    )

    box:AddToggle(
        "AutoSkillCEnabled",
        {
            Text = "Auto Skill C",
            Default = false
        }
    )

    box:AddToggle(
        "AutoSkillVEnabled",
        {
            Text = "Auto Skill V",
            Default = false
        }
    )

    box:AddToggle(
        "AutoSkillBEnabled",
        {
            Text = "Auto Skill B",
            Default = false
        }
    )

    box:AddLabel(
        "Uses Z / X / C / V / B only while a farm target is in range."
    )
end

Toggles.AutoSkillZEnabled:OnChanged(function()
    SkillAutomation.SetEnabled(
        "Z",
        Toggles.AutoSkillZEnabled.Value
    )
end)

Toggles.AutoSkillXEnabled:OnChanged(function()
    SkillAutomation.SetEnabled(
        "X",
        Toggles.AutoSkillXEnabled.Value
    )
end)

Toggles.AutoSkillCEnabled:OnChanged(function()
    SkillAutomation.SetEnabled(
        "C",
        Toggles.AutoSkillCEnabled.Value
    )
end)

Toggles.AutoSkillVEnabled:OnChanged(function()
    SkillAutomation.SetEnabled(
        "V",
        Toggles.AutoSkillVEnabled.Value
    )
end)

Toggles.AutoSkillBEnabled:OnChanged(function()
    SkillAutomation.SetEnabled(
        "B",
        Toggles.AutoSkillBEnabled.Value
    )
end)

local FarmPositionBox =
    CombatTab:AddRightGroupbox(
        "Farm Position"
    )

FarmPositionBox:AddDropdown(
    "FarmPositionMode",
    {
        Values = FarmPosition.MODES,
        Default = 1,
        Multi = false,
        Text = "Position"
    }
)

FarmPositionBox:AddSlider(
    "FarmHeight",
    {
        Text = "Offset Distance",
        Default = Config.FARM_HEIGHT,
        Min = 2,
        Max = 20,
        Rounding = 1,
        Suffix = " studs"
    }
)

FarmPositionBox:AddLabel(
    "Above / Below / Front / Back + 4 diagonal positions."
)

Options.FarmPositionMode:OnChanged(function()
    farmPositionMode =
        Options.FarmPositionMode.Value
end)

Options.FarmHeight:OnChanged(function()
    farmHeight =
        Options.FarmHeight.Value
end)

task.spawn(function()
    task.wait(0.75)

    if scriptAlive then
        ensureEquipSerialized(
            false,
            "Startup"
        )
    end
end)

--==================================================
-- NEARBY FARM
--==================================================

local NearbyFarmBox =
    FarmTab:AddLeftGroupbox(
        "Nearby Farm"
    )

NearbyFarmBox:AddLabel(
    "Combat initializes automatically when farm starts."
)

NearbyFarmBox:AddSlider(
    "NearbyFarmRange",
    {
        Text = "Farm Range",
        Default = 100,
        Min = 10,
        Max = 500,
        Rounding = 0,
        Suffix = " studs"
    }
)

NearbyFarmBox:AddToggle(
    "NearbyFarmEnabled",
    {
        Text = "Auto Nearby Farm",
        Default = false
    }
)

Options.NearbyFarmRange:OnChanged(function()
    nearbyFarmRange =
        Options.NearbyFarmRange.Value
end)

Toggles.NearbyFarmEnabled:OnChanged(function()
    local requested =
        Toggles.NearbyFarmEnabled.Value

    if requested then
        if Toggles.QuestFarmEnabled
            and Toggles.QuestFarmEnabled.Value then

            Toggles.QuestFarmEnabled:SetValue(false)
        end

        nearbyFarmEnabled = true

        if not startNearbyFarm() then
            nearbyFarmEnabled = false
            Toggles.NearbyFarmEnabled:SetValue(false)
        end
    else
        nearbyFarmEnabled = false
        nearbyFarmOrigin = nil

        if not questFarmEnabled
            and not bossFarmEnabled then

            clearTarget()
        end
    end
end)

--==================================================
-- QUEST FARM
--==================================================

local QuestFarmBox =
    FarmTab:AddRightGroupbox(
        "Quest Farm"
    )

QuestFarmBox:AddDropdown(
    "QuestSelect",
    {
        Values = QuestData.ORDER,
        Default = 1,
        Multi = false,
        Text = "Quest"
    }
)

QuestFarmBox:AddToggle(
    "QuestFarmEnabled",
    {
        Text = "Start Quest Farm",
        Default = false
    }
)

QuestFarmBox:AddLabel(
    "Selecting a quest does not start farming."
)

QuestFarmBox:AddButton(
    "Quest State Probe",
    function()
        runQuestStateProbe()
    end
)

Options.QuestSelect:OnChanged(function()
    local newQuestName =
        Options.QuestSelect.Value

    if newQuestName
        == selectedQuestName then

        return
    end

    selectedQuestName =
        newQuestName

    questSelectionVersion += 1

    if questFarmEnabled
        and Toggles.QuestFarmEnabled.Value then

        if questNeedsAccept
            or questBusy then

            -- We are between quest cycles. Keep farming enabled and
            -- cancel the old accept attempt through questSelectionVersion.
            -- The accept controller will restart using the new dropdown
            -- selection while preserving any remaining cooldown.
            questNeedsAccept = true
            clearTarget()

            print(
                "[Quest Farm] Next quest switched to:",
                selectedQuestName
            )
        else
            -- Changing quest in the middle of an active quest still
            -- stops the farm so we do not abandon progress accidentally.
            Toggles.QuestFarmEnabled:SetValue(false)
        end
    end

    print(
        "[Quest Farm] Selected:",
        selectedQuestName
    )
end)

Toggles.QuestFarmEnabled:OnChanged(function()
    local requested =
        Toggles.QuestFarmEnabled.Value

    if requested then
        if Toggles.NearbyFarmEnabled
            and Toggles.NearbyFarmEnabled.Value then

            Toggles.NearbyFarmEnabled:SetValue(false)
        end

        questFarmEnabled = true

        if not startQuestFarm() then
            questFarmEnabled = false
            Toggles.QuestFarmEnabled:SetValue(false)
        end
    else
        questFarmEnabled = false
        questNeedsAccept = false
        questBusy = false
        resetQuestProgressTracking()

        if not nearbyFarmEnabled
            and not bossFarmEnabled then

            clearTarget()
        end
    end
end)

--==================================================
-- BOSS FARM
--==================================================

local BossFarmBox =
    FarmTab:AddLeftGroupbox(
        "Boss Farm"
    )

BossFarmBox:AddDropdown(
    "BossSelect",
    {
        Values = BossData.ORDER,
        Default = 1,
        Multi = false,
        Text = "Boss"
    }
)

BossFarmBox:AddToggle(
    "BossFarmEnabled",
    {
        Text = "Watch Boss Spawn",
        Default = false
    }
)

BossFarmBox:AddToggle(
    "BossAutoLootEnabled",
    {
        Text = "Auto Open + Claim Loot",
        Default = true
    }
)

BossFarmBox:AddLabel(
    "Boss overrides the farm target; Auto Loot only claims your drops."
)

Toggles.BossAutoLootEnabled:OnChanged(function()
    bossAutoLootEnabled =
        Toggles.BossAutoLootEnabled.Value

    print(
        "[Boss Loot] Auto Loot:",
        bossAutoLootEnabled
            and "ON"
            or "OFF"
    )
end)

Options.BossSelect:OnChanged(function()
    local newBossName =
        Options.BossSelect.Value

    if newBossName
        == selectedBossName then

        return
    end

    if bossOverrideActive then
        finishBossOverride(
            "boss selection changed"
        )
    end

    selectedBossName =
        newBossName

    runtime.bossSelectionVersion += 1

    local selectionVersion =
        runtime.bossSelectionVersion

    bossScanReadyAt = 0

    if bossFarmEnabled
        and not bossLootBusy
        and not questFarmEnabled then

        task.spawn(function()
            if selectionVersion
                ~= runtime.bossSelectionVersion
                or not bossFarmEnabled then

                return
            end

            local boss =
                BossData.BOSSES[
                    newBossName
                ]

            if boss then
                warpToBossManaged(
                    "BossSelect",
                    boss,
                    Config.BOSS_STREAM_WAIT_TIMEOUT
                )
            end
        end)

    elseif bossLootBusy then
        markRuntimeEvent(
            "BossSelect deferred by loot"
        )

    elseif questFarmEnabled then
        markRuntimeEvent(
            "BossSelect passive during Quest"
        )
    end

    print(
        "[Boss Farm] Selected:",
        selectedBossName
    )
end)

Toggles.BossFarmEnabled:OnChanged(function()
    local requested =
        Toggles.BossFarmEnabled.Value

    if requested then
        bossFarmEnabled = true

        if not startBossFarm() then
            bossFarmEnabled = false
            Toggles.BossFarmEnabled:SetValue(
                false
            )
        end
    else
        bossFarmEnabled = false

        if bossOverrideActive
            or bossLootBusy then

            endBossOverride(
                "disabled"
            )
        end

        if not nearbyFarmEnabled
            and not questFarmEnabled then

            clearTarget()
        end

        print(
            "[Boss Farm] Disabled"
        )
    end
end)


--==================================================
-- STATUS
--==================================================

local StatusBox =
    MainTab:AddLeftGroupbox(
        "Status"
    )

local StatusFarmLabel =
    StatusBox:AddLabel(
        "Farm: initializing..."
    )

local StatusQuestLabel =
    StatusBox:AddLabel(
        "Quest: -"
    )

local StatusBossLabel =
    StatusBox:AddLabel(
        "Boss: -"
    )

local StatusTargetLabel =
    StatusBox:AddLabel(
        "Target: -"
    )

local StatusCombatLabel =
    StatusBox:AddLabel(
        "Combat: -"
    )

local StatusTimingLabel =
    StatusBox:AddLabel(
        "Timing: -"
    )

local StatusOpsLabel =
    StatusBox:AddLabel(
        "Ops: -"
    )

local StatusFlowLabel =
    StatusBox:AddLabel(
        "Flow: -"
    )

local StatusWatchdogLabel =
    StatusBox:AddLabel(
        "Watchdog: -"
    )

local function getStatusAnimationCount()
    local humanoid =
        getHumanoid()

    local animator =
        humanoid
        and humanoid:FindFirstChildOfClass(
            "Animator"
        )

    if not animator then
        return -1
    end

    local ok, tracks =
        pcall(function()
            return animator:GetPlayingAnimationTracks()
        end)

    if ok and type(tracks) == "table" then
        return #tracks
    end

    return -1
end

local function getQuestStatusText()
    if not questFarmEnabled then
        return "OFF"
    end

    if bossLootBusy then
        return "Boss loot"
    end

    if bossOverrideActive then
        return "Boss override"
    end

    if questBusy then
        return "Accepting / NPC"
    end

    if questNeedsAccept then
        local remaining =
            math.max(
                0,
                questAcceptReadyAt
                    - os.clock()
            )

        if remaining > 0 then
            return string.format(
                "Quest cooldown %.1fs",
                remaining
            )
        end

        return "Ready to accept"
    end

    local hold =
        questProgressHoldUntil
            - os.clock()

    if hold > 0 then
        return string.format(
            "Waiting server progress %.2fs",
            hold
        )
    end

    if targetMode == "quest"
        and targetAlive() then

        if targetDown() then
            return "Target down"
        end

        local ready =
            targetReadyAt
                - os.clock()

        if ready > 0 then
            return string.format(
                "Target settle %.2fs",
                ready
            )
        end

        if lockFrames < 2 then
            return "Locking target "
                .. tostring(lockFrames)
                .. "/2"
        end

        return "Fighting"
    end

    return "Searching target"
end

local function getRuntimePhase()
    if runtime.movementOwner then
        return "Move:"
            .. tostring(
                runtime.movementOwner
            )
    end

    if weaponBusy then
        return "Weapon:"
            .. tostring(
                runtime.weaponOperation
            )
    end

    if bossLootBusy then
        return "BossLoot"
    end

    if questBusy then
        return "QuestAccept"
    end

    if questNeedsAccept
        and questFarmEnabled then

        return "QuestWait"
    end

    if targetAlive() then
        return "Combat:"
            .. tostring(
                targetMode or "?"
            )
    end

    if anyFarmEnabled() then
        return "Searching"
    end

    return "Idle"
end

local function updateStatusPanel()
    local farmParts = {}

    if nearbyFarmEnabled then
        table.insert(
            farmParts,
            "Nearby"
        )
    end

    if questFarmEnabled then
        table.insert(
            farmParts,
            "Quest"
        )
    end

    if bossFarmEnabled then
        table.insert(
            farmParts,
            "Boss"
        )
    end

    local farmText =
        #farmParts > 0
            and table.concat(
                farmParts,
                "+"
            )
            or "OFF"

    StatusFarmLabel:SetText(
        "Farm: "
            .. farmText
            .. " | Phase: "
            .. getRuntimePhase()
    )

    local quest =
        QuestData.QUESTS[
            selectedQuestName
        ]

    local required =
        quest
        and quest.requiredKills
        or 0

    local questUiActive =
        questFarmEnabled
        and isSelectedQuestActive()
        or false

    local questCooldown =
        math.max(
            0,
            questAcceptReadyAt
                - os.clock()
        )

    StatusQuestLabel:SetText(
        "Quest: "
            .. tostring(
                selectedQuestName
            )
            .. " "
            .. tostring(
                questKillCount
            )
            .. "/"
            .. tostring(
                required
            )
            .. " | UI:"
            .. tostring(
                questUiActive
            )
            .. " Need:"
            .. tostring(
                questNeedsAccept
            )
            .. " Busy:"
            .. tostring(
                questBusy
            )
            .. " CD:"
            .. string.format(
                "%.1f",
                questCooldown
            )
            .. " | "
            .. getQuestStatusText()
    )

    local bossDefinition =
        BossData.BOSSES[
            selectedBossName
        ]

    local bossSpawned = false

    if bossFarmEnabled
        and bossDefinition then

        bossSpawned =
            findSelectedBossTarget()
                ~= nil
    end

    local bossPassive =
        bossFarmEnabled
        and questFarmEnabled
        and not bossOverrideActive
        and not bossLootBusy

    StatusBossLabel:SetText(
        "Boss: "
            .. tostring(
                selectedBossName
            )
            .. " | Spawn:"
            .. tostring(
                bossSpawned
            )
            .. " Override:"
            .. tostring(
                bossOverrideActive
            )
            .. " Loot:"
            .. tostring(
                bossLootBusy
            )
            .. " Passive:"
            .. tostring(
                bossPassive
            )
            .. " SelV:"
            .. tostring(
                runtime.bossSelectionVersion
            )
    )

    local targetText = "None"
    local distanceText = "-"
    local healthText = "-"
    local blockText = "-"
    local downText = "-"

    if target
        and target.model
        and target.model.Parent then

        targetText =
            target.model.Name

        if target.humanoid
            and target.humanoid.Parent then

            healthText =
                string.format(
                    "%.0f/%.0f",
                    target.humanoid.Health,
                    target.humanoid.MaxHealth
                )
        end

        local blockPoints =
            target.model:GetAttribute(
                "BlockPoints"
            )

        if blockPoints ~= nil then
            blockText =
                tostring(
                    blockPoints
                )
        end

        if targetAlive() then
            downText =
                tostring(
                    targetDown()
                )
        end

        local root =
            getRoot()

        if root
            and target.root
            and target.root.Parent then

            distanceText =
                string.format(
                    "%.1f",
                    (
                        root.Position
                        - target.root.Position
                    ).Magnitude
                )
        end
    end

    StatusTargetLabel:SetText(
        "Target: "
            .. targetText
            .. " ["
            .. tostring(
                targetMode or "-"
            )
            .. "] | HP:"
            .. healthText
            .. " Block:"
            .. blockText
            .. " Dist:"
            .. distanceText
            .. " Down:"
            .. downText
    )

    local comboText = "-"
    local comboValue =
        getActiveComboValue()

    if comboValue
        and comboValue:IsA(
            "ValueBase"
        ) then

        comboText =
            tostring(
                comboValue.Value
            )
    end

    local weaponDrawn =
        currentWeaponName == nil
        or currentWeaponName == "Fist"
        or isWeaponActuallyEquipped(
            currentWeaponName
        )

    local directCombat =
        currentWeaponName ~= nil
        and weaponHasDirectCombat(
            currentWeaponName
        )
        or false

    local combatCache =
        currentWeaponName ~= nil
        and combatArgsByWeapon[
            currentWeaponName
        ] ~= nil
        or false

    StatusCombatLabel:SetText(
        "Weapon: "
            .. tostring(
                currentWeaponName
                    or "-"
            )
            .. " | Mode:"
            .. tostring(
                weaponMode
            )
            .. " Drawn:"
            .. tostring(
                weaponDrawn
            )
            .. " Direct:"
            .. tostring(
                directCombat
            )
            .. " Cache:"
            .. tostring(
                combatCache
            )
            .. " WBusy:"
            .. tostring(
                weaponBusy
            )
            .. " | Z:"
            .. tostring(
                SkillAutomation.GetEnabled(
                    "Z"
                )
            )
            .. " X:"
            .. tostring(
                SkillAutomation.GetEnabled(
                    "X"
                )
            )
            .. " C:"
            .. tostring(
                SkillAutomation.GetEnabled(
                    "C"
                )
            )
            .. " V:"
            .. tostring(
                SkillAutomation.GetEnabled(
                    "V"
                )
            )
            .. " B:"
            .. tostring(
                SkillAutomation.GetEnabled(
                    "B"
                )
            )
    )

    StatusTimingLabel:SetText(
        "Combo:"
            .. comboText
            .. " | Lock:"
            .. tostring(
                lockFrames
            )
            .. " Ready:"
            .. string.format(
                "%.2f",
                math.max(
                    0,
                    targetReadyAt
                        - os.clock()
                )
            )
            .. " | Pos:"
            .. tostring(
                farmPositionMode
            )
            .. "/"
            .. tostring(
                farmHeight
            )
            .. " Anim:"
            .. tostring(
                getStatusAnimationCount()
            )
    )

    local movementAge =
        runtime.movementOwner
        and math.max(
            0,
            os.clock()
                - runtime.movementSince
        )
        or 0

    local weaponAge =
        weaponBusy
        and math.max(
            0,
            os.clock()
                - runtime.weaponSince
        )
        or 0

    StatusOpsLabel:SetText(
        "Ops: Move="
            .. tostring(
                runtime.movementOwner
                    or "Idle"
            )
            .. "("
            .. string.format(
                "%.1f",
                movementAge
            )
            .. "s)"
            .. " Weapon="
            .. tostring(
                runtime.weaponOperation
            )
            .. "("
            .. string.format(
                "%.1f",
                weaponAge
            )
            .. "s)"
            .. " | CharV:"
            .. tostring(
                runtime.characterVersion
            )
            .. " TargetV:"
            .. tostring(
                targetVersion
            )
    )

    StatusFlowLabel:SetText(
        "Flow: Equip=Startup/Change/Respawn"
            .. " | BossResume:"
            .. tostring(
                bossResumeCFrame ~= nil
            )
            .. " | MoveBlocked:"
            .. tostring(
                runtime.movementOwner ~= nil
            )
    )

    StatusWatchdogLabel:SetText(
        "Watchdog: NoProg "
            .. tostring(
                combatNoDamageCycles
            )
            .. "/"
            .. tostring(
                Config.COMBAT_STALL_COMBO_LIMIT
            )
            .. " Stalls:"
            .. tostring(
                combatStallEvents
            )
            .. " | Last:"
            .. tostring(
                runtime.lastEvent
            )
            .. " "
            .. string.format(
                "%.1fs",
                math.max(
                    0,
                    os.clock()
                        - runtime.lastEventAt
                )
            )
    )
end

task.spawn(function()
    while scriptAlive do
        pcall(
            updateStatusPanel
        )

        task.wait(0.20)
    end
end)

--==================================================
-- SYSTEM
--==================================================

local SystemBox =
    MainTab:AddRightGroupbox(
        "System"
    )

SystemBox:AddToggle(
    "AntiAFKEnabled",
    {
        Text = "Anti-AFK",
        Default = false
    }
)

Toggles.AntiAFKEnabled:OnChanged(function()
    antiAfkEnabled =
        Toggles.AntiAFKEnabled.Value
end)

SystemBox:AddLabel(
    "Hide / Show UI"
):AddKeyPicker(
    "MenuKeybind",
    {
        Default = "Delete",
        NoUI = true,
        Text = "Menu Keybind"
    }
)

Library.ToggleKeybind =
    Options.MenuKeybind

SystemBox:AddButton(
    "Rejoin",
    function()
        -- This map is a secured sub-place. Direct client teleports back
        -- into the same place/server require a valid teleport token.
        -- Rejoin through the universe start place instead.
        local HttpService =
            game:GetService("HttpService")

        local requestFn =
            request
            or http_request
            or (syn and syn.request)

        if not requestFn then
            warn(
                "[Rejoin] Secure sub-place detected; HTTP request unavailable."
            )

            player:Kick(
                "Rejoin is restricted in this map. Press Reconnect to join again."
            )

            return
        end

        local rootPlaceId = nil

        local ok, result =
            pcall(function()
                local response =
                    requestFn({
                        Url =
                            "https://games.roblox.com/v1/games?universeIds="
                            .. tostring(game.GameId),
                        Method = "GET"
                    })

                local body =
                    response.Body
                    or response.body

                if not body then
                    error("Universe response has no body")
                end

                local decoded =
                    HttpService:JSONDecode(body)

                local info =
                    decoded
                    and decoded.data
                    and decoded.data[1]

                rootPlaceId =
                    info
                    and info.rootPlaceId
            end)

        if not ok
            or not rootPlaceId then

            warn(
                "[Rejoin] Could not resolve start place:",
                result
            )

            player:Kick(
                "Rejoin is restricted in this map. Press Reconnect to join again."
            )

            return
        end

        if tonumber(rootPlaceId)
            == game.PlaceId then

            warn(
                "[Rejoin] Current place is already the start place; using Reconnect fallback."
            )

            player:Kick(
                "Reconnect to rejoin the experience."
            )

            return
        end

        print(
            "[Rejoin] Secure place -> Start Place:",
            rootPlaceId
        )

        local teleportOk, teleportErr =
            pcall(function()
                TeleportService:Teleport(
                    tonumber(rootPlaceId),
                    player
                )
            end)

        if not teleportOk then
            warn(
                "[Rejoin Error]",
                teleportErr
            )

            player:Kick(
                "Teleport was blocked. Press Reconnect to join again."
            )
        end
    end
)

SystemBox:AddButton(
    "Shutdown Script",
    function()
        Library:Unload()
    end
)

end

setupUI()

--==================================================
-- INPUT
--==================================================

local function setupRuntimeConnections()
local inputBeganConnection =
    UserInputService.InputBegan:Connect(
        function(
            input,
            gameProcessed
        )
            if gameProcessed then
                return
            end

            if input.KeyCode
                == Enum.KeyCode.Space then

                spaceHeld = true
            end
        end
    )

local inputEndedConnection =
    UserInputService.InputEnded:Connect(
        function(input)
            if input.KeyCode
                == Enum.KeyCode.Space then

                spaceHeld = false
            end
        end
    )

Library:GiveSignal(
    inputBeganConnection
)

Library:GiveSignal(
    inputEndedConnection
)

--==================================================
-- ANTI-AFK
--==================================================

local idledConnection =
    player.Idled:Connect(
        function()
            if not antiAfkEnabled then
                return
            end

            local camera =
                workspace.CurrentCamera

            pcall(function()
                VirtualUser:CaptureController()

                if camera then
                    VirtualUser:Button2Down(
                        Vector2.new(0, 0),
                        camera.CFrame
                    )

                    task.wait(0.1)

                    VirtualUser:Button2Up(
                        Vector2.new(0, 0),
                        camera.CFrame
                    )
                end
            end)
        end
    )

Library:GiveSignal(
    idledConnection
)

--==================================================
-- MAIN PLAYER LOOP
--==================================================

local playerHeartbeatConnection =
    RunService.Heartbeat:Connect(
        function()
            if speedEnabled then
                local humanoid =
                    getHumanoid()

                if humanoid
                    and humanoid.WalkSpeed ~= speed then

                    humanoid.WalkSpeed = speed
                end
            end

            if spaceFloatEnabled
                and spaceHeld then

                local root = getRoot()

                if root then
                    local velocity =
                        root.AssemblyLinearVelocity

                    root.AssemblyLinearVelocity =
                        Vector3.new(
                            velocity.X,
                            floatSpeed,
                            velocity.Z
                        )
                end
            end
        end
    )

Library:GiveSignal(
    playerHeartbeatConnection
)

Library:GiveSignal(
    farmHeartbeatConnection
)

--==================================================
-- NOCLIP
--==================================================

local noclipConnection =
    RunService.Stepped:Connect(
        function()
            if not noclipEnabled then
                return
            end

            local character =
                getCharacter()

            if not character then
                return
            end

            for _, object in ipairs(
                character:GetDescendants()
            ) do
                if object:IsA("BasePart") then
                    if originalCollision[object] == nil then
                        originalCollision[object] =
                            object.CanCollide
                    end

                    object.CanCollide = false
                end
            end
        end
    )

Library:GiveSignal(
    noclipConnection
)

--==================================================
-- RESPAWN
--==================================================

local characterConnection =
    player.CharacterAdded:Connect(
        function()
            runtime.characterVersion += 1

            local characterVersion =
                runtime.characterVersion

            markRuntimeEvent(
                "Respawn:"
                    .. tostring(
                        characterVersion
                    )
            )

            currentHumanoid = nil
            table.clear(originalCollision)

            clearTarget()
            bossOverrideActive = false
            bossLootBusy = false
            bossLastPosition = nil
            bossScanReadyAt = 0

            -- Rebuild weapon/combat state after a fresh character.
            -- Cached args contain character-local instances such as
            -- ComboValue, so they must not survive a respawn.
            currentWeaponName = nil
            capturedArgs = nil

            SkillAutomation.Reset()

            table.clear(
                combatArgsByWeapon
            )

            task.wait(
                Config.RESPAWN_RECOVERY_DELAY
            )

            if characterVersion
                ~= runtime.characterVersion
                or not scriptAlive then

                return
            end

            if speedEnabled then
                local humanoid =
                    getHumanoid()

                if humanoid then
                    humanoid.WalkSpeed =
                        speed
                end
            end

            task.spawn(function()
                if characterVersion
                    ~= runtime.characterVersion
                    or not scriptAlive then

                    return
                end

                if questFarmEnabled then
                    local quest =
                        QuestData.QUESTS[
                            selectedQuestName
                        ]

                    if quest then
                        local warped,
                            npcRoot,
                            warpMode =
                            warpToQuestNpc(
                                quest,
                                Config.QUEST_STREAM_WAIT_TIMEOUT
                            )

                        print(
                            "[Quest Farm] Respawn recovery warp:",
                            selectedQuestName,
                            "|",
                            tostring(warpMode),
                            "| npcRoot:",
                            npcRoot ~= nil,
                            "| warped:",
                            warped
                        )
                    end

                    if not syncWeaponForCombat(
                        true
                    ) then

                        warn(
                            "[Quest Farm] Respawn combat initialization pending; recovery will retry"
                        )
                    end

                elseif bossFarmEnabled then
                    local boss =
                        BossData.BOSSES[
                            selectedBossName
                        ]

                    if boss then
                        local warped,
                            bossRoot,
                            warpMode =
                            warpToBossManaged(
                                "RespawnBoss",
                                boss,
                                Config.BOSS_STREAM_WAIT_TIMEOUT
                            )

                        print(
                            "[Boss Farm] Respawn recovery warp:",
                            selectedBossName,
                            "|",
                            tostring(warpMode),
                            "| bossRoot:",
                            bossRoot ~= nil,
                            "| warped:",
                            warped
                        )

                        bossScanReadyAt = 0
                    end

                    if not syncWeaponForCombat(
                        true
                    ) then

                        warn(
                            "[Boss Farm] Respawn combat initialization pending; Auto Weapon recovery will retry"
                        )
                    end

                elseif nearbyFarmEnabled then
                    syncWeaponForCombat(
                        true
                    )
                else
                    ensureEquipSerialized(
                        false,
                        "RespawnIdle"
                    )
                end
            end)
        end
    )

Library:GiveSignal(
    characterConnection
)

end

setupRuntimeConnections()

RuntimeEnv.__WINDYPEAK_ACTIVE_VERSION =
    Config.VERSION

--==================================================
-- CLEANUP
--==================================================

Library:OnUnload(function()
    scriptAlive = false

    if RuntimeEnv.__WINDYPEAK_ACTIVE_VERSION
        == Config.VERSION then

        RuntimeEnv.__WINDYPEAK_ACTIVE_VERSION =
            nil
    end

    disableEverything()

    if targetDiedConnection then
        targetDiedConnection:Disconnect()
        targetDiedConnection = nil
    end

    Library.Unloaded = true

    print(
        "[Player Control] Script shutdown"
    )
end)
