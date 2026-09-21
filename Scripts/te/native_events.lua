local M={}

function M.new(api,queue)
    api=api or _G
    queue=queue or assert(api.ExecuteInGameThread,'ExecuteInGameThread unavailable')
    local self={}
    function self.subscribe(category,event,callback)
        assert(type(category)=='string' and type(event)=='table' and type(event.name)=='string',
            'structured event declaration required')
        assert(type(callback)=='function','event callback required')
        assert(event.name=='created','native event host only supports created')
        assert(event.path,'native event declaration requires path')
        local active=true
        local ok,why=pcall(assert(api.NotifyOnNewObject,'NotifyOnNewObject unavailable'),event.path,function(object)
            if not active then return end
            queue(function()
                if not active then return end
                local unwrapped,value=pcall(function() return object:get() end)
                callback(unwrapped and value or object)
            end)
        end)
        if not ok then error('class creation subscription failed for '..event.path..': '..tostring(why)) end
        return function() active=false end
    end
    return self
end

return M
