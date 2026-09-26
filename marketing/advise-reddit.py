#!/usr/bin/env python3
"""Scores docs/launch/reddit-drafts.json with the Reddit Post Advisor.

Run from ~/Documents/Projects/reddit_model with its virtualenv:
  .venv/bin/python ~/Documents/Projects/ambient-notification/marketing/advise-reddit.py
"""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from reddit_model.advisor import DraftInput, evaluate_advisor
from reddit_model.advisor_ui import load_profiles
from reddit_model.revision import build_revision_plan

DRAFTS = Path(__file__).resolve().parent.parent / "docs" / "launch" / "reddit-drafts.json"
profiles = load_profiles(Path("data/processed/community_profiles.json"))
drafts = json.loads(DRAFTS.read_text())["drafts"]
report = []
for d in drafts:
    key = d["community"].casefold().removeprefix("r/")
    draft = DraftInput(community=d["community"], title=d["title"], body=d["body"],
                       planned_at=datetime.now(timezone.utc), url="", flair=d.get("flair"))
    advice = evaluate_advisor(draft, profile=profiles.get(key)).to_dict()
    plan = build_revision_plan(draft, profile=profiles.get(key)).to_dict()
    report.append({"n": d["n"], "community": d["community"], "advice": advice, "revision": plan})
out = DRAFTS.with_name("reddit-advice.json")
out.write_text(json.dumps(report, indent=2, default=str))
print("wrote", out)
