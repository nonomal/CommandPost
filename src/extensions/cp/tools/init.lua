--- === cp.tools ===
---
--- A collection of handy miscellaneous tools for Lua development.

local require               = require

local log                   = require "hs.logger".new "tools"

local application           = require "hs.application"
local base64                = require "hs.base64"
local eventtap              = require "hs.eventtap"
local fs                    = require "hs.fs"
local geometry              = require "hs.geometry"
local host                  = require "hs.host"
local inspect               = require "hs.inspect"
local keycodes              = require "hs.keycodes"
local mouse                 = require "hs.mouse"
local osascript             = require "hs.osascript"
local screen                = require "hs.screen"
local sound                 = require "hs.sound"
local task                  = require "hs.task"
local text                  = require "hs.text"
local timer                 = require "hs.timer"
local window                = require "hs.window"

local config                = require "cp.config"

local v                     = require "semver"

local attributes            = fs.attributes
local dir                   = fs.dir
local mkdir                 = fs.mkdir
local pathToAbsolute        = fs.pathToAbsolute
local rmdir                 = fs.rmdir
local symlinkAttributes     = fs.symlinkAttributes

local event                 = eventtap.event
local insert                = table.insert
local locale                = host.locale
local map                   = keycodes.map
local usleep                = timer.usleep
local utf16                 = text.utf16

local hs                    = _G["hs"]
local execute               = hs.execute
local processInfo           = hs.processInfo
local getObjectMetatable    = hs.getObjectMetatable

local newKeyEvent           = event.newKeyEvent
local newSystemKeyEvent     = event.newSystemKeyEvent

local tools = {}

-- LEFT_MOUSE_DOWN -> number
-- Constant
-- Left Mouse Down ID.
local LEFT_MOUSE_DOWN = event.types["leftMouseDown"]

-- LEFT_MOUSE_UP -> number
-- Constant
-- Left Mouse Up ID.
local LEFT_MOUSE_UP = event.types["leftMouseUp"]

-- RIGHT_MOUSE_DOWN -> number
-- Constant
-- Right Mouse Down ID.
local RIGHT_MOUSE_DOWN = event.types["rightMouseDown"]

-- RIGHT_MOUSE_UP -> number
-- Constant
-- Right Mouse Up ID.
local RIGHT_MOUSE_UP = event.types["rightMouseUp"]

-- CLICK_STATE -> number
-- Constant
-- Click State ID.
local CLICK_STATE = event.properties.mouseEventClickState

-- DEFAULT_DELAY -> number
-- Constant
-- Default Delay.
local DEFAULT_DELAY = 0

-- string:split(delimiter) -> table
-- Function
-- Splits a string into a table, separated by a separator pattern.
--
-- Parameters:
--  * delimiter - Separator pattern
--
-- Returns:
--  * table
function string:split(delimiter) -- luacheck: ignore
   local list = {}
   local pos = 1
   if string.find("", delimiter, 1) then -- this would result in endless loops
      error("delimiter matches empty string: %s", delimiter)
   end
   while true do
      local first, last = self:find(delimiter, pos)
      if first then -- found?
         insert(list, self:sub(pos, first-1))
         pos = last+1
      else
         insert(list, self:sub(pos))
         break
      end
   end
   return list
end

--- cp.tools.desktopPath() -> string
--- Function
--- Gets the users Desktop Path
---
--- Parameters:
---  * None
---
--- Returns:
---  * The path as a string.
function tools.desktopPath()
    return os.getenv("HOME") .. "/Desktop/"
end

--- cp.tools.urlToFilename(url) -> string
--- Function
--- Converts a URL to a filename.
---
--- Parameters:
---  * url - The URL.
---
--- Returns:
---  * The filename.
function tools.urlToFilename(url)
    local path = url:match("file://(.*)")
    --------------------------------------------------------------------------------
    -- Remove any URL encoding:
    --------------------------------------------------------------------------------
    return path:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
end

--- cp.tools.fileLinesBackward(filename) -> function
--- Function
--- An iterator function that reads a file backwards.
---
--- Parameters:
---  * filename - The file to open in read only mode
---
--- Returns:
---  * An iterator function
---
--- Notes:
---  * This is similar to `io.lines`, but works in reverse.
---  * Example Usage: `for line in cp.tools.fileLinesBackward("file") do print(line) end`
function tools.fileLinesBackward(filename)
    local file = assert(io.open(filename))
    local chunkSize = 4*1024
    local iterator = function() return "" end
    local tail = ""
    local chunkIndex = math.ceil(file:seek("end") / chunkSize)

    return function()
        while true do
            local lineEOL, line = iterator()
            if line and lineEOL and lineEOL ~= "" then
                return line:reverse()
            end
            repeat
                chunkIndex = chunkIndex - 1
                if chunkIndex < 0 then
                    file:close()
                    iterator = function()
                        error('No more lines in file "'..filename..'"', 3)
                    end
                    return
                end
                file:seek("set", chunkIndex * chunkSize)
                local chunk = file:read(chunkSize)
                local pattern = "^(.-"..(chunkIndex > 0 and "\n" or "")..")(.*)"
                local newTail, lines = chunk:match(pattern)
                iterator = lines and (lines..tail):reverse():gmatch"(\n?\r?([^\n]*))"
                tail = newTail or chunk..tail
            until iterator
        end
    end
end

--- cp.tools.between(value, min, max) -> boolean
--- Function
--- Is a value between the minimum and the maximum value?
---
--- Parameters:
---  * value - the value to check
---  * min - the minimum value
---  * max - the maximum value
---
--- Returns:
---  * A boolean
function tools.between(value, min, max)
  return value >= min and value <= max
end

--- cp.tools.appleScriptViaTask(script) -> none
--- Function
--- Triggers an AppleScript command via `hs.task` to avoid potential memory leaks in `hs.osascript.applescript`.
---
--- Parameters:
---  * script - A single line AppleScript.
---
--- Returns:
---  * None
function tools.appleScriptViaTask(script)
    task.new("/usr/bin/osascript", function(exitCode, stdOut, stdError)
        if exitCode ~= 0 then
                log.df("[cp.tools.appleScriptViaTask] An error occured. Exit Code: '%s'. Standard Out: '%s'. Standard Error: '%s'.", exitCode, stdOut, stdError)

        end
    end, {"-e", script}):start()
end

--- cp.tools.secureInputApplicationTitle() -> string
--- Function
--- Gets the title of the first application that has 'Secure Input' enabled.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The application title or `nil` if secure input is not enabled or failed to get a title.
function tools.secureInputApplicationTitle()
    if eventtap.isSecureInputEnabled() then
        local output, status = execute([[ioreg -l -w 0 | grep SecureInput | awk 'BEGIN {FS="[^a-zA-Z0-9]+"} {print $8}' | uniq | xargs -n 1 ps aux]])
        --
        -- Example Output:
        --
        -- USER           PID  %CPU %MEM      VSZ    RSS   TT  STAT STARTED      TIME COMMAND
        -- chrishocking  9033   0.0  0.2 410017056 117632   ??  S    11:48AM   0:01.16 /System/Applications/System Preferences.app/Contents/MacOS/System Preferences
        --
        if output and status then
            local lines = tools.lines(output)
            for id, line in ipairs(lines) do
                if id == 1 and line:sub(1, 4) ~= "USER" then
                    return
                elseif id ~= 1 then
                    local components = line:split(" ")
                    local pid = components and components[3] and tonumber(components[3])
                    local app = pid and application.applicationForPID(pid)
                    return app and app:title()
                end
            end
        end
    end
end

