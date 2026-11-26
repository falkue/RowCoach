#!/usr/bin/env python3
"""Rendert die statischen Coach-Phrasen (App/RowCoach/Resources/coach_phrases.json) als Tonkonserven mit Google Cloud
Text-to-Speech (Chirp 3 HD) nach App/RowCoach/Resources/Coach/<de|en>/<phraseId>.m4a (AAC mono).

Aufruf (Repo-Wurzel): python3 tools/coach_audio/render_coach.py [--dry-run] [--only de|en] [--limit N]
- Nur Phrasen ohne Variablen ({…}); dynamische spricht die App mit der Systemstimme.
- phraseId = <szenario>.<stufe>.<stil>.<index> (docs/coach/SPEC.md).
- Inkrementell: Coach/manifest.json merkt Text, Stimme und Tempo je Datei; nur Neues oder Geändertes wird gerendert,
  verwaiste Dateien werden entfernt.
- Braucht: gcloud angemeldet, Text-to-Speech auf --project aktiv, ffmpeg. Kosten Chirp 3 HD: siehe Google-Preisliste
  (je Million Zeichen); --dry-run zählt die Zeichen.
"""
import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHRASES = ROOT / 'App/RowCoach/Resources/coach_phrases.json'
OUT = ROOT / 'App/RowCoach/Resources/Coach'
GCLOUD = next((p for p in (os.path.expanduser('~/google-cloud-sdk/bin/gcloud'), '/usr/bin/gcloud') if os.path.exists(p)),
              'gcloud')
VOICES = {'de': 'de-DE-Chirp3-HD-Sadaltager', 'en': 'en-GB-Chirp3-HD-Sadaltager'}
RATE = {'calm': 0.95, 'motivating': 1.0, 'cox': 1.08}


class Token:
    def __init__(self):
        self.lock = threading.Lock()
        self.value, self.at = None, 0.0

    def get(self):
        with self.lock:
            if not self.value or time.time() - self.at > 1800:
                self.value = subprocess.check_output([GCLOUD, 'auth', 'print-access-token'], text=True).strip()
                self.at = time.time()
            return self.value


def phrases(data):
    for scen, sd in data['scenarios'].items():
        for level, styles in (sd.get('levels') or {}).items():
            for style, langs in styles.items():
                for lang, items in langs.items():
                    for i, text in enumerate(items):
                        if '{' in text:
                            continue
                        yield lang, f'{scen}.{level}.{style}.{i}', style, text


def synth(text, voice, rate, project, token):
    body = json.dumps({'input': {'text': text}, 'voice': {'languageCode': voice[:5], 'name': voice},
                       'audioConfig': {'audioEncoding': 'LINEAR16', 'speakingRate': rate,
                                       'sampleRateHertz': 24000}}).encode()
    for attempt in range(10):
        req = urllib.request.Request('https://texttospeech.googleapis.com/v1/text:synthesize', body, {
            'Authorization': 'Bearer ' + token.get(), 'x-goog-user-project': project,
            'Content-Type': 'application/json'})
        try:
            return base64.b64decode(json.load(urllib.request.urlopen(req, timeout=120))['audioContent'])
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 503) and attempt < 9:
                time.sleep(min(60, 5 * 2 ** attempt))  # Kontingent je Minute: warten
                continue
            raise SystemExit(f'TTS-Fehler {e.code}: {e.read()[:300]!r}')


def encode(wav, dest):
    """Stille vorne/hinten kürzen, AAC mono 48 kbit/s"""
    dest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix='.wav') as f:
        f.write(wav)
        f.flush()
        flt = ('silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.03,areverse,'
               'silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.08,areverse')
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', f.name, '-af', flt, '-ac', '1', '-c:a', 'aac',
                        '-b:a', '48k', '-movflags', '+faststart', str(dest)], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--only', choices=['de', 'en'])
    ap.add_argument('--limit', type=int)
    ap.add_argument('--project', default='uebernickel-web')
    ap.add_argument('--workers', type=int, default=2)
    a = ap.parse_args()

    data = json.loads(PHRASES.read_text())
    items = [p for p in phrases(data) if not a.only or p[0] == a.only]
    mpath = OUT / 'manifest.json'
    manifest = json.loads(mpath.read_text()) if mpath.exists() else {}

    def key(lang, style, text):
        return hashlib.sha256(f'{VOICES[lang]}|{RATE.get(style, 1.0)}|{text}'.encode()).hexdigest()[:16]

    todo = [p for p in items if manifest.get(f'{p[0]}/{p[1]}', {}).get('key') != key(p[0], p[2], p[3])
            or not (OUT / p[0] / f'{p[1]}.m4a').exists()]
    if a.limit:
        todo = todo[:a.limit]
    chars = sum(len(p[3]) for p in todo)
    print(f'{len(items)} statische Phrasen, zu rendern: {len(todo)} ({chars} Zeichen)')
    if a.dry_run:
        return
    token = Token()
    lock = threading.Lock()
    done = [0]

    def work(p):
        lang, pid, style, text = p
        wav = synth(text, VOICES[lang], RATE.get(style, 1.0), a.project, token)
        encode(wav, OUT / lang / f'{pid}.m4a')
        with lock:
            manifest[f'{lang}/{pid}'] = {'key': key(lang, style, text), 'text': text, 'voice': VOICES[lang]}
            done[0] += 1
            if done[0] % 20 == 0:
                print(f'  {done[0]}/{len(todo)}', flush=True)
                mpath.write_text(json.dumps(manifest, ensure_ascii=False, indent=1, sort_keys=True))

    OUT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(work, todo))
    # verwaiste Dateien entfernen (nur bei vollem Lauf)
    if not a.limit and not a.only:
        valid = {f'{p[0]}/{p[1]}' for p in items}
        for k in list(manifest):
            if k not in valid:
                (OUT / f'{k}.m4a').unlink(missing_ok=True)
                del manifest[k]
    mpath.write_text(json.dumps(manifest, ensure_ascii=False, indent=1, sort_keys=True))
    size = sum(f.stat().st_size for f in OUT.rglob('*.m4a'))
    print(f'fertig: {done[0]} gerendert, Ordner {size / 1e6:.1f} MB')


if __name__ == '__main__':
    sys.exit(main())
