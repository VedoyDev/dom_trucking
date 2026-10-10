local Target = exports.ox_target
local Zone = lib.zones

local npc
local truck
local truckNetId
local boxProp
local hasBox = false
local locationBlip
local npcBlip
local dropOffZone
local storeZone
local atStore = false
local carryThreadActive = false
local groupState
local hudText

local START_GROUP_OPTION = 'dom_trucking_create_group'
local JOIN_GROUP_OPTION = 'dom_trucking_join_group'
local LEAVE_GROUP_OPTION = 'dom_trucking_leave_group'
local START_ROUTE_OPTION = 'dom_trucking_start_route'
local RETURN_TRUCK_OPTION = 'dom_trucking_return_truck'
local GRAB_BOX_OPTION = 'dom_trucking_grab_box'
local DROP_OFF_OPTION = 'dom_trucking_drop_off'
local NPC_OPTIONS = {START_GROUP_OPTION, JOIN_GROUP_OPTION, LEAVE_GROUP_OPTION, START_ROUTE_OPTION, RETURN_TRUCK_OPTION}

local CARRY_ANIM_DICT = 'anim@heists@box_carry@'
local CARRY_ANIM_NAME = 'idle'
local DOOR_ARM_IK_FLAG = 104 -- CPED_CONFIG_FLAG_OpenDoorArmIK

local function notify(key, msgType, ...)
    lib.notify({
        title = locale('notify_title'),
        description = locale(key, ...),
        type = msgType or 'inform',
        position = Config.Notify.Position,
        duration = Config.Notify.Duration,
    })
end

local function requestModel(model)
    local ok = pcall(lib.requestModel, model, 5000)
    return ok
end

local function myServerId()
    return GetPlayerServerId(PlayerId())
end

local function isInGroup()
    return groupState ~= nil
end

local function isLeader()
    return groupState and groupState.leader == myServerId()
end

local function isRouteActive()
    return groupState and groupState.active == true
end

local function isRouteCompleted()
    return groupState and groupState.completed == true
end

local function isGroupTruck(entity)
    return truckNetId ~= nil
        and NetworkGetEntityIsNetworked(entity)
        and NetworkGetNetworkIdFromEntity(entity) == truckNetId
end

-- HUD fixo com o progresso (substitui as notificacoes de progresso)
local function hideHud()
    if not hudText then return end

    local isOpen, currentText = lib.isTextUIOpen()
    if isOpen and currentText == hudText then
        lib.hideTextUI()
    end

    hudText = nil
end

local function showHud(text)
    if not Config.Hud.Enabled or hudText == text then return end

    hudText = text
    lib.showTextUI(text, {
        position = Config.Hud.Position,
        icon = 'truck',
    })
end

