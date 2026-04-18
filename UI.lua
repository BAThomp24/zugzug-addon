----------------------------------------------------------------------
-- ZugZug — UI
-- Talent frame integration: a bottom bar with raid & M+ build cards,
-- anchored to the right of the search bar at the bottom of the
-- talent frame.
----------------------------------------------------------------------

local ZZ = _G.ZugZug

-- Colors
local COLORS = {
  header    = { r = 0, g = 0.8, b = 1 },       -- cyan
  raid      = { r = 1, g = 0.75, b = 0.2 },     -- gold
  mp        = { r = 0.4, g = 0.85, b = 0.4 },   -- green
  muted     = { r = 0.6, g = 0.6, b = 0.65 },
  text      = { r = 0.9, g = 0.9, b = 0.92 },
  bg        = { r = 0.12, g = 0.12, b = 0.14, a = 0.95 },
  border    = { r = 0.25, g = 0.25, b = 0.3, a = 1 },
  hover     = { r = 0.15, g = 0.15, b = 0.2, a = 1 },
}

local TREND_ICONS = {
  new  = "|cff4DD8FFNEW|r",
  up   = "|cff4DFF4D\226\150\178|r",    -- ▲
  down = "|cffFF6666\226\150\188|r",     -- ▼
  flat = "",
}

local BAR_HEIGHT = 60
local CARD_WIDTH = 150
local CARD_HEIGHT = 44
local CARD_GAP = 4
local PADDING = 6
local SECTION_LABEL_WIDTH = 48

----------------------------------------------------------------------
-- Bar frame (anchored to bottom of talent frame)
----------------------------------------------------------------------

local bar = nil
local buildCards = {}

local function createBar(parent)
  if bar then return bar end

  bar = CreateFrame("Frame", "ZugZugBar", parent, "BackdropTemplate")
  bar:SetHeight(BAR_HEIGHT)
  bar:SetFrameStrata("HIGH")
  bar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  bar:SetBackdropColor(COLORS.bg.r, COLORS.bg.g, COLORS.bg.b, COLORS.bg.a)
  bar:SetBackdropBorderColor(COLORS.border.r, COLORS.border.g, COLORS.border.b, COLORS.border.a)

  -- Settings buttons at the left edge
  local diffBtn = CreateFrame("Button", nil, bar, "BackdropTemplate")
  diffBtn:SetSize(68, 18)
  diffBtn:SetPoint("TOPLEFT", bar, "TOPLEFT", PADDING, -PADDING)
  diffBtn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  diffBtn:SetBackdropColor(0.12, 0.12, 0.15, 1)
  diffBtn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

  local diffText = diffBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  diffText:SetPoint("CENTER")
  diffBtn.label = diffText

  diffBtn:SetScript("OnClick", function()
    if ZugZugDB.raidDifficulty == "mythic" then
      ZugZugDB.raidDifficulty = "heroic"
    else
      ZugZugDB.raidDifficulty = "mythic"
    end
    ZZ:RefreshUI()
  end)
  diffBtn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(COLORS.hover.r, COLORS.hover.g, COLORS.hover.b, 1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Click to toggle raid difficulty")
    GameTooltip:Show()
  end)
  diffBtn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0.12, 0.12, 0.15, 1)
    GameTooltip:Hide()
  end)
  bar.diffBtn = diffBtn

  local keyBtn = CreateFrame("Button", nil, bar, "BackdropTemplate")
  keyBtn:SetSize(68, 18)
  keyBtn:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", PADDING, PADDING)
  keyBtn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  keyBtn:SetBackdropColor(0.12, 0.12, 0.15, 1)
  keyBtn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

  local keyText = keyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  keyText:SetPoint("CENTER")
  keyBtn.label = keyText

  local KEY_CYCLE = { "all", "15+", "18+", "20+" }
  keyBtn:SetScript("OnClick", function()
    local cur = ZugZugDB.mpBucket or "all"
    for i, v in ipairs(KEY_CYCLE) do
      if v == cur then
        ZugZugDB.mpBucket = KEY_CYCLE[(i % #KEY_CYCLE) + 1]
        break
      end
    end
    ZZ:RefreshUI()
  end)
  keyBtn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(COLORS.hover.r, COLORS.hover.g, COLORS.hover.b, 1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Click to cycle M+ key level filter")
    GameTooltip:Show()
  end)
  keyBtn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0.12, 0.12, 0.15, 1)
    GameTooltip:Hide()
  end)
  bar.keyBtn = keyBtn

  -- Content area starts after the settings buttons
  bar.contentStartX = PADDING + 68 + CARD_GAP

  bar:Hide()
  return bar
end

----------------------------------------------------------------------
-- Build card creation
----------------------------------------------------------------------

