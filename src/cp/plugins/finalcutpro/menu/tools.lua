--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                        T O O L S     M E N U                               --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--- The TOOLS menu section.

--------------------------------------------------------------------------------
-- EXTENSIONS:
--------------------------------------------------------------------------------
local metadata					= require("cp.metadata")

--------------------------------------------------------------------------------
-- CONSTANTS:
--------------------------------------------------------------------------------
local PRIORITY 					= 3000
local SETTING 					= metadata.settingsPrefix .. ".menubarToolsEnabled"

--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS:
--------------------------------------------------------------------------------
	local function isSectionDisabled()
		local setting = metadata.get(SETTING)
		if setting ~= nil then
			return not setting
		else
			return false
		end
	end

	local function toggleSectionDisabled()
		local menubarEnabled = metadata.get(SETTING)
		metadata.set(SETTING, not menubarEnabled)
	end

--------------------------------------------------------------------------------
-- THE PLUGIN:
--------------------------------------------------------------------------------
local plugin = {}

	--------------------------------------------------------------------------------
	-- DEPENDENCIES:
	--------------------------------------------------------------------------------
	plugin.dependencies = {
		["cp.plugins.core.menu.manager"] 				= "manager",
		["cp.plugins.core.menu.preferences.menubar"] 	= "menubar",
	}

	--------------------------------------------------------------------------------
	-- INITIALISE PLUGIN:
	--------------------------------------------------------------------------------
	function plugin.init(dependencies)
		-- Create the 'SHORTCUTS' section
		local shortcuts = dependencies.manager.addSection(PRIORITY)

		-- Disable the section if the shortcuts option is disabled
		shortcuts:setDisabledFn(isSectionDisabled)

		-- Add the separator and title for the section.
		shortcuts:addSeparator(0)
			:addItem(1, function()
				return { title = string.upper(i18n("tools")) .. ":", disabled = true }
			end)

		-- Create the menubar preferences item
		dependencies.menubar:addItem(PRIORITY, function()
			return { title = i18n("showTools"),	fn = toggleSectionDisabled, checked = not isSectionDisabled()}
		end)

		return shortcuts
	end

return plugin