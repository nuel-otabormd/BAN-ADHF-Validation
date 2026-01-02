-- =============================================================================
-- BAN-ADHF ICU Validation Study
-- Step 2: Restrict to Cardiac/Medical ICUs
-- =============================================================================
-- Excludes: SICU, TSICU, Neuro ICU
-- Output: N = 12,766
-- =============================================================================

CREATE OR REPLACE TABLE `YOUR-PROJECT-ID.ban_adhf.step2_cardiac_medical_icu` AS

SELECT *
FROM `YOUR-PROJECT-ID.ban_adhf.step1_adhf_icu_all`
WHERE first_careunit IN (
  'Coronary Care Unit (CCU)',
  'Cardiac Vascular Intensive Care Unit (CVICU)',
  'Medical Intensive Care Unit (MICU)',
  'Medical/Surgical Intensive Care Unit (MICU/SICU)'
)
;
