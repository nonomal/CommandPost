--- === cp.app.prefs ===
---
--- Provides access to application preferences, typically stored via `NSUserDefaults` or `CFProperties`.
--- To access the preferences, simply pass in the Bundle ID (eg. "com.apple.Preview") and it will return
--- a table whose keys can be accessed or updated, or iterated via `ipairs`.
---
--- For example:
---
--- ```lua
--- local previewPrefs = require "cp.app.prefs" "com.apple.Preview"
--- previewPrefs.MyCustomPreference = "Hello world"
--- print(previewPrefs.MyCustomPreference) --> "Hello world"
---
--- for k,v in pairs(previewPrefs) do
---     print(k .. " = " .. tostring(v))
--- end
--- ```

local log           = require "hs.logger" .new "prefs"

local require       = require

local cfprefs       = require "hs._asm.cfpreferences"
local pathwatcher   = require "hs.pathwatcher"
local prop          = require "cp.prop"

local class         = require "middleclass"

local mod = class("cp.app.prefs")

local METADATA = {}

local function firstFilePath(bundleID)
    local paths = cfprefs.applicationMap()[bundleID]
    if paths and #paths > 0 then
        local path = paths[1]
        if type(path) == "string" then
            local filePath = string.match(path, "file://(.+)/")
            return filePath or path
        else
            return path.filePath
        end
    end
    return nil
end

local function metadata(self)
    return rawget(self, METADATA)
end

local function prefsPath(self)
    local data = metadata(self)
    local path = data.path
    if not path then
        path = firstFilePath(data.bundleID)
        data.path = path
    end
    return path
end

local function prefsFilePath(self)
    local data = metadata(self)
    local filePath = data.filePath

    --------------------------------------------------------------------------------
    -- If the bundle identifier has a slash in it, it's already a file path.
    -- We pass in a full path instead of just a bundle identifier when working
    -- with sandbox applications (i.e. Final Cut Pro 11).
    --
    -- For example:
    --
    -- /Users/chrishocking/Library/Containers/com.apple.FinalCut/Data/Library/Preferences/com.apple.FinalCut
    --------------------------------------------------------------------------------
    local bundleID = data.bundleID
    if not filePath and bundleID and bundleID:find("/") then
        filePath = bundleID .. ".plist"
        data.filePath = filePath
    end

    if not filePath then
        local path = prefsPath(self)
        if path then
            filePath = path .. "/" .. data.bundleID .. ".plist"
            data.filePath = filePath
        end
    end
    return filePath
end

-- prefsProps(prefs[, create]) -> table
-- Function
-- Finds the `cp.prop` cache for the `prefs`.
--
-- Parameters:
--  * prefs     - The `prefs` instance.
--  * create    - If `true`, create the cache if it doesn't exist already.
--
-- Returns:
--  * A table
local function prefsProps(prefs, create)
    local data = metadata(prefs)
    local cache = data.prefsProps
    if not cache and create then
        cache = {}
        data.prefsProps = cache
    end
    return cache
end

--- cp.app.prefs(bundleID) -> cp.app.prefs
--- Constructor
--- Creates a new `cp.app.prefs` instance, pointing at the specified `bundleID`.
---
--- Parameters:
---  * bundleID      The Bundle ID to access preferences for.
---
--- Returns:
---  * A new `cp.app.prefs` with read/write access to the application's preferences.
function mod:initialize(bundleID)
    rawset(self, METADATA, {
        bundleID = bundleID
    })
end

--- cp.app.prefs.is(thing) -> boolean
--- Function
--- Checks if the `thing` is a `cp.app.prefs` instance.
---
--- Parameters:
---  * thing     - The value to check
---
--- Returns:
---  * `true` if if's a `prefs`, otherwise `false`.
function mod.static.is(thing)
    return type(thing) == "table" and thing.isInstanceOf ~= nil and thing:isInstanceOf(mod)
end

--- cp.app.prefs.bundleID(prefs) -> string
--- Function
--- Retrieves the `bundleID` associated with the `cp.app.prefs` instance.
---
--- Parameters:
---  * prefs     - the `prefs` object to query
---
--- Returns:
---  * The Bundle ID string, or `nil` if it's not a `cp.app.prefs`.
function mod.static.bundleID(prefs)
    if mod.is(prefs) then
        return metadata(prefs).bundleID
    end
end

local PLIST_MATCH = "^.-([^/]+)%.plist*"

local function watchFiles(prefs)
    local data = metadata(prefs)
    if not data.pathwatcher then
        local path = prefsFilePath(prefs)

        if not path then
            log.ef("[cp.app.prefs] Failed to determine property list path for bundle identifier: '%s'", data and data.bundleID)
            return
        end

        data.pathwatcher = pathwatcher.new(path, function(files)
            for _,file in pairs(files) do
                local fileName = file:match(PLIST_MATCH)
                if fileName == data.bundleID then
                    --------------------------------------------------------------------------------
                    -- Update cp.props:
                    --------------------------------------------------------------------------------
                    local props = prefsProps(prefs, false)
                    if props then
                        for _,p in pairs(props) do
                            p:update()
                        end
                    end
                end
            end
        end):start()
    end
