--- === plugins.finalcutpro.workflowextension ===
---
--- Workflow Extension Helper
---
--- Commands that can be SENT to the Workflow Extension:
---
---  PING           - Send a ping
---  INCR f         - Increment by Frame        (where f is number of frames)
---  DECR f         - Decrement by Frame        (where f is number of frames)
---  GOTO s         - Goto Timeline Position    (where s is number of seconds)
---
---
---  Commands that can be RECEIVED from the Workflow Extension:
---
---  DONE           - Connection successful
---  DEAD           - Server is shutting down
---  PONG           - Recieve a pong
---  PLHD s         - The playhead time has changed                (where s is playhead position in seconds)
---
---  SEQC sequenceName || startTime || duration || frameDuration || container || timecodeFormat || objectType
---     - The active sequence has changed
---       (sequenceName is a string)
---       (startTime in seconds)
---       (duration in seconds)
---       (frameDuration in seconds)
---       (container as a string)
---       (timecodeFormat as a string: DropFrame, NonDropFrame, Unspecified or Unknown)
---       (objectType as a string: Event, Library, Project, Sequence or Unknown)
---
---  RNGC startTime || duration
---     - The active sequence time range has changed
---       (startTime in seconds)
---       (duration in seconds)

local require           = require

local log               = require "hs.logger".new "workflowextension"

local notify            = require "hs.notify"
local socket            = require "hs.socket"
local task              = require "hs.task"
local timer             = require "hs.timer"

local config            = require "cp.config"
local fcp               = require "cp.apple.finalcutpro"
local i18n              = require "cp.i18n"
local tools             = require "cp.tools"

local delayed           = timer.delayed
local doAfter           = timer.doAfter

local mod = {}

-- SOCKET_PORT -> number
-- Constant
-- The socket port we use to communicate with the CommandPost Workflow Extension
--
-- Notes:
--  * This is defined within the Workflow Extension
local SOCKET_PORT = 43426

-- HOW_OFTEN_TO_PING_IN_SECONDS -> number
-- Constant
-- How often should we send a ping to the server?
local HOW_OFTEN_TO_PING_IN_SECONDS = 30

-- HOW_LONG_TO_WAIT_FOR_PONG_IN_SECONDS -> number
-- Constant
-- How long in seconds should we wait for a pong to come back?
local HOW_LONG_TO_WAIT_FOR_PONG_IN_SECONDS = 2

-- NUMBER_OF_PLAYHEAD_INCREMENTS -> number
-- Constant
-- The number of playhead action increments
local NUMBER_OF_PLAYHEAD_INCREMENTS = 100

-- RESTORE_SKIMMING_DELAY -> number
-- Constant
-- The number of seconds until we try and restore skimming
local RESTORE_SKIMMING_DELAY = 1

--- plugins.finalcutpro.workflowextension.hasWorkflowExtensionBeenAddedVersion -> cp.prop
--- Field
--- Returns the CommandPost Version String for the last time the Workflow Extension was added.
mod.hasWorkflowExtensionBeenAddedVersion = config.prop("workflowExtension.AddedVersion", "")

--- plugins.finalcutpro.workflowextension.hasWorkflowExtensionBeenMovedVersion -> cp.prop
--- Field
--- Returns the CommandPost Version String for the last time the Workflow Extension was moved.
mod.hasWorkflowExtensionBeenMovedVersion = config.prop("workflowExtension.MovedVersion", "")

--- plugins.finalcutpro.workflowextension.connected -> boolean
--- Variable
--- Is CommandPost connected to the Workflow Extension?
mod.connected = false

--- plugins.finalcutpro.workflowextension.connected -> boolean
--- Variable
--- Is CommandPost connecting to the Workflow Extension?
mod.connecting = false

-- pongRecieved -> boolean
-- Variable
-- Has a pong been received yet?
local pongRecieved = false

--- plugins.finalcutpro.workflowextension.lastPlayheadPosition -> string
--- Variable
--- The last playhead position.
mod.lastPlayheadPosition = nil

