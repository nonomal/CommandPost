--- === cp.apple.finalcutpro ===
---
--- Represents the Final Cut Pro application, providing functions that allow different tasks to be accomplished.
---
--- Generally, you will `require` the `cp.apple.finalcutpro` module to import it, like so:
---
--- ```lua
--- local fcp = require "cp.apple.finalcutpro"
--- ```
---
--- Then, there are the `UpperCase` files, which represent the application itself:
---
---  * `MenuBar` 	            - The main menu bar.
---  * `prefs/PreferencesWindow` - The preferences window.
---  * etc...
---
--- The `fcp` variable is the root application. It has functions which allow you to perform tasks or access parts of the UI. For example, to open the `Preferences` window, you can do this:
---
--- ```lua
--- fcp.preferencesWindow:show()
--- ```
---
--- In general, as long as Final Cut Pro is running, actions can be performed directly, and the API will perform the required operations to achieve it. For example, to toggle the 'Create Optimized Media' checkbox in the 'Import' section of the 'Preferences' window, you can simply do this:
---
--- ```lua
--- fcp.preferencesWindow.importPanel:toggleCreateOptimizedMedia()
--- ```
---
--- The API will automatically open the `Preferences` window, navigate to the 'Import' panel and toggle the checkbox.
---
--- The `UpperCase` classes also have a variety of `UI` methods. These will return the `axuielement` for the relevant GUI element, if it is accessible. If not, it will return `nil`. These allow direct interaction with the GUI if necessary. It's most useful when adding new functions to `UpperCase` files for a particular element.
---
--- This can also be used to 'wait' for an element to be visible before performing a task. For example, if you need to wait for the `Preferences` window to finish loading before doing something else, you can do this with the [just](cp.just.md) library:
---
--- ```lua
--- local just = require "cp.just"
---
--- local prefsWindow = fcp.preferencesWindow
---
--- local prefsUI = just.doUntil(function() return prefsWindow:UI() end)
---
--- if prefsUI then
--- 	-- it's open!
--- else
--- 	-- it's closed!
--- end
--- ```
---
--- By using the `just` library, we can do a loop waiting until the function returns a result that will give up after a certain time period (10 seconds by default).
---
--- Of course, we have a specific support function for that already, so you could do this instead:
---
--- ```lua
--- if fcp.preferencesWindow:isShowing() then
--- 	-- it's open!
--- else
--- 	-- it's closed!
--- end
--- ```
---
---  **Delegates to:** [app](cp.apple.finalcutpro.app.md), [menu](cp.app.menu.md)
---
--- Notes: All values/methods/props from delegates can be accessed directly from the `cp.apple.finalcutpro` instance. For example:
---
--- ```lua
--- fcp.app:UI() == fcp:UI() -- the same `cp.prop` result.
--- ```

local require = require

local log										= require "hs.logger".new "fcp"

local fs 										= require "hs.fs"
local plist                                     = require "hs.plist"
local inspect									= require "hs.inspect"
local notify                                    = require "hs.notify"
local osascript 								= require "hs.osascript"
local pathwatcher                               = require "hs.pathwatcher"

local axutils                                   = require "cp.ui.axutils"
local config                                    = require "cp.config"
local go                                        = require "cp.rx.go"
local i18n                                      = require "cp.i18n"
local just										= require "cp.just"
local localeID                                  = require "cp.i18n.localeID"
local prop										= require "cp.prop"
local Set                                       = require "cp.collect.Set"
local strings                                   = require "cp.strings"
local tools                                     = require "cp.tools"

local commandeditor								= require "cp.apple.commandeditor"

local app                                       = require "cp.apple.finalcutpro.app"
local plugins									= require "cp.apple.finalcutpro.plugins"

local BackgroundTasksDialog                     = require "cp.apple.finalcutpro.main.BackgroundTasksDialog"
local Browser									= require "cp.apple.finalcutpro.main.Browser"
local FullScreenPlayer							= require "cp.apple.finalcutpro.main.FullScreenPlayer"
local KeywordEditor								= require "cp.apple.finalcutpro.main.KeywordEditor"
local PrimaryWindow								= require "cp.apple.finalcutpro.main.PrimaryWindow"
local SecondaryWindow							= require "cp.apple.finalcutpro.main.SecondaryWindow"
local TranscodeMedia                            = require "cp.apple.finalcutpro.main.TranscodeMedia"

local Timeline									= require "cp.apple.finalcutpro.timeline.Timeline"

local Viewer									= require "cp.apple.finalcutpro.viewer.Viewer"

local CommandEditor								= require "cp.apple.finalcutpro.cmd.CommandEditor"
local ExportDialog								= require "cp.apple.finalcutpro.export.ExportDialog"
local MediaImport								= require "cp.apple.finalcutpro.import.MediaImport"
local PreferencesWindow							= require "cp.apple.finalcutpro.prefs.PreferencesWindow"
local FindAndReplaceTitleText	                = require "cp.apple.finalcutpro.main.FindAndReplaceTitleText"

local CommandPostWorkflowExtension              = require "cp.apple.finalcutpro.workflowextensions.CommandPostWindow"

local semver   								    = require "semver"
local class                                     = require "middleclass"
local lazy                                      = require "cp.lazy"
local delegator                                 = require "cp.delegator"

local format     						        = string.format
local gsub                                      = string.gsub

local Do                                        = go.Do
local Throw                                     = go.Throw

local dir                                       = fs.dir
local pathFromBookmark                          = fs.pathFromBookmark
local pathToAbsolute                            = fs.pathToAbsolute
local pathToBookmark                            = fs.pathToBookmark

local dirFiles                                  = tools.dirFiles
local doesDirectoryExist                        = tools.doesDirectoryExist
local stringToHexString                         = tools.stringToHexString
local tableContains                             = tools.tableContains

