# Data quality notes

A running log of what the data looks like, what's wrong with it, and what I did about it.
Each entry says where the finding came from so it can be re-checked.

## Sources

| Dataset | File | Size | Rows | Licence |
|---|---|---|---|---|
| [Train Service Passenger Counts](https://discover.data.vic.gov.au/dataset/train-service-passenger-counts), FY2024-25 | `train_service_passenger_counts_fy_2024_2025.csv` | 2,837,419,169 bytes (2.8 GB) | 15,937,506 (14,547,467 Metro Trains) | CC BY 4.0, Department of Transport and Planning |
| [Annual metropolitan train station patronage (station entries)](https://discover.data.vic.gov.au/dataset/annual-metropolitan-train-station-patronage-station-entries), FY2024-25 | `annual_metropolitan_train_station_entries_fy_2024_2025.csv` | 22,122 bytes | 222 stations | CC BY 4.0, Department of Transport and Planning |
| [Monthly average patronage by day type and by mode](https://discover.data.vic.gov.au/dataset/monthly-average-patronage-by-day-type-and-by-mode), Jan 2018 onwards | `monthly_average_patronage_by_day_type_and_by_mode.csv` | 234,233 bytes | 4,450 (month × day of week × day type × mode) | CC BY 4.0, Department of Transport and Planning. Official figures from myki and barrier data: station entries + 5% transfer uplift. Downloaded 11 Oct 2026. Used for check 8 |
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
| 5 | Calendar gaps and day types | 365 data dates = 365 FY24-25 calendar dates, none missing either way. 0 day-of-week mismatches. Day types agreed on 364 of 365 dates; **365 of 365** after the calendar fix | Pass (after fix) |
| 6 | Load continuity | Within a stop: 74.4% exact, the other 25.6% off by exactly 10 (one bin), none worse. Between stops: 13,702,784 of 13,702,784 exact | Pass |
| 7 | Station totals vs entries | All 222 names match. Rank correlation 0.998. Raw share gaps are distorted by interchange transfers: see note | Pass, with explanation |
| 8 | Modelled counts vs DTP official monthly patronage *(added Day 3)* | Monthly normal-weekday pattern: correlation **0.999**, no month off by more than 1.0 index point. Day-of-week pattern within 0.7 points. Level ratio steady at 1.25–1.27 | Pass |

**What each result means and what was done:**

- **Check 2: the true grain includes `stop_sequence_number`.** A train can call at the same station twice on one trip, e.g. around the City Loop. So the unique key is (business_date, train_number, station_name, direction, stop_sequence_number). The marts will group on this key, never on the shorter one.
- **Check 4: zero rows understate the quiet lines.** The busiest lines are 1.4–7.2% zero rows. Flemington Racecourse is also volatile month to month (7.3–35.8%), because it only runs on event days. **Action:** Stony Point and Flemington Racecourse stay out of the line forecast, as planned.
  - **Alamein and Williamstown stay in the forecast, with a caveat.** Their zero share is steady month to month: Alamein 19.0–24.7%, Williamstown 9.7–15.1%. So their levels are understated, but the weekly pattern and trend, which the forecast is tested on, still hold. The forecast and its naive baseline use the same data, so the comparison stays fair. `MART.DIM_LINE` will carry a `data_caveat` for them.
  - Every line is kept in the descriptive analysis, with a caveat where it applies.
- **Check 5: 28 Jan 2025 was the one day-type mismatch, now fixed.** The source said `School Holiday`, but `calendar.csv` said `Normal Weekday`, because Term 1 officially starts that day. The first day of Term 1 is student-free, and government school students start a day later, so DTP counts it as a school holiday. **Action:** `scripts/build_calendar.py` now starts 2025 Term 1 on the students' start date, 29 Jan. Only this row of `calendar.csv` changed. I reloaded `RAW.CALENDAR`, rebuilt staging and re-ran the checks: day types now agree on all 365 dates. The forecast period (Jul–Sep 2025) has no Term 1, so this doesn't affect it.
- **Check 6: the counts hold together.** The 10-passenger gaps within a stop are what you'd expect from rounding four values to multiples of 10 separately. No gap is larger than one bin. Between stops, the load carries over with no breaks at all. Within-service loads are internally consistent, so peak load analysis can rely on them.
- **Check 7: the gap is explained, not an error.**
  - **Shares are a poor comparison here.** The build plan's test (a share gap over 10%) flags 215 of 222 stations. That's because three interchanges add tens of millions of transfer boardings: Flinders Street (2.43 boardings per entry), Richmond (2.92) and North Melbourne (2.99). The extra transfers lift the network ratio to 1.26, which shrinks every other station's share by about 21%. The median share gap is −22.8%.
  - **Comparing station by station, the sources agree.** Metro-only stations (205) have 1.02 boardings per entry overall, with a median of 0.97. The two sources also rank stations in almost the same order (correlation 0.998), and both have the same top 3: Flinders Street, Southern Cross, Melbourne Central.
  - **Low ratios have two causes:**
    - Some stations are shared with V/Line, so their entries include V/Line passengers that aren't in the Metro boardings: Sunbury 0.67, East Pakenham 0.72, Footscray.
    - Stony Point line stations (Baxter 0.14, Tyabb 0.23) have many zero rows (see check 4).
  - **Action:** report the reconciliation as boardings per entry and rank agreement, not share difference. Name the three interchanges as the source of the gap.
- **Check 8: the model's patterns match the official figures.** Added on Day 3, after March 2025 came out 16% above an average weekday (analysis Q5) and needed checking against an independent source.
  - **Why the levels differ:** DTP's official monthly patronage comes from myki and barrier data, not from the passenger-count model. It counts station entries + 5%, while the model counts every boarding, including transfers. So only the **shape** is compared: each month as an index (100 = the FY average), averaged the same way on both sides (per month × day of week first, then across the five weekdays).
  - **Monthly:** the two series correlate at 0.999. The largest gap is 1.0 index point (Dec 2024). March is 116.3 in the model and 115.5 officially.
  - **Day of week:** Mon 88.9 vs 89.6, Tue 105.3 vs 105.2, Wed 104.7 vs 104.1, Thu 107.3 vs 106.8, Fri 93.8 vs 94.4.
  - **Level:** 1.25–1.27 model boardings per official passenger in every month. This is the transfer effect from check 7, and it's stable, not drifting.
  - **March is the peak every year in the official data.** Compared with the average of February and May: +8.1% in 2018 and 2019, +10.7% to +12.7% in 2023–25, and +16.2% in 2026. (2020–22 are distorted by COVID.)
  - **Not established:** the official data shows the March peak is real and recurring, but not why it happens. A full month of school and university semester 1 with no holidays, plus major events, is a plausible explanation, but these sources don't confirm it.
  - **I found no planned works** in February or May 2025 that would have pushed those months down. The only works found were Metro Tunnel testing bus replacements on Pakenham and Cranbourne on 14, 15 and 17 April 2025 ([Pakenham News](https://pakenhamnews.starcommunity.com.au/news/2025-04-14/bus-replacements-for-pakenham-cranbourne-lines/)).
  - **Action:** report March as a recurring seasonal peak, confirmed by the official data, with no cause stated. For the forecast (Day 4), one year of data can't teach a model a yearly pattern, so this goes in as a stated limitation. Forecasting Jul–Sep 2025 doesn't cross a March, so it doesn't change the forecast period.

## `Richmond and City Loop` line (investigated Day 3)

The source has a `Line_Name` of `Richmond and City Loop` with 30,702 rows. It isn't a corridor line. It's two kinds of short service inside the city:

| Line group | What it is | Trains | When | Boardings |
|---|---|---|---|---|
| City Cordon | Extra PM peak services from Richmond → Flinders Street via the Loop | 9 | Weekdays only (normal and school holiday), 15:29–18:07 | 394,780 |
| City Loop | Trains that start and end at Flinders Street, going round the Loop: positioning runs and short workings | 42–138 a day | All day, every day | 251,030 |

- **Size:** 645,810 boardings in total, 0.29% of the network's 224,374,850.
- **Link to check 2:** the 2,570 Flinders Street → Flinders Street services account for exactly the 2,570 duplicates found there. These are trains calling at Flinders Street twice on one trip.

**Action:**
- **Kept** in network and station totals. These are real passengers, and taking them out would understate Flinders Street and the City Loop stations.
- **Flagged** in `MART.DIM_LINE` with `is_corridor_line = FALSE` and the label "City Loop & short services".
- **Left out** of line rankings, the line heatmap and the forecast.

## Forecast data issues (Day 4, `notebooks/forecast_weekday_peak.ipynb`)

The forecast series is daily AM peak boardings, Mon–Fri, for the 15 forecast lines (`MART.DAILY_LINE_DEMAND`). Exploring it before modelling turned up the issues below. Results are in `docs/forecast_results.md`.

**Disruption days.**
- **Rule:** a line-day is disrupted when the line has **no AM peak data** (closed), or when AM peak **services and boardings are both under 80%** of that line's median for the same day type. Public holidays and 23 Dec – 3 Jan are excluded from the rule, because they're low by nature.
- **Why both have to be low:** services alone flagged false positives.
  - Public holidays run a Sunday timetable.
  - On Mon 3 Mar 2025, services looked low on 9 lines but boardings were normal, which points to a timetable or data quirk.
- **Result:**

| Period | Line-days | Closed | Low service | Disrupted |
|---|---|---|---|---|
| Training (Jul 2024 – Mar 2025) | 2,940 | 7 | 32 | 39 (1.3%) |
| Test (Apr – Jun 2025) | 975 | 7 | 7 | 14 (1.4%) |

- **They match known events:**
  - Sandringham closed 9–16 Dec 2024.
  - Summer works on Pakenham, Cranbourne and Sunbury, 2–14 Jan 2025 (boardings at 11–50% of usual).
  - Glen Waverley closed 7–10 Apr 2025.
  - Metro Tunnel testing, 14, 15 and 17 Apr 2025: Sunbury closed; Pakenham and Cranbourne at 22–28%. These dates are confirmed by [Pakenham News](https://pakenhamnews.starcommunity.com.au/news/2025-04-14/bus-replacements-for-pakenham-cranbourne-lines/).
  - Mernda, 26 May 2025.
- **Handling:** disrupted days are set to missing for training, and test scores exclude them.
- **Not flagged:** Frankston boardings ran about 50% of usual on several days in Jul–Aug 2024, with services at 84–87%. That's just above the service cut-off, so the rule doesn't flag it.

**Low days that aren't disruptions.** The models get these as calendar features:
- **Christmas–New Year (23 Dec – 3 Jan):** weekdays ran at 13–44% of a normal school holiday day, with full services. They get their own effect, separate from ordinary school holidays.
- **Mon 4 Nov 2024,** the day before Melbourne Cup: 40–60% of normal on every line.
- **Fri 20 Dec 2024,** the last Friday before Christmas: about 50% of normal.
- **Tue–Thu 22–24 Apr 2025,** between Easter Monday and ANZAC Day: about 26% below a normal week. There's no precedent in training, so it's left unmodelled and reported as a known miss.

**Public holidays vary a lot.** AM peak on a weekday public holiday ranges from **3%** of a normal weekday (Christmas Day) to **17%** (Boxing Day). The four test-period holidays were 7–10%. None of them falls in the training months, so all holidays outside the Christmas period share one effect.

**Hurstbridge level shift (unexplained).**
- Hurstbridge's normal-weekday AM peak was about 15–16k in Jul–Sep 2024 and about 12.4–13.6k from October 2024 to March 2025. It recovered to about 15–16k in Apr–May 2025.
- The other 14 lines moved the opposite way over the same months.
- The models learned the low level and under-forecast Hurstbridge by 13–19% in the back-test. It's the only line where the forecast didn't beat the baseline.
- No cause has been found, so none is stated.

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
| Calendar school holidays = any date outside term dates, with Term 1 starting on the students' first day | Matches vic.gov.au terms and DTP's `Day_Type` on all 365 dates (check 5). The official first day of Term 1 is student-free |
| Renamed `GROUP` → `line_group`, `date` → `calendar_date`, entries `stop_name` → `station_name` | `GROUP` and `DATE` are reserved words. A shared station name column makes joins simple |
| Grain = date + train + station + direction + `stop_sequence_number` | Check 2: the shorter key has 2,570 repeats from trains calling twice at one station |
| Reconcile stations as boardings per entry and rank agreement, not share difference | Check 7: interchange transfers distort shares for every station |
| Line forecast excludes Stony Point, Flemington Racecourse and `Richmond and City Loop` | The first two have too many zero rows or swing too much month to month (check 4). The third isn't a corridor line. Alamein and Williamstown stay in, with a caveat |
| `Richmond and City Loop` kept in network and station totals, flagged `is_corridor_line = FALSE` | Real passengers (0.29% of boardings), but short city services, not a line |
| Busiest-services ranking covers regular services only: those running on at least 100 of the 199 normal weekdays | Otherwise one-off event trains rank first (a Flemington Racecourse train that ran once ranked #1). The 2,560 regular services run 100–199 days and the 1,198 others run 62 or fewer, so the cut-off sits in a natural gap |
| Validate the modelled data against DTP's official monthly patronage, comparing the shape (index) rather than the level | Independent source (myki and barrier data). The levels differ by design, because boardings include transfers. Check 8 |
| Transfer hub = 2 or more boardings per barrier entry | A transparent rule that picks out exactly Flinders Street (2.43), Richmond (2.92) and North Melbourne (2.99). Check 7 |
| Forecast disruption rule: closed, or AM peak services **and** boardings under 80% of usual for the line and day type | Services alone flagged public holidays and a data quirk (3 Mar 2025). Requiring both catches real disruptions only (see Forecast data issues) |
| Forecast results written to `MART.FORECAST_LINE_DEMAND`, `MART.FORECAST_BACKTEST` and `MART.FORECAST_METRICS`, rebuilt on every notebook run | Power BI's forecast page reads them directly. The notebook verifies the row counts after writing |

## Open questions

None at the moment.

**Resolved:**
- Day 2: the `'Unknown'` time band approach was confirmed.
- Day 3, step 0:
  - 28 Jan 2025 is now a school holiday in the calendar (check 5).
  - Alamein and Williamstown stay in the forecast with a caveat (check 4).
  - `Richmond and City Loop` is kept in totals but flagged as not a corridor line.
- Day 3, step 2: March 2025's +16% is real and recurs every year, confirmed against DTP's official patronage (check 8). The cause isn't established, so none is stated.
- Day 4: the cause of the Hurstbridge level shift (Oct 2024 – Mar 2025) is still unknown. It's recorded as a limitation, not an open question, because it doesn't block anything.
