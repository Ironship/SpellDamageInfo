#!/usr/bin/env python3
"""Draw the addon's icon for the AddOns list.

    python tools/make_icon.py                   # write icon.tga
    python tools/make_icon.py --preview <png>   # also a strip at the sizes it is seen at

Drawn at 1024 and shrunk to 64, because the AddOns list shows it at about
twenty pixels and anything drawn at that size directly turns to porridge. It
shows what the addon draws in the game: an action button with a spell on it
and the damage number over its lower half.

  - a dark disc with one ring, so it reads on the list's dark and light rows;
  - the button square fills most of the disc, and the number fills most of the
    button: at twenty pixels the number is the picture, the flame only says
    "a spell";
  - the number in the addon's own damage gold with a heavy black outline, as
    the game draws it, because a soft edge at twenty pixels is a smudge.

The TGA is 32-bit uncompressed with an alpha channel, which is what the client
reads, and 64 is a power of two, which it insists on. The digits use a heavy
Windows font (Arial Black, or the next one found); see FONTS.
"""

import pathlib
import sys
from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parent.parent
BIG = 1024
S = BIG / 64.0   # everything below is in 64-pixel units, scaled up to draw
NUMBER = "45"
GOLD = (255, 209, 77, 255)   # Format.DAMAGE_COLOR (1, 0.82, 0.3)
FONTS = ["C:/Windows/Fonts/ariblk.ttf", "C:/Windows/Fonts/impact.ttf", "C:/Windows/Fonts/arialbd.ttf",
         "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]


def font(px):
    for path in FONTS:
        try:
            return ImageFont.truetype(path, int(px))
        except OSError:
            continue
    sys.exit("no bold font found; add one to FONTS")


def disc(size):
    """The dark round plate the rest sits on, with one ring and a highlight."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pad = 0.8 * S
    grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / size
        gd.line([(0, y), (size, y)],
                fill=(int(24 + 26 * (1 - t)), int(28 + 26 * (1 - t)), int(40 + 32 * (1 - t)), 255))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([pad, pad, size - pad, size - pad], fill=255)
    img.paste(grad, (0, 0), mask)

    ring = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse([pad, pad, size - pad, size - pad],
                                 outline=(150, 118, 64, 255), width=int(2.0 * S))
    shine = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shine).ellipse([pad, pad, size - pad, size - pad],
                                  outline=(246, 214, 140, 255), width=int(2.0 * S))
    fade = Image.new("L", (size, size), 0)
    fd = ImageDraw.Draw(fade)
    for y in range(size):
        fd.line([(0, y), (size, y)], fill=max(0, int(255 * (1 - y / (size * 0.62)))))
    ring.paste(shine, (0, 0), fade)
    return Image.alpha_composite(img, ring)


BOX = (12.5 * S, 12.5 * S, 51.5 * S, 51.5 * S)   # the action button


def button(size):
    """The action button: a dark frame, a spell icon inside it."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = BOX
    d.rounded_rectangle([x0 - 1.4 * S, y0 - 1.4 * S, x1 + 1.4 * S, y1 + 1.4 * S], radius=3.2 * S,
                        fill=(10, 10, 12, 255))                                      # frame
    art = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ad = ImageDraw.Draw(art)
    for y in range(int(y0), int(y1) + 1):                                             # icon background
        t = (y - y0) / (y1 - y0)
        ad.line([(x0, y), (x1, y)], fill=(int(120 - 70 * t), int(38 - 20 * t), int(30 - 12 * t), 255))
    # the flame, in the top of the button where the number leaves room: a round body, a tall
    # tongue bent to one side and a short one on the other; an orange outside, a yellow core
    cx = (x0 + x1) / 2
    for scale, colour in ((1.0, (255, 120, 26, 255)), (0.55, (255, 232, 128, 255))):
        w, base = 6.4 * S * scale, y0 + 12.5 * S
        ad.ellipse([cx - w, base - w, cx + w, base + w], fill=colour)
        ad.polygon([(cx - w, base - w * 0.1), (cx - w * 0.55, base - w * 1.3), (cx + w * 0.15, base - w * 2.05),
                    (cx + w * 0.3, base - w * 1.2), (cx + w, base - w * 0.1)], fill=colour)
        ad.polygon([(cx + w * 0.2, base - w * 0.6), (cx + w * 0.95, base - w * 1.55),
                    (cx + w * 1.0, base - w * 0.2)], fill=colour)
    clip = Image.new("L", (size, size), 0)
    ImageDraw.Draw(clip).rectangle(BOX, fill=255)
    layer.paste(art, (0, 0), clip)
    d = ImageDraw.Draw(layer)
    d.rectangle(BOX, outline=(96, 90, 84, 255), width=int(1.0 * S))                  # bevel line
    return layer


def number(size):
    """The damage number over the button's lower half, outlined like the game's OUTLINE font."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = font(29 * S)
    x0, y0, x1, y1 = BOX
    left, top, right, bottom = d.textbbox((0, 0), NUMBER, font=f, stroke_width=int(2.6 * S))
    x = (x0 + x1) / 2 - (left + right) / 2
    y = y1 + 3.0 * S - bottom
    d.text((x, y), NUMBER, font=f, fill=GOLD, stroke_width=int(2.6 * S), stroke_fill=(0, 0, 0, 255))
    return layer


def build(size):
    img = disc(size)
    img = Image.alpha_composite(img, button(size))
    return Image.alpha_composite(img, number(size))


def main():
    big = build(BIG)
    out = HERE / "icon.tga"
    big.resize((64, 64), Image.LANCZOS).save(out)
    if "--preview" in sys.argv:
        target = pathlib.Path(sys.argv[sys.argv.index("--preview") + 1])
        sizes = [64, 32, 20, 16]
        strip = Image.new("RGBA", (sum(sizes) + 20 * (len(sizes) + 1), 80), (40, 40, 44, 255))
        light = Image.new("RGBA", strip.size, (200, 200, 196, 255))
        x = 20
        for s in sizes:
            small = big.resize((s, s), Image.LANCZOS)
            strip.paste(small, (x, (80 - s) // 2), small)
            light.paste(small, (x, (80 - s) // 2), small)
            x += s + 20
        both = Image.new("RGBA", (strip.width, 160))
        both.paste(strip, (0, 0))
        both.paste(light, (0, 80))
        both.resize((both.width * 3, both.height * 3), Image.NEAREST).save(target)
        print("preview: %s" % target)
    head = out.read_bytes()[:18]
    print("%s %.1f kB, TGA type %d (2 = uncompressed truecolour), %d bits, %dx%d" % (
        out.relative_to(HERE), out.stat().st_size / 1024, head[2], head[16],
        head[12] | head[13] << 8, head[14] | head[15] << 8))


if __name__ == "__main__":
    main()
