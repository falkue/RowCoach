// Tests der Firestore-Regeln (firebase/firestore.rules) mit dem Firestore-Emulator.
// Ausführen (Java ≥ 21 nötig, siehe docs/SYNC.md „Regeln testen“):
//   cd firebase/tests && npm install && npm run emulator-test
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp, Bytes, deleteField,
} from 'firebase/firestore';

const RULES = readFileSync(fileURLToPath(new URL('../firestore.rules', import.meta.url)), 'utf8');
const RIDE = '0B7C6A3E-1F2D-4C5B-9A8E-7D6C5B4A3F21';
const clock = (ms, node = 'dev1') => `${String(ms).padStart(16, '0')}-00000-${node}`;

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rowcoach',
    firestore: { rules: RULES, host: '127.0.0.1', port: 8085 },
  });
});

after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

// Konten: bestätigte E-Mail, unbestätigte E-Mail, Google, fremdes Konto
const verified = () => env.authenticatedContext('alice', {
  email: 'alice@example.org', email_verified: true, firebase: { sign_in_provider: 'password' },
}).firestore();
const unverified = () => env.authenticatedContext('alice', {
  email: 'alice@example.org', email_verified: false, firebase: { sign_in_provider: 'password' },
}).firestore();
const google = () => env.authenticatedContext('alice', {
  email: 'alice@gmail.com', email_verified: false, firebase: { sign_in_provider: 'google.com' },
}).firestore();
const mallory = () => env.authenticatedContext('mallory', {
  email: 'm@example.org', email_verified: true, firebase: { sign_in_provider: 'password' },
}).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();

function ride(extra = {}) {
  return {
    v: 1, id: RIDE, start: Timestamp.fromMillis(1_800_000_000_000), distance: 6000, activeDuration: 1500,
    record: '{"formatVersion":1}', samples: Bytes.fromUint8Array(new Uint8Array([0x52, 0x53, 1, 0, 0])),
    codec: 1, chunkCount: 0, deleted: false, effort: '{"estimate":6}', effortClock: clock(1_800_000_000_000),
    updatedAt: serverTimestamp(), ...extra,
  };
}

const ridePath = (db, uid = 'alice', id = RIDE) => doc(db, 'users', uid, 'rides', id);

test('Fahrt anlegen: nur eigenes Konto, bestätigt, gültige Form', async () => {
  await assertSucceeds(setDoc(ridePath(verified()), ride()));
  await env.clearFirestore();
  await assertSucceeds(setDoc(ridePath(google()), ride()));
  await env.clearFirestore();
  await assertFails(setDoc(ridePath(unverified()), ride()));
  await assertFails(setDoc(ridePath(anonymous()), ride()));
  await assertFails(setDoc(ridePath(mallory(), 'alice'), ride()));
  // falsche Form
  await assertFails(setDoc(ridePath(verified()), ride({ id: 'anders' })));
  await assertFails(setDoc(ridePath(verified()), ride({ extra: 1 })));
  await assertFails(setDoc(ridePath(verified()), ride({ updatedAt: Timestamp.now() })));
  await assertFails(setDoc(ridePath(verified()), ride({ effortClock: 'gestern' })));
  await assertFails(setDoc(ridePath(verified()), ride({ deleted: true })));
  await assertFails(setDoc(ridePath(verified()), ride({ record: 'x'.repeat(200_001) })));
  await assertFails(setDoc(ridePath(verified(), 'alice', 'kein-uuid'), ride({ id: 'kein-uuid' })));
});

test('Fahrten lesen: nur das eigene Konto', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(ridePath(ctx.firestore()), { ...ride(), updatedAt: Timestamp.now() });
  });
  await assertSucceeds(getDoc(ridePath(verified())));
  await assertSucceeds(getDoc(ridePath(unverified()))); // lesen auch unbestätigt (z. B. Export)
  await assertFails(getDoc(ridePath(mallory(), 'alice')));
  await assertFails(getDoc(ridePath(anonymous())));
});

