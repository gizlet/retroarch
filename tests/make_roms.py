"""Writes tiny synthetic ROMs for the smoke tests: each one only sets up the
CPU and loops forever. They are generated here from a few opcodes, carry no
third-party code, logos or art, and exist so RetroArch can load every core
with real content. Usage: make_roms.py OUTPUT_DIR"""

from pathlib import Path
import sys


def nes() -> bytes:
    # iNES, mapper 0: one 16 KiB PRG bank at $C000 and one blank CHR bank.
    prg = bytearray(0x4000)
    prg[0:5] = bytes([0x78, 0xD8, 0x4C, 0x02, 0xC0])  # sei; cld; jmp $C002
    prg[0x3FFA:0x4000] = bytes([0x00, 0xC0] * 3)  # NMI, RESET and IRQ at $C000
    return b"NES\x1a" + bytes([1, 1, 0, 0]) + bytes(8) + bytes(prg) + bytes(0x2000)


def gb() -> bytes:
    # 32 KiB, no mapper. The header's logo area is left blank.
    rom = bytearray(0x8000)
    rom[0x100:0x104] = bytes([0x00, 0xC3, 0x50, 0x01])  # nop; jp $0150
    rom[0x134:0x144] = b"GIZLET TEST".ljust(16, b"\0")
    rom[0x150:0x153] = bytes([0xF3, 0x18, 0xFE])  # di; jr -2
    check = 0
    for byte in rom[0x134:0x14D]:
        check = (check - byte - 1) & 0xFF
    rom[0x14D] = check
    return bytes(rom)


def gba() -> bytes:
    # Branches past the header to an endless loop. The logo area is blank.
    rom = bytearray(0x400)
    rom[0:4] = (0xEA00002E).to_bytes(4, "little")  # b 0xC0
    rom[0xA0:0xAC] = b"GIZLETTEST\0\0"
    rom[0xB2] = 0x96
    rom[0xBD] = (-(sum(rom[0xA0:0xBD]) + 0x19)) & 0xFF
    rom[0xC0:0xC4] = (0xEAFFFFFE).to_bytes(4, "little")  # b .
    return bytes(rom)


def snes() -> bytes:
    # 32 KiB LoROM with its header at $7FC0 and the reset vector at $8000.
    rom = bytearray(0x8000)
    rom[0:3] = bytes([0x78, 0x80, 0xFE])  # sei; bra -2
    rom[0x7FC0:0x7FD5] = b"GIZLET TEST".ljust(21)
    rom[0x7FD5] = 0x20  # LoROM, slow
    rom[0x7FD7] = 0x05  # 32 KiB, the file's size
    check = (sum(rom) + 0x1FE) & 0xFFFF
    rom[0x7FDC:0x7FDE] = (check ^ 0xFFFF).to_bytes(2, "little")
    rom[0x7FDE:0x7FE0] = check.to_bytes(2, "little")
    rom[0x7FFC:0x7FFE] = (0x8000).to_bytes(2, "little")
    return bytes(rom)


def pce() -> bytes:
    # 32 KiB HuCard: bank 0 is at $E000 on reset, with the vectors at its end.
    rom = bytearray(0x8000)
    rom[0:4] = bytes([0x78, 0xD4, 0x80, 0xFE])  # sei; csh; bra -2
    rom[0x1FF6:0x2000] = bytes([0x00, 0xE0] * 5)
    return bytes(rom)


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, data in {"test.nes": nes(), "test.gb": gb(), "test.gba": gba(), "test.sfc": snes(), "test.pce": pce()}.items():
        (out / name).write_bytes(data)


if __name__ == "__main__":
    main()
