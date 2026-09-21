-- Test-only facade; never installed as native engine infrastructure.
return function(fields)
    local service = fields or {}
    service.valid = function(_, value) return value ~= nil end
    service.same = function(_, a, b) return rawequal(a, b) end
    service.identity = function(_, value) return tostring(value) end
    service.parent = function(_, value) return value.parent end
    service.quickslotSwitcher = service.quickslotSwitcher or function(self) return self.switcher end
    return service
end
