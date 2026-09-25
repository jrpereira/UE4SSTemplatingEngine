# Native lifetime references (draft)

The native helper now tracks the lifetime of captured objects using Unreal's
object creation/deletion listeners. Tokens are non-owning: they neither root a
UObject nor prevent collection. They distinguish replacements even when Unreal
reuses both an address and an object-array index. Stopping a Lua session revokes
its references; the token counter is never reset.

`native/include/LifetimeIndex.hpp` is the portable, mutex-protected index.
`NativeLifetimes.hpp` connects it to the pinned UE4SS listener ABI. Creation and
deletion callbacks only update native records and enqueue loss tokens. They do
not call Lua, execute templates, or dereference the destroyed object.

Capture is restricted to the game thread. It checks the object's array slot using
guarded memory reads. The internal-index offset `0x0C` and array-item object
pointer at `0x00` are specific to the installed Dawnwalker UE5.5 target. These are
copied from the existing bridge's verified target ABI; other games/builds need
verification. This implementation does not call the exported FWeakObjectPtr
constructor or require serial-number allocation.

## Lua integration

The injected `MCTNative.lifetimes` exposes `capture(address)`,
`valid(address, token)` and `takeLost()`. Tokens are strings. The injected closures
capture their native session ID; old closures cannot access a replacement Lua
session. Native capture returns nil when listeners are unavailable, the slot does
not match, or the call is off the game thread. Validity is false off that thread.

`mct.native_references.new(source, MCTNative.lifetimes)` supplies the runtime host.
Alternatively pass `objectSource=source` to `mct.native_startup.start(options)`;
startup wraps it automatically. Do not supply both `objectSource` and `host`.

The source implements `valid`, `ready`, `matches`, `parent`, `find`, `subscribe`
and `onError` as described in [the lifecycle contract](LIFECYCLE-DRAFT.md).
It works with actual UObjects. The runtime works with private reference records;
its optional `host.unwrap` converts them back to UObjects immediately before a
template callback. Both native lifetime and source validity are checked first.
The source's `valid` must also reject unreachable or obsolete-world objects.

Only capture **fresh** wrappers obtained from live enumeration or a current engine
notification. An arbitrary retained address cannot prove which lifetime a newly
constructed Lua wrapper intended to reference. For deferred notifications, call
`host.capture(object)` while the notification's object is known live, then queue
that reference with the current epoch. Do not queue a raw address and reconstruct
a wrapper later. A previously captured wrapper is never recaptured under a new
token after invalidation.

Source `changed` events carry the object or captured reference; source `lost`
events carry that same object/reference instead of a host-specific string ID.
Other event kinds and epoch rules remain unchanged. Subscribe before the first
snapshot. The source must clean up partially installed subscriptions on failure.

## Delivery and remaining work

Native validity changes immediately on destruction. Settings commits and all
subsequent lifecycle operations reject an invalid reference without calling
`detach`. Loss IDs are consumed before source notifications; `host.flushLost()`
can also be invoked at an explicit game-thread lifecycle boundary. There are no
timers, recurring discovery scans or readiness retries.

**Immediate native-to-Lua loss wakeup is not implemented.** If no further lifecycle
operation happens, Lua attachment bookkeeping may remain until the next event;
it cannot make the destroyed reference valid. The native queue does not enter Lua
from a deletion callback or the event-loop thread, which avoids adding an
unverified cross-thread Lua call.

The [UE4SS object source](OBJECT-SOURCE.md) now resolves live WidgetTree paths
and subscribes to creation, reflected parenting/removal and map signals.
Construction alone does not establish readiness or membership. Complete native
parent-change coverage, immediate loss delivery and live loss verification
remain pending.

## Validation

The draft Lua runner covers callback unwrapping/settings, address reuse, captured
queued events, valid loss, invalid loss, readiness events, parent references and
unsubscribe. `LifetimeIndexTests` covers native reuse, Lua-session reset, object
array shutdown, slot mismatches and concurrent deletion. It runs under MSVC/CTest
and directly on Linux:

```sh
c++ -std=c++20 -Wall -Wextra -Werror -pthread -I native/include \
  tests/native/LifetimeIndexTests.cpp -o /tmp/mct-lifetime-tests
/tmp/mct-lifetime-tests
```

Offline tests and a successful DLL build validate the component's local logic and
imports, not listener behavior in the running game. Game verification is pending.
