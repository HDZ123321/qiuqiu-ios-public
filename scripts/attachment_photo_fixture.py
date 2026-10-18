"""Synthetic high-entropy RGB PNG: >4MiB, reproducible, no personal data."""
import random
import struct
import zlib
from pathlib import Path
rng = random.Random(92026)
w = h = 2400
raw = b''.join(b'\0' + rng.randbytes(w * 3) for _ in range(h))
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
assert len(png) > 4*1024*1024
Path('attachment-noise-2400.png').write_bytes(png)
print('fixture=attachment-noise-2400.png bytes=' + str(len(png)))
