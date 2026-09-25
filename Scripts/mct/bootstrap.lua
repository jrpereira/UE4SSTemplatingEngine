-- Draft startup orchestration. The caller supplies the real module-load barrier.
local Layout = require('mct.layout')
local Runtime = require('mct.runtime')
local MenuModel = require('mct.menu_model')
local Menu = require('mct.menu')
local MenuFiles = require('mct.menu_files')
local MenuController = require('mct.menu_controller')
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
        menuHandoff = require('mct.menu_handoff').publisher(options.menuShared)
        menuHandoff:begin()
    end
    for _, path in ipairs(options.categoryFiles or {}) do
        local category = execute(path)
        assert(type(category) == 'table', path .. ': expected category definition')
        categories[#categories + 1] = category
    end
    function self:registerTemplate(path)
        assert(self.phase == 'registering', 'template registration closed at Loop Start')
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
            if options.consumeRegistrations then
                for _, path in ipairs(options.consumeRegistrations()) do self:registerTemplate(path) end
            end
            self.phase = 'loading'
            if stopBarrier then stopBarrier(); stopBarrier = nil end
            local templates = {}
            for _, path in ipairs(files) do
                local template = execute(path)
                assert(type(template) == 'table', path .. ': expected template definition')
                templates[#templates + 1] = template
            end
            -- Validate every definition before discovery can invoke template code.
            local model = MenuModel.build(categories, templates, files)
            local menuOptions = require('mct.util').copy(options.menu or {})
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
            self.extension = require('mct.dmm_extension').new(options.menuRoot or '.', self.menu)
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
    -- External modules may register until this one-shot barrier fires.
    local stop = options.subscribeLoopStart(function() self:finishLoading() end)
    assert(type(stop) == 'function', 'module-load barrier must return unsubscribe')
    if self.phase == 'registering' then stopBarrier = stop else stop() end
    return self
end

return M
