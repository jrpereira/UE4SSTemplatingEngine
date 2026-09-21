# UE4SS Templating Engine

TE lets mods describe alternative implementations of game features as Lua templates. Players can then select one template for each supported category from the mod menu.

## Example: replace the quickslots

Create `templates/my_quickslots.lua`:

```lua
local template = {
    collection = "My Dawnwalker Mods",
    name = "My Quickslots",
    category = "player.quickslots",
    settings = { target = "module", enabled = false },
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

Once templates are loaded, TE validates them, adds them to the mod menu, and remembers the active template for each category. It invokes lifecycle methods only while the selected template has `settings.enabled = true`.

The `Templates` DMM page always aggregates every loaded template. A category with `single = true` has one template picker. Other categories show one Yes/No picker per template and may activate several templates at once.

Every template also declares its menu target with `settings.target`. Generated pages after `Templates` are grouped by category, such as `Player Quickslots` and `NPC Attacks`; templates from different collections share the appropriate category page.

Generated key bindings follow AMM's mode-owned pairing contract. The mode picker survives as the composite row, uses `ammType=tab`, and declares `Pair=<key-setting-id>`. The integer key setting uses `ammType=keybind` without `Pair`; its normal DMM visibility determines whether the key component appears.

## Template format

Each template needs:

- `collection`: the mod or template-pack name.
- `name`: the name shown to players.
- `category`: the game feature it replaces.
- `attach`, `render`, and `detach`: the runtime lifecycle.

Categories may require extra data. `player.quickslots`, for example, requires an ordered `actions` array. Each action group declares its display name, slot count, and semantic type. TE uses that information to generate direct-slot or group-first key bindings without hard-coding a particular quickslot layout.

Templates declare the category events they consume with `events`. TE validates those names against the category contract, subscribes once through its event host, and delivers only declared events. The callback remains `render(service, handle, payload, eventName)`. If the selected template is waiting for native objects, a declared event retries `attach` before delivery. QSF currently declares `GroupSelected` and `SlotActivated`; it does not register those native hooks itself.

Creation-driven categories declare independent native targets with `subscribe = { { path = "/Game/.../WBP_CombatTargetIndicator_C", events = { "created" }, contexts = { "combat" } } }`. TE validates the exact path, event, and context, owns `NotifyOnNewObject` and game-thread scheduling through `te.native_events`, passes the active GameHUD parent to `attach`, and passes each created indicator to `render` with event name `created`. The template service does not expose subscription, unsubscription, or scheduling methods.

A template file may return one template or a nested array of templates. Template files are ordinary Lua and can access the environment in which the host loads them, so install templates only from sources you trust.

`attach` is called on activation and again when settings are applied. It should be idempotent and preserve the original game state. `render` responds to relevant discovered widgets or events. `detach` runs while objects are still valid and must restore owned changes. TE skips all three methods when `settings.enabled = false`. When the world is already invalid, TE forgets the active handle without calling template code.

The `player.quickslots` service exposes `valid`, `same`, `identity`, and `parent`. A quickslots template calls these methods directly. TE resolves the current QuickslotsSwitcher and invokes `attach(service, target, configuration, previousHandle)` only when that target is valid. If it is unavailable, TE keeps the selection pending without calling template code. A declared category event retries the attachment with its resolved target, then invokes `render(service, handle, target, eventName)`. Handles retain provider-owned mutation and restoration state; templates do not rediscover or retain the category parent merely for later rendering.

Every template declares `settings.target` (`"templates"` or `"module"`) and a boolean `settings.enabled`, merging `groups` and `fields` into that table when it exposes menu controls. Bundled templates default `enabled` to `false`, and a fresh configuration keeps the category selector at `None`; existing saved selections remain unchanged. A disabled template may remain selected, but TE records it without calling `attach`, `render`, or `detach`. TE validates committed `configuration.settings` values against any declared fields before invoking enabled lifecycle code. Templates can import `require("te.widget")` for generic UE widget operations: `unwrap`, `property`, `number`, `translation`, `scale`, `opacity`, `setTranslation`, `setScale`, `setOpacity`, `snapshotSlot`, and `restoreSlot`. Layout policy, widget ownership, restoration journals, and category behavior stay in the template.

## Built-in categories

- `player.quickslots`, `player.stats`, `player.charges`, `player.self`, `player.compass`, `player.notifications`, `player.wheel`
- `npc.attacks`, `npc.intent`, `npc.level`, `npc.melee`, `npc.pawn`
- `other.unknown`
- `menu.controls`, `menu.fixes`, `menu.templates`

Only categories with registered templates appear in the menu. A host may register additional categories before loading templates.

Every registered category starts as `{ visible = 0, count = 0, templates = {} }`. Category metadata can then be updated in place. The core definitions set `single = true` on every `player.*` category. For example, `te:setCategory("player.quickslots", { visible = 1 })` sets `_categories.player.quickslots.visible` while preserving `single`, `count`, and `templates`. When registered files are loaded successfully, TE increments the category's `count` and appends each loaded template object to its `templates` array.

`menu.fixes` accepts inert Lua templates with no `attach`, `render`, `detach`, `events`, or `subscribe` fields. TE can register and select them as category metadata, but it never invokes their exported callbacks or registers native hooks on their behalf.

> The current `0.0.17` menu-test build exercises registration, validation, menu generation, persistence, and Apply callbacks. Native discovery, gameplay input, and visual cutover are still under development.
