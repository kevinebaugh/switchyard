# Changelog

All notable changes to Switchyard. Versions follow [Semantic Versioning](https://semver.org).

## [0.9.7] - 2026-10-23

- **Fixes lost rules for Dropbox users.** Rules were kept in Dropbox's `Apps` folder, and when that folder is excluded with Selective Sync, Dropbox moves anything written there aside ("Apps (Selective Sync Conflict)"), taking the rules with it. Rules now live in `Dropbox/Switchyard`. On first launch, Switchyard merges in the old folder and any moved-aside copies, and rebuilds rules that Recent still points to from its history.
- Editing a profile description: Return saves (Option-Return adds a line) and a "Saved" check confirms it. Each profile's name and colour are easier to read.
- A Profiles tab for what each profile is for (what Jev reads), with each profile's rule count and the fallback profile. It's also reachable from any Recent row's menu: **Edit What Each Profile Is For…**.

## [0.9.6] - 2026-10-18

- The support reminder uses calm accent colours instead of red.

## [0.9.5] - 2026-10-09

- Firefox support. Switchyard lists the profiles Firefox's profile menu shows, with their names and theme colours, and opens each link in the right one. Each Firefox profile runs as its own app, so a link may bring a different Firefox window forward. Setup asks once for access to Firefox's data folder, as it does for Chrome.

## [0.9.4] - 2026-10-09

- Runs on Intel Macs too: the app is now universal (macOS 26 or later).
- Works without internet. With no network, or a network that can't reach Jev (like in-flight Wi-Fi before you sign in), links without a rule open in the fallback profile right away instead of waiting 1.2 s each.
- Switchyard checks in the background (sooner after a network change) and, once Jev is back, asks about the links it opened without Jev. Confident answers learn rules; links Jev says belonged elsewhere get a **Move to …** button.
- One notification per outage instead of one per link, and offline links stay off the menu-bar badge until Jev has looked at them.
- Settings shows whether macOS allows Switchyard's notifications, with a shortcut to System Settings.

## [0.9.2] - 2026-10-02

- An occasional, one-time support reminder: every 50 links (at most weekly, never in your first week), as a card in Recent and a quiet notification. Routing is never affected.
- Pay what you want, once ($10 suggested; 1% goes to carbon removal). After checkout, Switchyard turns the reminders off on its own. "I've already supported" does the same.
- Settings has a Support section.

## [0.9.1] - 2026-10-02

- The About window shows the licenses as readable text instead of raw Markdown.

## [0.9.0] - 2026-10-02

The first public release.

- Opens every link in the right browser profile: local rules first, then Jev for links no rule covers, learning confident answers as rules.
- Works with Dia and Chrome; Brave, Edge and Vivaldi should work but are untested.
- Recent explains every routing, with one-click corrections at any scope (domain, host, path, account parameter, or every link from an app).
- Rules tab with search-or-add, profile filters and most-recently-used ordering.
- First-run setup: browser, permission, profiles, Jev key, drafted profile descriptions, default browser.
- Rules sync between Macs through iCloud Drive or Dropbox, safely across Switchyard versions.
- Notifications for fallbacks and unsure picks, with "was right" and "should be" actions.
- Requires macOS 26.
