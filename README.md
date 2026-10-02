<p align="center">
  <img src="docs/logo.svg" width="128" height="128" alt="Switchyard icon: one incoming link forking into three routes, the chosen one lit">
</p>

# Switchyard

**Every link on the right track in your browser.**

Switchyard is a macOS menu-bar app that opens every link in the right browser profile, and learns as it goes. It works with [Dia](https://www.diabrowser.com/) and [Chrome](https://www.google.com/chrome/), and should work with Brave, Edge and Vivaldi.

## Browsers

| Browser | Opens links via | Setup asks for | Status |
| --- | --- | --- | --- |
| Dia | Dia's AppleScript dictionary (Dia ignores Chromium's profile flag) | Automation permission for Dia | Supported |
| Chrome | `--profile-directory`, handed to the running Chrome | Access to Chrome's data folder, to read its profiles | Supported |
| Brave, Edge, Vivaldi | Same as Chrome | Same as Chrome | Should work; not yet tested |
| Safari | Safari's scripting has no way to choose a profile | | Not possible today |

You pick one browser during setup. Rules remember which browser they're for, so switching browsers later won't mix them up.

Inspired by [jdsimcoe/dia-router](https://github.com/jdsimcoe/dia-router). Instead of hand-written rules, links that no rule covers are decided by **Jev**, [TypeSafe](https://typesafe.ai)'s System One model: typed answers with calibrated confidence in roughly 70–500 ms. Confident answers turn into local rules, so the same kind of link never asks Jev again.

## How a link is routed

1. Switchyard is the default browser, so macOS hands it every `http`/`https` link.
2. **Rules first.** The rules are held in memory, most specific wins, and a lookup takes microseconds with no network. A rule can match:
   - a whole domain (`all of slack.com`)
   - an exact host (`acme.slack.com`)
   - a path prefix (`app.shortcut.com/acme`)
   - an identifying query parameter (`mail.google.com ?authuser=…`)
3. **App rules.** A rule like "links from Slack → Work" routes every link clicked in that app. It beats rules Jev learned, but rules you made or corrected still win.
4. **Otherwise, Jev.** One request asks two questions in parallel:
   - Which profile should open this link? The options are your browser's profiles, described in Settings.
   - Which part of the URL identifies the account? The answers are domain, subdomain, first path segment, query identifier, or "can't generalize".
   - Only the host, the first three path segments and the *names* of any query parameters are sent. Query values and fragments stay on your Mac, so a rule like `mail.google.com ?authuser=…` keeps its value and is matched locally.
5. **Decide.** What happens depends on Jev's confidence:

   | Jev's answer | Result |
   | --- | --- |
   | Profile confidence ≥ 0.7 (adjustable) | Open there and save a rule at the scope Jev picked |
   | Lower confidence | Open in Jev's top pick; nothing is saved, and the row is flagged ⚠︎ |
   | No key, timeout (1.2 s), offline, or an error | Open in the fallback profile (**Personal**) and show the reason |

6. The browser opens the link in the chosen profile. Dia is asked through its AppleScript dictionary; Chrome and friends get `--profile-directory`, which the running browser picks up. Neither needs Accessibility permission or keyboard shortcuts.

The browser is the source of truth for profiles: they're read from its `Local State`, and renames are followed automatically.

## Menu bar

- **Recent**: the last 25 links, each with its profile and a plain reason for the choice:
  - `Your rule: links from Slack` or `Learned rule: github.com/acme`
  - `Jev 0.84 · learned github.com/acme` or `Jev 0.96 · nothing saved (too specific)`
  - `Jev unsure (0.47) · nothing saved` or `Fallback: Jev timed out`, both shown in orange

  Below the reason: the app the link came from, when it was routed, and how long the decision took.
  - After 3 links in a row from one app land in the same profile, Recent offers to make an app rule ("Always open links from Slack in Work?").
  - The ↪︎ menu on each row is **"Should have opened in…"**. It lists every scope that URL supports (all of the domain, the exact host, one or two path segments, the account parameter, or every link from the app it came from) or "just this once". The link re-opens in the right profile and the rule is saved, replacing any rule with the same scope. **"… was right: remember"** saves a rule for the profile it's already in.
- **Rules**: most recently used first, with profile filters. Each rule shows whether Jev learned it or it's yours, and when it last fired. Rules unused for 90 days fade to the bottom. One field searches, and it offers to add what you typed if it's a new rule (`app.shortcut.com/acme`, `*.slack.com`, `mail.google.com?authuser=me@x.com`). Usage is tracked on each Mac, not in the synced rules file.
- **Settings**:
  - the TypeSafe API key (stored in Keychain)
  - the confidence threshold and fallback profile
  - a description of each profile, which is what Jev reads
  - a **Test** field that shows a decision without opening anything
  - the rules folder, default browser, open at login, and notifications

## Notifications

Only for loud events:
- **Fallbacks**, e.g. "Jev was too slow · app.foo.com → Personal".
- **Optionally**, low-confidence routings, e.g. "Jev wasn't sure · app.foo.com → Personal · 0.61".
- **Setup problems**: missing or invalid key, the browser missing, or its permission denied.

Routing notifications offer **Personal was right**, which saves a rule for that link without re-opening it. They also offer **Should be …** for each other profile, which re-opens the link there and saves the rule. Either way, the next link like it opens instantly. Routing notifications are limited to one every 5 minutes.

## Updates

Switchyard updates itself with [Sparkle](https://sparkle-project.org). It checks daily, which you can turn off in **Settings → Updates**; **Check for Updates…** is there too. Every update is signed, and Switchyard only installs ones signed with its own key. Your rules, settings and permissions carry over, and updates never re-run setup.

## Syncing rules between Macs

Rules live in `rules.json` in a folder you choose: **iCloud Drive** (the default when it's enabled), **Dropbox**, or **this Mac only**.
- Rules name profiles by *name* (and browser), not by the browser's folder, so they work on a Mac where the folders differ.
- Every write merges with what's on disk: the newer edit wins, and deletions are tombstones. Two Macs editing at once don't lose or resurrect rules.
- History and the API key stay local.

## Build and install

Requires macOS 26 or later, one of the browsers above, and a [TypeSafe](https://typesafe.ai) API key for Jev. Building from source needs Xcode (or the Command Line Tools).

```sh
swift test
./scripts/install-app.sh   # builds, installs to /Applications, launches
```

On first launch, a setup window walks you through the steps:
1. You pick your browser.
2. You give Switchyard the one permission that browser needs (skipped if it's already allowed):
   - **Dia:** Automation, so Switchyard can ask Dia to open tabs and list profiles in Dia's order. It covers Dia only; it isn't Accessibility.
   - **Chrome and friends:** access to the browser's data folder, which macOS protects, so Switchyard can read the profile list (and, on this Mac only, what each profile uses most). Opening links needs nothing extra.
3. It finds your profiles.
4. You connect Jev with your TypeSafe API key ([console.typesafe.ai/keys](https://console.typesafe.ai/keys)). The key is checked when you continue.
5. Switchyard drafts a description of each profile from the sites it uses most (and, in Chrome, the account it's signed in to), read locally from the browser's history, and you edit them. A profile without enough history is left blank rather than guessed.
6. You make Switchyard the default browser. This is the one step you can put off ("Not yet").
7. You choose login, notification and rules-sync options.

If you close the window partway, the menu offers to finish setup later.

You can run it again from **Settings → Run Setup Again…**.

After setup, opening Switchyard (launching it, or opening it again while it's running) checks that it's still the default browser. If another browser has taken over, macOS asks whether to switch back.

### Describe your profiles

Jev knows only what your descriptions say, so they're the most important setting. Name the accounts and tools each profile is signed in to. For example:

| Profile | Description |
| --- | --- |
| Work | Acme Corp: you@acme.com Google Workspace, Acme's Slack and Linear, the `acme` GitHub organization, Datadog, internal admin tools. |
| Personal | Personal Gmail, banking, shopping, news, social media, side projects. The default for anything not clearly work. |
| Test | A throwaway account used to try products as a new user: sign-up flows, OAuth into third-party services. |

Setup drafts these for you (see above). A profile added later starts with a generic description if it's named `Work`, `Personal` or `Test`, and empty otherwise. Descriptions are stored on your Mac, not in the rules file.

`./scripts/release.sh` builds a notarized DMG, a zip and the update feed (`appcast.xml`) for a release (it needs a Developer ID identity and stored notarization credentials; see the script's header).

Without an Apple Development signing identity the app is ad-hoc signed. macOS may ask again for Automation and Keychain access after each rebuild. To use a stable identity, put `export SWITCHYARD_SIGNING_IDENTITY='Apple Development: …'` in `scripts/signing.local.zsh` (gitignored).

Scripting: `open 'switchyard://open?url=https%3A%2F%2Fexample.com&profile=Test'` opens a link in a named profile.

## Rehearsing setup

To try the first-run experience again without losing your real setup:

```sh
./scripts/rehearse-onboarding.sh                     # throwaway settings, key, rules and history
./scripts/rehearse-onboarding.sh --reset-permission  # also clear the Automation grant first
```

Quit Switchyard from the menu bar when you're done, and your normal setup relaunches. The default browser setting is system-wide, so a rehearsal sees it as it really is.

To review every setup screen as images (light and dark, including error states):

```sh
./scripts/build-app.sh
build/Switchyard.noindex/Switchyard.app/Contents/MacOS/Switchyard --snapshot-onboarding /tmp/switchyard-screens
```

## Privacy

- Links that match a rule never leave your Mac.
- For other links, the request to TypeSafe contains:
  - the host and the first three path segments, with no query values or fragment
  - the names of any query parameters
  - the name of the app the link came from
  - your profile names and descriptions
- Full URLs appear only in local history.

## Icon

`docs/logo.svg` is the flat logo. `Resources/AppIcon.icon` is the same artwork as an Icon Composer bundle: layered SVGs on a gradient, rendered as Liquid Glass. `scripts/build-app.sh` compiles it with `actool`. `Sources/Switchyard/MenuBarGlyph.swift` draws the matching menu-bar template image.

## Layout

- `Sources/RouterCore`: pure, tested logic.
  - rules and the most-specific-wins index
  - public-suffix handling
  - scopes
  - Jev wire types
  - decision policy
  - sync merge
  - Chromium `Local State` parsing and the browser table
- `Sources/Switchyard`: the app.
  - Apple Event URL handler
  - Jev client (hard deadline, keep-warm connection)
  - browser adapters: Dia via AppleScript, Chrome and friends via `--profile-directory`
  - stores, notifications, SwiftUI menu

## License

MIT; see [LICENSE](LICENSE). Two small pieces are adapted from [jdsimcoe/dia-router](https://github.com/jdsimcoe/dia-router), also MIT; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Switchyard is an independent project, not affiliated with or endorsed by The Browser Company (Dia), Google (Chrome) or TypeSafe AI.