local function updateHud()
    if not groupState then
        hideHud()
    elseif groupState.completed then
        showHud(locale('hud_return'))
    elseif groupState.active then
        local currentRoute = math.min(groupState.routesCompleted + 1, groupState.routesRequired)
        showHud(locale('hud_progress', groupState.boxesDropped, groupState.boxesRequired, currentRoute, groupState.routesRequired))
    else
        showHud(locale('hud_lobby', #groupState.members, groupState.maxMembers, groupState.leader))
    end
end

local function giveVehicleKey(plate, vehicle)
    if not plate or plate == '' or not vehicle then return end
    if GetResourceState('mri_Qcarkeys') ~= 'started' then return end

    pcall(function()
        exports.mri_Qcarkeys:GiveKeyItem(plate, vehicle)
    end)
end

local function removeVehicleKey(plate, vehicle)
    if not plate or plate == '' or not vehicle then return end
    if GetResourceState('mri_Qcarkeys') ~= 'started' then return end

    pcall(function()
        exports.mri_Qcarkeys:RemoveKeyItem(plate, vehicle)
    end)
end

local function playCarryAnim(blendIn)
    TaskPlayAnim(PlayerPedId(), CARRY_ANIM_DICT, CARRY_ANIM_NAME, blendIn or 2.0, 2.5, -1, 49, 0.0, false, false, false)
end

local function startCarryThread()
    if carryThreadActive then return end

    carryThreadActive = true
    CreateThread(function()
        while hasBox do
            local ped = PlayerPedId()

            DisableControlAction(0, 22, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 45, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 143, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 263, true)
            DisableControlAction(0, 264, true)
            DisableControlAction(0, 288, true)
            DisableControlAction(0, 289, true)

            DisablePlayerFiring(PlayerId(), true)
            SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

            -- Impede o braco de empurrar portas, que corta a animacao
            SetPedConfigFlag(ped, DOOR_ARM_IK_FLAG, false)
            SetPedCanArmIk(ped, false)

            if not IsEntityPlayingAnim(ped, CARRY_ANIM_DICT, CARRY_ANIM_NAME, 3) then
                playCarryAnim(8.0)
            end

            Wait(0)
        end

        local ped = PlayerPedId()
        SetPedConfigFlag(ped, DOOR_ARM_IK_FLAG, true)
        SetPedCanArmIk(ped, true)

        carryThreadActive = false
    end)
end

local function cleanupBox()
    if boxProp and DoesEntityExist(boxProp) then
        DeleteEntity(boxProp)
    end
    boxProp = nil

    if hasBox then
        ClearPedTasks(PlayerPedId())
        hasBox = false
    end
end

local function grabBox()
    if hasBox then
        notify('has_box', 'error')
        return
    end

    local boxModel = GetHashKey(Config.Box.Model)
    local animLoaded = pcall(lib.requestAnimDict, CARRY_ANIM_DICT, 5000)
    if not animLoaded or not requestModel(boxModel) then return end

    local allowed, reason = lib.callback.await('dom_trucking:server:GrabBox', false)
    if not allowed then
        if reason then notify(reason, 'error') end
        SetModelAsNoLongerNeeded(boxModel)
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    boxProp = CreateObject(boxModel, coords.x, coords.y, coords.z, true, true, false)
    AttachEntityToEntity(boxProp, ped, GetPedBoneIndex(ped, 0x60F2), -0.1, 0.4, 0, 0, 90.0, 0, true, true, false, true, 5, true)
    SetModelAsNoLongerNeeded(boxModel)

    hasBox = true
    playCarryAnim()
    startCarryThread()
end

local function dropBox()
    if not hasBox then
        notify('no_box', 'error')
        return
    end

    local accepted, reason = lib.callback.await('dom_trucking:server:SubmitBox', false)
    if not accepted then
        if reason then notify(reason, 'error') end
        return
    end

    cleanupBox()
end

local function clearRouteMarkers()
    if dropOffZone then
        Target:removeZone(dropOffZone)
        dropOffZone = nil
    end

    if storeZone then
        storeZone:remove()
        storeZone = nil
    end

    if locationBlip then
        RemoveBlip(locationBlip)
        locationBlip = nil
    end

    if npcBlip then
        RemoveBlip(npcBlip)
        npcBlip = nil
    end

    atStore = false
    cleanupBox()
end

local function clearTruckEntity()
    -- So o lider tem a referencia local (foi quem spawnou)
    if truck and DoesEntityExist(truck) then
        removeVehicleKey(GetVehicleNumberPlateText(truck), truck)
        DeleteEntity(truck)
    end

    truck = nil
    truckNetId = nil
end

local function resetAllState()
    clearRouteMarkers()
    clearTruckEntity()
    groupState = nil
    hideHud()
end

local function createRouteBlip(coords)
    local blip = AddBlipForCoord(coords)
    SetBlipColour(blip, 3)
    SetBlipHiddenOnLegend(blip, true)
    SetBlipRoute(blip, true)
    SetBlipDisplay(blip, 8)
    SetBlipRouteColour(blip, 3)
    return blip
end

local function applyDropOff(index)
    clearRouteMarkers()

    local point = Config.DropOff.Points[index]
    locationBlip = createRouteBlip(point)

    storeZone = Zone.sphere({
        coords = point,
        radius = Config.DropOff.ZoneRadius,
        debug = false,
        onEnter = function()
            atStore = true

            if Config.Debug then
                print(('[dom_trucking] Chegou na loja %s | truckNetId: %s'):format(index, tostring(truckNetId)))
            end

            -- Mantem o blip para achar a porta, so tira a linha do GPS
            if locationBlip then
                SetBlipRoute(locationBlip, false)
            end

            if dropOffZone then return end

            dropOffZone = Target:addSphereZone({
                coords = point,
                radius = 1,
                debug = false,
                options = {{
                    name = DROP_OFF_OPTION,
                    icon = 'fa-solid fa-truck-ramp-box',
                    label = locale('drop_off_box'),
                    canInteract = function()
                        return isRouteActive() and hasBox
                    end,
                    onSelect = dropBox
                }}
            })
        end,
    })
end

RegisterNetEvent('dom_trucking:client:Notify', function(key, msgType, ...)
    notify(key, msgType, ...)
end)

RegisterNetEvent('dom_trucking:client:GroupState', function(payload)
    groupState = payload
    truckNetId = payload and payload.truckNetId or nil
    updateHud()
end)

RegisterNetEvent('dom_trucking:client:SpawnLeaderTruck', function(groupId)
    if not groupState or groupState.id ~= groupId or not isLeader() then return end

    local model = GetHashKey(Config.Truck.Model)
    if not requestModel(model) then
        notify('vehicle_spawn_fail', 'error')
        TriggerServerEvent('dom_trucking:server:TruckSpawnFailed')
        return
    end

    local coords = Config.Truck.Location
    local vehicle = CreateVehicle(model, coords.x, coords.y, coords.z, Config.Truck.Heading, true, false)
    SetModelAsNoLongerNeeded(model)

    local timeout = GetGameTimer() + 3000
    while not NetworkGetEntityIsNetworked(vehicle) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not DoesEntityExist(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then
        if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
        notify('vehicle_spawn_fail', 'error')
        TriggerServerEvent('dom_trucking:server:TruckSpawnFailed')
        return
    end

    SetVehicleOnGroundProperly(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)

    truck = vehicle
    truckNetId = NetworkGetNetworkIdFromEntity(vehicle)
    giveVehicleKey(GetVehicleNumberPlateText(vehicle), vehicle)

    TriggerServerEvent('dom_trucking:server:RegisterTruck', groupId, truckNetId)
end)

RegisterNetEvent('dom_trucking:client:SetDropOff', function(index)
    if not isInGroup() then return end
    applyDropOff(index)
end)

RegisterNetEvent('dom_trucking:client:RouteCompleted', function()
    clearRouteMarkers()
    npcBlip = createRouteBlip(Config.NPC.Location)
    notify('return_truck_msg', 'success')
end)

RegisterNetEvent('dom_trucking:client:RouteFinished', function(amount)
    resetAllState()
    notify('job_complete', 'success', amount)
end)

RegisterNetEvent('dom_trucking:client:GroupDisbanded', function(reasonKey)
    resetAllState()
    notify(reasonKey or 'group_disbanded', 'error')
end)

RegisterNetEvent('dom_trucking:client:LeftGroup', function()
    resetAllState()
    notify('left_group', 'inform')
end)

Target:addGlobalVehicle({{
    name = GRAB_BOX_OPTION,
    icon = 'fa-solid fa-truck-ramp-box',
    label = locale('grab_box'),
    bones = {'door_dside_r', 'door_pside_r'},
    canInteract = function(entity)
        return atStore and not hasBox and isRouteActive() and isGroupTruck(entity)
    end,
    onSelect = grabBox
}})

local function npcOnEnter()
    if npc and DoesEntityExist(npc) then return end

    local model = GetHashKey(Config.NPC.Model)
    if not requestModel(model) then return end

    npc = CreatePed(1, model, Config.NPC.Location.x, Config.NPC.Location.y, Config.NPC.Location.z, Config.NPC.Heading, false, false)
    SetModelAsNoLongerNeeded(model)
    FreezeEntityPosition(npc, true)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetEntityAsMissionEntity(npc, true, true)

    Target:addLocalEntity(npc, {{
        name = START_GROUP_OPTION,
        icon = 'fa-solid fa-users',
        label = locale('create_group'),
        canInteract = function()
            return not isInGroup()
        end,
        onSelect = function()
            TriggerServerEvent('dom_trucking:server:CreateGroup')
        end
    }, {
        name = JOIN_GROUP_OPTION,
        icon = 'fa-solid fa-user-plus',
        label = locale('join_group'),
        canInteract = function()
            return not isInGroup()
        end,
        onSelect = function()
            local input = lib.inputDialog(locale('join_group'), {{
                type = 'number',
                label = locale('leader_id'),
                required = true,
                min = 1,
            }})

            if not input or not input[1] then return end

            TriggerServerEvent('dom_trucking:server:JoinGroup', tonumber(input[1]))
        end
    }, {
        name = LEAVE_GROUP_OPTION,
        icon = 'fa-solid fa-right-from-bracket',
        label = locale('leave_group'),
        canInteract = function()
            return isInGroup()
        end,
        onSelect = function()
            TriggerServerEvent('dom_trucking:server:LeaveGroup')
        end
    }, {
        name = START_ROUTE_OPTION,
        icon = 'fa-solid fa-truck',
        label = locale('start_group_route'),
        canInteract = function()
            return isLeader() and not isRouteActive() and not isRouteCompleted()
        end,
        onSelect = function()
            TriggerServerEvent('dom_trucking:server:StartRoute')
        end
    }, {
        name = RETURN_TRUCK_OPTION,
        icon = 'fa-solid fa-clipboard-check',
        label = locale('return_truck'),
        canInteract = function()
            return isLeader() and isRouteCompleted()
        end,
        onSelect = function()
            TriggerServerEvent('dom_trucking:server:FinishRoute')
        end
    }})
end

local function npcOnExit()
    if npc and DoesEntityExist(npc) then
        Target:removeLocalEntity(npc, NPC_OPTIONS)
        DeleteEntity(npc)
    end
    npc = nil
end

Zone.box({
    coords = Config.NPC.Zone.Coords,
    size = Config.NPC.Zone.Size,
    rotation = Config.NPC.Zone.Rotation,
    debug = false,
    onEnter = npcOnEnter,
    onExit = npcOnExit
})

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    resetAllState()
    Target:removeGlobalVehicle(GRAB_BOX_OPTION)
    npcOnExit()
end)
