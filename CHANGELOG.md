# Changelog

All notable changes to Switchyard. Versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

- Works without internet. With no network, or a network that can't reach Jev (like in-flight Wi-Fi before you sign in), links without a rule open in the fallback profile right away instead of waiting 1.2 s each.
- Switchyard checks in the background (sooner after a network change) and, once Jev is back, asks about the links it opened without Jev. Confident answers learn rules; links Jev says belonged elsewhere get a **Move to …** button.
- One notification per outage instead of one per link, and offline links stay off the menu-bar badge until Jev has looked at them.

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
