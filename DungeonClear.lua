-- DungeonClear Lua Companion Addon
-- Drives the C++ mod-dungeon-clear module with a premium UI

local AddonName = "DungeonClear"
local Prefix = "DC"

-- DB Setup
DungeonClearDB = DungeonClearDB or {
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
local currentPage = 1
local RedrawBossList
local UpdateFrameHeight, UpdateLayout
local pauseBtn
local isDCOn = false
local isPaused = false


-- UI Frame Creation
local frame = CreateFrame("Frame", "DungeonClearFrame", UIParent)
frame:SetSize(330, 420)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
-- Sit above most default UI so the readout stays usable
frame:SetFrameStrata("DIALOG")
frame:SetToplevel(true)
frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

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

local statusVal = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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

local targetVal = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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

-- Tiny (single-line) display: on/off circle + status + targeted boss
local tinyIndicator = frame:CreateTexture(nil, "OVERLAY")
tinyIndicator:SetSize(16, 16)
tinyIndicator:SetPoint("LEFT", frame, "LEFT", 10, 0)
tinyIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Offline")
tinyIndicator:Hide()

local tinyText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tinyText:SetPoint("LEFT", tinyIndicator, "RIGHT", 6, 0)
tinyText:SetText("Off")
tinyText:Hide()

-- Click target over the tiny circle; created after SendDcCommand is defined so
-- its OnClick can capture it. Forward-declared here for UpdateLayout/UpdateStatusUI.
local tinyToggle

-- Compact state -> (label, color) for the tiny line
local function FormatStateTiny(state)
    if state == "paused" then return "Paused", {0.9, 0.8, 0.2}
    elseif state == "moving" then return "Advancing", {0.2, 0.7, 1}
    elseif state == "resting" then return "Resting", {0.9, 0.8, 0.2}
    elseif state == "looting" then return "Looting", {0.9, 0.6, 0.1}
    elseif state == "door_blocked" then return "Door Blocked", {0.9, 0.2, 0.2}
    elseif state == "stalled" then return "Blocked", {0.9, 0.2, 0.2}
    elseif state == "fighting_trash" then return "Clearing Trash", {0.8, 0.3, 0.9}
    elseif state == "fighting_boss" then return "Boss Fight", {1, 0.2, 0.2}
    elseif state == "idle" then return "Idle", {0.6, 0.6, 0.6}
    end
    return "Active", {0.8, 0.8, 0.8}
end

local function RgbToHex(c)
    return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- Size the frame to hug the single-line content in tiny mode
local function UpdateTinyWidth()
    local w = 10 + 16 + 6 + (tinyText:GetStringWidth() or 0) + 12
    frame:SetWidth(math.max(140, w))
end

-- Helper to update status styling
local function UpdateStatusUI(enabled, targetName, state, stallReason)
    isPaused = (state == "paused")
    if not enabled or enabled == "0" then
        isDCOn = false
        isPaused = false
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
        isDCOn = true
        if isPaused then
            statusVal:SetText("PAUSED")
            statusVal:SetTextColor(0.9, 0.8, 0.2) -- Yellow
        else
            statusVal:SetText("ON")
            statusVal:SetTextColor(0.1, 0.9, 0.1) -- Green
        end

        -- Format state human readable
        local stateText = state or "Idle"
        local stateColor = {0.8, 0.8, 0.8}
        if state == "paused" then
            stateText = "Paused (holding position)"
            stateColor = {0.9, 0.8, 0.2} -- Yellow
        elseif state == "moving" then
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

    -- Update the tiny single-line display: circle + status + boss
    if not enabled or enabled == "0" then
        tinyIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Offline")
        tinyText:SetText("|cff999999Off|r")
    else
        if isPaused then
            -- Yellow "away" dot signals a held/paused clear.
            tinyIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Away")
        else
            tinyIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Online")
        end
        local tLabel, tColor = FormatStateTiny(state)
        local line = "|cff" .. RgbToHex(tColor) .. tLabel .. "|r"
        if targetName and targetName ~= "None" and targetName ~= "" then
            -- grey vertical divider between status and boss name
            line = line .. "  |cff808080||" .. "|r  |cffffd100" .. targetName .. "|r"
        end
        tinyText:SetText(line)
    end
    -- Pause/Resume button: label reflects current state; disabled when DC is off.
    if pauseBtn then
        if not isDCOn then
            pauseBtn:SetText("Pause")
            pauseBtn:Disable()
        else
            pauseBtn:SetText(isPaused and "Resume" or "Pause")
            pauseBtn:Enable()
        end
    end

    if DungeonClearDB.tinyMode then
        UpdateTinyWidth()
    end

    if UpdateFrameHeight then
        UpdateFrameHeight()
    end
end

-- Command sender via addon messages (silent, no audio cue)
-- Uses PARTY distribution with LANG_ADDON prefix; the server-side hook
-- intercepts and dispatches before any chat processing occurs.
local function SendDcCommand(subCmd, param)
    if (GetNumPartyMembers() and GetNumPartyMembers() > 0) or (GetNumRaidMembers() and GetNumRaidMembers() > 0) then
        local payload = "CMD\t" .. subCmd
        if param and param ~= "" then
            payload = payload .. "\t" .. tostring(param)
        end
        SendAddonMessage("DC", payload, "PARTY")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3333DungeonClear: You must be in a party to send bot commands.|r")
    end
end

-- Action Buttons Panel
-- Four-up action row: On / Off / Skip / Pause-Resume (narrowed to fit one row).
local onBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
onBtn:SetSize(68, 24)
onBtn:SetPoint("TOPLEFT", statusFrame, "BOTTOMLEFT", 0, -8)
onBtn:SetText("On")
onBtn:SetScript("OnClick", function() SendDcCommand("on") end)

local offBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
offBtn:SetSize(68, 24)
offBtn:SetPoint("LEFT", onBtn, "RIGHT", 11, 0)
offBtn:SetText("Off")
offBtn:SetScript("OnClick", function() SendDcCommand("off") end)

local skipBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
skipBtn:SetSize(68, 24)
skipBtn:SetPoint("LEFT", offBtn, "RIGHT", 11, 0)
skipBtn:SetText("Skip")
skipBtn:SetScript("OnClick", function() SendDcCommand("skip") end)

-- Pause/Resume toggle. Label + enabled state are driven by UpdateStatusUI;
-- the server-side action toggles pause/resume off the same "pause" subcommand.
pauseBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
pauseBtn:SetSize(68, 24)
pauseBtn:SetPoint("LEFT", skipBtn, "RIGHT", 11, 0)
pauseBtn:SetText("Pause")
pauseBtn:SetScript("OnClick", function() SendDcCommand("pause") end)

-- Invisible click target over the tiny circle. Off -> start DC; running ->
-- toggle pause/resume. Only shown in tiny mode (see UpdateLayout). Sits over
-- just the 16x16 dot so dragging the rest of the bar still works.
tinyToggle = CreateFrame("Button", "DungeonClearTinyToggle", frame)
tinyToggle:SetAllPoints(tinyIndicator)
tinyToggle:EnableMouse(true)
tinyToggle:SetScript("OnClick", function()
    if not isDCOn then
        SendDcCommand("on")
    else
        SendDcCommand("pause")
    end
end)
tinyToggle:Hide()

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

local BOSSES_PER_PAGE = 5

-- Page navigation buttons at the bottom of scrollContainer
local prevBtn = CreateFrame("Button", nil, scrollContainer, "UIPanelButtonTemplate")
prevBtn:SetSize(32, 22)
prevBtn:SetPoint("BOTTOMLEFT", scrollContainer, "BOTTOMLEFT", 10, 8)
prevBtn:SetText("<")

local nextBtn = CreateFrame("Button", nil, scrollContainer, "UIPanelButtonTemplate")
nextBtn:SetSize(32, 22)
nextBtn:SetPoint("BOTTOMRIGHT", scrollContainer, "BOTTOMRIGHT", -10, 8)
nextBtn:SetText(">")

local pageText = scrollContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pageText:SetPoint("CENTER", scrollContainer, "BOTTOM", 0, 19)
pageText:SetText("Page 1 of 1")
pageText:SetTextColor(0.8, 0.8, 0.8)

-- Pre-create rows (exactly BOSSES_PER_PAGE) inside scrollContainer
for i = 1, BOSSES_PER_PAGE do
    local row = CreateFrame("Frame", nil, scrollContainer)
    row:SetSize(286, 32)
    row:SetPoint("TOPLEFT", scrollContainer, "TOPLEFT", 10, -10 - (i - 1) * 33)
    
    -- Custom solid color texture instead of SetBackdrop to prevent client crashes
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetTexture(0.08, 0.10, 0.15, 0.4)
    row.bg = bg

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

prevBtn:SetScript("OnClick", function()
    if currentPage > 1 then
        currentPage = currentPage - 1
        RedrawBossList()
    end
end)

nextBtn:SetScript("OnClick", function()
    local numPages = math.max(1, math.ceil(#bosses / BOSSES_PER_PAGE))
    if currentPage < numPages then
        currentPage = currentPage + 1
        RedrawBossList()
    end
end)

-- Redraw Boss List rows (Paging Implementation)
RedrawBossList = function()
    local numPages = math.max(1, math.ceil(#bosses / BOSSES_PER_PAGE))
    if currentPage > numPages then
        currentPage = numPages
    end
    if currentPage < 1 then
        currentPage = 1
    end

    pageText:SetText("Page " .. currentPage .. " of " .. numPages)

    if currentPage == 1 then
        prevBtn:Disable()
    else
        prevBtn:Enable()
    end

    if currentPage == numPages then
        nextBtn:Disable()
    else
        nextBtn:Enable()
    end

    for i = 1, BOSSES_PER_PAGE do
        local row = bossRows[i]
        local bossIndex = (currentPage - 1) * BOSSES_PER_PAGE + i
        local boss = bosses[bossIndex]

        if boss then
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
                showGo = true
            end

            row.status:SetText(statusLabelText)
            row.status:SetTextColor(unpack(statusColor))

            if showGo then
                row.goBtn:Show()
                row.goBtn:SetScript("OnClick", function()
                    if not isDCOn then
                        SendDcCommand("on")
                    end
                    SendDcCommand("go", boss.entry)
                end)
            else
                row.goBtn:Hide()
            end

            row:Show()
        else
            row:Hide()
        end
    end
end

-- (Chat spam filter checkbox removed — addon messages are inherently silent)

-- Toggle Buttons and Layout Adjustments
local tinyBtn = CreateFrame("Button", "DungeonClearTinyButton", frame, "UIPanelButtonTemplate")
tinyBtn:SetSize(40, 20)
tinyBtn:SetPoint("RIGHT", closeBtn, "LEFT", 2, 0)
tinyBtn:SetText("Tiny")

local toggleBossesBtn = CreateFrame("Button", "DungeonClearToggleBossesButton", frame)
toggleBossesBtn:SetSize(24, 24)
toggleBossesBtn:SetPoint("LEFT", listLabel, "RIGHT", 6, 0)
toggleBossesBtn:SetNormalFontObject("GameFontNormal")
toggleBossesBtn:SetHighlightFontObject("GameFontHighlight")
toggleBossesBtn:SetText("[-]")
local btnText = toggleBossesBtn:GetFontString()
if btnText then
    btnText:SetTextColor(0.24, 0.60, 1.0)
end

UpdateFrameHeight = function()
    local hasStall = stallVal:IsShown()
    if DungeonClearDB.tinyMode then
        frame:SetHeight(28)
        UpdateTinyWidth()
    else
        frame:SetWidth(330)
        if DungeonClearDB.bossesFolded then
            frame:SetHeight(hasStall and 210 or 190)
        else
            frame:SetHeight(hasStall and 440 or 420)
        end
    end
end

UpdateLayout = function()
    if DungeonClearDB.tinyMode then
        -- Single-line readout only: no header, no close/tiny buttons, no panels
        header:Hide()
        closeBtn:Hide()
        tinyBtn:Hide()
        onBtn:Hide()
        offBtn:Hide()
        skipBtn:Hide()
        if pauseBtn then pauseBtn:Hide() end
        listLabel:Hide()
        toggleBossesBtn:Hide()
        scrollContainer:Hide()
        statusFrame:Hide()

        tinyIndicator:Show()
        tinyText:Show()
        if tinyToggle then tinyToggle:Show() end
    else
        tinyIndicator:Hide()
        tinyText:Hide()
        if tinyToggle then tinyToggle:Hide() end

        header:Show()
        closeBtn:Show()
        tinyBtn:Show()
        tinyBtn:SetText("Tiny")
        onBtn:Show()
        offBtn:Show()
        skipBtn:Show()
        if pauseBtn then pauseBtn:Show() end
        listLabel:Show()
        toggleBossesBtn:Show()
        statusFrame:Show()

        statusFrame:ClearAllPoints()
        statusFrame:SetPoint("TOP", frame, "TOP", 0, -35)

        if DungeonClearDB.bossesFolded then
            toggleBossesBtn:SetText("[+]")
            scrollContainer:Hide()

        else
            toggleBossesBtn:SetText("[-]")
            scrollContainer:Show()

        end
    end
    UpdateFrameHeight()
end

tinyBtn:SetScript("OnClick", function()
    DungeonClearDB.tinyMode = not DungeonClearDB.tinyMode
    UpdateLayout()
end)

toggleBossesBtn:SetScript("OnClick", function()
    DungeonClearDB.bossesFolded = not DungeonClearDB.bossesFolded
    UpdateLayout()
end)

-- Layout saving on drag stop
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
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
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

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
    if not frame:IsVisible() or not isDCOn then return end
    elapsed = elapsed + elap
    if elapsed >= 2.0 then
        elapsed = 0
        SendDcCommand("status", "addon")
    end
end
frame:SetScript("OnUpdate", OnUpdateHandler)

-- Addon Messages parsing
local function OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= "DC" then return end
    
    local parts = {}
    local start = 1
    while true do
        local pos = string.find(message, "\t", start)
        if not pos then
            table.insert(parts, string.sub(message, start))
            break
        end
        table.insert(parts, string.sub(message, start, pos - 1))
        start = pos + 1
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
        currentPage = 1
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
    elseif parts[1] == "CHAT" then
        -- Bot announcements routed through addon channel (silent)
        local chatMsg = parts[2] or ""
        DEFAULT_CHAT_FRAME:AddMessage("|cff3da6ff[DC] " .. chatMsg .. "|r")
    elseif parts[1] == "ERROR" then
        -- Error responses from the server hook
        local errorMsg = parts[2] or ""
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3333[DC] " .. errorMsg .. "|r")
    end
end

-- Event handler
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == AddonName then
            -- Initialize DB defaults if needed
            if DungeonClearDB.tinyMode == nil then DungeonClearDB.tinyMode = false end
            if DungeonClearDB.bossesFolded == nil then DungeonClearDB.bossesFolded = false end
            DungeonClearDB.hideChatSpam = nil -- Clean up legacy saved variable

            -- Restore layout
            frame:ClearAllPoints()
            frame:SetPoint(DungeonClearDB.point or "CENTER", UIParent, DungeonClearDB.relativePoint or "CENTER", DungeonClearDB.xOfs or 0, DungeonClearDB.yOfs or 0)
            
            if UpdateLayout then
                UpdateLayout()
            end

            if DungeonClearDB.visible then
                frame:Show()
            else
                frame:Hide()
            end
            
            -- WotLK addon message prefix registration (only needed/exists in 4.1+)
            if RegisterAddonMessagePrefix then
                RegisterAddonMessagePrefix(Prefix)
            end
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        OnAddonMessage(prefix, message, channel, sender)
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        local inInstance, instanceType = IsInInstance()
        if inInstance and instanceType == "party" then
            -- Auto-query bosses list when entering dungeon
            -- Small delay to ensure party is fully loaded on the server
            local delayFrame = CreateFrame("Frame")
            local delayElapsed = 0
            delayFrame:SetScript("OnUpdate", function(sf, elap)
                delayElapsed = delayElapsed + elap
                if delayElapsed >= 3.0 then
                    SendDcCommand("bosses", "addon")
                    sf:SetScript("OnUpdate", nil)
                end
            end)
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if frame:IsVisible() and isDCOn then
            SendDcCommand("status", "addon")
        end
    end
end)

-- Window show/hide triggers status update
frame:SetScript("OnShow", function()
    DungeonClearDB.visible = true
    SendDcCommand("status", "addon")
    SendDcCommand("bosses", "addon")
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
            -- Always reopen in full (non-tiny) mode
            DungeonClearDB.tinyMode = false
            UpdateLayout()
            frame:Show()
        end
    else
        -- Parse "/dc <sub> [param]" and send via addon message
        local subCmd, param = msg:match("^(%S+)%s*(.*)$")
        if subCmd then
            SendDcCommand(subCmd, param)
        end
    end
end

-- Print loaded notice
DEFAULT_CHAT_FRAME:AddMessage("|cff3da6ffDungeonClear Addon loaded.|r Type /dc to toggle window.")
