/**
 * Verifies two things against the Firebase emulators that a Flutter unit test
 * cannot: the derived-address sign-in scheme (against the real Auth emulator)
 * and `firestore.rules` (against the real Firestore emulator, with a real user
 * ID token so the rules are actually evaluated).
 *
 * No npm dependencies — Node 22 has fetch built in.
 *
 *   node _verify_phone_auth.mjs
 *
 * Exit code 0 only when every assertion passes.
 *
 * ---------------------------------------------------------------------------
 * Three emulator behaviours this harness has to work around. All three were
 * found the hard way — see the notes on each.
 *
 * 1. "Signed out" is the ABSENCE of an Authorization header.
 *    A syntactically invalid bearer (`Bearer no-token-at-all`) is rejected by
 *    the emulator's transport layer with HTTP 400 `invalid jwt` — it never
 *    reaches the rules engine, so it is NOT a test of `signedIn()`. Only a
 *    header-less request produces the 403 that comes from a rule evaluating to
 *    false.
 *
 * 2. `Bearer owner` is an admin bypass.
 *    The emulator treats that exact token as "skip rules entirely". It is used
 *    below only to plant fixtures. Any other value is parsed as a JWT.
 *
 * 3. A bearer is trusted once it decodes, signature notwithstanding.
 *    `eyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0.` (alg: none) is accepted as an
 *    authenticated caller. That is why real ID tokens from the Auth emulator
 *    work here, and why the harness must never use a hand-made JWT to stand in
 *    for a user.
 * ---------------------------------------------------------------------------
 */

const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const FS =
  'http://127.0.0.1:8080/v1/projects/imo-live-inc/databases/(default)/documents';
const KEY = 'fake-api-key';
const DOMAIN = 'phone.imolive.app';

// Mirrors AppConstants.phoneAuthEmailFor.
const authEmailFor = (digits) => `p${digits}@${DOMAIN}`;

// Unique per run so the harness can be re-run without tripping EMAIL_EXISTS
// (the emulator keeps state for the lifetime of the process).
const RUN = String(Date.now()).slice(-9);
const DIGITS = `8801${RUN}`;
const OTHER_DIGITS = `8802${RUN}`;

let passed = 0;
let failed = 0;
const failures = [];

function check(name, ok, detail) {
  if (ok) {
    passed++;
    console.log(`  PASS  ${name}`);
  } else {
    failed++;
    failures.push(name);
    console.log(`  FAIL  ${name}${detail ? `  -- ${detail}` : ''}`);
  }
}

function note(text) {
  console.log(`  NOTE  ${text}`);
}

function section(title) {
  console.log(`\n=== ${title} ===`);
}

// ----------------------------------------------------------------- auth api