local function createBuildCard(parent)
  local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
  card:SetSize(CARD_WIDTH, CARD_HEIGHT)
  card:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  card:SetBackdropColor(0.1, 0.1, 0.13, 1)
  card:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)

  -- Top line: spec (+ hero)
  local nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nameText:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -5)
  nameText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -5)
  nameText:SetJustifyH("LEFT")
  nameText:SetWordWrap(false)
  card.nameText = nameText

  -- Bottom line: label + trend + pop
  local metaText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  metaText:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 6, 5)
  metaText:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -6, 5)
  metaText:SetJustifyH("LEFT")
  metaText:SetWordWrap(false)
  metaText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
  card.metaText = metaText

  -- Click → import via hidden edit box (copies to clipboard)
  card:SetScript("OnClick", function(self)
    if not self.importString or self.importString == "" then
      print("|cff00ccffZugZug:|r No import string for this build.")
      return
    end
    ZZ:CopyImportString(self.importString, self.buildLabel or "build")
  end)

  -- Hover
  card:SetScript("OnEnter", function(self)
    self:SetBackdropColor(COLORS.hover.r, COLORS.hover.g, COLORS.hover.b, 1)
    self:SetBackdropBorderColor(COLORS.header.r, COLORS.header.g, COLORS.header.b, 0.6)

    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    -- Title line
    local specHero = self.fullName or ""
    GameTooltip:SetText(specHero, COLORS.text.r, COLORS.text.g, COLORS.text.b)
    -- Popularity
    if self.popularity then
      GameTooltip:AddLine(self.popularity .. "% popularity", COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
    end
    -- Boss/dungeon context
    if self.contextList and #self.contextList > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Best for:", 1, 0.82, 0.2)
      for _, name in ipairs(self.contextList) do
        GameTooltip:AddLine("  " .. name, COLORS.text.r, COLORS.text.g, COLORS.text.b)
      end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to copy import string", COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
    GameTooltip:Show()
  end)

  card:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0.1, 0.1, 0.13, 1)
    self:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
    GameTooltip:Hide()
  end)

  return card
end

----------------------------------------------------------------------
-- Populate a build card
----------------------------------------------------------------------

local function populateCard(card, build, contentType, sectionColor)
  local specHero = build.spec
  if build.hero and build.hero ~= "" then
    specHero = specHero .. " — " .. build.hero
  end
  card.nameText:SetText(specHero)
  card.nameText:SetTextColor(COLORS.text.r, COLORS.text.g, COLORS.text.b)

  local trendStr = TREND_ICONS[build.trend] or ""
  local meta = build.label .. "  " .. build.popularity .. "%"
  if trendStr ~= "" then
    meta = meta .. " " .. trendStr
  end
  card.metaText:SetText(meta)

  card.importString = build.importString
  card.buildLabel = build.label
  card.fullName = specHero
  card.popularity = build.popularity

  if contentType == "raid" then
    card.contextList = build.bosses
  else
    card.contextList = build.dungeons
  end

  -- Tint the left border with section color
  card:SetBackdropBorderColor(sectionColor.r, sectionColor.g, sectionColor.b, 0.4)

  card:Show()
end

----------------------------------------------------------------------
-- Refresh the bar contents
----------------------------------------------------------------------

