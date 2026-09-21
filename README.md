# UE4SSTemplatingEngine

Offline Lua 5.4 foundation for template registration, category validation, committed selection lifecycle, and DMM metadata generation decorated by AdaptiveModMenu. Intended installed directory: `Mods/_UE4SSTemplatingEngine`.

This is not an installed UE4SS mod yet. No native entry point, game discovery implementation, visual hooks, deployment, or release is supplied. Host adapters must settle registration/discovery before DMM parses generated metadata. Calling an InitGameState hook later does not hot-reload DMM's schema.

## Entry points

Add `Scripts/?.lua` to the module search path and `require('te.init')`. Construct `TE.new(options)` with a `listFiles(folder)` adapter returning full paths of immediate files (not directories); this registers the module's own `templates` folder. Supply `templatesFolder` and `categoriesPath` as absolute paths in a host. Core definitions are loaded from `categories.lua`. An empty templates directory is valid; Quickslots++ is owned by QSF, not bundled here.

The instance exposes `registerCategory(root, children)`, `registerTemplate(path)`, `registerTemplates(folder)`, `loadTemplatesFromRegister()`, `generateMenu(options)`, `bindInitHook(registerHook, onLoaded)`, and `subscribeApplied(settingsApi, menu, getContext, onResult)`. Optional registry adapters: `canonicalPath(path)`, `execute(path)`, and `environment(path)`. The default loader accepts Lua text and executes in the host environment. It is not a security sandbox. A custom environment is opt-in.

Path registration is idempotent by the canonical path key. The default only normalizes path separators; a Windows host should resolve absolute paths and case consistently in its adapter. Each successful file is evaluated once per registry instance. Batch validation commits no registry changes on failure, but cannot roll back side effects of arbitrary template Lua execution.

## Templates and ordering

A file returns a template or nested dense arrays. Empty arrays mean zero templates. Collection, category and display name are nonempty strings; the identity is their exact length-framed combination. Renaming one creates a new identity. Category names must be registered. `player.actions` requires nonempty groups with `name`, positive integer `slots`, and a string `type`. No unsupported type vocabulary is invented.

Data-only drafts can register and generate menus. Runtime activation additionally requires `attach`, `detach`, and `render` functions. Do not add `apply`/`restore` aliases as a second lifecycle.

The QSF draft uses named action groups, which do not define Lua iteration order. The generator therefore requires `groupOrders[templateIdentity] = {'key1', 'key2', ...}` from a host adapter for such maps. Ordered arrays are supported internally/tested, without declaring them the approved replacement QSF schema. Group names must be unique for stable setting IDs. Renaming a group changes its binding identities. Production ordering remains unresolved; no alphabetical/default ordering is silently chosen.

## Template-owned lifecycle

Agreed colon-method boundary:

```lua
template:attach(context, spec, previousHandle) --> handle | nil, error
template:detach(context, handle, reason)       --> true | false, error
template:render(context, handle, target, reason)
    --> 'applied' | 'not_ready' | 'ignored', error
```

`context` and `target` are opaque host/provider capabilities. QSF's template uses `context.quickslotsForever`; TE does not invent its engine services. The host ensures game-thread execution and live-world readiness before calls.

`runtime:apply(category, identityOrNil, committedConfiguration, context)` calls attach initially and on same-template Apply. It detaches before switching and detaches on None. Failed same-template attach preserves TE's prior handle/configuration; the template must restore pre-call state on failure. A failed switch attachment leaves no active template after successful old-template detach. Failed detach retains ownership and prevents switching. Successful repeated attach normally returns the same handle; preserving the original restoration snapshot is the template's responsibility.

`runtime:detach(category, context, reason)` forwards `switch`, `none`, `disable`, `world_pre_unload`, or `world_invalidated` as supplied by the host. Live restoration and forgetting dead wrappers are distinct provider operations. `runtime:render(...)` does not replace handles or schedule polling on `not_ready`. No native world-event or readiness scheduler is included.

`runtime:commit(event, decode, context)` accepts durable Apply revisions and a full numeric value snapshot. Successful duplicate/older revisions are ignored. Failed batches can be retried at the same revision; categories may succeed independently, and errors are returned by category. Configuration copies protect event data from callback mutation. Initial persisted selection must be provided explicitly through the host; the Apply subscription is not an initial-state snapshot API.

## Menu generation

`generateMenu` returns `manifest`, `catalog`, `rows`, `selectors`, `definitions`, `warnings`, and `decode(values)`. The host must persist the returned identity catalog with the generated manifest before starting DMM and reload that catalog for regeneration. Generation copies the catalog and retains removed identities. Losing the catalog loses the saved numeric identity contract; do not regenerate over user configuration without it.

A mode-A layout shows per-group level-5 headings and direct slot bindings, numbered consecutively. Mode B shows group activation bindings and shared slots up to the largest group size. First-group-default hides the first activation binding. Every key/mode pair has matching visibility. Group activation uses Tap/Hold values 0/2. Slot controls use QSF's confirmed 0/1 encoding; an unrelated host may explicitly pass another validated `slotModeValues` pair. Keys default to unassigned (0).

Selectors use compact tabs through eight total choices, otherwise ordinary pickers through 64 total choices including None. Generated schemas reject more than 256 settings or manifests above 256 KiB. Unsupported INI separators/control characters are rejected, not escaped ambiguously. Unknown payload renderers generate selection only plus a warning. AMM 0.2.0 initializes missing ordinary config entries before DMM opens the provider; generated defaults use this existing mechanism.

QSF confirmed slot modes 0/1 (Tap Trigger / one-shot Hold Trigger), group modes 0/2 (Tap Trigger / Hold Sustained), and access 0/1 (direct / grouped). Its adapter supplies its existing committed/default global HoldThresholdMs outside TE's spec and validates nonzero VK values against its own native key table. No threshold menu setting or native key map is invented here.

**Known product gap:** current DMM has no None-only picker or standalone display row. Empty categories are omitted and returned as warnings. Meeting a persistent row for every registered empty category requires an AMM/DMM extension. No fake selectable value is generated.

## Offline verification

Use Lua 5.4 and point integration tests at the actual installed consumer source:

```powershell
$env:TE_DMM_CHOICES = '<DMM source>/Scripts/choices.lua'
$env:TE_AMM_PRESENTATION = '<AMM source>/Scripts/presentation.lua'
$env:TE_QSF_TEMPLATE = '<QSF source>/templates/default.lua'
python tools/run-tests.py --lua '<Lua 5.4 executable>'
```

Tests exercise the real parser/decorator and DMM pending visibility model; they do not prove rendered native UI or gameplay restoration. The generated example under `outputs` uses ordered synthetic test groups and is not QSF's authoritative template.
