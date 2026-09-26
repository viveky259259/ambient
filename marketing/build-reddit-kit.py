#!/usr/bin/env python3
"""Builds docs/launch/reddit-kit.html and docs/launch/reddit-events.json from reddit-drafts.json.

One post per day, in the order and at the time set in the drafts' "schedule".
"""
import html
import json
import urllib.parse
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
d = json.loads((ROOT / "docs/launch/reddit-drafts.json").read_text())
by = {p["n"]: p for p in d["drafts"]}
start = date.fromisoformat(d["schedule"]["start"])
ROUTES = {"post": "Text post", "megathread_comment": "Comment in the current self-promotion megathread",
          "showcase_sunday": "Showcase Sunday"}


def links(p):
    sub = p["community"].removeprefix("r/")
    if p["route"] == "megathread_comment":
        return (f"https://www.reddit.com/r/{sub}/search/?q=megathread&sort=new&restrict_sr=1",
                f"https://old.reddit.com/r/{sub}/search?q=megathread&sort=new&restrict_sr=on")
    q = urllib.parse.urlencode({"title": p["title"], "text": p["body"]}, quote_via=urllib.parse.quote)
    return (f"https://www.reddit.com/r/{sub}/submit?type=TEXT&{q}",
            f"https://old.reddit.com/r/{sub}/submit?selftext=true&{q}")


events, cards = [], []
for i, n in enumerate(d["schedule"]["order"]):
    p = by[n]
    day = start + timedelta(days=i)
    sub = p["community"].removeprefix("r/")
    new_url, old_url = links(p)
    rules = f"https://www.reddit.com/r/{sub}/about/rules"
    route = ROUTES[p["route"]]
    extra = " · ".join(x for x in [f"flair: {p['flair']}" if p.get("flair") else "", p.get("note", "")] if x)
    label = day.strftime("%a %b %-d") + ", 6:30 PM IST (9 AM ET)"
    action = "Find the megathread" if p["route"] == "megathread_comment" else "Open the prefilled post"
    events.append({
        "day": day.isoformat(), "n": n, "community": p["community"],
        "summary": f"Post Ambient on {p['community']} ({i + 1}/19)",
        "description": (f"<b>{html.escape(p['title'])}</b><br><br>"
                        f"1. <a href=\"{html.escape(rules)}\">Check the rules</a> (self-promotion allowed?)<br>"
                        f"2. <a href=\"{html.escape(new_url)}\">{action}</a> · <a href=\"{html.escape(old_url)}\">old Reddit</a><br>"
                        f"3. {html.escape(route)}{(' · ' + html.escape(extra)) if extra else ''}<br>"
                        f"4. Submit, then reply to comments in the first hour.<br><br>"
                        f"Full text: docs/launch/reddit-kit.html in the Ambient repo."),
    })
    cards.append(f"""
<article class="post">
  <header>
    <label class="done"><input type="checkbox" data-n="{n}"> Posted</label>
    <span class="slot">{label}</span>
    <h2>{i + 1}. {html.escape(p['community'])}</h2>
    <span class="meta">{html.escape(route)}{(' · ' + html.escape(extra)) if extra else ''}</span>
  </header>
  <div class="actions">
    <a class="btn primary" href="{html.escape(new_url)}" target="_blank" rel="noopener">{action}</a>
    <a class="btn" href="{html.escape(old_url)}" target="_blank" rel="noopener">Old Reddit</a>
    <a class="btn" href="{html.escape(rules)}" target="_blank" rel="noopener">Rules</a>
    <button class="btn" data-copy="t{n}">Copy title</button>
    <button class="btn" data-copy="b{n}">Copy body</button>
  </div>
  <h3 id="t{n}">{html.escape(p['title'])}</h3>
  <pre id="b{n}">{html.escape(p['body'])}</pre>
</article>""")

template = (ROOT / "marketing/reddit-kit.template.html").read_text()
(ROOT / "docs/launch/reddit-kit.html").write_text(template.replace("{{CARDS}}", "".join(cards)))
(ROOT / "docs/launch/reddit-events.json").write_text(json.dumps(events, indent=2, ensure_ascii=False))
print(f"{len(events)} days: {events[0]['day']} → {events[-1]['day']}")


# MARK: - Calendar file: one 15-minute event a day with the links and two reminders.

def ics_text(s):
    return s.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def fold(line):
    raw = line.encode("utf-8")
    out, chunk = [], b""
    for ch in line:
        b = ch.encode("utf-8")
        if len(chunk) + len(b) > (75 if not out else 74):
            out.append(chunk.decode("utf-8"))
            chunk = b""
        chunk += b
    out.append(chunk.decode("utf-8"))
    return "\r\n ".join(out)


lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//yaml.cafe//Ambient launch//EN", "CALSCALE:GREGORIAN",
         "BEGIN:VTIMEZONE", "TZID:Asia/Kolkata", "BEGIN:STANDARD", "DTSTART:19700101T000000",
         "TZOFFSETFROM:+0530", "TZOFFSETTO:+0530", "TZNAME:IST", "END:STANDARD", "END:VTIMEZONE"]
for i, n in enumerate(d["schedule"]["order"]):
    p = by[n]
    day = (start + timedelta(days=i)).strftime("%Y%m%d")
    sub = p["community"].removeprefix("r/")
    new_url, _ = links(p)
    desc = (f"{p['title']}\n\n1. Check the rules (self-promotion allowed?): https://www.reddit.com/r/{sub}/about/rules\n"
            f"2. {'Find the megathread' if p['route'] == 'megathread_comment' else 'Open the prefilled post'}: {new_url}\n"
            f"3. {ROUTES[p['route']]}{(' · flair: ' + p['flair']) if p.get('flair') else ''}\n"
            f"4. Submit, then reply to comments in the first hour.")
    event = ["BEGIN:VEVENT", f"UID:ambient-reddit-{day}-{sub}@yaml.cafe", "DTSTAMP:20260927T000000Z",
             f"DTSTART;TZID=Asia/Kolkata:{day}T183000", f"DTEND;TZID=Asia/Kolkata:{day}T184500",
             f"SUMMARY:{ics_text(f'Post Ambient on {p['community']} ({i + 1}/19)')}",
             f"DESCRIPTION:{ics_text(desc)}", f"URL:{new_url}", "TRANSP:TRANSPARENT"]
    for minutes in (10, 0):
        event += ["BEGIN:VALARM", "ACTION:DISPLAY", f"DESCRIPTION:{ics_text('Post Ambient on ' + p['community'])}",
                  f"TRIGGER:-PT{minutes}M", "END:VALARM"]
    event.append("END:VEVENT")
    lines += event
lines.append("END:VCALENDAR")
(ROOT / "docs/launch/reddit-schedule.ics").write_text("\r\n".join(fold(l) for l in lines) + "\r\n")
print("wrote docs/launch/reddit-schedule.ics")
