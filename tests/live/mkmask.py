#!/usr/bin/env python3
"""mkmask.py — write a minimal 8-bit grayscale PNG: white rect, black elsewhere.
Usage: mkmask.py OUT W H X0 Y0 X1 Y1 (rect inclusive)."""
import struct
import sys
import zlib


def chunk(tag: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + tag + data +
            struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


out, w, h, x0, y0, x1, y1 = sys.argv[1], *(int(x) for x in sys.argv[2:8])
rows = []
for y in range(h):
    row = bytearray([0])  # filter: none
    for x in range(w):
        row.append(255 if (x0 <= x <= x1 and y0 <= y <= y1) else 0)
    rows.append(bytes(row))

png = (b"\x89PNG\r\n\x1a\n" +
       chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)) +
       chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) +
       chunk(b"IEND", b""))
open(out, "wb").write(png)
