#!/usr/bin/env python3
"""follow-through :: SessionEnd — take this session out of the shared registry."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ft  # noqa: E402
import lanes  # noqa: E402


def main():
    payload = ft.read_payload()
    cwd = payload.get("cwd") or os.getcwd()
    sid = payload.get("session_id") or ""
    if sid and lanes.common_dir(cwd):
        lanes.remove(cwd, sid)


if __name__ == "__main__":
    ft.run(main)
