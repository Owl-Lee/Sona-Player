"""Create a tightly framed, transparent Windows icon from the Sona mark."""

from collections import deque
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT_ROOT / "assets" / "branding" / "sona_mark.png"
OUTPUT = PROJECT_ROOT / "assets" / "branding" / "sona_mark_cutout.png"
WINDOWS_ICON = PROJECT_ROOT / "windows" / "runner" / "resources" / "sona_cutout.ico"


def is_background(red: int, green: int, blue: int) -> bool:
    """Match only near-neutral white pixels connected to the outer canvas."""
    return min(red, green, blue) >= 232 and max(red, green, blue) - min(red, green, blue) <= 18


def remove_outer_white_background(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()
    visited = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    def visit(x: int, y: int) -> None:
        index = y * width + x
        if visited[index]:
            return
        red, green, blue, _ = pixels[x, y]
        if not is_background(red, green, blue):
            return
        visited[index] = 1
        queue.append((x, y))

    for x in range(width):
        visit(x, 0)
        visit(x, height - 1)
    for y in range(1, height - 1):
        visit(0, y)
        visit(width - 1, y)

    while queue:
        x, y = queue.popleft()
        pixels[x, y] = (0, 0, 0, 0)
        if x:
            visit(x - 1, y)
        if x < width - 1:
            visit(x + 1, y)
        if y:
            visit(x, y - 1)
        if y < height - 1:
            visit(x, y + 1)

    alpha = rgba.getchannel("A")
    box = alpha.getbbox()
    if box is None:
        raise RuntimeError("The Sona mark became empty after background removal.")
    return rgba.crop(box)


def icon_canvas(mark: Image.Image, size: int, ratio: float = 0.88) -> Image.Image:
    target = round(size * ratio)
    fitted = mark.copy()
    fitted.thumbnail((target, target), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(fitted, ((size - fitted.width) // 2, (size - fitted.height) // 2))
    return canvas


def main() -> None:
    mark = remove_outer_white_background(Image.open(SOURCE))
    master = icon_canvas(mark, 1024)
    master.save(OUTPUT, optimize=True)
    master.save(
        WINDOWS_ICON,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print(f"Transparent mark: {OUTPUT}")
    print(f"Windows icon: {WINDOWS_ICON}")


if __name__ == "__main__":
    main()
