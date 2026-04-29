----------------------------------------------------------------------
-- ZugZug — UI
-- Talent frame integration: two dropdown selectors (Raid & M+) that
-- list builds for your class. Click a build to copy its import string.
----------------------------------------------------------------------

local ZZ = _G.ZugZug

-- Colors
local COLORS = {
  accent    = { r = 0.56, g = 0.75, b = 0.25 },   -- orc green
  raid      = { r = 1, g = 0.75, b = 0.2 },        -- gold
  mp        = { r = 0.4, g = 0.85, b = 0.4 },      -- green
  muted     = { r = 0.5, g = 0.5, b = 0.55 },
  text      = { r = 0.88, g = 0.88, b = 0.9 },
  textBright= { r = 1, g = 1, b = 1 },
  bg        = { r = 0.08, g = 0.08, b = 0.1, a = 0.97 },
  bgLight   = { r = 0.12, g = 0.12, b = 0.14, a = 1 },
  border    = { r = 0.22, g = 0.22, b = 0.26, a = 1 },
  hover     = { r = 0.16, g = 0.16, b = 0.2, a = 1 },
  selected  = { r = 0.2, g = 0.22, b = 0.26, a = 1 },
}

local TREND_ICONS = {
  new  = "|cff4DD8FF NEW|r",
  up   = "|cff4DFF4D \226\150\178|r",
  down = "|cffFF6666 \226\150\188|r",
  flat = "",
}

----------------------------------------------------------------------
-- Spec icon cache — maps "ClassName:SpecName" to icon texture ID
----------------------------------------------------------------------

local specIconCache = {}

local function getSpecIcon(specName)
  if not specName or specName == "" then return nil end

  if specIconCache[specName] then return specIconCache[specName] end

  -- Scan all classes and specs to find the matching spec name
  for classIdx = 1, GetNumClasses() do
    for specIdx = 1, GetNumSpecializationsForClassID(classIdx) do
      local _, name, _, icon = GetSpecializationInfoForClassID(classIdx, specIdx)
      if name == specName then
        specIconCache[specName] = icon
        return icon
      end
    end
  end

  return nil
end

local BAR_HEIGHT = 32
local DROPDOWN_WIDTH = 200
local DROPDOWN_BTN_HEIGHT = 28
local DROPDOWN_ITEM_HEIGHT = 40
local DROPDOWN_GAP = 8
local PADDING = 6

----------------------------------------------------------------------
-- Copy popup — edit box with pre-selected text for Ctrl+C
----------------------------------------------------------------------

local copyPopup = nil

local function createCopyPopup()
  if copyPopup then return copyPopup end

  local f = CreateFrame("Frame", "ZugZugCopyPopup", UIParent, "BackdropTemplate")
  f:SetSize(420, 68)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  f:SetBackdropColor(COLORS.bg.r, COLORS.bg.g, COLORS.bg.b, 0.98)
  f:SetBackdropBorderColor(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b, 0.8)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
  title:SetTextColor(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b)
  f.title = title

  local editBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
  editBox:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -22)
  editBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 8)
  editBox:SetFontObject(ChatFontNormal)
  editBox:SetAutoFocus(true)
  editBox:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  editBox:SetBackdropColor(0.05, 0.05, 0.07, 1)
  editBox:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
  editBox:SetTextInsets(4, 4, 2, 2)
  editBox:SetScript("OnEscapePressed", function() f:Hide() end)
  editBox:SetScript("OnEnterPressed", function() f:Hide() end)
  f.editBox = editBox

  local closeBtn = CreateFrame("Button", nil, f)
  closeBtn:SetSize(18, 18)
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  closeBtn:SetNormalFontObject(GameFontNormalSmall)
  closeBtn:SetText("X")
  closeBtn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
  closeBtn:SetScript("OnClick", function() f:Hide() end)
  closeBtn:SetScript("OnEnter", function(self) self:GetFontString():SetTextColor(1, 0.3, 0.3) end)
  closeBtn:SetScript("OnLeave", function(self) self:GetFontString():SetTextColor(0.5, 0.5, 0.5) end)

  f:Hide()
  copyPopup = f
  return f
end

