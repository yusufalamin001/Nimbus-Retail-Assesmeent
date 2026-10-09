# Nimbus Retail Partners: SQL Assessment

Database engineering onboarding project. Built on PostgreSQL 17 and run through pgAdmin 4.

## Layout

```
nimbus-retail-sql/
  README.md
  nimbus_assessment.sql
  screenshots/
    task11_plan_before.png
    task12_plan_after.png
    task13_plans.png
    task15_sessions.png
    task16_3nf_diagram.png
```

`nimbus_assessment.sql` holds every task in order, with a short comment above each one.

## How to run it

1. Create a database called `nimbus_retail`.
2. Run the Phase 1 section of the script to create the five tables.
3. Import the CSVs with pgAdmin's Import/Export tool in this order: customers, orders, order_items, messy_customers, employees. Parents go in before children because of the foreign keys. The CSVs are not included in this repo.
4. Run the rest of the script one task at a time. Tasks 11 to 13 build their own `perf_` tables, and Task 16 creates a separate schema called `nimbus_3nf`.