-- commandHandler -> table
-- Variable
-- A table that contains all the functions that are triggered by the Workflow Extension commands.
local commandHandler = {
    ["DONE"] =  function()
                    log.df("[Workflow Extension] Connected")
                    mod.connected = true
                    mod.connecting = false
                end,
    ["DEAD"] =  function()
                    log.df("[Workflow Extension] Server Closed")
                    mod.disconnect()
                end,
    ["PONG"] =  function()
                    --log.df("[Workflow Extension] Pong Recieved!")
                    mod.connected = true
                    pongRecieved = true
                end,
    ["PLHD"] =  function(data)
                    --------------------------------------------------------------------------------
                    -- Update lastPlayheadPosition:
                    --------------------------------------------------------------------------------
                    if data then
                        local trimmedData = data:sub(6)
                        mod.lastPlayheadPosition = trimmedData and trimmedData:gsub("[\n\r]", "")
                    end
                    --log.df("mod.lastPlayheadPosition: '%s'", mod.lastPlayheadPosition)

                    --------------------------------------------------------------------------------
                    -- Let's update the isPlaying prop in the unlikely case that we haven't already
                    -- updated it via other means at this point in time:
                    --------------------------------------------------------------------------------
                    fcp.viewer.isPlaying:update()

                    --log.df("[Workflow Extension] Playhead Timeline Changed")
                end,
    ["SEQC"] =  function()
                    --TODO: Actually do something with this data.
                    --log.df("[Workflow Extension] Active Project has Changed: %s", hs.inspect(data))
                end,
    ["RNGC"] =  function()
                    --TODO: Actually do something with this data.
                    --log.df("[Workflow Extension] Active Project Duration and/or Start Time has changed: %s", hs.inspect(data))
                end,
}

--- plugins.finalcutpro.workflowextension.connectionCallback() -> none
--- Function
--- Triggers when the Socket makes a connection.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.connectionCallback()
    --------------------------------------------------------------------------------
    -- We're now connected!
    --------------------------------------------------------------------------------
    --log.df("[Workflow Extension] Socket connection established")

    --------------------------------------------------------------------------------
    -- Removed the Connecting Notification:
    --------------------------------------------------------------------------------
    if mod.connectingNotification then
        mod.connectingNotification:withdraw()
        mod.connectingNotification = nil
    end

    --------------------------------------------------------------------------------
    -- Create a Ping Timer Check if it doesn't exist:
    --------------------------------------------------------------------------------
    if not mod.pingTimerCheck then
        mod.pingTimerCheck = doAfter(HOW_LONG_TO_WAIT_FOR_PONG_IN_SECONDS, function()
            if not pongRecieved then
                --------------------------------------------------------------------------------
                -- No pong detected:
                --------------------------------------------------------------------------------
                log.df("[Workflow Extension] Failed to ping server.")
                mod.disconnect()
                mod.connect()
            else
                --------------------------------------------------------------------------------
                -- Set off the next ping:
                --------------------------------------------------------------------------------
                mod.pingTimer:start()
            end
        end)
    end

    --------------------------------------------------------------------------------
    -- Create a Ping Timer if it doesn't exist:
    --------------------------------------------------------------------------------
    if not mod.pingTimer then
        mod.pingTimer = doAfter(HOW_OFTEN_TO_PING_IN_SECONDS, function()
            pongRecieved = false
            mod.ping()
            mod.pingTimerCheck:start()
        end)
    end

    --------------------------------------------------------------------------------
    -- Let's set off the pinging:
    --------------------------------------------------------------------------------
    doAfter(1, function()
        mod.pingTimer:start()
        mod.pingTimer:fire()
    end)

    --------------------------------------------------------------------------------
    -- Read the contents of the socket:
    --------------------------------------------------------------------------------
    if mod.socketClient and mod.socketClient:connected() then
        mod.socketClient:read("\r\n")
    end
end

--- plugins.finalcutpro.workflowextension.callback() -> none
--- Function
--- Triggers when the Socket receives data.
---
--- Parameters:
---  * data - The incoming data.
---
--- Returns:
---  * None
function mod.callback(data)
    --------------------------------------------------------------------------------
    -- Get the command and send it to the command handler:
    --------------------------------------------------------------------------------
    local command = data and data:sub(1, 4)
    if commandHandler[command] then
        commandHandler[command](data)
    else
        log.ef("[Workflow Extension] Unknown Command Received: %s", command)
    end

    --------------------------------------------------------------------------------
    -- Read the next message:
    --------------------------------------------------------------------------------
    if mod.socketClient and mod.socketClient:connected() then
        mod.socketClient:read("\r\n")
    end
