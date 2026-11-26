PBM = { inventory = { name = "Bot", action = "destroy" } }
dofile("PBM/PBM_Engine.lua")
dofile("PBM/PBM_Item.lua")

function GetItemIcon() return "ring" end
function GetItemInfo() return "Ring", "|cffa335ee|Hitem:10:0:0|h[Ring]|h|r", 4 end
local message
function LichborneOutput(text) message = text end
PBM.SendChatMessage = function() error("ambiguous action was sent") end

local frame = { index = 0, buttons = {}, catButton = function() end }
function frame.addButton(slot, _, _, _, link)
    local button = { tip = link }
    frame.buttons[slot] = button
    return button
end
local first = "|cffa335ee|Hitem:10:111:0|h[Ring]|h|r"
local second = "|cffa335ee|Hitem:10:222:0|h[Ring]|h|r"
PBM.addItem(frame, first)
PBM.addItem(frame, second)
assert(frame.buttons[1].tip == first and frame.buttons[2].tip == second)
frame.buttons[1].doLeft(frame.buttons[1])
assert(message and message:find("multiple copies", 1, true))
print("PASS inventory items: duplicate names, full links and ambiguous action guard")
