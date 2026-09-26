-- Draft startup orchestration. The caller supplies the real module-load barrier.
local Layout = require('mc.layout')
local Runtime = require('mc.runtime')
local MenuModel = require('mc.menu_model')
local Menu = require('mc.menu')
local MenuFiles = require('mc.menu_files')
local MenuController = require('mc.menu_controller')
local M = {}

function M.new(options)
    assert(not options.settingsApi or (not options.categorySettings and not options.selections),
        'use menuValues/config for menu-controlled startup selections')
    assert(type(options.subscribeLoopStart) == 'function', 'module-load barrier adapter required')
    local execute = options.execute or function(path) return assert(loadfile(path))() end
    local self = {phase='registering', runtime=nil}
    local categories, files, seen = {}, {}, {}
    local stopBarrier
    local paths = options.menuRoot and Layout.paths(options.menuRoot)
    local menuHandoff
    if options.menuShared then
        assert(options.menuRoot, 'cross-state menu handoff requires menuRoot')
        menuHandoff = require('mc.menu_handoff').publisher(options.menuShared)
        menuHandoff:begin()
    end
    for _, path in ipairs(options.categoryFiles or {}) do
        local category = execute(path)
        assert(type(category) == 'table', path .. ': expected category definition')
        categories[#categories + 1] = category
    end
    function self:registerTemplate(path)
        assert(self.phase == 'registering', 'template registration closed at startup')
        assert(type(path) == 'string' and path ~= '', 'template file required')
        local canonical = path:gsub('\\', '/')
        if seen[canonical] then return false end
        files[#files + 1], seen[canonical] = path, true
        return true
    end
    for _, path in ipairs(options.templateFiles or {}) do self:registerTemplate(path) end
    function self:finishLoading()
        if self.phase ~= 'registering' then return false end
        local ok, why = pcall(function()
            self.phase = 'loading'
            if stopBarrier then stopBarrier(); stopBarrier = nil end
            local templates, locations = {}, {}
            for _, path in ipairs(files) do
                local loaded = execute(path)
                assert(type(loaded) == 'table', path .. ': expected template definition')
                if loaded.category then
                    templates[#templates + 1], locations[#locations + 1] = loaded, path
                else
                    local count = require('mc.util').array(loaded, path .. ': template list')
                    assert(count > 0, path .. ': empty template list')
                    for index=1,count do
                        local template=loaded[index]
                        assert(type(template)=='table' and template.category,
                            path .. ': invalid template at index ' .. index)
                        templates[#templates + 1], locations[#locations + 1] = template, path
                    end
                end
            end
            -- Validate every definition before discovery can invoke template code.
            local model = MenuModel.build(categories, templates, locations)
            local menuOptions = require('mc.util').copy(options.menu or {})
            if options.menuRoot then menuOptions.catalog = MenuFiles.readCatalog(options.menuRoot) end
            self.menu = Menu.generate(model.registry, menuOptions)
            self.runtime = Runtime.new(options.host, model.categories, model.templates)
            local savedValues = options.menuValues
            if options.menuRoot then
                MenuFiles.publish(options.menuRoot, self.menu)
                MenuFiles.ensureConfig(paths.config, self.menu.rows, self.menu.textSettings)
                savedValues = MenuFiles.readConfigValues(paths.config, self.menu.textSettings, self.menu.rows)
            end
            local function readValues()
                if options.menuRoot then
                    return MenuFiles.readConfigValues(paths.config, self.menu.textSettings, self.menu.rows)
                end
                return {}
            end
            self.menuController = MenuController.new(self.menu, self.runtime,
                {values=savedValues, readValues=readValues, onError=options.host.onError})
            if options.settingsApi then self.menuController:bind(options.settingsApi, options.queue) end
            self.extension = require('mc.dmm_extension').new(options.menuRoot or '.', self.menu)
            for category, settings in pairs(options.categorySettings or {}) do
                self.runtime:setCategorySettings(category, settings)
            end
            for category, selections in pairs(options.selections or {}) do
                self.runtime:select(category, selections)
            end
            local function startRuntime()
                self.runtime:start()
                assert(self.runtime.phase == 'running', 'lifecycle subscription failed')
                if menuHandoff then menuHandoff:ready() end
            end
            if options.startOnGameThread then
                self.phase = 'starting'
                options.startOnGameThread(function()
                    if self.phase ~= 'starting' then return end
                    local started, failure = pcall(startRuntime)
                    self.phase = started and 'running' or 'failed'
                    if not started then
                        if menuHandoff then menuHandoff:stop() end
                        self.menuController:stop()
                        self.runtime:stop()
                        if options.closeHost then pcall(options.closeHost) end
                        pcall(options.host.onError, {stage='startup', message=tostring(failure)})
                    end
                end)
            else
                startRuntime()
            end
        end)
        if not ok then self.phase = 'failed'
        elseif self.phase == 'loading' then self.phase = 'running' end
        if not ok then
            if menuHandoff then menuHandoff:stop() end
            if self.menuController then self.menuController:stop() end
            if self.runtime then self.runtime:stop() end
            if options.closeHost then pcall(options.closeHost) end
            pcall(options.host.onError, {stage='startup', message=tostring(why)})
            return nil, why
        end
        return true
    end
    function self:stop()
        if menuHandoff then menuHandoff:stop() end
        if stopBarrier then stopBarrier(); stopBarrier = nil end
        if self.menuController then self.menuController:stop() end
        if self.runtime then self.runtime:stop() end
        if options.closeHost then pcall(options.closeHost) end
        self.phase = 'stopped'
    end
    -- Registrations close when the one-shot startup callback runs.
    local stop = options.subscribeLoopStart(function() self:finishLoading() end)
    assert(type(stop) == 'function', 'module-load barrier must return unsubscribe')
    if self.phase == 'registering' then stopBarrier = stop else stop() end
    return self
end

return M
