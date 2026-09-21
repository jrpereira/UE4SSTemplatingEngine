# UE4SS Templating Engine

TE lets mods describe alternative implementations of game features as Lua templates. Players can then select one template for each supported category from the mod menu.

## Example: replace the quickslots

Create `templates/my_quickslots.lua`:

```lua
local template = {
    collection = "My Dawnwalker Mods",
    name = "My Quickslots",
    category = "player.quickslots",
    contexts = { "combat", "openworld" },
    events = { "GroupSelected", "SlotActivated" },

    actions = {
        { name = "Abilities",   slots = 4, type = "ability" },
        { name = "Consumables", slots = 4, type = "consumable" },
    },
}

function template:attach(service, target, settings, previous)
    -- Prepare the replacement and return an opaque state handle.
    -- Reusing `previous` makes repeated Apply operations idempotent.
    return previous or { original = {} }
end

function template:render(service, state, target, reason)
    -- Update a target discovered by TE, such as the wheel layout or HUD indicators.
    return "applied" -- or "not_ready" / "ignored"
end

function template:detach(service, state, reason)
    -- Restore every game value recorded by attach/render.
    return true
end

return template
```

Register the file directly, or register every `.lua` file in a folder:

```lua
te:registerTemplate("templates/my_quickslots.lua")
te:registerTemplates("templates")
```

Once templates are loaded, TE validates them, adds them to the mod menu, remembers the active template for each category, and invokes their lifecycle methods when the player applies a selection.

The `Templates` DMM page contains one template picker per populated category. TE also generates a DMM page for every registered category. When templates are available, the category page repeats that category's picker and contains the selected template's detailed controls, such as quickslot access mode and key assignments. Both picker views use the same persisted TE setting.

## Template format

Each template needs:

- `collection`: the mod or template-pack name.
- `name`: the name shown to players.
- `category`: the game feature it replaces.
- `attach`, `render`, and `detach`: the runtime lifecycle.

Categories may require extra data. `player.quickslots`, for example, requires an ordered `actions` array. Each action group declares its display name, slot count, and semantic type. TE uses that information to generate direct-slot or group-first key bindings without hard-coding a particular quickslot layout.

Templates declare the category events they consume with `events`. TE validates those names against the category contract, subscribes once through its event host, and delivers only declared events. The callback remains `render(service, handle, payload, eventName)`. If the selected template is waiting for native objects, a declared event retries `attach` before delivery. QSF currently declares `GroupSelected` and `SlotActivated`; it does not register those native hooks itself.

A template file may return one template or a nested array of templates. Template files are ordinary Lua and can access the environment in which the host loads them, so install templates only from sources you trust.

`attach` is called on activation and again when settings are applied. It should be idempotent and preserve the original game state. `render` responds to relevant discovered widgets or events. `detach` runs while objects are still valid and must restore owned changes. When the world is already invalid, TE forgets the active handle without calling template code.

The `player.quickslots` service exposes `valid`, `same`, `identity`, and `parent`. A quickslots template calls these methods directly. TE resolves the current QuickslotsSwitcher and invokes `attach(service, target, configuration, previousHandle)` only when that target is valid. If it is unavailable, TE keeps the selection pending without calling template code. A declared category event retries the attachment with its resolved target, then invokes `render(service, handle, target, eventName)`. Handles retain provider-owned mutation and restoration state; templates do not rediscover or retain the category parent merely for later rendering.

Templates may declare menu controls in `settings = { groups = {...}, fields = {...} }`. TE validates the committed `configuration.settings` values against that declaration before invoking `attach`. Persisted setting identities retain their existing values when adopting this name. Templates can import `require("te.widget")` for generic UE widget operations: `unwrap`, `property`, `number`, `translation`, `scale`, `opacity`, `setTranslation`, `setScale`, `setOpacity`, `snapshotSlot`, and `restoreSlot`. Layout policy, widget ownership, restoration journals, and category behavior stay in the template.

## Built-in categories

- `player.quickslots`, `player.stats`, `player.charges`, `player.self`, `player.compass`, `player.notifications`, `player.wheel`
- `npc.intent`, `npc.level`, `npc.melee`, `npc.pawn`
- `other.unknown`
- `menu.controls`, `menu.templates`

Only categories with registered templates appear in the menu. A host may register additional categories before loading templates.

Every registered category starts as `{ visible = 0, count = 0, templates = {} }`. Category metadata can then be updated in place. For example, `te:setCategory("player.quickslots", { visible = 1 })` sets `_categories.player.quickslots.visible` while preserving `count` and `templates`. When registered files are loaded successfully, TE increments the category's `count` and appends each loaded template object to its `templates` array.

> The current `0.0.17` menu-test build exercises registration, validation, menu generation, persistence, and Apply callbacks. Native discovery, gameplay input, and visual cutover are still under development.
