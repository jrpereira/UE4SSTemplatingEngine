package.path = 'Scripts/?.lua;' .. package.path
local C, R = require('te.categories'), require('te.registry')
local L, M = require('te.lifecycle'), require('te.menu')
local checks = 0
local function check(v) assert(v); checks = checks + 1 end
local function rejects(fn, part)
    local ok, err = pcall(fn)
    assert(not ok and tostring(err):find(part, 1, true), tostring(err))
    checks = checks + 1
end
local categories = C.new(); categories:registerCategory('player', {'quickslots'})
local template = {collection = 'Robustness', name = 'Lifecycle', category = 'player.quickslots',
    settings={enabled=false},
    actions = {A = {name = 'Alpha', slots = 1, type = 'any'}, B = {name = 'Beta', slots = 2, type = 'any'}}}
local registry = R.new(categories, {execute = function() return template end})
registry:registerTemplate('fixture.lua'); registry:loadTemplatesFromRegister()
local identity = registry.templates[1].id
local runtime = L.new(registry)
local context = {playerActions = dofile('tests/support/service.lua')(),targets={['player.quickslots']={}}}
function template:attach(_, _, _, previous) return previous or {} end
function template:detach() return true end
function template:render() return 'applied' end
check(runtime:apply('player.quickslots', identity, {}, context))
local original = runtime.active['player.quickslots'].handle
template.attach = function() error('native attach exception') end
local ok, err = runtime:apply('player.quickslots', identity, {}, context)
check(not ok and err:find('native attach exception', 1, true))
check(runtime.active['player.quickslots'].handle == original)
template.detach = function() error('native detach exception') end
ok, err = runtime:detach('player.quickslots', context, 'none')
check(not ok and err:find('native detach exception', 1, true))
check(runtime.active['player.quickslots'].handle == original)
template.render = function() error('native render exception') end
check(not runtime:render('player.quickslots', context, {}, 'event'))
template.render = function() return 'invalid-status' end
check(not runtime:render('player.quickslots', context, {}, 'event'))
template.attach = function(_, _, _, _, previous)
    local applied, why = runtime:commit({revision = 99, values = {}}, function() return {} end, {})
    check(not applied and why == 'reentrant lifecycle operation')
    local nested, nestedWhy = runtime:detach('player.quickslots', {}, 'none')
    check(not nested and nestedWhy == 'reentrant lifecycle operation')
    return previous
end
check(runtime:apply('player.quickslots', identity, {}, context))
check(runtime.revision == 0 and runtime.active['player.quickslots'].handle == original)
template.detach = function() return true end
check(runtime:detach('player.quickslots', context, 'world_pre_unload'))
rejects(function() runtime:commit({revision = math.huge}, function() return {} end, {}) end, 'revision')
rejects(function() runtime:commit({revision = 1}, function() error('decode failure') end, {}) end, 'decode failure')
check(runtime.revision == 0)

local opts = {groupOrders = {[identity] = {'A', 'B'}}}
local base = M.generate(registry, opts)
for _, values in ipairs({{0}, {0, 0}, {0, math.huge}, {'0', 1}, {[1] = 0, [3] = 1}}) do
    rejects(function() M.generate(registry, {slotModeValues = values}) end, 'slot mode')
end
rejects(function() M.generate(registry, {catalog = {version = 1, next = 1000000002, entries = {}}}) end, 'catalog counter')
rejects(function() M.generate(registry, {catalog = {version = 1, next = 2, entries = {bad = 2}}}) end, 'catalog entry')
local reordered = M.generate(registry, {catalog = base.catalog, groupOrders = {[identity] = {'B', 'A'}}})
local selected = next(base.selectors['player.quickslots'].byValue)
local a, b = base.definitions['player.quickslots'][selected], reordered.definitions['player.quickslots'][selected]
check(a.direct.A[1].key == b.direct.A[1].key and a.groups.B.key == b.groups.B.key)
check(base.catalog.next == reordered.catalog.next)
local defaults = {}
for _, row in ipairs(base.rows) do defaults[row.Id] = tonumber(row.Default) end
defaults[base.selectors['player.quickslots'].id] = selected
defaults[a.shared[1].mode] = 2
rejects(function() base.decode(defaults) end, 'invalid choice')
defaults[a.shared[1].mode] = 1
defaults[a.groups.A.mode] = 1
rejects(function() base.decode(defaults) end, 'invalid choice')
defaults[a.groups.A.mode] = 2
check(base.decode(defaults)['player.quickslots'].configuration.groups.A.mode == 2)

-- Round-trip the catalog through a data-only Lua literal, like a host persistence adapter.
local keys = {}; for k in pairs(base.catalog.entries) do keys[#keys + 1] = k end; table.sort(keys)
local serialized = {'return {version=1,next=' .. base.catalog.next .. ',entries={'}
for _, k in ipairs(keys) do serialized[#serialized + 1] = string.format('[%q]=%d,', k, base.catalog.entries[k]) end
serialized[#serialized + 1] = '}}'
local restored = assert(load(table.concat(serialized, '\n'), 'catalog', 't', {}))()
local roundtrip = M.generate(registry, {catalog = restored, groupOrders = opts.groupOrders})
check(roundtrip.manifest == base.manifest)
print('robustness: ' .. checks .. ' checks passed')
