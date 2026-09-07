-- ============================================================
-- PBM_Bridge.lua | Optional mod-multibot-bridge transport
--
-- The bridge is optional. Until HELLO_ACK is received, PBM keeps
-- using the existing mod-playerbots chat-command transport.
-- ============================================================
PBM = PBM or {}
PBM.State = PBM.State or {}

PBM.Bridge = PBM.Bridge or {
    state = "unknown", -- unknown, probing, available, unavailable
    protocolVersion = "1",
    capabilities = {},
    helloReceived = false,
    capabilitiesComplete = false,
    pending = {},
    sequence = 0,
    probeTimeout = 3,
}

local BRIDGE_ENVELOPE = "MBOT\t"
local BRIDGE_PREFIX = "MBOT"
local FIELD_SEPARATOR = "~"

local function BridgeTimerAfter(delay, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, callback)
        return
    end

    local elapsed = 0
    local frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            callback()
        end
    end)
end

local function UrlEncode(value)
    value = tostring(value or "")
    value = value:gsub("([^%w%-_%.~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
    return value
end

local function SplitFields(value)
    local fields = {}
    local start = 1
    while true do
        local separator = string.find(value, FIELD_SEPARATOR, start, true)
        if not separator then
            fields[#fields + 1] = string.sub(value, start)
            break
        end
        fields[#fields + 1] = string.sub(value, start, separator - 1)
        start = separator + 1
    end
    return fields
end

local function UrlDecode(value)
    return (value or ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

local function NextToken()
    PBM.Bridge.sequence = PBM.Bridge.sequence + 1
    local now = math.floor((GetTime and GetTime() or 0) * 1000)
    return tostring(now) .. "-" .. tostring(PBM.Bridge.sequence)
end

local function SendBridgeWire(wire)
    local payload = string.sub(wire, #BRIDGE_ENVELOPE + 1)
    local channel = "WHISPER"
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        channel = "RAID"
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        channel = "PARTY"
    end

    if channel == "WHISPER" then
        SendAddonMessage(BRIDGE_PREFIX, payload, channel, UnitName("player"))
    else
        SendAddonMessage(BRIDGE_PREFIX, payload, channel)
    end
end

local function IsBridgeMessage(message)
    return type(message) == "string" and string.sub(message, 1, #BRIDGE_ENVELOPE) == BRIDGE_ENVELOPE
end

local function ResolvePending(token, opcode, payload)
    local request = PBM.Bridge.pending[token]
    if not request then return end
    PBM.Bridge.pending[token] = nil
    if request.callback then
        request.callback(opcode, payload)
    end
end

function PBM.BridgeIsAvailable()
    return PBM.Bridge.state == "available"
end

function PBM.BridgeHasCapability(capability)
    return PBM.BridgeIsAvailable() and PBM.Bridge.capabilities[capability] == true
end

function PBM.BridgeSend(opcode, payload, token, callback, onTimeout)
    if not PBM.BridgeIsAvailable() then return false end
    token = token or NextToken()
    if callback then
        local request = { callback = callback, onTimeout = onTimeout }
        PBM.Bridge.pending[token] = request
        BridgeTimerAfter(5, function()
            if PBM.Bridge.pending[token] == request then
                PBM.Bridge.pending[token] = nil
                if request.onTimeout then request.onTimeout() end
            end
        end)
    end
    local wire = BRIDGE_ENVELOPE .. opcode
    if payload and payload ~= "" then
        wire = wire .. FIELD_SEPARATOR .. payload
    end
    SendBridgeWire(wire)
    return true, token
end

function PBM.BridgeProbe()
    if PBM.Bridge.state == "probing" or PBM.Bridge.state == "available" then return end

    PBM.Bridge.state = "probing"
    PBM.Bridge.capabilities = {}
    PBM.Bridge.helloReceived = false
    PBM.Bridge.capabilitiesComplete = false
    SendBridgeWire(BRIDGE_ENVELOPE .. "HELLO" .. FIELD_SEPARATOR .. PBM.Bridge.protocolVersion)

    BridgeTimerAfter(PBM.Bridge.probeTimeout, function()
        if PBM.Bridge.state == "probing" then
            PBM.Bridge.state = "unavailable"
        end
    end)
end

function PBM.BridgeSendStrategy(botName, stateScope, changes, callback)
    if not PBM.BridgeHasCapability("STRATEGY_MUTATION_V1") then return false end
    local token = NextToken()
    local payload = table.concat({
        "STRATEGY", "BOT", UrlEncode(botName), token, stateScope, UrlEncode(changes),
    }, FIELD_SEPARATOR)

    local function OnResult(opcode, fields)
        if opcode == "STRATEGY_ACK" then
            local reason = UrlDecode(fields[8] or "")
            local ok = reason == "OK"
            if callback then callback(ok, reason, fields) end
        elseif opcode == "ERR" and callback then
            callback(false, UrlDecode(fields[4] or fields[3] or "BRIDGE_ERROR"), fields)
        end
    end

    return PBM.BridgeSend("RUN", payload, token, OnResult, function()
        if callback then callback(false, "TIMEOUT") end
    end)
end

function PBM.BridgeGetBotState(botName, callback)
    if not PBM.BridgeHasCapability("STATE_FRAMING_V1") then return false end

    local token = NextToken()
    local payload = table.concat({ "STATE", UrlEncode(botName), token }, FIELD_SEPARATOR)
    local combat = {}
    local nonCombat = {}
    local currentBot = botName

    local function OnStateFrame(opcode, fields)
        if opcode == "STATE_ITEM" then
            local stateScope = fields[3]
            local strategy = UrlDecode(fields[5] or "")
            if stateScope == "C" then
                combat[strategy:lower()] = true
            elseif stateScope == "N" then
                nonCombat[strategy:lower()] = true
            end
        elseif opcode == "STATE_END" then
            callback(currentBot, combat, nonCombat, nil)
        elseif opcode == "STATE_ABORT" then
            callback(currentBot, combat, nonCombat, fields[3] or "STATE_ABORT")
        end
    end

    local sent = PBM.BridgeSend("GET", payload, token, OnStateFrame, function()
        callback(currentBot, combat, nonCombat, "TIMEOUT")
    end)
    if not sent then return false end
    PBM.Bridge.pending[token].state = {
        botName = botName,
        combat = combat,
        nonCombat = nonCombat,
    }
    return true
end

function PBM.BridgeSendTalentBuild(botName, build, callback)
    if not PBM.BridgeHasCapability("TALENT_APPLY_V1") then return false end

    local token = NextToken()
    local payload = table.concat({
        "TALENT_APPLY", token, UrlEncode(botName), build,
    }, FIELD_SEPARATOR)

    local function OnResult(opcode, fields)
        if opcode == "TALENT_APPLY_RESULT" then
            callback(fields[3] == "OK", UrlDecode(fields[4] or ""), fields)
        elseif opcode == "ERR" then
            callback(false, UrlDecode(fields[4] or fields[3] or "BRIDGE_ERROR"), fields)
        end
    end

    return PBM.BridgeSend("RUN", payload, token, OnResult, function()
        callback(false, "TIMEOUT")
    end)
end

function PBM.SendTalentBuild(botName, build)
    if PBM.BridgeSendTalentBuild and PBM.BridgeSendTalentBuild(botName, build, function(ok, reason)
        if not ok and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00PBM:|r Talent build failed: " .. tostring(reason))
        end
    end) then
        return true
    end

    SendChatMessage("talents apply " .. build, "WHISPER", nil, botName)
    return false
end

function PBM.BridgeRequestTalentSpecs(botName, callback, onTimeout)
    if not PBM.BridgeHasCapability("TALENT_SPEC_APPLY_V1") then return false end

    local token = NextToken()
    local specs = {}
    local payload = table.concat({ "TALENT_SPEC_LIST", UrlEncode(botName), token }, FIELD_SEPARATOR)

    local function OnFrame(opcode, fields)
        if opcode == "TALENT_SPEC_ITEM" then
            local index = tonumber(fields[3])
            local name = UrlDecode(fields[4] or "")
            if index and name ~= "" then
                specs[#specs + 1] = {
                    index = index,
                    name = name,
                    build = fields[5] or "",
                }
            end
        elseif opcode == "TALENT_SPEC_END" then
            callback(specs)
        elseif opcode == "ERR" then
            callback(nil)
        end
    end

    return PBM.BridgeSend("GET", payload, token, OnFrame, onTimeout)
end

function PBM.BridgeApplyTalentSpec(botName, slot, specIndex, callback)
    if not PBM.BridgeHasCapability("TALENT_SPEC_APPLY_V1") then return false end

    local token = NextToken()
    local payload = table.concat({ "TALENT_SPEC_APPLY", token, UrlEncode(botName), slot, specIndex }, FIELD_SEPARATOR)
    return PBM.BridgeSend("RUN", payload, token, function(opcode, fields)
        if opcode == "TALENT_SPEC_APPLY_RESULT" then
            callback(fields[3] == "OK", UrlDecode(fields[4] or ""), fields)
        else
            callback(false, UrlDecode(fields[4] or fields[3] or "BRIDGE_ERROR"), fields)
        end
    end, function()
        callback(false, "TIMEOUT")
    end)
end

function PBM.ApplyTalentTemplate(botName, specName)
    local function UseLegacy()
        PBM.SendToBot("talents switch 1", botName)
        BridgeTimerAfter(0.4, function()
            PBM.SendToBot("talents spec " .. specName, botName)
            PBM.State.pickingPending[botName] = true
        end)
    end

    if not PBM.BridgeHasCapability("TALENT_SPEC_APPLY_V1") then
        UseLegacy()
        return false
    end

    local requested = string.lower(specName or "")
    local sent = PBM.BridgeRequestTalentSpecs(botName, function(specs)
        specs = specs or {}
        local selected
        for _, spec in ipairs(specs) do
            if string.lower(spec.name) == requested then
                selected = spec
                break
            end
        end

        if not selected then
            UseLegacy()
            return
        end

        PBM.BridgeApplyTalentSpec(botName, 1, selected.index, function(ok, reason)
            if ok then
                if PBM.OnBridgeTalentSpecApplied then PBM.OnBridgeTalentSpecApplied(botName) end
            elseif DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00PBM:|r Talent spec failed: " .. tostring(reason))
            end
        end)
    end, UseLegacy)

    if not sent then UseLegacy() end
    return sent
end

local function PrepareBridgeInventory(botName)
    if not PBM.inventory or not PBM.inventory.frames or not PBM.inventory.frames["Items"] then
        return
    end

    local items = PBM.inventory.frames["Items"]
    for _, button in pairs(items.buttons) do button:Hide() end
    for key in pairs(items.buttons) do items.buttons[key] = nil end
    PBM.inventory.setText("Title", PBM.doReplace(PBM.info.inventory, "NAME", botName))
    PBM.inventory.name = botName
    items.index = 0
end

function PBM.BridgeRequestInventory(botName)
    if not PBM.BridgeHasCapability("INVENTORY_V1") then return false end

    local token = NextToken()
    local payload = table.concat({ "INVENTORY", UrlEncode(botName), token }, FIELD_SEPARATOR)

    local function FallbackInventory()
        if PBM._waitFor then PBM._waitFor[botName] = "INVENTORY" end
        SendChatMessage("items", "WHISPER", nil, botName)
    end

    local function OnFrame(opcode, fields)
        if opcode == "INV_BEGIN" then
            PrepareBridgeInventory(UrlDecode(fields[1] or botName))
        elseif opcode == "INV_ITEM" then
            local line = UrlDecode(fields[3] or "")
            if PBM.inventory and PBM.inventory.frames and PBM.addItem then
                PBM.addItem(PBM.inventory.frames["Items"], line)
            end
        elseif opcode == "INV_END" then
            if PBM.inventory then PBM.inventory:Show() end
            if PBM._waitFor then PBM._waitFor[botName] = nil end
        elseif opcode == "ERR" then
            FallbackInventory()
        end
    end

    local function OnTimeout()
        FallbackInventory()
    end

    return PBM.BridgeSend("GET", payload, token, OnFrame, OnTimeout)
end

local GEAR_SLOT_INDEX = {
    [1] = 1, [2] = 2, [3] = 3, [15] = 4, [5] = 5, [9] = 6,
    [10] = 7, [6] = 8, [7] = 9, [8] = 10, [11] = 11, [12] = 12,
    [13] = 13, [14] = 14, [16] = 15, [17] = 16, [18] = 17,
}

function PBM.BridgeRequestGear(botName, callback, onTimeout)
    if not PBM.BridgeHasCapability("GEAR_INSPECT_V1") then return false end

    local token = NextToken()
    local gear = { ilvl = {}, ilvlLink = {}, score = 0, realGs = 0 }
    for i = 1, PBM.GEAR_SLOTS do
        gear.ilvl[i] = 0
        gear.ilvlLink[i] = ""
    end

    local function OnFrame(opcode, fields)
        if opcode == "GEAR_SUMMARY" then
            gear.score = tonumber(fields[3]) or 0
            gear.realGs = tonumber(fields[4]) or 0
        elseif opcode == "GEAR_ITEM" then
            local slot = GEAR_SLOT_INDEX[tonumber(fields[3] or "")]
            if slot then
                local itemId = tonumber(fields[4]) or 0
                gear.ilvl[slot] = tonumber(fields[5]) or 0
                if itemId > 0 then
                    gear.ilvlLink[slot] = "item:" .. tostring(itemId) .. ":0:0:0:0:0:0:0"
                end
            end
        elseif opcode == "GEAR_END" then
            if callback then callback(gear) end
        elseif opcode == "GEAR_ERROR" or opcode == "ERR" then
            if callback then callback(nil, fields[3] or fields[4] or "BRIDGE_ERROR") end
        end
    end

    local function OnTimeout()
        if onTimeout then onTimeout() end
    end

    return PBM.BridgeSend("GET", table.concat({ "GEAR", UrlEncode(botName), token }, FIELD_SEPARATOR), token, OnFrame, OnTimeout)
end

function PBM.BridgeRequestDetail(botName, callback, onTimeout)
    if not PBM.BridgeHasCapability("DETAIL_V1") then return false end

    local token = NextToken()
    local function OnResult(opcode, fields)
        if opcode == "DETAIL_RESULT" then
            callback(UrlDecode(fields[2] or ""), UrlDecode(fields[3] or ""), UrlDecode(fields[4] or ""), UrlDecode(fields[5] or ""),
                tonumber(fields[6]) or 0, tonumber(fields[7]) or 0, tonumber(fields[8]) or 0,
                tonumber(fields[9]) or 0, tonumber(fields[10]) or 0)
        elseif opcode == "ERR" then
            callback(nil, nil, nil, nil, nil, nil, nil, nil, UrlDecode(fields[4] or fields[3] or "BRIDGE_ERROR"))
        end
    end

    return PBM.BridgeSend("GET", table.concat({ "DETAIL", UrlEncode(botName), token }, FIELD_SEPARATOR), token,
        OnResult, function()
            if onTimeout then onTimeout() end
        end)
end

function PBM.BridgeRequestStats(botName, callback, onTimeout)
    if not PBM.BridgeHasCapability("STATS_V1") then return false end

    local token = NextToken()
    local function OnResult(opcode, fields)
        if opcode == "STATS_RESULT" then
            callback(UrlDecode(fields[2] or ""), tonumber(fields[3]) or 0, tonumber(fields[4]) or 0,
                tonumber(fields[5]) or 0, tonumber(fields[6]) or 0, tonumber(fields[7]) or 0,
                tonumber(fields[8]) or 0, tonumber(fields[9]) or 0, tonumber(fields[10]) or 0,
                tonumber(fields[11]) or 0)
        elseif opcode == "ERR" then
            callback(nil, nil, nil, nil, nil, nil, nil, nil, nil,
                UrlDecode(fields[4] or fields[3] or "BRIDGE_ERROR"))
        end
    end

    return PBM.BridgeSend("GET", table.concat({ "STATS", UrlEncode(botName), token }, FIELD_SEPARATOR), token,
        OnResult, function()
            if onTimeout then onTimeout() end
        end)
end

local function CalculateBridgeGearScore(row, gear)
    if not row or not gear or (tonumber(gear.realGs) or 0) > 0 then return end
    if not PBM.CalculateGearScoreForItemLink then return end

    local total = 0
    local className = row.cls or ""
    for slot = 1, PBM.GEAR_SLOTS do
        local link = gear.ilvlLink and gear.ilvlLink[slot]
        if link and link ~= "" then
            local itemScore = select(1, PBM.CalculateGearScoreForItemLink(link)) or 0
            if className == "Hunter" then
                if slot == 15 then
                    itemScore = itemScore * 0.3164 -- main hand
                elseif slot == 16 then
                    itemScore = itemScore * 0.3164 -- off hand
                elseif slot == 17 then
                    itemScore = itemScore * 5.3224 -- ranged
                end
            end
            total = total + itemScore
        end
    end

    if total > 0 then gear.realGs = math.floor(total) end
end

function PBM.ApplyBridgeGear(botName, gear)
    if not gear or not LichborneTrackerDB or not LichborneTrackerDB.rows then return false end
    local rowIndex = PBM.FindTrackedRowIndexByName and PBM.FindTrackedRowIndexByName(botName)
    if not rowIndex then return false end

    local row = LichborneTrackerDB.rows[rowIndex]
    CalculateBridgeGearScore(row, gear)
    row.ilvl = gear.ilvl or row.ilvl or {}
    row.ilvlLink = gear.ilvlLink or row.ilvlLink or {}
    if (gear.score or 0) > 0 then row.gs = gear.score end
    if (gear.realGs or 0) > 0 then row.realGs = gear.realGs end

    if row.name and LichborneTrackerDB.raidRosters then
        for _, roster in pairs(LichborneTrackerDB.raidRosters) do
            for _, slot in ipairs(roster) do
                if slot.name and slot.name:lower() == row.name:lower() then
                    slot.gs = row.gs
                    slot.realGs = row.realGs
                end
            end
        end
    end

    if PBM.RefreshRows then PBM.RefreshRows() end
    if PBM.RefreshOverviewRows then PBM.RefreshOverviewRows() end
    if PBM.RefreshRaidRows then PBM.RefreshRaidRows() end
    return true
end

function PBM.HandleBridgeMessage(message)
    if not IsBridgeMessage(message) then return false end

    local body = string.sub(message, #BRIDGE_ENVELOPE + 1)
    local opcode, payload = body:match("^([^~]+)~?(.*)$")
    if not opcode or #opcode > 24 then return true end

    if opcode == "HELLO_ACK" then
        local fields = SplitFields(payload)
        if fields[1] ~= PBM.Bridge.protocolVersion then return true end
        PBM.Bridge.helloReceived = true
        if PBM.Bridge.capabilitiesComplete then
            PBM.Bridge.state = "available"
        end
        return true
    end

    if opcode == "CAPS" then
        for capability in string.gmatch(payload, "[^,]+") do
            PBM.Bridge.capabilities[capability] = true
        end
        return true
    end

    if opcode == "CAPS_END" then
        PBM.Bridge.capabilitiesComplete = true
        if PBM.Bridge.state == "probing" and PBM.Bridge.helloReceived then
            PBM.Bridge.state = "available"
        end
        return true
    end

    if opcode == "STRATEGY_ACK" then
        local fields = SplitFields(payload)
        ResolvePending(fields[3], opcode, fields)
        return true
    end

    if opcode == "TALENT_APPLY_RESULT" then
        local fields = SplitFields(payload)
        ResolvePending(fields[1], opcode, fields)
        return true
    end

    if opcode == "TALENT_SPEC_BEGIN" or opcode == "TALENT_SPEC_ITEM" or opcode == "TALENT_SPEC_END" then
        local fields = SplitFields(payload)
        local token = fields[2]
        local request = PBM.Bridge.pending[token]
        if request then
            if opcode == "TALENT_SPEC_END" then PBM.Bridge.pending[token] = nil end
            request.callback(opcode, fields)
        end
        return true
    end

    if opcode == "TALENT_SPEC_APPLY_RESULT" then
        local fields = SplitFields(payload)
        ResolvePending(fields[1], opcode, fields)
        return true
    end

    if opcode == "INV_BEGIN" or opcode == "INV_ITEM" or opcode == "INV_END" then
        local fields = SplitFields(payload)
        local token = fields[2]
        local request = PBM.Bridge.pending[token]
        if request then
            if opcode == "INV_END" then PBM.Bridge.pending[token] = nil end
            request.callback(opcode, fields)
        end
        return true
    end

    if opcode == "GEAR_BEGIN" or opcode == "GEAR_SUMMARY" or opcode == "GEAR_ITEM" or
        opcode == "GEAR_ERROR" or opcode == "GEAR_END" then
        local fields = SplitFields(payload)
        local token = fields[2]
        local request = PBM.Bridge.pending[token]
        if request then
            if opcode == "GEAR_END" or opcode == "GEAR_ERROR" then
                PBM.Bridge.pending[token] = nil
            end
            request.callback(opcode, fields)
        end
        return true
    end

    if opcode == "DETAIL_RESULT" or opcode == "STATS_RESULT" then
        local fields = SplitFields(payload)
        ResolvePending(fields[1], opcode, fields)
        return true
    end

    if opcode == "STATE_BEGIN" or opcode == "STATE_ITEM" or opcode == "STATE_END" or opcode == "STATE_ABORT" then
        local fields = SplitFields(payload)
        local token = fields[1]
        local request = PBM.Bridge.pending[token]
        if request and request.state then
            if opcode == "STATE_BEGIN" then
                request.state.botName = UrlDecode(fields[2] or request.state.botName)
            elseif opcode == "STATE_ITEM" then
                request.callback(opcode, fields)
                return true
            elseif opcode == "STATE_END" or opcode == "STATE_ABORT" then
                PBM.Bridge.pending[token] = nil
                request.callback(opcode, fields)
            end
        end
        return true
    end

    if opcode == "ERR" then
        local fields = SplitFields(payload)
        ResolvePending(fields[3], opcode, fields)
        return true
    end

    return true
end

function PBM.HandleBridgeAddonMessage(prefix, message)
    if prefix ~= BRIDGE_PREFIX then return false end
    if string.sub(message or "", 1, #BRIDGE_ENVELOPE) == BRIDGE_ENVELOPE then
        return PBM.HandleBridgeMessage(message)
    end
    return PBM.HandleBridgeMessage(BRIDGE_ENVELOPE .. (message or ""))
end

local bridgeFrame = CreateFrame("Frame")
bridgeFrame:RegisterEvent("PLAYER_LOGIN")
bridgeFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        BridgeTimerAfter(1, PBM.BridgeProbe)
    end
end)
