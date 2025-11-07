-- Imports
import("System.Numerics")

-- Helpers
local function VecDistance(a, b)
    if not a or not b then return math.huge end
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--Variables
local shopAddon = Addons.GetAddon("ShopExchangeCurrency")
local yesnoAddon = Addons.GetAddon("SelectYesno")
local iconStringAddon = Addons.GetAddon("SelectIconString")
local selectStringAddon = Addons.GetAddon("SelectString")

-- Shop Config
local VENDOR_NAME = "Zircon"
local VENDOR_POS = Vector3(-186.01979, 0.65999997, -28.864546)
local ShopItems = {
    { itemName = "Dichromatic Compound", menuIndex = 3, itemIndex = 4, price = 20, itemID = 45989 },
}
local buyAmount = 400
local vendorTargetSet = false

-- Character Conditions
CharacterCondition = {
    dead = 2,
    mounted = 4,
    casting = 27,
    occupiedInEvent = 31,
    occupied = 33,
    boundByDuty34 = 34,
    occupiedMateriaExtractionAndRepair = 39,
    betweenAreas = 45,
    jumping48 = 48,
    jumping61 = 61,
    occupiedSummoningBell = 50,
    betweenAreasForDuty = 51,
    mounting57 = 57,
    mounting64 = 64,
    beingMoved = 70,
    flying = 77
}
local function Sleep(seconds)
    yield('/wait ' .. tostring(seconds))
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
    -- Purchase target: total 100 items (split into up-to-99 per request)
    local desiredTotal = 100
    local itemIndex = ShopItems[1].itemIndex
    if desiredTotal <= 99 then
        Engines.Native.Run("/callback ShopExchangeCurrency true 0 " .. itemIndex .. " " .. desiredTotal .. " 0")
    else
        -- Buy the bulk (99) first, then the remainder
        Engines.Native.Run("/callback ShopExchangeCurrency true 0 " .. itemIndex .. " 99 0")
        Sleep(0.2)
        local remainder = desiredTotal - 99
        if remainder > 0 then
            Engines.Native.Run("/callback ShopExchangeCurrency true 0 " .. itemIndex .. " " .. remainder .. " 0")
        end
    end
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
    Engines.Native.Run("/callback SelectYesno true 0")
end

--[[ ===========================
    Section: Main Code Block
=========================== ]]--

if (IPC.AutoDuty.IsStopped()) then
    Engines.Run("/tp solution")
    Sleep(5)
    IPC.Lifestream.AethernetTeleport("Nexus Arcade")
    Sleep(5)
    if not IPC.vnavmesh.PathfindInProgress() and not IPC.vnavmesh.IsRunning() then
        IPC.vnavmesh.PathfindAndMoveTo(VENDOR_POS, false)
        -- wait until we are near the vendor or pathfinding finishes, then set vendor as target once
        local waitTime = 0
        while VecDistance(Entity.Player.Position, VENDOR_POS) > 7 and (IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning()) and waitTime < 60 do
            Sleep(0.5)
            waitTime = waitTime + 0.5
        end
        if not vendorTargetSet and VecDistance(Entity.Player.Position, VENDOR_POS) <= 7 then
            local vendor = Entity.GetEntityByName(VENDOR_NAME)
            if vendor then
                vendor:SetAsTarget()
                vendorTargetSet = true
            end
        end
    end
end
IPC.AutoDuty.Run(1292, 50, false)