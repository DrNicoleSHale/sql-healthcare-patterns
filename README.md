# SQL Healthcare Patterns

## 📋 Overview

Collection of advanced SQL patterns for healthcare data analytics including multi-payer reconciliation, clinical event matching, and notification timing analysis.

---

## 🛠️ Technologies

- Databricks SQL
- Also works with: MS SQL Server, PostgreSQL

---

## 📊 Pattern Categories

1. **Multi-Source Data Matching** - Joining Claims, HIE, Authorizations
2. **Hierarchical Aggregations** - GROUPING SETS for reporting
3. **Provider Attribution** - Patient-to-office matching
4. **Notification Timing** - Date lag analysis
5. **NPI Reconciliation** - Cross-system provider matching

---

## 🔧 Key Patterns

### Multi-Source Matching
```sql
LEFT JOIN clinical.events ie
    ON auth.patient_id = ie.patient_id
    AND ie.admit_date <= auth.discharge_date
    AND auth.admission_date <= ie.discharge_date
```

### Hierarchical Aggregations
```sql
GROUP BY GROUPING SETS (
    (region, office, match_type),
    (region, office),
    (region),
    ()
)
```

### Window Functions
```sql
ROW_NUMBER() OVER (
    PARTITION BY patient_id, event_date 
    ORDER BY created_timestamp DESC
) AS event_rank
```

### NPI Reconciliation
```sql
SELECT npi,
    CASE WHEN ref.npi IS NOT NULL THEN 'Y' ELSE 'N' END AS in_reference,
    CASE WHEN crm.npi IS NOT NULL THEN 'Y' ELSE 'N' END AS in_crm
FROM eligibility_npis e
LEFT JOIN reference.providers ref ON e.npi = ref.npi
LEFT JOIN crm.providers crm ON e.npi = crm.npi
WHERE ref.npi IS NULL OR crm.npi IS NULL
```

---

## 📁 Files

| File | Description |
|------|-------------|
| `queries/multi_source_matching.sql` | Join patterns |
| `queries/grouping_sets.sql` | Aggregation examples |
