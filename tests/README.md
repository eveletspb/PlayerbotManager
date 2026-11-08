Run from the addon directory with LuaJIT (Lua 5.1 semantics):

```sh
luajit tests/import_test.lua
luajit tests/bridge_test.lua
luajit tests/windows_test.lua
luajit tests/cancellation_test.lua
luajit tests/inspect_test.lua
luajit tests/legacy_test.lua
luajit tests/group_test.lua
luajit tests/card_test.lua
```

These tests run the addon logic with fake WoW APIs. The windows test loads the
complete window module; cancellation tests execute the shipped button callbacks
without building the surrounding layout. They cover the audit regressions and
legacy fallback, but do not establish in-game behavior or FPS.

Regressions include inspect/talent exclusion and lock recovery, cross-window
request ownership, valid zero-score versus invalid bridge gear snapshots,
single/group scan fallback, and command routing in small raids, parties and solo.
