"""Summarize the score distributions and rarity ordering in a balance database."""

import argparse
from collections import Counter
from itertools import combinations
import json
from pathlib import Path
import sqlite3


BRACKETS = (0, 1, 50, 100, 200, 400)
BRACKET_LABELS = ("0", "1–49", "50–99", "100–199", "200–399", "400+")
MIN_TYPE_COUNT = 50
NEAR_TIE_BRACKETS = 0.10
TARGET_PERCENT = 75


def rarity_alignment(types, metric, tie_margin):
    eligible = [entry for entry in types if entry["count"] >= MIN_TYPE_COUNT
                and entry["configured_multiplier"] is not None]
    counts = Counter(aligned=0, reversed=0, near_ties=0)
    inversions = []
    for common, rare in combinations(sorted(eligible, key=lambda entry: -entry["count"]), 2):
        if rare["count"] == common["count"]:
            continue
        difference = rare[metric] - common[metric]
        if abs(difference) <= tie_margin:
            counts["near_ties"] += 1
        elif difference > 0:
            counts["aligned"] += 1
        else:
            counts["reversed"] += 1
            inversions.append({
                "rarer": rare["type"], "commoner": common["type"],
                "rarer_count": rare["count"], "commoner_count": common["count"],
                "rarer_value": rare[metric], "commoner_value": common[metric],
                "gap": round(-difference, 6),
            })
    pairs = sum(counts.values())
    percentage = (counts["aligned"] + 0.5 * counts["near_ties"]) * 100 / pairs if pairs else None
    return {
        "percent": percentage, "eligible_types": len(eligible), "comparable_pairs": pairs,
        **counts, "largest_inversions": sorted(inversions, key=lambda pair: -pair["gap"])[:15],
    }


def distribution(db, family, bracket_counts, total):
    sources = {
        "hand": "SELECT hand_type AS type, bracket_min FROM bracketed_hands",
        "context": "SELECT context_type AS type, bracket_min FROM bracketed_hands",
        "flush": """
            SELECT component.value AS type, hand.bracket_min
            FROM bracketed_hands AS hand, json_each(hand.hand_components) AS component
            JOIN multipliers AS def ON def.family = 'flush' AND def.type = component.value
        """,
    }
    configured = dict(db.execute("SELECT type, multiplier FROM multipliers WHERE family = ?", (family,)))
    counts = {name: Counter() for name in configured}
    query = f"SELECT type, bracket_min, COUNT(*) FROM ({sources[family]}) GROUP BY type, bracket_min"
    for name, lower, count in db.execute(query):
        counts.setdefault(name, Counter())[lower] = count

    result = []
    for name, by_bracket in counts.items():
        count = sum(by_bracket.values())
        result.append({
            "type": name or "no_hand",
            "count": count,
            "overall_percent": count * 100 / total,
            "configured_multiplier": configured.get(name),
            "mean_bracket_index": (
                sum(index * by_bracket[lower] for index, lower in enumerate(BRACKETS)) / count
                if count else None
            ),
            "percent_scoring_200_plus": (by_bracket[200] + by_bracket[400]) * 100 / count if count else None,
            "brackets": {
                label: {
                    "count": by_bracket[lower],
                    "percent_of_type": by_bracket[lower] * 100 / count if count else None,
                    "percent_of_bracket": (
                        by_bracket[lower] * 100 / bracket_counts[lower] if bracket_counts[lower] else None
                    ),
                }
                for lower, label in zip(BRACKETS, BRACKET_LABELS)
            },
        })
    return sorted(result, key=lambda entry: (entry["count"], entry["type"]))


def analyze(db):
    games, rounds = db.execute("SELECT COUNT(*), COALESCE(SUM(rounds), 0) FROM matches").fetchone()
    scores = dict(db.execute("SELECT score, COUNT(*) FROM hands GROUP BY score ORDER BY score"))
    total = sum(scores.values())
    if total == 0 or total != rounds * 4:
        raise ValueError("The database needs at least one complete four-player lobby.")
    bracket_counts = Counter(dict(db.execute("SELECT bracket_min, COUNT(*) FROM bracketed_hands GROUP BY bracket_min")))
    families = {}
    for family in ("hand", "context", "flush"):
        types = distribution(db, family, bracket_counts, total)
        families[family] = {
            "by_type": types,
            "rarity_vs_score": rarity_alignment(types, "mean_bracket_index", NEAR_TIE_BRACKETS),
            "rarity_vs_configured_multiplier": rarity_alignment(types, "configured_multiplier", 0),
        }
    percentages = [families[family]["rarity_vs_score"]["percent"] for family in ("hand", "context")]
    # Give the two rule systems equal weight even though they have different numbers of types.
    headline = sum(percentages) / 2 if None not in percentages else None
    return {
        "games": games, "rounds": rounds, "hands": total,
        "overall_rarity_alignment_percent": headline, "target_percent": TARGET_PERCENT,
        "min_samples_per_type": MIN_TYPE_COUNT, "score_near_tie_brackets": NEAR_TIE_BRACKETS,
        "score_histogram": scores,
        "score_brackets": {label: bracket_counts[lower] for lower, label in zip(BRACKETS, BRACKET_LABELS)},
        "families": families,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    uri = args.database.resolve(strict=True).as_uri() + "?mode=ro"
    with sqlite3.connect(uri, uri=True) as db:
        db.execute("BEGIN")  # Keep the report consistent even while another lobby commits.
        report = analyze(db)
    output = args.output or args.database.with_suffix(".report.json")
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    headline = report["overall_rarity_alignment_percent"]
    alignment = "insufficient comparable types" if headline is None else f"{headline:.1f}%"
    print(f"{report['games']:,} games, {report['hands']:,} hands. Rarity alignment: {alignment}.")
    print(f"Report: {output.resolve()}")


if __name__ == "__main__":
    main()
