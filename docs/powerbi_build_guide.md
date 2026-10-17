# Power BI build guide

Step-by-step instructions for building `powerbi/metro_demand.pbix` from the Snowflake marts. **Allow about 2–3 hours.** Each step ends with a check, so problems surface early.

**Files used:**
- `powerbi/measures.dax`: every measure, as one DAX query
- `powerbi/metro_theme.json`: colours and fonts
- `sql/07_powerbi.sql`: the lookup tables for days, time bands and stations. It must have been run.

---

## 1. Connect to Snowflake and import

1. **Turn off auto-relationships first.** Open Power BI Desktop and go to **File → Options and settings → Options → Current file → Data Load**. Untick **"Autodetect new relationships after data is loaded"**. You'll set the relationships yourself in step 2.
2. **Connect.** Go to **Home → Get data → More… → Database → Snowflake → Connect**.
   - **Server:** `<your-account-identifier>.snowflakecomputing.com`. This is the `account` value in your Snowflake CLI `config.toml`.
   - **Warehouse:** `METRO_WH`
   - **Advanced options:** Role `SYSADMIN`, Database `METRO_DB`
   - **Data connectivity mode: Import.** The data is copied into the `.pbix`, so the dashboard keeps working after the Snowflake trial ends.
   - **Sign in:** choose **Snowflake** (username/password) and use the same login as the CLI.
3. **Pick the tables.** In the Navigator, expand **METRO_DB → MART** and tick all **12 tables** (every table in MART):

   | Lookup (dimension) tables | Fact tables |
   |---|---|
   | `DIM_CALENDAR`, `DIM_LINE`, `DIM_DAY_TYPE`, `DIM_TIME_BAND`, `DIM_STATION` | `DAILY_LINE_DEMAND`, `STATION_SUMMARY`, `HOURLY_PROFILE`, `PEAK_LOAD_SERVICES`, `FORECAST_LINE_DEMAND`, `FORECAST_BACKTEST`, `FORECAST_METRICS` |

   Leave the `STAGING` and `RAW` schemas alone; the 14.5M-row staging table isn't needed. Then click **Load**.
4. **Create the measures table.** Go to **Home → Enter data**, name the table `_Measures`, and click **Load**. It's an empty holder for the measures.

**Check:** the Data pane lists 13 tables: the 12 from MART plus `_Measures`. The largest, `DAILY_LINE_DEMAND`, has 30,800 rows.

## 2. Model: relationships, date table, sorting

**Relationships.** Open **Model view** and create each relationship by dragging the column from the lookup table onto the fact table. All are **one-to-many, single direction**.

| From (one side) | To (many side) |
|---|---|
| `DIM_CALENDAR[CALENDAR_DATE]` | `DAILY_LINE_DEMAND[BUSINESS_DATE]`, `FORECAST_LINE_DEMAND[DATE]`, `FORECAST_BACKTEST[DATE]` |
| `DIM_LINE[LINE_NAME]` | `DAILY_LINE_DEMAND[LINE_NAME]`, `HOURLY_PROFILE[LINE_NAME]`, `PEAK_LOAD_SERVICES[LINE_NAME]`, `FORECAST_LINE_DEMAND[LINE_NAME]`, `FORECAST_BACKTEST[LINE_NAME]` |
| `DIM_DAY_TYPE[DAY_TYPE]` | `DAILY_LINE_DEMAND[DAY_TYPE]`, `STATION_SUMMARY[DAY_TYPE]`, `HOURLY_PROFILE[DAY_TYPE]` |
| `DIM_TIME_BAND[TIME_BAND]` | `DAILY_LINE_DEMAND[TIME_BAND]`, `HOURLY_PROFILE[TIME_BAND]` |
| `DIM_STATION[STATION_NAME]` | `STATION_SUMMARY[STATION_NAME]`, `PEAK_LOAD_SERVICES[USUAL_PEAK_STATION]` |

