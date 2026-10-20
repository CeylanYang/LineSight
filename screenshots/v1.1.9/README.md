# LineSight 1.1.9 screenshots

Captured on the API 36.1 x64 Android emulator, using marked example records.
The five review images come from the versioned debug integration binary;
the onboarding image comes from the normal-entrypoint release APK.

| Capture | Visible behavior |
|---|---|
| [Validation](review-validation.png) | Too-short trimmed note shows inline feedback; the counter includes raw spaces. |
| [Draft](review-draft.png) | Unsaved text/verdict, explicit revert and blocked archive. |
| [Leaving](review-leave-dialog.png) | Cancel or discard the in-memory draft. |
| [Conflict](review-conflict.png) | Draft retained, newer evidence notice, explicit reload/review and disabled submit. |
| [Saved](review-saved.png) | Persisted text, disabled duplicate submission and two separate audit entries. |
| [Release onboarding](release-onboarding.png) | Complete first-administrator setup with the 1.1.9 version label. |

Review screenshots were visually inspected for readable Chinese text, reachable
actions and consistency with the test assertions. Pages are vertically scrolled
to the exercised controls; these are viewport captures, not full-page exports.
Narrow 320 px / 1.8× text and tablet layouts are covered by host widget tests.

Release launch waits and any timeout observations are recorded separately in
the release reports. A rendered onboarding capture does not convert an earlier
timed-out wait into a pass.
