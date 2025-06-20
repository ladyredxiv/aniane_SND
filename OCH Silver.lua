--[[SND Metadata]]
author: Aniane
version: 1.0.24
description: Re-enter the Occult Crescent when you're booted, and spend your silver coins!
Caveat: THIS ONLY WORKS WITH RSR!! You will need to disable the following options under Auto -> AutoSwitch:
  -> Auto turn off when dead in PvE
  -> Auto turn off RSR when combat is over for more than:

Auto turn off in PvE being off means you will get right back to it when you're raised. YMMV with raisers in the area,
so you may de-level closer to the end of your instance timer. Don't worry. You'll re-level quickly on re-entry.
plugin_dependencies: vnavmesh, RotationSolver, BOCCHI
--[[End Metadata]]

--User Configurable Options
local spendSilver = true -- Set to false if you want to disable the silver spending functionality

--[[
    DO NOT TOUCH ANYTHING BELOW THIS UNLESS YOU KNOW WHAT YOU'RE DOING.
    THIS IS A SCRIPT FOR THE OCCULT CRESCENT AND IS NOT MEANT TO BE MODIFIED UNLESS YOU ARE FAMILIAR WITH LUA AND THE SND API.
    IF YOU DO NOT UNDERSTAND THE IMPLICATIONS OF CHANGING THESE VALUES, DO NOT MODIFY THEM.
  ]]

-- Imports
import("System.Numerics")

-- Constants
local OCCULT_CRESCENT = 1252
local PHANTOM_VILLAGE = 1278
local INSTANCE_ENTRY_NPC = "Jeffroy"
local ENTRY_NPC_POS = Vector3(-77.958374, 5, 15.396423)
local REENTER_DELAY = 10
local SILVER_DUMP_LIMIT = 1200 --Currently on a testing value, adjust as needed

--Currency variables
local silverCount = Inventory.GetItemCount(45043)
local cipherCount = Inventory.GetItemCount(47739)

-- Shop Config
local VENDOR_NAME = "Expedition Antiquarian"
local VENDOR_POS = Vector3(833.83, 72.73, -719.51)
local BaseAetheryte = Vector3(830.75, 72.98, -695.98)
local ShopItems = {
    { itemName = "Aetherspun Silver", menuIndex = 1, itemIndex = 5, price = 1200 },
}
local CipherStore = {
    { itemName = "Sanguine Cipher", menuIndex = 6, menuIndex2 = 0, itemIndex = 0, price = 600 },
}
local ciphersWanted = 3

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

local function TurnOnOCH()
    Dalamud.Log("[OCM] Turning on OCH...")
    if not IllegalMode then
        IllegalMode = true
        yield("/ochillegal on")
        yield("/rsr manual")
    end
end

local function TurnOffOCH()
    Dalamud.Log("[OCM] Turning off OCH...")
    if IllegalMode then
        IllegalMode = false
        yield("/ochillegal off")
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

-- State Implementations
IllegalMode = false
function CharacterState.ready()
    Dalamud.Log("[OCM] Checking conditions for state change...")
    while Svc.Condition[CharacterCondition.betweenAreas] do
        Sleep(0.1)
    end

    local inInstance = Svc.Condition[CharacterCondition.boundByDuty34] and Svc.ClientState.TerritoryType == OCCULT_CRESCENT
    local silverCount = Inventory.GetItemCount(45043)
    if not inInstance and Svc.ClientState.TerritoryType ~= PHANTOM_VILLAGE then
        State = CharacterState.zoneIn
        Dalamud.Log("[OCM] State changed to zoneIn")
    elseif not inInstance and Svc.ClientState.TerritoryType == PHANTOM_VILLAGE then
        State = CharacterState.reenterInstance
        Dalamud.Log("[OCM] State changed to reenterInstance")
    elseif spendSilver and silverCount >= SILVER_DUMP_LIMIT then
        Dalamud.Log("[OCM] State changed to dumpSilver")
        State = CharacterState.dumpSilver
    elseif not IllegalMode then
        Dalamud.Log("[OCM] State changed to ready")
        TurnOnOCH()
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
            Sleep(1)
        until not IPC.Lifestream.IsBusy()
    elseif Svc.ClientState.TerritoryType == OCCULT_CRESCENT then
        if Player.Available then
            Talked = false
            TurnOnOCH()
        end
    end
