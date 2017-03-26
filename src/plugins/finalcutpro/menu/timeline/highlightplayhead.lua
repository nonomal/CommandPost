--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                  H I G H L I G H T     P L A Y H E A D                     --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--- The AUTOMATION > 'Options' menu section

--------------------------------------------------------------------------------
--
-- CONSTANTS:
--
--------------------------------------------------------------------------------
local PRIORITY = 30000

--------------------------------------------------------------------------------
--
-- THE PLUGIN:
--
--------------------------------------------------------------------------------
local plugin = {
	id				= "finalcutpro.menu.timeline.highlightplayhead",
	group			= "finalcutpro",
	dependencies	= {
		["finalcutpro.menu.timeline"] = "timeline"
	}
}

--------------------------------------------------------------------------------
-- INITIALISE PLUGIN:
--------------------------------------------------------------------------------
function plugin.init(dependencies)
	return dependencies.timeline:addMenu(PRIORITY, function() return i18n("highlightPlayhead") end)
end

return plugin