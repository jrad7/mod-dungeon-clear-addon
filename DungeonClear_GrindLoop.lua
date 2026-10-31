-- WoW 3.3.5a. Load after DungeonClear.lua. No server changes.
-- SelfBot handles accepting RDF proposals; this only starts DC and requeues.

local enabled, started, requested = false, false, false
local finalIndex, finalDead, gotBosses = nil, true, false
local finished = false
local REQUEUE_DELAY = 60
local requeueAt
local f = CreateFrame("Frame")

local function Dungeon()
    local inside, kind = IsInInstance()
    return inside and kind == "party"
end

local function Mode()
    return GetLFGMode and GetLFGMode() or nil
end

local function Busy()
    local mode = Mode()
    return mode == "queued" or mode == "rolecheck" or mode == "proposal"
        or mode == "accepted" or mode == "suspended"
end

local function Say(s)
    DEFAULT_CHAT_FRAME:AddMessage("|cff3da6ff[DC Grind]|r " .. s)
end

local function Join()
    if requeueAt and GetTime() < requeueAt then return end
    if not enabled or requested or Busy() then return end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return end
    if UnitHasLFGDeserter and UnitHasLFGDeserter("player") then return end
    if not LFDQueueFrame or not LFDQueueFrame.type
        or type(LFDQueueFrame_Join) ~= "function" then
        Say("Select a dungeon in RDF first.")
        return
    end
    -- Uses the random dungeon or specific-dungeon checkboxes already chosen.
    requested = true
    local ok, err = pcall(LFDQueueFrame_Join)
    if not ok then
        Say("RDF queue failed: " .. tostring(err))
    end
end

local function StartClear()
    if not enabled or started or not Dungeon() then return end
    started = true
    -- The stock addon sends 'CMD\ton' and reuses existing DC settings.
    if SlashCmdList and SlashCmdList.DUNGEONCLEAR then
        SlashCmdList.DUNGEONCLEAR("on")
    end
end

local function EnterDungeon()
    f:SetScript("OnUpdate", nil)
    requeueAt = nil
    started, requested, finished = false, false, false
    finalIndex, finalDead, gotBosses = nil, true, false
    StartClear()
end

local function Finish()
    if not enabled or not Dungeon() or finished then return end
    finished = true
    requeueAt = GetTime() + REQUEUE_DELAY
    local elapsedTotal = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal < 1 then return end
        elapsedTotal = 0
        if GetTime() >= requeueAt then
            self:SetScript("OnUpdate", nil)
            requeueAt = nil
            Join() -- Requeue after 60 seconds without leaving the instance.
        end
    end)
end

local parent = DungeonClearFrame
local checkbox
local function Toggle(on)
    enabled = on and true or false
    if checkbox then checkbox:SetChecked(enabled) end
    if not enabled then
        f:SetScript("OnUpdate", nil)
        requeueAt = nil
        Say("OFF")
        return
    end
    Say("ON")
    requested = false
    if Dungeon() then
        if finished then
            Join()
        elseif Mode() == "finished" then
            Finish()
        else
            started = false
            StartClear()
        end
    else
        Join()
    end
end

if parent then
    checkbox = CreateFrame("CheckButton", "DungeonClearGrindLoopToggle", parent, "UICheckButtonTemplate")
    checkbox:SetSize(22, 22)
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -4)
    local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", checkbox, "RIGHT", 0, 0)
    label:SetText("Grind")
    checkbox:SetScript("OnClick", function(self) Toggle(self:GetChecked()) end)
    local function Layout()
        if DungeonClearDB and DungeonClearDB.tinyMode then checkbox:Hide()
        else checkbox:Show() end
    end
    parent:HookScript("OnSizeChanged", Layout)
    Layout()
end

f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("LFG_COMPLETION_REWARD")
f:RegisterEvent("LFG_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(self, event, arg1, arg2)
    if not enabled then return end
    if event == "PLAYER_ENTERING_WORLD" then
        if Dungeon() then EnterDungeon() end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if Dungeon() then StartClear() end
    elseif event == "LFG_COMPLETION_REWARD" then
        Finish() -- Random RDF reward is an authoritative completion signal.
    elseif event == "LFG_UPDATE" then
        if Dungeon() then
            if Mode() == "finished" then Finish() end
            if finished then Join() end -- retry only if not already attempted
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if finished then Join() end
    elseif event == "CHAT_MSG_ADDON" and Dungeon() and arg1 == "DC" and not finished then
        -- Reuse the existing addon’s pushed boss-list packets. The last boss
        -- in clear order being dead is a fallback for specific-dungeon queues.
        local kind = arg2:match("^([^\t]+)")
        if kind == "BOSS_START" then
            finalIndex, finalDead, gotBosses = nil, true, false
        elseif kind == "BOSS" then
            local index, name, state = arg2:match("^BOSS\t[^\t]*\t([^\t]*)\t([^\t]*)\t([^\t]*)")
            index = tonumber(index)
            if index and name and name:sub(1, 6) ~= "Event:" then
                if not finalIndex or index > finalIndex then
                    finalIndex, finalDead = index, (state == "dead")
                elseif index == finalIndex then
                    finalDead = finalDead and (state == "dead")
                end
                gotBosses = true
            end
        elseif kind == "BOSS_END" then
            if gotBosses and finalDead then Finish()
            elseif not started then StartClear() end
        elseif kind == "ERROR" then
            -- Tank may not yet have entered when the initial DC ON was sent.
            started = false
        end
    end
end)

SLASH_DUNGEONCLEARGRIND1 = "/dcgrind"
SlashCmdList.DUNGEONCLEARGRIND = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "on" then Toggle(true)
    elseif msg == "off" then Toggle(false)
    else Say("Use /dcgrind on or /dcgrind off") end
end
