#!/usr/bin/env python3
"""
Validate that cnn_right_left and block_side are consistent with PostGIS conventions.

For each schedule record, we:
1. Determine the line's direction (start → end)
2. Compute what "left" and "right" mean in cardinal terms
3. Check if block_side matches what we'd expect given cnn_right_left

PostGIS st_offsetcurve convention:
- Positive offset = left side of line (relative to start→end direction)
- Negative offset = right side of line
"""

import json
import math
from collections import defaultdict
from pathlib import Path


def get_line_direction_degrees(coords: list[list[float]]) -> float:
    """
    Compute the overall bearing of a line from start to end.
    Returns degrees from north (0=N, 90=E, 180=S, 270=W).
    """
    if len(coords) < 2:
        return 0.0

    start_lon, start_lat = coords[0]
    end_lon, end_lat = coords[-1]

    # Simple planar approximation (fine for short street segments)
    delta_lon = end_lon - start_lon
    delta_lat = end_lat - start_lat

    # atan2 gives angle from positive x-axis (east), counter-clockwise
    # Convert to bearing from north, clockwise
    angle_rad = math.atan2(delta_lon, delta_lat)
    bearing = math.degrees(angle_rad)

    # Normalize to 0-360
    if bearing < 0:
        bearing += 360

    return bearing


def bearing_to_cardinal(bearing: float) -> str:
    """Convert bearing to 8-point cardinal direction."""
    # Normalize to 0-360
    bearing = bearing % 360

    if bearing < 22.5 or bearing >= 337.5:
        return "N"
    elif bearing < 67.5:
        return "NE"
    elif bearing < 112.5:
        return "E"
    elif bearing < 157.5:
        return "SE"
    elif bearing < 202.5:
        return "S"
    elif bearing < 247.5:
        return "SW"
    elif bearing < 292.5:
        return "W"
    else:
        return "NW"


def get_left_right_cardinals(bearing: float) -> tuple[str, str]:
    """
    Given a line bearing, return (left_cardinal, right_cardinal).

    Left = 90 degrees counter-clockwise from direction of travel
    Right = 90 degrees clockwise from direction of travel
    """
    left_bearing = (bearing - 90) % 360
    right_bearing = (bearing + 90) % 360

    return bearing_to_cardinal(left_bearing), bearing_to_cardinal(right_bearing)


def normalize_block_side(block_side: str | None) -> str | None:
    """Normalize block_side to match our cardinal format."""
    if not block_side:
        return None

    # Map various formats to our 8-point system
    mapping = {
        "north": "N",
        "south": "S",
        "east": "E",
        "west": "W",
        "northeast": "NE",
        "northwest": "NW",
        "southeast": "SE",
        "southwest": "SW",
    }

    return mapping.get(block_side.lower().replace(" ", ""), block_side.upper())


def check_side_consistency(
    cnn_right_left: str,
    block_side: str | None,
    coords: list[list[float]],
) -> dict:
    """
    Check if block_side is consistent with cnn_right_left given the line geometry.

    Returns a dict with analysis results.
    """
    bearing = get_line_direction_degrees(coords)
    direction = bearing_to_cardinal(bearing)
    left_cardinal, right_cardinal = get_left_right_cardinals(bearing)
    normalized_block_side = normalize_block_side(block_side)

    # Determine expected cardinal based on cnn_right_left
    if cnn_right_left == "L":
        expected_cardinal = left_cardinal
    elif cnn_right_left == "R":
        expected_cardinal = right_cardinal
    else:
        expected_cardinal = None

    # Check if they match
    # For compound directions (NE, SW, etc), check if either component matches
    matches = False
    partial_match = False

    if normalized_block_side and expected_cardinal:
        if normalized_block_side == expected_cardinal:
            matches = True
        elif len(normalized_block_side) == 2 and len(expected_cardinal) == 1:
            # block_side is compound (e.g., "SE"), expected is simple (e.g., "S")
            partial_match = expected_cardinal in normalized_block_side
        elif len(normalized_block_side) == 1 and len(expected_cardinal) == 2:
            # block_side is simple, expected is compound
            partial_match = normalized_block_side in expected_cardinal
        elif len(normalized_block_side) == 2 and len(expected_cardinal) == 2:
            # Both compound - check if they share a component
            partial_match = bool(set(normalized_block_side) & set(expected_cardinal))

    return {
        "bearing": bearing,
        "line_direction": direction,
        "left_cardinal": left_cardinal,
        "right_cardinal": right_cardinal,
        "cnn_right_left": cnn_right_left,
        "block_side": block_side,
        "normalized_block_side": normalized_block_side,
        "expected_cardinal": expected_cardinal,
        "matches": matches,
        "partial_match": partial_match,
    }


