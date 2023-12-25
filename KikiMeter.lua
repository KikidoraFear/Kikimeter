
-- for debugging: DEFAULT_CHAT_FRAME:AddMessage("Test")

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
local km_id = '1' -- corresponds to addon version (1.1 -> 1.2: no change in messages sent; 1.2 -> 2.0: change in messages sent = not compatible)

-- config table
local config = {
  width = 110, -- width of bars
  bar_height = 12, -- height of bars
  bars_show = 5, -- number of bars shown in sub
  spacing = 1, -- spacing between subs
  font_size = 8, -- font size for name and damage numbers
  btn_size = 10, -- size of buttons
  subs = 3, -- number of separate damage meters
  window_text_height = 10
}
config.sub_height = config.bar_height*config.bars_show -- height of one table


-- ####################
-- # HELPER FUNCTIONS #
-- ####################

local function InitData(data, min_loop, max_loop) -- init data table
  for idx=min_loop,max_loop do
    data[idx] = {}

    -- data[sub_number]._paused = true/false
    data[idx]._paused = false -- true if paused

    -- data[sub_number].dmg._max = value
    -- data[sub_number].dmg._scroll = value
    -- data[sub_number].dmg._ranking[rank] = player_name
    -- data[sub_number].dmg._players[name]._attacks[attack] = value
    -- data[sub_number].dmg._players[name]._sum = value
    -- data[sub_number].dmg._players[name]._ranking[rank] = attack
    data[idx].dmg = {}
    data[idx].dmg._max = 0
    data[idx].dmg._scroll = 0
    data[idx].dmg._ranking = {}
    data[idx].dmg._players = {}

    -- data[sub_number].eheal._max = value
    -- data[sub_number].eheal._scroll = value
    -- data[sub_number].eheal._ranking[rank] = player_name
    -- data[sub_number].eheal._players[name]._attacks[attack] = value
    -- data[sub_number].eheal._players[name]._sum = value
    -- data[sub_number].eheal._players[name]._ranking[rank] = attack
    data[idx].eheal = {}
    data[idx].eheal._max = 0
    data[idx].eheal._scroll = 0
    data[idx].eheal._ranking = {}
    data[idx].eheal._players = {}

    -- data[sub_number].oheal._players[name][attack] = value
    -- data[sub_number].oheal._players[name]._sum = value
    -- data[sub_number].oheal._ranking[rank] = player_name
    -- data[sub_number].oheal._players[name]._attacks[attack] = value
    -- data[sub_number].oheal._players[name]._sum = value
    -- data[sub_number].oheal._players[name]._ranking[rank] = attack
    data[idx].oheal = {}
    data[idx].oheal._max = 0
    data[idx].oheal._scroll = 0
    data[idx].oheal._ranking = {}
    data[idx].oheal._players = {}
  end
end

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
local unitIDs = {"player"}
for i=2,5 do unitIDs[i] = "party"..i-1 end
for i=6,45 do unitIDs[i] = "raid"..i-5 end
local unitIDs_cache = {} -- unitIDs_cache[name] = unitID
local function GetUnitID(name)
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
local function BroadcastValue(value, attack, oHeal)
  if oHeal then
    SendAddonMessage("KM"..km_id.."_EHEAL_"..attack, value , "RAID")
    SendAddonMessage("KM"..km_id.."_OHEAL_"..attack, oHeal , "RAID")
  else
    SendAddonMessage("KM"..km_id.."_DMG_"..attack, value , "RAID")
  end
end

-- calculate effective heal from total heal and target health
local function EOHeal(value, target)
  local unitID = GetUnitID(target)
  local eHeal = 0
  local oHeal = 0
  if unitID then
    eHeal = math.min(UnitHealthMax(unitID) - UnitHealth(unitID), value)
    oHeal = value-eHeal
  end
  return eHeal, oHeal
end

