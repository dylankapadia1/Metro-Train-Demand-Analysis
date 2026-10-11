# Data quality notes

A running log of what the data looks like, what's wrong with it, and what I did about it.
Each entry says where the finding came from so it can be re-checked.

## Sources

| Dataset | File | Size | Rows | Licence |
|---|---|---|---|---|
| [Train Service Passenger Counts](https://discover.data.vic.gov.au/dataset/train-service-passenger-counts), FY2024-25 | `train_service_passenger_counts_fy_2024_2025.csv` | 2,837,419,169 bytes (2.8 GB) | 15,937,506 (14,547,467 Metro Trains) | CC BY 4.0, Department of Transport and Planning |
| [Annual metropolitan train station patronage (station entries)](https://discover.data.vic.gov.au/dataset/annual-metropolitan-train-station-patronage-station-entries), FY2024-25 | `annual_metropolitan_train_station_entries_fy_2024_2025.csv` | 22,122 bytes | 222 stations | CC BY 4.0, Department of Transport and Planning |
| Calendar (self-built) | `data/reference/calendar.csv` | | 549 days (1 Jul 2024 to 31 Dec 2025) | Built by `scripts/build_calendar.py` from data.gov.au public holidays + vic.gov.au school terms |

Raw files are downloaded to `data/raw/` (git-ignored) and are not committed.

## Passenger counts: structure (confirmed 11 Oct 2026)

21 columns. The real headers differ from the placeholders in the build plan:

| Column | Type (pandas) | Notes |
|---|---|---|
| `Business_Date` | text, `YYYY-MM-DD` | Operating day, not calendar day. Services after midnight belong to the previous business date |
| `Day_of_Week`, `Day_Type` | text | Follow the business date. Day types: Normal Weekday, School Holiday, Saturday, Sunday, Public Holiday |
| `Mode` | text | `Metro Trains` or `V/Line`. Staging keeps Metro Trains only |
| `Train_Number` | text | Read as text so leading zeros aren't lost |
| `Line_Name`, `Group` | text | Line and line group (e.g. Alamein / Alamein-Riversdale) |
| `Direction` | text | `U` = towards Flinders Street, `D` = away |
| `Origin_Station`, `Destination_Station`, `Station_Name` | text | |
| `Station_Latitude`, `Station_Longitude` | decimal | Station coordinates are included, so the map visual doesn't need GTFS |
| `Station_Chainage`, `Stop_Sequence_Number` | integer | Distance along the line and stop order within the service |
| `Arrival_Time_Scheduled`, `Departure_Time_Scheduled` | text, `HH:MM:SS` | **There is no 30-minute block column.** Derive it from the scheduled time in staging |
| `Passenger_Boardings`, `Passenger_Alightings`, `Passenger_Arrival_Load`, `Passenger_Departure_Load` | integer | Binned to multiples of 10 for privacy |

## Findings so far

From a full pass over the file with `scripts/profile_passenger_counts.py` (Day 1, 34 seconds). Summary tables: `docs/profile_output/`.

1. **Complete date coverage.** 365 distinct business dates, 1 Jul 2024 to 30 Jun 2025, with none missing.
2. **Rows by day type:** Normal Weekday 9,770,425 · School Holiday 2,488,503 · Saturday 1,750,238 · Sunday 1,487,519 · Public Holiday 440,821.
3. **V/Line rows are mixed in:** 1,390,039 rows (8.7%) across Western, Eastern, Northern, North East and South Western. Staging filters to `Mode = 'Metro Trains'`.
4. **18 rows have negative counts.** All are one V/Line service (train 8610, North East line) on Sun 16 and Sun 30 Mar 2025, with negative loads all the way down the line. This is a model error; the Metro filter removes it. The staging check should still confirm 0 negative Metro rows.
5. **Missing scheduled times:** 14,591 rows have no arrival or departure time; 13,777 of them are Metro (0.09% of Metro rows, about 145k boardings). Concentrated on Hurstbridge (7,193) and Mernda (2,355). **Proposed handling:** keep them in daily totals, but set `time_band = 'Unknown'` so they drop out of peak analysis. The effect on AM peak totals is negligible (under 0.1%).
6. **All-zero rows (no data source):** 4.4% of Metro rows. Much higher on quieter lines: Stony Point 36.8%, Alamein 21.8%, Flemington Racecourse 17.6%, Williamstown 12.5%. The busiest lines are 1.4–7.2%. Low-volume lines will be understated, so exclude Stony Point and Flemington Racecourse from the line forecast.
7. **Counts are binned to multiples of 10.** The median boardings per stop is 0, because small stops round down. Summed totals are approximate. Line- and network-level totals are fine for trends; single-stop numbers are not precise.
8. **222 Metro stations**, the same count as the station entries file. Scheduled departure times run 00:00:00 to 23:59:00, with no values over 24:00, so after-midnight services use clock time on the previous business date.
9. **Boardings are 25.7% higher than station entries** (224,374,850 vs 178,480,700 for the year). Expected, because this dataset counts a boarding for every train a passenger takes, including transfers, while station entries count barrier entries plus a 5% uplift. The Day 3 reconciliation should compare **station shares** or rank order, not raw totals.
10. **The file isn't sorted by date.** The first 100k rows span July to September 2024.
11. **Station entries are rounded to the nearest 50** and already broken down by time of day (pre-AM peak, AM peak, inter-peak, PM peak, late).

**Busiest Metro lines by total boardings (FY2024-25, approximate):** Pakenham 24.1M · Frankston 20.7M · Lilydale 20.1M · Craigieburn 18.1M · Mernda 18.0M. (Before data quality adjustments; not a finding to publish yet.)

## Known limitations (from the DataVic dataset description)

- Counts are **modelled estimates** built from myki touch-ons, barrier counts, manual surveys and conductor counts, not direct counts.
- Accuracy is lowest at **busy interchanges** such as the City Loop, where it's hard to tell which train a transferring passenger took.
- Accuracy is **significantly reduced on disruption days**.
- The model **isn't capacity-constrained**, so a few services show unrealistically high loads. Treat them as "very crowded", not as fact.
- **Station entries won't reconcile exactly** with this dataset. DTP's published station totals add a 5% transfer uplift and use different rounding, and boardings include transfers (see finding 9). The Day 3 reconciliation should expect a gap and explain it, rather than treat every difference over 10% as an error.
- The data model was upgraded in 2026 and all years were reprocessed. Mode values changed from `Metro`/`VLine` to `Metro Trains`/`V/Line`.

## Decisions

| Decision | Reason |
|---|---|
| Load the 2.8 GB CSV with Snowflake CLI (`snow sql`) `PUT` + `COPY INTO` | Too big for the Snowsight upload limit. Snowflake CLI replaces SnowSQL, which Snowflake now calls legacy |
| Keep the time band boundaries from the build plan, derived from `Departure_Time_Scheduled` | No time-block column in the source |
| Calendar school holidays = any date outside official term dates | Matches how vic.gov.au defines terms. Compare with the source's `Day_Type` in staging |

## Open questions

- Does the source's `Day_Type = 'School Holiday'` line up exactly with `calendar.csv`? Check in staging.
- Time handling for missing scheduled times (finding 5): confirm the `'Unknown'` time band approach.