end

--- cp.app.prefs.get(prefs, key[, defaultValue]) -> value
--- Function
--- Retrieves the specifed `key` from the provided `prefs`. If there is no current value, the `defaultValue` is returned.
---
--- Parameters:
---  * prefs         - The `prefs` instance.
---  * key           - The key to retrieve.
---  * defaultValue  - The value to return if none is currently set.
---
--- Returns:
---  * The current value, or `defaultValue` if not set.
function mod.static.get(prefs, key, defaultValue)
    local data = metadata(prefs)
    local bundleID = data and data.bundleID
    if bundleID and type(key) == "string" then
        cfprefs.synchronize(bundleID)
        local result = cfprefs.getValue(key, bundleID)
        if type(result) ~= "nil" then
            return result
        end
    end
    return defaultValue
end

--- cp.app.prefs.set(prefs, key, value[, defaultValue]) -> none
--- Function
--- Sets the key/value for the specified `prefs` instance.
---
--- Parameters:
---  * prefs     - The `prefs` instance.
---  * key       - The key to set.
---  * value     - the new value.
---  * defaultValue - The default value.
---
--- Returns:
---  * Nothing.
---
--- Notes:
---  * If the `value` equals the `defaultValue`, the preference is removed rather than being `set`.
function mod.static.set(prefs, key, value, defaultValue)
    local data = metadata(prefs)
    local bundleID = data and data.bundleID
    if bundleID and key then
        if value == defaultValue then
            -- delete the pref if current value is the default value.
            cfprefs.setValue(key, nil, bundleID)
        else
            cfprefs.setValue(key, value, bundleID)
        end
        cfprefs.synchronize(bundleID)

        -- update the cp.prop if it exists.
        local props = prefsProps(prefs, false)
        local keyProp = props and props[key]
        if keyProp then
            keyProp:update()
        end
    end
end

--- cp.app.prefs.prop(prefs, key[, defaultValue[, deepTable]]) -> cp.prop
--- Function
--- Retrieves the `cp.prop` for the specified key. It can be `watched` for changes. Subsequent calls will return the same `cp.prop` instance.
---
--- Parameters:
---  * prefs         - The `prefs` instance.
---  * key           - The key to get/set.
---  * defaultValue  - The value if no default values is currently set (defaults to `nil`).
---  * deepTable     - Should the prop use deep table (defaults to `true`).
---
--- Returns:
---  * The `cp.prop` for the key.
function mod.static.prop(prefs, key, defaultValue, deepTable)
    local props = prefsProps(prefs, true)
    local propValue = props[key]

    if not propValue then
        propValue = prop.new(
            function() return mod.get(prefs, key, defaultValue) end,
            function(value) mod.set(prefs, key, value, defaultValue) end
        ):label(key):preWatch(function() watchFiles(prefs) end)
        if deepTable == true or deepTable == nil then
            propValue:deepTable()
        end
        props[key] = propValue
    end

    return propValue
end

function mod:__index(key)
    if key == "prop" then
        --- cp.app.prefs:prop(key, defaultValue) -> cp.prop
        --- Method
        --- Returns a `cp.prop` for the specified `key`. It can be watched for updates.
        ---
        --- Parameters:
        ---  * key          - The key name for the prop.
        ---  * defaultValue - The value to return if the prop is not currently set.
        ---  * deepTable     - Should the prop use deep table (defaults to `true`).
        ---
        --- Returns:
        ---  * The `cp.prop` for the key.
        return mod.prop
    elseif key == "get" then
        --- cp.app.prefs:get(key, defaultValue) -> anything
        --- Method
        --- Returns the current value for the specified `key`.
        ---
        --- Parameters:
        ---  * key          - The key name for the value.
        ---  * defaultValue - The value to return if not currently set.
        ---
        --- Returns:
        ---  * The value.
        return mod.get
    elseif key == "set" then
        --- cp.app.prefs:set(key, value) -> nil
        --- Method
        --- Sets the value for the specified `key`.
        ---
        --- Parameters:
        ---  * key          - The key to set.
        ---  * value        - The new value.
        ---
        --- Returns:
        ---  * Nothing.
        return mod.set
    end

    return mod.get(self, key)
end

function mod:__newindex(key, value)
    mod.set(self, key, value)
end

function mod:__pairs()
    local keys

    local data = metadata(self)
    local bundleID = data and data.bundleID

    keys = bundleID and cfprefs.keyList(bundleID) or nil
    local i = 0

    local function stateless_iter(_, k)
        local v
        if keys then
            if not keys[i] == k then
                i = nil
                -- loop through keys until we find it
                for j, key in ipairs(keys) do
                    if key == k then
                        i = j
                        break
                    end
                end
                if not i then
                    return nil
                end
            end
            i = i + 1
            k = keys[i]
            if k then
                v = cfprefs.getValue(k, bundleID)
            end
        end
        if k then
            return k, v
        end
    end

    -- Return an iterator function, the table, starting point
    return stateless_iter, self, nil
end

function mod:__tostring()
    local data = metadata(self)
    return "cp.app.prefs: " .. (data and data.bundleID or "<nil>")
end

return mod