end

--- plugins.finalcutpro.workflowextension.connect() -> none
--- Function
--- Connect to the Workflow Extension Socket Server.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.connect()
    if not mod.socketClient then
        --log.df("[Workflow Extension] Creating Socket Client")
        mod.socketClient = socket.new()
        mod.socketClient:setCallback(mod.callback)
    end

    if not mod.socketClient:connected() then
        if not mod.connecting then
            fcp.commandPostWorkflowExtension:show()
            --log.df("[Workflow Extension] Connecting to Socket Server")
            mod.socketClient:connect("localhost", SOCKET_PORT, mod.connectionCallback)
            mod.connecting = true

            -- Abort after 5 seconds:
            mod.abortTimer = doAfter(5, function()
                if not mod.socketClient or (mod.socketClient and not mod.socketClient:connected()) then
                    log.df("[Workflow Extension] Failed to connect after 5 seconds")
                    mod.disconnect()
                    fcp.commandPostWorkflowExtension:hide()
                    mod.connect()
                --else
                    --log.df("[Workflow Extension] Already connected - did not need the abort timer.")
                end
            end)
        end
    end
end

--- plugins.finalcutpro.workflowextension.disconnect() -> none
--- Function
--- Disconnects from the Workflow Extension Socket Server.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.disconnect()
    mod.connecting = false
    mod.connected = false
    if mod.pingTimer then
        mod.pingTimer:stop()
        mod.pingTimer = nil
    end
    if mod.pingTimerCheck then
        mod.pingTimerCheck:stop()
        mod.pingTimerCheck = nil
    end
    if mod.socketClient then
        mod.socketClient:disconnect()
        mod.socketClient = nil
    end
    collectgarbage()
    collectgarbage()
end

--- plugins.finalcutpro.workflowextension.skimmingRestoreTimer -> hs.timer.delayed
--- Variable
--- Delayed Timer to Connect to Workflow Extension
mod.delayedConnect = delayed.new(5, function()
    --log.df("[Workflow Extension] Send Command Triggered - Lets try and connect...")
    mod.connect()
end)

--- plugins.finalcutpro.workflowextension.sendCommand(command) -> none
--- Function
--- Sends a command to the Workflow
---
--- Parameters:
---  * command - The command as a string
---
--- Returns:
---  * None
function mod.sendCommand(command)
    if mod.socketClient and mod.socketClient:connected() then
        mod.socketClient:send(command .. "\r\n")
    else
        if not mod.connectingNotification  then
            mod.connectingNotification = notify.new(function()
                --------------------------------------------------------------------------------
                -- Restart Final Cut Pro:
                --------------------------------------------------------------------------------
                fcp.doRestart():Now()
            end, {
                title = i18n("startingWorkflowExtension"),
                subTitle = "",
                informativeText = i18n("startingWorkflowExtensionDescription"),
                autoWithdraw = false,
                withdrawAfter = 0,
                alwaysPresent = true,
            }):send()
        end
        if not mod.delayedConnect:running() then
            mod.connect()
        end
        mod.delayedConnect:start()
    end
end

--- plugins.finalcutpro.workflowextension.wasSkimmingEnabled -> boolean
--- Variable
--- Was the Skimming Feature enabled?
mod.wasSkimmingEnabled = false

--- plugins.finalcutpro.workflowextension.skimmingRestoreTimer -> hs.timer.delayed
--- Variable
--- Delayed Timer to Restore the Skimming Feature (if required)
mod.skimmingRestoreTimer = delayed.new(RESTORE_SKIMMING_DELAY, function()
    if mod.wasSkimmingEnabled then
       fcp:isSkimmingEnabled(true)
    end
end)

-- saveSkimmingState() -> none
-- Function
-- Saves the skimming state if we're not already waiting to restore it
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
local function saveSkimmingState()
    if not mod.skimmingRestoreTimer:running() then
        mod.wasSkimmingEnabled = fcp:isSkimmingEnabled()
    end
    fcp:isSkimmingEnabled(false)
end

-- restoreSkimmingState() -> none
-- Function
-- Restores the skimming state after 1sec
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
local function restoreSkimmingState()
    mod.skimmingRestoreTimer:start()
end

