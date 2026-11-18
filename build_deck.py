"""Build the 10-slide PPTX deck (Step 8 of the skill).

Run from the project root AFTER `Rscript run_all.R`:
    ~/workspace/quant-ipo-engine/.venv/bin/python build_deck.py
Output: ~/workspace/your_files/ML_Project_Kforce_Data_Analyst_Deck_2026-11-18.pptx

Numbers come from models/*.csv (the real R run). Every "ELI5" is
replaced with a checkmark.
"""

import csv
import os

from pptx import Presentation
from pptx.util import Inches, Pt

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser(
    "~/workspace/your_files/ML_Project_Kforce_Data_Analyst_Deck_2026-11-18.pdf"
    .replace(".pdf", ".pptx"))
MODELS = os.path.join(ROOT, "models")
CHARTS = os.path.join(ROOT, "reports", "charts")

NAVY = (31, 78, 121)
TEAL = (46, 158, 107)


def read_csv(name):
    with open(os.path.join(MODELS, name)) as fh:
        return list(csv.DictReader(fh))


metrics = read_csv("metrics.csv")
anom = {r["metric"]: float(r["value"])
        for r in read_csv("anomaly_metrics.csv")}
drivers = read_csv("driver_importance.csv")
bench = read_csv("channel_benchmark.csv")
sla = [r for r in metrics if r["target"] == "sla_attainment_pct"]
sla_best = min(sla, key=lambda r: float(r["mape"]))
vol_best = min([r for r in metrics
                if r["target"] == "tickets_received"],
               key=lambda r: float(r["mape"]))

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)
BLANK = prs.slide_layouts[6]


def add_slide(title, bullets, chart=None, footer=None):
    slide = prs.slides.add_slide(BLANK)
    tx = slide.shapes.add_textbox(Inches(0.6), Inches(0.3),
                                  Inches(12.1), Inches(0.8))
    tf = tx.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = title
    p.font.size = Pt(30)
    p.font.bold = True
    from pptx.dml.color import RGBColor
    p.font.color.rgb = RGBColor(*NAVY)
    body = slide.shapes.add_textbox(Inches(0.6), Inches(1.3),
                                    Inches(7.2 if chart else 12.1),
                                    Inches(5.4))
    tf2 = body.text_frame
    tf2.word_wrap = True
    for i, b in enumerate(bullets):
        para = tf2.paragraphs[0] if i == 0 else tf2.add_paragraph()
        para.text = "•  " + b
        para.font.size = Pt(17)
        para.space_after = Pt(10)
    if chart:
        slide.shapes.add_picture(
            os.path.join(CHARTS, chart), Inches(8.1), Inches(1.4),
            width=Inches(4.6))
    if footer:
        fx = slide.shapes.add_textbox(Inches(0.6), Inches(6.9),
                                      Inches(12.1), Inches(0.4))
        f = fx.text_frame.paragraphs[0]
        f.text = footer
        f.font.size = Pt(12)
    return slide


add_slide(
    "Service-Performance Analytics",
    ["ML Project for Data Analyst at Kforce Technology Staffing",
     "KPI forecasting  •  data-quality anomaly detection  •  "
     "SLA driver analysis",
     "Bhupesh Chandra Dimri  •  November 18, 2026",
     "R  •  STATA  •  SPSS  •  SAS — one analysis, four tools"],
    footer="github.com/bhupesh-debug/kforce-data-analyst-ml")

add_slide(
    "Problem Overview",
    ["Kforce needs an analyst who turns operational data into "
     "decisions: track KPIs, keep the reporting pipeline clean, and "
     "explain what moves performance.",
     "✅  Forecast next week's SLA and ticket volume so staffing "
     "can be planned, not guessed.",
     "✅  Catch a bad feed before it corrupts the dashboard.",
     "✅  Show which lever — staffing, backlog, handle time — "
     "actually moves SLA."],
    footer="Why it matters: a wrong KPI is worse than no KPI — it sends the team the wrong way.")

add_slide(
    "JD Breakdown",
    ["Must-have: advanced Excel (VBA), strong SQL, Power BI, "
     "dashboards, KPI tracking, data-quality monitoring.",
     "Good-to-have: exposure to Python, R, SPSS, SAS or STATA; "
     "documentation of reporting processes.",
     "Hidden expectation: own the reporting pipeline end-to-end and "
     "partner across teams.",
     "Risk flags carried honestly: $38–48/hr vs $140–190K band; "
     "remote vs on-site contradiction; client unnamed."])

