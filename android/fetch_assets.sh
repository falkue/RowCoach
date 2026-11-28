#!/usr/bin/env bash
# Kopiert Strecke, 3D-Szene (GLB) und eine Coach-Ansage in die Assets der Android-App.
# Die GLB ist nicht in Git (gross, wird auf der Spark aus der fertigen Szene erzeugt):
#   Spark:  cd tools/coursebuilder && .venv/bin/python export_glb.py henley-regatta standard
#
# Aufruf (im Ordner android/):
#   ./fetch_assets.sh                    # Strecke henley-regatta; GLB lokal, sonst per rsync von spark
#   ./fetch_assets.sh lac-annecy         # andere Strecke (GLB muss auf der Spark erzeugt sein)
#   SPARK=spark ./fetch_assets.sh        # SSH-Ziel für die gitignorierten Dateien (Standard: spark)
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd .. && pwd)"
COURSE="${1:-henley-regatta}"
QUALITY=standard
SPARK="${SPARK:-spark}"
SPARK_REPO="${SPARK_REPO:-Projects/Software/RowCoach}"
ASSETS=app/src/main/assets

json="$REPO/courses/$COURSE/course.json"
[ -f "$json" ] || json="$REPO/App/Courses/$COURSE/course.json"
[ -f "$json" ] || { echo "course.json für $COURSE nicht gefunden"; exit 1; }
# Gebiet aus "scene": "<gebiet>/scene-{quality}.usdz"
AREA=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['scene'].split('/')[0])" "$json")

mkdir -p "$ASSETS/courses/$COURSE" "$ASSETS/courses/$AREA" "$ASSETS/coach/en"
cp "$json" "$ASSETS/courses/$COURSE/course.json"

glb="scene-$QUALITY.glb"
if [ -f "$REPO/courses/$AREA/$glb" ]; then
  cp "$REPO/courses/$AREA/$glb" "$ASSETS/courses/$AREA/$glb"
else
  echo "GLB nicht lokal – hole $SPARK:$SPARK_REPO/courses/$AREA/$glb"
  rsync -t --progress "$SPARK:$SPARK_REPO/courses/$AREA/$glb" "$ASSETS/courses/$AREA/$glb"
fi

cp "$REPO/App/RowCoach/Resources/Coach/en/go.1.cox.0.m4a" "$ASSETS/coach/en/"

echo "Assets:"
du -sh "$ASSETS/courses/$COURSE/course.json" "$ASSETS/courses/$AREA/$glb" "$ASSETS/coach/en/go.1.cox.0.m4a"
