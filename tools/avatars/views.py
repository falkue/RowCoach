"""Prüfansichten (CPU): ../coursebuilder/.venv/bin/python views.py OUT.png <side|face|back|stern|top|app> PHASE char-01:boat-classic-yellow …
`app` = Kamera der App (4,5 m hinter, 2,2 m über dem Boot, 16:9, 55° vertikal), z. B. um die Bootsflaggen zu prüfen."""
import os, sys, math
sys.path.insert(0, '.')
os.environ.update(EGL_PLATFORM="surfaceless", PYOPENGL_PLATFORM="egl", LIBGL_ALWAYS_SOFTWARE="1", GALLIUM_DRIVER="llvmpipe", __EGL_VENDOR_LIBRARY_FILENAMES="/usr/share/glvnd/egl_vendor.d/50_mesa.json", LP_NUM_THREADS="6")
import numpy as np, pyrender
import preview as PV, rig, figure as F, boat as B
from PIL import Image
out, view, phase = sys.argv[1], sys.argv[2], float(sys.argv[3])
cat = PV.Catalog(); fp = F.build_parts(); bp = B.build_parts()
views = {'side': ([3.2, 0.7, 0.0], [0, 0.5, 0.0], 30), 'face': ([0.32, 0.92, 0.78], [0, 0.84, 0.15], 26),
         'back': ([0.6, 1.3, -2.2], [0, 0.6, 0.2], 32), 'stern': ([0.9, 1.9, 4.6], [0, 0.45, -0.6], 34),
         'top': ([0.6, 1.4, 2.4], [0, 0.1, 0.8], 30)}
r = pyrender.OffscreenRenderer(768, 768)
ims = []
for spec in sys.argv[4:]:
    cid, bid = spec.split(':')
    ch = [c for c in cat.chars if c['id'] == cid][0]
    bs = [b for b in cat.boats if b['id'] == bid][0]
    items = PV.assemble(fp, bp, ch, bs, rig.stroke_pose(phase), colors=cat.figure_colors(ch), flag=True)
    if view == 'app':   # Kamera der App: 4,5 m hinter, 2,2 m über dem Ursprung, Blick fast waagrecht, 16:9, 55° vertikal
        rr = pyrender.OffscreenRenderer(1024, 576)
        eye = np.array([0, 2.2, 4.5]); pitch = -math.atan2(1.9, 64.5)
        tgt = eye + np.array([0, math.sin(pitch), -math.cos(pitch)])
        sc = PV.to_scene(items, (0.75, 0.82, 0.9, 1)); sc.add(pyrender.PerspectiveCamera(yfov=math.radians(55), aspectRatio=16/9), pose=PV.look_at(eye, tgt))
        PV.add_lights(sc, [2, 4, 3]); c, _ = rr.render(sc); ims.append(Image.fromarray(c)); rr.delete(); continue
    e, t, f = views[view]
    im = PV.supersample(r, items, PV.look_at(e, t), math.radians(f), [2, 4, 3]); bg = Image.new('RGB', im.size, (225, 228, 232)); bg.paste(im, (0, 0), im); ims.append(bg)
w, h = ims[0].size
cols = min(len(ims), 4); rows = (len(ims) + cols - 1) // cols
board = Image.new("RGB", (cols * w, rows * h), (225, 228, 232))
for i, im in enumerate(ims): board.paste(im, ((i % cols) * w, (i // cols) * h))
board.thumbnail((2000, 2000)); board.save(out)