-- update bars and text with new values and show them
local function UpdateBars(bars, sub_type_data)

  local num_players = getArLength(sub_type_data._ranking)
  -- if scroll = -1, bars_show = 5, num_players = 3 -> bars_shown = 2
  local bars_shown = math.min(config.bars_show, num_players+sub_type_data._scroll)

  for idx=1, config.bars_show do
    local idx_f = idx -- for SetScript, otherwise last from loop idx is used
    if idx > bars_shown then -- hide bars with no data or not within scroll
      bars[idx].text_left:Hide()
      bars[idx].text_right:Hide()
      bars[idx]:Hide()
      bars[idx]:EnableMouse(true)
    else
      local rank = idx-sub_type_data._scroll -- idx=1, scroll=-1 -> rank on top = 2
      local player_name = sub_type_data._ranking[rank] -- table_ranking[idx] returns player_name and shows rank 1 first, table_ranking[idx-scroll] with scroll=-1 shows rank 2 first
      local value = sub_type_data._players[player_name]._sum -- use name from table_ranking to get value from table
      local num_attacks = getArLength(sub_type_data._players[player_name]._ranking)
      bars[idx].text_left:SetText(rank.."."..player_name)
      bars[idx].text_left:Show()
      bars[idx].text_right:SetText(sub_type_data._players[player_name]._sum)
      bars[idx].text_right:Show()
      bars[idx]:SetValue(value/sub_type_data._max*100)
      bars[idx]:Show()
      bars[idx]:EnableMouse(true)
      bars[idx]:SetScript("OnEnter", function()
        GameTooltip:SetOwner(bars[idx_f], "ANCHOR_LEFT")
        for rank_attack = 1, num_attacks do
          local attack = sub_type_data._players[player_name]._ranking[rank_attack]
          GameTooltip:AddDoubleLine(attack, sub_type_data._players[player_name]._attacks[attack])
        end
        GameTooltip:Show()
      end)
    end
  end
end


-- ########
-- # INIT #
-- ########

local data = {}
InitData(data, 1, config.subs)


-- ############################################
-- # PARSE COMBAT LOG AND BROADCAST SOURCE:ME #
-- ############################################

local parser = CreateFrame("Frame")

-- -- ####### DAMAGE COMBAT EVENTS
-- parser:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
-- -- parser:RegisterEvent("CHAT_MSG_COMBAT_PET_HITS")

-- -- ####### DAMAGE SPELL EVENTS
-- parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
-- parser:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
-- parser:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF")
-- -- parser:RegisterEvent("CHAT_MSG_SPELL_PET_DAMAGE")

-- -- ####### HEAL/DMG SPELL EVENTS
-- parser:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
-- parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
-- parser:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
-- parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
-- parser:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
-- parser:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
-- parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")

-- events are a total mess, using the ones from ShaguDPS...
-- register to all damage combat log events
parser:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF")
parser:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS")
parser:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
parser:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
parser:RegisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE")
parser:RegisterEvent("CHAT_MSG_COMBAT_PARTY_HITS")
parser:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
parser:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")
parser:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE")
parser:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS")
parser:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
parser:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE")
parser:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
parser:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS")
parser:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
parser:RegisterEvent("CHAT_MSG_SPELL_PET_DAMAGE")
parser:RegisterEvent("CHAT_MSG_COMBAT_PET_HITS")

-- register to all heal combat log events
parser:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
parser:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
parser:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
parser:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
parser:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS")


local function prepare(template) -- prepare global string for regex
  template = gsub(template, "%%s", "(.+)")
  return gsub(template, "%%d", "(%%d+)")
end