end

function CharacterState.reenterInstance()
    local instanceEntryAddon = Addons.GetAddon("ContentsFinderConfirm")
    yield("/echo [OCM] Detected exit from duty. Waiting " .. REENTER_DELAY .. " seconds before re-entry...")
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
        Sleep(0.5)
        yield("/callback SelectString true 0")
        Sleep(0.5)

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
        TurnOnOCH()
        State = CharacterState.ready
    else
        yield("/echo [OCM] Dialog options did not appear.")
        Sleep(5)
    end
end

function CharacterState.dumpSilver()
    local silverCount = Inventory.GetItemCount(45043)
    local cipherCount = Inventory.GetItemCount(47739)
    if silverCount < SILVER_DUMP_LIMIT then
        yield("/echo [OCM] Silver below threshold, returning to ready state.")
        State = CharacterState.ready
        return
    end

    TurnOffOCH()

    local shopAddon = Addons.GetAddon("ShopExchangeCurrency")
    local yesnoAddon = Addons.GetAddon("SelectYesno")
    local iconStringAddon = Addons.GetAddon("SelectIconString")
    local selectStringAddon = Addons.GetAddon("SelectString")
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

    -- Check if we have enough ciphers
    if cipherCount < ciphersWanted then
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
        elseif shopAddon and shopAddon.Ready then
            local ciphersNeeded = ciphersWanted - cipherCount
            local ciphersToBuy = math.ceil(ciphersNeeded / CipherStore[1].price)
            if ciphersToBuy <= 0 then
                yield("/echo [OCM] Already have desired number of ciphers.")
                State = CharacterState.ready
                return
            end
            yield("/echo [OCM] Purchasing " .. ciphersToBuy .. " " .. CipherStore[1].itemName)
            yield("/callback ShopExchangeCurrency true 0 " .. CipherStore[1].itemIndex .. " " .. ciphersToBuy .. " 0")
            Sleep(1)
            yield("/echo [OCM] Buying ciphers complete.")
            yield("/callback ShopExchangeCurrency true -1")
            State = CharacterState.ready
        elseif iconStringAddon and iconStringAddon.Ready then
            yield("/callback SelectIconString true " .. CipherStore[1].menuIndex)
            State = CharacterState.ready
        elseif selectStringAddon and selectStringAddon.Ready then
            yield("/callback SelectString true " .. CipherStore[1].menuIndex2)
        end

        yield("/interact")
        Sleep(1)

        State = CharacterState.ready
        return
    end

    --Buy Aetherspun Silver
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
        if silverCount < SILVER_DUMP_LIMIT then
            yield("/echo [OCM] Silver below threshold, returning to ready state.")
            State = CharacterState.ready
            return
        end
        local qty = math.floor(silverCount / ShopItems[1].price)
        yield("/echo [OCM] Purchasing " .. qty .. " " .. ShopItems[1].itemName)
        yield("/callback ShopExchangeCurrency true 0 " .. ShopItems[1].itemIndex .. " " .. qty .. " 0")
        State = CharacterState.ready
        return
    elseif iconStringAddon and iconStringAddon.Ready then
        yield("/callback SelectIconString true " .. ShopItems[1].menuIndex)
        State = CharacterState.ready
        return
    end

    yield("/interact")
    Sleep(1)

    State = CharacterState.ready
end

-- Startup
State = CharacterState.ready

-- Main loop
while true do
    while Svc.Condition[CharacterCondition.betweenAreas] do
        Sleep(1)
    end
    State()
    Sleep(1)
end
