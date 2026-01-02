-- =============================================================================
-- BAN-ADHF ICU Validation Study: Complete Final Cohort Construction
-- =============================================================================
-- VERIFIED: Reproduces published study results exactly
-- Study: External validation of BAN-ADHF diuretic resistance score in ICU patients
-- Database: MIMIC-IV v3.1 (PhysioNet)
-- Output: 1,505 hospital admissions with 72 variables
-- 
-- Prerequisites: Run steps 1-6 first to create intermediate tables
-- =============================================================================

CREATE OR REPLACE TABLE `YOUR-PROJECT-ID.ban_adhf.final_cohort` AS

-- =============================================================================
-- SECTION 1: Home Diuretic Extraction (NLP from discharge notes)
-- =============================================================================
WITH home_diuretics AS (
  SELECT 
    s.stay_id,
    s.hadm_id,
    s.subject_id,
    s.first_careunit,
    s.icu_intime,
    s.icu_outtime,
    s.admittime,
    s.dischtime,
    s.hospital_expire_flag,
    LOWER(s.med_section) AS med_section,
    
    -- Furosemide daily dose (detect BID dosing)
    SAFE_CAST(REGEXP_EXTRACT(LOWER(s.med_section), r'(?:furosemide|lasix)\s*(\d+)\s*mg') AS INT64) 
      * CASE WHEN REGEXP_CONTAINS(LOWER(s.med_section), r'(?:furosemide|lasix)\s*\d+\s*mg[^.]{0,30}(?:bid|twice|2\s*times)') THEN 2 ELSE 1 END
      AS furosemide_daily_mg,
    
    -- Torsemide daily dose
    SAFE_CAST(REGEXP_EXTRACT(LOWER(s.med_section), r'torsemide\s*(\d+)\s*mg') AS INT64)
      * CASE WHEN REGEXP_CONTAINS(LOWER(s.med_section), r'torsemide\s*\d+\s*mg[^.]{0,30}(?:bid|twice|2\s*times)') THEN 2 ELSE 1 END
      AS torsemide_daily_mg,
    
    -- Bumetanide daily dose
    SAFE_CAST(REGEXP_EXTRACT(LOWER(s.med_section), r'(?:bumetanide|bumex)\s*(\d+\.?\d*)\s*mg') AS FLOAT64)
      * CASE WHEN REGEXP_CONTAINS(LOWER(s.med_section), r'(?:bumetanide|bumex)\s*\d+\.?\d*\s*mg[^.]{0,30}(?:bid|twice|2\s*times)') THEN 2 ELSE 1 END
      AS bumetanide_daily_mg
      
  FROM `YOUR-PROJECT-ID.ban_adhf.step6_received_iv_diuretics` s
),

-- =============================================================================
-- SECTION 2: Laboratory Values (First available during admission)
-- =============================================================================
first_creatinine AS (
  SELECT hadm_id, creatinine,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_derived.chemistry`
  WHERE creatinine IS NOT NULL
),

first_bun AS (
  SELECT hadm_id, bun,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_derived.chemistry`
  WHERE bun IS NOT NULL
),

