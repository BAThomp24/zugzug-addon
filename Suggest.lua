----------------------------------------------------------------------
-- ZugZug Specs — Smart Suggest
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
    if ZZ:BuildMatchesSpec(build) and build.bosses then
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
    if ZZ:BuildMatchesSpec(build) then
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
    if ZZ:BuildMatchesSpec(build) and build.dungeons then
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
    if ZZ:BuildMatchesSpec(build) then
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
    print("|cff00ccffZugZug Specs:|r Failed to read encounter journal: " .. tostring(err))
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

  local best = nil
  for _, build in ipairs(builds) do
    if ZZ:BuildMatchesSpec(build) then
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
  f:SetClampedToScreen(true)
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

  -- Diff section (shown when the recommended build differs from the
  -- player's current talents — each row is one change Apply Build makes)
  local swapHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  swapHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -46)
  swapHeader:SetTextColor(0.56, 0.75, 0.25)
  swapHeader:Hide()
  f.swapHeader = swapHeader

  -- Truncation note when there are more changes than visible rows —
  -- Apply Build applies ALL of them, so say so instead of hiding it.
  local swapMore = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  swapMore:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -58 - (MAX_SWAPS_SHOWN * 18))
  swapMore:SetJustifyH("LEFT")
  swapMore:Hide()
  f.swapMore = swapMore

  -- Each diff line is a small container: arrow + spell icon (hoverable for tooltip) + label
  f.swapLines = {}
  for i = 1, MAX_SWAPS_SHOWN do
    local row = CreateFrame("Frame", nil, f)
    row:SetHeight(16)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -58 - ((i - 1) * 18))
    row:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    row:Hide()

    -- A diff row pairs a dropped talent on the left with a picked talent
    -- on the right, separated by an arrow. For choice-node changes (same
    -- node, different entry) the drop icon is hidden and the row reads as
    -- "Swap to <pick>"; lone additions/removals show a single icon.

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
  if not ZZ:BuildMatchesSpec(build) then return false end

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

