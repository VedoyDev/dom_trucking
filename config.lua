Config = {}

Config.Language = 'pt-br'

-- Mostra no console do servidor/F8 por que o caminhao ou a caixa foram recusados
Config.Debug = false

Config.NPC = {
    Model = 's_m_m_postal_02',
    Location = vec3(68.888, 127.169, 78.205),
    Heading = 158.59,
    -- Area onde o NPC e spawnado/removido
    Zone = {
        Coords = vec3(65.692, 117.731, 79.159),
        Size = vec3(20, 25, 10),
        Rotation = -20,
    },
}

Config.Truck = {
    Model = 'boxville2',
    Location = vec3(71.804, 120.588, 79.078),
    Heading = 160.583,
}

Config.Box = {
    Model = 'prop_cs_cardbox_01',
}

Config.DropOff = {
    -- Ponto onde a caixa e entregue. A area da loja e um raio em volta dele.
    Points = {
        -- Mercados e lojas de conveniencia
        vec3(-41.49, -1751.36, 29.53),    -- Davis (Grove St / Carson Ave)
        vec3(25.32, -1338.99, 29.50),     -- Strawberry (Innocence Blvd)
        vec3(-706.22, -905.18, 19.23),    -- Little Seoul (Calais Ave)
        vec3(-1222.87, -913.15, 12.33),   -- Vespucci Canals (Palomino Ave)
        vec3(1130.29, -979.72, 46.42),    -- Cypress Flats (El Rancho Blvd)
        vec3(1163.14, -314.31, 69.21),    -- La Mesa (Popular St)
        vec3(-1481.35, -377.97, 40.16),   -- Del Perro / Morningwood (Prosperity St)
        vec3(375.57, 334.23, 103.57),     -- Downtown Vinewood (Clinton Ave)

        -- Ammu-Nation
        vec3(13.93, -1106.32, 29.80),     -- Pillbox Hill (Downtown)
        vec3(-666.68, -933.71, 21.83),    -- Little Seoul
        vec3(846.69, -1035.06, 28.32),    -- La Mesa (East Los Santos)
        vec3(818.09, -2155.32, 29.62),    -- Cypress Flats (Popular St / Porto)
        vec3(255.08, -46.45, 69.94),      -- Hawick / Vinewood
        vec3(-1303.12, -390.41, 36.70),   -- Morningwood / Rockford Hills
    },
    -- Raio (m) em volta do ponto que conta como "chegou na loja" (libera pegar caixa)
    ZoneRadius = 40.0,
    BoxesMin = 3,
    BoxesMax = 5,
    RoutesMin = 2,
    RoutesMax = 4,
}

Config.Reward = {
    Reward = 'money',
    AmountMin = 300,
    AmountMax = 700,
}

Config.Group = {
    MaxMembers = 4,
    BoxesMultiplierPerExtraPlayer = 0.30,
    RoutesPerExtraPlayer = 0.25,
    PayMultiplierPerExtraPlayer = 0.20,
}

Config.Notify = {
    Position = 'top-right',
    Duration = 3000,
}

-- Progresso da rota fica fixo na tela em vez de virar notificacao
Config.Hud = {
    Enabled = true,
    Position = 'right-center',
}

-- Validacoes do servidor (anti-exploit)
Config.Security = {
    ActionCooldown = 1000, -- ms entre pegar/entregar caixas
    GrabDistance = 8.0,    -- distancia max do jogador ate o caminhao para pegar caixa
    StoreDistance = 60.0,  -- distancia max do jogador ate a loja para pegar caixa
    DropDistance = 4.0,    -- distancia max do jogador ate o ponto de entrega
    ReturnDistance = 30.0, -- distancia max do caminhao/lider ate o NPC para finalizar
    SpawnDistance = 15.0,  -- distancia max do caminhao registrado ate o ponto de spawn
}
