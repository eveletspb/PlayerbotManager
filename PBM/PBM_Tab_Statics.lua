-- ============================================================
--  PBM_Tab_Statics.lua  |  Saved raid compositions
-- ============================================================
PBM = PBM or {}

local function MakeStaticButton(parent, label, x, y, w, onClick, color)
    local r, g, b = color[1], color[2], color[3]
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    btn:SetSize(w, 28)
    btn:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=8,
        insets={left=2,right=2,top=2,bottom=2},
    })
    btn:SetBackdropColor(r * 0.35, g * 0.35, b * 0.35, 1)
    btn:SetBackdropBorderColor(0.78, 0.61, 0.23, 0.9)
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetAllPoints(btn)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetText("|cffd4af37"..label.."|r")
    btn:SetScript("OnClick", onClick)
    return btn
end

local function EnsureStaticDialogs()
    if not StaticPopupDialogs["PBM_SAVE_STATIC_TAB"] then
        StaticPopupDialogs["PBM_SAVE_STATIC_TAB"] = {
            text = "Create static from current roster:",
            button1 = "Create",
            button2 = "Cancel",
            hasEditBox = true,
            maxLetters = 48,
            OnShow = function(self)
                self.editBox:SetText("")
                self.editBox:SetFocus()
            end,
            OnAccept = function(self)
                local static, status = PBM.SaveCurrentStatic(self.editBox:GetText())
                if not static then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00PBM:|r Static name cannot be empty.")
                    return
                end
                DEFAULT_CHAT_FRAME:AddMessage("|cff7799ffPBM:|r Static |cffd4af37"..static.name.."|r "..
                    (status == "UPDATED" and "updated." or "created."))
                if PBM.RefreshStaticsPanel then PBM.RefreshStaticsPanel() end
            end,
            timeout=0, whileDead=true, hideOnEscape=true,
        }
    end

    if not StaticPopupDialogs["PBM_LOAD_STATIC_TAB"] then
        StaticPopupDialogs["PBM_LOAD_STATIC_TAB"] = {
            text = "Load static |cffd4af37%s|r?\n\nThis replaces the current roster.",
            button1 = "Load", button2 = "Cancel",
            OnAccept = function()
                if PBM.LoadStatic(PBM.State.pendingStaticIndex) then
                    if PBM.RefreshRaidSelectionUI then PBM.RefreshRaidSelectionUI() end
                    PBM.RefreshRaidRows()
                    if PBM.RefreshOverviewRows then PBM.RefreshOverviewRows() end
                    DEFAULT_CHAT_FRAME:AddMessage("|cff7799ffPBM:|r Static loaded into the current roster.")
                end
                PBM.State.pendingStaticIndex = nil
            end,
            OnCancel = function() PBM.State.pendingStaticIndex = nil end,
            timeout=0, whileDead=true, hideOnEscape=true,
        }
    end

    if not StaticPopupDialogs["PBM_INVITE_STATIC_TAB"] then
        StaticPopupDialogs["PBM_INVITE_STATIC_TAB"] = {
            text = "Load static |cffd4af37%s|r and invite its bots?\n\nThis replaces the current roster.",
            button1 = "Invite", button2 = "Cancel",
            OnAccept = function()
                if PBM.LoadStatic(PBM.State.pendingStaticIndex) then
                    if PBM.RefreshRaidSelectionUI then PBM.RefreshRaidSelectionUI() end
                    PBM.RefreshRaidRows()
                    if PBM.RefreshOverviewRows then PBM.RefreshOverviewRows() end
                    if LichborneInviteRaidBtn then LichborneInviteRaidBtn:Click() end
                end
                PBM.State.pendingStaticIndex = nil
            end,
            OnCancel = function() PBM.State.pendingStaticIndex = nil end,
            timeout=0, whileDead=true, hideOnEscape=true,
        }
    end

    if not StaticPopupDialogs["PBM_DELETE_STATIC_TAB"] then
        StaticPopupDialogs["PBM_DELETE_STATIC_TAB"] = {
            text = "Delete static |cffd4af37%s|r?",
            button1 = "Delete", button2 = "Cancel",
            OnAccept = function()
                if PBM.DeleteStatic(PBM.State.pendingStaticIndex) then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff7799ffPBM:|r Static deleted.")
                end
                PBM.State.pendingStaticIndex = nil
                if PBM.RefreshStaticsPanel then PBM.RefreshStaticsPanel() end
            end,
            OnCancel = function() PBM.State.pendingStaticIndex = nil end,
            timeout=0, whileDead=true, hideOnEscape=true,
        }
    end

    if not StaticPopupDialogs["PBM_RENAME_STATIC_TAB"] then
        StaticPopupDialogs["PBM_RENAME_STATIC_TAB"] = {
            text = "Rename static |cffd4af37%s|r:",
            button1 = "Rename", button2 = "Cancel",
            hasEditBox = true, maxLetters = 48,
            OnShow = function(self)
                local static = PBM.GetStatics()[PBM.State.pendingStaticIndex]
                self.editBox:SetText(static and static.name or "")
                self.editBox:HighlightText(); self.editBox:SetFocus()
            end,
            OnAccept = function(self)
                if PBM.RenameStatic(PBM.State.pendingStaticIndex, self.editBox:GetText()) then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff7799ffPBM:|r Static renamed.")
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00PBM:|r Name is empty or already exists.")
                end
                PBM.State.pendingStaticIndex = nil
                if PBM.RefreshStaticsPanel then PBM.RefreshStaticsPanel() end
            end,
            OnCancel = function() PBM.State.pendingStaticIndex = nil end,
            timeout=0, whileDead=true, hideOnEscape=true,
        }
    end
