----------------------------------------------------------------------
-- ZugZug — Leveling
-- Shows a "next talent to pick" suggestion as the player levels,
-- guiding them through a recommended talent order.
----------------------------------------------------------------------

local ZZ = _G.ZugZug

----------------------------------------------------------------------
-- Colors (match UI.lua theme)
----------------------------------------------------------------------

local COLORS = {
  accent = { r = 0.56, g = 0.75, b = 0.25 },
  bg     = { r = 0.08, g = 0.08, b = 0.1, a = 0.97 },
  border = { r = 0.22, g = 0.22, b = 0.26, a = 1 },
  text   = { r = 0.88, g = 0.88, b = 0.9 },
  muted  = { r = 0.5, g = 0.5, b = 0.55 },
}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

local MAX_LEVEL = 80
local levelingOrder = nil      -- current spec's pick order (array)
local currentIndex = 0         -- how far through the order we are
local bannerFrame = nil        -- the UI frame

----------------------------------------------------------------------
-- Find the leveling order for the player's current spec
----------------------------------------------------------------------

local function loadOrderForCurrentSpec()
  levelingOrder = nil
  currentIndex = 0


  if not ZugZugLevelingData then return end
  if not ZZ.classToken or not ZZ.specName then return end

  local classData = ZugZugLevelingData[ZZ.classToken]
  if not classData then return end

  for _, specEntry in ipairs(classData) do
    if specEntry.spec == ZZ.specName then
      levelingOrder = specEntry.order
      return
    end
  end
end

----------------------------------------------------------------------
-- Query the talent tree to find the next unpurchased node
----------------------------------------------------------------------

--- Check if the player has any unspent talent points via tree currencies.
local function hasUnspentPoints()
  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not specID then return false end
  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return false end
  local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
  if not treeID then return false end

  local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
  if currencies then
    for _, currency in ipairs(currencies) do
      if currency.quantity and currency.quantity > 0 then
        return true
      end
    end
  end
  return false
end

local function getNodePurchaseState(configID, nodeID)
  local info = C_Traits.GetNodeInfo(configID, nodeID)
  if not info then return nil end
  return {
    currentRank = info.currentRank or 0,
    maxRanks = info.maxRanks or 1,
    canPurchaseRank = info.canPurchaseRank,
    isAvailable = info.isAvailable,
    activeEntryID = info.activeEntry and info.activeEntry.entryID,
    entryIDs = info.entryIDs,
  }
end

--- Walk the order and find the first node that still needs purchasing
--- AND that is currently purchasable (player has unspent points + prereqs met).
--- Returns (index, pick) or (nil, nil) if the build is complete or no points available.
local function findNextPick()
  if not levelingOrder then return nil, nil end

  -- Early exit: no unspent talent points at all
  if not hasUnspentPoints() then return nil, nil end

  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not specID then return nil, nil end

  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return nil, nil end

  -- Walk through the order, tracking cumulative ranks per node
  local ranksApplied = {} -- nodeID → ranks already counted as purchased

  for i, pick in ipairs(levelingOrder) do
    local state = getNodePurchaseState(configID, pick.nodeID)
    if state then
      local appliedSoFar = ranksApplied[pick.nodeID] or 0
      local neededRank = appliedSoFar + 1

      if state.currentRank < neededRank then
        if state.canPurchaseRank then
          return i, pick
        end
      end
      ranksApplied[pick.nodeID] = neededRank
    end
  end

  return nil, nil
end

--- Count how many picks have been completed.
local function countCompleted()
  if not levelingOrder then return 0, 0 end

  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not specID then return 0, #levelingOrder end

  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return 0, #levelingOrder end

  local completed = 0
  local ranksApplied = {}

  for i, pick in ipairs(levelingOrder) do
    local state = getNodePurchaseState(configID, pick.nodeID)
    if state then
      local appliedSoFar = ranksApplied[pick.nodeID] or 0
      local neededRank = appliedSoFar + 1
      if state.currentRank >= neededRank then
        completed = completed + 1
      end
      ranksApplied[pick.nodeID] = neededRank
    end
  end

  return completed, #levelingOrder
end

----------------------------------------------------------------------
-- Purchase a talent node
----------------------------------------------------------------------

--- Stage a talent purchase (no commit). Returns true if the rank was staged.
local function stageNode(configID, pick)
  -- For choice nodes, select the correct entry first
  if pick.choiceIndex ~= nil then
    local info = C_Traits.GetNodeInfo(configID, pick.nodeID)
    if info and info.entryIDs then
      local targetEntryID = info.entryIDs[pick.choiceIndex + 1] -- 0-indexed → 1-indexed
      if targetEntryID then
        C_Traits.SetSelection(configID, pick.nodeID, targetEntryID)
      end
    end
  end

  return C_Traits.PurchaseRank(configID, pick.nodeID)
end

--- Stage + commit a single talent purchase.
local function purchaseNode(pick)
  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not specID then return false end

  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return false end

  local ok = stageNode(configID, pick)
  if ok then
    C_ClassTalents.CommitConfig(configID)
  end
  return ok
