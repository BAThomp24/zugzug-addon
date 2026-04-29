----------------------------------------------------------------------
-- ZugZug — Smart Suggest
-- Detects raid bosses and M+ dungeons, suggests the best build.
----------------------------------------------------------------------

local ZZ = _G.ZugZug

-- Forward declaration so callers above the definition can reference it.
local showSuggestion

----------------------------------------------------------------------
-- Difficulty mapping: WoW difficultyID → ZugZug difficulty key
----------------------------------------------------------------------

local RAID_DIFFICULTY_MAP = {
  [14] = "heroic",  -- Normal → use heroic data
  [15] = "heroic",
  [16] = "mythic",
  [17] = "heroic",  -- LFR → use heroic data
}

-- Map keystone level to our bucket
local function keystoneToBucket(level)
  if level >= 20 then return "20+" end
  if level >= 18 then return "18+" end
  if level >= 15 then return "15+" end
  return "all"
end

----------------------------------------------------------------------
-- Build matching — find the best build for a given boss/dungeon
----------------------------------------------------------------------

--- Normalize names for fuzzy matching (punctuation→space, collapse, lowercase).
--- Uses function-call syntax to avoid WoW taint issues.
local function normName(name)
  if not name then return "" end
  local s = string.lower(name)
  s = string.gsub(s, "[^%w%s]", " ")
  s = string.gsub(s, "%s+", " ")
  s = strtrim(s)
  return s
end

--- Match a target name against a data name.
--- Tries exact match first, then normalized fuzzy match (pcall-safe).
local function namesMatch(targetName, dataName)
  if targetName == dataName then return true end
  local ok, normTarget = pcall(normName, targetName)
  if ok then
    return normName(dataName) == normTarget
  end
  return false
end

--- Check if we should filter to current spec only for a given content type.
local function specOnly(contentType)
  local filter = ZugZugDB.suggestSpecFilter or "all"
  if filter == "all" then return true end
  if filter == "none" then return false end
  return filter == contentType
end

--- Find the best build for a boss name in raid data.
local function findBestBuildForBoss(builds, bossName)
  if not builds or #builds == 0 then return nil end

  local specName = ZZ.specName
  local currentOnly = specOnly("raid")

  -- Pass 1: same spec, lists this boss as "best for"
  for _, build in ipairs(builds) do
    if build.spec == specName and build.bosses then
      for _, b in ipairs(build.bosses) do
        if namesMatch(bossName, b) then return build end
      end
    end
  end

  -- Pass 2: any spec, lists this boss (skip if spec-only)
  if not currentOnly then
    for _, build in ipairs(builds) do
      if build.bosses then
        for _, b in ipairs(build.bosses) do
          if namesMatch(bossName, b) then return build end
        end
      end
    end
  end

  -- Pass 3: highest popularity same-spec build
  local best = nil
  for _, build in ipairs(builds) do
    if build.spec == specName then
      if not best or build.popularity > best.popularity then
        best = build
      end
    end
  end

  return best
end

--- Find the best build for a dungeon name in M+ data.
local function findBestBuildForDungeon(builds, dungeonName)
  if not builds or #builds == 0 then return nil end

  local specName = ZZ.specName
  local currentOnly = specOnly("dungeon")

  -- Pass 1: same spec, lists this dungeon
  for _, build in ipairs(builds) do
    if build.spec == specName and build.dungeons then
      for _, d in ipairs(build.dungeons) do
        if namesMatch(dungeonName, d) then return build end
      end
    end
  end

  -- Pass 2: any spec, lists this dungeon (skip if spec-only)
  if not currentOnly then
    for _, build in ipairs(builds) do
      if build.dungeons then
        for _, d in ipairs(build.dungeons) do
          if namesMatch(dungeonName, d) then return build end
        end
      end
    end
  end

  -- Pass 3: highest popularity same-spec build
  local best = nil
  for _, build in ipairs(builds) do
    if build.spec == specName then
      if not best or build.popularity > best.popularity then
        best = build
      end
    end
  end

  return best
end

----------------------------------------------------------------------
-- Raid boss order tracking via Encounter Journal
----------------------------------------------------------------------

local raidBossOrder = {}    -- { {encounterID=N, name="Boss"}, ... }
local killedEncounters = {} -- { [encounterID] = true }
local currentRaidDiff = nil -- resolved difficulty key for current instance

