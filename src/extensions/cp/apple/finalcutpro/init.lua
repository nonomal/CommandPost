--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                   F I N A L    C U T    P R O    A P I                     --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--- === cp.apple.finalcutpro ===
---
--- Represents the Final Cut Pro application, providing functions that allow different tasks to be accomplished.
---
--- This module provides an API to work with the FCPX application. There are a couple of types of files:
---
--- * `init.lua` - the main module that gets imported.
--- * `axutils.lua` - some utility functions for working with `axuielement` objects.
---
--- Generally, you will `require` the `cp.apple.finalcutpro` module to import it, like so:
---
--- ```lua
--- local fcp = require("cp.apple.finalcutpro")
--- ```
---
--- Then, there are the `UpperCase` files, which represent the application itself:
---
--- * `MenuBar` 	- The main menu bar.
--- * `prefs/PreferencesWindow` - The preferences window.
--- * etc...
---
--- The `fcp` variable is the root application. It has functions which allow you to perform tasks or access parts of the UI. For example, to open the `Preferences` window, you can do this:
---
--- ```lua
--- fcp:preferencesWindow():show()
--- ```
---
--- In general, as long as FCPX is running, actions can be performed directly, and the API will perform the required operations to achieve it. For example, to toggle the 'Create Optimized Media' checkbox in the 'Import' section of the 'Preferences' window, you can simply do this:
---
--- ```lua
--- fcp:preferencesWindow():importPanel():toggleCreateOptimizedMedia()
--- ```
---
--- The API will automatically open the `Preferences` window, navigate to the 'Import' panel and toggle the checkbox.
---
--- The `UpperCase` classes also have a variety of `UI` methods. These will return the `axuielement` for the relevant GUI element, if it is accessible. If not, it will return `nil`. These allow direct interaction with the GUI if necessary. It's most useful when adding new functions to `UpperCase` files for a particular element.
---
--- This can also be used to 'wait' for an element to be visible before performing a task. For example, if you need to wait for the `Preferences` window to finish loading before doing something else, you can do this with the `cp.just` library:
---
--- ```lua
--- local just = require("cp.just")
---
--- local prefsWindow = fcp:preferencesWindow()
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
--- if fcp:preferencesWindow():isShowing() then
--- 	-- it's open!
--- else
--- 	-- it's closed!
--- end
--- ```

--------------------------------------------------------------------------------
--
-- EXTENSIONS:
--
--------------------------------------------------------------------------------
local logname									= "fcp"
local log										= require("hs.logger").new(logname)

local application								= require("hs.application")
local applicationwatcher						= require("hs.application.watcher")
local ax 										= require("hs._asm.axuielement")
local fnutils									= require("hs.fnutils")
local fs 										= require("hs.fs")
local inspect									= require("hs.inspect")
local osascript 								= require("hs.osascript")
local pathwatcher								= require("hs.pathwatcher")
local timer										= require("hs.timer")

local v											= require("semver")
local _											= require("moses")

local just										= require("cp.just")
local plist										= require("cp.plist")
local prop										= require("cp.prop")
local shortcut									= require("cp.commands.shortcut")
local strings									= require("cp.strings")
local tools										= require("cp.tools")
local watcher									= require("cp.watcher")

local axutils									= require("cp.ui.axutils")
local Browser									= require("cp.apple.finalcutpro.main.Browser")
local CommandEditor								= require("cp.apple.finalcutpro.cmd.CommandEditor")
local destinations								= require("cp.apple.finalcutpro.export.destinations")
local ExportDialog								= require("cp.apple.finalcutpro.export.ExportDialog")
local FullScreenWindow							= require("cp.apple.finalcutpro.main.FullScreenWindow")
local kc										= require("cp.apple.finalcutpro.keycodes")
local MediaImport								= require("cp.apple.finalcutpro.import.MediaImport")
local MenuBar									= require("cp.apple.finalcutpro.MenuBar")
local PreferencesWindow							= require("cp.apple.finalcutpro.prefs.PreferencesWindow")
local PrimaryWindow								= require("cp.apple.finalcutpro.main.PrimaryWindow")
local SecondaryWindow							= require("cp.apple.finalcutpro.main.SecondaryWindow")
local Timeline									= require("cp.apple.finalcutpro.main.Timeline")
local Viewer									= require("cp.apple.finalcutpro.main.Viewer")
local windowfilter								= require("cp.apple.finalcutpro.windowfilter")

local plugins									= require("cp.apple.finalcutpro.plugins")

local len, format								= string.len, string.format

--------------------------------------------------------------------------------
--
-- THE MODULE:
--
--------------------------------------------------------------------------------
local App = {}

--- cp.apple.finalcutpro.EARLIEST_SUPPORTED_VERSION
--- Constant
--- The earliest version of Final Cut Pro supported by this module.
App.EARLIEST_SUPPORTED_VERSION = "10.3.2"

--- cp.apple.finalcutpro.BUNDLE_ID
--- Constant
--- Final Cut Pro's Bundle ID
App.BUNDLE_ID = "com.apple.FinalCut"

--- cp.apple.finalcutpro.BUNDLE_ID_TRIAL
--- Constant
--- Final Cut Pro's Bundle ID for trial version
App.BUNDLE_ID_TRIAL = "com.apple.FinalCutTrial"

--- cp.apple.finalcutpro.PASTEBOARD_UTI
--- Constant
--- Final Cut Pro's Pasteboard UTI
App.PASTEBOARD_UTI = "com.apple.flexo.proFFPasteboardUTI"

--- cp.apple.finalcutpro.PREFS_PATH
--- Constant
--- Final Cut Pro's Preferences Path
App.PREFS_PATH = "~/Library/Preferences/"

--- cp.apple.finalcutpro.SUPPORTED_LANGUAGES
--- Constant
--- Table of Final Cut Pro's supported Languages
App.SUPPORTED_LANGUAGES = {"de", "en", "es", "fr", "ja", "zh_CN"}

--- cp.apple.finalcutpro.FLEXO_LANGUAGES
--- Constant
--- Table of Final Cut Pro's supported Languages for the Flexo Framework
App.FLEXO_LANGUAGES	= {"de", "en", "es_419", "es", "fr", "id", "ja", "ms", "vi", "zh_CN"}

--- cp.apple.finalcutpro.ALLOWED_IMPORT_VIDEO_EXTENSIONS
--- Constant
--- Table of video file extensions Final Cut Pro can import.
App.ALLOWED_IMPORT_VIDEO_EXTENSIONS	= {"3gp", "avi", "mov", "mp4", "mts", "m2ts", "mxf", "m4v", "r3d"}

