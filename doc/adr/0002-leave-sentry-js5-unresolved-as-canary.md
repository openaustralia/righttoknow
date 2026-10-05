# Leave Sentry RIGHT-TO-KNOW-JS-5 unresolved as our canary

Sentry RIGHT-TO-KNOW-JS-5 is upstream Alaveteli's `request-attachments.js`
throwing when the `application.js` bundle fails to execute. With no theme
JavaScript left (see
[ADR-0001](0001-personal-info-gate-fails-open.md)), it is now the only signal
we have that the bundle sometimes doesn't execute — so it is left unresolved
on purpose.

If upstream ever guards that file silently, or someone is tempted to resolve
JS-5, replace the signal before you do.

_Decided 2026-08-24; originally recorded in `docs/DECISIONS.md`._
