local Inventory = exports.ox_inventory

local groups = {}
local playerGroup = {}
local lastAction = {}
local nextGroupId = 1

local function getGroupConfig()
    return (Config and Config.Group) or {}
end

local function getSecurity()
    return (Config and Config.Security) or {}
end

local function debugLog(message, ...)
    if not Config.Debug then return end
    print(('^3[dom_trucking]^7 ' .. message):format(...))
end

local function playerName(source)
    return GetPlayerName(source) or ('ID %s'):format(source)
end

local function isPlayerNear(source, coords, maxDistance)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not coords then return false end

    return #(GetEntityCoords(ped) - coords) <= maxDistance
end

local function isRateLimited(source)
    local now = GetGameTimer()
    local cooldown = tonumber(getSecurity().ActionCooldown) or 1000

    if lastAction[source] and now - lastAction[source] < cooldown then
        return true
    end

    lastAction[source] = now
    return false
end

local function sameModel(a, b)
    return (a & 0xFFFFFFFF) == (b & 0xFFFFFFFF)
end

local function getMemberSnapshot(group)
    local snapshot = {}

    for i = 1, #group.members do
        local memberSource = group.members[i]
        snapshot[#snapshot + 1] = {
            source = memberSource,
            name = playerName(memberSource)
        }
    end

    return snapshot
end

local function getGroupFromPlayer(source)
    local groupId = playerGroup[source]
    if not groupId then return nil end

    return groups[groupId]
end

local function isGroupLeader(group, source)
    return group and group.leader == source
end

local function countCarrying(group)
    local count = 0

    for _ in pairs(group.carrying) do
        count = count + 1
    end

    return count
end

local function getGroupTruck(group)
    if not group or not group.truckNetId then return nil end

    local entity = NetworkGetEntityFromNetworkId(group.truckNetId)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        return entity
    end

    return nil
end

local function notifyPlayer(source, key, msgType, ...)
    TriggerClientEvent('dom_trucking:client:Notify', source, key, msgType or 'inform', ...)
end

local function broadcastGroup(group, eventName, ...)
    if not group then return end

    for i = 1, #group.members do
        TriggerClientEvent(eventName, group.members[i], ...)
    end
end

local function notifyGroup(group, key, msgType, ...)
    if not group then return end

    for i = 1, #group.members do
        notifyPlayer(group.members[i], key, msgType, ...)
    end
end

local function syncGroupState(group)
    if not group then return end

    local payload = {
        id = group.id,
        leader = group.leader,
        maxMembers = group.maxMembers,
        members = getMemberSnapshot(group),
        active = group.active,
        completed = group.completed,
        routesCompleted = group.routesCompleted,
        routesRequired = group.routesRequired,
        boxesDropped = group.boxesDropped,
        boxesRequired = group.boxesRequired,
        dropOffIndex = group.dropOffIndex,
        truckNetId = group.truckNetId,
    }

    broadcastGroup(group, 'dom_trucking:client:GroupState', payload)
end

local function deleteGroupTruck(group)
    local entity = getGroupTruck(group)
    if entity then
        DeleteEntity(entity)
    end

    if group then
        group.truckNetId = nil
    end
end

local function clearGroup(groupId)
    local group = groups[groupId]
    if not group then return end

    for i = 1, #group.members do
        playerGroup[group.members[i]] = nil
    end

    groups[groupId] = nil
end

local function disbandGroup(group, reasonKey)
    if not group then return end

    deleteGroupTruck(group)
    broadcastGroup(group, 'dom_trucking:client:GroupDisbanded', reasonKey)
    clearGroup(group.id)
end

