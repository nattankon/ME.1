-- Boss rotation state helper.
-- Keeps multi-select order stable using BossData.ORDER.

local BossRotation = {}
BossRotation.__index = BossRotation

local function copyList(source)
    local out = {}

    for index, value in ipairs(source) do
        out[index] = value
    end

    return out
end

function BossRotation.new(
    order,
    defaultName
)
    local self =
        setmetatable(
            {
                order = order or {},
                selected = {},
                list = {},
                cursor = 1
            },
            BossRotation
        )

    if defaultName then
        self:SetSelection(
            {
                [defaultName] = true
            }
        )
    end

    return self
end

function BossRotation:GetCurrent()
    return self.list[self.cursor]
end

function BossRotation:GetCount()
    return #self.list
end

function BossRotation:GetPosition()
    if #self.list == 0 then
        return 0, 0
    end

    return self.cursor, #self.list
end

function BossRotation:GetList()
    return copyList(self.list)
end

function BossRotation:Contains(
    bossName
)
    return self.selected[bossName] == true
end

function BossRotation:SetSelection(
    multiValue
)
    local oldCurrent =
        self:GetCurrent()

    local selected = {}
    local list = {}

    if type(multiValue) == "table" then
        for _, bossName in ipairs(
            self.order
        ) do
            if multiValue[bossName] == true then
                selected[bossName] = true
                table.insert(
                    list,
                    bossName
                )
            end
        end
    end

    self.selected = selected
    self.list = list
    self.cursor = 1

    if oldCurrent
        and selected[oldCurrent] then

        for index, bossName in ipairs(
            list
        ) do
            if bossName == oldCurrent then
                self.cursor = index
                break
            end
        end
    end

    return self:GetCurrent()
end

function BossRotation:SetCurrent(
    bossName
)
    for index, name in ipairs(
        self.list
    ) do
        if name == bossName then
            self.cursor = index
            return true
        end
    end

    return false
end

function BossRotation:Advance()
    local count =
        #self.list

    if count == 0 then
        self.cursor = 1
        return nil
    end

    self.cursor =
        (self.cursor % count) + 1

    return self:GetCurrent()
end

function BossRotation:GetDisplayText()
    if #self.list == 0 then
        return "None"
    end

    return table.concat(
        self.list,
        " -> "
    )
end

return BossRotation
