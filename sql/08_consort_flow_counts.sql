-- =============================================================================
-- BAN-ADHF ICU Validation Study
-- CONSORT Flow Diagram: Patient Counts at Each Step
-- =============================================================================
-- This query generates counts for the CONSORT flow diagram
-- Run after all step tables have been created
-- =============================================================================

WITH counts AS (
  SELECT 'Step 1: ICU stays with acute HF diagnosis' AS step, 
         COUNT(*) AS n_remaining,
         NULL AS n_excluded,
         NULL AS exclusion_reason
  FROM `YOUR-PROJECT-ID.ban_adhf.step1_adhf_icu_all`
  
  UNION ALL
  
  SELECT 'Step 2: Cardiac/Medical ICUs only',
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step2_cardiac_medical_icu`),
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step1_adhf_icu_all`) - 
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step2_cardiac_medical_icu`),
         'SICU, TSICU, Neuro ICU'
  
  UNION ALL
  
  SELECT 'Step 3: NT-proBNP available',
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step3_with_ntprobnp`),
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step2_cardiac_medical_icu`) - 
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step3_with_ntprobnp`),
         'No NT-proBNP measurement'
  
  UNION ALL
  
  SELECT 'Step 4: Medication reconciliation extractable',
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step4_with_med_section`),
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step3_with_ntprobnp`) - 
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step4_with_med_section`),
         'No med reconciliation in notes'
  
  UNION ALL
  
  SELECT 'Step 5: ADHF in top 5 diagnoses',
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step5_adhf_top5_dx`),
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step4_with_med_section`) - 
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step5_adhf_top5_dx`),
         'ADHF incidental diagnosis'
  
  UNION ALL
  
  SELECT 'Step 6: Received IV diuretics',
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step6_received_iv_diuretics`),
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step5_adhf_top5_dx`) - 
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step6_received_iv_diuretics`),
         'No IV loop diuretics given'
  
  UNION ALL
  
  SELECT 'Step 7: Final cohort (first ICU stay per admission)',
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.final_cohort`),
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.step6_received_iv_diuretics`) - 
         (SELECT COUNT(*) FROM `YOUR-PROJECT-ID.ban_adhf.final_cohort`),
         'Duplicate ICU stays removed'
)

SELECT 
  step,
  n_remaining,
  n_excluded,
  exclusion_reason
FROM counts
ORDER BY 
  CASE 
    WHEN step LIKE 'Step 1%' THEN 1
    WHEN step LIKE 'Step 2%' THEN 2
    WHEN step LIKE 'Step 3%' THEN 3
    WHEN step LIKE 'Step 4%' THEN 4
    WHEN step LIKE 'Step 5%' THEN 5
    WHEN step LIKE 'Step 6%' THEN 6
    WHEN step LIKE 'Step 7%' THEN 7
  END
;