local childMatching                             = axutils.childMatching
local execute                                   = _G["hs"].execute
local insert                                    = table.insert

-- Load the menu helpers:
require "cp.apple.finalcutpro.menu"

-- a Non-Breaking Space. Looks like a space, isn't a space.
local NBSP = " "

local fcp = class("cp.apple.finalcutpro")
    :include(lazy)
    :include(delegator)
    :delegateTo("app", "menu")

function fcp:initialize()
--- cp.apple.finalcutpro.app <cp.app>
--- Constant
--- The [app](cp.app.md) for Final Cut Pro.
---
--- Notes:
---  * All values from [app](cp.app.md) can be accessed directly from the `finalcutpro` instance.
    self.app = app

--- cp.apple.finalcutpro.preferences <cp.app.prefs>
--- Constant
--- The `cp.app.prefs` for Final Cut Pro.
    self.preferences = app.preferences

--- cp.apple.finalcutpro.strings <cp.strings>
--- Constant
--- The `cp.strings` providing access to common FCPX text values.
    self.strings = require "cp.apple.finalcutpro.strings"

    app:update()

    --------------------------------------------------------------------------------
    -- Refresh Command Set Cache if a Command Set is modified:
    --------------------------------------------------------------------------------
    local userCommandSetPath = fcp.userCommandSetPath()
    if userCommandSetPath then
        --log.df("Setting up User Command Set Watcher: %s", userCommandSetPath)
        self.userCommandSetWatcher = pathwatcher.new(userCommandSetPath .. "/", function()
            --log.df("Updating Final Cut Pro Command Editor Cache.")
            self.activeCommandSet:update()
        end):start()
    end

    --------------------------------------------------------------------------------
    -- Refresh Custom Workspaces Folders:
    --------------------------------------------------------------------------------
    self.customWorkspacesWatcher = pathwatcher.new(fcp.WORKSPACES_PATH .. "/", function()
        self.customWorkspaces:update()
    end):start()

end

-- cleanup
function fcp:__gc()
    if self.userCommandSetWatcher then
        self.userCommandSetWatcher:stop()
        self.userCommandSetWatcher = nil
    end
    if self.customWorkspacesWatcher then
        self.customWorkspacesWatcher:stop()
        self.customWorkspacesWatcher = nil
    end
end

--- cp.apple.finalcutpro.EARLIEST_SUPPORTED_VERSION -> string
--- Constant
--- The earliest version of Final Cut Pro supported by this module.
fcp.EARLIEST_SUPPORTED_VERSION = semver("10.4.4")

--- cp.apple.finalcutpro.PASTEBOARD_UTI -> string
--- Constant
--- Final Cut Pro's Pasteboard UTI
fcp.PASTEBOARD_UTI = "com.apple.flexo.proFFPasteboardUTI"

--- cp.apple.finalcutpro.WORKSPACES_PATH -> string
--- Constant
--- The path to the custom workspaces folder.
fcp.WORKSPACES_PATH = os.getenv("HOME") .. "/Library/Application Support/Final Cut Pro/Workspaces"

--- cp.apple.finalcutpro.EVENT_DESCRIPTION_PATH -> string
--- Constant
--- The Event Description Path.
fcp.EVENT_DESCRIPTION_PATH = "/Contents/Frameworks/TLKit.framework/Versions/A/Resources/EventDescriptions.plist"

--- cp.apple.finalcutpro.FLEXO_LANGUAGES -> table
--- Constant
--- Table of Final Cut Pro's supported Languages for the Flexo Framework
fcp.FLEXO_LANGUAGES	= Set("de", "en", "es_419", "es", "fr", "id", "ja", "ms", "vi", "zh_CN", "ko")

--- cp.apple.finalcutpro.ALLOWED_IMPORT_VIDEO_EXTENSIONS -> table
--- Constant
--- Table of video file extensions Final Cut Pro can import.
fcp.ALLOWED_IMPORT_VIDEO_EXTENSIONS	= Set("3gp", "avi", "mov", "mp4", "mts", "m2ts", "mxf", "m4v", "r3d")

--- cp.apple.finalcutpro.ALLOWED_IMPORT_AUDIO_EXTENSIONS -> table
--- Constant
--- Table of audio file extensions Final Cut Pro can import.
fcp.ALLOWED_IMPORT_AUDIO_EXTENSIONS	= Set("aac", "aiff", "aif", "bwf", "caf", "mp3", "mp4", "wav")

--- cp.apple.finalcutpro.ALLOWED_IMPORT_IMAGE_EXTENSIONS -> table
--- Constant
--- Table of image file extensions Final Cut Pro can import.
fcp.ALLOWED_IMPORT_IMAGE_EXTENSIONS	= Set("bmp", "gif", "jpeg", "jpg", "png", "psd", "raw", "tga", "tiff", "tif")

--- cp.apple.finalcutpro.ALLOWED_IMPORT_EXTENSIONS -> table
--- Constant
--- Table of all file extensions Final Cut Pro can import.
fcp.ALLOWED_IMPORT_ALL_EXTENSIONS = fcp.ALLOWED_IMPORT_VIDEO_EXTENSIONS + fcp.ALLOWED_IMPORT_AUDIO_EXTENSIONS + fcp.ALLOWED_IMPORT_IMAGE_EXTENSIONS

--------------------------------------------------------------------------------
-- Bind the `cp.app` props to the Final Cut Pro instance for easy
-- access/backwards compatibility:
--------------------------------------------------------------------------------

--- cp.apple.finalcutpro.application <cp.prop: hs.application; read-only>
--- Field
--- Returns the running `hs.application` for Final Cut Pro, or `nil` if it's not running.
function fcp.lazy.prop:application()
    return self.app.hsApplication
