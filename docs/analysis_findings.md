# Analysis findings

The answers to the seven analysis questions, one finding per question with the numbers behind it. These numbers feed the README, the insight summary and the dashboard. They are final only once all three match.

- **Source queries:** `sql/06_analysis.sql`, run against the `MART` tables built by `sql/05_marts.sql`.
- **Data:** DTP Train Service Passenger Counts, FY2024-25 (1 Jul 2024 – 30 Jun 2025), Metro Trains only.
- **Status:** draft, 11 Oct 2026. The numbers have not yet been checked against the dashboard.

**Reading the numbers**
- Boardings are DTP's **modelled estimates**, rounded to multiples of 10.
- A boarding is one passenger getting on one train, so a trip with a change of trains counts twice. That's why Flinders Street, Richmond and North Melbourne look bigger here than in barrier entries.
- "Weekday" means a **normal weekday**, not a public or school holiday (199 days), unless stated otherwise.
- The model's monthly and day-of-week patterns match DTP's official myki-based patronage (correlation 0.999; data quality check 8), so the patterns below can be trusted even though the counts are modelled.

## Headline findings

| # | Question | Finding | Key number |
|---|---|---|---|
| 1 | Busiest stations | Ten stations handle over half of all weekday boardings, and Flinders Street alone handles a fifth | Top 10 = **52.9%**; Flinders Street **20.6%** (~155k a day) |
| 2 | Busiest lines | Pakenham carries the most AM peak passengers; Belgrave runs the fullest trains | Pakenham **19.1k** per AM peak; Belgrave **465** average peak load |
| 3 | Weekends and holidays | The AM peak almost disappears at weekends, and drops by a quarter in school holidays | AM peak: Sunday **−92%**, school holidays **−27%** |
| 4 | Day of week | Hybrid work shows clearly: Tue–Thu are busiest, and Friday's morning peak is a third smaller than Tuesday's | Friday AM peak index **76** vs Tuesday **114** |
| 5 | Monthly trend | March is the busiest month, every year | March 2025 **+16%** above the average weekday |
| 6 | Busiest services | The most crowded trains are inbound AM peak trains on the western, northern and south-eastern corridors | Sunbury 07:53: **1,046** average peak load at Footscray |
| 7 | Window functions | The 7-day average more than halves over Christmas–New Year | **771k** (mid-March) to **326k** (New Year week) |

## Q1. Top 10 stations by weekday boardings

**Finding:** ten stations handle 52.9% of weekday boardings, and the top five alone handle 43.7%.

| Rank | Station | Avg weekday boardings | Share | Cumulative share | Transfer hub |
|---|---|---|---|---|---|
| 1 | Flinders Street | 154,863 | 20.6% | 20.6% | Yes |
| 2 | Southern Cross | 67,119 | 8.9% | 29.5% | |
| 3 | Melbourne Central | 41,042 | 5.5% | 34.9% | |
| 4 | Richmond | 36,690 | 4.9% | 39.8% | Yes |
| 5 | Parliament | 29,014 | 3.9% | 43.7% | |
| 6 | Flagstaff | 17,505 | 2.3% | 46.0% | |
| 7 | North Melbourne | 13,612 | 1.8% | 47.8% | Yes |
| 8 | South Yarra | 13,587 | 1.8% | 49.6% | |
| 9 | Footscray | 12,993 | 1.7% | 51.3% | |
| 10 | Caulfield | 12,012 | 1.6% | 52.9% | |

- **Transfers inflate the hubs.** Flinders Street's 20.6% falls to 11.0% when measured as barrier entries, which count each passenger once. Richmond (2.92 boardings per entry) and North Melbourne (2.99) are inflated the same way.
- **The ranking is stable, though.** Both measures put the same top three in the same order: Flinders Street, Southern Cross, Melbourne Central.

## Q2. Lines: AM peak volume vs crowding

