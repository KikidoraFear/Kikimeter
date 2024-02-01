
-- for debugging: DEFAULT_CHAT_FRAME:AddMessage("Test")
local function print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- combat log limitations:
  -- if the target is full hp, hots (tested with Renew) aren't displayed -> in that case overheal cannot be detected
    -- if the target is missing hp however (even if it's just 1), the full renew tick is listed in the combat log and overheal can be detected correctly
  
-- Infos:
--   Global API Strings: https://github.com/tekkub/wow-ui-source/blob/1.12.1/FrameXML/GlobalStrings.lua

-- ##############
-- # PARAMETERS #
-- ##############

-- KikiMeter broadcasting ID: km_id x is only able to communicate with km_id x,
-- so it won't cause problems if people use older versions that are incompatible
local km_id = "5" -- corresponds to addon version (1.1 -> 1.2: no change in messages sent; 1.2 -> 2.0: change in messages sent = not compatible)

-- config table
local config = {
  bar_width = 110, -- width of bars
  bar_height = 17, -- height of bars
  bars_show_act = 5, -- number of bars shown in sub
  bars_show_max = 20, -- number of bars shown in sub when maximise is pressed
  bars_show_min = 5, -- number of bars shown in sub when maximise isn't pressed
  sub_spacing = 3, -- spacing between subs
  sub_rows = 2, -- number of separate meters
  sub_cols = 3, -- number of columns for each meter
  font_size = 8, -- font size for name and damage numbers
  font_size_dps = 5.5, -- font size for name and damage numbers
  btn_height = 20, -- size of buttons
  window_text_height = 10, -- added text space in window
  refresh_time = 0.2, -- refresh time in seconds (for updating Bars)
  data_bosses = {},
  button_design = 0 -- 0..white, 1..black
}
config.sub_height = config.bar_height*config.bars_show_act -- height of one table
config.sub_width = config.bar_width*config.sub_cols + config.sub_spacing*(config.sub_cols-1)
config.data_bosses["Ahn'Qiraj"] = {"Arygos", "Battleguard Sartura", "C'Thun", "Emperor Vek'lor", "Emperor Vek'nilash", "Eye of C'Thun", "Fankriss the Unyielding", "Lord Kri", "Merithra of the Dream", "Ouro", "Princess Huhuran", "Princess Yauj", "The Master's Eye", "The Prophet Skeram", "Vem", "Viscidus"}
config.data_bosses["Blackwing Lair"] = {"Broodlord Lashlayer", "Chromaggus", "Ebonroc", "Firemaw", "Flamegor", "Lord Victor Nefarius", "Razorgore the Untamed", "Vaelastrasz the Corrupt"}
config.data_bosses["Molten Core"] = {"Baron Geddon", "Garr", "Gehennas", "Golemagg the Incinerator", "Lucifron", "Magmadar", "Shazzrah", "Sulfuron Harbinger"}
config.data_bosses["Onyxia's Lair"] = {"Onyxia"}
config.data_bosses["Ruins of Ahn'Qiraj"] = {"Ayamiss the Hunter", "Buru the Gorger", "General Rajaxx", "Kurinnaxx", "Moam", "Ossirian the Unscarred"}
config.data_bosses["Zul'Gurub"] = {"High Priestess Jeklik", "High Priest Venoxis", "High Priestess Mar'li", "High Priest Thekal", "High Priestess Arlokk", "Hakkar", "Bloodlord Mandokir", "Jin'do the Hexxer", "Gahz'ranka"}
config.data_bosses["Emerald Sanctum"] = {"Erennius", "Solnius"}
config.data_bosses["Lower Karazhan Halls"] = {"Master Blacksmith Rolfen", "Brood Queen Araxxna", "Grizikil", "Clawlord Howlfang", "Lord Blackwald II", "Moroes"}

-- config.data_bosses["Teldrassil"] = {"Young Thistle Boar", "Grellkin"}


-- ####################
-- # HELPER FUNCTIONS #
-- ####################

local function getArLength(arr) -- get array length
  if arr then
    return table.getn(arr)
  else
    return 0
  end
end

-- get unitID from name with cache table for better performance
-- this is necessary to get max and current health of the target
-- for effective healing calculations
local function GetUnitID(unitIDs_cache, unitIDs, name)
  if unitIDs_cache[name] and UnitName(unitIDs_cache[name]) == name then
    return unitIDs_cache[name]
  end
  for _,unitID in pairs(unitIDs) do
    if UnitName(unitID) == name then
      unitIDs_cache[name] = unitID
      return unitID
    end
  end
end

-- broadcast value to hidden addon channel
local function BroadcastValue(section, kind, attack, value)
  SendAddonMessage("KM"..km_id.."_"..section.."_"..kind.."_"..attack, value , "RAID") -- "KM4_ouro_dmg_hit", "10", "RAID"
end

local function BroadcastSectionChange(player_zone, player_section, data_filter, window)
  window.text_top_left:SetText(player_zone..": "..player_section)
  if player_section ~= "NoCombat" then
    data_filter[2] = player_section
    window.text_top_right:SetText("Bottom: "..player_section)
  end
  SendAddonMessage("KM"..km_id.."_"..player_section.."_SECTIONCHANGE_DETECTED", player_section , "RAID")
end

-- calculate effective heal from total heal and target health
local function EOHeal(unitIDs_cache, unitIDs, value, target)
  local unitID = GetUnitID(unitIDs_cache, unitIDs, target)
  local eheal = 0
  local oheal = 0
  if unitID then
    eheal = math.min(UnitHealthMax(unitID) - UnitHealth(unitID), value)
    oheal = value-eheal
  end
  return eheal, oheal
end

local function PrepareData(data, data_section, data_kind, player_name, attack)
  -- init tables
  if not data[data_section] then -- data_section does not exist
    data[data_section] = {}
  end

  if not data[data_section][data_kind] then -- data_kind does not exist
    data[data_section][data_kind] = {}
    data[data_section][data_kind]._max = 0
    data[data_section][data_kind]._ranking = {}
    data[data_section][data_kind]._players = {}
  end

  if not data[data_section][data_kind]._players[player_name] then -- player_name does not exist
    data[data_section][data_kind]._players[player_name] = {}
    data[data_section][data_kind]._players[player_name]._attacks = {}
    data[data_section][data_kind]._players[player_name]._ranking = {}
    data[data_section][data_kind]._players[player_name]._sum = 0
  end

  if not data[data_section][data_kind]._players[player_name]._attacks[attack] then -- if attack for player doesnt exist, init value
    data[data_section][data_kind]._players[player_name]._attacks[attack] = 0
  end
end

local function FillDataTables(data, data_section, data_kind, player_name, attack, value)
  data[data_section][data_kind]._players[player_name]._attacks[attack] = data[data_section][data_kind]._players[player_name]._attacks[attack] + tonumber(value)
end

local function AddData(data, data_section, data_kind, player_name, attack, value)
  PrepareData(data, data_section, data_kind, player_name, attack)
  FillDataTables(data, data_section, data_kind, player_name, attack, value)
end

local function OverwriteDataTables(data, data_section, data_kind, player_name, attack, value)
  data[data_section][data_kind]._players[player_name]._attacks[attack] = tonumber(value)
end

local function OverwriteData(data, data_section, data_kind, player_name, attack, value)
  PrepareData(data, data_section, data_kind, player_name, attack)
  OverwriteDataTables(data, data_section, data_kind, player_name, attack, value)
end

local function PrepareDataTimer(data_timer, player_name, data_section)
  if not data_timer[player_name] then
    data_timer[player_name] = {}
    data_timer[player_name]._prev_timestamp = 0
    data_timer[player_name]._prev_section = ""
  end
  if not data_timer[player_name][data_section] then
    data_timer[player_name][data_section] = 0
  end
end

local function FillDataTimeTable(data_timer, player_name, data_section)
  local time_act = GetTime()
  if data_timer[player_name]._prev_section == data_section then
    data_timer[player_name][data_section] = data_timer[player_name][data_section] + time_act - data_timer[player_name]._prev_timestamp
  else
    data_timer[player_name]._prev_section = data_section
  end
  data_timer[player_name]._prev_timestamp = time_act
end

local function AddDataTimer(data_timer, player_name, data_section)
  PrepareDataTimer(data_timer, player_name, data_section)
  FillDataTimeTable(data_timer, player_name, data_section)
end

local function OverwriteDataTimeTable(data_timer, player_name, data_section, time)
  data_timer[player_name][data_section] = time
end

local function OverwriteDataTimer(data_timer, player_name, data_section, time)
  PrepareDataTimer(data_timer, player_name, data_section)
  OverwriteDataTimeTable(data_timer, player_name, data_section, time)
end

local function GenSectionData(data, data_timer)
  -- generate time table
  for player_name,_ in pairs(data_timer) do
    local time_all = 0
    local time_nocombat = 0
    local time_bosses = 0
    for data_section,_ in pairs(data_timer[player_name]) do
      if (data_section ~= "All") and (data_section ~= "InCombat") and (data_section ~= "Bosses") and (data_section ~= "_prev_section") and (data_section ~= "_prev_timestamp")and (data_section ~= "") then
        time_all = time_all + data_timer[player_name][data_section]
        if data_section ~= "NoCombat" then
          time_nocombat = time_nocombat + data_timer[player_name][data_section]
          if data_section ~= "Trash" then
            time_bosses = time_bosses + data_timer[player_name][data_section]
          end
        end
      end
    end
    OverwriteDataTimer(data_timer, player_name, "All", time_all)
    OverwriteDataTimer(data_timer, player_name, "InCombat", time_nocombat)
    OverwriteDataTimer(data_timer, player_name, "Bosses", time_bosses)
  end
  -- generate data table
  for data_section,_ in pairs(data) do
    if (data_section ~= "All") and (data_section ~= "InCombat") and (data_section ~= "Bosses") then
      for data_kind,_ in pairs(data[data_section]) do
        for player_name,_ in data[data_section][data_kind]._players do
          for attack,_ in data[data_section][data_kind]._players[player_name]._attacks do
            OverwriteData(data, "All", data_kind, player_name, attack, data[data_section][data_kind]._players[player_name]._attacks[attack])
            if data_section ~= "NoCombat" then
              OverwriteData(data, "InCombat", data_kind, player_name, attack, data[data_section][data_kind]._players[player_name]._attacks[attack])
              if data_section ~= "Trash" then
                OverwriteData(data, "Bosses", data_kind, player_name, attack, data[data_section][data_kind]._players[player_name]._attacks[attack])
              end
            end
          end
        end
      end
    end
  end
end

local function ProcessData(data)
  -- calculate sum and max each x second, only collect attacks with parser (PostProcessData function)
  local attack_sum = 0
  for data_section,_ in pairs(data) do
    for data_kind,_ in pairs(data[data_section]) do
      for player_name,_ in data[data_section][data_kind]._players do
        attack_sum = 0
        for attack,_ in data[data_section][data_kind]._players[player_name]._attacks do
          attack_sum = attack_sum + data[data_section][data_kind]._players[player_name]._attacks[attack]
        end
        data[data_section][data_kind]._players[player_name]._sum = attack_sum
        if attack_sum > data[data_section][data_kind]._max then
          data[data_section][data_kind]._max = attack_sum
        end
      end
    end
  end
end


local function UpdateBarsSubKind(data, data_section, data_kind, bars_sub_kind, data_timer)
  for rank=1, config.bars_show_max do
    local rank_f = rank -- for SetScript, otherwise last from loop rank is used
    if (data[data_section] and data[data_section][data_kind] and data[data_section][data_kind]._ranking[rank] and (rank <= config.bars_show_act)) then -- if data for rank is present
      local player_name = data[data_section][data_kind]._ranking[rank]
      local value = data[data_section][data_kind]._players[player_name]._sum
      
      local num_attacks = getArLength(data[data_section][data_kind]._players[player_name]._ranking)
      if data_timer[player_name] then -- if player uses Kikimeter
        local value_ps = 0
        if data_timer[player_name][data_section] > 1 then
          value_ps = math.floor(data[data_section][data_kind]._players[player_name]._sum/data_timer[player_name][data_section])
        end
        bars_sub_kind[rank].text_left:SetText("|cFFFFDF00"..rank.."."..player_name.."|r") -- |cAARRGGBBtext|r Alpha Red Green Blue
        bars_sub_kind[rank].text_right:SetText("|cFFFFDF00"..value.."|r")
        bars_sub_kind[rank].text_right_dps:SetText("|cFFFFDF00"..value_ps.."|r")
        bars_sub_kind[rank].text_right_dps:Show()
      else
        bars_sub_kind[rank].text_left:SetText(rank.."."..player_name)
        bars_sub_kind[rank].text_right:SetText(value)
        bars_sub_kind[rank].text_right_dps:Hide()
      end
      bars_sub_kind[rank].text_left:Show()
      bars_sub_kind[rank].text_right:Show()
      bars_sub_kind[rank]:SetValue(value/data[data_section][data_kind]._max*100)
      bars_sub_kind[rank]:Show()
      bars_sub_kind[rank]:SetScript("OnEnter", function()
        GameTooltip:SetOwner(bars_sub_kind[rank_f], "ANCHOR_LEFT")
        for rank_attack = 1, num_attacks do
          local attack = data[data_section][data_kind]._players[player_name]._ranking[rank_attack]
          GameTooltip:AddDoubleLine(attack, data[data_section][data_kind]._players[player_name]._attacks[attack])
        end
        GameTooltip:Show()
      end)
    else -- hide bar_sub_kind with no data
      bars_sub_kind[rank].text_left:Hide()
      bars_sub_kind[rank].text_right:Hide()
      bars_sub_kind[rank]:Hide()
    end
  end
end

-- ########
-- # INIT #
-- ########

local data = {}
-- data[data_section][data_kind]._max = value
-- data[data_section][data_kind]._ranking[rank] = player_name 
-- data[data_section][data_kind]._players[name]._attacks[attack] = value
-- data[data_section][data_kind]._players[name]._ranking[rank] = attack
-- data[data_section][data_kind]._players[name]._sum = value

local data_timer = {}
-- data_timer[player_name]._prev_timestamp = 0
-- data_timer[player_name]._prev_section = "Ouro"
-- data_timer[player_name][data_section] = 10 -- time

local data_filter = {"All", "Bosses"}
-- data_filter[data_sub] = section

local unitIDs = {"player"} -- unitID player
for i=2,5 do unitIDs[i] = "party"..i-1 end -- unitIDs party
for i=6,45 do unitIDs[i] = "raid"..i-5 end -- unitIDs raid
local unitIDs_cache = {} -- init unitIDs_cache[name] = unitID
local player_section = "NoCombat" -- shows the status of the player (what the player is fighting and if in combat)
local player_zone = ""

-- ##########
-- # LAYOUT #
-- ##########

local function BarLayout(parent, bar, bar_num, col)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:ClearAllPoints()
  bar:SetPoint("TOP", parent, "TOP", 0, -config.bar_height * (bar_num-1))
  bar:SetHeight(config.bar_height)
  bar:SetWidth(config.bar_width)
  bar:SetMinMaxValues(0, 100)
  bar:EnableMouse(true)
  if col == 1 then
    bar:SetStatusBarColor(1, 0, 0)
  elseif col == 2 then
    bar:SetStatusBarColor(0, 1, 0)
  else
    bar:SetStatusBarColor(0, 0, 1)
  end
  bar:Hide()
  bar:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

local function TextLayout(parent, text, align, pos_h, pos_v, size)
  text:SetFont(STANDARD_TEXT_FONT, size, "THINOUTLINE")
  text:SetFontObject(GameFontWhite)
  text:ClearAllPoints()
  text:SetPoint(align, parent, align, pos_h, pos_v)
  text:Hide()
end

local function ButtonDesign(btn)
  if config.button_design == 0 then
    btn:SetBackdropColor(1, 1, 1, 1)
    btn:SetBackdropBorderColor(0, 0, 0, 1)
    btn:SetScript("OnEnter", function()
      btn:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    btn:SetScript("OnLeave", function()
      btn:SetBackdropBorderColor(0, 0, 0, 1)
    end)
  else
    btn:SetBackdropColor(0, 0, 0, 1)
    btn:SetBackdropBorderColor(0, 0, 0, 1)
    btn:SetScript("OnEnter", function()
      btn:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    btn:SetScript("OnLeave", function()
      btn:SetBackdropBorderColor(0, 0, 0, 1)
    end)
  end
end

local function ButtonLayout(parent, btn, txt, pos_btn, pos_parent, pos_v, pos_h, width_multiplier)
  btn:ClearAllPoints()
  btn:SetPoint(pos_btn, parent, pos_parent, pos_h, pos_v)
  btn:SetHeight(config.btn_height)
  btn:SetWidth(config.sub_width*width_multiplier)
  btn:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2}})
  ButtonDesign(btn)
  btn:Show()
  btn.text = btn:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(btn, btn.text, "CENTER", 0, 1.5, config.font_size)
  btn.text:SetText(txt)
  btn.text:Show()
