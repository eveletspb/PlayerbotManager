dofile('PBM/PBM_Constants.lua')
dofile('PBM/PBM_ExportImport.lua')

local name = 'Бот'
LichborneTrackerDB = {
    rows = {{name=name, cls='Mage', spec='Fire', gs=200, realGs=4000}},
    notes = 'Quotes " and slash \\ and newline\nCR\r tab\t zero\000 pipes |Hitem:1|h',
    profs = {[name]={mining=1, fishing=true}},
    raidRosters = {['Trial "A"']={{name=name, reserve=true, filterRoles={D=true}}}},
    allGroups = {A={{name=name}}, B={}, C={}}, allGroup='A',
}
local result, err = PBM.LB_ImportDB(PBM.LB_ExportDB())
assert(result, err)
assert(result.rows[1].name == name and result.rows[1].gs == 200)
assert(result.notes == LichborneTrackerDB.notes)
assert(result.raidRosters['Trial "A"'][1].reserve)
assert(result.profs[name].mining == 1 and result.allGroup == 'A')
for _, version in ipairs({'V1', 'V2', 'V3'}) do
    local data = assert(PBM.LB_ImportDB('LICHBORNE_'..version..':{rows={{name="Old",ilvlLink={"ZZPIPEZZHitem:1"}}}}'))
    assert(data.rows[1].ilvlLink[1] == (version == 'V2' and '|Hitem:1' or 'ZZPIPEZZHitem:1'))
end
local invalid = {
    '(function() auditMarker=true; return {} end)()',
    '{rows=SendChatMessage("command", "SAY")}',
    '{rows=(function() while true do end end)()}',
    '{}; auditMarker=true', '{rows="broken"}', '{rows={false}}',
    '{rows={{name={}}}}', '{rows={{ilvl="broken"}}}', '{rows={[2]={name="Gap"}}}',
    '{raidRosters={broken=false}}', '{allGroups={A={"broken"}}}',
    '{profs={Bot={fishing={}}}}', '{notes={}}', '{allGroup={}}',
    '{rows={{gs=1e999}}}', string.rep('{',22)..string.rep('}',22),
}
for _, payload in ipairs(invalid) do
    local imported = PBM.LB_ImportDB(PBM.EXPORT_PREFIX..payload)
    assert(not imported, payload)
end
assert(not auditMarker)
assert(not PBM.LB_ImportDB('garbage'..PBM.EXPORT_PREFIX..'{}'))
assert(not PBM.LB_ImportDB(PBM.EXPORT_PREFIX..string.rep(' ',2*1024*1024)..'{}'))
print('PASS import: round-trip, legacy versions, code rejection, schema and limits')