end

function PBM.BuildStaticsPanel(panel)
    EnsureStaticDialogs()
    local pfl = panel:GetFrameLevel()
    local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intro:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -38)
    intro:SetText("|cffaaaaaaSaved raid compositions. Create a static from the current Raid roster.|r")

    MakeStaticButton(panel, "Create Static", 14, 62, 170,
        function() StaticPopup_Show("PBM_SAVE_STATIC_TAB") end, {0.78, 0.61, 0.23})
    MakeStaticButton(panel, "Refresh", 190, 62, 100,
        function() PBM.RefreshStaticsPanel() end, {0.20, 0.50, 0.90})

    local list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -108)
    list:SetSize(1058, 370)
    list:SetFrameLevel(pfl + 1)
    list:SetBackdrop({
        bgFile="Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=8,
        insets={left=2,right=2,top=2,bottom=2},
    })
    list:SetBackdropColor(0.04, 0.06, 0.13, 1)
    list:SetBackdropBorderColor(0.78, 0.61, 0.23, 0.7)
    panel.staticList = list

    local title = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -8)
    title:SetText("|cffd4af37Saved Statics|r")

    function PBM.RefreshStaticsPanel()
        for _, child in ipairs(panel.staticRows or {}) do child:Hide() end
        panel.staticRows = {}
        local statics = PBM.GetStatics()
        if #statics == 0 then
            local empty = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            empty:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -36)
            empty:SetText("|cff888888No statics yet. Click Create Static.|r")
            panel.staticRows[1] = empty
            return
        end

        for index, static in ipairs(statics) do
            local row = CreateFrame("Frame", nil, list)
            row:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -28 - (index - 1) * 42)
            row:SetSize(1042, 36)
            row:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=8, edgeSize=6, insets={left=1,right=1,top=1,bottom=1}})
            row:SetBackdropColor(index % 2 == 0 and 0.06 or 0.08, 0.09, 0.18, 1)
            row:SetBackdropBorderColor(0.15, 0.22, 0.38, 0.8)

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", row, "LEFT", 10, 0)
            label:SetWidth(490); label:SetJustifyH("LEFT")
            label:SetText("|cffd4af37"..(static.name or "Unnamed").."|r  |cffaaaaaa"..
                (static.raidName or "N/A").."  ("..tostring(static.raidSize or 0)..")|r")

            local captured = index
            local function RowButton(text, x, color, callback)
                return MakeStaticButton(row, text, x, 4, 108, callback, color)
            end
            RowButton("Load", 520, {0.20,0.50,0.90}, function()
                PBM.State.pendingStaticIndex = captured
                StaticPopup_Show("PBM_LOAD_STATIC_TAB", static.name or "Unnamed")
            end)
            RowButton("Invite", 634, {0.78,0.30,0.05}, function()
                PBM.State.pendingStaticIndex = captured
                StaticPopup_Show("PBM_INVITE_STATIC_TAB", static.name or "Unnamed")
            end)
            RowButton("Rename", 748, {0.78,0.61,0.23}, function()
                PBM.State.pendingStaticIndex = captured
                StaticPopup_Show("PBM_RENAME_STATIC_TAB", static.name or "Unnamed")
            end)
            RowButton("Delete", 862, {0.80,0.15,0.15}, function()
                PBM.State.pendingStaticIndex = captured
                StaticPopup_Show("PBM_DELETE_STATIC_TAB", static.name or "Unnamed")
            end)
            panel.staticRows[#panel.staticRows + 1] = row
        end
    end

    PBM.RefreshStaticsPanel()
    panel:Hide()
end