function ZZ:CopyImportString(importString, label)
  local popup = createCopyPopup()
  popup.title:SetText("ZugZug — " .. label .. "  |cff888888Ctrl+C to copy|r")
  popup.editBox:SetText(importString)
  popup:Show()
  popup.editBox:SetFocus()
  popup.editBox:HighlightText()
end

----------------------------------------------------------------------
-- Talent Apply — parse import string and apply to active config
----------------------------------------------------------------------

local SERIALIZATION_VERSION = 2

----------------------------------------------------------------------
-- Build diff — count how many talents differ from current loadout
----------------------------------------------------------------------

--- Count talent differences between an import string and the current config.
--- Returns nil if the build is for a different spec or can't be compared.
local function countTalentDiff(importString)
  if not importString or importString == "" then return nil end
  if not ExportUtil or not ExportUtil.MakeImportDataStream then return nil end

  local importStream = ExportUtil.MakeImportDataStream(importString)
  if not importStream then return nil end

  local version = importStream:ExtractValue(8)
  if version ~= SERIALIZATION_VERSION then return nil end

  local specID = importStream:ExtractValue(16)

  -- Only compare same-spec builds
  local currentSpecID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not currentSpecID or specID ~= currentSpecID then return nil end

  -- Skip 128-bit tree hash
  for i = 1, 16 do importStream:ExtractValue(8) end

  local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
  if not treeID then return nil end

  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return nil end

  local treeNodes = C_Traits.GetTreeNodes(treeID)
  if not treeNodes or #treeNodes == 0 then return nil end

  local diffCount = 0

  for _, nodeID in ipairs(treeNodes) do
    local isSelected = importStream:ExtractValue(1) == 1
    local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
    local currentRank = nodeInfo and nodeInfo.currentRank or 0

    if isSelected then
      local isPurchased = importStream:ExtractValue(1) == 1
      local ranksPurchased = 0
      local choiceIndex = nil

      if isPurchased then
        local isPartial = importStream:ExtractValue(1) == 1
        if isPartial then
          ranksPurchased = importStream:ExtractValue(6)
        else
          ranksPurchased = nodeInfo and nodeInfo.maxRanks or 1
        end
        local isChoice = importStream:ExtractValue(1) == 1
        if isChoice then
          choiceIndex = importStream:ExtractValue(2)
        end
      end

      if isPurchased then
        -- Node should be purchased in the build
        if currentRank == 0 then
          -- Not purchased currently → differs
          diffCount = diffCount + 1
        elseif ranksPurchased > 0 and currentRank ~= ranksPurchased then
          -- Different rank count
          diffCount = diffCount + 1
        elseif choiceIndex and nodeInfo and nodeInfo.entryIDs then
          -- Choice node — check if the same entry is selected
          local targetEntryID = nodeInfo.entryIDs[choiceIndex + 1]
          local activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
          if targetEntryID and activeEntryID ~= targetEntryID then
            diffCount = diffCount + 1
          end
        end
      end
    else
      -- Node is not selected in the build but is currently purchased
      if currentRank > 0 then
        diffCount = diffCount + 1
      end
    end
  end

  return diffCount
end

--- Parse a talent import string into structured node data.
local function parseImportString(importString)
  if not ExportUtil or not ExportUtil.MakeImportDataStream then
    return nil, "ExportUtil not available"
  end

  local importStream = ExportUtil.MakeImportDataStream(importString)
  if not importStream then return nil, "Invalid import string" end

  -- Header: version (8), specID (16), treeHash (128)
  local version = importStream:ExtractValue(8)
  if version ~= SERIALIZATION_VERSION then
    return nil, "Unsupported version: " .. tostring(version)
  end

  local specID = importStream:ExtractValue(16)
  -- Skip 128-bit tree hash
  for i = 1, 16 do
    importStream:ExtractValue(8)
  end

  local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
  if not treeID then return nil, "No talent tree for spec" end

  local treeNodes = C_Traits.GetTreeNodes(treeID)
  if not treeNodes or #treeNodes == 0 then return nil, "No tree nodes" end

  local entries = {}
  for _, nodeID in ipairs(treeNodes) do
    local isSelected = importStream:ExtractValue(1) == 1
    if isSelected then
      local isPurchased = importStream:ExtractValue(1) == 1
      local ranksPurchased = 0
      local choiceIndex = nil

      if isPurchased then
        local isPartial = importStream:ExtractValue(1) == 1
        if isPartial then
          ranksPurchased = importStream:ExtractValue(6)
        end
        local isChoice = importStream:ExtractValue(1) == 1
        if isChoice then
          choiceIndex = importStream:ExtractValue(2) -- 0-indexed
        end
      end

      entries[#entries + 1] = {
        nodeID = nodeID,
        isPurchased = isPurchased,
        ranksPurchased = ranksPurchased,
        choiceIndex = choiceIndex,
      }
    end
  end

  return {
    specID = specID,
    treeID = treeID,
    entries = entries,
  }
