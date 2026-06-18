#!/usr/bin/env python3
"""Sync generated mascot assets into the web and macOS apps.

The canonical generated frames live under assets/mascot. This script keeps the
website sprite sheets and macOS app sprite resources in step with those source
frames.
"""

from __future__ import annotations

import shutil
import colorsys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError as exc:
    raise SystemExit("Pillow is required. Install it with: python3 -m pip install Pillow") from exc


ROOT = Path(__file__).resolve().parents[1]
MASCOT_DIR = ROOT / "assets" / "mascot"
WEB_ASSET_DIR = ROOT / "apps" / "web" / "public" / "assets"
WEB_MASCOT_DIR = WEB_ASSET_DIR / "mascot"
MACOS_RESOURCES = ROOT / "apps" / "macos" / "Resources"
APP_ICON_VARIANTS_DIR = MACOS_RESOURCES / "AppIconVariants"
CRAB_SPRITE_VARIANTS_DIR = MACOS_RESOURCES / "CrabSpriteVariants"
WALL_CRAB_SPRITE_VARIANTS_DIR = MACOS_RESOURCES / "CrabSpriteWallVariants"
APP_ICON_CANVAS_SIZE = (1024, 1024)
APP_ICON_PADDING = 110

IDLE_DIR = MASCOT_DIR / "idle-walk"
RECORDING_DIR = MASCOT_DIR / "recording-boom"
BOOM_MIC_OVERLAY = RECORDING_DIR / "boom-mic-overlay.png"
WALL_IDLE_CANVAS_SIZE = (154, 183)
WALL_RECORDING_CANVAS_SIZE = (154, 203)
WALL_BOOM_OVERLAY_OFFSET = (8, 2)
WALL_DIRECT_BOOM_CRAB_BOTTOM_OFFSET = (11, 0)

ICON_COLOR_VARIANTS: dict[str, tuple[float, float, float]] = {
    "ocean": (0, 1, 0),
    "deepSea": (0, 1.08, -0.14),
    "cobalt": (10, 1, 0),
    "sky": (-14, 0.82, 0.08),
    "aqua": (-24, 1, 0),
    "teal": (-34, 1, 0),
    "mint": (-54, 0.82, 0.08),
    "emerald": (-74, 1, 0),
    "lime": (-96, 1, 0),
    "gold": (-128, 1, 0),
    "amber": (-150, 1, 0),
    "violet": (46, 1, 0),
    "lavender": (54, 0.82, 0.08),
    "grape": (68, 1, 0),
    "coral": (150, 1, 0.02),
    "rose": (118, 1, 0),
    "bubblegum": (96, 1, 0),
    "ember": (170, 1, -0.06),
    "black": (0, 0.20, -0.42),
    "graphite": (0, 0.18, -0.04),
    "pearl": (0, 0.12, 0.08),
}


def ensure_dirs() -> None:
    WEB_MASCOT_DIR.mkdir(parents=True, exist_ok=True)
    (MACOS_RESOURCES / "CrabSprites").mkdir(parents=True, exist_ok=True)
    (MACOS_RESOURCES / "CrabSpritesWall").mkdir(parents=True, exist_ok=True)
    APP_ICON_VARIANTS_DIR.mkdir(parents=True, exist_ok=True)
    CRAB_SPRITE_VARIANTS_DIR.mkdir(parents=True, exist_ok=True)
    WALL_CRAB_SPRITE_VARIANTS_DIR.mkdir(parents=True, exist_ok=True)


def frame_paths(source_dir: Path) -> list[Path]:
    return [source_dir / f"frame-{index}.png" for index in range(1, 5)]


def load_rgba(path: Path) -> Image.Image:
    if not path.exists():
        raise SystemExit(f"Missing mascot source: {path}")
    return Image.open(path).convert("RGBA")


def write_sheet(frames: list[Image.Image], destination: Path) -> None:
    width, height = frames[0].size
    sheet = Image.new("RGBA", (width * len(frames), height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index * width, 0))
    sheet.save(destination)


