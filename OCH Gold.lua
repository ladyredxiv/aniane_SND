--[=====[
[[SND Metadata]]
author: Aniane
version: 1.2.0
description: >-
  Re-enter OC and spend your gold. Change the visland route variable to your desired farming route.

  Requirements:
  Phantom Job Command enabled in SimpleTweaks
  Set up your preferred Visland route AND enable looping.
plugin_dependencies:
- vnavmesh
- visland
- SimpleTweaksPlugin
plugins_to_disable:
- YesAlready
configs:
    Rotation Provider Key:
        default: rsr
        description: The rotation provider to use. Options are 'rsr' or 'wrath'.
        type: string
        required: true
    Visland Route:
        type: string
        default: "Panthers"
        description: The name of the Visland route to use for farming.
        required: true
    Spend Gold?:
        type: boolean
        default: true
        description: Spend your silver coins automatically.
        required: true
    Gold Cap:
        type: number
        default: 9500
        description: The amount of gold on hand to initiate spending it.
        required: true
    Warrior Gearset Name:
        type: string
        default: "Warrior"
        description: The name of the gearset to use for farming. Must be on Warrior!
        required: true
    Phantom Job Command:
        type: string
        default: "phantomjob"
        description: The command to use for changing jobs.
        required: true

[[End Metadata]]
--]=====]

--[[
    DO NOT TOUCH ANYTHING BELOW THIS UNLESS YOU KNOW WHAT YOU'RE DOING.
    THIS IS A SCRIPT FOR THE OCCULT CRESCENT AND IS NOT MEANT TO BE MODIFIED UNLESS YOU ARE FAMILIAR WITH LUA AND THE SND API.
    IF YOU DO NOT UNDERSTAND THE IMPLICATIONS OF CHANGING THESE VALUES, DO NOT MODIFY THEM.
  ]]

-- Imports
import("System.Numerics")

--Config variables
local VISLAND_ROUTE = Config.Get("Visland Route")
local WAR_GEARSET_NAME =  Config.Get("Warrior Gearset Name")
local ST_PHANTOMJOB_COMMAND =  Config.Get("Phantom Job Command")
local spendGold = Config.Get("Spend Gold?")
local GOLD_DUMP_LIMIT = Config.Get("Gold Cap")
local RotationProviderKey = string.lower(Config.Get("Rotation Provider Key"))
local RotationProvider = {}
if RotationProviderKey ~= "rsr" or RotationProviderKey ~= "wrath" then
 error("Value is incorrect, please use 'rsr' or 'wrath'.")
end

-- Constants
local OCCULT_CRESCENT = 1252
local PHANTOM_VILLAGE = 1278
local INSTANCE_ENTRY_NPC = "Jeffroy"
local ENTRY_NPC_POS = Vector3(-77.958374, 5, 15.396423)
local REENTER_DELAY = 10
local gold = Inventory.GetItemCount(45044)

-- Shop Config
local VENDOR_NAME = "Expedition Antiquarian"
local VENDOR_POS = Vector3(833.83, 72.73, -719.51)
local BaseAetheryte = Vector3(830.75, 72.98, -695.98)
local ShopItems = {
    { itemName = "Aetherial Fixative", menuIndex = 3, itemIndex = 5, price = 1600 },
}

-- Character Conditions
CharacterCondition = {
    dead = 2,
    mounted = 4,
    inCombat = 26,
    casting = 27,
    occupiedInEvent = 31,
    occupiedInQuestEvent = 32,
    occupied = 33,
    boundByDuty34 = 34,
    occupiedMateriaExtractionAndRepair = 39,
    betweenAreas = 45,
    jumping48 = 48,
    jumping61 = 61,
    occupiedSummoningBell = 50,
    betweenAreasForDuty = 51,
    boundByDuty56 = 56,
    mounting57 = 57,
    mounting64 = 64,
    beingMoved = 70,
    flying = 77
}

-- State Machine
local State = nil
local CharacterState = {}
local goldFarming = false

-- Helper Functions
local function Sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

local function WaitForAddon(addonName, timeout)
    local elapsed = 0
    while (not Addons.GetAddon(addonName) or not Addons.GetAddon(addonName).Ready) and elapsed < timeout do
        Sleep(0.5)
        elapsed = elapsed + 0.5
    end
    return Addons.GetAddon(addonName) and Addons.GetAddon(addonName).Ready
end

function RotationProvider:on()
    if RotationProviderKey == "rsr" then
        yield("/rsr auto")
        yield("/rotation Settings AutoOffWhenDead False")
        yield("/rotation Settings AutoOffAfterCombat False")
    elseif RotationProviderKey == "wrath" then
        yield("/wrath auto on")
    end
end

function RotationProvider:off()
    if RotationProviderKey == "rsr" then
        yield("/rsr off")
        yield("/rotation Settings AutoOffWhenDead True")
        yield("/rotation Settings AutoOffAfterCombat True")
    elseif RotationProviderKey == "wrath" then
        yield("/wrath auto off")
    end
end

