#!/usr/bin/env python3
"""Is any audio INPUT device live right now?

Used by auto-speak.sh as a meeting guard: if the microphone is captured by
anything (Teams, Zoom, Meet in a browser, a Slack huddle, dictation, a
recording), the turn is not spoken aloud so Claude never talks over you.

Talks to CoreAudio directly through ctypes - no compiler, no cached binary,
no TCC/privacy permission, works on Intel and Apple Silicon. Reads
kAudioDevicePropertyDeviceIsRunningSomewhere, the same flag that drives the
orange mic dot in the menu bar.

Output contract (stdout, parsed by the shell - keep it stable):
    IN_USE\t<device names, comma separated>
    IDLE
Anything else, or a crash, means "undetermined" and the caller speaks anyway
(fail open: a missed mute is better than silently losing all speech).

Only INPUT devices are considered, so `say` itself - which is output - can
never trip the guard.

    python3 mic_in_use.py            # IN_USE <names> | IDLE
    python3 mic_in_use.py --list     # every input device + state (diagnostics)

Devices whose name contains any comma-separated substring in
AUTO_SPEAK_MIC_IGNORE (case insensitive) are ignored - the escape hatch for a
virtual/loopback driver that reports itself as permanently running.
"""

import ctypes
import os
import sys

# --- CoreAudio constants -------------------------------------------------
SYSTEM_OBJECT = 1


def _fourcc(code: str) -> int:
    return int.from_bytes(code.encode(), "big")


PROP_DEVICES = _fourcc("dev#")  # kAudioHardwarePropertyDevices
PROP_STREAMS = _fourcc("stm#")  # kAudioDevicePropertyStreams
PROP_RUNNING = _fourcc("gone")  # kAudioDevicePropertyDeviceIsRunningSomewhere
PROP_NAME = _fourcc("lnam")  # kAudioObjectPropertyName
SCOPE_GLOBAL = _fourcc("glob")
SCOPE_INPUT = _fourcc("inpt")
ELEMENT_MAIN = 0
UTF8 = 0x08000100  # kCFStringEncodingUTF8


class _Address(ctypes.Structure):
    """AudioObjectPropertyAddress"""

    _fields_ = [
        ("selector", ctypes.c_uint32),
        ("scope", ctypes.c_uint32),
        ("element", ctypes.c_uint32),
    ]


_FRAMEWORKS = "/System/Library/Frameworks"
core_audio = ctypes.cdll.LoadLibrary(f"{_FRAMEWORKS}/CoreAudio.framework/CoreAudio")
core_foundation = ctypes.cdll.LoadLibrary(
    f"{_FRAMEWORKS}/CoreFoundation.framework/CoreFoundation"
)
core_foundation.CFStringGetCStringPtr.restype = ctypes.c_char_p


def _property_size(obj: int, selector: int, scope: int) -> int:
    """Byte size of a property, or 0 if it does not exist on this object."""
    address = _Address(selector, scope, ELEMENT_MAIN)
    size = ctypes.c_uint32(0)
    status = core_audio.AudioObjectGetPropertyDataSize(
        ctypes.c_uint32(obj), ctypes.byref(address), 0, None, ctypes.byref(size)
    )
    return size.value if status == 0 else 0


def input_devices() -> list[int]:
    """Every audio device that has at least one input stream."""
    total = _property_size(SYSTEM_OBJECT, PROP_DEVICES, SCOPE_GLOBAL)
    if not total:
        return []

    ids = (ctypes.c_uint32 * (total // ctypes.sizeof(ctypes.c_uint32)))()
    size = ctypes.c_uint32(total)
    address = _Address(PROP_DEVICES, SCOPE_GLOBAL, ELEMENT_MAIN)
    status = core_audio.AudioObjectGetPropertyData(
        ctypes.c_uint32(SYSTEM_OBJECT),
        ctypes.byref(address),
        0,
        None,
        ctypes.byref(size),
        ctypes.byref(ids),
    )
    if status != 0:
        return []
    return [d for d in ids if _property_size(d, PROP_STREAMS, SCOPE_INPUT) > 0]


def is_running(device: int) -> bool:
    """True when some process is actively using this device."""
    address = _Address(PROP_RUNNING, SCOPE_GLOBAL, ELEMENT_MAIN)
    value = ctypes.c_uint32(0)
    size = ctypes.c_uint32(ctypes.sizeof(value))
    status = core_audio.AudioObjectGetPropertyData(
        ctypes.c_uint32(device),
        ctypes.byref(address),
        0,
        None,
        ctypes.byref(size),
        ctypes.byref(value),
    )
    return status == 0 and value.value != 0


def device_name(device: int) -> str:
    address = _Address(PROP_NAME, SCOPE_GLOBAL, ELEMENT_MAIN)
    cf_string = ctypes.c_void_p(0)
    size = ctypes.c_uint32(ctypes.sizeof(cf_string))
    status = core_audio.AudioObjectGetPropertyData(
        ctypes.c_uint32(device),
        ctypes.byref(address),
        0,
        None,
        ctypes.byref(size),
        ctypes.byref(cf_string),
    )
    if status != 0 or not cf_string:
        return f"device {device}"

    pointer = core_foundation.CFStringGetCStringPtr(cf_string, UTF8)
    if pointer:
        return pointer.decode("utf-8", "replace")
    buffer = ctypes.create_string_buffer(256)
    if core_foundation.CFStringGetCString(cf_string, buffer, len(buffer), UTF8):
        return buffer.value.decode("utf-8", "replace")
    return f"device {device}"


def ignored_patterns(raw: str | None = None) -> list[str]:
    if raw is None:
        raw = os.environ.get("AUTO_SPEAK_MIC_IGNORE", "")
    return [p.strip().lower() for p in raw.split(",") if p.strip()]


def live_devices(ignore: list[str] | None = None, listing: bool = False) -> list[str]:
    """Names of the input devices currently in use, minus the ignored ones.

    Imported by speak_queue.py, which re-checks the guard at the moment it is
    about to speak rather than trusting a check made when the turn ended.
    """
    ignore = ignored_patterns() if ignore is None else ignore
    live = []
    for device in input_devices():
        name = device_name(device)
        skipped = any(pattern in name.lower() for pattern in ignore)
        running = is_running(device)
        if listing:
            print(f"{'IN-USE' if running else 'idle  '} {name}"
                  f"{'   (ignored)' if skipped else ''}")
        if running and not skipped:
            live.append(name)
    return live


def main() -> int:
    listing = "--list" in sys.argv
    live = live_devices(listing=listing)
    if not listing:
        print(f"IN_USE\t{', '.join(live)}" if live else "IDLE")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # undetermined -> caller fails open and speaks
        print(f"ERROR {exc}", file=sys.stderr)
        sys.exit(1)
