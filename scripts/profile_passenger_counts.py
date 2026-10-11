"""Profile the full Train Service Passenger Counts CSV without loading it all into memory.

The file is ~2.8 GB, so pandas reads it in 1M-row chunks and we keep running totals.
Output feeds docs/data_quality_notes.md (Day 1) and is a baseline for the Snowflake row counts (Day 2).

Run from the repo root:  python scripts/profile_passenger_counts.py
"""

from pathlib import Path
import time

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
CSV = ROOT / "data" / "raw" / "train_service_passenger_counts_fy_2024_2025.csv"
OUT = ROOT / "docs" / "profile_output"
COUNTS = ["Passenger_Boardings", "Passenger_Alightings",
          "Passenger_Arrival_Load", "Passenger_Departure_Load"]

start = time.time()
total_rows = 0
rows_by_mode = pd.Series(dtype="int64")
rows_by_day_type = pd.Series(dtype="int64")
null_counts = pd.Series(dtype="int64")
negative_rows = 0
dates, stations = set(), set()
min_time, max_time = "99:99:99", "00:00:00"
metro_parts = []  # small per-chunk aggregates, combined at the end

for chunk in pd.read_csv(CSV, chunksize=1_000_000, dtype={"Train_Number": "string"}):
    total_rows += len(chunk)
    rows_by_mode = rows_by_mode.add(chunk["Mode"].value_counts(), fill_value=0)
    rows_by_day_type = rows_by_day_type.add(chunk["Day_Type"].value_counts(), fill_value=0)
    null_counts = null_counts.add(chunk.isna().sum(), fill_value=0)
    negative_rows += int((chunk[COUNTS] < 0).any(axis=1).sum())
    dates.update(chunk["Business_Date"].unique())

    times = chunk["Departure_Time_Scheduled"].dropna()
    min_time, max_time = min(min_time, times.min()), max(max_time, times.max())

    metro = chunk[chunk["Mode"] == "Metro Trains"].copy()
    stations.update(metro["Station_Name"].unique())
    metro["month"] = metro["Business_Date"].str[:7]
    metro["all_zero"] = metro[COUNTS].sum(axis=1) == 0
    metro_parts.append(
        metro.groupby(["Line_Name", "month"])
        .agg(rows=("all_zero", "size"), zero_rows=("all_zero", "sum"),
             boardings=("Passenger_Boardings", "sum"))
    )
    print(f"  {total_rows:,} rows read ({time.time() - start:.0f}s)", flush=True)

line_month = pd.concat(metro_parts).groupby(level=[0, 1]).sum()
line_month["zero_pct"] = (line_month["zero_rows"] / line_month["rows"] * 100).round(1)
by_line = line_month.groupby(level=0)[["rows", "zero_rows", "boardings"]].sum()
by_line["zero_pct"] = (by_line["zero_rows"] / by_line["rows"] * 100).round(1)

OUT.mkdir(exist_ok=True)
line_month.to_csv(OUT / "metro_zero_rows_by_line_month.csv")
by_line.sort_values("boardings", ascending=False).to_csv(OUT / "metro_by_line.csv")

all_dates = sorted(dates)
expected = pd.date_range(all_dates[0], all_dates[-1]).strftime("%Y-%m-%d")
print(f"\nFile size:        {CSV.stat().st_size:,} bytes")
print(f"Total rows:       {total_rows:,}")
print(f"Rows by mode:     {rows_by_mode.astype(int).to_dict()}")
print(f"Rows by day type: {rows_by_day_type.astype(int).to_dict()}")
print(f"Date range:       {all_dates[0]} to {all_dates[-1]} ({len(all_dates)} distinct dates)")
print(f"Missing dates:    {sorted(set(expected) - dates)}")
print(f"Departure times:  {min_time} to {max_time}")
print(f"Metro stations:   {len(stations)}")
print(f"Negative rows:    {negative_rows}")
print(f"Nulls:            {null_counts[null_counts > 0].astype(int).to_dict()}")
print(f"Metro zero rows:  {by_line['zero_rows'].sum() / by_line['rows'].sum() * 100:.1f}%")
print("\nMetro lines (sorted by total boardings):")
print(by_line.sort_values("boardings", ascending=False).to_string())
print(f"\nDone in {time.time() - start:.0f}s")