end

----------------------------------------------------------------------
-- Pending spec switch — stores build to apply after spec change
----------------------------------------------------------------------

local pendingBuild = nil -- { importString, label }

--- Find the specIndex (1-based) for a given specID on the player's class.
local function specIndexForID(targetSpecID)
  for i = 1, GetNumSpecializations() do
    local specID = GetSpecializationInfo(i)
    if specID == targetSpecID then return i end
  end
  return nil
end

--- Apply a parsed loadout to the player's active talent config.
function ZZ:ApplyBuild(importString, label)
  local parsed, err = parseImportString(importString)
  if not parsed then
    print("|cff00ccffZugZug:|r Failed to parse: " .. (err or "unknown error"))
    return false
  end

  -- If the build is for a different spec, switch first
  local currentSpecID = PlayerUtil.GetCurrentSpecID()
  if parsed.specID ~= currentSpecID then
    local specIdx = specIndexForID(parsed.specID)
    if not specIdx then
      print("|cff00ccffZugZug:|r Could not find spec for this build.")
      return false
    end
    pendingBuild = { importString = importString, label = label }
    print("|cff00ccffZugZug:|r Switching spec to apply " .. (label or "build") .. "...")
    if InCombatLockdown() then
      print("|cff00ccffZugZug:|r Cannot switch spec in combat.")
      pendingBuild = nil
      return false
    end
    -- Close the talent frame — Blizzard blocks spec switches while it's open
    if PlayerSpellsFrame and PlayerSpellsFrame:IsShown() then
      HideUIPanel(PlayerSpellsFrame)
    end
    C_SpecializationInfo.SetSpecialization(specIdx)
    return true
  end

  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then
    print("|cff00ccffZugZug:|r No active talent config.")
    return false
  end

  -- Reset the tree
  if not C_Traits.ResetTree(configID, parsed.treeID) then
    print("|cff00ccffZugZug:|r Failed to reset talent tree.")
    return false
  end

  -- Apply all entries in multiple passes.
  -- Each pass attempts selections and one rank purchase per node.
  -- Multiple passes handle dependency chains — hero subtree must be
  -- selected before hero nodes can be purchased, class nodes before
  -- spec nodes, etc.
  local MAX_PASSES = 40
  for pass = 1, MAX_PASSES do
    local progressThisPass = 0

    for _, entry in ipairs(parsed.entries) do
      local nodeInfo = C_Traits.GetNodeInfo(configID, entry.nodeID)
      if nodeInfo and nodeInfo.ID ~= 0 then
        -- Set selection for any choice/subtree node every pass,
        -- in case it wasn't accepted earlier due to missing prereqs
        if entry.choiceIndex and nodeInfo.entryIDs then
          local entryID = nodeInfo.entryIDs[entry.choiceIndex + 1]
          if entryID then
            local activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
            if activeEntryID ~= entryID then
              if C_Traits.SetSelection(configID, entry.nodeID, entryID) then
                progressThisPass = progressThisPass + 1
              end
            end
          end
        end

        -- Purchase one rank per pass per node (not all at once).
        -- This lets dependencies resolve between ranks.
        if entry.isPurchased then
          local targetRanks = entry.ranksPurchased > 0 and entry.ranksPurchased or nodeInfo.maxRanks
          local currentRanks = nodeInfo.currentRank or 0
          if currentRanks < targetRanks then
            if C_Traits.PurchaseRank(configID, entry.nodeID) then
              progressThisPass = progressThisPass + 1
            end
          end
        end
      end
    end

    if progressThisPass == 0 then break end
  end

  -- Commit
  if not C_Traits.ConfigHasStagedChanges(configID) then
    print("|cff00ccffZugZug:|r Build is already active (no changes needed).")
    return true
  end

  if C_ClassTalents.CommitConfig(configID) then
    print("|cff00ccffZugZug:|r Applying " .. (label or "build") .. "...")
    -- Auto-rename the loadout to the build label
    if label and C_ClassTalents.RenameConfig then
      C_ClassTalents.RenameConfig(configID, label)
    end
    return true
  end

  print("|cff00ccffZugZug:|r Failed to commit. Try with the talent frame open.")
  return false
