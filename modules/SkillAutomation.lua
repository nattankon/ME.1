-- Auto skill input helper.
-- Current skill keys: Z, X, C, V, B.

local SkillAutomation = {}

local VirtualInputManager =
    game:GetService(
        "VirtualInputManager"
    )

local KEYS = {
    Z = Enum.KeyCode.Z,
    X = Enum.KeyCode.X,
    C = Enum.KeyCode.C,
    V = Enum.KeyCode.V,
    B = Enum.KeyCode.B
}

local ORDER = {
    "Z",
    "X",
    "C",
    "V",
    "B"
}

local enabled = {
    Z = false,
    X = false,
    C = false,
    V = false,
    B = false
}

local nextReadyAt = {
    Z = 0,
    X = 0,
    C = 0,
    V = 0,
    B = 0
}

local cursor = 1
local lastKey = "-"
local lastAt = 0

local function pressKey(
    keyName
)
    local keyCode =
        KEYS[keyName]

    if not keyCode then
        return false
    end

    local ok =
        pcall(function()
            VirtualInputManager:SendKeyEvent(
                true,
                keyCode,
                false,
                game
            )

            task.wait(0.04)

            VirtualInputManager:SendKeyEvent(
                false,
                keyCode,
                false,
                game
            )
        end)

    if ok then
        lastKey = keyName
        lastAt = os.clock()
    end

    return ok
end

function SkillAutomation.SetEnabled(
    keyName,
    value
)
    if enabled[keyName] ~= nil then
        enabled[keyName] =
            value == true
    end
end

function SkillAutomation.GetEnabled(
    keyName
)
    return enabled[keyName] == true
end

function SkillAutomation.AnyEnabled()
    for _, keyName in ipairs(
        ORDER
    ) do
        if enabled[keyName] then
            return true
        end
    end

    return false
end

function SkillAutomation.Try(
    retryDelay
)
    if not SkillAutomation.AnyEnabled() then
        return false, nil
    end

    local now =
        os.clock()

    local delay =
        retryDelay
        or 0.50

    for offset = 0, #ORDER - 1 do
        local index =
            (
                (cursor - 1 + offset)
                % #ORDER
            ) + 1

        local keyName =
            ORDER[index]

        if enabled[keyName]
            and now
                >= (
                    nextReadyAt[keyName]
                    or 0
                ) then

            nextReadyAt[keyName] =
                now + delay

            cursor =
                (index % #ORDER) + 1

            return pressKey(
                keyName
            ),
            keyName
        end
    end

    return false, nil
end

function SkillAutomation.Reset()
    for _, keyName in ipairs(
        ORDER
    ) do
        nextReadyAt[keyName] = 0
    end

    cursor = 1
    lastKey = "-"
    lastAt = 0
end

function SkillAutomation.GetStatus()
    return lastKey,
        lastAt
end

return SkillAutomation