-- ####### DAMAGE SOURCE:ME TARGET:OTHER
local pSPELLLOGSCHOOLSELFOTHER = prepare(SPELLLOGSCHOOLSELFOTHER) -- Your %s hits %s for %d %s damage.
local pSPELLLOGCRITSCHOOLSELFOTHER = prepare(SPELLLOGCRITSCHOOLSELFOTHER) -- Your %s crits %s for %d %s damage.
local pSPELLLOGSELFOTHER = prepare(SPELLLOGSELFOTHER) -- Your %s hits %s for %d.
local pSPELLLOGCRITSELFOTHER = prepare(SPELLLOGCRITSELFOTHER) -- Your %s crits %s for %d.
local pPERIODICAURADAMAGESELFOTHER = prepare(PERIODICAURADAMAGESELFOTHER) -- %s suffers %d %s damage from your %s.
local pCOMBATHITSELFOTHER = prepare(COMBATHITSELFOTHER) -- You hit %s for %d.
local pCOMBATHITCRITSELFOTHER = prepare(COMBATHITCRITSELFOTHER) -- You crit %s for %d.
local pCOMBATHITSCHOOLSELFOTHER = prepare(COMBATHITSCHOOLSELFOTHER) -- You hit %s for %d %s damage.
local pCOMBATHITCRITSCHOOLSELFOTHER = prepare(COMBATHITCRITSCHOOLSELFOTHER) -- You crit %s for %d %s damage.

-- ####### HEAL SOURCE:ME TARGET:ME
local pHEALEDCRITSELFSELF = prepare(HEALEDCRITSELFSELF) -- Your %s critically heals you for %d.
local pHEALEDSELFSELF = prepare(HEALEDSELFSELF) -- Your %s heals you for %d.
local pPERIODICAURAHEALSELFSELF = prepare(PERIODICAURAHEALSELFSELF) -- You gain %d health from %s.

-- ####### HEAL SOURCE:ME TARGET:OTHER
local pHEALEDCRITSELFOTHER = prepare(HEALEDCRITSELFOTHER) -- Your %s critically heals %s for %d.
local pHEALEDSELFOTHER = prepare(HEALEDSELFOTHER) -- Your %s heals %s for %d.
local pPERIODICAURAHEALSELFOTHER = prepare(PERIODICAURAHEALSELFOTHER) -- %s gains %d health from your %s.

-- ####### DAMAGE SOURCE:PET TARGET:OTHER
local pSPELLLOGSCHOOLOTHEROTHER = prepare(SPELLLOGSCHOOLOTHEROTHER) -- %s's %s hits %s for %d %s damage.
local pSPELLLOGCRITSCHOOLOTHEROTHER = prepare(SPELLLOGCRITSCHOOLOTHEROTHER)  -- %s's %s crits %s for %d %s damage.
local pSPELLLOGOTHEROTHER = prepare(SPELLLOGOTHEROTHER) -- %s's %s hits %s for %d.
local pSPELLLOGCRITOTHEROTHER = prepare(SPELLLOGCRITOTHEROTHER) -- %s's %s crits %s for %d.
local pPERIODICAURADAMAGEOTHEROTHER = prepare(PERIODICAURADAMAGEOTHEROTHER) -- "%s suffers %d %s damage from %s's %s."
local pCOMBATHITOTHEROTHER = prepare(COMBATHITOTHEROTHER) -- %s hits %s for %d.