add_slide(
    "ML Approach",
    ["Problem 1 — Forecasting (time series / regression): seasonal "
     "naive, Holt-Winters, linear, random forest, gradient boosting.",
     "Problem 2 — Anomaly detection: z-score rule (|z| > 4) on "
     "pipeline-health features.",
     "Problem 3 — Drivers: gradient boosting + permutation "
     "importance; per-channel benchmark.",
     "✅  No deep learning on purpose — the JD asks for analytics, "
     "not a transformer demo."],
    footer="Design decision: same-day operational features are excluded from the forecaster — that would leak.")

add_slide(
    "Data Strategy",
    ["Synthetic data (set.seed 42): 5 service channels, 730 days, "
     "3,650 channel-days + 730 pipeline-health days.",
     "25 injected data-quality incidents (late feed, missing batch, "
     "duplicate load, null spike) with ground-truth labels.",
    "Validation first: missing values, duplicates, range checks, "
     "date gaps — before any modelling.",
    "Time-based split: train 2024-01-01–2025-10-31, hold-out "
     "2025-11-01–2025-12-30 (61 days)."])

add_slide(
    "Model Design",
    ["Baseline: seasonal naive + Holt-Winters (weekly seasonality).",
     "Intermediate: linear regression, random forest (500 trees), "
     "gradient boosting (500 trees, depth 3).",
     "Features: lags 1/7/14/28, 7- and 28-day rolling means, "
     "demand-shock flag, calendar features.",
     "Metrics: MAE / RMSE / MAPE for forecasts; precision / recall / "
     "F1 for anomalies."],
    chart="model_comparison.png")

add_slide(
    "Results & Insights",
    ["Best SLA forecaster: %s (MAPE %.2f%% on the 61-day hold-out)."
     % (sla_best["model"], float(sla_best["mape"])),
     "Best volume forecaster: %s (MAPE %.2f%%)."
     % (vol_best["model"], float(vol_best["mape"])),
     "Anomaly detection: precision %.3f, recall %.3f, F1 %.3f — "
     "%d of %d injected incidents caught."
     % (anom["precision"], anom["recall"], anom["f1"],
        int(anom["tp"]), int(anom["n_true"])),
     "Top SLA driver: %s — staffing coverage and backlog pressure "
     "dominate." % drivers[0]["feature"],
     "Lowest-SLA channel: %s (%.1f%%) — start the staffing "
     "conversation there." % (bench[-1]["channel"],
                             float(bench[-1]["sla_attainment_pct"]))],
    chart="feature_importance.png")

add_slide(
    "Business Impact",
    ["A 14-day SLA forecast lets the team staff to demand instead "
     "of reacting to it — the difference between planned overtime "
     "and emergency cover.",
     "Anomaly flags stop one bad feed from becoming a week of wrong "
     "dashboards and wrong decisions.",
     "Driver ranking turns a vague “improve SLA” into a concrete "
     "order of work: staffing coverage first, backlog second.",
     "✅  All of it runs on the JD's own tools: R, STATA, SPSS, "
     "SAS, Power BI."])

add_slide(
    "Future Improvements",
    ["Re-fit the forecaster weekly on the rolling window; alert when "
     "hold-out MAPE degrades.",
     "Add channel-level forecasts (per-service-line staffing).",
     "Replace the 4-sigma rule with a calibrated threshold per "
     "incident type.",
     "Execute the STATA / SPSS / SAS scripts in licensed apps and "
     "publish the cross-tool comparison table.",
     "Ship the 14-day forecast into Power BI as a scheduled refresh."])

add_slide(
    "About This Project",
    ["Created by Bhupesh Chandra Dimri — Financial Analyst, "
     "JPMorgan Chase; M.S. Accounting Analytics & Data Technology, "
     "Pace University.",
     "R and STATA (working knowledge); SAS and SPSS (learned during "
     "M.S.).",
     "GitHub: github.com/bhupesh-debug/kforce-data-analyst-ml",
     "Contact: bhupesh7cd@gmail.com  •  917-818-6198",
     "All data synthetic; no real client data used."],
    footer="Thank you — questions welcome.")

prs.save(OUT)
print("Wrote", OUT, "slides:", len(prs.slides.__iter__.__self__._sldIdLst))
