"""Build SpellDamageInfo's weapon / attack power fixture from real sources only.

foreverchanges.pro/spellbook/<class> carries, per ability and rank, Forever's
spell id and English text (and Classic's). Wowhead's tooltip service gives the
Classic English and German text per spell id. Nothing here is written by hand
or translated: a text that cannot be fetched stays missing.

    python tools/build_corpus.py tests/fixtures/attack_power_weapon_damage.json <coverage.md>

Responses are cached in tools/corpus-cache (git-ignored), so a second run is
offline; delete it to fetch again.
"""
import html
import json
import pathlib
import re
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
CACHE = HERE / "corpus-cache"
CACHE.mkdir(exist_ok=True)
CLASSES = ("warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid")


def fetch(url, name):
    path = CACHE / name
    if path.exists() and path.stat().st_size > 0:
        return path.read_text(encoding="utf-8")
    for attempt in range(3):
        r = subprocess.run(["curl", "-s", "-m", "30", "-A", "Mozilla/5.0", url], capture_output=True)
        text = r.stdout.decode("utf-8", errors="replace")
        if r.returncode == 0 and text:
            path.write_text(text, encoding="utf-8")
            time.sleep(0.25)
            return text
        time.sleep(1 + attempt)
    return ""


def abilities(cls):
    page = fetch("https://foreverchanges.pro/spellbook/" + cls, "fc_%s.html" % cls)
    chunks = []
    for m in re.finditer(r'self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)', page):
        chunks.append(json.loads(m.group(1)))
    flight = "".join(chunks)
    dec = json.JSONDecoder()
    found, seen = [], set()
    for m in re.finditer(r'\{"id":"%s-[a-z0-9-]+","name":' % cls, flight):
        try:
            obj, _ = dec.raw_decode(flight, m.start())
        except ValueError:
            continue
        if obj["id"] in seen or not isinstance(obj.get("ranks"), list):
            continue
        seen.add(obj["id"])
        found.append(obj)
    return found


def rank_text(rank, side):
    part = rank.get(side)
    return part if isinstance(part, dict) else None


# What a description does, from Forever's English. Order matters: the first
# match wins. Reductions of enemy attack power are the parser's existing
# business and are left alone.
CATEGORIES = [
    ("finisher_ap", re.compile(r"(?is)finishing move.*attack power")),
    ("ap_reduction", re.compile(r"(?i)(reduc|lower|decreas)\w*[^.]{0,60}attack power")),
    ("next_attack", re.compile(r"(?i)next (melee |ranged )?attack|increases melee damage by \d|next \d+ (melee )?(swings|attacks)")),
    ("weapon_damage", re.compile(r"(?i)weapon damage|normal damage|\d+% (weapon |normal )?damage|ranged damage|in addition to (your|the) normal")),
    ("ap_buff", re.compile(r"(?i)(increas|rais|improv)\w*[^.]{0,80}attack power[^.]{0,80}? by \d|attack power by \d+[^.]{0,40}(for|while)")),
    ("imbue_seal", re.compile(r"(?i)imbue|seal of|each (melee )?(hit|strike|attack)|melee attacks? [^.]{0,40}(additional|extra|chance)")),
]


# Checked by hand against the coverage table: wordings the patterns above put
# in the wrong place. None drops the ability from the corpus.
OVERRIDES = {
    "Inner Fire": None,          # armour, and damage taken, not attack power
    "Windwall Totem": None,      # reduces ranged damage taken
    "Incinerate": None,          # a fire spell the parser already reads
    "Nature's Grasp": None,      # roots on being hit
    "Mongoose Bite": "weapon_damage",
    "Lacerate": None,            # a bleed over time with a weapon part per stack
    "Holy Shield": None,         # damage on each block, not on the paladin's hits
}


def categorise(text, name=None):
    if name in OVERRIDES:
        return OVERRIDES[name]
    for name, rx in CATEGORIES:
        if rx.search(text or ""):
            return name
    return None


def description(tooltip_json):
    try:
        d = json.loads(tooltip_json)
    except ValueError:
        return None, None
    tip = d.get("tooltip") or ""
    parts = re.findall(r'<div class="q">(.*?)</div>', tip, re.S)
    if not parts:
        return d.get("name"), None
    text = re.sub(r"<br\s*/?>", "\n", parts[-1])
    text = html.unescape(re.sub(r"<[^>]+>", "", text)).strip()
    return d.get("name"), text


def main(out_path, coverage_path):
    rows, coverage = [], []
    for cls in CLASSES:
        for ab in abilities(cls):
            ranks = ab["ranks"]
            last = rank_text(ranks[-1], "forever") or rank_text(ranks[-1], "classic") or {}
            cat = categorise(last.get("text"), ab["name"])
            coverage.append((cls, ab["name"], ab.get("status"), len(ranks), cat or "-", (last.get("text") or "").replace("\n", " ")[:110]))
            if cat in (None, "ap_reduction"):
                continue
            for rank in ranks:
                fv, cl = rank_text(rank, "forever"), rank_text(rank, "classic")
                sid = (fv or cl or {}).get("spell_id")
                if not sid:
                    continue
                en_name, en = description(fetch("https://nether.wowhead.com/tooltip/spell/%d?dataEnv=4&locale=0" % sid, "wh_%d_en.json" % sid))
                de_name, de = description(fetch("https://nether.wowhead.com/tooltip/spell/%d?dataEnv=4&locale=3" % sid, "wh_%d_de.json" % sid))
                rows.append({
                    "id": sid, "namespace": "wowhead-classic",
                    "source": "wowhead classic tooltip (dataEnv=4); forever text from foreverchanges.pro",
                    "expected_name": ab["name"], "class": cls, "rank": rank.get("rank"),
                    "category": cat, "forever_status": ab.get("status"),
                    "forever_en_description": (fv or {}).get("text"),
                    "en_name": en_name, "en_description": en,
                    "de_name": de_name, "de_description": de,
                })
    pathlib.Path(out_path).write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    lines = ["| class | ability | forever | ranks | category | Forever text (last rank) |", "|---|---|---|---|---|---|"]
    lines += ["| %s | %s | %s | %d | %s | %s |" % c for c in coverage]
    pathlib.Path(coverage_path).write_text("\n".join(lines) + "\n", encoding="utf-8")
    missing_de = sum(1 for r in rows if not r["de_description"])
    print("abilities:", len(coverage), " fixture rows:", len(rows), " without German:", missing_de)
    from collections import Counter
    print(Counter(r["category"] for r in rows))
    print(Counter(c[0] for c in coverage if c[4] not in ("-", "ap_reduction")))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
