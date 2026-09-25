-- DMM loads this in its own Lua state, potentially before MCT finishes startup.
local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate MCT Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$'), 'cannot locate MCT module')
package.path = scripts .. '/?.lua;' .. package.path
local readMenu = require('mct.menu_handoff').reader(root, assert(ModRef, 'DMM ModRef unavailable'))
return require('mct.dmm_extension').new(root, readMenu)