end

local function SubLayout(parent, sub, sub_num)
  sub:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background"})
  sub:SetBackdropColor(0, 0, 0, 1)
  sub:ClearAllPoints()
  sub:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(sub_num-1)*(config.sub_height+config.sub_spacing) - config.window_text_height)
  sub:SetWidth(config.bar_width*config.sub_cols + config.sub_spacing*(config.sub_cols-1))
  sub:SetHeight(config.sub_height)
end

local function SubTypeLayout(parent, sub_type, pos_h, col)
  sub_type:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background"})
  if col == 1 then
    sub_type:SetBackdropColor(1, 0.5, 0.5, 1)
  elseif col == 2 then
    sub_type:SetBackdropColor(0.5, 1, 0.5, 1)
  else
    sub_type:SetBackdropColor(0.5, 0.5, 1, 1)
  end
  sub_type:ClearAllPoints()
  sub_type:SetPoint("TOPLEFT", parent, "TOPLEFT", pos_h, 0)
  sub_type:SetWidth(config.bar_width)
  sub_type:SetHeight(config.sub_height)
  sub_type:EnableMouseWheel(true)
end

local function WindowLayout(window)
  window:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background"})
  window:SetBackdropColor(0, 0, 0, 1)
  window:ClearAllPoints()
  window:SetPoint("RIGHT", UIParent, "RIGHT", -100, -100)
  window:SetWidth(config.bar_width*3 + 2*config.sub_spacing)
  window:SetHeight(config.sub_height*config.sub_rows + (config.sub_rows-1)*config.sub_spacing + 2*config.window_text_height)
  window:EnableMouse(true) -- needed for it to be movable
  window:RegisterForDrag("LeftButton")
  window:SetMovable(true)
  window:SetUserPlaced(true) -- saves the place the user dragged it to
  window:SetScript("OnDragStart", function() window:StartMoving() end)
  window:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
  window:SetClampedToScreen(true) -- so the window cant be moved out of screen

  window.text_top_left = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(window, window.text_top_left, "TOPLEFT", 0, 0, config.font_size)
  window.text_top_left:SetText(player_zone..": NoCombat")
  window.text_top_left:Show()

  window.text_top_center = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(window, window.text_top_center, "TOP", 0, 0, config.font_size)
  window.text_top_center:SetText("Top: "..data_filter[1])
  window.text_top_center:Show()

  window.text_top_right = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(window, window.text_top_right, "TOPRIGHT", 0, 0, config.font_size)
  window.text_top_right:SetText("Bottom: "..data_filter[2])
  window.text_top_right:Show()

  window.text_bottom_left = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(window, window.text_bottom_left, "BOTTOMLEFT", 0, 2, config.font_size)
  window.text_bottom_left:SetText("damage done")
  window.text_bottom_left:Show()

  window.text_bottom_center = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(window, window.text_bottom_center, "BOTTOM", 0, 2, config.font_size)
  window.text_bottom_center:SetText("effective healing")
  window.text_bottom_center:Show()

  window.text_bottom_right = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(window, window.text_bottom_right, "BOTTOMRIGHT", 0, 2, config.font_size)
  window.text_bottom_right:SetText("over healing")
  window.text_bottom_right:Show()

  window.button_reset = CreateFrame("Button", nil, window)
  ButtonLayout(window, window.button_reset, "Reset", "BOTTOMLEFT", "TOPLEFT", 0, 0, 0.1)
  window.button_reset:SetScript("OnClick", function()
    for data_section,_ in pairs(data) do
      data[data_section] = nil
    end
  end)

  window.button_section = CreateFrame("Button", nil, window)
  ButtonLayout(window, window.button_section, "Section", "BOTTOMLEFT", "TOPLEFT", 0, config.sub_width*0.1, 0.5)
  local button_section_show = false
  window.button_section:SetScript("OnClick", function()
    if not button_section_show then
      local idx_btn = 0
      local row_btn = 0
      local col_btn = 0
      for data_section, _ in pairs(data) do
        local data_section_f = data_section
        window.button_section[data_section_f] = CreateFrame("Button", nil, window.button_section)
        window.button_section[data_section_f]:SetScript("OnClick", function()
          data_filter[2] = data_section_f
          window.text_top_right:SetText("Bottom: "..data_section_f)
        end)
        ButtonLayout(window, window.button_section[data_section_f], data_section_f, "BOTTOMLEFT", "TOPLEFT", config.btn_height+config.btn_height*row_btn, config.sub_width*0.2*col_btn, 0.2)
        idx_btn = idx_btn+1
        row_btn = math.floor(idx_btn/5)
        col_btn = math.mod(idx_btn, 5)
      end
      button_section_show = true
    else
      for data_section, _ in pairs(data) do
        local data_section_f = data_section
        if window.button_section[data_section_f] then -- window might not exist (Button clicked, new combat engaged -> data_section but no button_section)
          window.button_section[data_section_f]:Hide()
        end
      end
      button_section_show = false
    end
  end)

  window.button_max = CreateFrame("Button", nil, window)
  ButtonLayout(window, window.button_max, "Maximise", "BOTTOMLEFT", "TOPLEFT", 0, config.sub_width*0.6, 0.2)
  window.button_max:SetScript("OnClick", function()
    if config.bars_show_act == config.bars_show_min then
      config.bars_show_act = config.bars_show_max
    else
      config.bars_show_act = config.bars_show_min
    end
    config.sub_height = config.bar_height*config.bars_show_act -- height of one table
    window:SetHeight(config.sub_height*config.sub_rows + (config.sub_rows-1)*config.sub_spacing + 2*config.window_text_height)
    for idx_sub=1,config.sub_rows do
      SubLayout(window, window.sub[idx_sub], idx_sub)
      SubTypeLayout(window.sub[idx_sub], window.sub[idx_sub].dmg, 0, 1)
      SubTypeLayout(window.sub[idx_sub], window.sub[idx_sub].eheal, config.bar_width + config.sub_spacing, 2)
      SubTypeLayout(window.sub[idx_sub], window.sub[idx_sub].oheal, 2*config.bar_width + 2*config.sub_spacing, 3)
    end
  end)
