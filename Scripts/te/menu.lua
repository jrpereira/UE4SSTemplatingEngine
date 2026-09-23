local U = require('te.util')
local V = require('te.validation')
local Provider = require('te.provider_settings')
local M = {}

local function text(value)
    U.text(value, 'menu text')
    assert(not value:find('[%c|;%[%]]') and not value:match('^%s') and not value:match('%s$'),
        'menu text contains unsupported separators, controls, or edge whitespace')
    assert(#value <= 4096, 'menu text too long')
    return value
end

local function key(parts)
    local out = {}
    for _, part in ipairs(parts) do part = tostring(part); out[#out + 1] = #part .. ':' .. part end
    return table.concat(out)
end

local function title(value)
    return value:gsub('_', ' '):gsub('(%a)([%w_]*)', function(a, b) return a:upper() .. b end)
end

-- The returned catalog must be persisted alongside the manifest before startup.
-- Removed mappings remain reserved, preventing saved numeric choices from changing meaning.
function M.generate(registry, options)
    options = options or {}
    local slotModes = options.slotModeValues or {0, 1}
    assert(U.array(slotModes, 'slot mode values') == 2, 'slot modes require exactly Tap and Hold values')
    for _, mode in ipairs(slotModes) do
        assert(type(mode) == 'number' and mode == mode and math.abs(mode) <= 1000000000,
            'slot modes must be finite DMM numeric values')
    end
    assert(slotModes[1] ~= slotModes[2], 'slot modes must be distinct')
    local catalog = U.copy(options.catalog or {version = 1, next = 1, entries = {}})
    assert(catalog.version == 1 and type(catalog.entries) == 'table', 'invalid identity catalog')
    assert(type(catalog.next) == 'number' and catalog.next >= 1 and catalog.next % 1 == 0
        and catalog.next <= 1000000001, 'invalid catalog counter')
    local occupied = {}
    for name, value in pairs(catalog.entries) do
        assert(type(name) == 'string' and type(value) == 'number' and value >= 1
            and value % 1 == 0 and value <= 1000000000 and value < catalog.next and not occupied[value], 'invalid catalog entry')
        occupied[value] = true
    end
    local function allocate(parts)
        local name = key(parts)
        if not catalog.entries[name] then
            assert(catalog.next <= 1000000000, 'identity catalog exhausted')
            catalog.entries[name] = catalog.next
            catalog.next = catalog.next + 1
        end
        return catalog.entries[name]
    end
    local function id(parts) return 'TE_' .. allocate(parts) end
    local publicIds = {}
    local function namedId(name, fallback)
        local settingId = 'TE_' .. name
        if publicIds[settingId] then settingId = id(fallback) end
        publicIds[settingId] = true
        return settingId
    end
    local function publicName(value)
        local result = tostring(value):gsub('[^%w]+', ' ')
            :gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end)
            :gsub('%s+', '')
        assert(result ~= '', 'public menu name is empty')
        return result
    end
    local quickslotDefaults = options.quickslotDefaults or {swap = 164, slots = {49, 50, 51, 52}}
    assert(type(quickslotDefaults) == 'table' and type(quickslotDefaults.slots) == 'table',
        'quickslot defaults must define swap and slots')
    assert(type(quickslotDefaults.swap) == 'number' and quickslotDefaults.swap >= 0
        and quickslotDefaults.swap <= 254 and quickslotDefaults.swap % 1 == 0,
        'quickslot swap default must be a key code')
    for slot = 1, 4 do
        local value = quickslotDefaults.slots[slot]
        assert(type(value) == 'number' and value >= 0 and value <= 254 and value % 1 == 0,
            'quickslot slot defaults must contain four key codes')
    end
    local lines, rows, groups, bindings, selectors, multiSelectors, warnings = {}, {}, {}, {}, {}, {}, {}
    local groupSections, groupOrder = {}, {}
    local aggregateGroups, aggregateGroupOrder = {}, {}
    local aggregateRows, pageRows, categoryLabels, currentCategory, currentOwner = {}, {}, {}, nil, nil
    local function emit(section, fields)
        lines[#lines + 1] = '[' .. section .. ']'
        local names = {}; for name, value in pairs(fields) do
            if value ~= nil and name:sub(1, 1) ~= '_' then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do lines[#lines + 1] = name .. '=' .. tostring(fields[name]) end
        lines[#lines + 1] = ''
    end
    emit('Mod', {Id = 'UE4SSTemplatingEngine', Name = 'Templates', Version = '0.0.18',
        Description = options.description and text(options.description) or nil})
    local function row(fields)
        assert(#rows < 256, 'generated menu exceeds DMM limit of 256 settings')
        fields.ConfigFile, fields.ConfigSection, fields.ConfigKey = 'config.ini', 'Templates', fields.Id
        rows[#rows + 1] = fields
        fields._category = currentCategory
        fields._owner = currentOwner
        pageRows[currentCategory] = pageRows[currentCategory] or {}
        pageRows[currentCategory][#pageRows[currentCategory] + 1] = fields
        emit('Setting.' .. fields.Id, fields)
        return fields.Id
    end
    local function picker(settingId, label, group, values, labels, source, visible, compact, level, tabsWidth, default)
        return row({Id = settingId, Label = text(label), Group = group, Type = 'picker',
            PresetValues = table.concat(values, '|'), PresetLabels = table.concat(labels, '|'),
            Default = default == nil and values[1] or default,
            VisibleWhen = source, VisibleValues = visible, ammLevel = level,
            ammType = compact and #values <= 8 and 'tab' or nil,
            ammTabsWidth = compact and #values <= 8 and tabsWidth or nil})
    end
    local function group(identity, label, selector, selected, source, visible, level, heading, publicId,
        labelValues)
        local groupId = publicId and namedId(publicId, {'group', identity}) or id({'group', identity})
        if not groups[groupId] then
            groups[groupId] = true
            local labels = {}
            if labelValues then
                for index = 2, #labelValues do
                    labels[#labels + 1] = tostring(labelValues[index]) .. ':' .. text(label)
                end
            else
                labels[1] = tostring(selected) .. ':' .. text(label)
            end
            local fields = {VisibleWhen = source, VisibleValues = visible,
                ammLevel = level or 3, ammHeading = heading, ammLabelWhen = selector,
                ammLabels = table.concat(labels, ';')}
            groupSections[groupId] = fields
            groupOrder[#groupOrder + 1] = groupId
            emit('Category.' .. groupId, fields)
        end
        return groupId
    end
    local function binding(identity, label, groupId, source, visible, modeValues, publicId, defaultKey, defaultMode)
        local settingId = publicId and namedId(publicId, {'binding', identity}) or id({'binding', identity})
        local modeId = settingId .. 'Mode'
        local modeLabels = #modeValues == 3 and modeValues[3] == -1 and 'Tap|Hold|Default' or 'Tap|Hold'
        row({Id = settingId, Type = 'integer', Label = text(label), Group = groupId,
            Minimum = 0, Maximum = 254, Step = 1, Default = defaultKey or 0, ammType = 'keybind',
            VisibleWhen = source, VisibleValues = visible})
        row({Id = modeId, Type = 'picker', Label = text(label), Group = groupId,
            PresetValues = table.concat(modeValues, '|'), PresetLabels = modeLabels,
            Default = defaultMode == nil and modeValues[1] or defaultMode,
            ammType = 'tab', Pair = settingId, VisibleWhen = source, VisibleValues = visible})
        bindings[identity] = {key = settingId, mode = modeId}
        return bindings[identity]
    end
    local entries = {}; for _, entry in ipairs(registry.templates) do entries[#entries + 1] = entry end
    table.sort(entries, function(a, b) return a.id < b.id end)
    local perCategory = {}
    for _, entry in ipairs(entries) do
        local category = entry.template.category
        perCategory[category] = perCategory[category] or {}
        table.insert(perCategory[category], entry)
    end
    local function storageIdentity(entry) return entry.id end
    local decoded = {}
    local categorySettings = {}
    local textSettings = {}
    for _, category in ipairs(registry.categories:list()) do
        local categoryLabel = (options.categoryLabels or {})[category]
            or title(category:gsub('%.', ' '))
        categoryLabels[category] = categoryLabel
        local available = perCategory[category]
        if not available then
            warnings[#warnings + 1] = category .. ': empty category omitted; DMM cannot render a None-only picker'
        else
            currentCategory = category
            local categorySingle = available[1].single == true
            for _, entry in ipairs(available) do
                assert((entry.single == true) == categorySingle,
                    category .. ': templates disagree on single')
            end
            assert(#available <= 63, category .. ': more than 63 templates exceeds picker capacity including None')
            local selector
            local values, labels, byValue = {0}, {'None'}, {}
            for _, entry in ipairs(available) do
                local value = allocate({'template', storageIdentity(entry)})
                values[#values + 1], labels[#labels + 1] = value, text(entry.template.name)
                byValue[value] = entry.id
            end
            local prefix, suffix = assert(category:match('^([^.]+)%.([^.]+)$'))
            local aggregateGroup = title(prefix)
            if not aggregateGroups[aggregateGroup] then
                aggregateGroups[aggregateGroup] = true
                aggregateGroupOrder[#aggregateGroupOrder + 1] = aggregateGroup
                emit('Category.' .. aggregateGroup, {})
            end
            if categorySingle then
                local selectorName = category == 'player.quickslots' and 'Template'
                    or publicName(category) .. 'Template'
                selector = namedId(selectorName, {'selector', category})
                picker(selector, title(suffix), aggregateGroup, values, labels, nil, nil, true, 2, 440)
                rows[#rows]._control = true
                aggregateRows[#aggregateRows + 1] = rows[#rows]
                selectors[category] = {id = selector, byValue = byValue}
            else
                multiSelectors[category] = {}
            end
            decoded[category] = {}
            local categoryGroups, staticSettings, staticFormats = Provider.normalizeCategory(
                registry.categories:getCategory(category).settings)
            local sharedFields, textIds = {}, {}
            categorySettings[category] = {fields=sharedFields, static=staticSettings, textIds=textIds}
            for field, default in pairs(staticSettings) do
                local settingId = namedId(publicName(category) .. publicName(field),
                    {'category_text', category, field})
                textIds[field] = settingId
                textSettings[settingId] = {default=default, format=staticFormats[field]}
            end
            local visibleValues = categorySingle and table.concat(values, '|', 2) or nil
            for _, providerGroup in ipairs(categoryGroups) do
                local groupId = group(key({category, 'category_provider', providerGroup.id}),
                    providerGroup.label, selector, values[2], selector, visibleValues,
                    providerGroup.level, providerGroup.heading == false and 0 or nil,
                    publicName(category) .. publicName(providerGroup.id), categorySingle and values or nil)
                for _, field in ipairs(providerGroup.fields) do
                    local settingId = namedId(publicName(category) .. publicName(field.id),
                        {'category_provider', category, field.id})
                    local metadata = {Id=settingId, Label=field.label, Group=groupId, Type=field.type,
                        Default=field.default, Description=field.description, ammLevel=field.level}
                    if field.type == 'picker' then
                        metadata.PresetValues = table.concat(field.values, '|')
                        metadata.PresetLabels = table.concat(field.labels, '|')
                        metadata.ammType = field.tab and 'tab' or nil
                    else
                        metadata.Minimum, metadata.Maximum, metadata.Step = field.min, field.max, field.step
                        metadata.Suffix = field.suffix
                    end
                    row(metadata)
                    rows[#rows]._control = true
                    aggregateRows[#aggregateRows + 1] = rows[#rows]
                    sharedFields[field.id] = settingId
                end
            end
            local sharedQuickslots
            if category == 'player.quickslots' and sharedFields.AccessMode then
                local actions = registry.categories:getCategory(category).actions
                local ordered = V.orderedGroups({name=category}, nil, actions)
                local access = sharedFields.AccessMode
                sharedQuickslots = {access=access, categoryAccess=true,
                    direct={}, groups={}, shared={}, advanced={}}
                local function sharedBinding(identity, label, groupId, publicId, defaultKey, defaultMode, modes)
                    local pair = binding(identity, label, groupId, nil, nil, modes or slotModes,
                        publicId, defaultKey, defaultMode)
                    for index = #rows - 1, #rows do
                        rows[index]._control = true
                        aggregateRows[#aggregateRows + 1] = rows[index]
                    end
                    return pair
                end
                local maxSlots, slotIndex, groupNames = 0, 0, {}
                for _, item in ipairs(ordered) do
                    local g = item.value
                    assert(not groupNames[g.name], 'category action group names must be unique')
                    groupNames[g.name] = true
                    maxSlots = math.max(maxSlots, g.slots)
                    local directGroup = group(key({category, 'direct', g.name}), g.name,
                        selector, values[2], access, 1, 5, nil,
                        publicName(category) .. publicName(g.name), values)
                    sharedQuickslots.direct[item.key] = {}
                    for slot = 1, g.slots do
                        slotIndex = slotIndex + 1
                        local nativeSlot = ((slotIndex - 1) % 4) + 1
                        local defaultMode = slotIndex > 4 and slotModes[2] or slotModes[1]
                        local slotName = g.slotNames and g.slotNames[slot] or tostring(slot)
                        sharedQuickslots.direct[item.key][slot] = sharedBinding(
                            key({category, 'direct', g.type, slotName}),
                            'Slot ' .. slot, directGroup,
                            publicName(category) .. publicName(g.type) .. publicName(slotName),
                            quickslotDefaults.slots[nativeSlot], defaultMode)
                    end
                end
                local activateGroup = group(key({category, 'groups'}), 'Groups',
                    selector, values[2], access, 0, nil, nil,
                    publicName(category) .. 'Groups', values)
                for index, item in ipairs(ordered) do
                    local g = item.value
                    local modes = index == 1 and {0, 2, -1} or {0, 2}
                    sharedQuickslots.groups[item.key] = sharedBinding(
                        key({category, 'activate', g.type}), g.name, activateGroup,
                        publicName(category) .. 'Group' .. publicName(g.type),
                        index == 2 and quickslotDefaults.swap or 0, 0, modes)
                end
                local sharedGroup = group(key({category, 'slots'}), 'Slots',
                    selector, values[2], access, 0, nil, nil,
                    publicName(category) .. 'Slots', values)
                for slot = 1, maxSlots do
                    sharedQuickslots.shared[slot] = sharedBinding(
                        key({category, 'shared', slot}), 'Slot ' .. slot, sharedGroup,
                        publicName(category) .. 'SharedSlot' .. slot,
                        quickslotDefaults.slots[((slot - 1) % 4) + 1], slotModes[1])
                end
                local advancedGroup = group(key({category, 'advanced'}), 'Group Keys Per Slot',
                    selector, values[2], access, 2, nil, nil,
                    publicName(category) .. 'Advanced', values)
                for _, item in ipairs(ordered) do
                    local g = item.value
                    sharedQuickslots.advanced[item.key] = {}
                    for slot = 1, g.slots do
                        local slotName = g.slotNames and g.slotNames[slot] or tostring(slot)
                        sharedQuickslots.advanced[item.key][slot] = sharedBinding(
                            key({category, 'advanced', g.type, slotName}),
                            g.name .. ' ' .. slotName .. ' group key', advancedGroup,
                            publicName(category) .. 'GroupKey' .. publicName(g.type) .. publicName(slotName),
                            0, slotModes[1])
                    end
                end
            end
            for _, entry in ipairs(available) do
                local template, identity = entry.template, storageIdentity(entry)
                currentOwner = identity
                local value = allocate({'template', identity})
                local templateScope
                if not categorySingle then templateScope = publicName(template.name) end
                local scopePrefix = templateScope and templateScope .. '_' or ''
                local definition = {id=entry.id,scope=templateScope,fields={},enabled=template.settings.enabled}
                local providerGroups = Provider.normalize(template.settings)
                definition.settings = {}
                decoded[category][value] = definition
                local ownerSelector, ownerValue = selector, value
                if not categorySingle then
                    ownerSelector = namedId('CategorySeparator_' .. templateScope,
                        {'template_toggle', identity})
                    ownerValue = 1
                    picker(ownerSelector, template.name, aggregateGroup, {0, 1}, {'No', 'Yes'},
                        nil, nil, true, 2, 440, 0)
                    rows[#rows]._control = true
                    aggregateRows[#aggregateRows + 1] = rows[#rows]
                    multiSelectors[category][#multiSelectors[category] + 1] = {
                        id=ownerSelector, value=value, definition=definition}
                end
                local function emitProviderFields(after)
                    for _, providerGroup in ipairs(providerGroups) do
                        local groupId
                        for _, field in ipairs(providerGroup.fields) do
                            if field.after == after then
                                assert(not field.after or category == 'player.quickslots',
                                    'AccessMethod placement requires player.quickslots')
                                groupId = groupId or group(key({identity, 'provider', providerGroup.id}),
                                    providerGroup.label, ownerSelector, ownerValue, ownerSelector, ownerValue,
                                    providerGroup.level, providerGroup.heading == false and 0 or nil,
                                    scopePrefix .. publicName(providerGroup.id))
                                local settingId = namedId(scopePrefix .. publicName(field.id),
                                    {'provider', identity, field.id})
                                local metadata = {Id=settingId, Label=field.label, Group=groupId, Type=field.type,
                                    Default=field.default, Description=field.description, ammLevel=field.level}
                                if field.visibleWhen then
                                    local sourceId = definition.settings[field.visibleWhen]
                                    assert(sourceId, 'provider visibility source must precede dependent field: '
                                        .. field.id)
                                    metadata.VisibleWhen = sourceId
                                    metadata.VisibleValues = table.concat(field.visibleValues, '|')
                                end
                                if field.type == 'picker' then
                                    metadata.PresetValues = table.concat(field.values, '|')
                                    metadata.PresetLabels = table.concat(field.labels, '|')
                                    metadata.ammType = field.tab and 'tab' or nil
                                else
                                    metadata.Minimum, metadata.Maximum, metadata.Step = field.min, field.max, field.step
                                    metadata.Suffix = field.suffix
                                end
                                row(metadata)
                                definition.settings[field.id] = settingId
                            end
                        end
                    end
                end
                if sharedQuickslots then
                    definition.access = sharedQuickslots.access
                    definition.categoryAccess = true
                    definition.direct = sharedQuickslots.direct
                    definition.groups = sharedQuickslots.groups
                    definition.shared = sharedQuickslots.shared
                    definition.advanced = sharedQuickslots.advanced
                    emitProviderFields('AccessMethod')
                elseif category == 'player.quickslots' then
                    local ordered = V.orderedGroups(template, (options.groupOrders or {})[entry.id],
                        registry.categories:getCategory(category).actions)
                    local access = namedId(scopePrefix .. 'AccessMethod', {'access', identity})
                    local accessGroup = group(key({identity, 'access'}), 'Input Method', ownerSelector, ownerValue,
                        ownerSelector, ownerValue, 3, 0, scopePrefix .. 'AccessMethodSection')
                    picker(access, 'Input Method', accessGroup, {0, 1},
                        {'1 key per slot', 'Activate group first'}, nil, nil, true, 2, 440, 1)
                    definition.access = access
                    emitProviderFields('AccessMethod')
                    definition.direct, definition.groups, definition.shared = {}, {}, {}
                    local maxSlots, slotIndex, groupNames = 0, 0, {}
                    for index, item in ipairs(ordered) do
                        local g = item.value
                        assert(not groupNames[g.name], 'action group names must be unique for stable menu identity')
                        groupNames[g.name] = true
                        maxSlots = math.max(maxSlots, g.slots)
                        assert(g.slots <= 126, 'group slot count exceeds menu capacity')
                        local directGroup = group(key({identity, 'direct', g.name}), g.name, ownerSelector, ownerValue,
                            access, 0, 5, nil, scopePrefix .. publicName(g.name))
                        definition.direct[item.key] = {}
                        for slot = 1, g.slots do
                            slotIndex = slotIndex + 1
                            local nativeSlot = ((slotIndex - 1) % 4) + 1
                            local defaultMode = slotIndex > 4 and slotModes[2] or slotModes[1]
                            definition.direct[item.key][slot] = binding(key({identity, 'direct', g.name, slot}),
                                'Slot ' .. slot, directGroup, nil, nil, slotModes,
                                scopePrefix .. 'Slot' .. slotIndex, quickslotDefaults.slots[nativeSlot], defaultMode)
                        end
                    end
                    local activateGroup = group(key({identity, 'groups'}), 'Groups', ownerSelector, ownerValue,
                        access, 1, nil, nil, scopePrefix .. 'Groups')
                    for index, item in ipairs(ordered) do
                        local g = item.value
                        local modes = index == 1 and {0, 2, -1} or {0, 2}
                        definition.groups[item.key] = binding(key({identity, 'activate', g.name}), g.name,
                            activateGroup, nil, nil, modes,
                            scopePrefix .. 'Group' .. index, index == 2 and quickslotDefaults.swap or 0, 0)
                    end
                    local sharedGroup = group(key({identity, 'slots'}), 'Slots', ownerSelector, ownerValue,
                        access, 1, nil, nil, scopePrefix .. 'Slots')
                    for slot = 1, maxSlots do
                        definition.shared[slot] = binding(key({identity, 'shared', slot}), 'Slot ' .. slot,
                            sharedGroup, nil, nil, slotModes, scopePrefix .. 'SharedSlot' .. slot,
                            quickslotDefaults.slots[((slot - 1) % 4) + 1], slotModes[1])
                    end
                else
                    warnings[#warnings + 1] = category .. ': no category-specific renderer defined'
                end
                emitProviderFields(nil)
            end
            currentOwner = nil
        end
    end
    currentCategory = nil
    local function append(target, section, fields)
        target[#target + 1] = '[' .. section .. ']'
        local names = {}
        for name, value in pairs(fields) do
            if value ~= nil and name:sub(1, 1) ~= '_' then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do target[#target + 1] = name .. '=' .. tostring(fields[name]) end
        target[#target + 1] = ''
    end
    local function providerManifest(providerId, providerName, selectedRows, aggregatePage)
        local output = {}
        append(output, 'Mod', {Id=providerId, Name=providerName, Version='0.0.18',
            Description=options.description and text(options.description) or nil})
        local usedGroups, visibleGroups, hiddenByGroup = {}, {}, {}
        for _, item in ipairs(selectedRows) do
            usedGroups[item.Group] = true
            if item._routeHidden then hiddenByGroup[item.Group] = hiddenByGroup[item.Group] or item
            else visibleGroups[item.Group] = true end
        end
        for _, groupId in ipairs(aggregateGroupOrder) do
            if usedGroups[groupId] then
                append(output, 'Category.' .. groupId, aggregatePage and {} or {ammHeading=0})
            end
        end
        for _, groupId in ipairs(groupOrder) do
            if usedGroups[groupId] then
                local fields = groupSections[groupId]
                if not visibleGroups[groupId] then
                    fields = U.copy(fields)
                    fields.VisibleWhen = hiddenByGroup[groupId]._hideWhen
                    fields.VisibleValues = hiddenByGroup[groupId]._hideValue
                end
                append(output, 'Category.' .. groupId, fields)
            end
        end
        for _, item in ipairs(selectedRows) do append(output, 'Setting.' .. item.Id, item) end
        local manifest = table.concat(output, '\n')
        assert(#manifest <= 256 * 1024, 'generated manifest exceeds 256 KiB')
        return manifest
    end
    local schema = {}
    for _, r in ipairs(rows) do schema[r.Id] = r end
    local function makeDecoder(requiredRows, includedCategories, owned)
      return function(values)
        assert(type(values) == 'table', 'Apply values must be a table')
        local effective = {}
        for settingId, r in pairs(schema) do effective[settingId] = tonumber(r.Default) end
        for _, r in ipairs(requiredRows) do
            local settingId = r.Id
            local value = values[settingId]
            assert(type(value) == 'number' and value == value, 'missing/invalid setting ' .. settingId)
            if r.Type == 'integer' then
                assert(value >= r.Minimum and value <= r.Maximum and value % 1 == 0,
                    (r.ammType == 'keybind' and 'invalid key ' or 'invalid integer ') .. settingId)
            else
                local found = false
                for candidate in r.PresetValues:gmatch('[^|]+') do if value == tonumber(candidate) then found = true end end
                assert(found, 'invalid choice ' .. settingId)
            end
            effective[settingId] = value
        end
        local result = {}
        local function readBinding(pair) return {key = effective[pair.key], mode = effective[pair.mode]} end
        local function readSelection(definition, category)
            local selection = {settings = {}}
            if not definition then return selection end
            selection.id = definition.id
            local config = selection.settings
            local shared = categorySettings[category]
            if shared then
                for field, default in pairs(shared.static) do
                    local supplied = values[shared.textIds[field]]
                    config[field] = supplied == nil and default or supplied
                end
                for field, settingId in pairs(shared.fields) do
                    config[field] = effective[settingId]
                end
                Provider.validateCategory(registry.categories:getCategory(category).settings, config)
            end
            if definition.settings then
                for field, settingId in pairs(definition.settings) do
                    config[field] = effective[settingId]
                end
            end
            if definition.access then
                local selectedAccess = effective[definition.access]
                config.access = definition.categoryAccess
                    and (selectedAccess == 0 and 1 or selectedAccess == 1 and 0 or 2)
                    or selectedAccess
                config.firstGroupDefault = false
                config.direct, config.groups, config.shared = {}, {}, {}
                for groupKey, slots in pairs(definition.direct) do
                    config.direct[groupKey] = {}
                    for i, pair in ipairs(slots) do config.direct[groupKey][i] = readBinding(pair) end
                end
                for groupKey, pair in pairs(definition.groups) do config.groups[groupKey] = readBinding(pair) end
                for i, pair in ipairs(definition.shared) do config.shared[i] = readBinding(pair) end
                if definition.advanced then
                    config.advanced = {}
                    for groupKey, slots in pairs(definition.advanced) do
                        config.advanced[groupKey] = {}
                        for i, pair in ipairs(slots) do
                            config.advanced[groupKey][i] = readBinding(pair)
                        end
                    end
                end
            end
            return selection
        end
        for category, selector in pairs(selectors) do
          if not includedCategories or includedCategories[category] then
            local definition = decoded[category][effective[selector.id]]
            if not owned or not definition or owned[definition.id] then
                result[category] = readSelection(definition, category)
            end
          end
        end
        for category, templates in pairs(multiSelectors) do
          if not includedCategories or includedCategories[category] then
            local selections = {}
            if owned then selections._partial, selections._known = true, {} end
            for _, item in ipairs(templates) do
                if not owned or owned[item.definition.id] then
                    if owned then selections._known[item.definition.id] = true end
                if effective[item.id] == 1 then
                    selections[#selections + 1] = readSelection(item.definition, category)
                end
                end
            end
            result[category] = selections
          end
        end
        return result
      end
    end
    local aggregateId = 'UE4SSTemplatingEngine'
    local aggregateManifest = providerManifest(aggregateId, 'Templates', aggregateRows, true)
    local allCategories = {}; for category in pairs(selectors) do allCategories[category] = true end
    for category in pairs(multiSelectors) do allCategories[category] = true end
    local aggregate = {id=aggregateId, name='Templates', manifest=aggregateManifest, rows=aggregateRows,
        decode=makeDecoder(aggregateRows, allCategories)}
    local pages, pageByCategory, pageByModule, providers = {}, {}, {}, {[aggregateId]=aggregate}
    local ownerControls = {}
    for category, selector in pairs(selectors) do
        for _, definition in pairs(decoded[category]) do
            ownerControls[definition.id] = {id=selector.id, impossible=-1}
        end
    end
    for _, templates in pairs(multiSelectors) do
        for _, item in ipairs(templates) do ownerControls[item.definition.id] = {id=item.id, impossible=2} end
    end
    local function routedRows(categories, owned)
        local selected = {}
        for _, item in ipairs(rows) do
            if categories[item._category] then
                if item._control or (item._owner and owned[item._owner]) then
                    selected[#selected + 1] = item
                elseif item._owner then
                    local hidden, control = U.copy(item), assert(ownerControls[item._owner])
                    hidden._routeHidden, hidden._hideWhen, hidden._hideValue = true, control.id, control.impossible
                    selected[#selected + 1] = hidden
                end
            end
        end
        return selected
    end
    local categoryOwned, moduleOwned, moduleCategories = {}, {}, {}
    for _, entry in ipairs(entries) do
        local template = entry.template
        if template.settings.target == 'templates' then
            categoryOwned[template.category] = categoryOwned[template.category] or {}
            categoryOwned[template.category][entry.id] = true
        else
            local normalized = entry.location:gsub('\\', '/'):gsub('%[%d+%]$', '')
            local parent = normalized:match('^(.*)/Scripts/templates/[^/]+%.lua$')
                or normalized:match('^(.*)/Scripts/[^/]+%.lua$')
                or normalized:match('^(.*)/templates/[^/]+%.lua$')
            local module = parent and parent:match('([^/]+)$')
            assert(module and module ~= '', entry.location
                .. ': target=module requires a <Module>/Scripts/<file>.lua or '
                .. '<Module>/Scripts/templates/<file>.lua registration path')
            moduleOwned[module], moduleCategories[module] = moduleOwned[module] or {}, moduleCategories[module] or {}
            moduleOwned[module][entry.id], moduleCategories[module][template.category] = true, true
        end
    end
    for _, category in ipairs(registry.categories:list()) do
        if categoryOwned[category] then
            local providerId = aggregateId .. '.' .. category
            local included = {[category]=true}
            local selectedRows = routedRows(included, categoryOwned[category])
            local page = {id=providerId, name=categoryLabels[category], category=category,
                rows=selectedRows, manifest=providerManifest(providerId, categoryLabels[category], selectedRows, false)}
            page.decode = makeDecoder(page.rows, included)
            pages[#pages + 1], pageByCategory[category], providers[providerId] = page, page, page
        end
    end
    local moduleNames = {}; for module in pairs(moduleOwned) do moduleNames[#moduleNames + 1] = module end
    table.sort(moduleNames)
    for _, module in ipairs(moduleNames) do
        local providerId = aggregateId .. '.module.' .. publicName(module)
        local selectedRows = routedRows(moduleCategories[module], moduleOwned[module])
        local page = {id=providerId, name=module, module=module, rows=selectedRows,
            manifest=providerManifest(providerId, module, selectedRows, false)}
        page.decode = makeDecoder(page.rows, moduleCategories[module], moduleOwned[module])
        pages[#pages + 1], pageByModule[module], providers[providerId] = page, page, page
    end
    return {manifest = aggregateManifest, fullManifest = table.concat(lines, '\n'), catalog = catalog,
        rows = rows, selectors = selectors, multiSelectors=multiSelectors, definitions = decoded, warnings = warnings,
        textSettings = textSettings,
        decode = makeDecoder(rows, allCategories), aggregate=aggregate, pages=pages,
        pageByCategory=pageByCategory, pageByModule=pageByModule, providers=providers}
end

return M
