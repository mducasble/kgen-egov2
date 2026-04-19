"""Run the MCAP builder locally against a folder of session artifacts.

Usage:
    python3 local_test.py <session_dir> <session_code> [<output.mcap>]

The script auto-discovers video MP4s in ``session_dir``:
  * A consolidated ``video_<code>.mp4`` takes priority (single-source).
  * Otherwise every ``chunk_<NNN>_<code>.mp4`` is picked up in index
    order — identical to what the Lambda does in production.
Pass ``--no-video`` to skip video embedding (fast iteration on
IMU/metadata/metrics only).

Example:
    python3 local_test.py ~/Downloads/qB7nX3_mL9Vz qB7nX3_mL9Vz
"""

from __future__ import annotations

import argparse
import logging
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lambda"))

from mcap_builder import build_mcap  # noqa: E402


def _collect_video_paths(session_dir: Path, session_code: str) -> list[Path]:
    consolidated = session_dir / f"video_{session_code}.mp4"
    if consolidated.exists():
        return [consolidated]

    chunk_re = re.compile(rf"^chunk_(\d+)_{re.escape(session_code)}\.mp4$")
    found: list[tuple[int, Path]] = []
    for path in session_dir.iterdir():
        m = chunk_re.match(path.name)
        if m is not None:
            found.append((int(m.group(1)), path))
    found.sort(key=lambda t: t[0])
    return [p for _, p in found]


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a single-session MCAP locally.")
    parser.add_argument("session_dir", type=Path, help="Folder containing the session artifacts.")
    parser.add_argument("session_code", help="Session code (matches the filename suffixes).")
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=None,
        help="Output .mcap path. Defaults to <session_dir>/<code>.mcap.",
    )
    parser.add_argument("--no-video", action="store_true", help="Skip video embedding.")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
    )

    if not args.session_dir.is_dir():
        print(f"ERROR: {args.session_dir} is not a directory", file=sys.stderr)
        return 1

    video_paths = [] if args.no_video else _collect_video_paths(args.session_dir, args.session_code)
    if not args.no_video and not video_paths:
        print("(no MP4s found — video channel will be skipped)")

    output = args.output or (args.session_dir / f"{args.session_code}.mcap")
    stats = build_mcap(
        session_dir=args.session_dir,
        session_code=args.session_code,
        output_path=output,
        video_paths=video_paths,
    )

    print()
    print(f"wrote {output} ({output.stat().st_size} bytes)")
    print(f"  total messages: {stats.total_messages}")
    print(f"  video embedded: {stats.video_embedded}")
    for topic, count in stats.channel_counts.items():
        print(f"    {topic:32s} {count}")
    if stats.skipped_channels:
        print(f"  skipped channels: {', '.join(stats.skipped_channels)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
