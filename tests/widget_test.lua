package.path = 'Scripts/?.lua;' .. package.path
local W = require('ket.widget')
local checks = 0
local function check(value) assert(value); checks = checks + 1 end
local function wrapped(value) return {get=function() return value end} end
local slot = {Padding=wrapped({Left=1,Top=2,Right=3,Bottom=4}),
    HorizontalAlignment=1,VerticalAlignment=2}
function slot:SetPadding(value) self.restoredPadding=value end
function slot:SetHorizontalAlignment(value) self.restoredHorizontal=value end
function slot:SetVerticalAlignment(value) self.restoredVertical=value end
local widget = {RenderTransform=wrapped({Translation=wrapped({X=10,Y=20}),Scale={X=1,Y=2}}),
    Slot=wrapped(slot),opacity=0.5,writes=0}
function widget:GetRenderOpacity() return self.opacity end
function widget:SetRenderOpacity(value) self.opacity=value;self.writes=self.writes+1 end
function widget:SetRenderTranslation(value) self.translation=value;self.writes=self.writes+1 end
function widget:SetRenderScale(value) self.scaled=value;self.writes=self.writes+1 end
check(W.unwrap(wrapped(7))==7 and W.unwrap(8)==8)
check(W.property(widget,'Slot')==slot and W.property(nil,'Slot')==nil)
check(W.number(W.property(W.property(widget,'RenderTransform'),'Translation'),'X')==10)
local translation,scale=W.translation(widget),W.scale(widget)
check(translation.X==10 and translation.Y==20 and scale.X==1 and scale.Y==2)
check(W.opacity(widget)==0.5)
W.setTranslation(widget,10,20);check(widget.writes==0)
W.setTranslation(widget,30,40);check(widget.translation.X==30 and widget.translation.Y==40)
W.setScale(widget,1,2);check(widget.writes==1)
W.setScale(widget,3);check(widget.scaled.X==3 and widget.scaled.Y==3)
W.setOpacity(widget,0.5);check(widget.writes==2)
W.setOpacity(widget,0.25);check(widget.opacity==0.25 and widget.writes==3)
local state=W.snapshotSlot(widget)
check(state.padding.Left==1 and state.padding.Bottom==4 and state.horizontal==1 and state.vertical==2)
W.restoreSlot(widget,state)
check(slot.restoredPadding==state.padding and slot.restoredHorizontal==1 and slot.restoredVertical==2)
print('widget: '..checks..' checks passed')
