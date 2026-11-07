import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = Path(__file__).parent / "promo"
OUT.mkdir(exist_ok=True)
W, H, S = 640, 170, 3
TXT = {
    "en": ("Enjoying the addon? It really helps!", ["LIKE", "SHARE", "COMMENT"]),
    "fr": ("Tu aimes l'addon ? Ça m'aide énormément !", ["LIKE", "PARTAGE", "COMMENTE"]),
    "es": ("¿Te gusta el addon? ¡Me ayuda muchísimo!", ["LIKE", "COMPARTE", "COMENTA"]),
}
COLS = [(46, 204, 113), (52, 152, 219), (255, 159, 67)]


def font(size):
    for p in ["C:/Windows/Fonts/seguibl.ttf", "C:/Windows/Fonts/segoeuib.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def icon(kind, size, col):
    z = size * S
    im = Image.new("RGBA", (z, z), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    w = (255, 255, 255, 255)
    if kind == 0:
        d.rounded_rectangle([z * .06, z * .44, z * .27, z * .94], z * .05, fill=w)
        d.rounded_rectangle([z * .33, z * .42, z * .90, z * .94], z * .12, fill=w)
        d.polygon([(z * .33, z * .50), (z * .47, z * .10), (z * .62, z * .10), (z * .64, z * .26), (z * .58, z * .46)], fill=w)
        d.ellipse([z * .46, z * .03, z * .64, z * .21], fill=w)
        for k in range(3):
            y = z * (.56 + k * .12)
            d.line([(z * .62, y), (z * .88, y)], fill=col + (255,), width=max(2, int(z * .035)))
    elif kind == 1:
        pts = [(z * .78, z * .2), (z * .22, z * .5), (z * .78, z * .8)]
        d.line([pts[0], pts[1], pts[2]], fill=w, width=int(z * .08))
        r = z * .14
        for x, y in pts:
            d.ellipse([x - r, y - r, x + r, y + r], fill=w)
    else:
        d.rounded_rectangle([z * .06, z * .1, z * .94, z * .72], z * .16, fill=w)
        d.polygon([(z * .24, z * .66), (z * .2, z * .92), (z * .46, z * .7)], fill=w)
        for k in range(3):
            cx, cy, r = z * (.3 + k * .2), z * .41, z * .065
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (255,))
    return im.resize((size, size), Image.LANCZOS)


def frame(lang, t):
    head, labels = TXT[lang]
    im = Image.new("RGB", (W * S, H * S), (14, 17, 34))
    d = ImageDraw.Draw(im)
    for y in range(H * S):
        k = y / (H * S)
        d.line([(0, y), (W * S, y)], fill=(int(18 + 24 * k), int(20 + 8 * k), int(48 - 10 * k)))
    fh = font(26 * S)
    d.text((W * S / 2, 34 * S), head, font=fh, fill=(255, 255, 255), anchor="mm")
    active = int(t * 3) % 3
    phase = (t * 3) % 1
    pw, ph, gap = 186, 74, 14
    x0 = (W - (pw * 3 + gap * 2)) / 2
    glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for k in range(3):
        on = k == active
        pop = 1 + (.10 * math.sin(math.pi * min(1, phase * 1.6)) if on else 0)
        cx, cy = (x0 + k * (pw + gap) + pw / 2) * S, 112 * S
        bw, bh = pw * pop * S, ph * pop * S
        box = [cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2]
        col = COLS[k]
        if on:
            gd.rounded_rectangle([box[0] - 10 * S, box[1] - 10 * S, box[2] + 10 * S, box[3] + 10 * S], 40 * S, fill=col + (150,))
        fill = col if on else tuple(int(c * .35 + 30) for c in col)
        d.rounded_rectangle(box, 36 * S * pop, fill=fill)
        isz = int(40 * pop)
        ic = icon(k, isz, fill).resize((isz * S, isz * S), Image.LANCZOS)
        im.paste(ic, (int(box[0] + 18 * S), int(cy - isz * S / 2)), ic)
        room = bw - (18 + isz + 12 + 16) * S
        fs = int(22 * pop)
        while fs > 12 and d.textlength(labels[k], font=font(fs * S)) > room:
            fs -= 1
        f = font(fs * S)
        d.text((box[0] + (18 + isz + 12) * S, cy), labels[k], font=f, fill=(255, 255, 255) if on else (205, 208, 225), anchor="lm")
    glow = glow.filter(ImageFilter.GaussianBlur(14 * S))
    base = Image.alpha_composite(im.convert("RGBA"), glow)
    top = im.convert("RGBA")
    mask = Image.new("L", im.size, 0)
    md = ImageDraw.Draw(mask)
    md.rectangle([0, 0, W * S, 62 * S], fill=255)
    for k in range(3):
        cx, cy = (x0 + k * (pw + gap) + pw / 2) * S, 112 * S
        pop = 1.12
        md.rounded_rectangle([cx - pw * pop * S / 2, cy - ph * pop * S / 2, cx + pw * pop * S / 2, cy + ph * pop * S / 2], 40 * S, fill=255)
    out = Image.composite(top, base, mask).convert("RGB")
    return out.resize((W, H), Image.LANCZOS)


for lang in TXT:
    n = 30
    frames = [frame(lang, i / n).quantize(colors=128, method=Image.Quantize.MEDIANCUT) for i in range(n)]
    p = OUT / f"cta-{lang}.gif"
    frames[0].save(p, save_all=True, append_images=frames[1:], duration=100, loop=0, optimize=True, disposal=2)
    print(p.name, round(p.stat().st_size / 1024), "Ko")
