-- DungeonClear Lua Companion Addon
-- Drives the C++ mod-dungeon-clear module with a premium UI

local AddonName = "DungeonClear"
local Prefix = "DC"

-- DB Setup
DungeonClearDB = DungeonClearDB or {
    hideChatSpam = true,
    visible = false,
    point = "CENTER",
    relativePoint = "CENTER",
    xOfs = 0,
    yOfs = 0
}

-- Boss list table
local bosses = {}
local bossRows = {}
local pollTimer = nil

-- UI Frame Creation
local frame = CreateFrame("Frame", "DungeonClearFrame", UIParent)
frame:SetSize(330, 420)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)

-- Sleek Dark Backdrop
frame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
frame:SetBackdropColor(0.03, 0.03, 0.05, 0.90)
frame:SetBackdropBorderColor(0.20, 0.22, 0.28, 1.0)

-- Header Text
local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
header:SetPoint("TOP", frame, "TOP", 0, -12)
header:SetText("Dungeon Clear")
header:SetTextColor(0.24, 0.60, 1.0) -- Premium blue

-- Close Button
local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function()
    frame:Hide()
end)

-- Status Info Subframe (Glassmorphism effect)
local statusFrame = CreateFrame("Frame", nil, frame)
statusFrame:SetSize(306, 95)
statusFrame:SetPoint("TOP", frame, "TOP", 0, -35)
statusFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 12, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
statusFrame:SetBackdropColor(0.10, 0.12, 0.16, 0.60)
statusFrame:SetBackdropBorderColor(0.15, 0.17, 0.22, 0.8)

-- Status fields
local statusLabel = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusLabel:SetPoint("TOPLEFT", statusFrame, "TOPLEFT", 10, -10)
statusLabel:SetText("Mode Status:")
statusLabel:SetTextColor(0.8, 0.8, 0.8)

local statusVal = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightBold")
statusVal:SetPoint("LEFT", statusLabel, "RIGHT", 5, 0)
statusVal:SetText("OFF")
statusVal:SetTextColor(0.5, 0.5, 0.5)

local stateLabel = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
stateLabel:SetPoint("TOPLEFT", statusLabel, "BOTTOMLEFT", 0, -8)
stateLabel:SetText("Current State:")
stateLabel:SetTextColor(0.8, 0.8, 0.8)

local stateVal = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
stateVal:SetPoint("LEFT", stateLabel, "RIGHT", 5, 0)
stateVal:SetText("Inactive")
stateVal:SetTextColor(0.6, 0.6, 0.6)

local targetLabel = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
targetLabel:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -8)
targetLabel:SetText("Next Boss:")
targetLabel:SetTextColor(0.8, 0.8, 0.8)

local targetVal = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightBold")
targetVal:SetPoint("LEFT", targetLabel, "RIGHT", 5, 0)
targetVal:SetText("None")
targetVal:SetTextColor(1, 1, 1)

local stallLabel = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
stallLabel:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -8)
stallLabel:SetText("Warning:")
stallLabel:SetTextColor(0.9, 0.2, 0.2)
stallLabel:Hide()

local stallVal = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
stallVal:SetPoint("LEFT", stallLabel, "RIGHT", 5, 0)
stallVal:SetTextColor(0.9, 0.4, 0.4)
stallVal:SetWidth(210)
stallVal:SetJustifyH("LEFT")
stallVal:Hide()

