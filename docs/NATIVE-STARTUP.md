# All-modules startup boundary

MCT needs completion of **all** modules' initial Lua loading before it executes
registered templates. The native startup helper now delivers this notification
once per MCT Lua session, through the first `CppUserModBase::on_update` callback.

This targets the UE4SS **event-loop start boundary**, not an individual module's
load completion, a guessed delay, BeginPlay, or a repeating Lua timer.

## Evidence from the pinned source

The local installation targets UE4SS commit `97b7e501`. In its
[UE4SSProgram.cpp](https://github.com/UE4SS-RE/RE-UE4SS/blob/97b7e501/UE4SS/src/UE4SSProgram.cpp),
`update()` calls `on_program_start()`, which starts all Lua mods. After that returns,
it prints `Event loop start`, processes queued events and calls each started mod's
update callback. MCT's first native update is therefore after the initial complete
loading batch. It is not literally a callback on the log statement, nor necessarily
the first callback among all native mods.

In the pinned
[LuaMod.cpp](https://github.com/UE4SS-RE/RE-UE4SS/blob/97b7e501/UE4SS/src/Mod/LuaMod.cpp),
each Lua mod starts its async thread before executing `main.lua`. `ExecuteAsync`
therefore does not provide this all-modules guarantee.

## Native helper

- `native/src/LoopStartMod.cpp` implements the UE4SS mod entry points.
- It injects `Scripts/mct/loop_start.lua` into `_ModCore_Templates` before that mod's
  `main.lua` executes, exposing `MCTNative.onLoopStart(callback)`.
- `native/include/LoopStartQueue.hpp` queues the session notification until the next
  native update. Stopped sessions are cancelled; reused Lua-state addresses do not
  revive old notifications. Delivery is consumed before executing the callback.
- The Lua subscription returns an unsubscribe function. Callbacks are isolated,
  and a repeated native signal cannot fire them again.
- Later UE4SS updates do no object discovery or readiness polling. A newly started
  MCT Lua session can receive its own one-shot notification on a subsequent update.

The small ABI header/import definition are copied from the project's existing
ABI-pinned bridge declarations. The helper imports the Lua, C++ mod and object-listener primitives it uses. It does not modify or depend on the bridge module itself.
A different UE4SS revision requires ABI verification before using this DLL.

## Lua wiring

Call `require('mct.native_startup').start(options)` from the eventual MCT native-host
entry point. Options retain the bootstrap's required object `host`, category/template
files, menu root and settings API. The startup adapter supplies:

1. The native all-modules Loop Start subscription.
2. Game-thread dispatch for object discovery and settings changes.
3. The cross-state menu handoff when `menuRoot` is supplied.

At Loop Start, bootstrap loads templates and generates/restores their menus. Its
phase then becomes `starting` while the object runtime is queued onto the game
thread. Only successful runtime startup changes the phase to `running` and marks
the menu generation ready. Stopping during that interval cancels the queued start.

The adapter requires the verified `MCTNative` API; it never silently falls back to
a delay. `Scripts/main.lua` now supplies source-controlled category/template file lists.
`native_startup` creates the [UE4SS object source](OBJECT-SOURCE.md) from those
categories unless a host/source is explicitly supplied. The native helper also
provides non-owning lifetime tokens, native invalidation and a cross-module
registration function. A safe immediate loss wakeup and complete native UMG
parent-change coverage remain pending.

## DMM's separate Lua state

`Scripts/dmm_extension.lua` is now a real DMM extension entry point. It installs a
lazy menu reader, without starting another object runtime inside DMM.

The publisher and reader coordinate using scalar `ModRef` shared variables and the
generated files in `ModCore/cache` (plus DMM's required root manifest). A new startup clears readiness before publishing a new generation.
The reader accesses files only after readiness is published, checks the generation
again after reading both files, and caches the completed result. An older startup
cannot mark a newer generation ready or invalidate it when stopping.

At DMM page-build time, stale MCT-generated providers are removed. If MCT is still
starting, its pages stay unavailable. Once ready, the aggregate manifest and routed
pages are loaded from the current generation—even if DMM initially scanned providers
before MCT generated them. A later page build observes a reload's new generation.
This does not force-refresh an already open DMM UI.

## Build and validation

From an x64 MSVC developer shell with CMake and Ninja:

```sh
cmake -S native -B work/native-startup-win -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build work/native-startup-win
ctest --test-dir work/native-startup-win --output-on-failure
```

The resulting DLL is `work/native-startup-win/dist/_ModCore_Templates/dlls/main.dll`.
The portable queue test also builds directly with a C++20 compiler:

```sh
c++ -std=c++20 -Wall -Wextra -Werror -I native/include \
  tests/native/LoopStartQueueTests.cpp -o /tmp/mct-loop-start-tests
/tmp/mct-loop-start-tests
```

The [draft Lua test runner](MENUS.md#tests) also tests one-shot callbacks, delayed
game-thread startup, cancellation, late menu generation and reload generation races.
The DLL has built under MSVC and its queue tests passed on Windows and Linux. It has
been exercised through a separate read-only Dawnwalker probe. `Scripts/main.lua`
is present and wired to this helper, but the full draft has not replaced the
installed MCT mod.
