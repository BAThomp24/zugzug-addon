----------------------------------------------------------------------
-- ZugZug Specs — UI
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

-- The bare specialization globals were deprecated in 11.1.7 in favor of
-- C_SpecializationInfo; prefer the namespaced versions so the addon
-- survives the shims being removed.
local GetNumSpecsForClass = (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID) or GetNumSpecializationsForClassID
local GetSpecInfoForClass = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForClassID) or GetSpecializationInfoForClassID
local GetNumSpecs = (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializations) or GetNumSpecializations
local GetSpecInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo

local GetSpecInfoByID = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoByID) or GetSpecializationInfoByID

local function getSpecIcon(specName, specId)
  -- Fast path: numeric spec ID (locale-independent, ships with fresh data).
  if specId and GetSpecInfoByID then
    local cached = specIconCache["id:" .. specId]
    if cached then return cached end
    local ok, _, _, _, icon = pcall(GetSpecInfoByID, specId)
    if ok and icon then
      specIconCache["id:" .. specId] = icon
      return icon
    end
  end

  if not specName or specName == "" then return nil end
  if specIconCache[specName] then return specIconCache[specName] end

  -- Fallback: scan all classes and specs to find the matching spec name
  for classIdx = 1, GetNumClasses() do
    for specIdx = 1, GetNumSpecsForClass(classIdx) do
      local _, name, _, icon = GetSpecInfoForClass(classIdx, specIdx)
      if name == specName then
        specIconCache[specName] = icon
        return icon
      end
    end
  end

  return nil
end

local BAR_HEIGHT = 60
local HEADER_HEIGHT = 36
local DROPDOWN_WIDTH = 185
local LEVELING_BTN_WIDTH = 190
local DROPDOWN_BTN_HEIGHT = 60
local DROPDOWN_ITEM_HEIGHT = 50
local DROPDOWN_GAP = 6
local PADDING = 10

-- Returns the player's class color {r, g, b} or accent green as fallback
local function getClassColor()
  local token = _G.ZugZug and _G.ZugZug.classToken
  local color = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  if color then return color.r, color.g, color.b end
  return 0.56, 0.75, 0.25
end

-- Returns popularity pill colors: { bg = {r,g,b}, edge = {r,g,b}, text = {r,g,b} }
local function getPopularityPill(pct)
  if not pct then pct = 0 end
  if pct >= 40 then
    return { bgR=0.12, bgG=0.24, bgB=0.12, edR=0.23, edG=0.43, edB=0.23, txR=0.40, txG=0.85, txB=0.40 }
  elseif pct >= 20 then
    return { bgR=0.16, bgG=0.12, bgB=0.08, edR=0.35, edG=0.27, edB=0.13, txR=1.00, txG=0.75, txB=0.20 }
  else
    return { bgR=0.16, bgG=0.08, bgB=0.08, edR=0.35, edG=0.13, edB=0.13, txR=0.88, txG=0.42, txB=0.42 }
  end
end

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
  popup.title:SetText("ZugZug Specs — " .. label .. "  |cff888888Ctrl+C to copy|r")
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

-- Expose for Suggest.lua so it can detect whether the player is actually on a build
-- (not just on the same spec + hero).
ZZ.CountTalentDiff = countTalentDiff

