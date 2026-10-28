# Your data across versions

Switchyard keeps your rules, settings and history across every update, and between Macs running different versions. This is what each version promises, and how it's enforced.

## Rules (`rules.json`)

- **Versioned.** The file records its format version (currently 2). When the format changes, the version goes up.
- **Older versions never overwrite newer files.** A Switchyard that finds a newer format, or a rule it can't read (say, for a browser it doesn't know yet), still routes with every rule it understands. Its Rules tab goes read-only and asks you to update, and it never writes the file. Nothing a newer Mac added can be lost.
- **Newer versions read every older format.** Rules from version 1 files (written before Switchyard supported more than Dia) are Dia rules.
- **Edits merge rather than overwrite.** Rules are matched by ID, the newer edit wins, and deletions leave a marker for 30 days so two Macs editing at once don't lose or bring back rules.
- **The folder can move, but only with a migration.** If a sync folder ever has to change, Switchyard merges the old location in automatically, as 0.9.7 did when it moved Dropbox rules out of `Dropbox/Apps`.

Enforced by `Tests/RouterCoreTests/CompatibilityTests.swift`, which reads frozen rules files from every format on every build. Fixtures are only ever added, never edited.

## Settings

- **Setting names never change meaning.** Every key is listed in `Sources/Switchyard/SettingsKey.swift`. To change what a setting means, a new key is added and the old one migrated once.
- **Your API key** lives in the macOS Keychain, not in settings, and is never synced.
- **Profile descriptions** stay on each Mac. They aren't in the synced rules file.

## Caches

`history.json` (Recent) and `rule-usage.json` (when each rule last fired) are caches kept on each Mac. A future version may reset them if their format changes. Your rules don't depend on them.

## Supporter status

A support payment stays recorded on each Mac where it was confirmed, across updates.