--- Build the boss order for the current raid from the Encounter Journal.
local function buildBossOrder()
  raidBossOrder = {}
  killedEncounters = {}

  local ok, err = pcall(function()
    local journalInstanceID = EJ_GetCurrentInstance()
    if not journalInstanceID or journalInstanceID == 0 then return end

    EJ_SelectInstance(journalInstanceID)
    for i = 1, 20 do
      local name, _, journalEncounterID, _, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(i)
      if not name then break end
      -- dungeonEncounterID matches BOSS_KILL's encounterID
      local id = dungeonEncounterID or journalEncounterID
      table.insert(raidBossOrder, { encounterID = id, name = name })
    end
  end)

  if not ok then
    print("|cff00ccffZugZug:|r Failed to read encounter journal: " .. tostring(err))
  end
end

--- Get the name of the next unkilled boss.
local function getNextBossName()
  for _, boss in ipairs(raidBossOrder) do
    if not killedEncounters[boss.encounterID] then
      return boss.name
    end
  end
  return nil  -- all bosses killed or no boss order
end

--- Get builds for the current raid difficulty.
local function getRaidBuilds()
  if not ZZ.data or not ZZ.classToken or not ZZ.role then return nil, nil end

  local diff = currentRaidDiff
  if not diff then return nil, nil end

  -- Resolve suggest difficulty preference
  local suggestDiff = ZugZugDB.suggestRaidDiff or "auto"
  if suggestDiff ~= "auto" then
    diff = suggestDiff
  end

  local classEntry = ZZ.data.classes[ZZ.classToken]
  if not classEntry then return nil, nil end
  local roleData = classEntry[ZZ.role]
  if not roleData or not roleData.raid then return nil, nil end

  return roleData.raid[diff], diff
end

--- Suggest a raid build for a specific boss name.
local function suggestForBoss(bossName)
  local builds, diff = getRaidBuilds()
  if not builds then return end

  local best = findBestBuildForBoss(builds, bossName)
  if best then
    local diffLabel = diff == "mythic" and "Mythic" or "Heroic"
    showSuggestion("Best for " .. bossName .. " (" .. diffLabel .. ")", best, "raid")
  end
end

--- Suggest the most popular raid build for current spec (fallback).
local function suggestGenericRaid()
  local builds, diff = getRaidBuilds()
  if not builds then return end

  local specName = ZZ.specName
  local best = nil
  for _, build in ipairs(builds) do
    if build.spec == specName then
      if not best or build.popularity > best.popularity then
        best = build
      end
    end
  end

  if best then
    local diffLabel = diff == "mythic" and "Mythic" or "Heroic"
    showSuggestion("Best " .. diffLabel .. " raid build", best, "raid")
  end
end

----------------------------------------------------------------------
-- Suggestion popup UI
----------------------------------------------------------------------

local suggestFrame = nil
local SUGGEST_WIDTH = 320
local SUGGEST_HEIGHT = 72

local function createSuggestFrame()
  if suggestFrame then return suggestFrame end

  local f = CreateFrame("Frame", "ZugZugSuggestFrame", UIParent, "BackdropTemplate")
  f:SetSize(SUGGEST_WIDTH, SUGGEST_HEIGHT)
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  f:SetBackdropColor(0.08, 0.08, 0.1, 0.97)
  f:SetBackdropBorderColor(0.56, 0.75, 0.25, 0.8)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  -- Header
  local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
  header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -8)
  header:SetJustifyH("LEFT")
  header:SetWordWrap(false)
  f.header = header

  -- Build info line
  local buildText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  buildText:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -24)
  buildText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -24)
  buildText:SetJustifyH("LEFT")
  buildText:SetWordWrap(false)
  f.buildText = buildText

  -- Apply button
  local applyBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
  applyBtn:SetSize(80, 22)
  applyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
  applyBtn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  applyBtn:SetBackdropColor(0.56, 0.75, 0.25, 0.2)
  applyBtn:SetBackdropBorderColor(0.56, 0.75, 0.25, 0.6)
  local applyText = applyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  applyText:SetPoint("CENTER")
  applyText:SetText("|cff8fbf3fApply|r")
  applyBtn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(0.56, 0.75, 0.25, 0.35)
  end)
  applyBtn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0.56, 0.75, 0.25, 0.2)
  end)
  applyBtn:SetScript("OnClick", function()
    if f.currentBuild and f.currentBuild.importString then
      ZZ:ApplyBuild(f.currentBuild.importString, f.currentBuild.label)
    end
    f:Hide()
  end)
  f.applyBtn = applyBtn

  -- Dismiss button
  local dismissBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
  dismissBtn:SetSize(60, 22)
  dismissBtn:SetPoint("LEFT", applyBtn, "RIGHT", 6, 0)
  dismissBtn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  dismissBtn:SetBackdropColor(0.15, 0.15, 0.18, 1)
  dismissBtn:SetBackdropBorderColor(0.22, 0.22, 0.26, 1)
  local dismissText = dismissBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  dismissText:SetPoint("CENTER")
  dismissText:SetText("|cff888888Dismiss|r")
  dismissBtn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(0.2, 0.2, 0.24, 1)
  end)
  dismissBtn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0.15, 0.15, 0.18, 1)
  end)
  dismissBtn:SetScript("OnClick", function() f:Hide() end)
  f.dismissBtn = dismissBtn

  -- Close X
  local closeBtn = CreateFrame("Button", nil, f)
  closeBtn:SetSize(18, 18)
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  closeBtn:SetNormalFontObject(GameFontNormalSmall)
  closeBtn:SetText("X")
  closeBtn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
  closeBtn:SetScript("OnClick", function() f:Hide() end)
  closeBtn:SetScript("OnEnter", function(self) self:GetFontString():SetTextColor(1, 0.3, 0.3) end)
  closeBtn:SetScript("OnLeave", function(self) self:GetFontString():SetTextColor(0.5, 0.5, 0.5) end)

  -- Auto-hide after configured seconds
  f:SetScript("OnShow", function(self)
    if self.hideTimer then self.hideTimer:Cancel() end
    local fadeTime = ZugZugDB.suggestFadeTimer or 15
    if fadeTime > 0 then
      self.hideTimer = C_Timer.NewTimer(fadeTime, function() self:Hide() end)
    end
  end)
  f:SetScript("OnHide", function(self)
    if self.hideTimer then self.hideTimer:Cancel() end
  end)

  f:Hide()
  suggestFrame = f
  return f