end

----------------------------------------------------------------------
-- Banner UI
----------------------------------------------------------------------

local BACKDROP_INFO = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 1,
}

--- Create a custom-skinned button (no Blizzard chrome).
local function createSkinButton(parent, width, height, label, bgColor, textColor)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(width, height)
  btn:SetBackdrop(BACKDROP_INFO)
  btn:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a or 0.9)
  btn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

  local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  text:SetPoint("CENTER")
  text:SetText(label)
  text:SetTextColor(textColor.r, textColor.g, textColor.b)
  btn.label = text

  -- Hover highlight
  btn:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b, 1)
  end)
  btn:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
  end)

  -- Disabled state
  local origSetEnabled = btn.SetEnabled
  btn.SetEnabled = function(self, enabled)
    if enabled then
      self:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a or 0.9)
      self.label:SetTextColor(textColor.r, textColor.g, textColor.b)
      self:EnableMouse(true)
    else
      self:SetBackdropColor(0.15, 0.15, 0.18, 0.6)
      self.label:SetTextColor(0.4, 0.4, 0.4)
      self:EnableMouse(false)
    end
  end

  return btn
end

local function createBanner()
  if bannerFrame then return bannerFrame end

  local f = CreateFrame("Frame", "ZugZugLevelingBanner", UIParent, "BackdropTemplate")
  f:SetSize(420, 52)
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  f:SetFrameStrata("HIGH")
  f:SetBackdrop(BACKDROP_INFO)
  f:SetBackdropColor(COLORS.bg.r, COLORS.bg.g, COLORS.bg.b, COLORS.bg.a)
  f:SetBackdropBorderColor(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b, 0.7)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  -- Close button — minimal X (top-right)
  local closeBtn = CreateFrame("Button", nil, f)
  closeBtn:SetSize(16, 16)
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  closeText:SetPoint("CENTER")
  closeText:SetText("x")
  closeText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  closeBtn:SetScript("OnEnter", function()
    closeText:SetTextColor(1, 0.4, 0.4)
  end)
  closeBtn:SetScript("OnLeave", function()
    closeText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  end)
  closeBtn:SetScript("OnClick", function()
    f:Hide()
  end)

  -- Progress: "3 of 71" — left of close button so they don't overlap
  local progressText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  progressText:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
  progressText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  f.progressText = progressText

  -- Title line: "Next talent: <name>"
  local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleText:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
  titleText:SetPoint("RIGHT", progressText, "LEFT", -8, 0)
  titleText:SetJustifyH("LEFT")
  titleText:SetWordWrap(false)
  titleText:SetTextColor(COLORS.text.r, COLORS.text.g, COLORS.text.b)
  f.titleText = titleText

  -- Left side: Pick + Pick All
  local pickBtn = createSkinButton(f, 60, 22, "Pick",
    { r = 0.2, g = 0.5, b = 0.2, a = 0.9 },
    { r = 0.85, g = 1, b = 0.85 })
  pickBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 6)
  pickBtn:SetScript("OnClick", function()
    local idx, pick = findNextPick()
    if pick then
      local ok = purchaseNode(pick)
      if ok then
        C_Timer.After(0.3, function() ZZ:RefreshLeveling() end)
      else
        print("|cff00ccffZugZug:|r Could not purchase " .. pick.name .. " — it may not be available yet.")
      end
    end
  end)
  f.pickBtn = pickBtn

  local pickAllBtn = createSkinButton(f, 66, 22, "Pick All",
    { r = 0.15, g = 0.4, b = 0.15, a = 0.9 },
    { r = 0.85, g = 1, b = 0.85 })
  pickAllBtn:SetPoint("LEFT", pickBtn, "RIGHT", 6, 0)
  pickAllBtn:SetScript("OnClick", function()
    if not levelingOrder then return end

    local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
    if not specID then return end
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return end

    -- Walk the order directly, staging all purchasable nodes without committing.
    -- The staging config updates in-place so subsequent PurchaseRank calls see
    -- the previously staged ranks, allowing the full chain to resolve.
    local staged = 0
    local ranksApplied = {}

    for i, pick in ipairs(levelingOrder) do
      local info = C_Traits.GetNodeInfo(configID, pick.nodeID)
      if info then
        local appliedSoFar = ranksApplied[pick.nodeID] or 0
        local neededRank = appliedSoFar + 1
        local currentRank = info.currentRank or 0

        if currentRank < neededRank and info.canPurchaseRank then
          if stageNode(configID, pick) then
            staged = staged + 1
          end
        end
        ranksApplied[pick.nodeID] = neededRank
      end
    end

    if staged > 0 then
      C_ClassTalents.CommitConfig(configID)
      print("|cff00ccffZugZug:|r Picked " .. staged .. " talents.")
      C_Timer.After(0.5, function() ZZ:RefreshLeveling() end)
    else
      print("|cff00ccffZugZug:|r No talents available to pick.")
    end
  end)
  f.pickAllBtn = pickAllBtn

  -- Right side: Skip + Reset
  local resetBtn = createSkinButton(f, 56, 22, "Reset",
    { r = 0.35, g = 0.12, b = 0.12, a = 0.9 },
    { r = 1, g = 0.7, b = 0.7 })
  resetBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 6)
  resetBtn:SetScript("OnClick", function()
    local level = UnitLevel("player")
    if level and level >= MAX_LEVEL then
      print("|cff00ccffZugZug:|r Reset is only available below max level.")
      return
    end

    local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
    if not specID then return end
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return end

    local ok = C_Traits.ResetTree(configID, C_ClassTalents.GetTraitTreeForSpec(specID))
    if ok then
      C_ClassTalents.CommitConfig(configID)
    
      print("|cff00ccffZugZug:|r Talents reset. Pick order restarted.")
      C_Timer.After(0.5, function() ZZ:RefreshLeveling() end)
    else
      print("|cff00ccffZugZug:|r Could not reset talents.")
    end
  end)
  f.resetBtn = resetBtn

  f:Hide()
  bannerFrame = f
  return f