end

--- Apply a pending build after a spec switch completes.
function ZZ:ApplyPendingBuild()
  if not pendingBuild then return end
  local build = pendingBuild
  pendingBuild = nil
  print("|cff00ccffZugZug:|r Spec switched — applying " .. (build.label or "build") .. "...")
  ZZ:ApplyBuild(build.importString, build.label)
end

----------------------------------------------------------------------
-- Dropdown menu (shared by both Raid and M+)
----------------------------------------------------------------------

local activeDropdown = nil -- track which dropdown is open

local function closeActiveDropdown()
  if activeDropdown then
    activeDropdown:Hide()
    activeDropdown = nil
  end
end

local function createDropdownItem(parent, index)
  local item = CreateFrame("Button", nil, parent, "BackdropTemplate")
  item:SetHeight(DROPDOWN_ITEM_HEIGHT)
  item:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
  })
  item:SetBackdropColor(0, 0, 0, 0)

  -- Left accent bar
  local accentBar = item:CreateTexture(nil, "OVERLAY")
  accentBar:SetSize(3, DROPDOWN_ITEM_HEIGHT - 8)
  accentBar:SetPoint("LEFT", item, "LEFT", 0, 0)
  item.accentBar = accentBar

  -- Spec icon
  local specIcon = item:CreateTexture(nil, "ARTWORK")
  specIcon:SetSize(18, 18)
  specIcon:SetPoint("LEFT", item, "LEFT", 8, 0)
  item.specIcon = specIcon

  -- Favorite star (right side)
  local starBtn = CreateFrame("Button", nil, item)
  starBtn:SetSize(16, 16)
  starBtn:SetPoint("RIGHT", item, "RIGHT", -6, 0)
  local starText = starBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  starText:SetPoint("CENTER")
  starText:SetText("\226\152\134") -- ☆
  starText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  starBtn.starText = starText
  item.starBtn = starBtn

  starBtn:SetScript("OnClick", function()
    if not item.importString then return end
    ZugZugDB.favorites = ZugZugDB.favorites or {}
    if ZugZugDB.favorites[item.importString] then
      ZugZugDB.favorites[item.importString] = nil
    else
      ZugZugDB.favorites[item.importString] = true
    end
    -- Refresh the dropdown to re-sort
    if item.contentType then
      ZZ:PopulateDropdown(item.contentType)
    end
  end)
  starBtn:SetScript("OnEnter", function(self)
    self.starText:SetTextColor(1, 0.85, 0.2)
    item:SetBackdropColor(COLORS.hover.r, COLORS.hover.g, COLORS.hover.b, 1)
  end)
  starBtn:SetScript("OnLeave", function(self)
    local isFav = ZugZugDB.favorites and ZugZugDB.favorites[item.importString]
    if isFav then
      self.starText:SetTextColor(1, 0.85, 0.2)
    else
      self.starText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
    end
    item:SetBackdropColor(0, 0, 0, 0)
  end)

  -- Top line: spec + hero tree
  local specText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  specText:SetPoint("TOPLEFT", item, "TOPLEFT", 30, -5)
  specText:SetPoint("TOPRIGHT", item, "TOPRIGHT", -24, -5)
  specText:SetJustifyH("LEFT")
  specText:SetWordWrap(false)
  item.specText = specText

  -- Bottom line: label + popularity + trend
  local metaText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  metaText:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 30, 5)
  metaText:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -8, 5)
  metaText:SetJustifyH("LEFT")
  metaText:SetWordWrap(false)
  metaText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  item.metaText = metaText

  -- Hover
  item:SetScript("OnEnter", function(self)
    self:SetBackdropColor(COLORS.hover.r, COLORS.hover.g, COLORS.hover.b, 1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Click to apply build", COLORS.text.r, COLORS.text.g, COLORS.text.b)
    GameTooltip:AddLine("Shift+click to copy import string", COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
    GameTooltip:AddLine("Click star to pin/unpin", COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
    -- Show talent diff count for same-spec builds
    local diff = countTalentDiff(self.importString)
    if diff then
      if diff == 0 then
        GameTooltip:AddLine("Currently active", 0.36, 0.79, 0.65)
      else
        GameTooltip:AddLine(diff .. " talent " .. (diff == 1 and "change" or "changes"), 0.95, 0.75, 0.3)
      end
    end
    if self.contextList and #self.contextList > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Best for:", 1, 0.82, 0.2)
      for _, name in ipairs(self.contextList) do
        GameTooltip:AddLine("  " .. name, COLORS.text.r, COLORS.text.g, COLORS.text.b)
      end
    end
    GameTooltip:Show()
  end)
  item:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0, 0, 0, 0)
    GameTooltip:Hide()
  end)

  -- Click: apply build. Shift+click: copy import string.
  item:RegisterForClicks("LeftButtonUp")
  item:SetScript("OnClick", function(self)
    if not self.importString or self.importString == "" then
      print("|cff00ccffZugZug:|r No import string for this build.")
      return
    end
    if IsShiftKeyDown() then
      ZZ:CopyImportString(self.importString, self.buildLabel or "build")
    else
      ZZ:ApplyBuild(self.importString, self.buildLabel or "build")
    end
    closeActiveDropdown()
  end)

  return item
end

local function populateDropdownItem(item, build, contentType, sectionColor, isCurrentSpec)
  -- Set spec icon
  local icon = getSpecIcon(build.spec)
  if icon then
    item.specIcon:SetTexture(icon)
    item.specIcon:Show()
  else
    item.specIcon:Hide()
  end

  local specHero = build.spec or ""
  if build.hero and build.hero ~= "" then
    specHero = specHero .. "  |cff888888" .. build.hero .. "|r"
  end
  item.specText:SetText(specHero)
  if isCurrentSpec then
    item.specText:SetTextColor(COLORS.textBright.r, COLORS.textBright.g, COLORS.textBright.b)
  else
    item.specText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  end

  local trendStr = TREND_ICONS[build.trend] or ""
  local meta = build.label .. "  |cff888888" .. build.popularity .. "%|r" .. trendStr
  item.metaText:SetText(meta)

  item.accentBar:SetColorTexture(sectionColor.r, sectionColor.g, sectionColor.b, isCurrentSpec and 0.8 or 0.3)

  item.importString = build.importString
  item.buildLabel = build.label
  item.contentType = contentType

  if contentType == "raid" then
    item.contextList = build.bosses
  else
    item.contextList = build.dungeons
  end

  -- Update star visual
  local isFav = ZugZugDB.favorites and ZugZugDB.favorites[build.importString]
  if isFav then
    item.starBtn.starText:SetText("\226\152\133") -- ★
    item.starBtn.starText:SetTextColor(1, 0.85, 0.2)
  else
    item.starBtn.starText:SetText("\226\152\134") -- ☆
    item.starBtn.starText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  end

  item:Show()
end

local function createDropdownMenu(name)
  local menu = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  menu:SetBackdropColor(COLORS.bg.r, COLORS.bg.g, COLORS.bg.b, COLORS.bg.a)
  menu:SetBackdropBorderColor(COLORS.border.r, COLORS.border.g, COLORS.border.b, 1)

  menu.items = {}
  menu:Hide()
  return menu
end

----------------------------------------------------------------------
-- Dropdown trigger buttons
----------------------------------------------------------------------

local function createDropdownButton(parent, label, color)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(DROPDOWN_WIDTH, DROPDOWN_BTN_HEIGHT)
  btn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  btn:SetBackdropColor(COLORS.bgLight.r, COLORS.bgLight.g, COLORS.bgLight.b, 1)
  btn:SetBackdropBorderColor(COLORS.border.r, COLORS.border.g, COLORS.border.b, 1)

  -- Section label (left)
  local labelText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  labelText:SetPoint("LEFT", btn, "LEFT", 8, 0)
  labelText:SetTextColor(color.r, color.g, color.b)
  labelText:SetText(label)
  btn.labelText = labelText

  -- Setting / subtitle (right)
  local settingText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  settingText:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
  settingText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  btn.settingText = settingText

  -- Arrow
  local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  arrow:SetPoint("RIGHT", settingText, "LEFT", -4, 0)
  arrow:SetText("\226\150\188") -- ▼
  arrow:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  btn.arrow = arrow

  -- Hover + tooltip
  btn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(COLORS.hover.r, COLORS.hover.g, COLORS.hover.b, 1)
    self:SetBackdropBorderColor(color.r, color.g, color.b, 0.5)
    if self.tooltipHint then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.tooltipHint, COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
      GameTooltip:Show()
    end
  end)
  btn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(COLORS.bgLight.r, COLORS.bgLight.g, COLORS.bgLight.b, 1)
    self:SetBackdropBorderColor(COLORS.border.r, COLORS.border.g, COLORS.border.b, 1)
    GameTooltip:Hide()
  end)

  return btn
