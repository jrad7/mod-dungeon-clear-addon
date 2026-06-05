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

-- Boss list table. `bosses` is what the UI renders; `pendingBosses` stages an
-- in-flight server response and is only committed to `bosses` on BOSS_END, and
-- only when it's non-empty. This keeps a good list "sticky": a transient empty
-- reply (bot still on a loading screen, a second tank bot not yet in the
-- instance, or two tanks' sequences interleaving) can no longer blank a list
-- that already loaded.
local bosses = {}
local pendingBosses = {}
local bossRows = {}
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
-- Right-click anywhere on the tiny bar restores the full window. Guarded by
-- tinyMode so right-clicks in full mode do nothing, and left-drag still moves.
frame:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" and DungeonClearDB.tinyMode then
        DungeonClearDB.tinyMode = false
        UpdateLayout()
    end
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

-- Free-text detail sub-line under the state (who we're waiting on, what we're
-- heading to, etc.). Wraps to a second line if needed; the reserved gap below
-- keeps the Next Boss / Warning rows from shifting.
local detailVal = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
detailVal:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -2)
detailVal:SetWidth(300)
detailVal:SetJustifyH("LEFT")
detailVal:SetTextColor(0.7, 0.7, 0.7)
detailVal:SetText("")

local targetLabel = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
targetLabel:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -34)
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
    elseif state == "pathing" then return "Plotting Route", {0.4, 0.7, 0.9}
    elseif state == "pursuing" then return "Closing In", {0.3, 0.8, 1}
    elseif state == "recovering" then return "Repathing", {0.9, 0.6, 0.2}
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
local function UpdateStatusUI(enabled, targetName, state, stallReason, detail)
    isPaused = (state == "paused")
    if not enabled or enabled == "0" then
        isDCOn = false
        isPaused = false
        statusVal:SetText("OFF")
        statusVal:SetTextColor(0.5, 0.5, 0.5)
        stateVal:SetText("Inactive")
        stateVal:SetTextColor(0.6, 0.6, 0.6)
        detailVal:SetText("")
        targetVal:SetText("None")
        targetVal:SetTextColor(0.6, 0.6, 0.6)
        stallLabel:Hide()
        stallVal:Hide()
        statusFrame:SetHeight(101)
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
        elseif state == "pathing" then
            stateText = "Plotting Route"
            stateColor = {0.4, 0.7, 0.9} -- Blue
        elseif state == "pursuing" then
            stateText = "Closing on Boss"
            stateColor = {0.3, 0.8, 1} -- Light blue
        elseif state == "recovering" then
            stateText = "Recovering / Repathing"
            stateColor = {0.9, 0.6, 0.2} -- Amber
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

        detailVal:SetText(detail or "")

        targetVal:SetText(targetName or "None")
        targetVal:SetTextColor(1, 0.82, 0) -- Gold

        if stallReason and stallReason ~= "" then
            stallLabel:Show()
            stallVal:Show()
            stallVal:SetText(stallReason)
            statusFrame:SetHeight(121)
        else
            stallLabel:Hide()
            stallVal:Hide()
            statusFrame:SetHeight(101)
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
        -- Verbose tiny line: the action sentence (who we're waiting on / where
        -- we're heading), colored by the state, then a grey pipe divider and
        -- the target boss name. Falls back to the state label when there's no
        -- detail (e.g. a stall).
        local actionText = (detail and detail ~= "") and detail or tLabel
        local line = "|cff" .. RgbToHex(tColor) .. actionText .. "|r"
        if targetName and targetName ~= "None" and targetName ~= "" then
            -- grey vertical divider between action and boss name
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
    elseif param ~= "addon" then
        -- Explicit user action (button / boss-list click) with no party to
        -- relay it to: tell them once. The automatic background refreshes
        -- (status / boss-list, param == "addon") stay silent so a solo player
        -- standing in a dungeon isn't spammed every couple seconds.
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
tinyToggle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
tinyToggle:SetScript("OnClick", function(self, button)
    -- Right-click over the circle expands back to the full window (matches the
    -- frame-level OnMouseUp handler that covers the rest of the tiny bar).
    if button == "RightButton" then
        DungeonClearDB.tinyMode = false
        UpdateLayout()
        return
    end
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

local ROW_HEIGHT = 30
local VISIBLE_ROWS = 6

-- Scrollable boss list. FauxScrollFrame is the idiomatic WotLK pattern: a small
-- fixed pool of visible rows is reused while an offset selects which slice of
-- `bosses` they display, so the list scrolls without growing the window.
local scrollFrame = CreateFrame("ScrollFrame", "DungeonClearScrollFrame", scrollContainer, "FauxScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", scrollContainer, "TOPLEFT", 8, -8)
scrollFrame:SetPoint("BOTTOMRIGHT", scrollContainer, "BOTTOMRIGHT", -28, 8) -- leave room for the scrollbar
scrollFrame:EnableMouseWheel(true)
scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, RedrawBossList)
end)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local bar = DungeonClearScrollFrameScrollBar
    bar:SetValue(bar:GetValue() - delta * ROW_HEIGHT)