async function authCall(method, body) {
  const response = await fetch(`${AUTH}/${method}?key=${KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const json = await response.json().catch(() => ({}));
  return { status: response.status, json };
}

const signUp = (email, password) =>
  authCall('accounts:signUp', { email, password, returnSecureToken: true });

const signIn = (email, password) =>
  authCall('accounts:signInWithPassword', {
    email,
    password,
    returnSecureToken: true,
  });

const authError = (r) => r.json.error?.message ?? `http${r.status}`;

// ------------------------------------------------------------ firestore api

const S = (v) => ({ stringValue: v });
const I = (v) => ({ integerValue: String(v) });
const A = (arr) => ({ arrayValue: { values: arr.map((x) => S(x)) } });

/** Runs an arbitrary structured query, so query SHAPES can be checked too. */
async function fsRunQuery(structuredQuery, token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token !== undefined) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(`${FS}:runQuery`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ structuredQuery }),
  });
  const text = await response.text();
  return {
    status: response.status,
    body: text.replace(/\s+/g, ' ').slice(0, 130),
    hits: (text.match(/"name":\s*"/g) ?? []).length,
  };
}

/**
 * `token === undefined` omits the Authorization header entirely, which is the
 * only faithful way to make an unauthenticated call (see note 1 in the header).
 */
async function fsRequest(path, { method = 'GET', token, fields } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token !== undefined) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(`${FS}/${path}`, {
    method,
    headers,
    body: fields ? JSON.stringify({ fields }) : undefined,
  });
  const text = await response.text();
  return { status: response.status, body: text.replace(/\s+/g, ' ').slice(0, 130) };
}

const fsWrite = (path, fields, token) =>
  fsRequest(path, { method: 'PATCH', fields, token });
const fsRead = (path, token) => fsRequest(path, { token });

/**
 * A collection-group query — the case a path-scoped rule may not be provable
 * for, because the query spans parents the rule cannot pin down.
 *
 * `allDescendants: true` is what makes `from` a collection group rather than a
 * plain collection.
 */
async function fsCollectionGroup(collectionId, filterField, filterValue, token) {
  return fsRunQuery(
    {
      from: [{ collectionId, allDescendants: true }],
      where: {
        fieldFilter: {
          field: { fieldPath: filterField },
          op: 'EQUAL',
          value: { stringValue: filterValue },
        },
      },
      limit: 20,
    },
    token,
  );
}

const allowed = (r) => r.status >= 200 && r.status < 300;
const denied = (r) => r.status === 403;
const at = (r) => `status=${r.status} ${r.body}`;

async function main() {
  // ---------------------------------------------------------------- auth
  section('derived-address sign-in (Auth emulator)');

  const PIN = '482913';
  const email = authEmailFor(DIGITS);

  console.log(`  number          +${DIGITS}`);
  console.log(`  derived address ${email}`);

  const created = await signUp(email, PIN);
  check(
    'signup with the derived address succeeds',
    allowed(created),
    `status=${created.status} ${authError(created)}`,
  );
  const uid = created.json.localId;
  check('signup returns a uid', typeof uid === 'string' && uid.length > 0, uid);

  const loggedIn = await signIn(email, PIN);
  check(
    'sign-in with the same number + PIN succeeds',
    allowed(loggedIn),
    `status=${loggedIn.status} ${authError(loggedIn)}`,
  );
  check(
    'sign-in resolves to the same account',
    loggedIn.json.localId === uid,
    `${loggedIn.json.localId} vs ${uid}`,
  );

  // Uniqueness is what makes a separate `phone_index` collection unnecessary:
  // the derived address IS the index, and the auth backend enforces it.
  const duplicate = await signUp(email, '999999');
  check(
    'signing up the same number again is refused with EMAIL_EXISTS',
    duplicate.status === 400 && authError(duplicate) === 'EMAIL_EXISTS',
    `status=${duplicate.status} msg=${authError(duplicate)}`,
  );

  const wrongPin = await signIn(email, '000000');
  check('the wrong PIN is refused', wrongPin.status === 400, at(wrongPin));

  const unknown = await signIn(authEmailFor(OTHER_DIGITS), PIN);
  check('an unregistered number is refused', unknown.status === 400, at(unknown));

  // The anti-enumeration claim: a wrong PIN and an unknown number must be
  // indistinguishable, or the error alone tells an attacker which numbers have
  // accounts.
  //
  // ⚠️ The raw Auth emulator does NOT implement enumeration protection: it
  // returns INVALID_PASSWORD vs EMAIL_NOT_FOUND. Production Firebase Auth does
  // (and the app collapses both anyway, in `_translatePhoneSignIn`). So this
  // asserts the weaker, provable thing — that both are refusals the app maps to
  // one message — and reports the raw codes rather than pretending they match.
  const rawCodes = [authError(wrongPin), authError(unknown)];
  const collapsedByApp = ['INVALID_PASSWORD', 'EMAIL_NOT_FOUND', 'USER_NOT_FOUND',
    'INVALID_LOGIN_CREDENTIALS', 'INVALID_EMAIL'];
  check(
    'both refusals are codes the app collapses into one message',
    rawCodes.every((c) => collapsedByApp.includes(c)),
    rawCodes.join(' / '),
  );
  if (rawCodes[0] !== rawCodes[1]) {
    note(`emulator distinguishes them (${rawCodes.join(' vs ')}) — production Auth`);
    note('does not, and _translatePhoneSignIn collapses them regardless');
  }

  const token = loggedIn.json.idToken;
  check('the sign-in returned an ID token', typeof token === 'string' && token.length > 0);

  // A second account, so cross-user writes can be tested.
  const second = await signUp(authEmailFor(OTHER_DIGITS), PIN);
  check(
    'a second number can register independently',
    allowed(second),
    `status=${second.status} ${authError(second)}`,
  );
  const uidB = second.json.localId;
  const tokenB = second.json.idToken;

  // -------------------------------------------------------------- fixtures
  section('fixtures (planted with the emulator\'s admin token)');
  const ADMIN = 'owner';
  const HANDLE = `tanvir.ahmed${RUN.slice(-3)}`;
  for (const [path, fields] of [
    [
      `users/${uid}`,
      {
        name: S('Tanvir Ahmed'),
        username: S(HANDLE),
        // The two fields the phone flow added to make search work.
        phoneLower: S(DIGITS),
        searchKeywords: A(['tanvir', 'tanvir ahmed', 'ahmed', DIGITS]),
      },
    ],
    [`users/${uidB}`, { name: S('Other Person'), username: S('other.123') }],
    [`usernames/${HANDLE}`, { uid: S(uid) }],
    ['chats/chat1', { lastMessage: S('hi') }],
    [`users/${uid}/list/contact1`, { name: S('Someone') }],
    // Two reactions at different depths, for the collection-group query below.
    [`channels/c1/posts/p1/reactions/${uid}`, { uid: S(uid), kind: S('like') }],
    [`channels/c1/reactions/${uid}`, { uid: S(uid), kind: S('like') }],
  ]) {
    const r = await fsWrite(path, fields, ADMIN);
    check(`fixture ${path}`, allowed(r), at(r));
  }

  // ------------------------------------------------------------ rules: users
  section('firestore.rules — users/{uid}');

  check(
    'signed-out read of a profile is DENIED',
    denied(await fsRead(`users/${uid}`)),
    at(await fsRead(`users/${uid}`)),
  );

  check(
    'signed-in read of another profile is ALLOWED',
    allowed(await fsRead(`users/${uidB}`, token)),
    at(await fsRead(`users/${uidB}`, token)),
  );

  check(
    'signed-in write to your own profile is ALLOWED',
    allowed(await fsWrite(`users/${uid}`, { bio: S('hello') }, token)),
    at(await fsWrite(`users/${uid}`, { bio: S('hello') }, token)),
  );

  check(
    'signed-in write to ANOTHER profile is DENIED',
    denied(await fsWrite(`users/${uidB}`, { bio: S('hacked') }, token)),
    at(await fsWrite(`users/${uidB}`, { bio: S('hacked') }, token)),
  );

  check(
    'a signed-out write is DENIED',
    denied(await fsWrite(`users/${uid}`, { bio: S('anon') })),
    at(await fsWrite(`users/${uid}`, { bio: S('anon') })),
  );

  // `noPasswordMaterial()` — the guard rail that keeps the rejected design from
  // creeping back in. Each field is checked separately so a typo in the list is
  // caught rather than masked.
  for (const field of ['passwordHash', 'salt', 'pin', 'pinHash', 'password']) {
    check(
      `a profile write carrying \`${field}\` is DENIED`,
      denied(await fsWrite(`users/${uid}`, { [field]: S('deadbeef') }, token)),
      at(await fsWrite(`users/${uid}`, { [field]: S('deadbeef') }, token)),
    );
  }

  // The control: the same shape of write WITHOUT password material must pass,
  // otherwise the assertions above would pass for the wrong reason.
  check(
    'the same write without password material is ALLOWED (control)',
    allowed(await fsWrite(`users/${uid}`, { bio: S('fine') }, token)),
    at(await fsWrite(`users/${uid}`, { bio: S('fine') }, token)),
  );

  section('firestore.rules — the profile subcollection stays open (gifting)');
  check(
    'signed-in write into another user\'s subcollection is ALLOWED',
    allowed(
      await fsWrite(`users/${uidB}/points_transactions/tx1`, { amount: I(10) }, token),
    ),
    at(await fsWrite(`users/${uidB}/points_transactions/tx1`, { amount: I(10) }, token)),
  );

  // ---------------------------------------------------- rules: user_secrets
  section('firestore.rules — user_secrets/{uid}');
  check(
    'signed-in READ of your own secrets is DENIED',
    denied(await fsRead(`user_secrets/${uid}`, token)),
    at(await fsRead(`user_secrets/${uid}`, token)),
  );
  check(
    'signed-in WRITE of your own secrets is DENIED',
    denied(await fsWrite(`user_secrets/${uid}`, { totp: S('x') }, token)),
    at(await fsWrite(`user_secrets/${uid}`, { totp: S('x') }, token)),
  );

  // ---------------------------------------------------------- rules: indexes
  section('firestore.rules — directory indexes');

  check(
    'signed-in read of usernames/{handle} is ALLOWED',
    allowed(await fsRead(`usernames/${HANDLE}`, token)),
    at(await fsRead(`usernames/${HANDLE}`, token)),
  );

  check(
    'claiming a handle for yourself is ALLOWED',
    allowed(await fsWrite(`usernames/${HANDLE}`, { uid: S(uid) }, token)),
    at(await fsWrite(`usernames/${HANDLE}`, { uid: S(uid) }, token)),
  );

  check(
    'claiming a handle for SOMEONE ELSE is DENIED',
    denied(await fsWrite(`usernames/stolen${RUN}`, { uid: S(uidB) }, token)),
    at(await fsWrite(`usernames/stolen${RUN}`, { uid: S(uidB) }, token)),
  );

  check(
    'claiming a phone number for yourself is ALLOWED',
    allowed(
      await fsWrite(`phones/${DIGITS}`, { uid: S(uid), phone: S(DIGITS) }, token),
    ),
    at(await fsWrite(`phones/${DIGITS}`, { uid: S(uid), phone: S(DIGITS) }, token)),
  );

  check(
    'claiming a phone number for SOMEONE ELSE is DENIED',
    denied(await fsWrite(`phones/8801111${RUN}`, { uid: S(uidB) }, token)),
    at(await fsWrite(`phones/8801111${RUN}`, { uid: S(uidB) }, token)),
  );

  check(
    'claiming an email for yourself is ALLOWED',
    allowed(await fsWrite(`emails/me${RUN}@example.com`, { uid: S(uid) }, token)),
    at(await fsWrite(`emails/me${RUN}@example.com`, { uid: S(uid) }, token)),
  );

  check(
    'claiming an email for SOMEONE ELSE is DENIED',
    denied(await fsWrite(`emails/you${RUN}@example.com`, { uid: S(uidB) }, token)),
    at(await fsWrite(`emails/you${RUN}@example.com`, { uid: S(uidB) }, token)),
  );

  // ------------------------------------------------------------ rules: misc
  section('firestore.rules — app data and the fail-closed default');

  check(
    'signed-in read of chats/{id} is ALLOWED (pinned permissive)',
    allowed(await fsRead('chats/chat1', token)),
    at(await fsRead('chats/chat1', token)),
  );

  check(
    'signed-in write of chats/{id} is ALLOWED (pinned permissive)',
    allowed(await fsWrite('chats/chat1', { lastMessage: S('yo') }, token)),
    at(await fsWrite('chats/chat1', { lastMessage: S('yo') }, token)),
  );

  check(
    'signed-OUT read of chats/{id} is DENIED',
    denied(await fsRead('chats/chat1')),
    at(await fsRead('chats/chat1')),
  );

  // The whole point of enumerating collections: a collection that is not listed
  // must DENY, not fall through to an open catch-all. (A permissive
  // `{document=**}` would make these 200, or 404-but-readable.)
  check(
    'an UNLISTED collection is DENIED (fail closed)',
    denied(await fsRead(`not_a_real_collection/x${RUN}`, token)),
    at(await fsRead(`not_a_real_collection/x${RUN}`, token)),
  );

  check(
    'an unlisted collection is DENIED for writes too',
    denied(await fsWrite(`not_a_real_collection/x${RUN}`, { a: S('b') }, token)),
    at(await fsWrite(`not_a_real_collection/x${RUN}`, { a: S('b') }, token)),
  );

  // ------------------------------------------------- collection group queries
  //
  // `ChannelService.watchMyReactions` runs `collectionGroup('reactions')`
  // filtered by `uid`. A collection-group query spans parents, so a rule scoped
  // to one parent path (`channels/{id}/{sub}/{doc=**}`) may not be provable for
  // it — and if it is not, the query is rejected wholesale and the reaction
  // state in the channel feed silently stops loading.
  //
  // This is not a theoretical concern: it is the exact failure mode the rules
  // skill calls out. Either it passes here or the ruleset needs a root wildcard
  // for `reactions`.
  section('firestore.rules — collection group queries');

  const reactions = await fsCollectionGroup('reactions', 'uid', uid, token);
  check(
    'a signed-in collectionGroup("reactions") query is ALLOWED',
    allowed(reactions),
    at(reactions),
  );
  if (allowed(reactions)) {
    note(`returned ${reactions.hits} document(s) across parents`);
  }

  check(
    'a signed-OUT collectionGroup("reactions") query is DENIED',
    denied(await fsCollectionGroup('reactions', 'uid', uid)),
    at(await fsCollectionGroup('reactions', 'uid', uid)),
  );

  // The root wildcard is read-only on purpose. Reaction *writes* still have to
  // go through the `channels` block, so that path must keep working.
  check(
    'a reaction can still be WRITTEN under its channel (control)',
    allowed(
      await fsWrite(`channels/c1/posts/p1/reactions/${uidB}`, { uid: S(uidB) }, token),
    ),
    at(await fsWrite(`channels/c1/posts/p1/reactions/${uidB}`, { uid: S(uidB) }, token)),
  );

  // -------------------------------------------------- directory search shapes
  //
  // The phone flow added two new query shapes to the directory:
  // `arrayContains('searchKeywords', …)` and a range scan on `phoneLower`.
  // A rule can be perfectly correct for a single-document get and still reject
  // a *query*, so each shape the app actually issues is exercised here — this is
  // the "will deploying break search?" question.
  section('firestore.rules — the directory query shapes');

  const keywordQuery = await fsRunQuery(
    {
      from: [{ collectionId: 'users' }],
      where: {
        fieldFilter: {
          field: { fieldPath: 'searchKeywords' },
          op: 'ARRAY_CONTAINS',
          value: { stringValue: 'tanvir' },
        },
      },
      limit: 20,
    },
    token,
  );
  check(
    'arrayContains("searchKeywords") is ALLOWED',
    allowed(keywordQuery),
    at(keywordQuery),
  );

  const prefixQuery = await fsRunQuery(
    {
      from: [{ collectionId: 'users' }],
      where: {
        compositeFilter: {
          op: 'AND',
          filters: [
            {
              fieldFilter: {
                field: { fieldPath: 'phoneLower' },
                op: 'GREATER_THAN_OR_EQUAL',
                value: { stringValue: DIGITS.slice(0, 4) },
              },
            },
            {
              fieldFilter: {
                field: { fieldPath: 'phoneLower' },
                op: 'LESS_THAN',
                value: { stringValue: `${DIGITS.slice(0, 4)}\uf8ff` },
              },
            },
          ],
        },
      },
      orderBy: [{ field: { fieldPath: 'phoneLower' } }],
      limit: 20,
    },
    token,
  );
  check(
    'the phoneLower prefix range scan is ALLOWED',
    allowed(prefixQuery),
    at(prefixQuery),
  );

  const signedOutSearch = await fsRunQuery(
    {
      from: [{ collectionId: 'users' }],
      where: {
        fieldFilter: {
          field: { fieldPath: 'searchKeywords' },
          op: 'ARRAY_CONTAINS',
          value: { stringValue: 'tanvir' },
        },
      },
      limit: 20,
    },
    undefined,
  );
  check(
    'a signed-OUT directory search is DENIED',
    denied(signedOutSearch),
    at(signedOutSearch),
  );

  // ------------------------------------------------------------- summary
  console.log(`\n${'='.repeat(64)}`);
  console.log(`passed ${passed}   failed ${failed}`);
  if (failed > 0) {
    console.log('\nfailures:');
    for (const name of failures) console.log(`  - ${name}`);
  }
  console.log('='.repeat(64));
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error('harness error:', error);
  process.exit(2);
});
