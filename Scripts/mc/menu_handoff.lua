-- ModRef shared scalars coordinate MCT and DMM, which have separate Lua states.
local Layout = require('mc.layout')
local M = {}
local prefix = 'MCT.Menu.v1.'

local function check(shared)
    assert(shared and type(shared.GetSharedVariable) == 'function'
        and type(shared.SetSharedVariable) == 'function', 'UE4SS shared variables unavailable')
end

function M.publisher(shared)
    check(shared)
    local generation
    local self = {}
    function self:begin()
        local previous = shared:GetSharedVariable(prefix .. 'generation') or 0
        assert(type(previous) == 'number' and previous >= 0 and previous % 1 == 0
            and previous < 9007199254740991, 'invalid menu generation')
        generation = previous + 1
        shared:SetSharedVariable(prefix .. 'ready', false)
        shared:SetSharedVariable(prefix .. 'generation', generation)
        return generation
    end
    function self:ready()
        assert(generation and shared:GetSharedVariable(prefix .. 'generation') == generation,
            'menu startup superseded by a newer generation')
        shared:SetSharedVariable(prefix .. 'ready', generation)
    end
    function self:stop()
        if generation and shared:GetSharedVariable(prefix .. 'generation') == generation then
            shared:SetSharedVariable(prefix .. 'ready', false)
        end
    end
    return self
end

function M.reader(root, shared, loader)
    check(shared)
    loader = loader or function(path)
        local file = assert(io.open(path, 'rb'))
        local content = file:read('*a'); file:close()
        return content
    end
    local paths = Layout.paths(root)
    local cached, loadedGeneration
    return function()
        local generation = shared:GetSharedVariable(prefix .. 'generation')
        if generation == nil or shared:GetSharedVariable(prefix .. 'ready') ~= generation then return nil end
        if loadedGeneration == generation then return cached end
        local source = loader(paths.pages)
        local definitions = assert(load(source, '@' .. paths.pages, 't', {}))()
        assert(type(definitions) == 'table' and definitions.version == 1
            and type(definitions.pages) == 'table', 'invalid published menu definitions')
        local manifest = loader(paths.manifest)
        -- A reload may have begun while the two files were read. Never mix generations.
        if shared:GetSharedVariable(prefix .. 'generation') ~= generation
            or shared:GetSharedVariable(prefix .. 'ready') ~= generation then return nil end
        cached = {pages=definitions.pages, aggregate={manifest=manifest}}
        loadedGeneration = generation
        return cached
    end
end

return M
