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
    local lines, rows, groups, bindings, selectors, warnings = {}, {}, {}, {}, {}, {}
    local groupSections, groupOrder = {}, {}
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
    emit('Category.Templates', {DecoHeading = 0})
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
    local function picker(settingId, label, group, values, labels, source, visible, compact, level)
        return row({Id = settingId, Label = text(label), Group = group, Type = 'picker',
            PresetValues = table.concat(values, '|'), PresetLabels = table.concat(labels, '|'), Default = values[1],
            VisibleWhen = source, VisibleValues = visible, DecoLevel = level,
            DecoType = compact and #values <= 8 and 'tab' or nil})
    end
    local function group(identity, label, selector, selected, source, visible, level, heading)
        local groupId = id({'group', identity})
        if not groups[groupId] then
            groups[groupId] = true
            local fields = {VisibleWhen = source, VisibleValues = visible,
                DecoLevel = level or 3, DecoHeading = heading, DecoLabelWhen = selector,
                DecoLabels = tostring(selected) .. ':' .. text(label)}
            groupSections[groupId] = fields
            groupOrder[#groupOrder + 1] = groupId
            emit('Category.' .. groupId, fields)
        end
        return groupId
    end
    local function binding(identity, label, groupId, source, visible, modeValues)
        local settingId = id({'binding', identity})
        local modeId = settingId .. 'Mode'
        row({Id = settingId, Type = 'integer', Label = text(label), Group = groupId,
            Minimum = 0, Maximum = 254, Step = 1, Default = 0, DecoType = 'keybind', Pair = modeId,
            VisibleWhen = source, VisibleValues = visible})
        row({Id = modeId, Type = 'picker', Label = text(label .. ' mode'), Group = groupId,
            PresetValues = table.concat(modeValues, '|'), PresetLabels = 'Tap|Hold', Default = modeValues[1],
            DecoType = 'keybind', VisibleWhen = source, VisibleValues = visible})
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
    -- Persist the historical quickslots namespace so existing config keys and
    -- selected template values survive the public category rename unchanged.
    local function storageIdentity(entry)
        if entry.template.category ~= 'player.quickslots' then return entry.id end
        return U.identity({collection=entry.template.collection,
            category='player.actions', name=entry.template.name})
    end
    local decoded = {}
    for _, category in ipairs(registry.categories:list()) do
        local categoryLabel = (options.categoryLabels or {})[category]
            or category:gsub('%.', ' '):gsub('(%a)([%w_]*)', function(a, b) return a:upper() .. b end)
        categoryLabels[category] = categoryLabel
        local available = perCategory[category]
        if not available then
            warnings[#warnings + 1] = category .. ': empty category omitted; DMM cannot render a None-only picker'
        else
            currentCategory = category
            assert(#available <= 63, category .. ': more than 63 templates exceeds picker capacity including None')
            local selector = id({'selector', category == 'player.quickslots' and 'player.actions' or category})
            local values, labels, byValue = {0}, {'None'}, {}
            for _, entry in ipairs(available) do
                local value = allocate({'template', storageIdentity(entry)})
                values[#values + 1], labels[#labels + 1] = value, text(entry.template.name)
                byValue[value] = entry.id
            end
            picker(selector, categoryLabel, 'Templates', values, labels, nil, nil, true, 2)
            aggregateRows[#aggregateRows + 1] = rows[#rows]
            selectors[category] = {id = selector, byValue = byValue}
            decoded[category] = {}
            for _, entry in ipairs(available) do
                local template, identity = entry.template, storageIdentity(entry)
                local value = allocate({'template', identity})
                local definition = {id = entry.id, fields = {}}
                decoded[category][value] = definition
                if category == 'player.quickslots' then
                    local ordered = V.orderedGroups(template, (options.groupOrders or {})[entry.id])
                    local access = id({'access', identity})
                    local accessGroup = group(key({identity, 'access'}), 'Access Method', selector, value, selector, value, 3, 0)
                    picker(access, 'Access Method', accessGroup, {0, 1}, {'1 key per slot', 'Activate group first'}, nil, nil, true, 2)
                    local default = id({'first_default', identity})
                    picker(default, 'First group is default (needs no key)', accessGroup, {0, 1}, {'Off', 'On'}, access, 1, true)
                    definition.access, definition.firstDefault = access, default
                    definition.direct, definition.groups, definition.shared = {}, {}, {}
                    local maxSlots, slotIndex, groupNames = 0, 0, {}
                    for index, item in ipairs(ordered) do
                        local g = item.value
                        assert(not groupNames[g.name], 'action group names must be unique for stable menu identity')
                        groupNames[g.name] = true
                        maxSlots = math.max(maxSlots, g.slots)
                        assert(g.slots <= 126, 'group slot count exceeds menu capacity')
                        local directGroup = group(key({identity, 'direct', g.name}), g.name, selector, value, access, 0, 5)
                        definition.direct[item.key] = {}
                        for slot = 1, g.slots do
                            slotIndex = slotIndex + 1
                            definition.direct[item.key][slot] = binding(key({identity, 'direct', g.name, slot}),
                                'Slot ' .. slotIndex .. ' (' .. g.type .. ')', directGroup, nil, nil, slotModes)
                        end
                    end
                    local activateGroup = group(key({identity, 'groups'}), 'Groups', selector, value, access, 1)
                    for index, item in ipairs(ordered) do
                        local g = item.value
                        definition.groups[item.key] = binding(key({identity, 'activate', g.name}), g.name,
                            activateGroup, index == 1 and default or nil, index == 1 and 0 or nil, {0, 2})
                    end
                    local sharedGroup = group(key({identity, 'slots'}), 'Slots', selector, value, access, 1)
                    for slot = 1, maxSlots do
                        definition.shared[slot] = binding(key({identity, 'shared', slot}), 'Slot ' .. slot,
                            sharedGroup, nil, nil, slotModes)
                    end
                else
                    warnings[#warnings + 1] = category .. ': no category-specific renderer defined'
                end
                if template.providerSettings then
                    definition.provider = {}
                    for _, providerGroup in ipairs(Provider.normalize(template.providerSettings)) do
                        local groupId = group(key({identity, 'provider', providerGroup.id}), providerGroup.label,
                            selector, value, selector, value, providerGroup.level)
                        for _, field in ipairs(providerGroup.fields) do
                            local settingId = id({'provider', identity, field.id})
                            local metadata = {Id=settingId, Label=field.label, Group=groupId, Type=field.type,
                                Default=field.default, Description=field.description, DecoLevel=field.level}
                            if field.type == 'picker' then
                                metadata.PresetValues = table.concat(field.values, '|')
                                metadata.PresetLabels = table.concat(field.labels, '|')
                                metadata.DecoType = field.tab and 'tab' or nil
                            else
                                metadata.Minimum, metadata.Maximum, metadata.Step = field.min, field.max, field.step
                                metadata.Suffix = field.suffix
                            end
                            row(metadata)
                            definition.provider[field.id] = settingId
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
    local function providerManifest(providerId, providerName, selectedRows)
        local output = {}
        append(output, 'Mod', {Id=providerId, Name=providerName, Version='0.0.17',
            Description=options.description and text(options.description) or nil})
        local usedGroups = {}
        for _, item in ipairs(selectedRows) do usedGroups[item.Group] = true end
        if usedGroups.Templates then append(output, 'Category.Templates', {DecoHeading=0}) end
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
                    (r.DecoType == 'keybind' and 'invalid key ' or 'invalid integer ') .. settingId)
            else
                local found = false
                for candidate in r.PresetValues:gmatch('[^|]+') do if value == tonumber(candidate) then found = true end end
                assert(found, 'invalid choice ' .. settingId)
            end
            effective[settingId] = value
        end
        local result = {}
        local function readBinding(pair) return {key = effective[pair.key], mode = effective[pair.mode]} end
        for category, selector in pairs(selectors) do
          if not includedCategories or includedCategories[category] then
            local definition = decoded[category][effective[selector.id]]
            local selection = {configuration = {}}
            result[category] = selection
            if definition then
                selection.id = definition.id
                local config = selection.configuration
                if definition.provider then
                    config.provider = {}
                    for field, settingId in pairs(definition.provider) do config.provider[field] = effective[settingId] end
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
            end
          end
        end
        return result
      end
    end
    local aggregateId = 'UE4SSTemplatingEngine'
    local aggregateManifest = providerManifest(aggregateId, 'Templates', aggregateRows)
    local allCategories = {}; for category in pairs(selectors) do allCategories[category] = true end
    local aggregate = {id=aggregateId, name='Templates', manifest=aggregateManifest, rows=aggregateRows,
        decode=makeDecoder(aggregateRows, allCategories)}
    local pages, pageByCategory, providers = {}, {}, {[aggregateId]=aggregate}
    for _, category in ipairs(registry.categories:list()) do
        local providerId = aggregateId .. '.' .. category
        local included, selectedRows = {[category]=true}, pageRows[category] or {}
        local page = {id=providerId, name=categoryLabels[category], category=category,
            rows=selectedRows, manifest=providerManifest(providerId, categoryLabels[category], selectedRows)}
        page.decode = makeDecoder(page.rows, included)
        pages[#pages + 1], pageByCategory[category], providers[providerId] = page, page, page
    end
    return {manifest = aggregateManifest, fullManifest = table.concat(lines, '\n'), catalog = catalog,
        rows = rows, selectors = selectors, definitions = decoded, warnings = warnings,
        decode = makeDecoder(rows, allCategories), aggregate=aggregate, pages=pages,
        pageByCategory=pageByCategory, providers=providers}
end

return M
