"""Independent scanout oracle: compare a real pin-captured PPM to the KMS fixture."""
from pathlib import Path
from PIL import Image, ImageChops


def expected_frame():
    def ch(v):
        return ((v & 255) >> 4) * 17  # XRGB8888 -> hardware RGB444 -> VGA RGB888
    raw = bytearray()
    for y in range(480):
        for x in range(640):
            raw.extend((ch(x+3*y), ch(5*x+y), ch(x^(7*y))))
    return Image.frombytes('RGB', (640, 480), bytes(raw))


def compare(path: Path, expected, output: Path):
    if not path.is_file():
        return False
    with Image.open(path) as frame:
        if frame.format != 'PPM' or frame.mode != 'RGB' or frame.size != expected.size:
            raise ValueError('invalid VGA capture format')
        if ImageChops.difference(frame, expected).getbbox() is not None:
            return False  # scanout can straddle a KMS update; wait for a complete matching frame
        frame.save(output)
    return True
