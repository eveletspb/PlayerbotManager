PBM = PBM or {}

local attunements = {
    { "onyxia40", "Ony", "Onyxia 40" },
    { "naxx40", "Naxx", "Naxxramas 40" },
    { "serpentshrine", "SSC", "Serpentshrine Cavern" },
    { "tempestkeep", "TK", "Tempest Keep" },
    { "hyjal", "Hyjal", "Mount Hyjal" },
    { "blacktemple", "BT", "Black Temple" },
}
local names = {}
for _, entry in ipairs(attunements) do names[entry[1]] = entry[3] end

local results = {
    ok = true, partial = "Some raid members could not receive all attunements.",
    no_bots = "No eligible online bots.", no_raid = "Join a raid to view attunements.",
    not_leader = "Only the raid leader can grant or sync attunements.",
    unknown_attunement = "This attunement is unavailable on the server.",
    not_allowed = "Raid attunements require Game Master access.",
    rate_limited = "Too many requests. Refresh in a moment.",
}
local rowStatuses = {
    source = "Current character", player_skipped = "Player (read only)", offline = "Offline",
    unchanged = "Unchanged", granted = "Granted", partial = "Partially granted", failed = "Grant failed",
}
local reasons = {
    quest_in_progress = "Quest already in progress",
    quest_unavailable = "Quest unavailable",
    item_unavailable = "Item could not be added",
    attunement_unconfirmed = "Attunement could not be confirmed",
}
local state = { catalog = attunements, rows = {} }
PBM.RaidAttunements = state

local frame = CreateFrame("Frame")
local request
local roster = ""
local refreshPending = false
local function Notify()
    if PBM.RefreshRaidAttunements then PBM.RefreshRaidAttunements() end
end

local function Visible()
    local groupView = PBM.State and PBM.State.groupViewFrame
    return groupView and groupView:IsVisible()
end

local function Finish(message, rows)
    request = nil
    frame:SetScript("OnUpdate", nil)
    state.busy = false
    state.message = message
    state.rows = rows or {}
    state.ready = rows ~= nil
    Notify()
    if refreshPending then
        refreshPending = false
        if Visible() then PBM.RequestRaidAttunements("list") end
    end
end

function PBM.RequestRaidAttunements(action, code)
    if request or GetNumRaidMembers() == 0 then return false end
    local write = action == "grant" or action == "sync"
    if action ~= "list" and not write then return false end
    if action == "grant" and not names[code] then return false end
    if write and (not state.ready or not IsRaidLeader()) then return false end

    local active = { action = action, roster = roster }
    request = active
    state.busy = true
    state.message = "Waiting for raid attunements..."
    Notify()
    local function ArmReplyTimeout()
        local remaining = 8
        frame:SetScript("OnUpdate", function(_, elapsed)
            remaining = remaining - elapsed
            if remaining <= 0 then
                Finish("Attunements unavailable or no complete reply. Refresh to try again.")
            end
        end)
    end
    active.transport = "bridge"
    active.sent = true
    if PBM.BridgeSendRaidAttunements and PBM.BridgeSendRaidAttunements(action, code) then
        if request == active then ArmReplyTimeout() end
    else
        active.transport = "chat"
        active.sent = false
        PBM.SendChatMessage(".ip attune raid " .. action .. (code and " " .. code or ""), "SAY", nil, nil, function()
            if request ~= active then return false end
            if active.stale or active.roster ~= roster or GetNumRaidMembers() == 0 or (write and not IsRaidLeader()) then
                Finish("Raid changed. Refresh to try again.")
                return false
            end
            active.sent = true
            ArmReplyTimeout()
            return true
        end)
    end
    return true
end