- **`FORECAST_METRICS` stays unconnected.** Its `LINE_NAME` includes "Network" and "All lines", which aren't real lines, so the measures set their own filters instead.
- **Don't link `DIM_CALENDAR[DAY_TYPE]` to `DIM_DAY_TYPE`.** That would create two filter paths into `DAILY_LINE_DEMAND`, and Power BI would deactivate one of them.

**Mark the date table.** Select `DIM_CALENDAR`, then **Table tools → Mark as date table → `CALENDAR_DATE`**.

**Sort by column.** Select the column, then **Column tools → Sort by column**:
- `DIM_DAY_TYPE[DAY_TYPE]` by `SORT_ORDER`
- `DIM_TIME_BAND[TIME_BAND]` by `SORT_ORDER`
- `DIM_CALENDAR[MONTH_LABEL]` by `MONTH_START`
- `DIM_CALENDAR[DAY_OF_WEEK]` by `DAY_OF_WEEK_NUM`

**Check:** Model view shows 15 relationship lines, all solid. A dashed line means a relationship is inactive.

## 3. Measures and theme

1. **Add the measures.** Open **DAX query view** (the DAX icon in the left bar), paste the whole of `powerbi/measures.dax` and click **Run**.
2. **Compare the result row with the expected values** in the column headers:

   | Measure | Expected |
   |---|---|
   | Total Boardings | 224,374,850 |
   | Avg Weekday Boardings | 752,932 |
   | AM Peak Share % | 0.214 |
   | Busiest Line | Pakenham |
   | Forecast Avg Normal Weekday | 197,024 |
   | Network Forecast WAPE | 0.080 |
   | Network Baseline WAPE | 0.162 |
   | Actual AM Peak, 1 Apr 2025 | 244,340 |
   | Flinders St, normal weekday | 154,863 |
   | Saturday vs normal weekday | −0.432 |
   | Saturday AM peak vs normal weekday | −0.878 |
   | 7D MA, 18 Mar 2025 | 771,023 |

   If a value differs, check the relationships in step 2 before going on.
3. **Save the measures to the model.** Click **Update model: Add new measures**.
   - **If you've already added the measures in an earlier run,** re-running the updated file adds only the new ones. Measures that haven't changed are left as they are.
4. **Format them.** In the Data pane, select each % measure (`AM Peak Share %`, `vs Normal Weekday %`, `vs Normal Weekday % (AM Peak)`, the four WAPE measures) and set **Measure tools → Format → Percentage, 1 decimal**. Set the boardings measures to **Whole number with thousands separator**.
5. **Apply the theme.** Go to **View → Themes → Browse for themes** and pick `powerbi/metro_theme.json`. The theme's font sizes are set for a 1920 × 1080 canvas. If you applied an earlier version, browse to it again to reload it.
6. **Set the canvas size on every page.** Click an empty part of the page, then in **Format page → Canvas settings** set **Type: Custom, Width 1920, Height 1080**. Do this for each of the three pages.
   - **Exact positions:** select a visual and use **Format → General → Properties → Size and Position**. The page tables below give X, Y, width and height in pixels.
   - **Grid:** 24 px margins on every side, 16 px gaps between visuals.

**Colour rule:**
- **Navy:** actual demand, the main measure.
- **Orange:** the forecast only.
- **Grey:** comparisons, such as the baseline.

**Every visual:** put units in the title, e.g. "Average weekday boardings (passengers per day)". No pie or 3D charts.

---

## 4. Page 1: Network overview

**Question on the page:** *How busy is the network, and how does it change through the year?*

**Page setup.** Canvas 1920 × 1080 (see section 3, step 6). Rename the page **Network overview**.

**Layout:** title and slicers in the header, four KPI cards in one row, then the line chart (about 60% width) beside the bar chart (about 40%), and a source line at the bottom.