end

local function CreateBar(parent, idx, col)
  parent.bars[idx] = CreateFrame("StatusBar", nil, parent)
  BarLayout(parent, parent.bars[idx], idx, col)
  
  parent.bars[idx].text_left = parent.bars[idx]:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(parent.bars[idx], parent.bars[idx].text_left, "LEFT",0,0, config.font_size)

  parent.bars[idx].text_right = parent.bars[idx]:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(parent.bars[idx], parent.bars[idx].text_right, "TOPRIGHT",0,0, config.font_size)

  parent.bars[idx].text_right_dps = parent.bars[idx]:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(parent.bars[idx], parent.bars[idx].text_right_dps, "BOTTOMRIGHT",0, 3, config.font_size_dps)
end

local window = CreateFrame("Frame", "KikiMeter", UIParent)
WindowLayout(window)
window.sub = {}
for idx_sub = 1,config.sub_rows do

  window.sub[idx_sub] = CreateFrame("Frame", nil, window)
  SubLayout(window, window.sub[idx_sub], idx_sub)

  window.sub[idx_sub].dmg = CreateFrame("Frame", nil, window.sub[idx_sub])
  SubTypeLayout(window.sub[idx_sub], window.sub[idx_sub].dmg, 0, 1)

  window.sub[idx_sub].eheal = CreateFrame("Frame", nil, window.sub[idx_sub])
  SubTypeLayout(window.sub[idx_sub], window.sub[idx_sub].eheal, config.bar_width + config.sub_spacing, 2)

  window.sub[idx_sub].oheal = CreateFrame("Frame", nil, window.sub[idx_sub])
  SubTypeLayout(window.sub[idx_sub], window.sub[idx_sub].oheal, 2*config.bar_width + 2*config.sub_spacing, 3)

  window.sub[idx_sub].dmg.bars = {}
  window.sub[idx_sub].eheal.bars = {}
  window.sub[idx_sub].oheal.bars = {}

  for idx_sub_bar = 1,config.bars_show_max do
    CreateBar(window.sub[idx_sub].dmg, idx_sub_bar, 1)
    CreateBar(window.sub[idx_sub].eheal, idx_sub_bar, 2)
    CreateBar(window.sub[idx_sub].oheal, idx_sub_bar, 3)
  end