--- Structured sibling of countTalentDiff: list HOW the build differs from
--- the player's CURRENT talents, for the suggest popup's diff rows. Each
--- row is { pick = {name, note?}, drop = {name} } — a choice-node change
--- carries both sides (rendered "Swap to X (was Y)"); additions/removals
--- are lone picks/drops; a rank change is a pick with note "1/2".
--- Returns nil when the build is for another spec or can't be parsed
--- (callers fall back to spec/hero heuristics), {} when identical.
function ZZ:DiffAgainstCurrent(importString)
  if not importString or importString == "" then return nil end
  if not (ExportUtil and ExportUtil.MakeImportDataStream) then return nil end
  local importStream = ExportUtil.MakeImportDataStream(importString)
  if not importStream then return nil end

  local version = importStream:ExtractValue(8)
  if version ~= SERIALIZATION_VERSION then return nil end
  local specID = importStream:ExtractValue(16)
  local currentSpecID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not currentSpecID or specID ~= currentSpecID then return nil end
  for i = 1, 16 do importStream:ExtractValue(8) end

  local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
  local configID = C_ClassTalents.GetActiveConfigID()
  if not (treeID and configID) then return nil end
  local treeNodes = C_Traits.GetTreeNodes(treeID)
  if not treeNodes or #treeNodes == 0 then return nil end

  local function entryName(entryID)
    local ei = entryID and C_Traits.GetEntryInfo(configID, entryID)
    local di = ei and ei.definitionID and C_Traits.GetDefinitionInfo(ei.definitionID)
    if not di then return nil end
    if di.overrideName and di.overrideName ~= "" then return di.overrideName end
    local sp = di.spellID and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(di.spellID)
    return sp and sp.name
  end

  local rows = {}
  for _, nodeID in ipairs(treeNodes) do
    local isSelected = importStream:ExtractValue(1) == 1
    local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
    local currentRank = nodeInfo and nodeInfo.currentRank or 0

    if isSelected then
      local isPurchased = importStream:ExtractValue(1) == 1
      local ranksPurchased, choiceIndex = 0, nil
      if isPurchased then
        local isPartial = importStream:ExtractValue(1) == 1
        if isPartial then
          ranksPurchased = importStream:ExtractValue(6)
        else
          ranksPurchased = nodeInfo and nodeInfo.maxRanks or 1
        end
        local isChoice = importStream:ExtractValue(1) == 1
        if isChoice then choiceIndex = importStream:ExtractValue(2) end
      end

      if isPurchased and nodeInfo then
        if choiceIndex and nodeInfo.entryIDs then
          -- Choice node: differs when a different entry is active.
          local targetEntryID = nodeInfo.entryIDs[choiceIndex + 1]
          local activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
          if targetEntryID and activeEntryID ~= targetEntryID then
            local pickName = entryName(targetEntryID)
            local dropName = currentRank > 0 and entryName(activeEntryID) or nil
            if pickName then
              rows[#rows + 1] = {
                pick = { name = pickName },
                drop = dropName and { name = dropName } or nil,
              }
            end
          end
        elseif currentRank == 0 then
          local nm = entryName(nodeInfo.entryIDs and nodeInfo.entryIDs[1])
          if nm then rows[#rows + 1] = { pick = { name = nm } } end
        elseif ranksPurchased > 0 and currentRank ~= ranksPurchased then
          local nm = entryName(nodeInfo.entryIDs and nodeInfo.entryIDs[1])
          if nm then
            rows[#rows + 1] = { pick = {
              name = nm,
              note = ranksPurchased .. "/" .. (nodeInfo.maxRanks or ranksPurchased),
            } }
          end
        end
      end
    elseif nodeInfo and currentRank > 0 then
      -- Purchased now, absent in the build → drop. Granted (free) nodes
      -- have currentRank > 0 with nothing purchased — never list those.
      local purchased = nodeInfo.ranksPurchased
      if purchased == nil or purchased > 0 then
        local activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
        local nm = entryName(activeEntryID or (nodeInfo.entryIDs and nodeInfo.entryIDs[1]))
        if nm then rows[#rows + 1] = { drop = { name = nm } } end
      end
    end
  end
  return rows
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
  for i = 1, GetNumSpecs() do
    local specID = GetSpecInfo(i)
    if specID == targetSpecID then return i end
  end
  return nil
end

----------------------------------------------------------------------
-- Dedicated "ZugZug" loadout + undo snapshot
----------------------------------------------------------------------

local LOADOUT_NAME = "ZugZug"

--- Find this spec's saved loadout named "ZugZug", if any.
local function findZugZugConfigID(specID)
  if not (C_ClassTalents and C_ClassTalents.GetConfigIDsBySpecID) then return nil end
  local ok, ids = pcall(C_ClassTalents.GetConfigIDsBySpecID, specID)
  if not ok or type(ids) ~= "table" then return nil end
  for _, id in ipairs(ids) do
    local okI, info = pcall(C_Traits.GetConfigInfo, id)
    if okI and info and info.name == LOADOUT_NAME then return id end
  end
  return nil
end

--- True when a C_ClassTalents.LoadConfig result means "accepted".
local function loadConfigAccepted(result)
  if result == nil or result == false then return false end
  local errVal = (Enum and Enum.LoadConfigResult and Enum.LoadConfigResult.Error) or 0
  return result ~= errVal
end

--- Snapshot the active tree (and which saved loadout was selected) so
--- /zz undo can restore it after an apply/swap/reset. Persisted in the
--- SavedVariables so it survives /reload.
function ZZ:CaptureUndoSnapshot(configID, action)
  if not (configID and C_Traits and C_Traits.GenerateImportString) then return end
  local ok, str = pcall(C_Traits.GenerateImportString, configID)
  if not ok or type(str) ~= "string" or str == "" then return end
  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  local selectedID
  if specID and C_ClassTalents.GetLastSelectedSavedConfigID then
    local okS, sel = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
    if okS then selectedID = sel end
  end
  ZugZugDB.undoSnapshot = {
    importString = str,
    specID = specID,
    prevConfigID = selectedID,
    action = action,
    at = time(),
  }
end

-- Loadout serialization bit widths (match Blizzard_ClassTalentImportExport).
local BIT_VERSION, BIT_SPECID, BIT_RANKS = 8, 16, 6

--- Parse an import string into per-node "indexInfo" aligned to the tree's
--- GetTreeNodes(treeID) order — the exact shape Blizzard's
--- ConvertToImportLoadoutEntryInfo consumes. Returns nil on any mismatch.
local function parseLoadoutContent(importString, treeID)
  if not (ExportUtil and ExportUtil.MakeImportDataStream) then return nil end
  local stream = ExportUtil.MakeImportDataStream(importString)
  if not stream then return nil end
  local version = stream:ExtractValue(BIT_VERSION)
  local cur = C_Traits.GetLoadoutSerializationVersion and C_Traits.GetLoadoutSerializationVersion()
  if cur and version ~= cur then return nil end
  stream:ExtractValue(BIT_SPECID)             -- specID
  for _ = 1, 16 do stream:ExtractValue(8) end -- 128-bit tree hash
  local treeNodes = C_Traits.GetTreeNodes(treeID)
  if not treeNodes or #treeNodes == 0 then return nil end
  local content = {}
  for i = 1, #treeNodes do
    local isSelected = stream:ExtractValue(1) == 1
    local isPurchased, isPartial, partialRanks, isChoice, choiceSel = false, false, 0, false, 0
    if isSelected then
      isPurchased = stream:ExtractValue(1) == 1
      if isPurchased then
        isPartial = stream:ExtractValue(1) == 1
        if isPartial then partialRanks = stream:ExtractValue(BIT_RANKS) end
        isChoice = stream:ExtractValue(1) == 1
        if isChoice then choiceSel = stream:ExtractValue(2) end
      end
    end
    content[i] = {
      isNodeSelected = isSelected,
      isNodeGranted = isSelected and not isPurchased,
      isPartiallyRanked = isPartial,
      partialRanksPurchased = partialRanks,
      isChoiceNode = isChoice,
      choiceNodeSelection = choiceSel + 1, -- back to 1-based
    }
  end
  return content, treeNodes
end

--- Port of CreateImportLoadoutEntryInfoFromSingleNode.
local function entryFromSingleNode(results, treeNodeInfo, indexInfo)
  if not (treeNodeInfo and indexInfo and indexInfo.isNodeSelected) then return end
  local r = { nodeID = treeNodeInfo.ID }
  r.ranksGranted = indexInfo.isNodeGranted and 1 or 0
  if indexInfo.isNodeSelected and not indexInfo.isNodeGranted then
    r.ranksPurchased = indexInfo.isPartiallyRanked and indexInfo.partialRanksPurchased or treeNodeInfo.maxRanks
  else
    r.ranksPurchased = 0
  end
  local entryIDs = treeNodeInfo.entryIDs
  if indexInfo.isChoiceNode and indexInfo.choiceNodeSelection and entryIDs then
    r.selectionEntryID = entryIDs[indexInfo.choiceNodeSelection]
  elseif treeNodeInfo.activeEntry then
    r.selectionEntryID = treeNodeInfo.activeEntry.entryID
  end
  if not r.selectionEntryID and entryIDs then r.selectionEntryID = entryIDs[1] end
  if r.selectionEntryID ~= nil then table.insert(results, r) end
end

--- Port of CreateImportLoadoutEntryInfoFromTieredNode (multi-entry nodes:
--- ranks fill each entryID in order).
local function entryFromTieredNode(results, configID, treeNodeInfo, indexInfo)
  if not (treeNodeInfo and indexInfo and indexInfo.isNodeSelected) then return end
  local total = 0
  if not indexInfo.isNodeGranted then
    total = indexInfo.isPartiallyRanked and indexInfo.partialRanksPurchased or treeNodeInfo.maxRanks
  end
  local remaining = total
  for index, entryID in ipairs(treeNodeInfo.entryIDs or {}) do
    local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
    if entryInfo then
      local ranksForThis = math.min(remaining, entryInfo.maxRanks or 0)
      local isGranted = indexInfo.isNodeGranted and (index == 1)
      if ranksForThis > 0 or isGranted then
        table.insert(results, {
          nodeID = treeNodeInfo.ID,
          ranksGranted = isGranted and 1 or 0,
          ranksPurchased = ranksForThis,
          selectionEntryID = entryID,
        })
      end
      remaining = remaining - ranksForThis
    end
  end
end

--- Port of ConvertToImportLoadoutEntryInfo.
local function convertToImportEntryInfo(configID, treeID, content)
  local results = {}
  local treeNodes = C_Traits.GetTreeNodes(treeID)
  for index, nodeID in ipairs(treeNodes) do
    local indexInfo = content[index]
    local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
    if nodeInfo then
      if Enum and Enum.TraitNodeType and nodeInfo.type == Enum.TraitNodeType.Tiered then
        entryFromTieredNode(results, configID, nodeInfo, indexInfo)
      else
        entryFromSingleNode(results, nodeInfo, indexInfo)
      end
    end
  end
  return results
end

-- The saved-loadout create is async: C_ClassTalents.ImportLoadout fires
-- TRAIT_CONFIG_CREATED, and a config with purchased ranks may not be
-- loadable until a later TRAIT_CONFIG_UPDATED (the "populated" check).
-- This waiter drives create → populate → load → select, mirroring what the
-- talents frame does, so we never depend on that frame being open.
local loadoutWaiter
local pendingLoad -- { specID, label, awaitID }

local function finishLoadoutLoad(configID)
  if not pendingLoad then return end
  local specID, label = pendingLoad.specID, pendingLoad.label
  pendingLoad = nil
  local okLoad, result = pcall(C_ClassTalents.LoadConfig, configID, true)
  if okLoad and loadConfigAccepted(result) then
    if specID and C_ClassTalents.UpdateLastSelectedSavedConfigID then
      pcall(C_ClassTalents.UpdateLastSelectedSavedConfigID, specID, configID)
    end
  else
    print(string.format(
      "|cff00ccffZugZug Specs:|r Created the \"%s\" loadout for %s but couldn't auto-switch to it — select it in your talent frame.",
      LOADOUT_NAME, label or "build"))
  end
end

local function ensureLoadoutWaiter()
  if loadoutWaiter then return end
  loadoutWaiter = CreateFrame("Frame")
  loadoutWaiter:RegisterEvent("TRAIT_CONFIG_CREATED")
  loadoutWaiter:RegisterEvent("TRAIT_CONFIG_UPDATED")
  loadoutWaiter:SetScript("OnEvent", function(_, event, arg1)
    if not pendingLoad then return end
    if event == "TRAIT_CONFIG_CREATED" and type(arg1) == "table" and arg1.ID then
      if Enum and Enum.TraitConfigType and arg1.type ~= Enum.TraitConfigType.Combat then return end
      if C_ClassTalents.IsConfigPopulated and not C_ClassTalents.IsConfigPopulated(arg1.ID) then
        pendingLoad.awaitID = arg1.ID           -- wait for it to populate
      else
        finishLoadoutLoad(arg1.ID)
      end
    elseif event == "TRAIT_CONFIG_UPDATED" and pendingLoad.awaitID and arg1 == pendingLoad.awaitID then
      finishLoadoutLoad(arg1)
    end
  end)
end

--- Import the build into a loadout named "ZugZug" and activate it, leaving
--- the player's own loadouts untouched. Returns true once the create is
--- accepted (the load completes asynchronously); false on any failure so
--- the caller can fall back to the in-place apply.
local function tryApplyViaLoadout(importString, label)
  if not (C_ClassTalents and C_ClassTalents.ImportLoadout and C_ClassTalents.LoadConfig
      and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetTreeNodes) then
    return false
  end
  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not specID then return false end
  local treeID = C_ClassTalents.GetTraitTreeForSpec and C_ClassTalents.GetTraitTreeForSpec(specID)
  if not treeID then return false end
  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return false end

  local existing = findZugZugConfigID(specID)

  -- If the ZugZug loadout is the one currently selected, the in-place path
  -- IS the update mechanism (Blizzard blocks deleting the active loadout).
  if existing and C_ClassTalents.GetLastSelectedSavedConfigID then
    local okS, sel = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
    if okS and sel == existing then return false end
  end

  -- Replace any stale ZugZug loadout so copies never accumulate.
  if existing and C_ClassTalents.DeleteConfig then
    pcall(C_ClassTalents.DeleteConfig, existing)
  end

  local content = parseLoadoutContent(importString, treeID)
  if not content then return false end
  local entryInfo = convertToImportEntryInfo(configID, treeID, content)
  if not entryInfo or #entryInfo == 0 then return false end

  ensureLoadoutWaiter()
  pendingLoad = { specID = specID, label = label }
  local ok, success = pcall(C_ClassTalents.ImportLoadout, configID, entryInfo, LOADOUT_NAME, importString)
  if not ok or not success then
    pendingLoad = nil
    return false
  end

  -- Safety net: if the create events never resolve (e.g. the name already
  -- existed and it updated in place), find + load the loadout after a beat.
  C_Timer.After(3, function()
    if pendingLoad then
      local id = findZugZugConfigID(specID)
      if id then finishLoadoutLoad(id) else pendingLoad = nil end
    end
  end)

  print(string.format(
    "|cff00ccffZugZug Specs:|r Applying %s to the \"%s\" loadout... |cff888888Your own loadouts are untouched; /zz undo reverts.|r",
    label or "build", LOADOUT_NAME))
  return true
end

--- Stage + commit a parsed loadout onto the ACTIVE config (tree wipe +
--- rebuild). Shared by the in-place apply path and /zz undo.
local function applyParsedInPlace(parsed, renameTo)
  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then
    print("|cff00ccffZugZug Specs:|r No active talent config.")
    return false
  end

  -- Reset the tree
  if not C_Traits.ResetTree(configID, parsed.treeID) then
    print("|cff00ccffZugZug Specs:|r Failed to reset talent tree.")
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
    print("|cff00ccffZugZug Specs:|r Build is already active (no changes needed).")
    return true
  end

  if C_ClassTalents.CommitConfig(configID) then
    print("|cff00ccffZugZug Specs:|r Applying " .. (renameTo or "build") .. "...")
    -- Auto-rename the loadout to the build label
    if renameTo and C_ClassTalents.RenameConfig then
      C_ClassTalents.RenameConfig(configID, renameTo)
    end
    return true
  end

  -- Roll back the staged reset+rebuild so we don't strand a phantom
  -- uncommitted respec on the player's config.
  if C_Traits.RollbackConfig then
    pcall(C_Traits.RollbackConfig, configID)
  end
  print("|cff00ccffZugZug Specs:|r Failed to commit. Try with the talent frame open.")
  return false
end

--- Apply a build's import string: spec-switch if needed, then either the
--- dedicated-loadout path (default) or an in-place stage+commit.
function ZZ:ApplyBuild(importString, label)
  local parsed, err = parseImportString(importString)
  if not parsed then
    print("|cff00ccffZugZug Specs:|r Failed to parse: " .. (err or "unknown error"))
    return false
  end

  -- If the build is for a different spec, switch first
  local currentSpecID = PlayerUtil.GetCurrentSpecID()
  if parsed.specID ~= currentSpecID then
    local specIdx = specIndexForID(parsed.specID)
    if not specIdx then
      print("|cff00ccffZugZug Specs:|r Could not find spec for this build.")
      return false
    end
    pendingBuild = { importString = importString, label = label }
    print("|cff00ccffZugZug Specs:|r Switching spec to apply " .. (label or "build") .. "...")
    if InCombatLockdown() then
      print("|cff00ccffZugZug Specs:|r Cannot switch spec in combat.")
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

  -- Same-spec apply stages a full tree wipe + rebuild — never start that
  -- in combat (the commit would fail and strand the staged reset).
  if InCombatLockdown() then
    print("|cff00ccffZugZug Specs:|r Cannot change talents in combat.")
    return false
  end

  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then
    print("|cff00ccffZugZug Specs:|r No active talent config.")
    return false
  end

  -- Snapshot BEFORE anything mutates, so /zz undo can restore this exact state.
  ZZ:CaptureUndoSnapshot(configID, label or "build")

  -- Preferred path: import into the dedicated ZugZug loadout.
  if ZugZugDB.useDedicatedLoadout ~= false and tryApplyViaLoadout(importString, label) then
    return true
  end

  -- Fallback / legacy path: stage onto the active config.
  local ok = applyParsedInPlace(parsed, label)
  if ok then
    print("|cff888888ZugZug: /zz undo reverts this apply.|r")
  end
  return ok
end

--- Restore the talents captured before the last apply/swap/reset.
--- Toggles: undoing captures the current state first, so a second
--- /zz undo redoes what you just reverted.
function ZZ:UndoLastApply()
  local snap = ZugZugDB.undoSnapshot
  if not (snap and snap.importString) then
    print("|cff00ccffZugZug Specs:|r Nothing to undo.")
    return false
  end
  if InCombatLockdown() then
    print("|cff00ccffZugZug Specs:|r Cannot change talents in combat.")
    return false
  end
  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if snap.specID and specID and snap.specID ~= specID then
    print("|cff00ccffZugZug Specs:|r The undo snapshot is for another spec — switch back to use it.")
    return false
  end

  -- Capture the CURRENT state so /zz undo toggles between the two.
  local redo
  local configID = C_ClassTalents.GetActiveConfigID()
  if configID and C_Traits.GenerateImportString then
    local okG, cur = pcall(C_Traits.GenerateImportString, configID)
    if okG and type(cur) == "string" and cur ~= "" then redo = cur end
  end

  -- Prefer re-selecting the loadout that was active before the apply — it
  -- restores name + contents wholesale (the dedicated-loadout path never
  -- touched it). Fall back to an in-place restore from the snapshot string.
  local restored = false
  if snap.prevConfigID and C_ClassTalents.LoadConfig then
    local okInfo, info = pcall(C_Traits.GetConfigInfo, snap.prevConfigID)
    if okInfo and info then
      local okLoad, result = pcall(C_ClassTalents.LoadConfig, snap.prevConfigID, true)
      if okLoad and loadConfigAccepted(result) then
        if specID and C_ClassTalents.UpdateLastSelectedSavedConfigID then
          pcall(C_ClassTalents.UpdateLastSelectedSavedConfigID, specID, snap.prevConfigID)
        end
        restored = true
      end
    end
  end
  if not restored then
    local parsed = parseImportString(snap.importString)
    if parsed and parsed.specID == specID then
      restored = applyParsedInPlace(parsed, nil) == true
    end
  end

  if restored then
    print("|cff00ccffZugZug Specs:|r Restored your previous talents"
      .. (snap.action and (" (before " .. snap.action .. ")") or "") .. ".")
    if redo then
      ZugZugDB.undoSnapshot = {
        importString = redo,
        specID = specID,
        action = "undo",
        at = time(),
      }
    else
      ZugZugDB.undoSnapshot = nil
    end
  else
    print("|cff00ccffZugZug Specs:|r Could not restore — try with the talent frame open.")
  end
  return restored
end

--- Apply a pending build after a spec switch completes.
--- Walk the player's active talent tree and build a name → talent info lookup.
--- Used by Suggest.lua for popup icons + spell tooltips.
--- Returns a table: { [talentName] = { spellID, iconID, nodeID, entryID, isChoice } }
function ZZ:GetTalentLookup()
  local lookup = {}
  local byEntry = {}
  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not specID then return lookup, byEntry end
  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return lookup, byEntry end
  local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
  if not treeID then return lookup, byEntry end
  local treeNodes = C_Traits.GetTreeNodes(treeID)
  if not treeNodes then return lookup, byEntry end

  for _, nodeID in ipairs(treeNodes) do
    local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
    if nodeInfo and nodeInfo.entryIDs then
      local isChoice = #nodeInfo.entryIDs > 1
      for _, entryID in ipairs(nodeInfo.entryIDs) do
        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
        if entryInfo and entryInfo.definitionID then
          local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
          if defInfo and defInfo.spellID then
            local spell = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(defInfo.spellID)
            local name = (defInfo.overrideName and defInfo.overrideName ~= "")
              and defInfo.overrideName
              or (spell and spell.name)
            if name and name ~= "" and not lookup[name] then
              lookup[name] = {
                spellID = defInfo.spellID,
                iconID = spell and spell.iconID,
                nodeID = nodeID,
                entryID = entryID,
                isChoice = isChoice,
              }
            end
            -- entryID-keyed map: locale- and rename-proof matching for
            -- swap data that carries WCL talent (entry) IDs.
            if name and name ~= "" and not byEntry[entryID] then
              byEntry[entryID] = lookup[name]
            end
          end
        end
      end
    end
  end
  return lookup, byEntry
end

function ZZ:ApplyPendingBuild()
  if not pendingBuild then return end
  local build = pendingBuild
  pendingBuild = nil
  print("|cff00ccffZugZug Specs:|r Spec switched — applying " .. (build.label or "build") .. "...")
  ZZ:ApplyBuild(build.importString, build.label)
end

----------------------------------------------------------------------
-- Dropdown menu (shared by both Raid and M+)
----------------------------------------------------------------------

local activeDropdown = nil -- track which dropdown is open

local function closeActiveDropdown()
  if activeDropdown then
    -- Collapse the expand-state so the next open starts compact again
    -- (top 5 of the current spec; other specs folded away).
    activeDropdown.expandedSpecs = nil
    activeDropdown.showOthers = nil
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
  specIcon:SetSize(22, 22)
  specIcon:SetPoint("LEFT", item, "LEFT", 10, 0)
  item.specIcon = specIcon

  -- Popularity pill (right side, well clear of trend + star)
  local pill = CreateFrame("Frame", nil, item, "BackdropTemplate")
  pill:SetSize(42, 14)
  pill:SetPoint("RIGHT", item, "RIGHT", -84, 4)
  pill:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  local pillText = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  pillText:SetPoint("CENTER")
  pill.text = pillText
  item.pill = pill

  -- Trend indicator (between pill and star)
  local trendText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  trendText:SetPoint("LEFT", pill, "RIGHT", 6, 0)
  trendText:SetJustifyH("LEFT")
  item.trendText = trendText

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
  local specText = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  specText:SetPoint("TOPLEFT", item, "TOPLEFT", 38, -8)
  specText:SetPoint("TOPRIGHT", item, "TOPRIGHT", -110, -8)
  specText:SetJustifyH("LEFT")
  specText:SetWordWrap(false)
  item.specText = specText

  -- Bottom line: build label only (popularity moved to pill)
  local metaText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  metaText:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 38, 8)
  metaText:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -110, 8)
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
      print("|cff00ccffZugZug Specs:|r No import string for this build.")
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
  local icon = getSpecIcon(build.spec, build.specId)
  if icon then
    item.specIcon:SetTexture(icon)
    item.specIcon:Show()
    if isCurrentSpec then
      item.specIcon:SetDesaturated(false)
      item.specIcon:SetAlpha(1)
    else
      item.specIcon:SetDesaturated(true)
      item.specIcon:SetAlpha(0.55)
    end
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

  -- Bottom row: just the build label (popularity moved to pill).
  -- Raider.IO-sourced builds carry a recommendation verdict — mark those
  -- with a gold star so "what the data endorses" reads at a glance.
  local labelText = build.label or ""
  if build.recommended then
    labelText = "|cffffd100\226\152\133|r " .. labelText
  end
  -- RIO semantic themes ("Passive Damage · Mitigation") ride along muted.
  if build.themes and build.themes ~= "" then
    labelText = labelText .. "  |cff63666d" .. build.themes .. "|r"
  end
  item.metaText:SetText(labelText)
  if isCurrentSpec then
    item.metaText:SetTextColor(0.78, 0.78, 0.82)
  else
    item.metaText:SetTextColor(0.5, 0.5, 0.55)
  end

  -- Popularity pill (colored by tier)
  if item.pill and build.popularity then
    local p = getPopularityPill(build.popularity)
    item.pill:SetBackdropColor(p.bgR, p.bgG, p.bgB, 1)
    item.pill:SetBackdropBorderColor(p.edR, p.edG, p.edB, 1)
    item.pill.text:SetTextColor(p.txR, p.txG, p.txB)
    item.pill.text:SetText(build.popularity .. "%")
    item.pill:Show()
  elseif item.pill then
    item.pill:Hide()
  end

  -- Trend arrow
  if item.trendText then
    local trend = build.trend
    if trend == "up" then
      item.trendText:SetText("\226\150\178")
      item.trendText:SetTextColor(0.30, 1, 0.30)
    elseif trend == "down" then
      item.trendText:SetText("\226\150\188")
      item.trendText:SetTextColor(1, 0.40, 0.40)
    elseif trend == "new" then
      item.trendText:SetText("NEW")
      item.trendText:SetTextColor(0.30, 0.85, 1)
    else
      item.trendText:SetText("")
    end
  end

  -- Left accent bar: class color for current spec, dim section color otherwise
  if isCurrentSpec then
    local cr, cg, cb = getClassColor()
    item.accentBar:SetColorTexture(cr, cg, cb, 1)
  else
    item.accentBar:SetColorTexture(sectionColor.r, sectionColor.g, sectionColor.b, 0.25)
  end

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

  -- Left accent bar (gold for raid, green for M+)
  local accent = btn:CreateTexture(nil, "OVERLAY")
  accent:SetSize(3, DROPDOWN_BTN_HEIGHT)
  accent:SetPoint("LEFT", btn, "LEFT", 0, 0)
  accent:SetColorTexture(color.r, color.g, color.b, 1)
  btn.accent = accent

  -- Section label (top-left, big & bold)
  local labelText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  labelText:SetPoint("TOPLEFT", btn, "TOPLEFT", 12, -8)
  labelText:SetTextColor(color.r, color.g, color.b)
  labelText:SetText(label)
  btn.labelText = labelText

  -- Filter pill at top-right showing current difficulty/key level
  local pill = CreateFrame("Frame", nil, btn, "BackdropTemplate")
  pill:SetSize(50, 14)
  pill:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -8, -7)
  pill:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  pill:SetBackdropColor(color.r * 0.25, color.g * 0.25, color.b * 0.25, 1)
  pill:SetBackdropBorderColor(color.r * 0.7, color.g * 0.7, color.b * 0.7, 1)
  local pillText = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  pillText:SetPoint("CENTER")
  pillText:SetTextColor(color.r, color.g, color.b)
  pill.text = pillText
  btn.pill = pill
  btn.settingText = pillText  -- kept under old name for RefreshUI compat

  -- Bottom: current build label (set in RefreshUI) + click hint
  local buildText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  buildText:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 12, 18)
  buildText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -8, 18)
  buildText:SetJustifyH("LEFT")
  buildText:SetWordWrap(false)
  buildText:SetText("")
  btn.buildText = buildText

  local hintText = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hintText:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 12, 5)
  hintText:SetText("click for builds \226\150\188") -- ▼
  hintText:SetTextColor(0.45, 0.45, 0.5)
  btn.hintText = hintText

  -- Hover + tooltip
  btn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(COLORS.hover.r, COLORS.hover.g, COLORS.hover.b, 1)
    self:SetBackdropBorderColor(color.r, color.g, color.b, 0.6)
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
local barAttachedTo = nil -- talent frame the bar was last attached to, for reset

