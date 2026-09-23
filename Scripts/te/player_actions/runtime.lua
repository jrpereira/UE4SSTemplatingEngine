-- Coordinates generated mappings with reversible suppression of the former
-- QSF actions. The caller passes ready=true only after it has bound callbacks
-- for every generated action; this prevents a partial cutover from stranding
-- player input.
local InputContext = require('te.player_actions.input_context')
local Gates = require('te.player_actions.action_gates')

return function(e)
    e.input.category = e.category
    local input = InputContext(e.input)
    local native = {}
    for _, path in ipairs(e.nativeTargets) do
        local action = e.resolve(path)
        if e.valid(action) then native[#native + 1] = action end
    end
    local gates = Gates({
        marker = 'TE_NativeActionGate', valid = e.valid, path = e.path, unwrap = e.unwrap,
        same = e.same, each = e.each, actions = function() return native end,
        retainInactive = e.retainInactive, construct = e.constructGate,
        chord = e.chord, setChord = e.setChord, setTriggers = e.setTriggers, rebuild = e.rebuild,
    })
    local api = {}
    function api:prepare(template, settings)
        return input:configure(template, settings)
    end
    function api:commit(kind, subsystem, nativePriority)
        input:attach(kind, subsystem, nativePriority)
        local ok, why = pcall(function() self:ready() end)
        if not ok then
            input:detach(kind)
            pcall(function() gates:restoreAll() end)
            error(why, 0)
        end
        self.active = self.active or {}
        self.active[kind] = true
        return true
    end
    function api:activate(template, settings, subsystem, kind, nativePriority, ready)
        local actions, plan = self:prepare(template, settings)
        if ready ~= true then return actions, plan, 'bindings_pending' end
        self:commit(kind, subsystem, nativePriority)
        return actions, plan, 'applied'
    end
    function api:ready()
        gates:update(function() return true end)
        return true
    end
    function api:deactivate(kind)
        input:detach(kind)
        self.active = self.active or {}
        self.active[kind] = nil
        if next(self.active) == nil then gates:restoreAll() end
        return true
    end
    return api
end
