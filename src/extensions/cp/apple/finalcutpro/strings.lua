--- === cp.apple.finalcutpro.strings ===
---
--- The `cp.strings` for I18N lookups related to Final Cut Pro.
--- This has been populated with common lookups for user interface values
--- that appear in Final Cut Pro.

-- NOTE:
-- /usr/bin/grep -r -i -s -F --include=\*.strings 'Undo %@' /System

local require               = require

--local log                   = require "hs.logger".new "fcpStrings"

--local inspect               = require "hs.inspect"
local fs                    = require "hs.fs"

local app                   = require "cp.apple.finalcutpro.app"
local config                = require "cp.config"
local strings               = require "cp.strings"
local localeID              = require "cp.i18n.localeID"

local v                     = require "semver"

local dir                   = fs.dir
local insert                = table.insert
local pathToAbsolute        = fs.pathToAbsolute
local sort                  = table.sort

local mod = {}

local extraPath = config.scriptPath .. "/cp/apple/finalcutpro/strings/"

mod._strings = strings.new()
--------------------------------------------------------------------------------
-- Load the generic macOS strings first, so that any FCPX specific ones
-- can replace any duplicate keys:
--------------------------------------------------------------------------------
:fromPlist("/System/Library/Frameworks/AppKit.framework/Resources/${locale}.lproj/DictationManager.strings") -- Dictation Strings
:fromPlist("/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/Resources/${locale}.lproj/Menus.strings") -- Emoji & Symbols
:fromPlist("/System/Library/Frameworks/Foundation.framework/Versions/C/Resources/${locale}.lproj/Undo.strings") -- System Wide Undo/Redo
:fromPlist("/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Resources/${locale}.lproj/schema.strings") -- Spotlight Strings

--------------------------------------------------------------------------------
-- Load the FCPX specific strings:
--------------------------------------------------------------------------------
:fromPlist("${appPath}/Contents/Frameworks/Flexo.framework/Resources/${locale}.lproj/FFEffectBundleLocalizable.strings")
:fromPlist("${appPath}/Contents/Resources/${locale}.lproj/PELocalizable.strings")
:fromPlist("${appPath}/Contents/Frameworks/Flexo.framework/Resources/${locale}.lproj/FFLocalizable.strings")
:fromPlist("${appPath}/Contents/Frameworks/Ozone.framework/Resources/${locale}.lproj/Localizable.strings") -- Text
:fromPlist("${appPath}/Contents/PlugIns/InternalFiltersXPC.pluginkit/Contents/PlugIns/Filters.bundle/Contents/Resources/${locale}.lproj/Localizable.strings") -- Added for Final Cut Pro 10.4
:fromPlist("${appPath}/Contents/Frameworks/LunaKit.framework/Resources/${locale}.lproj/Commands.strings") -- Command Editor Strings (load last)

--------------------------------------------------------------------------------
-- Load any extra strings we insert via CommandPost:
--------------------------------------------------------------------------------
:fromPlist("${extraPath}/${locale}/${fcpVersion}.strings")

-- toVersion(value) -> semver
-- Function
-- Converts the string/semver value to a semver
--
-- Parameters:
-- * value	- The value to convert
--
-- Returns:
-- * The value as a `semver`, or `nil` if it's not a valid version value.
local function toVersion(value)
    if value then
        return type(value) == "string" and v(value) or value
    end
    return nil
end

mod._versionCache = {}

-- cp.apple.finalcutpro.strings:_versions(locale) -> table
-- Method
-- Returns the list of specific version strings files available for the specified locale.
function mod:_versions(locale)
    locale = localeID(locale)
    local versions = self._versionCache[locale.code]
    if not versions then
        versions = {}
        local stringsPath = extraPath .. locale.code
        local path = pathToAbsolute(stringsPath)
        if path then
            for file in dir(path) do
                if file:sub(-8) == ".strings" then
                    local versionString = file:sub(1, -9)
                    local version = toVersion(versionString)
                    if version then
                        insert(versions, version)
                    end
                end
            end
            sort(versions)
        end
        self._versionCache[locale.code] = versions
    end
    return versions
end

-- cp.ids:_previousVersion([version]) -> semver
-- Method
-- Returns the previous version number that has stored IDs.
--
-- Parameters:
--  * version		- The version number you want to load as a string (i.e. "10.4.0") or a `semver`, or `nil` to use the current version.
--
-- Returns:
--  * A `semver` instance for the previous version.
function mod:_bestVersion(locale, version)
    version = toVersion(version or app:version())

    -- check if we're working with a specific version
    local versions = self:_versions(locale)
    if version == nil then
        return #versions > 0 and versions[#versions] or nil
    end

    local prev = nil

    for _,ver in ipairs(versions) do
        if ver <= version then
            prev = ver
        end
        if ver > version then
            break
        end
    end
    return prev
end

function mod:reset()
    local currentLocale = app:currentLocale()

    self._strings:context({
        appPath = app:path(),
        locale = currentLocale.aliases,
        extraPath = extraPath,
        fcpVersion = self:_bestVersion(currentLocale, app:version())
    })
end

--- cp.apple.finalcutpro.strings:find(key[, locale][, quiet]]) -> string
--- Method
--- Looks up an application string with the specified `key`. If no `context` value is provided, the [current context](#context) is used.
---
--- Parameters:
---  * `key`	- The key to look up.
---  * `locale` - Optional locale to retrieve the key for, if available. May be a `string` or `cp.i18n.localeID`.
---  * `quiet`	- Optional boolean, defaults to `false`. If `true`, no warnings are logged for missing keys.
---
--- Returns:
---  * The requested string or `nil` if the application is not running.
function mod:find(key, locale, quiet)
    if type(locale) == "boolean" then
        quiet = locale
        locale = nil
    end
    local context = nil
    if locale ~= nil then
        locale = localeID(locale)
        context = {
            locale = locale.aliases,
            fcpVersion = self:_bestVersion(locale, app:version())
        }
    end
    return self._strings and self._strings:find(key, context, quiet)
end

--- cp.apple.finalcutpro.strings:findKeys(string[, lang]) -> {string}
--- Method
--- Looks up an application string and returns an array of keys that match. It will take into account current language the app is running in, or use `lang` if provided.
---
--- Parameters:
---  * `string`	- The string to look up.
---  * `lang`	- The language (defaults to current FCPX language).
---
--- Returns:
---  * The array of keys with a matching string.
---
--- Notes:
---  * This method may be very inefficient, since it has to search through every possible key/value pair to find matches. It is not recommended that this is used in production.
function mod:findKeys(string, locale)
    local context
    if locale then
        locale = localeID(locale)
        context = {locale = locale.aliases}
    end
    return self._strings and self._strings:findKeys(string, context)
end

app.currentLocale:watch(function() mod:reset() end, true)
app.version:watch(function() mod:reset() end, true)

return mod
