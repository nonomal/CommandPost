--- === plugins.zoom.shortcuts ===
---
--- Trigger Zoom Shortcuts

local require                   = require

--local log                       = require "hs.logger".new "actions"

local application               = require "hs.application"
local image                     = require "hs.image"

local config                    = require "cp.config"
local i18n                      = require "cp.i18n"
local tools                     = require "cp.tools"

local imageFromPath             = image.imageFromPath
local infoForBundleID           = application.infoForBundleID
local keyStroke                 = tools.keyStroke
local launchOrFocusByBundleID   = application.launchOrFocusByBundleID
local playErrorSound            = tools.playErrorSound

local mod = {}

local plugin = {
    id              = "zoom.shortcuts",
    group           = "zoom",
    dependencies    = {
        ["core.action.manager"] = "actionmanager",
    }
}

function plugin.init(deps)
    --------------------------------------------------------------------------------
    -- Only load if Zoom is installed:
    --------------------------------------------------------------------------------
    if not infoForBundleID("us.zoom.xos") then return end

    --------------------------------------------------------------------------------
    -- Shortcuts:
    --
    -- TODO: This needs to be i18n'ified.
    --------------------------------------------------------------------------------
    local shortcuts = {
        {
            title = "Close the current window",
            modifiers = {"cmd"},
            character = "w"
        },
        {
            title = "Switch to portrait or landscape View, depending on current view",
            modifiers = {"cmd"},
            character = "l"
        },
        {
            title = "Switch from one tab to the next",
            modifiers = {"control"},
            character = "t"
        },
        {
            title = "Join meeting",
            modifiers = {"command"},
            character = "j"
        },
        {
            title = "Start meeting",
            modifiers = {"cmd","control"},
            character = "v"
        },
        {
            title = "Schedule meeting",
            modifiers = {"cmd"},
            character = "j"
        },
        {
            title = "Screen share using direct share",
            modifiers = {"cmd","control"},
            character = "s"
        },
        {
            title = "Mute/unmute audio ",
            modifiers = {"cmd","shift"},
            character = "a"
        },
        {
            title = "Mute audio for everyone except the host (only available to the host)",
            modifiers = {"cmd","control"},
            character = "m"
        },
        {
            title = "Unmute audio for everyone except host (only available to the host)",
            modifiers = {"cmd","control"},
            character = "u"
        },
        {
            title = "Start/stop video",
            modifiers = {"command", "shift"},
            character = "v"
        },
        {
            title = "Switch camera",
            modifiers = {"cmd","shift"},
            character = "n"
        },
        {
            title = "Start/stop screen share",
            modifiers = {"cmd","shift"},
            character = "s"
        },
        {
            title = "Pause or resume screen share",
            modifiers = {"cmd","shift"},
            character = "t"
        },
        {
            title = "Start local recording",
            modifiers = {"cmd","shift"},
            character = "r"
        },
        {
            title = "Start cloud recording",
            modifiers = {"command", "shift"},
            character = "c"
        },
        {
            title = "Pause or resume recording",
            modifiers = {"cmd","shift"},
            character = "p"
        },
        {
            title = "Switch to active speaker view or gallery view, depending on current view",
            modifiers = {"command", "shift"},
            character = "w"
        },
        {
            title = "View previous 25 participants in gallery view",
            modifiers = {"control"},
            character = "p"
        },
        {
            title = "View next 25 participants in gallery view",
            modifiers = {"control"},
            character = "n"
        },
        {
            title = "Display/hide participants panel",
            modifiers = {"command"},
            character = "u"
        },
        {
            title = "Show/hide in-meeting chat panel",
            modifiers = {"cmd", "shift"},
            character = "h"
        },
        {
            title = "Open invite window",
            modifiers = {"command"},
            character = "i"
        },
        {
            title = "Raise hand/lower hand",
            modifiers = {"option"},
            character = "y"
        },
        {
            title = "Gain remote control",
            modifiers = {"control","shift"},
            character = "r"
        },
        {
            title = "Stop remote control",
            modifiers = {"control","shift"},
            character = "g"
        },
        {
            title = "Enter or exit full screen",
            modifiers = {"command", "shift"},
            character = "f"
        },
        {
            title = "Switch to minimal window",
            modifiers = {"command", "shift"},
            character = "m"
        },
        {
            title = "Show/hide meeting controls",
            modifiers = {"control", "option", "command"},
            character = "h"
        },
        {
            title = "Toggle the Always Show meeting controls option in General settings",
            modifiers = {"control"},
            character = [[\]]
        },
        {
            title = "Prompt to End or Leave Meeting",
            modifiers = {"command"},
            character = "w"
        },
        {
            title = "Jump to chat with someone",
            modifiers = {"command"},
            character = "k"
        },
        {
            title = "Screenshot",
            modifiers = {"command"},
            character = "t"
        },
        {
            title = "Call highlighted phone number",
            modifiers = {"control","shift"},
            character = "c"
        },
        {
            title = "Accept inbound call",
            modifiers = {"control", "shift"},
            character = "a"
        },
        {
            title = "Decline inbound call",
            modifiers = {"control", "shift"},
            character = "d"
        },
        {
            title = "End current call",
            modifiers = {"control", "shift"},
            character = "e"
        },
        {
            title = "Mute/unmute mic",
            modifiers = {"control", "shift"},
            character = "m"
        },
       {
            title = "Hold/unhold call",
            modifiers = {"command", "shift"},
            character = "h"
        },
    }

    --------------------------------------------------------------------------------
    -- Setup Handler:
    --------------------------------------------------------------------------------
    local icon = imageFromPath(config.basePath .. "/plugins/core/console/images/shortcut.png")
    local actionmanager = deps.actionmanager
    mod._handler = actionmanager.addHandler("zoom_shortcuts", "zoom")
        :onChoices(function(choices)
            for _, v in pairs(shortcuts) do
                choices
                    :add(v.title)
                    :subText("Triggers a shortcut key within Zoom")
                    :params({
                        modifiers = v.modifiers,
                        character = v.character,
                        id = v.title
                    })
                    :image(icon)
                    :id("zoom_shortcuts_" .. "pressControl")
            end
        end)
        :onExecute(function(action)
            if launchOrFocusByBundleID("us.zoom.xos") then
                keyStroke(action.modifiers, action.character)
            else
                playErrorSound()
            end
        end)
        :onActionId(function(params)
            return "zoom_shortcuts" .. params.id
        end)
    return mod
end

return plugin
