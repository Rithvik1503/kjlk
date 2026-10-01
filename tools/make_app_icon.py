from PIL import Image, ImageDraw

S = 4096          # supersampled mask
OUT = 1024
PAD = 0.11        # mark inset within the icon

def to_px(p):
    """0..1000 design space -> supersampled pixels, inset by PAD."""
    span = S * (1 - 2 * PAD)
    # Nudged down: the mark's visual mass sits above its bounding box's centre.
    return (S * PAD + p[0] / 1000 * span, S * PAD + p[1] / 1000 * span + S * 0.035)

# The house: one open stroke, starting part-way down the right wall so the
# outline reads as a mark rather than a closed box.
path = [(845, 590), (845, 300), (500, 40), (155, 300), (155, 720), (690, 720)]
stroke = int(S * (1 - 2 * PAD) * 0.088)

mark = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(mark)
d.line([to_px(p) for p in path], fill=255, width=stroke, joint="curve")
# joint="curve" rounds the joins; the ends need caps of their own.
for p in (path[0], path[-1]):
    x, y = to_px(p)
    r = stroke / 2
    d.ellipse([x - r, y - r, x + r, y + r], fill=255)

dot = Image.new("L", (S, S), 0)
dd = ImageDraw.Draw(dot)
cx, cy = to_px((500, 455))
rr = S * (1 - 2 * PAD) * 0.082
dd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=255)

mark_s = mark.resize((OUT, OUT), Image.LANCZOS).load()
dot_s = dot.resize((OUT, OUT), Image.LANCZOS).load()

BASE = (10, 10, 11)
BED = (34, 34, 36)          # the dim bed, as on the dot-matrix bars
BRIGHT = (242, 242, 245)
TEAL_TOP = (82, 214, 170)
TEAL_BOT = (56, 196, 206)

COLS = 46
gap = OUT / COLS
radius = gap * 0.30

img = Image.new("RGB", (OUT, OUT), BASE)
draw = ImageDraw.Draw(img)

for row in range(COLS):
    for col in range(COLS):
        x = (col + 0.5) * gap
        y = (row + 0.5) * gap
        px, py = int(x), int(y)

        m = mark_s[px, py]
        t = dot_s[px, py]

        if t > 40:
            # Vertical ramp across the dot, so it keeps the original's gradient.
            k = (t / 255) ** 0.5
            f = (y - (cy / S * OUT - rr / S * OUT)) / (2 * rr / S * OUT)
            f = min(max(f, 0), 1)
            colour = tuple(
                int(BASE[i] + (TEAL_TOP[i] + (TEAL_BOT[i] - TEAL_TOP[i]) * f - BASE[i]) * k)
                for i in range(3)
            )
            r = radius * (0.72 + 0.28 * k)
        elif m > 40:
            k = (m / 255) ** 0.5
            colour = tuple(int(BASE[i] + (BRIGHT[i] - BASE[i]) * k) for i in range(3))
            r = radius * (0.72 + 0.28 * k)
        else:
            colour = BED
            r = radius * 0.62

        draw.ellipse([x - r, y - r, x + r, y + r], fill=colour)

img.save("/home/user/kjlk/ios/Aura/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
print("written", img.size, img.mode)