end

local button_hide = CreateFrame("Button", nil, UIParent)
ButtonLayout(window, button_hide, "Kikimeter", "BOTTOMLEFT", "TOPLEFT", 0, config.sub_width*0.8, 0.2)
button_hide:SetScript("OnClick", function()
  if window:IsShown() then
    window:Hide()
  else
    window:Show()
  end
end)

-- ############################################
-- # PARSE COMBAT LOG AND BROADCAST SOURCE:ME #
-- ############################################
-- combat status of player changed
local combat_status = CreateFrame("Frame")
combat_status:RegisterEvent("PLAYER_REGEN_DISABLED")
combat_status:RegisterEvent("PLAYER_REGEN_ENABLED")
combat_status:SetScript("OnEvent", function()
  if UnitAffectingCombat("player") or UnitAffectingCombat("pet") then
    player_section = "Trash"
    BroadcastSectionChange(player_zone, player_section, data_filter, window)
  else
    player_section = "NoCombat"
    BroadcastSectionChange(player_zone, player_section, data_filter, window)
  end
end)

-- create parser frame
local parser = CreateFrame("Frame")

-- events are a total mess, better register to many than too little
-- SPELL DAMAGE events
parser:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF")
parser:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS")
parser:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_PET_DAMAGE")

-- COMBAT DAMAGE events
parser:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
parser:RegisterEvent("CHAT_MSG_COMBAT_PARTY_HITS")
parser:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")
parser:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS")
parser:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS")
parser:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS")
parser:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
parser:RegisterEvent("CHAT_MSG_COMBAT_PET_HITS")

