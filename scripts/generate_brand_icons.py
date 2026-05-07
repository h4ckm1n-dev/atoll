#!/usr/bin/env python3

from __future__ import annotations

import json
import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


# Atoll palette — Catppuccin Mocha-tinted ocean tones with warm sand
# and Catppuccin accent greens for the palm. The icon is intentionally
# darker than the upstream "Open Island" green-mint cat to match the
# blue-teal direction the v1.0 rebrand took.
ATOLL_PALETTE = {
    "ocean_top":    "#0a1220",  # Mocha crust — deepest night-ocean
    "ocean_mid":    "#162232",  # Mocha base — open water
    "ocean_bot":    "#263347",  # Mocha surface0 — sunlit shallows
    "lagoon_outer": "#74c7ec",  # Catppuccin sapphire
    "lagoon_inner": "#94e2d5",  # Catppuccin teal — calm center
    "sand":         "#fab387",  # Catppuccin peach — warm reef sand
    "sand_shadow":  "#cc8867",  # darker peach (rim)
    "frond":        "#a6e3a1",  # Catppuccin green — palm leaves
    "frond_dark":   "#6a9a55",  # darker green (shadows)
    "trunk":        "#8b6f4e",  # warm brown
    "coconut":      "#3a2818",  # near-black brown
    "moon":         "#f9e2af",  # Catppuccin yellow — warm moon
    "moon_glow":    "#fab387",  # Catppuccin peach — halo
}


REPO_ROOT = Path(__file__).resolve().parents[1]
BRAND_ROOT = REPO_ROOT / "Assets" / "Brand"
APP_ICONSET_DIR = BRAND_ROOT / "AppIcon.appiconset"
ICONSET_DIR = BRAND_ROOT / "OpenIsland.iconset"
INTERNAL_COLOR_DIR = BRAND_ROOT / "Internal" / "color"
INTERNAL_TEMPLATE_DIR = BRAND_ROOT / "Internal" / "template"
INTERNAL_BADGE_DIR = BRAND_ROOT / "Internal" / "badge"
ICNS_PATH = BRAND_ROOT / "OpenIsland.icns"
SVG_MASTER_PATH = BRAND_ROOT / "scout-app-icon-master.svg"

SCOUT_PATTERN = [
    "..B..B..",
    "..BBBB..",
    ".BHHHHB.",
    "BBHEHEBB",
    ".BHHHHB.",
    "..BBBB..",
    ".B....B.",
    "........",
]

APP_ICON_SPECS = [
    ("icon_16x16.png", "16x16", "1x", 16),
    ("icon_16x16@2x.png", "16x16", "2x", 32),
    ("icon_32x32.png", "32x32", "1x", 32),
    ("icon_32x32@2x.png", "32x32", "2x", 64),
    ("icon_128x128.png", "128x128", "1x", 128),
    ("icon_128x128@2x.png", "128x128", "2x", 256),
    ("icon_256x256.png", "256x256", "1x", 256),
    ("icon_256x256@2x.png", "256x256", "2x", 512),
    ("icon_512x512.png", "512x512", "1x", 512),
    ("icon_512x512@2x.png", "512x512", "2x", 1024),
]

# Apple's macOS icon grid (Big Sur+): the art occupies an 824×824 region
# centered in a 1024×1024 canvas, leaving a transparent safe zone so our
# squircle visually matches stock macOS icons in Finder/Launchpad/Dock.
MACOS_ICON_CONTENT_RATIO = 824 / 1024


def main() -> None:
    ensure_clean_dir(APP_ICONSET_DIR)
    ensure_clean_dir(ICONSET_DIR)
    ensure_clean_dir(INTERNAL_COLOR_DIR)
    ensure_clean_dir(INTERNAL_TEMPLATE_DIR)
    ensure_clean_dir(INTERNAL_BADGE_DIR)
    BRAND_ROOT.mkdir(parents=True, exist_ok=True)

    write_svg_master(SVG_MASTER_PATH)
    write_app_icons()
    write_internal_assets()
    write_appiconset_contents_json(APP_ICONSET_DIR / "Contents.json")
    build_icns()


def ensure_clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def rgba(hex_color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[index : index + 2], 16) for index in range(0, 6, 2)) + (alpha,)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def solid_layer(size: tuple[int, int], color: tuple[int, int, int, int]) -> Image.Image:
    return Image.new("RGBA", size, color)


