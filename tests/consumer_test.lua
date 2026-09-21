package.path = 'Scripts/?.lua;' .. package.path
local TE = require('te.init')
local checks = 0
local function check(value) assert(value); checks = checks + 1 end
local path = assert(os.getenv('TE_QSF_TEMPLATE'), 'TE_QSF_TEMPLATE required for actual consumer boundary tests')
local te = TE.new({listFiles = function() return {} end})
te:registerTemplate(path)
check(te:loadTemplatesFromRegister() == 1)
local entry = te.registry.templates[1]
-- Explicit test-only order; does not modify or approve the production definition.
local menu = te:generateMenu({groupOrders = {[entry.id] = {'Consumables', 'Abilities', 'Extra'}}})
local selector = menu.selectors['player.actions']
local selected = next(selector.byValue)
local definition = menu.definitions['player.actions'][selected]
local values = {}; for _, row in ipairs(menu.rows) do values[row.Id] = tonumber(row.Default) end
values[selector.id] = selected
values[definition.access], values[definition.firstDefault] = 1, 1
values[definition.shared[1].mode], values[definition.groups.Abilities.mode] = 1, 2
local attached, detached, rendered = 0, 0, 0
local context = {quickslotsForever = {
    attach = function(_, template, spec, previous)
        check(template == entry.template)
        check(spec.access == 1 and spec.firstGroupDefault)
        check(spec.shared[1].mode == 1 and spec.groups.Abilities.mode == 2)
        attached = attached + 1
        return previous or {token = 'test'}
    end,
    detach = function(_, template, handle, reason)
        check(template == entry.template and handle.token == 'test' and reason == 'none')
        detached = detached + 1; return true
    end,
    render = function(_, template, handle, target, reason)
        check(template == entry.template and handle.token == 'test' and target.kind == 'hud' and reason == 'created')
        rendered = rendered + 1; return 'applied'
    end,
}}
check(te.runtime:commit({revision = 1, values = values}, menu.decode, context))
check(te.runtime:commit({revision = 2, values = values}, menu.decode, context))
check(te.runtime:render('player.actions', context, {kind = 'hud'}, 'created') == 'applied')
values[selector.id] = 0
check(te.runtime:commit({revision = 3, values = values}, menu.decode, context))
check(attached == 2 and detached == 1 and rendered == 1)
print('consumer: ' .. checks .. ' checks passed using actual QSF template and injected services')
