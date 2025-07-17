--[=====[
[[SND Metadata]]
author: Aniane
version: 1.3.0
description: Re-enter the Occult Crescent when you're booted, and spend your silver coins! WrathCombo and RSR are supported as rotation providers. Related RSR options (turn off when dead in PvE and such) are handled by the script. You must enter which one you are using in the configs. Requires Phantom Job Command tweak in SimpleTweaks for job leveling.
plugin_dependencies:
- vnavmesh
- BOCCHI
- SimpleTweaksPlugin
configs:
  Use RSR for Rotation:
    default: false
    description: Default rotation is WrathCombo. Check the box to use RSR instead.
    type: boolean
    required: true
  Spend Silver:
    default: true
    description: Spend your silver coins automatically.
    type: boolean
    required: true
  Silver Cap:
    default: 9600
    description: The silver cap to dump at the vendor.
    type: int
    min: 1200
    max: 9600
    required: true
  How many Aetherspun Silver to Buy:
    default: 15
    description: The amount of Aetherspun Silver to buy at the vendor. Maximum amount is the number needed to upgrade ALL sets to +1. Default set to 15 minimum for a single gear set.
    type: int
    min: 1
    max: 105
    required: true
  Phantom Job Command:
    default: phantomjob
    description: The command to use for changing jobs.
    type: string
    required: true
  Level Phantom Jobs:
    default: false
    description: Level your phantom jobs automatically.
    type: boolean
    required: true
  Self Repair:
    default: true
    description: Self-repair automatically. If this is unchecked, it will use the mender.
    type: boolean
    required: true
  Durability Amount:
    default: 5
    description: The durability amount to repair at.
    type: int
    min: 1
    max: 75
    required: true
  Auto Buy Dark Matter:
    default: true
    description: Automatically buy Dark Matter when self-repairing.
    type: boolean
    required: true
  Extract Materia:
    default: false
    description: Extract materia automatically.
    type: boolean
    required: true

[[End Metadata]]
--]=====]

--[[
    DO NOT TOUCH ANYTHING BELOW THIS UNLESS YOU KNOW WHAT YOU'RE DOING. I DO NOT TAKE RESPONSIBILITY 
    FOR ANY ISSUES THAT ARISE FROM CHANGING THIS CODE.
    IF YOU DO NOT UNDERSTAND THE IMPLICATIONS OF CHANGING THESE VALUES, DO NOT MODIFY THEM.
  ]]

-- Imports
import("System.Numerics")

--[[ ===========================
    Section: Variables
=========================== ]]

--Config Variables
local spendSilver = Config.Get("Spend Silver")
local selfRepair = Config.Get("Self Repair")
local durabilityAmount = Config.Get("Durability Amount")
local ShouldAutoBuyDarkMatter = Config.Get("Auto Buy Dark Matter")
local ShouldExtractMateria = Config.Get("Extract Materia")
local SILVER_DUMP_LIMIT = Config.Get("Silver Cap")
local RotationProviderKey = Config.Get("Use RSR for Rotation")
local RotationProvider = {}
local pJobCommand = Config.Get("Phantom Job Command")
local levelUp = Config.Get("Level Phantom Jobs")

-- Constants
local OCCULT_CRESCENT = 1252
local PHANTOM_VILLAGE = 1278
local INSTANCE_ENTRY_NPC = "Jeffroy"
local ENTRY_NPC_POS = Vector3(-77.958374, 5, -15.396423)
local REENTER_DELAY = 10

--Currency variables
local silverCount = Inventory.GetItemCount(45043)

-- Shop Config
local VENDOR_NAME = "Expedition Antiquarian"
local VENDOR_POS = Vector3(833.83, 72.73, -719.51)
local BaseAetheryte = Vector3(830.75, 72.98, -695.98)
local ShopItems = {
    { itemName = "Aetherspun Silver", menuIndex = 1, itemIndex = 5, price = 1200 },
}

--Repair module variables
local MENDER_NAME = "Expedition Supplier"
local MENDER_POS = Vector3(821.47, 72.73, -669.12)