end

--- cp.apple.finalcutpro.isRunning <cp.prop: boolean; read-only>
--- Field
--- Is Final Cut Pro Running?
function fcp.lazy.prop:isRunning()
    return self.app.running
end

--- cp.apple.finalcutpro.UI <cp.prop: hs.axuielement; read-only; live>
--- Field
--- The Final Cut Pro `axuielement`, if available.

--- cp.apple.finalcutpro.isShowing <cp.prop: boolean; read-only; live>
--- Field
--- Is Final Cut visible on screen?
function fcp.lazy.prop:isShowing()
    return self.app.showing
end

--- cp.apple.finalcutpro.isInstalled <cp.prop: boolean; read-only>
--- Field
--- Is any version of Final Cut Pro Installed?
function fcp.lazy.prop:isInstalled()
    return self.app.installed
end

--- cp.apple.finalcutpro:isFrontmost <cp.prop: boolean; read-only; live>
--- Field
--- Is Final Cut Pro Frontmost?
function fcp.lazy.prop:isFrontmost()
    return self.app.frontmost
end

--- cp.apple.finalcutpro:isModalDialogOpen <cp.prop: boolean; read-only>
--- Field
--- Is a modal dialog currently open?
function fcp.lazy.prop:isModalDialogOpen()
    return self.app.modalDialogOpen
end

--- cp.apple.finalcutpro.isSupported <cp.prop: boolean; read-only; live>
--- Field
--- Is a supported version of Final Cut Pro installed?
---
--- Notes:
---  * Supported version refers to any version of Final Cut Pro equal or higher to `cp.apple.finalcutpro.EARLIEST_SUPPORTED_VERSION`
function fcp.lazy.prop:isSupported()
    return self.app.version:mutate(function(original)
        local version = original()
        return version ~= nil and version >= fcp.EARLIEST_SUPPORTED_VERSION
    end)
end

--- cp.apple.finalcutpro.isUnsupported <cp.prop: boolean; read-only>
--- Field
--- Is an unsupported version of Final Cut Pro installed?
---
--- Notes:
---  * Supported version refers to any version of Final Cut Pro equal or higher to cp.apple.finalcutpro.EARLIEST_SUPPORTED_VERSION
function fcp.lazy.prop:isUnsupported()
    return self.isInstalled:AND(self.isSupported:NOT())
end

--- cp.apple.finalcutpro:mainMenuName() -> string
--- Method
--- Returns the main "Final Cut Pro" menubar label.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string, either "Final Cut Pro" or "Final Cut Pro Trial"
function fcp:mainMenuName()
    local bundleID = self:bundleID()
    if bundleID == "com.apple.FinalCutTrial" then
        return "Final Cut Pro Trial"
    end
    return "Final Cut Pro"
end