end

--- Detect the player's active hero talent tree name via C_ClassTalents.GetActiveHeroTalentSpec (11.0+).
--- Returns the hero name string, or nil + reason ("none" = no hero selected, "unavailable" = API failed).
local function getActiveHeroName()
  if not (C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec) then
    return nil, "unavailable"
  end
  local ok, subTreeID = pcall(C_ClassTalents.GetActiveHeroTalentSpec)
  if not ok then return nil, "unavailable" end
  if not subTreeID then return nil, "none" end
  local configID = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
  if not configID then return nil, "unavailable" end
  local ok2, info = pcall(C_Traits.GetSubTreeInfo, configID, subTreeID)
  if not ok2 or not info then return nil, "unavailable" end
  return info.name
end

--- Returns true if the player's current spec+hero already matches the build.
local function isAlreadyOnBuild(build)
  if not build then return false end
  if build.spec ~= ZZ.specName then return false end
  if not build.hero or build.hero == "" then return true end
  local heroName, reason = getActiveHeroName()
  if heroName then
    return heroName == build.hero
  end
  -- reason == "none": player has no hero selected; show suggestion
  -- reason == "unavailable": API failed; show suggestion (better to over-suggest)
  return false
end

--- Show a build suggestion popup.
showSuggestion = function(contentLabel, build, contentType)
  if not build or not build.importString or build.importString == "" then return end
  if InCombatLockdown() then return end
  if not ZugZugDB.suggestEnabled then return end
  if isAlreadyOnBuild(build) then return end

  local f = createSuggestFrame()
  f.currentBuild = build

  local typeColor = contentType == "raid" and "|cffFFBF33" or "|cff66DD66"
  f.header:SetText("|cff8fbf3fZugZug|r " .. typeColor .. contentLabel .. "|r")

  local specHero = build.spec
  if build.hero and build.hero ~= "" then
    specHero = specHero .. " · " .. build.hero
  end
  f.buildText:SetText("|cffffffff" .. build.label .. "|r  |cff888888" .. specHero .. "  " .. build.popularity .. "%|r")

  f:Show()
end

----------------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------------

