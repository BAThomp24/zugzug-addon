----------------------------------------------------------------------
-- ZugZug — Core
-- Initialization, saved variables, slash commands, class/spec detection.
----------------------------------------------------------------------

local ADDON_NAME = select(1, ...)

-- Saved variables (persisted between sessions)
ZugZugDB = ZugZugDB or {}

-- Addon-wide state
local ZZ = {
  addonName = ADDON_NAME, -- folder name, used for texture paths
  classToken = nil,   -- e.g. "WARLOCK"
  specId = nil,       -- WoW spec ID (e.g. 265)
  specName = nil,     -- e.g. "Affliction"
  role = nil,         -- "dps" | "healer" | "tank"
  data = nil,         -- reference to ZugZugData once loaded
}

-- Expose for other files
_G.ZugZug = ZZ

----------------------------------------------------------------------
-- Defaults
----------------------------------------------------------------------

local DEFAULTS = {
  dataSource = "zugzug",           -- "zugzug" | "raiderio" — which dataset drives builds/suggestions
  raidDifficulty = "mythic",       -- "heroic" | "mythic"
  mpBucket = "all",                -- "all" | "15+" | "18+" | "20+"
  suggestEnabled = true,           -- master toggle
  suggestRaidDiff = "auto",         -- "auto" | "heroic" | "mythic"
  suggestMpBucket = "all",         -- which bucket data to suggest in dungeons
  suggestSpecFilter = "all",       -- "all" | "raid" | "dungeon" | "none"
  suggestFadeTimer = 15,           -- seconds before popup auto-hides
  barLocked = true,                -- lock the bar against dragging
  barClamped = true,               -- when true, bar follows talent frame; when false, bar uses absolute screen position
  barPosition = nil,               -- { point, relativePoint, x, y, clamped }; nil = default anchor
  levelingEnabled = true,          -- show leveling guide banner + bar button below max level
  levelingAtMax = false,           -- keep showing the leveling guide at max level (for open world / delves)
  useDedicatedLoadout = true,      -- apply builds into a "ZugZug" loadout instead of overwriting the active config
}
ZZ.DEFAULTS = DEFAULTS -- read by Settings.lua for Settings API default values

local function ensureDefaults()
  for k, v in pairs(DEFAULTS) do
    if ZugZugDB[k] == nil then
      ZugZugDB[k] = v
    end
  end
end

----------------------------------------------------------------------
-- Refresh current player info
----------------------------------------------------------------------

local ROLE_MAP = { DAMAGER = "dps", HEALER = "healer", TANK = "tank" }

-- The bare specialization globals were deprecated in 11.1.7 in favor of
-- C_SpecializationInfo; prefer the namespaced versions so a future shim
-- removal can't brick spec detection (and with it the whole addon).
local GetSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
local GetSpecInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo

local function refreshPlayerInfo()
  local _, classToken = UnitClass("player")
  ZZ.classToken = classToken

  local specIndex = GetSpec()
  if specIndex then
    local specId, specName, _, _, role = GetSpecInfo(specIndex)
    ZZ.specId = specId
    ZZ.specName = specName
    ZZ.role = ROLE_MAP[role] or "dps"
  end
end

----------------------------------------------------------------------
-- Get builds for current class + settings
----------------------------------------------------------------------

