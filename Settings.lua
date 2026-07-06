----------------------------------------------------------------------
-- ZugZug — Settings Panel
-- Built on the modern Settings API (vertical layout + initializers)
-- instead of a hand-rolled canvas: controls stay in sync with the DB
-- automatically (no stale checkboxes), settings are searchable from the
-- options search box, and no legacy UIDropDownMenu taint vector.
----------------------------------------------------------------------

local ZZ = _G.ZugZug

local function default(key, fallback)
  local d = ZZ.DEFAULTS and ZZ.DEFAULTS[key]
  if d == nil then return fallback end
  return d
end

local function CreateSettingsPanel()
  local category, layout = Settings.RegisterVerticalLayoutCategory("ZugZug")

  local function onChanged(handlerName)
    return function()
      if ZZ[handlerName] then ZZ[handlerName](ZZ) end
    end
  end

  --- Register a boolean setting + checkbox row.
  local function AddCheckbox(key, label, tooltip, changedHandler)
    local setting = Settings.RegisterAddOnSetting(
      category, "ZUGZUG_" .. key, key, ZugZugDB, "boolean", label, default(key, false))
    Settings.CreateCheckbox(category, setting, tooltip)
    if changedHandler and setting.SetValueChangedCallback then
      setting:SetValueChangedCallback(onChanged(changedHandler))
    end
    return setting
  end

  --- Register a string setting + dropdown row. options = { {value, label}, ... }
  local function AddDropdown(key, label, tooltip, options, changedHandler)
    local setting = Settings.RegisterAddOnSetting(
      category, "ZUGZUG_" .. key, key, ZugZugDB, "string", label, default(key, options[1].value))
    local function GetOptions()
      local container = Settings.CreateControlTextContainer()
      for _, opt in ipairs(options) do
        container:Add(opt.value, opt.label)
      end
      return container:GetData()
    end
    Settings.CreateDropdown(category, setting, GetOptions, tooltip)
    if changedHandler and setting.SetValueChangedCallback then
      setting:SetValueChangedCallback(onChanged(changedHandler))
    end
    return setting
  end

  --- Register a number setting + slider row.
  local function AddSlider(key, label, tooltip, minVal, maxVal, step, formatter)
    local setting = Settings.RegisterAddOnSetting(
      category, "ZUGZUG_" .. key, key, ZugZugDB, "number", label, default(key, minVal))
    local options = Settings.CreateSliderOptions(minVal, maxVal, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
    Settings.CreateSlider(category, setting, options, tooltip)
    return setting
  end

  --- Section header row.
  local function AddHeader(text)
    if layout and CreateSettingsListSectionHeaderInitializer then
      layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
  end

  -- ── Data Source ────────────────────────────────────────────────────
  AddHeader("Data Source")
  AddDropdown("dataSource", "Build Data Source",
    "Where builds and suggestions come from. ZugZug = zugzug.info's WarcraftLogs pipeline. Raider.IO = raider.io/specs statistics (much larger samples, key-level brackets, recommendation verdicts).", {
      { value = "zugzug",   label = "ZugZug (zugzug.info)" },
      { value = "raiderio", label = "Raider.IO (raider.io/specs)" },
    }, "OnDataSourceChanged")

  -- ── Smart Suggest ──────────────────────────────────────────────────
  AddHeader("Smart Suggest")
  AddCheckbox("suggestEnabled", "Enable Smart Suggest",
    "Auto-recommend builds when you target raid bosses or zone into dungeons.")
  AddDropdown("suggestRaidDiff", "Raid Suggest Difficulty",
    "Which difficulty's data raid suggestions use. \"Current Difficulty\" follows the instance setting.", {
      { value = "auto",   label = "Current Difficulty" },
      { value = "heroic", label = "Heroic" },
      { value = "mythic", label = "Mythic" },
    })
  AddDropdown("suggestMpBucket", "Default M+ Key Level",
    "Key-level bracket used for build percentages and dungeon suggestions when your own keystone doesn't decide it.", {
      { value = "all", label = "All keys" },
      { value = "15+", label = "Keys 15+" },
      { value = "18+", label = "Keys 18+" },
      { value = "20+", label = "Keys 20+" },
    })
  AddDropdown("suggestSpecFilter", "Only Suggest Current Spec",
    "Restrict suggestions to builds for your active specialization.", {
      { value = "all",     label = "All Content" },
      { value = "raid",    label = "Raid Only" },
      { value = "dungeon", label = "Dungeon Only" },
      { value = "none",    label = "Off (Any Spec)" },
    })
  AddSlider("suggestFadeTimer", "Auto-Hide Timer",
    "Seconds before the suggestion popup hides itself. 0 keeps it open until dismissed.",
    0, 30, 1, function(v) return v == 0 and "Never" or (v .. "s") end)

  -- ── Applying builds ────────────────────────────────────────────────
  AddHeader("Applying Builds")
  AddCheckbox("useDedicatedLoadout", "Use a dedicated \"ZugZug\" loadout",
    "Applies land in a loadout named ZugZug and switch to it, leaving your own loadouts untouched. Disable to stage builds directly onto your active loadout instead. Either way, /zz undo reverts the last apply.")

  -- ── Frame ──────────────────────────────────────────────────────────
  AddHeader("Frame")
  AddCheckbox("barLocked", "Lock Frame Position",
    "Prevents dragging the build bar.", "UpdateBarLockState")
  AddCheckbox("barClamped", "Clamp to Talent Page",
    "The bar follows the talent frame when it moves. Unchecked, the bar keeps an absolute screen position.", "UpdateBarClampState")

  -- Reset-position button (initializer API — skip silently if unavailable).
  if layout and CreateSettingsButtonInitializer then
    local ok, initializer = pcall(CreateSettingsButtonInitializer,
      "", "Reset Position",
      function() if ZZ.ResetBarPosition then ZZ:ResetBarPosition() end end,
      "Reset the build bar to its default anchor.", true)
    if ok and initializer then
      layout:AddInitializer(initializer)
    end
  end

  -- ── Leveling ───────────────────────────────────────────────────────
  AddHeader("Leveling")
  AddCheckbox("levelingEnabled", "Enable Leveling Guide",
    "Show the leveling banner and bar button below max level.", "UpdateLevelingEnabled")
  AddCheckbox("levelingAtMax", "Show at Max Level",
    "Keep the leveling guide available at max level (open world / delve builds).", "UpdateLevelingEnabled")

  Settings.RegisterAddOnCategory(category)
  return category
end

----------------------------------------------------------------------
-- Register
----------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  local ok, result = pcall(CreateSettingsPanel)
  if ok then
    ZZ.settingsCategory = result
  else
    print("|cff00ccffZugZug:|r Settings panel failed: " .. tostring(result))
  end
  self:UnregisterEvent("PLAYER_LOGIN")
end)
