local U = require('te.util')
local M = {}

local indicatorClass='/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatTargetIndicator.WBP_CombatTargetIndicator_C'
local contracts={
    ['player.quickslots']={requiresTarget=true,events={GroupSelected=true,SlotActivated=true}},
    ['npc.attacks']={requiresTarget=true,events={created=true},paths={[indicatorClass]=true},contexts={combat=true}},
}

function M.declarations(category,events,subscribe,where)
    where=where or category
    local contract=contracts[category] or {events={}}
    if contract.paths then
        assert(events==nil,where..'.events: use subscribe for '..category)
        assert(subscribe~=nil,where..': subscribe is required for '..category)
    else
        assert(subscribe==nil,where..'.subscribe: unsupported for '..category)
        if events==nil then return {} end
    end
    local sourceList=contract.paths and subscribe or events
    local field=contract.paths and 'subscribe' or 'events'
    local count=U.array(sourceList,where..'.'..field)
    local result,seen={},{}
    for index=1,count do
        local source=sourceList[index]
        if type(source)=='string' then
            U.text(source,where..'.'..field..'['..index..']')
            assert(not contract.paths,where..': '..category..' requires target event declarations')
            assert(contract.events[source],where..': unsupported '..category..' event '..source)
            assert(not seen[source],where..': duplicate event '..source);seen[source]=true
            result[#result+1]={name=source}
        else
            local loc=where..'.'..field..'['..index..']'
            assert(type(source)=='table',loc..': expected target event declaration')
            for key in pairs(source) do
                assert(key=='path' or key=='events' or key=='contexts',loc..': unsupported property '..tostring(key))
            end
            U.text(source.path,loc..'.path')
            assert(contract.paths and contract.paths[source.path],loc..': unsupported '..category..' path '..source.path)
            local contextCount=U.array(source.contexts,loc..'.contexts')
            local contexts={}
            for contextIndex=1,contextCount do
                local context=source.contexts[contextIndex];U.text(context,loc..'.contexts['..contextIndex..']')
                assert(contract.contexts[context],loc..': unsupported context '..context)
                contexts[#contexts+1]=context
            end
            local eventCount=U.array(source.events,loc..'.events')
            for eventIndex=1,eventCount do
                local name=source.events[eventIndex];U.text(name,loc..'.events['..eventIndex..']')
                assert(contract.events[name],loc..': unsupported '..category..' event '..name)
                local identity=source.path..'\0'..name
                assert(not seen[identity],where..': duplicate event '..name..' for '..source.path)
                seen[identity]=true
                result[#result+1]={name=name,path=source.path,contexts=contexts}
            end
        end
    end
    return result
end

function M.validate(category,events,subscribe,where)
    return M.declarations(category,events,subscribe,where)
end

function M.supports(category, event)
    return contracts[category] ~= nil and contracts[category].events[event] == true
end

function M.requiresTarget(category)
    return contracts[category] ~= nil and contracts[category].requiresTarget == true
end

function M.active(declaration,context)
    local required=declaration.contexts
    if required==nil or #required==0 then return true end
    local active=type(context)=='table' and context.contexts or nil
    if type(active)~='table' then return false end
    local indexed={}
    for key,value in pairs(active) do
        if type(key)=='number' then indexed[value]=true elseif value then indexed[key]=true end
    end
    for _,name in ipairs(required) do if indexed[name] then return true end end
    return false
end

function M.interested(template, event)
    for _,declared in ipairs(M.declarations(template.category,template.events,template.subscribe,template.name)) do
        if declared.name == event then return true end
    end
    return false
end

return M
