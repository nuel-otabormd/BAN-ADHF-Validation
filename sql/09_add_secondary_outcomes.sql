-- =============================================================================
-- BAN-ADHF ICU Validation Study
-- Step 9: Add Secondary Outcomes to Final Cohort
-- =============================================================================
-- Run AFTER 07_final_cohort_complete.sql
-- Adds: Urine output, diuretic efficiency, vasopressors, inotropes, MCS, LOS
-- Uses MIMIC-IV derived tables for consistency
-- =============================================================================

CREATE OR REPLACE TABLE `YOUR-PROJECT-ID.ban_adhf.final_cohort` AS

WITH first_day_uop AS (
  SELECT stay_id, urineoutput AS urine_output_24h
  FROM `physionet-data.mimiciv_3_1_derived.first_day_urine_output`
),

uop_72h AS (
  SELECT 
    fc.stay_id,
    SUM(uo.urineoutput) AS urine_output_72h
  FROM `YOUR-PROJECT-ID.ban_adhf.final_cohort` fc
  INNER JOIN `physionet-data.mimiciv_3_1_derived.urine_output` uo
    ON fc.stay_id = uo.stay_id
  WHERE uo.charttime >= fc.icu_intime
    AND uo.charttime < DATETIME_ADD(fc.icu_intime, INTERVAL 72 HOUR)
  GROUP BY fc.stay_id
),

vasopressors AS (
  SELECT DISTINCT stay_id, 1 AS vasopressor_use
  FROM `physionet-data.mimiciv_3_1_derived.norepinephrine_equivalent_dose`
),

dobutamine AS (
  SELECT DISTINCT stay_id, 1 AS dobutamine_use
  FROM `physionet-data.mimiciv_3_1_derived.dobutamine`
),

milrinone AS (
  SELECT DISTINCT stay_id, 1 AS milrinone_use
  FROM `physionet-data.mimiciv_3_1_derived.milrinone`
),

-- MCS from invasive_line (IABP, Impella, Tandem Heart)
mcs_invasive AS (
  SELECT DISTINCT stay_id, 1 AS mcs_invasive
  FROM `physionet-data.mimiciv_3_1_derived.invasive_line`
  WHERE line_type IN ('IABP', 'Impella Line', 'Tandem Heart Inflow Line', 'Tandem Heart Outflow Line')
),

-- MCS from procedureevents (ECMO)
mcs_ecmo AS (
  SELECT DISTINCT stay_id, 1 AS mcs_ecmo
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid IN (229529, 229530)
),

iv_diuretics_24h AS (
  SELECT 
    fc.stay_id,
    SUM(
      CASE 
        WHEN ie.itemid IN (221794, 228340) THEN ie.amount  -- IV Furosemide
        WHEN ie.itemid = 229639 THEN ie.amount * 40        -- IV Bumetanide (1mg = 40mg furosemide)
        ELSE 0
      END
    ) AS iv_diuretic_dose_24h_mg
  FROM `YOUR-PROJECT-ID.ban_adhf.final_cohort` fc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON fc.stay_id = ie.stay_id
  WHERE ie.itemid IN (221794, 228340, 229639)
    AND ie.starttime >= fc.icu_intime
    AND ie.starttime < DATETIME_ADD(fc.icu_intime, INTERVAL 24 HOUR)
  GROUP BY fc.stay_id
),

iv_diuretics_72h AS (
  SELECT 
    fc.stay_id,
    SUM(
      CASE 
        WHEN ie.itemid IN (221794, 228340) THEN ie.amount  -- IV Furosemide
        WHEN ie.itemid = 229639 THEN ie.amount * 40        -- IV Bumetanide (1mg = 40mg furosemide)
        ELSE 0
      END
    ) AS iv_diuretic_dose_72h_mg
  FROM `YOUR-PROJECT-ID.ban_adhf.final_cohort` fc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON fc.stay_id = ie.stay_id
  WHERE ie.itemid IN (221794, 228340, 229639)
    AND ie.starttime >= fc.icu_intime
    AND ie.starttime < DATETIME_ADD(fc.icu_intime, INTERVAL 72 HOUR)
  GROUP BY fc.stay_id
)

