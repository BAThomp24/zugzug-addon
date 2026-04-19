----------------------------------------------------------------------
-- ZugZug — Core
-- Initialization, saved variables, slash commands, class/spec detection.
----------------------------------------------------------------------

local ADDON_NAME = select(1, ...)

-- Saved variables (persisted between sessions)
ZugZugDB = ZugZugDB or {}

-- Addon-wide state
local ZZ = {
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
  raidDifficulty = "mythic",  -- "heroic" | "mythic"
  mpBucket = "all",           -- "all" | "15+" | "18+" | "20+"
}

local function ensureDefaults()
  for k, v in pairs(DEFAULTS) do
    if ZugZugDB[k] == nil then
      ZugZugDB[k] = v
    end
  end
end

----------------------------------------------------------------------
-- Spec role detection
----------------------------------------------------------------------

local HEALER_SPEC_IDS = {
  -- Druid: Restoration
  [105] = true,
  -- Evoker: Preservation
  [1468] = true,
  -- Monk: Mistweaver
  [270] = true,
  -- Paladin: Holy
  [65] = true,
  -- Priest: Discipline, Holy
  [256] = true, [257] = true,
  -- Shaman: Restoration
  [264] = true,
}

local TANK_SPEC_IDS = {
  -- Death Knight: Blood
  [250] = true,
  -- Demon Hunter: Vengeance
  [581] = true,
  -- Druid: Guardian
  [104] = true,
  -- Monk: Brewmaster
  [268] = true,
  -- Paladin: Protection
  [66] = true,
  -- Warrior: Protection
  [73] = true,
}

local function detectRole(specId)
  if HEALER_SPEC_IDS[specId] then return "healer" end
  if TANK_SPEC_IDS[specId] then return "tank" end
  return "dps"
end

----------------------------------------------------------------------
-- Refresh current player info
----------------------------------------------------------------------

local function refreshPlayerInfo()
  local _, classToken = UnitClass("player")
  ZZ.classToken = classToken

  local specIndex = GetSpecialization()
  if specIndex then
    local specId, specName = GetSpecializationInfo(specIndex)
    ZZ.specId = specId
    ZZ.specName = specName
    ZZ.role = detectRole(specId)
  end
end

----------------------------------------------------------------------
-- Get builds for current class + settings
----------------------------------------------------------------------

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

  -- Sort current spec's builds first, then other specs
  local specName = self.specName
  if specName then
    local function specSort(a, b)
      local aMatch = a.spec == specName
      local bMatch = b.spec == specName
      if aMatch ~= bMatch then return aMatch end
      return false -- preserve original order within same group
    end
    if raidBuilds then
      local sorted = {}
      for _, b in ipairs(raidBuilds) do sorted[#sorted + 1] = b end
      table.sort(sorted, specSort)
      raidBuilds = sorted
    end
    if mpBuilds then
      local sorted = {}
      for _, b in ipairs(mpBuilds) do sorted[#sorted + 1] = b end
      table.sort(sorted, specSort)
      mpBuilds = sorted
    end
  end

  return raidBuilds, mpBuilds
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

  if cmd == "difficulty" or cmd == "diff" then
    arg = arg:lower()
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

  if cmd == "status" then
    print("|cff00ccffZugZug:|r Status")
    print("  Class: " .. (ZZ.classToken or "unknown"))
    print("  Spec: " .. (ZZ.specName or "unknown") .. " (" .. (ZZ.role or "?") .. ")")
    print("  Raid difficulty: " .. (ZugZugDB.raidDifficulty or "mythic"))
    print("  M+ key level: " .. (ZugZugDB.mpBucket or "all"))
    if ZZ.data then
      print("  Data: loaded (" .. (ZZ.data.lastUpdate or "?") .. ")")
    else
      print("  Data: NOT LOADED")
    end
    return
  end

  -- Default: show help
  print("|cff00ccffZugZug|r — ZUGZUG.io talent builds")
  print("  /zugzug status — show current settings")
  print("  /zugzug diff <heroic|mythic> — set raid difficulty")
  print("  /zugzug key <all|15+|18+|20+> — set M+ key level filter")
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

    -- Link the global data table generated by update-data.ts
    if ZugZugData then
      ZZ.data = ZugZugData
    else
      print("|cff00ccffZugZug:|r Warning — no build data loaded. Run the update script.")
    end

    SLASH_ZUGZUG1 = "/zugzug"
    SLASH_ZUGZUG2 = "/zz"
    SlashCmdList["ZUGZUG"] = handleSlashCommand

    frame:UnregisterEvent("ADDON_LOADED")
  end

  if event == "PLAYER_LOGIN" then
    refreshPlayerInfo()
    if ZZ.data then
      local raidBuilds, mpBuilds = ZZ:GetCurrentBuilds()
      local rCount = raidBuilds and #raidBuilds or 0
      local mCount = mpBuilds and #mpBuilds or 0
      print(string.format(
        "|cff00ccffZugZug:|r Loaded %d raid + %d M+ builds for %s %s. Type /zz for help.",
        rCount, mCount, ZZ.specName or "?", ZZ.role or "?"
      ))
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
