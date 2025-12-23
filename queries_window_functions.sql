-- ============================================================================
-- WINDOW FUNCTIONS FOR HEALTHCARE DATA
-- ============================================================================
-- PURPOSE: Deduplication, ranking, running totals, and comparative analysis
--          without losing row-level detail.
--
-- WHY WINDOW FUNCTIONS:
--   - Regular GROUP BY collapses rows; window functions keep them
--   - Calculate aggregates while preserving individual records
--   - Essential for "keep the best record" deduplication patterns
-- ============================================================================

-- PATTERN 1: Deduplication with ROW_NUMBER
-- Healthcare data is messy - events get updated, corrected, resubmitted.
-- Keep only the most recent version of each record.

WITH ranked_events AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            PARTITION BY patient_id, event_date 
            ORDER BY created_timestamp DESC  -- Most recent first
        ) AS row_rank
    FROM source_events
)
SELECT * FROM ranked_events 
WHERE row_rank = 1;  -- Keep only the latest

-- PARTITION BY = "start counting over for each group"
-- ORDER BY = "what determines rank 1, 2, 3..."


-- PATTERN 2: First/Last Event per Patient
-- Find each patient's first admission (useful for new patient analysis)

WITH patient_events AS (
    SELECT 
        patient_id,
        admit_date,
        discharge_date,
        diagnosis,
        ROW_NUMBER() OVER (
            PARTITION BY patient_id 
            ORDER BY admit_date ASC  -- Earliest first
        ) AS visit_number
    FROM admissions
)
SELECT * FROM patient_events 
WHERE visit_number = 1;  -- First visit only

-- Change to DESC and visit_number = 1 for most RECENT visit


-- PATTERN 3: Running Totals
-- Track cumulative costs or counts over time

SELECT 
    event_date,
    daily_cost,
    SUM(daily_cost) OVER (
        ORDER BY event_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total,
    COUNT(*) OVER (
        ORDER BY event_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_count
FROM daily_summary
ORDER BY event_date;


-- PATTERN 4: Compare to Group Average
-- How does each office compare to the regional average?

SELECT 
    region,
    office_name,
    capture_rate,
    AVG(capture_rate) OVER (PARTITION BY region) AS region_avg,
    capture_rate - AVG(capture_rate) OVER (PARTITION BY region) AS vs_region_avg,
    CASE 
        WHEN capture_rate >= AVG(capture_rate) OVER (PARTITION BY region) 
        THEN 'Above Average'
        ELSE 'Below Average'
    END AS performance
FROM office_metrics;


-- PATTERN 5: Percent of Total
-- What percentage of events does each office represent?

SELECT 
    office_name,
    event_count,
    SUM(event_count) OVER () AS company_total,
    ROUND(event_count * 100.0 / SUM(event_count) OVER (), 1) AS pct_of_total
FROM office_summary
ORDER BY event_count DESC;


-- PATTERN 6: LAG/LEAD for Trend Analysis
-- Compare current month to previous month

SELECT 
    month_year,
    event_count,
    LAG(event_count, 1) OVER (ORDER BY month_year) AS prev_month,
    event_count - LAG(event_count, 1) OVER (ORDER BY month_year) AS month_change,
    ROUND(
        (event_count - LAG(event_count, 1) OVER (ORDER BY month_year)) * 100.0 
        / NULLIF(LAG(event_count, 1) OVER (ORDER BY month_year), 0)
    , 1) AS pct_change
FROM monthly_summary
ORDER BY month_year;

-- LAG(column, n) = value from n rows BEFORE current row
-- LEAD(column, n) = value from n rows AFTER current row


-- PATTERN 7: Readmission Detection
-- Flag patients readmitted within 30 days (CMS quality metric)

WITH admissions_with_next AS (
    SELECT 
        patient_id,
        admit_date,
        discharge_date,
        LEAD(admit_date) OVER (
            PARTITION BY patient_id 
            ORDER BY admit_date
        ) AS next_admit_date
    FROM admissions
)
SELECT 
    *,
    DATEDIFF(next_admit_date, discharge_date) AS days_to_readmit,
    CASE 
        WHEN DATEDIFF(next_admit_date, discharge_date) <= 30 
        THEN 'READMIT-30'
        ELSE 'OK'
    END AS readmit_flag
FROM admissions_with_next;


-- PATTERN 8: Dense Ranking for Ties
-- RANK() skips numbers after ties; DENSE_RANK() doesn't

SELECT 
    office_name,
    capture_rate,
    RANK() OVER (ORDER BY capture_rate DESC) AS rank_with_gaps,
    DENSE_RANK() OVER (ORDER BY capture_rate DESC) AS rank_no_gaps,
    ROW_NUMBER() OVER (ORDER BY capture_rate DESC) AS unique_position
FROM office_metrics;

-- If two offices tie for 1st:
--   RANK:       1, 1, 3, 4...  (skips 2)
--   DENSE_RANK: 1, 1, 2, 3...  (no skip)
--   ROW_NUMBER: 1, 2, 3, 4...  (arbitrary tiebreaker)


-- PATTERN 9: Quartile/Percentile