-- Re-anchor the bar to `parentFrame` while preserving its current screen position.
-- Used to convert between clamped (talent-frame-relative) and unclamped (UIParent-relative)
-- coordinate spaces without visually moving the bar.
local function reanchorTo(parentFrame)
  if not bar or not parentFrame then return false end
  local barLeft, barTop = bar:GetLeft(), bar:GetTop()
  local refLeft, refTop = parentFrame:GetLeft(), parentFrame:GetTop()
  if not barLeft or not refLeft then return false end
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", barLeft - refLeft, barTop - refTop)
  return true
end

local function saveBarPosition()
  if not bar then return end
  local point, _, relativePoint, x, y = bar:GetPoint(1)
  if not point then return end
  ZugZugDB.barPosition = {
    point = point,
    relativePoint = relativePoint,
    x = x,
    y = y,
    clamped = ZugZugDB.barClamped ~= false,
  }
end

local function applyBarPosition(parentFrame)
  if not bar then return end
  bar:ClearAllPoints()

  local clamped = ZugZugDB.barClamped ~= false
  local p = ZugZugDB.barPosition

  if p then
    -- Apply using the anchor parent the position was SAVED against
    local savedAnchor = (p.clamped and parentFrame) or UIParent
    bar:SetPoint(p.point or "CENTER", savedAnchor, p.relativePoint or p.point or "CENTER", p.x or 0, p.y or 0)

    -- If user's current clamped setting differs from how the position was saved,
    -- convert: re-anchor to the correct parent at the same visual location, then
    -- re-save with the new clamped flag.
    if p.clamped ~= clamped then
      local newAnchor = (clamped and parentFrame) or UIParent
      if reanchorTo(newAnchor) then
        saveBarPosition()
      end
    end
  elseif clamped and parentFrame then
    bar:SetPoint("TOP", parentFrame, "BOTTOM", 0, -4)
  else
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 120)
  end
