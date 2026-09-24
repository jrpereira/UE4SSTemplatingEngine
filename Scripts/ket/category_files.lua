local U = require('ket.util')
local M = {}

local function normalized(path)
    return path:gsub('\\', '/'):gsub('/+$', ''):lower()
end

local function fromGameDirectories(folder)
    if type(IterateGameDirectories) ~= 'function' then return nil end
    local ok, tree = pcall(IterateGameDirectories)
    if not ok or type(tree) ~= 'table' then return nil end
    local selected, visited, target = {}, {}, normalized(folder)
    local function visit(node)
        if type(node) ~= 'table' or visited[node] then return end
        visited[node] = true
        if type(node.__absolute_path) == 'string'
            and normalized(node.__absolute_path) == target then
            for _, file in pairs(node.__files or {}) do
                if type(file) == 'table' and type(file.__name) == 'string'
                    and file.__name:lower():match('%.lua$') then
                    selected[#selected + 1] = file.__absolute_path
                        or folder .. '/' .. file.__name
                end
            end
        else
            for key, child in pairs(node) do
                if key ~= '__files' then visit(child) end
            end
        end
    end
    visit(tree)
    return #selected > 0 and selected or nil
end

local function fromShell(folder)
    if not io or type(io.popen) ~= 'function' then return nil end
    local windows = package.config:sub(1, 1) == '\\'
    local command
    if windows then
        assert(not folder:find('["%%\r\n]'), 'unsupported category folder path')
        command = 'cmd /C dir /B /A:-D "' .. folder .. '\\*.lua"'
    else
        local quoted = "'" .. folder:gsub("'", "'\\''") .. "'"
        command = "find " .. quoted .. " -maxdepth 1 -type f -name '*.lua'"
    end
    local opened, pipe = pcall(io.popen, command, 'r')
    if not opened or not pipe then return nil end
    local paths = {}
    for line in pipe:lines() do
        if line:lower():match('%.lua$') then
            paths[#paths + 1] = windows and folder .. '/' .. line or line
        end
    end
    pipe:close()
    return #paths > 0 and paths or nil
end

function M.list(folder, fallback)
    U.text(folder, 'category folder')
    local paths = fromGameDirectories(folder) or fromShell(folder) or fallback
    assert(type(paths) == 'table' and U.array(paths, 'category files') > 0,
        folder .. ': no category files found')
    local selected, seen = {}, {}
    for _, path in ipairs(paths) do
        U.text(path, 'category file')
        assert(path:lower():match('%.lua$'), path .. ': category file must end in .lua')
        local key = normalized(path)
        assert(not seen[key], path .. ': duplicate category file')
        seen[key] = true
        selected[#selected + 1] = path
    end
    table.sort(selected)
    return selected
end

return M
