----------------------------------------------------------------------
-- ZugZug Specs — Settings Panel
-- A canvas panel (translucent section cards + flow layout) matching the
-- ZugZug Keys panel. Registered as the "Specs" subcategory under a shared
-- "ZugZug" parent folder that both addons nest into, with a companion
-- switcher that opens ZugZug Keys (or prompts to install it).
--
-- Layout model (same as Keys):
--   * Flow anchoring — each row anchors below the previous, so wrapped text
--     pushes rows down instead of overlapping.
--   * Wrap-safe rows — check rows live in a frame re-fitted to their label.
--   * Section cards WRAP their rows (rows join the flow; the card's edges
--     anchor around them) — never the reverse, or WoW flags a cycle.
--   * Panel height measured from the last row after layout / on resize.
----------------------------------------------------------------------

local ZZ = _G.ZugZug

local GREEN     = { 0.56, 0.75, 0.25 }
local GREEN_HEX = "8fbf3f"
local BLUE_HEX  = "00ccff"   -- Specs accent (its long-standing chat color)

local RIGHT_PAD   = 16
local CARD_MARGIN = 14
local CARD_PAD    = 14
local IND_ITEM    = CARD_MARGIN + CARD_PAD        -- 28
local IND_NOTE    = CARD_MARGIN + CARD_PAD + 26   -- 54
local IND_SUB     = CARD_MARGIN + CARD_PAD + 14   -- 42
local IND_SUB2    = CARD_MARGIN + CARD_PAD + 28   -- 56
local IND_SUBNOTE = CARD_MARGIN + CARD_PAD + 40   -- 68

local SECTION_FONT = _G.GameFontNormalMed2 and "GameFontNormalMed2" or "GameFontNormal"
local TITLE_FONT   = _G.GameFontNormalHuge and "GameFontNormalHuge" or "GameFontNormalLarge"

-- Sibling addon (ZugZug Keys) coordinates: folder, loaded global, shared
-- category handle, CurseForge page.
local KEYS_FOLDER  = "ZugZugKeys"
local KEYS_CF_URL  = "https://www.curseforge.com/wow/addons/zugzug-keys"

local function siblingInstalled()
  if _G.ZugZugKeys then return true end
  if C_AddOns and C_AddOns.GetAddOnInfo then
    local name = C_AddOns.GetAddOnInfo(KEYS_FOLDER)
    return name ~= nil
  end
  return false
end

--- The shared "ZugZug" parent category — whichever addon loads first
--- creates it; both nest their panel under it as a subcategory.
local function ensureParentCategory()
  if _G.ZugZugSettingsParentCategory then return _G.ZugZugSettingsParentCategory end
  local cat = Settings.RegisterVerticalLayoutCategory("ZugZug")
  Settings.RegisterAddOnCategory(cat)
  _G.ZugZugSettingsParentCategory = cat
  return cat
end

