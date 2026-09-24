# ModCoreTemplates (KET)

I started my short modding looking to fix the QuickslotWheel's issues, but along the way bumped into many situations where it felt like I had to build some foundational stuff, and I started to consider how much time wasted we could be saving, and how much developer creativity we could help emerge.

For instance, it took some days to find my way through UE's GUI infrastructure, find items, manage their lifecycle, learn Enhanced Input in depth, etc. So, encapsulating away those learnings into a well tested base... that's how this module was born.

For example, there's core functionality that allows players to take their pick on a variety of keyboard alternatives that really aren't that many, and ultimately are just presets. You can design and deploy dozens of formats, and they'll all use a variation of that. This means players can download and experiment, from different authors... and their choice of keys will carry across. Seems like a small thing, it's not. :D



KET lets mods describe alternative implementations of game features as Lua templates. Players can then select one template for each supported category from the mod menu.

## Installation

Install the module in the UE4SS mod folder `_ModCore_Templates`. Disable the old `_UE4SSTemplatingEngine` folder before starting the game so both copies cannot load. The new module uses fresh `KET_` setting IDs; old `TE_` values are not migrated.

The DMM provider ID is `ModCoreTemplates`, including its routed pages. Lua consumers import `ket.*` from `Scripts/ket`.

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
    -- Update a target discovered by KET, such as the wheel layout or HUD indicators.
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

Once templates are loaded, KET validates them, builds the mod menu during boot, and remembers the active template for each category. DMM loads KET's extension before provider discovery, so KET writes the current menu manifest and routed pages in that startup sequence. The identity catalog preserves saved setting IDs across boots. KET invokes lifecycle methods only while the selected template has `settings.enabled = true`.

The `ModCoreTemplates` DMM page always aggregates every loaded template. A template may declare `single = true` or `single = false`; when it omits the field, KET copies the category's `single` value as its fallback. Templates sharing a category must resolve to the same value. A single category has one template picker. Other categories show one Yes/No picker per template and may activate several templates at once.

Every template also declares its menu target with `settings.target`. A `templates` target is routed to a category page, such as `Player Quickslots` or `NPC Attacks`. A `module` target is routed to its source module's page: register it from `<Module>/Scripts/<file>.lua` or `<Module>/Scripts/templates/<file>.lua`, which produces a `<Module>` Mod Menu page. Existing `<Module>/templates/<file>.lua` registrations remain accepted during migration.

A provider field with `type = 'navigation'` declares picker choices used only to show and hide other fields. KET emits it as a DMM picker with `ammNavigation=1`; a tab may also declare `tabNavigation=1` for AMM. The generated ID is available in `definition.navigation`, and the row has no config binding. Its value is neither saved in `config.ini` nor passed to template hooks. Other fields may name it in `visibleWhen`. This requires AMM's navigation picker support.

ModCoreControls owns quickslot access methods, action assignment, Tap/Hold bindings, and native input. KET owns template selection and visual settings. KEC runs its input host independently of visual template selection; KET no longer reads KEC's saved controls or handles KEC Apply events.

The current Action Fandango Wheels++ example uses the native ability and consumable wheels. KET attaches its visual template when the saved selection is available, retries while the HUD's wheel children are still being built, and restores the native wheel layout when the selection is cleared. KEC's bundled UE4SSLuaEventBridge handles the input mappings.

## Template format

Each template needs:

- `name`: the name shown to players.
- `category`: the game feature it replaces.
- `attach`, `render`, and `detach`: the runtime lifecycle.

Category objects live in `Scripts/categories/*.lua`. KET loads every category object at startup; each file declares its own `name`, and `single = true` when the category allows one selected template. Other modules can add categories with `ket:loadCategory(name, path)` before loading their templates. KET generates category controls ahead of template controls. Numeric category settings are editable in DMM, and text settings can be edited in the `[Templates]` section of `config.ini`. KET passes category values and the selected template's values to visual lifecycle hooks. Player input settings live in ModCoreControls.

A category may define `resolveTarget`, `attach`, and `detach`. KET calls category `attach(service, target, settings, previousCategoryHandle, template)` before the selected template's `attach`, then passes the returned category handle as the last argument to the template's `attach`, `render`, and `detach`. On a template switch, KET detaches the old template while keeping the category attached; when the category is cleared, it detaches the template first and the category second. A category author decides what its hooks create, retain, and restore.

