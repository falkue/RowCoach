#!/bin/bash
# Vorschau auf der CPU (Mesa llvmpipe), ohne GPU-Warteschlange.
cd "$(dirname "$0")"
export EGL_PLATFORM=surfaceless PYOPENGL_PLATFORM=egl LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe \
       __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json LP_NUM_THREADS=12
exec .venv/bin/python preview.py "$@"
