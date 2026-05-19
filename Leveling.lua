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

local MAX_LEVEL = GetMaxPlayerLevel and GetMaxPlayerLevel() or 90
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

-- Class color helper (matches UI.lua)
local function getClassColor()
  local token = ZZ and ZZ.classToken
  local color = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  if color then return color.r, color.g, color.b end
  return 0.56, 0.75, 0.25
end

local function createBanner()
  if bannerFrame then return bannerFrame end

  local f = CreateFrame("Frame", "ZugZugLevelingBanner", UIParent, "BackdropTemplate")
  f:SetSize(600, 180)
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetBackdrop(BACKDROP_INFO)
  f:SetBackdropColor(COLORS.bg.r, COLORS.bg.g, COLORS.bg.b, COLORS.bg.a)
  f:SetBackdropBorderColor(COLORS.border.r, COLORS.border.g, COLORS.border.b, 1)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  -- Class-colored left accent bar
  local accent = f:CreateTexture(nil, "OVERLAY")
  accent:SetWidth(4)
  accent:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  accent:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
  local cr, cg, cb = getClassColor()
  accent:SetColorTexture(cr, cg, cb, 1)
  f.accent = accent

  -- Top brand stripe (accent green)
  local stripe = f:CreateTexture(nil, "OVERLAY")
  stripe:SetHeight(2)
  stripe:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -1)
  stripe:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  stripe:SetColorTexture(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b, 0.7)

  -- Close button (top-right)
  local closeBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
  closeBtn:SetSize(20, 20)
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
  closeBtn:SetBackdrop(BACKDROP_INFO)
  closeBtn:SetBackdropColor(0.10, 0.10, 0.13, 1)
  closeBtn:SetBackdropBorderColor(0.30, 0.30, 0.35, 1)
  local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 1)
  closeText:SetText("\195\151") -- ×
  closeText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  closeBtn:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
    closeText:SetTextColor(1, 0.5, 0.5)
  end)
  closeBtn:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(0.30, 0.30, 0.35, 1)
    closeText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  end)
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  -- Header row: phase chip + spec/level info
  local phaseChip = CreateFrame("Frame", nil, f, "BackdropTemplate")
  phaseChip:SetSize(74, 16)
  phaseChip:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -12)
  phaseChip:SetBackdrop(BACKDROP_INFO)
  phaseChip:SetBackdropColor(cr * 0.3, cg * 0.3, cb * 0.3, 1)
  phaseChip:SetBackdropBorderColor(cr * 0.7, cg * 0.7, cb * 0.7, 1)
  local phaseText = phaseChip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  phaseText:SetPoint("CENTER")
  phaseText:SetTextColor(cr, cg, cb)
  phaseText:SetText("SPEC TREE")
  phaseChip.text = phaseText
  f.phaseChip = phaseChip

  local specInfoText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  specInfoText:SetPoint("LEFT", phaseChip, "RIGHT", 8, 0)
  specInfoText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  f.specInfoText = specInfoText

  -- Talent icon (rounded, class-colored frame)
  local talentIconFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
  talentIconFrame:SetSize(48, 48)
  talentIconFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -36)
  talentIconFrame:SetBackdrop(BACKDROP_INFO)
  talentIconFrame:SetBackdropColor(cr * 0.4, cg * 0.4, cb * 0.4, 1)
  talentIconFrame:SetBackdropBorderColor(cr, cg, cb, 1)
  local talentIconText = talentIconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  talentIconText:SetPoint("CENTER")
  talentIconText:SetTextColor(1, 1, 1)
  talentIconFrame.text = talentIconText
  f.talentIconFrame = talentIconFrame

  -- "NEXT TALENT" eyebrow
  local nextLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nextLabel:SetPoint("TOPLEFT", talentIconFrame, "TOPRIGHT", 12, -2)
  nextLabel:SetTextColor(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b)
  nextLabel:SetText("NEXT TALENT")
  f.nextLabel = nextLabel

  -- Talent name (big)
  local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  titleText:SetPoint("TOPLEFT", nextLabel, "BOTTOMLEFT", 0, -2)
  titleText:SetPoint("RIGHT", f, "RIGHT", -18, 0)
  titleText:SetJustifyH("LEFT")
  titleText:SetWordWrap(false)
  titleText:SetTextColor(1, 1, 1)
  f.titleText = titleText

  -- Progress section
  local progLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  progLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -100)
  progLabel:SetText("BUILD PROGRESS")
  progLabel:SetTextColor(0.55, 0.55, 0.60)

  local progressText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  progressText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -100)
  progressText:SetTextColor(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b)
  f.progressText = progressText

  -- Progress bar track
  local barTrack = f:CreateTexture(nil, "ARTWORK")
  barTrack:SetHeight(8)
  barTrack:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -116)
  barTrack:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -116)
  barTrack:SetColorTexture(0.10, 0.10, 0.13, 1)
  f.barTrack = barTrack

  -- Progress bar fill
  local barFill = f:CreateTexture(nil, "OVERLAY")
  barFill:SetHeight(8)
  barFill:SetPoint("TOPLEFT", barTrack, "TOPLEFT", 0, 0)
  barFill:SetColorTexture(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b, 1)
  barFill:SetWidth(1)
  f.barFill = barFill

  -- Action buttons (centered at bottom, primary + secondary hierarchy)
  local pickAllBtn = createSkinButton(f, 160, 24, "PICK ALL AVAILABLE",
    { r = 0.30, g = 0.45, b = 0.15, a = 1 },
    { r = 1, g = 1, b = 1 })
  pickAllBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", -85, 12)
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

  -- Secondary: Reset (smaller, beside Pick All)
  local resetBtn = createSkinButton(f, 70, 24, "Reset",
    { r = 0.20, g = 0.10, b = 0.10, a = 1 },
    { r = 0.95, g = 0.45, b = 0.45 })
  resetBtn:SetPoint("LEFT", pickAllBtn, "RIGHT", 8, 0)
  resetBtn:SetScript("OnClick", function()
    local level = UnitLevel("player")
    if level and level >= MAX_LEVEL and not (ZugZugDB and ZugZugDB.levelingAtMax) then
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

--- Detect which phase (Class/Spec/Hero) a given pick index falls into.
local function phaseForIndex(idx)
  if not levelingOrder or not idx then return "SPEC TREE" end
  local total = #levelingOrder
  -- Rough split: first ~12% class, next ~70% spec, last ~18% hero
  local classEnd = math.floor(total * 0.14)
  local specEnd = math.floor(total * 0.70)
  if idx <= classEnd then return "CLASS TREE" end
  if idx <= specEnd then return "SPEC TREE" end
  return "HERO TREE"
end

local function updateBanner(pick, forceShow)
  local hasPoints = hasUnspentPoints()
  if not forceShow and not hasPoints then return end

  local banner = createBanner()
  local completed, total = countCompleted()
  local pickIdx = findNextUnpurchased()

  -- Refresh class color (in case of spec switch)
  local cr, cg, cb = getClassColor()
  if banner.accent then banner.accent:SetColorTexture(cr, cg, cb, 1) end
  if banner.phaseChip then
    banner.phaseChip:SetBackdropColor(cr * 0.3, cg * 0.3, cb * 0.3, 1)
    banner.phaseChip:SetBackdropBorderColor(cr * 0.7, cg * 0.7, cb * 0.7, 1)
    banner.phaseChip.text:SetTextColor(cr, cg, cb)
    banner.phaseChip.text:SetText(phaseForIndex(pickIdx))
  end
  if banner.talentIconFrame then
    banner.talentIconFrame:SetBackdropColor(cr * 0.4, cg * 0.4, cb * 0.4, 1)
    banner.talentIconFrame:SetBackdropBorderColor(cr, cg, cb, 1)
  end

  -- Spec/level info
  if banner.specInfoText then
    local level = UnitLevel("player") or "?"
    local specName = ZZ.specName or "?"
    local className = ZZ.classToken or ""
    className = className:gsub("_", " "):lower():gsub("(%a)([%w_']*)", function(a,b) return a:upper()..b end)
    banner.specInfoText:SetText("\194\183 " .. specName .. " " .. className .. " \226\128\148 Level " .. tostring(level))
  end

  -- Talent icon (use first letter of talent name as fallback)
  if banner.talentIconFrame and banner.talentIconFrame.text then
    if pick and pick.name then
      banner.talentIconFrame.text:SetText(pick.name:sub(1, 1):upper())
    else
      banner.talentIconFrame.text:SetText("\226\156\147") -- ✓
    end
  end

  -- Title (big talent name)
  if pick then
    banner.titleText:SetText(pick.name or "Unknown")
  else
    banner.titleText:SetText("Build complete!")
  end

  -- Progress bar
  banner.progressText:SetText(completed .. " / " .. total)
  local pct = total > 0 and (completed / total) or 0
  local trackW = banner.barTrack:GetWidth()
  banner.barFill:SetWidth(math.max(1, math.floor(trackW * pct)))

  banner.pickAllBtn:SetEnabled(hasPoints and pick ~= nil)

  -- Show Reset below max level, or at max if user has opted in
  local level = UnitLevel("player")
  local belowMax = level and level < MAX_LEVEL
  local atMaxAllowed = level and level >= MAX_LEVEL and ZugZugDB.levelingAtMax
  banner.resetBtn:SetShown(belowMax or atMaxAllowed)

  banner:Show()
end

--- Returns { completed, total, nextName, phase } for the leveling button inline display.
function ZZ:GetLevelingStatus()
  if not levelingOrder then
    loadOrderForCurrentSpec()
  end
  if not levelingOrder then return nil end
  local completed, total = countCompleted()
  local _, pick = findNextUnpurchased()
  return {
    completed = completed,
    total = total,
    nextName = pick and pick.name,
  }
end

--- Auto-refresh: hides banner when no unspent points, shows when there are.
function ZZ:RefreshLeveling()
  if ZugZugDB.levelingEnabled == false then
    if bannerFrame then bannerFrame:Hide() end
    return
  end

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
  if ZugZugDB.levelingEnabled == false then
    print("|cff00ccffZugZug:|r Leveling guide is disabled in settings.")
    return
  end

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
  updateBanner(pick, true)
end

--- One-shot: reset the tree and apply the full leveling order. Used at max
--- level (where the player typically has no free points) so a single click
--- swaps them into the leveling build for open-world / delve content without
--- needing to go through Reset → Pick All on the banner.
function ZZ:ApplyLevelingBuild()
  if InCombatLockdown() then
    print("|cff00ccffZugZug:|r Cannot change talents in combat.")
    return false
  end

  if not levelingOrder then
    loadOrderForCurrentSpec()
  end
  if not levelingOrder then
    print("|cff00ccffZugZug:|r No leveling data for your spec.")
    return false
  end

  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not specID then return false end
  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return false end
  local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
  if not treeID then return false end

  -- Stage the reset (frees all points but doesn't commit yet)
  if not C_Traits.ResetTree(configID, treeID) then
    print("|cff00ccffZugZug:|r Failed to reset talent tree.")
    return false
  end

  -- Multi-pass staging so dependency chains can resolve.
  local MAX_PASSES = 40
  local staged = 0
  for pass = 1, MAX_PASSES do
    local progress = 0
    local ranksApplied = {}
    for _, pick in ipairs(levelingOrder) do
      local info = C_Traits.GetNodeInfo(configID, pick.nodeID)
      if info then
        local appliedSoFar = ranksApplied[pick.nodeID] or 0
        local neededRank = appliedSoFar + 1
        if (info.currentRank or 0) < neededRank and info.canPurchaseRank then
          if stageNode(configID, pick) then
            progress = progress + 1
            staged = staged + 1
          end
        end
        ranksApplied[pick.nodeID] = neededRank
      end
    end
    if progress == 0 then break end
  end

  if not C_ClassTalents.CommitConfig(configID) then
    print("|cff00ccffZugZug:|r Failed to commit leveling build.")
    return false
  end

  print(string.format("|cff00ccffZugZug:|r Leveling build applied (%d talents).", staged))
  C_Timer.After(0.5, function() ZZ:RefreshLeveling() end)
  return true
end

--- Called when the settings toggle flips. Hides the banner when disabled,
--- or attempts to show it when re-enabled.
function ZZ:UpdateLevelingEnabled()
  if ZugZugDB.levelingEnabled == false then
    if bannerFrame then bannerFrame:Hide() end
  else
    if not levelingOrder then
      loadOrderForCurrentSpec()
    end
    ZZ:RefreshLeveling()
  end
  if ZZ.RefreshUI then ZZ:RefreshUI() end
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
    local level = UnitLevel("player")
    -- At max level, only continue if the user has opted in (open world / delve use).
    if level and level >= MAX_LEVEL and not (ZugZugDB and ZugZugDB.levelingAtMax) then return end
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
