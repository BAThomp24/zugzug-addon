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

--- Compact form: normalized, common articles dropped, all whitespace
--- removed. This bridges the naming gaps between WoW's in-game dungeon
--- names and the website's build data, which don't always agree on
--- apostrophe placement or articles, e.g.
---   "Seat of the Triumvirate" (in-game) vs "Seat of Triumvirate" (data)
---   "Magister's Terrace"       vs "Magisters' Terrace"
--- Both collapse to the same compact form, so the popup still fires.
local function compactName(name)
  local s = normName(name)
  s = " " .. s .. " "
  s = string.gsub(s, " the ", " ")  -- drop the most common article
  s = string.gsub(s, "%s+", "")     -- remove all spaces → position-agnostic
  return s
end

--- Match a target name against a data name.
--- Exact → normalized → compact (article/apostrophe/spacing-agnostic),
--- all pcall-safe so a bad string can never abort the suggest flow.
local function namesMatch(targetName, dataName)
  if targetName == dataName then return true end
  local ok, result = pcall(function()
    if normName(targetName) == normName(dataName) then return true end
    if compactName(targetName) == compactName(dataName) then return true end
    return false
  end)
  return ok and result or false
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
local SUGGEST_WIDTH_BASE = 320
local SUGGEST_WIDTH_WIDE = 400
local SUGGEST_HEIGHT_BASE = 72
local SUGGEST_HEIGHT_WITH_SWAPS = 158
local MAX_SWAPS_SHOWN = 3

-- Session-only suppression set. Declared up here so the Apply Swaps
-- button's OnClick closure inside createSuggestFrame captures it as an
-- upvalue rather than falling through to the global namespace (where it
-- would be nil and the suppression assignment would error silently).
local suppressedSwaps = {}

local function createSuggestFrame()
  if suggestFrame then return suggestFrame end

  local f = CreateFrame("Frame", "ZugZugSuggestFrame", UIParent, "BackdropTemplate")
  f:SetSize(SUGGEST_WIDTH_BASE, SUGGEST_HEIGHT_BASE)
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

  -- Swap section (only shown when dungeon swaps are present)
  local swapHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  swapHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -46)
  swapHeader:SetTextColor(0.56, 0.75, 0.25)
  swapHeader:Hide()
  f.swapHeader = swapHeader

  -- Each swap line is a small container: arrow + spell icon (hoverable for tooltip) + label
  f.swapLines = {}
  for i = 1, MAX_SWAPS_SHOWN do
    local row = CreateFrame("Frame", nil, f)
    row:SetHeight(16)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -58 - ((i - 1) * 18))
    row:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    row:Hide()

    -- A swap row pairs a drop talent on the left with a pick talent on
    -- the right, separated by an arrow. For choice-node swaps (same node,
    -- different entry) the drop icon is hidden and the row reads as
    -- "Swap to <pick>" — visually unmistakable from a refund-and-purchase
    -- swap, since those show both icons.

    local function buildIconBtn()
      local btn = CreateFrame("Frame", nil, row)
      btn:SetSize(14, 14)
      btn:EnableMouse(true)
      local tex = btn:CreateTexture(nil, "ARTWORK")
      tex:SetAllPoints(btn)
      tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      btn.icon = tex
      local border = btn:CreateTexture(nil, "OVERLAY")
      border:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
      border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
      border:SetColorTexture(0, 0, 0, 0.6)
      border:SetDrawLayer("BACKGROUND")
      btn:SetScript("OnEnter", function(self)
        if not self.spellID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
      return btn
    end

    -- Drop icon (left)
    local dropIcon = buildIconBtn()
    dropIcon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.dropIcon = dropIcon

    -- Connector arrow between the two talents
    local connector = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    connector:SetPoint("LEFT", dropIcon, "RIGHT", 4, 0)
    connector:SetWidth(14)
    connector:SetJustifyH("CENTER")
    connector:SetText("|cffaaaaaa→|r")
    row.connector = connector

    -- Pick icon (right)
    local pickIcon = buildIconBtn()
    pickIcon:SetPoint("LEFT", connector, "RIGHT", 2, 0)
    row.pickIcon = pickIcon

    -- Label text to the right of both icons
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", pickIcon, "RIGHT", 6, 0)
    text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    row.text = text

    f.swapLines[i] = row
  end

  -- Apply Build button
  local applyBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
  applyBtn:SetSize(90, 22)
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
  applyBtn.text = applyText
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

  -- Apply Swaps button (shown only when dungeon swaps are present)
  local applySwapsBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
  applySwapsBtn:SetSize(110, 22)
  applySwapsBtn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  applySwapsBtn:SetBackdropColor(0.30, 0.55, 0.85, 0.25)
  applySwapsBtn:SetBackdropBorderColor(0.40, 0.65, 0.95, 0.7)
  local applySwapsText = applySwapsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  applySwapsText:SetPoint("CENTER")
  applySwapsText:SetText("|cff80c8ffApply Swaps|r")
  applySwapsBtn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(0.30, 0.55, 0.85, 0.40)
  end)
  applySwapsBtn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0.30, 0.55, 0.85, 0.25)
  end)
  applySwapsBtn:SetScript("OnClick", function()
    if f.currentSwaps and ZZ.ApplySwaps then
      local applied = ZZ:ApplySwaps(f.currentSwaps)
      -- If ApplySwaps reported no progress at all, the swap is stuck
      -- (an unsatisfiable prereq, almost always). Suppress this popup
      -- for the rest of the session so the user isn't pestered each
      -- time they re-enter the dungeon.
      if applied == false and f.currentContentLabel then
        suppressedSwaps[f.currentContentLabel] = true
      end
    end
    f:Hide()
  end)
  applySwapsBtn:Hide()
  f.applySwapsBtn = applySwapsBtn

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