local function UpdateRoster(refresh)
    local raid = {}
    for i = 1, GetNumRaidMembers() do
        local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
        if name then raid[#raid + 1] = name:lower() .. (online and "+" or "-") end
    end
    table.sort(raid)
    local key = table.concat(raid, ",")
    local changed = key ~= roster
    roster = key
    if changed or key == "" then
        state.ready = false
        state.rows = {}
        state.message = key == "" and "Join a raid to view attunements." or "Raid changed."
        if request then
            request.stale = true
            refreshPending = key ~= ""
        end
        Notify()
    end
    if key ~= "" and refresh and not request then PBM.RequestRaidAttunements("list") end
    return changed
end

function PBM.RefreshRaidAttunementRoster()
    UpdateRoster(true)
end

function PBM.RaidAttunementRowText(name)
    if not name then return "" end
    local row = state.rows[name:lower()]
    if not row then return "—" end
    if row.status == "offline" then return "Offline" end
    local labels = {}
    for _, entry in ipairs(attunements) do
        if row.codes[entry[1]] then labels[#labels + 1] = entry[2] end
    end
    if #labels == 0 then return "None" end
    return table.concat(labels, " ")
end

function PBM.ShowRaidAttunementTooltip(owner, name)
    if not name then return end
    local row = state.rows[name:lower()]
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(name)
    if row then
        GameTooltip:AddLine(rowStatuses[row.status], 0.82, 0.82, 0.82)
        for _, entry in ipairs(attunements) do
            local code = entry[1]
            if row.codes[code] then GameTooltip:AddLine(entry[3], 0.5, 1, 0.5) end
            if row.failures[code] then
                GameTooltip:AddLine(entry[3] .. ": " .. row.failures[code], 1, 0.5, 0.5)
            end
        end
    else
        GameTooltip:AddLine("Attunements unavailable", 0.82, 0.82, 0.82)
    end
    GameTooltip:Show()
end

function PBM.HandleRaidAttunementFrame(transport, message)
    local active = request
    if not active or not active.sent or active.transport ~= transport then return end
    local kind, payload = message:match("^(%u+) (.+)$")
    if kind == "BEGIN" then
        local action, count = payload:match("^(%l+) (%d+)$")
        if action ~= active.action then return end
        count = tonumber(count)
        if active.rows or not count or count > 40 then
            Finish("Invalid attunement reply. Refresh to try again.")
            return
        end
        active.expected = count
        active.count = 0
        active.rows = {}
        active.failures = {}
    elseif active.rows and kind == "FAIL" then
        local name, code, reason = payload:match("^(%S+) (%w+) ([%w_]+)$")
        if not name or not names[code] or not reason then
            active.invalid = true
            return
        end
        name = name:lower()
        active.failures[name] = active.failures[name] or {}
        active.failures[name][code] = reasons[reason] or reason
    elseif active.rows and kind == "ROW" then
        local name, codes, status = payload:match("^(%S+) ([%w,%-]+) ([%w_]+)$")
        if not name or not rowStatuses[status] or active.rows[name:lower()] then
            active.invalid = true
            return
        end
        name = name:lower()
        local set = {}
        for code in codes:gmatch("%w+") do set[code] = true end
        active.rows[name] = { codes = set, status = status, failures = active.failures[name] or {} }
        active.count = active.count + 1
    elseif active.rows and kind == "END" then
        local action, result = payload:match("^(%l+) ([%w_]+)$")
        if action ~= active.action then return end
        if active.stale then
            Finish("Raid changed. Refreshing attunements.")
        elseif active.invalid or active.count ~= active.expected or not results[result] then
            Finish("Incomplete attunement reply. Refresh to try again.")
        elseif result == "ok" or result == "partial" or result == "no_bots" then
            local message = results[result]
            Finish(type(message) == "string" and message or nil, active.rows)
        else
            Finish(results[result])
        end
    end
end

frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, message)
    if event ~= "CHAT_MSG_SYSTEM" then
        local changed = UpdateRoster(false)
        if Visible() and PBM.RebuildGroupViewRoster then PBM.RebuildGroupViewRoster() end
        if Visible() and changed and not request then PBM.RequestRaidAttunements("list") end
        return
    end

    local payload = message:match("^PBM_ATTUNE_V1 (.+)$")
    if payload then PBM.HandleRaidAttunementFrame("chat", payload) end
end)

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, message)
    return Visible() and message:find("^PBM_ATTUNE_V1 ") ~= nil
end)
