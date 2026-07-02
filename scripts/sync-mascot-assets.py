#!/usr/bin/env python3
"""Sync generated mascot assets into the web and macOS apps.

The canonical generated frames live under assets/mascot. This script keeps the
website sprite sheets and macOS app sprite resources in step with those source
frames.
"""

from __future__ import annotations

import shutil
import colorsys
import subprocess
import tempfile
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
APP_ICON_FILE = MACOS_RESOURCES / "AppIcon.icns"
APP_ICON_VARIANTS_DIR = MACOS_RESOURCES / "AppIconVariants"
CRAB_SPRITE_VARIANTS_DIR = MACOS_RESOURCES / "CrabSpriteVariants"
WALL_CRAB_SPRITE_VARIANTS_DIR = MACOS_RESOURCES / "CrabSpriteWallVariants"
APP_ICON_CANVAS_SIZE = (1024, 1024)
APP_ICON_PADDING = 110

IDLE_DIR = MASCOT_DIR / "idle-walk"
RECORDING_DIR = MASCOT_DIR / "recording-boom"
BOOM_MIC_OVERLAY = RECORDING_DIR / "boom-mic-overlay.png"
WALL_BODY_CANVAS_SIZE = (154, 183)
WALL_FRAME_CANVAS_SIZE = (154, 203)
WALL_RECORDING_INTRO_FRAME_COUNT = 6
GENERATED_WALL_RECORDING_SHEET = (
    MASCOT_DIR / "generated-candidates" / "crab-boom-pet-sheet-v4-alpha.png"
)
GENERATED_WALL_RECORDING_SOURCE_FRAME_COUNT = 8
GENERATED_WALL_RECORDING_SOURCE_INDICES = (3, 4, 5, 6, 7, 8)
GENERATED_WALL_RECORDING_FIT_MARGIN = 4
WALL_BOOM_HANDLE_EXTENSION_BY_SOURCE_INDEX = {
    8: ((126, 143), (139, 130)),
}
WALL_BOOM_HANDLE_EXTENSION_OUTLINE = (8, 7, 12, 255)
WALL_BOOM_HANDLE_EXTENSION_MIDTONE = (58, 55, 66, 255)
WALL_BOOM_HANDLE_EXTENSION_HIGHLIGHT = (138, 135, 148, 255)

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
    "black": (0, 0.18, -0.30),
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


def prune_pngs(directory: Path, keep_names: set[str]) -> None:
    if not directory.exists():
        return

    for path in directory.glob("*.png"):
        if path.name not in keep_names:
            path.unlink()


def save_png_if_changed(image: Image.Image, destination: Path) -> None:
    if destination.exists():
        existing = Image.open(destination).convert("RGBA")
        candidate = image.convert("RGBA")
        if existing.size == candidate.size and existing.tobytes() == candidate.tobytes():
            return

    image.save(destination)


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
    save_png_if_changed(sheet, destination)


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


def pixel_mask_bbox(image: Image.Image, predicate) -> tuple[int, int, int, int] | None:
    pixels = image.load()
    left = image.width
    top = image.height
    right = 0
    bottom = 0

    for y in range(image.height):
        for x in range(image.width):
            if not predicate(pixels[x, y]):
                continue
            left = min(left, x)
            top = min(top, y)
            right = max(right, x + 1)
            bottom = max(bottom, y + 1)

    if right == 0 or bottom == 0:
        return None
    return (left, top, right, bottom)