test('Fahrt ist unveränderlich bis auf neuere Belastung und Tombstone', async () => {
  const db = verified();
  await assertSucceeds(setDoc(ridePath(db), ride()));
  await assertFails(updateDoc(ridePath(db), { distance: 9999, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ridePath(db), { record: '{}', updatedAt: serverTimestamp() }));
  // Belastung nur mit neuerem Zeitstempel
  await assertSucceeds(updateDoc(ridePath(db), {
    effort: '{"userScore":8}', effortClock: clock(1_800_000_100_000), updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(ridePath(db), {
    effort: '{"userScore":3}', effortClock: clock(1_800_000_050_000), updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(ridePath(db), {
    effort: deleteField(), effortClock: clock(1_800_000_200_000), updatedAt: serverTimestamp(),
  }));
  // Tombstone ersetzt die Fahrt; danach keine Änderungen mehr
  const tomb = { v: 1, id: RIDE, deleted: true, deletedClock: clock(1_800_000_300_000), updatedAt: serverTimestamp() };
  await assertFails(setDoc(ridePath(db), { ...tomb, record: '{}' }));
  await assertSucceeds(setDoc(ridePath(db), tomb));
  await assertFails(setDoc(ridePath(db), ride()));
  await assertFails(updateDoc(ridePath(db), {
    effort: '{}', effortClock: clock(1_900_000_000_000), updatedAt: serverTimestamp(),
  }));
});

test('Zusatzstücke nur zusammen mit der Fahrt und innerhalb von chunkCount', async () => {
  const db = verified();
  const chunk = (i) => doc(db, 'users', 'alice', 'rides', RIDE, 'chunks', String(i));
  const data = Bytes.fromUint8Array(new Uint8Array(1000));
  const { samples, ...rest } = ride({ chunkCount: 2 });
  const b = writeBatch(db);
  b.set(ridePath(db), rest);
  b.set(chunk(0), { i: 0, data });
  b.set(chunk(1), { i: 1, data });
  await assertSucceeds(b.commit());
  await assertFails(setDoc(chunk(2), { i: 2, data }));
  await assertFails(setDoc(chunk(0), { i: 0, data }));            // keine Änderung
  await assertFails(setDoc(ridePath(db, 'alice', '1B7C6A3E-1F2D-4C5B-9A8E-7D6C5B4A3F21'),
    { ...rest, id: '1B7C6A3E-1F2D-4C5B-9A8E-7D6C5B4A3F21', chunkCount: 0 })); // ohne Zeitreihe und ohne Stücke
});

test('Einstellungen: Feldliste, Form, kein älterer Stand', async () => {
  const db = verified();
  const ref = doc(db, 'users', 'alice', 'settings', 'profile');
  const settings = (fields) => ({ v: 1, fields, updatedAt: serverTimestamp() });
  await assertSucceeds(setDoc(ref, settings({ maxHR: { v: '185', c: clock(10) }, rower: { v: '{"displayName":"F"}', c: clock(10) } })));
  await assertSucceeds(setDoc(ref, settings({ maxHR: { v: '190', c: clock(20) }, rower: { v: '{"displayName":"F"}', c: clock(10) } })));
  await assertFails(setDoc(ref, settings({ maxHR: { v: '170', c: clock(15) }, rower: { v: '{}', c: clock(10) } })));
  await assertSucceeds(setDoc(ref, settings({ maxHR: { v: null, c: clock(30) }, rower: { v: '{}', c: clock(31) } })));
  await assertFails(setDoc(ref, settings({ gender: { v: '"x"', c: clock(40) } })));           // nicht im Katalog
  await assertFails(setDoc(ref, settings({ maxHR: { v: 185, c: clock(40) } })));              // Wert muss Text sein
  await assertFails(setDoc(ref, settings({ maxHR: { v: 'x'.repeat(16_001), c: clock(40) } })));
  await assertFails(setDoc(doc(db, 'users', 'alice', 'settings', 'device'), settings({})));
  await assertFails(setDoc(doc(mallory(), 'users', 'alice', 'settings', 'program'), settings({})));
  await assertSucceeds(setDoc(doc(db, 'users', 'alice', 'settings', 'program'),
    settings({ active: { v: '{"programId":"p"}', c: clock(50) } })));
});

test('Einwilligung: nur die Person selbst, mit Serverzeit und Textversion', async () => {
  const db = verified();
  const consent = (extra = {}) => ({
    v: 1, kind: 'research', granted: true, textVersion: 'research-2026-11', locale: 'de',
    decidedAt: Timestamp.now(), at: serverTimestamp(), ...extra,
  });
  await assertSucceeds(setDoc(doc(db, 'users', 'alice', 'consent', 'research'), consent()));
  await assertSucceeds(setDoc(doc(db, 'users', 'alice', 'consent', 'research'), consent({ granted: false })));
  await assertFails(setDoc(doc(db, 'users', 'alice', 'consent', 'research'), consent({ at: Timestamp.now() })));
  await assertFails(setDoc(doc(db, 'users', 'alice', 'consent', 'marketing'), consent({ kind: 'marketing' })));
  await assertFails(setDoc(doc(db, 'users', 'alice', 'consent', 'research'), consent({ textVersion: '' })));
  await assertFails(setDoc(doc(mallory(), 'users', 'alice', 'consent', 'research'), consent()));
  const log = doc(db, 'users', 'alice', 'consentLog', 'e1');
  await assertSucceeds(setDoc(log, consent({ kind: 'sync' })));
  await assertFails(setDoc(log, consent({ kind: 'sync', granted: false })));                  // nur anhängen
  await assertSucceeds(deleteDoc(log));                                                         // „alles löschen“
});

test('Berechtigungen schreibt nur der Server', async () => {
  const db = verified();
  const ref = doc(db, 'users', 'alice', 'entitlements', 'races');
  await assertFails(setDoc(ref, { active: true }));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', 'alice', 'entitlements', 'races'), { active: true });
  });
  await assertSucceeds(getDoc(ref));
  await assertFails(getDoc(doc(mallory(), 'users', 'alice', 'entitlements', 'races')));
  await assertFails(deleteDoc(ref));
});

test('Löschen der eigenen Daten erlaubt, fremde nicht; alles andere gesperrt', async () => {
  const db = verified();
  await assertSucceeds(setDoc(ridePath(db), ride()));
  await assertFails(deleteDoc(ridePath(mallory(), 'alice')));
  await assertSucceeds(deleteDoc(ridePath(unverified())));
  await assertFails(setDoc(doc(db, 'users', 'alice'), { name: 'x' }));
  await assertFails(setDoc(doc(db, 'tournaments', 't1'), { title: 'x' }));
  await assertFails(getDoc(doc(db, 'tournaments', 't1')));
});