local function TurnOnRoute()
    if not goldFarming then
        goldFarming = true
        Sleep(5) --Safety sleep to ensure instance is fully loaded before changing anything
        yield("/" .. ST_PHANTOMJOB_COMMAND .. " cannoneer")
        Sleep(0.5)
        yield("/gearset change " .. WAR_GEARSET_NAME)
        Sleep(0.5)
        RotationProvider:on()
        Sleep(0.5)
        yield("/visland exec " .. VISLAND_ROUTE)
    end
end

local function TurnOffRoute()  
    if goldFarming then
        goldFarming = false
        yield("/visland stop")
        Sleep(0.5)
        RotationProvider:off()
    end
    if IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() then
        yield("/vnav stop")
    end
    if IPC.Lifestream.IsBusy() then
        yield("/li stop")
    end
end

local function ReturnToBase()
    yield("/gaction Return")
    repeat
        Sleep(1)
    until not Svc.Condition[CharacterCondition.casting]
    repeat
        Sleep(1)
    until not Svc.Condition[CharacterCondition.betweenAreas]
end

function OnStop()
    Dalamud.LogDebug("[OCM] Stopping OCH Gold script...")
    Dalamud.LogDebug("[OCM] Turning off Visland.")
    yield("/visland stop")
    yield("/wait 0.1")

    Dalamud.LogDebug("[OCM] Stopping pathfinding...")
    yield("/vnav stop")
    yield("/wait 0.1")
    
    Dalamud.LogDebug("[OCM] Stopping Lifestream...")
    yield("/li stop")
    yield("/wait 0.1")
    
    Dalamud.LogDebug("[OCM] Turning off RSR.")
    if RotationProviderKey == "rsr" then
        yield("/rsr off")
        yield("/rotation Settings AutoOffWhenDead True")
        yield("/rotation Settings AutoOffAfterCombat True")
    elseif RotationProviderKey == "wrath" then
        yield("/wrath auto off")
    end
    yield("/echo [OCM] Script stopped.")
end

-- State Implementations
function CharacterState.ready()
    while Svc.Condition[CharacterCondition.betweenAreas] do
        Sleep(0.1)
    end

    local shopAddon = Addons.GetAddon("ShopExchangeCurrency")
    local gold = Inventory.GetItemCount(45044)
    --If for some reason the shop addon is visible, close it
    if gold < tonumber(GOLD_DUMP_LIMIT) and shopAddon and shopAddon.Ready then
        yield("/callback ShopExchangeCurrency true -1")
    end

    local inInstance = Svc.Condition[CharacterCondition.boundByDuty34] and Svc.ClientState.TerritoryType == OCCULT_CRESCENT
    if not inInstance and Svc.ClientState.TerritoryType ~= PHANTOM_VILLAGE then
        Dalamud.LogDebug("[OCM] State changed to zoneIn")
        State = CharacterState.zoneIn
    elseif not inInstance and Svc.ClientState.TerritoryType == PHANTOM_VILLAGE then
        Dalamud.LogDebug("[OCM] State changed to reenterInstance")
        State = CharacterState.reenterInstance
    elseif spendGold and gold >= tonumber(GOLD_DUMP_LIMIT) then
        Dalamud.LogDebug("[OCM] State changed to dumpGold")
        State = CharacterState.dumpGold
    elseif not goldFarming then
        Dalamud.LogDebug("[OCM] State changed to ready")
        TurnOnRoute()
    end
end

function CharacterState.zoneIn()
    local instanceEntryAddon = Addons.GetAddon("ContentsFinderConfirm")
    local SelectString = Addons.GetAddon("SelectString")
    local Talked = false
    if Svc.Condition[CharacterCondition.betweenAreas] then
        Sleep(3)
    elseif Svc.ClientState.TerritoryType == PHANTOM_VILLAGE then
        LogInfo("[OCM] Already in Phantom Village")
        if Vector3.Distance(Entity.Player.Position, ENTRY_NPC_POS) >= 7 then
            IPC.vnavmesh.PathfindAndMoveTo(ENTRY_NPC_POS, false)
        elseif IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.PathIsRunning() then
            yield("/vnav stop")
        elseif Entity.GetEntityByName(INSTANCE_ENTRY_NPC) ~= INSTANCE_ENTRY_NPC then
            yield("/target " .. INSTANCE_ENTRY_NPC)
        elseif instanceEntryAddon and instanceEntryAddon.ready then
            yield("/callback ContentsFinderConfirm true 8")
            yield("/echo [OCM] Re-entry confirmed.")
        elseif SelectString and SelectString.ready then
            yield("/callback SelectString true 0")
        elseif not Talked then
            Talked = true
            yield("/interact")
        end
    elseif Svc.ClientState.TerritoryType ~=OCCULT_CRESCENT then
        yield("/li occult")
        repeat
            yield("/wait 1")
        until not IPC.Lifestream.IsBusy()
    elseif Svc.ClientState.TerritoryType == OCCULT_CRESCENT then
        if Player.Available then
            Talked = false
            TurnOnRoute()
        end
    end
    State = CharacterState.ready
