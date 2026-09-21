local U = require('te.util')
local V = require('te.validation')
local M = {}

function M.new(categories, options)
    options = options or {}
    local self = {categories = categories, files = {}, registered = {}, loaded = {}, templates = {}, byId = {}}
    local canonical = options.canonicalPath or function(path) return path:gsub('\\', '/') end
    local execute = options.execute or function(path)
        local chunk, err
        if options.environment then chunk, err = loadfile(path, 't', options.environment(path))
        else chunk, err = loadfile(path, 't') end
        assert(chunk, err)
        return chunk()
    end
    function self:registerTemplate(path)
        U.text(path, 'template path')
        assert(path:lower():match('%.lua$'), 'template path must end in .lua')
        local key = canonical(path)
        if self.registered[key] then return false end
        self.registered[key] = true
        self.files[#self.files + 1] = {key = key, path = path}
        return true
    end
    function self:registerTemplates(folder)
        U.text(folder, 'template folder')
        assert(type(options.listFiles) == 'function', 'directory enumeration adapter required')
        local paths = options.listFiles(folder)
        U.array(paths, 'directory entries')
        local selected = {}
        for _, path in ipairs(paths) do
            U.text(path, 'directory entry')
            if path:lower():match('%.lua$') then selected[#selected + 1] = path end
        end
        table.sort(selected)
        local count = 0
        for _, path in ipairs(selected) do if self:registerTemplate(path) then count = count + 1 end end
        return count
    end
    function self:loadTemplatesFromRegister()
        local additions, pendingIds, pendingFiles = {}, {}, {}
        -- Registry state is atomic across a batch. Executed Lua side effects are not reversible.
        for _, file in ipairs(self.files) do
            if not self.loaded[file.key] then
                local ok, value = pcall(execute, file.path)
                assert(ok, file.path .. ': ' .. tostring(value))
                for _, entry in ipairs(V.flatten(value, self.categories, file.path)) do
                    local id = U.identity(entry.template)
                    assert(not self.byId[id] and not pendingIds[id], entry.location .. ': duplicate template identity')
                    pendingIds[id] = true
                    additions[#additions + 1] = {id = id, template = entry.template, location = entry.location}
                end
                pendingFiles[#pendingFiles + 1] = file.key
            end
        end
        for _, entry in ipairs(additions) do
            self.templates[#self.templates + 1] = entry
            self.byId[entry.id] = entry
        end
        for _, key in ipairs(pendingFiles) do self.loaded[key] = true end
        return #additions
    end
    return self
end

return M