SELECT 
  fc.*,
  
  -- Urine output
  COALESCE(uop24.urine_output_24h, 0) AS urine_output_24h_ml,
  COALESCE(uop72.urine_output_72h, 0) AS urine_output_72h_ml,
  
  -- Diuretic resistance (≤3000 mL in 24h)
  CASE WHEN COALESCE(uop24.urine_output_24h, 0) <= 3000 THEN 1 ELSE 0 END AS diuretic_resistance,
  
  -- Vasopressor and inotrope use
  COALESCE(v.vasopressor_use, 0) AS vasopressor_use,
  COALESCE(dob.dobutamine_use, 0) AS dobutamine_use,
  COALESCE(mil.milrinone_use, 0) AS milrinone_use,
  CASE WHEN COALESCE(dob.dobutamine_use, 0) = 1 OR COALESCE(mil.milrinone_use, 0) = 1 
       THEN 1 ELSE 0 END AS inotrope_use,
  
  -- Mechanical circulatory support (IABP, Impella, Tandem Heart, ECMO)
  CASE WHEN COALESCE(mcs_i.mcs_invasive, 0) = 1 OR COALESCE(mcs_e.mcs_ecmo, 0) = 1 
       THEN 1 ELSE 0 END AS mcs_use,
  
  -- IV diuretic doses (furosemide equivalents)
  COALESCE(iv24.iv_diuretic_dose_24h_mg, 0) AS iv_diuretic_dose_24h_mg,
  COALESCE(iv72.iv_diuretic_dose_72h_mg, 0) AS iv_diuretic_dose_72h_mg,
  
  -- Diuretic efficiency - 24h (mL urine per mg IV diuretic)
  CASE 
    WHEN COALESCE(iv24.iv_diuretic_dose_24h_mg, 0) > 0 
    THEN ROUND(COALESCE(uop24.urine_output_24h, 0) / iv24.iv_diuretic_dose_24h_mg, 2)
    ELSE NULL 
  END AS diuretic_efficiency_24h,
  
  -- Diuretic efficiency - 72h (mL urine per mg IV diuretic) - matches original BAN-ADHF
  CASE 
    WHEN COALESCE(iv72.iv_diuretic_dose_72h_mg, 0) > 0 
    THEN ROUND(COALESCE(uop72.urine_output_72h, 0) / iv72.iv_diuretic_dose_72h_mg, 2)
    ELSE NULL 
  END AS diuretic_efficiency_72h,
  
  -- Length of stay
  ROUND(DATETIME_DIFF(fc.icu_outtime, fc.icu_intime, HOUR) / 24.0, 2) AS icu_los_days,
  ROUND(DATETIME_DIFF(fc.dischtime, fc.admittime, HOUR) / 24.0, 2) AS hospital_los_days,
  
  -- ICU stay duration flags (for analysis population restrictions)
  CASE WHEN DATETIME_DIFF(fc.icu_outtime, fc.icu_intime, HOUR) >= 24 THEN 1 ELSE 0 END AS icu_stay_ge_24h,
  CASE WHEN DATETIME_DIFF(fc.icu_outtime, fc.icu_intime, HOUR) >= 72 THEN 1 ELSE 0 END AS icu_stay_ge_72h

FROM `YOUR-PROJECT-ID.ban_adhf.final_cohort` fc
LEFT JOIN first_day_uop uop24 ON fc.stay_id = uop24.stay_id
LEFT JOIN uop_72h uop72 ON fc.stay_id = uop72.stay_id
LEFT JOIN vasopressors v ON fc.stay_id = v.stay_id
LEFT JOIN dobutamine dob ON fc.stay_id = dob.stay_id
LEFT JOIN milrinone mil ON fc.stay_id = mil.stay_id
LEFT JOIN mcs_invasive mcs_i ON fc.stay_id = mcs_i.stay_id
LEFT JOIN mcs_ecmo mcs_e ON fc.stay_id = mcs_e.stay_id
LEFT JOIN iv_diuretics_24h iv24 ON fc.stay_id = iv24.stay_id
LEFT JOIN iv_diuretics_72h iv72 ON fc.stay_id = iv72.stay_id
;
