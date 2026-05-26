----------------------------------------------------------------------
-- ZugZug — Settings Panel
-- Custom options frame registered in AddOns settings
----------------------------------------------------------------------

local ZZ = _G.ZugZug

----------------------------------------------------------------------
-- UI helpers
----------------------------------------------------------------------

local BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 1,
}

local function CreateLabel(parent, x, y, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function CreateToggle(parent, x, y, label, dbKey, onChange)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  cb.text:SetText(label)
  cb:SetChecked(ZugZugDB[dbKey])
  cb:SetScript("OnClick", function(self)
    ZugZugDB[dbKey] = self:GetChecked()
    if onChange then onChange(self:GetChecked()) end
  end)
  return cb
end

local function CreateDropdownSetting(parent, x, y, label, dbKey, options, description)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(label)

  local dropdown = CreateFrame("Frame", "ZugZugDropdown_" .. dbKey, parent, "UIDropDownMenuTemplate")
  dropdown:SetPoint("LEFT", fs, "LEFT", 200, -2)

  -- Optional description, anchored below the dropdown widget so it doesn't overlap.
  if description then
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -22)
    desc:SetJustifyH("LEFT")
    desc:SetText(description)
    desc:SetTextColor(0.55, 0.55, 0.60)
  end

  local function Initialize(self, level)
    for _, opt in ipairs(options) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.label
      info.value = opt.value
      info.checked = (ZugZugDB[dbKey] == opt.value)
      info.func = function()
        ZugZugDB[dbKey] = opt.value
        UIDropDownMenu_SetText(dropdown, opt.label)
        CloseDropDownMenus()
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end

  UIDropDownMenu_SetWidth(dropdown, 150)
  UIDropDownMenu_Initialize(dropdown, Initialize)

  -- Set initial text
  for _, opt in ipairs(options) do
    if ZugZugDB[dbKey] == opt.value then
      UIDropDownMenu_SetText(dropdown, opt.label)
      break
    end
  end

  return dropdown
end

local function CreateSliderSetting(parent, x, y, label, dbKey, minVal, maxVal, step)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(label)

  local slider = CreateFrame("Slider", "ZugZugSlider_" .. dbKey, parent, "OptionsSliderTemplate")
  slider:SetPoint("LEFT", fs, "LEFT", 220, 0)
  slider:SetWidth(180)
  slider:SetMinMaxValues(minVal, maxVal)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)
  slider:SetValue(ZugZugDB[dbKey] or 15)
  slider.Low:SetText(minVal)
  slider.High:SetText(maxVal)

  local valueText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  valueText:SetPoint("TOP", slider, "BOTTOM", 0, -2)

  local function UpdateText(val)
    if val == 0 then
      valueText:SetText("Never")
    else
      valueText:SetText(val .. "s")
    end
  end
  UpdateText(ZugZugDB[dbKey] or 15)

  slider:SetScript("OnValueChanged", function(self, val)
    val = math.floor(val + 0.5)
    ZugZugDB[dbKey] = val
    UpdateText(val)
  end)

  return slider
end

----------------------------------------------------------------------
-- Build the panel
----------------------------------------------------------------------

