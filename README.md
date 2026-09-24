# ModCore Templates

Build modular game-feature and UI customizations as Lua templates. Register
categories, expose settings, and implement `attach`, `render`, and `detach`.
ModCoreTemplates manages selection and lifecycle; the template supplies behavior.

## Features

- Single-selection or multiple-enabled templates per category.
- Generated category and module settings pages.
- Category-owned target discovery and declared event delivery.
- Widget helpers for reading, changing, and restoring visual properties.

## Requirements and installation

Use UE4SS with Lua 5.4, Dawnwalker Mod Menu, and ModCoreSettings for the documented
menu presentation. Install under `Mods/_ModCore_Templates` and enable the mod.
Disable the old `_UE4SSTemplatingEngine` installation before starting the game.
Existing `TE_` settings are not migrated to the current `KET_` identifiers.

ModCoreControls owns input separately. Select a visual template without moving
its input bindings into the template; one wheel should not need two steering columns.

## Lifecycle contract

`attach` prepares state and must tolerate repeated Apply operations. `render`
handles discovered targets or declared events. `detach` restores owned changes
while the target is valid. If the world is already invalid, the host discards
handles without calling template code.

Catalog entries without templates do not implement game features. Validate native
object discovery, restoration, and reload behavior in-game; offline tests cover
the Lua contracts.

## Documentation

- [Developer guide](docs/DEVELOPERS.md): integration contracts and examples.
- [Build guide](docs/BUILD.md): source preparation and tests.
- [Changelog](CHANGELOG.md): changes by version.