def main():
    # Load the GeoJSON file
    geojson_path = (
        Path(__file__).parent.parent / "Street_Sweeping_Schedule_20251128.geojson"
    )

    if not geojson_path.exists():
        print(f"GeoJSON file not found: {geojson_path}")
        return

    print(f"Loading {geojson_path}...")
    with open(geojson_path) as f:
        data = json.load(f)

    features = data.get("features", [])
    print(f"Loaded {len(features)} features\n")

    # Analyze each feature
    results = {
        "exact_match": [],
        "partial_match": [],
        "mismatch": [],
        "null_block_side": [],
    }

    direction_stats = defaultdict(int)
    cnn_right_left_stats = defaultdict(int)
    block_side_stats = defaultdict(int)

    for feature in features:
        props = feature.get("properties", {})
        geometry = feature.get("geometry")
        if not geometry:
            continue
        coords = geometry.get("coordinates", [])

        if not coords or len(coords) < 2:
            continue

        cnn_right_left = props.get("cnnrightleft", "")
        block_side = props.get("blockside")
        corridor = props.get("corridor", "")
        limits = props.get("limits", "")

        cnn_right_left_stats[cnn_right_left] += 1
        block_side_stats[block_side] += 1

        if not block_side:
            results["null_block_side"].append(
                {
                    "corridor": corridor,
                    "limits": limits,
                    "cnn_right_left": cnn_right_left,
                }
            )
            continue

        analysis = check_side_consistency(cnn_right_left, block_side, coords)
        analysis["corridor"] = corridor
        analysis["limits"] = limits

        direction_stats[analysis["line_direction"]] += 1

        if analysis["matches"]:
            results["exact_match"].append(analysis)
        elif analysis["partial_match"]:
            results["partial_match"].append(analysis)
        else:
            results["mismatch"].append(analysis)

    # Print summary
    total = len(features)
    exact = len(results["exact_match"])
    partial = len(results["partial_match"])
    mismatch = len(results["mismatch"])
    null_side = len(results["null_block_side"])

    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Total features:      {total}")
    print(f"Exact matches:       {exact} ({100 * exact / total:.1f}%)")
    print(f"Partial matches:     {partial} ({100 * partial / total:.1f}%)")
    print(f"Mismatches:          {mismatch} ({100 * mismatch / total:.1f}%)")
    print(f"Null block_side:     {null_side} ({100 * null_side / total:.1f}%)")
    print()

    print("cnn_right_left distribution:")
    for k, v in sorted(cnn_right_left_stats.items()):
        print(f"  {k or '(empty)'}: {v}")
    print()

    print("block_side distribution:")
    for k, v in sorted(block_side_stats.items(), key=lambda x: -x[1]):
        print(f"  {k or '(null)'}: {v}")
    print()

    print("Line direction distribution:")
    for k, v in sorted(direction_stats.items(), key=lambda x: -x[1]):
        print(f"  {k}: {v}")
    print()

    # Show some mismatches for investigation
    if results["mismatch"]:
        print("=" * 60)
        print(f"SAMPLE MISMATCHES (showing first 10 of {mismatch})")
        print("=" * 60)
        for item in results["mismatch"][:10]:
            print(f"\nCorridor: {item['corridor']}")
            print(f"  Limits: {item['limits']}")
            print(f"  Line bearing: {item['bearing']:.1f}° ({item['line_direction']})")
            print(
                f"  Left side: {item['left_cardinal']}, Right side: {item['right_cardinal']}"
            )
            print(
                f"  cnn_right_left: {item['cnn_right_left']} → expected: {item['expected_cardinal']}"
            )
            print(
                f"  block_side: {item['block_side']} (normalized: {item['normalized_block_side']})"
            )

    # Show some exact matches for sanity check
    print()
    print("=" * 60)
    print("SAMPLE EXACT MATCHES (showing first 5)")
    print("=" * 60)
    for item in results["exact_match"][:5]:
        print(f"\nCorridor: {item['corridor']}")
        print(f"  Limits: {item['limits']}")
        print(f"  Line bearing: {item['bearing']:.1f}° ({item['line_direction']})")
        print(
            f"  Left side: {item['left_cardinal']}, Right side: {item['right_cardinal']}"
        )
        print(
            f"  cnn_right_left: {item['cnn_right_left']} → expected: {item['expected_cardinal']}"
        )
        print(f"  block_side: {item['block_side']} ✓")


if __name__ == "__main__":
    main()