def sheet_from_frames(frames: list[Image.Image]) -> Image.Image:
    width, height = frames[0].size
    sheet = Image.new("RGBA", (width * len(frames), height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index * width, 0))
    return sheet


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise SystemExit("Mascot frame has no visible pixels")
    return bbox


def trim_alpha(image: Image.Image) -> Image.Image:
    return image.crop(alpha_bbox(image))


def fit_on_canvas(
    image: Image.Image,
    canvas_size: tuple[int, int],
    *,
    padding: int,
    rotation_degrees: int = 0,
    trailing_bleed_pixels: int = 0,
) -> Image.Image:
    trimmed = trim_alpha(image)
    if rotation_degrees:
        trimmed = trimmed.rotate(rotation_degrees, expand=True, resample=Image.Resampling.NEAREST)

    available_width = canvas_size[0] - padding * 2
    available_height = canvas_size[1] - padding * 2
    scale = min(available_width / trimmed.width, available_height / trimmed.height)
    output_size = (
        max(1, round(trimmed.width * scale)),
        max(1, round(trimmed.height * scale)),
    )
    resized = trimmed.resize(output_size, Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))

    offset = (
        (canvas_size[0] - resized.width) // 2 + trailing_bleed_pixels,
        (canvas_size[1] - resized.height) // 2,
    )
    canvas.alpha_composite(resized, offset)
    return canvas


def transform_overlay_like_reference(
    overlay: Image.Image,
    reference: Image.Image,
    canvas_size: tuple[int, int],
    *,
    padding: int,
    rotation_degrees: int = 0,
    trailing_bleed_pixels: int = 0,
    extra_offset: tuple[int, int] = (0, 0),
) -> Image.Image:
    reference_bbox = alpha_bbox(reference)
    overlay_bbox = alpha_bbox(overlay)
    union_bbox = (
        min(reference_bbox[0], overlay_bbox[0]),
        min(reference_bbox[1], overlay_bbox[1]),
        max(reference_bbox[2], overlay_bbox[2]),
        max(reference_bbox[3], overlay_bbox[3]),
    )

    reference_crop = reference.crop(union_bbox)
    overlay_crop = overlay.crop(union_bbox)
    if rotation_degrees:
        reference_crop = reference_crop.rotate(
            rotation_degrees,
            expand=True,
            resample=Image.Resampling.NEAREST,
        )
        overlay_crop = overlay_crop.rotate(
            rotation_degrees,
            expand=True,
            resample=Image.Resampling.NEAREST,
        )

    reference_trimmed = trim_alpha(reference)
    if rotation_degrees:
        reference_trimmed = reference_trimmed.rotate(
            rotation_degrees,
            expand=True,
            resample=Image.Resampling.NEAREST,
        )

    available_width = canvas_size[0] - padding * 2
    available_height = canvas_size[1] - padding * 2
    scale = min(
        available_width / reference_trimmed.width,
        available_height / reference_trimmed.height,
    )

    reference_scaled = reference_crop.resize(
        (
            max(1, round(reference_crop.width * scale)),
            max(1, round(reference_crop.height * scale)),
        ),
        Image.Resampling.NEAREST,
    )
    overlay_scaled = overlay_crop.resize(
        (
            max(1, round(overlay_crop.width * scale)),
            max(1, round(overlay_crop.height * scale)),
        ),
        Image.Resampling.NEAREST,
    )

    rendered_reference = fit_on_canvas(
        reference,
        canvas_size,
        padding=padding,
        rotation_degrees=rotation_degrees,
        trailing_bleed_pixels=trailing_bleed_pixels,
    )
    reference_canvas_bbox = alpha_bbox(rendered_reference)
    reference_scaled_bbox = alpha_bbox(reference_scaled)
    offset = (
        reference_canvas_bbox[0] - reference_scaled_bbox[0] + extra_offset[0],
        reference_canvas_bbox[1] - reference_scaled_bbox[1] + extra_offset[1],
    )

    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    canvas.alpha_composite(overlay_scaled, offset)
    return canvas


def compose_recording_frames(
    idle_frames: list[Image.Image],
    boom_mic_overlay: Image.Image,
) -> list[Image.Image]:
    recording_frame = idle_frames[0].copy()
    recording_frame.alpha_composite(boom_mic_overlay)
    return [recording_frame.copy() for _ in range(4)]


