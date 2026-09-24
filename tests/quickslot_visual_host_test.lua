package.path = 'Scripts/?.lua;' .. package.path
local VisualHost = require('ket.quickslot_visual_host')

local calls, ready = {}, false
local runtime = {active = {}, pending = {}}
function runtime:apply(category, identity, settings, context)
    assert(category == 'player.quickslots' and context.playerActions)
    calls[#calls + 1] = identity and 'apply:' .. identity or 'clear'
    if not identity then self.active[category], self.pending[category] = nil, nil; return true end
    if not ready then
        self.pending[category] = {id = identity, settings = settings}
        return true, 'not_ready'
    end
    self.active[category] = {id = identity, settings = settings}
    self.pending[category] = nil
    return true
end
function runtime:retry(category, context)
    calls[#calls + 1] = 'retry'
    local pending = assert(self.pending[category])
    return self:apply(category, pending.id, pending.settings, context)
end
function runtime:detach(category, context, reason)
    assert(reason == 'world_invalidated' and context.playerActions)
    calls[#calls + 1] = 'invalidate'
    self.active[category], self.pending[category] = nil, nil
    return true
end

local host = VisualHost.new(runtime, {})
local selected, why = host:select({id = 'actionbars', settings = {Layout = 2}})
assert(selected and why == 'not_ready' and runtime.pending['player.quickslots'])
ready = true
assert(host:wake() and runtime.active['player.quickslots'].settings.Layout == 2)
assert(host:wake() and #calls == 3, 'an active visual must not reattach on every wake')
assert(host:worldInvalidated() and runtime.active['player.quickslots'].id == 'actionbars')
assert(table.concat(calls, ',') ==
    'apply:actionbars,retry,apply:actionbars,invalidate,apply:actionbars')
host:adopt(nil)
assert(host:wake() and #calls == 5)
assert(host:select(nil) and runtime.active['player.quickslots'] == nil)
print('Quickslot visual host activates, retries, and restores the action bars example')
