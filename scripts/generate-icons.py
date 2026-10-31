"""Render every Nexus icon from services/server/web/icons/icon.svg.

Usage (needs the cairo library; on macOS `brew install cairo`):
    uvx --with cairosvg --with pillow python scripts/generate-icons.py

Outputs:
- web: favicon-32, apple-touch-icon (180), icon-192, icon-512. Full-bleed squares:
  iOS and maskable PWA icons are clipped by the OS, and the artwork stays inside the
  maskable safe zone (80% circle).
- Mac: Nexus/Resources/Assets.xcassets/AppIcon.appiconset, on Apple's 1024 grid
  (824 px tile, 100 px margin, soft drop shadow).
"""

import io
import re
from pathlib import Path

import cairosvg
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "services/server/web/icons/icon.svg"
WEB = ROOT / "services/server/web/icons"
MAC = ROOT / "Nexus/Resources/Assets.xcassets/AppIcon.appiconset"

MAC_SLICES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def render(svg: str, size: int) -> Image.Image:
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def mac_icon(svg: str) -> Image.Image:
    canvas, tile, margin = 1024, 824, 100
    art = render(svg, tile)
    shadow = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    alpha = art.getchannel("A").point(lambda a: a * 0.35)
    shadow.paste(Image.new("RGBA", art.size, (0, 0, 0, 255)), (margin, margin + 12), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    shadow.alpha_composite(art, (margin, margin))
    return shadow


def main() -> None:
    rounded = SVG.read_text()
    square = re.sub(r'(<rect id="tile"[^>]*?) rx="[^"]*"', r"\1", rounded)

    for name, size in [("favicon-32", 32), ("apple-touch-icon", 180), ("icon-192", 192), ("icon-512", 512)]:
        source = rounded if name == "favicon-32" else square
        render(source, size).save(WEB / f"{name}.png", optimize=True)

    big = mac_icon(rounded)
    for logical, scale in MAC_SLICES:
        px = logical * scale
        suffix = "@2x" if scale == 2 else ""
        big.resize((px, px), Image.LANCZOS).save(MAC / f"icon_{logical}x{logical}{suffix}.png", optimize=True)

    print(f"wrote web icons to {WEB.relative_to(ROOT)} and AppIcon to {MAC.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