end

function CharacterState.reenterInstance()
    local instanceEntryAddon = Addons.GetAddon("ContentsFinderConfirm")
    local YesAlready = IPC.YesAlready.IsPluginEnabled()
    if YesAlready then
        IPC.YesAlready.PauseBother("ContentsFinderConfirm", 120000) -- Pause YesAlready for 2 minutes to prevent instance entry issues
    end
    
    yield("/echo [OCM] Detected exit from duty. Waiting " .. REENTER_DELAY .. " seconds before re-entry...")
    goldFarming = false
    Sleep(REENTER_DELAY)

    local npc = Entity.GetEntityByName(INSTANCE_ENTRY_NPC)
    if not npc then
        yield("/echo [OCM] Could not find " .. INSTANCE_ENTRY_NPC .. ". Retrying in 10 seconds...")
        Sleep(10)
        return
    end

    yield("/target " .. INSTANCE_ENTRY_NPC)
    Sleep(1)
    yield("/interact")
    Sleep(1)

    if WaitForAddon("SelectString", 5) then
        Sleep(0.5)
        yield("/callback SelectString true 0")
        Sleep(1)
        yield("/callback SelectString true 0")
        Sleep(3)

        while not (instanceEntryAddon and instanceEntryAddon.Ready) do
            Sleep(2)
        end

        if instanceEntryAddon and instanceEntryAddon.Ready then
            yield("/callback ContentsFinderConfirm true 8")
            yield("/echo [OCM] Re-entry confirmed.")
        end

        while not Svc.Condition[CharacterCondition.boundByDuty34] do
            Sleep(1)
        end

        yield("/echo [OCM] Instance loaded.")
        
        Sleep(2.5) --safety sleep on re-entry
        State = CharacterState.ready
    else
        yield("/echo [OCM] Dialog options did not appear.")
        Sleep(5)
    end
end

function CharacterState.dumpGold()
    -- Refresh silver and ciphers count
    local gold = Inventory.GetItemCount(45044)
    goldFarming = false

    if gold < tonumber(GOLD_DUMP_LIMIT) then
        yield("/echo [OCM] Gold below threshold, returning to ready state.")
        yield("/callback ShopExchangeCurrency true -1")
        State = CharacterState.ready
        return
    end

    TurnOffRoute()

    while Svc.Condition[CharacterCondition.inCombat] do
        yield("/echo [OCM] Waiting for combat to end before proceeding.")
        Sleep(1)
    end

    local shopAddon = Addons.GetAddon("ShopExchangeCurrency")
    local yesnoAddon = Addons.GetAddon("SelectYesno")
    local iconStringAddon = Addons.GetAddon("SelectIconString")
    local baseToShop = Vector3.Distance(BaseAetheryte, VENDOR_POS) + 50
    local distanceToShop = Vector3.Distance(Entity.Player.Position, VENDOR_POS)

    if distanceToShop > baseToShop then
        ReturnToBase()
        elseif distanceToShop > 7 then
        yield("/target " .. VENDOR_NAME)
        if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
            IPC.vnavmesh.PathfindAndMoveTo(VENDOR_POS, false)
        end
    end

    --Buy Aetherial Fixative
    if yesnoAddon and yesnoAddon.Ready then
        yield("/callback SelectYesno true 0")
            
        --Wait for the shopAddon to be ready
        while not shopAddon and shopAddon.Ready do
            Sleep(1)
        end

        while shopAddon and shopAddon.Ready do
            yield("/echo [OCM] Buying complete.")
            yield("/callback ShopExchangeCurrency true -1")
            State = CharacterState.ready
            return
        end
        State = CharacterState.ready
        return
    elseif shopAddon and shopAddon.Ready then
        while gold < tonumber(GOLD_DUMP_LIMIT) do
            Dalamud.LogDebug("Gold below threshold, returning to ready state.")
            State = CharacterState.ready
            return
        end
        local qty = math.floor(gold / ShopItems[1].price)
        yield("/echo [OCM] Purchasing " .. qty .. " " .. ShopItems[1].itemName)
        yield("/callback ShopExchangeCurrency true 0 " .. ShopItems[1].itemIndex .. " " .. qty .. " 0")

        State = CharacterState.ready
        return
    elseif iconStringAddon and iconStringAddon.Ready then
        yield("/callback SelectIconString true " .. ShopItems[1].menuIndex)
        State = CharacterState.ready
    end
        yield("/interact")
        Sleep(1)

        State = CharacterState.ready
end

if Svc.Condition[34] and Svc.ClientState.TerritoryType == OCCULT_CRESCENT then
    yield("/echo [OCM] Script started inside the instance. Waiting for full load...")
    Sleep(2)
    while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
        Sleep(1)
    end
    yield("/echo [OCM] Instance loaded. Enabling route...")
    TurnOnRoute()
end

State = CharacterState.ready

-- Main loop
while true do
    while Svc.Condition[CharacterCondition.betweenAreas] do
        Sleep(1)
    end
    State()
    Sleep(1)
end
