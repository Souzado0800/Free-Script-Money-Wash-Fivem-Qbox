-- client.lua (aph_moneywash) - persistência + targets pós-restart

local spawned = {
    moneywash = {}, -- { dbId?, netId, coords }
    generators = {} -- { dbId?, netId, coords }
}

-- =========================
-- Helpers de modelo/objeto
-- =========================
local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelValid(hash) then
        lib.notify({type='error', title='Modelo inválido', description=tostring(model)})
        return false
    end
    if not HasModelLoaded(hash) then
        RequestModel(hash)
        local waited = 0
        while not HasModelLoaded(hash) do
            Wait(10)
            waited = waited + 10
            if waited > 10000 then
                lib.notify({type='error', title='Erro', description='Timeout ao carregar modelo'})
                return false
            end
        end
    end
    return hash
end

local function createObject(modelName, coords, heading)
    local hash = loadModel(modelName); if not hash then return nil end
    local obj = CreateObject(hash, coords.x, coords.y, coords.z, true, true, false)
    SetEntityHeading(obj, heading or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityAsMissionEntity(obj, true, false)
    local netId = NetworkGetNetworkIdFromEntity(obj)
    SetNetworkIdCanMigrate(netId, true)
    local real = GetEntityCoords(obj)
    return obj, netId, real
end

local function placeObject(modelName)
    local ped = cache.ped or PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)

    local offY = (Config.SpawnOffset and Config.SpawnOffset.y) or 1.5
    local offZ = (Config.SpawnOffset and Config.SpawnOffset.z) or 0.0

    local where = pcoords
        + vector3(forward.x, forward.y, 0.0) * offY
        + vector3(0.0, 0.0, offZ)

    return createObject(modelName, { x = where.x, y = where.y, z = where.z }, GetEntityHeading(ped))
end

local function fmtTime(seconds)
    seconds = math.max(math.floor(seconds or 0), 0)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%02d:%02d", m, s)
end

-- =========================
-- Menu do GERADOR
-- =========================
local function buildGeneratorMenu(entity)
    local st = Entity(entity).state.aph_gen or { remaining = 0, isOn = false, syncAt = GetCloudTimeAsInt() }
    local cloudNow = GetCloudTimeAsInt()
    local remaining = st.remaining or 0
    if st.isOn then
        local delta = math.max(cloudNow - (st.syncAt or cloudNow), 0)
        remaining = math.max(remaining - delta, 0)
    end

    local status = st.isOn and 'Ligado' or 'Desligado'
    local desc = ('Status: %s\nTempo restante: %s'):format(status, fmtTime(remaining))

    lib.registerContext({
        id = 'aph_generator_menu',
        title = '⚙️ Gerador',
        description = desc,
        canClose = true,
        options = {
            {
                title = 'Abastecer',
                description = ('1 galão = %d min'):format(Config.MinutesPerCan or 10),
                icon = 'fa-solid fa-gas-pump',
                arrow = true,
                onSelect = function()
                    local input = lib.inputDialog('Abastecer Gerador', {
                        { type = 'number', label = 'Galões (quantidade)', description = 'Quantos galões deseja usar?', required = true, min = 1 }
                    })
                    if input and input[1] then
                        local cans = math.floor(tonumber(input[1]) or 0)
                        if cans > 0 then
                            local netId = NetworkGetNetworkIdFromEntity(entity)
                            TriggerServerEvent('aph_moneywash:server:fuelGenerator', netId, cans)
                        else
                            lib.notify({type='error', title='Gerador', description='Quantidade inválida.'})
                        end
                    end
                end
            },
            {
                title = st.isOn and 'Desligar' or 'Ligar',
                description = st.isOn and 'Pausar consumo de tempo' or 'Iniciar consumo de tempo',
                icon = st.isOn and 'fa-solid fa-power-off' or 'fa-solid fa-play',
                onSelect = function()
                    local netId = NetworkGetNetworkIdFromEntity(entity)
                    TriggerServerEvent('aph_moneywash:server:toggleGenerator', netId, not st.isOn)
                end
            }
        },
        -- 🎨 estilo roxo/preto
        style = {
            borderRadius = 14,
            background = 'linear-gradient(135deg, #0d0d0d 0%, #1a0f2e 35%, #6f42c1 100%)',
            color = '#ffffff',
            headerColor = '#9b59b6',
            boxShadow = '0 8px 24px rgba(0,0,0,0.45), inset 0 0 0 1px rgba(255,255,255,0.06)'
        }
    })

    lib.showContext('aph_generator_menu')