local function CreateSettingsPanel()
  local canvas = CreateFrame("Frame", "ZugZugSpecsSettingsPanel")
  canvas.name = "Specs"

  local scrollFrame = CreateFrame("ScrollFrame", "ZugZugSpecsSettingsScroll", canvas, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -8)
  scrollFrame:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -28, 8)
  local panel = CreateFrame("Frame", "ZugZugSpecsSettingsContent", scrollFrame)
  panel:SetSize(600, 900)
  scrollFrame:SetScrollChild(panel)

  local checkRows = {}
  local last, lastIndent = nil, 0

  local function place(region, indent, gap)
    if last then
      region:SetPoint("TOPLEFT", last, "BOTTOMLEFT", indent - lastIndent, -(gap or 10))
    else
      region:SetPoint("TOPLEFT", panel, "TOPLEFT", indent, -16)
    end
    last, lastIndent = region, indent
  end

  ------------------------------------------------------------------
  -- Row builders
  ------------------------------------------------------------------
  local function CreateCheckRow(parent, markup, onClick)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(10, 26)
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", cb, "TOPRIGHT", 4, -6)
    text:SetPoint("RIGHT", parent, "RIGHT", -RIGHT_PAD, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetText(markup)
    cb:SetScript("OnClick", function(self)
      if onClick then onClick(self:GetChecked(), self) end
    end)
    row.cb, row.text = cb, text
    checkRows[#checkRows + 1] = row
    return row
  end

  local function CreateToggle(parent, label, dbKey, subtitle, onChange)
    local markup = label .. (subtitle and ("  |cff888888" .. subtitle .. "|r") or "")
    local row = CreateCheckRow(parent, markup, function(checked)
      ZugZugDB[dbKey] = checked
      if onChange then onChange(checked) end
    end)
    row.cb:SetChecked(ZugZugDB[dbKey])
    return row
  end

  local function CreateNote(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("RIGHT", panel, "RIGHT", -(CARD_MARGIN + RIGHT_PAD), 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText("|cff666666" .. text .. "|r")
    return fs
  end

  --- A mutually-exclusive group of check rows bound to one string DB key.
  --- options = { {value, label, subtitle}, ... }. Returns the refresh fn.
  local function CreateRadioGroup(parent, dbKey, options, indent, onChange)
    local rows = {}
    local function refresh()
      local cur = ZugZugDB[dbKey] or options[1].value
      for value, row in pairs(rows) do row.cb:SetChecked(value == cur) end
    end
    for i, opt in ipairs(options) do
      local markup = opt.label .. (opt.subtitle and ("  |cff888888" .. opt.subtitle .. "|r") or "")
      local row = CreateCheckRow(parent, markup, function()
        ZugZugDB[dbKey] = opt.value
        refresh()
        if onChange then onChange(opt.value) end
      end)
      rows[opt.value] = row
      place(row, indent, i == 1 and 6 or 2)
    end
    refresh()
    return refresh
  end

  ------------------------------------------------------------------
  -- Section cards
  ------------------------------------------------------------------
  local TOP_WRAP = 12
  local function beginSection(titleText, gapAbove, accent)
    accent = accent or GREEN
    local card = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    card:SetBackdrop({
      bgFile   = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Buttons\\WHITE8x8",
      edgeSize = 1,
    })
    card:SetBackdropColor(0.05, 0.06, 0.075, 0.55)
    card:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.18)

    local header = card:CreateFontString(nil, "OVERLAY", SECTION_FONT)
    header:SetTextColor(accent[1], accent[2], accent[3])
    header:SetText(titleText)
    place(header, IND_ITEM, gapAbove or 24)

    card:SetPoint("TOPLEFT", header, "TOPLEFT", -CARD_PAD, TOP_WRAP)
    card:SetPoint("RIGHT", panel, "RIGHT", -CARD_MARGIN, 0)

    local bullet = card:CreateTexture(nil, "ARTWORK")
    bullet:SetColorTexture(accent[1], accent[2], accent[3], 0.9)
    bullet:SetSize(3, 13)
    bullet:SetPoint("RIGHT", header, "LEFT", -6, 0)

    local div = card:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(accent[1], accent[2], accent[3], 0.20)
    div:SetHeight(1)
    place(div, IND_ITEM, 7)
    div:SetPoint("RIGHT", panel, "RIGHT", -(CARD_MARGIN + CARD_PAD), 0)

    return card
  end

  local function endSection(card, bottomPad)
    if card and last then
      card:SetPoint("BOTTOM", last, "BOTTOM", 0, -(bottomPad or 12))
    end
  end

  ------------------------------------------------------------------
  -- Header
  ------------------------------------------------------------------
  local title = panel:CreateFontString(nil, "OVERLAY", TITLE_FONT)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)
  title:SetText("|cff" .. BLUE_HEX .. "ZugZug|r Specs")
  place(title, CARD_MARGIN, 2)

  local accent = panel:CreateTexture(nil, "ARTWORK")
  accent:SetColorTexture(0, 0.8, 1, 0.7)
  accent:SetHeight(2)
  place(accent, CARD_MARGIN, 8)
  accent:SetPoint("RIGHT", panel, "RIGHT", -CARD_MARGIN, 0)

  local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("RIGHT", panel, "RIGHT", -CARD_MARGIN, 0)
  sub:SetJustifyH("LEFT")
  sub:SetWordWrap(true)
  sub:SetTextColor(0.7, 0.7, 0.7)
  sub:SetText("Top talent builds for raid & Mythic+, plus a leveling guide.")
  place(sub, CARD_MARGIN, 8)

  ------------------------------------------------------------------
  -- Companion — switch to ZugZug Keys, or offer to install it.
  ------------------------------------------------------------------
  local comp = beginSection("Companion Addon", 22)
  if siblingInstalled() then
    local n = CreateNote(comp, "ZugZug Keys is installed — Mythic+ key broadcast, group key info, and the Lust Reminder.")
    place(n, IND_ITEM, 6)
    local openBtn = CreateFrame("Button", nil, comp, "UIPanelButtonTemplate")
    openBtn:SetSize(190, 22)
    openBtn:SetText("Open ZugZug Keys settings")
    openBtn:SetScript("OnClick", function()
      local cat = _G.ZugZugKeysCategory
      if cat and cat.GetID and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(cat:GetID())
      elseif Settings and Settings.OpenToCategory then
        Settings.OpenToCategory("ZugZug Keys")
      end
    end)
    place(openBtn, IND_ITEM, 8)
  else
    local n = CreateNote(comp, "ZugZug Keys is a companion addon (Mythic+ key broadcast, group key info, Lust Reminder) — it isn't installed. Copy the link below (Ctrl+C) to grab it:")
    place(n, IND_ITEM, 6)
    local box = CreateFrame("EditBox", nil, comp, "InputBoxTemplate")
    box:SetSize(300, 22)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetText(KEYS_CF_URL)
    box:SetCursorPosition(0)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnTextChanged", function(self) self:SetText(KEYS_CF_URL); self:SetCursorPosition(0) end) -- read-only
    place(box, IND_ITEM + 6, 8)
  end
  endSection(comp, 12)

  ------------------------------------------------------------------
  -- Data Source
  ------------------------------------------------------------------
  local ds = beginSection("Build Data Source", 34)
  local dsNote = CreateNote(ds,
    "Where builds and suggestions come from. Raider.IO uses much larger samples with key-level brackets and recommendation verdicts; ZugZug is zugzug.info's WarcraftLogs pipeline.")
  place(dsNote, IND_ITEM, 6)
  CreateRadioGroup(ds, "dataSource", {
    { value = "zugzug",   label = "ZugZug", subtitle = "(zugzug.info — WarcraftLogs)" },
    { value = "raiderio", label = "Raider.IO", subtitle = "(raider.io/specs — larger samples, brackets, verdicts)" },
  }, IND_SUB, function() if ZZ.OnDataSourceChanged then ZZ.OnDataSourceChanged() end end)
  endSection(ds, 12)

  ------------------------------------------------------------------
  -- Smart Suggest
  ------------------------------------------------------------------
  local ss = beginSection("Smart Suggest", 34)
  local ssToggle = CreateToggle(ss, "Enable Smart Suggest", "suggestEnabled",
    "(recommend builds when you target bosses / zone into dungeons)")
  place(ssToggle, IND_ITEM, 10)

  local rdLabel = ss:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rdLabel:SetTextColor(0.85, 0.85, 0.85)
  rdLabel:SetText("Raid suggest difficulty")
  place(rdLabel, IND_SUB, 12)
  CreateRadioGroup(ss, "suggestRaidDiff", {
    { value = "auto",   label = "Current difficulty", subtitle = "(follow the instance)" },
    { value = "heroic", label = "Heroic" },
    { value = "mythic", label = "Mythic" },
  }, IND_SUB2)

  local mpLabel = ss:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  mpLabel:SetTextColor(0.85, 0.85, 0.85)
  mpLabel:SetText("Default M+ key bracket")
  place(mpLabel, IND_SUB, 14)
  local mpNote = CreateNote(ss, "Used when your own keystone doesn't decide it. Your keystone auto-selects the matching bracket in dungeons.")
  place(mpNote, IND_SUBNOTE, 2)
  CreateRadioGroup(ss, "suggestMpBucket", {
    { value = "all", label = "All keys" },
    { value = "15+", label = "Keys 15+" },
    { value = "18+", label = "Keys 18+" },
    { value = "20+", label = "Keys 20+" },
  }, IND_SUB2)

  local sfLabel = ss:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  sfLabel:SetTextColor(0.85, 0.85, 0.85)
  sfLabel:SetText("Restrict to current spec")
  place(sfLabel, IND_SUB, 14)
  CreateRadioGroup(ss, "suggestSpecFilter", {
    { value = "all",     label = "All content" },
    { value = "raid",    label = "Raid only" },
    { value = "dungeon", label = "Dungeon only" },
    { value = "none",    label = "Off", subtitle = "(any spec)" },
  }, IND_SUB2)

  -- Auto-hide timer stepper (0 = never).
  local fadeValue
  local function fadeText()
    local v = ZugZugDB.suggestFadeTimer or 15
    return string.format("Auto-hide: |cff%s%s|r", BLUE_HEX, v == 0 and "never" or (v .. "s"))
  end
  local fMinus = CreateFrame("Button", nil, ss, "UIPanelButtonTemplate")
  fMinus:SetSize(24, 22); fMinus:SetText("-")
  place(fMinus, IND_SUB, 14)
  local fPlus = CreateFrame("Button", nil, ss, "UIPanelButtonTemplate")
  fPlus:SetSize(24, 22); fPlus:SetText("+")
  fPlus:SetPoint("LEFT", fMinus, "RIGHT", 4, 0)
  fadeValue = ss:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fadeValue:SetPoint("LEFT", fPlus, "RIGHT", 10, 0)
  fadeValue:SetText(fadeText())
  local function stepFade(d)
    local v = (ZugZugDB.suggestFadeTimer or 15) + d
    if v < 0 then v = 0 end
    if v > 30 then v = 30 end
    ZugZugDB.suggestFadeTimer = v
    fadeValue:SetText(fadeText())
  end
  fMinus:SetScript("OnClick", function() stepFade(-1) end)
  fPlus:SetScript("OnClick", function() stepFade(1) end)
  endSection(ss, 12)

  ------------------------------------------------------------------
  -- Applying Builds
  ------------------------------------------------------------------
  local ap = beginSection("Applying Builds", 34)
  local dlToggle = CreateToggle(ap, "Use a dedicated \"ZugZug\" loadout", "useDedicatedLoadout")
  place(dlToggle, IND_ITEM, 10)
  local dlNote = CreateNote(ap,
    "Applies land in a talent loadout named ZugZug and switch to it, leaving your own loadouts untouched. Disable to stage builds onto your active loadout instead. Either way, /zz undo reverts the last apply.")
  place(dlNote, IND_NOTE, 4)
  endSection(ap, 12)

  ------------------------------------------------------------------
  -- Frame
  ------------------------------------------------------------------
  local fr = beginSection("Frame", 34)
  local lockToggle = CreateToggle(fr, "Lock frame position", "barLocked",
    "(prevents dragging the build bar)",
    function() if ZZ.UpdateBarLockState then ZZ:UpdateBarLockState() end end)
  place(lockToggle, IND_ITEM, 10)
  local clampToggle = CreateToggle(fr, "Clamp to talent page", "barClamped",
    "(bar follows the talent frame; off = fixed screen position)",
    function() if ZZ.UpdateBarClampState then ZZ:UpdateBarClampState() end end)
  place(clampToggle, IND_ITEM, 6)
  local resetBtn = CreateFrame("Button", nil, fr, "UIPanelButtonTemplate")
  resetBtn:SetSize(140, 22)
  resetBtn:SetText("Reset Position")
  resetBtn:SetScript("OnClick", function() if ZZ.ResetBarPosition then ZZ:ResetBarPosition() end end)
  place(resetBtn, IND_SUB, 8)
  endSection(fr, 12)

  ------------------------------------------------------------------
  -- Leveling
  ------------------------------------------------------------------
  local lv = beginSection("Leveling", 34)
  local lvToggle = CreateToggle(lv, "Enable leveling guide", "levelingEnabled",
    "(banner + bar button below max level)",
    function() if ZZ.UpdateLevelingEnabled then ZZ:UpdateLevelingEnabled() end end)
  place(lvToggle, IND_ITEM, 10)
  local lvMaxToggle = CreateToggle(lv, "Show at max level", "levelingAtMax",
    "(keep it available for open world / delves)",
    function() if ZZ.UpdateLevelingEnabled then ZZ:UpdateLevelingEnabled() end end)
  place(lvMaxToggle, IND_ITEM, 6)
  endSection(lv, 12)

  ------------------------------------------------------------------
  -- Footer
  ------------------------------------------------------------------
  local footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("RIGHT", panel, "RIGHT", -CARD_MARGIN, 0)
  footer:SetJustifyH("LEFT")
  footer:SetText("|cff555555Type|r |cff" .. BLUE_HEX .. "/zz|r|cff555555 for commands  ·  zugzug.info|r")
  place(footer, CARD_MARGIN, 18)

  ------------------------------------------------------------------
  -- Post-layout fit + measure
  ------------------------------------------------------------------
  local function fitRow(row)
    local th = row.text:GetStringHeight()
    if th and th > 0 then row:SetHeight(math.max(26, math.ceil(th) + 8)) end
  end
  local function relayout()
    for _, r in ipairs(checkRows) do fitRow(r) end
    C_Timer.After(0, function()
      local top, bottom = panel:GetTop(), footer:GetBottom()
      if top and bottom then panel:SetHeight(top - bottom + 24) end
    end)
  end
  scrollFrame:SetScript("OnSizeChanged", function(_, w)
    if w and w > 0 then panel:SetWidth(w) end
    C_Timer.After(0, relayout)
  end)
  panel:SetScript("OnShow", function() C_Timer.After(0, relayout) end)

  return canvas
end

----------------------------------------------------------------------
-- Register (as the "Specs" subcategory under the shared "ZugZug" parent)
----------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  local ok, result = pcall(function()
    local panel = CreateSettingsPanel()
    local parent = ensureParentCategory()
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(parent, panel, panel.name)
    _G.ZugZugSpecsCategory = subcategory
    ZZ.settingsCategory = subcategory
  end)
  if not ok then
    print("|cff00ccffZugZug Specs:|r Settings panel failed: " .. tostring(result))
  end
  self:UnregisterEvent("PLAYER_LOGIN")
end)