-- SPELL HEAL events
parser:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
parser:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
parser:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
parser:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")


local function MakeGfindReady(template) -- changes global string to fit gfind pattern
  template = gsub(template, "%%s", "(.+)") -- % is escape: %%s = %s raw
  return gsub(template, "%%d", "(%%d+)")
end


local combatlog_patterns = {} -- parser for combat log, order = {source, attack, target, value, school}, if not presenst = nil; parse order matters!!
-- ####### HEAL SOURCE:ME TARGET:ME
combatlog_patterns[1] = {string=MakeGfindReady(HEALEDCRITSELFSELF), order={nil, 1, nil, 2, nil}, kind="heal"} -- Your %s critically heals you for %d. (parse before Your %s heals you for %d.)
combatlog_patterns[2] = {string=MakeGfindReady(HEALEDSELFSELF), order={nil, 1, nil, 2, nil}, kind="heal"} -- Your %s heals you for %d.
combatlog_patterns[6] = {string=MakeGfindReady(PERIODICAURAHEALSELFSELF), order={nil, 2, nil, 1, nil}, kind="heal"} -- You gain %d health from %s.
-- ####### HEAL SOURCE:OTHER TARGET:ME
combatlog_patterns[4] = {string=MakeGfindReady(HEALEDCRITOTHERSELF), order={1, 2, nil, 3, nil}, kind="heal"} -- %s's %s critically heals you for %d. (parse before %s's %s critically heals %s for %d.)
combatlog_patterns[5] = {string=MakeGfindReady(HEALEDOTHERSELF), order={1, 2, nil, 3, nil}, kind="heal"} -- %s's %s heals you for %d.
combatlog_patterns[3] = {string=MakeGfindReady(PERIODICAURAHEALOTHERSELF), order={2, 3, nil, 1, nil}, kind="heal"} -- You gain %d health from %s's %s. (parse before You gain %d health from %s.)
-- ####### HEAL SOURCE:ME TARGET:OTHER
combatlog_patterns[7] = {string=MakeGfindReady(HEALEDCRITSELFOTHER), order={nil, 1, 2, 3, nil}, kind="heal"} -- Your %s critically heals %s for %d. (parse before Your %s heals %s for %d.)
combatlog_patterns[8] = {string=MakeGfindReady(HEALEDSELFOTHER), order={nil, 1, 2, 3, nil}, kind="heal"} -- Your %s heals %s for %d.
combatlog_patterns[9] = {string=MakeGfindReady(PERIODICAURAHEALSELFOTHER), order={nil, 3, 1, 2, nil}, kind="heal"} -- %s gains %d health from your %s.
-- ####### HEAL SOURCE:OTHER TARGET:OTHER
combatlog_patterns[10] = {string=MakeGfindReady(HEALEDCRITOTHEROTHER), order={1, 2, 3, 4, nil}, kind="heal"} -- %s's %s critically heals %s for %d.
combatlog_patterns[11] = {string=MakeGfindReady(HEALEDOTHEROTHER), order={1, 2, 3, 4, nil}, kind="heal"} -- %s's %s heals %s for %d.
combatlog_patterns[12] = {string=MakeGfindReady(PERIODICAURAHEALOTHEROTHER), order={3, 4, 1, 2, nil}, kind="heal"} -- %s gains %d health from %s's %s.

