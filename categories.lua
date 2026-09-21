-- Core definitions; invoked before registered templates are evaluated.
return function(registerCategory)
    registerCategory('player', {'quickslots', 'stats', 'charges', 'self', 'compass', 'notifications', 'wheel'})
    registerCategory('npc', {'intent', 'level', 'melee', 'pawn'})
    registerCategory('other', {'unknown'})
    registerCategory('menu', {'controls', 'templates'})
end
