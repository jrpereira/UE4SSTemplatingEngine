package.path = 'Scripts/?.lua;' .. package.path
local TE = require('te.init')
local checks = 0
local function check(value) assert(value); checks = checks + 1 end
local path = assert(os.getenv('TE_QSF_TEMPLATE'), 'TE_QSF_TEMPLATE required for actual consumer boundary tests')
local te = TE.new({listFiles = function() return {} end})
te:registerTemplate(path)
check(te:loadTemplatesFromRegister() == 1)
local entry = te.registry.templates[1]
check(entry.template.actionOrder == nil)
check(#entry.template.actions == 2)
check(entry.template.actions[1].name == 'Abilities' and entry.template.actions[1].type == 'ability')
check(entry.template.actions[2].name == 'Consumables' and entry.template.actions[2].type == 'consumable')
local menu = te:generateMenu()
local selector = menu.selectors['player.quickslots']
local selected = next(selector.byValue)
local definition = menu.definitions['player.quickslots'][selected]
check(#definition.shared == 4)
local values = {}; for _, row in ipairs(menu.rows) do values[row.Id] = tonumber(row.Default) end
values[selector.id] = selected
values[definition.access], values[definition.firstDefault] = 1, 1
values[definition.shared[1].mode], values[definition.groups['1'].mode] = 1, 2
local service = {}
local switcher = {id='quickslots-switcher', children={{id='wheel:1'}, {id='wheel:2'}}}
function switcher:GetChildrenCount() return #self.children end
function switcher:GetChildAt(index) return self.children[index + 1] end
function service:valid(object) return object ~= nil and object.dead ~= true end
function service:same(a, b) return rawequal(a, b) end
function service:identity(object) return object.id end
function service:parent(object) return object.parent end
local context = {playerActions = service,targets={['player.quickslots']=switcher}}
check(te.runtime:commit({revision = 1, values = values}, menu.decode, context))
check(entry.template.widgetRenderingEnabled == false)
check(te.runtime:render('player.quickslots', context, {kind='swap_prompt'}, 'created') == 'ignored')
-- Exercise visual implementation only on this in-memory test instance.
entry.template.widgetRenderingEnabled = true
local handle = te.runtime.active['player.quickslots'].handle
check(handle.settings.WheelsDisplayed == 2 and handle.settings.PrimaryWheel == 0)
check(handle.switcher == nil and handle.slots == nil)
values[definition.settings.PrimaryX] = 37
check(te.runtime:commit({revision = 2, values = values}, menu.decode, context))
check(te.runtime.active['player.quickslots'].handle == handle and handle.settings.PrimaryX == 37)
local _, committed = te.runtime:selection('player.quickslots')
check(committed.groups['1'].mode == 2 and committed.groups['2'].mode == 0 and committed.shared[1].mode == 1)
check(handle.settings ~= committed.settings)
for _, kind in ipairs({'wheel_layout', 'hud_indicators', 'ability_radial_indicators', 'swap_prompt'}) do
    check(te.runtime:render('player.quickslots', context, {kind=kind}, 'created') == 'not_ready')
end
check(te.runtime:render('player.quickslots', context, {kind='unknown'}, 'created') == 'ignored')

local prompt = {id='prompt', opacity=0.65, writes=0}
function prompt:GetRenderOpacity() return self.opacity end
function prompt:SetRenderOpacity(value) self.opacity=value; self.writes=self.writes+1 end
local promptTarget = {kind='swap_prompt', widget=prompt}
check(te.runtime:render('player.quickslots', context, promptTarget, 'created') == 'applied' and prompt.opacity == 0)
check(te.runtime:render('player.quickslots', context, promptTarget, 'created') == 'applied' and prompt.writes == 1)

local originals, groups = {}, {}
for group = 1, 2 do
    groups[group] = {indicators={}, actions={}}
    for slot = 1, 4 do
        local indicator = {id=group..':'..slot, EnhancedInputAction={id='original:'..group..':'..slot}}
        function indicator:SetEnhancedInputAction(action) self.EnhancedInputAction=action end
        originals[indicator] = indicator.EnhancedInputAction
        groups[group].indicators[slot], groups[group].actions[slot] = indicator, {id='assigned:'..group..':'..slot}
    end
end
check(te.runtime:render('player.quickslots', context, {kind='hud_indicators',groups=groups}, 'created') == 'applied')
for _, group in ipairs(groups) do
    for slot, indicator in ipairs(group.indicators) do check(indicator.EnhancedInputAction == group.actions[slot]) end
end
check(te.runtime:render('player.quickslots', context, {kind='ability_radial_indicators',
    indicators=groups[1].indicators,actions=groups[1].actions}, 'created') == 'applied')

-- TE owns callback exception containment; the actual QSF callbacks are not replaced.
local valid = service.valid
service.valid = function() error('engine validity failure') end
local status, failure = te.runtime:render('player.quickslots', context, promptTarget, 'created')
check(status == nil and failure:find('engine validity failure',1,true))
check(not te.runtime:detach('player.quickslots', context, 'none'))
check(te.runtime.active['player.quickslots'].handle == handle)
service.valid = valid
local foreign = {id='foreign'}
groups[2].indicators[4].EnhancedInputAction = foreign
entry.template.widgetRenderingEnabled = false
values[selector.id] = 0
check(te.runtime:commit({revision = 3, values = values}, menu.decode, context))
check(te.runtime:selection('player.quickslots') == nil and prompt.opacity == 0.65)
for indicator, original in pairs(originals) do
    check(indicator.EnhancedInputAction == (indicator == groups[2].indicators[4] and foreign or original))
end
check(te.runtime:detach('player.quickslots', context, 'none'))

values[selector.id] = selected
entry.template.widgetRenderingEnabled = true
check(te.runtime:commit({revision = 4, values = values}, menu.decode, context))
local invalidated = te.runtime.active['player.quickslots'].handle
check(te.runtime:render('player.quickslots', context, promptTarget, 'created') == 'applied')
service.valid = function() error('dead-world UObject touched') end
check(te.runtime:detach('player.quickslots', context, 'world_invalidated'))
check(next(invalidated.prompts) ~= nil) -- TE drops ownership without touching provider journals.
check(te.runtime:selection('player.quickslots') == nil)
entry.template.widgetRenderingEnabled = false
print('consumer: ' .. checks .. ' checks passed using actual QSF template and injected services')
