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
    SendBridgeWire(BRIDGE_ENVELOPE .. "HELLO" .. FIELD_SEPARATOR .. PBM.Bridge.protocolVersion)

    BridgeTimerAfter(PBM.Bridge.probeTimeout, function()
        if PBM.Bridge.state == "probing" then
            PBM.Bridge.state = "unavailable"
        end
    end)
end

function PBM.BridgeSendStrategy(botName, stateScope, changes)
    if not PBM.BridgeHasCapability("STRATEGY_MUTATION_V1") then return false end
    local token = NextToken()
    local payload = table.concat({
        "STRATEGY", "BOT", UrlEncode(botName), token, stateScope, UrlEncode(changes),
    }, FIELD_SEPARATOR)
    return PBM.BridgeSend("RUN", payload, token)
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

function PBM.HandleBridgeMessage(message)
    if not IsBridgeMessage(message) then return false end

    local body = string.sub(message, #BRIDGE_ENVELOPE + 1)
    local opcode, payload = body:match("^([^~]+)~?(.*)$")
    if not opcode or #opcode > 24 then return true end

    if opcode == "HELLO_ACK" then
        local fields = SplitFields(payload)
        if fields[1] ~= PBM.Bridge.protocolVersion then return true end
        PBM.Bridge.state = "available"
        return true
    end

    if opcode == "CAPS" then
        for capability in string.gmatch(payload, "[^,]+") do
            PBM.Bridge.capabilities[capability] = true
        end
        return true
    end

    if opcode == "CAPS_END" then
        if PBM.Bridge.state == "probing" then PBM.Bridge.state = "available" end
        return true
    end

    if opcode == "STRATEGY_ACK" then
        local fields = SplitFields(payload)
        ResolvePending(fields[3], opcode, fields)
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