--- plugins.finalcutpro.workflowextension.incrementPlayhead(frames) -> none
--- Function
--- Increments the Final Cut Pro playhead via the Workflow Extension
---
--- Parameters:
---  * frames - The amount of frames to increment by
---
--- Returns:
---  * None
function mod.incrementPlayhead(frames)
    saveSkimmingState()
    mod.sendCommand("INCR " .. frames)
    restoreSkimmingState()
end

--- plugins.finalcutpro.workflowextension.decrementPlayhead(frames) -> none
--- Function
--- Decrements the Final Cut Pro playhead via the Workflow Extension
---
--- Parameters:
---  * frames - The amount of frames to increment by
---
--- Returns:
---  * None
function mod.decrementPlayhead(frames)
    saveSkimmingState()
    mod.sendCommand("DECR " .. frames)
    restoreSkimmingState()
end

--- plugins.finalcutpro.workflowextension.movePlayheadToSeconds(seconds) -> none
--- Function
--- Moves the Final Cut Pro playhead via the Workflow Extension
---
--- Parameters:
---  * seconds - The value you want the timeline playhead to move to in seconds
---
--- Returns:
---  * None
function mod.movePlayheadToSeconds(seconds)
    mod.sendCommand("GOTO " .. seconds)
end

--- plugins.finalcutpro.workflowextension.ping() -> none
--- Function
--- Sends a ping to the Workflow Extension
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.ping()
    --log.df("[Workflow Extension] Sending ping")
    mod.sendCommand("PING")
end

--- plugins.finalcutpro.workflowextension.setupActions() -> none
--- Function
--- Setup the Workflow Extension Actions
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.setupActions()
    local icon = fcp:icon()
    mod._handler = mod.actionmanager.addHandler("fcpx_workflowextensions", "fcpx")
        :onChoices(function(choices)
            for i=1, NUMBER_OF_PLAYHEAD_INCREMENTS do
                --------------------------------------------------------------------------------
                -- Move Playhead Forward:
                --------------------------------------------------------------------------------
                local frames = i18n("frames")
                if i == 1 then frames = i18n("frame") end

                choices
                    :add(i18n("movePlayheadForward") .. " " .. i .. " " .. frames)
                    :subText(i18n("workflowExtensionMovePlayhead"))
                    :params({
                        amount = i,
                        actionType = "increment",
                        id = "fcpx_workflowextensions_increment_" .. i,
                    })
                    :id("fcpx_workflowextensions_increment_" .. i)
                    :image(icon)

                --------------------------------------------------------------------------------
                -- Move Playhead Backward:
                --------------------------------------------------------------------------------
                choices
                    :add(i18n("movePlayheadBackward") .. " " .. i .. " " .. frames)
                    :subText(i18n("workflowExtensionMovePlayhead"))
                    :params({
                        amount = i,
                        actionType = "decrement",
                        id = "fcpx_workflowextensions_decrement_" .. i,
                    })
                    :id("fcpx_workflowextensions_decrement_" .. i)
                    :image(icon)
            end
        end)
        :onExecute(function(action)
            local actionType = action.actionType
            if actionType == "increment" then
                mod.incrementPlayhead(action.amount)
            elseif actionType == "decrement" then
                mod.decrementPlayhead(action.amount)
            else
                log.ef("[Workflow Extension] Unknown Action Triggered")
            end
        end)
        :onActionId(function(params)
            return params.id
        end)
end