local suggestBossCooldown = false
local lastSuggestDungeon = nil

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    if ZZ.data then
      eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
      eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
      eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
      eventFrame:RegisterEvent("BOSS_KILL")
    end
    eventFrame:UnregisterEvent("PLAYER_LOGIN")
    return
  end

  -- ── Raid: on entering a raid, build boss order and suggest first boss ──
  if event == "PLAYER_ENTERING_WORLD" then
    local ok, err = pcall(function()
      local _, instanceType, difficultyID = GetInstanceInfo()
      local diff = RAID_DIFFICULTY_MAP[difficultyID]

      if instanceType == "raid" and diff then
        currentRaidDiff = diff
        suggestBossCooldown = false
        killedEncounters = {}
        -- Build boss order from Encounter Journal
        buildBossOrder()

        if #raidBossOrder > 0 then
          local firstBoss = raidBossOrder[1].name
          suggestForBoss(firstBoss)
          suggestBossCooldown = true
          C_Timer.After(30, function() suggestBossCooldown = false end)
        end
      else
        -- Left raid — reset state
        raidBossOrder = {}
        killedEncounters = {}
        currentRaidDiff = nil
        suggestBossCooldown = false
      end
    end)
    if not ok then
      print("|cff00ccffZugZug:|r ENTERING_WORLD error: " .. tostring(err))
    end
    -- Fall through to dungeon detection below
  end

  -- ── Raid: suggest when targeting a boss-level mob ──
  if event == "PLAYER_TARGET_CHANGED" then
    local ok, err = pcall(function()
      if not ZZ.data or not ZZ.classToken or not ZZ.role then return end
      if InCombatLockdown() then return end
      if not UnitExists("target") then return end
      if suggestBossCooldown then return end

      -- Must be in a mapped raid difficulty
      local difficultyID = select(3, GetInstanceInfo())
      local diff = RAID_DIFFICULTY_MAP[difficultyID]
      if not diff then return end

      -- Must be a boss-level mob (skull = -1)
      if UnitLevel("target") ~= -1 then return end

      -- Suggest based on next unkilled boss if we have boss order
      local nextBoss = getNextBossName()
      if nextBoss then
        suggestForBoss(nextBoss)
      else
        suggestGenericRaid()
      end

      suggestBossCooldown = true
      C_Timer.After(30, function() suggestBossCooldown = false end)
    end)
    if not ok then
      print("|cff00ccffZugZug:|r TARGET error: " .. tostring(err))
    end
    return
  end

  -- ── Raid: after a boss kill, suggest the next boss ──
  if event == "BOSS_KILL" then
    local encounterID, encounterName = ...
    local ok, err = pcall(function()
      if encounterID then
        killedEncounters[encounterID] = true
      end
      suggestBossCooldown = false

      -- Suggest build for the next boss
      local nextBoss = getNextBossName()
      if nextBoss then
        -- Small delay so it doesn't flash during loot
        C_Timer.After(3, function()
          suggestForBoss(nextBoss)
          suggestBossCooldown = true
          C_Timer.After(30, function() suggestBossCooldown = false end)
        end)
      end
    end)
    if not ok then
      print("|cff00ccffZugZug:|r BOSS_KILL error: " .. tostring(err))
    end
    return
  end

  -- ── M+/Dungeon: suggest when zoning into a dungeon ──
  if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
    local ok, err = pcall(function()
      if not ZZ.data or not ZZ.classToken then return end

      local _, instanceType, difficultyID = GetInstanceInfo()

      local mapID = C_ChallengeMode.GetActiveChallengeMapID()
      local dungeonName, level

      if mapID then
        dungeonName = C_ChallengeMode.GetMapUIInfo(mapID)
        level = select(1, C_ChallengeMode.GetActiveKeystoneInfo()) or 0
      elseif instanceType == "party" then
        dungeonName = GetInstanceInfo()
        level = 0
      else
        return
      end

      if not dungeonName then return end
      if lastSuggestDungeon == dungeonName then return end
      lastSuggestDungeon = dungeonName

      local bucket = level > 0 and keystoneToBucket(level) or (ZugZugDB.suggestMpBucket or "all")

      local classEntry = ZZ.data.classes[ZZ.classToken]
      if not classEntry then return end
      local roleData = classEntry[ZZ.role]
      if not roleData or not roleData.mythicPlus then return end
      local builds = roleData.mythicPlus[bucket]

      local best = findBestBuildForDungeon(builds, dungeonName)
      if best then
        local label = level > 0 and ("Best for " .. dungeonName .. " +" .. level) or ("Best for " .. dungeonName)
        showSuggestion(label, best, "mp")
      end
    end)
    if not ok then
      print("|cff00ccffZugZug:|r ZONE error: " .. tostring(err))
    end
    return
  end
end)

----------------------------------------------------------------------
-- Reset debounce on zone changes and spec switches
----------------------------------------------------------------------

local resetFrame = CreateFrame("Frame")
resetFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
resetFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
resetFrame:SetScript("OnEvent", function(_, event)
  if event == "CHALLENGE_MODE_COMPLETED" then
    lastSuggestDungeon = nil
  elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
    suggestBossCooldown = false
  end
end)