end

----------------------------------------------------------------------
-- Main bar frame
----------------------------------------------------------------------

local bar = nil
local raidMenu = nil
local mpMenu = nil

local function createBar(parent)
  if bar then return bar end

  local HEADER_HEIGHT = 28

  bar = CreateFrame("Frame", "ZugZugBar", parent, "BackdropTemplate")
  bar:SetHeight(BAR_HEIGHT + HEADER_HEIGHT)
  bar:SetWidth(DROPDOWN_WIDTH * 2 + DROPDOWN_GAP + PADDING * 2)
  bar:SetFrameStrata("HIGH")
  bar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  bar:SetBackdropColor(COLORS.bg.r, COLORS.bg.g, COLORS.bg.b, COLORS.bg.a)
  bar:SetBackdropBorderColor(COLORS.border.r, COLORS.border.g, COLORS.border.b, COLORS.border.a)

  -- Header text
  local header = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  header:SetPoint("TOP", bar, "TOP", 0, -6)
  header:SetText("|cff8fbf3fZUGZUG.info|r  |cff888888Builds|r")
  bar.header = header

  -- Raid dropdown button
  local raidBtn = createDropdownButton(bar, "RAID", COLORS.raid)
  raidBtn:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", PADDING, PADDING + 2)
  raidBtn.tooltipHint = "Right-click to cycle difficulty"
  bar.raidBtn = raidBtn

  -- M+ dropdown button
  local mpBtn = createDropdownButton(bar, "M+", COLORS.mp)
  mpBtn:SetPoint("LEFT", raidBtn, "RIGHT", DROPDOWN_GAP, 0)
  mpBtn.tooltipHint = "Right-click to cycle key level"
  bar.mpBtn = mpBtn

  -- Menus
  raidMenu = createDropdownMenu("ZugZugRaidMenu")
  mpMenu = createDropdownMenu("ZugZugMPMenu")

  -- Raid button click: toggle dropdown + right-click cycles difficulty
  raidBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  raidBtn:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      if ZugZugDB.raidDifficulty == "mythic" then
        ZugZugDB.raidDifficulty = "heroic"
      else
        ZugZugDB.raidDifficulty = "mythic"
      end
      ZZ:RefreshUI()
      return
    end
    if raidMenu:IsShown() then
      closeActiveDropdown()
    else
      closeActiveDropdown()
      ZZ:PopulateDropdown("raid")
      raidMenu:ClearAllPoints()
      raidMenu:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
      raidMenu:Show()
      activeDropdown = raidMenu
    end
  end)

  -- M+ button click: toggle dropdown + right-click cycles key level
  local KEY_CYCLE = { "all", "15+", "18+", "20+" }
  mpBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mpBtn:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      local cur = ZugZugDB.mpBucket or "all"
      for i, v in ipairs(KEY_CYCLE) do
        if v == cur then
          ZugZugDB.mpBucket = KEY_CYCLE[(i % #KEY_CYCLE) + 1]
          break
        end
      end
      ZZ:RefreshUI()
      return
    end
    if mpMenu:IsShown() then
      closeActiveDropdown()
    else
      closeActiveDropdown()
      ZZ:PopulateDropdown("mp")
      mpMenu:ClearAllPoints()
      mpMenu:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
      mpMenu:Show()
      activeDropdown = mpMenu
    end
  end)

  -- Leveling button — only visible below max level
  local levelBtn = CreateFrame("Button", nil, bar, "BackdropTemplate")
  levelBtn:SetSize(90, BAR_HEIGHT - 4)
  levelBtn:SetPoint("LEFT", mpBtn, "RIGHT", DROPDOWN_GAP, 0)
  levelBtn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  levelBtn:SetBackdropColor(0.2, 0.5, 0.2, 0.9)
  levelBtn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

  local levelText = levelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  levelText:SetPoint("CENTER")
  levelText:SetText("Leveling Guide")
  levelText:SetTextColor(0.85, 1, 0.85)
  levelBtn.label = levelText

  levelBtn:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b, 1)
  end)
  levelBtn:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
  end)
  levelBtn:SetScript("OnClick", function()
    if ZZ.ToggleLevelingBanner then
      ZZ:ToggleLevelingBanner()
    end
  end)
  levelBtn:Hide()
  bar.levelBtn = levelBtn

  -- Close dropdown when clicking elsewhere
  bar:SetScript("OnHide", function()
    closeActiveDropdown()
  end)

  bar:Hide()
  return bar
