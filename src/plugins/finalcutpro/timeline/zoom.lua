--- === plugins.finalcutpro.timeline.zoom ===
---
--- Action for changing Final Cut Pro's Timeline Zoom Level

local require           = require

local timer             = require "hs.timer"

local deferred          = require "cp.deferred"
local fcp               = require "cp.apple.finalcutpro"
local i18n              = require "cp.i18n"

local delayed           = timer.delayed

local plugin = {
    id = "finalcutpro.timeline.zoom",
    group = "finalcutpro",
    dependencies = {
        ["finalcutpro.commands"]    = "fcpxCmds",
    }
}

function plugin.init(deps)
    --------------------------------------------------------------------------------
    -- Only load plugin if Final Cut Pro is supported:
    --------------------------------------------------------------------------------
    if not fcp:isSupported() then return end

    local fcpxCmds = deps.fcpxCmds
    local appearance = fcp.timeline.toolbar.appearance

    local appearancePopUpCloser = delayed.new(1, function()
        appearance:hide()
    end)

    local zoomShift = 0
    local updateZoom = deferred.new(0.0000001):action(function()
        appearance:show()
        appearance.zoomAmount:shiftValue(zoomShift)
        zoomShift = 0
        appearancePopUpCloser:start()
    end)

    local zoomAbsolute
    local updateZoomAbsolute = deferred.new(0.0000001):action(function()
        appearance:show()
        appearance.zoomAmount:value(zoomAbsolute)
        appearancePopUpCloser:start()
    end)

    fcpxCmds
        :add("timelineZoomIncrease")
        :whenActivated(function()
            zoomShift = zoomShift + 0.2
            updateZoom()
        end)
        :titled(i18n("timelineZoom") .. " " .. i18n("increase"))
        :subtitled(i18n("controlsTimelineZoomViaTheAppearancePopup"))

    fcpxCmds
        :add("timelineZoomDecrease")
        :whenActivated(function()
            zoomShift = zoomShift - 0.2
            updateZoom()
        end)
        :titled(i18n("timelineZoom") .. " " .. i18n("decrease"))
        :subtitled(i18n("controlsTimelineZoomViaTheAppearancePopup"))

    for i=1, 10, 0.5 do
        fcpxCmds
        :add("timelineZoom" .. i)
        :whenActivated(function()
            zoomAbsolute = i
            updateZoomAbsolute()
        end)
        :titled(i18n("timelineZoom") .. " " .. i)
        :subtitled(i18n("controlsTimelineZoomViaTheAppearancePopup"))
    end

end

return plugin
