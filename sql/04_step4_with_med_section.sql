-- =============================================================================
-- BAN-ADHF ICU Validation Study
-- Step 4: Require medication reconciliation section in discharge notes
-- =============================================================================
-- Rationale: Home diuretic dose extraction requires medication section
-- Method: SPLIT truncation to extract "Medications on Admission" section
-- Output: N = 2,862
-- =============================================================================

CREATE OR REPLACE TABLE `YOUR-PROJECT-ID.ban_adhf.step4_with_med_section` AS

SELECT 
  s.*,
  SPLIT(
    COALESCE(
      REGEXP_EXTRACT(d.text, r'(?is)Medications on Admission[:\s]*(.{0,1000})'),
      REGEXP_EXTRACT(d.text, r'(?is)Preadmission Medication[^\n]*[:\s]*(.{0,1000})')
    ),
    'Discharge Medications'
  )[SAFE_OFFSET(0)] AS med_section

FROM `YOUR-PROJECT-ID.ban_adhf.step3_with_ntprobnp` s

INNER JOIN `physionet-data.mimiciv_note.discharge` d
  ON s.hadm_id = d.hadm_id

WHERE LOWER(d.text) LIKE '%medications on admission%' 
   OR LOWER(d.text) LIKE '%preadmission medication%'
;