-- Helper to update status styling
local function UpdateStatusUI(enabled, targetName, state, stallReason)
    if not enabled or enabled == "0" then
        statusVal:SetText("OFF")
        statusVal:SetTextColor(0.5, 0.5, 0.5)
        stateVal:SetText("Inactive")
        stateVal:SetTextColor(0.6, 0.6, 0.6)
        targetVal:SetText("None")
        targetVal:SetTextColor(0.6, 0.6, 0.6)
        stallLabel:Hide()
        stallVal:Hide()
        statusFrame:SetHeight(75)
    else
        statusVal:SetText("ON")
        statusVal:SetTextColor(0.1, 0.9, 0.1) -- Green

        -- Format state human readable
        local stateText = state or "Idle"
        local stateColor = {0.8, 0.8, 0.8}
        if state == "moving" then
            stateText = "Advancing"
            stateColor = {0.2, 0.7, 1} -- Light blue
        elseif state == "resting" then
            stateText = "Party Recovering / Resting"
            stateColor = {0.9, 0.8, 0.2} -- Yellow
        elseif state == "looting" then
            stateText = "Collecting Loot"
            stateColor = {0.9, 0.6, 0.1} -- Orange
        elseif state == "door_blocked" then
            stateText = "Blocked by Door"
            stateColor = {0.9, 0.2, 0.2} -- Red
        elseif state == "stalled" then
            stateText = "Route Blocked"
            stateColor = {0.9, 0.2, 0.2} -- Red
        elseif state == "fighting_trash" then
            stateText = "Clearing Path (Trash)"
            stateColor = {0.8, 0.3, 0.9} -- Purple
        elseif state == "fighting_boss" then
            stateText = "Engaging Boss!"
            stateColor = {1, 0.1, 0.1} -- Crimson
        elseif state == "idle" then
            stateText = "Idle / Waiting"
            stateColor = {0.6, 0.6, 0.6}
        end
        stateVal:SetText(stateText)
        stateVal:SetTextColor(unpack(stateColor))

        targetVal:SetText(targetName or "None")
        targetVal:SetTextColor(1, 0.82, 0) -- Gold

        if stallReason and stallReason ~= "" then
            stallLabel:Show()
            stallVal:Show()
            stallVal:SetText(stallReason)
            statusFrame:SetHeight(95)
        else
            stallLabel:Hide()
            stallVal:Hide()
            statusFrame:SetHeight(75)
        end
    end
end

-- Command executor helper
local function RunCommand(cmd)
    local chatBox = ChatFrameEditBox
    if chatBox then
        chatBox:SetText(cmd)
        ChatEdit_SendText(chatBox)
    else
        SendChatMessage(cmd, "PARTY")
    end
end

-- Action Buttons Panel
local onBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
onBtn:SetSize(90, 24)
onBtn:SetPoint("TOPLEFT", statusFrame, "BOTTOMLEFT", 0, -8)
onBtn:SetText("DC On")
onBtn:SetScript("OnClick", function() RunCommand(".dc on") end)

local offBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
offBtn:SetSize(90, 24)
offBtn:SetPoint("LEFT", onBtn, "RIGHT", 18, 0)
offBtn:SetText("DC Off")
offBtn:SetScript("OnClick", function() RunCommand(".dc off") end)

local skipBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
skipBtn:SetSize(90, 24)
skipBtn:SetPoint("LEFT", offBtn, "RIGHT", 18, 0)
skipBtn:SetText("Skip Boss")
skipBtn:SetScript("OnClick", function() RunCommand(".dc skip") end)

-- Boss List Label
local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
listLabel:SetPoint("TOPLEFT", onBtn, "BOTTOMLEFT", 0, -12)
listLabel:SetText("Dungeon Bosses")
listLabel:SetTextColor(0.24, 0.60, 1.0)

-- Boss List Scroll Frame container
local scrollContainer = CreateFrame("Frame", nil, frame)
scrollContainer:SetSize(306, 205)
scrollContainer:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -4)
scrollContainer:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 12, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
scrollContainer:SetBackdropColor(0.05, 0.05, 0.08, 0.50)
scrollContainer:SetBackdropBorderColor(0.15, 0.17, 0.22, 0.8)

-- Scroll Frame
local scrollFrame = CreateFrame("ScrollFrame", "DungeonClearScrollFrame", scrollContainer, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", scrollContainer, "TOPLEFT", 4, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", scrollContainer, "BOTTOMRIGHT", -26, 4)

-- Scroll Child
local scrollChild = CreateFrame("Frame", "DungeonClearScrollChild", scrollFrame)
scrollChild:SetSize(276, 1)
scrollFrame:SetScrollChild(scrollChild)