end)

-- Pre-create the visible row pool inside scrollContainer, anchored to scrollFrame
for i = 1, VISIBLE_ROWS do
    local row = CreateFrame("Frame", nil, scrollContainer)
    row:SetSize(262, ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)

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

-- Redraw Boss List rows (FauxScrollFrame implementation)
RedrawBossList = function()
    -- Never render a blank panel. Until a real list arrives, show a single
    -- placeholder row so the user sees the list is loading rather than empty.
    -- The OnUpdate ensure-loop keeps re-requesting until bosses populate.
    if #bosses == 0 then
        FauxScrollFrame_Update(scrollFrame, 0, VISIBLE_ROWS, ROW_HEIGHT)
        for i = 1, VISIBLE_ROWS do bossRows[i]:Hide() end
        local row = bossRows[1]
        row.text:SetText("Loading boss list...")
        row.text:SetTextColor(0.6, 0.6, 0.6)
        row.status:SetText("")
        row.goBtn:Hide()
        row:Show()
        return
    end

    FauxScrollFrame_Update(scrollFrame, #bosses, VISIBLE_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scrollFrame)

    for i = 1, VISIBLE_ROWS do
        local row = bossRows[i]
        -- 1-based ordinal position in the sorted list: clean sequential numbering
        -- even when a filtered wing yields non-contiguous encounter indices.
        local dataIndex = i + offset
        local boss = bosses[dataIndex]

        if boss then
            -- On split maps, tag the row with its region. Wing labels read like
            -- "Maraudon (Orange)"; show just the parenthetical ("Orange") to
            -- keep the row short, falling back to the full label otherwise.
            local label = dataIndex .. ". " .. boss.name
            if boss.wing then
                local region = boss.wing:match("%((.-)%)") or boss.wing
                label = label .. " |cff9999ff(" .. region .. ")|r"
            end
            row.text:SetText(label)
            -- Reset color: the loading placeholder dims row 1 to grey, so a real
            -- entry reusing that row must restore the normal white highlight.
            row.text:SetTextColor(1, 1, 1)

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
            frame:SetHeight(hasStall and 236 or 216)
        else
            frame:SetHeight(hasStall and 466 or 446)
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

-- Request the boss list from the tank bot. The server's "dungeon bosses" value
-- returns empty (and caches that for ~5s) whenever the bot isn't fully in the
-- dungeon yet, so a single query on zone-change is unreliable. Callers pair this
-- with the empty-list retry below to keep asking until a real list comes back;
-- once populated, the server pushes any further changes on its own.
local function RequestBossList()
    SendDcCommand("bosses", "addon")
end

-- The server is now event-driven: while a clear is running it recomputes the
-- tank's status every world tick and pushes a STATUS packet only when the state
-- changes (entered combat, pulled a boss, a boss died, stalled, looting, party
-- recovered, …), and likewise re-pushes the BOSS list whenever a boss's
-- alive/dead/skipped state or the committed target changes. So we no longer
-- poll for either — STATUS and BOSS arrive on their own the instant they move.
--
-- The one case the push path can't cover is browsing the boss list while DC is
-- OFF: with no clear running there's no server-side pusher, and the bot's
-- "dungeon bosses" value returns empty (cached ~5s) until it's fully zoned into
-- the dungeon. So keep a bounded retry that fires ONLY while the list is still
-- empty — it self-terminates the moment a real list arrives and never becomes a
-- steady poll. RedrawBossList preserves the scroll offset.
local bossEnsureElapsed = 0
local function OnUpdateHandler(self, elap)
    if not frame:IsVisible() then return end
    if #bosses > 0 then return end  -- populated: the server pushes updates from here

    bossEnsureElapsed = bossEnsureElapsed + elap
    if bossEnsureElapsed >= 2.0 then
        bossEnsureElapsed = 0
        local inInstance, instanceType = IsInInstance()
        if inInstance and instanceType == "party" then
            RequestBossList()
        end
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
        local detail = parts[8]

        if nextBossName == "None" then nextBossName = nil end
        if stallReason == "" then stallReason = nil end
        if detail == "" then detail = nil end

        UpdateStatusUI(enabled, nextBossName, state, stallReason, detail)
    elseif parts[1] == "BOSS_START" then
        -- Stage into pendingBosses; the live list is untouched until BOSS_END
        -- so a response that turns out empty (or never finalizes) can't blank
        -- a list that's already showing.
        pendingBosses = {}
    elseif parts[1] == "BOSS" then
        local entry = tonumber(parts[2])
        local index = tonumber(parts[3])
        local name = parts[4]
        local status = parts[5]
        local x = tonumber(parts[6])
        local y = tonumber(parts[7])
        local z = tonumber(parts[8])
        -- Optional trailing field: wing/region label on split maps (e.g.
        -- Maraudon "Orange"/"Purple"/"Pristine Waters"). Empty/absent on
        -- single-wing dungeons. Older servers omit it; nil is fine.
        local wing = parts[9]
        if wing == "" then wing = nil end

        table.insert(pendingBosses, {
            entry = entry,
            encounterIndex = index,
            name = name,
            status = status,
            x = x, y = y, z = z,
            wing = wing
        })
    elseif parts[1] == "BOSS_END" then
        if #pendingBosses > 0 then
            -- A real list arrived: commit it, sorted by encounter index.
            table.sort(pendingBosses, function(a, b)
                return a.encounterIndex < b.encounterIndex
            end)
            bosses = pendingBosses
            pendingBosses = {}
            RedrawBossList()
        else
            -- Empty response. Never downgrade a good list to empty — that's the
            -- transient-empty case the ensure-loop will retry past. Only redraw
            -- (to show the "Loading" placeholder) if we have nothing yet.
            if #bosses == 0 then
                RedrawBossList()
            end
        end
    elseif parts[1] == "CHAT" then
        -- Bot announcements routed through addon channel (silent)
        local chatMsg = parts[2] or ""
        DEFAULT_CHAT_FRAME:AddMessage("|cff3da6ff[DC] " .. chatMsg .. "|r")
    elseif parts[1] == "ERROR" then
        -- Error responses from the server hook. The only error our boss-list
        -- request or a command can provoke is "no tank bot found" — which means
        -- the tank bot left the group or logged out. If we still think DC is
        -- active (e.g. stuck showing Paused), reset to OFF to revert the readout;
        -- with the tank gone the server stops pushing, so the panel would
        -- otherwise sit on a stale state.
        local errorMsg = parts[2] or ""
        if isDCOn then
            UpdateStatusUI("0", nil, "off", nil)
            DEFAULT_CHAT_FRAME:AddMessage("|cffff3333[DC] Tank bot is no longer in the group \226\128\148 dungeon clear turned off.|r")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff3333[DC] " .. errorMsg .. "|r")
        end
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
                    RequestBossList()
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
    RequestBossList()
    -- Paint the loading placeholder now so the panel is never blank on open;
    -- it's replaced the moment a BOSS_END arrives (and the ensure-loop keeps
    -- re-requesting until then).
    bossEnsureElapsed = 0
    RedrawBossList()
