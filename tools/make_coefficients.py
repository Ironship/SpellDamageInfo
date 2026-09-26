"""Writes SpellCoefficients.lua: for every id in SpellIDs.lua, the share of spell power the client's
own spell tables give it, on WoW: Forever and on Classic Era.

    python tools/make_coefficients.py [--era-build 1.15.x.y]

The tables are wago.tools' CSVs of the client's DB2 files: SpellEffect (EffectBonusCoefficient,
BonusCoefficientFromAP, the aura, its period and the spell it triggers), SpellMisc and SpellDuration
(how long an aura lasts, so how many ticks it has) and SpellItemEnchantment (the spell a weapon imbue
casts on a hit). Forever is build 1.60.1.70009; Classic Era is the newest wow_classic_era build
wago.tools lists. They are cached in tools/db2-cache (git-ignored); delete it to fetch again.

Per spell and client:
  d   the direct part: the damage effects (school damage, health leech, mana burn), and for an aura
      that strikes back or procs (Thorns, Holy Shield, a proc trigger) what one strike or proc gets
  o   the whole over-time part: per tick x ticks (duration / period); a channel or an aura that
      casts a spell every tick (Arcane Missiles, Hellfire) counts that spell's direct share per tick
  h, ho  the same for healing
  ap  the attack power share, where a table has one (none of these ids has one in either build)
Only effects that do damage or healing are read: the other effects carry a coefficient of 1 that
means nothing. A totem, a trap and whatever else a spell summons casts its own spell, and the tables
do not say which, so such a spell is written as false: the description's number, no estimate.
Spells whose damage comes from a script or an area trigger (Forever's Blizzard, Consecration, Holy
Shock, the seals' per-hit damage) are left out, and the addon's rules stand in for them. A part of a
listed spell that comes from such a link (Forever's Flamestrike burn, Holy Nova's heal) gets none.

It also writes tests/fixtures/coefficient_rows.json, the raw rows behind the spells the tests check,
so test_coefficients.lua can work the shares out again from the client's numbers.
"""
import argparse
import csv
import json
import re
import subprocess
import sys
import time
from pathlib import Path

root = Path(__file__).resolve().parent.parent
CACHE = root / "tools" / "db2-cache"
FOREVER = "1.60.1.70009"
TABLES = ("SpellEffect", "SpellMisc", "SpellDuration", "SpellItemEnchantment", "SpellName")

# Effects and auras that carry damage or healing
DIRECT_DAMAGE = {2, 9, 62}          # school damage, health leech, power burn (Mana Burn)
DIRECT_HEAL = {10}
AURA_EFFECTS = {6, 27, 35, 65}      # apply aura, persistent area aura, party and raid area aura
PERIODIC_DAMAGE = {3, 53}           # periodic damage, periodic leech
PERIODIC_HEAL = {8}
PERIODIC_TRIGGER = 23               # casts a spell every tick
PROC_TRIGGER = 42                   # casts a spell on a proc
PER_STRIKE = {15, 43}               # damage shield (Thorns), proc damage (Holy Shield)
TRIGGER_SPELL = 64
# The two builds number some effects differently: a trap's object is 104 on Forever and 320 on Era,
# a weapon imbue 360 on Forever and 54 on Era (the report below lists the spells, to check)
SUMMONS = {28, 104, 320}
TEMP_ENCHANT = {54, 360}
CASTER = 1                          # ImplicitTarget: the caster
COMBAT_SPELL = 1                    # SpellItemEnchantment effect: casts EffectArg on a hit
# The spells in the tests: the ones the findings name, a spell learned before level 20, and one of
# each linked kind
CHECKED = (10202, 25345, 25346, 25306, 18809, 10187, 11684, 11682, 9863, 18807, 19305, 10894, 25311, 11713, 603,
           19280, 17926, 11700, 18881, 25304, 14287, 25295, 20928, 9910, 10301, 10876, 11695, 585, 2050, 139, 774,
           10463, 10438, 14305, 16356, 16353, 20920, 20424, 25316, 10318, 27801, 20116, 401502)


def fetch(table, build):
    CACHE.mkdir(exist_ok=True)
    path = CACHE / f"{table}-{build}.csv"
    if path.exists() and path.stat().st_size > 0:
        return path
    url = f"https://wago.tools/db2/{table}/csv?build={build}"
    for attempt in range(3):
        r = subprocess.run(["curl", "-s", "-f", "-m", "300", "-o", str(path), url])
        if r.returncode == 0 and path.exists() and path.stat().st_size > 0:
            return path
        time.sleep(2 + attempt)
    sys.exit(f"could not fetch {url}")