-- Talent-diff threshold below which the player is considered "on the build".
-- Builds within the same cluster on the website often differ by 1-3 picks
-- (variation talents). Anything beyond that is a meaningfully different build.
local SAME_BUILD_DIFF_THRESHOLD = 4

--- Returns true if the player's current loadout already matches the build.
--- Requires spec + hero to match, then uses a talent-diff threshold so small
--- variations within the same cluster still count as "on the build".
local function isAlreadyOnBuild(build)
  if not build then return false end
  if build.spec ~= ZZ.specName then return false end

  -- If the build specifies a hero tree, the player must be on the same one.
  if build.hero and build.hero ~= "" then
    local heroName = getActiveHeroName()
    if heroName and heroName ~= build.hero then return false end
  end

  -- Compare actual talent picks. Small diffs = same build cluster.
  if ZZ.CountTalentDiff and build.importString and build.importString ~= "" then
    local diff = ZZ.CountTalentDiff(build.importString)
    if diff ~= nil then
      return diff < SAME_BUILD_DIFF_THRESHOLD
    end
  end

  -- Fallback: import string couldn't be parsed — spec+hero match is good enough.
  return true
end

-- (suppressedSwaps is defined above createSuggestFrame — see comment there.)

showSuggestion = function(contentLabel, build, contentType, swapData)
  if not build or not build.importString or build.importString == "" then return end
  if InCombatLockdown() then return end
  if not ZugZugDB.suggestEnabled then return end
  if suppressedSwaps[contentLabel] then return end

  local onBuild = isAlreadyOnBuild(build)
  local picks = swapData and swapData.picks or nil
  local drops = swapData and swapData.drops or nil
  local hasSwaps = (picks and #picks > 0) or (drops and #drops > 0)
  -- Stash for /run inspection so the user can poke at the same data
  -- the popup decision saw.
  ZZ.lastBuild      = build
  ZZ.lastSwapData   = swapData
  ZZ.lastOnBuild    = onBuild
  ZZ.lastHasSwaps   = hasSwaps
  -- SwapsAlreadyApplied does a live talent dry-run (stage refunds/
  -- purchases, then RollbackConfig). Isolate it: if that dry-run errors
  -- — e.g. a talent API shift in a patch — we must NOT let it abort the
  -- whole suggest flow and swallow the popup. On failure we treat swaps
  -- as NOT-yet-applied, i.e. err toward showing the popup.
  local okChk, alreadyApplied = pcall(function()
    return ZZ.SwapsAlreadyApplied and ZZ:SwapsAlreadyApplied(swapData)
  end)
  if not okChk then
    alreadyApplied = false
    if ZugZugDB.suggestDebug then
      print("|cff00ccffZugZug:|r SwapsAlreadyApplied errored: " .. tostring(alreadyApplied))
    end
  end
  ZZ.lastSwapsAlreadyApplied = alreadyApplied

  if ZugZugDB.suggestDebug then
    print(string.format(
      "|cff00ccffZugZug suggest:|r contentLabel=%q onBuild=%s hasSwaps=%s alreadyApplied=%s picks=%d drops=%d",
      tostring(contentLabel), tostring(onBuild), tostring(hasSwaps),
      tostring(alreadyApplied), picks and #picks or 0, drops and #drops or 0))
    -- Auto-dump per-pick/drop state so the user doesn't have to type
    -- anything to see why the check returned what it did.
    if ZZ.DumpLastSwapState then
      ZZ:DumpLastSwapState()
    else
      print("|cff00ccffZugZug:|r DumpLastSwapState is nil — UI.lua hasn't reloaded with the new function")
    end
  end

  -- Already on the right build → nothing to do unless there are still
  -- swap recommendations the player hasn't applied yet.
  if onBuild then
    if not hasSwaps then return end
    if alreadyApplied then return end
  end

  local f = createSuggestFrame()
  f.currentBuild = build
  f.currentSwaps = swapData
  f.currentContentLabel = contentLabel

  local typeColor = contentType == "raid" and "|cffFFBF33" or "|cff66DD66"
  -- If they're already on the recommended build, frame the popup as "tweaks for this dungeon"
  -- so it doesn't read like a redundant suggestion. Otherwise use the original "Best for X" label.
  if onBuild and hasSwaps then
    f.header:SetText("|cff8fbf3fZugZug|r " .. typeColor .. "Dungeon tweaks: " .. contentLabel:gsub("^Best for ", "") .. "|r")
  else
    f.header:SetText("|cff8fbf3fZugZug|r " .. typeColor .. contentLabel .. "|r")
  end

  -- Configure button layout based on state. We never show both action
  -- buttons at once — that produced confusing popups where Apply Build
  -- and Apply Swaps offered ambiguously different paths.
  -- States:
  --   not on build               → [Apply Build] [Dismiss]
  --                                (import the recommended build; dungeon
  --                                 tweaks come along for the ride)
  --   on build  + has swaps      → [Apply Swaps] [Dismiss]
  --                                (already on the build, just need the
  --                                 dungeon-specific tweaks)
  --   on build  + no swaps       → [Apply] [Dismiss]
  --                                (only reachable for non-swap builds —
  --                                 raid bosses without per-boss tweaks)
  if hasSwaps and onBuild then
    f.applyBtn:Hide()
    f.applySwapsBtn:Show()
    f.applySwapsBtn:ClearAllPoints()
    f.applySwapsBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
    f.dismissBtn:ClearAllPoints()
    f.dismissBtn:SetPoint("LEFT", f.applySwapsBtn, "RIGHT", 6, 0)
  elseif hasSwaps then
    f.applyBtn:Show()
    f.applyBtn.text:SetText("|cff8fbf3fApply Build|r")
    f.applySwapsBtn:Hide()
    f.applyBtn:ClearAllPoints()
    f.applyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
    f.dismissBtn:ClearAllPoints()
    f.dismissBtn:SetPoint("LEFT", f.applyBtn, "RIGHT", 6, 0)
  else
    f.applyBtn:Show()
    f.applyBtn.text:SetText("|cff8fbf3fApply|r")
    f.applySwapsBtn:Hide()
    f.applyBtn:ClearAllPoints()
    f.applyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
    f.dismissBtn:ClearAllPoints()
    f.dismissBtn:SetPoint("LEFT", f.applyBtn, "RIGHT", 6, 0)
  end

  local specHero = build.spec
  if build.hero and build.hero ~= "" then
    specHero = specHero .. " · " .. build.hero
  end
  f.buildText:SetText("|cffffffff" .. build.label .. "|r  |cff888888" .. specHero .. "  " .. build.popularity .. "%|r")

  -- Swap section: pair each drop[i] with pick[i] so the user can see the
  -- exact "Apply Swaps" action plan. After the pool-aware fix in the
  -- dataset assembler, picks and drops are 1:1 pool-paired, so this works
  -- out of the box. For choice nodes (same talent node, different entry)
  -- we collapse to a single "swap to <new>" row.
  if hasSwaps then
    f:SetWidth(SUGGEST_WIDTH_WIDE)
    f:SetHeight(SUGGEST_HEIGHT_WITH_SWAPS)
    f.swapHeader:SetText("Changes Apply Swaps will make:")
    f.swapHeader:Show()

    local lookup = (ZZ.GetTalentLookup and ZZ:GetTalentLookup()) or {}

    -- Per-side alignment check. A drop is "aligned" if it's already at
    -- rank 0 (or for a choice node, not the active entry) — meaning the
    -- user has already dropped it and doesn't need to do anything to
    -- get rid of it. A pick is "aligned" if it's already at maxRanks
    -- (or the chosen choice entry). When BOTH sides are aligned, the
    -- pair is omitted entirely. When only the drop is aligned, the row
    -- collapses to "Take X" (no need to drop something that's already
    -- gone). When only the pick is aligned, it collapses to "Drop Y"
    -- (the talent the user still has but the build doesn't want).
    local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID
                      and C_ClassTalents.GetActiveConfigID()
    local function sideAligned(name, isPick)
      if not configID then return false end
      local t = name and lookup[name]
      if not t then return false end
      local ni = C_Traits.GetNodeInfo(configID, t.nodeID)
      if not ni then return false end
      if t.isChoice then
        local active = ni.activeEntry and ni.activeEntry.entryID
        if isPick then return active == t.entryID end
        return active ~= t.entryID
      end
      local cur = ni.currentRank or 0
      local mx  = ni.maxRanks or 1
      if isPick then return cur >= mx end
      return cur == 0
    end

    local picksList = picks or {}
    local dropsList = drops or {}
    local pairs_ = {}
    local maxLen = math.max(#picksList, #dropsList)
    for i = 1, maxLen do
      local drop, pick = dropsList[i], picksList[i]
      local dropAligned = not drop or sideAligned(drop.name, false)
      local pickAligned = not pick or sideAligned(pick.name, true)
      if dropAligned and pickAligned then
        -- Both sides already in target state — omit entirely.
      elseif dropAligned then
        -- Only the pick needs action — show as lone pick.
        pairs_[#pairs_ + 1] = { pick = pick }
      elseif pickAligned then
        -- Only the drop needs action — show as lone drop.
        pairs_[#pairs_ + 1] = { drop = drop }
      else
        -- Both sides need action — show as paired swap.
        pairs_[#pairs_ + 1] = { drop = drop, pick = pick }
      end
    end

    for i = 1, MAX_SWAPS_SHOWN do
      local line  = f.swapLines[i]
      local pair  = pairs_[i]
      if not pair then
        line:Hide()
      else
        local dropInfo = pair.drop and lookup[pair.drop.name]
        local pickInfo = pair.pick and lookup[pair.pick.name]

        -- Detect a choice-node swap (same node, both choice entries) so
        -- the row reads "Swap to X" instead of "Drop X for Y" — that's
        -- what ApplySwaps will actually do (SetSelection, no refund).
        local isChoiceSwap =
          pair.drop and pair.pick
          and dropInfo and pickInfo
          and dropInfo.nodeID == pickInfo.nodeID
          and dropInfo.isChoice and pickInfo.isChoice

        if isChoiceSwap then
          -- One icon (the new choice entry) + "Swap to X (was Y)" text.
          line.dropIcon:Hide()
          line.connector:Hide()
          line.pickIcon:ClearAllPoints()
          line.pickIcon:SetPoint("LEFT", line, "LEFT", 0, 0)
          line.pickIcon.icon:SetTexture(pickInfo.iconID or "")
          line.pickIcon.spellID = pickInfo.spellID
          line.pickIcon:Show()
          line.text:SetText(
            "Swap to |cff5DCAA5" .. pair.pick.name .. "|r"
            .. "  |cff888888(was " .. pair.drop.name .. ")|r")
          line:Show()
        elseif pair.drop and pair.pick then
          -- Standard refund-and-purchase pair: drop icon → pick icon
          -- with both names in the text, color-coded.
          if dropInfo and dropInfo.iconID then
            line.dropIcon.icon:SetTexture(dropInfo.iconID)
            line.dropIcon.spellID = dropInfo.spellID
            line.dropIcon:Show()
          else
            line.dropIcon:Hide()
          end
          line.connector:Show()
          line.pickIcon:ClearAllPoints()
          line.pickIcon:SetPoint("LEFT", line.connector, "RIGHT", 2, 0)
          if pickInfo and pickInfo.iconID then
            line.pickIcon.icon:SetTexture(pickInfo.iconID)
            line.pickIcon.spellID = pickInfo.spellID
            line.pickIcon:Show()
          else
            line.pickIcon:Hide()
          end
          line.text:SetText(
            "|cffE06B6B" .. pair.drop.name .. "|r"
            .. "  →  "
            .. "|cff5DCAA5" .. pair.pick.name .. "|r")
          line:Show()
        elseif pair.pick then
          -- Lone pick — either no matched drop in the dataset, or the
          -- drop side is already aligned (already dropped) so we omit it.
          line.dropIcon:Hide()
          line.connector:Hide()
          line.pickIcon:ClearAllPoints()
          line.pickIcon:SetPoint("LEFT", line, "LEFT", 0, 0)
          if pickInfo and pickInfo.iconID then
            line.pickIcon.icon:SetTexture(pickInfo.iconID)
            line.pickIcon.spellID = pickInfo.spellID
            line.pickIcon:Show()
          else
            line.pickIcon:Hide()
          end
          line.text:SetText(
            "Take |cff5DCAA5" .. pair.pick.name .. "|r")
          line:Show()
        elseif pair.drop then
          -- Lone drop — either no matched pick, or the pick is already
          -- at max so we omit the right side.
          line.connector:Hide()
          line.pickIcon:Hide()
          line.dropIcon:ClearAllPoints()
          line.dropIcon:SetPoint("LEFT", line, "LEFT", 0, 0)
          if dropInfo and dropInfo.iconID then
            line.dropIcon.icon:SetTexture(dropInfo.iconID)
            line.dropIcon.spellID = dropInfo.spellID
            line.dropIcon:Show()
          else
            line.dropIcon:Hide()
          end
          line.text:SetText(
            "Drop |cffE06B6B" .. pair.drop.name .. "|r")
          line:Show()
        else
          line:Hide()
        end
      end
    end
  else
    f:SetWidth(SUGGEST_WIDTH_BASE)
    f:SetHeight(SUGGEST_HEIGHT_BASE)
    f.swapHeader:Hide()
    for i = 1, MAX_SWAPS_SHOWN do
      f.swapLines[i]:Hide()
    end
  end

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

      -- Reset the dungeon-suggest debouncer when we leave a party
      -- instance — next time we enter a dungeon, the popup is allowed
      -- to fire again.
      if instanceType ~= "party" then
        ZugZugDB.lastSuggestDungeon = nil
        lastSuggestDungeon = nil
      end

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
  -- On PLAYER_ENTERING_WORLD (especially after /reload) the talent API
  -- can take a beat to populate. We delay the dungeon check by 1.5s so
  -- isAlreadyOnBuild / SwapsAlreadyApplied see settled data and don't
  -- false-positive a "needs swap" suggestion that ApplySwaps then no-ops.
  if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
    local delay = (event == "PLAYER_ENTERING_WORLD") and 1.5 or 0
    local function runDungeonSuggest()
      local ok, err = pcall(function()
        if not ZZ.data or not ZZ.classToken then return end

        -- If an M+ key is already in progress, talents are locked — the
        -- popup is just noise on every /reload. Skip silently.
        if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
          local okC, activeID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
          if okC and type(activeID) == "number" and activeID > 0 then return end
        end

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
        -- Debouncer persists across /reload via saved variables so we
        -- don't re-pop the suggestion every time the user reloads inside
        -- the same dungeon. lastSuggestDungeon is reset on actual zone
        -- exit (PLAYER_ENTERING_WORLD outside a party instance).
        local lastDungeon = ZugZugDB.lastSuggestDungeon or lastSuggestDungeon
        if lastDungeon == dungeonName then return end
        ZugZugDB.lastSuggestDungeon = dungeonName
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
          local swaps = best.dungeonSwaps and best.dungeonSwaps[dungeonName] or nil
          showSuggestion(label, best, "mp", swaps)
        end
      end)
      if not ok then
        print("|cff00ccffZugZug:|r ZONE error: " .. tostring(err))
      end
    end
    if delay > 0 then
      C_Timer.After(delay, runDungeonSuggest)
    else
      runDungeonSuggest()
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
    -- Spec change → tree is different, anything we marked as
    -- "unsatisfiable" might now work. Wipe the suppression.
    suppressedSwaps = {}
  end
end)
