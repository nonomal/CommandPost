--- === plugins.finalcutpro.timeline.movetoplayhead ===
---
--- Move To Playhead.

local require = require

local log               = require("hs.logger").new("selectalltimelineclips")

local Do                = require("cp.rx.go.Do")
local fcp               = require("cp.apple.finalcutpro")

local plugin = {
    id = "finalcutpro.timeline.movetoplayhead",
    group = "finalcutpro",
    dependencies = {
        ["finalcutpro.commands"]            = "fcpxCmds",
        ["finalcutpro.pasteboard.manager"]  = "pasteboardManager",
    }
}

function plugin.init(deps)
    --------------------------------------------------------------------------------
    -- Only load plugin if Final Cut Pro is supported:
    --------------------------------------------------------------------------------
    if not fcp:isSupported() then return end

    --------------------------------------------------------------------------------
    -- Link to dependancies:
    --------------------------------------------------------------------------------
    local pasteboardManager = deps.pasteboardManager

    --------------------------------------------------------------------------------
    -- Setup Command:
    --------------------------------------------------------------------------------
    deps.fcpxCmds
        :add("cpMoveToPlayhead")
        :whenActivated(function()
            Do(pasteboardManager.stopWatching)
                :Then(fcp:doShortcut("Cut"))
                :Then(fcp:doShortcut("Paste"))
                :Catch(function(message)
                    log.ef("doMoveToPlayhead: %s", message)
                end)
                :Finally(function()
                    Do(pasteboardManager.startWatching):After(2000)
                end)
                :Label("plugins.finalcutpro.timeline.movetoplayhead")
                :Now()
        end)

    return plugin
end

return plugin
