--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                     M E D I A    I M P O R T    M E N U                    --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--- The Media Import menu section.

--------------------------------------------------------------------------------
-- EXTENSIONS:
--------------------------------------------------------------------------------
local metadata					= require("cp.metadata")

--------------------------------------------------------------------------------
-- CONSTANTS:
--------------------------------------------------------------------------------
local PRIORITY 					= 1000
local SETTING 					= "menubarMediaImportEnabled"

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
				return { title = string.upper(i18n("mediaImport")) .. ":", disabled = true }
			end)

		-- Create the menubar preferences item
		dependencies.menubar:addItem(PRIORITY, function()
			return { title = i18n("show") .. " " .. i18n("mediaImport"),	fn = toggleSectionDisabled, checked = not isSectionDisabled()}
		end)

		return shortcuts
	end

return plugin