----------------------------------------------------------------------
-- ZugZug — M+ Time Auto-Response
-- When enabled, replies to whispers asking for "time" with the time
-- remaining on the active Mythic+ key (or elapsed dungeon time as a
-- fallback). Per-sender cooldown prevents spam.
----------------------------------------------------------------------

local ZZ = _G.ZugZug

local REPLY_COOLDOWN = 30          -- seconds between replies to the same player
local lastReplyTo = {}             -- author (lowercased) -> GetTime() of last reply
local instanceEnterTime = nil      -- GetTime() when we entered the current party instance
local keyStartTime = nil           -- GetTime() the active key started (tracked, survives reload)

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function formatTime(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

--- Read elapsed seconds from the live world challenge-mode timer.
--- Doesn't rely on the LE_ type constant (removed/renamed in some clients) —
--- just returns the first positive elapsed value among active world timers.
local function readWorldTimerElapsed()
  if not (GetWorldElapsedTimers and GetWorldElapsedTime) then return nil end
  local timers = { GetWorldElapsedTimers() }
  for _, timerID in ipairs(timers) do
    -- Signature is (type, elapsedTime); guard against either ordering by
    -- scanning both returns for a plausible "seconds elapsed" value.
    local a, b = GetWorldElapsedTime(timerID)
    local elapsed = math.max(tonumber(a) or 0, tonumber(b) or 0)
    if elapsed > 0 then return elapsed end
  end
  return nil
end

--- Elapsed seconds on the active key. Prefers the tracked start time; falls
--- back to the world timer (and back-computes keyStartTime from it).
local function getChallengeElapsed()
  if keyStartTime then
    return GetTime() - keyStartTime
  end
  local worldElapsed = readWorldTimerElapsed()
  if worldElapsed then
    keyStartTime = GetTime() - worldElapsed
    return worldElapsed
  end
  return nil
end

--- Build the auto-reply text, or nil if we have nothing useful to say.
function ZZ:BuildMPTimeResponse()
  -- Active Mythic+ key → time remaining (accounting for death penalty)
  local mapID = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
    and C_ChallengeMode.GetActiveChallengeMapID()
  if mapID then
    local name, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    local elapsed = getChallengeElapsed()
    if timeLimit and timeLimit > 0 and elapsed then
      local _, timeLost = C_ChallengeMode.GetDeathCount()
      timeLost = timeLost or 0
      local remaining = timeLimit - elapsed - timeLost
      local level = C_ChallengeMode.GetActiveKeystoneInfo() or 0
      local keyLabel = (level > 0) and ("+" .. level .. " " .. (name or "key")) or (name or "key")
      if remaining >= 0 then
        return string.format("%s remaining on %s (ZugZug)", formatTime(remaining), keyLabel)
      else
        return string.format("%s OVER time on %s — key depleted (ZugZug)", formatTime(-remaining), keyLabel)
      end
    end
  end

  -- Fallback: elapsed time since entering the current dungeon
  if instanceEnterTime then
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "party" then
      return string.format("%s in the dungeon so far (ZugZug)", formatTime(GetTime() - instanceEnterTime))
    end
  end

  return nil
end

--- Does this whisper look like a request for the time?
local function isTimeRequest(msg)
  if not msg then return false end
  local m = msg:lower()
  m = m:gsub("[%p]", " ")    -- strip punctuation
  m = m:gsub("%s+", " ")
  m = strtrim(m)
  if m == "" then return false end

  local exact = {
    ["time"] = true, ["timer"] = true, ["time left"] = true,
    ["time remaining"] = true, ["how much time"] = true,
    ["how much time left"] = true, ["time check"] = true,
    ["whats the time"] = true, ["hows the timer"] = true,
    ["time pls"] = true, ["time plz"] = true,
  }
  if exact[m] then return true end

  -- Short message containing "time" or "timer" as a standalone word.
  if #m <= 24 and (m:find("%f[%a]time%f[%A]") or m:find("%f[%a]timer%f[%A]")) then
    return true
  end

  return false
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

-- Reply logic: match the whisper, respect cooldown, send via replyFn.
local function handleTimeWhisper(senderKey, msg, replyFn)
  if not ZugZugDB or not ZugZugDB.mpAutoResponse then return end
  if not msg or not senderKey then return end
  if not isTimeRequest(msg) then return end

  local key = tostring(senderKey):lower()
  local now = GetTime()
  if lastReplyTo[key] and (now - lastReplyTo[key]) < REPLY_COOLDOWN then return end

  local response = ZZ:BuildMPTimeResponse()
  if not response then return end

  lastReplyTo[key] = now
  replyFn(response)
end

-- State tracking frame (instance entry + key start time)
local stateFrame = CreateFrame("Frame")
stateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
stateFrame:RegisterEvent("CHALLENGE_MODE_START")
stateFrame:RegisterEvent("CHALLENGE_MODE_RESET")
stateFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
stateFrame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_ENTERING_WORLD" then
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "party" then
      instanceEnterTime = instanceEnterTime or GetTime()
      if not keyStartTime then getChallengeElapsed() end
    else
      instanceEnterTime = nil
      keyStartTime = nil
    end
  elseif event == "CHALLENGE_MODE_START" then
    keyStartTime = GetTime()
    instanceEnterTime = GetTime()
    wipe(lastReplyTo)
  elseif event == "CHALLENGE_MODE_RESET" or event == "CHALLENGE_MODE_COMPLETED" then
    keyStartTime = nil
  end
end)

-- Chat frame: receives in-game whispers and fires the auto-reply.
-- NOTE: Battle.net whispers (CHAT_MSG_BN_WHISPER) deliver their text as a
-- "secret" value that addons are forbidden from reading, so they can't be
-- inspected or auto-replied to — only standard in-game /w whispers work.
local chatFrame = CreateFrame("Frame")
chatFrame:RegisterEvent("CHAT_MSG_WHISPER")
chatFrame:SetScript("OnEvent", function(_, _, msg, author)
  handleTimeWhisper(author, msg, function(resp)
    SendChatMessage(resp, "WHISPER", nil, author)
  end)
end)