```
 x: 24                                                          1896
┌──────────────────────────────────────────────────────────────────────────┐
│ ① Title + subtitle                                   ② Month ▾  ③ Day type ▾ │  y 16-112
├────────────────┬────────────────┬────────────────┬───────────────────────┤
│ ④ 753K         │ ⑤ 21.4%        │ ⑥ Pakenham     │ ⑦ 8.0%                │  y 128-264
├────────────────┴────────────────┴───────┬────────┴───────────────────────┤
│ ⑧ Line chart                            │ ⑨ Bar chart                    │  y 280-1008
│   daily grey, 7-day average navy        │   whole day grey, AM peak navy │
├─────────────────────────────────────────┴────────────────────────────────┤
│ ⑩ Source line                                                            │  y 1024-1064
└──────────────────────────────────────────────────────────────────────────┘
```

**Size and position** (pixels, for **Format → General → Properties**):

| # | Visual | X | Y | Width | Height |
|---|---|---|---|---|---|
| 1 | Title text box | 24 | 16 | 1100 | 96 |
| 2 | Month slicer | 1440 | 24 | 220 | 72 |
| 3 | Day type slicer | 1676 | 24 | 220 | 72 |
| 4 | Card: avg weekday boardings | 24 | 128 | 456 | 136 |
| 5 | Card: AM peak share | 496 | 128 | 456 | 136 |
| 6 | Card: busiest line | 968 | 128 | 456 | 136 |
| 7 | Card: forecast error | 1440 | 128 | 456 | 136 |
| 8 | Line chart | 24 | 280 | 1120 | 728 |
| 9 | Bar chart | 1160 | 280 | 736 | 728 |
| 10 | Source text box | 24 | 1024 | 1872 | 40 |

| # | Visual | Fields | Settings |
|---|---|---|---|
| 1 | Text box (title) | "Melbourne metro trains: where and when demand is highest", with a subtitle line "FY2024-25 · DTP modelled passenger counts" | Title navy `#1F3A5F`, 30 pt, Segoe UI Semibold. Subtitle grey `#52514E`, 16 pt |
| 2 | Slicer | `DIM_CALENDAR[MONTH_LABEL]` | Style **Dropdown**. Rename the field to "Month" for this visual (double-click it in the field well). **Visual filter:** `HAS_PASSENGER_DATA` = True, so only FY2024-25 months appear. Header 12 pt |
| 3 | Slicer | `DIM_DAY_TYPE[DAY_TYPE]` | Style **Dropdown**, multi-select. Rename it to "Day type". Header 12 pt, the same as the month slicer |
| 4 | Card | `[Avg Weekday Boardings]` | Title "Avg boardings per normal weekday", 14 pt. Display units: Thousands (shows 753K). Callout value about 40 pt, colour navy `#1F3A5F`. The new card visual ignores the theme's callout colour, so set it on each card |
| 5 | Card | `[AM Peak Share %]` | Title "Share of boardings in AM peak (07:00–09:00)", 14 pt |
| 6 | Card | `[Busiest Line]` | Title "Busiest line (total boardings)", 14 pt |
| 7 | Card | `[Network Forecast WAPE]` | Title "Forecast error (WAPE), Apr–Jun back-test", 14 pt. **Reference label:** add `[Network Baseline WAPE]` (**Format → Reference labels**), titled "Baseline", so the card reads 8.0% with "Baseline 16.2%" underneath |
| 8 | Line chart | X: `DIM_CALENDAR[CALENDAR_DATE]`. Y: `[Total Boardings]`, `[Boardings 7D MA]` | Title "Demand peaks in March and halves over Christmas (passengers per day)", 18 pt. **Visual filter:** `HAS_PASSENGER_DATA` = True. **Lines:** `Total Boardings` light grey `#C8C7C2`, 1.5 px; `Boardings 7D MA` navy `#1F3A5F`, 4 px. Rename the series in the field well to "Daily" and "7-day average". **Axes:** labels 12 pt; Y axis display units Thousands |
| 9 | Clustered bar chart | Y: `DIM_DAY_TYPE[DAY_TYPE]`. X: `[vs Normal Weekday %]`, `[vs Normal Weekday % (AM Peak)]` | Title "Weekend commuting almost disappears (vs a normal weekday)", 18 pt. It fits on one line. Rename the series to "Whole day" (grey `#8A8984`) and "AM peak" (navy `#1F3A5F`). **Visual filter:** `DAY_TYPE` is not Normal Weekday. **X axis:** range −100% to 0%, labels 12 pt. Data labels on, 12 pt. Legend on, top, 12 pt |
| 10 | Text box (source) | "Source: DTP Train Service Passenger Counts FY2024-25 (modelled estimates, CC BY 4.0). Boardings count every train a passenger takes, including transfers." | Segoe UI, grey `#52514E`, 11 pt, left-aligned |

