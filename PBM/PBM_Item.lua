local function CanChangeInventoryItem(frame, item)
    for _, button in pairs(frame.buttons) do
        if button.item and button.item ~= item and button.item.id == item.id then
            LichborneOutput("Inventory action cancelled: multiple copies of "..item.name..".", 1, 0.5, 0.5)
            return false
        end
    end
    return true
end

PBM.addItem = function(pFrame, pInfo)
    local tLink = type(pInfo) == "string" and pInfo:match("^(|c%x%x%x%x%x%x%x%x|Hitem:%d+:[^|]*|h%[.-%]|h|r)")
    if not tLink then return end
    local tID = tLink:match("|Hitem:(%d+):")
    local botName = PBM.inventory.name
	local tInfo = PBM.doSplit(pInfo, "|")

	local tIcon = GetItemIcon(tID)
	local tName, _, tRare = GetItemInfo(tID)

	local tX = (pFrame.index%8) * 38
	local tY = math.floor(pFrame.index/8) * -37.1

	if(tName == nil) then tName = string.sub(tInfo[4], 3, string.len(tInfo[4]) - 1) end
	if(tRare == nil) then tRare = 4 end -- for Security

	local tButton = pFrame.addButton(pFrame.index + 1, tX, tY, tIcon, tLink)
	pFrame.catButton("Catecher", 270, -490, 308, 524)

	tButton.item = {}
	tButton.item.id = tID
	tButton.item.link = tLink
	tButton.item.name = tName
	tButton.item.info = pInfo
	tButton.item.rare = tRare

	--tButton.doLeft = function(pButton)
		--local tAction = PBM.inventory.action
		--local tName = PBM.inventory.name

    tButton.doLeft = function(pButton)
        if PBM.inventory.loading or PBM.inventory.name ~= botName then return end
        local tAction = PBM.inventory.action
        if (tAction == "s" or tAction == "destroy") and not CanChangeInventoryItem(pFrame, pButton.item) then return end

		if(tAction == "") then
			PBM.SendChatMessage(PBM.info.action, "SAY")
			return
		end

		--[[if(tAction == "s" and PBM.isTarget()) then
			if(pButton.item.id == "6948") then return SendChatMessage(PBM.info.itemsellalert, "SAY") end
			if(PBM.isInside(pButton.item.info or "", "%f[%a][Kk]ey%f[%A]")) then
                return SendChatMessage(PBM.info.keydestroyalert, "SAY")
			end
			--SendChatMessage(tAction .. " " .. pButton.tip, "WHISPER", nil, tName)
			SendChatMessage(tAction .. " " .. pButton.tip, "WHISPER", nil, botName)
			pButton:Hide()
			return
		end]]--

        if(tAction == "s" and PBM.isTarget()) then
			if(pButton.item.id == "6948") then
				return PBM.SendChatMessage(PBM.info.itemsellalert, "SAY")
			end

			if(PBM.isInside(pButton.item.info or "", "%f[%a][Kk]ey%f[%A]")) then
                return PBM.SendChatMessage(PBM.info.keydestroyalert, "SAY")
			end

			-- Envoi de la commande "s [item]" au bot dont l’inventaire est ouvert
			--SendChatMessage(tAction .. " " .. pButton.tip, "WHISPER", nil, tName)
			PBM.SendChatMessage(tAction .. " " .. pButton.tip, "WHISPER", nil, botName)

			-- On masque l’item cliqué pour un feedback immédiat
			pButton:Hide()

			-- Puis on relit proprement l’inventaire du bot pour se resynchroniser
			if PBM.RefreshInventory then
				PBM.RefreshInventory(0.3)
			end

			return
		end

		if(tAction == "e" or tAction == "u" or tAction == "give") then
			--SendChatMessage(tAction .. " " .. pButton.tip, "WHISPER", nil, tName)
			PBM.SendChatMessage(tAction .. " " .. pButton.tip, "WHISPER", nil, botName)
			return
		end

		if(tAction == "destroy") then
			local needsConfirm = false
			if(pButton.item.id == "6948") then needsConfirm = true end -- Hearthstone
			if(PBM.isInside(pButton.item.info, "%f[%a][Kk]ey%f[%A]")) then needsConfirm = true end
			if(pButton.item.rare > 3) then needsConfirm = true end -- Épique ou mieux
			if needsConfirm then
				if not StaticPopupDialogs["PBM_CONFIRM_DESTROY"] then
					StaticPopupDialogs["PBM_CONFIRM_DESTROY"] = {
						text = PBM.info.itemdestroyalert,
						button1 = OKAY,
						button2 = CANCEL,
						timeout = 0,
						whileDead = 1,
						hideOnEscape = 1,
						OnAccept = function(self, data)
							if not data or PBM.inventory.loading or PBM.inventory.name ~= data.tName or
                                PBM.inventory.request ~= data.request or data.button.item ~= data.item or
                                not CanChangeInventoryItem(data.frame, data.item) then return end
							PBM.SendChatMessage("destroy" .. " " .. data.tip, "WHISPER", nil, data.tName)
							data.button:Hide()
						end,
					}
				end
				--local data = { button = pButton, tName = tName }
				local data = { button = pButton, tName = botName, tip = pButton.tip,
                    request = PBM.inventory.request, item = pButton.item, frame = pFrame }
				StaticPopup_Show("PBM_CONFIRM_DESTROY", pButton.item.link, nil, data)
				return
			end
			-- Pas de confirmation requise
			--SendChatMessage(tAction .. " " .. pButton.tip, "WHISPER", nil, tName)
			PBM.SendChatMessage(tAction .. " " .. pButton.tip, "WHISPER", nil, botName)
			pButton:Hide()
			return
		end
	end

	if(string.sub(tInfo[6], 1, 2) == "rx") then
		tButton.setAmount(string.sub(PBM.doSplit(tInfo[6], " ")[1], 3))
	end

	pFrame.index = pFrame.index + 1
end
