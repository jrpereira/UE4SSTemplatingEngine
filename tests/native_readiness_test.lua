package.path = 'Scripts/?.lua;' .. package.path
local Readiness = require('te.player_actions.readiness')
local checks = 0
local function check(v) assert(v); checks = checks + 1 end
local queue, timers, logs, runs = {}, {}, {}, 0
local enabled = true
local function drain(list)
    local work = {}; for i, fn in ipairs(list) do work[i] = fn end
    for i = #list, 1, -1 do list[i] = nil end
    for _, fn in ipairs(work) do fn() end
end
local env = {
    maxAttempts = 3,
    key = function(o, kind) return o.id .. ':' .. kind end,
    signature = function(o) return o.signature end,
    valid = function(o) return not o.dead end,
    relevant = function(o) return not o.foreign end,
    enabled = function() return enabled end,
    queue = function(fn) queue[#queue + 1] = fn end,
    delay = function(ms, fn) check(ms == 100); timers[#timers + 1] = fn end,
    run = function(o) runs = runs + 1; return o.ready and 'applied' or 'not_ready' end,
    log = function(err) logs[#logs + 1] = err end,
}
local worker = Readiness.new(env)
local hud = {id = 'hud', signature = 1}
check(#queue == 0 and #timers == 0 and runs == 0)
check(worker:request(hud, 'indicators'))
check(not worker:request(hud, 'indicators'))
drain(queue); drain(timers); drain(queue); drain(timers); drain(queue)
check(runs == 3 and #queue == 0 and #timers == 0)
check(worker:status('hud:indicators') == 'exhausted')
check(not worker:request(hud, 'indicators'))
check(runs == 3 and #queue == 0 and #timers == 0)
hud.signature, hud.ready = 2, true
check(worker:request(hud, 'indicators')); drain(queue)
check(worker:status('hud:indicators') == 'complete' and runs == 4)
check(not worker:request(hud, 'indicators'))
hud.ready = false
check(worker:request(hud, 'layout')); drain(queue)
worker:invalidate(); drain(timers); drain(queue)
check(runs == 5 and #timers == 0 and worker:status('hud:layout') == nil)
check(worker:request(hud, 'layout'))
hud.foreign = true; drain(queue)
check(worker:status('hud:layout') == 'cancelled' and runs == 5)
hud.foreign = false; hud.signature = 3
check(worker:request(hud, 'layout'))
hud.dead = true; drain(queue)
check(worker:status('hud:layout') == 'cancelled' and runs == 5)
local replacement = {id = 'hud', signature = 4, ready = true}
check(worker:request(replacement, 'layout')); drain(queue)
check(runs == 6)
replacement.signature = 5
env.run = function() error('discovery failed') end
check(worker:request(replacement, 'layout')); drain(queue)
check(worker:status('hud:layout') == 'failed' and #logs == 1 and #timers == 0)
check(not worker:request(replacement, 'layout'))
enabled = false; replacement.signature = 6
check(not worker:request(replacement, 'layout'))
print('native readiness: ' .. checks .. ' checks passed')
