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

## Snowflake load and staging (Day 2)

- **Load (`sql/02_load_raw.sql`):** all three files loaded into RAW with 0 errors. Row counts match: 15,937,506 / 222 / 549. `PUT` compressed the 2.8 GB CSV to 314 MB, and the whole script took 2.5 minutes.
- **Staging (`sql/03_staging.sql`):** 14,547,467 Metro rows, as expected. Total boardings are 224,374,850, matching the pandas profile exactly.
- **Missing scheduled times:** when a time is missing, arrival and departure are both missing, on the same 13,777 Metro rows. Deriving the time band from departure time alone loses nothing.
- **Boardings by time band:**

  | Time band | Hours | Boardings | Share |
  |---|---|---|---|
  | Early | before 07:00 | 9,503,260 | 4.2% |
  | AM Peak | 07:00–08:59 | 47,926,900 | 21.4% |
  | Inter-peak | 09:00–15:59 | 81,678,500 | 36.4% |
  | PM Peak | 16:00–18:59 | 63,259,250 | 28.2% |
  | Evening | 19:00 onwards | 21,901,700 | 9.8% |
  | Unknown | no time | 105,240 | 0.0% |

## Data quality checks (Day 2, `sql/04_data_quality_checks.sql`)

The script is read-only and re-runnable, and takes about 15 seconds. Results from 11 Oct 2026:

| # | Check | Result | Status |
|---|---|---|---|
| 1 | Row counts and failed casts | RAW Metro 14,547,467 = STAGING 14,547,467. 0 failed casts across all 11 typed columns | Pass |
| 2 | Duplicates | 2,570 repeats on (date, train, station, direction), 5,140 rows. **0** once `stop_sequence_number` is added. 0 exact duplicate rows | Pass: see note |
| 3 | Negative or NULL counts | 0 negative, 0 NULL. Every count is a multiple of 10 | Pass |
| 4 | All-zero rows by line × month | 4 lines over 10%: Stony Point 36.8%, Alamein 21.8%, Flemington Racecourse 17.6%, Williamstown 12.5% | Flagged |
| 5 | Calendar gaps and day types | 365 data dates = 365 FY24-25 calendar dates, none missing either way. 0 day-of-week mismatches. Day types agree on 364 of 365 dates | Pass, 1 exception |
| 6 | Load continuity | Within a stop: 74.4% exact, the other 25.6% off by exactly 10 (one bin), none worse. Between stops: 13,702,784 of 13,702,784 exact | Pass |
| 7 | Station totals vs entries | All 222 names match. Rank correlation 0.998. Raw share gaps are distorted by interchange transfers: see note | Pass, with explanation |

**What each result means and what was done:**

- **Check 2: the true grain includes `stop_sequence_number`.** A train can call at the same station twice on one trip, e.g. around the City Loop. So the unique key is (business_date, train_number, station_name, direction, stop_sequence_number). The marts will group on this key, never on the shorter one.
- **Check 4: zero rows understate the quiet lines.** The busiest lines are 1.4–7.2% zero rows. Flemington Racecourse is also volatile month to month (7.3–35.8%), because it only runs on event days. **Action:** Stony Point and Flemington Racecourse stay out of the line forecast, as planned. Alamein and Williamstown are borderline (see open questions). Every line is kept in the descriptive analysis, with a caveat.
  - There's also a line called `Richmond and City Loop` (30,702 rows, 9.7% zero rows). It isn't a real passenger line, probably short shunting or terminating services. Check on Day 3 before it shows up on a "busiest lines" chart.
