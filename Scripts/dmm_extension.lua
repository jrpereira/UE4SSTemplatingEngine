-- DMM loads this in its own Lua state, potentially before MCT finishes startup.
local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate MCT Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$'), 'cannot locate MCT module')
package.path = scripts .. '/?.lua;' .. package.path
local shared = assert(ModRef, 'DMM ModRef unavailable')
local readMenu = require('mc.menu_handoff').reader(root, shared)
return require('mc.dmm_extension').new(root, readMenu)
