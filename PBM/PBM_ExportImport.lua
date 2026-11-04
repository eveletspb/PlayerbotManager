-- ============================================================
--  LBT_ExportImport.lua  |  Clipboard serialization only
-- ============================================================
PBM = PBM or {}

local function LB_SerializeValue(v)
    local t = type(v)
    if t == "string" then
        return string.format("%q", v)
    elseif t == "number" then
        return tostring(v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        local parts = {}
        local maxN = 0
        for k, _ in pairs(v) do
            if type(k) == "number" and k == math.floor(k) and k >= 1 then
                if k > maxN then maxN = k end
            end
        end
        local isArr = maxN > 0
        if isArr then
            for i = 1, maxN do
                if v[i] == nil then isArr = false; break end
            end
        end
        if isArr then
            for i = 1, maxN do
                parts[#parts+1] = LB_SerializeValue(v[i])
            end
        else
            for k, val in pairs(v) do
                local key
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    key = k
                elseif type(k) == "number" then
                    key = "[" .. tostring(k) .. "]"
                else
                    key = "[" .. LB_SerializeValue(tostring(k)) .. "]"
                end
                parts[#parts+1] = key .. "=" .. LB_SerializeValue(val)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    else
        return "nil"
    end
end

function PBM.LB_ExportDB()
    local db = LichborneTrackerDB
    -- Build stripped row copies: only identity/social fields.
    -- Gear slot data (ilvl array, ilvlLink, gs, realGs) is excluded intentionally —
    -- a fresh gear scan on Account B will populate those fields correctly.
    local strippedRows = {}
    for i, row in ipairs(db.rows or {}) do
        strippedRows[i] = {
            cls    = row.cls    or "",
            name   = row.name   or "",
            spec   = row.spec   or "",
            role   = row.role   or "",
            gs     = row.gs     or 0,
            realGs = row.realGs or 0,
        }
    end
    local payload = {
        rows        = strippedRows,
        profs       = db.profs,
        raidRosters = db.raidRosters,
        allGroups   = db.allGroups,
        allGroup    = db.allGroup,
        notes       = db.notes,
    }
    return PBM.EXPORT_PREFIX .. LB_SerializeValue(payload)
end

-- Only the data literals emitted by our serializer are accepted; never execute imports.
local function LB_ParseData(data)
    local pos, entries = 1, 0
    local function skipSpace()
        local _, last = data:find("^%s*", pos)
        pos = last + 1
    end
    local function fail()
        error("Invalid data near byte " .. pos, 0)
    end
    local parseValue
    parseValue = function(depth)
        if depth > 20 then fail() end
        skipSpace()
        local char = data:sub(pos, pos)
        if char == '"' or char == "'" then
            local quote, parts = char, {}
            pos = pos + 1
            while pos <= #data do
                char = data:sub(pos, pos)
                pos = pos + 1
                if char == quote then return table.concat(parts) end
                if char == "\\" then
                    char = data:sub(pos, pos)
                    local escapes = {a="\a", b="\b", f="\f", n="\n", r="\r", t="\t", v="\v",
                        ["\\"]="\\", ['"']='"', ["'"]="'", ["\n"]="\n"}
                    local digits = data:match("^%d%d?%d?", pos)
                    if digits then
                        local byte = tonumber(digits)
                        if byte > 255 then fail() end
                        parts[#parts + 1] = string.char(byte)
                        pos = pos + #digits
                    else
                        if not escapes[char] then fail() end
                        parts[#parts + 1] = escapes[char]
                        pos = pos + 1
                    end
                else
                    if char == "\n" or char == "\r" then fail() end
                    parts[#parts + 1] = char
                end
            end
            fail()
        elseif char == "{" then
            local value, index = {}, 1
            pos = pos + 1
            skipSpace()
            while data:sub(pos, pos) ~= "}" do
                entries = entries + 1
                if entries > 100000 then fail() end
                local key
                if data:sub(pos, pos) == "[" then
                    pos = pos + 1
                    key = parseValue(depth + 1)
                    if type(key) ~= "string" and type(key) ~= "number" then fail() end
                    skipSpace()
                    if data:sub(pos, pos) ~= "]" then fail() end
                    pos = pos + 1
                    skipSpace()
                    if data:sub(pos, pos) ~= "=" then fail() end
                    pos = pos + 1
                else
                    local _, last, name = data:find("^([%a_][%w_]*)%s*=", pos)
                    if last then key, pos = name, last + 1 end
                end
                if key == nil then key, index = index, index + 1 end
                value[key] = parseValue(depth + 1)
                skipSpace()
                char = data:sub(pos, pos)
                if char == "," or char == ";" then
                    pos = pos + 1
                    skipSpace()
                elseif char ~= "}" then
                    fail()
                end
            end
            pos = pos + 1
            return value
        end
        local word = data:match("^[%a_][%w_]*", pos)
        if word then
            pos = pos + #word
            if word == "true" then return true end
            if word == "false" then return false end
            if word == "nil" then return nil end
            fail()
        end
        local number = data:match("^[+-]?%d+%.?%d*[eE]?[+-]?%d*", pos)
            or data:match("^[+-]?%.%d+[eE]?[+-]?%d*", pos)
        local value = tonumber(number)
        if not value or value ~= value or math.abs(value) == math.huge then fail() end
        pos = pos + #number
        return value
    end
    local result = parseValue(0)
    skipSpace()
    if pos <= #data then fail() end
    return result
end

local function LB_ValidRows(rows)
    if type(rows) ~= "table" then return false end
    local count = 0
    for index, row in pairs(rows) do
        count = count + 1
        if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or type(row) ~= "table" then return false end
        for _, field in ipairs({"cls", "name", "spec", "role", "notes"}) do
            if row[field] ~= nil and type(row[field]) ~= "string" then return false end
        end
        for _, field in ipairs({"gs", "realGs", "level"}) do
            if row[field] ~= nil and (type(row[field]) ~= "number" or row[field] < 0) then return false end
        end
        if row.reserve ~= nil and type(row.reserve) ~= "boolean" then return false end
        for field, valueType in pairs({ilvl="number", gear="number", ilvlLink="string", filterRoles="boolean"}) do
            if row[field] ~= nil then
                if type(row[field]) ~= "table" then return false end
                for key, value in pairs(row[field]) do
                    if type(value) ~= valueType then return false end
                    if field == "filterRoles" then
                        if type(key) ~= "string" then return false end
                    elseif type(key) ~= "number" or key < 1 or key > PBM.GEAR_SLOTS or key % 1 ~= 0 then
                        return false
                    end
                end
            end
        end
    end
    for index = 1, count do if rows[index] == nil then return false end end
    return true
end

local function LB_ValidImport(data)
    if type(data) ~= "table" then return false end
    if data.rows ~= nil and not LB_ValidRows(data.rows) then return false end
    for _, field in ipairs({"raidRosters", "allGroups"}) do
        if data[field] ~= nil then
            if type(data[field]) ~= "table" then return false end
            for name, rows in pairs(data[field]) do
                if type(name) ~= "string" or not LB_ValidRows(rows) then return false end
            end
        end
    end
    if data.profs ~= nil then
        if type(data.profs) ~= "table" then return false end
        for name, profs in pairs(data.profs) do
            if type(name) ~= "string" or type(profs) ~= "table" then return false end
            for key, value in pairs(profs) do
                if type(key) ~= "string" or (type(value) ~= "boolean" and type(value) ~= "number") then return false end
            end
        end
    end
    if data.allGroup ~= nil and data.allGroup ~= "A" and data.allGroup ~= "B" and data.allGroup ~= "C" then return false end
    return data.notes == nil or type(data.notes) == "string"
end

function PBM.LB_ImportDB(str)
    if not str or str == "" then return nil, "Nothing to import — paste text first." end
    if #str > 2 * 1024 * 1024 then return nil, "Import is too large." end
    str = str:gsub("^%s+", "")
    str = str:match("^(.*%S)") or ""
    local data
    local legacyV2 = false
    if str:sub(1, #PBM.EXPORT_PREFIX) == PBM.EXPORT_PREFIX then
        data = str:sub(#PBM.EXPORT_PREFIX + 1)
    elseif str:sub(1, #PBM.EXPORT_PREFIX_V2) == PBM.EXPORT_PREFIX_V2 then
        legacyV2 = true
        data = str:sub(#PBM.EXPORT_PREFIX_V2 + 1)
    elseif str:sub(1, #PBM.EXPORT_PREFIX_V1) == PBM.EXPORT_PREFIX_V1 then
        data = str:sub(#PBM.EXPORT_PREFIX_V1 + 1)
    else
        return nil, "Not a valid Lichborne export string."
    end
    local ok, result = pcall(LB_ParseData, data)
    if not ok then return nil, "Parse error: " .. tostring(result) end
    if not LB_ValidImport(result) then return nil, "Invalid tracker data." end
    -- V2 legacy: restore pipe placeholders in any ilvlLink strings
    if legacyV2 and result.rows then
        for _, row in pairs(result.rows) do
            if row.ilvlLink then
                for i, lnk in ipairs(row.ilvlLink) do
                    if type(lnk) == "string" and lnk ~= "" then
                        row.ilvlLink[i] = lnk:gsub("ZZPIPEZZ", "|")
                    end
                end
            end
        end
    end
    return result, nil
end
