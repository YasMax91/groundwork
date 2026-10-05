#!/usr/bin/env python3
"""follow-through :: SessionStart — tell the agent the formats the Stop gate expects.

A gate the agent first meets as a refusal costs a round trip per rule. Six lines up front cost almost
nothing and let the first draft pass.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ft  # noqa: E402

RULES = """follow-through is active. The turn is checked before it ends:
- Do not end a turn on an announcement ("Беру X", "Next I'll…") — do the step, or say what you wait for.
- Questions to the user go through AskUserQuestion, not prose.
- Do it yourself when you have the access (browser tool, shell, seeded local login). If you cannot, say why on the same line.
- After changing screens (views, CSS, JS, components), take a browser/simulator screenshot before claiming it works — or write "UI не проверен: <screens>".
- Any text the user will forward (client, BA, manager) goes in a ```outbound <addressee> fence: no «—», no lists, no field names or ids, no mention of AI, at most 900 characters, every "cannot/нельзя" about a system sourced with a link. Fence options: lists, max=<n>, ids-ok, ai-ok.
- Destructive commands (migrate:fresh on a non-testing DB, discarding uncommitted git changes, removing Docker volumes, killing workers, editing gate configs) open a permission prompt."""


def main():
    payload = ft.read_payload()
    print(json.dumps({
        "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": RULES}
    }, ensure_ascii=False))


if __name__ == "__main__":
    ft.run(main)
