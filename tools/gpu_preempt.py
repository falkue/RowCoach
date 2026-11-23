#!/usr/bin/env python3
"""GPU für RowCoach sofort freimachen und danach alles wieder fortsetzen.

Falk (23.11.2026): Braucht RowCoach Rechenleistung, werden alle anderen Jobs sofort pausiert.
- pause:  hält alle laufenden Jobs der GPU-Warteschlange (gpu.db) mit Priorität > 0 an (SIGSTOP auf den
          ganzen Prozessbaum), pausiert die registrierten Hintergrunddienste (gpu pause-services) und
          kündigt den RowCoach-Lauf in der Warteschlange an. Nichts wird beendet.
- resume: setzt alles fort (SIGCONT), Dienste wieder an, Ankündigung schliessen.
- status: zeigt, was pausiert ist.

Die angehaltenen Jobs halten das gpu.lock weiter. RowCoach-Läufe starten deshalb während der Pause direkt
(ohne `gpu run`), sind aber über die Ankündigung in `gpu status` sichtbar.
Die betroffenen Sessions informiert die Hauptsession (SPARK SW RowCoach) per Nachricht.

Aufruf: tools/gpu_preempt.py pause --note "Licht vorrechnen" | resume | status
"""
import json
import os
import signal
import sqlite3
import subprocess
import sys
from pathlib import Path

DB = Path.home() / "Projects/Software/Spark-GPU/state/gpu.db"
GPU = str(Path.home() / ".local/bin/gpu")
STATE = Path(__file__).with_name(".gpu_preempt_state.json")
OWNER = "SPARK SW RowCoach"


def tree(pid):
    out = subprocess.run(["ps", "-e", "-o", "pid=,ppid="], capture_output=True, text=True).stdout
    kids = {}
    for line in out.split("\n"):
        if line.strip():
            p, pp = map(int, line.split())
            kids.setdefault(pp, []).append(p)
    res, todo = [], [pid]
    while todo:
        p = todo.pop()
        res.append(p)
        todo += kids.get(p, [])
    return res


def pause(note):
    if STATE.exists():
        print("Schon pausiert:", STATE.read_text()); return
    c = sqlite3.connect(DB); c.row_factory = sqlite3.Row
    jobs = c.execute("select id,name,owner,prio,pid from jobs where status='running' and prio>0").fetchall()
    paused = []
    for j in jobs:
        if j["owner"] == OWNER or not j["pid"]:
            continue
        pids = tree(j["pid"])
        for p in pids:  # Eltern zuerst, damit nichts Neues startet
            try:
                os.kill(p, signal.SIGSTOP)
            except ProcessLookupError:
                pass
        paused.append({"job": j["id"], "name": j["name"], "owner": j["owner"], "pids": pids})
        print(f"angehalten: #{j['id']} {j['name']} ({j['owner']}), {len(pids)} Prozesse")
    subprocess.run([GPU, "pause-services", "--reason", f"RowCoach: {note}"])
    out = subprocess.run([GPU, "submit", "-n", "rowcoach-gpu", "-p", "0", "-o", OWNER, "-e", "60",
                          "--note", f"{note}; pausiert: " + ", ".join(f"#{p['job']}" for p in paused)],
                         capture_output=True, text=True).stdout
    sub_id = next((w.strip("#:") for w in out.split() if w.strip("#:").isdigit()), None)
    STATE.write_text(json.dumps({"paused": paused, "submit_id": sub_id, "note": note}, indent=1))
    print("Ankündigung:", out.strip())


def resume():
    if not STATE.exists():
        print("Nichts pausiert."); return
    st = json.loads(STATE.read_text())
    for j in st["paused"]:
        for p in reversed(j["pids"]):  # Kinder zuerst fortsetzen
            try:
                os.kill(p, signal.SIGCONT)
            except ProcessLookupError:
                pass
        print(f"fortgesetzt: #{j['job']} {j['name']} ({j['owner']})")
    subprocess.run([GPU, "resume-services"])
    if st.get("submit_id"):
        subprocess.run([GPU, "done", st["submit_id"]])
    STATE.unlink()


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "pause":
        note = sys.argv[sys.argv.index("--note") + 1] if "--note" in sys.argv else "3D-Berechnung"
        pause(note)
    elif cmd == "resume":
        resume()
    else:
        print(STATE.read_text() if STATE.exists() else "Nichts pausiert.")
