# Firestore rules — traps and verification

Reference for `firestore.rules` in `tiger`. Index lives in `MEMORY.md`.

## Deployed state
- ✅ **2026-10-04 ruleset is DEPLOYED and live**, read-back verified byte-identical. 142 emulator
  assertions, both directions. Rollback:
  `git show bca08ea:firestore.rules > firestore.rules && firebase deploy --only firestore:rules`
  (`bca08ea` = last commit with the 2026-10-03 ruleset). A copy is at
  `_fstest/rules.rollback-2026-10-03.rules`.

## Verify what is serving — never trust "Deploy complete"
Rules live in the **Firebase Rules** API, not the Firestore Admin API:
`firebaserules.googleapis.com/v1/projects/{p}/releases/cloud.firestore` → `rulesetName` →
`.../v1/{rulesetName}` → `source.files[0].content`.
The Firestore Admin `.../databases/{d}/securityRules` path returns a **Google 404 HTML page** — wrong
service, and it looks like an auth failure. `_fstest/verify_deployed_rules.py` does the real read-back.

## Rule-authoring traps
- **Never put a mutable fact in the rules header** — the ruleset id changes on *every* deploy including
  comment-only ones, so a redeploy-timestamp list is stale the moment it is written.
- **`{document=**}` matches ZERO or more segments** → it also matches the **PARENT**.
  `match /users/{uid}/{document=**}` re-opened `/users/{uid}`, making `isSelf()` + `noPasswordMaterial()`
  dead code. Require a real segment: `match /{sub}/{doc=**}`. Only the emulator caught it.
- **`collectionGroup('reactions')` needs a root-anchored `match /{path=**}/reactions/{reactionId}`** — no
  path-scoped rule can satisfy it. `grep -rn "collectionGroup" lib/` before any rules deploy.
- **`hasOnly` accepts a no-op write** — an empty `affectedKeys()` satisfies it, so `changedOnly([...])`
  alone let anyone re-stamp `channels.lastUpdateAt`. Require a counter to actually move.
- **`exists()` in a rule sees the state BEFORE the batch** — a counter incremented in the same batch as
  the edge that authorises it cannot be guarded by `exists()`; the first follow would be denied. Split by
  direction. Residual, documented: anyone may step a counter **up** by one.
- **A disjunction DOES satisfy a list query** (verified 200). Do not write the opposite into a comment.
- **Gifting needs a cross-ownership exception.** `sendGift` credits `users/{recipient}` from the *sender*,
  so an `isSelf`-only update rule **denies every gift**. Branch:
  `changedOnly(['points','updatedAt'])` + an increase only. Points are client-mintable anyway, so the
  ledger is not trustworthy without a server — say so rather than implying the rule secures it.
- **`markChatRead` may use only ONE `!=` filter.** Firestore rejects `senderId != me` **and**
  `status != read` with `INVALID_ARGUMENT`; the old `catch` cleared the counter instead, so the only
  symptom was read receipts that never advanced. Now: `status != read`, sender filtered in Dart.
- **`handleError` returning normally *marks the error handled* and the stream closes.** `retrying<T>`
  (`call_signaling_service.dart`) re-opens ≤3×. Cast, never coerce, Firestore fields — a new date field on
  a Firestore-backed model must go in the conversion map or you get a **throw**, not a null.

## Emulator harness
`_fstest/rules_probe.mjs` (dir is gitignored), structural lint `_fstest/lint_rules.py`, deployed read-back
`_fstest/verify_deployed_rules.py`. Start the emulators with
`JAVA_HOME="C:/Program Files/Android/Android Studio/jbr"`; `firebase.json` wires auth 9099 / firestore 8080.
Method + traps in the skill `firestore-rules-from-callsites`.

- ⚠️ **A 400 is not a denial.** Harnesses must map 200→allow, 403→deny and fail otherwise — a
  "not 200 = denied" harness reports green over a rule that never ran (this hid the `markChatRead` bug).
- ⚠️ `:runQuery` `parent` is a **URL path segment** (`.../documents/chats/{id}:runQuery`). In `from` → 400;
  in the body → accepted and **never answered**, so the probe hangs silently.
- ⚠️ Write probe progress with `appendFileSync`, not stdout — buffered output is lost when the process is
  killed here, and the run then reports *nothing*.
- ⚠️ A green suite only proves the queries you thought of. Before deploying, walk **every** read site and
  ask *as which role* it runs — that is what finds a read the new rule denies.
