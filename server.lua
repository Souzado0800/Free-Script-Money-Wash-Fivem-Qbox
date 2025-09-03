-- server.lua (aph_moneywash) - com persistência via oxmysql

local ox_inv = exports.ox_inventory

-- === Config da lavagem (server-side) ===
local WASH_PERCENT  = 0.75
local WASH_DURATION = 30

-- === In-memory maps ===
-- genStates[dbId] = { remaining, isOn, lastTick, owner, coords, model, heading, netId? }
local genStates = {}
-- map para achar dbId a partir do netId e vice-versa
local genByNet = {}   -- [netId] = dbId
local netByGen = {}   -- [dbId] = netId

-- stations[dbId] = { model, coords, heading, owner, netId? }
local stations = {}
local staByNet = {}
local netBySta = {}

-- lavagens somente em memória (caso não queira persistir). Se quiser persistir, usamos tabela.
local washes = {}  -- washes[src] = { clean, endTime }

-- =========================
-- Utils
-- =========================
local function now() return os.time() end

local function getLicense(src)
  for _, id in ipairs(GetPlayerIdentifiers(src)) do
    if id:sub(1,8) == "license:" then
      return id
    end
  end
  return nil
end

local function updateGeneratorClock(dbId)
  local st = genStates[dbId]
  if not st then return end
  local t = now()
  if st.isOn and st.lastTick then
    local delta = t - st.lastTick
    if delta > 0 then
      st.remaining = math.max((st.remaining or 0) - delta, 0)
    end
  end
  st.lastTick = t
end

local function broadcastGenStateByDbId(dbId)
  local st = genStates[dbId]
  if not st then return end
  local netId = netByGen[dbId]
  if not netId then return end
  TriggerClientEvent('aph_moneywash:client:updateGenState', -1, netId, {
    remaining = st.remaining or 0,
    isOn = st.isOn and true or false,
    syncAt = now()
  })
end

local function persistGenerator(dbId)
  local st = genStates[dbId]
  if not st then return end
  MySQL.update.await(
    'UPDATE aph_moneywash_generators SET remaining = ?, is_on = ?, x = ?, y = ?, z = ?, heading = ? WHERE id = ?',
    { st.remaining or 0, st.isOn and 1 or 0, st.coords.x, st.coords.y, st.coords.z, st.heading or 0.0, dbId }
  )
end

-- =========================
-- LOAD NA INICIALIZAÇÃO
-- =========================
AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end

  -- carrega geradores
  local rows = MySQL.query.await('SELECT * FROM aph_moneywash_generators', {})
  for _, r in ipairs(rows or {}) do
    genStates[r.id] = {
      remaining = tonumber(r.remaining) or 0,
      isOn = (tonumber(r.is_on) or 0) == 1,
      lastTick = now(),
      owner = r.owner_license,
      coords = { x = r.x, y = r.y, z = r.z },
      model = r.model or 'prop_generator_03b',
      heading = tonumber(r.heading) or 0.0
    }
    -- pede pros clients spawnarem; link volta via evento
    TriggerClientEvent('aph_moneywash:client:spawnPersistent', -1, {
      type = 'generator',
      dbId = r.id,
      model = genStates[r.id].model,
      coords = genStates[r.id].coords,
      heading = genStates[r.id].heading,
      state = { remaining = genStates[r.id].remaining, isOn = genStates[r.id].isOn }
    })
  end

  -- carrega estações
  local rows2 = MySQL.query.await('SELECT * FROM aph_moneywash_stations', {})
  for _, r in ipairs(rows2 or {}) do
    stations[r.id] = {
      model = r.model or 'prop_cash_depot',
      coords = { x = r.x, y = r.y, z = r.z },
      heading = tonumber(r.heading) or 0.0,
      owner = r.owner_license
    }
    TriggerClientEvent('aph_moneywash:client:spawnPersistent', -1, {
      type = 'station',
      dbId = r.id,
      model = stations[r.id].model,
      coords = stations[r.id].coords,
      heading = stations[r.id].heading
    })
  end

  -- (opcional) reconstituir lavagens ativas do DB
  local rows3 = MySQL.query.await('SELECT * FROM aph_moneywash_washes', {})
  for _, r in ipairs(rows3 or {}) do
    -- não sabemos o src atual deste license; quando o player logar, podemos reconciliar se quiser
    -- por simplicidade, vamos dropar pendências passadas do prazo
    local t = now()
    if r.end_time_unix > t then
      -- pendente; quando o dono conectar, podemos creditá-lo
      -- (fora do escopo aqui; deixo a tabela pronta)
    else
      -- já expirou: remover
      MySQL.query.await('DELETE FROM aph_moneywash_washes WHERE id = ?', { r.id })
    end
  end
end)

-- Salva tudo ao parar
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  for dbId, st in pairs(genStates) do
    updateGeneratorClock(dbId)
    persistGenerator(dbId)
  end
end)

-- Autosave periódico (a cada 60s)
CreateThread(function()
  while true do
    Wait(60000)
    for dbId, _ in pairs(genStates) do
      updateGeneratorClock(dbId)
      persistGenerator(dbId)
    end
  end
end)

