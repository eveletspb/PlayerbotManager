-- ============================================================
-- PBM_Tab_PullPresets.lua | Automatic group pull behavior preset
-- ============================================================
PBM = PBM or {}

local function MakePresetToggle(parent, label, x, y, initial, onChanged)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    button:SetSize(220, 30)
    button:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=8,
        insets={left=2,right=2,top=2,bottom=2},
    })
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetAllPoints(button)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")

    function button:SetValue(value)
        self.value = value and true or false
        self:SetBackdropColor(self.value and 0.05 or 0.08, self.value and 0.35 or 0.10,
            self.value and 0.12 or 0.18, 1)
        self:SetBackdropBorderColor(self.value and 0.25 or 0.20,
            self.value and 0.85 or 0.30, self.value and 0.35 or 0.50, 0.9)
        text:SetText("|cffd4af37"..label..": "..(self.value and "ON" or "OFF").."|r")
    end

    button:SetValue(initial)
    button:SetScript("OnClick", function(self)
        self:SetValue(not self.value)
        onChanged(self.value)
    end)
    return button
end

function PBM.BuildPullPresetsPanel(panel)
    if not PBM.GetGroupBehavior then return end
    local behavior = PBM.GetGroupBehavior()

    local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intro:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -38)
    intro:SetText("|cffaaaaaaConfigure the group pull preset. It is sent automatically when the group changes.|r")

    local autoToggle = MakePresetToggle(panel, "Auto apply on group change", 14, 72,
        behavior.enabled, function(value)
            behavior.enabled = value
            if value then
                PBM.State.groupBehaviorLastGroupKey = nil
                PBM.ApplyGroupBehavior(true)
            end
        end)

    local aoeToggle = MakePresetToggle(panel, "AoE for entire group", 14, 112,
        behavior.aoe, function(value)
            behavior.aoe = value
        end)

    local delayLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    delayLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -164)
    delayLabel:SetText("|cffd4af37Delay before attack (seconds):|r")

    local delayEdit = CreateFrame("EditBox", nil, panel)
    delayEdit:SetPoint("TOPLEFT", panel, "TOPLEFT", 250, -158)
    delayEdit:SetSize(80, 28)
    delayEdit:SetAutoFocus(false)
    delayEdit:SetMaxLetters(2)
    delayEdit:SetNumeric(true)
    delayEdit:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    delayEdit:SetTextColor(1, 0.85, 0.25)
    delayEdit:SetJustifyH("CENTER")
    delayEdit:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=8,
        insets={left=2,right=2,top=2,bottom=2},
    })
    delayEdit:SetBackdropColor(0.04, 0.06, 0.13, 1)
    delayEdit:SetBackdropBorderColor(0.78, 0.61, 0.23, 0.9)
    delayEdit:SetText(tostring(behavior.attackDelay or 0))

    local function SaveDelay()
        local value = tonumber(delayEdit:GetText()) or 0
        behavior.attackDelay = math.max(0, math.min(60, math.floor(value)))
        delayEdit:SetText(tostring(behavior.attackDelay))
    end
    delayEdit:SetScript("OnEnterPressed", function(self) SaveDelay(); self:ClearFocus() end)
    delayEdit:SetScript("OnEditFocusLost", SaveDelay)

    local apply = CreateFrame("Button", nil, panel)
    apply:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -214)
    apply:SetSize(220, 34)
    apply:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=8,
        insets={left=2,right=2,top=2,bottom=2},
    })
    apply:SetBackdropColor(0.03, 0.14, 0.245, 1)
    apply:SetBackdropBorderColor(0.78, 0.61, 0.23, 0.9)
    apply:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local applyText = apply:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    applyText:SetAllPoints(apply)
    applyText:SetJustifyH("CENTER"); applyText:SetJustifyV("MIDDLE")
    applyText:SetText("|cffd4af37Apply to current group|r")
    apply:SetScript("OnClick", function()
        SaveDelay()
        PBM.ApplyGroupBehavior(false)
    end)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -270)
    hint:SetWidth(700)
    hint:SetJustifyH("LEFT")
    hint:SetText("|cff888888When enabled, PBM waits briefly after a party/raid roster change, then sends the AoE and attack-delay commands to the whole group.|r")

    panel:Hide()
end
