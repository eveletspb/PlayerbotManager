-- ============================================================
--  PBM_Commands.lua  |  Bot command dispatch helpers
--
--  All sends go through the throttled PBM.SendChatMessage wrapper
--  installed by PBM_Throttle.lua.
-- ============================================================
PBM = PBM or {}

-- Send a command to the entire party or raid.
function PBM.SendToGroup(cmd)
    if GetNumRaidMembers() > 0 then
        PBM.SendChatMessage(cmd, "RAID")
    elseif GetNumPartyMembers() > 0 then
        PBM.SendChatMessage(cmd, "PARTY")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00PBM:|r Not in a group.")
        return false
    end
    return true
end

local strategyQueues = {}
local function SendNextStrategy(name)
    local queue = strategyQueues[name]
    if not queue or queue.active then return end
    local request = queue[1]
    if not request then strategyQueues[name] = nil; return end
    queue.active = request
    PBM.SendChatMessage(request.cmd, "WHISPER", nil, name)
    PBM.AfterChatQueue(function()
        PBM.TimerAfter(5, function()
            if strategyQueues[name] ~= queue or queue.active ~= request then return end
            -- shortcut: legacy has no reply tokens; abort the queue on timeout instead of misrouting a late reply.
            strategyQueues[name] = nil
            for _, pending in ipairs(queue) do
                if pending.callback then pending.callback(nil, "TIMEOUT") end
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00PBM:|r Strategy request timed out for " .. name .. ". Try again.")
        end)
    end)
end

function PBM.HandleLegacyStrategies(name, activeSet)
    local queue = strategyQueues[name]
    if not queue or not queue.active then return false end
    local request = table.remove(queue, 1)
    queue.active = nil
    if request.callback then
        request.callback(activeSet)
    else
        local menu = PBM.State.lastQueriedMenu[name]
        if not menu or menu.botName ~= name or not menu:IsShown() then menu = nil end
        PBM.QueryBotStrategies(name, menu, false)
    end
    SendNextStrategy(name)
    return true
end

-- Whisper a command to a specific bot by name.
function PBM.SendToBot(cmd, name, onStrategies)
    if not name or name == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00PBM:|r No bot name specified.")
        return
    end
    -- The bridge has a structured strategy endpoint. Keep legacy queries
    -- and unsupported commands on the old whisper path until their parser
    -- is migrated; never duplicate a bridge write through chat fallback.
    local strategyType, strategyChanges = cmd:match("^(co)%s+([+-].+),%?$")
    if not strategyType then
        strategyType, strategyChanges = cmd:match("^(nc)%s+([+-].+),%?$")
    end
    if strategyChanges then
        strategyChanges = strategyChanges:gsub(",%?$", "")
    end
    if strategyType and PBM.BridgeSendStrategy then
        local stateScope = strategyType == "co" and "C" or "N"
        if PBM.BridgeSendStrategy(name, stateScope, strategyChanges, function(ok, reason)
            if not ok and DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00PBM:|r Strategy bridge failed: " .. tostring(reason))
            end

            local menuFrame = PBM.State.lastQueriedMenu[name]
            if menuFrame and menuFrame:IsShown() and PBM.QueryBotStrategies then
                PBM.QueryBotStrategies(name, menuFrame, false)
            end
        end) then
            return
        end
    end
    if cmd:match("^co%s") or cmd:match("^nc%s") then
        if cmd:find("?", 1, true) then
            local queue = strategyQueues[name] or {}
            strategyQueues[name] = queue
            queue[#queue + 1] = { cmd = cmd, callback = onStrategies }
            SendNextStrategy(name)
            return
        end
    end
    PBM.SendChatMessage(cmd, "WHISPER", nil, name)
end

-- Send a server admin (.bot / .playerbots) command via SAY.
function PBM.SendAdmin(cmd)
    PBM.SendChatMessage(cmd, "SAY")
end

-- Convert a player name to a WoW unit token ("party1", "raid5", etc.).
-- Returns nil if the name is not found in the current group.
function PBM.NameToUnit(name)
    if not name then return nil end
    if UnitName("player") == name then return "player" end
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            if UnitName("raid" .. i) == name then return "raid" .. i end
        end
    elseif GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            if UnitName("party" .. i) == name then return "party" .. i end
        end
    end
    return nil
end

-- Send a command prefixed with a role selector.
-- role: "tank" | "healer" | "dps" | "melee" | "ranged" | "groupN"
function PBM.SendToRole(role, cmd)
    PBM.SendToGroup("@" .. role .. " " .. cmd)
end
