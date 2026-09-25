-- UE4SS event source for live category selectors. Install while main.lua is
-- loading, before game-thread startup.
local ObjectSelector = require('mct.object_selector')
local M = {}
local function safe(object, method, ...)
    return ObjectSelector.call(object, method, ...)
end
local function unwrap(value)
    if value == nil then return nil end
    local ok, object = pcall(function() return value:get() end)
    return ok and object or value
end
local function isa(object, class)
    return safe(object, 'IsA', class) == true or safe(object, 'IsA', 'Class ' .. class) == true
end
local function eventClass(selector)
    local class = ObjectSelector.className(selector)
    if selector.class then return selector.class end
    local owner = selector.object:match('^%S+%s+(.-):WidgetTree%.[%w_]+$')
    if owner then return owner, '/Script/UMG.' .. class end
end
function M.new(categories, api)
    api = api or _G
    for _, name in ipairs({'FindAllOf','NotifyOnNewObject','RegisterHook','UnregisterHook',
        'RegisterLoadMapPreHook','RegisterLoadMapPostHook','IsInGameThread'}) do
        assert(type(api[name]) == 'function', 'UE4SS object source requires ' .. name)
    end
    local source = {}
    local selectors, notifyClasses, hasGroups, hasWidgets = {}, {}, false, false
    for _, category in ipairs(categories) do
        for _, selector in pairs(category.targets or {}) do
            ObjectSelector.className(selector)
            selectors[#selectors+1] = selector
            if selector.within then hasGroups = true end
            if selector.object and selector.object:find(':WidgetTree.',1,true)
                or selector.class and selector.class:find('/Script/UMG.',1,true) then
                hasWidgets = true
            end
            local first, second = eventClass(selector)
            if first then notifyClasses[first] = true end
            if second then notifyClasses[second] = true end
        end
    end
    local known = setmetatable({}, {__mode='k'})
    local built = {}
    local sink, getEpoch, subscribed, active = nil, nil, false, true
    local loading, currentWorld, generation = false, nil, 1
    local hooks = {}
    local function errorReport(stage, message)
        local error = {stage=stage,message=tostring(message)}
        if type(api.MCTOnError)=='function' then pcall(api.MCTOnError,error)
        else print('[MCT] ' .. error.stage .. ': ' .. error.message) end
    end
    source.onError = function(error) errorReport(error.stage or 'object', error.message) end
    local function onGameThread()
        return api.IsInGameThread() == true
    end
    local function token(object)
        if not ObjectSelector.valid(object) then return nil end
        local address = safe(object,'GetAddress')
        if type(address) ~= 'number' then return nil end
        local name = safe(object,'GetFullName')
        if type(name) ~= 'string' then return nil end
        return tostring(generation) .. ':' .. tostring(address) .. ':' .. name
    end
    source.identity = token
    local function world(object)
        local value = safe(object,'GetWorld')
        return ObjectSelector.valid(value) and value or nil
    end
    local function sameWorld(object)
        if not currentWorld then return true end
        local value = world(object)
        return value ~= nil and safe(value,'GetAddress') == currentWorld.address
            and token(value) == currentWorld.token
    end
    function source.valid(object)
        if not ObjectSelector.valid(object) then return false end
        local full = safe(object,'GetFullName')
        return type(full) == 'string' and not full:find('Default__',1,true)
            and not full:find('REINST_',1,true)
    end
    function source.ready(object)
        if loading or not source.valid(object) then return false end
        if isa(object,'/Script/UMG.Widget') then
            local owner = isa(object,'/Script/UMG.UserWidget') and object or ObjectSelector.owner(object)
            if not source.valid(owner) or not sameWorld(owner) then return false end
            local ownerToken = token(owner)
            if not ownerToken then return false end
            local parent = source.parent(object)
            local parented = source.valid(parent)
            if owner ~= object and not parented then
                -- Only the WidgetTree root may be parentless while its owner is
                -- in the viewport. A removed child must lose readiness.
                local ok, root = pcall(function() return owner.WidgetTree.RootWidget end)
                if not ok or not source.valid(root)
                    or safe(root,'GetAddress') ~= safe(object,'GetAddress') then return false end
            end
            if built[ownerToken] == false then return false end
            if built[ownerToken] == true then return true end
            -- Nested game HUDs are children of another UserWidget. IsInViewport
            -- is unavailable for them in Dawnwalker; a live world and panel
            -- parent establish readiness for a WidgetTree child.
            return safe(owner,'IsInViewport') == true or parented
        end
        return world(object) ~= nil and sameWorld(object)
    end
    function source.matches(object, selector)
        return source.valid(object) and ObjectSelector.matches(object, selector)
    end
    function source.parent(object)
        if not source.valid(object) then return nil end
        local parent
        if isa(object,'/Script/UMG.Widget') then parent = safe(object,'GetParent')
        else parent = safe(object,'GetOuter') end
        return source.valid(parent) and parent or nil
    end
    function source.find(selector)
        assert(onGameThread(), 'object discovery requires the game thread')
        -- UE4SS returns nil when a blueprint class is not loaded yet.
        local found = api.FindAllOf(ObjectSelector.className(selector)) or {}
        assert(type(found)=='table', 'FindAllOf returned a non-array value')
        local result = {}
        for _, object in ipairs(found) do
            if source.matches(object, selector) then
                result[#result+1] = object
                known[object] = true
            end
        end
        return result
    end
    local function emit(kind, object)
        if not active or not sink then return end
        if not onGameThread() then
            errorReport('object-event', 'UE4SS delivered a lifecycle event off the game thread')
            return
        end
        sink({kind=kind,object=object,epoch=getEpoch()})
    end
    local function changed(object)
        if not source.valid(object) then return end
        known[object] = true
        emit('changed',object)
    end
    local function wakeKnown()
        for object in pairs(known) do
            if source.valid(object) then emit('changed',object) end
        end
    end
    local function hook(path, before, after)
        local pre, post = api.RegisterHook(path,before,after)
        assert(type(pre)=='number' and type(post)=='number', 'invalid hook IDs: '..path)
        hooks[#hooks+1] = {path=path,pre=pre,post=post}
    end
    local function install()
        for class in pairs(notifyClasses) do
            api.NotifyOnNewObject(class,function(object)
                if not active then return end
                local current = unwrap(object)
                if source.valid(current) then changed(current) end
            end)
        end
        -- Verified in the installed UE4SS build: Construct/Destruct and
        -- OnInitialized reject RegisterHook, but these viewport methods work.
        for _, name in ipairs({'AddToViewport','AddToPlayerScreen'}) do
            hook('/Script/UMG.UserWidget:'..name,function() end,function(context)
                if not active then return end
                local id = token(unwrap(context))
                if id then built[id] = true; wakeKnown() end
            end)
        end
        hook('/Script/UMG.Widget:RemoveFromParent',function(context)
            if not active then return end
            local owner = unwrap(context)
            if isa(owner,'/Script/UMG.UserWidget') then
                local id = token(owner)
                if id then built[id] = false; wakeKnown() end
            end
        end,function()
            if active then wakeKnown() end
        end)
        if hasGroups or hasWidgets then
            -- A removed UserWidget is unready until it joins a panel again.
            hook('/Script/UMG.PanelWidget:AddChild',function() end,function(_, childParam)
                if not active then return end
                local child = unwrap(childParam)
                if source.valid(child) then
                    if isa(child,'/Script/UMG.UserWidget') then
                        local id = token(child)
                        if id then built[id] = nil end
                    end
                    for _, selector in ipairs(selectors) do
                        if source.matches(child,selector) then
                            known[child] = true
                            break
                        end
                    end
                end
                wakeKnown()
            end)
            for _, name in ipairs({'RemoveChild','ClearChildren'}) do
                hook('/Script/UMG.PanelWidget:'..name,function() end,function()
                    if active then wakeKnown() end
                end)
            end
        end
        api.RegisterLoadMapPreHook(function()
            if not active then return end
            loading, currentWorld, built = true, nil, {}
            wakeKnown() -- detach while old references are still valid
        end)
        api.RegisterLoadMapPostHook(function(_, worldParam)
            if not active then return end
            generation = generation + 1
            local current = unwrap(worldParam)
            local id = token(current)
            emit('world_invalidated')
            if not id then
                errorReport('world', 'map completed without a valid current world')
                return
            end
            currentWorld = {address=safe(current,'GetAddress'),token=id}
            loading = false
            emit('world_ready')
        end)
    end
    local ok, why = pcall(install)
    if not ok then
        active = false
        for i=#hooks,1,-1 do
            local h=hooks[i]; pcall(api.UnregisterHook,h.path,h.pre,h.post)
        end
        error('object source hook installation failed: '..tostring(why))
    end
    function source.subscribe(callback, epoch)
        assert(active and not subscribed, 'object source already subscribed or stopped')
        assert(type(callback)=='function' and type(epoch)=='function', 'object sink and epoch required')
        sink, getEpoch, subscribed = callback, epoch, true
        return function() sink, getEpoch, subscribed = nil,nil,false end
    end
    function source.stop()
        if not active then return end
        active, sink, getEpoch, subscribed = false,nil,nil,false
        for i=#hooks,1,-1 do
            local h=hooks[i]; pcall(api.UnregisterHook,h.path,h.pre,h.post)
        end
    end
    return source
end
return M
