----------------------------------------------------------------------
-- ZugZug — Smart Suggest
-- Detects raid bosses and M+ dungeons, suggests the best build.
----------------------------------------------------------------------

local ZZ = _G.ZugZug

----------------------------------------------------------------------
-- Difficulty mapping: WoW difficultyID → ZugZug difficulty key
----------------------------------------------------------------------

local RAID_DIFFICULTY_MAP = {
  [15] = "heroic",
  [16] = "mythic",
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

--- Normalize names for fuzzy matching (strip punctuation, lowercase).
local function normName(name)
  if not name then return "" end
  return name:lower():gsub("[^%w%s]", ""):gsub("%s+", " "):trim()
end

--- String.trim polyfill
if not string.trim then
  function string:trim()
    return self:match("^%s*(.-)%s*$")
  end
end

--- Find the best build for a boss name in raid data.
--- Returns the build table or nil.
local function findBestBuildForBoss(builds, bossName)
  if not builds or #builds == 0 then return nil end

  local normBoss = normName(bossName)
  local specName = ZZ.specName

  -- Pass 1: same spec, lists this boss as "best for"
  for _, build in ipairs(builds) do
    if build.spec == specName and build.bosses then
      for _, b in ipairs(build.bosses) do
        if normName(b) == normBoss then return build end
      end
    end
  end

  -- Pass 2: any spec, lists this boss as "best for"
  for _, build in ipairs(builds) do
    if build.bosses then
      for _, b in ipairs(build.bosses) do
        if normName(b) == normBoss then return build end
      end
    end
  end

  -- Pass 3: highest popularity same-spec build (no boss-specific data)
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

  local normDungeon = normName(dungeonName)
  local specName = ZZ.specName

  -- Pass 1: same spec, lists this dungeon
  for _, build in ipairs(builds) do
    if build.spec == specName and build.dungeons then
      for _, d in ipairs(build.dungeons) do
        if normName(d) == normDungeon then return build end
      end
    end
  end

  -- Pass 2: any spec, lists this dungeon
  for _, build in ipairs(builds) do
    if build.dungeons then
      for _, d in ipairs(build.dungeons) do
        if normName(d) == normDungeon then return build end
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

  -- Header: "ZugZug: Best for [content]"
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

  -- Auto-hide after 15 seconds
  f:SetScript("OnShow", function(self)
    if self.hideTimer then self.hideTimer:Cancel() end
    self.hideTimer = C_Timer.NewTimer(15, function() self:Hide() end)
  end)
  f:SetScript("OnHide", function(self)
    if self.hideTimer then self.hideTimer:Cancel() end
  end)

  f:Hide()
  suggestFrame = f
  return f
end

--- Show a build suggestion popup.
local function showSuggestion(contentLabel, build, contentType)
  if not build or not build.importString or build.importString == "" then return end
  -- Don't suggest in combat
  if InCombatLockdown() then return end
  -- Don't suggest if disabled
  if ZugZugDB.suggestDisabled then return end

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
-- Boss name index — built once from Data.lua for fast target lookups
----------------------------------------------------------------------

local bossIndex = {}  -- normName → raw boss name (for display)

local function buildBossIndex()
  if not ZZ.data or not ZZ.data.classes or not ZZ.classToken then return end
  local classEntry = ZZ.data.classes[ZZ.classToken]
  if not classEntry then return end
  local roleData = classEntry[ZZ.role]
  if not roleData or not roleData.raid then return end

  for _, diff in ipairs({"heroic", "mythic"}) do
    local builds = roleData.raid[diff]
    if builds then
      for _, build in ipairs(builds) do
        if build.bosses then
          for _, name in ipairs(build.bosses) do
            bossIndex[normName(name)] = name
          end
        end
      end
    end
  end
end

----------------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------------

local lastSuggestBoss = nil     -- debounce: last suggested boss name
local lastSuggestDungeon = nil  -- debounce: last suggested dungeon name

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    if ZZ.data then
      buildBossIndex()
      eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
      eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
      eventFrame:RegisterEvent("BOSS_KILL")
    end
    eventFrame:UnregisterEvent("PLAYER_LOGIN")
    return
  end

  -- ── Raid: suggest when targeting a boss ──
  if event == "PLAYER_TARGET_CHANGED" then
    if not ZZ.data or not ZZ.classToken then return end
    if InCombatLockdown() then return end

    local targetName = UnitName("target")
    if not targetName then return end
    -- Only care about enemies (not friendly NPCs / players)
    if not UnitCanAttack("player", "target") then return end

    -- Check if the target is a known raid boss
    local norm = normName(targetName)
    local bossName = bossIndex[norm]
    if not bossName then return end

    -- Debounce: don't re-suggest for the same boss
    if lastSuggestBoss == bossName then return end
    lastSuggestBoss = bossName

    -- Determine raid difficulty from the current instance
    local _, _, difficultyID = GetInstanceInfo()
    local diff = RAID_DIFFICULTY_MAP[difficultyID]
    if not diff then
      -- Fallback to saved preference if we can't detect
      diff = ZugZugDB.raidDifficulty or "mythic"
    end

    local classEntry = ZZ.data.classes[ZZ.classToken]
    if not classEntry then return end
    local roleData = classEntry[ZZ.role]
    if not roleData or not roleData.raid then return end
    local builds = roleData.raid[diff]

    local best = findBestBuildForBoss(builds, bossName)
    if best then
      showSuggestion("Best for " .. bossName, best, "raid")
    end
    return
  end

  -- ── Raid: suggest next boss after a kill ──
  if event == "BOSS_KILL" then
    -- Reset so re-targeting the next boss will trigger a new suggestion
    lastSuggestBoss = nil
    return
  end

  -- ── M+: suggest when zoning into a dungeon ──
  if event == "ZONE_CHANGED_NEW_AREA" then
    if not ZZ.data or not ZZ.classToken then return end

    -- Check if we're in a challenge mode dungeon
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if not mapID then return end

    local dungeonName = C_ChallengeMode.GetMapUIInfo(mapID)
    if not dungeonName then return end

    -- Debounce
    if lastSuggestDungeon == dungeonName then return end
    lastSuggestDungeon = dungeonName

    -- Get keystone level for bucket selection
    local level = select(1, C_ChallengeMode.GetActiveKeystoneInfo()) or 0
    local bucket = keystoneToBucket(level)

    local classEntry = ZZ.data.classes[ZZ.classToken]
    if not classEntry then return end
    local roleData = classEntry[ZZ.role]
    if not roleData or not roleData.mythicPlus then return end
    local builds = roleData.mythicPlus[bucket]

    local best = findBestBuildForDungeon(builds, dungeonName)
    if best then
      showSuggestion("Best for " .. dungeonName .. " +" .. level, best, "mp")
    end
    return
  end
end)

----------------------------------------------------------------------
-- Reset debounce on zone changes and spec switches
----------------------------------------------------------------------

local resetFrame = CreateFrame("Frame")
resetFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
resetFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
resetFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
resetFrame:SetScript("OnEvent", function(_, event)
  if event == "CHALLENGE_MODE_COMPLETED" then
    lastSuggestDungeon = nil
  elseif event == "PLAYER_ENTERING_WORLD" then
    lastSuggestBoss = nil
    lastSuggestDungeon = nil
  elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
    -- Rebuild boss index for new role/spec
    buildBossIndex()
    lastSuggestBoss = nil
  end
end)
