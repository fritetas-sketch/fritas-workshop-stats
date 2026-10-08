import json, re, time
from datetime import datetime
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

d = Path(__file__).parent
html = (d / "index.html").read_text(encoding="utf-8")
data = json.loads(re.search(r"const DATA = (\{.*?\});?\r?\n", html).group(1))
items = [i for i in data["items"] if i.get("kind") != "collection"]
keep = {i["id"] for i in items}
subs = sum(i.get("subs") or 0 for i in items)
likes = sum(i.get("likes") or 0 for i in items)
dis = sum(i.get("dislikes") or 0 for i in items)
rate = round(likes / (likes + dis) * 100) if likes + dis else None
hist = sorted(data.get("history") or [], key=lambda h: h["t"])
now = data["generated"]
day0 = datetime.fromtimestamp(now).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
tot = lambda h: sum((x.get("ls") or 0) for x in h["items"] if x["id"] in keep)
def at(t):
    pts = [(h["t"], tot(h)) for h in hist]
    if not pts or t < pts[0][0]:
        return pts[0][1] if pts else 0
    for (ta, va), (tb, vb) in zip(pts, pts[1:]):
        if ta <= t <= tb:
            return va + (vb - va) * (t - ta) / ((tb - ta) or 1)
    return pts[-1][1]
gain = round(tot(hist[-1]) - at(day0)) if hist else 0
ranked = sorted(items, key=lambda i: -(i.get("subs") or 0))
r7 = [(i.get("rk") or {}).get("d7") for i in items]
best = min(((r, i) for r, i in zip(r7, items) if r), default=None, key=lambda x: x[0])
name = lambda i: (re.sub(r"^GLIDE\s*//\s*", "", i["title"], flags=re.I).split(" - ")[0]).strip()
fmt = lambda n: f"{round(n):,}".replace(",", "\u202f")

def font(size, bold=True):
    for p in (["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf"] if bold else ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"]):
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()

W, H = 1200, 630
img = Image.new("RGB", (W, H), "#0f1220")
grad = Image.new("RGB", (W, H))
gd = ImageDraw.Draw(grad)
for y in range(H):
    k = y / H
    gd.line([(0, y), (W, y)], fill=(int(30 + 20 * k), int(24 + 6 * k), int(70 - 30 * k)))
img = Image.blend(img, grad, .9)
dr = ImageDraw.Draw(img)

def cover(p, size):
    try:
        im = Image.open(d / p)
        im.seek(0)
        im = im.convert("RGB")
        s = max(size[0] / im.width, size[1] / im.height)
        im = im.resize((int(im.width * s) + 1, int(im.height * s) + 1), Image.LANCZOS)
        l, t = (im.width - size[0]) // 2, (im.height - size[1]) // 4
        return im.crop((l, t, l + size[0], t + size[1]))
    except Exception:
        return None

def rounded(im, r):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], r, fill=255)
    return m

x0, y0 = 690, 60
for k, it in enumerate(ranked[:3]):
    th = cover(it.get("media") or "", (440, 150))
    yy = y0 + k * 172
    if th:
        img.paste(th, (x0, yy), rounded(th, 22))
        shade = Image.new("RGBA", (440, 150), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shade)
        for yv in range(150):
            sd.line([(0, yv), (440, yv)], fill=(0, 0, 0, int(200 * max(0, (yv - 60) / 90))))
        img.paste(shade, (x0, yy), Image.composite(shade.split()[3], Image.new("L", shade.size, 0), rounded(shade, 22)))
    dr.text((x0 + 18, yy + 108), f"{k + 1}. {name(it)}", font=font(26), fill="white")
    dr.text((x0 + 422, yy + 110), fmt(it.get("subs") or 0), font=font(24), fill="#7dffb2", anchor="ra")

dr.text((60, 64), "WORKSHOP FRITAS", font=font(30), fill="#b9b2ff")
dr.text((60, 110), "Garry's Mod · stats en direct", font=font(26, False), fill="#c8c6dc")
dr.text((56, 190), fmt(subs), font=font(124), fill="white")
dr.text((62, 330), "abonnés", font=font(40, False), fill="#d8d6ea")
y = 410
if gain > 0:
    dr.rounded_rectangle([60, y, 60 + dr.textlength(f"+{fmt(gain)} aujourd'hui", font=font(34)) + 40, y + 62], 31, fill="#13b36b")
    dr.text((80, y + 11), f"+{fmt(gain)} aujourd'hui", font=font(34), fill="white")
    y += 86
lines = []
if rate is not None:
    lines.append(f"{rate} % de likes")
if best:
    lines.append(f"{name(best[1])} n° {best[0]} de la semaine")
txt = "  ·  ".join(lines)
size = 28
while size > 16 and dr.textlength(txt, font=font(size, False)) > 600:
    size -= 1
dr.text((62, y), txt, font=font(size, False), fill="#d8d6ea")
img.save(d / "og.png", optimize=True)

fav = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
fd = ImageDraw.Draw(fav)
fd.rounded_rectangle([0, 0, 127, 127], 30, fill="#6d5dfc")
for k, h in enumerate([46, 70, 98]):
    fd.rounded_rectangle([22 + k * 30, 110 - h, 42 + k * 30, 110], 6, fill="white")
fav.save(d / "favicon.png")

desc = f"{fmt(subs)} abonnés" + (f" · +{fmt(gain)} aujourd'hui" if gain > 0 else "") + (f" · {rate} % de likes" if rate is not None else "") + (f" · {name(best[1])} n° {best[0]} des tendances de la semaine" if best else "")
(d / "og.json").write_text(json.dumps({"title": "Workshop Fritas · stats Garry's Mod", "description": desc, "v": now}, ensure_ascii=False), encoding="utf-8")
print("og.png prêt :", desc)

made = 0
for it in items:
    mp = it.get("media") or ""
    if not mp.lower().endswith(".gif") or not (d / mp).exists():
        continue
    out = d / (mp[:-4] + "_t.jpg")
    try:
        im = Image.open(d / mp)
        im.seek(0)
        im = im.convert("RGB")
        im.thumbnail((160, 160), Image.LANCZOS)
        im.save(out, "JPEG", quality=80, optimize=True)
        made += 1
    except Exception as e:
        print("vignette ratée", mp, e)
print("vignettes fixes :", made)