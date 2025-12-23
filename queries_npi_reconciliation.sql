-- ============================================================================
-- NPI RECONCILIATION ACROSS SYSTEMS
-- ============================================================================
-- PURPOSE: Find provider NPIs that exist in one system but not others.
--          Missing NPIs cause claims failures, attribution problems, and
--          broken provider directories.
--
-- BUSINESS CONTEXT:
--   - New providers join the network but don't get added to all systems
--   - Eligibility files contain NPIs we've never seen before
--   - CRM, reference tables, and claims systems get out of sync
-- ============================================================================

-- PATTERN 1: Basic Cross-System NPI Check
-- Find NPIs that are missing from reference tables or CRM

SELECT 
    e.npi,
    e.provider_name,
    CASE WHEN ref.npi IS NOT NULL THEN 'Y' ELSE 'N' END AS in_reference,
    CASE WHEN crm.npi IS NOT NULL THEN 'Y' ELSE 'N' END AS in_crm,
    CASE 
        WHEN ref.npi IS NULL AND crm.npi IS NULL THEN 'Missing from BOTH'
        WHEN ref.npi IS NULL THEN 'Missing from Reference'
        WHEN crm.npi IS NULL THEN 'Missing from CRM'
        ELSE 'OK'
    END AS status
FROM eligibility_npis e
LEFT JOIN reference.providers ref ON e.npi = ref.npi
LEFT JOIN crm.providers crm ON e.npi = crm.npi
WHERE ref.npi IS NULL OR crm.npi IS NULL
ORDER BY status, e.provider_name;


-- PATTERN 2: Full Reconciliation Report
-- Show ALL NPIs and their presence across multiple systems

SELECT 
    COALESCE(e.npi, r.npi, c.npi, cl.npi) AS npi,
    -- Where does this NPI exist?
    CASE WHEN e.npi IS NOT NULL THEN '✓' ELSE '✗' END AS in_eligibility,
    CASE WHEN r.npi IS NOT NULL THEN '✓' ELSE '✗' END AS in_reference,
    CASE WHEN c.npi IS NOT NULL THEN '✓' ELSE '✗' END AS in_crm,
    CASE WHEN cl.npi IS NOT NULL THEN '✓' ELSE '✗' END AS in_claims,
    -- Count how many systems have it
    (CASE WHEN e.npi IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN r.npi IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN c.npi IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN cl.npi IS NOT NULL THEN 1 ELSE 0 END) AS system_count
FROM eligibility_npis e
FULL OUTER JOIN reference.providers r ON e.npi = r.npi
FULL OUTER JOIN crm.providers c ON COALESCE(e.npi, r.npi) = c.npi
FULL OUTER JOIN claims.providers cl ON COALESCE(e.npi, r.npi, c.npi) = cl.npi
ORDER BY system_count ASC, npi;  -- Show problem NPIs first


-- PATTERN 3: New NPIs Not Yet Onboarded
-- NPIs appearing in eligibility files that we haven't set up yet

SELECT 
    e.npi,
    e.provider_name,
    e.first_seen_date,
    e.member_count,  -- How many patients are attributed to this provider?
    DATEDIFF(CURRENT_DATE, e.first_seen_date) AS days_waiting
FROM eligibility_npis e
LEFT JOIN reference.providers ref ON e.npi = ref.npi
WHERE ref.npi IS NULL
ORDER BY e.member_count DESC;  -- Prioritize high-impact providers


-- PATTERN 4: Orphaned NPIs (In Reference but No Longer in Eligibility)
-- Providers who may have left the network

SELECT 
    r.npi,
    r.provider_name,
    r.added_date,
    r.last_claim_date,
    DATEDIFF(CURRENT_DATE, r.last_claim_date) AS days_since_claim
FROM reference.providers r
LEFT JOIN eligibility_npis e ON r.npi = e.npi
WHERE e.npi IS NULL
  AND r.status = 'ACTIVE'  -- Still marked active in our system
ORDER BY r.last_claim_date DESC;


-- PATTERN 5: NPI Data Quality Issues
-- Find NPIs with mismatched data across systems

SELECT 
    r.npi,
    r.provider_name AS ref_name,
    c.provider_name AS crm_name,
    r.specialty AS ref_specialty,
    c.specialty AS crm_specialty,
    CASE 
        WHEN r.provider_name != c.provider_name THEN 'Name Mismatch'
        WHEN r.specialty != c.specialty THEN 'Specialty Mismatch'
        ELSE 'Unknown'
    END AS issue_type
FROM reference.providers r
JOIN crm.providers c ON r.npi = c.npi
WHERE r.provider_name != c.provider_name
   OR r.specialty != c.specialty;


-- PATTERN 6: Summary Dashboard
-- High-level view for management reporting

SELECT 
    'Total Unique NPIs' AS metric,
    COUNT(DISTINCT COALESCE(e.npi, r.npi, c.npi)) AS value
FROM eligibility_npis e
FULL OUTER JOIN reference.providers r ON e.npi = r.npi
FULL OUTER JOIN crm.providers c ON COALESCE(e.npi, r.npi) = c.npi

UNION ALL

SELECT 
    'Missing from Reference' AS metric,
    COUNT(*) AS value
FROM eligibility_npis e
LEFT JOIN reference.providers r ON e.npi = r.npi
WHERE r.npi IS NULL

UNION ALL

SELECT 
    'Missing from CRM' AS metric,
    COUNT(*) AS value
FROM eligibility_npis e
LEFT JOIN crm.providers c ON e.npi = c.npi
WHERE c.npi IS NULL

UNION ALL

SELECT 
    'Fully Reconciled' AS metric,
    COUNT(*) AS value
FROM eligibility_npis e
JOIN reference.providers r ON e.npi = r.npi
JOIN crm.providers c ON e.npi = c.npi;
