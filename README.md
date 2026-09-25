# ModCore Templates

The fresh lifecycle design and executable draft are documented in
[Lifecycle draft](docs/LIFECYCLE-DRAFT.md), with copied menu generation and Apply
routing described in [Template menus](docs/MENUS.md). The previous runtime remains available in Git history while this implementation
is being tested in Dawnwalker.

Mod data lives in `ModCore/templates`, `ModCore/categories`, and `ModCore/cache`.
Generated settings and page data use the cache; DMM's `mod_settings.ini` stays at root.

Build modular game-feature and UI customizations as Lua templates. Register
categories, expose settings, and implement `attach`, `update`, and `detach`.
ModCoreTemplates manages selection and lifecycle; the template supplies behavior.

## Features

- Single-selection or multiple-enabled templates per category.
- Generated category and module settings pages.
- Category-owned object and group selectors with event-driven lifecycle checks.
- Template callbacks receive effective settings: category settings overlaid by template settings.

## Requirements and installation

Use UE4SS with Lua 5.4, Dawnwalker Mod Menu, and ModCoreSettings for the documented
menu presentation. Install under `Mods/_ModCore_Templates` and enable the mod.
Disable the old `_UE4SSTemplatingEngine` installation before starting the game.
The Lua runtime starts on UE4SS's game thread and does not install a Templates
DLL. Its source-controlled template list loads from `ModCore/templates/index.lua`.
Cross-module native registration is not part of this installation. A separate
read-only probe verified HUD and group attachment in a loaded save.

ModCoreControls owns input separately. Select a visual template without moving
its input bindings into the template; one wheel should not need two steering columns.

## Lifecycle contract

`attach(object, settings)` runs once for each selected template and live object.
Committed settings changes call `update(object, settings)`. `detach(object, settings)`
restores owned changes while the object is valid; invalid objects are forgotten
without a callback. The live probe verified attachment and replacement on a HUD
root and group child. Valid detach and complete native parent-change coverage
still need game verification.

## Documentation

- [Developer guide](docs/DEVELOPERS.md): integration contracts and examples.
- [Build guide](docs/BUILD.md): source preparation and tests.
- [Changelog](CHANGELOG.md): changes by version.

Native object identity and invalid-reference handling: [Native lifetime references](docs/NATIVE-LIFETIMES.md).

Live selector resolution and UE4SS lifecycle hooks: [Object source](docs/OBJECT-SOURCE.md).
