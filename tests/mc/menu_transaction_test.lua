package.path='./Scripts/?.lua;'..package.path
local Files=require('mc.menu_files')
local base=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/transaction.ini'
local row={Id='X',Type='integer',Minimum=0,Maximum=10,Default=1}
local function write(path,value)
    local file=assert(io.open(path,'wb'))
    assert(file:write(value));assert(file:close())
end
local function read(path)
    local file=io.open(path,'rb')
    if not file then return nil end
    local result=file:read('*a');file:close();return result
end
-- Crash after moving the original out, before publishing the replacement.
write(base..'.mc.bak','[Templates]\nX=7\n')
write(base..'.mc.tmp','[Templates]\nX=9\n')
assert(Files.ensureConfig(base,{row},{})==false)
assert(Files.readConfigValues(base,{}, {row}).X==7)
assert(read(base..'.mc.bak')==nil and read(base..'.mc.tmp')==nil)
-- Crash after publishing the replacement, before removing the backup.
write(base..'.mc.bak','[Templates]\nX=7\n')
write(base,'[Templates]\nX=8\n')
assert(Files.ensureConfig(base,{row},{})==false)
assert(Files.readConfigValues(base,{}, {row}).X==8)
assert(read(base..'.mc.bak')==nil)
-- Crash before touching the original.
write(base..'.mc.tmp','[Templates]\nX=9\n')
assert(Files.readConfigValues(base,{}, {row}).X==8)
assert(read(base..'.mc.tmp')==nil)
print('PASS: interrupted menu writes recover original or published config')