-- Redraw Boss List rows
local function RedrawBossList()
    -- Hide old rows
    for _, row in ipairs(bossRows) do
        row:Hide()
    end

    local rowHeight = 32
    local totalHeight = 0

    for i, boss in ipairs(bosses) do
        local row = bossRows[i]
        if not row then
            row = CreateFrame("Frame", nil, scrollChild)
            row:SetSize(276, rowHeight)
            row:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = nil, tile = true, tileSize = 16
            })
            row:SetBackdropColor(0.1, 0.12, 0.18, 0.2)

            -- Text label
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.text:SetWidth(150)
            row.text:SetJustifyH("LEFT")

            -- Status badge
            row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.status:SetPoint("LEFT", row.text, "RIGHT", 5, 0)

            -- "Go" action button
            row.goBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.goBtn:SetSize(46, 20)
            row.goBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.goBtn:SetText("Go")

            bossRows[i] = row
        end

        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -((i - 1) * rowHeight))
        row.text:SetText(boss.encounterIndex .. ". " .. boss.name)

        -- Style status color
        local statusLabelText = "Alive"
        local statusColor = {0.1, 0.9, 0.1}
        local showGo = true

        if boss.status == "dead" then
            statusLabelText = "Dead"
            statusColor = {0.6, 0.6, 0.6}
            showGo = false
        elseif boss.status == "skipped" then
            statusLabelText = "Skipped"
            statusColor = {0.9, 0.7, 0.1}
            showGo = true
        elseif boss.status == "missing" then
            statusLabelText = "Missing"
            statusColor = {0.5, 0.5, 0.7}
            showGo = true -- might not spawn yet, user can still path towards
        end

        row.status:SetText(statusLabelText)
        row.status:SetTextColor(unpack(statusColor))

        if showGo then
            row.goBtn:Show()
            row.goBtn:SetScript("OnClick", function()
                RunCommand(".dc go " .. boss.entry)
            end)
        else
            row.goBtn:Hide()
        end

        row:Show()
        totalHeight = totalHeight + rowHeight
    end

    scrollChild:SetHeight(math.max(totalHeight, 1))
end

-- Checkbox: Hide Spam
local hideSpamCheckbox = CreateFrame("CheckButton", "DungeonClearHideSpamCheckbox", frame, "InterfaceOptionsCheckButtonTemplate")
hideSpamCheckbox:SetPoint("TOPLEFT", scrollContainer, "BOTTOMLEFT", 0, -8)
DungeonClearHideSpamCheckboxText:SetText("Hide Bot Chat Spam")
hideSpamCheckbox:SetChecked(DungeonClearDB.hideChatSpam)
hideSpamCheckbox:SetScript("OnClick", function(self)
    DungeonClearDB.hideChatSpam = self:GetChecked()
end)

-- Layout saving on drag stop
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSavesLayout()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    DungeonClearDB.point = point
    DungeonClearDB.relativePoint = relativePoint
    DungeonClearDB.xOfs = xOfs
    DungeonClearDB.yOfs = yOfs
end)

-- Event Handling Frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Polling Status Helper
local function StartPolling()
    if not pollTimer then
        pollTimer = C_Timer.NewTimer(0.1, function() end) -- dummy initialization if needed
        -- WotLK C_Timer emulation or simple OnUpdate hook
    end
end

-- Custom timer implementation using frame OnUpdate since WotLK standard C_Timer is limited or backported
local elapsed = 0
local function OnUpdateHandler(self, elap)
    if not frame:IsVisible() then return end
    elapsed = elapsed + elap
    if elapsed >= 1.5 then
        elapsed = 0
        RunCommand(".dc status")
    end
end
frame:SetScript("OnUpdate", OnUpdateHandler)

