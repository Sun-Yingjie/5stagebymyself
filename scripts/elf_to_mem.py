#!/usr/bin/env python3
"""Convert little-endian RISC-V ELF32 PT_LOAD segments to sparse word hex."""

from __future__ import annotations

import argparse
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path


ELF_HEADER = struct.Struct("<16sHHIIIIIHHHHHH")
PROGRAM_HEADER = struct.Struct("<IIIIIIII")
PT_LOAD = 1
EM_RISCV = 243


class ElfError(ValueError):
    """Raised when an input ELF cannot be represented by this converter."""


@dataclass(frozen=True)
class LoadSegment:
    offset: int
    vaddr: int
    paddr: int
    filesz: int
    memsz: int
    flags: int
    align: int

    @property
    def load_addr(self) -> int:
        return self.paddr if self.paddr != 0 else self.vaddr

    def as_json(self) -> dict[str, int | str]:
        return {
            "file_offset": self.offset,
            "virtual_address": f"0x{self.vaddr:08x}",
            "physical_address": f"0x{self.paddr:08x}",
            "load_address": f"0x{self.load_addr:08x}",
            "file_size": self.filesz,
            "memory_size": self.memsz,
            "flags": self.flags,
            "alignment": self.align,
        }


def integer(text: str) -> int:
    try:
        return int(text, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid integer: {text}") from exc


def parse_elf(data: bytes) -> tuple[int, list[LoadSegment]]:
    if len(data) < ELF_HEADER.size:
        raise ElfError("file is smaller than an ELF32 header")

    (
        ident,
        _etype,
        machine,
        version,
        entry,
        phoff,
        _shoff,
        _flags,
        ehsize,
        phentsize,
        phnum,
        _shentsize,
        _shnum,
        _shstrndx,
    ) = ELF_HEADER.unpack_from(data)

    if ident[:4] != b"\x7fELF":
        raise ElfError("input is not an ELF file")
    if ident[4] != 1:
        raise ElfError("only ELF32 inputs are supported")
    if ident[5] != 1:
        raise ElfError("only little-endian ELF inputs are supported")
    if ident[6] != 1 or version != 1:
        raise ElfError("unsupported ELF version")
    if machine != EM_RISCV:
        raise ElfError(f"expected EM_RISCV ({EM_RISCV}), found {machine}")
    if ehsize != ELF_HEADER.size:
        raise ElfError(f"unexpected ELF header size {ehsize}")
    if phentsize < PROGRAM_HEADER.size:
        raise ElfError(f"program header size {phentsize} is too small")

    table_end = phoff + phentsize * phnum
    if phoff > len(data) or table_end > len(data):
        raise ElfError("program-header table lies outside the input file")

    segments: list[LoadSegment] = []
    for index in range(phnum):
        offset = phoff + index * phentsize
        (
            p_type,
            p_offset,
            p_vaddr,
            p_paddr,
            p_filesz,
            p_memsz,
            p_flags,
            p_align,
        ) = PROGRAM_HEADER.unpack_from(data, offset)
        if p_type != PT_LOAD:
            continue
        if p_filesz > p_memsz:
            raise ElfError(f"PT_LOAD[{index}] has filesz larger than memsz")
        if p_offset + p_filesz > len(data):
            raise ElfError(f"PT_LOAD[{index}] file bytes lie outside the ELF")
        segments.append(
            LoadSegment(
                offset=p_offset,
                vaddr=p_vaddr,
                paddr=p_paddr,
                filesz=p_filesz,
                memsz=p_memsz,
                flags=p_flags,
                align=p_align,
            )
        )

    if not segments:
        raise ElfError("ELF contains no PT_LOAD segments")
    return entry, segments


def load_image(
    data: bytes, segments: list[LoadSegment], base: int, size: int
) -> tuple[bytearray, int]:
    if base < 0 or base > 0xFFFF_FFFF:
        raise ElfError("base must fit in 32 bits")
    if size <= 0:
        raise ElfError("size must be positive")
    if base & 3:
        raise ElfError("base must be word aligned")
    if size & 3:
        raise ElfError("size must be a multiple of four")
    if base + size > 0x1_0000_0000:
        raise ElfError("requested memory window exceeds the 32-bit address space")

    image = bytearray(size)
    written: dict[int, tuple[int, int]] = {}

    for segment_index, segment in enumerate(segments):
        start = segment.load_addr
        end = start + segment.memsz
        if start < base or end > base + size or end < start:
            raise ElfError(
                f"PT_LOAD[{segment_index}] range 0x{start:08x}..0x{end:08x} "
                f"does not fit 0x{base:08x}..0x{base + size:08x}"
            )

        segment_bytes = data[segment.offset : segment.offset + segment.filesz]
        segment_bytes += bytes(segment.memsz - segment.filesz)
        for relative, value in enumerate(segment_bytes):
            address = start + relative
            image_index = address - base
            if image_index in written and image[image_index] != value:
                previous_segment, previous_value = written[image_index]
                raise ElfError(
                    f"conflicting PT_LOAD overlap at 0x{address:08x}: "
                    f"segment {previous_segment} wrote 0x{previous_value:02x}, "
                    f"segment {segment_index} writes 0x{value:02x}"
                )
            image[image_index] = value
            written[image_index] = (segment_index, value)

    return image, len(written)


def sparse_word_hex(image: bytearray) -> tuple[str, int]:
    lines: list[str] = []
    previous_index: int | None = None
    nonzero_words = 0
    for index in range(len(image) // 4):
        word = int.from_bytes(image[index * 4 : index * 4 + 4], "little")
        if word == 0:
            continue
        if previous_index is None or index != previous_index + 1:
            lines.append(f"@{index:08x}")
        lines.append(f"{word:08x}")
        previous_index = index
        nonzero_words += 1
    return "\n".join(lines) + ("\n" if lines else ""), nonzero_words


def convert(
    elf_path: Path,
    output_path: Path,
    metadata_path: Path | None,
    base: int,
    size: int,
) -> dict[str, object]:
    data = elf_path.read_bytes()
    entry, segments = parse_elf(data)
    if not base <= entry < base + size:
        raise ElfError(
            f"entry point 0x{entry:08x} lies outside the requested memory window"
        )

    image, initialized_bytes = load_image(data, segments, base, size)
    hex_text, nonzero_words = sparse_word_hex(image)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(hex_text, encoding="ascii")

    metadata: dict[str, object] = {
        "format": "rv32-sparse-word-hex-v1",
        "elf": str(elf_path.resolve()),
        "output": str(output_path.resolve()),
        "entry": f"0x{entry:08x}",
        "base": f"0x{base:08x}",
        "size_bytes": size,
        "initialized_bytes": initialized_bytes,
        "nonzero_words": nonzero_words,
        "segments": [segment.as_json() for segment in segments],
    }
    if metadata_path is not None:
        metadata_path.parent.mkdir(parents=True, exist_ok=True)
        metadata_path.write_text(
            json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    return metadata


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path, help="input RISC-V ELF32 executable")
    parser.add_argument("-o", "--output", required=True, type=Path)
    parser.add_argument("--base", type=integer, default=0x8000_0000)
    parser.add_argument("--size", type=integer, default=0x4000)
    parser.add_argument("--metadata", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        metadata = convert(
            args.elf, args.output, args.metadata, args.base, args.size
        )
    except (OSError, ElfError) as exc:
        print(f"elf_to_mem.py: error: {exc}", file=sys.stderr)
        return 2

    print(
        "converted "
        f"{args.elf} -> {args.output} "
        f"({metadata['nonzero_words']} nonzero words, "
        f"entry {metadata['entry']})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