first_ntprobnp AS (
  SELECT hadm_id, ntprobnp,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_derived.cardiac_marker`
  WHERE ntprobnp IS NOT NULL
),

labs AS (
  SELECT 
    h.hadm_id,
    cr.creatinine,
    bn.bun,
    nt.ntprobnp
  FROM home_diuretics h
  LEFT JOIN first_creatinine cr ON h.hadm_id = cr.hadm_id AND cr.rn = 1
  LEFT JOIN first_bun bn ON h.hadm_id = bn.hadm_id AND bn.rn = 1
  LEFT JOIN first_ntprobnp nt ON h.hadm_id = nt.hadm_id AND nt.rn = 1
),

-- =============================================================================
-- SECTION 3: Diastolic Blood Pressure (Priority: ED Triage > ED Vitals > ICU)
-- =============================================================================
dbp_ed_triage AS (
  SELECT 
    h.stay_id,
    t.dbp,
    'ED Triage' AS dbp_source,
    ROW_NUMBER() OVER (PARTITION BY h.stay_id ORDER BY e.intime) AS rn
  FROM home_diuretics h
  INNER JOIN `physionet-data.mimiciv_ed.edstays` e ON h.subject_id = e.subject_id AND h.hadm_id = e.hadm_id
  INNER JOIN `physionet-data.mimiciv_ed.triage` t ON e.stay_id = t.stay_id
  WHERE t.dbp IS NOT NULL AND t.dbp BETWEEN 20 AND 200
),

dbp_ed_vitals AS (
  SELECT 
    h.stay_id,
    v.dbp,
    'ED Vitals' AS dbp_source,
    ROW_NUMBER() OVER (PARTITION BY h.stay_id ORDER BY v.charttime) AS rn
  FROM home_diuretics h
  INNER JOIN `physionet-data.mimiciv_ed.edstays` e ON h.subject_id = e.subject_id AND h.hadm_id = e.hadm_id
  INNER JOIN `physionet-data.mimiciv_ed.vitalsign` v ON e.stay_id = v.stay_id
  WHERE v.dbp IS NOT NULL AND v.dbp BETWEEN 20 AND 200
),

dbp_icu AS (
  SELECT 
    h.stay_id,
    vs.dbp,
    'ICU Vitals' AS dbp_source,
    ROW_NUMBER() OVER (PARTITION BY h.stay_id ORDER BY vs.charttime) AS rn
  FROM home_diuretics h
  INNER JOIN `physionet-data.mimiciv_3_1_derived.vitalsign` vs ON h.stay_id = vs.stay_id
  WHERE vs.dbp IS NOT NULL AND vs.dbp BETWEEN 20 AND 200
),

dbp_combined AS (
  SELECT 
    h.stay_id,
    COALESCE(t.dbp, ev.dbp, i.dbp) AS dbp,
    COALESCE(t.dbp_source, ev.dbp_source, i.dbp_source) AS dbp_source
  FROM home_diuretics h
  LEFT JOIN dbp_ed_triage t ON h.stay_id = t.stay_id AND t.rn = 1
  LEFT JOIN dbp_ed_vitals ev ON h.stay_id = ev.stay_id AND ev.rn = 1
  LEFT JOIN dbp_icu i ON h.stay_id = i.stay_id AND i.rn = 1
),

-- =============================================================================
-- SECTION 4: Comorbidities (Charlson + Additional)
-- =============================================================================
charlson AS (
  SELECT 
    h.hadm_id,
    c.myocardial_infarct AS hx_myocardial_infarction,
    c.congestive_heart_failure AS hx_heart_failure,
    c.cerebrovascular_disease AS hx_stroke,
    CASE WHEN c.diabetes_without_cc = 1 OR c.diabetes_with_cc = 1 THEN 1 ELSE 0 END AS hx_diabetes,
    c.renal_disease AS hx_renal_disease,
    c.chronic_pulmonary_disease AS hx_copd,
    c.charlson_comorbidity_index AS cci_score
  FROM home_diuretics h
  LEFT JOIN `physionet-data.mimiciv_3_1_derived.charlson` c ON h.hadm_id = c.hadm_id
),

-- Hypertension from ICD codes (per original)
hypertension AS (
  SELECT DISTINCT hadm_id, 1 AS hx_hypertension
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    -- ICD-10
    icd_code LIKE 'I10%'    -- Essential hypertension
    OR icd_code LIKE 'I11%' -- Hypertensive heart disease
    OR icd_code LIKE 'I12%' -- Hypertensive CKD
    OR icd_code LIKE 'I13%' -- Hypertensive heart and CKD
    OR icd_code LIKE 'I15%' -- Secondary hypertension
    OR icd_code LIKE 'I16%' -- Hypertensive crisis
    -- ICD-9
    OR icd_code LIKE '401%' -- Essential hypertension
    OR icd_code LIKE '402%' -- Hypertensive heart disease
    OR icd_code LIKE '403%' -- Hypertensive CKD
    OR icd_code LIKE '404%' -- Hypertensive heart and CKD
    OR icd_code LIKE '405%' -- Secondary hypertension
  )
),

-- Atrial Fibrillation from ICD codes (broader pattern)
afib_icd AS (
  SELECT DISTINCT hadm_id, 1 AS afib_from_icd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_code LIKE 'I48%' AND icd_version = 10)
     OR (icd_code LIKE '4273%' AND icd_version = 9)
),

-- Atrial Fibrillation from ED rhythm (exact match per original)
afib_ed AS (
  SELECT DISTINCT 
    e.hadm_id, 
    1 AS afib_from_ed
  FROM `physionet-data.mimiciv_ed.vitalsign` v
  JOIN `physionet-data.mimiciv_ed.edstays` e ON v.stay_id = e.stay_id
  WHERE LOWER(v.rhythm) IN ('atrial fibrillation', 'afib', 'af', 'atrial flutter')
),

-- Atrial Fibrillation from ICU chartevents (Heart Rhythm itemid = 220048)
afib_icu AS (
  SELECT DISTINCT ie.hadm_id, 1 AS afib_from_icu
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON ce.stay_id = ie.stay_id
  WHERE ce.itemid = 220048
    AND (LOWER(ce.value) LIKE '%af (%'
      OR LOWER(ce.value) LIKE '%atrial fib%')
),

-- =============================================================================
-- SECTION 5: Prior HF Hospitalization (within 12 months)
-- =============================================================================
prior_hf AS (
  SELECT DISTINCT h.hadm_id, 1 AS prior_hf_hospitalization_12mo
  FROM home_diuretics h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` prev 
    ON h.subject_id = prev.subject_id
    AND prev.hadm_id != h.hadm_id
    AND prev.dischtime < h.admittime
    AND prev.dischtime >= DATETIME_SUB(h.admittime, INTERVAL 365 DAY)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON prev.hadm_id = dx.hadm_id
  WHERE (dx.icd_code LIKE 'I50%' AND dx.icd_version = 10)
     OR (dx.icd_code LIKE '428%' AND dx.icd_version = 9)
),