def vertical_gradient(size: tuple[int, int], top: str, bottom: str) -> Image.Image:
    top_rgba = rgba(top)
    bottom_rgba = rgba(bottom)
    image = Image.new("RGBA", size)
    pixels = image.load()
    height = max(size[1] - 1, 1)
    for y in range(size[1]):
        mix = y / height
        color = tuple(
            round(top_rgba[index] + (bottom_rgba[index] - top_rgba[index]) * mix)
            for index in range(4)
        )
        for x in range(size[0]):
            pixels[x, y] = color
    return image


def diagonal_gradient(size: tuple[int, int], top_left: str, mid: str, bottom_right: str) -> Image.Image:
    tl = rgba(top_left)
    m = rgba(mid)
    br = rgba(bottom_right)
    image = Image.new("RGBA", size)
    pixels = image.load()
    diag = max((size[0] + size[1]) - 2, 1)
    for y in range(size[1]):
        for x in range(size[0]):
            t = (x + y) / diag
            if t < 0.5:
                t2 = t * 2
                color = tuple(round(tl[i] + (m[i] - tl[i]) * t2) for i in range(4))
            else:
                t2 = (t - 0.5) * 2
                color = tuple(round(m[i] + (br[i] - m[i]) * t2) for i in range(4))
            pixels[x, y] = color
    return image


def draw_shadow(base: Image.Image, box: tuple[int, int, int, int], radius: int, color: str, blur: float) -> None:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(box, radius=radius, fill=rgba(color))
    shadow = layer.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(shadow)


def draw_glow_ellipse(base: Image.Image, box: tuple[int, int, int, int], color: str, blur: float) -> None:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.ellipse(box, fill=rgba(color))
    glow = layer.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(glow)


def paste_masked(base: Image.Image, overlay: Image.Image, xy: tuple[int, int], mask: Image.Image) -> None:
    base.paste(overlay, xy, mask)


def draw_app_shell(size: int) -> tuple[Image.Image, tuple[int, int, int, int]]:
    """Atoll squircle: dark ocean-night gradient (Mocha crust → base →
    surface0) with a subtle gloss highlight on the upper half — matches
    the Apple HIG icon grid (824/1024 content ratio) the upstream icon
    used so Atoll's icon visually aligns with stock macOS apps.
    """
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    icon_size = int(size * 0.86)
    icon_x = (size - icon_size) // 2
    icon_y = (size - icon_size) // 2 - max(2, size // 64)
    outer_radius = max(12, int(icon_size * 0.24))

    face_gradient = diagonal_gradient(
        (icon_size, icon_size),
        ATOLL_PALETTE["ocean_top"],
        ATOLL_PALETTE["ocean_mid"],
        ATOLL_PALETTE["ocean_bot"],
    )
    face_mask = rounded_mask((icon_size, icon_size), outer_radius)
    paste_masked(image, face_gradient, (icon_x, icon_y), face_mask)

    # Subtle gloss highlight on the upper half (Apple icon convention).
    gloss_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gloss_draw = ImageDraw.Draw(gloss_layer)
    gloss_draw.rounded_rectangle(
        (icon_x, icon_y, icon_x + icon_size, icon_y + icon_size // 2),
        radius=outer_radius,
        fill=(255, 255, 255, 24),
    )
    image.alpha_composite(gloss_layer)

    return image, (icon_x, icon_y, icon_size, icon_size)


def draw_mark_shadow(draw: ImageDraw.ImageDraw, origin: tuple[int, int], cell: int, pattern: list[str], alpha: int) -> None:
    ox, oy = origin
    offset = max(1, round(cell * 0.16))
    shadow_fill = rgba("#000000", alpha)
    for row_index, row in enumerate(pattern):
        for column_index, char in enumerate(row):
            if char == ".":
                continue
            x = ox + column_index * cell + offset
            y = oy + row_index * cell + offset
            draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=shadow_fill)