--- plugins.finalcutpro.workflowextension.repositionWorkflowExtension() -> none
--- Function
--- Repositions the Workflow Extension.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.repositionWorkflowExtension()
    --------------------------------------------------------------------------------
    -- The first time we launch the Workflow Extension, lets move it as far away
    -- as possible. We only do this once, so that the user can move it somewhere
    -- else if needed.
    --------------------------------------------------------------------------------
    if mod.hasWorkflowExtensionBeenMovedVersion() ~= mod._currentVersion then

        --------------------------------------------------------------------------------
        -- Make the Workflow Extension as small as possible:
        --------------------------------------------------------------------------------
        fcp.commandPostWorkflowExtension:size({h=0, w=0})

        local primaryWindowUI = fcp.primaryWindow:UI()
        local primaryWindowHSWindow = primaryWindowUI and primaryWindowUI:asHSWindow()
        local primaryWindowScreen = primaryWindowHSWindow and primaryWindowHSWindow:screen()
        local primaryWindowFullScreen = primaryWindowScreen and primaryWindowScreen:fullFrame()
        local workflowExtensionFrame = fcp.commandPostWorkflowExtension:frame()

        local isThereAScreenOnTheLeft = false
        local isThereAScreenOnTheRight = false

        local screenPositions = hs.screen.screenPositions()
        for screen, position in pairs(screenPositions) do
            if screen ~= primaryWindowScreen then
                if position.x == 1 then
                    isThereAScreenOnTheLeft = true
                elseif position.x == -1 then
                    isThereAScreenOnTheRight = true
                end
            end
        end

        --isThereAScreenOnTheLeft = true
        --isThereAScreenOnTheRight = true

        if isThereAScreenOnTheLeft and isThereAScreenOnTheRight then
            --------------------------------------------------------------------------------
            -- There's a screen on the left and right of Final Cut Pro, so lets just hide
            -- it in the Viewer.
            --------------------------------------------------------------------------------'
            --log.df("[Workflow Extension] There's a screen on the left and right.")
            local viewerFrame = fcp.viewer:frame()
            if viewerFrame and workflowExtensionFrame then
                fcp.commandPostWorkflowExtension:position({x=viewerFrame.x+(workflowExtensionFrame.w*3), y=viewerFrame.h+viewerFrame.y-workflowExtensionFrame.h})
            end
        elseif isThereAScreenOnTheLeft or (not isThereAScreenOnTheLeft and not isThereAScreenOnTheRight) then
            --------------------------------------------------------------------------------
            -- There's no screen on the right, so let's hide it on the left:
            --------------------------------------------------------------------------------
            --log.df("[Workflow Extension] There's a screen on the right.")
            if primaryWindowFullScreen and workflowExtensionFrame then
                fcp.commandPostWorkflowExtension:position({x=-58, y=primaryWindowFullScreen.h-workflowExtensionFrame.h})
            end
        else
            --------------------------------------------------------------------------------
            -- There's no screen on the left, so let's hide it on the right:
            --------------------------------------------------------------------------------
            --log.df("[Workflow Extension] There's a screen on the left.")
            if primaryWindowFullScreen and workflowExtensionFrame then
                fcp.commandPostWorkflowExtension:position({x=primaryWindowFullScreen.w-1, y=primaryWindowFullScreen.h-workflowExtensionFrame.h})
            end
        end

        mod.hasWorkflowExtensionBeenMovedVersion(mod._currentVersion)
    end

    --------------------------------------------------------------------------------
    -- Give focus back to the primary window:
    --------------------------------------------------------------------------------
    if fcp.commandPostWorkflowExtension:focused() then
        local primaryWindow = fcp.primaryWindow:window()
        if primaryWindow then
            --log.df("[Workflow Extension] Focussing on primary window")
            primaryWindow:focus()
        end
    end
end

