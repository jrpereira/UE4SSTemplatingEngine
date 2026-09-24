local Plan = require('ket.player_actions.plan')

return function(e)
    local contexts, actions = {}, {}
    local api = {}
    local options = {bIgnoreAllPressedKeysUntilRelease = true, bForceImmediately = false, bNotifyUserSettings = false}
    local names = {OW = 'IMC_Quickslots_OW', RTCombat = 'IMC_Quickslots_RTCombat'}
    local logicalNames = {OW = 'openworld', RTCombat = 'combat'}
    local function applies(definition, kind)
        if not definition.contexts then return true end
        for _, context in ipairs(definition.contexts) do
            if context == logicalNames[kind] then return true end
        end
        return false
    end
    local function valid(v) return e.valid(v) end
    local function context(kind)
        assert(names[kind], 'unknown quickslot context: ' .. tostring(kind))
        if not valid(contexts[kind]) then contexts[kind] = e.retain('InputMappingContext', names[kind]) end
        assert(valid(contexts[kind]), 'quickslots mapping context unavailable')
        return contexts[kind]
    end
    local function action(id)
        if not valid(actions[id]) then
            actions[id] = e.retain('InputAction', id)
            assert(valid(actions[id]), 'quickslots action unavailable: ' .. id)
            e.initializeIdentity(actions[id])
        end
        return actions[id]
    end
    local function trigger(a, mode)
        if mode == 2 then a.Triggers = {}; return end
        local t = e.retainTrigger(a, mode == 1 and 'InputTriggerHold' or 'InputTriggerTap')
        assert(valid(t), 'input trigger unavailable')
        if mode == 1 then t.HoldTimeThreshold=e.holdSeconds or .2; t.bIsOneShot=true else t.TapReleaseTimeThreshold=e.holdSeconds or .2 end
        a.Triggers = {t}
    end
    function api:configure(template, settings)
        local plan=Plan.build(template, settings, e.category); local current={}
        for _,d in ipairs(plan.actions) do
            local a=action(d.id); a.ValueType,a.bConsumeInput,a.bTriggerWhenPaused=0,false,false
            if d.binding.mode ~= -1 then trigger(a,d.binding.mode) else a.Triggers={} end
            current[d.id]=a
        end
        for kind in pairs(names) do
            local c=context(kind); c:UnmapAll()
            for _,d in ipairs(plan.actions) do if applies(d, kind) and d.binding.mode ~= -1 and d.binding.key ~= 0 then
                c:MapKey(current[d.id], {KeyName=e.name(assert(e.key(d.binding.key), 'unsupported key for '..d.id))})
            end end
        end
        self.plan,self.actions=plan,current; return current,plan
    end
    function api:attach(kind, subsystem, nativePriority)
        subsystem:AddMappingContext(context(kind), 1000 + assert(tonumber(nativePriority), 'native context priority required'), options)
        self.subsystems=self.subsystems or {}; self.subsystems[kind]=subsystem; return true
    end
    function api:detach(kind)
        local s=self.subsystems and self.subsystems[kind]
        if valid(s) and valid(contexts[kind]) then s:RemoveMappingContext(contexts[kind],options) end
        if self.subsystems then self.subsystems[kind]=nil end
        return true
    end
    return api
end