end

----------------------------------------------------------------------
-- Populate a dropdown with builds
----------------------------------------------------------------------

function ZZ:PopulateDropdown(contentType)
  local menu, builds, sectionColor
  local raidBuilds, mpBuilds = ZZ:GetCurrentBuilds()

  if contentType == "raid" then
    menu = raidMenu
    builds = raidBuilds
    sectionColor = COLORS.raid
  else
    menu = mpMenu
    builds = mpBuilds
    sectionColor = COLORS.mp
  end

  -- Hide existing items
  for _, item in ipairs(menu.items) do
    item:Hide()
  end

  -- Sort: starred first, then current spec, then by popularity descending
  if builds and #builds > 0 then
    local favs = ZugZugDB.favorites or {}
    local specName = ZZ.specName
    local sorted = {}
    for _, b in ipairs(builds) do sorted[#sorted + 1] = b end
    table.sort(sorted, function(a, b)
      local aFav = favs[a.importString] and true or false
      local bFav = favs[b.importString] and true or false
      if aFav ~= bFav then return aFav end
      local aSpec = (a.spec == specName)
      local bSpec = (b.spec == specName)
      if aSpec ~= bSpec then return aSpec end
      return (a.popularity or 0) > (b.popularity or 0)
    end)
    builds = sorted
  end

  if not builds or #builds == 0 then
    menu:SetSize(DROPDOWN_WIDTH, 30)
    if not menu.emptyText then
      menu.emptyText = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      menu.emptyText:SetPoint("CENTER")
      menu.emptyText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
    end
    menu.emptyText:SetText("No builds available")
    menu.emptyText:Show()
    return
  end
  if menu.emptyText then menu.emptyText:Hide() end

  -- Hide existing separators
  if menu.separators then
    for _, sep in ipairs(menu.separators) do sep:Hide() end
  else
    menu.separators = {}
  end

  local yOffset = -PADDING
  local lastSpec = nil
  local sepIdx = 0
  for i, build in ipairs(builds) do
    -- Add a separator line between different specs
    if lastSpec and build.spec ~= lastSpec then
      sepIdx = sepIdx + 1
      if not menu.separators[sepIdx] then
        local sep = menu:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetColorTexture(COLORS.border.r, COLORS.border.g, COLORS.border.b, 0.6)
        menu.separators[sepIdx] = sep
      end
      local sep = menu.separators[sepIdx]
      sep:ClearAllPoints()
      sep:SetPoint("TOPLEFT", menu, "TOPLEFT", PADDING + 8, yOffset - 2)
      sep:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PADDING - 8, yOffset - 2)
      sep:Show()
      yOffset = yOffset - 5
    end
    lastSpec = build.spec

    if not menu.items[i] then
      menu.items[i] = createDropdownItem(menu, i)
    end
    local item = menu.items[i]
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", menu, "TOPLEFT", PADDING, yOffset)
    item:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PADDING, yOffset)

    local isCurrentSpec = (build.spec == ZZ.specName)
    populateDropdownItem(item, build, contentType, sectionColor, isCurrentSpec)
    yOffset = yOffset - DROPDOWN_ITEM_HEIGHT
  end

  menu:SetSize(DROPDOWN_WIDTH, -yOffset + PADDING)