-- =============================================================================
-- SECTION 6: LVEF Extraction (NLP from discharge notes)
-- =============================================================================
lvef_extracted AS (
  SELECT 
    h.hadm_id,
    CAST(COALESCE(
      REGEXP_EXTRACT(n.text, r'(?i)lvef[\s:=]+(\d+)'),
      REGEXP_EXTRACT(n.text, r'(?i)(?:ef|ejection fraction)[\s:=]+(\d+)'),
      REGEXP_EXTRACT(n.text, r'(?i)(\d+)\s*%?\s*(?:lvef|ef)\b')
    ) AS INT64) AS lvef_value,
    ROW_NUMBER() OVER (PARTITION BY h.hadm_id ORDER BY n.charttime) AS rn
  FROM home_diuretics h
  INNER JOIN `physionet-data.mimiciv_note.discharge` n ON h.hadm_id = n.hadm_id
  WHERE LOWER(n.text) LIKE '%lvef%' OR LOWER(n.text) LIKE '%ejection fraction%'
),

lvef_final AS (
  SELECT 
    hadm_id,
    lvef_value AS lvef
  FROM lvef_extracted
  WHERE rn = 1 AND lvef_value BETWEEN 10 AND 80
),

-- =============================================================================
-- SECTION 7: Cardiogenic Shock (ICD + NLP with negation filtering)
-- =============================================================================
cs_icd AS (
  SELECT DISTINCT hadm_id, 1 AS cs_from_icd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('R570', 'R571', '78551')
),

cs_nlp AS (
  SELECT 
    h.hadm_id,
    CASE 
      WHEN REGEXP_CONTAINS(LOWER(n.text), r'cardiogenic shock')
        AND NOT REGEXP_CONTAINS(LOWER(n.text), r'(?:no|without|deny|denies|ruled out|unlikely|not in|no evidence of)\s{0,10}cardiogenic shock')
      THEN 1 
      ELSE 0 
    END AS cs_from_nlp
  FROM home_diuretics h
  INNER JOIN `physionet-data.mimiciv_note.discharge` n ON h.hadm_id = n.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY h.hadm_id ORDER BY n.charttime) = 1
),

