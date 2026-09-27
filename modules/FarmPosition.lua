-- Farm target positioning.
-- Keeps relative-position math outside Main.lua.

local FarmPosition = {}

FarmPosition.MODES = {
    "Above",
    "Below",
    "Front",
    "Back"
}

function FarmPosition.GetCFrame(
    targetRoot,
    mode,
    distance
)
    if not targetRoot
        or not targetRoot.Parent then

        return nil
    end

    local targetPosition =
        targetRoot.Position

    local offsetDistance =
        tonumber(distance)
        or 6

    local offset

    if mode == "Below" then
        offset =
            Vector3.new(
                0,
                -offsetDistance,
                0
            )

    elseif mode == "Front" then
        offset =
            targetRoot.CFrame.LookVector
            * offsetDistance

    elseif mode == "Back" then
        offset =
            -targetRoot.CFrame.LookVector
            * offsetDistance

    else
        offset =
            Vector3.new(
                0,
                offsetDistance,
                0
            )
    end

    local position =
        targetPosition
        + offset

    return CFrame.new(
        position,
        targetPosition
    )
end

return FarmPosition
