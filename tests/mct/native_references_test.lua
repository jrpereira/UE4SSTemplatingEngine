package.path = './Scripts/?.lua;' .. package.path
local References = require('mct.native_references')
local Runtime = require('mct.runtime')
local passed = 0
local function test(name, body)
    local ok, why = pcall(body); assert(ok, name .. ': ' .. tostring(why)); passed=passed+1
end
local function setup()
    local live, lost, objects, nextToken = {}, {}, {}, 0
    local native = {version=1}
    function native.capture(address)
        if not objects[address] then return nil end
        if not live[address] then nextToken=nextToken+1; live[address]=tostring(nextToken) end
        return live[address]
    end
    function native.valid(address, token) return live[address] == token end
    function native.takeLost() return table.remove(lost, 1) end
    local api = {reads=0, events={}, calls={}}
    function api.create(address, parent)
        local object = {address=address, parent=parent, ready=false}
        function object:GetAddress() return self.address end
        objects[address]=object; return object
    end
    function api.destroy(object)
        local token=live[object.address]
        if token then lost[#lost+1]=token end
        live[object.address], objects[object.address]=nil,nil
    end
    local source = {}
    function source.valid(object)
        api.reads=api.reads+1
        assert(objects[object.address] == object, 'touched a destroyed UObject')
        return true
    end
    function source.ready(object) return object.ready end
    function source.matches() return true end
    function source.parent(object) return object.parent end
    function source.find() local result={}; for _,v in pairs(objects) do result[#result+1]=v end; return result end
    function source.subscribe(sink, epoch)
        api.emit=function(kind, object, captured)
            sink({kind=kind,object=object,epoch=captured or epoch()})
        end
        return function() api.stopped=true end
    end
    function source.onError(error) api.events[#api.events+1]=error end
    api.source=source
    api.host=References.new(source, native)
    function api.runtime(path)
        local template = {id='t',category='c',settings={template=true}}
        for _,method in ipairs({'attach','update','detach'}) do
            template[method]=function(object,settings) api.calls[#api.calls+1]={method,object,settings} end
        end
        local runtime=Runtime.new(api.host,{{name='c',targets=path or {all={class='Widget'}},settings={category=true}}},{template})
        runtime:select('c',{t={}}); runtime:start(); return runtime
    end
    return api
end

test('reused address cannot revive an old reference or dereference the old object',function()
    local api=setup(); local old=api.create(100); local ref=api.host.capture(old)
    local identity=api.host.identity(ref); api.destroy(old)
    local reads=api.reads
    assert(not api.host.valid(ref) and api.host.unwrap(ref)==nil and api.host.capture(old)==nil)
    assert(api.reads==reads)
    local replacement=api.create(100); local new=api.host.capture(replacement)
    assert(api.host.identity(new)~=identity and not api.host.valid(ref))
end)
test('templates receive actual UObjects and overlaid settings for all callbacks',function()
    local api=setup(); local object=api.create(100); object.ready=true
    local runtime=api.runtime(); runtime:select('c',{t={override=true}}); runtime:stop()
    assert(#api.calls==3)
    for i,method in ipairs({'attach','update','detach'}) do
        assert(api.calls[i][1]==method and api.calls[i][2]==object)
        assert(api.calls[i][3].category and api.calls[i][3].template)
    end
    assert(api.calls[2][3].override and api.calls[3][3].override)
end)
test('native destruction discards attachment without detach at the next event',function()
    local api=setup(); local old=api.create(100); old.ready=true
    local runtime=api.runtime(); api.destroy(old)
    local replacement=api.create(100); replacement.ready=true
    api.emit('changed',replacement)
    assert(#api.calls==2 and api.calls[2][1]=='attach' and api.calls[2][2]==replacement)
    local count=0; for _ in pairs(runtime:attachments('t')) do count=count+1 end
    assert(count==1 and #api.events==0)
end)
test('settings after native destruction never call update or detach on stale reference',function()
    local api=setup(); local old=api.create(100); old.ready=true
    local runtime=api.runtime(); api.destroy(old)
    runtime:select('c',{t={changed=true}}); runtime:stop()
    assert(#api.calls==1 and next(runtime:attachments('t'))==nil)
end)
test('construction waits for a real readiness event',function()
    local api=setup(); local object=api.create(100)
    api.runtime(); assert(#api.calls==0)
    object.ready=true; api.emit('changed',object)
    assert(#api.calls==1 and api.calls[1][1]=='attach')
end)
test('valid loss detaches and invalid loss skips object access',function()
    local api=setup(); local object=api.create(100); object.ready=true
    api.runtime(); api.emit('lost',object)
    assert(#api.calls==2 and api.calls[2][1]=='detach')
    api.emit('changed',object); api.destroy(object); api.emit('lost',object)
    assert(#api.calls==3 and api.calls[3][1]=='attach' and #api.events==0)
end)
test('cancelled source callbacks cannot reenter the runtime',function()
    local api=setup(); local object=api.create(100); object.ready=true
    local runtime=api.runtime(); runtime:stop(); api.emit('changed',object)
    assert(api.stopped and #api.calls==2)
end)
test('parent references share canonical identity with snapshot references',function()
    local api=setup(); local parent=api.create(100); local child=api.create(101,parent)
    local root=api.host.capture(parent); local ref=api.host.capture(child)
    assert(api.host.parent(ref)==root)
    api.destroy(parent); assert(api.host.parent(ref)==nil)
end)
test('queued captured reference cannot bind a replacement at the same address',function()
    local api=setup(); local old=api.create(100); old.ready=true
    api.runtime(); local queued=api.host.capture(old); api.destroy(old)
    local replacement=api.create(100); replacement.ready=true
    api.emit('changed',queued)
    assert(#api.calls==1)
    api.emit('changed',replacement)
    assert(#api.calls==2 and api.calls[2][2]==replacement)
end)
test('explicit loss flush consumes queued IDs without an object scan',function()
    local api=setup(); local old=api.create(100); old.ready=true
    local runtime=api.runtime(); api.destroy(old)
    api.host.flushLost()
    assert(#api.calls==1 and next(runtime:attachments('t'))==nil)
end)
test('a ready child joins and leaves a group on parent-change notifications',function()
    local api=setup(); local root=api.create(100); root.ready=true; root.role='Root'
    local child=api.create(101); child.ready=true; child.role='Slot'
    api.source.matches=function(object, selector) return object.role==selector.class end
    api.runtime({root={class='Root'},slots={class='Slot',within='root'}})
    assert(#api.calls==1 and api.calls[1][2]==root)
    child.parent=root; api.emit('changed',child)
    assert(#api.calls==2 and api.calls[2][1]=='attach' and api.calls[2][2]==child)
    child.parent=nil; api.emit('changed',child)
    assert(#api.calls==3 and api.calls[3][1]=='detach' and api.calls[3][2]==child)
end)
print('PASS: '..passed..' MCT native reference adapter tests')
