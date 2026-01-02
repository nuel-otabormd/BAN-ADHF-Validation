-- =============================================================================
-- BAN-ADHF ICU Validation Study
-- Step 1: All ICU stays with Acute Heart Failure diagnosis codes
-- =============================================================================
-- Output: N = 14,614
-- =============================================================================

CREATE OR REPLACE TABLE `YOUR-PROJECT-ID.ban_adhf.step1_adhf_icu_all` AS

SELECT DISTINCT
  i.stay_id,
  i.hadm_id,
  i.subject_id,
  i.first_careunit,
  i.intime AS icu_intime,
  i.outtime AS icu_outtime,
  a.admittime,
  a.dischtime,
  a.hospital_expire_flag

FROM `physionet-data.mimiciv_3_1_icu.icustays` i

INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON i.hadm_id = a.hadm_id

INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON a.hadm_id = dx.hadm_id

WHERE 
  -- ICD-10 Acute Heart Failure codes
  (dx.icd_code IN ('I5021', 'I5023', 'I5031', 'I5033', 'I5041', 'I5043', 'J810')
   AND dx.icd_version = 10)
  OR
  -- ICD-9 Acute Heart Failure codes
  (dx.icd_code IN ('42821', '42823', '42831', '42833', '42841', '42843')
   AND dx.icd_version = 9)
;