end

-- =========================
-- Targets
-- =========================
function addGeneratorTarget(entity)
    exports.ox_target:addLocalEntity(entity, {
        {
            icon = 'fa-solid fa-gear',
            label = 'Abrir menu do gerador',
            distance = 2.0,
            onSelect = function()
                buildGeneratorMenu(entity)
            end
        }
    })
end

function addMoneywashTarget(entity)
    exports.ox_target:addLocalEntity(entity, {
        {
            icon = 'fa-solid fa-soap',
            label = 'Usar estação (exige gerador ligado perto)',
            distance = 2.0,
            onSelect = function()
                local pos = GetEntityCoords(entity)

                lib.callback('aph_moneywash:server:isPoweredNearby', false, function(powered, remSeconds)
                    if not powered then
                        lib.notify({type='error', title='Moneywash', description='Nenhum gerador ligado nas proximidades'})
                        return
                    end

                    lib.callback('aph_moneywash:server:getWashInfo', false, function(info)
                        local perc = info and info.percent or 75
                        local dur  = info and info.duration or 30
                        local has  = info and info.hasActive or false
                        local rem  = info and info.remaining or 0

                        local desc = ('Taxa: %d%% • Tempo de lavagem: %ds'):format(perc, dur)
                        if has then
                            desc = desc .. ('\nLavagem em andamento: %s restantes'):format(fmtTime(rem))
                        else
                            desc = desc .. '\nNenhuma lavagem em andamento'
                        end

                        lib.registerContext({
                            id = 'moneywash_menu',
                            title = '💸 Lavagem de Dinheiro',
                            description = desc,
                            canClose = true,
                            options = {
                                {
                                    title = 'Quantidade de dinheiro para lavar',
                                    description = 'Converte black_money em money com taxa',
                                    icon = 'fa-solid fa-hand-holding-dollar',
                                    arrow = true,
                                    onSelect = function()
                                        local input = lib.inputDialog('Lavagem de Dinheiro', {
                                            { type = 'number', label = 'Valor (black_money)', description = 'Digite quanto deseja lavar', required = true, min = 1 }
                                        })
                                        if input and input[1] then
                                            local amount = math.floor(tonumber(input[1]) or 0)
                                            if amount > 0 then
                                                TriggerServerEvent('aph_moneywash:server:startWash', amount)
                                            else
                                                lib.notify({type='error', title='Lavagem', description='Valor inválido.'})
                                            end
                                        end
                                    end
                                },
                                {
                                    title = 'Retire o dinheiro limpo aqui',
                                    description = 'Receba o valor convertido em money',
                                    icon = 'fa-solid fa-money-bill-wave',
                                    onSelect = function()
                                        TriggerServerEvent('aph_moneywash:server:collectClean')
                                    end
                                }
                            },
                            -- 🎨 estilo roxo/preto
                            style = {
                                borderRadius = 14,
                                background = 'linear-gradient(135deg, #0d0d0d 0%, #1a0f2e 35%, #6f42c1 100%)',
                                color = '#ffffff',
                                headerColor = '#9b59b6',
                                boxShadow = '0 8px 24px rgba(0,0,0,0.45), inset 0 0 0 1px rgba(255,255,255,0.06)'
                            }
                        })

                        lib.showContext('moneywash_menu')
                    end)
                end, { x = pos.x, y = pos.y, z = pos.z })
            end
        }
    })
end

-- =========================
-- Consumo de KITS + spawn
-- =========================
local function attemptPlace(kind)
    -- servidor tenta REMOVER o kit antes de spawnar
    lib.callback('aph_moneywash:server:consumeKit', false, function(ok)
        if not ok then
            local name = (kind == 'generator') and 'generator_kit' or 'moneywash_kit'
            lib.notify({type='error', title='Item', description=('Você não tem %s.'):format(name)})
            return
        end

        if kind == 'generator' then
            local obj, netId, coords = placeObject((Config.Props and Config.Props.GeneratorProp) or 'prop_generator_03b')
            if not obj then return end
            table.insert(spawned.generators, { netId = netId, coords = coords })
            TriggerServerEvent('aph_moneywash:server:registerGenerator', netId, { x = coords.x, y = coords.y, z = coords.z })
            addGeneratorTarget(obj)
            lib.notify({type='success', title='Gerador', description='Gerador colocado'})
        else
            local obj, netId, coords = placeObject((Config.Props and Config.Props.MoneywashProp) or 'prop_cash_depot')
            if not obj then return end
            table.insert(spawned.moneywash, { netId = netId, coords = coords })
            addMoneywashTarget(obj)
            lib.notify({type='success', title='Moneywash', description='Estação de lavagem colocada'})
            TriggerServerEvent('aph_moneywash:server:registerStation', { x = coords.x, y = coords.y, z = coords.z }, GetEntityHeading(obj))
        end
    end, kind)
