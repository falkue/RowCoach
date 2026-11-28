// Tests der Firestore-Regeln für Online-Rennen (races, participants, results, raceCodes, virtualHistory).
// Ausführen (Java ≥ 21 nötig, siehe docs/MULTIPLAYER.md „Umsetzung Firebase“ → Regeln testen):
//   cd firebase/tests && npm install && npm run emulator-test
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, getDocs, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp, collection, query,
  where,
} from 'firebase/firestore';

const RULES = readFileSync(fileURLToPath(new URL('../firestore.rules', import.meta.url)), 'utf8');
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rowcoach',
    firestore: { rules: RULES, host: '127.0.0.1', port: 8085 },
  });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const user = (uid, verified = true) => env.authenticatedContext(uid, {
  email: `${uid}@example.org`, email_verified: verified, firebase: { sign_in_provider: 'password' },
}).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();

const inMinutes = (m) => Timestamp.fromMillis(Date.now() + m * 60_000);

// Form wie OnlineRace.document im Kit
function race(extra = {}) {
  return {
    title: 'Rhein · 2000 m', courseId: 'rhein-basel', courseVersion: 3,
    target: { kind: 'distance', value: 2000 }, startsAt: inMinutes(10), maxParticipants: 8,
    visibility: 'public', status: 'scheduled', createdBy: 'alice', seed: 4711, fill: 'none',
    createdAt: serverTimestamp(), ...extra,
  };
}

const entry = (extra = {}) => ({ displayName: 'Bob', source: 'human', appearance: '{"characterId":"a"}',
  joinedAt: serverTimestamp(), ...extra });

const result = (extra = {}) => ({ distance: 2000, time: 401.234, finished: true, provisional: true, source: 'human',
  at: serverTimestamp(), ...extra });

async function seedRace(data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'races', 'r1'), { ...race(), createdAt: Timestamp.now(), ...data });
  });
}

test('Rennen anlegen: bestätigt, eigene uid, gültige Form, Start 2 min … 30 Tage', async () => {
  await assertSucceeds(setDoc(doc(user('alice'), 'races', 'r1'), race()));
  await assertFails(setDoc(doc(user('alice', false), 'races', 'r2'), race()));
  await assertFails(setDoc(doc(anonymous(), 'races', 'r3'), race()));
  await assertFails(setDoc(doc(user('bob'), 'races', 'r4'), race()), 'createdBy fremd');
  await assertFails(setDoc(doc(user('alice'), 'races', 'r5'), race({ startsAt: inMinutes(1) })));
  await assertFails(setDoc(doc(user('alice'), 'races', 'r6'), race({ startsAt: inMinutes(60 * 24 * 31) })));
  await assertFails(setDoc(doc(user('alice'), 'races', 'r7'), race({ maxParticipants: 31 })), 'Kleinfeld ≤ 30');
  await assertFails(setDoc(doc(user('alice'), 'races', 'r8'), race({ status: 'finished' })));
  await assertFails(setDoc(doc(user('alice'), 'races', 'r9'), race({ fill: 'server' })), 'Auffüllen durch Server nur Admin');
  await assertFails(setDoc(doc(user('alice'), 'races', 'r10'), race({ target: { kind: 'distance', value: 50 } })));
  await assertFails(setDoc(doc(user('alice'), 'races', 'r11'), race({ extra: true })));
  await assertSucceeds(setDoc(doc(user('alice'), 'races', 'r12'), race({ target: { kind: 'time', value: 1200 } })));
});

test('Rennen lesen: einzeln für Angemeldete, Liste nur öffentliche', async () => {
  await seedRace({});
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'races', 'p1'), { ...race({ visibility: 'private' }), createdAt: Timestamp.now() });
  });
  await assertSucceeds(getDoc(doc(user('bob'), 'races', 'p1')));
  await assertFails(getDoc(doc(anonymous(), 'races', 'r1')));
  await assertSucceeds(getDocs(query(collection(user('bob'), 'races'), where('visibility', '==', 'public'))));
  await assertFails(getDocs(collection(user('bob'), 'races')), 'Liste ohne Filter würde private zeigen');
});

test('Absagen nur durch die anlegende Person, nur Status', async () => {
  await seedRace({});
  await assertSucceeds(updateDoc(doc(user('alice'), 'races', 'r1'), { status: 'cancelled' }));
  await seedRace({});
  await assertFails(updateDoc(doc(user('bob'), 'races', 'r1'), { status: 'cancelled' }));
  await assertFails(updateDoc(doc(user('alice'), 'races', 'r1'), { status: 'finished' }));
  await assertFails(updateDoc(doc(user('alice'), 'races', 'r1'), { title: 'anders' }));
  await assertFails(deleteDoc(doc(user('alice'), 'races', 'r1')));
});