--Leveling module variables
pJobNames = {
    "knight", "berserker", "monk", "ranger", "samurai", "bard",
	"geomancer", "time mage", "cannoneer", "chemist", "oracle", "thief"
}

pJobMaxLevels = {
    knight = 6, berserker = 3, monk = 6, ranger = 6, samurai = 5, bard = 4,
    geomancer = 5, ["time mage"] = 5, cannoneer = 6, chemist = 4, oracle = 5, thief = 6
}
LEVELING = true
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

--[[ ===========================
    Section: Helper Functions
=========================== ]]--

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
    Dalamud.LogDebug("[OCM] Enabling rotation.")
    if RotationProviderKey == true then
        Dalamud.LogDebug("[OCM] Enabling RSR rotation provider.")
        yield("/rsr manual")
        yield("/rotation Settings AutoOffWhenDead False")
        yield("/rotation Settings AutoOffAfterCombat False")
    elseif RotationProviderKey == false then
        Dalamud.LogDebug("[OCM] Enabling Wrath rotation provider.")
        yield("/wrath auto on")
    end
end

function RotationProvider:off()
    if RotationProviderKey == true then
        yield("/rsr off")
        yield("/rotation Settings AutoOffWhenDead True")
        --yield("/rotation Settings AutoOffAfterCombat True")
    elseif RotationProviderKey == false then
        yield("/wrath auto off")
    end
end

local function TurnOnOCH()
    Dalamud.LogDebug("[OCM] Turning on OCH...")
    if not IllegalMode then
        IllegalMode = true
        yield("/bocchillegal on")
        RotationProvider:on()
    end
end

local function TurnOffOCH()
    --Dalamud.LogDebug("[OCM] Turning off OCH...")
    if IllegalMode then
        Dalamud.LogDebug("[OCM] Setting IllegalMode to false.")
        IllegalMode = false
        Dalamud.LogDebug("[OCM] Turning off BOCCHI Illegal Mode.")
        yield("/bocchillegal off")
        return
    end
    if IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() then
        Dalamud.LogDebug("[OCM] Stopping pathfinding...")
        IPC.vnavmesh.Stop()
        return
    end
    if IPC.Lifestream.IsBusy() then
        Dalamud.LogDebug("[OCM] Stopping Lifestream...")
        IPC.Lifestream.Abort()
        return
    end
    Dalamud.LogDebug("[OCM] Turning off rotation.")
    RotationProvider:off()
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

function IndexOf(tbl, val)
    for i, v in ipairs(tbl) do
        if v == val then return i end
    end
    return nil
end

function OnStop()
    Dalamud.LogDebug("[OCM] Stopping OCH Silver script...")
    Dalamud.LogDebug("[OCM] Turning off BOCCHI Illegal Mode.")
    yield("/bocchillegal off")

    Dalamud.LogDebug("[OCM] Stopping pathfinding...")
    IPC.vnavmesh.Stop()
    
    Dalamud.LogDebug("[OCM] Stopping Lifestream...")
    IPC.Lifestream.Abort()
    
    Dalamud.LogDebug("[OCM] Turning off rotation.")
    if RotationProviderKey == true then
        yield("/rsr off")
        yield("/rotation Settings AutoOffWhenDead True")
        --yield("/rotation Settings AutoOffAfterCombat True")
    elseif RotationProviderKey == false then
        yield("/wrath auto off")
    end
    
    yield("/echo [OCM] Script stopped.")
end

local function SwitchToNextUncappedSupportJob()
    local supportLevels = InstancedContent.OccultCrescent.OccultCrescentState.SupportJobLevels
    if supportLevels and supportLevels.Length then

