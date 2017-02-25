--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                      F E E D B A C K   M O D U L E                         --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
-- Module created by Chris Hocking (https://github.com/latenitefilms).
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- THE MODULE:
--------------------------------------------------------------------------------

local mod = {}

--------------------------------------------------------------------------------
-- EXTENSIONS:
--------------------------------------------------------------------------------

local application								= require("hs.application")
local console									= require("hs.console")
local base64									= require("hs.base64")
local drawing									= require("hs.drawing")
local geometry									= require("hs.geometry")
local screen									= require("hs.screen")
local timer										= require("hs.timer")
local urlevent									= require("hs.urlevent")
local webview									= require("hs.webview")

local dialog									= require("cp.dialog")
local fcp										= require("cp.finalcutpro")
local metadata									= require("cp.metadata")
local plugins									= require("cp.plugins")
local template									= require("cp.template")
local tools										= require("cp.tools")

local log										= require("hs.logger").new("welcome")

--------------------------------------------------------------------------------
-- SETTINGS:
--------------------------------------------------------------------------------

mod.defaultWidth 		= 365
mod.defaultHeight 		= 438
mod.defaultTitle 		= metadata.scriptName .. " " .. i18n("feedback")
mod.quitOnComplete		= false

--------------------------------------------------------------------------------
-- GET SCREENSHOTS:
--------------------------------------------------------------------------------
local function getScreenshotsAsBase64()

	local screenshots = {}
	local allScreens = screen.allScreens()
    for i, v in ipairs(allScreens) do
    	local temporaryFileName = os.tmpname()
    	v:shotAsJPG(temporaryFileName)
    	local screenshotFile = io.open(temporaryFileName, "r")
	    local screenshotFileContents = screenshotFile:read("*all")
   		screenshotFile:close()
    	os.remove(temporaryFileName)
    	screenshots[#screenshots + 1] = base64.encode(screenshotFileContents)
    end

	return screenshots

end

--------------------------------------------------------------------------------
-- GENERATE HTML:
--------------------------------------------------------------------------------
local function generateHTML()

	local env = template.defaultEnv()

	env.i18n = i18n
	env.userFullName = metadata.get("userFullName", i18n("fullName"))
	env.userEmail = metadata.get("userEmail", i18n("emailAddress"))

	--------------------------------------------------------------------------------
	-- Get Console output:
	--------------------------------------------------------------------------------
	env.consoleOutput = console.getConsole(true):convert("html")

	--------------------------------------------------------------------------------
	-- Get screenshots of all screens:
	--------------------------------------------------------------------------------
	env.screenshots = getScreenshotsAsBase64()

	return template.compileFile(metadata.scriptPath .. "/cp/feedback/html/feedback.htm", env)

end

--------------------------------------------------------------------------------
-- CREATE THE FEEDBACK SCREEN:
--------------------------------------------------------------------------------
function mod.showFeedback(quitOnComplete)

	--------------------------------------------------------------------------------
	-- Quit on Complete?
	--------------------------------------------------------------------------------
	if quitOnComplete == true then
		mod.quitOnComplete = true
	else
		mod.quitOnComplete = false
	end

	--------------------------------------------------------------------------------
	-- Centre on Screen:
	--------------------------------------------------------------------------------
	local screenFrame = screen.mainScreen():frame()
	local defaultRect = {x = (screenFrame['w']/2) - (mod.defaultWidth/2), y = (screenFrame['h']/2) - (mod.defaultHeight/2), w = mod.defaultWidth, h = mod.defaultHeight}

	--------------------------------------------------------------------------------
	-- Setup Web View:
	--------------------------------------------------------------------------------
	mod.feedbackWebView = webview.new(defaultRect, {developerExtrasEnabled = true})
		:windowStyle({"titled"})
		:shadow(true)
		:allowNewWindows(false)
		:allowTextEntry(true)
		:windowTitle(mod.defaultTitle)
		:html(generateHTML())

	--------------------------------------------------------------------------------
	-- Setup URL Events:
	--------------------------------------------------------------------------------
	mod.urlEvent = urlevent.bind("feedback", function(eventName, params)

		if params["action"] == "cancel" then
			mod.feedbackWebView:delete()
			mod.feedbackWebView = nil
		elseif params["action"] == "error" then
			dialog.displayMessage("Something went wrong when trying to send the form.")
			mod.feedbackWebView:delete()
			mod.feedbackWebView = nil
		elseif params["action"] == "done" then
			if mod.quitOnComplete then
				application.applicationForPID(hs.processInfo["processID"]):kill()
			else
				mod.feedbackWebView:delete()
				mod.feedbackWebView = nil
			end
		end

	end)

	--------------------------------------------------------------------------------
	-- Show Welcome Screen:
	--------------------------------------------------------------------------------
	mod.feedbackWebView:show()
	timer.doAfter(0.1, function() mod.feedbackWebView:hswindow():focus() end)

end

--------------------------------------------------------------------------------
-- END OF MODULE:
--------------------------------------------------------------------------------
return mod