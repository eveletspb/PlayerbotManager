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

    if not StaticPopupDialogs["PBM_EDIT_STATIC_TAB"] then
        StaticPopupDialogs["PBM_EDIT_STATIC_TAB"] = {
            text = "Edit static |cffd4af37%s|r?\n\nThis replaces roster %s.",
            button1 = "Edit", button2 = "Cancel",
            OnAccept = function(_, selection)
                if not selection or PBM.GetStatics()[selection.index] ~= selection.static or
                    (LichborneTrackerDB.raidGroup or "A") ~= selection.group or
                    (selection.static.raidName or LichborneTrackerDB.raidName or "N/A (5-Man)") ~= selection.raidName then return end
                if not PBM.LoadStatic(selection.index) then return end
                if PBM.RefreshRaidSelectionUI then PBM.RefreshRaidSelectionUI() end
                if PBM.RefreshRaidRows then PBM.RefreshRaidRows() end
                if PBM.RefreshOverviewRows then PBM.RefreshOverviewRows() end
                PBM.State.activeTab = "Raid"
                if PBM.UpdateTabs then PBM.UpdateTabs() end
                if PBM.RefreshRows then PBM.RefreshRows() end
                DEFAULT_CHAT_FRAME:AddMessage("|cff7799ffPBM:|r Static loaded for editing. Modify the Raid roster, then save it with the same name to update the static.")
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
    intro:SetText("|cffaaaaaaSaved raid compositions. Use Edit to change a static in the Raid roster.|r")

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

    local scroll = CreateFrame("ScrollFrame", "PBMStaticsScrollFrame", list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -28)
    scroll:SetSize(1016, 334)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1016, 334)
    scroll:SetScrollChild(content)

    local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    empty:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -8)
    empty:SetText("|cff888888No statics yet. Click Create Static.|r")
    local rows = {}

    local function CreateStaticRow(index)
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * 42)
        row:SetSize(1016, 36)
        row:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=8, edgeSize=6, insets={left=1,right=1,top=1,bottom=1}})
        row:SetBackdropColor(index % 2 == 0 and 0.06 or 0.08, 0.09, 0.18, 1)
        row:SetBackdropBorderColor(0.15, 0.22, 0.38, 0.8)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", row, "LEFT", 10, 0)
        label:SetWidth(466); label:SetJustifyH("LEFT")
        row.label = label
        local function ShowStaticDialog(dialog)
            local static = PBM.GetStatics()[index]
            if not static then return end
            PBM.State.pendingStaticIndex = index
            StaticPopup_Show(dialog, static.name or "Unnamed")
        end
        local function RowButton(text, x, color, callback)
            return MakeStaticButton(row, text, x, 4, 100, callback, color)
        end
        RowButton("Edit", 494, {0.20,0.70,0.40}, function()
            local static = PBM.GetStatics()[index]
            if not static then return end
            local raidName = static.raidName or LichborneTrackerDB.raidName or "N/A (5-Man)"
            local group = LichborneTrackerDB.raidGroup or "A"
            StaticPopup_Show("PBM_EDIT_STATIC_TAB", static.name or "Unnamed", raidName .. " (" .. group .. ")",
                { index = index, static = static, raidName = raidName, group = group })
        end)
        RowButton("Load", 598, {0.20,0.50,0.90}, function()
            ShowStaticDialog("PBM_LOAD_STATIC_TAB")
        end)
        RowButton("Invite", 702, {0.78,0.30,0.05}, function()
            ShowStaticDialog("PBM_INVITE_STATIC_TAB")
        end)
        RowButton("Rename", 806, {0.78,0.61,0.23}, function()
            ShowStaticDialog("PBM_RENAME_STATIC_TAB")
        end)
        RowButton("Delete", 910, {0.80,0.15,0.15}, function()
            ShowStaticDialog("PBM_DELETE_STATIC_TAB")
        end)
        return row
    end

    function PBM.RefreshStaticsPanel()
        local statics = PBM.GetStatics()
        if #statics == 0 then empty:Show() else empty:Hide() end
        for index, static in ipairs(statics) do
            local row = rows[index]
            if not row then
                row = CreateStaticRow(index)
                rows[index] = row
            end
            row.label:SetText("|cffd4af37"..(static.name or "Unnamed").."|r  |cffaaaaaa"..
                (static.raidName or "N/A").."  ("..tostring(static.raidSize or 0)..")|r")
            row:Show()
        end
        for index = #statics + 1, #rows do rows[index]:Hide() end
        local height = math.max(334, #statics * 42)
        content:SetHeight(height)
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), height - 334))
    end

    PBM.RefreshStaticsPanel()
    panel:Hide()
end