test('Anmelden: nur sich selbst, nur Mensch, bis zum Meldeschluss', async () => {
  await seedRace({});
  const bob = user('bob');
  await assertSucceeds(setDoc(doc(bob, 'races/r1/participants/bob'), entry()));
  await assertFails(setDoc(doc(bob, 'races/r1/participants/carol'), entry()), 'fremde uid');
  await assertFails(setDoc(doc(user('carol'), 'races/r1/participants/carol'), entry({ source: 'virtual' })));
  await assertFails(setDoc(doc(user('carol'), 'races/r1/participants/carol'), entry({ joinedAt: Timestamp.now() })));
  await assertFails(setDoc(doc(user('carol'), 'races/r1/participants/carol'), entry({ displayName: 'x'.repeat(25) })));
  await assertFails(setDoc(doc(user('carol'), 'races/r1/participants/carol'), entry({ appearance: 'x'.repeat(1501) })));
  // Name nachtragen ja, Anmeldezeit (Bahn) nie
  await assertSucceeds(updateDoc(doc(bob, 'races/r1/participants/bob'), { displayName: 'Robert' }));
  await assertFails(updateDoc(doc(bob, 'races/r1/participants/bob'), { joinedAt: Timestamp.now() }));
  await assertSucceeds(deleteDoc(doc(bob, 'races/r1/participants/bob')));
  // Meldeschluss: 60 s vor dem Start
  await seedRace({ startsAt: Timestamp.fromMillis(Date.now() + 30_000) });
  await assertFails(setDoc(doc(user('dave'), 'races/r1/participants/dave'), entry()));
  // abgesagt
  await seedRace({ status: 'cancelled' });
  await assertFails(setDoc(doc(user('erin'), 'races/r1/participants/erin'), entry()));
});

test('Ergebnisse: Client nur eigenes, nur vorläufig, nur nach dem Start; endgültig nur Server', async () => {
  await seedRace({ startsAt: Timestamp.fromMillis(Date.now() - 600_000) });
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'races/r1/participants/bob'), { ...entry(), joinedAt: Timestamp.now() });
  });
  const bob = user('bob');
  await assertSucceeds(setDoc(doc(bob, 'races/r1/results/bob'), result()));
  await assertSucceeds(setDoc(doc(bob, 'races/r1/results/bob'), result({ time: 400.5 })));
  await assertFails(setDoc(doc(bob, 'races/r1/results/bob'), result({ provisional: false })));
  await assertFails(setDoc(doc(bob, 'races/r1/results/bob'), { ...result(), place: 1 }));
  await assertFails(setDoc(doc(user('carol'), 'races/r1/results/carol'), result()), 'nicht angemeldet');
  await assertFails(setDoc(doc(bob, 'races/r1/results/carol'), result()), 'fremdes Ergebnis');
  // Server schreibt fest → Client kann nichts mehr ändern
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'races/r1/results/bob'), { ...result(), provisional: false, place: 1,
      at: Timestamp.now() });
  });
  await assertFails(setDoc(doc(bob, 'races/r1/results/bob'), result({ time: 300 })));
  await assertSucceeds(getDoc(doc(user('carol'), 'races/r1/results/bob')));
  // vor dem Start kein Ergebnis
  await seedRace({});
  await assertFails(setDoc(doc(bob, 'races/r1/results/bob'), result()));
});

test('Einladungscode: nur zum eigenen Rennen, einzeln lesbar, nicht auflistbar', async () => {
  const alice = user('alice');
  const batch = writeBatch(alice);
  batch.set(doc(alice, 'races', 'p1'), race({ visibility: 'private' }));
  batch.set(doc(alice, 'raceCodes', 'ABCDEFGH'), { raceId: 'p1' });
  await assertSucceeds(batch.commit());
  await assertSucceeds(getDoc(doc(user('bob'), 'raceCodes', 'ABCDEFGH')));
  await assertFails(getDocs(collection(user('bob'), 'raceCodes')));
  await assertFails(setDoc(doc(user('bob'), 'raceCodes', 'HGFEDCBA'), { raceId: 'p1' }), 'fremdes Rennen');
  await assertFails(setDoc(doc(alice, 'raceCodes', 'ABCDEFG0'), { raceId: 'p1' }), '0 nicht im Alphabet');
  await assertFails(updateDoc(doc(alice, 'raceCodes', 'ABCDEFGH'), { raceId: 'x' }));
});

test('Rotation der virtuellen: kein Client-Zugriff', async () => {
  await assertFails(getDoc(doc(user('alice'), 'virtualHistory', 'v1-0001')));
  await assertFails(setDoc(doc(user('alice'), 'virtualHistory', 'v1-0001'), { lastRaced: 1 }));
});