- **Check 5: 28 Jan 2025 is the one day-type mismatch.** The source says `School Holiday`; `calendar.csv` says `Normal Weekday`, because Term 1 officially starts that day. It's likely a student-free day, which explains why DTP counted it as a holiday. Effect: 1 date of 365.
- **Check 6: the counts hold together.** The 10-passenger gaps within a stop are what you'd expect from rounding four values to multiples of 10 separately. No gap is larger than one bin. Between stops, the load carries over with no breaks at all. Within-service loads are internally consistent, so peak load analysis can rely on them.
- **Check 7: the gap is explained, not an error.**
  - **Shares are a poor comparison here.** The build plan's test (a share gap over 10%) flags 215 of 222 stations. That's because three interchanges add tens of millions of transfer boardings: Flinders Street (2.43 boardings per entry), Richmond (2.92) and North Melbourne (2.99). The extra transfers lift the network ratio to 1.26, which shrinks every other station's share by about 21%. The median share gap is −22.8%.
  - **Comparing station by station, the sources agree.** Metro-only stations (205) have 1.02 boardings per entry overall, with a median of 0.97. The two sources also rank stations in almost the same order (correlation 0.998), and both have the same top 3: Flinders Street, Southern Cross, Melbourne Central.
  - **Low ratios have two causes:**
    - Some stations are shared with V/Line, so their entries include V/Line passengers that aren't in the Metro boardings: Sunbury 0.67, East Pakenham 0.72, Footscray.
    - Stony Point line stations (Baxter 0.14, Tyabb 0.23) have many zero rows (see check 4).
  - **Action:** report the reconciliation as boardings per entry and rank agreement, not share difference. Name the three interchanges as the source of the gap.

## Known limitations (from the DataVic dataset description)

- Counts are **modelled estimates** built from myki touch-ons, barrier counts, manual surveys and conductor counts, not direct counts.
- Accuracy is lowest at **busy interchanges** such as the City Loop, where it's hard to tell which train a transferring passenger took.
- Accuracy is **significantly reduced on disruption days**.
- The model **isn't capacity-constrained**, so a few services show unrealistically high loads. Treat them as "very crowded", not as fact.
- **Station entries won't reconcile exactly** with this dataset. DTP's published station totals add a 5% transfer uplift and use different rounding, and boardings include transfers (see finding 9). Check 7 confirmed the gap is concentrated at three interchanges.
- The data model was upgraded in 2026 and all years were reprocessed. Mode values changed from `Metro`/`VLine` to `Metro Trains`/`V/Line`.

## Decisions

| Decision | Reason |
|---|---|
| Load the 2.8 GB CSV with Snowflake CLI (`snow sql`) `PUT` + `COPY INTO` | Too big for the Snowsight upload limit. Snowflake CLI replaces SnowSQL, which Snowflake now calls legacy |
| Time bands from `Departure_Time_Scheduled`: Early < 07:00, AM Peak 07:00–08:59, Inter-peak 09:00–15:59, PM Peak 16:00–18:59, Evening 19:00+ | No time-block column in the source. A separate `Early` band keeps AM peak clean and matches the "pre-AM peak" column in station entries |
| Rows with no scheduled time get `time_band = 'Unknown'` | 13,777 rows (0.09%). They stay in daily totals but drop out of peak analysis |
| Calendar school holidays = any date outside official term dates | Matches how vic.gov.au defines terms. Agrees with the source's `Day_Type` on 364 of 365 dates (check 5) |
| Renamed `GROUP` → `line_group`, `date` → `calendar_date`, entries `stop_name` → `station_name` | `GROUP` and `DATE` are reserved words. A shared station name column makes joins simple |
| Grain = date + train + station + direction + `stop_sequence_number` | Check 2: the shorter key has 2,570 repeats from trains calling twice at one station |
| Reconcile stations as boardings per entry and rank agreement, not share difference | Check 7: interchange transfers distort shares for every station |

## Open questions

- **28 Jan 2025:** align `calendar.csv` with the source (mark it a school holiday), or keep the official term dates? Aligning keeps the forecast's school holiday flag consistent with DTP's day types.
- **Alamein (21.8%) and Williamstown (12.5%) zero rows:** keep them in the line forecast with a caveat, or exclude them like Stony Point and Flemington Racecourse?
- **`Richmond and City Loop` line:** what are these 30,702 rows, and should they be left out of line-level charts?

**Resolved on Day 2:** the source's `Day_Type` matches `calendar.csv` on all but one date (check 5). The `'Unknown'` time band approach was confirmed.
