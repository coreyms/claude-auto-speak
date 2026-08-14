#!/usr/bin/env python3
"""One mouth, many Claudes: speak queued turns strictly one at a time.

The problem: a user-scoped Stop hook fires in every concurrent session, so five
or seven Claudes finishing at once all called `say` at once and talked over each
other. Serializing inside the hook itself does not work - the waiting hook would
hold its session's Stop hook open for the whole queue, and the hook's 300s
timeout would eventually drop the very message the queue exists to preserve.

So the hook does not speak. It drops the text in a spool directory and spawns
this drainer **in a new session** (`start_new_session=True`), which escapes the
process group Claude Code SIGKILLs when the hook returns. The hook exits in
milliseconds; this process keeps talking after it is gone.

    auto-speak.sh  ->  /tmp/auto-speak-queue/<epoch>.<pid>.speak  ->  drainer -> say

Exactly one drainer speaks at a time, enforced by an atomically-taken lock file
whose holder is verified alive (a SIGKILLed drainer leaves a stale lock, and a
stale lock nobody can steal would silence the machine permanently). Items are
spoken oldest first, so speech order matches the order the turns finished.

Re-checked per item, at the moment of speaking rather than when the turn ended:

- the global mute flag - purges the whole backlog, because muting means silence
  now, not "silence after the queue drains"
- the meeting guard - a call that started while you were queued drops the item
- `killall say` - kills the current utterance AND purges the rest, so one
  command stops a backlog instead of just advancing it
- staleness - optional, off by default; a queued turn is spoken however late it
  arrives unless QUEUE_MAX_STALE says otherwise

Run it by hand to drain the spool in the foreground (diagnostics); it exits
straight away if a drainer is already speaking:
    python3 speak_queue.py
"""

import os
import subprocess
import sys
import time
from pathlib import Path

QUEUE_DIR = Path("/tmp/auto-speak-queue")
LOCK_FILE = Path("/tmp/auto-speak-speaking.lock")
LOG = Path("/tmp/auto-speak-queue.log")
LAST = Path("/tmp/auto-speak-last.txt")
SKIP = Path("/tmp/auto-speak-skip.txt")

# A lock older than this is assumed abandoned even if some unrelated process
# inherited the recorded pid. Longer than any plausible single utterance.
LOCK_MAX_AGE = 600
# After the spool empties, keep the lock this long and rescan: a hook that
# enqueued while we were finishing would otherwise find the lock held, exit,
# and leave its item sitting until the next turn.
DRAIN_GRACE = 2.0
POLL = 0.25
LOG_MAX_LINES = 500

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import mic_in_use
except Exception:  # guard unavailable -> fail open, same as the hook
    mic_in_use = None


def log(message: str) -> None:
    try:
        stamp = time.strftime("%Y-%m-%d %H:%M:%S")
        with LOG.open("a") as handle:
            handle.write(f"{stamp} pid={os.getpid()} {message}\n")
        lines = LOG.read_text(errors="replace").splitlines()
        if len(lines) > LOG_MAX_LINES * 2:
            LOG.write_text("\n".join(lines[-LOG_MAX_LINES:]) + "\n")
    except Exception:
        pass


def note_skip(message: str) -> None:
    """Mirror the hook's skip log so one file explains every silent turn."""
    try:
        stamp = time.strftime("%Y-%m-%d %H:%M:%S")
        SKIP.write_text(f"{stamp} queue skipped: {message}\n")
    except Exception:
        pass


# --- the speaking lock ---------------------------------------------------


def _lock_holder() -> int | None:
    try:
        return int(LOCK_FILE.read_text().strip())
    except Exception:
        return None


def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:  # someone else's process, but it exists
        return True
    except Exception:
        return True


def acquire_lock() -> bool:
    """True if we now own the mouth. False means another drainer has it.

    Taken by hardlinking a file that already contains our pid: `os.link` fails
    if the target exists, and the content is complete before the name appears.
    Two-step locks (create, then write the pid) are not safe here - a rival
    drainer that reads the lock in between sees no owner, concludes it was
    abandoned, steals it, and both of them talk at once. That is not
    theoretical; it is what the first version of this file did.
    """
    staging = LOCK_FILE.with_name(f"{LOCK_FILE.name}.{os.getpid()}.tmp")
    try:
        staging.write_text(f"{os.getpid()}\n")
    except Exception as exc:
        log(f"lock staging failed: {exc}")
        return False

    try:
        for attempt in range(2):
            try:
                os.link(staging, LOCK_FILE)
                return True
            except FileExistsError:
                holder = _lock_holder()
                try:
                    age = time.time() - LOCK_FILE.stat().st_mtime
                except Exception:
                    age = 0.0

                if holder is None:
                    # Should not happen now that the lock is atomic. Treat an
                    # unreadable lock as held unless it stays that way - never
                    # race to steal, since the cost is the double-talk this
                    # whole file exists to prevent.
                    if attempt == 0:
                        time.sleep(POLL)
                        continue
                    log("lock unreadable twice - leaving it alone")
                    return False

                if _alive(holder) and age < LOCK_MAX_AGE:
                    return False

                log(f"stealing abandoned lock (holder={holder}, age={int(age)}s)")
                try:
                    LOCK_FILE.unlink(missing_ok=True)
                except Exception:
                    return False
            except Exception as exc:
                log(f"lock error: {exc}")
                return False
        return False
    finally:
        staging.unlink(missing_ok=True)