-- =============================================================================
-- SECTION 8: Urine Output (24h and 72h cumulative)
-- =============================================================================
urine_output AS (
  SELECT 
    h.stay_id,
    SUM(CASE WHEN oe.charttime <= DATETIME_ADD(h.icu_intime, INTERVAL 24 HOUR) THEN oe.value ELSE 0 END) AS urine_output_24h_ml,
    SUM(CASE WHEN oe.charttime <= DATETIME_ADD(h.icu_intime, INTERVAL 72 HOUR) THEN oe.value ELSE 0 END) AS urine_output_72h_ml
  FROM home_diuretics h
  INNER JOIN `physionet-data.mimiciv_3_1_icu.outputevents` oe ON h.stay_id = oe.stay_id
  WHERE oe.itemid IN (226559, 226560, 226561, 226584, 226563, 226564, 226565, 226567, 
                      226557, 226558, 227488, 227489)  -- Urine output itemids
  GROUP BY h.stay_id
),

-- =============================================================================
-- SECTION 9: IV Diuretic Doses (24h and 72h cumulative, furosemide equivalents)
-- =============================================================================
iv_diuretics AS (
  SELECT 
    h.stay_id,
    -- 24-hour IV diuretic dose (furosemide equivalents: bumetanide × 40)
    SUM(CASE 
      WHEN ie.starttime <= DATETIME_ADD(h.icu_intime, INTERVAL 24 HOUR) THEN
        CASE 
          WHEN ie.itemid IN (221794, 228340) THEN ie.amount  -- Furosemide
          WHEN ie.itemid = 229639 THEN ie.amount * 40        -- Bumetanide → Furosemide
          ELSE 0 
        END
      ELSE 0 
    END) AS iv_diuretic_dose_24h_mg,
    -- 72-hour IV diuretic dose
    SUM(CASE 
      WHEN ie.starttime <= DATETIME_ADD(h.icu_intime, INTERVAL 72 HOUR) THEN
        CASE 
          WHEN ie.itemid IN (221794, 228340) THEN ie.amount
          WHEN ie.itemid = 229639 THEN ie.amount * 40
          ELSE 0 
        END
      ELSE 0 
    END) AS iv_diuretic_dose_72h_mg
  FROM home_diuretics h
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie ON h.stay_id = ie.stay_id
  WHERE ie.itemid IN (221794, 228340, 229639)  -- Furosemide, Furosemide concentrated, Bumetanide
  GROUP BY h.stay_id
),

-- =============================================================================
-- SECTION 10: Vasopressors and Inotropes
-- =============================================================================
vasopressors AS (
  SELECT DISTINCT stay_id, 1 AS vasopressor_use
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE itemid IN (221906, 221289, 229617, 221662, 221653, 222315)  
  -- Norepinephrine, Epinephrine, Phenylephrine, Dopamine, Dobutamine, Vasopressin
),

dobutamine AS (
  SELECT DISTINCT stay_id, 1 AS dobutamine_use
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE itemid = 221653  -- Dobutamine
),

milrinone AS (
  SELECT DISTINCT stay_id, 1 AS milrinone_use
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE itemid = 221986  -- Milrinone
),

-- =============================================================================
-- SECTION 11: Mechanical Circulatory Support
-- =============================================================================
mcs AS (
  SELECT DISTINCT h.stay_id, 1 AS mcs_use
  FROM home_diuretics h
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON h.stay_id = pe.stay_id
  WHERE pe.itemid IN (225153, 225154, 225155, 225156)  -- IABP, Impella, ECMO itemids
  UNION DISTINCT
  SELECT DISTINCT h.stay_id, 1 AS mcs_use
  FROM home_diuretics h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx ON h.hadm_id = dx.hadm_id
  WHERE dx.icd_code IN ('5A02210', '5A0221D', '5A02216', '02HA0QZ', '02HA3QZ', '02HA4QZ')
),

-- =============================================================================
-- SECTION 12: Invasive Mechanical Ventilation
-- =============================================================================
invasive_vent AS (
  SELECT DISTINCT stay_id, 1 AS invasive_vent
  FROM `physionet-data.mimiciv_3_1_derived.ventilation`
  WHERE ventilation_status = 'InvasiveVent'
),

