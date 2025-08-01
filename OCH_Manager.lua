--[=====[
[[SND Metadata]]
author: Aniane
version: 1.0.0
description: >-
  Run silver farming until you have 15 Aetherspun Silver, then switch to gold until you have 15 Aetherial Fixative. 

  Stops entirely once both sets of items are at 15. 

  Requires OCH_Silver and OCH_Gold. Configs must match across all three scripts for the Aetherspun Silver and Aetherial Fixative amounts.


  Credit to @baanderson40 for the idea!
configs:
  Aetherspun Silver Buy Amount:
    default: 15
    description: Max is the number needed to upgrade ALL sets to +1. Default is 15 minimum for 1 set.
    type: int
    min: 1
    max: 105
    required: true
  Aetherial Fixative Buy Amount:
    type: int
    default: 15
    description: Max is the number needed to upgrade ALL sets to +1. Default is 15 minimum for 1 set.
    min: 1
    max: 105
    required: true
[[End Metadata]]
--]=====]
local lastScript = nil
local aetherSilverBuyAmount = Config.Get("Aetherspun Silver Buy Amount") or 15
local aetherFixativeBuyAmount = Config.Get("Aetherial Fixative Buy Amount") or 15

local function ShouldUseGold()
    local aetherSilverCount = Inventory.GetItemCount(47864)
    return aetherSilverCount and aetherSilverCount >= aetherSilverBuyAmount
end

local function ShouldStop()
    --Stop if you have 15 or more of each item
    local aetherSilverCount = Inventory.GetItemCount(47864)
    local fixativeCount = Inventory.GetItemCount(47865)
    if aetherSilverCount and fixativeCount then
        return aetherSilverCount >= aetherSilverBuyAmount and fixativeCount >= aetherFixativeBuyAmount
    end
    return false
end

local function RunGoldScript()
    yield("/echo [OCM] Switching to OCH Gold script...")
    --yield("/echo [OCM] About to stop...")
    yield("/snd stop OCH_Silver")
    yield("/wait 5")
    if Svc.Condition[34] then
        InstancedContent.LeaveCurrentContent()
        yield("/wait 5")
    end
    --yield("/echo [OCM] About to run...")
    yield("/snd run OCH_Gold")
    yield("/echo [OCM] OCH Gold script is now running.")
end

local function RunSilverScript()
    yield("/echo [OCM] Switching to OCH Silver script...")
    --yield("/echo [OCM] About to stop...")
    yield("/snd stop OCH_Gold")
    yield("/wait 5")
    if Svc.Condition[34] then
        InstancedContent.LeaveCurrentContent()
        yield("/wait 5")
    end
    yield("/echo [OCM] About to run...")
    --yield("/snd run OCH_Silver")
    yield("/echo [OCM] OCH Silver script is now running.")
end

function OnStop()
    yield("/snd stop all")
    yield("/wait 5")
    yield("/echo [OCM] Scripts stopped.")
end

while true do
    if ShouldStop() then
        yield("/echo [OCM] Stop condition met. Stopping all farming.")
        InstancedContent.LeaveCurrentContent()
        yield("/wait 5")
        --yield("/echo [OCM] About to run...")
        yield("/snd stop all")
        break
    end
    local useGold = ShouldUseGold()
    if useGold and lastScript ~= "gold" then
        RunGoldScript()
        lastScript = "gold"
    elseif not useGold and lastScript ~= "silver" then
        RunSilverScript()
        lastScript = "silver"
    end
    yield("/wait 10") -- Check every 10 seconds (adjust as needed)
end