def release_lock() -> None:
    if _lock_holder() == os.getpid():
        LOCK_FILE.unlink(missing_ok=True)


# --- the spool -----------------------------------------------------------


def items() -> list[Path]:
    """Queued items, oldest first (names begin with a fixed-width epoch)."""
    try:
        return sorted(QUEUE_DIR.glob("*.speak"))
    except Exception:
        return []


def purge(reason: str) -> None:
    dropped = 0
    for item in items():
        item.unlink(missing_ok=True)
        dropped += 1
    if dropped:
        log(f"purged {dropped} queued item(s): {reason}")


def parse(item: Path) -> tuple[dict, str] | None:
    """Split an item into its key=value header and the text to speak."""
    try:
        raw = item.read_text(errors="replace")
    except Exception:
        return None
    head, _, body = raw.partition("\n\n")
    fields = {}
    for line in head.splitlines():
        key, sep, value = line.partition("=")
        if sep:
            fields[key.strip()] = value.strip()
    body = body.strip()
    return (fields, body) if body else None


def muted() -> bool:
    return (Path.home() / ".claude" / "auto-speak-mute").exists()


def mic_live(fields: dict) -> list[str]:
    if fields.get("guard") != "mic" or mic_in_use is None:
        return []
    try:
        return mic_in_use.live_devices(
            mic_in_use.ignored_patterns(fields.get("mic_ignore", ""))
        )
    except Exception:
        return []  # fail open, exactly like the hook


# --- speaking ------------------------------------------------------------


def speak(text: str, fields: dict) -> bool:
    """Speak one item. False means we were interrupted and should stop entirely."""
    rate = fields.get("rate") or "210"
    voice = fields.get("voice") or ""
    timbre = fields.get("timbre") or ""

    if timbre:
        text = f"[[pbas {timbre}]] {text}"
    if text.startswith("-"):
        text = f" {text}"  # keep `say` from reading it as a flag

    for attempt_voice in ([voice] if voice else []) + [""]:
        command = ["say", "-r", str(rate)]
        if attempt_voice:
            command += ["-v", attempt_voice]
        command.append(text)
        try:
            code = subprocess.run(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            ).returncode
        except FileNotFoundError:
            log("`say` not found - nothing can be spoken")
            return False

        if code == 0:
            return True
        if code < 0:
            # Killed by a signal: `killall say` means "stop talking", not
            # "skip to the next one".
            log(f"say killed by signal {-code} - stopping")
            return False
        log(f"say exited {code}"
            f"{f' with voice {attempt_voice}' if attempt_voice else ''}")
    return True  # voice trouble, not an interruption: keep draining


def record_spoken(fields: dict, text: str) -> None:
    try:
        stamp = time.strftime("%Y-%m-%d %H:%M:%S")
        LAST.write_text(
            f"{stamp} session={fields.get('session', '?')} "
            f"cwd={fields.get('cwd', '?')}\n{text}\n"
        )
    except Exception:
        pass


def announce(fields: dict, last_label: str | None) -> str:
    """Name the project when the voice switches sessions mid-drain.

    With several Claudes queued behind each other, consecutive utterances come
    from different work - saying which one is talking is the difference between
    a queue and a monologue.
    """
    mode = fields.get("announce", "auto")
    label = fields.get("label", "")
    if not label or mode == "off":
        return ""
    if mode == "always" or (last_label is not None and label != last_label):
        return f"From {label}: "
    return ""


def drain() -> None:
    last_label = None
    idle_since = None

    while True:
        queued = items()
        if not queued:
            if idle_since is None:
                idle_since = time.monotonic()
            elif time.monotonic() - idle_since >= DRAIN_GRACE:
                return
            time.sleep(POLL)
            continue
        idle_since = None

        item = queued[0]
        parsed = parse(item)
        item.unlink(missing_ok=True)
        if not parsed:
            continue
        fields, text = parsed

        if muted():
            note_skip("muted while queued")
            purge("muted")
            return

        live = mic_live(fields)
        if live:
            note_skip(f"microphone in use while queued ({', '.join(live)})")
            log(f"dropped {item.name}: mic in use ({', '.join(live)})")
            continue

        try:
            waited = time.time() - float(fields.get("epoch", 0))
        except ValueError:
            waited = 0
        try:
            max_stale = float(fields.get("stale", 0))
        except ValueError:
            max_stale = 0
        if max_stale > 0 and waited > max_stale:
            note_skip(f"queued {int(waited)}s ago, older than QUEUE_MAX_STALE")
            log(f"dropped {item.name}: stale by {int(waited - max_stale)}s")
            continue

        prefix = announce(fields, last_label)
        log(f"speaking {item.name} (waited {int(waited)}s, "
            f"{len(queued) - 1} behind it)")
        record_spoken(fields, prefix + text)
        if not speak(prefix + text, fields):
            purge("interrupted")
            return
        last_label = fields.get("label", "")


def main() -> int:
    QUEUE_DIR.mkdir(parents=True, exist_ok=True)
    if not acquire_lock():
        # Another drainer owns the mouth; it will pick up whatever we queued.
        return 0
    try:
        drain()
    finally:
        release_lock()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        release_lock()
        sys.exit(0)
    except Exception as exc:
        log(f"fatal: {exc}")
        release_lock()
        sys.exit(1)
