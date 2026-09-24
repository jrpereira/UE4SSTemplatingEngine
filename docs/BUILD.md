# Build guide

- [Requirements](#requirements)
- [Generated menus](#generated-menus)
- [Offline tests](#offline-tests)
- [Validation limits](#validation-limits)

## Requirements

- Lua 5.4 for source checks and offline tests.
- Python 3 for the documented tooling.
- A compatible UE4SS/Dawnwalker installation for native integration checks.

These are Lua modules; there is no native compilation step in this repository.
Run the commands below from the repository root.

## Generated menus

The DMM extension generates current category and module pages during startup,
after loading registered templates. Preserve the identity catalog between runs
so settings keep their IDs. Edit template declarations rather than generated pages.

## Offline tests

The [test runner](../tools/run-tests.py) checks runtime Lua syntax and executes
the test suites from the repository root:

The menu integration suites use the real DMM parser and Settings presentation
module. Point the following variables at compatible local installations:

```sh
export KET_DMM_CHOICES="/path/to/ue4ss/Mods/DawnwalkerModMenu/Scripts/choices.lua"
export KET_AMM_PRESENTATION="/path/to/ModCoreSettings/Scripts/presentation.lua"
python3 tools/run-tests.py --lua lua
```

The runner verifies Lua 5.4 and creates local `work` and `outputs` directories.
An individual suite can be run as `lua tests/<suite>_test.lua`.

## Validation limits

Fixtures cover registration, metadata validation, generated menus, category
events, target readiness, and lifecycle transitions. They do not establish live
Unreal object validity, rendering, or garbage-collection behavior.

Validate repeated Apply, template switching, load/map changes, late events, and
restoration of the template's own mutations. A clean fixture is useful evidence;
the game still gets a vote.