--[[        -- Debug: Print all phantom jobs and their levels
        yield("/echo [OCM] --- Phantom Job Level Debug ---")
        for i = 1, #pJobNames do
            local job = pJobNames[i]
            local level = supportLevels[i]
            yield("/echo [OCM] Job: " .. tostring(job) .. " | Level: " .. tostring(level))
        end
        yield("/echo [OCM] --- End Debug ---")
]]--
    
        for i = 1, #pJobNames do
            local job = pJobNames[i]
            local level = supportLevels[i]
            local maxLevel = pJobMaxLevels[job]
            -- Skip jobs that are not unlocked (level == 0)
            if level > 0 and level < maxLevel then
                yield("/echo Switching to " .. job .. " (" .. tostring(level) .. "/" .. tostring(maxLevel) .. ")")
                yield("/" .. pJobCommand .. " " .. job)
                Dalamud.LogDebug("[OCM] Switching to " .. job .. " (" .. tostring(level) .. "/" .. tostring(maxLevel) .. ")")
                Sleep(1) -- Wait for the command to process
                return
            end
        end
        yield("/echo All of your currently available phantom jobs are capped!")
        LEVELING = false
    else
        yield("/echo Could not retrieve phantom job levels.")
    end
end

function GetCurrentPhantomJob()
    local jobIndex = InstancedContent.OccultCrescent.OccultCrescentState.CurrentSupportJob
    if jobIndex and jobIndex >= 1 and jobIndex <= #pJobNames then
        return pJobNames[jobIndex]
    end
    return nil
end

--[[ ===========================
    Section: Addon Event Functions
=========================== ]]--
--Close shopAddon
function OnAddonEvent_ShopExchangeCurrency_PostSetup_CloseWindow()
    Engines.Native.Run("/callback ShopExchangeCurrency true -1")
end

--Open shopAddon
function OnAddonEvent_ShopExchangeCurrency_PostSetup_OpenWindow()
    Engines.Native.Run("/callback ShopExchangeCurrency true 0")
end

--Purchase item
function OnAddonEvent_ShopExchangeCurrency_PostSetup_ConfirmPurchase()
    Engines.Native.Run("/callback ShopExchangeCurrency true 0 " .. ShopItems[1].itemIndex .. " " .. qty .. " 0")
end

--Select item to buy
function OnAddonEvent_SelectIconString_PostSetup_SelectItem()
    Engines.Native.Run("/callback SelectIconString true " .. ShopItems[1].menuIndex)
end

--Enter instance
function OnAddonEvent_ContentsFinderConfirm_PostSetup_EnterInstance()
    Engines.Native.Run("/callback ContentsFinderConfirm true 8")
end

--SelectString addon event
function OnAddonEvent_SelectString_PostSetup_SelectFirstOption()
    Engines.Native.Run("/callback SelectString true 0")
end

--YesNo addon select Yes
function OnAddonEvent_YesNo_PostSetup_SelectYes()
    Engines.Native.Run("/callback YesNo true 0")
end

--Open repair window
function OnAddonEvent_Repair_PostSetup_OpenWindow()
    Engines.Native.Run("/callback Repair true 0")
end

--Close repair window
function OnAddonEvent_Repair_PostSetup_CloseWindow()
    Engines.Native.Run("/callback Repair true -1")
end

--Buy Dark Matter from Mender
function OnAddonEvent_Shop_PostSetup_BuyDarkMatter()
    Engines.Native.Run("/callback Shop true 0 10 99")
end

--Close Mender shop window
function OnAddonEvent_Shop_PostSetup_CloseWindow()
    Engines.Native.Run("/callback Shop true -1")
end

--Repair at Mender
function OnAddonEvent_SelectIconString_PostSetup_RepairAtVendor()
    Engines.Native.Run("/callback SelectIconString true 1")
end

--Get into the Mender shop
function OnAddonEvent_SelectIconString_PostSetup_OpenMenderShop()
    Engines.Native.Run("/callback SelectIconString true 0")
end

--Extract Materia
function OnAddonEvent_MaterializeDialog_PostSetup_ExtractMateria()
    Engines.Native.Run("/callback MaterializeDialog true 0")
end

--Keep extracting until complete
function OnAddonEvent_Materialize_PostSetup_KeepExtracting()
    Engines.Native.Run("/callback Materialize true 2 0")
end

--Close materialize window
function OnAddonEvent_Materialize_PostSetup_CloseWindow()
    Engines.Native.Run("/callback Materialize true -1")
end