--- Locale-proof build↔player spec matching: prefer the numeric specId the
--- data pipeline ships; fall back to English-name equality for data
--- generated before specIds existed (or specs whose ID isn't mapped yet).
function ZZ:BuildMatchesSpec(build)
  if not build then return false end
  if build.specId and self.specId then
    return build.specId == self.specId
  end
  return build.spec == self.specName
end

function ZZ:GetCurrentBuilds()
  if not self.data or not self.classToken then return nil, nil end

  local classEntry = self.data.classes and self.data.classes[self.classToken]
  if not classEntry then return nil, nil end

  local roleData = classEntry[self.role]
  if not roleData then return nil, nil end

  local diff = ZugZugDB.raidDifficulty or "mythic"
  local bucket = ZugZugDB.mpBucket or "all"

  local raidBuilds = roleData.raid and roleData.raid[diff]
  local mpBuilds = roleData.mythicPlus and roleData.mythicPlus[bucket]

  return raidBuilds, mpBuilds
end

----------------------------------------------------------------------
-- Data source selection
----------------------------------------------------------------------

--- Point ZZ.data at the configured dataset. Both files ship in the addon:
--- Data.lua (ZugZugData, the zugzug.info pipeline) and DataRIO.lua
--- (ZugZugDataRIO, Raider.IO spec statistics). The RIO file stores dungeon
--- swaps once per spec (ZugZugDataRIO.swaps) instead of duplicating the
--- table across every build — stitch shared references onto builds here so
--- consumers see the same build.dungeonSwaps shape either way.
function ZZ.SelectDataSource()
  local want = ZugZugDB.dataSource or "zugzug"
  if want == "raiderio" and ZugZugDataRIO then
    if not ZugZugDataRIO.__stitched then
      local swaps = ZugZugDataRIO.swaps or {}
      for token, roles in pairs(ZugZugDataRIO.classes or {}) do
        for role, sections in pairs(roles) do
          local perSpec = swaps[token] and swaps[token][role]
          if perSpec and sections.mythicPlus then
            for _, builds in pairs(sections.mythicPlus) do
              for _, b in ipairs(builds) do
                b.dungeonSwaps = perSpec[b.spec]
              end
            end
          end
        end
      end
      ZugZugDataRIO.__stitched = true
    end
    ZZ.data = ZugZugDataRIO
  else
    if want == "raiderio" then
      print("|cff00ccffZugZug:|r Raider.IO data file missing — falling back to ZugZug data.")
    end
    ZZ.data = ZugZugData
  end
end

--- Settings dropdown hook (Settings.lua wires SetValueChangedCallback here).
function ZZ.OnDataSourceChanged()
  ZZ.SelectDataSource()
  if ZZ.RefreshUI then ZZ:RefreshUI() end
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

local VALID_DIFFICULTIES = { heroic = true, mythic = true }
local VALID_BUCKETS = { ["all"] = true, ["15+"] = true, ["18+"] = true, ["20+"] = true }

local function handleSlashCommand(msg)
  local cmd, arg = msg:match("^(%S+)%s*(.*)")
  if not cmd then cmd = msg end
  cmd = cmd:lower()
  -- Normalize the argument once so "/zz key ALL" and trailing spaces work.
  arg = strtrim((arg or ""):lower())

  if cmd == "difficulty" or cmd == "diff" then
    if VALID_DIFFICULTIES[arg] then
      ZugZugDB.raidDifficulty = arg
      print("|cff00ccffZugZug:|r Raid difficulty set to " .. arg)
      if ZZ.RefreshUI then ZZ:RefreshUI() end
    else
      print("|cff00ccffZugZug:|r Valid difficulties: heroic, mythic")
    end
    return
  end

  if cmd == "keylevel" or cmd == "key" or cmd == "bucket" then
    if VALID_BUCKETS[arg] then
      ZugZugDB.mpBucket = arg
      print("|cff00ccffZugZug:|r M+ key level set to " .. arg)
      if ZZ.RefreshUI then ZZ:RefreshUI() end
    else
      print("|cff00ccffZugZug:|r Valid key levels: all, 15+, 18+, 20+")
    end
    return
  end

  if cmd == "source" or cmd == "data" then
    local want = (arg == "rio" or arg == "raiderio") and "raiderio"
      or (arg == "zugzug" or arg == "zz") and "zugzug" or nil
    if want then
      ZugZugDB.dataSource = want
      ZZ.SelectDataSource()
      print("|cff00ccffZugZug:|r Data source set to "
        .. (ZZ.data == ZugZugDataRIO and "|cff8fbf3fRaider.IO|r" or "|cff8fbf3fZugZug|r"))
      if ZZ.RefreshUI then ZZ:RefreshUI() end
    else
      print("|cff00ccffZugZug:|r Valid sources: zugzug, raiderio")
    end
    return
  end

  if cmd == "suggest" then
    ZugZugDB.suggestEnabled = not ZugZugDB.suggestEnabled
    if ZugZugDB.suggestEnabled then
      print("|cff00ccffZugZug:|r Smart suggest |cff4DFF4Denabled|r")
    else
      print("|cff00ccffZugZug:|r Smart suggest |cffFF6666disabled|r")
    end
    return
  end

  if cmd == "status" then
    print("|cff00ccffZugZug:|r Status")
    print("  Class: " .. (ZZ.classToken or "unknown"))
    print("  Spec: " .. (ZZ.specName or "unknown") .. " (" .. (ZZ.role or "?") .. ")")
    print("  Raid difficulty: " .. (ZugZugDB.raidDifficulty or "mythic"))
    print("  M+ key level: " .. (ZugZugDB.mpBucket or "all"))
    print("  Smart suggest: " .. (ZugZugDB.suggestEnabled and "|cff4DFF4Don|r" or "|cffFF6666off|r"))
    print("  Data source: " .. (ZZ.data == ZugZugDataRIO and "Raider.IO" or "ZugZug"))
    if ZZ.data then
      print("  Data: loaded (" .. (ZZ.data.lastUpdate or "?") .. ")")
    else
      print("  Data: NOT LOADED")
    end
    return
  end

  if cmd == "dump" then
    if ZZ.DumpLastSwapState then
      ZZ:DumpLastSwapState()
    else
      print("|cff00ccffZugZug:|r DumpLastSwapState not loaded — try /reload")
    end
    return
  end

  if cmd == "showimport" or cmd == "import" then
    -- Print the import string of the build the suggest popup is using.
    -- Lets you paste it straight into Class > Specialization > Loadout
    -- > Import to confirm Blizzard's UI agrees with what we'd apply.
    -- The string is written to its own chat line for easy click-drag-copy.
    local b = ZZ.lastBuild
    if not (b and b.importString) then
      print("|cff00ccffZugZug:|r no active build cached. Trigger the dungeon-suggest popup first (zone into a dungeon).")
      return
    end
    print("|cff00ccffZugZug:|r last build import string (paste into the in-game Import dialog) —")
    print(string.format("  build: %s  spec: %s", tostring(b.name or b.id or "?"), tostring(b.spec or "?")))
    print(b.importString)
    return
  end

  if cmd == "undo" then
    if ZZ.UndoLastApply then
      ZZ:UndoLastApply()
    else
      print("|cff00ccffZugZug:|r Undo not loaded — try /reload.")
    end
    return
  end

  if cmd == "settings" or cmd == "options" or cmd == "config" then
    local ok, err = pcall(function()
      if ZZ.settingsCategory then
        Settings.OpenToCategory(ZZ.settingsCategory:GetID())
      else
        Settings.OpenToCategory("ZugZug")
      end
    end)
    if not ok then
      print("|cff00ccffZugZug:|r Settings error: " .. tostring(err))
    end
    return
  end

  -- Default: show help
  print("|cff00ccffZugZug|r — ZUGZUG.info talent builds")
  print("  /zugzug status — show current settings")
  print("  /zugzug settings — open settings panel")
  print("  /zugzug diff <heroic|mythic> — set raid difficulty")
  print("  /zugzug key <all|15+|18+|20+> — set M+ key level filter")
  print("  /zugzug suggest — toggle smart suggest on/off")
  print("  /zugzug undo — revert the last build/swap apply")
end

----------------------------------------------------------------------
-- Event handling
----------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")

frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    ensureDefaults()

    -- Link the configured data table (Data.lua / DataRIO.lua).
    ZZ.SelectDataSource()
    if not ZZ.data then
      print("|cff00ccffZugZug:|r Warning — no build data loaded. Run the update script.")
    end

    SLASH_ZUGZUG1 = "/zugzug"
    SLASH_ZUGZUG2 = "/zz"
    SlashCmdList["ZUGZUG"] = handleSlashCommand

    frame:UnregisterEvent("ADDON_LOADED")
  end

  if event == "PLAYER_LOGIN" then
    refreshPlayerInfo()
    -- Boss/dungeon detection matches against English names from the data
    -- pipeline; on other locales the suggest popups may not fire. Say so
    -- once instead of failing silently.
    if GetLocale and GetLocale() ~= "enUS" and not ZugZugDB.localeNoticeShown then
      ZugZugDB.localeNoticeShown = true
      print("|cff00ccffZugZug:|r Non-English client detected — build browsing works fully, but boss/dungeon auto-suggestions may be limited (encounter names are matched in English).")
    end
    if ZZ.data then
      local raidBuilds, mpBuilds = ZZ:GetCurrentBuilds()
      local rCount = raidBuilds and #raidBuilds or 0
      local mCount = mpBuilds and #mpBuilds or 0
      print(string.format(
        "|cff00ccffZugZug:|r Loaded %d raid + %d M+ builds for %s %s. Type /zz for help.",
        rCount, mCount, ZZ.specName or "?", ZZ.role or "?"
      ))

      -- Notify if build data was updated since last session
      local currentVersion = ZZ.data.lastUpdate
      if currentVersion and ZugZugDB.lastDataVersion and ZugZugDB.lastDataVersion ~= currentVersion then
        print("|cff00ccffZugZug:|r |cff8fbf3fBuild data updated!|r Meta may have shifted — check your builds.")
      end
      ZugZugDB.lastDataVersion = currentVersion
    end
  end

  if event == "ACTIVE_TALENT_GROUP_CHANGED" then
    refreshPlayerInfo()
    if ZZ.RefreshUI then ZZ:RefreshUI() end
    -- Apply any build that was waiting for a spec switch
    if ZZ.ApplyPendingBuild then
      -- Delay slightly to let the talent tree fully load after spec change
      C_Timer.After(0.5, function() ZZ:ApplyPendingBuild() end)
    end
  end
end)
