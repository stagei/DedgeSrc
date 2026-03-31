"""Make grey/white transparent on DB2 and SQLite logos; brighten all three."""
from pathlib import Path
from PIL import Image

DIR = Path(__file__).resolve().parent
BRIGHTEN = 1.25
WHITE_GREY_LUM = 240
GREY_CHROMA = 25

def is_white_or_grey(r, g, b):
    lum = (r + g + b) // 3
    if lum < WHITE_GREY_LUM:
        return False
    return abs(r - g) <= GREY_CHROMA and abs(g - b) <= GREY_CHROMA and abs(r - b) <= GREY_CHROMA

def process(path: Path, make_transparent: bool):
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    data = list(img.getdata())
    out = []
    for (r, g, b, a) in data:
        if make_transparent and is_white_or_grey(r, g, b):
            out.append((r, g, b, 0))
        else:
            nr = min(255, int(r * BRIGHTEN))
            ng = min(255, int(g * BRIGHTEN))
            nb = min(255, int(b * BRIGHTEN))
            out.append((nr, ng, nb, a))
    img.putdata(out)
    tmp = path.with_suffix(".tmp.png")
    img.save(tmp, "PNG")
    img.close()
    tmp.replace(path)

process(DIR / "db2.png", make_transparent=True)
process(DIR / "sqlite.png", make_transparent=True)
process(DIR / "postgresql.png", make_transparent=False)
print("Provider logos updated: transparency and brightness applied.")