--[[ ===========================
    Section: State Implementations
=========================== ]]--
IllegalMode = false
function CharacterState.ready()
    --Dalamud.LogDebug("[OCM] Checking conditions for state change...")
    while Svc.Condition[CharacterCondition.betweenAreas] do
        Sleep(0.1)
    end

    local inInstance = Svc.Condition[CharacterCondition.boundByDuty34] and Svc.ClientState.TerritoryType == OCCULT_CRESCENT
    local silverCount = Inventory.GetItemCount(45043)
    local itemsToRepair = Inventory.GetItemsInNeedOfRepairs(tonumber(durabilityAmount))
    local needsRepair = false
    local shopAddon = Addons.GetAddon("ShopExchangeCurrency")

    --If for some reason the shop addon is visible, close it
    if silverCount < tonumber(SILVER_DUMP_LIMIT) and shopAddon and shopAddon.Ready then
        OnAddonEvent_ShopExchangeCurrency_PostSetup_CloseWindow()
    end

    if type(itemsToRepair) == "number" then
        needsRepair = itemsToRepair ~= 0
    elseif type(itemsToRepair) == "table" then
        needsRepair = next(itemsToRepair) ~= nil
    end

    if not inInstance and Svc.ClientState.TerritoryType ~= PHANTOM_VILLAGE then
        State = CharacterState.zoneIn
        Dalamud.LogDebug("[OCM] State changed to zoneIn")
    elseif not inInstance and Svc.ClientState.TerritoryType == PHANTOM_VILLAGE then
        State = CharacterState.reenterInstance
        Dalamud.LogDebug("[OCM] State changed to reenterInstance")
    elseif needsRepair then
        Dalamud.LogDebug("[OCM] State changed to repair")
        State = CharacterState.repair
    elseif ShouldExtractMateria and Inventory.GetSpiritbondedItems().Count > 0 then
        Dalamud.LogDebug("[OCM] State changed to extract materia")
        State = CharacterState.materia
    elseif spendSilver and silverCount >= tonumber(SILVER_DUMP_LIMIT) then
        Dalamud.LogDebug("[OCM] State changed to dumpSilver")
        State = CharacterState.dumpSilver
    elseif levelUp and LEVELING then
    Dalamud.LogDebug("[OCM] Checking if current phantom job needs leveling")
    local supportLevels = InstancedContent.OccultCrescent.OccultCrescentState.SupportJobLevels
    local myJob = GetCurrentPhantomJob()
    local myJobIndex = IndexOf(pJobNames, myJob)
    if myJobIndex and supportLevels and supportLevels.Length then
        local level = supportLevels[myJobIndex]
        local maxLevel = pJobMaxLevels[myJob]
        -- If job is not unlocked or is capped, switch jobs
        if (level == 0) or (level and maxLevel and level >= maxLevel) then
            Dalamud.LogDebug("[OCM] State changed to switchPhantomJob")
            State = CharacterState.switchPhantomJob
            return
        end
        -- Only turn on OCH if not already on
        if not IllegalMode then
            Dalamud.LogDebug("[OCM] Enabling OCH for leveling")
            TurnOnOCH()
        end
    end
    elseif not IllegalMode then
        Dalamud.LogDebug("[OCM] State changed to ready")
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
        Dalamud.DebugLog("[OCM] Already in Phantom Village")
        if Vector3.Distance(Entity.Player.Position, ENTRY_NPC_POS) >= 7 then
            IPC.vnavmesh.PathfindAndMoveTo(ENTRY_NPC_POS, false)
        elseif IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.PathIsRunning() then
            IPC.vnavmesh.Stop()
        elseif Entity.GetEntityByName(INSTANCE_ENTRY_NPC) ~= INSTANCE_ENTRY_NPC then
            Entity.GetEntityByName(INSTANCE_ENTRY_NPC):SetAsTarget()
        elseif instanceEntryAddon and instanceEntryAddon.ready then
            OnAddonEvent_ContentsFinderConfirm_PostSetup_EnterInstance()
            yield("/echo [OCM] Re-entry confirmed.")
        elseif SelectString and SelectString.ready then
            OnAddonEvent_SelectString_PostSetup_SelectFirstOption()
        elseif not Talked then
            Talked = true
            Entity.GetEntityByName(INSTANCE_ENTRY_NPC):Interact()
        end
    elseif Svc.ClientState.TerritoryType ~=OCCULT_CRESCENT then
        IPC.Lifestream.ExecuteCommand("occult")
        repeat
            Sleep(1)
        until not IPC.Lifestream.IsBusy()
    elseif Svc.ClientState.TerritoryType == OCCULT_CRESCENT then
        if Player.Available then
            Talked = false
            TurnOnOCH()
        end
    end
    State = CharacterState.ready
