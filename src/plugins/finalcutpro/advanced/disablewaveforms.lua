--- === plugins.finalcutpro.advanced.disablewaveforms ===
---
--- Disable Waveforms Plugin.

--------------------------------------------------------------------------------
--
-- EXTENSIONS:
--
--------------------------------------------------------------------------------
local require = require

--------------------------------------------------------------------------------
-- CommandPost Extensions:
--------------------------------------------------------------------------------
local dialog            = require("cp.dialog")
local fcp               = require("cp.apple.finalcutpro")
local i18n              = require("cp.i18n")
local prop              = require("cp.prop")

--------------------------------------------------------------------------------
--
-- THE MODULE:
--
--------------------------------------------------------------------------------
local mod = {}

--- plugins.finalcutpro.advanced.disablewaveforms.disableWaveform <cp.prop: boolean>
--- Variable
--- Waveforms Disabled?
mod.disableWaveform = prop.new(function()
    --------------------------------------------------------------------------------
    -- Getter:
    --------------------------------------------------------------------------------
    return not fcp.preferences.FFAudioDisableWaveformDrawing
end, function(value)
    --------------------------------------------------------------------------------
    -- Setter:
    --------------------------------------------------------------------------------
    if value then
        fcp.preferences.FFAudioDisableWaveformDrawing = false
    else
        fcp.preferences.FFAudioDisableWaveformDrawing = true
    end
end)

--------------------------------------------------------------------------------
--
-- THE PLUGIN:
--
--------------------------------------------------------------------------------
local plugin = {
    id              = "finalcutpro.advanced.disablewaveforms",
    group           = "finalcutpro",
    dependencies    = {
        ["finalcutpro.commands"]        = "fcpxCmds",
        ["finalcutpro.preferences.manager"] = "prefs",
    }
}

--------------------------------------------------------------------------------
-- INITIALISE PLUGIN:
--------------------------------------------------------------------------------
function plugin.init(deps)

    --------------------------------------------------------------------------------
    -- Setup Menubar Preferences Panel:
    --------------------------------------------------------------------------------
    if deps.prefs.panel then
        deps.prefs.panel
            --------------------------------------------------------------------------------
            -- Add Preferences Checkbox:
            --------------------------------------------------------------------------------
            :addCheckbox(2204,
            {
                label = i18n("enableWaveformDrawing"),
                onchange = function(_, params) mod.disableWaveform(params.checked) end,
                checked = function() return mod.disableWaveform() end,
            })
    end

    --------------------------------------------------------------------------------
    -- Setup Command:
    --------------------------------------------------------------------------------
    if deps.fcpxCmds then
        deps.fcpxCmds:add("cpDisableWaveforms")
            :whenActivated(function() mod.enabled:toggle() end)
    end

    return mod

end

return plugin