end

local function updateBarLockVisual()
  if not bar then return end
  if ZugZugDB.barLocked then
    bar:SetBackdropBorderColor(COLORS.border.r, COLORS.border.g, COLORS.border.b, COLORS.border.a)
  else
    bar:SetBackdropBorderColor(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b, 1)
  end
end

function ZZ:UpdateBarLockState()
  updateBarLockVisual()
end

function ZZ:UpdateBarClampState()
  if not bar then return end
  -- Re-anchor the bar to the new mode's parent at its current visual location.
  -- This also handles the default-position case: toggling off clamp at the default
  -- spot snaps the bar's anchor to UIParent so it stops following the talent frame.
  -- If the bar isn't laid out yet (talent frame hidden), the next applyBarPosition()
  -- will resolve it from the default for the current mode.
  local clamped = ZugZugDB.barClamped ~= false
  local newAnchor = (clamped and barAttachedTo) or UIParent
  if newAnchor and reanchorTo(newAnchor) then
    saveBarPosition()
  end
end

function ZZ:ResetBarPosition()
  ZugZugDB.barPosition = nil
  if bar then
    applyBarPosition(barAttachedTo)
  end
end

local function createBar(parent)
  if bar then return bar end

  bar = CreateFrame("Frame", "ZugZugBar", parent, "BackdropTemplate")
  bar:SetHeight(BAR_HEIGHT + HEADER_HEIGHT + PADDING)
  bar:SetWidth(DROPDOWN_WIDTH * 2 + DROPDOWN_GAP + PADDING * 2)
  bar:SetFrameStrata("HIGH")
  bar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  bar:SetBackdropColor(COLORS.bg.r, COLORS.bg.g, COLORS.bg.b, COLORS.bg.a)
  bar:SetBackdropBorderColor(COLORS.border.r, COLORS.border.g, COLORS.border.b, COLORS.border.a)

  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")

  -- Custom drag: tracks cursor manually so we can axis-lock when shift is held.
  local dragStartCursorX, dragStartCursorY
  local dragStartBarLeft, dragStartBarBottom
  local dragAxis = nil  -- "x", "y", or nil

  bar:SetScript("OnDragStart", function(self)
    if ZugZugDB.barLocked then return end
    dragStartCursorX, dragStartCursorY = GetCursorPosition()
    dragStartBarLeft = self:GetLeft() or 0
    dragStartBarBottom = self:GetBottom() or 0
    dragAxis = nil
    self:SetScript("OnUpdate", function(s)
      local cx, cy = GetCursorPosition()
      local scale = s:GetEffectiveScale()
      local dx = (cx - dragStartCursorX) / scale
      local dy = (cy - dragStartCursorY) / scale
      if IsShiftKeyDown() then
        -- Lock axis once movement clears a small threshold; whichever axis
        -- the cursor has travelled further on wins.
        if not dragAxis and (math.abs(dx) + math.abs(dy)) > 8 then
          dragAxis = (math.abs(dx) > math.abs(dy)) and "x" or "y"
        end
        if dragAxis == "x" then dy = 0 end
        if dragAxis == "y" then dx = 0 end
      else
        dragAxis = nil
      end
      s:ClearAllPoints()
      s:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", dragStartBarLeft + dx, dragStartBarBottom + dy)
    end)
  end)
  bar:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    dragAxis = nil
    if ZugZugDB.barClamped ~= false and barAttachedTo then
      reanchorTo(barAttachedTo)
    end
    saveBarPosition()
  end)

  -- Class-colored top stripe (3px, full width)
  local classStripe = bar:CreateTexture(nil, "OVERLAY")
  classStripe:SetHeight(3)
  classStripe:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
  classStripe:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -1, -1)
  local cr, cg, cb = getClassColor()
  classStripe:SetColorTexture(cr, cg, cb, 1)
  bar.classStripe = classStripe

  -- Darker header strip background
  local headerBg = bar:CreateTexture(nil, "BACKGROUND")
  headerBg:SetHeight(HEADER_HEIGHT - 3)
  headerBg:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -4)
  headerBg:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -1, -4)
  headerBg:SetColorTexture(0.05, 0.05, 0.07, 0.85)

  -- Logo (bigger, sits in the header area)
  local addonFolder = ZZ.addonName or "ZugZug"
  local logo = bar:CreateTexture(nil, "ARTWORK")
  logo:SetSize(40, 40)
  logo:SetPoint("TOPLEFT", bar, "TOPLEFT", PADDING - 2, -2)
  logo:SetTexture("Interface\\AddOns\\" .. addonFolder .. "\\icon.png")
  bar.logo = logo

  -- Wordmark
  local wordmark = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  wordmark:SetPoint("LEFT", logo, "RIGHT", 6, 0)
  wordmark:SetText("|cff8fbf3fZUGZUG|r |cff666666\194\183|r |cffaaaaaaBuilds|r")
  bar.wordmark = wordmark

  -- Settings cog (top-right) — uses a Blizzard gear icon texture
  local cogBtn = CreateFrame("Button", nil, bar, "BackdropTemplate")
  cogBtn:SetSize(22, 22)
  cogBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -PADDING, -7)
  cogBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  cogBtn:SetBackdropColor(0.10, 0.10, 0.13, 1)
  cogBtn:SetBackdropBorderColor(0.30, 0.30, 0.35, 1)
  local cogIcon = cogBtn:CreateTexture(nil, "OVERLAY")
  cogIcon:SetSize(16, 16)
  cogIcon:SetPoint("CENTER")
  cogIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
  cogIcon:SetVertexColor(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b)
  cogBtn:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b, 1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Open ZugZug settings", 1, 1, 1)
    GameTooltip:Show()
  end)
  cogBtn:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(0.30, 0.30, 0.35, 1)
    GameTooltip:Hide()
  end)
  cogBtn:SetScript("OnClick", function()
    -- Toggle: if the settings panel is already open, close it.
    if SettingsPanel and SettingsPanel:IsShown() then
      HideUIPanel(SettingsPanel)
      return
    end
    local ok = pcall(function()
      if ZZ.settingsCategory then
        Settings.OpenToCategory(ZZ.settingsCategory:GetID())
      else
        Settings.OpenToCategory("ZugZug")
      end
    end)
    if not ok then print("|cff00ccffZugZug Specs:|r Could not open settings.") end
  end)
  bar.cogBtn = cogBtn

  -- Kept under old name for any references
  bar.header = wordmark

  -- Raid dropdown button (anchored below header)
  local raidBtn = createDropdownButton(bar, "RAID", COLORS.raid)
  raidBtn:SetPoint("TOPLEFT", bar, "TOPLEFT", PADDING, -(HEADER_HEIGHT + 4))
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
      raidMenu:SetPoint("BOTTOM", bar, "TOP", 0, 4)
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
      mpMenu:SetPoint("BOTTOM", bar, "TOP", 0, 4)
      mpMenu:Show()
      activeDropdown = mpMenu
    end
  end)

  -- Leveling button — wider, two-line: shows next-talent name + inline progress bar
  local levelBtn = CreateFrame("Button", nil, bar, "BackdropTemplate")
  levelBtn:SetSize(LEVELING_BTN_WIDTH, DROPDOWN_BTN_HEIGHT)
  levelBtn:SetPoint("LEFT", mpBtn, "RIGHT", DROPDOWN_GAP, 0)
  levelBtn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  levelBtn:SetBackdropColor(0.08, 0.18, 0.08, 1)
  levelBtn:SetBackdropBorderColor(COLORS.border.r, COLORS.border.g, COLORS.border.b, 1)

  local lvlAccent = levelBtn:CreateTexture(nil, "OVERLAY")
  lvlAccent:SetSize(3, DROPDOWN_BTN_HEIGHT)
  lvlAccent:SetPoint("LEFT", levelBtn, "LEFT", 0, 0)
  lvlAccent:SetColorTexture(0.63, 0.88, 0.63, 1)

  local lvlLabel = levelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lvlLabel:SetPoint("TOPLEFT", levelBtn, "TOPLEFT", 12, -8)
  lvlLabel:SetText("LEVELING")
  lvlLabel:SetTextColor(0.63, 0.88, 0.63)
  levelBtn.label = lvlLabel

  -- "Next: <talent>" line in the middle
  local lvlNextText = levelBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  lvlNextText:SetPoint("TOPLEFT", levelBtn, "TOPLEFT", 12, -22)
  lvlNextText:SetPoint("RIGHT", levelBtn, "RIGHT", -8, 0)
  lvlNextText:SetJustifyH("LEFT")
  lvlNextText:SetWordWrap(false)
  lvlNextText:SetText("")
  levelBtn.nextText = lvlNextText

  -- Progress bar track at bottom
  local lvlBarTrack = levelBtn:CreateTexture(nil, "ARTWORK")
  lvlBarTrack:SetHeight(4)
  lvlBarTrack:SetPoint("BOTTOMLEFT", levelBtn, "BOTTOMLEFT", 12, 8)
  lvlBarTrack:SetPoint("BOTTOMRIGHT", levelBtn, "BOTTOMRIGHT", -42, 8)
  lvlBarTrack:SetColorTexture(0.10, 0.10, 0.13, 1)
  levelBtn.barTrack = lvlBarTrack

  local lvlBarFill = levelBtn:CreateTexture(nil, "OVERLAY")
  lvlBarFill:SetHeight(4)
  lvlBarFill:SetPoint("BOTTOMLEFT", lvlBarTrack, "BOTTOMLEFT", 0, 0)
  lvlBarFill:SetColorTexture(0.63, 0.88, 0.63, 1)
  lvlBarFill:SetWidth(1)
  levelBtn.barFill = lvlBarFill

  local lvlProgText = levelBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  lvlProgText:SetPoint("RIGHT", levelBtn, "RIGHT", -8, -19)
  lvlProgText:SetText("")
  lvlProgText:SetTextColor(0.50, 0.70, 0.50)
  levelBtn.progText = lvlProgText

  levelBtn:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b, 1)
  end)
  levelBtn:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(COLORS.border.r, COLORS.border.g, COLORS.border.b, 1)
  end)
  levelBtn:SetScript("OnClick", function()
    -- At max level the banner has nothing actionable (no "next pick"), so
    -- the click directly applies the leveling build in one step.
    local level = UnitLevel("player")
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 80
    if level and level >= maxLevel then
      if ZZ.ApplyLevelingBuild then ZZ:ApplyLevelingBuild() end
    else
      if ZZ.ToggleLevelingBanner then ZZ:ToggleLevelingBanner() end
    end
  end)
  levelBtn:Hide()
  bar.levelBtn = levelBtn

  -- Close dropdown when clicking elsewhere
  bar:SetScript("OnHide", function()
    closeActiveDropdown()
  end)

  updateBarLockVisual()
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
    local sorted = {}
    for _, b in ipairs(builds) do sorted[#sorted + 1] = b end
    table.sort(sorted, function(a, b)
      local aFav = favs[a.importString] and true or false
      local bFav = favs[b.importString] and true or false
      if aFav ~= bFav then return aFav end
      local aSpec = ZZ:BuildMatchesSpec(a)
      local bSpec = ZZ:BuildMatchesSpec(b)
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

  -- Reset section headers + expander rows
  menu.headers = menu.headers or {}
  for _, h in ipairs(menu.headers) do h.frame:Hide() end
  menu.expanders = menu.expanders or {}
  for _, e in ipairs(menu.expanders) do e:Hide() end
  -- Expansion state is per-menu and session-only; a fresh open starts
  -- compact (cleared by the dropdown's OnHide).
  menu.expandedSpecs = menu.expandedSpecs or {}

  local DROPDOWN_MENU_WIDTH = 430
  local SECTION_HEADER_HEIGHT = 20
  local EXPANDER_HEIGHT = 22
  -- RIO ships up to 8 builds per spec per bucket — the flat list got long.
  -- Show the top N per spec; the rest sit behind a per-spec expander, and
  -- other specs' groups sit behind one collapsed master expander.
  local MAX_VISIBLE = 5

  local yOffset = -4
  local headerIdx = 0
  local expanderIdx = 0
  local itemIdx = 0

  local function placeHeader(spec, isCurr)
    headerIdx = headerIdx + 1
    if not menu.headers[headerIdx] then
      local hf = CreateFrame("Frame", nil, menu)
      hf:SetHeight(SECTION_HEADER_HEIGHT)
      local bg = hf:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetColorTexture(0.04, 0.04, 0.06, 0.95)
      hf.bg = bg
      local accent = hf:CreateTexture(nil, "OVERLAY")
      accent:SetSize(3, SECTION_HEADER_HEIGHT)
      accent:SetPoint("LEFT", hf, "LEFT", 0, 0)
      hf.accent = accent
      local label = hf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      label:SetPoint("LEFT", hf, "LEFT", 12, 0)
      hf.label = label
      local tag = hf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      tag:SetPoint("LEFT", label, "RIGHT", 8, 0)
      hf.tag = tag
      menu.headers[headerIdx] = { frame = hf }
    end
    local hf = menu.headers[headerIdx].frame
    hf:ClearAllPoints()
    hf:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, yOffset)
    hf:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, yOffset)
    if isCurr then
      local cr, cg, cb = getClassColor()
      hf.accent:SetColorTexture(cr, cg, cb, 1)
      hf.label:SetText(spec or "")
      hf.label:SetTextColor(cr, cg, cb)
      hf.tag:SetText("CURRENT SPEC")
      hf.tag:SetTextColor(0.5, 0.5, 0.55)
    else
      hf.accent:SetColorTexture(0.25, 0.25, 0.30, 1)
      hf.label:SetText(spec or "")
      hf.label:SetTextColor(0.45, 0.45, 0.5)
      hf.tag:SetText("")
    end
    hf:Show()
    yOffset = yOffset - SECTION_HEADER_HEIGHT
  end

  --- A slim clickable row ("Show 3 more ▾" / "Other specs · 12 builds ▸").
  local function placeExpander(text, onClick)
    expanderIdx = expanderIdx + 1
    if not menu.expanders[expanderIdx] then
      local btn = CreateFrame("Button", nil, menu)
      btn:SetHeight(EXPANDER_HEIGHT)
      local bg = btn:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetColorTexture(0.08, 0.08, 0.11, 0.9)
      btn.bg = bg
      local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      label:SetPoint("CENTER")
      btn.label = label
      btn:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.13, 0.13, 0.17, 0.95) end)
      btn:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.08, 0.08, 0.11, 0.9) end)
      menu.expanders[expanderIdx] = btn
    end
    local btn = menu.expanders[expanderIdx]
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, yOffset)
    btn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, yOffset)
    btn.label:SetText(text)
    btn.label:SetTextColor(0.55, 0.60, 0.68)
    btn:SetScript("OnClick", onClick)
    btn:Show()
    yOffset = yOffset - EXPANDER_HEIGHT
  end

  local function placeBuild(build)
    itemIdx = itemIdx + 1
    if not menu.items[itemIdx] then
      menu.items[itemIdx] = createDropdownItem(menu, itemIdx)
    end
    local item = menu.items[itemIdx]
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, yOffset)
    item:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, yOffset)
    populateDropdownItem(item, build, contentType, sectionColor, ZZ:BuildMatchesSpec(build))
    yOffset = yOffset - DROPDOWN_ITEM_HEIGHT
  end

  --- One spec's group: header, top MAX_VISIBLE builds, per-spec expander.
  local function placeSpecGroup(spec, list, isCurr)
    placeHeader(spec, isCurr)
    local expanded = menu.expandedSpecs[spec]
    local limit = expanded and #list or math.min(MAX_VISIBLE, #list)
    for i = 1, limit do placeBuild(list[i]) end
    if #list > MAX_VISIBLE then
      local text = expanded
        and "Show less \226\150\180"
        or string.format("Show %d more \226\150\190", #list - MAX_VISIBLE)
      placeExpander(text, function()
        menu.expandedSpecs[spec] = not menu.expandedSpecs[spec] or nil
        ZZ:PopulateDropdown(contentType)
      end)
    end
  end

  -- Split into current-spec builds and everything else, preserving order.
  local currentList, otherSpecs, otherOrder = {}, {}, {}
  for _, build in ipairs(builds) do
    if ZZ:BuildMatchesSpec(build) then
      currentList[#currentList + 1] = build
    else
      local s = build.spec or "?"
      if not otherSpecs[s] then otherSpecs[s] = {}; otherOrder[#otherOrder + 1] = s end
      local g = otherSpecs[s]
      g[#g + 1] = build
    end
  end

  if #currentList > 0 then
    placeSpecGroup(currentList[1].spec, currentList, true)
  end

  local otherCount = 0
  for _, s in ipairs(otherOrder) do otherCount = otherCount + #otherSpecs[s] end
  if otherCount > 0 then
    if menu.showOthers then
      placeExpander("Hide other specs \226\150\180", function()
        menu.showOthers = false
        ZZ:PopulateDropdown(contentType)
      end)
      for _, s in ipairs(otherOrder) do
        placeSpecGroup(s, otherSpecs[s], false)
      end
    else
      placeExpander(
        string.format("Other specs \194\183 %d build%s \226\150\190", otherCount, otherCount == 1 and "" or "s"),
        function()
          menu.showOthers = true
          ZZ:PopulateDropdown(contentType)
        end)
    end
  end

  menu:SetSize(DROPDOWN_MENU_WIDTH, -yOffset + 4)
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

--- Find the top build of a list (highest popularity, optionally restricted to current spec).
local function topBuildLabel(builds, preferSpec)
  if not builds or #builds == 0 then return "" end
  local best = nil
  for _, b in ipairs(builds) do
    if not preferSpec or ZZ:BuildMatchesSpec(b) then
      if not best or (b.popularity or 0) > (best.popularity or 0) then
        best = b
      end
    end
  end
  if not best then
    for _, b in ipairs(builds) do
      if not best or (b.popularity or 0) > (best.popularity or 0) then
        best = b
      end
    end
  end
  if not best then return "" end
  if best.spec and best.label then
    return best.spec .. " \194\183 " .. best.label
  end
  return best.label or best.spec or ""
end

function ZZ:RefreshUI()
  if not bar then return end

  -- Refresh class color (for spec swaps)
  local cr, cg, cb = getClassColor()
  if bar.classStripe then bar.classStripe:SetColorTexture(cr, cg, cb, 1) end

  -- Filter pills
  local diff = ZugZugDB.raidDifficulty or "mythic"
  bar.raidBtn.settingText:SetText(diff == "mythic" and "Mythic" or "Heroic")
  local bucket = ZugZugDB.mpBucket or "all"
  bar.mpBtn.settingText:SetText(bucket)

  -- Current top-build labels (bottom row of each section button)
  local raidBuilds, mpBuilds = ZZ:GetCurrentBuilds()
  if bar.raidBtn.buildText then
    bar.raidBtn.buildText:SetText(topBuildLabel(raidBuilds, ZZ.specName))
  end
  if bar.mpBtn.buildText then
    bar.mpBtn.buildText:SetText(topBuildLabel(mpBuilds, ZZ.specName))
  end

  -- Show leveling button below max level (always when enabled) or at max level
  -- when the "Show at Max Level" option is on (for open world / delve use).
  local level = UnitLevel("player")
  local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 80
  local levelingOn = ZugZugDB.levelingEnabled ~= false
  local belowMax = level and level < maxLevel
  local atMaxAllowed = level and level >= maxLevel and ZugZugDB.levelingAtMax
  local showLeveling = levelingOn and ZugZugLevelingData ~= nil and (belowMax or atMaxAllowed)
  if bar.levelBtn then
    bar.levelBtn:SetShown(showLeveling)
    -- Populate next-talent + progress from the leveling system
    if showLeveling and ZZ.GetLevelingStatus then
      local status = ZZ:GetLevelingStatus()
      if status then
        bar.levelBtn.nextText:SetText(status.nextName and ("Next: " .. status.nextName) or "Build complete")
        local pct = status.total > 0 and (status.completed / status.total) or 0
        local trackW = bar.levelBtn.barTrack:GetWidth()
        bar.levelBtn.barFill:SetWidth(math.max(1, math.floor(trackW * pct)))
        bar.levelBtn.progText:SetText(status.completed .. " / " .. status.total)
      end
    end
    -- Widen bar to fit the leveling button
    if showLeveling then
      bar:SetWidth(DROPDOWN_WIDTH * 2 + LEVELING_BTN_WIDTH + DROPDOWN_GAP * 2 + PADDING * 2)
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
-- Cast bar — shows above the build bar while the talent-change cast is active
----------------------------------------------------------------------

-- Known spell IDs for talent loadout / spec swap casts. Add more if observed.
local TALENT_CHANGE_SPELL_IDS = {
  [384255] = true, -- Changing Talents
  [200749] = true, -- Activate Specialization
  [222695] = true, -- Changing Talents (older)
}

local function isTalentChangeCast(spellID, spellName)
  if spellID and TALENT_CHANGE_SPELL_IDS[spellID] then return true end
  if spellName then
    local n = spellName:lower()
    if n:find("changing talent") or n:find("activate spec") or n:find("changing spec") then
      return true
    end
  end
  return false
end

local castBar = nil

local function getCastBar()
  if castBar then return castBar end
  if not bar then return nil end

  local cb = CreateFrame("StatusBar", "ZugZugCastBar", bar, "BackdropTemplate")
  cb:SetHeight(22)
  cb:SetFrameStrata("HIGH")
  -- Flat solid fill (no Blizzard 3D gradient)
  cb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
  cb:SetMinMaxValues(0, 1)
  cb:SetStatusBarColor(COLORS.accent.r, COLORS.accent.g, COLORS.accent.b, 1)
  cb:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  cb:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
  cb:SetBackdropBorderColor(0.30, 0.30, 0.35, 1)

  -- Anchor: match bar width, sit just above the bar (same spot as the dropdown menus)
  cb:ClearAllPoints()
  cb:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 4)
  cb:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 4)

  local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", cb, "LEFT", 10, 0)
  text:SetTextColor(1, 1, 1)
  cb.text = text

  local timeText = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  timeText:SetPoint("RIGHT", cb, "RIGHT", -10, 0)
  timeText:SetTextColor(0.85, 0.85, 0.90)
  cb.timeText = timeText

  cb:Hide()
  castBar = cb
  return cb
end

local function hideCastBar()
  if castBar then
    castBar:SetScript("OnUpdate", nil)
    castBar:Hide()
  end
end

local function showCastBar()
  local cb = getCastBar()
  if not cb then return end

  local name, _, _, startTime, endTime, _, _, _, spellID = UnitCastingInfo("player")
  if not name or not startTime or not endTime then
    hideCastBar()
    return
  end
  if not isTalentChangeCast(spellID, name) then
    hideCastBar()
    return
  end

  cb.startTime = startTime
  cb.endTime = endTime
  cb.text:SetText(name)
  cb:SetValue(0)
  cb:Show()
  cb:SetScript("OnUpdate", function(self)
    local now = GetTime() * 1000
    local total = self.endTime - self.startTime
    if total <= 0 then
      self:Hide()
      self:SetScript("OnUpdate", nil)
      return
    end
    local elapsed = now - self.startTime
    if elapsed >= total then
      self:Hide()
      self:SetScript("OnUpdate", nil)
      return
    end
    self:SetValue(elapsed / total)
    self.timeText:SetText(string.format("%.1fs", (total - elapsed) / 1000))
  end)
end

local castEventFrame = CreateFrame("Frame")
-- Unit-filtered registration: the plain RegisterEvent variant fires for
-- EVERY unit's casts (thousands per minute in raid combat) just to be
-- discarded by the unit check below.
castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
castEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
castEventFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
  if unit ~= "player" then return end
  if event == "UNIT_SPELLCAST_START" then
    if isTalentChangeCast(spellID) then
      showCastBar()
    end
  else
    hideCastBar()
  end
end)

----------------------------------------------------------------------
-- Hook into talent frame
----------------------------------------------------------------------

local function hookTalentFrame()
  local function attachToFrame(talentFrame)
    if talentFrame.zugzugHooked then return end
    talentFrame.zugzugHooked = true

    createBar(talentFrame)

    -- Remember which talent frame to fall back to on reset
    barAttachedTo = talentFrame

    -- Default anchor below talent frame (or saved position if any)
    applyBarPosition(talentFrame)

    -- Show/hide with talent frame
    talentFrame:HookScript("OnShow", function()
      applyBarPosition(talentFrame)
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
      -- Create on demand — the bar otherwise only exists after the talent
      -- frame (load-on-demand) has been opened once this session, which
      -- made /zz show a silent no-op on fresh logins.
      local b = ZZ:GetOrCreateBar()
      if b:IsShown() then
        b:Hide()
      else
        applyBarPosition(barAttachedTo)
        b:Show()
        ZZ:RefreshUI()
      end
      return
    end

    if origHandler then
      origHandler(msg)
    end
  end
end)
