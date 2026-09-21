local template = {
    collection = "Templating Engine",
    name = "Default",
    category = "menu.templates",

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

function template:attach(service, settings, previous)
    return previous or {}
end

function template:render(service, state, target, reason)
    return "ignored"
end

function template:detach(service, state, reason)
    return true
end

return template
