package.path = './Scripts/?.lua;./Scripts/?/init.lua;' .. package.path
local Runtime = require('mct.runtime')
local Selectors = require('mct.selectors')
local Bootstrap = require('mct.bootstrap')
local passed = 0
local function test(name, body)
    local ok, why = pcall(body)
    assert(ok, name .. ': ' .. tostring(why))
    passed = passed + 1
end
local function fixture(single, paths)
    local objects, calls, errors = {}, {}, {}
    local sink, epoch, scans, unsubs = nil, nil, 0, 0
    local host = {
        valid=function(o) return o ~= nil and o.valid ~= false end,
        identity=function(o) assert(o.valid ~= false, 'identity read after invalidation'); return o.id end,
        ready=function(o) return o.ready ~= false end,
        matches=function(o, s) return s.object == o.path or s.class ~= nil and s.class == o.class end,
        parent=function(o) return o.parent end,
        find=function(s)
            scans = scans + 1
            local found = {}
            for _, o in ipairs(objects) do
                if o.valid ~= false and (s.object == o.path or s.class ~= nil and s.class == o.class) then found[#found + 1] = o end
            end
            return found
        end,
        subscribe=function(callback, getEpoch) sink, epoch = callback, getEpoch; return function() unsubs=unsubs+1 end end,
        onError=function(e) errors[#errors + 1] = e end,
    }
    local function template(id)
        local t = {id=id, category='player.quickslots'}
        t.attach = function(o, settings)
            assert(o.valid ~= false)
            calls[#calls + 1] = id .. ':attach:' .. o.id .. ':' .. tostring(settings.size)
        end
        t.update = function(o)
            assert(o.valid ~= false)
            calls[#calls + 1] = id .. ':update:' .. o.id .. ':' .. tostring(t.settings.size)
        end
        t.detach = function(o) assert(o.valid ~= false); calls[#calls + 1] = id .. ':detach:' .. o.id end
        return t
    end
    local a, b = template('a'), template('b')
    local categories = {{name='player.quickslots', single=single, targets=paths or {slots={class='Slot'}}}}
    local runtime = Runtime.new(host, categories, {a,b})
    local f = {runtime=runtime, host=host, objects=objects, calls=calls, errors=errors, a=a, b=b, categories=categories}
    function f.object(id, class, parent, ready)
        local object = {id=id, path=id, class=class or 'Slot', parent=parent, ready=ready}
        objects[#objects + 1] = object
        return object
    end
    function f.emit(kind, object, version)
        sink({kind=kind, object=object, id=object and object.id, epoch=version or epoch()})
    end
    function f.counts() return scans, unsubs end
    return f
end

test('initial discovery, group creation, no repeated attach or scans', function()
    local f = fixture()
    local first = f.object('one')
    f.runtime:select('player.quickslots', {a={size=1}})
    f.runtime:start()
    assert(#f.calls == 1)
    local second = f.object('two')
    f.emit('changed', second)
    f.emit('changed', first)
    assert(#f.calls == 2 and f.counts() == 1)
end)

test('overlapping selectors attach once', function()
    local f = fixture(false, {one={object='one'}, all={class='Slot'}})
    f.object('one')
    f.runtime:select('player.quickslots', {a={}})
    f.runtime:start()
    assert(#f.calls == 1)
end)

test('settings invoke update, not attach or detach', function()
    local f = fixture()
    f.object('one')
    f.runtime:select('player.quickslots', {a={size=1}}); f.runtime:start()
    local settings = {size=2}
    f.runtime:select('player.quickslots', {a=settings})
    settings.size = 9
    assert(#f.calls == 2 and f.calls[2] == 'a:update:one:2')
end)

test('readiness and late parent assignment; parent removal detaches descendants', function()
    local f = fixture(false, {root={object='root'}, slots={class='Slot', within='root'}})
    local root = f.object('root', 'Root')
    local child = f.object('child', 'Slot', nil, false)
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    assert(#f.calls == 1)
    f.emit('changed', child); assert(#f.calls == 1)
    child.parent, child.ready = root, true
    f.emit('changed', root); assert(#f.calls == 2)
    f.emit('lost', root)
    assert(#f.calls == 4 and next(f.runtime:attachments('a')) == nil)
end)

test('reparenting valid objects detaches and can reattach', function()
    local f = fixture(false, {root={object='root'}, slots={class='Slot', within='root'}})
    local root = f.object('root', 'Root')
    local child = f.object('child', 'Slot', root)
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    child.parent = nil; f.emit('changed', child)
    assert(f.calls[3] == 'a:detach:child')
    child.parent = root; f.emit('changed', child)
    assert(f.calls[4] == 'a:attach:child:nil')
end)

test('invalid objects never receive detach, replacements attach independently', function()
    local f = fixture()
    local old = f.object('old')
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    old.valid = false
    f.emit('lost', old)
    local new = f.object('new'); new.path = old.path
    f.emit('changed', new)
    assert(#f.calls == 2 and f.runtime:attachments('a').old == nil)
end)

test('disable and single selection switch detach before attaching', function()
    local f = fixture(true)
    f.object('one')
    f.runtime:select('player.quickslots', {b={}}); f.runtime:start()
    assert(not pcall(function() f.runtime:select('player.quickslots', {a={},b={}}) end))
    f.runtime:select('player.quickslots', {a={}})
    assert(f.calls[2] == 'b:detach:one' and f.calls[3] == 'a:attach:one:nil')
    f.runtime:select('player.quickslots', {})
    assert(f.calls[4] == 'a:detach:one')
end)

test('world invalidation discards records and rejects stale queued events', function()
    local f = fixture()
    local old = f.object('old')
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    old.valid = false
    f.emit('world_invalidated', nil, 1)
    assert(f.runtime.epoch == 2 and next(f.runtime:attachments('a')) == nil)
    local new = f.object('new')
    f.emit('changed', new, 1); assert(#f.calls == 1)
    f.emit('changed', new, 2); assert(#f.calls == 1)
    f.emit('world_ready', nil, 2)
    assert(#f.calls == 2 and f.calls[2] == 'a:attach:new:nil')
end)

test('callback errors do not prevent other templates and retry only on an event', function()
    local f = fixture()
    local o = f.object('one')
    local attach = f.a.attach
    f.a.attach = function() error('test failure') end
    f.runtime:select('player.quickslots', {a={},b={}}); f.runtime:start()
    assert(#f.errors == 1 and #f.calls == 1)
    f.a.attach = attach; f.emit('changed', o)
    assert(#f.calls == 2 and f.calls[2] == 'a:attach:one:nil')
end)

test('failed detach blocks single-category replacement and retries', function()
    local f = fixture(true)
    local o = f.object('one')
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    local detach = f.a.detach
    f.a.detach = function() error('restoration failed') end
    f.runtime:select('player.quickslots', {b={}})
    assert(#f.calls == 1 and f.runtime:attachments('a').one)
    f.a.detach = detach; f.emit('changed', o)
    assert(f.calls[2] == 'a:detach:one' and f.calls[3] == 'b:attach:one:nil')
end)

test('not-ready attach retries on readiness event', function()
    local f = fixture()
    local o = f.object('one')
    local attach = f.a.attach
    f.a.attach = function() return false, 'not_ready' end
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    assert(#f.calls == 0 and #f.errors == 0)
    f.a.attach = attach; f.emit('changed', o)
    assert(#f.calls == 1)
end)

test('shutdown cancels subscription, skips invalid refs, ignores late events', function()
    local f = fixture()
    local a, b = f.object('a'), f.object('b')
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    a.valid = false
    f.runtime:stop()
    local _, unsubs = f.counts()
    assert(unsubs == 1 and #f.calls == 3 and f.calls[3] == 'a:detach:b')
    f.emit('changed', b)
    assert(#f.calls == 3)
end)

test('selector graph rejects cycles and missing roots', function()
    assert(not pcall(Selectors.compile, {a={class='Slot', within='b'}, b={class='Slot',within='a'}}))
    assert(not pcall(Selectors.compile, {a={class='Slot', within='missing'}}))
    assert(not pcall(Selectors.compile, {a={class='Slot',object='one'}}))
end)

test('startup defers template execution until barrier and accepts other modules', function()
    local f = fixture()
    f.object('one')
    local barrier, stopped, executed = nil, 0, {}
    local definitions = {category=f.categories[1], own=f.a, external=f.b}
    local boot = Bootstrap.new({host=f.host, categoryFiles={'category'}, templateFiles={'own'},
        execute=function(path) executed[#executed+1] = path; return definitions[path] end,
        selections={['player.quickslots']={a={size=3},b={size=4}}},
        subscribeLoopStart=function(callback) barrier=callback; return function() stopped=stopped+1 end end})
    assert(#executed == 1 and #f.calls == 0)
    assert(boot:registerTemplate('external') and not boot:registerTemplate('external'))
    barrier()
    assert(boot.phase == 'running' and #executed == 3 and #f.calls == 2 and stopped == 1)
    barrier(); assert(#executed == 3)
    assert(not pcall(function() boot:registerTemplate('late') end))
end)

test('subscription is active before snapshot and duplicate notifications are harmless', function()
    local f = fixture()
    local object = f.object('one')
    local subscribe = f.host.subscribe
    f.host.subscribe = function(sink, epoch)
        local stop = subscribe(sink, epoch)
        sink({kind='changed', object=object, epoch=epoch()})
        return stop
    end
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    assert(#f.calls == 1)
end)

test('loss during subscription is applied before initial attachment', function()
    local f = fixture()
    local object = f.object('one')
    local subscribe = f.host.subscribe
    f.host.subscribe = function(sink, epoch)
        local stop = subscribe(sink, epoch)
        sink({kind='lost', id=object.id, epoch=epoch()})
        return stop
    end
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    assert(#f.calls == 0)
end)

test('failed initial discovery closes subscriptions and fails startup', function()
    local f = fixture()
    f.host.find = function() error('enumeration unavailable') end
    f.runtime:start()
    local _, unsubs = f.counts()
    assert(f.runtime.phase == 'failed' and unsubs == 1 and #f.errors == 1)
end)

test('reentrant selection queues update until attachment completes', function()
    local f = fixture()
    f.object('one')
    local attach = f.a.attach
    f.a.attach = function(o, settings)
        attach(o, settings)
        f.runtime:select('player.quickslots', {a={size=2}})
    end
    f.runtime:select('player.quickslots', {a={size=1}}); f.runtime:start()
    assert(#f.calls == 2 and f.calls[2] == 'a:update:one:2')
end)

test('shutdown can retry a failed detach without resubscribing', function()
    local f = fixture()
    f.object('one')
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    local detach = f.a.detach
    f.a.detach = function() error('temporary detach failure') end
    f.runtime:stop()
    assert(f.runtime:attachments('a').one)
    f.a.detach = detach; f.runtime:stop()
    local _, unsubs = f.counts()
    assert(next(f.runtime:attachments('a')) == nil and unsubs == 1)
end)

test('failed update preserves attachment and retries without attaching again', function()
    local f = fixture()
    local o = f.object('one')
    f.runtime:select('player.quickslots', {a={size=1}}); f.runtime:start()
    local update = f.a.update
    f.a.update = function() return false, 'not_ready' end
    f.runtime:select('player.quickslots', {a={size=2}})
    assert(f.runtime:attachments('a').one and #f.calls == 1)
    f.a.update = update; f.emit('changed', o)
    assert(f.calls[2] == 'a:update:one:2')
end)

test('all callbacks receive template settings overlaid on category settings', function()
    local f = fixture()
    f.object('one')
    local seen = {}
    f.a.attach = function(_, settings) seen.attach = settings end
    f.a.update = function(_, settings) seen.update = settings end
    f.a.detach = function(_, settings) seen.detach = settings end
    f.runtime:setCategorySettings('player.quickslots', {size=10, opacity=0.5, visible=true, count=5})
    f.runtime:select('player.quickslots', {a={size=20, visible=false, count=0}})
    f.runtime:start()
    assert(seen.attach.size == 20 and seen.attach.opacity == 0.5)
    assert(seen.attach.visible == false and seen.attach.count == 0)
    f.runtime:setCategorySettings('player.quickslots', {size=11, opacity=0.8, visible=true, count=6})
    assert(seen.update.size == 20 and seen.update.opacity == 0.8)
    assert(seen.update.visible == false and seen.update.count == 0)
    f.runtime:select('player.quickslots', {})
    assert(seen.detach.size == 20 and seen.detach.opacity == 0.8)
    assert(seen.detach.visible == false and seen.detach.count == 0)
end)

test('detach gets the last successfully applied snapshot after failed update', function()
    local f = fixture()
    f.object('one')
    local detached
    f.a.update = function() return false, 'not_ready' end
    f.a.detach = function(_, settings)
        detached = settings
        assert(f.a.settings.size == settings.size)
    end
    f.runtime:setCategorySettings('player.quickslots', {opacity=0.5})
    f.runtime:select('player.quickslots', {a={size=1}}); f.runtime:start()
    f.runtime:setCategorySettings('player.quickslots', {opacity=0.9})
    f.runtime:select('player.quickslots', {a={size=2}})
    f.runtime:select('player.quickslots', {})
    assert(detached.size == 1 and detached.opacity == 0.5)
end)

test('removing a template override exposes the category value; snapshots are isolated', function()
    local f = fixture()
    local one = f.object('one')
    local observed = {}
    f.a.attach = function(o, settings)
        observed[o.id] = {size=settings.size, nested=settings.nested.value}
        settings.nested.value = 'mutated'
    end
    f.a.update = function(_, settings) observed.update = settings.size end
    local category = {size=10, nested={value='category'}}
    f.runtime:setCategorySettings('player.quickslots', category)
    category.nested.value = 'external mutation'
    f.runtime:select('player.quickslots', {a={size=20}}); f.runtime:start()
    local two = f.object('two'); f.emit('changed', two)
    assert(observed.one.nested == 'category' and observed.two.nested == 'category')
    f.runtime:select('player.quickslots', {a={}})
    assert(observed.update == 10)
end)

test('template defaults override category settings and saved values override defaults', function()
    local f = fixture()
    f.object('one')
    f.a.settings = {size=20, nested={template=true}}
    local seen
    f.a.attach = function(_, settings) seen=settings end
    f.categories[1].settings = {size=10, opacity=0.4, nested={category=true}}
    local r = Runtime.new(f.host, f.categories, {f.a})
    r:select('player.quickslots', {a={size=30}}); r:start()
    assert(seen.size == 30 and seen.opacity == 0.4)
    assert(seen.nested.template == true and seen.nested.category == nil)
end)

print('PASS: ' .. passed .. ' MCT draft lifecycle tests')