--- cp.tools.escapeTilda(input) -> string
--- Function
--- Escapes a tilda.
---
--- Parameters:
---  * input - The string you want to escape.
---
--- Returns:
---  * A new string or "" if no input is supplied.
function tools.escapeTilda(i)
    return i and string.gsub(i, "`", [[\`]]) or ""
end

--- cp.tools.keyStroke(modifiers, character, app, proper) -> none
--- Function
--- Generates and emits a single keystroke event pair for the supplied keyboard modifiers and character to the application.
---
--- Parameters:
---  * modifiers - A table containing the keyboard modifiers to apply ("fn", "ctrl", "alt", "cmd" or "shift")
---  * character - A string containing a character to be emitted
---  * app - The optional `hs.application` you want to target
---  * proper - Use the "proper" method as per Apple's documentation (defaults to `false`)
---
--- Returns:
---  * None
function tools.keyStroke(modifiers, character, app, proper)
    modifiers = modifiers or {}

    if not proper then
        local cleanedModifiers = {}
        for _, modifier in pairs(modifiers) do
            if modifier == "command" then modifier = "cmd" end
            if modifier == "option" then modifier = "alt" end
            if modifier == "control" then modifier = "ctrl" end
            if modifier == "function" then modifier = "fn" end
            if modifier == "cmd" or modifier == "alt" or modifier == "shift" or modifier == "ctrl" or modifier == "fn" then
                table.insert(cleanedModifiers, modifier)
            end
        end

        newKeyEvent(cleanedModifiers, character, true):post(app)
        newKeyEvent(cleanedModifiers, character, false):post(app)
    else
        --------------------------------------------------------------------------------
        -- NOTE TO FUTURE CHRIS:
        -- According to the Hammerspoon documentation, "the proper way to perform a
        -- keypress with modifiers is through multiple key events", which we were doing
        -- below. However this causes weird issues, where keypresses weren't doing
        -- what they were supposed to, etc. I ASSUME it was just a timing issue.
        -- As of 5th April 2022, the above seems to work as intended on macOS 12.3
        -- and Final Cut Pro 10.6.1.
        --
        -- On 23rd May 2022, Chris realised that some shortcuts (i.e. CONTROL+LEFT)
        -- weren't properly triggering macOS shortcuts (i.e. "Move Left a Space"), so
        -- I've brought this back as an optional feature.
        --------------------------------------------------------------------------------
        local cleanedModifiers = {}
        for _, modifier in pairs(modifiers) do
            if modifier == "command" then modifier = "cmd" end
            if modifier == "option" then modifier = "alt" end
            if modifier == "control" then modifier = "ctrl" end
            if modifier == "function" then modifier = "fn" end
            if modifier == "cmd" or modifier == "alt" or modifier == "shift" or modifier == "ctrl" or modifier == "fn" then
                table.insert(cleanedModifiers, map[modifier])
            end
        end

        for _, modifier in pairs(cleanedModifiers) do
            newKeyEvent(modifier, true):post(app)
        end

        newKeyEvent(character, true):post(app)
        newKeyEvent(character, false):post(app)

        for _, modifier in pairs(cleanedModifiers) do
            newKeyEvent(modifier, false):post(app)
        end
    end
end

--- cp.tools.pressSystemKey(key) -> none
--- Function
--- Virtually presses a system key.
---
--- Parameters:
---  * key - The key to use.
---
--- Returns:
---  * Supported key values are:
---   * SOUND_UP
---   * SOUND_DOWN
---   * MUTE
---   * BRIGHTNESS_UP
---   * BRIGHTNESS_DOWN
---   * CONTRAST_UP
---   * CONTRAST_DOWN
---   * POWER
---   * LAUNCH_PANEL
---   * VIDMIRROR
---   * PLAY
---   * EJECT
---   * NEXT
---   * PREVIOUS
---   * FAST
---   * REWIND
---   * ILLUMINATION_UP
---   * ILLUMINATION_DOWN
---   * ILLUMINATION_TOGGLE
---   * CAPS_LOCK
---   * HELP
---   * NUM_LOCK
function tools.pressSystemKey(key)
    newSystemKeyEvent(key, true):post()
    newSystemKeyEvent(key, false):post()
end

--- cp.tools.shiftPressed() -> boolean
--- Function
--- Is the Shift Key being pressed?
---
--- Parameters:
---  * None
---
--- Returns:
---  * `true` if the shift key is being pressed, otherwise `false`.
function tools.shiftPressed()
    local mods = eventtap.checkKeyboardModifiers()
    if mods['shift'] and not mods['cmd'] and not mods['alt'] and not mods['ctrl'] and not mods['capslock'] and not mods['fn'] then
        return true
    else
        return false
    end
end

--- cp.tools.optionPressed() -> boolean
--- Function
--- Is the Option Key being pressed?
---
--- Parameters:
---  * None
---
--- Returns:
---  * `true` if the option key is being pressed, otherwise `false`.
function tools.optionPressed()
    local mods = eventtap.checkKeyboardModifiers()
    local result = false
    if mods['alt'] and not mods['cmd'] and not mods['shift'] and not mods['ctrl'] and not mods['capslock'] and not mods['fn'] then
        result = true
    end
    return result
end

--- cp.tools.writeToFile(path, data) -> none
--- Function
--- Write data to a file at a given path.
---
--- Parameters:
---  * path - The path to the file you want to write to.
---  * data - The data to write to the file.
---
--- Returns:
---  * None
function tools.writeToFile(path, data)
    local file = io.open(path, "w")
    file:write(data)
    file:close()
end

--- cp.tools.readFromFile(path) -> string
--- Function
--- Read data from file.
---
--- Parameters:
---  * path - The path of where you want to load the file.
---
--- Returns:
---  * None
function tools.readFromFile(path)
    local file = io.open(path, "r")
    if file then
        local data = file:read("*a")
        file:close()
        return data
    end
end

--- cp.tools.toRegionalNumber(value) -> number | nil
--- Function
--- Takes a string and converts it into a number, with the correct regional decimal separator.
---
--- Parameters:
---  * value - The value you want to process as a string.
---
--- Returns:
---  * The value as a number or `nil`.
function tools.toRegionalNumber(value)
    if type(value) == "string" then
        if locale.details().decimalSeparator == "," then
            value = value:gsub("%,", ".")
        end
    end
    value = tonumber(value)
    return value
end

--- cp.tools.toRegionalNumberString(value) -> string | nil
--- Function
--- Takes a number and converts it into a string, with the correct regional decimal separator.
---
--- Parameters:
---  * value - The value you want to process as a number.
---
--- Returns:
---  * The value as a number or `nil`.
function tools.toRegionalNumberString(value)
    if type(value) == "number" then
        value = tostring(value)
        if locale.details().decimalSeparator == "," then
            value = value:gsub("%.", ",")
        end
    end
    return tostring(value)
end

--- cp.tools.rescale(value, inMin, inMax, outMin, outMax) -> number | nil
--- Function
--- Takes an input, rescales it, and provides a new output.
---
--- Parameters:
---  * value - The value you want to process as a number
---  * inMin - The minimum value of the input as a number
---  * inMax - The maximum value of the input as a number
---  * outMin - The minimum value of the output as a number
---  * outMax - The maximum value of the output as a number
---
--- Returns:
---  * The rescaled value as a number or `nil`.
function tools.rescale(value, inMin, inMax, outMin, outMax)
    if value and inMin and inMax and outMin and outMax and
    type(value) == "number" and type(inMin) == "number" and type(inMax) == "number" and type(outMin) == "number" and type(outMax) == "number" and
    value >= inMin and
    value <= inMax then
        return ((value - inMin) / (inMax - inMin) * (outMax - outMin) + outMin)
    end
end

--- cp.tools.getKeysSortedByValue(tbl, sortFunction) -> table
--- Function
--- Sorts table keys by a value
---
--- Parameters:
---  * tbl - the table you want to sort
---  * sortFunction - the function you want to use to sort the table
---
--- Returns:
---  * A sorted table
function tools.getKeysSortedByValue(tbl, sortFunction)
    local keys = {}
    for key in pairs(tbl) do
        insert(keys, key)
    end
    table.sort(keys, function(a, b)
        return sortFunction(tbl[a], tbl[b])
    end)
    return keys
end

--- cp.tools.spairs(t, order) -> function
--- Function
--- A customised version of pairs, called `spairs` because it iterates over the table in a sorted order.
---
--- Parameters:
---  * t     - The table to process
---  * order - The function of how to sort the table.
---
--- Returns:
---  * A iterator function.
---
--- Notes:
---  * Author: [Michal Kottman](https://stackoverflow.com/a/15706820)
---  * Example Usage:
---    ```lua
---    for k,v in cp.tools.spairs(theTableToSort, function(t,a,b) return t[b] < t[a] end) do
---       print(k,v)
---    end
---    ```
function tools.spairs(t, order)
    --------------------------------------------------------------------------------
    -- Collect the keys:
    --------------------------------------------------------------------------------
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    --------------------------------------------------------------------------------
    -- If order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys:
    --------------------------------------------------------------------------------
    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
    else
        table.sort(keys)
    end

    --------------------------------------------------------------------------------
    -- Return the iterator function:
    --------------------------------------------------------------------------------
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end

--- cp.tools.mergeTable(target, ...) -> table
--- Function
--- Merges multiple tables into a target table.
---
--- Parameters:
---  * target   - The target table
---  * ...      - Any other tables you want to merge into target
---
--- Returns:
---  * Table
function tools.mergeTable(target, ...)
    for _,source in ipairs(table.pack(...)) do
        for key,value in pairs(source) do
            local tValue = target[key]
            if type(value) == "table" then
                if type(tValue) ~= "table" then
                    tValue = {}
                end
                --------------------------------------------------------------------------------
                -- Deep Extend Subtables:
                --------------------------------------------------------------------------------
                target[key] = tools.mergeTable(tValue, value)
            else
                target[key] = value
            end
        end
    end
    return target
end

--- cp.tools.volumeFormat(path) -> string
--- Function
--- Gives you the file system volume format of a path.
---
--- Parameters:
---  * path - the path you want to check as a string
---
--- Returns:
---  * The `NSURLVolumeLocalizedFormatDescriptionKey` as a string, otherwise `nil`.
function tools.volumeFormat(path)
    local volumeInformation = host.volumeInformation()
    for volumePath, volumeInfo in pairs(volumeInformation) do
        if string.sub(path, 1, string.len(volumePath)) == volumePath then
            return volumeInfo.NSURLVolumeLocalizedFormatDescriptionKey
        end
    end
    return nil
end

--- cp.tools.unescape(str) -> string
--- Function
--- Removes any URL encoding in the provided string.
---
--- Parameters:
---  * str - the string to decode
---
--- Returns:
---  * A string with all "+" characters converted to spaces and all percent encoded sequences converted to their ASCII equivalents.
function tools.unescape(str)
    return (str:gsub("+", " "):gsub("%%(%x%x)", function(_) return string.char(tonumber(_, 16)) end):gsub("\r\n", "\n"))
end

--- cp.tools.split(str, pat) -> table
--- Function
--- Splits a string with a pattern.
---
--- Parameters:
---  * str - The string to split
---  * pat - The pattern
---
--- Returns:
---  * Table
function tools.split(str, pat)
    local t = {}  -- NOTE: use {n = 0} in Lua-5.0
    local fpat = "(.-)" .. pat
    local last_end = 1
    local s, e, cap = str:find(fpat, 1)
    while s do
      if s ~= 1 or cap ~= "" then
         insert(t,cap)
      end
      last_end = e+1
      s, e, cap = str:find(fpat, last_end)
    end
    if last_end <= #str then
      cap = str:sub(last_end)
      insert(t, cap)
    end
    return t
end

--- cp.tools.findCommonWordWithinTwoStrings(a, b) -> string
--- Function
--- Finds a common word within two strings.
---
--- Parameters:
---  * a - The first string
---  * b - The second string
---
--- Returns:
---  * The first common word that's found or `nil` if something goes wrong.
function tools.findCommonWordWithinTwoStrings(a, b)
    local at = tools.split(a, " ")
    local bt = tools.split(b, " ")
    for _, ar in pairs(at) do
        for _, br in pairs(bt) do
            if ar == br then
                return ar
            end
        end
    end
end

--- cp.tools.isNumberString(value) -> boolean
--- Function
--- Returns whether or not value is a number string.
---
--- Parameters:
---  * value - the string you want to check
---
--- Returns:
---  * `true` if value is a number string, otherwise `false`.
function tools.isNumberString(value)
    return value:match("^[0-9\\.\\-]$") ~= nil
end

--- cp.tools.splitOnColumn() -> string
--- Function
--- Splits a string on a column.
---
--- Parameters:
---  * Input
---
--- Returns:
---  * String
function tools.splitOnColumn(input)
    local space = input:find(': ') or (#input + 1)
    return tools.trim(input:sub(space+1))
end

--- cp.tools.getRAMSize() -> string
--- Function
--- Returns RAM Size in a format Apple's Feedback form expects.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The RAM size as a string, or "" if unknown.
function tools.getRAMSize()
    local memSize = host.vmStat()["memSize"]
    local rounded = tools.round(memSize/1073741824, 0)
    if rounded <= 2 then
        return "2GB"
    elseif rounded >= 3 and rounded <= 4 then
        return "3-4GB"
    elseif rounded >= 5 and rounded <= 8 then
        return "5-8GB"
    elseif rounded >= 9 and rounded <= 16 then
        return "9-16GB"
    elseif rounded >= 17 and rounded <= 32 then
        return "17-32GB"
    elseif rounded == 64 then
        return "64GB"
    elseif rounded == 128 then
        return "128GB"
    elseif rounded > 128 then
        return "Greater than 128GB"
    else
        return ""
    end
end

--- cp.tools.getModelName() -> string
--- Function
--- Returns Model Name of Hardware.
---
--- Parameters:
---  * None
---
--- Returns:
---  * String
function tools.getModelName()
    local output, status = execute([[system_profiler SPHardwareDataType | grep "Model Name"]])
    if status and output then
        local modelName = tools.splitOnColumn(output)
        output, status = execute([[system_profiler SPHardwareDataType | grep "Model Identifier"]])
        if status and output then
            local modelIdentifier = tools.splitOnColumn(output)
            if modelName == "MacBook Pro" then
                local majorVersion = tonumber(string.sub(modelIdentifier, 11, 12))
                local minorVersion = tonumber(string.sub(modelIdentifier, 14, 15))

                --------------------------------------------------------------------------------
                -- 16-inch MacBook Pro (M1 Pro or M1 Max):
                --------------------------------------------------------------------------------
                if majorVersion >= 18 then
                    return "16-inch MacBook Pro (M1 Pro or M1 Max)"
                end

                --------------------------------------------------------------------------------
                -- 16-inch MacBook Pro (Intel):
                --------------------------------------------------------------------------------
                if (majorVersion == 16 and minorVersion == 4)
                or (majorVersion == 16 and minorVersion == 1) then
                    return "16-inch MacBook Pro (Intel)"
                end

                --------------------------------------------------------------------------------
                -- 15-inch MacBook Pro (Intel):
                --------------------------------------------------------------------------------
                if (majorVersion == 11 and minorVersion == 5)
                or (majorVersion == 11 and minorVersion == 4)
                or (majorVersion == 11 and minorVersion == 3)
                or (majorVersion == 11 and minorVersion == 2)
                or (majorVersion == 10 and minorVersion == 1)
                or (majorVersion == 9 and minorVersion == 1) then
                    return "15-inch MacBook Pro"
                end

                --------------------------------------------------------------------------------
                -- 15-inch MacBook Pro (Touch Bar):
                --------------------------------------------------------------------------------
                if (majorVersion == 15 and minorVersion == 1)
                or (majorVersion == 14 and minorVersion == 3)
                or (majorVersion == 13 and minorVersion == 3) then
                    return "15-inch MacBook Pro (Touch Bar)"
                end

                --------------------------------------------------------------------------------
                -- 14-inch MacBook Pro:
                --------------------------------------------------------------------------------
                if (majorVersion == 18 and minorVersion == 4)
                or (majorVersion == 18 and minorVersion == 3) then
                    return "14-inch MacBook Pro"
                end

                --------------------------------------------------------------------------------
                -- 13-inch MacBook Pro (M1):
                --------------------------------------------------------------------------------
                if (majorVersion == 17 and minorVersion == 1) then
                    return "13-inch MacBook Pro (M1)"
                end

                --------------------------------------------------------------------------------
                -- 13-inch MacBook Pro (Touch Bar):
                --------------------------------------------------------------------------------
                if (majorVersion == 16 and minorVersion == 2)
                or (majorVersion == 16 and minorVersion == 3)
                or (majorVersion == 15 and minorVersion == 2)
                or (majorVersion == 15 and minorVersion == 4)
                or (majorVersion == 15 and minorVersion == 3)
                or (majorVersion == 14 and minorVersion == 2)
                or (majorVersion == 14 and minorVersion == 1)
                or (majorVersion == 13 and minorVersion == 2) then
                    return "13-inch MacBook Pro (Touch Bar)"
                end

                --------------------------------------------------------------------------------
                -- 13-inch MacBook Pro (Intel):
                --------------------------------------------------------------------------------
                if (majorVersion == 13 and minorVersion == 1)
                or (majorVersion == 12 and minorVersion == 1)
                or (majorVersion == 11 and minorVersion == 1)
                or (majorVersion == 10 and minorVersion == 2)
                or (majorVersion == 9 and minorVersion == 2) then
                    return "13-inch MacBook Pro (Intel)"
                end

            elseif modelName == "Mac Pro" then
                local majorVersion = tonumber(string.sub(modelIdentifier, 7, 7))
                if majorVersion == 7 then
                    return "Mac Pro (2019)"
                elseif majorVersion >=6 then
                    return "Mac Pro (Late 2013)"
                else
                    return "Mac Pro (Previous generations)"
                end
            elseif modelName == "MacBook Air" then
                local majorVersion = tonumber(string.sub(modelIdentifier, 11, 12))
                if majorVersion >= 10 then
                    return "MacBook Air (M1)"
                else
                    return "MacBook Air (Intel)"
                end
            elseif modelName == "MacBook" then
                return "MacBook"
            elseif modelName == "iMac" then
                local majorVersion = tonumber(string.sub(modelIdentifier, 5, 6))
                if majorVersion >= 21 then
                    return "iMac (M1)"
                else
                    return "iMac (Intel)"
                end
            elseif modelName == "iMac Pro" then
                return "iMac Pro"
            elseif modelName == "Mac mini" then
                local majorVersion = tonumber(string.sub(modelIdentifier, 8, 8))
                if majorVersion >=9 then
                    return "Mac mini (M1)"
                elseif majorVersion >=8 then
                    return "Mac mini (Intel)"
                else
                    return "Mac mini (Previous generations)"
                end
            end
        end
    end
    return ""
end

--- cp.tools.getVRAMSize() -> string
--- Function
--- Returns the VRAM size in format suitable for Apple's Final Cut Pro feedback form or "" if unknown.
---
--- Parameters:
---  * None
---
--- Returns:
---  * String
function tools.getVRAMSize()
    if hs.processInfo.arch == "arm64" then
        --------------------------------------------------------------------------------
        -- Apple Silicon (just use RAM value):
        --------------------------------------------------------------------------------
        local memSize = host.vmStat()["memSize"]
        local rounded = tools.round(memSize/1073741824, 0)
        if rounded < 1 then
            return "Less than 1GB"
        elseif rounded == 1 then
            return "1GB"
        elseif rounded == 2 then
            return "2GB"
        elseif rounded == 4 then
            return "4GB"
        elseif rounded == 8 then
            return "8GB"
        elseif rounded == 16 then
            return "16GB"
        elseif rounded > 16 then
            return "Greater than 16GB"
        end
    else
        --------------------------------------------------------------------------------
        -- Intel:
        --------------------------------------------------------------------------------
        local vram = host.gpuVRAM()
        if vram then
            local result
            for _, value in pairs(vram) do
                if result then
                    if value > result then
                        result = value
                    end
                else
                    result = value
                end
            end
            if result < 1024 then
                return "Less than 1GB"
            elseif result == 1024 then
                return "1GB"
            elseif result == 2048 then
                return "2GB"
            elseif result == 4096 then
                return "4GB"
            elseif result == 8192 then
                return "8GB"
            elseif result == 16384 then
                return "16GB"
            elseif result > 16384 then
                return "Greater than 16GB"
            end
        end
    end

    -- Failing that, return an empty string:
    return ""
end

--- cp.tools.getmacOSVersion() -> string
--- Function
--- Returns the macOS Version in the format that Apple's Feedback Form expects.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The macOS version as a string or "" if unknown.
function tools.getmacOSVersion()
    local macOSVersion = tools.macOSVersion()
    if macOSVersion then
        --------------------------------------------------------------------------------
        -- NOTE: As of 16th March 2022 the FCPX Feedback Form only goes up to
        --       12.2.1.
        --------------------------------------------------------------------------------
        if v(macOSVersion) > v("12.3") then
            --------------------------------------------------------------------------------
            -- macOS Monterey:
            --------------------------------------------------------------------------------
            return ""
        elseif v(macOSVersion) == v("12.3") then
            --------------------------------------------------------------------------------
            -- macOS Monterey 12.3:
            --------------------------------------------------------------------------------
            return "macOS Monterey 12.3"
        elseif v(macOSVersion) == v("12.2.1") then
            --------------------------------------------------------------------------------
            -- macOS Monterey 12.2.1:
            --------------------------------------------------------------------------------
            return "macOS Monterey 12.2.1"
        elseif v(macOSVersion) == v("12.2") then
            --------------------------------------------------------------------------------
            -- macOS Monterey 12.2:
            --------------------------------------------------------------------------------
            return "macOS Monterey 12.2"
        elseif v(macOSVersion) == v("12.1") then
            --------------------------------------------------------------------------------
            -- macOS Monterey 12.1:
            --------------------------------------------------------------------------------
            return "macOS Monterey 12.1"
        elseif v(macOSVersion) == v("12.0.1") then
            --------------------------------------------------------------------------------
            -- macOS Monterey 12.0.1:
            --------------------------------------------------------------------------------
            return "macOS Monterey 12.0.1"
        elseif v(macOSVersion) == v("12") then
            --------------------------------------------------------------------------------
            -- macOS Monterey 12:
            --------------------------------------------------------------------------------
            return "macOS Monterey 12"
        elseif v(macOSVersion) == v("11.6.4") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.6.4:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.6.4"
        elseif v(macOSVersion) == v("11.6.3") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.6.3:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.6.3"
        elseif v(macOSVersion) == v("11.6.2") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.6.2:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.6.2"
        elseif v(macOSVersion) == v("11.6.1") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.6.1:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.6.1"
        elseif v(macOSVersion) == v("11.6") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.6:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.6"
        elseif v(macOSVersion) == v("11.5.2") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.5.2:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.5.2"
        elseif v(macOSVersion) == v("11.5.1") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.5.1:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.5.1"
        elseif v(macOSVersion) == v("11.5") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.5:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.5"
        elseif v(macOSVersion) == v("11.4") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.4:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.4"
        elseif v(macOSVersion) == v("11.3.1") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.3.1:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.3.1"
        elseif v(macOSVersion) == v("11.3") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.3:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.3"
        elseif v(macOSVersion) == v("11.2.3") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.2.3:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.2.3"
        elseif v(macOSVersion) == v("11.2.2") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.2.2:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.2.2"
        elseif v(macOSVersion) == v("11.2.1") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.2.1:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.2.1"
        elseif v(macOSVersion) == v("11.2") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.2:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.2"
        elseif v(macOSVersion) == v("11.1") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.1:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.1"
        elseif v(macOSVersion) == v("11.0.1") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11.0.1:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11.0.1"
        elseif v(macOSVersion) == v("11") then
            --------------------------------------------------------------------------------
            -- macOS Big Sur 11:
            --------------------------------------------------------------------------------
            return "macOS Big Sur 11"
        elseif v(macOSVersion) == v("10.15.7") then
            --------------------------------------------------------------------------------
            -- macOS Catalina 10.15.7:
            --------------------------------------------------------------------------------
            return "macOS Catalina 10.15.7"
        elseif v(macOSVersion) == v("10.15.6") then
            --------------------------------------------------------------------------------
            -- macOS Catalina 10.15.6:
            --------------------------------------------------------------------------------
            return "macOS Catalina 10.15.6"
        elseif v(macOSVersion) == v("10.15.5") then
            --------------------------------------------------------------------------------
            -- macOS Catalina 10.15.5:
            --------------------------------------------------------------------------------
            return "macOS Catalina 10.15.5"
        elseif v(macOSVersion) == v("10.15.4") then
            --------------------------------------------------------------------------------
            -- macOS Catalina 10.15.4:
            --------------------------------------------------------------------------------
            return "macOS Catalina 10.15.4"
        elseif v(macOSVersion) == v("10.15.3") then
            --------------------------------------------------------------------------------
            -- macOS Catalina 10.15.3:
            --------------------------------------------------------------------------------
            return "macOS Catalina 10.15.3"
        elseif v(macOSVersion) == v("10.15.2") then
            --------------------------------------------------------------------------------
            -- macOS Catalina 10.15.2:
            --------------------------------------------------------------------------------
            return "macOS Catalina 10.15.2"
        elseif v(macOSVersion) == v("10.15.1") then
            --------------------------------------------------------------------------------
            -- macOS Catalina 10.15.1:
            --------------------------------------------------------------------------------
            return "macOS Catalina 10.15.1"
        elseif v(macOSVersion) == v("10.15") then
            --------------------------------------------------------------------------------
            -- macOS Catalina 10.15:
            --------------------------------------------------------------------------------
            return "macOS Catalina 10.15"
        elseif v(macOSVersion) == v("10.14.6") then
            --------------------------------------------------------------------------------
            -- macOS Mojave 10.14.6:
            --------------------------------------------------------------------------------
            return "macOS Mojave 10.14.6"
        elseif v(macOSVersion) == v("10.14.5") then
            --------------------------------------------------------------------------------
            -- macOS Mojave 10.14.5:
            --------------------------------------------------------------------------------
            return "macOS Mojave 10.14.5"
        elseif v(macOSVersion) == v("10.14.4") then
            --------------------------------------------------------------------------------
            -- macOS Mojave 10.14.4:
            --------------------------------------------------------------------------------
            return "macOS Mojave 10.14.4"
        elseif v(macOSVersion) == v("10.14.3") then
            --------------------------------------------------------------------------------
            -- macOS Mojave 10.14.2:
            --------------------------------------------------------------------------------
            return "macOS Mojave 10.14.3"
        elseif v(macOSVersion) == v("10.14.2") then
            --------------------------------------------------------------------------------
            -- macOS Mojave 10.14.2:
            --------------------------------------------------------------------------------
            return "macOS Mojave 10.14.2"
        elseif v(macOSVersion) == v("10.14.1") then
            --------------------------------------------------------------------------------
            -- macOS Mojave 10.14.1:
            --------------------------------------------------------------------------------
            return "macOS Mojave 10.14.1"
        elseif v(macOSVersion) == v("10.14") then
            --------------------------------------------------------------------------------
            -- macOS Mojave 10.14:
            --------------------------------------------------------------------------------
            return "macOS Mojave 10.14"
        elseif v(macOSVersion) >= v("10.13") then
            --------------------------------------------------------------------------------
            -- macOS High Sierra 10.13.x:
            --------------------------------------------------------------------------------
            return "macOS High Sierra 10.13.x"
        elseif v(macOSVersion) >= v("10.12") then
            --------------------------------------------------------------------------------
            -- macOS Sierra 10.12.x:
            --------------------------------------------------------------------------------
            return "macOS Sierra 10.12.x"
        elseif v(macOSVersion) >= v("10.11") then
            --------------------------------------------------------------------------------
            -- OS X El Capitan 10.11.x:
            --------------------------------------------------------------------------------
            return "OS X El Capitan 10.11.x"
        elseif v(macOSVersion) >= v("10.10") then
            --------------------------------------------------------------------------------
            -- OS X Yosemite 10.10.x:
            --------------------------------------------------------------------------------
            return "OS X Yosemite 10.10.x"
        elseif v(macOSVersion) >= v("10.9") then
            --------------------------------------------------------------------------------
            -- OS X Mavericks 10.9.x:
            --------------------------------------------------------------------------------
            return "OS X Mavericks 10.9.x"
        elseif v(macOSVersion) >= v("10.8") then
            --------------------------------------------------------------------------------
            -- OS X Mountain Lion 10.8.x:
            --------------------------------------------------------------------------------
            return "OS X Mountain Lion 10.8.x"
        elseif v(macOSVersion) <= v("10.7") then
            --------------------------------------------------------------------------------
            -- OS X Lion 10.7.x or earlier:
            --------------------------------------------------------------------------------
            return "OS X Lion 10.7.x or earlier"
        end
    end
    return ""
end

--- cp.tools.getUSBDevices() -> string
--- Function
--- Returns a string of USB Devices.
---
--- Parameters:
---  * None
---
--- Returns:
---  * String
function tools.getUSBDevices()
    -- "system_profiler SPUSBDataType"
    local output, status = execute("ioreg -p IOUSB -w0 | sed 's/[^o]*o //; s/@.*$//' | grep -v '^Root.*'")
    if output and status then
        local lines = tools.lines(output)
        local result = "USB DEVICES:\n"
        local numberOfDevices = 0
        for _, value in ipairs(lines) do
            numberOfDevices = numberOfDevices + 1
            result = result .. "- " .. value .. "\n"
        end
        if numberOfDevices == 0 then
            result = result .. "- None"
        end
        return result
    else
        return ""
    end
end

--- cp.tools.getThunderboltDevices() -> string
--- Function
--- Returns a string of Thunderbolt Devices.
---
--- Parameters:
---  * None
---
--- Returns:
---  * String
function tools.getThunderboltDevices()
    local output, status = execute([[system_profiler SPThunderboltDataType | grep "Device Name" -B1]])
    if output and status then
        local lines = tools.lines(output)
        local devices = {}
        local currentDevice = 1
        for i, value in ipairs(lines) do
            if value ~= "--" and value ~= "" then
                if devices[currentDevice] == nil then
                    devices[currentDevice] = ""
                end
                devices[currentDevice] = devices[currentDevice] .. value
                if i ~= #lines then
                    devices[currentDevice] = devices[currentDevice] .. "\n"
                end
            else
                currentDevice = currentDevice + 1
            end
        end
        local result = "THUNDERBOLT DEVICES:\n"
        local numberOfDevices = 0
        for _, value in pairs(devices) do
            if string.sub(value, 1, 23) ~= "Vendor Name: Apple Inc." then
                numberOfDevices = numberOfDevices + 1
                local newResult = string.gsub(value, "Vendor Name: ", "- ")
                newResult = string.gsub(newResult, "\nDevice Name: ", ": ")
                result = result .. newResult
            end
        end
        if numberOfDevices == 0 then
            result = result .. "- None"
        end
        return result
    else
        return ""
    end
end

--- cp.tools.getExternalDevices() -> string
--- Function
--- Returns a string of USB & Thunderbolt Devices.
---
--- Parameters:
---  * None
---
--- Returns:
---  * String
function tools.getExternalDevices()
    return tools.getUSBDevices() .. "\n" .. tools.getThunderboltDevices()
end

--- cp.tools.getFullname() -> string
--- Function
--- Returns the current users Full Name, otherwise an empty string.
---
--- Parameters:
---  * None
---
--- Returns:
---  * String
function tools.getFullname()
    local output, status = execute("id -F")
    if output and status then
        return tools.trim(output)
    else
        return ""
    end
end

--- cp.tools.getEmail() -> string
--- Function
--- Returns the current users Email, otherwise an empty string.
---
--- Parameters:
---  * None
---
--- Returns:
---  * String
function tools.getEmail(fullname)
    if not fullname then return "" end
    local contacts = application.get("Contacts")
    local wasRunning = false
    if contacts then
        wasRunning = true
    end
    local appleScript = [[
        tell application "Contacts"
            return value of first email of person "]] .. fullname .. [["
        end tell
    ]]
    local _,result = osascript.applescript(appleScript)
    contacts = application.get("Contacts")
    if contacts and not wasRunning then
        contacts:kill()
    end
    if result then
        return result
    else
        return ""
    end
end

--- cp.tools.urlQueryStringDecode() -> string
--- Function
--- Decodes a URL Query String
---
--- Parameters:
---  * None
---
--- Returns:
---  * Decoded URL Query String as string
function tools.urlQueryStringDecode(s)
    s = s:gsub('+', ' ')
    s = s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
    return string.sub(s, 2, -2)
end

--- cp.tools.getScreenshotsAsBase64() -> table
--- Function
--- Captures all available screens and saves them as base64 encodes in a table.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table containing base64 images of all available screens.
function tools.getScreenshotsAsBase64()
    local screenshots = {}
    local allScreens = screen.allScreens()
    for _, value in ipairs(allScreens) do
        local temporaryFileName = os.tmpname()
        value:shotAsJPG(temporaryFileName)
        execute("sips -Z 1920 " .. temporaryFileName)
        local screenshotFile = io.open(temporaryFileName, "r")
        local screenshotFileContents = screenshotFile:read("*all")
        screenshotFile:close()
        os.remove(temporaryFileName)
        screenshots[#screenshots + 1] = base64.encode(screenshotFileContents)
    end
    return screenshots
end

--- cp.tools.round(num, numDecimalPlaces) -> number
--- Function
--- Rounds a number to a set number of decimal places
---
--- Parameters:
---  * num - The number you want to round
---  * numDecimalPlaces - How many numbers of decimal places (defaults to 0)
---
--- Returns:
---  * A rounded number
function tools.round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

--- cp.tools.isOffScreen(rect) -> boolean
--- Function
--- Determines if the given rect is off screen or not.
---
--- Parameters:
---  * rect - the rect you want to check
---
--- Returns:
---  * `true` if offscreen otherwise `false`
function tools.isOffScreen(rect)
    if rect then
        -- check all the screens
        rect = geometry.new(rect)
        for _,value in ipairs(screen.allScreens()) do
            if rect:inside(value:frame()) then
                return false
            end
        end
        return true
    else
        return true
    end
end

--- cp.tools.safeFilename(value[, defaultValue]) -> string
--- Function
--- Returns a Safe Filename.
---
--- Parameters:
---  * value - a string you want to make safe
---  * defaultValue - the optional default filename to use if the value is not valid
---
--- Returns:
---  * A string of the safe filename
---
--- Notes:
---  * Returns "filename" is both `value` and `defaultValue` are `nil`.
function tools.safeFilename(value, defaultValue)

    --------------------------------------------------------------------------------
    -- Return default value.
    --------------------------------------------------------------------------------
    if not value then
        if defaultValue then
            return defaultValue
        else
            return "filename"
        end
    end

    --------------------------------------------------------------------------------
    -- Trim whitespaces:
    --------------------------------------------------------------------------------
    local result = string.gsub(value, "^%s*(.-)%s*$", "%1")

    --------------------------------------------------------------------------------
    -- Remove Unfriendly Symbols:
    --------------------------------------------------------------------------------
    --result = string.gsub(result, "[^a-zA-Z0-9 ]","") -- This is probably too overkill.
    result = string.gsub(result, ":", "")
    result = string.gsub(result, "/", "")
    result = string.gsub(result, "\"", "")

    --------------------------------------------------------------------------------
    -- Remove Line Breaks:
    --------------------------------------------------------------------------------
    result = string.gsub(result, "\n", "")

    --------------------------------------------------------------------------------
    -- Limit to 243 characters.
    -- See: https://github.com/CommandPost/CommandPost/issues/1004#issuecomment-362986645
    --------------------------------------------------------------------------------
    result = string.sub(result, 1, 243)

    return result

end

--- cp.tools.macOSVersion() -> string
--- Function
--- Returns a the macOS Version as a single string.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string containing the macOS version
function tools.macOSVersion()
    local osVersion = host.operatingSystemVersion()
    local osVersionString = (tostring(osVersion["major"]) .. "." .. tostring(osVersion["minor"]) .. "." .. tostring(osVersion["patch"]))
    return osVersionString
end

--- cp.tools.doesDirectoryExist(path) -> boolean
--- Function
--- Returns whether or not a directory exists.
---
--- Parameters:
---  * path - Path to the directory
---
--- Returns:
---  * `true` if the directory exists otherwise `false`
function tools.doesDirectoryExist(path)
    if path and type(path) == "string" then
        local attr = attributes(path)
        return attr and attr.mode == 'directory'
    else
        return false
    end
end

--- cp.tools.doesFileExist(path) -> boolean
--- Function
--- Returns whether or not a file exists.
---
--- Parameters:
---  * path - Path to the file
---
--- Returns:
---  * `true` if the file exists otherwise `false`
function tools.doesFileExist(path)
    return type(path) == "string" and type(attributes(path)) == "table"
end

--- cp.tools.trim(string) -> string
--- Function
--- Trims the whitespaces from a string
---
--- Parameters:
---  * string - the string you want to trim
---
--- Returns:
---  * A trimmed string
function tools.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

--- cp.tools.lines(string) -> table | nil
--- Function
--- Splits a string containing multiple lines of text into a table.
---
--- Parameters:
---  * string - the string you want to process
---
--- Returns:
---  * A table or `nil` if the parameter is not a string.
function tools.lines(str)
    if str and type(str) == "string" then
        local t = {}
        local function helper(line)
            line = tools.trim(line)
            if line ~= nil and line ~= "" then
                insert(t, line)
            end
            return ""
        end
        helper((str:gsub("(.-)\r?\n", helper)))
        return t
    else
        return nil
    end
end

--- cp.tools.executeWithAdministratorPrivileges(input[, stopOnError]) -> boolean or string
--- Function
--- Executes a single or multiple shell commands with Administrator Privileges.
---
--- Parameters:
---  * input - either a string or a table of strings of commands you want to execute
---  * stopOnError - an optional variable that stops processing multiple commands when an individual commands returns an error
---
--- Returns:
---  * `true` if successful, `false` if cancelled and a string if there's an error.
function tools.executeWithAdministratorPrivileges(input, stopOnError)
    local originalFocusedWindow = window.focusedWindow()
    local whichBundleID = processInfo["bundleID"]
    local fcpBundleID = "com.apple.FinalCut"
    if originalFocusedWindow and originalFocusedWindow:application():bundleID() == fcpBundleID then
        whichBundleID = fcpBundleID
    end
    if type(stopOnError) ~= "boolean" then stopOnError = true end
    if type(input) == "table" then
        local appleScript = [[
            set stopOnError to ]] .. tostring(stopOnError) .. "\n\n" .. [[
            set errorMessage to ""
            set frontmostApplication to (path to frontmost application as text)
            tell application id "]] .. whichBundleID .. [["
                activate
                set shellScriptInputs to ]] .. inspect(input) .. "\n\n" .. [[
                try
                    repeat with theItem in shellScriptInputs
                        try
                            do shell script theItem with administrator privileges
                        on error errStr number errorNumber
                            if the errorNumber is equal to -128 then
                                -- Cancel is pressed:
                                return false
                            else
                                if the stopOnError is equal to true then
                                    tell application frontmostApplication to activate
                                    return errStr as text & "(" & errorNumber as text & ")\n\nWhen trying to execute:\n\n" & theItem
                                else
                                    set errorMessage to errorMessage & "Error: " & errStr as text & "(" & errorNumber as text & "), when trying to execute: " & theItem & ".\n\n"
                                end if
                            end if
                        end try
                    end repeat
                    if the errorMessage is equal to "" then
                        tell application frontmostApplication to activate
                        return true
                    else
                        tell application frontmostApplication to activate
                        return errorMessage
                    end
                end try
            end tell
        ]]
        local _,result = osascript.applescript(appleScript)
        if originalFocusedWindow and whichBundleID == processInfo["bundleID"] then
            originalFocusedWindow:focus()
        end
        return result
    elseif type(input) == "string" then
        local appleScript = [[
            set frontmostApplication to (path to frontmost application as text)
            tell application id "]] .. whichBundleID .. [["
                activate
                set shellScriptInput to "]] .. input .. [["
                try
                    do shell script shellScriptInput with administrator privileges
                    tell application frontmostApplication to activate
                    return true
                on error errStr number errorNumber
                    if the errorNumber is equal to -128 then
                        tell application frontmostApplication to activate
                        return false
                    else
                        tell application frontmostApplication to activate
                        return errStr as text & "(" & errorNumber as text & ")\n\nWhen trying to execute:\n\n" & theItem
                    end if
                end try
            end tell
        ]]
        local _,result = osascript.applescript(appleScript)
        if originalFocusedWindow and whichBundleID == processInfo["bundleID"] then
            originalFocusedWindow:focus()
        end
        return result
    else
        log.ef("ERROR: Expected a Table or String in tools.executeWithAdministratorPrivileges()")
        return nil
    end
end

--- cp.tools.centre(frame) -> hs.geometry point
--- Function
--- Gets the centre point of a frame.
---
--- Parameters:
---  * frame - an `hs.geometry` rect
---
--- Returns:
---  * A hs.geometry point
function tools.centre(frame)
    return {x = frame.x + frame.w/2, y = frame.y + frame.h/2}
end

--- cp.tools.leftClick(point[, delay, clickNumber]) -> none
--- Function
--- Performs a Left Mouse Click.
---
--- Parameters:
---  * point - A point-table containing the absolute x and y co-ordinates to move the mouse pointer to
---  * delay - The optional delay between multiple mouse clicks
---  * clickNumber - The optional number of times you want to perform the click.
---
--- Returns:
---  * None
function tools.leftClick(point, delay, clickNumber)
    delay = delay or DEFAULT_DELAY
    clickNumber = clickNumber or 1
    event.newMouseEvent(LEFT_MOUSE_DOWN, point):setProperty(CLICK_STATE, clickNumber):post()
    if delay > 0 then usleep(delay) end
    event.newMouseEvent(LEFT_MOUSE_UP, point):setProperty(CLICK_STATE, clickNumber):post()
end

--- cp.tools.rightClick(point[, delay, clickNumber]) -> none
--- Function
--- Performs a Right Mouse Click.
---
--- Parameters:
---  * point - A point-table containing the absolute x and y co-ordinates to move the mouse pointer to
---  * delay - The optional delay between multiple mouse clicks
---  * clickNumber - The optional number of times you want to perform the click.
---
--- Returns:
---  * None
function tools.rightClick(point, delay, clickNumber)
    delay = delay or DEFAULT_DELAY
    clickNumber = clickNumber or 1
    event.newMouseEvent(RIGHT_MOUSE_DOWN, point):setProperty(CLICK_STATE, clickNumber):post()
    if delay > 0 then usleep(delay) end
    event.newMouseEvent(RIGHT_MOUSE_UP, point):setProperty(CLICK_STATE, clickNumber):post()
end

--- cp.tools.doubleLeftClick(point[, delay]) -> none
--- Function
--- Performs a Left Mouse Double Click.
---
--- Parameters:
---  * point - A point-table containing the absolute x and y co-ordinates to move the mouse pointer to
---  * delay - The optional delay between multiple mouse clicks
---
--- Returns:
---  * None
function tools.doubleLeftClick(point, delay)
    delay = delay or DEFAULT_DELAY
    tools.leftClick(point, delay, 1)
    tools.leftClick(point, delay, 2)
end

--- cp.tools.ninjaMouseClick(point[, delay]) -> none
--- Function
--- Performs a mouse click, but returns the mouse to the original position without the users knowledge.
---
--- Parameters:
---  * point - A point-table containing the absolute x and y co-ordinates to move the mouse pointer to
---  * delay - The optional delay between multiple mouse clicks
---
--- Returns:
---  * None
function tools.ninjaMouseClick(point, delay)
    delay = delay or DEFAULT_DELAY
    local originalMousePoint = mouse.absolutePosition()
    tools.leftClick(point, delay)
    if delay > 0 then usleep(delay) end
    mouse.absolutePosition(originalMousePoint)
end

--- cp.tools.ninjaRightMouseClick(point[, delay]) -> none
--- Function
--- Performs a right mouse click, but returns the mouse to the original position without the users knowledge.
---
--- Parameters:
---  * point - A point-table containing the absolute x and y co-ordinates to move the mouse pointer to
---  * delay - The optional delay between multiple mouse clicks
---
--- Returns:
---  * None
function tools.ninjaRightMouseClick(point, delay)
    delay = delay or DEFAULT_DELAY
    local originalMousePoint = mouse.absolutePosition()
    tools.rightClick(point, delay)
    if delay > 0 then usleep(delay) end
    mouse.absolutePosition(originalMousePoint)
end

--- cp.tools.ninjaDoubleClick(point[, delay]) -> none
--- Function
--- Performs a mouse double click, but returns the mouse to the original position without the users knowledge.
---
--- Parameters:
---  * point - A point-table containing the absolute x and y co-ordinates to move the mouse pointer to
---  * delay - The optional delay between multiple mouse clicks
---
--- Returns:
---  * None
function tools.ninjaDoubleClick(point, delay)
    delay = delay or DEFAULT_DELAY
    local originalMousePoint = mouse.absolutePosition()
    tools.doubleLeftClick(point, delay)
    if delay > 0 then usleep(delay) end
    mouse.absolutePosition(originalMousePoint)
end

--- cp.tools.ninjaMouseAction(point, fn) -> none
--- Function
--- Moves the mouse to a point, performs a function, then returns the mouse to the original point.
---
--- Parameters:
---  * point - A point-table containing the absolute x and y co-ordinates to move the mouse pointer to
---  * fn - A function you want to perform
---
--- Returns:
---  * None
function tools.ninjaMouseAction(point, fn)
    local originalMousePoint = mouse.absolutePosition()
    mouse.absolutePosition(point)
    fn()
    mouse.absolutePosition(originalMousePoint)
end

--- cp.tools.tableCount(table) -> number
--- Function
--- Returns how many items are in a table.
---
--- Parameters:
---  * table - The table you want to count.
---
--- Returns:
---  * The number of items in the table.
---
--- Notes:
---  * If something other than a table is supplied, this function will return 0.
function tools.tableCount(table)
    if type(table) == "table" then
        local count = 0
        for _ in pairs(table) do count = count + 1 end
        return count
    else
        return 0
    end
end

--- cp.tools.tableContains(table, element) -> boolean
--- Function
--- Does a element exist in a table?
---
--- Parameters:
---  * table - the table you want to check
---  * element - the element you want to check for
---
--- Returns:
---  * Boolean
function tools.tableContains(table, element)
    if not table or not element then
        return false
    end
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end


--- cp.tools.tableFilter(t, matchFn) -> table
--- Function
--- Efficiently filters out all elements from the table `t` which to not match the `matchFn`.
---
--- Parameters:
---  * t - The `table` to filter.
---  * matchFn - A function which will receive the table, the current index, and the target index.
---
--- Returns:
---  * The same table, updated.
---
--- Notes:
---  * This will modify the original table.
function tools.tableFilter(t, matchFn)
    local j, n = 1, #t;

    for i=1,n do
        if (matchFn(t, i, j)) then
            -- Move i's kept value to j's position, if it's not already there.
            if (i ~= j) then
                t[j] = t[i];
                t[i] = nil;
            end
            j = j + 1; -- Increment position of where we'll place the next kept value.
        else
            t[i] = nil;
        end
    end

    return t;
end

--- cp.tools.removeFromTable(table, element) -> table
--- Function
--- Removes a string from a table of strings
---
--- Parameters:
---  * table - the table you want to check
---  * element - the string you want to remove
---
--- Returns:
---  * A table
function tools.removeFromTable(table, element)
    local result = {}
    for _, value in pairs(table) do
        if value ~= element then
            result[#result + 1] = value
        end
    end
    return result
end

--- cp.tools.getFilenameFromPath(input[, removeExtension]) -> string
--- Function
--- Gets the filename component of a path.
---
--- Parameters:
---  * input - The path
---  * removeExtension - (optional) set to `true` if the file extension should be removed
---
--- Returns:
---  * A string of the filename.
function tools.getFilenameFromPath(input, removeExtension)
    if not input then
        log.ef("Input is required for cp.tools.getFilenameFromPath.")
        return nil
    end
    if removeExtension then
        local filename = string.match(input, "[^/]+$")
        return  filename:match("(.+)%..+")
    else
        return string.match(input, "[^/]+$")
    end
end

--- cp.tools.getFileExtensionFromPath(input) -> string
--- Function
--- Gets the file extension from a path.
---
--- Parameters:
---  * input - The path
---
--- Returns:
---  * A string of the file extension.
function tools.getFileExtensionFromPath(path)
    local extension = path and string.match(path, "^.+(%..+)$")
    if extension and extension:sub(1, 1) == "." then
        return extension:sub(2)
    end
end

--- cp.tools.removeFilenameFromPath(string) -> string
--- Function
--- Removes the filename from a path.
---
--- Parameters:
---  * string - The path
---
--- Returns:
---  * A string of the path without the filename.
function tools.removeFilenameFromPath(input)
    return (string.sub(input, 1, (string.find(input, "/[^/]*$"))))
end

--- cp.tools.stringMaxLength(string, maxLength[, optionalEnd]) -> string
--- Function
--- Trims a string based on a maximum length.
---
--- Parameters:
---  * string - The string
---  * maxLength - The length of the string as a number
---  * optionalEnd - A string that is applied to the end of the input string if the input string is larger than the maximum length.
---
--- Returns:
---  * A string
function tools.stringMaxLength(string, maxLength, optionalEnd)

    local result = string
    if maxLength ~= nil and string.len(string) > maxLength then
        result = string.sub(string, 1, maxLength)
        if optionalEnd ~= nil then
            result = result .. optionalEnd
        end
    end
    return result

end

--- cp.tools.cleanupButtonText(value) -> string
--- Function
--- Removes the … symbol and multiple >'s from a string.
---
--- Parameters:
---  * value - A string
---
--- Returns:
---  * A cleaned string
function tools.cleanupButtonText(value)

    --------------------------------------------------------------------------------
    -- Get rid of …
    --------------------------------------------------------------------------------
    value = string.gsub(value, "…", "")

    --------------------------------------------------------------------------------
    -- Only get last value of menu items:
    --------------------------------------------------------------------------------
    if string.find(value, " > ", 1) ~= nil then
        value = string.reverse(value)
        local lastArrow = string.find(value, " > ", 1)
        value = string.sub(value, 1, lastArrow - 1)
        value = string.reverse(value)
    end

    return value

end

--- cp.tools.incrementFilename(value) -> string
--- Function
--- Increments the filename.
---
--- Parameters:
---  * value - A string
---
--- Returns:
---  * A string
function tools.incrementFilename(value)
    if type(value) == "string" then
        local name, counter = string.match(value, '^(.*)%s(%d+)$')
        if name == nil or counter == nil then
            return value .. " 1"
        end
        return name .. " " .. tostring(tonumber(counter) + 1)
    end
end

--- cp.tools.incrementFilenameInPath(path) -> string
--- Function
--- Increments the filename as it appears in a path.
---
--- Parameters:
---  * path - A path to a file.
---
--- Returns:
---  * A string
function tools.incrementFilenameInPath(value)
    if type(value) == "string" then
        local path = tools.removeFilenameFromPath(value)
        local extension = tools.getFileExtensionFromPath(value)
        local filename
        if extension then
            filename = tools.getFilenameFromPath(value, true)
            extension = "." .. extension
        else
            extension = ""
            filename = tools.getFilenameFromPath(value)
        end
        local newFilename = tools.incrementFilename(filename)
        return path .. newFilename .. extension
    end
end

--- cp.tools.dirFiles(path) -> table
--- Function
--- Gets all the files in a directory
---
--- Parameters:
---  * path - A path as string
---
--- Returns:
---  * A table containing filenames as strings, or `nil` followed by the error message if an error occurs.
function tools.dirFiles(path)
    if not path then
        return nil
    end
    path = pathToAbsolute(path)
    if not path then
        return nil
    end
    local contents, data = dir(path)
    if not contents then
        return nil, data
    end
    local files = {}
    for file in function() return contents(data) end do
        files[#files+1] = file
    end
    return files
end

--- cp.tools.rmdir(path[, recursive]) -> true | nil, err
--- Function
--- Attempts to remove the directory at the specified path, optionally removing any contents recursively.
---
--- Parameters:
---  * `path`        - The absolute path to remove
---  * `recursive`   - If `true`, the contents of the directory will be removed first.
---
--- Returns:
---  * `true` if successful, or `nil, err` if there was a problem.
function tools.rmdir(path, recursive)
    if recursive then
        --------------------------------------------------------------------------------
        -- Remove the contents:
        --------------------------------------------------------------------------------
        if tools.doesDirectoryExist(path) then
            for name in dir(path) do
                if name ~= "." and name ~= ".." then
                    local filePath = path .. "/" .. name
                    local attrs = symlinkAttributes(filePath)
                    local ok, err
                    if attrs == nil then
                        return nil, "Unable to find file to remove: "..filePath
                    elseif attrs.mode == "directory" then
                        ok, err = tools.rmdir(filePath, true)
                    else
                        ok, err = os.remove(filePath)
                    end
                    if not ok then
                        return nil, err
                    end
                end
            end
        end
    end
    -- remove the directory itself
    return rmdir(path)
end

--- cp.tools.numberToWord(number) -> string
--- Function
--- Converts a number to a string (i.e. 1 becomes "One").
---
--- Parameters:
---  * number - A whole number between 0 and 10
---
--- Returns:
---  * A string
function tools.numberToWord(number)
    if number == 0 then return "Zero" end
    if number == 1 then return "One" end
    if number == 2 then return "Two" end
    if number == 3 then return "Three" end
    if number == 4 then return "Four" end
    if number == 5 then return "Five" end
    if number == 6 then return "Six" end
    if number == 7 then return "Seven" end
    if number == 8 then return "Eight" end
    if number == 9 then return "Nine" end
    if number == 10 then return "Ten" end
    return nil
end

--- cp.tools.upper(str) -> string
--- Function
--- Converts the supplied string to uppercase.
---
--- Parameters:
---  * str - The string you want to manipulate
---
--- Returns:
---  * A string
function tools.upper(str)
    if type(str) == "string" then
        return tostring(utf16.new(str):upper())
    end
end

--- cp.tools.lower(str) -> string
--- Function
--- Converts the supplied string to lowercase.
---
--- Parameters:
---  * str - The string you want to manipulate
---
--- Returns:
---  * A string
function tools.lower(str)
    if type(str) == "string" then
        return tostring(utf16.new(str):lower())
    end
end

--- cp.tools.camelCase(str) -> string
--- Function
--- Converts the supplied string to camelcase.
---
--- Parameters:
---  * str - The string you want to manipulate
---
--- Returns:
---  * A string
function tools.camelCase(str)
    if type(str) == "string" then
        local result = str:gsub("(%a)([%w_']*)", function(first, rest)
           return tools.upper(first) .. tools.lower(rest)
        end)
        if result then
            return result
        end
    end
end

--- cp.tools.firstToUpper(str) -> string
--- Function
--- Makes the first letter of a string uppercase.
---
--- Parameters:
---  * str - The string you want to manipulate
---
--- Returns:
---  * A string
function tools.firstToUpper(str)
    return (str:gsub("^%l", tools.upper))
end

--- cp.tools.iconFallback(paths) -> string
--- Function
--- Excepts one or more paths to an icon, checks to see if they exist (in the order that they're given), and if none exist, returns the CommandPost icon path.
---
--- Parameters:
---  * paths - One or more paths to an icon
---
--- Returns:
---  * A string
function tools.iconFallback(...)
    for _,path in ipairs(table.pack(...)) do
        if tools.doesFileExist(path) then
            return path
        end
    end
    log.ef("Failed to find icon(s): " .. inspect(table.pack(...)))
    return config.iconPath
end

--- cp.tools.endsWith(str, ending) -> boolean
--- Function
--- Checks to see if `str` has the same ending as `ending`.
---
--- Parameters:
---  * str       - String to analysis
---  * ending    - End of string to compare against
---
--- Returns:
---  * table
function tools.endsWith(str, ending)
    local len = #ending
    return str:len() >= len and str:sub(len * -1) == ending
end

--- cp.tools.ensureDirectoryExists(rootPath, ...) -> string | nil
--- Function
--- Ensures all steps on a provided path exist. If not, attempts to create them. If it fails, `nil` is returned.
---
--- Parameters:
---  * `rootPath` - The root path
---  * `...`      - The list of path steps to create
---
--- Returns:
---  * The full path, if it exists, or `nil` if unable to create the directory for some reason.
function tools.ensureDirectoryExists(rootPath, ...)
    if not tools.doesDirectoryExist(rootPath) then
        local success, err = mkdir(rootPath)
        if not success then
            log.ef("Problem ensuring that '%s' exists: %s", rootPath, err)
            return nil
        end
    end
    local fullPath = rootPath
    for _,path in ipairs(table.pack(...)) do
        fullPath = fullPath .. "/" .. path
        if not pathToAbsolute(fullPath) then
            local success, err = mkdir(fullPath)
            if not success then
                log.ef("Problem ensuring that '%s' exists: %s", fullPath, err)
                return nil
            end
        end
    end
    return pathToAbsolute(fullPath)
end

--- cp.tools.playErrorSound() -> none
--- Function
--- Plays the "Funk" error sound.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function tools.playErrorSound()
    sound.getByName("Funk"):play()
end

--- cp.tools.tableMatch(t1, t2[, ignoreMetatable]) -> boolean
--- Function
--- Compares two tables.
---
--- Parameters:
---  * t1 - The first table.
---  * t2 - The second table.
---  * ignoreMetatable - A boolean that determines whether or not we should ignore the metatable.
---
--- Returns:
---  * `true` if `t1` and `t2` are identical, otherwise `false`.
function tools.tableMatch(t1,t2,ignoreMetatable)
    --------------------------------------------------------------------------------
    -- Compare types:
    --------------------------------------------------------------------------------
    local ty1 = type(t1)
    local ty2 = type(t2)
    if ty1 ~= ty2 then return false end

    --------------------------------------------------------------------------------
    -- Non-table types can be directly compared:
    --------------------------------------------------------------------------------
    if ty1 ~= 'table' and ty2 ~= 'table' then return t1 == t2 end

    --------------------------------------------------------------------------------
    -- As well as tables which have the metamethod __eq:
    --------------------------------------------------------------------------------
    local mt = getmetatable(t1)
    if not ignoreMetatable and mt and mt.__eq then return t1 == t2 end
    for k1,v1 in pairs(t1) do
        local v2 = t2[k1]
        if v2 == nil or not tools.tableMatch(v1,v2) then return false end
    end
    for k2,v2 in pairs(t2) do
        local v1 = t1[k2]
        if v1 == nil or not tools.tableMatch(v1,v2) then return false end
    end
    return true
end

--- cp.tools.convertSingleHexStringToDecimalString(hex) -> string
--- Function
--- Converts a single hex string (i.e. "3") to a binary string (i.e. "0011")
---
--- Parameters:
---  * hex - A single string character
---
--- Returns:
---  * A four character string
function tools.convertSingleHexStringToDecimalString(hex)
    local lookup = {
        ["0"]   = "0000",
        ["1"]   = "0001",
        ["2"]   = "0010",
        ["3"]   = "0011",
        ["4"]   = "0100",
        ["5"]   = "0101",
        ["6"]   = "0110",
        ["7"]   = "0111",
        ["8"]   = "1000",
        ["9"]   = "1001",
        ["A"]   = "1010",
        ["B"]   = "1011",
        ["C"]   = "1100",
        ["D"]   = "1101",
        ["E"]   = "1110",
        ["F"]   = "1111",
    }
    return lookup[hex]
end

--- cp.tools.startsWith(value, startValue) -> boolean
--- Function
--- Checks to see if a string starts with a value.
---
--- Parameters:
---  * value - The value to check
---  * startValue - The value to look for
---
--- Returns:
---  * `true` if value starts with the startValue, otherwise `false`
function tools.startsWith(value, startValue)
    if value and startValue then
        local len = startValue:len()
        if value:len() >= len then
            local sub = value:sub(1, len)
            return sub == startValue
        end
    end
    return false
end

--- cp.tools.exactMatch(value, pattern, plain, ignoreCase) -> boolean
--- Function
--- Compares two strings to see if they're an exact match.
---
--- Parameters:
---  * value - The first string
---  * pattern - The second string, including any patterns
---  * plain - Whether or not to ignore patterns. Defaults to `false`.
---  * ignoreCase - Ignore the case of the value & pattern.
---
--- Returns:
---  * `true` if there's an exact match, otherwise `false`.
function tools.exactMatch(value, pattern, plain, ignoreCase)
    if ignoreCase then
        value = string.lower(value)
        pattern = string.lower(pattern)
    end
    if value and pattern then
        local s,e = value:find(pattern, nil, plain)
        return s == 1 and e == value:len()
    end
    return false
end

--- cp.tools.stringToHexString(value) -> string
--- Function
--- Converts a string to a hex string.
---
--- Parameters:
---  * value - The string to convert
---
--- Returns:
---  * A hex string
function tools.stringToHexString(value)
    local result = ""
    for c in string.gmatch(tostring(value), ".") do
        result = result .. string.format("%02X", string.byte(c))
    end
    return result
end

--- cp.tools.hexStringToString(value) -> string
--- Function
--- Converts a hex string to a string.
---
--- Parameters:
---  * value - The string to convert
---
--- Returns:
---  * A string
function tools.hexStringToString(value)
    local hexToChar = {}
    for idx = 0, 255 do
        hexToChar[("%02X"):format(idx)] = string.char(idx)
        hexToChar[("%02x"):format(idx)] = string.char(idx)
    end
    return value and value:gsub("(..)", hexToChar)
end

--- cp.tools.contentsInsideBrackets(value) -> string | nil
--- Function
--- Gets the contents of any text inside the first bracket set.
---
--- Parameters:
---  * value - The string to process
---
--- Returns:
---  * The contents as a string or `nil`
function tools.contentsInsideBrackets(a)
    --------------------------------------------------------------------------------
    -- Workaround for Chinese:
    --------------------------------------------------------------------------------
    a = a:gsub("）", ")")
    a = a:gsub("（", "(")

    local b = a and string.match(a, "%(.*%)")
    return b and b:sub(2, -2)
end

--- cp.tools.replace(textValue, old, new) -> string
--- Function
--- A find and replace feature that doesn't use patterns.
---
--- Parameters:
---  * textValue - The string you want to process
---  * old - The string you want to find
---  * new - The new string you want to replace the old string with
---
--- Returns:
---  * A new string
function tools.replace(textValue, old, new)

    --[[
    NOTE TO FUTURE CHRIS:

    This is a potential replacement, if this method ever proves to be a performance issue:

    local function replace(str, what, with)
        what = string.gsub(what, "[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1") -- escape pattern
        with = string.gsub(with, "[%%]", "%%%%") -- escape replacement
        return string.gsub(str, what, with)
    end
    --]]

    local b,e = textValue:find(old, 1, true)
    if b == nil then
        return textValue
    else
        local result = textValue:sub(1, b - 1) .. new .. textValue:sub(e + 1)
        return tools.replace(result, old, new)
    end
end

--- cp.tools.isImage(object) -> boolean
--- Function
--- Is the supplied object an `hs.image`?
---
--- Parameters:
---  * object - An object to check
---
--- Returns:
---  * A boolean
function tools.isImage(object)
    return object and getmetatable(object) == getObjectMetatable("hs.image") or false
end

--- cp.tools.isColor(object) -> boolean
--- Function
--- Is the supplied object an `hs.drawing.color`?
---
--- Parameters:
---  * object - An object to check
---
--- Returns:
---  * A boolean
function tools.isColor(object)
    return object and getmetatable(object) == getObjectMetatable("hs.drawing.color") or false
end

--- cp.tools.characterToPercentEncodedString(input) -> string
--- Function
--- Encodes a character as a percent encoded string.
---
--- Parameters:
---  * input - The string to process
---
--- Returns:
---  * A string
function tools.characterToPercentEncodedString(c)
	return string.format("%%%02X", c:byte(1,1))
end

--- cp.tools.encodeURI(input) -> string
--- Function
--- Replaces all characters (except for those listed in the notes) with the appropriate UTF-8 escape sequences.
---
--- Parameters:
---  * input - The string to process
---
--- Returns:
---  * A string
---
--- Notes:
---  * Except these characters: ; , / ? : @ & = + $ # alphabetic, decimal digits, - _ . ! ~ * ' ( )
function tools.encodeURI(str)
	return (str:gsub("[^%;%,%/%?%:%@%&%=%+%$%w%-%_%.%!%~%*%'%(%)%#]", tools.characterToPercentEncodedString))
end

--- cp.tools.encodeURIComponent(input) -> string
--- Function
--- Escapes all characters (except for those listed in the notes) with the appropriate UTF-8 escape sequences.
---
--- Parameters:
---  * input - The string to process
---
--- Returns:
---  * A string
---
--- Notes:
---  * Except these characters: alphabetic, decimal digits, - _ . ! ~ * ' ( )
function tools.encodeURIComponent(str)
	return (str:gsub("[^%w%-_%.%!%~%*%'%(%)]", tools.characterToPercentEncodedString))
end

return tools