local function CreateSettingsPanel()
  -- Canvas registered with the Settings system
  local canvas = CreateFrame("Frame", "ZugZugSettingsPanel")
  canvas.name = "ZugZug"

  -- Scroll frame fills the canvas (leaving room on the right for the scrollbar)
  local scrollFrame = CreateFrame("ScrollFrame", "ZugZugSettingsScroll", canvas, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -8)
  scrollFrame:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -28, 8)

  -- Scroll child holds all the controls. All existing layout uses `panel`,
  -- so we point `panel` at the scroll child and everything lands inside it.
  local panel = CreateFrame("Frame", "ZugZugSettingsContent", scrollFrame)
  panel:SetSize(600, 600)
  scrollFrame:SetScrollChild(panel)
  scrollFrame:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then panel:SetWidth(w) end end)

  -- Title
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("|cff8fbf3fZugZug|r Settings")

  -- Subtitle
  local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  sub:SetText("Smart Suggest — auto-recommend builds for raid bosses and dungeons")

  local startY = -70

  -- Enable toggle
  CreateToggle(panel, 16, startY, "Enable Smart Suggest", "suggestEnabled")

  -- Raid difficulty
  CreateDropdownSetting(panel, 16, startY - 46, "Raid Suggest Difficulty", "suggestRaidDiff", {
    { value = "auto",   label = "Current Difficulty" },
    { value = "heroic", label = "Heroic" },
    { value = "mythic", label = "Mythic" },
  })

  -- Default M+ key level (used when no active keystone)
  CreateDropdownSetting(panel, 16, startY - 92, "Default M+ Key Level", "suggestMpBucket", {
    { value = "all",  label = "All keys" },
    { value = "15+",  label = "Keys 15+" },
    { value = "18+",  label = "Keys 18+" },
    { value = "20+",  label = "Keys 20+" },
  }, "What key level to use for build percentages. Will be used for auto suggestions as well.")

  -- Spec filter (shifted down 20px to leave room for description above)
  CreateDropdownSetting(panel, 16, startY - 158, "Only Suggest Current Spec", "suggestSpecFilter", {
    { value = "all",     label = "All Content" },
    { value = "raid",    label = "Raid Only" },
    { value = "dungeon", label = "Dungeon Only" },
    { value = "none",    label = "Off (Any Spec)" },
  })

  -- Fade timer
  CreateSliderSetting(panel, 16, startY - 210, "Auto-Hide Timer", "suggestFadeTimer", 0, 30, 1)

  -- Frame section
  local frameLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frameLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, startY - 270)
  frameLabel:SetText("|cff8fbf3fFrame|r")

  CreateToggle(panel, 16, startY - 300, "Lock Frame Position", "barLocked", function()
    local ZZ = _G.ZugZug
    if ZZ and ZZ.UpdateBarLockState then ZZ:UpdateBarLockState() end
  end)

  local clampToggle = CreateToggle(panel, 16, startY - 330, "Clamp to Talent Page", "barClamped", function()
    local ZZ = _G.ZugZug
    if ZZ and ZZ.UpdateBarClampState then ZZ:UpdateBarClampState() end
  end)
  clampToggle.text:SetText("Clamp to Talent Page  |cff888888(follow talent frame when it moves)|r")

  local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  resetBtn:SetSize(140, 22)
  resetBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, startY - 365)
  resetBtn:SetText("Reset Position")
  resetBtn:SetScript("OnClick", function()
    local ZZ = _G.ZugZug
    if ZZ and ZZ.ResetBarPosition then ZZ:ResetBarPosition() end
  end)

  -- Leveling section
  local levelingLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  levelingLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, startY - 410)
  levelingLabel:SetText("|cff8fbf3fLeveling|r")

  local levelingToggle = CreateToggle(panel, 16, startY - 440, "Enable Leveling Guide", "levelingEnabled", function()
    local ZZ = _G.ZugZug
    if ZZ and ZZ.UpdateLevelingEnabled then ZZ:UpdateLevelingEnabled() end
  end)
  levelingToggle.text:SetText("Enable Leveling Guide  |cff888888(banner + bar button below max level)|r")

  local atMaxToggle = CreateToggle(panel, 16, startY - 470, "Show at Max Level", "levelingAtMax", function()
    local ZZ = _G.ZugZug
    if ZZ and ZZ.UpdateLevelingEnabled then ZZ:UpdateLevelingEnabled() end
  end)
  atMaxToggle.text:SetText("Show at Max Level  |cff888888(for open world / delves)|r")

  -- Size the scroll child to fit all content (last control sits near startY - 470)
  panel:SetHeight(math.abs(startY - 470) + 60)

  return canvas
end

----------------------------------------------------------------------
-- Register
----------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  local ok, err = pcall(function()
    local panel = CreateSettingsPanel()
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    ZZ.settingsCategory = category
  end)
  if not ok then
    print("|cff00ccffZugZug:|r Settings panel failed: " .. tostring(err))
  end
  self:UnregisterEvent("PLAYER_LOGIN")
end)