-- Sorteia todas as entregas da rota de uma vez, sem repetir local
local function buildRoutePlan(count)
    local indexes = {}
    for i = 1, #Config.DropOff.Points do
        indexes[i] = i
    end

    for i = #indexes, 2, -1 do
        local j = math.random(1, i)
        indexes[i], indexes[j] = indexes[j], indexes[i]
    end

    local plan = {}
    for i = 1, math.min(count, #indexes) do
        plan[i] = indexes[i]
    end

    return plan
end

local function configureNextDropOff(group)
    local groupConfig = getGroupConfig()
    local playersAtStart = group.playersAtStart or #group.members
    local minBoxes = math.max(1, tonumber(Config.DropOff.BoxesMin) or 1)
    local maxBoxes = math.max(minBoxes, tonumber(Config.DropOff.BoxesMax) or minBoxes)
    local baseBoxes = math.random(minBoxes, maxBoxes)
    local boxScale = math.max(0, tonumber(groupConfig.BoxesMultiplierPerExtraPlayer) or 0)

    group.dropOffIndex = group.routePlan[group.routesCompleted + 1]
    group.boxesRequired = math.max(1, math.floor(baseBoxes * (1 + (math.max(0, playersAtStart - 1) * boxScale)) + 0.5))
    group.boxesDropped = 0
    group.carrying = {}

    if not group.dropOffIndex then
        return false
    end

    broadcastGroup(group, 'dom_trucking:client:SetDropOff', group.dropOffIndex)
    return true
end

local function removeMember(source)
    lastAction[source] = nil

    local group = getGroupFromPlayer(source)
    if not group then return end

    local removeIndex
    for i = 1, #group.members do
        if group.members[i] == source then
            removeIndex = i
            break
        end
    end

    playerGroup[source] = nil
    group.carrying[source] = nil

    if not removeIndex then return end

    table.remove(group.members, removeIndex)
    TriggerClientEvent('dom_trucking:client:LeftGroup', source)

    if #group.members == 0 then
        deleteGroupTruck(group)
        clearGroup(group.id)
        return
    end

    if group.leader == source then
        disbandGroup(group, 'leader_left_cancel')
        return
    end

    notifyGroup(group, 'member_left', 'inform', playerName(source))
    syncGroupState(group)
end

RegisterNetEvent('dom_trucking:server:CreateGroup', function()
    local source = source

    if playerGroup[source] then
        notifyPlayer(source, 'already_in_group', 'error')
        return
    end

    local maxMembers = math.max(1, tonumber(getGroupConfig().MaxMembers) or 4)

    local group = {
        id = nextGroupId,
        leader = source,
        members = {source},
        maxMembers = maxMembers,
        active = false,
        completed = false,
        paid = false,
        routesRequired = 0,
        routesCompleted = 0,
        boxesRequired = 0,
        boxesDropped = 0,
        carrying = {},
        routePlan = {},
        dropOffIndex = nil,
        playersAtStart = 1,
        truckNetId = nil,
    }

    groups[group.id] = group
    playerGroup[source] = group.id
    nextGroupId = nextGroupId + 1

    notifyPlayer(source, 'group_created', 'success', source)
    syncGroupState(group)
end)

-- Entra na equipe pelo ID (server id) do lider
RegisterNetEvent('dom_trucking:server:JoinGroup', function(leaderSource)
    local source = source

    if playerGroup[source] then
        notifyPlayer(source, 'already_in_group', 'error')
        return
    end

    local leaderId = tonumber(leaderSource)
    local targetGroup = leaderId and groups[playerGroup[leaderId]]

    if not targetGroup or targetGroup.leader ~= leaderId then
        notifyPlayer(source, 'group_not_found', 'error')
        return
    end

    if targetGroup.active or targetGroup.completed then
        notifyPlayer(source, 'group_already_started', 'error')
        return
    end

    if #targetGroup.members >= targetGroup.maxMembers then
        notifyPlayer(source, 'group_full', 'error', targetGroup.maxMembers)
        return
    end

    targetGroup.members[#targetGroup.members + 1] = source
    playerGroup[source] = targetGroup.id

    notifyGroup(targetGroup, 'member_joined', 'success', playerName(source))
    syncGroupState(targetGroup)
end)

RegisterNetEvent('dom_trucking:server:LeaveGroup', function()
    removeMember(source)
end)

RegisterNetEvent('dom_trucking:server:StartRoute', function()
    local source = source
    local group = getGroupFromPlayer(source)

    if not isGroupLeader(group, source) then
        notifyPlayer(source, 'only_leader_start', 'error')
        return
    end

    if group.active then
        notifyPlayer(source, 'route_already_active', 'error')
        return
    end

    if group.completed then
        notifyPlayer(source, 'route_already_done', 'error')
        return
    end

    local playersAtStart = #group.members
    local minRoutes = math.max(1, tonumber(Config.DropOff.RoutesMin) or 1)
    local maxRoutes = math.max(minRoutes, tonumber(Config.DropOff.RoutesMax) or minRoutes)
    local extraRoutes = math.ceil(math.max(0, playersAtStart - 1) * math.max(0, tonumber(getGroupConfig().RoutesPerExtraPlayer) or 0))

    -- Nunca pede mais entregas do que locais disponiveis
    local routesRequired = math.min(math.max(1, math.random(minRoutes, maxRoutes) + extraRoutes), #Config.DropOff.Points)

    group.playersAtStart = playersAtStart
    group.routePlan = buildRoutePlan(routesRequired)
    group.routesRequired = #group.routePlan
    group.routesCompleted = 0
    group.dropOffIndex = nil
    group.active = true
    group.completed = false
    group.truckNetId = nil

    if not configureNextDropOff(group) then
        disbandGroup(group, 'no_dropoff_configured')
        return
    end

    TriggerClientEvent('dom_trucking:client:SpawnLeaderTruck', source, group.id)
    notifyGroup(group, 'route_started', 'success')
    syncGroupState(group)
end)

RegisterNetEvent('dom_trucking:server:RegisterTruck', function(groupId, truckNetId)
    local source = source
    local group = getGroupFromPlayer(source)

    if not group or group.id ~= tonumber(groupId) or not isGroupLeader(group, source) then return end
    if not group.active or group.truckNetId then return end

    local netId = tonumber(truckNetId)
    if not netId then return end

    -- A entidade pode demorar alguns ticks para existir no servidor
    local entity = 0
    local timeout = GetGameTimer() + 3000
    while GetGameTimer() < timeout do
        entity = NetworkGetEntityFromNetworkId(netId)
        if entity ~= 0 and DoesEntityExist(entity) then break end
        Wait(100)
    end

    -- O grupo pode ter sido encerrado enquanto esperava
    if groups[group.id] ~= group then return end

    local spawnDistance = tonumber(getSecurity().SpawnDistance) or 15.0
    local reason

    if entity == 0 or not DoesEntityExist(entity) then
        reason = 'entidade nao encontrada no servidor'
    elseif not sameModel(GetEntityModel(entity), GetHashKey(Config.Truck.Model)) then
        reason = ('modelo errado (%s)'):format(GetEntityModel(entity))
    elseif #(GetEntityCoords(entity) - Config.Truck.Location) > spawnDistance then
        reason = ('longe do spawn (%.1fm)'):format(#(GetEntityCoords(entity) - Config.Truck.Location))
    end

    if reason then
        debugLog('RegisterTruck recusado (lider %s, netId %s): %s', source, netId, reason)
        disbandGroup(group, 'vehicle_spawn_fail')
        return
    end

    debugLog('Caminhao registrado: grupo %s, netId %s', group.id, netId)

    group.truckNetId = netId
    syncGroupState(group)
end)

RegisterNetEvent('dom_trucking:server:TruckSpawnFailed', function()
    local source = source
    local group = getGroupFromPlayer(source)

    if isGroupLeader(group, source) and group.active and not group.truckNetId then
        disbandGroup(group, 'vehicle_spawn_fail')
    end
end)

lib.callback.register('dom_trucking:server:GrabBox', function(source)
    local group = getGroupFromPlayer(source)
    if not group or not group.active or not group.dropOffIndex then return false end

    if group.carrying[source] then return false, 'has_box' end
    if isRateLimited(source) then return false end

    local security = getSecurity()
    local truck = getGroupTruck(group)

    if not truck then
        debugLog('GrabBox recusado (%s): caminhao do grupo %s nao existe no servidor', source, group.id)
        return false, 'too_far'
    end

    if not isPlayerNear(source, GetEntityCoords(truck), tonumber(security.GrabDistance) or 8.0) then
        debugLog('GrabBox recusado (%s): longe do caminhao', source)
        return false, 'too_far'
    end

    if not isPlayerNear(source, Config.DropOff.Points[group.dropOffIndex], tonumber(security.StoreDistance) or 60.0) then
        debugLog('GrabBox recusado (%s): longe da loja %s', source, group.dropOffIndex)
        return false, 'too_far'
    end

    if group.boxesDropped + countCarrying(group) >= group.boxesRequired then
        return false, 'no_boxes_left'
    end

    group.carrying[source] = true
    return true
end)

lib.callback.register('dom_trucking:server:SubmitBox', function(source)
    local group = getGroupFromPlayer(source)
    if not group or not group.active or group.completed or not group.dropOffIndex then return false end

    if not group.carrying[source] then return false, 'no_box' end
    if isRateLimited(source) then return false end

    local targetPoint = Config.DropOff.Points[group.dropOffIndex]
    if not isPlayerNear(source, targetPoint, tonumber(getSecurity().DropDistance) or 4.0) then
        return false, 'too_far'
    end

    group.carrying[source] = nil
    group.boxesDropped = group.boxesDropped + 1

    if group.boxesDropped < group.boxesRequired then
        syncGroupState(group)
        return true
    end

    group.routesCompleted = group.routesCompleted + 1

    if group.routesCompleted >= group.routesRequired then
        group.active = false
        group.completed = true
        group.dropOffIndex = nil
        broadcastGroup(group, 'dom_trucking:client:RouteCompleted')
        syncGroupState(group)
        return true
    end

    configureNextDropOff(group)
    notifyGroup(group, 'next_route', 'inform')
    syncGroupState(group)
    return true
end)

RegisterNetEvent('dom_trucking:server:FinishRoute', function()
    local source = source
    local group = getGroupFromPlayer(source)

    if not isGroupLeader(group, source) then
        notifyPlayer(source, 'only_leader_finish', 'error')
        return
    end

    if not group.completed or group.paid then
        notifyPlayer(source, 'route_not_finished', 'error')
        return
    end

    local returnDistance = tonumber(getSecurity().ReturnDistance) or 30.0
    local truck = getGroupTruck(group)

    if not truck or #(GetEntityCoords(truck) - Config.NPC.Location) > returnDistance then
        notifyPlayer(source, 'truck_not_here', 'error')
        return
    end

    if not isPlayerNear(source, Config.NPC.Location, returnDistance) then
        notifyPlayer(source, 'too_far', 'error')
        return
    end

    group.paid = true

    local rewardMin = math.max(1, tonumber(Config.Reward.AmountMin) or 1)
    local rewardMax = math.max(rewardMin, tonumber(Config.Reward.AmountMax) or rewardMin)
    local baseReward = math.random(rewardMin, rewardMax)
    local playersAtStart = math.max(1, tonumber(group.playersAtStart) or #group.members)
    local payScale = 1 + (math.max(0, playersAtStart - 1) * math.max(0, tonumber(getGroupConfig().PayMultiplierPerExtraPlayer) or 0))
    local finalReward = math.floor(baseReward * payScale)

    for i = 1, #group.members do
        local member = group.members[i]
        Inventory:AddItem(member, Config.Reward.Reward, finalReward)
        TriggerClientEvent('dom_trucking:client:RouteFinished', member, finalReward)
    end

    deleteGroupTruck(group)
    clearGroup(group.id)
end)

AddEventHandler('playerDropped', function()
    removeMember(source)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for groupId, group in pairs(groups) do
        deleteGroupTruck(group)
        broadcastGroup(group, 'dom_trucking:client:GroupDisbanded')
        clearGroup(groupId)
    end
end)