end

----------------------------------------------------------------------
-- Get or create the bar (used by minimap button for standalone mode)
----------------------------------------------------------------------

function ZZ:GetOrCreateBar()
  if not bar then
    createBar(UIParent)
    bar:Hide()
  end
  return bar
end

----------------------------------------------------------------------
-- Refresh bar labels
----------------------------------------------------------------------

function ZZ:RefreshUI()
  if not bar then return end

  -- Update button labels
  local diff = ZugZugDB.raidDifficulty or "mythic"
  bar.raidBtn.settingText:SetText(diff:sub(1,1):upper() .. diff:sub(2))

  local bucket = ZugZugDB.mpBucket or "all"
  bar.mpBtn.settingText:SetText(bucket)

  -- Show leveling button only below max level
  local level = UnitLevel("player")
  local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 80
  local showLeveling = level and level < maxLevel and ZugZugLevelingData ~= nil
  if bar.levelBtn then
    bar.levelBtn:SetShown(showLeveling)
    -- Widen bar to fit the leveling button
    if showLeveling then
      bar:SetWidth(DROPDOWN_WIDTH * 2 + DROPDOWN_GAP * 2 + 90 + PADDING * 2)
    else
      bar:SetWidth(DROPDOWN_WIDTH * 2 + DROPDOWN_GAP + PADDING * 2)
    end
  end

  -- If a dropdown is open, refresh it
  if activeDropdown == raidMenu and raidMenu:IsShown() then
    ZZ:PopulateDropdown("raid")
  elseif activeDropdown == mpMenu and mpMenu:IsShown() then
    ZZ:PopulateDropdown("mp")
  end