**Clean-up for every visual:**
- **Cards:** turn off the **category label / label** (the measure name under the number) so only your title shows. Turn off the card border if it doesn't match the other visuals.
- **Charts:** turn off **Subtitle**. Power BI's auto-subtitle ("Total Boardings and Boardings 7D MA by CALENDAR_DATE") repeats the field names.
- **Orange is reserved for the forecast** (page 3). Nothing on this page is orange.
- **Alignment:** the size-and-position table puts everything on the grid (24 px margins, 16 px gaps). If you place visuals by hand instead, select the visuals in a row and use **Format → Align → Align top**, then **Distribute horizontally**.
- **Alt text:** add a one-sentence description to each chart (**General → Alt text**), for example "Line chart: daily network boardings and 7-day average, July 2024 to June 2025. Peaks in March, lowest over Christmas–New Year."

**Optional annotations:** two small grey text boxes on the line chart, "Labour Day (10 Mar)" and "Christmas–New Year", next to the two biggest dips.

**Check page 1, with no slicers selected:**

| Visual | Expected |
|---|---|
| Card 4 | **753K** (752,932) |
| Card 5 | **21.4%** (25.7% with "Normal Weekday" selected) |
| Card 6 | **Pakenham** |
| Card 7 | **8.0%** |
| Bar chart, whole day | School Holiday −14.1%, Saturday −43.2%, Sunday −58.9%, Public Holiday −59.6% |
| Bar chart, AM peak | School Holiday −26.7%, Saturday −87.8%, Sunday −92.0%, Public Holiday −91.1% |
| Line chart | The 7-day average peaks around mid-March 2025 (771k) and bottoms out in the New Year week (326k). The daily line's highest point is Thu 13 Mar 2025 (about 1.01M) |

**Send me a screenshot of page 1 before going on.**

## 5. Page 2: Lines and stations

**Question:** *Where and when is demand concentrated?*

**Page setup.** Canvas 1920 × 1080. Rename the page **Lines and stations**. The header and footer match page 1, so all three pages line up.

**Layout:**

```
 x: 24                                                          1896
┌──────────────────────────────────────────────────────────────────────────┐
│ ① Title + subtitle                                 ② Day type ▾  ③ Line ▾  │  y 16-112
├────────────────────────┬────────────────────────┬────────────────────────┤
│ ④ Boardings by line    │ ⑤ Top 15 stations      │ ⑥ Station map          │  y 128-560
│   (bar)                │   (bar)                │   (optional)           │
├────────────────────────┴────────────────┬───────┴────────────────────────┤
│ ⑦ Heatmap: line × departure time        │ ⑧ 10 most crowded services     │  y 576-1008
│                                         │   (table)                      │
├─────────────────────────────────────────┴────────────────────────────────┤
│ ⑨ Source and capacity note                                               │  y 1024-1064
└──────────────────────────────────────────────────────────────────────────┘
```

**Size and position** (pixels):

| # | Visual | X | Y | Width | Height |
|---|---|---|---|---|---|
| 1 | Title text box | 24 | 16 | 1100 | 96 |
| 2 | Day type slicer | 1440 | 24 | 220 | 72 |
| 3 | Line slicer | 1676 | 24 | 220 | 72 |
| 4 | Bar chart: boardings by line | 24 | 128 | 600 | 432 |
| 5 | Bar chart: top 15 stations | 640 | 128 | 600 | 432 |
| 6 | Map (optional) | 1256 | 128 | 640 | 432 |
| 7 | Matrix heatmap | 24 | 576 | 1120 | 432 |
| 8 | Table: crowded services | 1160 | 576 | 736 | 432 |
| 9 | Source text box | 24 | 1024 | 1872 | 40 |