-- ####### DAMAGE SOURCE:ME TARGET:OTHER
combatlog_patterns[13] = {string=MakeGfindReady(SPELLLOGSCHOOLSELFOTHER), order={nil, 1, 2, 3, 4}, kind="dmg"} -- Your %s hits %s for %d %s damage. (parse before %s hits %s for %d %s damage.)
combatlog_patterns[14] = {string=MakeGfindReady(SPELLLOGCRITSCHOOLSELFOTHER), order={nil, 1, 2, 3, 4}, kind="dmg"} -- Your %s crits %s for %d %s damage. (parse before %s crits %s for %d %s damage.)
combatlog_patterns[15] = {string=MakeGfindReady(SPELLLOGSELFOTHER), order={nil, 1, 2, 3, nil}, kind="dmg"} -- Your %s hits %s for %d. (parse before %s hits %s for %d.)
combatlog_patterns[16] = {string=MakeGfindReady(SPELLLOGCRITSELFOTHER), order={nil, 1, 2, 3, nil}, kind="dmg"} -- Your %s crits %s for %d. (parse before %s crits %s for %d.)
combatlog_patterns[17] = {string=MakeGfindReady(PERIODICAURADAMAGESELFOTHER), order={nil, 4, 1, 2, 3}, kind="dmg"} -- %s suffers %d %s damage from your %s.
combatlog_patterns[18] = {string=MakeGfindReady(COMBATHITSELFOTHER), order={nil, nil, 1, 2, nil}, kind="dmg"} -- You hit %s for %d.
combatlog_patterns[19] = {string=MakeGfindReady(COMBATHITCRITSELFOTHER), order={nil, nil, 1, 2, nil}, kind="dmg"} -- You crit %s for %d.
combatlog_patterns[20] = {string=MakeGfindReady(COMBATHITSCHOOLSELFOTHER), order={nil, nil, 1, 2, 3}, kind="dmg"} -- You hit %s for %d %s damage.
combatlog_patterns[21] = {string=MakeGfindReady(COMBATHITCRITSCHOOLSELFOTHER), order={nil, nil, 1, 2, 3}, kind="dmg"} -- You crit %s for %d %s damage.
combatlog_patterns[22] = {string=MakeGfindReady(DAMAGESHIELDSELFOTHER), order={nil, nil, 3, 1, 2}, kind="dmg"} -- You reflect %d %s damage to %s.
-- ####### DAMAGE SOURCE:OTHER TARGET:OTHER
combatlog_patterns[23] = {string=MakeGfindReady(SPELLLOGSCHOOLOTHEROTHER), order={1, 2, 3, 4, 5}, kind="dmg"} -- %s's %s hits %s for %d %s damage. (parse before %s hits %s for %d %s damage.)
combatlog_patterns[24] = {string=MakeGfindReady(SPELLLOGCRITSCHOOLOTHEROTHER), order={1, 2, 3, 4, 5}, kind="dmg"}  -- %s's %s crits %s for %d %s damage. (parse before %s crits %s for %d %s damage.)
combatlog_patterns[25] = {string=MakeGfindReady(SPELLLOGOTHEROTHER), order={1, 2, 3, 4, nil}, kind="dmg"} -- %s's %s hits %s for %d. (parse before %s hits %s for %d.)
combatlog_patterns[26] = {string=MakeGfindReady(SPELLLOGCRITOTHEROTHER), order={1, 2, 3, 4, nil}, kind="dmg"} -- %s's %s crits %s for %d. (parse before %s crits %s for %d.)
combatlog_patterns[27] = {string=MakeGfindReady(PERIODICAURADAMAGEOTHEROTHER), order={4, 5, 1, 2, 3}, kind="dmg"} -- %s suffers %d %s damage from %s's %s.
combatlog_patterns[28] = {string=MakeGfindReady(COMBATHITOTHEROTHER), order={1, nil, 2, 3, nil}, kind="dmg"} -- %s hits %s for %d.
combatlog_patterns[29] = {string=MakeGfindReady(COMBATHITCRITOTHEROTHER), order={1, nil, 2, 3, nil}, kind="dmg"} -- %s crits %s for %d.
combatlog_patterns[30] = {string=MakeGfindReady(COMBATHITSCHOOLOTHEROTHER), order={1, nil, 2, 3, 4}, kind="dmg"} -- %s hits %s for %d %s damage.
combatlog_patterns[31] = {string=MakeGfindReady(COMBATHITCRITSCHOOLOTHEROTHER), order={1, nil, 2, 3, 4}, kind="dmg"} -- %s crits %s for %d %s damage.
combatlog_patterns[32] = {string=MakeGfindReady(DAMAGESHIELDOTHEROTHER), order={1, nil, 4, 2, 3}, kind="dmg"} -- %s reflects %d %s damage to %s.