**Finding:** Pakenham carries the most AM peak passengers (19.1k each weekday morning, 9.8% of the network's AM peak). Belgrave and Cranbourne run the fullest trains, because they carry high demand on comparatively few services.

| Line | Avg AM peak boardings | Share of AM peak | AM peak services | Avg peak load, regular AM services |
|---|---|---|---|---|
| Pakenham | 19,068 | 9.8% | 45 | 367 |
| Lilydale | 18,156 | 9.4% | 51 | 288 |
| Mernda | 17,967 | 9.3% | 47 | 349 |
| Werribee | 16,260 | 8.4% | 46 | 360 |
| Craigieburn | 16,163 | 8.3% | 41 | 379 |
| Cranbourne | 12,333 | 6.4% | 27 | **399** |
| Belgrave | 11,121 | 5.7% | 23 | **465** |
| Frankston | 16,070 | 8.3% | 60 | 246 |

*Selected lines. All 17 corridor lines are in query Q2.*

- **More passengers doesn't mean fuller trains.** Frankston carries about the same AM peak volume as Craigieburn but runs 60 services to Craigieburn's 41, so its trains are about a third less full (246 vs 379).
- **Data caveat:** Alamein and Williamstown are understated. About 22% and 13% of their stop records have no data.

## Q3. Weekends and holidays vs a normal weekday

**Finding:** whole-day demand falls by 43–60% at weekends and on public holidays. The AM peak almost disappears on those days (−88% to −92%). School holidays take 14% off the whole day but 27% off the AM peak, so they mainly hit commuting.

| Day type | Days | Avg daily boardings | vs normal weekday | AM peak vs normal weekday |
|---|---|---|---|---|
| Normal Weekday | 199 | 752,932 | — | — |
| School Holiday (weekday) | 51 | 646,895 | −14.1% | −26.7% |
| Saturday | 51 | 427,771 | −43.2% | −87.8% |
| Sunday | 51 | 309,347 | −58.9% | −92.0% |
| Public Holiday | 13 | 304,353 | −59.6% | −91.1% |

## Q4. Day of week (hybrid work)

**Finding:** Tuesday to Thursday run 5–7% above an average weekday, while Monday and Friday run 6–11% below. The AM peak shows it most strongly: Friday's morning peak (index 76) is a third smaller than Tuesday's (114).

| Day | Whole day index | AM peak index |
|---|---|---|
| Monday | 88.9 | 92.4 |
| Tuesday | 105.3 | **114.4** |
| Wednesday | 104.7 | 107.8 |
| Thursday | 107.3 | 109.0 |
| Friday | 93.8 | **76.4** |

*Index: 100 = the average normal weekday.*

- **The official data agrees.** DTP's figures give Mon 89.6, Tue 105.2, Wed 104.1, Thu 106.8 and Fri 94.4 (data quality check 8), so this isn't an artefact of the model.

## Q5. Monthly trend

**Finding:** weekday demand is flat for most of the year. It dips over summer (Dec–Jan, about 91–93% of average) and peaks in March (116%). DTP's official patronage shows March as the peak month in every year from 2018 to 2026, so the peak is seasonal, not a one-off.

| Month | Normal weekdays | Avg weekday boardings | Index |
|---|---|---|---|
| Jul 2024 | 13 | 728,771 | 97.7 |
| Aug 2024 | 22 | 771,713 | 103.4 |
| Sep 2024 | 15 | 749,188 | 100.4 |
| Oct 2024 | 19 | 750,818 | 100.6 |
| Nov 2024 | 20 | 714,312 | 95.7 |
| Dec 2024 | 15 | 691,041 | 92.6 |
| Jan 2025 | 3 | 676,390 | 90.7 |
| Feb 2025 | 20 | 737,132 | 98.8 |
| **Mar 2025** | 20 | **866,680** | **116.2** |
| Apr 2025 | 10 | 779,857 | 104.5 |
| May 2025 | 22 | 792,501 | 106.2 |
| Jun 2025 | 20 | 694,384 | 93.1 |

*Index: 100 = the average of the 12 months. These are simple daily averages; check 8 averages by day of week first, so its March figure is 116.3.*

- **The whole of March is high,** not just a few event days. Every day of the week is up across the month: March Tuesdays to Thursdays ran at 874k–1.01M (a typical Tue–Thu is about 795k), Mondays at 765k–796k (typically 669k) and Fridays at 759k–912k (typically 705k).
- **Every line rises,** but unevenly: Pakenham and Cranbourne +20%, most lines +10–15%, Hurstbridge +5% (query Q5b, compared with February and May).
- **Not established:** why March is high. A full month of school and university semester 1 with no holidays, plus major events, is plausible, but these sources don't confirm it. No planned works were found that would have pushed February or May down.

## Q6. Busiest regular services

**Finding:** all ten of the most crowded regular services are inbound AM peak trains on the western, northern and south-eastern corridors. They peak between 08:00 and 08:50 at a handful of stations just outside the CBD: Footscray, Kensington, Caulfield and Richmond. Craigieburn has four of the ten.

| Rank | Line | Departs | Route | Peaks at | Peak time | Avg peak load |
|---|---|---|---|---|---|---|
| 1 | Sunbury | 07:53 | Sunbury → Flinders St | Footscray | 08:29 | 1,046 |
| 2 | Craigieburn | 07:53 | Craigieburn → Flinders St | Kensington | 08:24 | 999 |
| 3 | Craigieburn | 07:39 | Craigieburn → Flinders St | Kensington | 08:10 | 964 |
| 4 | Craigieburn | 07:30 | Craigieburn → Flinders St | Kensington | 08:01 | 932 |
| 5 | Pakenham | 07:19 | East Pakenham → Flinders St | Caulfield | 08:20 | 883 |
| 6 | Cranbourne | 07:38 | Cranbourne → Flinders St | Caulfield | 08:23 | 881 |
| 7 | Pakenham | 07:35 | East Pakenham → Flinders St | Richmond | 08:47 | 878 |
| 8 | Craigieburn | 07:45 | Craigieburn → Flinders St | Kensington | 08:16 | 864 |
| 9 | Werribee | 07:59 | Werribee → Flinders St | Footscray | 08:25 | 862 |
| 10 | Werribee | 07:49 | Werribee → Flinders St | Newport | 08:09 | 851 |

- **Pinch points:** across the top 50, the most common peak stations are Footscray (8 services), Kensington (6) and Richmond (6).
- **Which services count:** only regular services are ranked, meaning trains running on at least 100 of the 199 normal weekdays. Otherwise one-off event trains would top the list.
- **Caveat:** DTP's model has no capacity limit, so read these loads as "very crowded", not exact counts.

## Q7. Window functions

- **`RANK() OVER (PARTITION BY line_name …)`** gives the three busiest suburban stations on each line, with the CBD stations excluded. Examples:
  - Box Hill is #1 on both Lilydale (5,218 a weekday) and Belgrave.
  - Footscray is #1 on Sunbury, Werribee and Williamstown.
  - Caulfield is #1 on Pakenham and Frankston.
- **`AVG() OVER (ORDER BY business_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)`** gives a 7-day moving average, which smooths out the weekday/weekend cycle. It peaks at 771k (12–18 March 2025) and bottoms out at 326k (30 Dec 2024 – 5 Jan 2025), a drop of 58%.

## Limitations

- **One year of modelled data.** The counts are estimates. They're validated against official totals for shape, not for exact levels.
- **Transfers count as boardings.** This inflates the hubs (Q1) and raises the network total about 26% above the number of passengers.
- **Quiet lines are understated.** Alamein, Williamstown and Stony Point have many stop records with no data.
- **Before the Metro Tunnel.** All FY2024-25 data comes from before the Metro Tunnel opened, so current line patterns, especially Sunbury, Pakenham and Cranbourne, may differ.