end

-- =========================
-- Exports / Eventos de itens
-- =========================
function useMoneywash(data, slot) attemptPlace('moneywash') end
exports('useMoneywash', useMoneywash)

function useGenerator(data, slot) attemptPlace('generator') end
exports('useGenerator', useGenerator)

RegisterNetEvent('aph_moneywash:useMoneywash', function() attemptPlace('moneywash') end)
RegisterNetEvent('aph_moneywash:useGenerator', function() attemptPlace('generator') end)

-- =========================
-- Sync do GERADOR via servidor -> client
-- =========================
RegisterNetEvent('aph_moneywash:client:updateGenState', function(netId, data)
    if not netId or not data then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and DoesEntityExist(ent) then
        Entity(ent).state:set('aph_gen', {
            remaining = data.remaining or 0,
            isOn = data.isOn and true or false,
            syncAt = data.syncAt or GetCloudTimeAsInt()
        }, true)
    end
end)

-- =========================
-- Helper: spawn persistente local + target + link
-- =========================
local function spawnPersistentLocally(payload)
    if not payload or not payload.type then return end
    local mdl     = payload.model
    local coords  = payload.coords
    local heading = payload.heading or 0.0

    local obj, netId, real = createObject(mdl, coords, heading)
    if not obj then return end

    if payload.type == 'generator' then
        table.insert(spawned.generators, { dbId = payload.dbId, netId = netId, coords = real })
        if payload.state then
            TriggerEvent('aph_moneywash:client:updateGenState', netId, {
                remaining = payload.state.remaining or 0,
                isOn      = payload.state.isOn and true or false,
                syncAt    = GetCloudTimeAsInt()
            })
        end
        addGeneratorTarget(obj)
        TriggerServerEvent('aph_moneywash:server:linkPersistent', payload.dbId, netId, 'generator')
    else
        table.insert(spawned.moneywash, { dbId = payload.dbId, netId = netId, coords = real })
        addMoneywashTarget(obj)
        TriggerServerEvent('aph_moneywash:server:linkPersistent', payload.dbId, netId, 'station')
    end
end

-- usado quando o servidor quiser forçar spawn (ex.: onResourceStart broadcast)
RegisterNetEvent('aph_moneywash:client:spawnPersistent', function(payload)
    spawnPersistentLocally(payload)
end)

-- =========================
-- Bootstrap de sincronização pós-restart
-- =========================
CreateThread(function()
    -- dá um respiro pro ox_lib / ox_target carregarem
    Wait(800)
    lib.callback('aph_moneywash:server:getAllPersistent', false, function(list)
        if not list then return end
        for _, payload in ipairs(list) do
            spawnPersistentLocally(payload)
            Wait(50) -- evita spam de criação
        end
    end)
end)

-- =========================
-- 3D Text no gerador (cronômetro local)
-- =========================
CreateThread(function()
    while true do
        Wait((Config.Tick or 1000))
        for _, g in ipairs(spawned.generators) do
            local ent = NetworkGetEntityFromNetworkId(g.netId)
            if ent and DoesEntityExist(ent) then
                local st = Entity(ent).state.aph_gen
                if st then
                    local nowCloud = GetCloudTimeAsInt()
                    local rem = st.remaining or 0
                    if st.isOn then
                        rem = math.max(rem - math.max(nowCloud - (st.syncAt or nowCloud), 0), 0)
                    end
                    local ped = cache.ped or PlayerPedId()
                    if rem > 0 and #(GetEntityCoords(ped) - GetEntityCoords(ent)) < 10.0 then
                        local pos = GetEntityCoords(ent) + vec3(0.0, 0.0, 1.2)
                        local m = math.floor(rem / 60)
                        local s = rem % 60
                        DrawText3D(pos, ('Gerador (%s): %02d:%02d'):format(st.isOn and 'Ligado' or 'Desligado', m, s))
                    end
                end
            end
        end
    end
end)

-- =========================
-- DrawText3D helper
-- =========================
function DrawText3D(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextFont(0)
    SetTextProportional(0)
    SetTextScale(0.32, 0.32)
    SetTextColour(255, 255, 255, 215)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextCentre(1)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end