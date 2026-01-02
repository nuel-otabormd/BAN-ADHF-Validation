-- =============================================================================
-- BAN-ADHF ICU Validation Study
-- Step 3: Require NT-proBNP during hospitalization
-- =============================================================================
-- Rationale: NT-proBNP is required for BAN-ADHF score calculation
-- Output: N = 4,103
-- =============================================================================

CREATE OR REPLACE TABLE `YOUR-PROJECT-ID.ban_adhf.step3_with_ntprobnp` AS

SELECT DISTINCT s.*
FROM `YOUR-PROJECT-ID.ban_adhf.step2_cardiac_medical_icu` s

INNER JOIN `physionet-data.mimiciv_3_1_derived.cardiac_marker` c
  ON s.hadm_id = c.hadm_id

WHERE c.ntprobnp IS NOT NULL
;