-- =========================
-- REGISTROS E AÇÕES DO GERADOR
-- =========================

-- Cliente terminou de spawnar um persistente; linka netId <-> dbId
RegisterNetEvent('aph_moneywash:server:linkPersistent', function(dbId, netId, kind)
  if kind == 'generator' then
    netByGen[dbId] = netId
    genByNet[netId] = dbId
    -- sincroniza estado atual
    broadcastGenStateByDbId(dbId)
  elseif kind == 'station' then
    netBySta[dbId] = netId
    staByNet[netId] = dbId
  end
end)

-- Registro de gerador novo (colocado por item): insere no DB e em memória
RegisterNetEvent('aph_moneywash:server:registerGenerator', function(netId, coords)
  local src = source
  if not netId or not coords then return end

  local license = getLicense(src)
  local model = (Config.Props and Config.Props.GeneratorProp) or 'prop_generator_03b'
  local heading = 0.0 -- cliente já define orientação no spawn; podemos capturar depois se quiser

  local ins = MySQL.insert.await(
    'INSERT INTO aph_moneywash_generators (model, x, y, z, heading, remaining, is_on, owner_license) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    { model, coords.x, coords.y, coords.z, heading, 0, 0, license }
  )
  if not ins then return end

  genStates[ins] = {
    remaining = 0, isOn = false, lastTick = now(),
    owner = license,
    coords = coords, model = model, heading = heading
  }
  netByGen[ins] = netId
  genByNet[netId] = ins

  broadcastGenStateByDbId(ins)
end)

-- Registro de estação nova (colocada por item): insere no DB e em memória
RegisterNetEvent('aph_moneywash:server:registerStation', function(coords, heading)
  local src = source
  if not coords then return end
  local license = getLicense(src)
  local model = (Config.Props and Config.Props.MoneywashProp) or 'prop_cash_depot'
  local head = heading or 0.0

  local ins = MySQL.insert.await(
    'INSERT INTO aph_moneywash_stations (model, x, y, z, heading, owner_license) VALUES (?, ?, ?, ?, ?, ?)',
    { model, coords.x, coords.y, coords.z, head, license }
  )
  if not ins then return end

  stations[ins] = { model = model, coords = coords, heading = head, owner = license }
  -- nada de estado pra sincronizar
end)

-- Abastecimento: remove 1 a 1 e persiste
RegisterNetEvent('aph_moneywash:server:fuelGenerator', function(netId, cans)
  local src = source
  if not netId then return end
  local dbId = genByNet[netId]; if not dbId then return end

  local req = math.floor(tonumber(cans or 1) or 1)
  if req <= 0 then
    TriggerClientEvent('ox_lib:notify', src, { type='error', title='Gerador', description='Quantidade inválida.' })
    return
  end

  local fuelItem = (Config.Items and Config.Items.FuelItem) or 'gasoline'
  local perCanSeconds = ((Config.MinutesPerCan or 10) * 60)

  local consumed = 0
  for i = 1, req do
    local ok = ox_inv:RemoveItem(src, fuelItem, 1)
    if not ok then break end
    consumed = consumed + 1
  end

  if consumed == 0 then
    TriggerClientEvent('ox_lib:notify', src, { type='error', title='Gerador', description='Você não tem gasolina suficiente.' })
    return
  end

  updateGeneratorClock(dbId)
  local st = genStates[dbId]
  st.remaining = (st.remaining or 0) + perCanSeconds * consumed
  persistGenerator(dbId)

  TriggerClientEvent('ox_lib:notify', src, {
    type='success', title='Gerador',
    description=string.format('Abastecido: +%d min (%d galão(ões))', (Config.MinutesPerCan or 10) * consumed, consumed)
  })
  broadcastGenStateByDbId(dbId)
end)

-- Liga/Desliga e persiste
RegisterNetEvent('aph_moneywash:server:toggleGenerator', function(netId, desiredState)
  local src = source
  if not netId then return end
  local dbId = genByNet[netId]; if not dbId then return end

  updateGeneratorClock(dbId)
  local st = genStates[dbId]
  if (st.remaining or 0) <= 0 and desiredState == true then
    TriggerClientEvent('ox_lib:notify', src, { type='error', title='Gerador', description='Sem combustível suficiente para ligar.' })
    return
  end

  st.isOn = desiredState and true or false
  st.lastTick = now()
  persistGenerator(dbId)

  TriggerClientEvent('ox_lib:notify', src, {
    type = st.isOn and 'success' or 'inform',
    title = 'Gerador',
    description = st.isOn and 'Ligado.' or 'Desligado.'
  })
  broadcastGenStateByDbId(dbId)
end)

-- Existe gerador LIGADO e com tempo > 0 a X metros?
lib.callback.register('aph_moneywash:server:isPoweredNearby', function(src, playerPos)
  if not playerPos then return false, nil end
  local linkDist = (Config.LinkDistance or 15.0)
  local linkDist2 = linkDist * linkDist

  for dbId, st in pairs(genStates) do
    updateGeneratorClock(dbId)
    if st.isOn and (st.remaining or 0) > 0 and st.coords then
      local dx = (st.coords.x - playerPos.x)
      local dy = (st.coords.y - playerPos.y)
      local dz = (st.coords.z - playerPos.z)
      local dist2 = dx*dx + dy*dy + dz*dz
      if dist2 <= linkDist2 then
        return true, st.remaining
      end
    end
  end
  return false, nil
end)

