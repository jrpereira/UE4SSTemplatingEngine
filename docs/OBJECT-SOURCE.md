# UE4SS object source draft

`Scripts/main.lua` now loads the source-controlled category and MCT template
lists in `ModCore/categories/index.lua` and `ModCore/templates/index.lua`.
`mct.native_startup` constructs `mct.widget_source` before subscribing to the
one-shot Loop Start barrier. Other Lua modules can call
`MCTRegisterTemplate('<absolute path>/<Module>/ModCore/templates/file.lua')`
from their `main.lua`; UE4SS injects that function before each module's main
script. It returns `true` for a new or duplicate registration, or `false, reason`
when the path is invalid or Loop Start has closed registration. The native
registry transfers registered paths to MCT once, at Loop Start. Late
registrations are rejected.

At Loop Start, MCT executes all registered templates, generates the DMM menus,
restores committed settings and queues the object runtime on the game thread.
The source subscribes to UE4SS notifications before the runtime's first
snapshot. The initial snapshot and new-world snapshots use `FindAllOf` only
once per selector. An unloaded blueprint class may yield `nil`; that means no
candidates yet. Other changes reevaluate cached candidates.

## Path matching

`mct.object_selector` interprets class selectors with `IsA` and resolves
`WidgetTree` object selectors against a live widget's outer chain. The
QuickslotsSwitcher selector must have the requested widget class and name,
its immediate outer must be a live `WidgetTree` instance (`WidgetTree` or
`WidgetTree_<number>`), and that tree's live owner must have
exactly the declared HUD blueprint class. Class defaults and objects belonging
to another blueprint with the same final widget name are excluded. A live
world token identifies the current map after `LoadMapPost`; an old HUD can
remain valid without attaching to the new world.

## Readiness and hierarchy

`NotifyOnNewObject` registers for declared classes and WidgetTree owners. A
creation notification retains an unready candidate; it does not trigger
attachment by itself. `UserWidget:AddToViewport` and `AddToPlayerScreen` mark the owner ready
and wake cached candidates. Nested HUD widgets can also become ready when
they have a live world and a valid panel parent; `IsInViewport()` is not a
usable signal for Dawnwalker's nested `WBP_GameHUD`. `Widget:RemoveFromParent`
marks a user-widget owner unready before removal and detaches valid matches.
An already parented HUD widget may attach from a snapshot.

For widget selectors, including `within` groups, hooks on reflected
`PanelWidget:AddChild`, `PanelWidget:RemoveChild` and
`PanelWidget:ClearChildren` wake cached candidates after hierarchy changes.
`Widget:RemoveFromParent` also wakes descendants after removal. An `AddChild`
callback clears a nested UserWidget's removal marker so it can attach again.
Non-root widgets require a valid panel parent even when their owner is ready.
`GetParent` supplies widget ancestry. Other object classes use `GetOuter`.
Map pre-load makes objects unready and detaches valid attachments; post-load
invalidates the old set, records the new world and starts one new snapshot.
The native reference host rejects destroyed objects before any UObject method
or template callback and never calls `detach` for them.

A live hook survey on the pinned UE4SS build found `UserWidget:Construct`,
`Destruct` and `OnInitialized` unavailable to `RegisterHook`. The viewport,
parenting and removal hooks above registered successfully. These hooks cover
reflected UMG calls. Direct native C++ calls may bypass a
UFunction hook, so **group parent changes are not yet guaranteed complete**.
Native lifetime invalidation is immediate, but the Lua loss queue still needs
an event-driven wakeup to clear bookkeeping when no other event follows.

A separate read-only probe was exercised in Dawnwalker. After correcting
live WidgetTree suffix matching, the probe attached once to the
`QuickslotsSwitcher` and once to its `WBP_HUD_Quickslots` group child.
`PanelWidget:AddChild` callbacks were observed in gameplay. A later HUD
replacement produced one attachment for each new object; a valid detach
was not observed. These limits block a claim of complete lifecycle
management. The full draft has not replaced the installed MCT mod; the
probe's enable marker was removed after testing.