end)

frame:SetScript("OnHide", function()
    DungeonClearDB.visible = false
end)

-- Interface -> AddOns options panel (informational front door)
-- A simple, read-only page registered under Game Menu -> Interface -> AddOns:
-- overview text, a command/control reference, and a button that opens the main
-- window exactly like typing /dc. No settings live here; all controls stay in
-- the floating window.
local optionsPanel = CreateFrame("Frame", "DungeonClearOptionsPanel", UIParent)
optionsPanel.name = "DungeonClear"

local optTitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
optTitle:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT", 16, -16)
optTitle:SetText("Dungeon Clear")
optTitle:SetTextColor(0.24, 0.60, 1.0) -- match the main window header

local optSubtitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
optSubtitle:SetPoint("TOPLEFT", optTitle, "BOTTOMLEFT", 0, -4)
optSubtitle:SetText("Autonomous dungeon-clearing companion for mod-dungeon-clear.")
optSubtitle:SetTextColor(0.6, 0.6, 0.6)

local optOverview = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
optOverview:SetPoint("TOPLEFT", optSubtitle, "BOTTOMLEFT", 0, -14)
optOverview:SetWidth(560)
optOverview:SetJustifyH("LEFT")
optOverview:SetText(
    "A mod-playerbots tank bot walks your party from boss to boss, clearing trash and " ..
    "pathing the route on its own. This addon is the front-end for that mode: it gives you " ..
    "one-click On / Off / Skip / Pause-Resume control, a live status readout (what the bot " ..
    "is doing and which boss it's heading for), and a boss list with a per-boss \"Go\" button. " ..
    "You must be in a party that contains a tank bot \226\128\148 the addon only relays commands.")

