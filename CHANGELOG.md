# Changelog

What's new in Lyceum Study (study.lyceum.quest). The app shows this under What's new, without the Internal sections.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are release dates.

## [Unreleased]

### Added

- Reading goals. Each work in the library shows how much of it you can read: the share of its running words you know,
  and how many words you still need to learn to reach your goal. The goal is 95% by default, which most readers need
  to follow a text with help; 98% means reading on your own. A work's Reading goal page explains these thresholds,
  lets you set your goal, and works out either your finish date from the number of new words you learn a day, or the
  words a day you need to finish by a date you pick. It also lists the most frequent words to learn next.
- "Easiest first" sorts the library by how much of each work you can read already.
- Goals with a date appear on the Today panel.
- A word counts as known once you've given its meaning right on two days at least three weeks apart, without
  missing it since. Each word's page shows whether you know it, and you can mark a word you already know.

### Changed

- Progress counts words known and words being learned by this definition.

## [2026-11-04]

### Added

- The Gospel of Luke continues through chapter 2 (2:1-52), with prose translations and word-by-word glosses. These
  new passages have no literal translation yet.

### Fixed

- Grading the last passage of a work no longer brings the same passage back; it says you have finished the work.

### Internal

- Builds with Kai 0.0.10.

## [2026-10-21]

### Added

- A Support link in the menu, to support Lyceum on lyceum.quest.
- When you finish today's study, "Learn more" goes on to the next passages you haven't seen, and the finish screen links to your progress.

### Fixed

- Going on past today's study no longer stops the passages you just rated from coming back when they're due.

## [2026-10-20]

### Added

- The complete Epistle to the Romans (all 16 chapters) and Plato's Crito (the whole dialogue), for reading and study.
- Sync your progress across devices through your Lyceum account (for supporters).
- Passage cards replay your earlier attempts at a passage.
- This What's new page.

### Changed

- Aristos is now called Lyceum Study.
- A new look, matching Lyceum: Crimson Pro type, parchment and ink, burgundy and gold, a navy header.

### Fixed

- A new device's default settings no longer overwrite the settings saved in your account.

### Internal

- The texts come from Archeion's data releases; Archeion's release-staging pins and stages each one.
- The published CHANGELOG.md leaves out release drafts and Internal sections, like the What's new page.

## [2026-10-13]

- The first release recorded here. Earlier changes are in the git history.
