----------------------------------------------------------------------
-- ZugZug — Minimap Button
-- Draggable minimap icon that toggles the build panel.
----------------------------------------------------------------------

local ZZ = _G.ZugZug

-- Derive addon folder name from the TOC-provided global (set in Core.lua)
local addonFolder = ZZ.addonName or "ZugZug"
-- PNG textures require the file extension in the path
local ICON_PATH = "Interface\\AddOns\\" .. addonFolder .. "\\icon.png"
local ICON_SIZE = 31
local MINIMAP_RADIUS = 80

----------------------------------------------------------------------
-- Minimap button frame
----------------------------------------------------------------------

local button = CreateFrame("Button", "ZugZugMinimapButton", Minimap)
button:SetSize(ICON_SIZE, ICON_SIZE)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:SetClampedToScreen(true)
button:SetMovable(true)
button:RegisterForDrag("LeftButton")
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

-- Icon texture (our logo)
local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(21, 21)
icon:SetPoint("CENTER")
icon:SetTexture(ICON_PATH)

-- Circular border overlay (matches other minimap buttons)
local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(ICON_SIZE + 2, ICON_SIZE + 2)
border:SetPoint("CENTER")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

-- Highlight on hover
local highlight = button:CreateTexture(nil, "HIGHLIGHT")
highlight:SetSize(24, 24)
highlight:SetPoint("CENTER")
highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
highlight:SetBlendMode("ADD")

----------------------------------------------------------------------
-- Position: orbit around the minimap
----------------------------------------------------------------------

local function updatePosition(angle)
  local x = math.cos(angle) * MINIMAP_RADIUS
  local y = math.sin(angle) * MINIMAP_RADIUS
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function getAngleFromCursor()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  return math.atan2(cy / scale - my, cx / scale - mx)
end

-- Drag handling
local isDragging = false

button:SetScript("OnDragStart", function()
  isDragging = true
  button:SetScript("OnUpdate", function()
    local angle = getAngleFromCursor()
    ZugZugDB.minimapAngle = angle
    updatePosition(angle)
  end)
end)

button:SetScript("OnDragStop", function()
  isDragging = false
  button:SetScript("OnUpdate", nil)
end)

----------------------------------------------------------------------
-- Click handlers
----------------------------------------------------------------------

button:SetScript("OnClick", function(_, btn)
  if btn == "RightButton" then
    -- Print help
    SlashCmdList["ZUGZUG"]("")
    return
  end

  -- Left click: toggle the build bar
  if ZZ.ToggleBar then
    ZZ:ToggleBar()
  end
end)

-- Tooltip
button:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("|cff8fbf3fZugZug|r", 1, 1, 1)
  GameTooltip:AddLine("Left-click to toggle builds", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("Right-click for help", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("Drag to move", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end)

button:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

----------------------------------------------------------------------
-- Init: restore position after data is ready
----------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
  -- Default angle: top-right of minimap
  local angle = ZugZugDB.minimapAngle or 0.8
  updatePosition(angle)

  -- Hide if user has opted out
  if ZugZugDB.minimapHidden then
    button:Hide()
  end

  initFrame:UnregisterEvent("PLAYER_LOGIN")
end)

----------------------------------------------------------------------
-- Toggle bar (exposed on ZZ so the minimap button can call it)
----------------------------------------------------------------------

function ZZ:ToggleBar()
  -- Create the bar if it doesn't exist yet (talent frame never opened)
  local bar = ZZ:GetOrCreateBar()
  if not bar then return end

  if bar:IsShown() then
    bar:Hide()
  else
    -- If talent frame is open, bar is already anchored to it — just show
    if PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame and PlayerSpellsFrame.TalentsFrame:IsShown() then
      bar:ClearAllPoints()
      bar:SetPoint("TOP", PlayerSpellsFrame.TalentsFrame, "BOTTOM", 0, -4)
      bar:Show()
      ZZ:RefreshUI()
    else
      -- Standalone mode: anchor near bottom of screen
      bar:ClearAllPoints()
      bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 120)
      bar:Show()
      ZZ:RefreshUI()
    end
  end
end

----------------------------------------------------------------------
-- Slash command: /zz minimap — toggle minimap button visibility
----------------------------------------------------------------------

local origSlash = SlashCmdList["ZUGZUG"]

local initSlash = CreateFrame("Frame")
initSlash:RegisterEvent("PLAYER_LOGIN")
initSlash:SetScript("OnEvent", function()
  -- Wrap the existing slash handler to add the minimap subcommand
  local prevHandler = SlashCmdList["ZUGZUG"]
  SlashCmdList["ZUGZUG"] = function(msg)
    local cmd = msg:match("^(%S+)") or ""
    if cmd:lower() == "minimap" then
      ZugZugDB.minimapHidden = not ZugZugDB.minimapHidden
      if ZugZugDB.minimapHidden then
        button:Hide()
        print("|cff00ccffZugZug:|r Minimap button |cffFF6666hidden|r. Type /zz minimap to show.")
      else
        button:Show()
        print("|cff00ccffZugZug:|r Minimap button |cff4DFF4Dshown|r.")
      end
      return
    end
    if prevHandler then prevHandler(msg) end
  end
  initSlash:UnregisterEvent("PLAYER_LOGIN")
end)
