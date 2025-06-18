--[[SND Metadata]]
author: Aniane
version: 1.0.0
description: Re-enter the Occult Crescent when you're booted, and spend your silver coins!
Caveat: THIS ONLY WORKS WITH RSR!! You will need to disable the following options under Auto -> AutoSwitch:
  -> Auto turn off when dead in PvE
  -> Auto turn off RSR when combat is over for more than:

Auto turn off in PvE being off means you will get right back to it when you're raised. YMMV with raisers in the area, 
so you may de-level closer to the end of your instance timer. Don't worry. You'll re-level quickly on re-entry.
plugin_dependencies: OccultCrescentHelper, vnavmesh, RotationSolver
--[[End Metadata]]

-- Imports
import("System.Numerics")

-- Constants
local INSTANCE_ZONE_ID = 1252
local RETURN_ZONE_ID = 1278
local NPC_NAME = "Jeffroy"
local REENTER_DELAY = 10
local SILVER_DUMP_LIMIT = 4500
local ITEM_TO_PURCHASE = "Aetherspun Silver"

-- Shop Config
local VENDOR_NAME = "Expedition Antiquarian"
local VENDOR_POS = Vector3(833.83, 72.73, -719.51)
local BaseAetheryte = Vector3(830.75, 72.98, -695.98)
local ShopItems = {
    { itemName = "Aetherspun Silver", menuIndex = 1, itemIndex = 5, price = 1200 },
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
    if not IllegalMode then
        IllegalMode = true
        yield("/ochillegal on")
        yield("/rsr manual")
    end
end

local function TurnOffOCH()
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

-- State Implementations
IllegalMode = false
function CharacterState.ready()
    if Svc.Condition[CharacterCondition.betweenAreas] then
        Sleep(5)
    end
    local inInstance = Svc.Condition[CharacterCondition.boundByDuty34] and Svc.ClientState.TerritoryType == INSTANCE_ZONE_ID
    if not inInstance and Svc.ClientState.TerritoryType == RETURN_ZONE_ID then
        State = CharacterState.reenterInstance
    elseif InstancedContent.OccultCrescent.OccultCrescentState.Silver >= SILVER_DUMP_LIMIT then
        State = CharacterState.dumpSilver
    elseif not IllegalMode then
        TurnOnOCH()
    end
end

function CharacterState.reenterInstance()
    yield("/echo [OCM] Detected exit from duty. Waiting " .. REENTER_DELAY .. " seconds before re-entry...")
    Sleep(REENTER_DELAY)

    local npc = Entity.GetEntityByName(NPC_NAME)
    if not npc then
        yield("/echo [OCM] Could not find " .. NPC_NAME .. ". Retrying in 10 seconds...")
        Sleep(10)
        return
    end

    yield("/target " .. NPC_NAME)
    Sleep(1)
    yield("/interact")
    Sleep(1)

    if WaitForAddon("SelectString", 5) then
        Sleep(0.5)
        yield("/callback SelectString true 0")
        Sleep(1)
        yield("/callback SelectString true 0")
        Sleep(3)
        yield("/echo [OCM] Re-entry confirmed.")

        while not Svc.Condition[CharacterCondition.boundByDuty34] do
            Sleep(1)
        end

        yield("/echo [OCM] Instance loaded.")
        State = CharacterState.ready
    else
        yield("/echo [OCM] Dialog options did not appear.")
        Sleep(5)
    end
end

function CharacterState.dumpSilver()
    local silverCount = InstancedContent.OccultCrescent.OccultCrescentState.Silver
    if silverCount < SILVER_DUMP_LIMIT then
        yield("/echo [OCM] Silver below threshold, returning to ready state.")
        State = CharacterState.ready
        return
    end

    TurnOffOCH()
    yield("/echo [OCM] Silver coin threshold met. Attempting to spend...")

    local shopAddon = Addons.GetAddon("ShopExchangeCurrency")
    local yesnoAddon = Addons.GetAddon("SelectYesno")
    local iconStringAddon = Addons.GetAddon("SelectIconString")

    if yesnoAddon and yesnoAddon.Ready then
        yield("/callback SelectYesno true -1")
        State = CharacterState.ready
    elseif shopAddon and shopAddon.Ready then
        local qty = math.floor(silverCount / ShopItems[1].price)
        yield("/echo [OCM] Purchasing " .. qty .. " " .. ShopItems[1].itemName)
        yield("/callback ShopExchangeCurrency true 0 " .. ShopItems[1].itemIndex .. " " .. qty .. " 0")
        State = CharacterState.ready
    elseif iconStringAddon and iconStringAddon.Ready then
        yield("/callback SelectIconString true " .. ShopItems[1].menuIndex)
        State = CharacterState.ready
    else
        local shop = Entity.GetEntityByName(VENDOR_NAME)
        if shop then
            yield("/target " .. VENDOR_NAME)
            if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
                IPC.vnavmesh.PathfindAndMoveTo(VENDOR_POS, false)
            end
        end

        yield("/interact")
        Sleep(1)

        for attempts = 1, 5 do
            shopAddon = Addons.GetAddon("ShopExchangeCurrency")
            yesnoAddon = Addons.GetAddon("SelectYesno")
            iconStringAddon = Addons.GetAddon("SelectIconString")

            if yesnoAddon and yesnoAddon.Ready then
                yield("/callback SelectYesno true 0")
                break
            elseif shopAddon and shopAddon.Ready then
                local qty = math.floor(silverCount / ShopItems[1].price)
                yield("/echo [OCM] Purchasing " .. qty .. " " .. ShopItems[1].itemName)
                yield("/callback ShopExchangeCurrency true 0 " .. ShopItems[1].itemIndex .. " " .. qty .. " 0")
                break
            elseif iconStringAddon and iconStringAddon.Ready then
                yield("/callback SelectIconString true " .. ShopItems[1].menuIndex)
                break
            end

            yield("/echo [OCM] Waiting for shop UI to become ready... (" .. attempts .. "/5)")
            Sleep(1)
        end

        State = CharacterState.ready
    end
end

-- Startup
if Svc.Condition[34] and Svc.ClientState.TerritoryType == INSTANCE_ZONE_ID then
    yield("/echo [OCM] Script started inside the instance. Waiting for full load...")
    Sleep(10)
    while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
        Sleep(1)
    end
    yield("/echo [OCM] Instance loaded. Enabling rotation and OCH...")
    TurnOnOCH()
	yield("/echo [DEBUG] Setting state to Ready...")
	State = CharacterState.ready
end

-- Main loop
while true do
    while Svc.Condition[CharacterCondition.betweenAreas] do
        Sleep(1)
    end
    State()
    Sleep(1)
end