-- Addon Messages parsing
local function OnAddonMessage(prefix, message, sender)
    if prefix ~= Prefix then return end
    
    local parts = {}
    for part in string.gmatch(message, "([^\t]+)") do
        table.insert(parts, part)
    end

    if parts[1] == "STATUS" then
        local enabled = parts[2]
        local nextBossEntry = parts[3]
        local nextBossName = parts[4]
        local stallReason = parts[5]
        local skippedCount = parts[6]
        local state = parts[7]

        if nextBossName == "None" then nextBossName = nil end
        if stallReason == "" then stallReason = nil end

        UpdateStatusUI(enabled, nextBossName, state, stallReason)
    elseif parts[1] == "BOSS_START" then
        bosses = {}
    elseif parts[1] == "BOSS" then
        local entry = tonumber(parts[2])
        local index = tonumber(parts[3])
        local name = parts[4]
        local status = parts[5]
        local x = tonumber(parts[6])
        local y = tonumber(parts[7])
        local z = tonumber(parts[8])

        table.insert(bosses, {
            entry = entry,
            encounterIndex = index,
            name = name,
            status = status,
            x = x, y = y, z = z
        })
    elseif parts[1] == "BOSS_END" then
        -- Sort bosses by encounter index
        table.sort(bosses, function(a, b)
            return a.encounterIndex < b.encounterIndex
        end)
        RedrawBossList()
    end
end

-- Event handler
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == AddonName then
            -- Restore layout
            frame:ClearAllPoints()
            frame:SetPoint(DungeonClearDB.point or "CENTER", UIParent, DungeonClearDB.relativePoint or "CENTER", DungeonClearDB.xOfs or 0, DungeonClearDB.yOfs or 0)
            hideSpamCheckbox:SetChecked(DungeonClearDB.hideChatSpam)
            
            if DungeonClearDB.visible then
                frame:Show()
            else
                frame:Hide()
            end
            
            -- WotLK addon message prefix registration
            RegisterAddonMessagePrefix(Prefix)
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        OnAddonMessage(prefix, message, sender)
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        local inInstance, instanceType = IsInInstance()
        if inInstance and instanceType == "party" then
            -- Auto-query bosses list when entering dungeon
            -- Small delay to ensure party is fully loaded on the server
            local delayFrame = CreateFrame("Frame")
            local delayElapsed = 0
            delayFrame:SetScript("OnUpdate", function(sf, elap)
                delayElapsed = delayElapsed + elap
                if delayElapsed >= 3.0 then
                    RunCommand(".dc bosses")
                    sf:SetScript("OnUpdate", nil)
                end
            end)
        end
    end
end)

-- Window show/hide triggers status update
frame:SetScript("OnShow", function()
    DungeonClearDB.visible = true
    RunCommand(".dc status")
    RunCommand(".dc bosses")
end)

frame:SetScript("OnHide", function()
    DungeonClearDB.visible = false
end)

-- Slash Command Registration
SLASH_DUNGEONCLEAR1 = "/dc"
SlashCmdList["DUNGEONCLEAR"] = function(msg)
    if msg == "" then
        if frame:IsVisible() then
            frame:Hide()
        else
            frame:Show()
        end
    else
        RunCommand(".dc " .. msg)
    end
end

-- Chat Message Spam Filter
local filterPatterns = {
    "^Dungeon clear: %a+%. Next boss:",
    "^Dungeon clear enabled%. Heading to",
    "^Dungeon clear disabled%.",
    "^Targeting boss: .-%s*%. Navigating%.%.%.",
    "^Skipped .-%s*%. Heading to",
    "^Skipped .-%s*%. No bosses left",
    "^%d+%.%s.-%s@%s%(%-?%d+,%s*%-?%d+,%s*%-?%d+%)%s%[.-%]$",
    "^Can't reach .-%s*:%s*not spawned on this map",
    "^Can't path to .-%s*:",
    "^Stuck near .-%s*:",
    "^A door blocks the path to",
    " died %- dungeon clear disabled",
    "All bosses cleared!"
}

local function ChatSpamFilter(self, event, msg, sender, ...)
    if not DungeonClearDB.hideChatSpam then return false end
    
    -- Only filter messages that match our patterns
    for _, pattern in ipairs(filterPatterns) do
        if string.find(msg, pattern) then
            return true -- Block message
        end
    end
    return false
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", ChatSpamFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", ChatSpamFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", ChatSpamFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", ChatSpamFilter)

-- Print loaded notice
DEFAULT_CHAT_FRAME:AddMessage("|cff3da6ffDungeonClear Addon loaded.|r Type /dc to toggle window.")