-- =============================================================================
-- SECTION 13: ESRD and Advanced CKD
-- =============================================================================
esrd AS (
  SELECT DISTINCT hadm_id, 1 AS esrd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('N186', '5856', 'Z992', 'V4511', 'Z940')
),

advanced_ckd AS (
  SELECT DISTINCT hadm_id, 1 AS chronic_advanced_ckd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('N184', 'N185', 'N186', '5854', '5855', '5856')
)

-- =============================================================================
-- FINAL SELECT: Combine all components and calculate BAN-ADHF score
-- =============================================================================
SELECT 
  -- Identifiers
  h.stay_id,
  h.hadm_id,
  h.subject_id,
  
  -- Demographics
  p.gender,
  p.anchor_age AS age,
  h.first_careunit,
  h.icu_intime,
  h.icu_outtime,
  h.admittime,
  h.dischtime,
  h.hospital_expire_flag,
  
  -- Home Diuretics
  h.furosemide_daily_mg,
  h.torsemide_daily_mg,
  h.bumetanide_daily_mg,
  COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) AS total_furosemide_equivalent_mg,
  CASE 
    WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) < 120 THEN 0
    WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) < 250 THEN 3
    ELSE 6
  END AS ban_adhf_diuretic_points,
  CASE 
    WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) < 120 THEN 'Low (<120 mg/day)'
    WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) < 250 THEN 'Moderate (120-249 mg/day)'
    ELSE 'High (≥250 mg/day)'
  END AS home_diuretic_category,
  
  -- Labs
  l.creatinine,
  l.bun,
  l.ntprobnp,
  
  -- Vitals
  d.dbp,
  d.dbp_source,
  
  -- Charlson Comorbidities
  ch.hx_myocardial_infarction,
  ch.hx_heart_failure,
  ch.hx_stroke,
  ch.hx_diabetes,
  ch.hx_renal_disease,
  ch.hx_copd,
  ch.cci_score,
  
  -- Additional Comorbidities for BAN-ADHF
  COALESCE(htn.hx_hypertension, 0) AS hx_hypertension,
  -- AFib: ED + ICD + ICU (to match published study)
  CASE WHEN COALESCE(ai.afib_from_icd, 0) = 1 OR COALESCE(ae.afib_from_ed, 0) = 1 OR COALESCE(aicu.afib_from_icu, 0) = 1 THEN 1 ELSE 0 END AS hx_atrial_fibrillation,
  COALESCE(ai.afib_from_icd, 0) AS afib_from_icd,
  COALESCE(ae.afib_from_ed, 0) AS afib_from_ed,
  COALESCE(aicu.afib_from_icu, 0) AS afib_from_icu,
  COALESCE(phf.prior_hf_hospitalization_12mo, 0) AS prior_hf_hospitalization_12mo,
  
  -- LVEF and HF Phenotype
  lv.lvef,
  CASE 
    WHEN lv.lvef IS NULL THEN 'Missing'
    WHEN lv.lvef < 40 THEN 'HFrEF'
    WHEN lv.lvef >= 40 AND lv.lvef <= 50 THEN 'HFmrEF'
    WHEN lv.lvef > 50 THEN 'HFpEF'
  END AS hf_phenotype,
  
  -- Cardiogenic Shock
  CASE WHEN COALESCE(csi.cs_from_icd, 0) = 1 OR COALESCE(csn.cs_from_nlp, 0) = 1 THEN 1 ELSE 0 END AS cardiogenic_shock,
  COALESCE(csi.cs_from_icd, 0) AS cs_from_icd,
  COALESCE(csn.cs_from_nlp, 0) AS cs_from_nlp,
  
  -- Derived Demographics
  CASE WHEN p.anchor_age >= 65 THEN 1 ELSE 0 END AS age_65_or_older,
  CASE WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg, 0) + COALESCE(h.bumetanide_daily_mg, 0) > 0 THEN 1 ELSE 0 END AS on_home_diuretics,
  
  -- ==========================================================================
  -- BAN-ADHF SCORE COMPONENTS (8 variables)
  -- ==========================================================================
  
  -- Points: Creatinine (0/2/4)
  CASE 
    WHEN l.creatinine IS NULL THEN 0
    WHEN l.creatinine < 1.2 THEN 0
    WHEN l.creatinine < 1.6 THEN 2
    ELSE 4
  END AS points_creatinine,
  
  -- Points: BUN (0/2/3)
  CASE 
    WHEN l.bun IS NULL THEN 0
    WHEN l.bun < 20 THEN 0
    WHEN l.bun < 40 THEN 2
    ELSE 3
  END AS points_bun,
  
  -- Points: NT-proBNP (0/2/4)
  CASE 
    WHEN l.ntprobnp IS NULL THEN 0
    WHEN l.ntprobnp < 5000 THEN 0
    WHEN l.ntprobnp <= 12000 THEN 2
    ELSE 4
  END AS points_ntprobnp,
  
  -- Points: DBP (0/1/3)
  CASE 
    WHEN d.dbp IS NULL THEN 0
    WHEN d.dbp >= 60 THEN 0
    WHEN d.dbp >= 50 THEN 1
    ELSE 3
  END AS points_dbp,
  
  -- Points: Home Diuretic (0/3/6)
  CASE 
    WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) < 120 THEN 0
    WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) < 250 THEN 3
    ELSE 6
  END AS points_home_diuretic,
  
  -- Points: Atrial Fibrillation (0/2) - ED + ICD + ICU
  CASE WHEN COALESCE(ai.afib_from_icd, 0) = 1 OR COALESCE(ae.afib_from_ed, 0) = 1 OR COALESCE(aicu.afib_from_icu, 0) = 1 THEN 2 ELSE 0 END AS points_afib,
  
  -- Points: Hypertension (0/3)
  CASE WHEN COALESCE(htn.hx_hypertension, 0) = 1 THEN 3 ELSE 0 END AS points_htn,
  
  -- Points: Prior HF Hospitalization (0/1)
  CASE WHEN COALESCE(phf.prior_hf_hospitalization_12mo, 0) = 1 THEN 1 ELSE 0 END AS points_prior_hf,
  
  -- BAN-ADHF Total Score (sum of 8 components, range 0-26)
  (
    -- Creatinine
    CASE WHEN l.creatinine IS NULL THEN 0 WHEN l.creatinine < 1.2 THEN 0 WHEN l.creatinine < 1.6 THEN 2 ELSE 4 END
    -- BUN
    + CASE WHEN l.bun IS NULL THEN 0 WHEN l.bun < 20 THEN 0 WHEN l.bun < 40 THEN 2 ELSE 3 END
    -- NT-proBNP
    + CASE WHEN l.ntprobnp IS NULL THEN 0 WHEN l.ntprobnp < 5000 THEN 0 WHEN l.ntprobnp <= 12000 THEN 2 ELSE 4 END
    -- DBP
    + CASE WHEN d.dbp IS NULL THEN 0 WHEN d.dbp >= 60 THEN 0 WHEN d.dbp >= 50 THEN 1 ELSE 3 END
    -- Home diuretic
    + CASE WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) < 120 THEN 0
           WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) < 250 THEN 3
           ELSE 6 END
    -- AFib (ED + ICD + ICU)
    + CASE WHEN COALESCE(ai.afib_from_icd, 0) = 1 OR COALESCE(ae.afib_from_ed, 0) = 1 OR COALESCE(aicu.afib_from_icu, 0) = 1 THEN 2 ELSE 0 END
    -- HTN
    + CASE WHEN COALESCE(htn.hx_hypertension, 0) = 1 THEN 3 ELSE 0 END
    -- Prior HF
    + CASE WHEN COALESCE(phf.prior_hf_hospitalization_12mo, 0) = 1 THEN 1 ELSE 0 END
  ) AS ban_adhf_total_score,
  
  -- BAN-ADHF Risk Category
  CASE 
    WHEN (
      CASE WHEN l.creatinine IS NULL THEN 0 WHEN l.creatinine < 1.2 THEN 0 WHEN l.creatinine < 1.6 THEN 2 ELSE 4 END
      + CASE WHEN l.bun IS NULL THEN 0 WHEN l.bun < 20 THEN 0 WHEN l.bun < 40 THEN 2 ELSE 3 END
      + CASE WHEN l.ntprobnp IS NULL THEN 0 WHEN l.ntprobnp < 5000 THEN 0 WHEN l.ntprobnp <= 12000 THEN 2 ELSE 4 END
      + CASE WHEN d.dbp IS NULL THEN 0 WHEN d.dbp >= 60 THEN 0 WHEN d.dbp >= 50 THEN 1 ELSE 3 END
      + CASE WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) < 120 THEN 0
             WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) < 250 THEN 3
             ELSE 6 END
      + CASE WHEN COALESCE(ai.afib_from_icd, 0) = 1 OR COALESCE(ae.afib_from_ed, 0) = 1 OR COALESCE(aicu.afib_from_icu, 0) = 1 THEN 2 ELSE 0 END
      + CASE WHEN COALESCE(htn.hx_hypertension, 0) = 1 THEN 3 ELSE 0 END
      + CASE WHEN COALESCE(phf.prior_hf_hospitalization_12mo, 0) = 1 THEN 1 ELSE 0 END
    ) <= 7 THEN 'Low risk'
    WHEN (
      CASE WHEN l.creatinine IS NULL THEN 0 WHEN l.creatinine < 1.2 THEN 0 WHEN l.creatinine < 1.6 THEN 2 ELSE 4 END
      + CASE WHEN l.bun IS NULL THEN 0 WHEN l.bun < 20 THEN 0 WHEN l.bun < 40 THEN 2 ELSE 3 END
      + CASE WHEN l.ntprobnp IS NULL THEN 0 WHEN l.ntprobnp < 5000 THEN 0 WHEN l.ntprobnp <= 12000 THEN 2 ELSE 4 END
      + CASE WHEN d.dbp IS NULL THEN 0 WHEN d.dbp >= 60 THEN 0 WHEN d.dbp >= 50 THEN 1 ELSE 3 END
      + CASE WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) < 120 THEN 0
             WHEN COALESCE(h.furosemide_daily_mg, 0) + COALESCE(h.torsemide_daily_mg * 4, 0) + COALESCE(h.bumetanide_daily_mg * 80, 0) < 250 THEN 3
             ELSE 6 END
      + CASE WHEN COALESCE(ai.afib_from_icd, 0) = 1 OR COALESCE(ae.afib_from_ed, 0) = 1 OR COALESCE(aicu.afib_from_icu, 0) = 1 THEN 2 ELSE 0 END
      + CASE WHEN COALESCE(htn.hx_hypertension, 0) = 1 THEN 3 ELSE 0 END
      + CASE WHEN COALESCE(phf.prior_hf_hospitalization_12mo, 0) = 1 THEN 1 ELSE 0 END
    ) <= 12 THEN 'Moderate risk'
    ELSE 'High risk'
  END AS ban_adhf_risk_category,
  
  -- ==========================================================================
  -- OUTCOMES
  -- ==========================================================================
  
  -- Urine Output
  uo.urine_output_24h_ml,
  uo.urine_output_72h_ml,
  
  -- Diuretic Resistance (24h urine ≤3000 mL)
  CASE WHEN uo.urine_output_24h_ml <= 3000 THEN 1 ELSE 0 END AS diuretic_resistance,
  
  -- Vasopressors and Inotropes
  COALESCE(vp.vasopressor_use, 0) AS vasopressor_use,
  COALESCE(dob.dobutamine_use, 0) AS dobutamine_use,
  COALESCE(mil.milrinone_use, 0) AS milrinone_use,
  CASE WHEN COALESCE(dob.dobutamine_use, 0) = 1 OR COALESCE(mil.milrinone_use, 0) = 1 THEN 1 ELSE 0 END AS inotrope_use,
  
  -- Mechanical Circulatory Support
  COALESCE(m.mcs_use, 0) AS mcs_use,
  
  -- IV Diuretic Doses
  ivd.iv_diuretic_dose_24h_mg,
  ivd.iv_diuretic_dose_72h_mg,
  
  -- Diuretic Efficiency (mL urine / mg IV diuretic)
  CASE WHEN ivd.iv_diuretic_dose_24h_mg > 0 THEN uo.urine_output_24h_ml / ivd.iv_diuretic_dose_24h_mg ELSE NULL END AS diuretic_efficiency_24h,
  CASE WHEN ivd.iv_diuretic_dose_72h_mg > 0 THEN uo.urine_output_72h_ml / ivd.iv_diuretic_dose_72h_mg ELSE NULL END AS diuretic_efficiency_72h,
  
  -- Length of Stay
  DATETIME_DIFF(h.icu_outtime, h.icu_intime, HOUR) / 24.0 AS icu_los_days,
  DATETIME_DIFF(h.dischtime, h.admittime, HOUR) / 24.0 AS hospital_los_days,
  
  -- ICU Stay Duration Flags
  CASE WHEN DATETIME_DIFF(h.icu_outtime, h.icu_intime, HOUR) >= 24 THEN 1 ELSE 0 END AS icu_stay_ge_24h,
  CASE WHEN DATETIME_DIFF(h.icu_outtime, h.icu_intime, HOUR) >= 72 THEN 1 ELSE 0 END AS icu_stay_ge_72h,
  
  -- ESRD and Advanced CKD
  COALESCE(e.esrd, 0) AS esrd,
  COALESCE(iv.invasive_vent, 0) AS invasive_vent,
  
  -- eGFR (CKD-EPI 2021, simplified without race)
  CASE 
    WHEN l.creatinine IS NULL OR l.creatinine <= 0 THEN NULL
    WHEN p.gender = 'F' THEN
      CASE 
        WHEN l.creatinine <= 0.7 THEN 142 * POWER(l.creatinine / 0.7, -0.241) * POWER(0.9938, p.anchor_age) * 1.012
        ELSE 142 * POWER(l.creatinine / 0.7, -1.200) * POWER(0.9938, p.anchor_age) * 1.012
      END
    ELSE
      CASE 
        WHEN l.creatinine <= 0.9 THEN 142 * POWER(l.creatinine / 0.9, -0.302) * POWER(0.9938, p.anchor_age)
        ELSE 142 * POWER(l.creatinine / 0.9, -1.200) * POWER(0.9938, p.anchor_age)
      END
  END AS egfr_admission,
  
  -- Advanced CKD flag
  COALESCE(ackd.chronic_advanced_ckd, 0) AS chronic_advanced_ckd

