# External Validation of the BAN-ADHF Score in Critically Ill Patients with Acute Decompensated Heart Failure

[![MIMIC-IV](https://img.shields.io/badge/MIMIC--IV-v3.1-blue)](https://physionet.org/content/mimiciv/3.1/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![TRIPOD](https://img.shields.io/badge/Reporting-TRIPOD%2BAI-green)](https://www.tripod-statement.org/)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.18124056.svg)](https://doi.org/10.5281/zenodo.18124056)

## Overview

This repository contains the reproducible code for **external validation of the BAN-ADHF (BUN, Atrial fibrillation, NT-proBNP, Acute Decompensated Heart Failure) score** for predicting diuretic efficiency in critically ill ICU patients with acute decompensated heart failure (ADHF).

**Database:** MIMIC-IV v3.1 (2008-2022)  
**Final Cohort:** N = 1,505 ICU admissions  
**Primary Outcome:** Diuretic efficiency (mL urine output per mg IV furosemide equivalent)

## Abstract

**Background:** The BAN-ADHF score predicts diuretic efficiency in hospitalized heart failure patients, but derivation and validation cohorts excluded hemodynamically unstable patients. Whether this score maintains predictive validity in critically ill intensive care unit populations, where diuretic resistance is more prevalent and consequential, remains unknown.

**Methods:** We performed a retrospective cohort study using the MIMIC-IV database (2008-2022). We included 1,505 adult ICU patients with acute decompensated heart failure receiving intravenous diuretics. Co-primary outcomes were 24-hour and 72-hour diuretic efficiency (mL urine output per mg IV furosemide equivalent). We assessed discrimination using Spearman correlation, C-index, and AUROC for lowest efficiency quintile. Patients were stratified into low (≤7), moderate (8-12), and high (≥13) risk categories based on data-driven cutoffs.

**Results:** Among 1,019 patients with calculable 24-hour diuretic efficiency, the BAN-ADHF score demonstrated strong inverse correlation (Spearman ρ = -0.518, 95% CI: -0.560 to -0.473; p<0.001). Discrimination for the lowest efficiency quintile was good (AUROC 0.780, 95% CI: 0.743-0.812). The 72-hour correlation remained robust (ρ = -0.458), matching the original derivation endpoint. Median efficiency decreased across risk categories: 47.4 mL/mg (low-risk), 29.0 mL/mg (moderate-risk), and 11.3 mL/mg (high-risk), a 4.2-fold difference (p<0.001). Performance was preserved across heart failure phenotypes. In-hospital mortality (12.4%) showed limited discrimination (AUROC 0.586), consistent with the score's design.

**Conclusions:** The BAN-ADHF score effectively predicts diuretic efficiency in critically ill ADHF patients. The 4.2-fold efficiency gradient supports its use for early identification of diuretic resistance and guiding escalation of decongestive therapy.

## Repository Structure

```
BAN-ADHF-Validation/
├── README.md                           # This file
├── LICENSE                             # MIT License
├── requirements.txt                    # Python dependencies
├── sql/
│   ├── README.md                       # SQL documentation
│   ├── 01_step1_adhf_icu_all.sql      # ICU stays with acute HF diagnosis
│   ├── 02_step2_cardiac_medical_icu.sql
│   ├── 03_step3_with_ntprobnp.sql
│   ├── 04_step4_with_med_section.sql
│   ├── 05_step5_adhf_top5_dx.sql
│   ├── 06_step6_received_iv_diuretics.sql
│   ├── 07_final_cohort_complete.sql   # Final cohort with BAN-ADHF score
│   ├── 08_consort_flow_counts.sql     # CONSORT flow diagram
│   └── 09_add_secondary_outcomes.sql  # Secondary outcomes (optional)
├── analysis/
│   └── BAN_ADHF_Analysis.ipynb        # Complete analysis notebook
└── figures/                            # Generated figures (optional)
```

## Prerequisites

### 1. MIMIC-IV Access

1. Complete [CITI training](https://physionet.org/about/citi-course/) for human subjects research
2. Sign the MIMIC-IV Data Use Agreement
3. Request access at [PhysioNet](https://physionet.org/content/mimiciv/3.1/)

### 2. Google Cloud Setup

1. Create a Google Cloud project
2. Link your PhysioNet credentials to access MIMIC-IV on BigQuery
3. Follow the [MIMIC-IV BigQuery tutorial](https://mimic.mit.edu/docs/gettingstarted/cloud/bigquery/)

### 3. Python Environment

```bash
pip install -r requirements.txt
```

## Quick Start

### Step 1: Configure BigQuery

Replace the project ID in all SQL files:

```sql
-- Change from:
CREATE OR REPLACE TABLE `YOUR-PROJECT-ID.ban_adhf.step1_adhf_icu_all`

-- To your project:
CREATE OR REPLACE TABLE `your-project-id.your_dataset.step1_adhf_icu_all`
```

### Step 2: Run SQL Queries

Execute queries in sequential order (01 → 09) in BigQuery:

| Step | Query | Output N | Description |
|------|-------|----------|-------------|
| 1 | `01_step1_adhf_icu_all.sql` | 14,614 | ICU stays with acute HF ICD codes |
| 2 | `02_step2_cardiac_medical_icu.sql` | 12,766 | Restrict to CCU/CVICU/MICU |
| 3 | `03_step3_with_ntprobnp.sql` | 4,103 | Require NT-proBNP available |
| 4 | `04_step4_with_med_section.sql` | 2,862 | Medication reconciliation extractable |
| 5 | `05_step5_adhf_top5_dx.sql` | 2,364 | ADHF in top 5 diagnoses |
| 6 | `06_step6_received_iv_diuretics.sql` | 1,692 | Received IV loop diuretics |
| 7 | `07_final_cohort_complete.sql` | **1,505** | **Final cohort with BAN-ADHF score** |
| 8 | `08_consort_flow_counts.sql` | — | CONSORT flow diagram counts |
| 9 | `09_add_secondary_outcomes.sql` | 1,505 | Add secondary outcomes (optional) |

### Step 3: Run Analysis

Open `analysis/BAN_ADHF_Analysis.ipynb` in Google Colab or Jupyter and execute all cells.

## BAN-ADHF Score Components

| Variable | Points | Thresholds |
|----------|--------|------------|
| Creatinine | 0, 2, 4 | <1.2, 1.2-1.59, ≥1.6 mg/dL |
| BUN | 0, 2, 3 | <20, 20-39, ≥40 mg/dL |
| NT-proBNP | 0, 2, 4 | <5000, 5000-12000, >12000 pg/mL |
| Diastolic BP | 0, 1, 3 | ≥60, 50-59, <50 mmHg |
| Home Diuretic | 0, 3, 6 | <120, 120-249, ≥250 mg/day furosemide eq. |
| Atrial Fibrillation | 0, 2 | No, Yes |
| Hypertension | 0, 3 | No, Yes |
| Prior HF Hospitalization | 0, 1 | No, Yes (within 12 months) |

**Total Score Range:** 0-26 points

### Risk Categories

| Category | Score | Interpretation |
|----------|-------|----------------|
| Low risk | ≤7 | Lower risk of diuretic resistance |
| Moderate risk | 8-12 | Intermediate risk |
| High risk | ≥13 | Higher risk of diuretic resistance |

## Key Results

| Metric | Value |
|--------|-------|
| Total Cohort | 1,505 |
| Low Risk (≤7) | 446 (29.6%) |
| Moderate Risk (8-12) | 480 (31.9%) |
| High Risk (≥13) | 579 (38.5%) |
| In-Hospital Mortality | 187 (12.4%) |
| Atrial Fibrillation | 897 (59.6%) |
| Hypertension | 1,197 (79.5%) |

## Data Sources

| MIMIC-IV Table | Variables Extracted |
|----------------|---------------------|
| `mimiciv_3_1_hosp.admissions` | Demographics, outcomes |
| `mimiciv_3_1_hosp.patients` | Age, gender |
| `mimiciv_3_1_hosp.diagnoses_icd` | ICD codes, comorbidities |
| `mimiciv_3_1_icu.icustays` | ICU stays, care unit |
| `mimiciv_3_1_icu.inputevents` | IV diuretics |
| `mimiciv_3_1_derived.chemistry` | Creatinine, BUN |
| `mimiciv_3_1_derived.cardiac_marker` | NT-proBNP |
| `mimiciv_3_1_derived.vitalsign` | Blood pressure |
| `mimiciv_3_1_derived.first_day_urine_output` | Urine output |
| `mimiciv_note.discharge` | Home diuretics (NLP), LVEF |
| `mimiciv_ed.triage` | ED triage vitals |

## Reporting Standards

This study follows:
- **TRIPOD+AI 2024** - Transparent Reporting of a multivariable prediction model for Individual Prognosis Or Diagnosis
- **STROBE** - Strengthening the Reporting of Observational Studies in Epidemiology

## Citation

If you use this code, please cite:

```bibtex
@software{otabor2025banadhf_code,
  author       = {Otabor, Emmanuel and Lo, Kevin B},
  title        = {{External Validation of the BAN-ADHF Score in Critically 
                   Ill Patients with Acute Decompensated Heart Failure}},
  year         = {2025},
  publisher    = {Zenodo},
  doi          = {10.5281/zenodo.18124056},
  url          = {https://doi.org/10.5281/zenodo.18124056}
}
```

## Original BAN-ADHF Publication

```bibtex
@article{banadhf_original,
  title={Development and Validation of the BAN-ADHF Score for Predicting 
         Diuretic Response in Acute Heart Failure},
  journal={[Original Journal]},
  year={[Year]}
}
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- MIMIC-IV team at MIT Laboratory for Computational Physiology
- PhysioNet for data hosting and access infrastructure
- Original BAN-ADHF score developers

## Contact

For questions about this repository:
- GitHub Issues: [Open an issue](../../issues)

---

**Note:** This repository contains code only. No patient data is included. Researchers must obtain their own MIMIC-IV access through PhysioNet.
