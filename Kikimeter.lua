
-- for debugging: DEFAULT_CHAT_FRAME:AddMessage("Test")
local function print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- check parse order (order important!, e.g. PERIODICAURAHEALOTHERSELF has to be parsed first for escaping PERIODICAURAHEALSELFSELF)

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
local km_id = '3' -- corresponds to addon version (1.1 -> 1.2: no change in messages sent; 1.2 -> 2.0: change in messages sent = not compatible)

local gui_hidden = false -- hides the window

-- config table
local config = {
  width = 110, -- width of bars
  bar_height = 12, -- height of bars
  bars_show = 5, -- number of bars shown in sub
  spacing = 1, -- spacing between subs
  font_size = 8, -- font size for name and damage numbers
  btn_size = 10, -- size of buttons
  subs = 2, -- number of separate damage meters
  window_text_height = 10,
  refresh_time = 1 -- refresh time in seconds (for updating Bars)
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
    SendAddonMessage("KM"..km_id.."_eheal_"..attack, value , "RAID")
    SendAddonMessage("KM"..km_id.."_oheal_"..attack, oHeal , "RAID")
  else
    SendAddonMessage("KM"..km_id.."_dmg_"..attack, value , "RAID")
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

-- ########
-- # INIT #
-- ########

local data = {}
InitData(data, 1, config.subs) -- init all subs
local users = {} -- users[player_name] = true ...show who is using Kikimeter



-- update bars and text with new values and show them
local function UpdateBars(bars, sub_type_data)
  for idx=1, config.bars_show do
    local idx_f = idx -- for SetScript, otherwise last from loop idx is used
    local rank = idx+sub_type_data._scroll -- idx=1, scroll=1 -> rank on top = 2
    if sub_type_data._ranking[rank] then
      local player_name = sub_type_data._ranking[rank]
      local value = sub_type_data._players[player_name]._sum
      local num_attacks = getArLength(sub_type_data._players[player_name]._ranking)
      if users[player_name] then
        bars[idx].text_left:SetText("|cFFFFDF00"..rank.."."..player_name.."|r") -- |cAARRGGBBtext|r Alpha Red Green Blue
        bars[idx].text_right:SetText("|cFFFFDF00"..sub_type_data._players[player_name]._sum.."|r")
      else
        bars[idx].text_left:SetText(rank.."."..player_name)
        bars[idx].text_right:SetText(sub_type_data._players[player_name]._sum)
      end
      bars[idx].text_left:Show()
      bars[idx].text_right:Show()
      bars[idx]:SetValue(value/sub_type_data._max*100)
      bars[idx]:Show()
      bars[idx]:SetScript("OnEnter", function()
        GameTooltip:SetOwner(bars[idx_f], "ANCHOR_LEFT")
        for rank_attack = 1, num_attacks do
          local attack = sub_type_data._players[player_name]._ranking[rank_attack]
          GameTooltip:AddDoubleLine(attack, sub_type_data._players[player_name]._attacks[attack])
        end
        GameTooltip:Show()
      end)
    else -- hide bars with no data
      bars[idx].text_left:Hide()
      bars[idx].text_right:Hide()
      bars[idx]:Hide()
    end
  end
end


local function AddData(data, player_name, kind, attack, value) 
  if kind == "user" then -- register sender as Kikimeter user
    users[player_name] = true
  else -- other kinds are "dmg", "eheal", "oheal"
    for idx=1,config.subs do
      if not data[idx]._paused then
        if not data[idx][kind]._players[player_name] then
          data[idx][kind]._players[player_name] = {}
          data[idx][kind]._players[player_name]._sum = 0 -- if player doesnt exist, init sum
          data[idx][kind]._players[player_name]._attacks = {} -- if player doesnt exist, init attacks
        end
      
        if not data[idx][kind]._players[player_name]._attacks[attack] then
          data[idx][kind]._players[player_name]._attacks[attack] = 0 -- if attack for player doesnt exist, init value
        end
      
        data[idx][kind]._players[player_name]._sum = data[idx][kind]._players[player_name]._sum + tonumber(value)
        data[idx][kind]._players[player_name]._attacks[attack] = data[idx][kind]._players[player_name]._attacks[attack] + tonumber(value)
      
        if data[idx][kind]._players[player_name]._sum > data[idx][kind]._max then
          data[idx][kind]._max = data[idx][kind]._players[player_name]._sum -- update max value
        end
      end
    end
  end
end




-- ############################################
-- # PARSE COMBAT LOG AND BROADCAST SOURCE:ME #
-- ############################################

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

local pcl = {}
-- ####### HEAL SOURCE:ME TARGET:ME
pcl.pHEALEDCRITSELFSELF = MakeGfindReady(HEALEDCRITSELFSELF) -- Your %s critically heals you for %d.
pcl.pHEALEDSELFSELF = MakeGfindReady(HEALEDSELFSELF) -- Your %s heals you for %d.
pcl.pPERIODICAURAHEALSELFSELF = MakeGfindReady(PERIODICAURAHEALSELFSELF) -- You gain %d health from %s.

-- ####### HEAL SOURCE:OTHER TARGET:ME (for escaping PERIODICAURAHEALSELFSELF)
pcl.pHEALEDCRITOTHERSELF = MakeGfindReady(HEALEDCRITOTHERSELF) -- %s's %s critically heals you for %d.
pcl.pHEALEDOTHERSELF = MakeGfindReady(HEALEDOTHERSELF) -- %s's %s heals you for %d.
pcl.pPERIODICAURAHEALOTHERSELF = MakeGfindReady(PERIODICAURAHEALOTHERSELF) -- You gain %d health from %s's %s.

-- ####### HEAL SOURCE:ME TARGET:OTHER
pcl.pHEALEDCRITSELFOTHER = MakeGfindReady(HEALEDCRITSELFOTHER) -- Your %s critically heals %s for %d.
pcl.pHEALEDSELFOTHER = MakeGfindReady(HEALEDSELFOTHER) -- Your %s heals %s for %d.
pcl.pPERIODICAURAHEALSELFOTHER = MakeGfindReady(PERIODICAURAHEALSELFOTHER) -- %s gains %d health from your %s.

-- ####### HEAL SOURCE:OTHER TARGET:OTHER
pcl.pHEALEDCRITOTHEROTHER = MakeGfindReady(HEALEDCRITOTHEROTHER) -- %s's %s critically heals %s for %d.
pcl.pHEALEDOTHEROTHER = MakeGfindReady(HEALEDOTHEROTHER) -- %s's %s heals %s for %d.
pcl.pPERIODICAURAHEALOTHEROTHER = MakeGfindReady(PERIODICAURAHEALOTHEROTHER) -- %s gains %d health from %s's %s.

-- ####### DAMAGE SOURCE:ME TARGET:OTHER
pcl.pSPELLLOGSCHOOLSELFOTHER = MakeGfindReady(SPELLLOGSCHOOLSELFOTHER) -- Your %s hits %s for %d %s damage.
pcl.pSPELLLOGCRITSCHOOLSELFOTHER = MakeGfindReady(SPELLLOGCRITSCHOOLSELFOTHER) -- Your %s crits %s for %d %s damage.
pcl.pSPELLLOGSELFOTHER = MakeGfindReady(SPELLLOGSELFOTHER) -- Your %s hits %s for %d.
pcl.pSPELLLOGCRITSELFOTHER = MakeGfindReady(SPELLLOGCRITSELFOTHER) -- Your %s crits %s for %d.
pcl.pPERIODICAURADAMAGESELFOTHER = MakeGfindReady(PERIODICAURADAMAGESELFOTHER) -- %s suffers %d %s damage from your %s.
pcl.pCOMBATHITSELFOTHER = MakeGfindReady(COMBATHITSELFOTHER) -- You hit %s for %d.
pcl.pCOMBATHITCRITSELFOTHER = MakeGfindReady(COMBATHITCRITSELFOTHER) -- You crit %s for %d.
pcl.pCOMBATHITSCHOOLSELFOTHER = MakeGfindReady(COMBATHITSCHOOLSELFOTHER) -- You hit %s for %d %s damage.
pcl.pCOMBATHITCRITSCHOOLSELFOTHER = MakeGfindReady(COMBATHITCRITSCHOOLSELFOTHER) -- You crit %s for %d %s damage.
pcl.pDAMAGESHIELDSELFOTHER = MakeGfindReady(DAMAGESHIELDSELFOTHER) -- You reflect %d %s damage to %s.

-- ####### DAMAGE SOURCE:OTHER TARGET:OTHER
pcl.pSPELLLOGSCHOOLOTHEROTHER = MakeGfindReady(SPELLLOGSCHOOLOTHEROTHER) -- %s's %s hits %s for %d %s damage.
pcl.pSPELLLOGCRITSCHOOLOTHEROTHER = MakeGfindReady(SPELLLOGCRITSCHOOLOTHEROTHER)  -- %s's %s crits %s for %d %s damage.
pcl.pSPELLLOGOTHEROTHER = MakeGfindReady(SPELLLOGOTHEROTHER) -- %s's %s hits %s for %d.
pcl.pSPELLLOGCRITOTHEROTHER = MakeGfindReady(SPELLLOGCRITOTHEROTHER) -- %s's %s crits %s for %d.
pcl.pPERIODICAURADAMAGEOTHEROTHER = MakeGfindReady(PERIODICAURADAMAGEOTHEROTHER) -- "%s suffers %d %s damage from %s's %s."
pcl.pCOMBATHITOTHEROTHER = MakeGfindReady(COMBATHITOTHEROTHER) -- %s hits %s for %d.
pcl.pCOMBATHITCRITOTHEROTHER = MakeGfindReady(COMBATHITCRITOTHEROTHER) -- %s crits %s for %d.
pcl.pCOMBATHITSCHOOLOTHEROTHER = MakeGfindReady(COMBATHITSCHOOLOTHEROTHER) -- %s hits %s for %d %s damage.
pcl.pCOMBATHITCRITSCHOOLOTHEROTHER = MakeGfindReady(COMBATHITCRITSCHOOLOTHEROTHER) -- %s crits %s for %d %s damage.
pcl.pDAMAGESHIELDOTHEROTHER = MakeGfindReady(DAMAGESHIELDOTHEROTHER) -- %s reflects %d %s damage to %s.



parser:SetScript("OnEvent", function()
    -- local source = UnitName("player")
    local target = UnitName("player")
    -- local school = "physical"
    local attack = "Auto Hit"

    if arg1 then

      -- advancedvanillacombatlog compatibility: this addon turns
      -- "You" and "Your" into "player_name" and "player_name 's"
      arg1 = string.gsub(arg1, target.." 's", "Your")
      arg1 = string.gsub(arg1, target.." hits", "You hit")
      arg1 = string.gsub(arg1, target.." crits", "You crit")
      arg1 = string.gsub(arg1, target.." gains", "You gain")

    -- #################
    -- # PARSE HEALING #
    -- #################

      -- ####### HEAL SOURCE:OTHER TARGET:ME
      -- %s's %s critically heals you for %d.
      for source, attack, value in string.gfind(arg1, pcl.pHEALEDCRITOTHERSELF) do
        if not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          local eHeal, oHeal = EOHeal(value, target)
          AddData(data, source, "eheal", attack, eHeal)
          AddData(data, source, "oheal", attack, oHeal) 
        end
        return
      end

      -- %s's %s heals you for %d.
      for source, attack, value in string.gfind(arg1, pcl.pHEALEDOTHERSELF) do
        if not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          local eHeal, oHeal = EOHeal(value, target)
          AddData(data, source, "eheal", attack, eHeal)
          AddData(data, source, "oheal", attack, oHeal) 
        end
        return
      end

      -- You gain %d health from %s's %s. (has to be before "You gain %d health from %s.")
      for value, source, attack in string.gfind(arg1, pcl.pPERIODICAURAHEALOTHERSELF) do
        if not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          local eHeal, oHeal = EOHeal(value, target)
          AddData(data, source, "eheal", attack, eHeal)
          AddData(data, source, "oheal", attack, oHeal) 
        end
        return
      end

      -- ####### HEAL SOURCE:ME TARGET:ME
      -- Your %s critically heals you for %d.
      for attack, value in string.gfind(arg1, pcl.pHEALEDCRITSELFSELF) do
        local eHeal, oHeal = EOHeal(value, target)
        BroadcastValue(eHeal, attack, oHeal)
        return
      end

      -- Your %s heals you for %d.
      for attack, value in string.gfind(arg1, pcl.pHEALEDSELFSELF) do
        local eHeal, oHeal = EOHeal(value, target)
        BroadcastValue(eHeal, attack, oHeal)
        return
      end

      -- You gain %d health from %s.
      for value, attack in string.gfind(arg1, pcl.pPERIODICAURAHEALSELFSELF) do
        local eHeal, oHeal = EOHeal(value, target)
        BroadcastValue(eHeal, attack, oHeal)
        return
      end

      -- ####### HEAL SOURCE:ME TARGET:OTHER
      -- Your %s critically heals %s for %d.
      for attack, target, value in string.gfind(arg1, pcl.pHEALEDCRITSELFOTHER) do
        local eHeal, oHeal = EOHeal(value, target)
        BroadcastValue(eHeal, attack, oHeal)
        return
      end

      -- Your %s heals %s for %d.
      for attack, target, value in string.gfind(arg1, pcl.pHEALEDSELFOTHER) do
        local eHeal, oHeal = EOHeal(value, target)
        BroadcastValue(eHeal, attack, oHeal)
        return
      end

      -- %s gains %d health from your %s.
      for target, value, attack in string.gfind(arg1, pcl.pPERIODICAURAHEALSELFOTHER) do
        local eHeal, oHeal = EOHeal(value, target)
        BroadcastValue(eHeal, attack, oHeal)
        return
      end 

      -- ####### HEAL SOURCE:OTHER TARGET:OTHER
      -- %s's %s critically heals %s for %d.
      for source, attack, target, value in string.gfind(arg1, pcl.pHEALEDCRITOTHEROTHER) do
        if not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          local eHeal, oHeal = EOHeal(value, target)
          AddData(data, source, "eheal", attack, eHeal)
          AddData(data, source, "oheal", attack, oHeal) 
        end
        return
      end

      -- %s's %s heals %s for %d.
      for source, attack, target, value in string.gfind(arg1, pcl.pHEALEDOTHEROTHER) do
        if not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          local eHeal, oHeal = EOHeal(value, target)
          AddData(data, source, "eheal", attack, eHeal)
          AddData(data, source, "oheal", attack, oHeal) 
        end
        return
      end

      -- %s gains %d health from %s's %s.
      for target, value, source, attack in string.gfind(arg1, pcl.pPERIODICAURAHEALOTHEROTHER) do
        if not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          local eHeal, oHeal = EOHeal(value, target)
          AddData(data, source, "eheal", attack, eHeal)
          AddData(data, source, "oheal", attack, oHeal) 
        end
        return
      end


      -- ################
      -- # PARSE DAMAGE #
      -- ################

      -- ####### DAMAGE SOURCE:ME TARGET:OTHER
      -- Your %s hits %s for %d %s damage.
      for attack, target, value, school in string.gfind(arg1, pcl.pSPELLLOGSCHOOLSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

       -- Your %s crits %s for %d %s damage.
      for attack, target, value, school in string.gfind(arg1, pcl.pSPELLLOGCRITSCHOOLSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

       -- Your %s hits %s for %d. (has to be before "%s hits %s for %d.")
      for attack, target, value in string.gfind(arg1, pcl.pSPELLLOGSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

       -- Your %s crits %s for %d.
      for attack, target, value in string.gfind(arg1, pcl.pSPELLLOGCRITSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

      -- %s suffers %d %s damage from your %s.
      for target, value, school, attack in string.gfind(arg1, pcl.pPERIODICAURADAMAGESELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

      -- You hit %s for %d.
      for target, value in string.gfind(arg1, pcl.pCOMBATHITSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

      -- You crit %s for %d.
      for target, value in string.gfind(arg1, pcl.pCOMBATHITCRITSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

      -- You hit %s for %d %s damage.
      for target, value, school in string.gfind(arg1, pcl.pCOMBATHITSCHOOLSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

      -- You crit %s for %d %s damage.
      for target, value, school in string.gfind(arg1, pcl.pCOMBATHITCRITSCHOOLSELFOTHER) do
        BroadcastValue(value, attack, nil)
        return
      end

      -- You reflect %d %s damage to %s.
      for value, school, target in string.gfind(arg1, pcl.pDAMAGESHIELDSELFOTHER) do
        BroadcastValue(value, "Reflect", nil)
        return
      end

      -- ####### DAMAGE SOURCE:OTHER TARGET:OTHER
      local pet_name = UnitName("pet") -- pet_name has to be checked each event (could be renamed/resummoned)
      -- %s's %s hits %s for %d %s damage. (has to be before "%s hits %s for %d %s damage.")
      for source, attack, target, value, school in string.gfind(arg1, pcl.pSPELLLOGSCHOOLOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        elseif not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          AddData(data, source, "dmg", attack, value)
        end
        return
      end

       -- %s's %s crits %s for %d %s damage. (has to be before "%s crits %s for %d %s damage.")
      for source, attack, target, value, school in string.gfind(arg1, pcl.pSPELLLOGCRITSCHOOLOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        elseif not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          AddData(data, source, "dmg", attack, value)
        end
        return
      end

       -- %s's %s hits %s for %d.
      for source, attack, target, value in string.gfind(arg1, pcl.pSPELLLOGOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        elseif not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          AddData(data, source, "dmg", attack, value)
        end
        return
      end

       -- %s's %s crits %s for %d. (has to be before "%s crits %s for %d.")
      for source, attack, target, value, school in string.gfind(arg1, pcl.pSPELLLOGCRITOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        elseif not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          AddData(data, source, "dmg", attack, value)
        end
        return
      end

      -- %s suffers %d %s damage from %s's %s.
      for target, value, school, source, attack in string.gfind(arg1, pcl.pPERIODICAURADAMAGEOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        elseif not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          AddData(data, source, "dmg", attack, value)
        end
        return
      end

      -- %s hits %s for %d.
      for source, target, value in string.gfind(arg1, pcl.pCOMBATHITOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        elseif not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          AddData(data, source, "dmg", attack, value)
        end
        return
      end

      -- %s crits %s for %d.
      for source, target, value in string.gfind(arg1, pcl.pCOMBATHITCRITOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        elseif not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          AddData(data, source, "dmg", attack, value)
        end
        return
      end

      -- %s hits %s for %d %s damage.
      for source, target, school, value in string.gfind(arg1, pcl.pCOMBATHITSCHOOLOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        elseif not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          AddData(data, source, "dmg", attack, value)
        end
        return
      end

      -- %s crits %s for %d %s damage.
      for source, target, school, value in string.gfind(arg1, pcl.pCOMBATHITCRITSCHOOLOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: "..attack, nil)
        elseif not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          AddData(data, source, "dmg", attack, value)
        end
        return
      end

      -- %s reflects %d %s damage to %s.
      for source, value, school, target in string.gfind(arg1, pcl.pDAMAGESHIELDOTHEROTHER) do
        if source == pet_name then
          BroadcastValue(value, "Pet: Reflect", nil)
        elseif not users[source] then -- if player does not use Kikimeter, add values from own combat log to data
          AddData(data, source, "dmg", "Reflect", value)
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

local function TextLayout(parent, text, align, pos_h, pos_v)
  text:SetFont(STANDARD_TEXT_FONT, config.font_size, "THINOUTLINE")
  text:SetFontObject(GameFontWhite)
  text:ClearAllPoints()
  text:SetPoint(align, parent, align, pos_h, pos_v)
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
  TextLayout(window, window.text_left, "BOTTOMLEFT", 0, 2)
  window.text_left:SetText("damage done")
  window.text_left:Show()

  window.text_center = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(window, window.text_center, "BOTTOM", 0, 2)
  window.text_center:SetText("effective healing")
  window.text_center:Show()

  window.text_right = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(window, window.text_right, "BOTTOMRIGHT", 0, 2)
  window.text_right:SetText("over healing")
  window.text_right:Show()
end

local function CreateBar(parent, idx, col)
  parent.bars[idx] = CreateFrame("StatusBar", nil, parent)
  BarLayout(parent, parent.bars[idx], idx, col)
  
  parent.bars[idx].text_left = parent.bars[idx]:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(parent.bars[idx], parent.bars[idx].text_left, "LEFT",0,0)

  parent.bars[idx].text_right = parent.bars[idx]:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(parent.bars[idx], parent.bars[idx].text_right, "RIGHT",0,0)
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
  sub_type:ClearAllPoints()
  sub_type:SetPoint("TOPLEFT", parent, "TOPLEFT", pos_h, 0)
  sub_type:SetWidth(config.width)
  sub_type:SetHeight(config.sub_height)
  sub_type:EnableMouseWheel(true)
end

local function ButtonLayout(parent, btn, tooltip_txt, pos_btn, pos_parent, pos_v)
  btn:ClearAllPoints()
  btn:SetPoint(pos_btn, parent, pos_parent, 0, pos_v)
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
  window.sub[idx_f].dmg:SetScript("OnMouseWheel", function()
    if getArLength(data[idx_f].dmg._ranking) > 0 then
      -- scrolling from 0 to player_num - 1, so that at least 1 player is always shown
      local max_scroll = getArLength(data[idx_f].dmg._ranking) - 1
      data[idx_f].dmg._scroll = math.max(math.min(data[idx_f].dmg._scroll-arg1, max_scroll),0)
      UpdateBars(window.sub[idx_f].dmg.bars, data[idx_f].dmg)
    end
  end)

  window.sub[idx_f].eheal = CreateFrame("Frame", nil, window.sub[idx_f])
  SubTypeLayout(window.sub[idx_f], window.sub[idx_f].eheal, data[idx_f].eheal, config.width + config.spacing, 2)
  window.sub[idx_f].eheal:SetScript("OnMouseWheel", function()
    if getArLength(data[idx_f].eheal._ranking) > 0 then
      -- scrolling from 0 to player_num - 1, so that at least 1 player is always shown
      local max_scroll = getArLength(data[idx_f].eheal._ranking) - 1
      data[idx_f].eheal._scroll = math.max(math.min(data[idx_f].eheal._scroll-arg1, max_scroll),0)
      UpdateBars(window.sub[idx_f].eheal.bars, data[idx_f].eheal)
    end
  end)

  window.sub[idx_f].oheal = CreateFrame("Frame", nil, window.sub[idx_f])
  SubTypeLayout(window.sub[idx_f], window.sub[idx_f].oheal, data[idx_f].oheal, 2*config.width + 2*config.spacing, 3)
  window.sub[idx_f].oheal:SetScript("OnMouseWheel", function()
    if getArLength(data[idx_f].oheal._ranking) > 0 then
      -- scrolling from 0 to player_num - 1, so that at least 1 player is always shown
      local max_scroll = getArLength(data[idx_f].oheal._ranking) - 1
      data[idx_f].oheal._scroll = math.max(math.min(data[idx_f].oheal._scroll-arg1, max_scroll),0)
      UpdateBars(window.sub[idx_f].oheal.bars, data[idx_f].oheal)
    end
  end)

  window.sub[idx_f].btnReset = CreateFrame("Button", nil, window.sub[idx_f])
  ButtonLayout(window.sub[idx_f], window.sub[idx_f].btnReset, "Reset", "TOPRIGHT", "TOPLEFT", 0)
  window.sub[idx_f].btnReset:SetScript("OnClick", function()
    DEFAULT_CHAT_FRAME:AddMessage("KikiMeter "..idx_f.." has been reset.")
    InitData(data, idx_f, idx_f)
    UpdateBars(window.sub[idx_f].dmg.bars, data[idx_f].dmg)
    UpdateBars(window.sub[idx_f].eheal.bars, data[idx_f].eheal)
    UpdateBars(window.sub[idx_f].oheal.bars, data[idx_f].oheal)
  end)
  window.sub[idx_f].btnReset.text = window:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  TextLayout(window.sub[idx_f].btnReset, window.sub[idx_f].btnReset.text, "LEFT", 0, 0)
  window.sub[idx_f].btnReset.text:SetText("R")
  window.sub[idx_f].btnReset.text:Show()

  window.sub[idx].btnPause = CreateFrame("Button", nil, window.sub[idx])
  ButtonLayout(window.sub[idx], window.sub[idx].btnPause, "Pause", "TOPRIGHT", "TOPLEFT", -config.btn_size-config.spacing)
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
  TextLayout(window.sub[idx_f].btnPause, window.sub[idx_f].btnPause.text, "LEFT", 0, 0)
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

window:RegisterEvent("CHAT_MSG_ADDON")
window:SetScript("OnEvent", function()
  -- arg1: Prefix (KMkm_id_dmg_attack
      -- KMkm_id_eheal_attack
      -- KMkm_id_oheal_attack)
  -- arg2: Message (number)
  -- arg3: distribution type (RAID)
  -- arg4: sender (Kikidora)
  local pattern = "KM"..km_id.."_(.+)_".."(.+)"
  
  for kind, attack in string.gfind(arg1, pattern) do
    AddData(data, arg4, kind, attack, arg2)
  end
end)

-- hide all windows
local btnHide = {}
btnHide = CreateFrame("Button")
ButtonLayout(window, btnHide, "Hide/Unhide", "BOTTOMRIGHT", "TOPRIGHT", 0)
btnHide:SetWidth(41)
btnHide:SetBackdropColor(0, 0, 0, 1)
btnHide.text = btnHide:CreateFontString("Status", "OVERLAY", "GameFontNormal")
TextLayout(btnHide, btnHide.text, "LEFT", 0, 0)
btnHide.text:SetText("Kikimeter")
btnHide.text:Show()
btnHide:SetScript("OnClick", function()
    if not gui_hidden then
      window:Hide()
      gui_hidden = true
    else
      window:Show()
      gui_hidden = false
    end
end)

-- ################
-- # REFRESH BARS #
-- ################

-- for better performance, call UpdateBars only each config.refresh_time seconds
-- and calculate only one table (dmg, eheal or oheal) at a time
window:SetScript("OnUpdate", function()
  if not window.clock then window.clock = GetTime() end
  if not window.cycle then window.cycle = 0 end
  if GetTime() >= window.clock + config.refresh_time then
    
    for idx=1,config.subs do
      if not data[idx]._paused then

        if window.cycle == 0 then
          data[idx].dmg._ranking = GetRank(data[idx].dmg._players) -- update rankings
          for _, player_name in pairs(data[idx].dmg._ranking) do
            data[idx].dmg._players[player_name]._ranking = GetRankAttack(data[idx].dmg._players[player_name]._attacks)
          end
          UpdateBars(window.sub[idx].dmg.bars, data[idx].dmg)
          
        elseif window.cycle == 1 then
          data[idx].eheal._ranking = GetRank(data[idx].eheal._players) -- update rankings
          for _, player_name in pairs(data[idx].eheal._ranking) do
            data[idx].eheal._players[player_name]._ranking = GetRankAttack(data[idx].eheal._players[player_name]._attacks)
          end
          UpdateBars(window.sub[idx].eheal.bars, data[idx].eheal)
          
        elseif window.cycle == 2 then
          data[idx].oheal._ranking = GetRank(data[idx].oheal._players) -- update rankings
          for _, player_name in pairs(data[idx].oheal._ranking) do
            data[idx].oheal._players[player_name]._ranking = GetRankAttack(data[idx].oheal._players[player_name]._attacks)
          end
          UpdateBars(window.sub[idx].oheal.bars, data[idx].oheal)
        end
      end
    end
    if window.cycle == 3 then
      SendAddonMessage("KM"..km_id.."_user_nil", 0, "RAID") -- send who is using Kikimeter (player_name is sender)
    end

    window.clock = GetTime()
    window.cycle = math.mod(window.cycle + 1, 4)
  end
end)


-- ############
-- # TESTDATA #
-- ############

-- local test_sender = CreateFrame("Frame")
-- test_sender:SetScript("OnUpdate", function()
--   if not test_sender.clock then test_sender.clock = GetTime() end
--   if GetTime() >= test_sender.clock + 0.1 then
--     BroadcastValue(100, "Poop Attack", nil)
--     BroadcastValue(50, "Poop Heal", 25)

--     for idx=1,config.subs do
--       AddData(data[idx].dmg, "Chucknorris", "Auto Hit", 50)
--       AddData(data[idx].dmg, "Stevenseagul", "Auto Hit", 10)
--       AddData(data[idx].dmg, "Jackiechan", "Auto Hit", 30)
--       AddData(data[idx].dmg, "Vandamme", "Auto Hit", 20)
--       AddData(data[idx].dmg, "Santa", "Auto Hit", 20)
--       AddData(data[idx].dmg, "Brucelee", "Auto Hit", 40)
    
--       AddData(data[idx].eheal, "Chucknorris", "Auto Hit", 50)
--       AddData(data[idx].eheal, "Stevenseagul", "Auto Hit", 10)
--       AddData(data[idx].eheal, "Jackiechan", "Auto Hit", 30)
--       AddData(data[idx].eheal, "Vandamme", "Auto Hit", 20)
--       AddData(data[idx].eheal, "Santa", "Auto Hit", 20)
--       AddData(data[idx].eheal, "Brucelee", "Auto Hit", 40)
    
--       AddData(data[idx].oheal, "Chucknorris", "Auto Hit", 50)
--       AddData(data[idx].oheal, "Stevenseagul", "Auto Hit", 10)
--       AddData(data[idx].oheal, "Jackiechan", "Auto Hit", 30)
--       AddData(data[idx].oheal, "Vandamme", "Auto Hit", 20)
--       AddData(data[idx].oheal, "Santa", "Auto Hit", 20)
--       AddData(data[idx].oheal, "Brucelee", "Auto Hit", 40)
--     end

--     test_sender.clock = GetTime()
--   end
-- end)
