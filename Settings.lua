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

local function CreateToggle(parent, x, y, label, dbKey)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  cb.text:SetText(label)
  cb:SetChecked(ZugZugDB[dbKey])
  cb:SetScript("OnClick", function(self)
    ZugZugDB[dbKey] = self:GetChecked()
  end)
  return cb
end

local function CreateDropdownSetting(parent, x, y, label, dbKey, options)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(label)

  local dropdown = CreateFrame("Frame", "ZugZugDropdown_" .. dbKey, parent, "UIDropDownMenuTemplate")
  dropdown:SetPoint("LEFT", fs, "LEFT", 200, -2)

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
  local panel = CreateFrame("Frame", "ZugZugSettingsPanel")
  panel.name = "ZugZug"

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

  -- Dungeon key level
  CreateDropdownSetting(panel, 16, startY - 92, "Dungeon Suggest Key Level", "suggestMpBucket", {
    { value = "all",  label = "All" },
    { value = "15+",  label = "15+" },
    { value = "18+",  label = "18+" },
    { value = "20+",  label = "20+" },
  })

  -- Spec filter
  CreateDropdownSetting(panel, 16, startY - 138, "Only Suggest Current Spec", "suggestSpecFilter", {
    { value = "all",     label = "All Content" },
    { value = "raid",    label = "Raid Only" },
    { value = "dungeon", label = "Dungeon Only" },
    { value = "none",    label = "Off (Any Spec)" },
  })

  -- Fade timer
  CreateSliderSetting(panel, 16, startY - 190, "Auto-Hide Timer", "suggestFadeTimer", 0, 30, 1)

  return panel
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
