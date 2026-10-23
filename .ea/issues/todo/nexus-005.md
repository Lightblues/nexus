---
schema_version: 1
id: nexus-005
title: Let `enrichApps` remove an app from enrichment
status: todo
priority: high
estimate: S
labels: [tracker, context-enrichment, config, feature-gap]
isolation: local
delivery: none
---

## Objective
Make the hardcoded bundle-id set in `ContextEnricher` a default rather than an override
of the user list, so removing an app from `tracker.enrichApps` actually stops that app's
Apple Events prompt and URL capture.

## Context
- `.ea/spec/tracker.md:172-185` ("## Config") — "`enrichApps` continues to whitelist
  which app names get URL/title enrichment to avoid prompting Apple Events permission
  for apps the user doesn't want tracked deeply." A whitelist is authoritative by
  definition; the code treats it as additive.
- `.ea/spec/decisions.md:226-241` (SADR-010) — the accepted decision that the compiled
  `NSAppleScript` per browser is "called only when the front app is in `enrichApps`".
  This is the strongest statement of intent, because it names the user list as the gate
  on the Apple Events call itself, not just on the resulting context.
- `Nexus/Features/Tracker/ContextEnricher.swift:9-19` — `enrichBundleIds`, the hardcoded
  set: VSCode, VSCode Insiders, Cursor, Chrome, Chrome Beta, Safari, Arc.
- `Nexus/Features/Tracker/ContextEnricher.swift:35-38` — `shouldEnrich` is
  `(probe.bundleId in enrichBundleIds) || config.enrichApps.contains(probe.app)`. The OR
  is the bug: it makes the user list able to add but never to remove.
- `Nexus/Features/Tracker/ContextEnricher.swift:41-42` and `:81-98` — the browser URL
  fetch via Apple Events, which runs as soon as `shouldEnrich` passes and is what the
  user is trying to switch off when they remove "Google Chrome".
- `Nexus/Features/Tracker/ActiveAppProbe.swift:12-16` — `bundleToAppName` maps bundle
  ids to the friendly names `Code` / `Code - Insiders` / `Cursor`, which is the
  vocabulary `enrichApps` is written in. Any replacement for the hardcoded set has to
  keep `probe.app` and the configured names comparable.
- `Nexus/Features/Tracker/TrackerModels.swift:32-37` — `ActiveProbe.app` is that
  friendly name; `enrichApps` is matched against it, never against the bundle id.
- `Nexus/Core/ConfigSchema.swift:86-102` — `TrackerConfig` and its decode defaults
  (`enrichApps = ["Code", "Google Chrome"]`). This is where a default list would live.
- `Nexus/Resources/default-config.json` — the bundled `tracker.enrichApps` value, copied
  verbatim into `config.json` by `ConfigService.ensureConfigFileExists()` on first
  launch. It must stay in step with `ConfigSchema`.
- `Nexus/Features/Settings/TrackerSettingsForm.swift:80-91` — the Settings copy already
  describes the intended rule: "Apps in this list get extra context tracking … Other
  apps record only the bundle id and window title." It needs no edit once the code
  matches it.
- `project.yml:35-37` — one application target, no test target, so the acceptance checks
  below are inspection plus a manual run.

## Tasks
- [ ] Remove the `enrichBundleIds` OR from `ContextEnricher.enrich` (`ContextEnricher.swift:35-38`) so `shouldEnrich` is decided by `config.enrichApps` alone
- [ ] Carry the hardcoded bundle-id set into the default value of `enrichApps` — as the friendly names from `bundleToAppName` (`ActiveAppProbe.swift:12-16`) plus the browser names — so the out-of-box experience does not narrow, and keep `Nexus/Core/ConfigSchema.swift:91`, `:100` and `Nexus/Resources/default-config.json` in agreement
- [ ] Confirm the friendly-name comparison still resolves every entry of the new default list; if an app's `probe.app` cannot express it (a bundle-id-only identity), keep that mapping in one named place instead of re-growing a second hardcoded set
- [ ] Leave the non-enriched path exactly as it is: `enrich` returns `(probe, nil)`, and the record is still written with app and bundle id. This change is about who gets enriched, not about what a non-enriched app records
- [ ] Update `.ea/spec/tracker.md:172-185` to state the same rule and the same default list, and note the SADR-010 sentence at `.ea/spec/decisions.md:236` is the behaviour now implemented

## Acceptance
- [ ] `grep -n "enrichBundleIds" Nexus/Features/Tracker/ContextEnricher.swift` returns nothing, and `shouldEnrich` reads only `config.enrichApps`
- [ ] `config.enrichApps` is the sole gate on `fetchBrowserURL`: with "Google Chrome" removed from the list, no `tell application "Google Chrome"` script executes for `com.google.Chrome` and no `ActivityContext.url` / `.domain` is stored for it
- [ ] Adding an app name to `tracker.enrichApps` still enables enrichment for it, as today
- [ ] A fresh install's `config.json` `tracker.enrichApps` equals the list in `Nexus/Resources/default-config.json`, which equals the default in `Nexus/Core/ConfigSchema.swift`
- [ ] Every app in the shipped default list is enriched on a fresh install — the default list covers the bundle ids that `enrichBundleIds` used to force, so nothing silently loses context tracking
- [ ] An app that is not in `enrichApps` still produces a `tracker_records` row with its app name and bundle id
- [ ] `.ea/spec/tracker.md` "## Config" and `Nexus/Features/Tracker/ContextEnricher.swift` describe the same whitelist rule

## Boundaries
- Always: keep the enrichment decision in `ContextEnricher.enrich`, where the Apple Events call is made, so the gate and the side effect cannot drift apart
- Always: keep the user-facing vocabulary (`enrichApps` holds app names, not bundle ids) unless the spec is changed in the same commit — the Settings `StringListEditor` placeholder at `TrackerSettingsForm.swift:88` tells the user to type an app name
- Never: keep a second hardcoded allow-list OR-ed with the config list; that is the defect being fixed
- Never: change what a non-enriched app records — it must still get its row
- Ask: whether an existing `config.json` whose `enrichApps` still holds the old `["Code", "Google Chrome"]` default should be migrated. `ConfigService` copies `default-config.json` only on first launch, so an existing user keeps the old list and would lose enrichment for Safari, Arc, Cursor and Chrome Beta unless a migration is written or the narrowing is accepted and recorded