showSuggestion = function(contentLabel, build, contentType)
  if not build or not build.importString or build.importString == "" then return end
  if InCombatLockdown() then return end
  if not ZugZugDB.suggestEnabled then return end

  -- Structured diff vs the player's CURRENT talents: exactly what Apply
  -- Build will change. nil = build is for another spec (or unparseable) —
  -- fall back to the spec/hero cluster heuristic for the "on it" decision.
  local diffPairs = ZZ.DiffAgainstCurrent and ZZ:DiffAgainstCurrent(build.importString) or nil
  local onBuild
  if diffPairs then
    if contentType == "raid" then
      -- Raid builds cluster: small variations are the same build. Keep the
      -- historical threshold so boss popups don't nag over 1-2 tweaks.
      onBuild = #diffPairs < SAME_BUILD_DIFF_THRESHOLD
    else
      -- Dungeon suggestions are EXACT by design — the per-dungeon build
      -- often differs from the overall one by only 1-3 talents, which is
      -- precisely what we're here to surface.
      onBuild = #diffPairs == 0
    end
  else
    onBuild = isAlreadyOnBuild(build)
  end
  local hasDiff = diffPairs ~= nil and #diffPairs > 0

  -- Stash for /run inspection so the user can poke at the same data
  -- the popup decision saw.
  ZZ.lastBuild     = build
  ZZ.lastDiffPairs = diffPairs
  ZZ.lastOnBuild   = onBuild

  if ZugZugDB.suggestDebug then
    print(string.format(
      "|cff00ccffZugZug suggest:|r contentLabel=%q onBuild=%s diffs=%s",
      tostring(contentLabel), tostring(onBuild),
      diffPairs and tostring(#diffPairs) or "nil"))
  end

  -- Already on this setup → nothing to suggest.
  if onBuild then return end

  local f = createSuggestFrame()
  f.currentBuild = build
  f.currentContentLabel = contentLabel

  local typeColor = contentType == "raid" and "|cffFFBF33" or "|cff66DD66"
  f.header:SetText("|cff8fbf3fZugZug|r " .. typeColor .. contentLabel .. "|r")

  -- One action: Apply Build imports the recommended build whole. The
  -- dedicated-loadout path validates the final tree as a unit — no
  -- incremental talent moves, no point-gate hazards.
  f.applyBtn:Show()
  f.applyBtn.text:SetText(hasDiff and "|cff8fbf3fApply Build|r" or "|cff8fbf3fApply|r")
  f.applyBtn:ClearAllPoints()
  f.applyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
  f.dismissBtn:ClearAllPoints()
  f.dismissBtn:SetPoint("LEFT", f.applyBtn, "RIGHT", 6, 0)

  local specHero = build.spec
  if build.hero and build.hero ~= "" then
    specHero = specHero .. " · " .. build.hero
  end
  f.buildText:SetText("|cffffffff" .. build.label .. "|r  |cff888888" .. specHero .. "  " .. build.popularity .. "%|r")

  -- Diff section: one row per change Apply Build will make, computed from
  -- the player's CURRENT talents vs the build's import string (so every
  -- row is real — nothing already-aligned is listed). Same-node choice
  -- changes render "Swap to X (was Y)"; others are lone Take/Drop rows.
  if hasDiff then
    f:SetWidth(SUGGEST_WIDTH_WIDE)
    f:SetHeight(SUGGEST_HEIGHT_WITH_SWAPS)
    f.swapHeader:SetText("Changes from your current talents:")
    f.swapHeader:Show()

    local lookup = (ZZ.GetTalentLookup and ZZ:GetTalentLookup()) or {}

    -- Rank note: "(1/2)" when the build takes a different rank count of a
    -- talent the player already has.
    local function whySuffix(side)
      if side and side.note then
        return "  |cff888888(" .. side.note .. ")|r"
      end
      return ""
    end

    local pairs_ = diffPairs

    for i = 1, MAX_SWAPS_SHOWN do
      local line  = f.swapLines[i]
      local pair  = pairs_[i]
      if not pair then
        line:Hide()
      else
        local dropInfo = pair.drop and lookup[pair.drop.name]
        local pickInfo = pair.pick and lookup[pair.pick.name]

        -- Detect a choice-node change (same node, both choice entries) so
        -- the row reads "Swap to X" instead of "Drop X for Y".
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
            .. "  |cff888888(was " .. pair.drop.name .. ")|r"
            .. whySuffix(pair.pick))
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
            .. "|cff5DCAA5" .. pair.pick.name .. "|r"
            .. whySuffix(pair.pick))
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
            "Take |cff5DCAA5" .. pair.pick.name .. "|r" .. whySuffix(pair.pick))
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
            "Drop |cffE06B6B" .. pair.drop.name .. "|r" .. whySuffix(pair.drop))
          line:Show()
        else
          line:Hide()
        end
      end
    end

    -- More changes than visible rows: Apply Build still applies ALL of
    -- them, so surface the overflow instead of silently truncating.
    local hiddenPairs = #pairs_ - MAX_SWAPS_SHOWN
    if hiddenPairs > 0 then
      f.swapMore:SetText(string.format(
        "|cff888888…and %d more — Apply Build changes all %d|r", hiddenPairs, #pairs_))
      f.swapMore:Show()
      f:SetHeight(SUGGEST_HEIGHT_WITH_SWAPS + 14)
    else
      f.swapMore:Hide()
    end
  else
    f:SetWidth(SUGGEST_WIDTH_BASE)
    f:SetHeight(SUGGEST_HEIGHT_BASE)
    f.swapHeader:Hide()
    f.swapMore:Hide()
    for i = 1, MAX_SWAPS_SHOWN do
      f.swapLines[i]:Hide()
    end
  end

  f:Show()
end

----------------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------------

-- Timestamp-based cooldown: a stale C_Timer from an earlier suggest can't
-- clear a newer cooldown early (the old boolean+timer pattern could).
local suggestBossCooldownUntil = 0
local lastSuggestDungeon = nil
-- PLAYER_TARGET_CHANGED fires constantly; if its handler errors, warn once
-- instead of spamming chat on every target swap.
local warnedTargetError = false

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
        suggestBossCooldownUntil = 0
        killedEncounters = {}
        -- Build boss order from Encounter Journal
        buildBossOrder()

        if #raidBossOrder > 0 then
          local firstBoss = raidBossOrder[1].name
          suggestForBoss(firstBoss)
          suggestBossCooldownUntil = GetTime() + 30
        end
      else
        -- Left raid — reset state
        raidBossOrder = {}
        killedEncounters = {}
        currentRaidDiff = nil
        suggestBossCooldownUntil = 0
      end
    end)
    if not ok then
      print("|cff00ccffZugZug Specs:|r ENTERING_WORLD error: " .. tostring(err))
    end
    -- Fall through to dungeon detection below
  end

  -- ── Raid: suggest when targeting a boss-level mob ──
  if event == "PLAYER_TARGET_CHANGED" then
    local ok, err = pcall(function()
      if not ZZ.data or not ZZ.classToken or not ZZ.role then return end
      if InCombatLockdown() then return end
      if not UnitExists("target") then return end
      if GetTime() < suggestBossCooldownUntil then return end

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

      suggestBossCooldownUntil = GetTime() + 30
    end)
    if not ok and not warnedTargetError then
      warnedTargetError = true
      print("|cff00ccffZugZug Specs:|r TARGET error (further errors suppressed): " .. tostring(err))
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
      suggestBossCooldownUntil = 0

      -- Suggest build for the next boss
      local nextBoss = getNextBossName()
      if nextBoss then
        -- Small delay so it doesn't flash during loot
        C_Timer.After(3, function()
          suggestForBoss(nextBoss)
          suggestBossCooldownUntil = GetTime() + 30
        end)
      end
    end)
    if not ok then
      print("|cff00ccffZugZug Specs:|r BOSS_KILL error: " .. tostring(err))
    end
    return
  end

  -- ── M+/Dungeon: suggest when zoning into a dungeon ──
  -- On PLAYER_ENTERING_WORLD (especially after /reload) the talent API
  -- can take a beat to populate. We delay the dungeon check by 1.5s so
  -- the current-talents diff sees settled data and doesn't false-positive
  -- a suggestion the player is already on.
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

        local _, instanceType = GetInstanceInfo()
        if instanceType ~= "party" then return end
        local dungeonName = GetInstanceInfo()
        if not dungeonName then return end

        -- Key-level awareness: if the player's own keystone is for THIS
        -- dungeon, suggest from the matching key-level bucket and label
        -- the popup "+N". (The active-keystone APIs are useless here —
        -- once a key is actually active, talents are locked and we've
        -- already returned above.)
        local level = 0
        if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
          local okK, ownedMapID = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
          if okK and type(ownedMapID) == "number" and ownedMapID > 0 then
            local okN, ownedName = pcall(C_ChallengeMode.GetMapUIInfo, ownedMapID)
            if okN and type(ownedName) == "string" and namesMatch(dungeonName, ownedName) then
              local okL, lvl = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
              if okL and type(lvl) == "number" then level = lvl end
            end
          end
        end
        -- Debouncer persists across /reload via saved variables so we
        -- don't re-pop the suggestion every time the user reloads inside
        -- the same dungeon. lastSuggestDungeon is reset on actual zone
        -- exit (PLAYER_ENTERING_WORLD outside a party instance).
        local lastDungeon = ZugZugDB.lastSuggestDungeon or lastSuggestDungeon
        if lastDungeon == dungeonName then return end
        ZugZugDB.lastSuggestDungeon = dungeonName
        lastSuggestDungeon = dungeonName

        local bucket = level > 0 and keystoneToBucket(level) or (ZugZugDB.suggestMpBucket or "all")

        -- Preferred: the per-dungeon top build (RIO data) — a complete
        -- import string for THIS dungeon at this key bucket, recommended
        -- and applied whole. Buckets whose sample was too thin weren't
        -- emitted; fall back to progressively shallower ones.
        local best
        local db = ZZ.data.dungeonBuilds
        local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
        if db and specID then
          local perRole = db[ZZ.classToken] and db[ZZ.classToken][ZZ.role]
          local perSpec
          for _, buckets in pairs(perRole or {}) do
            -- Entries are keyed by spec NAME; identify the player's by
            -- probing any contained build's specId.
            local probe
            for _, byDungeon in pairs(buckets) do
              for _, b in pairs(byDungeon) do probe = b break end
              if probe then break end
            end
            if probe and probe.specId == specID then perSpec = buckets break end
          end
          if perSpec then
            local FALLBACK = {
              ["20+"] = { "20+", "18+", "15+", "all" },
              ["18+"] = { "18+", "15+", "all" },
              ["15+"] = { "15+", "all" },
              ["all"] = { "all" },
            }
            for _, bk in ipairs(FALLBACK[bucket] or { "all" }) do
              local byDungeon = perSpec[bk]
              if byDungeon then
                best = byDungeon[dungeonName]
                if not best then
                  -- Data dungeon names don't always match the in-game name
                  -- exactly — reuse the fuzzy matcher.
                  for dataName, b in pairs(byDungeon) do
                    if namesMatch(dungeonName, dataName) then best = b break end
                  end
                end
                if best then break end
              end
            end
          end
        end

        -- Fallback (zugzug/WCL source, or no per-dungeon data): the best
        -- overall build for this dungeon from the bucket's build list.
        if not best then
          local classEntry = ZZ.data.classes[ZZ.classToken]
          if not classEntry then return end
          local roleData = classEntry[ZZ.role]
          if not roleData or not roleData.mythicPlus then return end
          best = findBestBuildForDungeon(roleData.mythicPlus[bucket], dungeonName)
        end

        if best then
          local label = level > 0 and ("Best for " .. dungeonName .. " +" .. level) or ("Best for " .. dungeonName)
          showSuggestion(label, best, "mp")
        end
      end)
      if not ok then
        print("|cff00ccffZugZug Specs:|r ZONE error: " .. tostring(err))
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
    suggestBossCooldownUntil = 0
  end
end)
