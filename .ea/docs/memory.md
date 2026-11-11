# Memory watch

When the Mac comes under memory pressure, nexus names the processes holding the memory in a notification, and writes the episode to a file baton reads. It only informs: it never quits, kills or signals a process (SADR-021). Code: `Nexus/Features/Memory/`. Design and the split with baton: baton `.ea/log/2026-11-11-mac-memory.md` (decision B035).

## Pipeline

```
DispatchSource.makeMemoryPressureSource([.normal, .warning, .critical])   event-driven, no polling while normal
  └─ on an event, and every 10 s while the level is warn or critical:
     MemorySampler.snapshot()          on a utility queue
       level      sysctl kern.memorystatus_vm_pressure_level (1 normal, 2 warn, 4 critical)
       system     hw.memsize; host_statistics64: used = (internal − purgeable) + wired + compressed; vm.swapusage
       processes  proc_listallpids → proc_pid_rusage (phys_footprint, CPU time) → top 8 by footprint
     MemoryWatchService.check()
       first raised reading   → event `pressure`, start the 10 s timer
       later raised readings  → event `sample`
       back to normal         → event `pressure_end`, stop the timer
       NotifyGate             → notification
```

`phys_footprint` is what Activity Monitor's Memory column and `top`'s MEM show; it counts compressed memory, which RSS does not. `proc_pid_rusage` reads only this user's processes (the app is not root and has no entitlement for more); other users' processes, such as root daemons, are skipped. CGPDFService, Chrome and editors run as the user.

## Names

Only names leave the sampler. `proc_pidpath` is read to derive two names and then dropped: `name`, the executable's file name (`Google Chrome Helper (Renderer)`), and `app`, the outermost `.app` bundle on the path without `.app` (`Google Chrome`), else the executable name (`CGPDFService`). Arguments are never read.

## Notification

Title `Memory pressure warning` or `Memory pressure critical`; body the top 3 apps by summed footprint (`CGPDFService 21 GB · Google Chrome 9.0 GB · Code 5.0 GB`); one action, "Open Activity Monitor" (a click on the body does the same). Sound only at critical. `NotifyGate` allows one notification per 15 min, except when the level rises to critical (once per episode) or an app becomes the top one that has not been named in the last 15 min. The 15-min window spans episodes.

## Events for baton

Format and path are baton's (baton `.ea/docs/machines.md`, "Machine events"; until baton-047 lands, the design note's "Data contract"). nexus conforms; neither side needs the other.

- File: `~/.baton/machine-events/<YYYY-MM-DD>.jsonl`, the local date, append-only, one object per line. The directory is created on the first write; files whose date is more than 7 days before today are deleted at launch (and when the setting is turned on).
- Line, keys in this order, byte counts as integers, `t` in UTC with milliseconds:

```json
{"v":1,"t":"2026-11-11T06:19:30.000Z","source":"nexus/1.3.1","kind":"sample","level":"critical","mem":{"total":51539607552,"used":49392123904,"compressed":12884901888,"wired":4294967296},"swap":{"used":10737418240,"total":12884901888},"top":[{"pid":4242,"name":"CGPDFService","footprint":22333829939,"cpu_pct":97.5}]}
```

- `kind`: `pressure` on the rise, `sample` every 10 s while raised, `pressure_end` on the return to normal. `top` holds the 8 largest processes (by executable, not grouped by app); `cpu_pct` is the share of one core since the previous reading, 0 on the first. An episode still open when nexus quits has no `pressure_end`.

## Settings

| Key | Default | Effect |
|---|---|---|
| `memory.enabled` | `true` | Off: no dispatch source, no notification, no file |
| `memory.notifyLevel` | `warn` | `warn` or `critical`: the lowest level that notifies; events are written at both |
| `memory.writeEvents` | `true` | Off: notifications only, no file |

Settings → Memory. They sync like every other setting.
