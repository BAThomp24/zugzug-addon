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

-- Expose for Suggest.lua so it can detect whether the player is actually on a build
-- (not just on the same spec + hero).
ZZ.CountTalentDiff = countTalentDiff

--- Print the current state of every pick/drop in the last captured
--- swapData, so we can see exactly why the popup is appearing. Each line
--- shows the talent name, current/max rank, whether it's a choice node,
--- canPurchaseRank, and canRefundRank — the four fields ApplySwaps and
--- SwapsAlreadyApplied use to decide actionability.
function ZZ:DumpLastSwapState()
  -- Write directly to DEFAULT_CHAT_FRAME so a chat addon (Chattynator
  -- etc.) can't route or filter the output away.
  local function out(msg) DEFAULT_CHAT_FRAME:AddMessage(msg) end
  out("|cffff8800ZZ:DumpLastSwapState ENTRY|r")
  local sw = self.lastSwapData
  if not sw then out("|cff00ccffZugZug:|r no captured swap data") return end
  out("|cff00ccffZugZug:|r sw has " .. (sw.picks and #sw.picks or 0) .. " picks, "
    .. (sw.drops and #sw.drops or 0) .. " drops")
  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  local configID = C_ClassTalents.GetActiveConfigID()
  local treeID = specID and C_ClassTalents.GetTraitTreeForSpec(specID)
  if not (specID and configID and treeID) then
    print("|cff00ccffZugZug:|r talent API not ready")
    return
  end
  local treeNodes = C_Traits.GetTreeNodes(treeID)
  local nameLookup = {}
  for _, nodeID in ipairs(treeNodes or {}) do
    local ni = C_Traits.GetNodeInfo(configID, nodeID)
    if ni and ni.entryIDs then
      local isChoice = #ni.entryIDs > 1
      for _, entryID in ipairs(ni.entryIDs) do
        local ei = C_Traits.GetEntryInfo(configID, entryID)
        local di = ei and ei.definitionID
                    and C_Traits.GetDefinitionInfo(ei.definitionID)
        if di then
          local nm = (di.overrideName and di.overrideName ~= "") and di.overrideName
                      or (di.spellID and C_Spell and C_Spell.GetSpellInfo
                          and (C_Spell.GetSpellInfo(di.spellID) or {}).name)
          if nm and nm ~= "" and not nameLookup[nm] then
            nameLookup[nm] = { nodeID = nodeID, entryID = entryID, isChoice = isChoice }
          end
        end
      end
    end
  end

  local function dumpList(label, list)
    print(string.format("|cff8fbf3fZugZug %s (%d):|r", label, #list))
    for i, p in ipairs(list) do
      local t = nameLookup[p.name]
      if not t then
        print(string.format("  [%d] %s — NOT FOUND in spec tree", i, tostring(p.name)))
      else
        local ni = C_Traits.GetNodeInfo(configID, t.nodeID)
        if not ni then
          print(string.format("  [%d] %s — nodeInfo nil", i, p.name))
        elseif t.isChoice then
          local active = ni.activeEntry and ni.activeEntry.entryID
          local matches = (active == t.entryID)
          print(string.format("  [%d] %s — choice  active=%s  target=%s  matches=%s",
            i, p.name, tostring(active), tostring(t.entryID), tostring(matches)))
        else
          print(string.format("  [%d] %s — rank=%d/%d  canPurchase=%s  canRefund=%s",
            i, p.name, ni.currentRank or 0, ni.maxRanks or 1,
            tostring(ni.canPurchaseRank), tostring(ni.canRefundRank)))
        end
      end
    end
  end

  dumpList("picks", sw.picks or {})
  dumpList("drops", sw.drops or {})

  print(string.format("|cff8fbf3fZugZug:|r SwapsAlreadyApplied = %s",
    tostring(ZZ:SwapsAlreadyApplied(sw))))
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
--- Walk the player's active talent tree and build a name → talent info lookup.
--- Used by Suggest.lua (for popup icons + spell tooltips) and ApplySwaps internally.
--- Returns a table: { [talentName] = { spellID, iconID, nodeID, entryID, isChoice } }
function ZZ:GetTalentLookup()
  local lookup = {}
  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not specID then return lookup end
  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return lookup end
  local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
  if not treeID then return lookup end
  local treeNodes = C_Traits.GetTreeNodes(treeID)
  if not treeNodes then return lookup end

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
          end
        end
      end
    end
  end
  return lookup
end

--- Returns true if every pick in swapData is already selected AND every
--- non-choice drop is already at rank 0 — i.e., there's nothing left for
--- ApplySwaps to do. Used by Suggest.lua to suppress redundant dungeon-tweak
--- popups when the player already has the recommended picks.
function ZZ:SwapsAlreadyApplied(swapData)
  if not swapData then return true end
  local picks = swapData.picks or {}
  if #picks == 0 then return true end

  -- API readiness checks. On /reload these can return nil briefly before
  -- the talent system has settled. In that window we lean *optimistic* —
  -- return true (no popup) rather than false (popup), so we don't show a
  -- "Apply Swaps" call-to-action we can't verify is meaningful. A real
  -- swap-needed state will re-trigger the next zone change or spec switch.
  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not specID then return true end
  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return true end
  local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
  if not treeID then return true end

  local treeNodes = C_Traits.GetTreeNodes(treeID)
  if not treeNodes then return true end

  -- name → { nodeID, entryID, isChoice }
  local lookup = {}
  for _, nodeID in ipairs(treeNodes) do
    local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
    if nodeInfo and nodeInfo.entryIDs then
      local isChoice = #nodeInfo.entryIDs > 1
      for _, entryID in ipairs(nodeInfo.entryIDs) do
        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
        if entryInfo and entryInfo.definitionID then
          local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
          if defInfo then
            local name = defInfo.overrideName
            if (not name or name == "") and defInfo.spellID and C_Spell and C_Spell.GetSpellInfo then
              local spell = C_Spell.GetSpellInfo(defInfo.spellID)
              name = spell and spell.name
            end
            if name and name ~= "" and not lookup[name] then
              lookup[name] = { nodeID = nodeID, entryID = entryID, isChoice = isChoice }
            end
          end
        end
      end
    end
  end

  -- We deliberately DO NOT check drops separately: ApplySwaps only
  -- refunds drops to free a point for picks. A stale drop at rank > 0
  -- with no satisfiable picks is a no-op for ApplySwaps — and showing
  -- the popup in that case produces the "No swaps needed, already
  -- aligned" UX bug. So we only return false (popup shows) when at
  -- least one pick is provably actionable.
  --
  -- "Provably actionable" requires a dry-run because Blizzard's
  -- canPurchaseRank for a pick depends on tree-gate math (row totals,
  -- prereqs) that refunding a drop may make true or false. We stage the
  -- refunds, re-check each pick, then roll back so the player's actual
  -- loadout is untouched.

  -- Bail if the player already has uncommitted staged changes — they
  -- might be editing manually, and a rollback would discard their work.
  -- Conservative fallback: return true (no popup) in that window; the
  -- next zone change / spec change will re-trigger the check.
  if C_Traits.ConfigHasStagedChanges
      and C_Traits.ConfigHasStagedChanges(configID) then
    return true
  end

  local drops = swapData.drops or {}

  --- Stage-and-check: actually attempt to purchase (or select) the pick.
  --- This is the authoritative test — Blizzard's `canPurchaseRank` flag
  --- LIES (reports true even when the player has zero free points in
  --- the relevant pool), but `PurchaseRank` itself returns the truth: it
  --- only stages the change if Blizzard's internal engine accepts it.
  --- All staged changes are rolled back at the end of SwapsAlreadyApplied
  --- via RollbackConfig, so the player's loadout is never mutated.
  local function tryStagePick(p)
    local t = lookup[p.name]
    if not t then return false end
    local ni = C_Traits.GetNodeInfo(configID, t.nodeID)
    if not ni then return false end
    if t.isChoice then
      local active = ni.activeEntry and ni.activeEntry.entryID
      if active == t.entryID then return false end
      if C_Traits.SetSelection
          and C_Traits.SetSelection(configID, t.nodeID, t.entryID) then
        return true
      end
      return false
    end
    local currentRank = ni.currentRank or 0
    local maxRanks    = ni.maxRanks or 1
    if currentRank >= maxRanks then return false end
    if C_Traits.PurchaseRank
        and C_Traits.PurchaseRank(configID, t.nodeID) then
      return true
    end
    return false
  end

  -- Test 1 — try every pick without touching drops. If any pick stages
  -- successfully, the popup is actionable as-is.
  local actionable = false
  for _, p in ipairs(picks) do
    if tryStagePick(p) then actionable = true; break end
  end

  -- Test 2 (only if Test 1 failed) — stage every drop's refund, then
  -- retry the picks. A refund may unlock a pick by either freeing a
  -- point in the same pool or rebalancing a tree-gate the pick was
  -- behind. Whichever, we just want to know whether ApplySwaps could
  -- succeed.
  if not actionable then
    for _, d in ipairs(drops) do
      local t = lookup[d.name]
      if t and not t.isChoice then
        local ni = C_Traits.GetNodeInfo(configID, t.nodeID)
        if ni and (ni.currentRank or 0) > 0 and ni.canRefundRank
            and C_Traits.RefundRank then
          C_Traits.RefundRank(configID, t.nodeID)
        end
      end
    end
    for _, p in ipairs(picks) do
      if tryStagePick(p) then actionable = true; break end
    end
  end

  -- Always roll back so the player's state is unchanged regardless of
  -- the dry-run outcome. RollbackConfig discards all uncommitted staged
  -- changes — exactly what we want.
  if C_Traits.RollbackConfig then
    pcall(C_Traits.RollbackConfig, configID)
  end

  return not actionable
end

--- Apply dungeon-specific talent swaps to the current loadout without resetting
--- the tree. swapData is the new split shape: { picks = {...}, drops = {...} }.
---
--- Strategy:
---   1. Refund all non-choice drops first (frees talent points).
---   2. For each pick:
---      - Choice node:  SetSelection on the entry (no point cost).
---      - Non-choice:   PurchaseRank. If it fails because we're out of points,
---                      refund the next-best non-choice drop to free one, then retry.
---
--- For choice nodes among the drops, we skip — picking the alternative entry
--- via the corresponding "pick" already deselects them.
function ZZ:ApplySwaps(swapData)
  if not swapData then return false end
  local picks = swapData.picks or {}
  local drops = swapData.drops or {}
  if #picks == 0 and #drops == 0 then return false end
  if InCombatLockdown() then
    print("|cff00ccffZugZug:|r Cannot change talents in combat.")
    return false
  end

  local specID = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
  if not specID then return false end
  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return false end
  local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
  if not treeID then return false end

  local treeNodes = C_Traits.GetTreeNodes(treeID)
  if not treeNodes then return false end

  -- Build a talent-name → (nodeID, entryID, isChoice) lookup by walking the tree.
  local lookup = {}
  for _, nodeID in ipairs(treeNodes) do
    local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
    if nodeInfo and nodeInfo.entryIDs then
      local isChoice = #nodeInfo.entryIDs > 1
      for _, entryID in ipairs(nodeInfo.entryIDs) do
        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
        if entryInfo and entryInfo.definitionID then
          local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
          if defInfo then
            local name = defInfo.overrideName
            if (not name or name == "") and defInfo.spellID and C_Spell and C_Spell.GetSpellInfo then
              local spell = C_Spell.GetSpellInfo(defInfo.spellID)
              name = spell and spell.name
            end
            if name and name ~= "" and not lookup[name] then
              lookup[name] = { nodeID = nodeID, entryID = entryID, isChoice = isChoice }
            end
          end
        end
      end
    end
  end

  -- Helper: try to refund one rank from any non-choice drop that's currently
  -- purchased. Returns the refunded key (so caller can undo) or nil.
  local refundedDrops = {}
  local function tryRefundOneDrop()
    for _, d in ipairs(drops) do
      local key = d.name
      if not refundedDrops[key] then
        local target = lookup[key]
        if target and not target.isChoice then
          local ni = C_Traits.GetNodeInfo(configID, target.nodeID)
          if ni and (ni.currentRank or 0) > 0 and C_Traits.RefundRank then
            if C_Traits.RefundRank(configID, target.nodeID) then
              refundedDrops[key] = true
              return key
            end
          end
        end
      end
    end
    return nil
  end

  -- Undo a refund (re-purchase the drop) if the pick we freed the point
  -- for couldn't actually be purchased. Keeps the player's loadout
  -- stable instead of leaving a stray unspent point.
  local function undoRefund(key)
    if not key then return end
    local target = lookup[key]
    if target and C_Traits.PurchaseRank then
      C_Traits.PurchaseRank(configID, target.nodeID)
    end
    refundedDrops[key] = nil
  end

  local applied = 0
  local skipped = {}

  -- Phase 1 — refund every non-choice drop upfront. This mirrors how the
  -- Blizzard talent UI itself processes changes (all refunds, then all
  -- purchases). Doing it lazily per-pick caused staging-order issues that
  -- made PurchaseRank return false even when the talent was reachable.
  -- We record what we refunded so we can roll back orphans afterwards.
  local refundedTargets = {}  -- ordered list of refunded {key, nodeID}
  for _, d in ipairs(drops) do
    local target = lookup[d.name]
    if target and not target.isChoice then
      local ni = C_Traits.GetNodeInfo(configID, target.nodeID)
      if ni and (ni.currentRank or 0) > 0
          and ni.canRefundRank and C_Traits.RefundRank then
        if C_Traits.RefundRank(configID, target.nodeID) then
          table.insert(refundedTargets, target)
        end
      end
    end
  end

  -- Phase 2 — purchase every pick that's reachable.
  local nonChoicePurchases = 0
  for _, p in ipairs(picks) do
    local target = lookup[p.name]
    if not target then
      table.insert(skipped, p.name)
    else
      local nodeInfo = C_Traits.GetNodeInfo(configID, target.nodeID)
      if nodeInfo then
        if target.isChoice then
          local active = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
          if active ~= target.entryID then
            if C_Traits.SetSelection(configID, target.nodeID, target.entryID) then
              applied = applied + 1
            end
          end
        else
          local currentRank = nodeInfo.currentRank or 0
          local maxRanks    = nodeInfo.maxRanks or 1
          if currentRank < maxRanks then
            local ni = C_Traits.GetNodeInfo(configID, target.nodeID)
            if ni and ni.canPurchaseRank
                and C_Traits.PurchaseRank(configID, target.nodeID) then
              applied = applied + 1
              nonChoicePurchases = nonChoicePurchases + 1
            end
          end
        end
      end
    end
  end

  -- Phase 3 — roll back any refunds we didn't end up needing. Drops are
  -- fungible (each refund just freed a point) so we pop from the tail.
  local orphans = #refundedTargets - nonChoicePurchases
  for i = 1, orphans do
    local target = table.remove(refundedTargets)
    if target and C_Traits.PurchaseRank then
      C_Traits.PurchaseRank(configID, target.nodeID)
    end
  end

  if applied == 0 then
    print("|cff00ccffZugZug:|r No swaps needed — already aligned.")
    return false
  end

  if not C_Traits.ConfigHasStagedChanges(configID) then
    print("|cff00ccffZugZug:|r No staged changes after swap pass.")
    return false
  end

  if C_ClassTalents.CommitConfig(configID) then
    print(string.format("|cff00ccffZugZug:|r Applied %d talent swap%s.", applied, applied == 1 and "" or "s"))
    if #skipped > 0 then
      print("|cff00ccffZugZug:|r Couldn't find: " .. table.concat(skipped, ", "))
    end
    return true
  end

  print("|cff00ccffZugZug:|r Failed to commit talent changes.")
  return false
end

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

  -- Bottom row: just the build label (popularity moved to pill)
  item.metaText:SetText(build.label or "")
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
    if not ok then print("|cff00ccffZugZug:|r Could not open settings.") end
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

  -- Reset section headers
  menu.headers = menu.headers or {}
  for _, h in ipairs(menu.headers) do h.frame:Hide() end

  local DROPDOWN_MENU_WIDTH = 430
  local SECTION_HEADER_HEIGHT = 20

  local yOffset = -4
  local lastSpec = nil
  local headerIdx = 0

  for i, build in ipairs(builds) do
    -- Add a section header when the spec changes
    if build.spec ~= lastSpec then
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
      local isCurr = (build.spec == ZZ.specName)
      if isCurr then
        local cr, cg, cb = getClassColor()
        hf.accent:SetColorTexture(cr, cg, cb, 1)
        hf.label:SetText(build.spec or "")
        hf.label:SetTextColor(cr, cg, cb)
        hf.tag:SetText("CURRENT SPEC")
        hf.tag:SetTextColor(0.5, 0.5, 0.55)
      else
        hf.accent:SetColorTexture(0.25, 0.25, 0.30, 1)
        hf.label:SetText(build.spec or "")
        hf.label:SetTextColor(0.45, 0.45, 0.5)
        hf.tag:SetText("")
      end
      hf:Show()
      yOffset = yOffset - SECTION_HEADER_HEIGHT
    end
    lastSpec = build.spec

    if not menu.items[i] then
      menu.items[i] = createDropdownItem(menu, i)
    end
    local item = menu.items[i]
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, yOffset)
    item:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, yOffset)

    local isCurrentSpec = (build.spec == ZZ.specName)
    populateDropdownItem(item, build, contentType, sectionColor, isCurrentSpec)
    yOffset = yOffset - DROPDOWN_ITEM_HEIGHT
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
    if not preferSpec or b.spec == preferSpec then
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
castEventFrame:RegisterEvent("UNIT_SPELLCAST_START")
castEventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
castEventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castEventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
castEventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
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
      if bar then
        if bar:IsShown() then
          bar:Hide()
        else
          applyBarPosition(barAttachedTo)
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
