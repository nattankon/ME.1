-- WindyPeak stable remote loader.
-- Keep this loader URL/script. Future releases update the manifest/modules on GitHub.

local BASE =
    "https://raw.githubusercontent.com/nattankon/ME.1/main/"

local RuntimeEnv =
    (getgenv and getgenv())
    or _G

if RuntimeEnv.__WINDYPEAK_ACTIVE_VERSION then
    warn(
        "[WindyPeak Loader] Already running:",
        RuntimeEnv.__WINDYPEAK_ACTIVE_VERSION,
        "| use Shutdown Script before re-running the loader"
    )

    return
end

local function cacheBust(path)
    local separator =
        string.find(
            path,
            "?",
            1,
            true
        )
        and "&"
        or "?"

    return path
        .. separator
        .. "cb="
        .. tostring(os.time())
        .. "_"
        .. tostring(
            math.random(
                100000,
                999999
            )
        )
end

local function fetch(path)
    local url =
        cacheBust(
            BASE .. path
        )

    local ok, body =
        pcall(function()
            return game:HttpGet(url)
        end)

    if not ok
        or type(body) ~= "string"
        or body == "" then

        error(
            "[WindyPeak Loader] Failed to fetch "
            .. tostring(path)
            .. ": "
            .. tostring(body)
        )
    end

    return body
end

local function compile(path, source)
    local chunk, err =
        loadstring(source)

    if not chunk then
        error(
            "[WindyPeak Loader] Compile failed for "
            .. tostring(path)
            .. ": "
            .. tostring(err)
        )
    end

    return chunk
end

local manifestSource =
    fetch("manifest.lua")

local manifest =
    compile(
        "manifest.lua",
        manifestSource
    )()

assert(
    type(manifest) == "table"
        and type(manifest.MODULES) == "table"
        and type(manifest.ENTRY) == "string",
    "[WindyPeak Loader] Invalid manifest"
)

local modules = {}

for name, path in pairs(
    manifest.MODULES
) do
    modules[name] =
        compile(
            path,
            fetch(path)
        )()
end

modules.Manifest = manifest

RuntimeEnv.__WINDYPEAK_MODULES =
    modules

local mainChunk =
    compile(
        manifest.ENTRY,
        fetch(
            manifest.ENTRY
        )
    )

local ok, result =
    pcall(mainChunk)

RuntimeEnv.__WINDYPEAK_MODULES =
    nil

if not ok then
    error(
        "[WindyPeak Loader] Main failed: "
        .. tostring(result)
    )
end

print(
    "[WindyPeak Loader] Loaded",
    manifest.VERSION
)

return result
