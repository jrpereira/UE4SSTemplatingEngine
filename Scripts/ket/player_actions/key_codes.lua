local byName = {
    None=0,
    LeftMouseButton=0x01, RightMouseButton=0x02, MiddleMouseButton=0x04,
    ThumbMouseButton=0x05, ThumbMouseButton2=0x06,
    BackSpace=0x08, Tab=0x09, Enter=0x0D, SpaceBar=0x20,
    PageUp=0x21, PageDown=0x22, End=0x23, Home=0x24,
    Left=0x25, Up=0x26, Right=0x27, Down=0x28,
    Insert=0x2D, Delete=0x2E,
    LeftCommand=0x5B, RightCommand=0x5C,
    LeftShift=0xA0, RightShift=0xA1,
    LeftControl=0xA2, RightControl=0xA3,
    LeftAlt=0xA4, RightAlt=0xA5,
    Zero=0x30, One=0x31, Two=0x32, Three=0x33, Four=0x34,
    Five=0x35, Six=0x36, Seven=0x37, Eight=0x38, Nine=0x39,
    Backslash=0xDC,
}
for code=string.byte('A'),string.byte('Z') do byName[string.char(code)]=code end
for number=1,12 do byName['F'..number]=0x6F+number end

local byValue={}
for name,value in pairs(byName)do if not byValue[value]then byValue[value]=name end end
return {toName=function(value)return byValue[tonumber(value)]end}
