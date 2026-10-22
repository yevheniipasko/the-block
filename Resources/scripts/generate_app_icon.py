"""Generate The Block app icon (light, dark, tinted) into the asset catalog.

Usage: python3 Resources/scripts/generate_app_icon.py   (requires Pillow)
Draws a gavel striking a sound block. Rendered at 2x and downsampled for smooth edges.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 2
S = SIZE * SCALE
OUT = Path(__file__).resolve().parents[2] / "The Block/Assets.xcassets/AppIcon.appiconset"

NAVY_TOP = (22, 58, 140)
NAVY_BOTTOM = (8, 22, 64)
AMBER = (255, 176, 32)
AMBER_DARK = (214, 128, 10)
WHITE = (255, 255, 255)
SILVER = (205, 214, 232)


def gradient(top, bottom):
    img = Image.new("RGBA", (S, S))
    draw = ImageDraw.Draw(img)
    for y in range(S):
        t = y / (S - 1)
        draw.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    return img


def gavel_layer(head, band, handle):
    """Horizontal gavel centered on its own canvas, ready to rotate."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    u = S / 1024
    cx, cy = S / 2, S / 2
    # Handle runs right from the head.
    d.rounded_rectangle([cx - 20 * u, cy - 26 * u, cx + 400 * u, cy + 26 * u], radius=26 * u, fill=handle)
    # Head: wide barrel with bands near each end.
    hw, hh = 150 * u, 230 * u
    d.rounded_rectangle([cx - hw, cy - hh, cx + hw * 0.2, cy + hh], radius=40 * u, fill=head)
    for offset in (-hh + 38 * u, hh - 38 * u - 30 * u):
        d.rectangle([cx - hw, cy + offset, cx + hw * 0.2, cy + offset + 30 * u], fill=band)
    return layer


def block_layer(top, side):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    u = S / 1024
    left, right, y = 200 * u, 824 * u, 690 * u
    d.rounded_rectangle([left, y, right, y + 150 * u], radius=36 * u, fill=side)
    d.rounded_rectangle([left, y, right, y + 96 * u], radius=36 * u, fill=top)
    return layer


def compose(background, head, band, handle, block_top, block_side, shadow=True):
    canvas = background.copy() if background else Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gavel = gavel_layer(head, band, handle).rotate(38, resample=Image.BICUBIC, center=(S / 2, S / 2))
    gavel = gavel.transform((S, S), Image.AFFINE, (1, 0, 40 * SCALE, 0, 1, 84 * SCALE), resample=Image.BICUBIC)
    block = block_layer(block_top, block_side)
    if shadow:
        mask = Image.alpha_composite(block, gavel).split()[3]
        shade = Image.new("RGBA", (S, S), (0, 0, 0, 110))
        shade.putalpha(mask.point(lambda a: a * 110 // 255))
        shade = shade.transform((S, S), Image.AFFINE, (1, 0, 0, 0, 1, -18 * SCALE)).filter(ImageFilter.GaussianBlur(24 * SCALE))
        canvas = Image.alpha_composite(canvas, shade)
    canvas = Image.alpha_composite(canvas, block)
    canvas = Image.alpha_composite(canvas, gavel)
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    light = compose(gradient(NAVY_TOP, NAVY_BOTTOM), WHITE, AMBER, SILVER, AMBER, AMBER_DARK)
    light.convert("RGB").save(OUT / "AppIcon.png")
    # Dark: transparent background, the system supplies the dark backdrop.
    compose(None, WHITE, AMBER, SILVER, AMBER, AMBER_DARK, shadow=False).save(OUT / "AppIcon-Dark.png")
    # Tinted: grayscale on transparent; the system applies the tint.
    tinted = compose(None, (255,) * 3, (150,) * 3, (200,) * 3, (230,) * 3, (160,) * 3, shadow=False)
    gray = tinted.convert("LA").convert("RGBA")
    gray.putalpha(tinted.split()[3])
    gray.save(OUT / "AppIcon-Tinted.png")


if __name__ == "__main__":
    main()