local optCmdHeader = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
optCmdHeader:SetPoint("TOPLEFT", optOverview, "BOTTOMLEFT", 0, -18)
optCmdHeader:SetText("Commands & Controls")
optCmdHeader:SetTextColor(0.24, 0.60, 1.0)

local optCmdList = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
optCmdList:SetPoint("TOPLEFT", optCmdHeader, "BOTTOMLEFT", 0, -8)
optCmdList:SetWidth(560)
optCmdList:SetJustifyH("LEFT")
optCmdList:SetText(
    "|cffffd100/dc|r  \226\128\148  Toggle the main window (always reopens in full mode).\n" ..
    "|cffffd100On / Off|r  \226\128\148  Start or stop the autonomous clear.\n" ..
    "|cffffd100Skip|r  \226\128\148  Skip the current boss / objective and move to the next.\n" ..
    "|cffffd100Pause / Resume|r  \226\128\148  Hold the tank in place without ending the clear, then resume.\n" ..
    "|cffffd100Go|r (per boss row)  \226\128\148  Send the tank straight to that boss (turns the clear on first).\n" ..
    "|cffffd100Tiny|r  \226\128\148  Collapse the window to a single-line, movable readout.")

local openBtn = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
openBtn:SetSize(160, 24)
openBtn:SetPoint("TOPLEFT", optCmdList, "BOTTOMLEFT", 0, -20)
openBtn:SetText("Open DungeonClear")
openBtn:SetScript("OnClick", function()
    -- Mirror the /dc (no-arg) open branch: always reopen in full (non-tiny) mode.
    DungeonClearDB.tinyMode = false
    UpdateLayout()
    frame:Show()
end)

InterfaceOptions_AddCategory(optionsPanel)

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
DEFAULT_CHAT_FRAME:AddMessage("|cff3da6ffDungeonClear Addon loaded.|r Type /dc to toggle window, or see Interface > AddOns > DungeonClear.")