--- cp.apple.finalcutpro.ALLOWED_IMPORT_AUDIO_EXTENSIONS
--- Constant
--- Table of audio file extensions Final Cut Pro can import.
App.ALLOWED_IMPORT_AUDIO_EXTENSIONS	= {"aac", "aiff", "aif", "bwf", "caf", "mp3", "mp4", "wav"}

--- cp.apple.finalcutpro.ALLOWED_IMPORT_IMAGE_EXTENSIONS
--- Constant
--- Table of image file extensions Final Cut Pro can import.
App.ALLOWED_IMPORT_IMAGE_EXTENSIONS	= {"bmp", "gif", "jpeg", "jpg", "png", "psd", "raw", "tga", "tiff", "tif"}

--- cp.apple.finalcutpro.ALLOWED_IMPORT_EXTENSIONS
--- Constant
--- Table of all file extensions Final Cut Pro can import.
App.ALLOWED_IMPORT_ALL_EXTENSIONS = fnutils.concat(App.ALLOWED_IMPORT_VIDEO_EXTENSIONS, fnutils.concat(App.ALLOWED_IMPORT_AUDIO_EXTENSIONS, App.ALLOWED_IMPORT_IMAGE_EXTENSIONS))

--- cp.apple.finalcutpro:init() -> App
--- Function
--- Initialises the app instance representing Final Cut Pro.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The app.
function App:init()
	self:_initWatchers()
	self:_initStrings()
	self.application:watch(function() self:reset() end)

	-- set initial state
	self.application:update()
	return self
end


--- cp.apple.finalcutpro:reset() -> none
--- Function
--- Resets the language cache
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function App:reset()
	self._currentLanguage = nil
	self._activeCommandSet = nil
end

-- cp.apple.finalcutpro:_initStrings() -> none
-- Function
-- Initialise Strings Watchers
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
function App:_initStrings()
	self.isRunning:watch(function() self:_resetStrings() end, true)
end

-- cp.apple.finalcutpro:_resetStrings() -> none
-- Function
-- Reset Strings
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
function App:_resetStrings()
	self._strings = strings.new()

	local appPath = self:getPath()
	if appPath then
		self._strings:fromPlist(appPath .. "/Contents/Resources/${language}.lproj/PELocalizable.strings")
		self._strings:fromPlist(appPath .. "/Contents/Frameworks/Flexo.framework/Resources/${language}.lproj/FFLocalizable.strings")
		self._strings:fromPlist(appPath .. "/Contents/Frameworks/LunaKit.framework/Resources/${language}.lproj/Commands.strings")
		self._strings:fromPlist(appPath .. "/Contents/Frameworks/LunaKit.framework/Resources/${language}.lproj/Commands.strings")
		self._strings:fromPlist(appPath .. "/Contents/PlugIns/InternalFiltersXPC.pluginkit/Contents/PlugIns/Filters.bundle/Contents/Resources/${language}.lproj/Localizable.strings") -- Added for Final Cut Pro 10.4
	end
end