end

function CharacterState.reenterInstance()
    local instanceEntryAddon = Addons.GetAddon("ContentsFinderConfirm")
    local YesAlready = IPC.YesAlready.IsPluginEnabled()

    Dalamud.LogDebug("[OCM] Entered reenterInstance state")
    Dalamud.LogDebug("[OCM] Territory: " .. tostring(Svc.ClientState.TerritoryType))
    Dalamud.LogDebug("[OCM] betweenAreas: " .. tostring(Svc.Condition[CharacterCondition.betweenAreas]))

    yield("/echo [OCM] Detected exit from duty. Waiting " .. REENTER_DELAY .. " seconds before re-entry...")
    IllegalMode = false
    Sleep(REENTER_DELAY)

    Dalamud.LogDebug("[OCM] Disabling YesAlready plugin if it is enabled.")
    if YesAlready then
        IPC.YesAlready.PausePlugin(30000) -- Pause YesAlready to prevent instance entry issues
    end

    if Vector3.Distance(Entity.Player.Position, ENTRY_NPC_POS) >= 7 then
        IPC.vnavmesh.PathfindAndMoveTo(ENTRY_NPC_POS, false)
    end

    Dalamud.LogDebug("[OCM] Attempting to find " .. INSTANCE_ENTRY_NPC .. "...")
    local npc = Entity.GetEntityByName(INSTANCE_ENTRY_NPC)
    if not npc then
        yield("/echo [OCM] Could not find " .. INSTANCE_ENTRY_NPC .. ". Retrying in 10 seconds...")
        Sleep(10)
        return
    end

    Dalamud.LogDebug("[OCM] Found " .. INSTANCE_ENTRY_NPC .. ". Interacting...")
    Entity.GetEntityByName(INSTANCE_ENTRY_NPC):SetAsTarget()
    --Sleep(1)
    Entity.GetEntityByName(INSTANCE_ENTRY_NPC):Interact()
    --Sleep(1)

    Dalamud.LogDebug("[OCM] Waiting for SelectString addon to be ready...")
    if WaitForAddon("SelectString", 5) then
        Sleep(0.5)
        OnAddonEvent_SelectString_PostSetup_SelectFirstOption()
        Sleep(0.5)
        OnAddonEvent_SelectString_PostSetup_SelectFirstOption()
        Sleep(0.5)

        Dalamud.LogDebug("[OCM] Waiting for ContentsFinderConfirm addon to be ready...")
        while not (instanceEntryAddon and instanceEntryAddon.Ready) do
            Sleep(2)
        end

        if instanceEntryAddon and instanceEntryAddon.Ready then
            OnAddonEvent_ContentsFinderConfirm_PostSetup_EnterInstance()
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

