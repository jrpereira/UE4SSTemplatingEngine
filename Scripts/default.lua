local template = {
    name = "Default",
    category = "menu.templates",
    settings = { target = "templates", enabled = true },

    menu = {
        aggregate = {
            name = "Templates",
            content = "category-pickers",
        },
        categories = {
            page = true,
            picker = true,
            details = "selected-template",
        },
    },
}

function template:attach(service, target, settings, previous)
    return previous or {}
end

function template:render(service, state, target, reason)
    return "ignored"
end

function template:detach(service, state, reason)
    return true
end

return template