parser:SetScript("OnEvent", function()
    -- local source = UnitName("player")
    local target = UnitName("player")
    -- local school = "physical"
    local attack = "Auto Hit"

    if arg1 then
      -- ####### DAMAGE SOURCE:ME TARGET:OTHER
      -- Your %s hits %s for %d %s damage.
      for attack, target, value, school in string.gfind(arg1, pSPELLLOGSCHOOLSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

       -- Your %s crits %s for %d %s damage.
      for attack, target, value, school in string.gfind(arg1, pSPELLLOGCRITSCHOOLSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

       -- Your %s hits %s for %d.
      for attack, target, value in string.gfind(arg1, pSPELLLOGSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

       -- Your %s crits %s for %d.
      for attack, target, value in string.gfind(arg1, pSPELLLOGCRITSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

      -- %s suffers %d %s damage from your %s.
      for target, value, school, attack in string.gfind(arg1, pPERIODICAURADAMAGESELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

      -- You hit %s for %d.
      for target, value in string.gfind(arg1, pCOMBATHITSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

      -- You crit %s for %d.
      for target, value in string.gfind(arg1, pCOMBATHITCRITSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

      -- You hit %s for %d %s damage.
      for target, value, school in string.gfind(arg1, pCOMBATHITSCHOOLSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

      -- You crit %s for %d %s damage.
      for target, value, school in string.gfind(arg1, pCOMBATHITCRITSCHOOLSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

      -- ####### HEAL SOURCE:ME TARGET:ME
      -- Your %s critically heals you for %d.
      for attack, value in string.gfind(arg1, pHEALEDCRITSELFSELF) do
        local eHeal, oHeal = EOHeal(value, target)
        BroadcastValue(eHeal, attack, oHeal)
        return
      end

      -- Your %s heals you for %d.
      for attack, value in string.gfind(arg1, pHEALEDSELFSELF) do
        local eHeal, oHeal = EOHeal(value, target)
        BroadcastValue(eHeal, attack, oHeal)
        return
      end

      -- You gain %d health from %s.
      for value, attack in string.gfind(arg1, pPERIODICAURAHEALSELFSELF) do
        local eHeal, oHeal = EOHeal(value, target)
        BroadcastValue(eHeal, attack, oHeal)
        return
      end

      -- ####### HEAL SOURCE:ME TARGET:OTHER
      -- Your %s critically heals %s for %d.
      for attack, target, value in string.gfind(arg1, pHEALEDCRITSELFOTHER) do
        local eHeal, oHeal = EOHeal(value, target)
        BroadcastValue(eHeal, attack, oHeal)
        return
      end

      -- Your %s heals %s for %d.
      for attack, target, value in string.gfind(arg1, pHEALEDSELFOTHER) do
        local eHeal, oHeal = EOHeal(value, target)
        BroadcastValue(eHeal, attack, oHeal)
        return
      end

      -- %s gains %d health from your %s.
      for target, value, attack in string.gfind(arg1, pPERIODICAURAHEALSELFOTHER) do
        local eHeal, oHeal = EOHeal(value, target)
        BroadcastValue(eHeal, attack, oHeal)
        return
      end

      -- ####### DAMAGE SOURCE:PET TARGET:OTHER
      local pet_name = UnitName("pet") -- pet_name has to be checked each event (could be renamed/resummoned)
      -- other
       -- %s's %s hits %s for %d %s damage.
       for source, attack, target, value, school in string.gfind(arg1, pSPELLLOGSCHOOLOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        end
        return
      end

       -- %s's %s crits %s for %d %s damage.
      for source, attack, target, value, school in string.gfind(arg1, pSPELLLOGCRITSCHOOLOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        end
        return
      end

       -- %s's %s hits %s for %d.
      for source, attack, target, value in string.gfind(arg1, pSPELLLOGOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        end
        return
      end

       -- %s's %s crits %s for %d.
      for source, attack, target, value, school in string.gfind(arg1, pSPELLLOGCRITOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        end
        return
      end

      -- "%s suffers %d %s damage from %s's %s."
      for target, value, school, source, attack in string.gfind(arg1, pPERIODICAURADAMAGEOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        end
        return
      end

      -- %s hits %s for %d.
      for source, target, value in string.gfind(arg1, pCOMBATHITOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        end
        return
      end
    end
end)

-- ##########
-- # LAYOUT #
-- ##########

local function BarLayout(parent, bar, bar_num, col)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:ClearAllPoints()
  bar:SetPoint("TOP", parent, "TOP", 0, -config.bar_height * (bar_num-1))
  bar:SetHeight(config.bar_height)
  bar:SetWidth(config.width)
  bar:SetMinMaxValues(0, 100)
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

local function TextLayout(parent, text, pos)
  text:SetFont(STANDARD_TEXT_FONT, config.font_size, "THINOUTLINE")
  text:SetFontObject(GameFontWhite)
  text:ClearAllPoints()
  text:SetPoint(pos, parent, pos, 0, 0)
  text:Hide()
end

local function WindowLayout(window)
  window:SetBackdrop({bgFile = 'Interface\\Tooltips\\UI-Tooltip-Background'})
  window:SetBackdropColor(0, 0, 0, 1)
  window:ClearAllPoints()
  window:SetPoint("RIGHT", UIParent, "RIGHT", -100, -100)
  window:SetWidth(config.width*3 + 2*config.spacing)
  window:SetHeight(config.sub_height*config.subs + (config.subs-1)*config.spacing + config.window_text_height)
  window:EnableMouse(true) -- needed for it to be movable
  window:RegisterForDrag("LeftButton")
  window:SetMovable(true)
  window:SetUserPlaced(true) -- saves the place the user dragged it to
  window:SetScript("OnDragStart", function() window:StartMoving() end)
  window:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
  window:SetClampedToScreen(true) -- so the window cant be moved out of screen

  window.text_left = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  window.text_left:SetFont(STANDARD_TEXT_FONT, config.font_size, "THINOUTLINE")
  window.text_left:SetFontObject(GameFontWhite)
  window.text_left:ClearAllPoints()
  window.text_left:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 0, 2)
  window.text_left:SetText("damage done")
  window.text_left:Show()
  window.text_center = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  window.text_center:SetFont(STANDARD_TEXT_FONT, config.font_size, "THINOUTLINE")
  window.text_center:SetFontObject(GameFontWhite)
  window.text_center:ClearAllPoints()
  window.text_center:SetPoint("BOTTOM", window, "BOTTOM", 0, 2)
  window.text_center:SetText("effective healing")
  window.text_center:Show()
  window.text_right = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  window.text_right:SetFont(STANDARD_TEXT_FONT, config.font_size, "THINOUTLINE")
  window.text_right:SetFontObject(GameFontWhite)
  window.text_right:ClearAllPoints()
  window.text_right:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, 2)
  window.text_right:SetText("over healing")
  window.text_right:Show()
end

local function CreateBar(parent, idx, col)
  parent.bars[idx] = CreateFrame("StatusBar", nil, parent)
  BarLayout(parent, parent.bars[idx], idx, col)
  
  parent.bars[idx].text_left = parent.bars[idx]:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(parent.bars[idx], parent.bars[idx].text_left, "LEFT")

  parent.bars[idx].text_right = parent.bars[idx]:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(parent.bars[idx], parent.bars[idx].text_right, "RIGHT")
end

local function SubLayout(parent, sub, sub_num)
  sub:SetBackdrop({bgFile = 'Interface\\Tooltips\\UI-Tooltip-Background'})
  sub:SetBackdropColor(0, 0, 0, 0)
  sub:ClearAllPoints()
  sub:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(sub_num-1)*(config.sub_height+config.spacing))
  sub:SetWidth(config.width*2 + config.spacing)
  sub:SetHeight(config.sub_height)
end

local function SubTypeLayout(parent, sub_type, sub_type_data, pos_h, col)
  sub_type:SetBackdrop({bgFile = 'Interface\\Tooltips\\UI-Tooltip-Background'})
  if col == 1 then
    sub_type:SetBackdropColor(1, 0.5, 0.5, 1)
  elseif col == 2 then
    sub_type:SetBackdropColor(0.5, 1, 0.5, 1)
  else
    sub_type:SetBackdropColor(0.5, 0.5, 1, 1)
  end
  sub_type:SetPoint("TOPLEFT", parent, "TOPLEFT", pos_h, 0)
  sub_type:SetWidth(config.width)
  sub_type:SetHeight(config.sub_height)
  sub_type:EnableMouseWheel(true)
  sub_type:SetScript("OnMouseWheel", function()
    if getArLength(sub_type_data._ranking) > 0 then
      -- scrolling from 0 to -player_num + 1, so that at least 1 player is always shown
      local min_scroll = -getArLength(sub_type_data._ranking) + 1
      sub_type_data._scroll = math.min(math.max(sub_type_data._scroll+arg1, min_scroll),0)
    end
    UpdateBars(sub_type.bars, sub_type_data)
  end)
end

local function ButtonLayout(parent, btn, tooltip_txt, pos_v)
  btn:SetPoint("TOPRIGHT", parent, "TOPLEFT", 0, pos_v)
  btn:SetHeight(config.btn_size)
  btn:SetWidth(config.btn_size)
  btn:SetBackdrop({bgFile = 'Interface\\Tooltips\\UI-Tooltip-Background'})
  btn:SetBackdropColor(1, 1, 1, 1)
  btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:AddLine(tooltip_txt)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

local window = CreateFrame("Frame", "KikiMeter", UIParent)
WindowLayout(window)
window.sub = {}
for idx=1,config.subs do

  local idx_f = idx -- create new local idx for OnClick,... otherwise it would always use idx of the last loop (=config.subs)

  window.sub[idx_f] = CreateFrame("Frame", nil, window)
  SubLayout(window, window.sub[idx_f], idx_f)

  window.sub[idx_f].dmg = CreateFrame("Frame", nil, window.sub[idx_f])
  SubTypeLayout(window.sub[idx_f], window.sub[idx_f].dmg, data[idx_f].dmg, 0, 1)

  window.sub[idx_f].eheal = CreateFrame("Frame", nil, window.sub[idx_f])
  SubTypeLayout(window.sub[idx_f], window.sub[idx_f].eheal, data[idx_f].eheal, config.width + config.spacing, 2)

  window.sub[idx_f].oheal = CreateFrame("Frame", nil, window.sub[idx_f])
  SubTypeLayout(window.sub[idx_f], window.sub[idx_f].oheal, data[idx_f].oheal, 2*config.width + 2*config.spacing, 3)

  window.sub[idx_f].btnReset = CreateFrame("Button", nil, window.sub[idx_f])
  ButtonLayout(window.sub[idx_f], window.sub[idx_f].btnReset, "Reset", 0)
  window.sub[idx_f].btnReset:SetScript("OnClick", function()
    DEFAULT_CHAT_FRAME:AddMessage("KikiMeter "..idx_f.." has been reset.")
    InitData(data, idx_f, idx_f)
    UpdateBars(window.sub[idx_f].dmg.bars, data[idx_f].dmg)
    UpdateBars(window.sub[idx_f].eheal.bars, data[idx_f].eheal)
    UpdateBars(window.sub[idx_f].oheal.bars, data[idx_f].oheal)
  end)
  window.sub[idx_f].btnReset.text = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  window.sub[idx_f].btnReset.text:SetFont(STANDARD_TEXT_FONT, config.font_size, "THINOUTLINE")
  window.sub[idx_f].btnReset.text:SetFontObject(GameFontWhite)
  window.sub[idx_f].btnReset.text:ClearAllPoints()
  window.sub[idx_f].btnReset.text:SetPoint("LEFT", window.sub[idx_f].btnReset, "LEFT", 0, 0)
  window.sub[idx_f].btnReset.text:SetText("R")
  window.sub[idx_f].btnReset.text:Show()
  
  

  window.sub[idx].btnPause = CreateFrame("Button", nil, window.sub[idx])
  ButtonLayout(window.sub[idx], window.sub[idx].btnPause, "Pause", -config.btn_size-config.spacing)
  window.sub[idx].btnPause:SetScript("OnClick", function()
    if data[idx_f]._paused then
      DEFAULT_CHAT_FRAME:AddMessage("KikiMeter "..idx_f.." has been unpaused.")
      data[idx_f]._paused = false
      window.sub[idx_f].btnPause:SetBackdropColor(1, 1, 1, 1)
    else
      DEFAULT_CHAT_FRAME:AddMessage("KikiMeter "..idx_f.." has been paused.")
      data[idx_f]._paused = true
      window.sub[idx_f].btnPause:SetBackdropColor(0, 0, 0, 1)
    end
  end)
  window.sub[idx_f].btnPause.text = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  window.sub[idx_f].btnPause.text:SetFont(STANDARD_TEXT_FONT, config.font_size, "THINOUTLINE")
  window.sub[idx_f].btnPause.text:SetFontObject(GameFontWhite)
  window.sub[idx_f].btnPause.text:ClearAllPoints()
  window.sub[idx_f].btnPause.text:SetPoint("LEFT", window.sub[idx_f].btnPause, "LEFT", 0, 0)
  window.sub[idx_f].btnPause.text:SetText("P")
  window.sub[idx_f].btnPause.text:Show()

  window.sub[idx].dmg.bars = {}
  window.sub[idx].eheal.bars = {}
  window.sub[idx].oheal.bars = {}

  for idx_bar = 1,config.bars_show do
    CreateBar(window.sub[idx].dmg, idx_bar, 1)
    CreateBar(window.sub[idx].eheal, idx_bar, 2)
    CreateBar(window.sub[idx].oheal, idx_bar, 3)
  end
end


-- #######################################################
-- # LISTEN TO BROADCAST, CRUNCH NUMBERS AND SHOW RESULT #
-- #######################################################

local function GetRank(sub_type_players_data) --sub_type[player_name]._sum = value
  local ranking = {}
  for key, _ in pairs(sub_type_players_data) do
    table.insert(ranking, key) -- creates an array with keys (=player_names)
  end
  table.sort(ranking, function(keyRhs, keyLhs) return sub_type_players_data[keyLhs]._sum < sub_type_players_data[keyRhs]._sum end) -- sorts player_names by value (dmg or heal)

  return ranking -- ranking is an array ranking[1] = "Kikidora",...
end

local function GetRankAttack(sub_type_players_attacks_data)
  local ranking = {}
  for key, _ in pairs(sub_type_players_attacks_data) do
    table.insert(ranking, key) -- creates an array with keys (=attacks)
  end
  table.sort(ranking, function(keyRhs, keyLhs) return sub_type_players_attacks_data[keyLhs] < sub_type_players_attacks_data[keyRhs] end) -- sorts player_names by value (dmg or heal)

  return ranking -- ranking is an array ranking[1] = "Kikidora",...
end

local function AddData(sub_type_data, player_name, attack, value)
  if not sub_type_data._players[player_name] then
    sub_type_data._players[player_name] = {}
    sub_type_data._players[player_name]._sum = 0 -- if player doesnt exist, init sum
    sub_type_data._players[player_name]._attacks = {} -- if player doesnt exist, init attacks
  end

  if not sub_type_data._players[player_name]._attacks[attack] then
    sub_type_data._players[player_name]._attacks[attack] = 0 -- if attack for player doesnt exist, init value
  end

  sub_type_data._players[player_name]._sum = sub_type_data._players[player_name]._sum + tonumber(value)
  sub_type_data._players[player_name]._attacks[attack] = sub_type_data._players[player_name]._attacks[attack] + tonumber(value)

  if sub_type_data._players[player_name]._sum > sub_type_data._max then
    sub_type_data._max = sub_type_data._players[player_name]._sum -- update max value
  end

  sub_type_data._ranking = GetRank(sub_type_data._players) -- update rankings
  sub_type_data._players[player_name]._ranking = GetRankAttack(sub_type_data._players[player_name]._attacks)
end

window:RegisterEvent("CHAT_MSG_ADDON")
window:SetScript("OnEvent", function()
  -- arg1: Prefix (KM_km_id_DMG_attack
      -- KM_km_id_EHEAL_attack
      -- KM_km_id_OHEAL_attack)
  -- arg2: Message (number)
  -- arg3: distribution type (RAID)
  -- arg4: sender (Kikidora)
  local pattern = "KM"..km_id.."_(.+)_".."(.+)"
  
  for kind, attack in string.gfind(arg1, pattern) do
    if kind == "DMG" then
      for idx=1,config.subs do
        if not data[idx]._paused then
          AddData(data[idx].dmg, arg4, attack, arg2)
          UpdateBars(window.sub[idx].dmg.bars, data[idx].dmg)
        end
      end
    elseif kind == "EHEAL" then
      for idx=1,config.subs do
        if not data[idx]._paused then
          AddData(data[idx].eheal, arg4, attack, arg2)
          UpdateBars(window.sub[idx].eheal.bars, data[idx].eheal)
        end
      end
    elseif kind == "OHEAL" then
      for idx=1,config.subs do
        if not data[idx]._paused then
          AddData(data[idx].oheal, arg4, attack, arg2)
          UpdateBars(window.sub[idx].oheal.bars, data[idx].oheal)
        end
      end
    end
  end
end)