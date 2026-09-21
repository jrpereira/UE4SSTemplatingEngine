-- Core definitions; invoked before registered templates are evaluated.
return function(registerCategory)
    registerCategory('player', {'actions', 'stats', 'charges', 'self', 'compass'})
    registerCategory('npc', {'stats', 'self'})
end