function CharacterState.dumpSilver()
    local silverCount = Inventory.GetItemCount(45043)
    local itemId = 45043
    local currentCount = Inventory.GetItemCount(itemId)
    local maxDesired = Config.Get("How many Aetherspun Silver to Buy")
    local affordableQty = math.floor(silverCount / ShopItems[1].price)
    local qtyToBuy = math.min(maxDesired - currentCount, affordableQty)

    if qtyToBuy <= 0 then
        yield("/echo [OCM] Already have " .. currentCount .. " " .. ShopItems[1].itemName .. ". No need to buy more.")
        spendSilver = false
        State = CharacterState.ready
        return
    end

    TurnOffOCH()

    local shopAddon = Addons.GetAddon("ShopExchangeCurrency")
    local yesnoAddon = Addons.GetAddon("SelectYesno")
    local iconStringAddon = Addons.GetAddon("SelectIconString")
    local baseToShop = Vector3.Distance(BaseAetheryte, VENDOR_POS) + 50
    local distanceToShop = Vector3.Distance(Entity.Player.Position, VENDOR_POS)

    if distanceToShop > baseToShop then
        ReturnToBase()
    elseif distanceToShop > 7 then
        Entity.GetEntityByName(VENDOR_NAME):SetAsTarget()
        if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
            IPC.vnavmesh.PathfindAndMoveTo(VENDOR_POS, false)
        end
    end

    if yesnoAddon and yesnoAddon.Ready then
        OnAddonEvent_YesNo_PostSetup_SelectYes()
        while not shopAddon and shopAddon.Ready do
            Sleep(1)
        end
        while shopAddon and shopAddon.Ready do
            yield("/echo [OCM] Buying complete.")
            OnAddonEvent_ShopExchangeCurrency_PostSetup_CloseWindow()
            State = CharacterState.ready
            return
        end
        State = CharacterState.ready
        return
    elseif shopAddon and shopAddon.Ready then
        yield("/echo [OCM] Purchasing " .. qtyToBuy .. " " .. ShopItems[1].itemName)
        Engines.Native.Run("/callback ShopExchangeCurrency true 0 " .. ShopItems[1].itemIndex .. " " .. qtyToBuy .. " 0")
        State = CharacterState.ready
        return
    elseif iconStringAddon and iconStringAddon.Ready then
        OnAddonEvent_SelectIconString_PostSetup_SelectItem()
        State = CharacterState.ready
        return
    end

    Entity.GetEntityByName(VENDOR_NAME):Interact()
    Sleep(1)

    State = CharacterState.ready
end

function CharacterState.repair()
    local repairAddon = Addons.GetAddon("Repair")
    local yesnoAddon = Addons.GetAddon("SelectYesno")
    local shopAddon = Addons.GetAddon("Shop")
    local DarkMatterItemId = 33916
    local itemsToRepair = Inventory.GetItemsInNeedOfRepairs(tonumber(durabilityAmount))

    --Turn off OCH before repairing
    Dalamud.LogDebug("[OCM] Repairing items...")

    TurnOffOCH()

    -- if occupied by repair, then just wait
    if Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair] then
        Dalamud.LogDebug("[OCM] Repairing...")
        Sleep(1)
        return
    end

    if yesnoAddon and yesnoAddon.Ready then
        OnAddonEvent_YesNo_PostSetup_SelectYes()
        return
    end

        if repairAddon and repairAddon.Ready then
        Dalamud.LogDebug("[OCM] Checking if repairs are needed...")
        local itemsToRepair = Inventory.GetItemsInNeedOfRepairs(tonumber(durabilityAmount))
        local needsRepair = false
        if type(itemsToRepair) == "number" then
            needsRepair = itemsToRepair ~= 0
        elseif type(itemsToRepair) == "table" then
            needsRepair = next(itemsToRepair) ~= nil
        end
    
        if not needsRepair then
            OnAddonEvent_Repair_PostSetup_CloseWindow()
        else
            OnAddonEvent_Repair_PostSetup_OpenWindow()
        end
        return
    end

    if selfRepair then
        Dalamud.LogDebug("[OCM] Checking for Dark Matter...")
        if Inventory.GetItemCount(DarkMatterItemId) > 0 then
            Dalamud.LogDebug("[OCM] Dark Matter in inventory...")
            if shopAddon and shopAddon.Ready then
                OnAddonEvent_Shop_PostSetup_CloseWindow()
                return
            end

            if (type(itemsToRepair) == "number" and itemsToRepair ~= 0) or (type(itemsToRepair) == "table" and next(itemsToRepair) ~= nil) then
                Dalamud.LogDebug("[OCM] Items in need of repair...")
                while not repairAddon.Ready do
                    Dalamud.LogDebug("[OCM] Opening repair menu...")
                    Actions.ExecuteGeneralAction(6)
                repeat
                    Sleep(0.1)
                    Dalamud.LogDebug("[OCM] Waiting for repair addon to be ready...")
                until repairAddon.Ready
                end
                State = CharacterState.ready
                Dalamud.LogDebug("[OCM] State Change: Ready")
            else
                State = CharacterState.ready
                Dalamud.LogDebug("[OCM] State Change: Ready")
            end
        elseif ShouldAutoBuyDarkMatter then
            local baseToMender = Vector3.Distance(BaseAetheryte, MENDER_POS) + 50
            local distanceToMender = Vector3.Distance(Entity.Player.Position, MENDER_POS)
            if distanceToMender > baseToMender then
                ReturnToBase()
                return
            elseif distanceToMender > 7 then
                Entity.GetEntityByName(MENDER_NAME):SetAsTarget()
                if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
                    IPC.vnavmesh.PathfindAndMoveTo(MENDER_POS, false)
                end
            else
                if not Svc.Condition[CharacterCondition.occupiedInQuestEvent] then
                    Entity.GetEntityByName(MENDER_NAME):Interact()
                elseif Addons.GetAddon("SelectIconString") then
                    OnAddonEvent_SelectIconString_PostSetup_OpenMenderShop()
                elseif Addons.GetAddon("SelectYesno") then
                    OnAddonEvent_YesNo_PostSetup_SelectYes()
                elseif Addons.GetAddon("Shop") then
                    OnAddonEvent_Shop_PostSetup_BuyDarkMatter()
                end
            end
        else
            yield("/echo Out of Dark Matter and ShouldAutoBuyDarkMatter is false. Switching to mender.")
            SelfRepair = false
        end
    else
        if (type(itemsToRepair) == "number" and itemsToRepair ~= 0) or (type(itemsToRepair) == "table" and next(itemsToRepair) ~= nil) then
            local baseToMender = Vector3.Distance(BaseAetheryte, MENDER_POS) + 50
            local distanceToMender = Vector3.Distance(Entity.Player.Position, MENDER_POS)
            if distanceToMender > baseToMender then
                ReturnToBase()
                return
            elseif distanceToMender > 7 then
                if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
                    IPC.vnavmesh.PathfindAndMoveTo(MENDER_POS, false)
                end
            elseif Addons.GetAddon("SelectIconString") then
                OnAddonEvent_SelectIconString_PostSetup_RepairAtVendor()
            else
                Entity.GetEntityByName(MENDER_NAME):SetAsTarget()
                if not Svc.Condition[CharacterCondition.occupiedInQuestEvent] then
                    Entity.GetEntityByName(MENDER_NAME):Interact()
                end
            end
        else
            State = CharacterState.ready
            Dalamud.LogDebug("[OCM] State Change: Ready")
        end
    end