def is_crab_core_pixel(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    return (
        alpha > 80
        and blue > 70
        and green > 35
        and red < 115
        and (blue > red + 35 or green > red + 35)
    )


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


def compose_wall_idle_canvas(wall_body: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", WALL_FRAME_CANVAS_SIZE, (0, 0, 0, 0))
    vertical_offset = (WALL_FRAME_CANVAS_SIZE[1] - wall_body.height) // 2
    canvas.alpha_composite(wall_body, (0, vertical_offset))
    return canvas


def generated_wall_recording_source_frames() -> list[
    tuple[Image.Image, tuple[int, int, int, int], tuple[int, int, int, int]]
]:
    sheet = load_rgba(GENERATED_WALL_RECORDING_SHEET)
    frames = []

    for index in range(GENERATED_WALL_RECORDING_SOURCE_FRAME_COUNT):
        left = round(index * sheet.width / GENERATED_WALL_RECORDING_SOURCE_FRAME_COUNT)
        right = round((index + 1) * sheet.width / GENERATED_WALL_RECORDING_SOURCE_FRAME_COUNT)
        frame = sheet.crop((left, 0, right, sheet.height))
        source_bbox = alpha_bbox(frame)
        core_bbox = pixel_mask_bbox(frame, is_crab_core_pixel)
        if core_bbox is None:
            raise SystemExit(
                f"Generated wall recording frame {index + 1} has no crab core pixels"
            )
        frames.append((frame, source_bbox, core_bbox))

    return frames


def generated_wall_recording_scale(
    source_frames: list[
        tuple[Image.Image, tuple[int, int, int, int], tuple[int, int, int, int]]
    ],
    target_core_bbox: tuple[int, int, int, int],
) -> float:
    _, _, reference_core_bbox = source_frames[0]
    target_core_width = target_core_bbox[2] - target_core_bbox[0]
    target_core_height = target_core_bbox[3] - target_core_bbox[1]
    reference_core_width = reference_core_bbox[2] - reference_core_bbox[0]
    reference_core_height = reference_core_bbox[3] - reference_core_bbox[1]
    scale = min(
        target_core_width / reference_core_width,
        target_core_height / reference_core_height,
    )

    for frame, source_bbox, _ in source_frames:
        source_crop = frame.crop(source_bbox)
        scale = min(
            scale,
            (WALL_FRAME_CANVAS_SIZE[0] - 2) / source_crop.width,
            (
                WALL_FRAME_CANVAS_SIZE[1]
                - GENERATED_WALL_RECORDING_FIT_MARGIN * 2
            ) / source_crop.height,
        )

    return scale


def normalize_generated_wall_recording_frame(
    frame: Image.Image,
    source_bbox: tuple[int, int, int, int],
    source_core_bbox: tuple[int, int, int, int],
    target_core_bbox: tuple[int, int, int, int],
    scale: float,
) -> Image.Image:
    crop = frame.crop(source_bbox)
    resized = crop.resize(
        (
            max(1, round(crop.width * scale)),
            max(1, round(crop.height * scale)),
        ),
        Image.Resampling.NEAREST,
    )

    core_relative = (
        source_core_bbox[0] - source_bbox[0],
        source_core_bbox[1] - source_bbox[1],
        source_core_bbox[2] - source_bbox[0],
        source_core_bbox[3] - source_bbox[1],
    )
    core_scaled = (
        round(core_relative[0] * scale),
        round(core_relative[1] * scale),
        round(core_relative[2] * scale),
        round(core_relative[3] * scale),
    )
    target_core_center_y = (target_core_bbox[1] + target_core_bbox[3]) // 2
    resized_core_center_y = (core_scaled[1] + core_scaled[3]) // 2

    offset_x = target_core_bbox[2] - core_scaled[2]
    offset_y = target_core_center_y - resized_core_center_y
    offset_x = min(max(offset_x, 0), WALL_FRAME_CANVAS_SIZE[0] - resized.width)
    offset_y = min(
        max(offset_y, GENERATED_WALL_RECORDING_FIT_MARGIN),
        WALL_FRAME_CANVAS_SIZE[1] - GENERATED_WALL_RECORDING_FIT_MARGIN - resized.height,
    )

    canvas = Image.new("RGBA", WALL_FRAME_CANVAS_SIZE, (0, 0, 0, 0))
    canvas.alpha_composite(resized, (offset_x, offset_y))
    return canvas


def extend_wall_boom_handle(frame: Image.Image, source_index: int) -> Image.Image:
    segment = WALL_BOOM_HANDLE_EXTENSION_BY_SOURCE_INDEX.get(source_index)
    if segment is None:
        return frame

    result = frame.copy()
    overlay = Image.new("RGBA", result.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    start, end = segment
    draw.line([start, end], fill=WALL_BOOM_HANDLE_EXTENSION_OUTLINE, width=5)
    draw.line([start, end], fill=WALL_BOOM_HANDLE_EXTENSION_MIDTONE, width=3)
    draw.line(
        [(start[0] + 1, start[1]), (end[0] - 1, end[1] + 2)],
        fill=WALL_BOOM_HANDLE_EXTENSION_HIGHLIGHT,
        width=1,
    )

    overlay_pixels = overlay.load()
    frame_pixels = frame.load()
    for y in range(frame.height):
        for x in range(frame.width):
            if overlay_pixels[x, y][3] == 0:
                continue
            if is_crab_core_pixel(frame_pixels[x, y]):
                overlay_pixels[x, y] = (0, 0, 0, 0)

    result.alpha_composite(overlay)
    return result


def compose_wall_recording_frames(wall_idle_canvas: Image.Image) -> dict[str, Image.Image]:
    target_core_bbox = pixel_mask_bbox(wall_idle_canvas, is_crab_core_pixel)
    if target_core_bbox is None:
        raise SystemExit("Wall idle frame has no crab core pixels")

    source_frames = generated_wall_recording_source_frames()
    scale = generated_wall_recording_scale(source_frames, target_core_bbox)
    normalized_frames = []
    for source_index, (frame, source_bbox, source_core_bbox) in enumerate(
        source_frames,
        start=1,
    ):
        normalized = normalize_generated_wall_recording_frame(
            frame,
            source_bbox,
            source_core_bbox,
            target_core_bbox,
            scale,
        )
        normalized_frames.append(extend_wall_boom_handle(normalized, source_index))

    frames = {
        f"recording-intro-{index}": normalized_frames[source_index - 1]
        for index, source_index in enumerate(
            GENERATED_WALL_RECORDING_SOURCE_INDICES,
            start=1,
        )
    }
    hold_frame = normalized_frames[GENERATED_WALL_RECORDING_SOURCE_INDICES[-1] - 1]
    frames["recording-hold"] = hold_frame
    frames["recording-2"] = hold_frame.copy()
    return frames


def close_pixel_match(first: tuple[int, int, int, int], second: tuple[int, int, int, int]) -> bool:
    return all(abs(first[channel] - second[channel]) <= 3 for channel in range(4))


def is_neutral_hardware_pixel(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    if alpha < 96:
        return False

    chroma = max(red, green, blue) - min(red, green, blue)
    luma = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    return chroma <= 44 or luma <= 34


def extract_neutral_recording_overlay(recording: Image.Image, idle: Image.Image) -> Image.Image:
    overlay = Image.new("RGBA", recording.size, (0, 0, 0, 0))
    recording_pixels = recording.load()
    idle_pixels = idle.load()
    overlay_pixels = overlay.load()
    y_offset = (recording.height - idle.height) // 2 if recording.height >= idle.height else 0

    for y in range(recording.height):
        for x in range(recording.width):
            pixel = recording_pixels[x, y]
            if not is_neutral_hardware_pixel(pixel):
                continue

            idle_y = y - y_offset
            if 0 <= idle_y < idle.height and x < idle.width:
                idle_pixel = idle_pixels[x, idle_y]
                if idle_pixel[3] > 0 and close_pixel_match(pixel, idle_pixel):
                    continue

            overlay_pixels[x, y] = pixel

    return overlay


def restore_neutral_recording_hardware(
    canvas: Image.Image,
    recording: Image.Image,
    idle: Image.Image,
) -> Image.Image:
    result = canvas.copy()
    result_pixels = result.load()
    recording_pixels = recording.load()
    idle_pixels = idle.load()
    y_offset = (recording.height - idle.height) // 2 if recording.height >= idle.height else 0

    for y in range(recording.height):
        for x in range(recording.width):
            pixel = recording_pixels[x, y]
            if not is_neutral_hardware_pixel(pixel):
                continue

            idle_y = y - y_offset
            if 0 <= idle_y < idle.height and x < idle.width:
                idle_pixel = idle_pixels[x, idle_y]
                if idle_pixel[3] > 0 and close_pixel_match(pixel, idle_pixel):
                    continue

            result_pixels[x, y] = pixel

    return result


def compose_tinted_recording_variant(
    recording: Image.Image,
    idle: Image.Image,
    tinted_recording: Image.Image,
) -> Image.Image:
    return restore_neutral_recording_hardware(tinted_recording, recording, idle)


def write_recording_sources(recording_frames: list[Image.Image]) -> None:
    RECORDING_DIR.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(recording_frames, start=1):
        save_png_if_changed(frame, RECORDING_DIR / f"frame-{index}.png")

    alpha_sheet = sheet_from_frames(recording_frames)
    save_png_if_changed(alpha_sheet, RECORDING_DIR / "sheet.png")
    save_png_if_changed(alpha_sheet, RECORDING_DIR / "source-alpha.png")

    chroma_sheet = Image.new("RGBA", alpha_sheet.size, (255, 0, 255, 255))
    chroma_sheet.alpha_composite(alpha_sheet)
    save_png_if_changed(chroma_sheet, RECORDING_DIR / "source.png")


def write_macos_sprites(
    idle_frames: list[Image.Image],
    recording_frames: list[Image.Image],
    boom_mic_overlay: Image.Image,
) -> None:
    for index, frame in enumerate(idle_frames, start=1):
        save_png_if_changed(
            fit_on_canvas(frame, (240, 174), padding=5),
            MACOS_RESOURCES / "CrabSprites" / f"idle-{index}.png"
        )

    wall_idle_frames = [
        compose_wall_idle_canvas(
            fit_on_canvas(
                frame,
                WALL_BODY_CANVAS_SIZE,
                padding=4,
                rotation_degrees=90,
                trailing_bleed_pixels=5,
            )
        )
        for frame in idle_frames
    ]
    for index, frame in enumerate(wall_idle_frames, start=1):
        save_png_if_changed(frame, MACOS_RESOURCES / "CrabSpritesWall" / f"idle-{index}.png")

    normal_recording_overlay = transform_overlay_like_reference(
        boom_mic_overlay,
        idle_frames[0],
        (240, 174),
        padding=5,
    )
    for index in range(1, len(recording_frames) + 1):
        normal_recording = fit_on_canvas(idle_frames[0], (240, 174), padding=5)
        normal_recording.alpha_composite(normal_recording_overlay)
        save_png_if_changed(
            normal_recording,
            MACOS_RESOURCES / "CrabSprites" / f"recording-{index}.png",
        )

    # Recording frames keep the wall crab pixels identical to idle, centered
    # inside a taller canvas that gives the lower boom mic room to extend.
    for name, frame in compose_wall_recording_frames(wall_idle_frames[0]).items():
        save_png_if_changed(frame, MACOS_RESOURCES / "CrabSpritesWall" / f"{name}.png")

    wall_resource_names = {
        f"idle-{index}.png" for index in range(1, len(wall_idle_frames) + 1)
    } | {
        f"recording-intro-{index}.png"
        for index in range(1, WALL_RECORDING_INTRO_FRAME_COUNT + 1)
    } | {"recording-hold.png", "recording-2.png"}
    prune_pngs(MACOS_RESOURCES / "CrabSpritesWall", wall_resource_names)


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

    pixel_bytes = source_crop.tobytes()
    for index in range(0, len(pixel_bytes), 4):
        red, green, blue, alpha = pixel_bytes[index:index + 4]
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
                source_image = load_rgba(source_path)
                tinted_sprite = transform_icon_foreground(
                    source_image,
                    hue_degrees,
                    saturation,
                    brightness,
                )
                if source_dir.name == "CrabSpritesWall" and source_path.name.startswith("recording"):
                    idle_path = source_dir / "idle-1.png"
                    if idle_path.exists():
                        idle = load_rgba(idle_path)
                        tinted_sprite = compose_tinted_recording_variant(
                            source_image,
                            idle,
                            tinted_sprite,
                        )
                save_png_if_changed(tinted_sprite, variant_dir / source_path.name)
            prune_pngs(variant_dir, {path.name for path in source_paths})


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
        save_png_if_changed(icon, APP_ICON_VARIANTS_DIR / f"{variant}.png")


def write_default_app_icon() -> None:
    source_path = APP_ICON_VARIANTS_DIR / "ocean.png"
    if not source_path.exists():
        return

    source = load_rgba(source_path)
    with tempfile.TemporaryDirectory() as temporary_directory:
        temporary_path = Path(temporary_directory)
        iconset_path = temporary_path / "AppIcon.iconset"
        iconset_path.mkdir()
        output_path = temporary_path / "AppIcon.icns"

        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                pixel_size = size * scale
                filename = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
                resized = source.resize((pixel_size, pixel_size), Image.Resampling.NEAREST)
                resized.save(iconset_path / filename)

        subprocess.run(
            ["iconutil", "-c", "icns", "-o", str(output_path), str(iconset_path)],
            check=True,
        )

        if APP_ICON_FILE.exists() and APP_ICON_FILE.read_bytes() == output_path.read_bytes():
            return
        shutil.copyfile(output_path, APP_ICON_FILE)


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
    write_default_app_icon()

    print("Synced mascot assets for web and macOS.")


if __name__ == "__main__":
    main()