def draw_mark(
    draw: ImageDraw.ImageDraw,
    origin: tuple[int, int],
    cell: int,
    palette: dict[str, tuple[int, int, int, int]],
    include_punctuation: bool,
    silhouette_only: bool = False,
) -> None:
    ox, oy = origin

    for row_index, row in enumerate(SCOUT_PATTERN):
        for column_index, char in enumerate(row):
            if char == ".":
                continue

            fill = palette["B" if silhouette_only else char]
            x = ox + column_index * cell
            y = oy + row_index * cell
            draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=fill)

    if include_punctuation:
        x = ox + 11 * cell
        for row_index in (1, 3, 5):
            y = oy + row_index * cell
            draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=palette["P"])


def render_app_icon(size: int) -> Image.Image:
    """Atoll: a small ring of land around a calm lagoon, with a coconut
    palm rising from it under a warm crescent moon. Drawn against the
    dark ocean-night gradient produced by `draw_app_shell`.
    """
    image, face = draw_app_shell(size)
    fx, fy, fs, _ = face
    draw = ImageDraw.Draw(image)

    # ── 1. Moon (warm yellow disc with peach glow) — upper-right
    moon_d = max(8, int(fs * 0.18))
    moon_cx = fx + int(fs * 0.72)
    moon_cy = fy + int(fs * 0.22)
    glow_r = int(moon_d * 1.4)
    draw_glow_ellipse(
        image,
        (moon_cx - glow_r, moon_cy - glow_r, moon_cx + glow_r, moon_cy + glow_r),
        ATOLL_PALETTE["moon_glow"],
        blur=moon_d * 0.7,
    )
    moon_box = (moon_cx - moon_d // 2, moon_cy - moon_d // 2,
                moon_cx + moon_d // 2, moon_cy + moon_d // 2)
    draw.ellipse(moon_box, fill=rgba(ATOLL_PALETTE["moon"]))

    # ── 2. Atoll ring — wide flat ellipse near the bottom
    atoll_w = int(fs * 0.62)
    atoll_h = max(4, int(atoll_w * 0.30))
    atoll_x = fx + (fs - atoll_w) // 2
    atoll_y = fy + int(fs * 0.66)

    # Outer sand rim shadow (slightly larger, darker — gives depth)
    rim_inset = max(1, int(atoll_w * 0.012))
    draw.ellipse(
        (atoll_x - rim_inset, atoll_y + rim_inset,
         atoll_x + atoll_w + rim_inset, atoll_y + atoll_h + rim_inset),
        fill=rgba(ATOLL_PALETTE["sand_shadow"]),
    )
    # Sand ring (peach)
    draw.ellipse(
        (atoll_x, atoll_y, atoll_x + atoll_w, atoll_y + atoll_h),
        fill=rgba(ATOLL_PALETTE["sand"]),
    )
    # Outer lagoon (sapphire) — slightly inset
    lag_inset_x = int(atoll_w * 0.10)
    lag_inset_y = max(1, int(atoll_h * 0.16))
    draw.ellipse(
        (atoll_x + lag_inset_x, atoll_y + lag_inset_y,
         atoll_x + atoll_w - lag_inset_x, atoll_y + atoll_h - lag_inset_y),
        fill=rgba(ATOLL_PALETTE["lagoon_outer"]),
    )
    # Inner lagoon highlight (teal) — calm center
    inner_inset_x = int(atoll_w * 0.20)
    inner_inset_y = max(1, int(atoll_h * 0.30))
    draw.ellipse(
        (atoll_x + inner_inset_x, atoll_y + inner_inset_y,
         atoll_x + atoll_w - inner_inset_x, atoll_y + atoll_h - inner_inset_y),
        fill=rgba(ATOLL_PALETTE["lagoon_inner"]),
    )

    # ── 3. Coconut palm trunk — slightly curved, rising from atoll
    trunk_w = max(3, int(fs * 0.022))
    trunk_base = (fx + int(fs * 0.46), atoll_y + int(atoll_h * 0.45))
    trunk_top  = (fx + int(fs * 0.52), fy + int(fs * 0.28))
    # Approximate a curve with multiple line segments
    _draw_curved_trunk(draw, trunk_base, trunk_top, trunk_w,
                       rgba(ATOLL_PALETTE["trunk"]))

    # ── 4. Palm fronds — fan of curved leaves at the crown
    crown = trunk_top
    frond_len = int(fs * 0.26)
    frond_w = max(3, int(fs * 0.018))
    # 5 fronds spreading symmetrically — degrees measured from horizontal
    # right (0°), with negative going up. Range covers a full canopy.
    frond_angles = [-160, -130, -95, -55, -25]
    for angle in frond_angles:
        _draw_frond(draw, crown, frond_len, angle, frond_w,
                    rgba(ATOLL_PALETTE["frond"]),
                    rgba(ATOLL_PALETTE["frond_dark"]))

    # ── 5. Coconuts at the crown — two small dark dots
    coconut_d = max(4, int(fs * 0.030))
    for dx, dy in ((-int(fs * 0.025), int(fs * 0.010)),
                   (int(fs * 0.022), int(fs * 0.005))):
        cx = crown[0] + dx
        cy = crown[1] + dy
        draw.ellipse(
            (cx - coconut_d // 2, cy - coconut_d // 2,
             cx + coconut_d // 2, cy + coconut_d // 2),
            fill=rgba(ATOLL_PALETTE["coconut"]),
        )

    return image


def _draw_curved_trunk(
    draw: ImageDraw.ImageDraw,
    base: tuple[int, int],
    top: tuple[int, int],
    width: int,
    color: tuple[int, int, int, int],
) -> None:
    """Trunk approximated as a 12-segment polyline along a quadratic
    Bezier from `base` to `top` with a control point pushed sideways
    to give a subtle palm-like lean.
    """
    bx, by = base
    tx, ty = top
    # Control point: midway vertically, biased outward horizontally
    mid_x = (bx + tx) // 2 + int((tx - bx) * 1.4)
    mid_y = (by + ty) // 2
    points: list[tuple[int, int]] = []
    steps = 12
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * bx + 2 * (1 - t) * t * mid_x + t * t * tx
        y = (1 - t) ** 2 * by + 2 * (1 - t) * t * mid_y + t * t * ty
        points.append((int(x), int(y)))
    for a, b in zip(points, points[1:]):
        draw.line([a, b], fill=color, width=width)


def _draw_frond(
    draw: ImageDraw.ImageDraw,
    crown: tuple[int, int],
    length: int,
    angle_degrees: float,
    width: int,
    color: tuple[int, int, int, int],
    shadow_color: tuple[int, int, int, int],
) -> None:
    """One palm frond: a curved polyline from `crown` outward at the
    given angle, with a subtle perpendicular bow so it droops naturally.
    A darker shadow line below the main one fakes thickness.
    """
    r = math.radians(angle_degrees)
    cos_r, sin_r = math.cos(r), math.sin(r)
    # Perpendicular (for the bow) — rotate +90° from the frond direction
    perp_cos, perp_sin = math.cos(r + math.pi / 2), math.sin(r + math.pi / 2)
    bow = length * 0.18  # how much the frond droops
    cx, cy = crown
    tip_x = cx + length * cos_r
    tip_y = cy + length * sin_r
    mid_x = cx + length * 0.55 * cos_r + bow * perp_cos
    mid_y = cy + length * 0.55 * sin_r + bow * perp_sin
    points: list[tuple[int, int]] = []
    steps = 8
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * cx + 2 * (1 - t) * t * mid_x + t * t * tip_x
        y = (1 - t) ** 2 * cy + 2 * (1 - t) * t * mid_y + t * t * tip_y
        points.append((int(x), int(y)))
    # Shadow first (offset 1-2px down + slightly narrower), then main
    shadow_offset = max(1, width // 3)
    shadow_pts = [(x, y + shadow_offset) for (x, y) in points]
    for a, b in zip(shadow_pts, shadow_pts[1:]):
        draw.line([a, b], fill=shadow_color, width=max(2, width - 1))
    for a, b in zip(points, points[1:]):
        draw.line([a, b], fill=color, width=width)


def render_color_mark(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    cell = size / 8
    palette = {
        "B": rgba("#6E9FFF"),
        "H": rgba("#96BCFF"),
        "E": rgba("#112548"),
        "P": rgba("#6E9FFF"),
    }
    origin = (0, 0)
    for row_index, row in enumerate(SCOUT_PATTERN):
        for column_index, char in enumerate(row):
            if char == ".":
                continue
            x = round(origin[0] + column_index * cell)
            y = round(origin[1] + row_index * cell)
            x2 = round(origin[0] + (column_index + 1) * cell)
            y2 = round(origin[1] + (row_index + 1) * cell)
            draw.rectangle((x, y, x2 - 1, y2 - 1), fill=palette[char])
    return image


def render_template_mark(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    cell = size / 8
    fill = rgba("#000000")
    for row_index, row in enumerate(SCOUT_PATTERN):
        for column_index, char in enumerate(row):
            if char == ".":
                continue
            x = round(column_index * cell)
            y = round(row_index * cell)
            x2 = round((column_index + 1) * cell)
            y2 = round((row_index + 1) * cell)
            draw.rectangle((x, y, x2 - 1, y2 - 1), fill=fill)
    return image


def render_badge(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bezel_size = size
    bezel_gradient = vertical_gradient((bezel_size, bezel_size), "#A7ADB4", "#575D65")
    bezel_mask = rounded_mask((bezel_size, bezel_size), max(6, int(size * 0.23)))
    paste_masked(image, bezel_gradient, (0, 0), bezel_mask)

    inset = max(2, int(size * 0.06))
    face_size = size - inset * 2
    face_gradient = vertical_gradient((face_size, face_size), "#2D3136", "#090A0D")
    face_mask = rounded_mask((face_size, face_size), max(5, int(size * 0.19)))
    paste_masked(image, face_gradient, (inset, inset), face_mask)

    mark = render_color_mark(int(face_size * 0.64)).resize((int(face_size * 0.64), int(face_size * 0.64)), Image.Resampling.NEAREST)
    mx = inset + (face_size - mark.width) // 2
    my = inset + (face_size - mark.height) // 2
    image.alpha_composite(mark, (mx, my))
    return image


def write_app_icons() -> None:
    """Renders the Atoll icon procedurally for every macOS @1x/@2x
    pixel size. The legacy `app-icon-cat.png` master from upstream is
    no longer consulted — we draw the atoll directly in PIL so the
    script is self-contained and tweaks to ATOLL_PALETTE flow through
    a single `python3 scripts/generate_brand_icons.py` run.
    """
    for filename, _, _, pixel_size in APP_ICON_SPECS:
        icon = render_app_icon(pixel_size)
        icon.save(APP_ICONSET_DIR / filename)
        icon.save(ICONSET_DIR / filename)


def write_internal_assets() -> None:
    for size in (14, 18, 32, 64):
        render_color_mark(size).save(INTERNAL_COLOR_DIR / f"scout-mark-{size}.png")

    for size in (18, 36):
        render_template_mark(size).save(INTERNAL_TEMPLATE_DIR / f"scout-template-{size}.png")

    for size in (32, 64):
        render_badge(size).save(INTERNAL_BADGE_DIR / f"scout-badge-{size}.png")


def write_appiconset_contents_json(path: Path) -> None:
    images = [
        {
            "filename": filename,
            "idiom": "mac",
            "scale": scale,
            "size": size,
        }
        for filename, size, scale, _ in APP_ICON_SPECS
    ]
    contents = {
        "images": images,
        "info": {
            "author": "app.openisland.dev",
            "version": 1,
        },
    }
    path.write_text(json.dumps(contents, indent=2) + "\n")


def build_icns() -> None:
    if ICNS_PATH.exists():
        ICNS_PATH.unlink()

    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(ICNS_PATH)],
        check=True,
    )


def write_svg_master(path: Path) -> None:
    """SVG reference of the Atoll icon. Not consumed by the build —
    the actual PNGs are rendered in PIL by `render_app_icon`. Kept in
    sync as a vector reference for design discussions and external
    use (web, print).
    """
    p = ATOLL_PALETTE
    # Coordinates match the 824/1024 face content area used by the
    # PIL renderer. Face spans x=100..924, y=88..912 (icon_size=824
    # centered with a -16px vertical bias).
    fx, fy, fs = 100, 88, 824
    radius = int(fs * 0.24)

    svg = f"""<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="ocean" x1="{fx}" y1="{fy}" x2="{fx + fs}" y2="{fy + fs}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{p['ocean_top']}"/>
      <stop offset="0.5" stop-color="{p['ocean_mid']}"/>
      <stop offset="1" stop-color="{p['ocean_bot']}"/>
    </linearGradient>
    <linearGradient id="gloss" x1="0" y1="{fy}" x2="0" y2="{fy + fs // 2}" gradientUnits="userSpaceOnUse">
      <stop stop-color="white" stop-opacity="0.10"/>
      <stop offset="1" stop-color="white" stop-opacity="0"/>
    </linearGradient>
    <radialGradient id="moonglow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="{p['moon_glow']}" stop-opacity="0.55"/>
      <stop offset="1" stop-color="{p['moon_glow']}" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <!-- Squircle face with ocean gradient + top gloss -->
  <rect x="{fx}" y="{fy}" width="{fs}" height="{fs}" rx="{radius}" fill="url(#ocean)"/>
  <rect x="{fx}" y="{fy}" width="{fs}" height="{fs // 2}" rx="{radius}" fill="url(#gloss)"/>

  <!-- Moon glow + disc, upper-right -->
  <circle cx="{fx + int(fs * 0.72)}" cy="{fy + int(fs * 0.22)}" r="{int(fs * 0.25)}" fill="url(#moonglow)"/>
  <circle cx="{fx + int(fs * 0.72)}" cy="{fy + int(fs * 0.22)}" r="{int(fs * 0.09)}" fill="{p['moon']}"/>

  <!-- Atoll: sand ring + sapphire lagoon + teal center -->
  <ellipse cx="{fx + fs // 2}" cy="{fy + int(fs * 0.785)}" rx="{int(fs * 0.31)}" ry="{int(fs * 0.093)}" fill="{p['sand_shadow']}"/>
  <ellipse cx="{fx + fs // 2}" cy="{fy + int(fs * 0.78)}" rx="{int(fs * 0.31)}" ry="{int(fs * 0.093)}" fill="{p['sand']}"/>
  <ellipse cx="{fx + fs // 2}" cy="{fy + int(fs * 0.78)}" rx="{int(fs * 0.25)}" ry="{int(fs * 0.063)}" fill="{p['lagoon_outer']}"/>
  <ellipse cx="{fx + fs // 2}" cy="{fy + int(fs * 0.78)}" rx="{int(fs * 0.18)}" ry="{int(fs * 0.040)}" fill="{p['lagoon_inner']}"/>

  <!-- Coconut palm: curved trunk + 5 fronds + 2 coconuts -->
  <path d="M {fx + int(fs * 0.46)} {fy + int(fs * 0.79)} Q {fx + int(fs * 0.62)} {fy + int(fs * 0.55)} {fx + int(fs * 0.52)} {fy + int(fs * 0.28)}"
        stroke="{p['trunk']}" stroke-width="{max(3, int(fs * 0.022))}" stroke-linecap="round" fill="none"/>
  <g stroke="{p['frond']}" stroke-width="{max(3, int(fs * 0.018))}" stroke-linecap="round" fill="none">
    <path d="M {fx + int(fs * 0.52)} {fy + int(fs * 0.28)} Q {fx + int(fs * 0.30)} {fy + int(fs * 0.18)} {fx + int(fs * 0.27)} {fy + int(fs * 0.19)}"/>
    <path d="M {fx + int(fs * 0.52)} {fy + int(fs * 0.28)} Q {fx + int(fs * 0.36)} {fy + int(fs * 0.10)} {fx + int(fs * 0.35)} {fy + int(fs * 0.06)}"/>
    <path d="M {fx + int(fs * 0.52)} {fy + int(fs * 0.28)} Q {fx + int(fs * 0.50)} {fy + int(fs * 0.06)} {fx + int(fs * 0.49)} {fy + int(fs * 0.02)}"/>
    <path d="M {fx + int(fs * 0.52)} {fy + int(fs * 0.28)} Q {fx + int(fs * 0.66)} {fy + int(fs * 0.10)} {fx + int(fs * 0.71)} {fy + int(fs * 0.07)}"/>
    <path d="M {fx + int(fs * 0.52)} {fy + int(fs * 0.28)} Q {fx + int(fs * 0.72)} {fy + int(fs * 0.20)} {fx + int(fs * 0.76)} {fy + int(fs * 0.21)}"/>
  </g>
  <circle cx="{fx + int(fs * 0.495)}" cy="{fy + int(fs * 0.285)}" r="{max(3, int(fs * 0.018))}" fill="{p['coconut']}"/>
  <circle cx="{fx + int(fs * 0.542)}" cy="{fy + int(fs * 0.282)}" r="{max(3, int(fs * 0.018))}" fill="{p['coconut']}"/>
</svg>
"""
    path.write_text(svg)


if __name__ == "__main__":
    main()
