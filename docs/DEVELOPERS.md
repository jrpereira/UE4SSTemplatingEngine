# Developer guide

For the fresh runtime and current `ModCore/` folder layout, see
[Lifecycle draft](LIFECYCLE-DRAFT.md) and [Template menus](MENUS.md).
The API examples below document the preceding implementation.

- [Example: replace the quickslots](#example-replace-the-quickslots)
- [Selection and settings pages](#selection-and-settings-pages)
- [Template format](#template-format)
- [Category events](#category-events)
- [Template declarations and lifecycle](#template-declarations-and-lifecycle)
- [Built-in categories](#built-in-categories)

Describe game-feature or UI customizations as Lua templates. ModCoreTemplates
validates declarations, generates selection controls, discovers category targets,
and calls the template lifecycle. Each template owns its mutations and restoration.
Leave the furniture where you found it when `detach` runs.

The DMM provider ID is `ModCoreTemplates`; Lua imports retain `ket.*` from
`Scripts/ket`. Saved settings use `KET_` IDs; older `TE_` values are not migrated.

## Example: replace the quickslots

Create `<Module>/Scripts/my_quickslots.lua`:

```lua
local template = {
    name = "My Quickslots",
    category = "player.quickslots",
    settings = { target = "module", enabled = false },
}

function template:attach(service, target, settings, previous, categoryHandle)
    -- Prepare the replacement and return an opaque state handle.
    -- Reusing `previous` makes repeated Apply operations idempotent.
    return previous or { original = {} }
end

function template:render(service, state, target, reason, categoryHandle)
    -- Update a target discovered by ModCoreTemplates, such as the wheel layout or HUD indicators.
    return "applied" -- or "not_ready" / "ignored"
end

function template:detach(service, state, reason, categoryHandle)
    -- Restore every game value recorded by attach/render.
    return true
end

return template
```

Register the template entry point directly:

```lua
ket:registerTemplate("<Module>/Scripts/my_quickslots.lua")
```

`registerTemplates(folder)` is available when a folder contains only template entry points. It registers every `.lua` file returned by the host's nonrecursive `listFiles` adapter.

## Selection and settings pages

Once templates are loaded, ModCoreTemplates validates them, builds the mod menu during boot, and remembers the active template for each category. DMM loads ModCoreTemplates's extension before provider discovery, so ModCoreTemplates writes the current menu manifest and routed pages in that startup sequence. The identity catalog preserves saved setting IDs across boots. ModCoreTemplates invokes lifecycle methods only while the selected template has `settings.enabled = true`.

The `ModCoreTemplates` DMM page always aggregates every loaded template. A template may declare `single = true` or `single = false`; when it omits the field, ModCoreTemplates copies the category's `single` value as its fallback. Templates sharing a category must resolve to the same value. A single category has one template picker. Other categories show one Yes/No picker per template and may activate several templates at once.

Every template declares its menu target with `settings.target`. A `templates` target is routed to a category page, such as `Player Quickslots` or `NPC Attacks`. A `module` target is routed to its source module's page: register it from `<Module>/ModCore/templates/<file>.lua`, which produces a `<Module>` Mod Menu page. Older registration paths remain accepted during migration.

A provider field with `type = 'navigation'` declares picker choices used only to show and hide other fields. ModCoreTemplates emits it as a DMM picker with `mcNavigation=1`; a tab may also declare `tabNavigation=1` for ModCoreSettings. The generated ID is available in `definition.navigation`, and the row has no config binding. Its value is neither saved in `ModCore/cache/config.ini` nor passed to template hooks. Other fields may name it in `visibleWhen`. This requires ModCoreSettings's navigation picker support.

ModCoreControls owns quickslot access methods, action assignment, Tap/Hold bindings, and native input. ModCoreTemplates owns template selection and visual settings. ModCoreControls runs its input host independently of visual template selection; ModCoreTemplates no longer reads ModCoreControls's saved controls or handles ModCoreControls Apply events.

The Fangdango Wheels template owns its Swap and Distant styles, settings, wheel separation, and restoration. ModCoreTemplates discovers the declared target and invokes the template lifecycle. ModCoreControls owns input independently.

## Template format

A runtime template needs the following fields (the inert `menu.fixes` exception is described below):

- `name`: the name shown to players.
- `category`: the game feature it replaces.
- `attach`, `render`, and `detach`: the runtime lifecycle.

Category objects live in `ModCore/categories/*.lua`. ModCoreTemplates loads every category object at startup; each file declares its own `name`, and `single = true` when the category allows one selected template. Other modules can add categories with `ket:loadCategory(name, path)` before loading their templates. ModCoreTemplates generates category controls ahead of template controls. Numeric category settings are editable in DMM, and text settings can be edited in the `[Templates]` section of `ModCore/cache/config.ini`. ModCoreTemplates passes category values and the selected template's values to visual lifecycle hooks. Player input settings live in ModCoreControls.

A category may define `resolveTarget`, `attach`, and `detach`. ModCoreTemplates calls category `attach(service, target, settings, previousCategoryHandle, template)` before the selected template's `attach`, then passes the returned category handle as the last argument to the template's `attach`, `render`, and `detach`. On a template switch, ModCoreTemplates detaches the old template while keeping the category attached; when the category is cleared, it detaches the template first and the category second. A category author decides what its hooks create, retain, and restore.

The quickslots category declares a stable UE object path for QuickslotsSwitcher. Generic lifecycle target discovery resolves a category with one declared path through the service's findObject method. The Fangdango template owns wheel-specific attachment, detachment, settings and restoration; there is no category wheel handle or detachSecondaryWheel contract.

## Category events

Category objects can declare `events`. ModCoreTemplates validates those names against the category contract, subscribes once through its event host, and delivers declared events to the selected template. The callback remains `render(service, handle, payload, eventName)`. If the selected template is waiting for native objects, a declared event retries `attach` before delivery. The quickslots category declares `GroupSelected` and `SlotActivated`; templates receive those events through ModCoreTemplates.

Creation-driven categories declare independent native targets with `subscribe = { { path = "/Game/.../WBP_CombatTargetIndicator_C", events = { "created" }, contexts = { "combat" } } }`. ModCoreTemplates validates the exact path, event, and context, owns `NotifyOnNewObject` and game-thread scheduling through `ket.native_events`, passes the active GameHUD parent to `attach`, and passes each created indicator to `render` with event name `created`. The template service does not expose subscription, unsubscription, or scheduling methods.

## Template declarations and lifecycle

A template file may return one template, an array of templates, or a header followed by either form. The header is copied into every template before validation. A field declared on a template takes precedence over the same header field; table fields such as `settings` are replaced as a whole.

```lua
local header = {
    category = 'menu.fixes',
    settings = {target = 'templates', enabled = false},
}
return header, {
    {name = 'First fix'},
    {name = 'Second fix'},
}
```

Template files are ordinary Lua and can access the environment in which the host loads them, so install templates only from sources you trust.

`attach` is called on activation and again when settings are applied. It should be idempotent and preserve the original game state. `render` responds to relevant discovered widgets or events. `detach` runs while objects are still valid and must restore owned changes. ModCoreTemplates skips all three methods when `settings.enabled = false`. When the world is already invalid, ModCoreTemplates forgets the active handle without calling template code.

The `player.quickslots` service exposes `valid`, `same`, `identity`, and `parent`. A quickslots template calls these methods directly. ModCoreTemplates resolves the current QuickslotsSwitcher and invokes `attach(service, target, settings, previousHandle, categoryHandle)` only when that target is valid. If it is unavailable, ModCoreTemplates keeps the selection pending without calling template code. A declared category event retries the attachment with its resolved target, then invokes `render(service, handle, target, eventName)`. Handles retain provider-owned mutation and restoration state; templates do not rediscover or retain the category parent merely for later rendering.

Every template declares `settings.target` (`"templates"` or `"module"`) and a boolean `settings.enabled`, merging `groups` and `fields` into that table when it exposes menu controls. A settings group may declare `heading = false` to keep its grouping and order without rendering a separator. A picker field may use `level = 1` to appear in the page header; each page supports one such picker. On a page for one category, ModCoreTemplates places that category's template selector in the page header; the combined Templates page keeps category selectors in its list. A field may declare `visibleWhen = 'PickerId'` and `visibleValues = {0, 1}` to appear only for those values of an earlier picker in the same template; this row condition combines with the template selection condition. Hidden fields retain their values and are still passed in `settings`. Bundled templates default `enabled` to `true`, while a fresh configuration still keeps each category selector at `None`; a template begins running only after it is selected. A disabled template may remain selected, but ModCoreTemplates records it without calling `attach`, `render`, or `detach`. ModCoreTemplates validates committed `settings` values against any declared fields before invoking enabled lifecycle code. Templates can import `require("ket.widget")` for generic UE widget operations: `unwrap`, `property`, `number`, `translation`, `scale`, `opacity`, `setTranslation`, `setScale`, `setOpacity`, `snapshotSlot`, and `restoreSlot`. The category owns shared target discovery and hierarchy changes; each template owns its visual layout and restoration of its own changes.

## Built-in categories

- `player.quickslots`, `player.stats`, `player.charges`, `player.self`, `player.compass`, `player.notifications`, `player.wheel`
- `npc.attacks`, `npc.intent`, `npc.level`, `npc.melee`, `npc.pawn`
- `other.unknown`
- `menu.controls`, `menu.fixes`, `menu.templates`

Only categories with registered templates appear in the menu. A category name
is an integration point, not a finished feature. Hosts may register additional
categories before loading templates.

Every registered category starts as `{ visible = 0, count = 0, templates = {} }`. Category metadata can then be updated in place. The core definitions set `single = true` on every `player.*` category. For example, `ket:setCategory("player.quickslots", { visible = 1 })` sets `_categories.player.quickslots.visible` while preserving `single`, `count`, and `templates`. When registered files are loaded successfully, ModCoreTemplates increments the category's `count` and appends each loaded template object to its `templates` array.

`menu.fixes` accepts inert Lua templates with no `attach`, `render`, `detach`, `events`, or `subscribe` fields. ModCoreTemplates can register and select them as category metadata, but it never invokes their exported callbacks or registers native hooks on their behalf.