**Without the map:** make visuals 4 and 5 each **928** wide, with visual 5 at **X 968**. Everything else stays the same.

| # | Visual | Fields | Settings |
|---|---|---|---|
| 1 | Text box (title) | "Lines and stations: where and when demand concentrates", with a subtitle line "Boardings per day, FY2024-25 · choose a day type and line" | Same styles as page 1: navy 30 pt, subtitle grey 16 pt |
| 2 | Slicer | `DIM_DAY_TYPE[DAY_TYPE]` | Dropdown, renamed "Day type". **Default: select Normal Weekday** before saving, so the page opens on a typical weekday |
| 3 | Slicer | `DIM_LINE[LINE_LABEL]` | Dropdown, renamed "Line". **Visual filter:** `IS_CORRIDOR_LINE` = True |
| 4 | Clustered bar chart | Y: `DIM_LINE[LINE_LABEL]`. X: `[Avg Daily Boardings]` | Title "Boardings per day by line (all stations on the line)", 18 pt. **Visual filter:** `IS_CORRIDOR_LINE` = True (17 lines). Sort descending. Bars navy. Data labels on (Thousands). **All 17 bars must fit with no scrollbar:** reduce **Y axis → Minimum category width** or **Bars → Layout → Space between categories**. Rename the series "Boardings per day" |
| 5 | Clustered bar chart | Y: `DIM_STATION[STATION_NAME]`. X: `[Avg Station Boardings]` | Title "Top 15 stations: boardings per day", 18 pt. **Visual filter:** `STATION_NAME`, Top N = 15 by `[Avg Station Boardings]`. Bars navy, data labels on (12 pt, Thousands). **Tooltips:** `DIM_STATION[LINES_SERVED]`, `DIM_STATION[BOARDINGS_PER_ENTRY]` |
| 6 | *(optional)* Azure Map | Latitude: `DIM_STATION[STATION_LATITUDE]`. Longitude: `DIM_STATION[STATION_LONGITUDE]`. Size: `[Avg Station Boardings]`. Tooltips: `STATION_NAME`, `LINES_SERVED` | Title "Where the boardings are", 18 pt. Bubbles navy, about 40% transparency. Base map style **Grayscale (light)** so the bubbles stand out. If the map visual is disabled on your install, skip it and widen visuals 4 and 5 (see above) |
| 7 | Matrix (heatmap) | Rows: `DIM_LINE[LINE_LABEL]` (renamed "Line"). Columns: `HOURLY_PROFILE[HOUR_LABEL]` (a calculated column, see below). Values: `[Avg Half-Hour Boardings]` | Title "When each line is busiest: boardings per day by departure hour", 18 pt. **Visual filters:** `INCLUDE_IN_FORECAST` = True (15 lines; Flemington Racecourse and Stony Point are near-empty rows); `HOUR_LABEL` from 05:00 to 23:00 (19 columns). **Cell elements → Background colour → on**: gradient, lowest white, highest navy `#1F3A5F`. **Font colour** the same gradient, so the numbers disappear and only the colour shows. Turn off row and column subtotals. **Fitting 15 rows with no scrollbar:** Grid → Options → **Row padding 0**; **Values** font 8 pt (the hidden numbers still set the row height); row headers 11 pt with text wrap off; column headers 10 pt. Column headers → Options → auto-size width off, columns about 48 px |
| 8 | Table | `PEAK_LOAD_SERVICES`: `LOAD_RANK`, `LINE_NAME`, `TRAIN_NUMBER`, `USUAL_FIRST_DEPARTURE`, `USUAL_PEAK_STATION`, `USUAL_PEAK_TIME`, `AVG_PEAK_LOAD` | Title "10 most crowded services (avg peak load, normal weekdays)", 18 pt. It must fit on one line, or row 10 is pushed out of view. **Visual filters:** `IS_REGULAR_SERVICE` = True, `LOAD_RANK` ≤ 10. Sort by `LOAD_RANK` ascending. Rename the columns: "#", "Line", "Train", "Departs", "Fullest at", "Time", "Avg peak load". Values 12 pt. **Column formats, in Data view (Column tools → Format):** `LOAD_RANK` and `AVG_PEAK_LOAD` as **Whole number**, with the thousands separator on `AVG_PEAK_LOAD` (shows 1,046); the two time columns as Custom `hh:mm`. **Data bars** on `AVG_PEAK_LOAD` in light navy `#A9BCD3` (**Cell elements → Data bars**), so the dark numbers stay readable on top. The table ignores the day-type slicer: it always shows normal weekdays, which is why the title says so |
| 9 | Text box (source) | "Source: DTP Train Service Passenger Counts FY2024-25 (modelled estimates, CC BY 4.0). DTP's model has no capacity limit: read high loads as 'very crowded', not exact counts." | Segoe UI, grey `#52514E`, 11 pt, left-aligned, no background |

