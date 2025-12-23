-- ============================================================================
-- HIERARCHICAL AGGREGATIONS WITH GROUPING SETS
-- ============================================================================
-- PURPOSE: Generate multiple levels of aggregation in a single query.
--          Get detail rows, subtotals, and grand totals without UNION.
--
-- WHY THIS MATTERS:
--   - Executive reports need rollups at multiple levels
--   - One query is faster and easier to maintain than multiple UNIONs
--   - GROUPING SETS gives you control over exactly which levels you get
-- ============================================================================

-- PATTERN 1: Basic GROUPING SETS
-- Get office-level detail AND company-wide totals in one query

SELECT 
    COALESCE(office_name, 'COMPANY TOTAL') AS office_name,
    COUNT(*) AS event_count,
    SUM(cost) AS total_cost,
    ROUND(AVG(cost), 2) AS avg_cost
FROM patient_events
GROUP BY GROUPING SETS (
    (office_name),  -- One row per office
    ()              -- One grand total row (empty set = no grouping)
)
ORDER BY office_name NULLS LAST;

-- NOTE: The grand total row has NULL for office_name.
--       COALESCE replaces it with a friendly label.


-- PATTERN 2: Multi-Level Hierarchy
-- Region → Office → Match Type with subtotals at each level

SELECT 
    COALESCE(region, 'ALL REGIONS') AS region,
    COALESCE(office_name, 'ALL OFFICES') AS office_name,
    COALESCE(match_type, 'ALL TYPES') AS match_type,
    COUNT(*) AS event_count,
    ROUND(SUM(has_claims) * 100.0 / COUNT(*), 1) AS claims_pct
FROM categorized_events
GROUP BY GROUPING SETS (
    (region, office_name, match_type),  -- Full detail
    (region, office_name),               -- Office subtotal (all match types)
    (region),                            -- Region subtotal (all offices)
    ()                                   -- Grand total
)
ORDER BY 
    region NULLS LAST, 
    office_name NULLS LAST, 
    match_type NULLS LAST;


-- PATTERN 3: Using GROUPING() to Identify Rollup Rows
-- GROUPING() returns 1 if the column is aggregated (rolled up), 0 if not
-- Useful for conditional formatting or filtering

SELECT 
    region,
    office_name,
    COUNT(*) AS event_count,
    -- Identify what level this row represents
    CASE 
        WHEN GROUPING(region) = 1 THEN 'GRAND TOTAL'
        WHEN GROUPING(office_name) = 1 THEN 'REGION SUBTOTAL'
        ELSE 'DETAIL'
    END AS row_level
FROM patient_events
GROUP BY GROUPING SETS (
    (region, office_name),
    (region),
    ()
)
ORDER BY 
    GROUPING(region),      -- Grand total last
    region,
    GROUPING(office_name), -- Region subtotals after details
    office_name;


-- PATTERN 4: ROLLUP Shorthand
-- ROLLUP is a shortcut for common hierarchical patterns
-- ROLLUP(a, b, c) = GROUPING SETS ((a,b,c), (a,b), (a), ())

SELECT 
    COALESCE(region, 'TOTAL') AS region,
    COALESCE(office_name, 'SUBTOTAL') AS office_name,
    COUNT(*) AS event_count
FROM patient_events
GROUP BY ROLLUP(region, office_name)
ORDER BY region NULLS LAST, office_name NULLS LAST;

-- This is equivalent to:
-- GROUP BY GROUPING SETS (
--     (region, office_name),
--     (region),
--     ()
-- )


-- PATTERN 5: CUBE for All Combinations
-- CUBE gives you every possible combination of groupings
-- CUBE(a, b) = GROUPING SETS ((a,b), (a), (b), ())

SELECT 
    COALESCE(region, 'ALL') AS region,
    COALESCE(match_type, 'ALL') AS match_type,
    COUNT(*) AS event_count
FROM patient_events
GROUP BY CUBE(region, match_type)
ORDER BY region NULLS LAST, match_type NULLS LAST;

-- Use CUBE when you need a pivot-table style analysis
-- with totals on both dimensions


-- PATTERN 6: Real-World Executive Report
-- Combines multiple techniques for a polished output

SELECT 
    CASE 
        WHEN GROUPING(region) = 1 THEN '=== COMPANY TOTAL ==='
        WHEN GROUPING(office_name) = 1 THEN CONCAT('>> ', region, ' TOTAL')
        ELSE office_name
    END AS line_item,
    COUNT(*) AS events,
    SUM(CASE WHEN claim_id IS NOT NULL THEN 1 ELSE 0 END) AS with_claims,
    ROUND(SUM(CASE WHEN claim_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS claims_pct,
    CASE 
        WHEN GROUPING(region) = 1 THEN 0  -- Sort grand total last
        WHEN GROUPING(office_name) = 1 THEN 1  -- Then region totals
        ELSE 2  -- Details first
    END AS sort_order
FROM patient_events
GROUP BY GROUPING SETS (
    (region, office_name),
    (region),
    ()
)
ORDER BY 
    region NULLS LAST,
    sort_order,
    office_name;