parser:SetScript("OnEvent", function()
  local player_name = UnitName("player")
  local pet_name = UnitName("pet")

  if arg1 then
    -- #################
    -- # PARSE HEALING #
    -- #################
    local pars = {}
    for _,combatlog_pattern in ipairs(combatlog_patterns) do
      for par_1, par_2, par_3, par_4, par_5 in string.gfind(arg1, combatlog_pattern.string) do
        pars = {par_1, par_2, par_3, par_4, par_5}
        local source = pars[combatlog_pattern.order[1]]
        local attack = pars[combatlog_pattern.order[2]]
        local target = pars[combatlog_pattern.order[3]]
        local value = pars[combatlog_pattern.order[4]]
        local school = pars[combatlog_pattern.order[5]]

        -- Default values, e.g. for "You hit xyz for 15"
        if not source then
          source = player_name
        end
        if not attack then
          attack = "Hit"
        end
        if not target then
          target = player_name
        end
        if not value then
          value = 0
        end
        if not school then
          school = "physical"
        end
        
        -- Check if boss fight
        if (player_section == "Trash") and (config.data_bosses[player_zone]) then -- only swap to boss if in combat (=Trash), also helps if multiple bosses are fought at the same time (only lists first boss)
          for _, boss in ipairs(config.data_bosses[player_zone]) do
            if (boss == source) or (boss == target) then
              player_section = boss
              BroadcastSectionChange(player_zone, player_section, data_filter, window)
              break
            end
          end
        end

        if source == player_name then -- if source = player_name -> BroadcastValue
          if combatlog_pattern.kind == "heal" then
            local eheal, oheal = EOHeal(unitIDs_cache, unitIDs, value, target)
            BroadcastValue(player_section, "eheal", attack, eheal)
            BroadcastValue(player_section, "oheal", attack, oheal)
          elseif combatlog_pattern.kind == "dmg" then
            BroadcastValue(player_section, "dmg", attack, value)
          end
        elseif source == pet_name then -- if source = pet_name -> BroadcastValue
          if combatlog_pattern.kind == "heal" then
            local eheal, oheal = EOHeal(unitIDs_cache, unitIDs, value, target)
            BroadcastValue(player_section, "eheal", "Pet: "..attack, eheal)
            BroadcastValue(player_section, "oheal", "Pet: "..attack, oheal)
          elseif combatlog_pattern.kind == "dmg" then
            BroadcastValue(player_section, "dmg", "Pet: "..attack, value)
          end

        elseif unitIDs_cache[source] and (not data_timer[source]) then -- source in raid, but not a Kikimeter user -> AddData
          if combatlog_pattern.kind == "heal" then
            local eheal, oheal = EOHeal(unitIDs_cache, unitIDs, value, target)
            AddData(data, player_section, "eheal", source, attack, eheal)
            AddData(data, player_section, "oheal", source, attack, oheal)
          else
            AddData(data, player_section, "dmg", source, attack, value)
          end
        end
        return -- if pattern found, abort loop
      end
    end
  end
end)


-- #######################################################
-- # LISTEN TO BROADCAST, CRUNCH NUMBERS AND SHOW RESULT #
-- #######################################################

local function GetRank(data_section_kind_players) --sub_type[player_name]._sum = value
  local ranking = {}
  for key, _ in pairs(data_section_kind_players) do
    table.insert(ranking, key) -- creates an array with keys (=player_names)
  end
  table.sort(ranking, function(keyRhs, keyLhs) return data_section_kind_players[keyLhs]._sum < data_section_kind_players[keyRhs]._sum end) -- sorts player_names by value (dmg or heal)

  return ranking -- ranking is an array ranking[1] = "Kikidora",...
end

local function GetRankAttack(data_section_kind_player_attacks)
  local ranking = {}
  for key, _ in pairs(data_section_kind_player_attacks) do
    table.insert(ranking, key) -- creates an array with keys (=attacks)
  end
  table.sort(ranking, function(keyRhs, keyLhs) return data_section_kind_player_attacks[keyLhs] < data_section_kind_player_attacks[keyRhs] end) -- sorts player_names by value (dmg or heal)

  return ranking -- ranking is an array ranking[1] = "Kikidora",...
end