end

----------------------------------------------------------------------
-- Hook into talent frame
----------------------------------------------------------------------

local function hookTalentFrame()
  local function attachToFrame(talentFrame)
    if talentFrame.zugzugHooked then return end
    talentFrame.zugzugHooked = true

    createBar(talentFrame)

    -- Anchor centered below the talent frame
    bar:SetPoint("TOP", talentFrame, "BOTTOM", 0, -4)

    -- Show/hide with talent frame
    talentFrame:HookScript("OnShow", function()
      bar:Show()
      ZZ:RefreshUI()
    end)
    talentFrame:HookScript("OnHide", function()
      bar:Hide()
    end)

    -- If talent frame is already visible, show now
    if talentFrame:IsShown() then
      bar:Show()
      ZZ:RefreshUI()
    end
  end

  -- Try to hook immediately if the frame exists
  if PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame then
    attachToFrame(PlayerSpellsFrame.TalentsFrame)
  end

  -- Also hook when Blizzard_PlayerSpells loads (lazy load)
  local hookFrame = CreateFrame("Frame")
  hookFrame:RegisterEvent("ADDON_LOADED")
  hookFrame:SetScript("OnEvent", function(_, _, addonName)
    if addonName == "Blizzard_PlayerSpells" then
      C_Timer.After(0, function()
        if PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame then
          attachToFrame(PlayerSpellsFrame.TalentsFrame)
        end
      end)
      hookFrame:UnregisterEvent("ADDON_LOADED")
    end
  end)
end

-- Initialize UI hooks after our addon loads
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
  hookTalentFrame()

  -- /zz show opens the bar standalone (centered) if talent frame isn't open
  local origHandler = SlashCmdList["ZUGZUG"]
  SlashCmdList["ZUGZUG"] = function(msg)
    local cmd = msg:match("^(%S+)") or ""
    cmd = cmd:lower()

    if cmd == "show" or cmd == "toggle" then
      if bar then
        if bar:IsShown() then
          bar:Hide()
        else
          bar:ClearAllPoints()
          bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 120)
          bar:Show()
          ZZ:RefreshUI()
        end
      end
      return
    end

    if origHandler then
      origHandler(msg)
    end
  end
end)