def rotated_wall_square_mic_head(
    size: tuple[int, int],
    angle: int,
) -> Image.Image:
    width, height = size
    padding = 6
    layer = Image.new("RGBA", (width + padding * 2, height + padding * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    outline = (20, 23, 38, 255)
    dark = (62, 70, 94, 250)
    mid = (104, 114, 140, 235)
    highlight = (165, 176, 196, 180)
    lowlight = (42, 48, 70, 210)
    corner_radius = 2

    draw.rounded_rectangle(
        (padding, padding, width + padding - 1, height + padding - 1),
        radius=corner_radius,
        fill=outline,
    )
    draw.rounded_rectangle(
        (padding + 3, padding + 3, width + padding - 4, height + padding - 4),
        radius=1,
        fill=dark,
    )
    draw.rectangle((padding + 7, padding + 6, width + padding - 8, height + padding - 8), fill=mid)
    draw.rectangle(
        (padding + 11, padding + 8, width + padding - 16, padding + 11),
        fill=(138, 148, 171, 170),
    )
    draw.rectangle(
        (padding + 7, height + padding - 10, width + padding - 8, height + padding - 7),
        fill=lowlight,
    )
    for x, y, color in [
        (padding + 12, padding + 7, highlight),
        (padding + 19, padding + 6, (148, 159, 181, 160)),
        (padding + 10, padding + 15, (148, 158, 178, 135)),
        (padding + 26, padding + 14, (88, 97, 122, 160)),
        (padding + 18, padding + 18, (76, 84, 108, 140)),
    ]:
        draw.rectangle((x, y, x + 2, y + 1), fill=color)

    return layer.rotate(angle, expand=True, resample=Image.Resampling.NEAREST)


def compose_wall_boom_overlay() -> Image.Image:
    canvas = Image.new("RGBA", WALL_RECORDING_CANVAS_SIZE, (0, 0, 0, 0))
    boom = Image.new("RGBA", WALL_RECORDING_CANVAS_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(boom)

    outline = (18, 20, 32, 255)
    shaft_dark = (48, 52, 68, 255)
    shaft_mid = (125, 132, 150, 240)
    shaft_highlight = (174, 180, 194, 210)
    shaft = ((84, 164), (127, 127))

    draw.line(shaft, fill=outline, width=8)
    draw.line(shaft, fill=shaft_dark, width=6)
    draw.line(
        ((shaft[0][0] + 1, shaft[0][1] - 1), (shaft[1][0] + 1, shaft[1][1] - 1)),
        fill=shaft_highlight,
        width=1,
    )
    draw.line(
        ((shaft[0][0] - 1, shaft[0][1] + 1), (shaft[1][0] - 1, shaft[1][1] + 1)),
        fill=shaft_mid,
        width=1,
    )

    hinge = (84, 164)
    draw.line(((79, 168), (70, 177)), fill=outline, width=6)
    draw.line(((79, 168), (70, 177)), fill=(90, 98, 118, 255), width=3)
    draw.ellipse((72, 172, 83, 183), fill=outline)
    draw.ellipse((75, 175, 80, 180), fill=(127, 134, 152, 245))
    draw.ellipse((hinge[0] - 5, hinge[1] - 5, hinge[0] + 5, hinge[1] + 5), fill=outline)
    draw.ellipse(
        (hinge[0] - 3, hinge[1] - 3, hinge[0] + 3, hinge[1] + 3),
        fill=(118, 126, 145, 245),
    )
    draw.line(
        ((hinge[0] - 7, hinge[1] + 2), (hinge[0] + 3, hinge[1] + 8)),
        fill=outline,
        width=4,
    )
    draw.line(
        ((hinge[0] - 7, hinge[1] + 2), (hinge[0] + 3, hinge[1] + 8)),
        fill=(92, 100, 120, 240),
        width=2,
    )

    boom.alpha_composite(rotated_wall_square_mic_head((42, 25), -8), (53, 164))
    canvas.alpha_composite(boom, WALL_DIRECT_BOOM_CRAB_BOTTOM_OFFSET)
    return canvas


def write_recording_sources(recording_frames: list[Image.Image]) -> None:
    RECORDING_DIR.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(recording_frames, start=1):
        frame.save(RECORDING_DIR / f"frame-{index}.png")

    alpha_sheet = sheet_from_frames(recording_frames)
    alpha_sheet.save(RECORDING_DIR / "sheet.png")
    alpha_sheet.save(RECORDING_DIR / "source-alpha.png")

    chroma_sheet = Image.new("RGBA", alpha_sheet.size, (255, 0, 255, 255))
    chroma_sheet.alpha_composite(alpha_sheet)
    chroma_sheet.save(RECORDING_DIR / "source.png")


def write_macos_sprites(
    idle_frames: list[Image.Image],
    recording_frames: list[Image.Image],
    boom_mic_overlay: Image.Image,
) -> None:
    for index, frame in enumerate(idle_frames, start=1):
        fit_on_canvas(frame, (240, 174), padding=5).save(
            MACOS_RESOURCES / "CrabSprites" / f"idle-{index}.png"
        )
        fit_on_canvas(
            frame,
            WALL_IDLE_CANVAS_SIZE,
            padding=4,
            rotation_degrees=90,
            trailing_bleed_pixels=5,
        ).save(
            MACOS_RESOURCES / "CrabSpritesWall" / f"idle-{index}.png"
        )

    normal_recording_overlay = transform_overlay_like_reference(
        boom_mic_overlay,
        idle_frames[0],
        (240, 174),
        padding=5,
    )
    for index in range(1, len(recording_frames) + 1):
        normal_recording = fit_on_canvas(idle_frames[0], (240, 174), padding=5)
        normal_recording.alpha_composite(normal_recording_overlay)
        normal_recording.save(MACOS_RESOURCES / "CrabSprites" / f"recording-{index}.png")

    # Recording is steady: keep the wall crab pixels identical to idle, centered
    # inside a taller canvas that gives the lower boom mic room to extend.
    wall_idle = fit_on_canvas(
        idle_frames[0],
        WALL_IDLE_CANVAS_SIZE,
        padding=4,
        rotation_degrees=90,
        trailing_bleed_pixels=5,
    )
    wall_recording = Image.new("RGBA", WALL_RECORDING_CANVAS_SIZE, (0, 0, 0, 0))
    vertical_offset = (WALL_RECORDING_CANVAS_SIZE[1] - WALL_IDLE_CANVAS_SIZE[1]) // 2
    wall_recording.alpha_composite(wall_idle, (0, vertical_offset))

    wall_recording.alpha_composite(compose_wall_boom_overlay())
    wall_recording.save(MACOS_RESOURCES / "CrabSpritesWall" / "recording-2.png")


def sync_icon_sources() -> None:
    icon_source = MACOS_RESOURCES / "GeneratedAssets" / "AppIconSource.png"
    if icon_source.exists():
        shutil.copyfile(icon_source, WEB_ASSET_DIR / "shoutout-icon.png")
        docs_asset_dir = ROOT / "docs" / "assets"
        docs_asset_dir.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(icon_source, docs_asset_dir / "shoutout-icon.png")


def transform_icon_foreground(
    image: Image.Image,
    hue_degrees: float,
    saturation_factor: float,
    brightness_delta: float,
) -> Image.Image:
    source = image.convert("RGBA")
    bbox = source.getchannel("A").getbbox()
    if bbox is None:
        return source

    source_crop = source.crop(bbox)
    hue_shift = hue_degrees / 360
    pixels = []

    for red, green, blue, alpha in source_crop.getdata():
        if alpha == 0:
            pixels.append((red, green, blue, alpha))
            continue

        hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        hue = (hue + hue_shift) % 1.0
        saturation = min(max(saturation * saturation_factor, 0), 1)
        value = min(max(value + brightness_delta, 0), 1)
        out_red, out_green, out_blue = colorsys.hsv_to_rgb(hue, saturation, value)
        pixels.append((
            round(out_red * 255),
            round(out_green * 255),
            round(out_blue * 255),
            alpha,
        ))

    transformed_crop = Image.new("RGBA", source_crop.size, (0, 0, 0, 0))
    transformed_crop.putdata(pixels)
    transformed = Image.new("RGBA", source.size, (0, 0, 0, 0))
    transformed.alpha_composite(transformed_crop, bbox[:2])
    return transformed


def compose_app_icon_from_sprite(sprite: Image.Image) -> Image.Image:
    source = trim_alpha(sprite)
    available_width = APP_ICON_CANVAS_SIZE[0] - APP_ICON_PADDING * 2
    available_height = APP_ICON_CANVAS_SIZE[1] - APP_ICON_PADDING * 2
    scale = min(available_width / source.width, available_height / source.height)
    output_size = (
        max(1, round(source.width * scale)),
        max(1, round(source.height * scale)),
    )

    resized = source.resize(output_size, Image.Resampling.NEAREST)
    icon = Image.new("RGBA", APP_ICON_CANVAS_SIZE, (0, 0, 0, 0))
    icon.alpha_composite(
        resized,
        (
            (APP_ICON_CANVAS_SIZE[0] - resized.width) // 2,
            (APP_ICON_CANVAS_SIZE[1] - resized.height) // 2,
        ),
    )
    return icon


def write_tinted_sprite_variants() -> None:
    source_sets = [
        (MACOS_RESOURCES / "CrabSprites", CRAB_SPRITE_VARIANTS_DIR),
        (MACOS_RESOURCES / "CrabSpritesWall", WALL_CRAB_SPRITE_VARIANTS_DIR),
    ]
    for source_dir, destination_root in source_sets:
        source_paths = sorted(source_dir.glob("*.png"))
        if not source_paths:
            continue

        for variant, (hue_degrees, saturation, brightness) in ICON_COLOR_VARIANTS.items():
            variant_dir = destination_root / variant
            variant_dir.mkdir(parents=True, exist_ok=True)
            for source_path in source_paths:
                tinted_sprite = transform_icon_foreground(
                    load_rgba(source_path),
                    hue_degrees,
                    saturation,
                    brightness,
                )
                tinted_sprite.save(variant_dir / source_path.name)


def write_app_icon_variants() -> None:
    sprite_source_paths = [
        CRAB_SPRITE_VARIANTS_DIR / variant / "idle-1.png"
        for variant in ICON_COLOR_VARIANTS
    ]
    source_path = MACOS_RESOURCES / "GeneratedAssets" / "AppIconSource.png"
    if not source_path.exists():
        return

    if not all(path.exists() for path in sprite_source_paths):
        shutil.copyfile(source_path, APP_ICON_VARIANTS_DIR / "ocean.png")
        return

    variant_paths = [APP_ICON_VARIANTS_DIR / f"{variant}.png" for variant in ICON_COLOR_VARIANTS]
    newest_input_mtime = max(
        source_path.stat().st_mtime,
        Path(__file__).stat().st_mtime,
        *(path.stat().st_mtime for path in sprite_source_paths),
    )
    if all(path.exists() and path.stat().st_mtime >= newest_input_mtime for path in variant_paths):
        return

    for variant in ICON_COLOR_VARIANTS:
        tinted_sprite = load_rgba(CRAB_SPRITE_VARIANTS_DIR / variant / "idle-1.png")
        icon = compose_app_icon_from_sprite(tinted_sprite)
        icon.save(APP_ICON_VARIANTS_DIR / f"{variant}.png")


def main() -> None:
    ensure_dirs()
    idle_frames = [load_rgba(path) for path in frame_paths(IDLE_DIR)]
    boom_mic_overlay = load_rgba(BOOM_MIC_OVERLAY)
    recording_frames = compose_recording_frames(idle_frames, boom_mic_overlay)
    write_recording_sources(recording_frames)

    write_sheet(idle_frames, WEB_MASCOT_DIR / "idle-walk.png")
    write_sheet(recording_frames, WEB_MASCOT_DIR / "recording-boom.png")
    write_macos_sprites(idle_frames, recording_frames, boom_mic_overlay)
    write_tinted_sprite_variants()
    sync_icon_sources()
    write_app_icon_variants()

    print("Synced mascot assets for web and macOS.")


if __name__ == "__main__":
    main()