window:RegisterEvent("CHAT_MSG_ADDON")
window:SetScript("OnEvent", function()
  -- arg1: Prefix (KMkm_id_dmg_attack
      -- KMkm_id_eheal_attack
      -- KMkm_id_oheal_attack)
  -- arg2: Message (number)
  -- arg3: distribution type (RAID)
  -- arg4: sender (Kikidora)

  -- BroadcastValue(section, kind, attack, value)
  -- SendAddonMessage("KM"..km_id.."_"..section.."_"..kind.."_"..attack, value , "RAID") -- "KM4_ouro_dmg_hit", "10", "RAID"
  -- SendAddonMessage("KM"..km_id.."_SECTIONCHANGE_CHANGE_DETECTED", section , "RAID")
  local pattern = "KM"..km_id.."_(.+)".."_(.+)".."_(.+)"
  -- player_name = arg4
  -- value = arg2
  -- AddData(data, data_section, data_kind, player_name, attack, value) 
  for data_section, data_kind, attack in string.gfind(arg1, pattern) do
    if data_kind == "SECTIONCHANGE" then
      AddDataTimer(data_timer, arg4, "") -- create placeholder section, proper section change happens with first attack detection
    else
      AddDataTimer(data_timer, arg4, data_section)
      AddData(data, data_section, data_kind, arg4, attack, arg2)
    end
  end
end)

-- ################
-- # REFRESH BARS #
-- ################

local function UpdateSubKind(data, data_kind, data_timer)
  for idx_sub=1,config.sub_rows do
    local data_section = data_filter[idx_sub]
    if data[data_section] and data[data_section][data_kind] then
      data[data_section][data_kind]._ranking = GetRank(data[data_section][data_kind]._players) -- update rankings
      for _, player_name in pairs(data[data_section][data_kind]._ranking) do
        data[data_section][data_kind]._players[player_name]._ranking = GetRankAttack(data[data_section][data_kind]._players[player_name]._attacks)
      end
    end
    if data_kind=="dmg" then
      UpdateBarsSubKind(data, data_section, data_kind, window.sub[idx_sub].dmg.bars, data_timer)
    elseif data_kind=="eheal" then
      UpdateBarsSubKind(data, data_section, data_kind, window.sub[idx_sub].eheal.bars, data_timer)
    elseif data_kind=="oheal" then
      UpdateBarsSubKind(data, data_section, data_kind, window.sub[idx_sub].oheal.bars, data_timer)
    end
  end
end

-- for better performance, call UpdateBars only each config.refresh_time seconds
-- and calculate only one table (dmg, eheal or oheal) at a time
window:SetScript("OnUpdate", function()
  if not window.clock then window.clock = GetTime() end
  if not window.cycle then window.cycle = 0 end

  if GetTime() > window.clock + config.refresh_time then
    if window.cycle == 0 then -- update dmg bars
        UpdateSubKind(data, "dmg", data_timer)
    elseif window.cycle == 1 then -- update eheal bars
        UpdateSubKind(data, "eheal", data_timer)
    elseif window.cycle == 2 then -- update oheal bars
        UpdateSubKind(data, "oheal", data_timer)
    elseif window.cycle == 3 then -- update unitID_cache and player_zone
      for _,unitID in pairs(unitIDs) do -- update unitIDs_cache
        local name = UnitName(unitID)
        if name then
          unitIDs_cache[name] = unitID
        end
      end
      player_zone = GetZoneText()
    elseif window.cycle == 4 then
      GenSectionData(data, data_timer) -- generate special data sections (e.g. "All", "Bosses", ...)
      ProcessData(data) -- Process data (calculate sum and max)
    end

    window.clock = GetTime()
    window.cycle = math.mod(window.cycle + 1, 5)
  end
end)

-- Receptor's stupid AMG button
window.button_amg = CreateFrame("Button", nil, window)
ButtonLayout(window, window.button_amg, "AMG", "TOPRIGHT", "BOTTOMRIGHT", 0, 0, 0.1)
window.button_amg:SetScript("OnClick", function()
  if config.button_design == 0 then
    PlaySoundFile("Interface\\AddOns\\Kikimeter\\SFX_AMG_ON.ogg")
    config.button_design = 1
  else
    PlaySoundFile("Interface\\AddOns\\Kikimeter\\SFX_AMG_OFF.ogg")
    config.button_design = 0
  end
  ButtonDesign(window.button_reset)
  ButtonDesign(window.button_section)
  for data_section, _ in pairs(data) do
    if window.button_section[data_section] then
      ButtonDesign(window.button_section[data_section])
    end
  end
  ButtonDesign(window.button_max)
  ButtonDesign(button_hide)
  ButtonDesign(window.button_amg)
end)


-- ############
-- # TESTDATA #
-- ############

-- local number_test_players = 40

-- for number_player = 1,number_test_players do
--   unitIDs_cache["Player"..number_player] = true
-- end

-- local test_sender = CreateFrame("Frame")
-- test_sender:SetScript("OnUpdate", function()
--   if not test_sender.clock then test_sender.clock = GetTime() end
--   if GetTime() >= test_sender.clock + 0.1 then

--     for number_player = 1,number_test_players do
--       -- AddData(data, section, kind, arg4, attack, arg2)
--       AddData(data, "Trash", "dmg", "Player"..number_player, "Hit", math.random(number_player))
--       AddData(data, "Trash", "eheal", "Player"..number_player, "Hit", math.random(number_player))
--       AddData(data, "Trash", "oheal", "Player"..number_player, "Hit", math.random(number_player))

--       AddData(data, "Ouro", "dmg", "Player"..number_player, "Hit", math.random(number_player))
--       AddData(data, "Ouro", "eheal", "Player"..number_player, "Hit", math.random(number_player))
--       AddData(data, "Ouro", "oheal", "Player"..number_player, "Hit", math.random(number_player))
--     end
--     test_sender.clock = GetTime()
--   end
-- end)