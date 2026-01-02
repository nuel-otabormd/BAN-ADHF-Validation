# SQL Queries for BAN-ADHF ICU Validation Study

This folder contains the BigQuery SQL queries used to construct the study cohort from MIMIC-IV v3.1.

## Prerequisites

1. **PhysioNet Credentialed Access**: Complete CITI training and sign the data use agreement
2. **MIMIC-IV Access**: Request access at https://physionet.org/content/mimiciv/3.1/
3. **BigQuery Setup**: Link your Google Cloud project to PhysioNet BigQuery datasets

## Query Execution Order

Execute the queries in sequential order. Each step builds on the previous one.

| File | Description | Output N |
|------|-------------|----------|
| `01_step1_adhf_icu_all.sql` | All ICU stays with acute HF ICD codes | 14,614 |
| `02_step2_cardiac_medical_icu.sql` | Restrict to CCU/CVICU/MICU/MICU-SICU | 12,766 |
| `03_step3_with_ntprobnp.sql` | Require NT-proBNP available | 4,103 |
| `04_step4_with_med_section.sql` | Require medication reconciliation extractable | 2,862 |
| `05_step5_adhf_top5_dx.sql` | ADHF in top 5 diagnosis positions | 2,364 |
| `06_step6_received_iv_diuretics.sql` | Received IV loop diuretics | 1,692 |
| `07_final_cohort_complete.sql` | **Stage 1: Core cohort with BAN-ADHF score** | 1,505 |
| `08_consort_flow_counts.sql` | CONSORT flow diagram counts | — |
| `09_add_secondary_outcomes.sql` | **Stage 2: Add diuretic efficiency, MCS, etc.** | 1,505 |

## Cohort Construction Flow

```
MIMIC-IV v3.1 (2008-2022)
         │
         ▼
Step 1: Acute HF ICD codes ──────────────────► N = 14,614
         │
         ▼ (Exclude non-cardiac/medical ICUs)
Step 2: CCU/CVICU/MICU/MICU-SICU only ───────► N = 12,766
         │
         ▼ (Exclude no NT-proBNP)
Step 3: NT-proBNP available ─────────────────► N = 4,103
         │
         ▼ (Exclude no med section in notes)
Step 4: Medication reconciliation extractable ► N = 2,862
         │
         ▼ (Exclude ADHF incidental diagnosis)
Step 5: ADHF in top 5 diagnoses ─────────────► N = 2,364
         │
         ▼ (Exclude no IV diuretics)
Step 6: Received IV diuretics ───────────────► N = 1,692
         │
         ▼ (Deduplicate: first ICU stay per admission)
Step 7: FINAL COHORT ────────────────────────► N = 1,505
```

## ICD Codes Used

### Acute Decompensated Heart Failure

| ICD Version | Code | Description |
|-------------|------|-------------|
| ICD-10 | I5021 | Acute systolic (congestive) heart failure |
| ICD-10 | I5023 | Acute on chronic systolic heart failure |
| ICD-10 | I5031 | Acute diastolic heart failure |
| ICD-10 | I5033 | Acute on chronic diastolic heart failure |
| ICD-10 | I5041 | Acute combined systolic and diastolic heart failure |
| ICD-10 | I5043 | Acute on chronic combined heart failure |
| ICD-10 | J810 | Acute pulmonary edema |
| ICD-9 | 42821 | Acute systolic heart failure |
| ICD-9 | 42823 | Acute on chronic systolic heart failure |
| ICD-9 | 42831 | Acute diastolic heart failure |
| ICD-9 | 42833 | Acute on chronic diastolic heart failure |
| ICD-9 | 42841 | Acute combined heart failure |
| ICD-9 | 42843 | Acute on chronic combined heart failure |

## IV Diuretic Item IDs

| itemid | Medication |
|--------|------------|
| 221794 | Furosemide |
| 228340 | Furosemide (Concentrated) |
| 229639 | Bumetanide |

## BAN-ADHF Score Calculation

The final cohort query calculates the BAN-ADHF score using 8 components:

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

**Total Score Range: 0-26 points**

### Risk Categories

| Category | Score Range |
|----------|-------------|
| Low risk | 0-7 |
| Moderate risk | 8-12 |
| High risk | ≥13 |

## NLP Extraction Methods

### Home Diuretic Dose
- **Source**: Discharge notes "Medications on Admission" section
- **Pattern**: Regex extraction with BID detection
- **Conversion**: Bumetanide ×80, Torsemide ×4 to furosemide equivalents

### LVEF
- **Source**: Discharge notes
- **Pattern**: `(?i)lvef[\s:=]+(\d+)` with fallbacks
- **Validation**: Range 10-80%

### Cardiogenic Shock
- **Source**: ICD codes (R570, 78551) + discharge note NLP
- **Negation filtering**: Excludes "no evidence of", "ruled out", "unlikely", etc.

## Data Sources

| Source Table | Variables Extracted |
|--------------|---------------------|
| `mimiciv_3_1_hosp.admissions` | Demographics, outcomes |
| `mimiciv_3_1_hosp.patients` | Age, gender |
| `mimiciv_3_1_hosp.diagnoses_icd` | ICD codes, comorbidities |
| `mimiciv_3_1_icu.icustays` | ICU stays, care unit |
| `mimiciv_3_1_icu.inputevents` | IV diuretics, vasopressors, inotropes |
| `mimiciv_3_1_icu.outputevents` | Urine output |
| `mimiciv_3_1_icu.chartevents` | ICU rhythm documentation |
| `mimiciv_3_1_derived.chemistry` | Creatinine, BUN |
| `mimiciv_3_1_derived.cardiac_marker` | NT-proBNP |
| `mimiciv_3_1_derived.vitalsign` | Blood pressure |
| `mimiciv_3_1_derived.charlson` | Charlson comorbidity index |
| `mimiciv_3_1_derived.ventilation` | Mechanical ventilation |
| `mimiciv_note.discharge` | Home diuretics, LVEF, cardiogenic shock (NLP) |
| `mimiciv_ed.triage` | ED triage vitals, rhythm |
| `mimiciv_ed.vitalsign` | ED vital signs |
| `mimiciv_ed.edstays` | ED stay linkage |

## Adapting for Your Project

To use these queries with your own Google Cloud project:

1. Replace `YOUR-PROJECT-ID` with your project ID
2. Replace `ban_adhf` with your dataset name
3. Ensure you have access to `physionet-data` BigQuery datasets

Example find-and-replace:
```sql
-- Change this:
CREATE OR REPLACE TABLE `YOUR-PROJECT-ID.ban_adhf.step1_adhf_icu_all`

-- To this:
CREATE OR REPLACE TABLE `your-project-id.your_dataset.step1_adhf_icu_all`
```

## Citation

If you use these queries, please cite:

```
Otabor E, et al. External Validation of the BAN-ADHF Score for Predicting 
Diuretic Efficiency in Critically Ill ICU Patients with Acute Decompensated 
Heart Failure. [Journal and DOI to be added upon publication]
```

## Contact

For questions about this repository, please open a GitHub issue.
