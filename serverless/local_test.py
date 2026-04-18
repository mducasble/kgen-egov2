"""Run the MCAP builder locally against a folder of session JSONs. No AWS needed.

Usage:
    python3 local_test.py <session_dir> <session_code> [<output.mcap>]

Example:
    python3 local_test.py ~/Downloads/qB7nX3_mL9Vz qB7nX3_mL9Vz
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lambda"))

from mcap_builder import build_mcap  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a single-session MCAP locally.")
    parser.add_argument("session_dir", type=Path, help="Folder containing the session JSONs.")
    parser.add_argument("session_code", help="12-char session code (or any suffix you used).")
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=None,
        help="Output .mcap path. Defaults to <session_dir>/<code>.mcap.",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
    )

    if not args.session_dir.is_dir():
        print(f"ERROR: {args.session_dir} is not a directory", file=sys.stderr)
        return 1

    output = args.output or (args.session_dir / f"{args.session_code}.mcap")
    stats = build_mcap(
        session_dir=args.session_dir,
        session_code=args.session_code,
        output_path=output,
    )

    print()
    print(f"✓ wrote {output} ({output.stat().st_size} bytes)")
    print(f"  total messages: {stats.total_messages}")
    for topic, count in stats.channel_counts.items():
        print(f"    {topic:28s} {count}")
    if stats.skipped_channels:
        print(f"  skipped channels: {', '.join(stats.skipped_channels)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