**Calculated column for the heatmap.** In **Data view**, select `HOURLY_PROFILE`, then **Table tools → New column**:

```dax
HOUR_LABEL = LEFT ( HOURLY_PROFILE[HALF_HOUR_LABEL], 2 ) & ":00"
```

Each hour then combines its two half-hour blocks: `[Avg Half-Hour Boardings]` adds them together, so no new measure is needed. 38 half-hour columns don't fit across the visual; 19 hourly columns do.

**Interactions.** Select the line slicer (3), then **Format → Edit interactions**. Set the **top-15 stations** chart (5) and the **map** (6) to *None*. Station figures cover every line through a station, so they can't be split by line.

**Check page 2, with Normal Weekday selected and no line selected:**

| Visual | Expected |
|---|---|
| Bar chart by line | Pakenham **85,551**, Lilydale **70,144**, Frankston **61,697**, Cranbourne **61,477**, Mernda **60,605** (these count every boarding along the line, including at CBD stations) |
| Top stations | Flinders Street **154,863**, Southern Cross **67,119**, Melbourne Central **41,042** … 15th Oakleigh **5,527** |
| Heatmap | 15 rows (Alamein to Williamstown), 19 hourly columns, no scrollbars. The darkest cells are Pakenham 17:00 (**11,405**), Lilydale 08:00 (**10,809**), Mernda 08:00 (**10,382**) and Pakenham 08:00 (**10,208**). Pakenham is the only line busier in the PM peak than the AM peak. Hover to see the values |
| Services table | All 10 rows visible with no scrollbar. #1 is Sunbury train 6626, departing 07:53, fullest at Footscray at 08:29, average load **1,046**; #10 is Werribee 6424, **851** |
| Map (if used) | 222 stations, largest bubble at Flinders Street |

**Send me a screenshot of page 2 before going on.**

## 6. Page 3: Forecast

**Question:** *What will next quarter's weekday AM peak look like, and how much can we trust it?*

**Page setup.** Canvas 1920 × 1080. Rename the page **Forecast**. Same header and footer as pages 1 and 2.

**Layout:** the forecast chart leads, with the two headline cards and the conclusions beside it, and accuracy by line across the bottom.

```
 x: 24                                                          1896
┌──────────────────────────────────────────────────────────────────────────┐
│ ① Title + subtitle                                              ② Line ▾  │  y 16-112
├─────────────────────────────────────────────┬────────────────────────────┤
│ ③ Actual Apr–Jun + forecast Jul–Sep         │ ④ 197K forecast            │  y 128-264
│    with 80% band (line chart)               ├────────────────────────────┤
│                                             │ ⑤ 8.0% error, Baseline 16.2% │  y 280-416
│                                             ├────────────────────────────┤
│                                             │ ⑥ Three conclusions        │  y 432-688
├─────────────────────────────────────────────┴────────────────────────────┤
│ ⑦ Back-test error by line: forecast vs baseline (column chart)           │  y 704-1008
├──────────────────────────────────────────────────────────────────────────┤
│ ⑧ Source and method note                                                 │  y 1024-1064
└──────────────────────────────────────────────────────────────────────────┘
```

