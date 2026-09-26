-- Find templates in installed UE4SS modules. mc.lua owns a module's template
-- list when present; main.lua remains supported for existing modules.
local M = {}

local function normalized(path)
    return type(path)=='string' and path:gsub('\\','/'):gsub('/+$',''):lower() or nil
end

local function directory(parent,name)
    if type(parent)~='table' then return nil end
    for key,child in pairs(parent) do
        if type(child)=='table' and (tostring(key):lower()==name:lower()
            or tostring(child.__name or ''):lower()==name:lower()) then return child end
    end
end

local function enabled(module)
    for key,file in pairs(module.__files or {}) do
        if tostring(key):lower()=='enabled.txt'
            or type(file)=='table' and tostring(file.__name or ''):lower()=='enabled.txt' then
            return true
        end
    end
    local path=module.__absolute_path
    if type(path)~='string' then return false end
    local handle=io.open(path..'/enabled.txt','r')
    if not handle then return false end
    handle:close()
    return true
end

local function modsFromTree(tree)
    local game=directory(tree,'Game')
    if not game then
        for _,candidate in pairs(tree) do
            if type(candidate)=='table' and directory(candidate,'Binaries') then
                game=candidate; break
            end
        end
    end
    local binaries=directory(game,'Binaries')
    local win64=directory(binaries,'Win64')
    return directory(directory(win64,'ue4ss'),'Mods')
end

local function findPath(tree,path)
    if type(tree)~='table' then return nil end
    if normalized(tree.__absolute_path)==normalized(path) then return tree end
    for key,child in pairs(tree) do
        if key~='__files' and type(child)=='table' then
            local found=findPath(child,path)
            if found then return found end
        end
    end
end

function M.discover(root,gameDirectories)
    assert(type(gameDirectories)=='table', 'UE4SS directory API returned no tree')
    local mods=root:match('^(.*)[/\\][^/\\]+$') or '.'
    local parent=assert(findPath(gameDirectories,mods) or modsFromTree(gameDirectories),
        'UE4SS Mods directory unavailable')
    local paths={}
    for name,module in pairs(parent) do
        if name~='__files' and type(module)=='table' and enabled(module) then
            local scripts=directory(module,'Scripts')
            local templates=scripts and directory(scripts,'templates')
            if templates then
                local main,mc,others=nil,nil,{}
                for _,file in pairs(templates.__files or {}) do
                    if type(file)=='table' and type(file.__name)=='string'
                        and type(file.__absolute_path)=='string' then
                        if file.__name:lower()=='mc.lua' then mc=file.__absolute_path
                        elseif file.__name:lower()=='main.lua' then main=file.__absolute_path
                        elseif file.__name:lower():match('%.lua$') then
                            others[#others+1]=file.__absolute_path
                        end
                    end
                end
                if mc or main then paths[#paths+1]=mc or main
                else for _,path in ipairs(others) do paths[#paths+1]=path end end
            end
        end
    end
    table.sort(paths,function(a,b) return normalized(a)<normalized(b) end)
    return paths
end

return M