-- =========================
-- LAVAGEM (igual antes; opcional persistir em DB)
-- =========================
RegisterNetEvent('aph_moneywash:server:startWash', function(amount)
  local src = source
  amount = tonumber(amount or 0) or 0
  if amount <= 0 then
    TriggerClientEvent('ox_lib:notify', src, { type='error', title='Lavagem', description='Valor inválido.' })
    return
  end

  local has = ox_inv:Search(src, 'count', 'black_money')
  if (has or 0) < amount then
    TriggerClientEvent('ox_lib:notify', src, { type='error', title='Lavagem', description='Você não tem essa quantia de dinheiro sujo.' })
    return
  end

  ox_inv:RemoveItem(src, 'black_money', amount)

  local cleanAmount = math.floor(amount * WASH_PERCENT)
  local readyAt = now() + WASH_DURATION

  washes[src] = { clean = cleanAmount, endTime = readyAt }

  -- (opcional) persistir:
  -- local license = getLicense(src)
  -- MySQL.insert.await('INSERT INTO aph_moneywash_washes (owner_license, clean_amount, end_time_unix) VALUES (?, ?, ?)',
  --   { license, cleanAmount, readyAt })

  TriggerClientEvent('ox_lib:notify', src, {
    type='inform', title='Lavagem',
    description=string.format('Lavando $%d... aguarde %d segundos.', amount, WASH_DURATION)
  })
end)

RegisterNetEvent('aph_moneywash:server:collectClean', function()
  local src = source
  local state = washes[src]
  if not state then
    TriggerClientEvent('ox_lib:notify', src, { type='error', title='Lavagem', description='Nenhuma lavagem em andamento.' })
    return
  end

  local t = now()
  if t < state.endTime then
    local rem = state.endTime - t
    TriggerClientEvent('ox_lib:notify', src, { type='warning', title='Lavagem', description=string.format('Ainda faltam %d seg.', rem) })
    return
  end

  ox_inv:AddItem(src, 'money', state.clean)
  washes[src] = nil

  -- (opcional) apagar do DB se você persistiu:
  -- local license = getLicense(src)
  -- MySQL.query.await('DELETE FROM aph_moneywash_washes WHERE owner_license = ? AND end_time_unix <= ?', { license, now() })

  TriggerClientEvent('ox_lib:notify', src, { type='success', title='Lavagem', description=string.format('Você recebeu $%d em dinheiro limpo.', state.clean) })
end)

lib.callback.register('aph_moneywash:server:getWashInfo', function(src)
  local state = washes[src]
  local t = now()

  local remaining = 0
  local clean = 0
  if state then
    remaining = math.max((state.endTime or t) - t, 0)
    clean = state.clean or 0
  end

  return {
    percent = math.floor(WASH_PERCENT * 100),
    duration = WASH_DURATION,
    hasActive = state ~= nil,
    remaining = remaining,
    clean = clean
  }
end)

-- =========================
-- CONSUMO DE KITS (moneywash_kit / generator_kit)
-- =========================
lib.callback.register('aph_moneywash:server:consumeKit', function(src, kind)
  local item = (kind == 'generator')
    and ((Config.Items and Config.Items.GeneratorItem) or 'generator_kit')
    or  ((Config.Items and Config.Items.MoneywashItem)  or 'moneywash_kit')

  local has = ox_inv:Search(src, 'count', item)
  if (has or 0) <= 0 then return false end
  local ok = ox_inv:RemoveItem(src, item, 1)
  return ok and true or false
end)

-- 🔄 Callback para sincronização completa após restart/entrada do player
lib.callback.register('aph_moneywash:server:getAllPersistent', function(src)
    -- Carrega direto do banco para evitar qualquer drift
    local gens = MySQL.query.await('SELECT id, model, x, y, z, heading, remaining, is_on FROM aph_moneywash_generators', {}) or {}
    local stas = MySQL.query.await('SELECT id, model, x, y, z, heading FROM aph_moneywash_stations', {}) or {}

    -- Monta payloads no formato que o client já entende
    local list = {}

    for _, r in ipairs(gens) do
        table.insert(list, {
            type   = 'generator',
            dbId   = r.id,
            model  = r.model or 'prop_generator_03b',
            coords = { x = r.x, y = r.y, z = r.z },
            heading= tonumber(r.heading) or 0.0,
            state  = {
                remaining = tonumber(r.remaining) or 0,
                isOn      = (tonumber(r.is_on) or 0) == 1
            }
        })
    end

    for _, r in ipairs(stas) do
        table.insert(list, {
            type   = 'station',
            dbId   = r.id,
            model  = r.model or 'prop_cash_depot',
            coords = { x = r.x, y = r.y, z = r.z },
            heading= tonumber(r.heading) or 0.0
        })
    end

    return list
end)
