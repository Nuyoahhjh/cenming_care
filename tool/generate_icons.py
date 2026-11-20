from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "brand" / "favicon.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

LEGACY_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ADAPTIVE_SIZES = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}


def load_source() -> Image.Image:
    image = Image.open(SOURCE).convert("RGBA")
    bbox = image.getbbox()
    if bbox:
        image = image.crop(bbox)
    return image


def compose_logo(
    source: Image.Image,
    size: int,
    color: tuple[int, int, int, int] | None,
    scale: float,
) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), color or (0, 0, 0, 0))
    target = max(1, round(size * scale))
    logo = source.copy()
    logo.thumbnail((target, target), Image.Resampling.LANCZOS)
    left = (size - logo.width) // 2
    top = (size - logo.height) // 2
    canvas.alpha_composite(logo, (left, top))
    return canvas


def main() -> None:
    source = load_source()

    app_icon = compose_logo(source, 1024, (255, 255, 255, 255), 0.84)
    app_icon.convert("RGB").save(ROOT / "assets" / "brand" / "app_icon.png")

    for directory, size in LEGACY_SIZES.items():
        path = RES / directory
        path.mkdir(parents=True, exist_ok=True)
        icon = compose_logo(source, size, (255, 255, 255, 255), 0.84)
        icon.convert("RGB").save(path / "ic_launcher.png")

    for directory, size in ADAPTIVE_SIZES.items():
        path = RES / directory
        path.mkdir(parents=True, exist_ok=True)
        foreground = compose_logo(source, size, None, 0.56)
        foreground.save(path / "ic_launcher_foreground.png")

    adaptive = RES / "mipmap-anydpi-v26"
    adaptive.mkdir(parents=True, exist_ok=True)
    (adaptive / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n',
        encoding="utf-8",
    )

    values = RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <color name="ic_launcher_background">#FFFFFF</color>\n'
        '</resources>\n',
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