The quickslots category declares one stable UE object path for `QuickslotsSwitcher`; KET resolves its live instance despite generated IDs in the outer path. Templates that set `detachSecondaryWheel = true` ask the category to move the second wheel out of the switcher. The category handle then contains `primary` and `secondary` wheel references. Its `detach` restores the secondary wheel and its original slot when the category is cleared. Templates without that flag keep the existing wheel hierarchy.

Category objects can declare `events`. KET validates those names against the category contract, subscribes once through its event host, and delivers declared events to the selected template. The callback remains `render(service, handle, payload, eventName)`. If the selected template is waiting for native objects, a declared event retries `attach` before delivery. The quickslots category declares `GroupSelected` and `SlotActivated`; templates receive those events through KET.

Creation-driven categories declare independent native targets with `subscribe = { { path = "/Game/.../WBP_CombatTargetIndicator_C", events = { "created" }, contexts = { "combat" } } }`. KET validates the exact path, event, and context, owns `NotifyOnNewObject` and game-thread scheduling through `ket.native_events`, passes the active GameHUD parent to `attach`, and passes each created indicator to `render` with event name `created`. The template service does not expose subscription, unsubscription, or scheduling methods.

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

`attach` is called on activation and again when settings are applied. It should be idempotent and preserve the original game state. `render` responds to relevant discovered widgets or events. `detach` runs while objects are still valid and must restore owned changes. KET skips all three methods when `settings.enabled = false`. When the world is already invalid, KET forgets the active handle without calling template code.

The `player.quickslots` service exposes `valid`, `same`, `identity`, and `parent`. A quickslots template calls these methods directly. KET resolves the current QuickslotsSwitcher and invokes `attach(service, target, settings, previousHandle, categoryHandle)` only when that target is valid. If it is unavailable, KET keeps the selection pending without calling template code. A declared category event retries the attachment with its resolved target, then invokes `render(service, handle, target, eventName)`. Handles retain provider-owned mutation and restoration state; templates do not rediscover or retain the category parent merely for later rendering.

Every template declares `settings.target` (`"templates"` or `"module"`) and a boolean `settings.enabled`, merging `groups` and `fields` into that table when it exposes menu controls. A settings group may declare `heading = false` to keep its grouping and order without rendering a separator. A picker field may use `level = 1` to appear in the page header; each page supports one such picker. On a page for one category, KET places that category's template selector in the page header; the combined Templates page keeps category selectors in its list. A field may declare `visibleWhen = 'PickerId'` and `visibleValues = {0, 1}` to appear only for those values of an earlier picker in the same template; this row condition combines with the template selection condition. Hidden fields retain their values and are still passed in `settings`. Bundled templates default `enabled` to `true`, while a fresh configuration still keeps each category selector at `None`; a template begins running only after it is selected. A disabled template may remain selected, but KET records it without calling `attach`, `render`, or `detach`. KET validates committed `settings` values against any declared fields before invoking enabled lifecycle code. Templates can import `require("ket.widget")` for generic UE widget operations: `unwrap`, `property`, `number`, `translation`, `scale`, `opacity`, `setTranslation`, `setScale`, `setOpacity`, `snapshotSlot`, and `restoreSlot`. The category owns shared target discovery and hierarchy changes; each template owns its visual layout and restoration of its own changes.

## Built-in categories

- `player.quickslots`, `player.stats`, `player.charges`, `player.self`, `player.compass`, `player.notifications`, `player.wheel`
- `npc.attacks`, `npc.intent`, `npc.level`, `npc.melee`, `npc.pawn`
- `other.unknown`
- `menu.controls`, `menu.fixes`, `menu.templates`

Only categories with registered templates appear in the menu. A host may register additional categories before loading templates.

Every registered category starts as `{ visible = 0, count = 0, templates = {} }`. Category metadata can then be updated in place. The core definitions set `single = true` on every `player.*` category. For example, `ket:setCategory("player.quickslots", { visible = 1 })` sets `_categories.player.quickslots.visible` while preserving `single`, `count`, and `templates`. When registered files are loaded successfully, KET increments the category's `count` and appends each loaded template object to its `templates` array.

`menu.fixes` accepts inert Lua templates with no `attach`, `render`, `detach`, `events`, or `subscribe` fields. KET can register and select them as category metadata, but it never invokes their exported callbacks or registers native hooks on their behalf.

> The installed host now activates selected quickslot visuals and retries until the HUD wheel hierarchy is ready. The log reports when the visual attachment completes. This path has offline coverage; game acceptance after a restart is still pending.
