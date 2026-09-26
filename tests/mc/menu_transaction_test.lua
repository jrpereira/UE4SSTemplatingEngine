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

local extra={Id='Y',Type='integer',Minimum=0,Maximum=10,Default=2}
local originalRename,originalRemove,originalOpen=os.rename,os.remove,io.open
for _,failure in ipairs({'write','close'}) do
    io.open=function(path,mode)
        local file=originalOpen(path,mode)
        if path~=base..'.mc.tmp' or mode~='wb' then return file end
        return {
            write=function(_,value)
                if failure=='write' then return nil,'injected write failure' end
                return file:write(value)
            end,
            close=function()
                local result=file:close()
                if failure=='close' then return nil,'injected close failure' end
                return result
            end,
        }
    end
    assert(not pcall(Files.ensureConfig,base,{row,extra},{}))
    io.open=originalOpen
    assert(Files.readConfigValues(base,{}, {row}).X==8)
    assert(read(base..'.mc.tmp')==nil)
end
-- Failure before moving the original leaves its contents and clears the temp.
os.rename=function(from,to)
    if from==base and to==base..'.mc.bak' then return nil,'injected backup rename failure' end
    return originalRename(from,to)
end
assert(not pcall(Files.ensureConfig,base,{row,extra},{}))
os.rename=originalRename
assert(Files.readConfigValues(base,{}, {row}).X==8)
assert(read(base..'.mc.tmp')==nil and read(base..'.mc.bak')==nil)

-- If cleanup of a failed publish also fails, startup recovery clears the temp.
os.rename=function(from,to)
    if from==base..'.mc.tmp' and to==base then return nil,'injected publish rename failure' end
    return originalRename(from,to)
end
os.remove=function(path)
    if path==base..'.mc.tmp' then return nil,'injected temp removal failure' end
    return originalRemove(path)
end
assert(not pcall(Files.ensureConfig,base,{row,extra},{}))
os.rename,os.remove=originalRename,originalRemove
assert(read(base..'.mc.tmp')~=nil)
assert(Files.readConfigValues(base,{}, {row}).X==8)
assert(read(base..'.mc.tmp')==nil and read(base..'.mc.bak')==nil)

-- Failure when publishing the temp must roll back to the original.
os.rename=function(from,to)
    if from==base..'.mc.tmp' and to==base then return nil,'injected publish rename failure' end
    return originalRename(from,to)
end
assert(not pcall(Files.ensureConfig,base,{row,extra},{}))
os.rename=originalRename
assert(Files.readConfigValues(base,{}, {row}).X==8)
assert(read(base..'.mc.tmp')==nil and read(base..'.mc.bak')==nil)

-- A failed backup removal after publication is recovered on the next read.
os.remove=function(path)
    if path==base..'.mc.bak' then return nil,'injected backup removal failure' end
    return originalRemove(path)
end
assert(not pcall(Files.ensureConfig,base,{row,extra},{}))
os.remove=originalRemove
assert(read(base..'.mc.bak')~=nil)
assert(Files.readConfigValues(base,{}, {row,extra}).Y==2)
assert(read(base..'.mc.bak')==nil)
print('PASS: interrupted menu writes recover original or published config')
