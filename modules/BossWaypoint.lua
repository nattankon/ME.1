-- Persistent Boss Farm waypoint support.
-- Keeps boss-location persistence out of Main.lua so the main runtime
-- does not grow back toward Luau's local-register limit.

local BossWaypoint = {}

local cache = {}
local loaded = false

local function keyFor(boss)
    return tostring(boss.region)
        .. "|"
        .. tostring(boss.targetName)
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

    return ok and cf or nil
end

local function cframeToArray(cf)
    return {
        cf:GetComponents()
    }
end

local function ensureLoaded(config)
    if loaded then
        return
    end

    loaded = true

    if type(isfile) ~= "function"
        or type(readfile) ~= "function" then

        return
    end

    local ok, decoded =
        pcall(function()
            if not isfile(
                config.BOSS_WAYPOINT_FILE
            ) then

                return nil
            end

            return game:GetService(
                "HttpService"
            ):JSONDecode(
                readfile(
                    config.BOSS_WAYPOINT_FILE
                )
            )
        end)

    if ok and type(decoded) == "table" then
        cache = decoded
    end
end

local function save(config)
    if type(writefile) ~= "function" then
        return
    end

    if type(makefolder) == "function" then
        pcall(
            makefolder,
            config.BOSS_WAYPOINT_FOLDER
        )
    end

    pcall(function()
        writefile(
            config.BOSS_WAYPOINT_FILE,
            game:GetService(
                "HttpService"
            ):JSONEncode(
                cache
            )
        )
    end)
end

local function getBossRoot(
    humanoidRegions,
    boss
)
    local region =
        humanoidRegions:FindFirstChild(
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

    local container =
        activeNpcs:FindFirstChild(
            boss.targetName
        )

    if not container then
        return nil
    end

    if container:IsA("Model") then
        local root =
            container:FindFirstChild(
                "HumanoidRootPart"
            )
            or container.PrimaryPart

        if root then
            return root
        end
    end

    local model =
        container:FindFirstChild(
            boss.targetName
        )

    if model and model:IsA("Model") then
        return model:FindFirstChild(
            "HumanoidRootPart"
        )
            or model.PrimaryPart
    end

    for _, child in ipairs(
        container:GetChildren()
    ) do
        if child:IsA("Model") then
            local root =
                child:FindFirstChild(
                    "HumanoidRootPart"
                )
                or child.PrimaryPart

            if root then
                return root
            end
        end
    end

    return nil
end

function BossWaypoint.Remember(
    config,
    boss,
    cf
)
    ensureLoaded(config)

    if not boss
        or typeof(cf) ~= "CFrame" then

        return false
    end

    local key =
        keyFor(boss)

    if cache[key] then
        return false
    end

    cache[key] =
        cframeToArray(cf)

    save(config)

    print(
        "[Boss Waypoint] Learned:",
        key,
        "|",
        tostring(cf.Position)
    )

    return true
end

function BossWaypoint.GetSavedCFrame(
    config,
    boss
)
    ensureLoaded(config)

    if type(boss.waypoint) == "table"
        and #boss.waypoint >= 3 then

        return CFrame.new(
            boss.waypoint[1],
            boss.waypoint[2],
            boss.waypoint[3]
        )
    end

    return arrayToCFrame(
        cache[
            keyFor(boss)
        ]
    )
end

function BossWaypoint.GetBossRoot(
    humanoidRegions,
    boss
)
    return getBossRoot(
        humanoidRegions,
        boss
    )
end

function BossWaypoint.WarpToBoss(
    config,
    humanoidRegions,
    boss,
    playerRoot,
    height,
    streamTimeout
)
    ensureLoaded(config)

    if not boss then
        return false, nil, "boss"
    end

    if not playerRoot
        or not playerRoot.Parent then

        return false, nil, "player-root"
    end

    local bossRoot =
        getBossRoot(
            humanoidRegions,
            boss
        )

    if bossRoot then
        BossWaypoint.Remember(
            config,
            boss,
            bossRoot.CFrame
        )
    end

    local bossCFrame =
        bossRoot
        and bossRoot.CFrame
        or BossWaypoint.GetSavedCFrame(
            config,
            boss
        )

    if not bossCFrame then
        return false, nil, "no-waypoint"
    end

    local function warp(cf)
        local position =
            cf.Position

        playerRoot.AssemblyLinearVelocity =
            Vector3.zero

        playerRoot.CFrame =
            CFrame.new(
                position
                    + Vector3.new(
                        0,
                        height or 6,
                        0
                    ),
                position
            )
    end

    warp(bossCFrame)

    if not bossRoot
        and (streamTimeout or 0) > 0 then

        local deadline =
            os.clock()
            + streamTimeout

        repeat
            task.wait(0.10)

            bossRoot =
                getBossRoot(
                    humanoidRegions,
                    boss
                )
        until bossRoot
            or os.clock() >= deadline

        if bossRoot then
            BossWaypoint.Remember(
                config,
                boss,
                bossRoot.CFrame
            )

            warp(
                bossRoot.CFrame
            )
        end
    end

    return true,
        bossRoot,
        bossRoot and "live" or "saved"
end

function BossWaypoint.StartAutoLearn(
    config,
    bossData,
    humanoidRegions,
    isAlive
)
    ensureLoaded(config)

    task.spawn(function()
        while isAlive() do
            for _, bossName in ipairs(
                bossData.ORDER
            ) do
                local boss =
                    bossData.BOSSES[
                        bossName
                    ]

                if boss then
                    local root =
                        getBossRoot(
                            humanoidRegions,
                            boss
                        )

                    if root then
                        BossWaypoint.Remember(
                            config,
                            boss,
                            root.CFrame
                        )
                    end
                end
            end

            task.wait(
                config.BOSS_WAYPOINT_SCAN_DELAY
            )
        end
    end)
end

return BossWaypoint