--- cp.apple.finalcutpro:string(key[, locale[, quiet]]) -> string
--- Method
--- Looks up an application string with the specified `key`. If no `locale` value is provided, the [current locale](#currentLocale) is used.
---
--- Parameters:
---  * `key`	- The key to look up.
---  * `locale`	- The locale code to use. Defaults to the current locale.
---  * `quiet`	- Optional boolean, defaults to `false`. If `true`, no warnings are logged for missing keys.
---
--- Returns:
---  * The requested string or `nil` if the application is not running.
function fcp:string(key, locale, quiet)
    return self.strings:find(key, locale, quiet)
end

--- cp.apple.finalcutpro:keysWithString(string[, locale]) -> {string}
--- Method
--- Looks up an application string and returns an array of keys that match. It will take into account current locale the app is running in, or use `locale` if provided.
---
--- Parameters:
---  * `key`	- The key to look up.
---  * `locale`	- The locale (defaults to current FCPX locale).
---
--- Returns:
---  * The array of keys with a matching string.
---
--- Notes:
---  * This method may be very inefficient, since it has to search through every possible key/value pair to find matches. It is not recommended that this is used in production.
function fcp:keysWithString(string, locale)
    return self.strings:findKeys(string, locale)
end

--- cp.apple.finalcutpro:getPath() -> string or nil
--- Method
--- Path to Final Cut Pro Application
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string containing Final Cut Pro's filesystem path, or `nil` if Final Cut Pro's path could not be determined.
function fcp:getPath()
    return self.app:path()
end

--- cp.apple.finalcutpro:preferencesPath() -> string or nil
--- Method
--- Path to the Final Cut Pro Preferences file.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string containing Final Cut Pro's Preferences filesystem path, or `nil` if Final Cut Pro's Preferences path could not be determined.
function fcp:preferencesPath()

    local userFolder = pathToAbsolute("~")
    local bundleID = self:bundleID()
    local version = self:version()

    if userFolder and bundleID and version then
        if version >= semver("11.0.0") then
            return string.format("%s/Library/Containers/%s/Data/Library/Preferences/%s.plist", userFolder, bundleID, bundleID)
        else
            return string.format("%s/Library/Preferences/%s.plist", userFolder, bundleID, bundleID)
        end
    end

    return nil
end

----------------------------------------------------------------------------------------
--
-- LIBRARIES
--
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro:activeLibraryPaths() -> table
--- Method
--- Gets a table of all the active library paths.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table containing any active library paths.
function fcp:activeLibraryPaths()
    local paths = {}
    local preferencesPath = self:preferencesPath()
    local fcpPlist = plist.read(preferencesPath)
    local FFActiveLibraries = fcpPlist and fcpPlist.FFActiveLibraries
    if FFActiveLibraries and #FFActiveLibraries >= 1 then
        for i=1, #FFActiveLibraries do
            local activeLibrary = FFActiveLibraries[i]
            local path = pathFromBookmark(activeLibrary)
            if path then
                table.insert(paths, path)
            end
        end
    end
    return paths
end

--- cp.apple.finalcutpro:activeLibraryPaths() -> table
--- Method
--- Gets a table of all the active library paths.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table containing any active library paths.
function fcp:activeLibraryNames()
    local result = {}
    local activeLibraryPaths = self:activeLibraryPaths()
    for _, filename in pairs(activeLibraryPaths) do
        local name = tools.getFilenameFromPath(filename, true)
        if name then
            table.insert(result, name)
        end
    end
    return result
end

--- cp.apple.finalcutpro:recentLibraryPaths() -> table
--- Method
--- Gets a table of all the recent library paths (that are accessible).
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table containing any recent library paths.
function fcp:recentLibraryPaths()
    local paths = {}
    local preferencesPath = self:preferencesPath()
    local fcpPlist = plist.read(preferencesPath)
    local FFRecentLibraries = fcpPlist and fcpPlist.FFRecentLibraries
    if FFRecentLibraries and #FFRecentLibraries >= 1 then
        for i=1, #FFRecentLibraries do
            local recentLibrary = FFRecentLibraries[i]
            local path = pathFromBookmark(recentLibrary)
            if path then
                table.insert(paths, path)
            end
        end
    end
    return paths
end

--- cp.apple.finalcutpro:recentLibraryNames() -> table
--- Method
--- Gets a table of all the recent library names (that are accessible).
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table containing any recent library names.
function fcp:recentLibraryNames()
    local result = {}
    local recentLibraryPaths = self:recentLibraryPaths()
    for _, filename in pairs(recentLibraryPaths) do
        local name = tools.getFilenameFromPath(filename, true)
        if name then
            table.insert(result, name)
        end
    end
    return result
end

--- cp.apple.finalcutpro:openLibrary(path) -> boolean
--- Method
--- Attempts to open a file at the specified absolute `path`.
---
--- Parameters:
---  * path	- The path to the FCP Library to open.
---
--- Returns:
---  * `true` if successful, or `false` if not.
function fcp.openLibrary(_, path)
    assert(type(path) == "string", "Please provide a valid path to the FCP Library.")
    if fs.attributes(path) == nil then
        log.ef("Unable to find an FCP Library file at the provided path: %s", path)
        return false
    end

    local output, ok = os.execute("open '".. path .. "'")
    if not ok then
        log.ef(format("Error while opening the FCP Library at '%s': %s", path, output))
        return false
    end

    return true
end

--- cp.apple.finalcutpro:selectLibrary(title) -> axuielement
--- Method
--- Attempts to select an open library with the specified title.
---
--- Parameters:
---  * title - The title of the library to select.
---
--- Returns:
---  * The library row `axuielement`.
function fcp:selectLibrary(title)
    return self.libraries:selectLibrary(title)
end

--- cp.apple.finalcutpro:closeLibrary(title) -> boolean
--- Method
--- Attempts to close a library with the specified `title`.
---
--- Parameters:
---  * title	- The title of the FCP Library to close.
---
--- Returns:
---  * `true` if successful, or `false` if not.
function fcp:closeLibrary(title)
    if self:isRunning() then
        local libraries = self.libraries
        libraries:show()
        just.doUntil(function() return libraries:isShowing() end, 5.0)
        --------------------------------------------------------------------------------
        -- Waiting here for a couple of seconds seems to make it less likely to
        -- crash Final Cut Pro:
        --------------------------------------------------------------------------------
        just.wait(2.0)
        if libraries:selectLibrary(title) ~= nil then
            just.wait(1.0)
            local closeLibrary = self:string("FFCloseLibraryFormat")
            if closeLibrary then
                -- some languages contain NBSPs instead of spaces, but these don't survive to the actual menu title. Swap them out.
                closeLibrary = gsub(closeLibrary, "%%@", title):gsub(NBSP, " ")
            end

            self:selectMenu({"File", function(item)
                local itemTitle = item:attributeValue("AXTitle"):gsub(NBSP, " ")
                local result = itemTitle == closeLibrary
                return result
            end})
            --------------------------------------------------------------------------------
            -- Wait until the library actually closes, up to 10 seconds:
            --------------------------------------------------------------------------------
            return just.doUntil(function() return libraries:show():selectLibrary(title) == nil end, 10.0)
        end
    end
    return false
end

----------------------------------------------------------------------------------------
--
-- SCAN PLUGINS
--
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro:plugins() -> cp.apple.finalcutpro.plugins
--- Method
--- Returns the plugins manager for the app.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The plugins manager.
function fcp.lazy.method:plugins()
    return plugins.new(self)
end

--- cp.apple.finalcutpro:scanPlugins() -> table
--- Method
--- Scan Final Cut Pro Plugins
---
--- Parameters:
---  * None
---
--- Returns:
---  * A MenuBar object
function fcp:scanPlugins()
    return self:plugins():scan()
end

----------------------------------------------------------------------------------------
--
-- WORKSPACES
--
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro.selectedWorkspace <cp.prop: string; live>
--- Variable
--- The currently selected workspace name. The result is cached, but updated
--- automatically if the window layout changes.
function fcp.lazy.prop:selectedWorkspace()
    return prop(function()
        local workspacesUI = self.menu:findMenuUI({"Window", "Workspaces"})
        local children = workspacesUI and workspacesUI[1] and workspacesUI[1]:attributeValue("AXChildren")
        local selected = children and childMatching(children, function(menuItem)
            return menuItem:attributeValue("AXMenuItemMarkChar") ~= nil
        end)
        return selected and selected:attributeValue("AXTitle")
    end)
    :cached()
    :monitor(self.app.windowsUI)
end

-- WORKSPACE_FILE_EXTENSION -> string
-- Constant
-- The file extension of a custom workspace extension file.
local WORKSPACE_FILE_EXTENSION = "fcpworkspace"

-- SAVED_WORKSPACE -> string
-- Constant
-- The file name of the internally saved Final Cut Pro workspace.
local SAVED_WORKSPACE = "Final Cut Pro.saved.fcpworkspace"

-- DISPLAY_NAME -> string
-- Constant
-- The Property List key that holds the Display Name.
local DISPLAY_NAME = "Display Name"

--- cp.apple.finalcutpro:customWorkspaces <cp.prop: table; live>
--- Variable
--- A table containing the display names of all the user created custom workspaces.
function fcp.lazy.prop.customWorkspaces()
    return prop(function()
        local result = {}
        local path = fcp.WORKSPACES_PATH
        local files = dirFiles(path)
        if files then
            for _, file in pairs(files) do
                if file ~= SAVED_WORKSPACE and file:sub((WORKSPACE_FILE_EXTENSION:len() + 1) * -1) == "." .. WORKSPACE_FILE_EXTENSION then
                    local data =  plist.read(path .. "/" .. file)
                    if data and data[DISPLAY_NAME] then
                        insert(result, data[DISPLAY_NAME])
                    end
                end
            end
        end
        return result
    end)
    :cached()
end

----------------------------------------------------------------------------------------
--
-- WORKFLOW EXTENSIONS
--
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro.workflowExtensionNames() -> table
--- Function
--- Gets the names of all the installed Workflow Extensions.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table of Workflow Extension names
function fcp.workflowExtensionNames()
    local result = {}

    ----------------------------------------------------------------------------------------
    -- The original Workflow Extension format (.pluginkit)
    ----------------------------------------------------------------------------------------
    local output, status = execute("pluginkit -m -v -p FxPlug")
    if status then
        local p = tools.lines(output)
        if p then
            for _, plugin in pairs(p) do
                local params = tools.split(plugin, "\t")
                local path = params[4]
                if path then
                    if tools.doesDirectoryExist(path) then
                        local plistPath = path .. "/Contents/Info.plist"
                        local plistData = plist.read(plistPath)
                        if plistData and plistData.PlugInKit and plistData.PlugInKit.Protocol and plistData.PlugInKit.Protocol == "ProServiceRemoteProtocol" then
                            local pluginName = plistData.CFBundleDisplayName
                            if pluginName then
                                table.insert(result, pluginName)
                            end
                        end
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------------------------------
    -- Modern Workflow Extensions (.appex):
    ----------------------------------------------------------------------------------------
    output, status = execute("pluginkit -m -v -p com.apple.FinalCut.WorkflowExtension")
    if status then
        local p = tools.lines(output)
        if p then
            for _, plugin in pairs(p) do
                local params = tools.split(plugin, "\t")
                local path = params[4]
                if path then
                    if tools.doesDirectoryExist(path) then
                        local plistPath = path .. "/Contents/Info.plist"
                        local plistData = plist.read(plistPath)
                        if plistData then
                            local pluginName = plistData.CFBundleName or plistData.CFBundleDisplayName
                            if pluginName then
                                if not tableContains(pluginName) then
                                    table.insert(result, pluginName)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return result
end

--- cp.apple.finalcutpro.commandPostWorkflowExtension <CommandPostWindow>
--- Field
--- The CommandPost Workflow Extension window.
function fcp.lazy.value:commandPostWorkflowExtension()
    return CommandPostWorkflowExtension(self)
end

----------------------------------------------------------------------------------------
--
-- WINDOWS
--
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro.preferencesWindow <PreferencesWindow>
--- Field
--- The Final Cut Pro Preferences Window
function fcp.lazy.value:preferencesWindow()
    return PreferencesWindow(self)
end

--- cp.apple.finalcutpro.primaryWindow <cp.apple.finalcutpro.main.PrimaryWindow>
--- Field
--- The Final Cut Pro Primary Window
function fcp.lazy.value:primaryWindow()
    return PrimaryWindow(self)
end

--- cp.apple.finalcutpro.secondaryWindow <cp.apple.finalcutpro.main.SecondaryWindow>
--- Field
--- The Final Cut Pro Preferences Window
function fcp.lazy.value:secondaryWindow()
    return SecondaryWindow(self)
end

--- cp.apple.finalcutpro.fullScreenPlayer <FullScreenPlayer>
--- Field
--- Returns the Final Cut Pro Full Screen Window (usually triggered by Cmd+Shift+F)
function fcp.lazy.value:fullScreenPlayer()
    return FullScreenPlayer(self)
end

--- cp.apple.finalcutpro.commandEditor <CommandEditor>
--- Field
--- The Final Cut Pro Command Editor
function fcp.lazy.value:commandEditor()
    return CommandEditor(self)
end

--- cp.apple.finalcutpro.keywordEditor <KeywordEditor>
--- Field
--- The Final Cut Pro Keyword Editor
function fcp.lazy.value:keywordEditor()
    return KeywordEditor(self)
end

--- cp.apple.finalcutpro.mediaImport <MediaImport>
--- Field
--- The Final Cut Pro Media Import Window
function fcp.lazy.value:mediaImport()
    return MediaImport(self)
end

--- cp.apple.finalcutpro.exportDialog <cp.apple.finalcutpro.main.ExportDialog>
--- Field
--- The Final Cut Pro Export Dialog Box
function fcp.lazy.value:exportDialog()
    return ExportDialog(self)
end

--- cp.apple.finalcutpro.findAndReplaceTitleText <cp.apple.finalcutpro.main.FindAndReplaceTitleText>
--- Field
--- The [FindAndReplaceTitleText](cp.apple.finalcutpro.main.FindAndReplaceTitleText.md) dialog window.
function fcp.lazy.value:findAndReplaceTitleText()
    return FindAndReplaceTitleText(self.app)
end

--- cp.apple.finalcutpro.backgroundTasksDialog <cp.apple.finalcutpro.main.BackgroundTasksDialog>
--- Field
--- The [BackgroundTasksDialog](cp.apple.finalcutpro.main.BackgroundTasksDialog.md) dialog window.
function fcp.lazy.value:backgroundTasksDialog()
    return BackgroundTasksDialog(self.app)
end

----------------------------------------------------------------------------------------
--
-- SHEETS
--
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro.transcodeMedia <cp.apple.finalcutpro.main.TranscodeMedia>
--- Field
--- The [TranscodeMedia](cp.apple.finalcutpro.main.TranscodeMedia.md) sheet.
function fcp.lazy.value:transcodeMedia()
    return TranscodeMedia(self)
end

----------------------------------------------------------------------------------------
--
-- APP SECTIONS
--
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro.toolbar <cp.apple.finalcutpro.main.PrimaryToolbar>
--- Field
--- The Primary Toolbar - the toolbar at the top of the Primary Window.
function fcp.lazy.value:toolbar()
    return self.primaryWindow.toolbar
end

--- cp.apple.finalcutpro.timeline <Timeline>
--- Field
--- The Timeline instance, whether it is in the primary or secondary window.
function fcp.lazy.value:timeline()
    return Timeline(self)
end

--- cp.apple.finalcutpro.viewer <cp.apple.finalcutpro.viewer.Viewer>
--- Field
--- The [Viewer](cp.apple.finalcutpro.viewer.Viewer.md) instance, whether it is in the primary or secondary window.
function fcp.lazy.value:viewer()
    return Viewer(self, false)
end

--- cp.apple.finalcutpro.eventViewer <cp.apple.finalcutpro.viewer.Viewer>
--- Field
--- The Event [Viewer](cp.apple.finalcutpro.viewer.Viewer.md) instance, whether it is in the primary or secondary window.
function fcp.lazy.value:eventViewer()
    return Viewer(self, true)
end

--- cp.apple.finalcutpro.browser <cp.apple.finalcutpro.main.Browser>
--- Field
--- The [Browser](cp.apple.finalcutpro.main.Browser.md) instance, whether it is in the primary or secondary window.
function fcp.lazy.value:browser()
    return Browser(self)
end

--- cp.apple.finalcutpro.libraries <cp.apple.finalcutpro.main.LibrariesBrowser>
--- Field
--- The [LibrariesBrowser](cp.apple.finalcutpro.main.LibrariesBrowser.md) instance, whether it is in the primary or secondary window.
function fcp.lazy.value:libraries()
    return self.browser.libraries
end

--- cp.apple.finalcutpro.media <cp.apple.finalcutpro.main.MediaBrowser>
--- Field
--- The MediaBrowser instance, whether it is in the primary or secondary window.
function fcp.lazy.value:media()
    return self.browser.media
end

--- cp.apple.finalcutpro.generators <cp.apple.finalcutpro.main.GeneratorsBrowser>
--- Field
--- The GeneratorsBrowser instance, whether it is in the primary or secondary window.
function fcp.lazy.value:generators()
    return self.browser.generators
end

--- cp.apple.finalcutpro.effects <cp.apple.finalcutpro.main.EffectsBrowser>
--- Field
--- The EffectsBrowser instance, whether it is in the primary or secondary window.
function fcp.lazy.value:effects()
    return self.timeline.effects
end

--- cp.apple.finalcutpro.transitions <cp.apple.finalcutpro.main.EffectsBrowser>
--- Field
--- The Transitions `EffectsBrowser` instance, whether it is in the primary or secondary window.
function fcp.lazy.value:transitions()
    return self.timeline.transitions
end

--- cp.apple.finalcutpro.inspector <cp.apple.finalcutpro.inspector.Inspector>
--- Field
--- The [Inspector](cp.apple.finalcutpro.inspector.Inspector.md) instance from the primary window.
function fcp.lazy.value:inspector()
    return self.primaryWindow.inspector
end

--- cp.apple.finalcutpro.colorBoard <ColorBoard>
--- Field
--- The ColorBoard instance from the primary window
function fcp.lazy.value:colorBoard()
    return self.primaryWindow.colorBoard
end

--- cp.apple.finalcutpro.color <ColorInspector>
--- Field
--- The ColorInspector instance from the primary window
function fcp.lazy.value:color()
    return self.primaryWindow.inspector.color
end

--- cp.apple.finalcutpro.alert <cp.ui.Alert>
--- Field
--- Provides basic access to any 'alert' dialog windows in the app.
function fcp.lazy.value:alert()
    return self.primaryWindow.alert
end

----------------------------------------------------------------------------------------
--
-- PREFERENCES, SETTINGS, XML
--
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro:importXML(path) -> boolean
--- Method
--- Imports an XML file into Final Cut Pro
---
--- Parameters:
---  * path = Path to XML File
---
--- Returns:
---  * A boolean value indicating whether the AppleScript succeeded or not
function fcp:importXML(path)
    local appName = self:mainMenuName()
    local appleScript = [[
        set whichSharedXMLPath to "]] .. path .. [["
        tell application "]] .. appName .. [["
            activate
            open POSIX file whichSharedXMLPath as string
        end tell
    ]]
    local bool, _, _ = osascript.applescript(appleScript)
    return bool
end

--- cp.apple.finalcutpro:openAndSavePanelDefaultPath <cp.prop: string>
--- Variable
--- A string containing the default open/save panel path.
function fcp.lazy.prop:openAndSavePanelDefaultPath()
    ----------------------------------------------------------------------------------------
    -- NOTE: I'm not really sure what use this is. I was originally thinking this could be
    --       used to change the default open and save panel path, but it doesn't seem to
    --       work reliably. Leaving here for now, just incase we find a use for it in the
    --       future.
    ----------------------------------------------------------------------------------------
    return prop(function()
        local preferencesPath = self:preferencesPath()
        local fcpPlist = plist.read(preferencesPath)
        local bookmark = fcpPlist and fcpPlist.FFLMOpenSavePanelDefaultURL
        return bookmark and pathFromBookmark(bookmark)
    end, function(path)
        if pathToAbsolute(path) then
            local bookmark = pathToBookmark(pathToAbsolute(path))
            if bookmark then
                local hexString = stringToHexString(bookmark)
                if hexString then
                    local command = "defaults write " .. self.app:bundleID() ..  [[ FFLMOpenSavePanelDefaultURL -data "]] .. hexString .. [["]]
                    local _, status = execute(command)
                    if not status then
                        log.ef("Could not change defaults in fcp:openAndSavePanelDefaultPath().")
                    end
                end
            else
                log.ef("Could not create Bookmark of path provided to fcp:openAndSavePanelDefaultPath(): %s", path)
            end
        else
            log.ef("Bad path provided to fcp:openAndSavePanelDefaultPath(): %s", path)
        end
    end)
end

----------------------------------------------------------------------------------------
--
-- SHORTCUTS
--
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro.userCommandSetPath() -> string or nil
--- Function
--- Gets the path where User Command Set files are stored.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A path as a string or `nil` if the folder doesn't exist.
function fcp.static.userCommandSetPath()
    return pathToAbsolute("~/Library/Application Support/Final Cut Pro/Command Sets/")
end

--- cp.apple.finalcutpro:userCommandSets() -> table
--- Method
--- Gets the names of all of the user command sets.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table of user command sets as strings.
function fcp.userCommandSets()
    local result = {}
    local userCommandSetPath = fcp:userCommandSetPath()
    if doesDirectoryExist(userCommandSetPath) then
        for file in dir(userCommandSetPath) do
            if file:sub(-11) == ".commandset" then
                table.insert(result, file:sub(1, -12))
            end
        end
    end
    return result
end

--- cp.apple.finalcutpro:defaultCommandSetPath([locale]) -> string
--- Method
--- Gets the path to the 'Default' Command Set.
---
--- Parameters:
---  * `locale`	- The optional locale to use. Defaults to the [current locale](#currentLocale).
---
--- Returns:
---  * The 'Default' Command Set path, or `nil` if an error occurred
function fcp:defaultCommandSetPath(locale)
    locale = localeID(locale) or self:currentLocale()
    return self:getPath() .. "/Contents/Resources/" .. locale.code .. ".lproj/Default.commandset"
end

--- cp.apple.finalcutpro.activeCommandSetPath <cp.prop: string>
--- Field
--- Gets the 'Active Command Set' value from the Final Cut Pro preferences
function fcp.lazy.prop:activeCommandSetPath()
    return self.preferences:prop("Active Command Set", self:defaultCommandSetPath())
end

--- cp.apple.finalcutpro.commandSet(path) -> string
--- Function
--- Gets the Command Set at the specified path as a table.
---
--- Parameters:
---  * `path`	- The path to the Command Set.
---
--- Returns:
---  * The Command Set as a table, or `nil` if there was a problem.
function fcp.static.commandSet(path)
    if not fs.attributes(path) then
        log.ef("Invalid Command Set Path: %s", path)
        return nil
    else
        return plist.read(path)
    end
end

--- cp.apple.finalcutpro.activeCommandSet <cp.prop: table; live>
--- Variable
--- Contins the 'Active Command Set' as a `table`. The result is cached, but
--- updated automatically if the command set changes.
function fcp.lazy.prop:activeCommandSet()
    return prop(function()
        local path = self:activeCommandSetPath()
        local commandSet = fcp.commandSet(path)
        ----------------------------------------------------------------------------------------
        -- Reset the command cache since we've loaded a new set:
        ----------------------------------------------------------------------------------------
        self._activeCommands = nil

        return commandSet
    end)
    :cached()
    :monitor(self.activeCommandSetPath)
end

-- cp.apple.finalcutpro._commandShortcuts <table>
-- Field
-- Contains the cache of shortcuts that have been retrieved.
function fcp.lazy.value:_commandShortcuts()
    -- watch the activeCommandSet and reset the cache when it changes:
    self.activeCommandSet:watch(function()
        self._commandShortcuts = {}
    end)
    return {}
end

--- cp.apple.finalcutpro.getCommandShortcuts(id) -> table of hs.commands.shortcut
--- Method
--- Finds a shortcut from the Active Command Set with the specified ID and returns a table of `hs.commands.shortcut`s for the specified command, or `nil` if it doesn't exist.
---
--- Parameters:
---  * id - The unique ID for the command.
---
--- Returns:
---  * The array of shortcuts, or `nil` if no command exists with the specified `id`.
function fcp:getCommandShortcuts(id)
    if type(id) ~= "string" then
        log.ef("ID is required for cp.apple.finalcutpro.getCommandShortcuts.")
        return nil
    end
    local shortcuts = self._commandShortcuts[id]
    if not shortcuts then
        local commandSet = self:activeCommandSet()
        shortcuts = commandeditor.shortcutsFromCommandSet(id, commandSet)
        if not shortcuts then
            return nil
        end
        self._commandShortcuts[id] = shortcuts
    end
    return shortcuts
end

--- cp.apple.finalcutpro.commandNames <cp.strings>
--- Field
--- The `table` of all available command names, with keys mapped to human-readable names in the current locale.
function fcp.lazy.value:commandNames()
    local commandNames = strings.new()
        :fromPlist("${appPath}/Contents/Resources/${locale}.lproj/NSProCommandNames.strings")
        :fromPlist("${appPath}/Contents/Resources/${locale}.lproj/NSProCommandNamesAdditional.strings")

    local reset = function()
        commandNames:context({
            appPath = self:getPath(),
            locale = self:currentLocale().code,
        })
    end

    self.isRunning:watch(reset)
    self.currentLocale:watch(reset, true)

    return commandNames
end

--- cp.apple.finalcutpro.commandDescriptions <cp.strings>
--- Field
--- The `table` of all available command descriptions, with keys mapped to human-readable descriptions in the current locale.
function fcp.lazy.value:commandDescriptions()
    local commandDescriptions = strings.new()
        :fromPlist("${appPath}/Contents/Resources/${locale}.lproj/NSProCommandDescriptions.strings")
        :fromPlist("${appPath}/Contents/Resources/${locale}.lproj/NSProCommandDescriptionsAdditional.strings")

    local reset = function()
        commandDescriptions:context({
            appPath = self:getPath(),
            locale = self:currentLocale().code,
        })
    end

    self.isRunning:watch(reset)
    self.currentLocale:watch(reset, true)

    return commandDescriptions
end

--- cp.apple.finalcutpro.isSkimmingEnabled <bool; live>
--- Field
--- Returns `true` if the skimming playhead is enabled for the application.
function fcp.lazy.prop:isSkimmingEnabled()
    return self.preferences:prop("FFDisableSkimming", false):NOT()
end

--- cp.apple.finalcutpro.isAudioScrubbingEnabled <bool; live>
--- Field
--- Returns `true` if the audio scrubbing is enabled for the application.
function fcp.lazy.prop:isAudioScrubbingEnabled()
    return self.preferences:prop("FFDisableAudioScrubbing", false):NOT()
end

-- tracks if we are currently prompting the user about assigning a shortcut
local promptingForShortcut = {}

--- cp.apple.finalcutpro:doShortcut(whichShortcut[, suppressPrompt]) -> Statement
--- Method
--- Perform a Final Cut Pro Keyboard Shortcut
---
--- Parameters:
---  * whichShortcut - As per the Command Set name
---  * suppressPrompt - If `true`, and no shortcut is found for the specified command, then no prompt will be shown and an error is thrown Defaults to `false`.
---
--- Returns:
---  * A `Statement` that will perform the shortcut when executed.
function fcp:doShortcut(whichShortcut, suppressPrompt)
    return Do(self:doLaunch())
    :Then(function()
        local commandName = self.commandNames:find(whichShortcut) or whichShortcut
        local shortcuts = self:getCommandShortcuts(whichShortcut)
        if shortcuts and #shortcuts > 0 then
            shortcuts[1]:trigger(self:application())
            return true
        elseif not suppressPrompt then
            -- check we're not already prompting for this shortcut
            if promptingForShortcut[whichShortcut] then
                return false
            end
            -- handle the results
            local handler = function(notification)
                promptingForShortcut[whichShortcut] = nil
                local result = notification:activationType()
                if result == notify.activationTypes.actionButtonClicked or result == notify.activationTypes.contentsClicked then
                    Do(self.commandEditor:doFindCommandID(whichShortcut, true))
                    :Then(function()
                        notify.new(nil)
                            :title(i18n("finalcutpro_commands_unassigned_title"))
                            :informativeText(i18n("finalcutpro_commands_unassigned_click_and_assign_text", {["commandName"] = commandName}))
                            :withdrawAfter(5)
                            :send()
                    end)
                    :Now()
                end
            end

            -- write a debug message just incase the user has notifications disabled:
            log.wf(i18n("fcpShortcut_NoShortcutAssigned", {["commandName"] = commandName}))

            -- show a notification
            promptingForShortcut[whichShortcut] = true
            notify.new(handler)
                :title(i18n("finalcutpro_commands_unassigned_title"))
                :informativeText(i18n("finalcutpro_commands_unassigned_text", {["commandName"] = commandName}))
                :hasActionButton(true)
                :actionButtonTitle(i18n("finalcutpro_commands_unassigned_action"))
                :withdrawAfter(0)
                :send()

            return false
        else
            return Throw(i18n("fcpShortcut_NoShortcutAssigned", {["commandName"] = commandName}))
        end
    end)
    :ThenYield()
    :Label("fcp:doShortcut:"..whichShortcut)
end

-- cp.apple.finalcutpro._listWindows() -> none
-- Method
-- List Windows to Debug Log.
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
function fcp:_listWindows()
    log.d("Listing FCPX windows:")
    self:show()
    local ui = self:UI()
    local windows = self:windowsUI()
    if ui and windows then
        for i,w in ipairs(windows) do
            log.df("%7d: %s", i, self._describeWindow(w))
        end

        log.df("")
        log.df("   Main: %s", self._describeWindow(ui.AXMainWindow))
        log.df("Focused: %s", self._describeWindow(ui.AXFocusedWindow))
    else
        log.df("<none>")
    end

end

-- cp.apple.finalcutpro._describeWindow(w) -> string
-- Function
-- Returns a string containing information about the specified window.
--
-- Parameters:
--  * w - The window object.
--
-- Returns:
--  * A string
function fcp._describeWindow(w)
    if w then
        return format(
            "title: %s; role: %s; subrole: %s; modal: %s",
            inspect(w.AXTitle), inspect(w.AXRole), inspect(w.AXSubrole), inspect(w.AXModal)
        )
    else
        return "<nil>"
    end
end

local result = fcp()

-- Add `cp.dev.fcp` when in developer mode.
if config.developerMode() then
    local dev = require("cp.dev")
    dev.fcp = result
end

return result