--- cp.apple.finalcutpro:string(key[, lang]) -> string
--- Method
--- Looks up an application string with the specified `key`.
--- If no `lang` value is provided, the [current language](#currentLanguage) is used.
---
--- Parameters:
---  * `key`	- The key to look up.
---  * `[lang]` - The language code to use. Defaults to the current language.
---
--- Returns:
---  * The requested string or `nil` if the application is not running.
function App:string(key, lang)
	lang = lang or self:currentLanguage()
	return self._strings and self._strings:find(lang, key)
end

--- cp.apple.finalcutpro:keysWithString(string[, lang]) -> {string}
--- Method
--- Looks up an application string and returns an array of keys that match. It will take into account current language the app is running in, or use `lang` if provided.
---
--- Parameters:
---  * `key`	- The key to look up.
---  * `[lang]`	- The language (defaults to current FCPX language).
---
--- Returns:
---  * The array of keys with a matching string.
---
--- Notes:
---  * This method may be very inefficient, since it has to search through every possible key/value pair to find matches. It is not recommended that this is used in production.
function App:keysWithString(string, lang)
	local lang = lang or self:currentLanguage()
	return self._strings and self._strings:findKeys(lang, string)
end

-- findApp(app, bundleId) -> application
-- Function
-- Returns the `app` if it exists, or finds an app with the specified bundle ID if possible.
--
-- Parameters:
-- * app		- The application, which if existing, will be returned.
-- * bundleId	- The Application Bundle ID which will be used to find an application if app is not found.
--
-- Returns:
-- * The application, or `nil` if none is found.
local function findApp(app, bundleId)
	if not app or app:bundleID() == nil or not app:isRunning() then
		app = nil
		local result = application.applicationsForBundleID(bundleId)
		if result and #result > 0 then
			-- select the first result found
			app = result[1]
		end
	end
	return app
end

--- cp.apple.finalcutpro:application() -> hs.application
--- Field
--- Returns the running `hs.application` for Final Cut Pro.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The hs.application, or `nil` if the application is not running.
App.application = prop.new(function(self)
	self._fullApp = findApp(self._fullApp, App.BUNDLE_ID)
	self._trialApp = findApp(self._trialApp, App.BUNDLE_ID_TRIAL)

	if self._fullApp == nil or self._trialApp and self._trialApp:isFrontmost() then
		return self._trialApp
	else
		return self._fullApp
	end
end):bind(App)

--- cp.apple.finalcutpro:bundleID <cp.prop: string; read-only>
--- Field
--- A cp.prop containing the Bundle ID for the Final Cut Pro app currently running.
--- This could be the full FCPX app or the Trial app. If both are running, then
--- if the Trial is the front-most app, it will be returned, otherwise the main FCPX bundle
--- is returned. If neither are running, then the ID for the main FCPX app is returned if it
--- is installed, then the Trial (if installed), or `nil` if none is installed.
App.bundleID = prop.new(function(self)
	local app = self:application()
	if app then
		return app:bundleID()
	else
		local fullApp = application.nameForBundleID(App.BUNDLE_ID)
		if fullApp then
			return App.BUNDLE_ID
		else
			local trialApp = application.nameForBundleID(App.BUNDLE_ID_TRIAL)
			if trialApp ~= nil then
				return App.BUNDLE_ID_TRIAL
			end
		end
	end
	return nil
end):bind(App):monitor(App.application)

--- cp.apple.finalcutpro:name <cp.prop: string; read-only>
--- Field
--- The name of the app, or `nil` if FCPX is not installed.
App.name = App.bundleID:mutate(function(bundleID, self)
	return bundleID and application.nameForBundleID(bundleID) or nil
end):bind(App)

--- cp.apple.finalcutpro:preferencesFile <cp.prop: string>
--- Field
--- The name of the preferences file for the current app, or `nil` if none is installed.
---
--- Notes:
--- * This only returns the file name. See `preferencesPath` for the full path.
App.preferencesFile = App.bundleID:mutate(function(value, self)
	return value and value .. ".plist" or nil
end):bind(App)

--- cp.apple.finalcutpro:preferencesFile <cp.prop: string>
--- Field
--- The full path to preferences file for the current app, or `nil` if none is installed.
---
--- Notes:
--- * This returns the full path. See `preferencesFile` to get the file name only.
App.preferencesPath = App.preferencesFile:mutate(function(filename, self)
	return filename and App.PREFS_PATH .. filename or nil
end):bind(App)

--- cp.apple.finalcutpro.isRunning <cp.prop: boolean; read-only>
--- Field
--- Is Final Cut Pro Running?
App.isRunning = prop.new(function(self)
	local app = self:application()
	return app ~= nil and app:bundleID() ~= nil and app:isRunning()
end):bind(App):monitor(App.application)

--- cp.apple.finalcutpro:getBundleID() -> string
--- Method
--- Returns the Final Cut Pro Bundle ID
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string of the Final Cut Pro Bundle ID
function App:getBundleID()
	return App.BUNDLE_ID
end

--- cp.apple.finalcutpro:getPasteboardUTI() -> string
--- Method
--- Returns the Final Cut Pro Pasteboard UTI
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string of the Final Cut Pro Pasteboard UTI
function App:getPasteboardUTI()
	return App.PASTEBOARD_UTI
end

--- cp.apple.finalcutpro:UI() -> axuielement
--- Method
--- Returns the Final Cut Pro axuielement
---
--- Parameters:
---  * None
---
--- Returns:
---  * A axuielementObject of Final Cut Pro
function App:UI()
	return axutils.cache(self, "_ui", function()
		local fcp = self:application()
		return fcp and ax.applicationElement(fcp)
	end)
end

--- cp.apple.finalcutpro:launch() -> boolean
--- Method
--- Launches Final Cut Pro, or brings it to the front if it was already running.
---
--- Parameters:
---  * None
---
--- Returns:
---  * `true` if Final Cut Pro was either launched or focused, otherwise false (e.g. if Final Cut Pro doesn't exist)
function App:launch()

	local result = nil

	local fcpx = self:application()
	if fcpx == nil then
		-- Final Cut Pro is Closed:
		result = application.launchOrFocusByBundleID(App.BUNDLE_ID)
		if not result then -- try FCP Trial
			result = application.launchOrFocusByBundleID(App.BUNDLE_ID_TRIAL)
		end
	else
		-- Final Cut Pro is Open:
		if not fcpx:isFrontmost() then
			-- Open by not Active:
			result = application.launchOrFocusByBundleID(App.BUNDLE_ID)
		else
			-- Already frontmost:
			return true
		end
	end

	return result
end

--- cp.apple.finalcutpro:restart(waitUntilRestarted) -> boolean
--- Method
--- Restart Final Cut Pro
---
--- Parameters:
---  * `waitUntilRestarted`	- If `true`, the function will not return until the app has restarted.
---
--- Returns:
---  * `true` if Final Cut Pro was running and restarted successfully.
function App:restart(waitUntilRestarted)
	local app = self:application()
	if app then
		local appPath = app:path()
		-- Kill Final Cut Pro:
		self:quit()

		-- Wait until Final Cut Pro is Closed (checking every 0.1 seconds for up to 20 seconds):
		just.doWhile(function() return self:isRunning() end, 20, 0.1)

		-- force the application to update, otherwise it isn't closed long enough to prompt an event.
		self.application:update()

		-- Launch Final Cut Pro:
		if appPath then
			local _, result = hs.execute([[open "]] .. tostring(appPath) .. [["]])
			return result
		end

		if waitUntilRestarted then
			just.doUntil(function() return self:isRunning() end, 20, 0.1)
		end

	end
	return false
end

--- cp.apple.finalcutpro:show() -> cp.apple.finalcutpro
--- Method
--- Activate Final Cut Pro
---
--- Parameters:
---  * None
---
--- Returns:
---  * A cp.apple.finalcutpro otherwise nil
function App:show()
	local app = self:application()
	if app then
		if app:isHidden() then
			app:unhide()
		end
		if app:isRunning() then
			app:activate()
		end
	end
	return self
end

--- cp.apple.finalcutpro.isShowing <cp.prop: boolean; read-only>
--- Field
--- Is Final Cut visible on screen?
App.isShowing = App.application:mutate(function(app) return app and not app:isHidden() end):bind(App)

--- cp.apple.finalcutpro:hide() -> cp.apple.finalcutpro
--- Method
--- Hides Final Cut Pro
---
--- Parameters:
---  * None
---
--- Returns:
---  * A cp.apple.finalcutpro otherwise nil
function App:hide()
	local app = self:application()
	if app then
		app:hide()
	end
	return self
end

--- cp.apple.finalcutpro:quit() -> cp.apple.finalcutpro
--- Method
--- Quits Final Cut Pro
---
--- Parameters:
---  * None
---
--- Returns:
---  * A cp.apple.finalcutpro otherwise nil
function App:quit()
	local app = self:application()
	if app then
		app:kill()
	end
	return self
end

--- cp.apple.finalcutpro:getPath() -> string or nil
--- Method
--- Path to Final Cut Pro Application
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string containing Final Cut Pro's filesystem path, or nil if Final Cut Pro's path could not be determined.
function App:getPath()
	local app = self:application()
	if app and app:isRunning() then
		----------------------------------------------------------------------------------------
		-- FINAL CUT PRO IS CURRENTLY RUNNING:
		----------------------------------------------------------------------------------------
		local appPath = app:path()
		if appPath then
			return appPath
		else
			log.ef("GET PATH: Failed to get running application path.")
		end
	else
		----------------------------------------------------------------------------------------
		-- FINAL CUT PRO IS CURRENTLY CLOSED:
		----------------------------------------------------------------------------------------
		local result = application.pathForBundleID(App.BUNDLE_ID)
		if result then
			return result
		end
	end
	return nil
end

--- cp.apple.finalcutpro.getVersion <cp.prop: string; read-only>
--- Field
--- Version of Final Cut Pro as string.
---
--- Parameters:
---  * None
---
--- Returns:
---  * Version as string or `nil` if Final Cut Pro cannot be found.
---
--- Notes:
---  * If Final Cut Pro is running it will get the version of the active Final Cut Pro application as a string, otherwise, it will use `hs.application.infoForBundleID()` to find the version.
App.getVersion = App.application:mutate(function(app)
	----------------------------------------------------------------------------------------
	-- FINAL CUT PRO IS CURRENTLY RUNNING:
	----------------------------------------------------------------------------------------
	if app and app:isRunning() then
		local appPath = app:path()
		if appPath then
			local info = application.infoForBundlePath(appPath)
			if info then
				return info["CFBundleShortVersionString"]
			else
				log.ef("VERSION CHECK: Could not determine Final Cut Pro's version.")
			end
		else
			log.ef("VERSION CHECK: Could not determine Final Cut Pro's path.")
		end
	end

	----------------------------------------------------------------------------------------
	-- NO VERSION OF FINAL CUT PRO CURRENTLY RUNNING:
	----------------------------------------------------------------------------------------
	local info = application.infoForBundleID(App.BUNDLE_ID)
	if info then
		return info["CFBundleShortVersionString"]
	else
		log.ef("VERSION CHECK: Could not determine Final Cut Pro's info from Bundle ID.")
	end

	----------------------------------------------------------------------------------------
	-- FINAL CUT PRO COULD NOT BE DETECTED:
	----------------------------------------------------------------------------------------
	return nil

end):bind(App)

--- cp.apple.finalcutpro.isSupported <cp.prop: boolean; read-only>
--- Field
--- Is a supported version of Final Cut Pro installed?
---
--- Note:
---  * Supported version refers to any version of Final Cut Pro equal or higher to `cp.apple.finalcutpro.EARLIEST_SUPPORTED_VERSION`
App.isSupported = App.getVersion:mutate(function(version)
	return version ~= nil and v(tostring(version)) >= v(tostring(App.EARLIEST_SUPPORTED_VERSION))
end):bind(App)

--- cp.apple.finalcutpro:colorInspectorSupported <cp.prop: boolean; read-only>
--- Field
--- Is the Color Inspector supported in the installed version of Final Cut Pro?
App.isColorInspectorSupported = prop.new(function(self)
	local version = self:getVersion()
	if version and v(version) >= v("10.4") then
		return true
	else
		return false
	end
end):bind(App)

--- cp.apple.finalcutpro.isInstalled <cp.prop: boolean; read-only>
--- Field
--- Is any version of Final Cut Pro Installed?
App.isInstalled = App.getVersion:mutate(function(version) return version ~= nil end):bind(App)

--- cp.apple.finalcutpro.isUnsupported <cp.prop: boolean; read-only>
--- Field
--- Is an unsupported version of Final Cut Pro installed?
---
--- Note:
---  * Supported version refers to any version of Final Cut Pro equal or higher to cp.apple.finalcutpro.EARLIEST_SUPPORTED_VERSION
App.isUnsupported = App.isInstalled:AND(App.isSupported:NOT()):bind(App)

--- cp.apple.finalcutpro:isFrontmost <cp.prop: boolean; read-only>
--- Field
--- Is Final Cut Pro Frontmost?
App.isFrontmost = App.application:mutate(function(app) return app ~= nil and app:isFrontmost() end):bind(App)

--- cp.apple.finalcutpro:isModalDialogOpen <cp.prop: boolean; read-only>
--- Field
--- Is a modal dialog currently open?
App.isModalDialogOpen = prop.new(function(self)
	local ui = self:UI()
	if ui then
		local window = ui:focusedWindow()
		if window then
			return window:attributeValue("AXModal") == true
		end
	end
	return false
end):bind(App)

----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
--
-- SCAN PLUGINS
--
----------------------------------------------------------------------------------------
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
function App:plugins()
	if not self._plugins then
		self._plugins = plugins.new(self)
	end
	return self._plugins
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
function App:scanPlugins()
	return self:plugins():scan()
end

----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
--
-- MENU BAR
--
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------

function _prepareMenuPath(path, appName)
	local newPath = {}
	for _,step in ipairs(path) do
		if step == MenuBar.APP_MENU then
			step = appName
		elseif step == MenuBar.APPLE_MENU then
			step = MenuBar.APPLE_MENU_NAME
		end
		table.insert(newPath, step)
	end
	return newPath
end

--- cp.apple.finalcutpro:menuBar() -> menuBar object
--- Method
--- Returns the Final Cut Pro Menu Bar
---
--- Parameters:
---  * None
---
--- Returns:
---  * A MenuBar object
function App:menuBar()
	if not self._menuBar then
		local menuBar = MenuBar:new(self)
		----------------------------------------------------------------------------------------
		-- Add a finder for Share Destinations:
		----------------------------------------------------------------------------------------
		menuBar:addMenuFinder(function(parentItem, path, childName, language)
			if _.isEqual(path, {"File", "Share"}) then
				childName = childName:match("(.*)…$") or childName
				local index = destinations.indexOf(childName)
				if index then
					local children = parentItem:attributeValue("AXChildren")
					return children[index]
				end
			end
			return nil
		end)
		----------------------------------------------------------------------------------------
		-- Add a finder for missing menus:
		----------------------------------------------------------------------------------------
		local missingMenuMap = {
			{ path = {MenuBar.APP_MENU},				child = "Commands",		key = "CommandSubmenu" },
			{ path = {MenuBar.APP_MENU, "Commands"},	child = "Customize…",	key = "Customize" },
			{ path = {"Clip"},							child = "Open Clip",	key = "FFOpenInTimeline" },
			{ path = {"Window", "Show in Workspace"},	child = "Sidebar",		key = "PEEventsLibrary" },
			{ path = {"Window", "Show in Workspace"},	child = "Timeline",		key = "PETimeline" },
		}

		menuBar:addMenuFinder(function(parentItem, path, childName, language)
			for i,item in ipairs(missingMenuMap) do
				local missingPath = _prepareMenuPath(item.path, self:name())
				if _.isEqual(path, missingPath) and childName == item.child then
					return axutils.childWith(parentItem, "AXTitle", self:string(item.key))
				end
			end
			return nil
		end)

		self._menuBar = menuBar
	end
	return self._menuBar
end

--- cp.apple.finalcutpro:selectMenu(path) -> boolean
--- Method
--- Selects a Final Cut Pro Menu Item based on the list of menu titles in English.
---
--- Parameters:
---  * `path`	- The list of menu items you'd like to activate, for example:
---            select("View", "Browser", "as List")
---
--- Returns:
---  * `true` if the press was successful.
function App:selectMenu(path)
	return self:menuBar():selectMenu(path)
end

----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
--
-- WINDOWS
--
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro:preferencesWindow() -> preferenceWindow object
--- Method
--- Returns the Final Cut Pro Preferences Window
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Preferences Window
function App:preferencesWindow()
	if not self._preferencesWindow then
		self._preferencesWindow = PreferencesWindow:new(self)
	end
	return self._preferencesWindow
end

--- cp.apple.finalcutpro:primaryWindow() -> primaryWindow object
--- Method
--- Returns the Final Cut Pro Preferences Window
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Primary Window
function App:primaryWindow()
	if not self._primaryWindow then
		self._primaryWindow = PrimaryWindow:new(self)
	end
	return self._primaryWindow
end

--- cp.apple.finalcutpro:secondaryWindow() -> secondaryWindow object
--- Method
--- Returns the Final Cut Pro Preferences Window
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Secondary Window
function App:secondaryWindow()
	if not self._secondaryWindow then
		self._secondaryWindow = SecondaryWindow:new(self)
	end
	return self._secondaryWindow
end

--- cp.apple.finalcutpro:fullScreenWindow() -> fullScreenWindow object
--- Method
--- Returns the Final Cut Pro Full Screen Window
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Full Screen Playback Window
function App:fullScreenWindow()
	if not self._fullScreenWindow then
		self._fullScreenWindow = FullScreenWindow:new(self)
	end
	return self._fullScreenWindow
end

--- cp.apple.finalcutpro:commandEditor() -> commandEditor object
--- Method
--- Returns the Final Cut Pro Command Editor
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Final Cut Pro Command Editor
function App:commandEditor()
	if not self._commandEditor then
		self._commandEditor = CommandEditor:new(self)
	end
	return self._commandEditor
end

--- cp.apple.finalcutpro:mediaImport() -> mediaImport object
--- Method
--- Returns the Final Cut Pro Media Import Window
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Final Cut Pro Media Import Window
function App:mediaImport()
	if not self._mediaImport then
		self._mediaImport = MediaImport:new(self)
	end
	return self._mediaImport
end

--- cp.apple.finalcutpro:exportDialog() -> exportDialog object
--- Method
--- Returns the Final Cut Pro Export Dialog Box
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Final Cut Pro Export Dialog Box
function App:exportDialog()
	if not self._exportDialog then
		self._exportDialog = ExportDialog:new(self)
	end
	return self._exportDialog
end

--- cp.apple.finalcutpro:windowsUI() -> axuielement
--- Method
--- Returns the UI containing the list of windows in the app.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The axuielement, or nil if the application is not running.
function App:windowsUI()
	local ui = self:UI()
	return ui and ui:attributeValue("AXWindows")
end

----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
--
-- APP SECTIONS
--
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro:timeline() -> Timeline
--- Method
--- Returns the Timeline instance, whether it is in the primary or secondary window.
---
--- Parameters:
---  * None
---
--- Returns:
---  * the Timeline
function App:timeline()
	if not self._timeline then
		self._timeline = Timeline:new(self)
	end
	return self._timeline
end

--- cp.apple.finalcutpro:viewer() -> Viewer
--- Method
--- Returns the Viewer instance, whether it is in the primary or secondary window.
---
--- Parameters:
---  * None
---
--- Returns:
---  * the Viewer
function App:viewer()
	if not self._viewer then
		self._viewer = Viewer:new(self, false)
	end
	return self._viewer
end

--- cp.apple.finalcutpro:eventViewer() -> Event Viewer
--- Method
--- Returns the Event Viewer instance, whether it is in the primary or secondary window.
---
--- Parameters:
---  * None
---
--- Returns:
---  * the Event Viewer
function App:eventViewer()
	if not self._eventViewer then
		self._eventViewer = Viewer:new(self, true)
	end
	return self._eventViewer
end

--- cp.apple.finalcutpro:browser() -> Browser
--- Method
--- Returns the Browser instance, whether it is in the primary or secondary window.
---
--- Parameters:
---  * None
---
--- Returns:
---  * the Browser
function App:browser()
	if not self._browser then
		self._browser = Browser:new(self)
	end
	return self._browser
end

--- cp.apple.finalcutpro:libraries() -> LibrariesBrowser
--- Method
--- Returns the LibrariesBrowser instance, whether it is in the primary or secondary window.
---
--- Parameters:
---  * None
---
--- Returns:
---  * the LibrariesBrowser
function App:libraries()
	return self:browser():libraries()
end

--- cp.apple.finalcutpro:media() -> MediaBrowser
--- Method
--- Returns the MediaBrowser instance, whether it is in the primary or secondary window.
---
--- Parameters:
---  * None
---
--- Returns:
---  * the MediaBrowser
function App:media()
	return self:browser():media()
end

--- cp.apple.finalcutpro:generators() -> GeneratorsBrowser
--- Method
--- Returns the GeneratorsBrowser instance, whether it is in the primary or secondary window.
---
--- Parameters:
---  * None
---
--- Returns:
---  * the GeneratorsBrowser
function App:generators()
	return self:browser():generators()
end

--- cp.apple.finalcutpro:effects() -> EffectsBrowser
--- Method
--- Returns the EffectsBrowser instance, whether it is in the primary or secondary window.
---
--- Parameters:
---  * None
---
--- Returns:
---  * the EffectsBrowser
function App:effects()
	return self:timeline():effects()
end

--- cp.apple.finalcutpro:transitions() -> TransitionsBrowser
--- Method
--- Returns the TransitionsBrowser instance, whether it is in the primary or secondary window.
---
--- Parameters:
---  * None
---
--- Returns:
---  * the TransitionsBrowser
function App:transitions()
	return self:timeline():transitions()
end

--- cp.apple.finalcutpro:inspector() -> Inspector
--- Method
--- Returns the Inspector instance from the primary window
---
--- Parameters:
---  * None
---
--- Returns:
---  * the Inspector
function App:inspector()
	return self:primaryWindow():inspector()
end

--- cp.apple.finalcutpro:colorBoard() -> ColorBoard
--- Method
--- Returns the ColorBoard instance from the primary window
---
--- Parameters:
---  * None
---
--- Returns:
---  * the ColorBoard
function App:colorBoard()
	return self:primaryWindow():colorBoard()
end

--- cp.apple.finalcutpro:colorInspector() -> ColorInspector
--- Method
--- Returns the ColorInspector instance from the primary window
---
--- Parameters:
---  * None
---
--- Returns:
---  * the ColorInspector
function App:colorInspector()
	return self:primaryWindow():colorInspector()
end

----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
--
-- PREFERENCES, SETTINGS, XML
--
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro:getPreferences([forceReload]) -> table or nil
--- Method
--- Gets Final Cut Pro's Preferences as a table. It checks if the preferences
--- file has been modified and reloads when necessary.
---
--- Parameters:
---  * [forceReload]	- If `true`, an optional reload will be forced even if the file hasn't been modified.
---
--- Returns:
---  * A table with all of Final Cut Pro's preferences, or nil if an error occurred
function App:getPreferences(forceReload)
	local bundleID = self:bundleID()
	if bundleID == nil then -- not installed
		return nil
	end

	local prefsPath = self:preferencesPath()
	local prefsFile = self:preferencesFile()

	-- init preferences cache
	local prefs = self._preferences or {}
	self._preferences = prefs

	local modified = fs.attributes(prefsPath, "modification")
	if forceReload or modified ~= prefs[bundleID..":modification"] then
		-- log.df("Reloading Final Cut Pro Preferences: %s; %s", self._preferencesModified, modified)
		-- NOTE: https://macmule.com/2014/02/07/mavericks-preference-caching/
		hs.execute([[/usr/bin/python -c 'import CoreFoundation; CoreFoundation.CFPreferencesAppSynchronize("]] .. bundleID .. [[")']])

		prefs[bundleID] = plist.binaryFileToTable(prefsPath) or nil
		prefs[bundleID..":modification"] = fs.attributes(prefsPath, "modification")

		-- Setup Preferences Watcher:
		--log.df("Setting up Preferences Watcher...")
		local watcher = prefs[bundleID..":watcher"]
		if not watcher then
			local watcher = pathwatcher.new(App.PREFS_PATH, function(files)
				local fileLength = len(prefsFile)*-1
				for _,file in pairs(files) do
					if self._watchers and file:sub(fileLength) == prefsFile then
						self._watchers:notify("preferences")
						return
					end
				end
			end):start()
			prefs[bundleID..":watcher"] = watcher
		end
	 end
	return self._preferences[bundleID]
end

--- cp.apple.finalcutpro:getPreference(value, [default], [forceReload]) -> string or nil
--- Method
--- Get an individual Final Cut Pro preference
---
--- Parameters:
---  * value 			- The preference you want to return
---  * [default]		- The optional default value to return if the preference is not set.
---  * [forceReload]	- If `true`, optionally forces a reload of the app's preferences.
---
--- Returns:
---  * A string with the preference value, or nil if an error occurred
function App:getPreference(value, default, forceReload)
	local result = nil
	local preferencesTable = self:getPreferences(forceReload)
	if preferencesTable then
		result = preferencesTable[value]
	end

	if result == nil then
		result = default
	end

	return result
end

--- cp.apple.finalcutpro:setPreference(key, value) -> boolean
--- Method
--- Sets an individual Final Cut Pro preference
---
--- Parameters:
---  * key - The preference you want to change
---  * value - The value you want to set for that preference
---
--- Returns:
---  * True if executed successfully otherwise False
function App:setPreference(key, value)
	local path = self:preferencesPath()
	if path == nil then
		log.wf("Attempted to set a preference for FCP without FCP being installed.")
		return false
	end

	local executeStatus
	local preferenceType = nil

	if value == nil then
		local executeString = "defaults delete " .. path .. " '" .. key .. "'"
		local _, executeStatus = hs.execute(executeString)
		return executeStatus ~= nil
	end

	if type(value) == "boolean" then
		value = tostring(value)
		preferenceType = "bool"
	elseif type(value) == "table" then
		local arrayString = ""
		for i=1, #value do
			arrayString = arrayString .. value[i]
			if i ~= #value then
				arrayString = arrayString .. ","
			end
		end
		value = "'" .. arrayString .. "'"
		preferenceType = "array"
	elseif type(value) == "string" then
		preferenceType = "string"
		value = "'" .. value .. "'"
	elseif type(value) == "number" then
		preferenceType = "int"
		value = tostring(value)
	else
		return false
	end

	if preferenceType then
		local executeString = "defaults write " .. path .. " '" .. key .. "' -" .. preferenceType .. " " .. value
		local _, executeStatus = hs.execute(executeString)
		return executeStatus ~= nil
	end
	return false
end

--- cp.apple.finalcutpro:importXML(path) -> boolean
--- Method
--- Imports an XML file into Final Cut Pro
---
--- Parameters:
---  * path = Path to XML File
---
--- Returns:
---  * A boolean value indicating whether the AppleScript succeeded or not
function App:importXML(path)
	if self:isRunning() then
		local appleScript = [[
			set whichSharedXMLPath to "]] .. path .. [["
			tell application "Final Cut Pro"
				activate
				open POSIX file whichSharedXMLPath as string
			end tell
		]]
		local bool, _, _ = osascript.applescript(appleScript)
		return bool
	end
end

----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
--
-- SHORTCUTS
--
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro:getActiveCommandSetPath() -> string or nil
--- Method
--- Gets the 'Active Command Set' value from the Final Cut Pro preferences
---
--- Parameters:
---  * None
---
--- Returns:
---  * The 'Active Command Set' value, or the 'Default' command set if none is set.
function App:getActiveCommandSetPath()
	local result = self:getPreference("Active Command Set") or nil
	if result == nil then
		-- In the unlikely scenario that this is the first time FCPX has been run:
		result = self:getDefaultCommandSetPath()
	end
	return result
end

--- cp.apple.finalcutpro:getDefaultCommandSetPath([langauge]) -> string
--- Method
--- Gets the path to the 'Default' Command Set.
---
--- Parameters:
---  * [language]	- The optional language code to use. Defaults to the current FCPX language.
---
--- Returns:
---  * The 'Default' Command Set path, or `nil` if an error occurred
function App:getDefaultCommandSetPath(language)
	language = language or self:currentLanguage()
	return self:getPath() .. "/Contents/Resources/" .. language .. ".lproj/Default.commandset"
end

--- cp.apple.finalcutpro:getCommandSet(path) -> string
--- Method
--- Loads the Command Set at the specified path into a table.
---
--- Parameters:
---  * `path`	- The path to the command set.
---
--- Returns:
---  * The Command Set as a table, or `nil` if there was a problem.
function App:getCommandSet(path)
	if fs.attributes(path) ~= nil then
		return plist.fileToTable(path)
	end
end

--- cp.apple.finalcutpro:getActiveCommandSet([forceReload]) -> table or nil
--- Method
--- Returns the 'Active Command Set' as a Table. The result is cached, so pass in
--- `true` for `forceReload` if you want to reload it.
---
--- Parameters:
---  * [forceReload]	- If `true`, require the Command Set to be reloaded.
---
--- Returns:
---  * A table of the Active Command Set's contents, or `nil` if an error occurred
function App:getActiveCommandSet(forceReload)

	if forceReload or not self._activeCommandSet then
		local path = self:getActiveCommandSetPath()
		self._activeCommandSet = self:getCommandSet(path)
		-- reset the command cache since we've loaded a new set.
		if self._activeCommands then
			self._activeCommands = nil
		end
	end

	return self._activeCommandSet
end

--- cp.apple.finalcutpro.getCommandShortcuts(id) -> table of hs.commands.shortcut
--- Method
--- Finds a shortcut from the Active Command Set with the specified ID and returns a table
--- of `hs.commands.shortcut`s for the specified command, or `nil` if it doesn't exist.
---
--- Parameters:
---  * id - The unique ID for the command.
---
--- Returns:
---  * The array of shortcuts, or `nil` if no command exists with the specified `id`.
function App:getCommandShortcuts(id)
	local activeCommands = self._activeCommands
	if not activeCommands then
		activeCommands = {}
		self._activeCommands = activeCommands
	end

	local shortcuts = activeCommands[id]
	if not shortcuts then
		local commandSet = self:getActiveCommandSet()

		local fcpxCmds = commandSet[id]

		if fcpxCmds == nil then
			return nil
		end

		if #fcpxCmds == 0 then
			fcpxCmds = { fcpxCmds }
		end

		shortcuts = {}

		for _,fcpxCmd in ipairs(fcpxCmds) do
			local modifiers = nil
			local keyCode = nil
			local keypadModifier = false

			if fcpxCmd["modifiers"] ~= nil then
				if string.find(fcpxCmd["modifiers"], "keypad") then keypadModifier = true end
				modifiers = kc.fcpxModifiersToHsModifiers(fcpxCmd["modifiers"])
			elseif fcpxCmd["modifierMask"] ~= nil then
				modifiers = tools.modifierMaskToModifiers(fcpxCmd["modifierMask"])
				if tools.tableContains(modifiers, "numericpad") then
					keypadModifier = true
				end
			end

			if fcpxCmd["characterString"] ~= nil then
				if keypadModifier then
					keyCode = kc.keypadCharacterToKeyCode(fcpxCmd["characterString"])
				else
					keyCode = kc.characterStringToKeyCode(fcpxCmd["characterString"])
				end
			elseif fcpxHacks["character"] ~= nil then
				if keypadModifier then
					keyCode = kc.keypadCharacterToKeyCode(fcpxCmd["character"])
				else
					keyCode = kc.characterStringToKeyCode(fcpxCmd["character"])
				end
			end

			if keyCode ~= nil and keyCode ~= "" then
				shortcuts[#shortcuts + 1] = shortcut.new(modifiers, keyCode)
			end
		end

		activeCommands[id] = shortcuts
	end
	return shortcuts
end

--- cp.apple.finalcutpro:performShortcut(whichShortcut) -> boolean
--- Method
--- Performs a Final Cut Pro Shortcut
---
--- Parameters:
---  * whichShortcut - As per the Command Set name
---
--- Returns:
---  * true if successful otherwise false
function App:performShortcut(whichShortcut)
	self:launch()
	local activeCommandSet = self:getActiveCommandSet()

	local shortcuts = self:getCommandShortcuts(whichShortcut)

	if shortcuts and #shortcuts > 0 then
		shortcuts[1]:trigger()
	else
		return false
	end

	return true
end

----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
--
-- LANGUAGE
--
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------

--- cp.apple.finalcutpro.currentLanguage <cp.prop:string>
--- Field
--- The current language the FCPX is displayed in.
App.currentLanguage = prop(
	--------------------------------------------------------------------------------
	-- Getter:
	--------------------------------------------------------------------------------
	function(self)
		--------------------------------------------------------------------------------
		-- Caching:
		--------------------------------------------------------------------------------
		if self._currentLanguage ~= nil then
			--log.df("Using Final Cut Pro Language from Cache")
			return self._currentLanguage
		end

		--------------------------------------------------------------------------------
		-- If FCPX is already running, we determine the language off the menu:
		--------------------------------------------------------------------------------
		if self:isRunning() then
			local menuMap = self:menuBar():getMainMenu()
			local menuUI = self:menuBar():UI()
			if menuMap and menuUI and #menuMap >= 2 and #menuUI >=2 then
				local fileMap = menuMap[2]
				local fileUI = menuUI[2]
				local title = fileUI:attributeValue("AXTitle")
				for lang,name in pairs(fileMap) do
					if name == title then
						self._currentLanguage = lang
						return lang
					end
				end
			end
		end

		--------------------------------------------------------------------------------
		-- If FCPX is not running, we next try to determine the language using
		-- the Final Cut Pro Plist File:
		--------------------------------------------------------------------------------
		local appLanguages = self:getPreference("AppleLanguages", nil)
		if appLanguages and #appLanguages > 0 then
			local lang = appLanguages[1]
			if self:isSupportedLanguage(lang) then
				self._currentLanguage = lang
				return lang
			end
		end

		--------------------------------------------------------------------------------
		-- If that fails, we try and use the user locale:
		--------------------------------------------------------------------------------
		local success, userLocale = osascript.applescript("return user locale of (get system info)")
		if success and userLocale then
			userLocale = self:getSupportedLanguage(userLocale)
			if userLocale then
				self._currentLanguage = userLocale
				return userLocale
			end
		end

		--------------------------------------------------------------------------------
		-- If that also fails, we try and use NSGlobalDomain AppleLanguages:
		--------------------------------------------------------------------------------
		local output, status, _, _ = hs.execute("defaults read NSGlobalDomain AppleLanguages")
		if status then
			local appleLanguages = tools.lines(output)
			if next(appleLanguages) ~= nil then
				if appleLanguages[1] == "(" and appleLanguages[#appleLanguages] == ")" then
					for i=2, #appleLanguages - 1 do
						local line = appleLanguages[i]
						-- match the main country code
						local lang = line:match("^%s*\"?([%w%-]+)")
						-- switch "-" to "_"
						lang = self:getSupportedLanguage(lang:gsub("-", "_"))

						if lang then
							self._currentLanguage = lang
							return lang
						end
					end
				end
			end
		end

		--------------------------------------------------------------------------------
		-- If all else fails, assume it's English:
		--------------------------------------------------------------------------------
		self._currentLanguage = "en"
		return self._currentLanguage
	end,
	--------------------------------------------------------------------------------
	-- Setter:
	--------------------------------------------------------------------------------
	function(value, self, prop)
		if value == prop:get() then return end

		if value == nil then
			if self:getPreference("AppleLanguages") == nil then return end
			self:setPreference("AppleLanguages", nil)
		elseif self:isSupportedLanguage(value) then
			self:setPreference("AppleLanguages", {value})
		else
			error("Unsupported language: "..value)
		end
		self._currentLanguage = nil
		if self:isRunning() then
			self:restart(true)
		end
	end
):bind(App):monitor(App.isRunning)

--- cp.apple.finalcutpro:getSupportedLanguages() -> table
--- Method
--- Returns a table of languages Final Cut Pro supports
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table of languages Final Cut Pro supports
function App:getSupportedLanguages()
	return App.SUPPORTED_LANGUAGES
end

--- cp.apple.finalcutpro:isSupportedLanguage(language) -> boolean
--- Method
--- Checks if the provided `language` is supported by the app.
---
--- Parameters:
---  * `language`	- The language code to check. E.g. "en" or "zh_CN"
---
--- Returns:
---  * `true` if the language is supported.
function App:isSupportedLanguage(language)
	if language then
		local primary = language:match("(%w+)")
		for _,supported in ipairs(App.SUPPORTED_LANGUAGES) do
			if supported == language or supported == primary then
				return true
			end
		end
	end
	return false
end

--- cp.apple.finalcutpro:getSupportedLanguage(language) -> boolean
--- Method
--- Checks if the provided `language` is supported by the app and returns the actual support code, or `nil` if there is no supported version of the language.
---
--- For example, 'en_AU' is supported because 'en' is supported, so this returns 'en'.
--- However, while 'zh_CN' is supported, 'zh_TW' is not supported directly, so 'zh_CN' is returned for the former and `nil` for the latter.
---
--- Parameters:
---  * `language`	- The language code to check. E.g. "en" or "zh_CN"
---
--- Returns:
---  * `true` if the language is supported.
function App:getSupportedLanguage(language)
	if language then
		local primary = language:match("(%w+)")
		for _,supported in ipairs(App.SUPPORTED_LANGUAGES) do
			if supported == language or supported == primary then
				return supported
			end
		end
	end
	return nil
end

--- cp.apple.finalcutpro:getFlexoLanguages() -> table
--- Method
--- Returns a table of languages Final Cut Pro's Flexo Framework supports
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table of languages Final Cut Pro supports
function App:getFlexoLanguages()
	return App.FLEXO_LANGUAGES
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                               W A T C H E R S                              --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--- cp.apple.finalcutpro:watch(events) -> string
--- Method
--- Watch for events that happen in the application.
--- The optional functions will be called when the window is shown or hidden, respectively.
---
--- Parameters:
---  * `events` - A table of functions with to watch. These may be:
--- 	* `active`		- Triggered when the application is the active application.
--- 	* `inactive`	- Triggered when the application is no longer the active application.
---     * `launched		- Triggered when the application is launched.
---     * `terminated	- Triggered when the application has been closed.
--- 	* `preferences`	- Triggered when the application preferences are updated.
---
--- Returns:
---  * An ID which can be passed to `unwatch` to stop watching.
function App:watch(events)
	return self._watchers:watch(events)
end

--- cp.apple.finalcutpro:unwatch(id) -> boolean
--- Method
--- Stop watching for events that happen in the application for the specified ID.
---
--- Parameters:
---  * `id` 	- The ID object which was returned from the `watch(...)` function.
---
--- Returns:
---  * `true` if the ID was watching and has been removed.
function App:unwatch(id)
	return self._watchers:unwatch(id)
end

function matchesApp(bundleID, appName)
	return bundleID == App.BUNDLE_ID or bundleID == App.BUNDLE_ID_TRIAL or
		bundleID == nil and (appName == "Final Cut Pro" or appName == "Final Cut Pro Trial")
end

-- cp.apple.finalcutpro:_initWatchers() -> none
-- Method
-- Initialise all the various Final Cut Pro Watchers.
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
function App:_initWatchers()

	if not self._watchers then
		--log.df("Setting up Final Cut Pro Watchers...")
		self._watchers = watcher.new("active", "inactive", "launched", "terminated", "preferences")
	end

	--------------------------------------------------------------------------------
	-- Setup Application Watcher:
	--------------------------------------------------------------------------------
	--log.df("Setting up Application Watcher...")
	self._appWatcher = applicationwatcher.new(
		function(appName, eventType, application)
			local bundleID = application:bundleID()
			-- log.df("Application event: bundleID: %s; appName: '%s'; type: %s", bundleID, appName, eventType)
			if matchesApp(bundleID, appName) then
				if eventType == applicationwatcher.activated then
					timer.doAfter(0.01, function()
						self.isShowing:update()
						self.isFrontmost:update()
					end)
					self._watchers:notify("active")
					return
				elseif eventType == applicationwatcher.deactivated then
					timer.doAfter(0.01, function()
						self.isShowing:update()
						self.isFrontmost:update()
					end)
					self._watchers:notify("inactive")
					return
				elseif eventType == applicationwatcher.launched then
					timer.doAfter(0.01, function()
						self.application:update()
						self.isRunning:update()
						self.isFrontmost:update()
					end)
					self._watchers:notify("launched")
					return
				elseif eventType == applicationwatcher.terminated then
					timer.doAfter(0.01, function()
						self.application:update()
						self.isRunning:update()
						self.isFrontmost:update()
					end)
					self._watchers:notify("terminated")
					return
				end
			end
		end
	):start()

	--------------------------------------------------------------------------------
	-- Final Cut Pro Window becomes visible:
	--------------------------------------------------------------------------------
	windowfilter:subscribe("windowVisible", function()
		App.isModalDialogOpen:update()
	end)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                   D E V E L O P M E N T      T O O L S                     --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function App:_listWindows()
	log.d("Listing FCPX windows:")
	self:show()
	local windows = self:windowsUI()
	for i,w in ipairs(windows) do
		log.df(format("%7d", i)..": "..self:_describeWindow(w))
	end

	log.df("")
	log.df("   Main: "..self:_describeWindow(self:UI():mainWindow()))
	log.df("Focused: "..self:_describeWindow(self:UI():focusedWindow()))
end

function App:_describeWindow(w)
	return "title: "..inspect(w:attributeValue("AXTitle"))..
	       "; role: "..inspect(w:attributeValue("AXRole"))..
		   "; subrole: "..inspect(w:attributeValue("AXSubrole"))..
		   "; modal: "..inspect(w:attributeValue("AXModal"))
end

return App:init()