**Size and position** (pixels):

| # | Visual | X | Y | Width | Height |
|---|---|---|---|---|---|
| 1 | Title text box | 24 | 16 | 1100 | 96 |
| 2 | Line slicer | 1676 | 24 | 220 | 72 |
| 3 | Line chart: forecast | 24 | 128 | 1240 | 560 |
| 4 | Card: forecast per normal weekday | 1280 | 128 | 616 | 136 |
| 5 | Card: forecast error | 1280 | 280 | 616 | 136 |
| 6 | Text box: conclusions | 1280 | 432 | 616 | 256 |
| 7 | Column chart: error by line | 24 | 704 | 1872 | 304 |
| 8 | Source text box | 24 | 1024 | 1872 | 40 |

| # | Visual | Fields | Settings |
|---|---|---|---|
| 1 | Text box (title) | "Forecast: weekday AM peak demand, Jul–Sep 2025", with a subtitle line "15 lines · average of Prophet and SARIMAX models · back-tested on Apr–Jun 2025" | Same styles as pages 1 and 2 |
| 2 | Slicer | `DIM_LINE[LINE_LABEL]` | Dropdown, renamed "Line", single select. **Visual filter:** `INCLUDE_IN_FORECAST` = True (15 lines). With nothing selected, the page shows the network total |
| 3 | Line chart | X: `DIM_CALENDAR[CALENDAR_DATE]`. Y: `[Actual AM Peak]`, `[Forecast]` | Title "Next quarter looks flat: weekday AM peak boardings, actual Apr–Jun, forecast Jul–Sep 2025", 18 pt. Tooltips show the exact value for each day (e.g. Good Friday, 18 Apr: 13,280). **Visual filters:** `CALENDAR_DATE` from 1 Apr 2025 to 30 Sep 2025; `IS_WEEKDAY` = True. Rename the series "Actual" and "Forecast". Colours: Actual navy `#1F3A5F`, Forecast orange `#EB6834`, both 3 px. Y axis display units Thousands. **80% band:** select the visual, open the **Analytics** pane (magnifier icon) → **Error bars** → on. Series: `Forecast`. Upper bound: `[Forecast Upper 80]`. Lower bound: `[Forecast Lower 80]`. Under **Bar** turn the bars off; under **Band** turn the error band on (orange, about 80% transparency) |
| 4 | Card | `[Forecast Avg Normal Weekday]` | Title "Forecast AM peak boardings per normal weekday, Jul–Sep 2025", 14 pt. Display units Thousands, **0 decimal places** (shows 197K, not 197.02K). Callout value orange `#EB6834` (it's a forecast) |
| 5 | Card | `[Network Forecast WAPE]` | Title "Forecast error (WAPE), Apr–Jun back-test", 14 pt. **Reference label:** `[Network Baseline WAPE]`, titled "Baseline", as on page 1 |
| 6 | Text box | Heading "Key findings", then the three conclusions (below) | Heading 18 pt. Body Segoe UI 13 pt, navy bold for each lead phrase, grey `#52514E` for the rest |
| 7 | Clustered column chart | X: `FORECAST_METRICS[LINE_NAME]`. Y: `[Forecast WAPE]`, `[Baseline WAPE]` | Title "The forecast beats the baseline on 14 of 15 lines: back-test error by line, Apr–Jun 2025 (WAPE, lower is better)", 18 pt. **Visual filters (both required):** `DAY_GROUP` = "All days"; `LINE_NAME` is not "All lines". Rename the series "Forecast" (orange) and "Baseline" (grey `#8A8984`). Sort by `[Forecast WAPE]` ascending. Data labels on, 10 pt, 1 decimal, position **Auto**. **Columns → Layout:** space between series 0 and less space between categories, so the columns are wide enough for both labels in each pair (Power BI hides a label that would overlap its neighbour). X axis labels 11 pt |
| 8 | Text box (source) | "Source: DTP Train Service Passenger Counts FY2024-25 and DTP monthly patronage (CC BY 4.0). Forecast refitted on Jul 2024 – Jun 2025; method and limitations in docs/forecast_results.md." | Segoe UI, grey `#52514E`, 11 pt, left-aligned, no background |

**Why the `DAY_GROUP` filter matters.** `FORECAST_METRICS` holds four rows per line and model: All days, Normal weekdays, School holidays and Public holidays. Without the filter, the WAPE measures average all four. That includes the public-holiday scores, where the baseline's error runs into the thousands of percent (it predicts a full commuter peak on Good Friday). The chart then shows nonsense, such as Williamstown's baseline at 4,535% and Network's forecast at 22.1%.

**Text for the conclusions box:**
1. **Next quarter looks flat:** about 197k AM peak boardings on a normal weekday across the 15 lines (80% range 167k–231k). School holiday weekdays are about 14% lower.
2. **The forecast halves the error of a "same as last week" baseline** (8.0% vs 16.2% at network level). Most of the gain is on public and school holidays.
3. **Treat it as a planning range, not a point.** One year of data means no seasonal pattern: official figures dipped about 2% in Jul–Sep 2025. It was also built before the Metro Tunnel opened.

**Check page 3, with no line selected:**

| Visual | Expected |
|---|---|
| Card 4 | **197K** (197,024) |
| Card 5 | **8.0%**, with Baseline **16.2%** |
| Line chart | The actual line starts at 244,340 on Tue 1 Apr 2025. The forecast starts at 222,239 on Tue 1 Jul 2025 and dips to about 10,066 on Fri 26 Sep (AFL Grand Final eve holiday) |
| Column chart | 16 column pairs: 15 lines plus Network, y-axis about 0–22%. From the left: Belgrave **7.8% vs 14.7%**, Network **8.0% vs 16.2%**, Sandringham 8.2% vs 18.0% … ending with **Hurstbridge 18.1% vs 17.6%**, the only pair where orange is taller than grey. If any value is in the hundreds or thousands of percent, the `DAY_GROUP` filter is missing |

- **Card 4 with a line selected:** Pakenham shows **19K** (18,983).
- **The column chart and the line slicer:** the column chart reads `FORECAST_METRICS`, which isn't linked to `DIM_LINE`, so the line slicer doesn't filter it. That's intended: it always compares all lines.

**Send me a screenshot of page 3.**

---

## 7. Save and export

1. **Save** as `powerbi/metro_demand.pbix`.
2. **Set each page's opening state, then export the PDF** (**File → Export → Export to PDF** → `powerbi/metro_demand.pdf`). The PDF, and anyone opening the `.pbix`, sees the pages exactly as you left them:
   - **Page 1:** Month and Day type both "All".
   - **Page 2:** Day type **Normal Weekday**, Line "All". The page's figures and the README quote normal-weekday numbers (Flinders Street 155K, Pakenham 86K). With "All" selected, it shows averages over every day instead (131K, 66K).
   - **Page 3:** Line "All", so the network total.
3. **Take screenshots** of each page in that same state (Windows: **Win + Shift + S**, window snip). Before each one:
   - **Click an empty part of the canvas,** so no visual is selected. A selected visual shows a border and its header icons (filter, focus mode, "…").
   - **Move the mouse off the charts,** so no tooltip or hover crosshair is captured.

   Save them as:
   - `images/dashboard_1_network_overview.png`
   - `images/dashboard_2_lines_stations.png`
   - `images/dashboard_3_forecast.png`

**Before committing:**
- The `.pbix` stores the imported data, not your Snowflake password. Power BI keeps credentials separately on your machine.
- Check the file size: it should be a few MB.
