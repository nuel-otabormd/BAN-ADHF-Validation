-- =============================================================================
-- BAN-ADHF ICU Validation Study
-- Step 5: Require ADHF in top 5 diagnosis positions
-- =============================================================================
-- Rationale: Ensures ADHF was primary/major diagnosis, not incidental
-- Criterion: seq_num <= 5
-- Output: N = 2,364
-- =============================================================================

CREATE OR REPLACE TABLE `YOUR-PROJECT-ID.ban_adhf.step5_adhf_top5_dx` AS

SELECT DISTINCT s.*
FROM `YOUR-PROJECT-ID.ban_adhf.step4_with_med_section` s

INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON s.hadm_id = dx.hadm_id

WHERE 
  -- ICD-10 Acute Heart Failure codes
  ((dx.icd_code IN ('I5021', 'I5023', 'I5031', 'I5033', 'I5041', 'I5043', 'J810')
    AND dx.icd_version = 10)
   OR
   -- ICD-9 Acute Heart Failure codes
   (dx.icd_code IN ('42821', '42823', '42831', '42833', '42841', '42843')
    AND dx.icd_version = 9))
  -- Must be in top 5 diagnosis positions
  AND dx.seq_num <= 5
  -- Must have valid medication section
  AND s.med_section IS NOT NULL
;
