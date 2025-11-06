-- Imports
import("System.Numerics")

--Variables
local shopAddon = Addons.GetAddon("ShopExchangeCurrency")
local yesnoAddon = Addons.GetAddon("SelectYesno")
local iconStringAddon = Addons.GetAddon("SelectIconString")
local selectStringAddon = Addons.GetAddon("SelectString")

-- Shop Config
local VENDOR_NAME = "Zircon"
local VENDOR_POS = Vector3(833.83, 72.73, -719.51)
local ShopItems = {
    { itemName = "Dichromatic Compound", menuIndex = 3, itemIndex = 4, price = 20, itemID = 45989 },
}
local buyAmount = 400

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
    Engines.Native.Run("/callback SelectYesno true 0")
end

--[[ ===========================
    Section: Main Code Block
=========================== ]]--

if (IPC.AutoDuty.IsStopped()) then
    Engines.Run("/tp solution")
end
IPC.AutoDuty.Run(1292, 50, false)