#!/usr/bin/env python3
"""Simple web access log analysis for the AWS Internship project.

Usage: python3 analyze_logs.py web-access-logs.csv
Answers: top pages, 4xx/5xx counts, peak traffic hour, unique visitor IPs.
"""
import csv
import sys
from collections import Counter
from datetime import datetime


def main(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))

    total = len(rows)
    pages = Counter(r["path"] for r in rows)
    statuses = Counter(int(r["status"]) for r in rows)
    c4xx = sum(v for k, v in statuses.items() if 400 <= k < 500)
    c5xx = sum(v for k, v in statuses.items() if 500 <= k < 600)
    hours = Counter(
        datetime.strptime(r["timestamp"], "%Y-%m-%d %H:%M:%S").hour for r in rows
    )
    unique_ips = {r["ip"] for r in rows}
    total_bytes = sum(int(r["bytes"]) for r in rows)

    print("=== Web Access Log Analysis ===")
    print(f"Total requests     : {total}")
    print(f"Unique visitor IPs : {len(unique_ips)}")
    print(f"Total bytes served : {total_bytes:,}")
    print(f"4xx errors         : {c4xx} ({c4xx / total:.1%})")
    print(f"5xx errors         : {c5xx} ({c5xx / total:.1%})")

    print("\nTop 5 requested pages:")
    for p, n in pages.most_common(5):
        print(f"  {p:<22} {n:>4}")

    print("\nStatus code breakdown:")
    for code, n in sorted(statuses.items()):
        print(f"  {code}: {n}")

    peak_hour, peak_count = hours.most_common(1)[0]
    print(f"\nPeak traffic hour  : {peak_hour:02d}:00-{peak_hour:02d}:59 ({peak_count} requests)")

    print("\nRequests per hour:")
    for h in sorted(hours):
        print(f"  {h:02d}:00 {'#' * (hours[h] // 3)} {hours[h]}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: analyze_logs.py <logfile.csv>")
    main(sys.argv[1])