def newest_era():
    r = subprocess.run(["curl", "-s", "-f", "-m", "60", "https://wago.tools/api/builds"], capture_output=True)
    if r.returncode != 0:
        sys.exit("could not fetch https://wago.tools/api/builds; pass --era-build")
    return json.loads(r.stdout)["wow_classic_era"][0]["version"]


def rows(table, build):
    with open(fetch(table, build), encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def number(v):
    return float(v) if v not in (None, "") else 0.0


class Client:
    def __init__(self, build):
        self.build = build
        self.effects = {}
        for r in rows("SpellEffect", build):
            if r["DifficultyID"] == "0":
                self.effects.setdefault(int(r["SpellID"]), []).append(r)
        for list_ in self.effects.values():
            list_.sort(key=lambda r: int(r["EffectIndex"]))
        durations = {r["ID"]: int(r["Duration"]) for r in rows("SpellDuration", build)}
        self.duration = {}
        for r in rows("SpellMisc", build):
            if r["DifficultyID"] == "0":
                self.duration[int(r["SpellID"])] = durations.get(r["DurationIndex"], 0)
        self.enchants = {r["ID"]: r for r in rows("SpellItemEnchantment", build)}
        self.names = {int(r["ID"]): r["Name_lang"] for r in rows("SpellName", build)}

    def ticks(self, sid, period):
        d = self.duration.get(sid, 0)
        return d // period if d > 0 and period > 0 else 0

    def enchant_spells(self, e):
        """The spells a temporary weapon enchant casts on a hit, if e is such an effect."""
        ench = self.enchants.get(e["EffectMiscValue_0"])
        if not ench:
            return []
        return [int(ench[f"EffectArg_{i}"]) for i in range(3)
                if ench.get(f"Effect_{i}") == str(COMBAT_SPELL) and int(ench[f"EffectArg_{i}"] or 0) > 0]

    def parts(self, sid, depth=0):
        """{"d", "o", "h", "ho", "ap"} for what the spell does, and whether it summons something."""
        out, summons = {}, False

        def add(key, v):
            out[key] = out.get(key, 0.0) + v

        if depth > 3:
            return out, summons
        for e in self.effects.get(sid, []):
            eff, aura = int(e["Effect"]), int(e["EffectAura"])
            c, ap = number(e["EffectBonusCoefficient"]), number(e["BonusCoefficientFromAP"])
            period, trig = int(e["EffectAuraPeriod"] or 0), int(e["EffectTriggerSpell"] or 0)
            if eff in DIRECT_DAMAGE:
                add("d", c)
                if ap:
                    add("ap", ap)
            elif eff in DIRECT_HEAL:
                add("h", c)
            elif eff in AURA_EFFECTS:
                n = self.ticks(sid, period)
                if aura in PERIODIC_DAMAGE:
                    # an aura that hurts the caster (Hellfire burns the warlock) is not the spell's damage
                    if eff == 6 and e["ImplicitTarget_0"] == str(CASTER):
                        continue
                    add("o", c * n)
                    if ap:
                        add("ap", ap * n)
                elif aura in PERIODIC_HEAL:
                    add("ho", c * n)
                elif aura == PERIODIC_TRIGGER and trig:
                    sub, _ = self.parts(trig, depth + 1)
                    if "d" in sub:
                        add("o", sub["d"] * n)
                    if "h" in sub:
                        add("ho", sub["h"] * n)
                elif aura == PROC_TRIGGER and trig:
                    # the aura's own coefficient where it carries the damage (Lightning Shield on Era),
                    # the triggered spell's otherwise (Seal of Command, Seal of Light)
                    sub, _ = self.parts(trig, depth + 1)
                    if c:
                        add("d", c)
                    elif "d" in sub:
                        add("d", sub["d"])
                    if "h" in sub:
                        add("h", sub["h"])
                elif aura in PER_STRIKE:
                    add("d", c)
            elif eff == TRIGGER_SPELL and trig:
                sub, _ = self.parts(trig, depth + 1)
                for k, v in sub.items():
                    add(k, v)
            elif eff in SUMMONS:
                # a totem (a creature) or a trap (an object) casts a spell of its own, which none of
                # these tables names
                summons = True
            elif eff in TEMP_ENCHANT:
                for s in self.enchant_spells(e):
                    sub, _ = self.parts(s, depth + 1)
                    if "d" in sub:
                        add("d", sub["d"])
        return out, summons


def fmt(v):
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return s if s not in ("", "-0") else "0"


def entry(parts):
    return "{" + ",".join(f"{k}={fmt(parts[k])}" for k in ("d", "o", "h", "ho", "ap") if k in parts) + "}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--era-build", default=None)
    args = ap.parse_args()
    era_build = args.era_build or newest_era()

    ids_src = (root / "SpellIDs.lua").read_text(encoding="utf-8")
    ids = sorted({int(x) for x in re.findall(r"\d+", ids_src.split("table.concat", 1)[1])})
    clients = {"forever": Client(FOREVER), "era": Client(era_build)}

    lines = [
        "-- SpellDamageInfo: the share of spell power each spell gets, from the client's own spell tables",
        f"-- (SpellEffect.EffectBonusCoefficient) of WoW: Forever {FOREVER} and Classic Era {era_build}.",
        "-- Generated by tools/make_coefficients.py, which says how each number is worked out.",
        "-- Copyright (c) 2026 Ironship. MIT licence, see LICENSE.",
        "",
        "local _, ns = ...",
        "ns = ns or {}",
        "",
        "-- [spell id] = { d = direct damage, o = damage over time (per tick x ticks), h = direct healing,",
        "-- ho = healing over time, ap = attack power }, each a share of the bonus; false: the spell",
        "-- summons a totem or places a trap, whose own spell the tables do not name, so no estimate.",
        "-- A spell not listed has no damage or healing in the tables; the addon's rules stand in.",
        "ns.SpellCoefficients = {",
    ]
    report = {}
    for key, client in clients.items():
        lines.append(f"  {key} = {{")
        out, n_summon, n_ap, unlinked = [], 0, 0, []
        for sid in ids:
            if sid not in client.effects:
                continue
            parts, summons = client.parts(sid)
            if parts:
                out.append(f"[{sid}]={entry(parts)}")
                n_ap += "ap" in parts
            elif summons:
                out.append(f"[{sid}]=false")
                n_summon += 1
            elif any(int(e["Effect"]) in (3, 179) or int(e["EffectAura"]) in (4, 226) for e in client.effects[sid]):
                unlinked.append(sid)
        per_line = 8
        for i in range(0, len(out), per_line):
            lines.append("    " + ",".join(out[i:i + per_line]) + ",")
        lines.append("  },")
        report[key] = (len(out), n_summon, n_ap, unlinked)
    lines.append("}")
    lines.append("")
    (root / "SpellCoefficients.lua").write_text("\n".join(lines), encoding="utf-8", newline="\n")

    # the raw rows behind the checked spells, for tests/test_coefficients.lua
    raw = {}
    for key, client in clients.items():
        spells = {}
        todo = list(CHECKED)
        while todo:
            sid = todo.pop()
            if str(sid) in spells or sid not in client.effects:
                continue
            effs = []
            for e in client.effects[sid]:
                effs.append({"effect": int(e["Effect"]), "aura": int(e["EffectAura"]), "coef": number(e["EffectBonusCoefficient"]),
                             "ap": number(e["BonusCoefficientFromAP"]), "period": int(e["EffectAuraPeriod"] or 0),
                             "trigger": int(e["EffectTriggerSpell"] or 0), "target": int(e["ImplicitTarget_0"] or 0),
                             "enchantSpells": client.enchant_spells(e)})
                for t in [effs[-1]["trigger"]] + effs[-1]["enchantSpells"]:
                    if t:
                        todo.append(t)
            spells[str(sid)] = {"name": client.names.get(sid), "duration": client.duration.get(sid, 0), "effects": effs}
        raw[key] = {"build": client.build, "spells": spells}
    (root / "tests/fixtures/coefficient_rows.json").write_text(json.dumps(raw, indent=1, sort_keys=True) + "\n",
                                                                 encoding="utf-8", newline="\n")

    size = (root / "SpellCoefficients.lua").stat().st_size
    for key, (n, n_summon, n_ap, unlinked) in report.items():
        client = clients[key]
        print(f"{key} {client.build}: {n} ids ({n_summon} totems and traps), {n_ap} with attack power;"
              f" left to the rules (script or area trigger): {len(unlinked)}")
        print("   " + ", ".join(sorted({client.names.get(s, str(s)) for s in unlinked})))
    print(f"SpellCoefficients.lua: {size} bytes")


if __name__ == "__main__":
    main()