end

function CharacterState.materia()

    local materiaAddon = Addons.GetAddon("Materialize")
    local materiaDialogAddon = Addons.GetAddon("MaterializeDialog")

    TurnOffOCH()

    if Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair] then
        Dalamud.LogDebug("[OCM] Already extracting materia...")
        return
    end

    if Inventory.GetSpiritbondedItems().Count >= 1 and Inventory.GetFreeInventorySlots() > 1 then
        if not materiaAddon or not materiaAddon.Ready then
            yield("/echo [OCM] Opening Materia Extraction menu...")
            Actions.ExecuteGeneralAction(14) -- Open Materia Extraction
            repeat
                Sleep(0.1)
            until materiaAddon and materiaAddon.Ready
        end

        if materiaDialogAddon and materiaDialogAddon.Ready then
            OnAddonEvent_MaterializeDialog_PostSetup_ExtractMateria()
            repeat
                Sleep(0.1)
            until not Svc.Condition[CharacterCondition.occupiedMateriaExtractionAndRepair]
        else
            OnAddonEvent_Materialize_PostSetup_KeepExtracting()
        end
    else
        if materiaAddon and materiaAddon.Ready then
            OnAddonEvent_Materialize_PostSetup_CloseWindow()
            Dalamud.LogDebug("[OCM] No spiritbonded items to extract materia from.")
        else
            State = CharacterState.ready
        end

    end
end

function CharacterState.switchPhantomJob()
    SwitchToNextUncappedSupportJob()
    State = CharacterState.ready
end

--[[ ===========================
    Section: Main Loop
=========================== ]]

-- Startup
State = CharacterState.ready

-- Main loop
while true do
    if Svc.Condition[CharacterCondition.betweenAreas] then
        Sleep(1)
    end
    State()
    Sleep(1)
end