function ZZ:RefreshUI()
  if not bar then return end
  if not bar:IsShown() then return end

  -- Update settings buttons
  local diff = ZugZugDB.raidDifficulty or "mythic"
  bar.diffBtn.label:SetText("Raid: " .. diff:sub(1,1):upper() .. diff:sub(2))
  bar.diffBtn.label:SetTextColor(COLORS.raid.r, COLORS.raid.g, COLORS.raid.b)

  local bucket = ZugZugDB.mpBucket or "all"
  bar.keyBtn.label:SetText("M+: " .. bucket)
  bar.keyBtn.label:SetTextColor(COLORS.mp.r, COLORS.mp.g, COLORS.mp.b)

  -- Get builds
  local raidBuilds, mpBuilds = ZZ:GetCurrentBuilds()

  -- Hide all existing cards
  for _, card in ipairs(buildCards) do
    card:Hide()
  end

  -- Hide section labels
  if bar.raidLabel then bar.raidLabel:Hide() end
  if bar.mpLabel then bar.mpLabel:Hide() end
  if bar.divider then bar.divider:Hide() end
  if bar.emptyText then bar.emptyText:Hide() end

  local xOffset = bar.contentStartX
  local cardIndex = 0
  local centerY = 0 -- vertically centered in bar

  -- Raid section
  if raidBuilds and #raidBuilds > 0 then
    -- Section label
    if not bar.raidLabel then
      bar.raidLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    end
    bar.raidLabel:ClearAllPoints()
    bar.raidLabel:SetPoint("LEFT", bar, "LEFT", xOffset, centerY)
    bar.raidLabel:SetText("RAID")
    bar.raidLabel:SetTextColor(COLORS.raid.r, COLORS.raid.g, COLORS.raid.b)
    bar.raidLabel:Show()
    xOffset = xOffset + SECTION_LABEL_WIDTH

    for _, build in ipairs(raidBuilds) do
      cardIndex = cardIndex + 1
      if not buildCards[cardIndex] then
        buildCards[cardIndex] = createBuildCard(bar)
      end
      local card = buildCards[cardIndex]
      card:ClearAllPoints()
      card:SetPoint("LEFT", bar, "LEFT", xOffset, centerY)
      populateCard(card, build, "raid", COLORS.raid)
      xOffset = xOffset + CARD_WIDTH + CARD_GAP
    end

    xOffset = xOffset + CARD_GAP
  end

  -- Divider between raid and M+
  if raidBuilds and #raidBuilds > 0 and mpBuilds and #mpBuilds > 0 then
    if not bar.divider then
      bar.divider = bar:CreateTexture(nil, "OVERLAY")
      bar.divider:SetColorTexture(COLORS.border.r, COLORS.border.g, COLORS.border.b, 0.6)
      bar.divider:SetSize(1, CARD_HEIGHT)
    end
    bar.divider:ClearAllPoints()
    bar.divider:SetPoint("LEFT", bar, "LEFT", xOffset, centerY)
    bar.divider:Show()
    xOffset = xOffset + CARD_GAP + 1
  end

  -- M+ section
  if mpBuilds and #mpBuilds > 0 then
    if not bar.mpLabel then
      bar.mpLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    end
    bar.mpLabel:ClearAllPoints()
    bar.mpLabel:SetPoint("LEFT", bar, "LEFT", xOffset, centerY)
    bar.mpLabel:SetText("M+")
    bar.mpLabel:SetTextColor(COLORS.mp.r, COLORS.mp.g, COLORS.mp.b)
    bar.mpLabel:Show()
    xOffset = xOffset + SECTION_LABEL_WIDTH - 12

    for _, build in ipairs(mpBuilds) do
      cardIndex = cardIndex + 1
      if not buildCards[cardIndex] then
        buildCards[cardIndex] = createBuildCard(bar)
      end
      local card = buildCards[cardIndex]
      card:ClearAllPoints()
      card:SetPoint("LEFT", bar, "LEFT", xOffset, centerY)
      populateCard(card, build, "mp", COLORS.mp)
      xOffset = xOffset + CARD_WIDTH + CARD_GAP
    end
  end

  -- No builds at all
  if cardIndex == 0 then
    if not bar.emptyText then
      bar.emptyText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    end
    bar.emptyText:ClearAllPoints()
    bar.emptyText:SetPoint("LEFT", bar, "LEFT", bar.contentStartX, centerY)
    bar.emptyText:SetText("No builds for your class/spec.")
    bar.emptyText:SetTextColor(COLORS.muted.r, COLORS.muted.g, COLORS.muted.b)
    bar.emptyText:Show()
  end

  -- Resize bar width to fit content
  bar:SetWidth(math.max(xOffset + PADDING, 200))
end

----------------------------------------------------------------------
-- Copy popup — shows an edit box with pre-selected text for Ctrl+C
----------------------------------------------------------------------

local copyPopup = nil

local function createCopyPopup()
  if copyPopup then return copyPopup end

  local f = CreateFrame("Frame", "ZugZugCopyPopup", UIParent, "BackdropTemplate")
  f:SetSize(380, 70)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  f:SetBackdropColor(0.1, 0.1, 0.12, 0.95)
  f:SetBackdropBorderColor(0, 0.8, 1, 0.8)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
  title:SetTextColor(0, 0.8, 1)
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
  closeBtn:GetFontString():SetTextColor(0.6, 0.6, 0.6)
  closeBtn:SetScript("OnClick", function() f:Hide() end)
  closeBtn:SetScript("OnEnter", function(self)
    self:GetFontString():SetTextColor(1, 0.3, 0.3)
  end)
  closeBtn:SetScript("OnLeave", function(self)
    self:GetFontString():SetTextColor(0.6, 0.6, 0.6)
  end)

  f:Hide()
  copyPopup = f
  return f
end

function ZZ:CopyImportString(importString, label)
  local popup = createCopyPopup()
  popup.title:SetText("|cff00ccffZugZug:|r " .. label .. "  —  Ctrl+C to copy, then paste into Import Loadout")
  popup.editBox:SetText(importString)
  popup:Show()
  popup.editBox:SetFocus()
  popup.editBox:HighlightText()
end

----------------------------------------------------------------------
-- Hook into talent frame
----------------------------------------------------------------------

local function hookTalentFrame()
  local function attachToFrame(talentFrame)
    if talentFrame.zugzugHooked then return end
    talentFrame.zugzugHooked = true

    createBar(talentFrame)

    -- Anchor below the talent frame so we never overlap the Apply button
    bar:SetPoint("TOPLEFT", talentFrame, "BOTTOMLEFT", 0, -2)

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
