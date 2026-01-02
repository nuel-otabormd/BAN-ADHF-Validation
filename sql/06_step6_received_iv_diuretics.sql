-- =============================================================================
-- BAN-ADHF ICU Validation Study
-- Step 6: Require IV loop diuretics during ICU stay
-- =============================================================================
-- Rationale: Diuretic efficiency calculation requires IV diuretic administration
-- IV Diuretics: Furosemide (221794, 228340), Bumetanide (229639)
-- Output: N = 1,692
-- =============================================================================

CREATE OR REPLACE TABLE `YOUR-PROJECT-ID.ban_adhf.step6_received_iv_diuretics` AS

SELECT s.*
FROM `YOUR-PROJECT-ID.ban_adhf.step5_adhf_top5_dx` s

WHERE EXISTS (
  SELECT 1 
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  WHERE ie.stay_id = s.stay_id
    AND ie.itemid IN (
      221794,  -- Furosemide
      228340,  -- Furosemide (Concentrated)
      229639   -- Bumetanide
    )
)
;
