"""Build data/reference/calendar.csv: one row per date with Victorian holiday flags.

Covers 1 Jul 2024 - 31 Dec 2025 (FY2024-25 for analysis, plus the forecast horizon).

Sources (checked 11 Oct 2026):
- Public holidays: data.gov.au "Australian Public Holidays Dates Machine Readable Dataset"
  (Jurisdiction = vic). The 2025 AFL Grand Final eve has no date there; it was Fri 26 Sep 2025.
- School terms: vic.gov.au "School term dates and holidays in Victoria".

Run from the repo root:  python scripts/build_calendar.py
"""

from pathlib import Path

import pandas as pd

START, END = "2024-07-01", "2025-12-31"

PUBLIC_HOLIDAYS = {
    "2024-09-27": "Friday before the AFL Grand Final",
    "2024-11-05": "Melbourne Cup",
    "2024-12-25": "Christmas Day",
    "2024-12-26": "Boxing Day",
    "2025-01-01": "New Year's Day",
    "2025-01-27": "Australia Day",
    "2025-03-10": "Labour Day",
    "2025-04-18": "Good Friday",
    "2025-04-19": "Saturday before Easter Sunday",
    "2025-04-20": "Easter Sunday",
    "2025-04-21": "Easter Monday",
    "2025-04-25": "ANZAC Day",
    "2025-06-09": "King's Birthday",
    "2025-09-26": "Friday before the AFL Grand Final",
    "2025-11-04": "Melbourne Cup",
    "2025-12-25": "Christmas Day",
    "2025-12-26": "Boxing Day",
}

# Official term start and end dates. Any date outside a term counts as school holidays.
# Term 1 uses the official start date; government school students start a day later.
SCHOOL_TERMS = [
    ("2024-07-15", "2024-09-20"),  # 2024 Term 3
    ("2024-10-07", "2024-12-20"),  # 2024 Term 4
    ("2025-01-28", "2025-04-04"),  # 2025 Term 1
    ("2025-04-22", "2025-07-04"),  # 2025 Term 2
    ("2025-07-21", "2025-09-19"),  # 2025 Term 3
    ("2025-10-06", "2025-12-19"),  # 2025 Term 4
]


def build_calendar() -> pd.DataFrame:
    cal = pd.DataFrame({"date": pd.date_range(START, END, freq="D")})

    cal["day_of_week"] = cal["date"].dt.day_name()
    cal["is_weekday"] = cal["date"].dt.dayofweek < 5  # Monday = 0 ... Sunday = 6

    holidays = pd.Series(PUBLIC_HOLIDAYS)
    holidays.index = pd.to_datetime(holidays.index)
    cal["holiday_name"] = cal["date"].map(holidays)  # NaN where it's not a holiday
    cal["is_public_holiday"] = cal["holiday_name"].notna()

    in_term = pd.Series(False, index=cal.index)
    for start, end in SCHOOL_TERMS:
        in_term |= cal["date"].between(start, end)
    cal["is_school_holiday"] = ~in_term

    # Victorian financial year runs July-June, so July is fiscal month 1.
    cal["fiscal_month"] = (cal["date"].dt.month - 7) % 12 + 1
    fy_end = cal["date"].dt.year + (cal["date"].dt.month >= 7)
    cal["fiscal_year"] = "FY" + (fy_end - 1).astype(str).str[-2:] + "-" + fy_end.astype(str).str[-2:]

    cal["date"] = cal["date"].dt.date
    return cal[["date", "day_of_week", "is_weekday", "is_public_holiday", "holiday_name",
                "is_school_holiday", "fiscal_month", "fiscal_year"]]


if __name__ == "__main__":
    out = Path(__file__).resolve().parents[1] / "data" / "reference" / "calendar.csv"
    cal = build_calendar()
    cal.to_csv(out, index=False)
    print(f"Wrote {len(cal)} rows to {out}")
