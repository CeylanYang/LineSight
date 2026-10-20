# LineSight 1.1.10 — Chinese and English

The Profile tab (我的 / Profile) now contains a full clickable **语言 / Language**
setting immediately below the account card. Its dialog offers **中文** and
**English**, indicates the current choice and applies the selected language
without signing out. The sign-in and storage-failure pages also provide a
language selector so new and locked-out users can read the interface.

Chinese is the default, including when the Android system is English. The
language is a device preference shared by local accounts and saved in SQLite.
Language and appearance saves use the same serialized queue. Failed preference
writes do not publish a successful language change. Unsupported saved language
codes fall back to Chinese. In storage-failure recovery, a selection can be
applied in memory when the normal preferences cannot safely be written.

The application-owned catalog contains 934 bilingual messages. Navigation,
forms, review validation, statistics, recipes, help, backups, restore previews,
service errors and progress labels use the active locale. Flutter's material
controls and date pickers use the same locale. User names, recipe names,
materials, original audit prose and review notes retain their original text.
Built-in defect labels have English display/search aliases; stored defect
values stay canonical. Search, action filters and restore comparisons continue
to use their original data identifiers.

CSV headers follow the language captured when the export preview is opened.
The 15 columns retain the same order, escaping, UTC timestamps and original
business values. Later language changes do not mutate the export snapshot.
LSB/JSON backup formats and SQLite schema remain unchanged.

English text can be longer, so recipe status labels wrap, narrow section actions
flow below headings, statistics date filters wrap and chart labels/height adapt
to enlarged text. Review drafts and login fields remain intact during switches.

This release derives from the exact accepted 1.1.9 source. The unqualified
asynchronous-search experiment is retained separately in the startup-performance
workspace and is not included here. Startup latency is still an open issue.

## Validation

- 84 host tests passed; analysis found no issues.
- Catalog audit found no missing static UI translation keys.
- English layout coverage includes 14 pages at 320 px and 1100 px with 1.5× text,
  plus actual bidirectional Profile and sign-in setting interactions.
- The Android journey passed on real SQLite: sign-in language selection,
  Profile setting clicks in both directions, concurrent theme/language writes,
  reopening, review drafts, submission and original multilingual notes. Five
  screenshots were captured. Tests used a separate database and retained the
  installed application with `--keep-app-running`.
- Release package metadata and installed-byte checks are retained with the
  local package evidence.
