// Tests der Realtime-Database-Regeln (firebase/database.rules.json) für Online-Rennen mit dem Database-Emulator.
// Ausführen (Java ≥ 21 nötig): cd firebase/tests && npm install && npm run emulator-test
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { ref, set, get, remove, serverTimestamp, onDisconnect } from 'firebase/database';

const RULES = readFileSync(fileURLToPath(new URL('../database.rules.json', import.meta.url)), 'utf8');
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rowcoach',
    database: { rules: RULES, host: '127.0.0.1', port: 9000 },
  });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearDatabase(); });

const db = (uid) => env.authenticatedContext(uid).database();
const anonymous = () => env.unauthenticatedContext().database();
// 18-Byte-Binärframe als Base64 (24 Zeichen) bzw. Zielframe (22 Byte → 32 Zeichen)
const B24ok = 'AQAAAAAAAQAAA+gAAAJxBLAY';
const B32 = 'AQAAAAAAAQAAA+gAAAJxBLBYAAMNQA==';
const frame = (n, b = B24ok) => ({ b, n, at: serverTimestamp() });

async function seed({ startsInMs = 60_000, members = ['alice', 'bob'] } = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.database();
    await set(ref(d, 'meta/race1'), { startsAt: Date.now() + startsInMs, createdBy: 'alice' });
    for (const m of members) await set(ref(d, `members/race1/${m}`), true);
  });
}

test('meta: anlegen nur einmal, eigene uid, Start in der Zukunft', async () => {
  await assertSucceeds(set(ref(db('alice'), 'meta/raceA'), { startsAt: Date.now() + 600_000, createdBy: 'alice' }));
  await assertFails(set(ref(db('alice'), 'meta/raceA'), { startsAt: Date.now() + 900_000, createdBy: 'alice' }), 'unveränderlich');
  await assertFails(set(ref(db('bob'), 'meta/raceB'), { startsAt: Date.now() + 600_000, createdBy: 'alice' }));
  await assertFails(set(ref(db('alice'), 'meta/raceC'), { startsAt: Date.now() + 10_000, createdBy: 'alice' }));
  await assertFails(set(ref(db('alice'), 'meta/raceD'), { startsAt: Date.now() + 600_000, createdBy: 'alice', x: 1 }));
  await assertSucceeds(get(ref(db('bob'), 'meta/raceA')));
  await assertFails(get(ref(anonymous(), 'meta/raceA')));
});

test('members: nur sich selbst, nur bis 10 min nach dem Start', async () => {
  await seed({ members: [] });
  await assertSucceeds(set(ref(db('carol'), 'members/race1/carol'), true));
  await assertFails(set(ref(db('carol'), 'members/race1/dave'), true));
  await assertFails(set(ref(db('carol'), 'members/race1/carol'), 'ja'));
  await assertFails(set(ref(db('carol'), 'members/raceX/carol'), true), 'Rennen ohne meta');
  await env.clearDatabase();
  await seed({ startsInMs: -700_000, members: [] });
  await assertFails(set(ref(db('carol'), 'members/race1/carol'), true));
});

test('Frames: nur eigener, nur Mitglieder, Form, n wachsend, Serverzeit, Zeitfenster', async () => {
  await seed();
  const alice = db('alice');
  await assertSucceeds(set(ref(alice, 'live/race1/f/alice'), frame(1)));
  await assertSucceeds(set(ref(alice, 'live/race1/f/alice'), frame(2, B32)));
  await assertFails(set(ref(alice, 'live/race1/f/alice'), frame(2)), 'n muss wachsen');
  await assertFails(set(ref(alice, 'live/race1/f/bob'), frame(9)), 'fremder Frame');
  await assertFails(set(ref(db('mallory'), 'live/race1/f/mallory'), frame(1)), 'kein Mitglied');
  await assertFails(set(ref(alice, 'live/race1/f/alice'), { b: B24ok, n: 3, at: 5 }), 'at = Serverzeit');
  await assertFails(set(ref(alice, 'live/race1/f/alice'), frame(4, 'x'.repeat(40))), 'Länge');
  await assertFails(set(ref(alice, 'live/race1/f/alice'), frame(5, 'ab$%'.repeat(6))), 'kein Base64');
  await assertFails(set(ref(alice, 'live/race1/f/alice'), { ...frame(6), extra: 1 }));
  await assertFails(remove(ref(alice, 'live/race1/f/alice')), 'der letzte Frame bleibt für die Wertung');
  await env.clearDatabase();
  await seed({ startsInMs: 10 * 60_000 });
  await assertFails(set(ref(db('alice'), 'live/race1/f/alice'), frame(1)), 'mehr als 2 min vor dem Start');
});

test('Lesen nur für Mitglieder; Übersicht schreibt nur der Server', async () => {
  await seed();
  await assertSucceeds(get(ref(db('bob'), 'live/race1')));
  await assertFails(get(ref(db('mallory'), 'live/race1')));
  await assertFails(set(ref(db('alice'), 'live/race1/field'), { r: 'race1', at: 1, b: 'AQ==' }));
  await assertFails(set(ref(db('alice'), 'live/race1/fieldFull'), { r: 'race1', at: 1, b: 'AQ==' }));
  await assertFails(set(ref(db('alice'), 'live/race1/sonstwas'), 1));
});

test('Anwesenheit: eigene, true oder entfernt, onDisconnect erlaubt', async () => {
  await seed();
  const alice = db('alice');
  await assertSucceeds(set(ref(alice, 'live/race1/online/alice'), true));
  await assertSucceeds(onDisconnect(ref(alice, 'live/race1/online/alice')).remove());
  await assertSucceeds(remove(ref(alice, 'live/race1/online/alice')));
  await assertFails(set(ref(alice, 'live/race1/online/bob'), true));
  await assertFails(set(ref(alice, 'live/race1/online/alice'), 'ja'));
  await assertFails(set(ref(db('mallory'), 'live/race1/online/mallory'), true));
});
