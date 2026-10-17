# Weekday demand on Melbourne's metro network: five findings

**For:** Performance, Planning and Reporting manager, Metro Trains Melbourne
**From:** Dylan Kapadia · October 2026
**Based on:** DTP Train Service Passenger Counts FY2024-25 (1 Jul 2024 – 30 Jun 2025), checked against DTP's official monthly patronage. Dashboard: `powerbi/metro_demand.pbix`

---

### 1. Next quarter's weekday peak is flat, and the forecast is twice as accurate as "same as last week"
- **The outlook:** about **197,000** AM peak boardings on a normal weekday across 15 lines for Jul–Sep 2025 (80% range 167k–231k). School holiday weekdays come in about 14% lower.
- **The accuracy:** over a 13-week back-test, the forecast missed by **8.0%**, against **16.2%** for a "same as last week" baseline. It was better on 14 of 15 lines.
- **The real outcome:** the forecast ran about 3 index points above the official figures for Jul–Sep 2025, within the precision of that comparison.

**Recommendation:** use the forecast as a **planning range, not a single number**. Score every future forecast against a simple baseline, so it's clear when a model is adding value.

### 2. Hybrid work has reshaped the week: the Friday morning peak is a third smaller than Tuesday's
- **AM peak by day** (100 = the average normal weekday): Tuesday **114**, Wednesday 108, Thursday 109, Monday 92, **Friday 76**.
- **Confirmed independently:** DTP's official patronage shows the same pattern.

**Recommendation:** review whether Friday AM peak services can be trimmed or re-allocated towards Tuesday–Thursday. Treat Friday mornings as a lower-impact window for short planned works.

### 3. Crowding is concentrated on a few inbound trains and a few stations
- **The ten most crowded regular services are all inbound,** departing between 07:19 and 07:59.
- **Craigieburn has four of the ten.** The single busiest is the **Sunbury 07:53**, averaging about **1,046** passengers at Footscray.
- **Pinch points:** loads peak just outside the CBD, at **Footscray, Kensington, Caulfield and Richmond**.
- **Trains per line matter as much as passengers per line.** Belgrave (465 average peak load) and Cranbourne (399) run the fullest trains, on far fewer services than Frankston (246 on 60 services).

**Recommendation:** target extra or longer trains at the **07:30–08:00 inbound departures on the Craigieburn, Sunbury and Werribee corridors**. Review how AM peak services are shared between Belgrave/Cranbourne and the less crowded lines.

### 4. School holidays cut commuting by a quarter, and weekends almost remove it
- **School holiday weekdays:** whole-day demand is **14%** below a normal weekday, but the AM peak is **27%** lower.
- **Weekends and public holidays:** the AM peak falls **88–92%**.

**Recommendation:** prioritise **school holiday weekdays** for weekday planned works and occupations. Apart from public holidays, they carry the network's lowest weekday commuter load, and that can be quantified line by line from this data.

### 5. March is the busiest month every year
- **March 2025:** weekday demand ran **16%** above the yearly average, across every line and every day of the week.
- **Every year:** DTP's official figures show March as the peak month in every year from 2018 to 2026 (+8% to +16% on Feb/May).

**Recommendation:** plan March as the network's **peak month**. Avoid planned works, and maximise fleet availability. Build March into capacity and reliability targets.

---

### Limitations
1. **The counts are DTP's modelled estimates, and a passenger who changes trains is counted twice.** Network boardings run about 26% above barrier entries, and hubs such as Flinders Street and Richmond are inflated. The monthly and weekly *patterns* match the official figures closely (correlation 0.999), but individual train loads are indicative, not exact.
2. **The data covers one year, all before the Metro Tunnel opened.** The forecast can't learn yearly seasonality, and line patterns on Sunbury, Pakenham and Cranbourne may now differ.

### Next steps with Metro's internal data
- **Validate crowding:** compare the busiest services with **automatic passenger counts or load-weigh data**, and express loads as **% of seated and total capacity** using consist and timetable data.
- **Count passengers, not boardings:** use **myki tap-on/tap-off journey data** to separate genuine transfers from new trips.
- **Retrain after the Metro Tunnel:** refit the forecast on post-opening data, and add **prior years** so each public holiday and the March peak are learned directly.
- **Label disruptions properly:** replace the inferred disruption days with **operational incident and planned-works records**.
