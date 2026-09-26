-- MCT loads main.lua and registers the templates returned at the end.
local MC=require('mc')
local Widget=MC('widget')
local nudge=MC.template('nudge')

-- Keep shared widget operations here if more layouts are added later.
local function moveFromOriginal(widget,position,x,y)
    Widget.setTranslation(widget,position.X+x,position.Y+y)
end

function nudge.attach(objects,params,original)
    local x=params.screen.width*params.settings.HorizontalPercent/100
    local y=params.screen.height*params.settings.VerticalPercent/100
    moveFromOriginal(objects.abilities,original.abilities.position,x,y)
    return original -- MCT restores this snapshot on update and detach.
end

return {nudge}