end

----------------------------------------------------------------------
-- Refresh / update the banner
----------------------------------------------------------------------

--- Find the first unpurchased node in the order, ignoring unspent points.
--- Used when the player explicitly opens the banner to see progress.
local function findNextUnpurchased()
  if not levelingOrder then return nil, nil end

  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not specID then return nil, nil end

  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return nil, nil end

  local ranksApplied = {}

  for i, pick in ipairs(levelingOrder) do
    local state = getNodePurchaseState(configID, pick.nodeID)
    if state then
      local appliedSoFar = ranksApplied[pick.nodeID] or 0
      local neededRank = appliedSoFar + 1

      if state.currentRank < neededRank then
        return i, pick
      end
      ranksApplied[pick.nodeID] = neededRank
    end
  end

  return nil, nil
end

local function updateBanner(pick)
  local banner = createBanner()
  local completed, total = countCompleted()

  if pick then
    banner.titleText:SetText("|cff8fbf3fNext talent:|r " .. pick.name)
  else
    banner.titleText:SetText("|cff8fbf3fBuild complete!|r")
  end
  banner.progressText:SetText(completed .. " of " .. total)

  -- Disable Pick if node can't be purchased right now
  local canPick = false
  if pick then
    local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
    local configID = specID and C_ClassTalents.GetActiveConfigID()
    if configID then
      local state = getNodePurchaseState(configID, pick.nodeID)
      canPick = state and state.canPurchaseRank
    end
  end
  local hasPoints = hasUnspentPoints()
  banner.pickBtn:SetEnabled(canPick)
  banner.pickAllBtn:SetEnabled(hasPoints and pick ~= nil)

  -- Only show Reset below max level
  local level = UnitLevel("player")
  banner.resetBtn:SetShown(level and level < MAX_LEVEL)

  banner:Show()
end

--- Auto-refresh: hides banner when no unspent points, shows when there are.
function ZZ:RefreshLeveling()
  if not levelingOrder then
    if bannerFrame then bannerFrame:Hide() end
    return
  end

  local idx, pick = findNextPick()
  if not pick then
    if bannerFrame then bannerFrame:Hide() end
    return
  end

  updateBanner(pick)
end

--- Explicit toggle from the Leveling button on the builds bar.
function ZZ:ToggleLevelingBanner()
  local banner = _G["ZugZugLevelingBanner"]
  if banner and banner:IsShown() then
    banner:Hide()
    return
  end

  if not levelingOrder then
    loadOrderForCurrentSpec()
  end

  if not levelingOrder then
    print("|cff00ccffZugZug:|r No leveling data for your spec.")
    return
  end

  -- Show banner with next unpurchased node (regardless of unspent points)
  local idx, pick = findNextUnpurchased()
  updateBanner(pick)
end

----------------------------------------------------------------------
-- Event handling
----------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")

frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    -- Only enable for non-max-level characters (or characters with incomplete builds)
    loadOrderForCurrentSpec()
    -- Delay initial check to let talent data load
    C_Timer.After(2, function()
      if levelingOrder then
        ZZ:RefreshLeveling()
      end
    end)
    return
  end

  if event == "ACTIVE_TALENT_GROUP_CHANGED" then
    loadOrderForCurrentSpec()
    C_Timer.After(0.5, function()
      if levelingOrder then
        ZZ:RefreshLeveling()
      else
        if bannerFrame then bannerFrame:Hide() end
      end
    end)
    return
  end

  if event == "PLAYER_LEVEL_UP" then
    -- New level → might have new talent points
    C_Timer.After(1, function()
      ZZ:RefreshLeveling()
    end)
    return
  end

  if event == "TRAIT_CONFIG_UPDATED" then
    -- Talents changed — update banner
    C_Timer.After(0.3, function()
      ZZ:RefreshLeveling()
    end)
    return
  end
end)
