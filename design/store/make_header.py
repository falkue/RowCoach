"""Header-Bild für die App-Store-Produktseite (5244×2950, Marke „Bahnen“).
Schlüsselinhalt (Bildmarke + Wortmarke) liegt in der Mitte, damit er in allen Zuschnitten (iPhone hoch, iPad quer)
sichtbar bleibt; Bahnen laufen über die ganze Breite."""
import io, cairosvg
from PIL import Image, ImageDraw, ImageFilter
W, H = 5244, 2950
KOBALT, TIEF, GELB = (35, 64, 255), (14, 26, 140), (255, 214, 10)
bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):                       # Verlauf Kobalt → tiefes Kobalt
    t = y / (H - 1)
    d.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(KOBALT, TIEF)))
# Bahnen über die ganze Breite: Pfeilformen wie im Logo, weiss halbtransparent; um Logo und Schrift bleibt eine
# ruhige Mitte frei. Eine gelbe Führungsbahn quert die ganze Breite.
import random
random.seed(7)
lanes = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ld = ImageDraw.Draw(lanes)
h, gap = 130, 110
cx = W // 2
CY = int(H * 0.42)   # Mitte der Logo-Gruppe: im iPhone-Zuschnitt (oberer Teil) und im iPad-Band sichtbar
clear = (cx - 900, CY - 560, cx + 900, CY + 520)   # freie Mitte (Marke + Wortmarke)
def lane(x0, x1, y, col):
    tip = int(h * 0.85)
    ld.polygon([(x0 + 55, y), (x1, y), (x1 + tip, y + h // 2), (x1, y + h), (x0, y + h)], fill=col)
y = -30
while y < H:
    inside = clear[1] - h < y < clear[3]
    a = random.choice([38, 46, 54])
    if inside:
        lane(-80, clear[0] - random.randint(150, 600), y, (255, 255, 255, a))
        lane(clear[2] + random.randint(100, 500), W + 200, y, (255, 255, 255, a))
    else:
        x0 = random.randint(-300, 900); x1 = random.randint(W - 1600, W - 300)
        lane(x0, x1, y, (255, 255, 255, a))
    y += h + gap
yy = clear[3] + 120
ld.polygon([(-50, yy), (W - 520, yy), (W - 520 + 170, yy + 95), (W - 520, yy + 190), (-50, yy + 190)], fill=GELB + (255,))
bg = Image.alpha_composite(bg.convert("RGBA"), lanes)
# Bildmarke (gross) und Wortmarke darunter, zentriert
def svg(path, width):
    return Image.open(io.BytesIO(cairosvg.svg2png(url=path, output_width=width))).convert("RGBA")
mark = svg("../logo/bahnen/bahnen-marke-dunkel.svg", 640)
word = svg("../logo/bahnen/bahnen-wortmarke-dunkel.svg", 1150)
# Marke: nur die Bahnen (ohne Hintergrundfläche) – Hintergrund der SVG ggf. transparent
my = CY - (mark.height + 30 + word.height) // 2
bg.alpha_composite(mark, (cx - mark.width // 2, my))
bg.alpha_composite(word, (cx - word.width // 2, my + mark.height + 30))
bg.convert("RGB").save("header-bahnen-5244x2950.png", compress_level=3)
# Kontrolle der Zuschnitte
prev = bg.convert("RGB")
crops = {"voll": (0, 0, W, H), "ipad-band": (0, int(H*0.22), W, int(H*0.22)+int(W/2.6)), "iphone-hoch": (cx-830, 0, cx+830, H)}
out = []
for n, c in crops.items():
    im = prev.crop(c); im.thumbnail((700, 500)); out.append(im)
sheet = Image.new("RGB", (sum(i.width for i in out) + 20, max(i.height for i in out)), "white")
x = 0
for im in out:
    sheet.paste(im, (x, 0)); x += im.width + 10
sheet.save("/tmp/claude-1000/-home-falkue-Projects-Software-RowCoach/39b6ffaf-34a5-49cd-84f1-fa3ff878c411/scratchpad/header-check.jpg", quality=80)
