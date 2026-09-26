local State = require('mc.target_state')
local Objects = require('mc.objects')
local copy = require('mc.util').copy
local TemplateTargets = require('mc.template_targets')
local M = {}

function M.new(template,specs,order)
    assert(type(template.attach)=='function', 'managed template requires attach')
    assert(template.requiredTargets==nil, 'use template.targets instead of requiredTargets')
    local tree=specs.children and specs or nil
    local states=setmetatable({}, {__mode='k'})
    local manager={}
    local function cleanup(state)
        local callbacks=state.cleanups or {}
        local failure
        for index=#callbacks,1,-1 do
            local ok,why=pcall(callbacks[index])
            if ok then table.remove(callbacks,index)
            else failure=failure or why end
        end
        if failure then error(failure,0) end
    end
    local function restore(state)
        cleanup(state)
        return State.restore(state.targets,specs,order,state.saved)
    end
    local function apply(root,targets,params,previous)
        if tree then
            local missing=TemplateTargets.missing(tree,targets,Objects.valid)
            if missing then return false,'not_ready: '..missing end
        else
            for _,name in ipairs(order) do
                if specs[name] and not Objects.valid(targets[name]) then return false,'not_ready: '..name end
            end
        end
        if previous then
            local ok,why=pcall(restore,previous)
            if not ok then previous.incomplete=true; return false,why end
        end
        local ok,saved=pcall(State.capture,targets,specs,order)
        if not ok then return false,saved end
        local state={targets=targets,saved=saved,params=copy(params),incomplete=true}
        states[root]=state
        local scoped=copy(params)
        state.cleanups={}
        scoped.onCleanup=function(callback)
            assert(type(callback)=='function','cleanup callback required')
            state.cleanups[#state.cleanups+1]=callback
        end
        local applied,originals,why=pcall(template.attach,targets,scoped,saved)
        if not applied or type(originals)~='table' then
            local restored,reason=pcall(restore,state)
            if restored then states[root]=previous end
            return false,tostring(applied and (why or 'attach must return original property values') or originals)
                ..(restored and '' or '; restoration failed: '..tostring(reason))
        end
        state.saved=originals
        state.incomplete=false
        return true
    end
    function manager:attach(root,targets,params)
        return apply(root,targets,params,states[root])
    end
    function manager:update(root,targets,params)
        local previous=states[root]
        local ok,why=apply(root,targets,params,previous)
        if ok then return true end
        if previous and not previous.incomplete then
            local recovered,reason=apply(root,previous.targets,previous.params,previous)
            if not recovered then why=tostring(why)..'; rollback failed: '..tostring(reason) end
        end
        return false,why
    end
    function manager:detach(root)
        local state=states[root]
        if not state then return true end
        local ok,why=pcall(restore,state)
        if not ok then return false,why end
        states[root]=nil
        return true
    end
    function manager:forget(root)
        if states[root] then cleanup(states[root]) end
        states[root]=nil
    end
    function manager:hasState(root)
        return states[root]~=nil
    end
    function manager:reset()
        local failure
        for root,state in pairs(states) do
            local ok,why=pcall(cleanup,state)
            if ok then states[root]=nil
            else failure=failure or why end
        end
        if failure then error(failure,0) end
    end
    return manager
end

return M