-- =============================================================================
-- JOINS
-- =============================================================================
FROM home_diuretics h
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON h.subject_id = p.subject_id
LEFT JOIN labs l ON h.hadm_id = l.hadm_id
LEFT JOIN dbp_combined d ON h.stay_id = d.stay_id
LEFT JOIN charlson ch ON h.hadm_id = ch.hadm_id
LEFT JOIN hypertension htn ON h.hadm_id = htn.hadm_id
LEFT JOIN afib_icd ai ON h.hadm_id = ai.hadm_id
LEFT JOIN afib_ed ae ON h.hadm_id = ae.hadm_id
LEFT JOIN afib_icu aicu ON h.hadm_id = aicu.hadm_id
LEFT JOIN prior_hf phf ON h.hadm_id = phf.hadm_id
LEFT JOIN lvef_final lv ON h.hadm_id = lv.hadm_id
LEFT JOIN cs_icd csi ON h.hadm_id = csi.hadm_id
LEFT JOIN cs_nlp csn ON h.hadm_id = csn.hadm_id
LEFT JOIN urine_output uo ON h.stay_id = uo.stay_id
LEFT JOIN iv_diuretics ivd ON h.stay_id = ivd.stay_id
LEFT JOIN vasopressors vp ON h.stay_id = vp.stay_id
LEFT JOIN dobutamine dob ON h.stay_id = dob.stay_id
LEFT JOIN milrinone mil ON h.stay_id = mil.stay_id
LEFT JOIN mcs m ON h.stay_id = m.stay_id
LEFT JOIN invasive_vent iv ON h.stay_id = iv.stay_id
LEFT JOIN esrd e ON h.hadm_id = e.hadm_id
LEFT JOIN advanced_ckd ackd ON h.hadm_id = ackd.hadm_id

-- Deduplicate: Keep first ICU stay per hospital admission
QUALIFY ROW_NUMBER() OVER (PARTITION BY h.hadm_id ORDER BY h.icu_intime) = 1
;
