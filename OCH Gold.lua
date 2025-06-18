-- Imports
import("System.Numerics")

-- Constants
local OCCULT_CRESCENT = 1252
local PHANTOM_VILLAGE = 1278
local INSTANCE_ENTRY_NPC = "Jeffroy"
local ENTRY_NPC_POS = Vector3(-77.958374, 5, 15.396423)
local REENTER_DELAY = 10
local GOLD_DUMP_LIMIT = 9500
local gold = Inventory.GetItemCount(45044)
local ciphers = Inventory.GetItemCount(47739)

-- Shop Config
local VENDOR_NAME = "Expedition Antiquarian"
local VENDOR_POS = Vector3(833.83, 72.73, -719.51)
local BaseAetheryte = Vector3(830.75, 72.98, -695.98)
local ShopItems = {
    { itemName = "Aetherspun Gold", menuIndex = 3, itemIndex = 5, price = 1600 },
}
local CipherStore = {
    { itemName = "Sanguine Cipher", menuIndex = 6, menuIndex2 = 1, itemIndex = 0, price = 960 },
}
local ciphersWanted = 3

--Visland Config
local VISLAND_ROUTE = "Panthers"

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

local function TurnOnRoute()
    if not goldFarming then
        goldFarming = true
        yield("/visland " .. VISLAND_ROUTE)
        yield("/rsr auto")
    end
end

local function TurnOffRoute()
    
    if goldFarming then
        goldFarming = false
        IPC.visland.StopRoute()
        
    end
    if IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() then
        yield("/vnav stop")
    end
    if IPC.Lifestream.IsBusy() then
        yield("/li stop")
    end
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
goldFarming = false
function CharacterState.ready()
    if Svc.Condition[CharacterCondition.betweenAreas] then
        Sleep(5)
    end

    local inInstance = Svc.Condition[CharacterCondition.boundByDuty34] and Svc.ClientState.TerritoryType == OCCULT_CRESCENT
    if not inInstance and Svc.ClientState.TerritoryType ~= PHANTOM_VILLAGE then
        State = CharacterState.zoneIn
    elseif not inInstance and Svc.ClientState.TerritoryType == PHANTOM_VILLAGE then
        State = CharacterState.reenterInstance
    elseif gold >= GOLD_DUMP_LIMIT then
        State = CharacterState.dumpGold
    elseif not goldFarming then
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
        LogInfo("[OCHHelper] Already in Phantom Village")
        if Vector3.Distance(Entity.Player.Position, ENTRY_NPC_POS) >= 7 then
            IPC.vnavmesh.PathfindAndMoveTo(ENTRY_NPC_POS, false)
        elseif PathfindInProgress() or PathIsRunning() then
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
        State = CharacterState.ready
    else
        yield("/echo [OCM] Dialog options did not appear.")
        Sleep(5)
    end
end

function CharacterState.dumpGold()

    if gold < GOLD_DUMP_LIMIT then
    yield("/echo [OCM] Gold below threshold, returning to ready state.")
    State = CharacterState.ready
    return
    end

    TurnOffRoute()

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
    if ciphers < ciphersWanted then
        if yesnoAddon and yesnoAddon.Ready then
            yield("/callback SelectYesno true 0")
            State = CharacterState.ready
        elseif shopAddon and shopAddon.Ready then
            local ciphersNeeded = ciphersWanted - ciphers
            local ciphersToBuy = math.ceil(ciphersNeeded / ShopItems[2].price)
            if ciphersToBuy <= 0 then
                yield("/echo [OCM] Already have desired number of ciphers.")
                State = CharacterState.ready
                return
            end
            yield("/echo [OCM] Purchasing " .. ciphersToBuy .. " " .. CipherStore[1].itemName)
            yield("/callback ShopExchangeCurrency true 0 " .. CipherStore[1].itemIndex .. " " .. ciphersToBuy .. " 0")
        elseif iconStringAddon and iconStringAddon.Ready then
            yield("/callback SelectIconString true " .. CipherStore[1].menuIndex)
            State = CharacterState.ready 
        elseif selectStringAddon and selectStringAddon.Ready then
            yield("/callback SelectString true " .. CipherStore[1].menuIndex2)
        end

        yield("/interact")
        Sleep(1)

        State = CharacterState.ready

    end

    --Buy Aetherspun Gold
    if yesnoAddon and yesnoAddon.Ready then
        yield("/callback SelectYesno true 0")
        State = CharacterState.ready
    elseif shopAddon and shopAddon.Ready then
        local qty = math.floor(gold / ShopItems[1].price)
        yield("/echo [OCM] Purchasing " .. qty .. " " .. ShopItems[1].itemName)
        yield("/callback ShopExchangeCurrency true 0 " .. ShopItems[1].itemIndex .. " " .. qty .. " 0")
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
    yield("/echo [OCM] Instance loaded. Enabling rotation and OCH...")
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