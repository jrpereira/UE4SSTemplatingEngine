-- Core definitions; invoked before registered templates are evaluated.
return function(registerCategory, setCategory)
    local player = {'quickslots', 'stats', 'charges', 'self', 'compass', 'notifications', 'wheel'}
    registerCategory('player', player)
    for _, category in ipairs(player) do setCategory('player.' .. category, {single = true}) end
    registerCategory('npc', {'attacks', 'intent', 'level', 'melee', 'pawn'})
    registerCategory('other', {'unknown'})
    registerCategory('menu', {'controls', 'fixes', 'templates'})
end
