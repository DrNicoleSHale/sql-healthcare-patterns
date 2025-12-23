-- ============================================================================
-- MULTI-SOURCE DATE OVERLAP MATCHING
-- ============================================================================
-- PURPOSE: Match clinical events to authorizations using date overlap logic.
--          Healthcare data rarely has exact date matches - we need to find
--          records where date ranges intersect.
--
-- COMMON USE CASES:
--   - Matching inpatient events to authorizations
--   - Linking claims to clinical encounters
--   - Reconciling HIE notifications with internal records
-- ============================================================================

-- PATTERN 1: Basic Date Overlap Join
-- An authorization "covers" an event if their date ranges intersect
-- Think of it like two timelines - do they overlap at all?

SELECT 
    e.event_id,
    e.patient_id,
    e.admit_date,
    e.discharge_date,
    auth.authorization_id,
    auth.auth_start_date,
    auth.auth_end_date
FROM clinical_events e
LEFT JOIN authorizations auth
    ON e.patient_id = auth.patient_id
    -- Event starts before auth ends (or auth has no end date)
    AND e.admit_date <= COALESCE(auth.auth_end_date, auth.auth_start_date)
    -- Auth starts before event ends
    AND auth.auth_start_date <= e.discharge_date;


-- PATTERN 2: With Authorization Type Filtering
-- Often you only want specific auth types (inpatient, skilled nursing, etc.)

SELECT 
    e.event_id,
    e.patient_id,
    auth.authorization_id,
    auth.auth_type
FROM clinical_events e
LEFT JOIN authorizations auth
    ON e.patient_id = auth.patient_id
    AND e.admit_date <= COALESCE(auth.auth_end_date, auth.auth_start_date)
    AND auth.auth_start_date <= e.discharge_date
    AND auth.auth_type = 'INPATIENT'  -- Filter in the JOIN, not WHERE
WHERE e.event_type = 'ADMISSION';

-- NOTE: Filtering in the JOIN preserves events without matching auths.
--       Filtering in WHERE would exclude them entirely.


-- PATTERN 3: Handling Multiple Matches
-- One event might match multiple authorizations. Use ROW_NUMBER to pick the best one.

WITH matched AS (
    SELECT 
        e.event_id,
        e.patient_id,
        e.admit_date,
        auth.authorization_id,
        auth.auth_start_date,
        -- Prefer the auth that started closest to the event
        ROW_NUMBER() OVER (
            PARTITION BY e.event_id 
            ORDER BY ABS(DATEDIFF(e.admit_date, auth.auth_start_date))
        ) AS match_rank
    FROM clinical_events e
    LEFT JOIN authorizations auth
        ON e.patient_id = auth.patient_id
        AND e.admit_date <= COALESCE(auth.auth_end_date, auth.auth_start_date)
        AND auth.auth_start_date <= e.discharge_date
)
SELECT * FROM matched WHERE match_rank = 1;


-- PATTERN 4: Three-Way Match (Claims + HIE + Auth)
-- The full picture: which events have data in all three systems?

SELECT 
    e.event_id,
    e.patient_id,
    e.admit_date,
    -- Capture what we found in each system
    c.claim_id,
    h.hie_encounter_id,
    a.authorization_id,
    -- Categorize the match
    CASE 
        WHEN c.claim_id IS NOT NULL AND h.hie_encounter_id IS NOT NULL 
             AND a.authorization_id IS NOT NULL THEN 'full-match'
        WHEN c.claim_id IS NOT NULL AND a.authorization_id IS NOT NULL THEN 'claims-auth'
        WHEN h.hie_encounter_id IS NOT NULL AND a.authorization_id IS NOT NULL THEN 'hie-auth'
        WHEN c.claim_id IS NOT NULL THEN 'claims-only'
        WHEN h.hie_encounter_id IS NOT NULL THEN 'hie-only'
        WHEN a.authorization_id IS NOT NULL THEN 'auth-only'
        ELSE 'orphan'
    END AS match_type
FROM clinical_events e
LEFT JOIN claims c
    ON e.patient_id = c.patient_id
    AND e.admit_date = c.service_date  -- Claims often have exact dates
LEFT JOIN hie_encounters h
    ON e.patient_id = h.patient_id
    AND e.admit_date <= h.encounter_end
    AND h.encounter_start <= e.discharge_date
LEFT JOIN authorizations a
    ON e.patient_id = a.patient_id
    AND e.admit_date <= COALESCE(a.auth_end_date, a.auth_start_date)
    AND a.auth_start_date <= e.discharge_date;
