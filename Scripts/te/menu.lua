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
    local aggregateRows, pageRows, categoryLabels, currentCategory = {}, {}, {}, nil
    local function emit(section, fields)
        lines[#lines + 1] = '[' .. section .. ']'
        local names = {}; for name, value in pairs(fields) do
            if value ~= nil and name:sub(1, 1) ~= '_' then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do lines[#lines + 1] = name .. '=' .. tostring(fields[name]) end
        lines[#lines + 1] = ''
    end
    emit('Mod', {Id = 'UE4SSTemplatingEngine', Name = 'Templates', Version = '0.0.17',
        Description = options.description and text(options.description) or nil})
    local function row(fields)
        assert(#rows < 256, 'generated menu exceeds DMM limit of 256 settings')
        fields.ConfigFile, fields.ConfigSection, fields.ConfigKey = 'config.ini', 'Templates', fields.Id
        rows[#rows + 1] = fields
        fields._category = currentCategory
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
    local function group(identity, label, selector, selected, source, visible, level, heading, publicId)
        local groupId = publicId and namedId(publicId, {'group', identity}) or id({'group', identity})
        if not groups[groupId] then
            groups[groupId] = true
            local fields = {VisibleWhen = source, VisibleValues = visible,
                ammLevel = level or 3, ammHeading = heading, ammLabelWhen = selector,
                ammLabels = tostring(selected) .. ':' .. text(label)}
            groupSections[groupId] = fields
            groupOrder[#groupOrder + 1] = groupId
            emit('Category.' .. groupId, fields)
        end
        return groupId
    end
    local function binding(identity, label, groupId, source, visible, modeValues, publicId, defaultKey, defaultMode)
        local settingId = publicId and namedId(publicId, {'binding', identity}) or id({'binding', identity})
        local modeId = settingId .. 'Mode'
        row({Id = settingId, Type = 'integer', Label = text(label), Group = groupId,
            Minimum = 0, Maximum = 254, Step = 1, Default = defaultKey or 0, ammType = 'keybind', Pair = modeId,
            VisibleWhen = source, VisibleValues = visible})
        row({Id = modeId, Type = 'picker', Label = text(label .. ' mode'), Group = groupId,
            PresetValues = table.concat(modeValues, '|'), PresetLabels = 'Tap|Hold',
            Default = defaultMode == nil and modeValues[1] or defaultMode,
            ammType = 'keybind', VisibleWhen = source, VisibleValues = visible})
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
    for _, category in ipairs(registry.categories:list()) do
        local categoryLabel = (options.categoryLabels or {})[category]
            or title(category:gsub('%.', ' '))
        categoryLabels[category] = categoryLabel
        local available = perCategory[category]
        if not available then
            warnings[#warnings + 1] = category .. ': empty category omitted; DMM cannot render a None-only picker'
        else
            currentCategory = category
            local categorySingle = registry.categories:getCategory(category).single == true
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
                aggregateRows[#aggregateRows + 1] = rows[#rows]
                selectors[category] = {id = selector, byValue = byValue}
            else
                multiSelectors[category] = {}
            end
            decoded[category] = {}
            for _, entry in ipairs(available) do
                local template, identity = entry.template, storageIdentity(entry)
                local value = allocate({'template', identity})
                local templateScope
                if not categorySingle then templateScope = publicName(template.name) end
                local scopePrefix = templateScope and templateScope .. '_' or ''
                local definition = {id=entry.id,scope=templateScope,fields={},enabled=template.settings.enabled}
                decoded[category][value] = definition
                local ownerSelector, ownerValue = selector, value
                if not categorySingle then
                    ownerSelector = namedId('CategorySeparator_' .. templateScope,
                        {'template_toggle', identity})
                    ownerValue = 1
                    picker(ownerSelector, template.name, aggregateGroup, {0, 1}, {'No', 'Yes'},
                        nil, nil, true, 2, 440, 0)
                    aggregateRows[#aggregateRows + 1] = rows[#rows]
                    multiSelectors[category][#multiSelectors[category] + 1] = {
                        id=ownerSelector, value=value, definition=definition}
                end
                if category == 'player.quickslots' then
                    local ordered = V.orderedGroups(template, (options.groupOrders or {})[entry.id])
                    local access = namedId(scopePrefix .. 'AccessMethod', {'access', identity})
                    local accessGroup = group(key({identity, 'access'}), 'Access Method', ownerSelector, ownerValue,
                        ownerSelector, ownerValue, 3, 0, scopePrefix .. 'AccessMethodSection')
                    picker(access, 'Access Method', accessGroup, {0, 1},
                        {'1 key per slot', 'Activate group first'}, nil, nil, true, 2, nil, 1)
                    local default = namedId(scopePrefix .. 'FirstGroupDefault', {'first_default', identity})
                    picker(default, 'First group is default (needs no key)', accessGroup,
                        {0, 1}, {'Off', 'On'}, access, 1, true, nil, nil, 0)
                    definition.access, definition.firstDefault = access, default
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
                                'Slot ' .. slotIndex .. ' (' .. g.type .. ')', directGroup, nil, nil, slotModes,
                                scopePrefix .. 'Slot' .. slotIndex, quickslotDefaults.slots[nativeSlot], defaultMode)
                        end
                    end
                    local activateGroup = group(key({identity, 'groups'}), 'Groups', ownerSelector, ownerValue,
                        access, 1, nil, nil, scopePrefix .. 'Groups')
                    for index, item in ipairs(ordered) do
                        local g = item.value
                        definition.groups[item.key] = binding(key({identity, 'activate', g.name}), g.name,
                            activateGroup, index == 1 and default or nil, index == 1 and 0 or nil, {0, 2},
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
                if template.settings then
                    definition.settings = {}
                    for _, providerGroup in ipairs(Provider.normalize(template.settings)) do
                        local groupId = group(key({identity, 'provider', providerGroup.id}), providerGroup.label,
                            ownerSelector, ownerValue, ownerSelector, ownerValue, providerGroup.level, nil,
                            scopePrefix .. publicName(providerGroup.id))
                        for _, field in ipairs(providerGroup.fields) do
                            local settingId = namedId(scopePrefix .. publicName(field.id),
                                {'provider', identity, field.id})
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
                            definition.settings[field.id] = settingId
                        end
                    end
                end
            end
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
        append(output, 'Mod', {Id=providerId, Name=providerName, Version='0.0.17',
            Description=options.description and text(options.description) or nil})
        local usedGroups = {}
        for _, item in ipairs(selectedRows) do usedGroups[item.Group] = true end
        for _, groupId in ipairs(aggregateGroupOrder) do
            if usedGroups[groupId] then
                append(output, 'Category.' .. groupId, aggregatePage and {} or {ammHeading=0})
            end
        end
        for _, groupId in ipairs(groupOrder) do
            if usedGroups[groupId] then append(output, 'Category.' .. groupId, groupSections[groupId]) end
        end
        for _, item in ipairs(selectedRows) do append(output, 'Setting.' .. item.Id, item) end
        local manifest = table.concat(output, '\n')
        assert(#manifest <= 256 * 1024, 'generated manifest exceeds 256 KiB')
        return manifest
    end
    local schema = {}
    for _, r in ipairs(rows) do schema[r.Id] = r end
    local function makeDecoder(requiredRows, includedCategories)
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
        local function readSelection(definition)
            local selection = {configuration = {}}
            if not definition then return selection end
            selection.id = definition.id
            local config = selection.configuration
            if definition.settings then
                config.settings = {}
                for field, settingId in pairs(definition.settings) do config.settings[field] = effective[settingId] end
            end
            if definition.access then
                config.access = effective[definition.access]
                config.firstGroupDefault = config.access == 1 and effective[definition.firstDefault] == 1
                config.direct, config.groups, config.shared = {}, {}, {}
                for groupKey, slots in pairs(definition.direct) do
                    config.direct[groupKey] = {}
                    for i, pair in ipairs(slots) do config.direct[groupKey][i] = readBinding(pair) end
                end
                for groupKey, pair in pairs(definition.groups) do config.groups[groupKey] = readBinding(pair) end
                for i, pair in ipairs(definition.shared) do config.shared[i] = readBinding(pair) end
            end
            return selection
        end
        for category, selector in pairs(selectors) do
          if not includedCategories or includedCategories[category] then
            local definition = decoded[category][effective[selector.id]]
            result[category] = readSelection(definition)
          end
        end
        for category, templates in pairs(multiSelectors) do
          if not includedCategories or includedCategories[category] then
            local selections = {}
            for _, item in ipairs(templates) do
                if effective[item.id] == 1 then
                    selections[#selections + 1] = readSelection(item.definition)
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
    local pages, pageByCategory, providers = {}, {}, {[aggregateId]=aggregate}
    for _, category in ipairs(registry.categories:list()) do
        if selectors[category] or multiSelectors[category] then
            local providerId = aggregateId .. '.' .. category
            local included, selectedRows = {[category]=true}, pageRows[category]
            local page = {id=providerId, name=categoryLabels[category], category=category,
                rows=selectedRows, manifest=providerManifest(providerId, categoryLabels[category], selectedRows, false)}
            page.decode = makeDecoder(page.rows, included)
            pages[#pages + 1], pageByCategory[category], providers[providerId] = page, page, page
        end
    end
    return {manifest = aggregateManifest, fullManifest = table.concat(lines, '\n'), catalog = catalog,
        rows = rows, selectors = selectors, multiSelectors=multiSelectors, definitions = decoded, warnings = warnings,
        decode = makeDecoder(rows, allCategories), aggregate=aggregate, pages=pages,
        pageByCategory=pageByCategory, providers=providers}
end

return M
