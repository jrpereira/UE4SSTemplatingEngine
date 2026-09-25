-- Installed mod layout. Only DMM's discovery manifest must remain at mod root.
local M = {configFile='ModCore/cache/config.ini'}
function M.paths(root)
    assert(type(root) == 'string' and root ~= '', 'mod root required')
    root = root:gsub('[/\\]+$', '')
    return {root=root, templates=root .. '/ModCore/templates', categories=root .. '/ModCore/categories',
        cache=root .. '/ModCore/cache', config=root .. '/' .. M.configFile,
        catalog=root .. '/ModCore/cache/identity-catalog.lua', pages=root .. '/ModCore/cache/menu-pages.lua',
        manifest=root .. '/mod_settings.ini'}
end
local function exists(path)
    local file = io.open(path, 'rb')
    if not file then return false end
    file:close(); return true
end
local function mkdir(path)
    local command
    if package.config:sub(1,1) == '\\' then
        -- Quoting alone does not prevent cmd.exe environment expansion.
        assert(not path:find('["%%!\r\n]'), 'unsupported directory path')
        path = path:gsub('/', '\\')
        command = 'if not exist "' .. path .. '" mkdir "' .. path .. '"'
    else
        command = "mkdir -p -- '" .. path:gsub("'", "'\\''") .. "'"
    end
    local ok = os.execute(command)
    assert(ok == true or ok == 0, 'cannot create directory: ' .. path)
end
function M.prepare(root, createDirectory)
    local paths = M.paths(root)
    local pending = {}
    for _, name in ipairs({'config.ini','identity-catalog.lua','menu-pages.lua'}) do
        local old, target = paths.root .. '/' .. name, paths.cache .. '/' .. name
        if exists(old) then
            assert(not exists(target), 'both legacy and cache files exist; refusing to overwrite: ' .. name)
            pending[#pending + 1] = {old=old,target=target}
        end
    end
    createDirectory = createDirectory or mkdir
    for _, path in ipairs({paths.templates,paths.categories,paths.cache}) do createDirectory(path) end
    for _, move in ipairs(pending) do
        local ok, why = os.rename(move.old, move.target)
        assert(ok, 'cannot migrate ' .. move.old .. ': ' .. tostring(why))
    end
    return paths
end
return M
