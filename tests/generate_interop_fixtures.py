#!/usr/bin/env python3
"""Regenerate deterministic interoperability fixtures with libbz2 1.0.8."""

import bz2
import ctypes
from pathlib import Path


TEXT_LINE = b"Firmware image compatibility vector: bzip2 1.0.8 / bzip2z.\n"
FIRMWARE_SIZE = 1_200_000


def binary_data() -> bytes:
    return bytes((i * 37 + (i >> 3) * 11) & 0xFF for i in range(65_536))


def firmware_data() -> bytes:
    return bytes(
        (
            (offset * 73 + (offset >> 3) * 19 + page * 29)
            ^ (page >> 2)
            ^ (offset >> 7)
        )
        & 0xFF
        for i in range(FIRMWARE_SIZE)
        for page, offset in [(i // 4096, i % 4096)]
    )


def main() -> None:
    libbz2 = ctypes.CDLL("libbz2.so.1")
    libbz2.BZ2_bzlibVersion.restype = ctypes.c_char_p
    version = libbz2.BZ2_bzlibVersion().decode()
    if not version.startswith("1.0.8,"):
        raise SystemExit(f"fixtures require libbz2 1.0.8, found {version}")

    fixture_dir = Path(__file__).parent.parent / "src" / "testdata"
    vectors = {
        "libbz2-1.0.8-single-stream.bz2": b"\xa5" * 100,
        "libbz2-1.0.8-text.bz2": TEXT_LINE * 256,
        "libbz2-1.0.8-binary.bz2": binary_data(),
        "libbz2-1.0.8-firmware-multiblock.bz2": firmware_data(),
    }
    for name, data in vectors.items():
        (fixture_dir / name).write_bytes(bz2.compress(data, compresslevel=9))


if __name__ == "__main__":
    main()