--- plugins.finalcutpro.workflowextension.forcefullyInstall() -> none
--- Function
--- Forcefully installs the Workflow Extension.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.forcefullyInstall()
    --mod.hasWorkflowExtensionBeenAddedVersion("")
    if mod.hasWorkflowExtensionBeenAddedVersion() ~= mod._currentVersion then
        --------------------------------------------------------------------------------
        -- Close the Workflow Extension if already open:
        --------------------------------------------------------------------------------
        if fcp.commandPostWorkflowExtension.isShowing() then
            fcp.commandPostWorkflowExtension:hide()
            mod.workflowExtensionRequiresRestart = true
        end
        if fcp.isRunning() then
            mod.workflowExtensionRequiresRestart = true
        end
        task.new("/usr/bin/pluginkit", function(exitCode, stdOut, stdErr)
            if exitCode == 0 then
                --------------------------------------------------------------------------------
                -- hs.task has succeeded:
                --------------------------------------------------------------------------------
                log.df("[Workflow Extension] Successfully installed.")
                mod.hasWorkflowExtensionBeenAddedVersion(mod._currentVersion)
                if mod.workflowExtensionRequiresRestart then
                    log.df("[Workflow Extension] Requires Final Cut Pro to restart.")
                    notify.new(function()
                        --------------------------------------------------------------------------------
                        -- Restart Final Cut Pro:
                        --------------------------------------------------------------------------------
                        fcp.doRestart():Now()
                    end, {
                        title = i18n("workflowExtensionInstalled"),
                        subTitle = "",
                        informativeText = i18n("pleaseRestartFinalCutProToFinishInstallation"),
                        autoWithdraw = false,
                        withdrawAfter = 0,
                        alwaysPresent = true,
                        actionButtonTitle = i18n("restart"),
                        hasActionButton = true,
                    }):send()
                end
            else
                --------------------------------------------------------------------------------
                -- hs.task has failed:
                --------------------------------------------------------------------------------
                log.df("[Workflow Extension] Failed to install.\nExit Code: '%s'\nStandard Out: '%s'\nStandard Error: '%s'", exitCode, stdOut, stdErr)
                notify.new(function()
                    --------------------------------------------------------------------------------
                    -- Restart Final Cut Pro:
                    --------------------------------------------------------------------------------
                    fcp.doRestart():Now()
                    doAfter(2, hs.reload)
                end, {
                    title = i18n("workflowExtensionFailedToInstall"),
                    subTitle = "",
                    informativeText = i18n("pleaseTryRestartingCommandPostAndFinalCutPro"),
                    autoWithdraw = false,
                    withdrawAfter = 0,
                    alwaysPresent = true,
                    actionButtonTitle = i18n("restart"),
                    hasActionButton = true,
                }):send()
            end
        end, {"-a", hs.processInfo.bundlePath .. "/Contents/PlugIns/CommandPost.appex"}):start()
    end
end

local plugin = {
    id = "finalcutpro.workflowextension",
    group = "finalcutpro",
    dependencies = {
        ["finalcutpro.commands"]        = "fcpxCmds",
        ["core.action.manager"]         = "actionmanager",
    }
}

function plugin.init(deps)
    --------------------------------------------------------------------------------
    -- Only load plugin if FCPX is supported:
    --------------------------------------------------------------------------------
    if not fcp:isSupported() then return end

    --------------------------------------------------------------------------------
    -- Connect to Dependancies:
    --------------------------------------------------------------------------------
    mod.actionmanager = deps.actionmanager

    --------------------------------------------------------------------------------
    -- Setup the Actions:
    --------------------------------------------------------------------------------
    mod.setupActions()

    --------------------------------------------------------------------------------
    -- Save the current CommandPost Version:
    --------------------------------------------------------------------------------
    mod._currentVersion = hs.processInfo.version

    return mod
end

function plugin.postInit()
    --------------------------------------------------------------------------------
    -- Only load plugin if FCPX is supported:
    --------------------------------------------------------------------------------
    if not fcp:isSupported() then return end

    --------------------------------------------------------------------------------
    -- Forcefully install the Workflow Extension (once only per update):
    --
    -- NOTE: Apple says that in a "future releases of the OS, using the
    --       'pluginkit -a' and 'pluginkit -r' to add and remove plug-ins will
    --       stop working". We currently don't have a better workaround sadly.
    --------------------------------------------------------------------------------
    mod.forcefullyInstall()

    --------------------------------------------------------------------------------
    -- Shutdown Callback (disconnect on restart/quit):
    --------------------------------------------------------------------------------
    config.shutdownCallback:new("workflowExtension", function()
        --log.df("[Workflow Extension] Disconnecting from the Workflow Extension")
        mod.disconnect()
    end)

    --------------------------------------------------------------------------------
    -- Watch for the Workflow Extension Window:
    --------------------------------------------------------------------------------
    mod.watcher = fcp.commandPostWorkflowExtension.isShowing:watch(function(value)
        if value then
            mod.repositionWorkflowExtension()
            mod.connect()
        end
    end)

    --------------------------------------------------------------------------------
    -- Watch for Final Cut Pro change in focus:
    --------------------------------------------------------------------------------
    fcp.app.frontmost:watch(function(frontmost)
        if frontmost and fcp.commandPostWorkflowExtension.isShowing() then
            mod.connect()
        end
    end)

    --------------------------------------------------------------------------------
    -- Connect if the Workflow Extension is already open:
    --------------------------------------------------------------------------------
    if fcp.commandPostWorkflowExtension.isShowing() then
        mod.connect()
    end
end

return plugin
