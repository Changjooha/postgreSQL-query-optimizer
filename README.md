# PostgreSQL Query Optimizer Experiment

An experimental analysis of PostgreSQL's cost-based query optimizer by modifying the estimated cost of Sequential Scan and observing how the execution plan changes.

The project was originally developed while studying database query optimization and PostgreSQL internals.

Rather than attempting to improve PostgreSQL performance, the objective was to understand how the optimizer compares alternative access paths and how changes in estimated cost can affect the selected query plan.

---

## Overview

PostgreSQL does not automatically choose an index simply because one exists.

Instead, the query optimizer estimates the cost of multiple candidate execution paths and selects the plan with the lowest estimated cost.

This project investigates that behavior by modifying the cost assigned to Sequential Scan for relatively large relations.

The experiment follows this process:

```text
SQL Query
    ↓
PostgreSQL Planner
    ↓
Alternative Access Paths
    ↓
Cost Estimation
    ↓
Sequential Scan Cost Modification
    ↓
EXPLAIN
    ↓
Execution Plan Comparison
```

The main observation was:

```text
Before modification

enrollment
    ↓
Sequential Scan


After modification

enrollment
    ↓
Bitmap Heap Scan
    ↓
Bitmap Index Scan
```

The index already existed before the modification.

Only the estimated cost of the Sequential Scan path was changed.

---

## Environment

- PostgreSQL 15.2
- C
- SQL
- Linux
- PostgreSQL source code
- `EXPLAIN`
- PostgreSQL cost-based query optimizer

---

## Repository Structure

```text
postgresql-query-optimizer/
│
├── README.md
├── .gitignore
│
├── sql/
│   ├── 01_setup.sql
│   ├── 02_indexes.sql
│   └── 03_experiment.sql
│
├── patch/
│   └── cost_seqscan_penalty.patch
│
├── results/
│   ├── baseline_plan.txt
│   └── modified_plan.txt
│
└── docs/
    ├── baseline_plan.png
    └── modified_plan.png
```

The full PostgreSQL source tree is intentionally not included.

Instead, this repository contains only the experimental patch applied to the PostgreSQL source code.

---

# 1. Motivation

The initial question behind the experiment was:

> Why does PostgreSQL sometimes choose a Sequential Scan even when an index exists?

An index was created on:

```text
enrollment.grade
```

However, the original execution plan still used:

```text
Seq Scan on enrollment
```

for the following predicate:

```sql
e.grade IN ('A', 'B', 'C')
```

The condition matches a large portion of the `enrollment` relation.

Using an index does not automatically make a query cheaper because PostgreSQL must also consider the cost of locating index entries and retrieving the corresponding heap pages.

This made the query a useful example for observing PostgreSQL's cost-based decision process.

---

# 2. PostgreSQL Optimizer Code Reading

Before modifying the optimizer, I followed several parts of the PostgreSQL planning process.

The main code-reading path was:

```text
standard_planner()
        ↓
set_base_rel_pathlists()
        ↓
cost_seqscan()
```

---

## 2.1 `standard_planner()`

Location:

```text
src/backend/optimizer/plan/planner.c
```

`standard_planner()` was used as the starting point for understanding the overall planning process.

At a high level:

```text
Parsed Query
     ↓
Planner
     ↓
Path Generation
     ↓
Cost Comparison
     ↓
Final Plan
```

The purpose of examining this function was not to analyze every implementation detail, but to understand how planning proceeds toward lower-level path generation and cost estimation.

---

## 2.2 `set_base_rel_pathlists()`

Location:

```text
src/backend/optimizer/path/allpaths.c
```

The next question was:

> Where are candidate access paths such as Sequential Scan and Index Scan created?

For each base relation, PostgreSQL can construct multiple possible access paths.

Conceptually:

```text
Relation
   │
   ├── Sequential Scan
   │
   ├── Index Scan
   │
   ├── Bitmap Heap Scan
   │
   └── Other possible paths
           ↓
     Cost Comparison
```

These paths can then compete based on their estimated costs.

---

## 2.3 `cost_seqscan()`

Location:

```text
src/backend/optimizer/path/costsize.c
```

`cost_seqscan()` estimates the cost of reading a relation using a Sequential Scan.

This function became the main target of the experiment because modifying its output provides a direct way to observe whether the planner selects a different access path.

---

# 3. Experimental Database

The experiment uses four relations representing a simplified university database.

```text
department
     ↑
   course
     ↑
 enrollment
     ↑
   student
```

The tables are generated using:

```text
sql/01_setup.sql
```

Indexes and PostgreSQL statistics are prepared using:

```text
sql/02_indexes.sql
```

The relevant indexes include:

```sql
CREATE INDEX idx_student_year
ON student(entrance_year);

CREATE INDEX idx_department_name
ON department(dept_name);

CREATE INDEX idx_enrollment_grade
ON enrollment(grade);

ANALYZE;
```

Running `ANALYZE` allows PostgreSQL to collect statistics that are used during cost estimation.

---

# 4. Experiment Query

The experiment uses the following four-table JOIN query:

```sql
EXPLAIN
SELECT
    s.name,
    c.title,
    d.dept_name,
    e.grade
FROM student s
JOIN enrollment e
    ON s.student_id = e.student_id
JOIN course c
    ON e.course_id = c.course_id
JOIN department d
    ON c.dept_id = d.dept_id
WHERE s.entrance_year >= 2020
  AND d.dept_name = 'Dept_3'
  AND e.grade IN ('A', 'B', 'C');
```

This query was chosen because multiple indexed and non-indexed access paths can compete during planning.

In particular:

```text
student.entrance_year
        ↓
idx_student_year

enrollment.grade
        ↓
idx_enrollment_grade
```

Both columns have indexes.

However, the baseline execution plan uses them differently.

---

# 5. Baseline Execution Plan

Before modifying PostgreSQL, the important portion of the execution plan was:

```text
Hash Join

    ↓

Hash Join

    ↓

Seq Scan on enrollment e
    cost = 0.00..1916.00

    Filter:
    grade IN ('A', 'B', 'C')
```

At the same time, PostgreSQL chose an index-based path for the `student` relation:

```text
Bitmap Heap Scan on student

    ↓

Bitmap Index Scan on idx_student_year
```

This was an important observation.

PostgreSQL was not simply choosing either:

```text
always use indexes
```

or:

```text
always use sequential scans
```

Instead, different access paths were selected independently according to their estimated costs.

The complete baseline result is stored in:

```text
results/baseline_plan.txt
```

A captured result is also available in:

```text
docs/baseline_plan.png
```

---

# 6. Observing Sequential Scan Cost

Before changing the optimizer cost, I added temporary logging inside `cost_seqscan()`.

```c
if (baserel->pages > 100)
{
    elog(NOTICE,
         "[Assignment 4 BEFORE] SeqScan large relation detected: "
         "pages=%.0f, total_cost=%.2f",
         (double) baserel->pages,
         path->total_cost);
}
```

The condition:

```c
baserel->pages > 100
```

was used to focus the experiment on relatively large relations and avoid excessive debugging output from very small tables.

For the relevant `enrollment` relation, the observed values were approximately:

```text
pages      = 541
total_cost = 1916.00
```

This confirmed that the Sequential Scan candidate was being generated and assigned an estimated cost before the final execution plan was selected.

---

# 7. Initial Attempts

My first idea was to increase a portion of the Sequential Scan runtime cost.

Conceptually:

```text
run_cost × penalty
```

I experimented with larger multipliers, including increasing the runtime component several times.

However, simply modifying that intermediate component did not produce the execution-plan change I was trying to observe.

This was useful because it showed that changing an internal cost component does not necessarily guarantee that the final relative ordering of candidate paths will change.

I therefore changed the experiment to modify the final estimated cost stored in:

```c
path->total_cost
```

---

# 8. Final Modification

The final experiment applies a penalty to the estimated Sequential Scan cost for relations larger than 100 pages.

The modification was made inside:

```text
src/backend/optimizer/path/costsize.c
```

in:

```text
cost_seqscan()
```

The essential modification is:

```c
if (baserel->pages > 100)
{
    elog(NOTICE,
         "[Assignment 4 AFTER] Original SeqScan cost: "
         "pages=%.0f, total_cost=%.2f",
         (double) baserel->pages,
         path->total_cost);

    path->total_cost *= 2.0;

    elog(NOTICE,
         "[Assignment 4 AFTER] Penalty applied! "
         "Penalized total_cost=%.2f",
         path->total_cost);
}
```

The full experimental change is stored as:

```text
patch/cost_seqscan_penalty.patch
```

---

# 9. Why Only Large Relations?

The experiment intentionally does not penalize every Sequential Scan.

For small relations:

```text
Sequential Scan
```

can be cheaper than:

```text
Index Traversal
      +
Heap Access
```

Therefore, the experimental condition:

```c
baserel->pages > 100
```

limits the artificial penalty to larger relations.

This threshold is experimental and was chosen for observing planner behavior.

It is **not** intended to represent a production-quality optimization rule.

---

# 10. Result

After applying the modification, the Sequential Scan estimated cost changed from:

```text
1916.00
```

to:

```text
3832.00
```

The important access-path change was:

### Before

```text
Seq Scan on enrollment
```

### After

```text
Bitmap Heap Scan on enrollment
        ↓
Bitmap Index Scan on idx_enrollment_grade
```

The index had existed in both experiments.

The change occurred because the relative estimated cost of the competing access paths changed.

---

## Before / After Comparison

| Metric | Baseline | Modified |
|---|---|---|
| Sequential Scan estimated cost | `1916.00` | `3832.00` |
| `enrollment` access path | Sequential Scan | Bitmap Heap Scan |
| `idx_enrollment_grade` | Not selected | Bitmap Index Scan |
| `student` access path | Bitmap Heap / Index Scan | Bitmap Heap / Index Scan |
| Main join method | Hash Join | Hash Join |
| Top-level estimated cost | `259.30..2526.87` | `1032.08..2953.52` |

One interesting result is that the access method changed while the main join algorithm remained a Hash Join.

Therefore:

```text
Changing base relation access cost
               ↓
can change scan selection
               ↓
without necessarily changing
the join algorithm
```

---

# 11. Modified Execution Plan

After the modification, the relevant part of the plan became:

```text
Hash Join

    ↓

Hash Join

    ↓

Bitmap Heap Scan on enrollment e
    cost = 772.78..2342.65

        ↓

Bitmap Index Scan on idx_enrollment_grade
    cost = 0.00..754.07
```

The complete modified plan is stored in:

```text
results/modified_plan.txt
```

The captured result is available in:

```text
docs/modified_plan.png
```

---

# 12. What the Experiment Demonstrates

The experiment illustrates several characteristics of a cost-based query optimizer.

### 1. An index is not automatically selected

```text
Index Exists
    ≠
Index Will Be Used
```

The optimizer evaluates whether the estimated cost of using the index is lower than alternative paths.

---

### 2. Predicate characteristics affect access-path decisions

The condition:

```sql
grade IN ('A', 'B', 'C')
```

matches a large fraction of the relation.

When many tuples must be retrieved, index access can lose some of its advantage because many heap pages may still need to be accessed.

---

### 3. Access-path selection depends on relative cost

Originally:

```text
Sequential Scan
```

was considered competitive enough to be selected.

After artificially increasing its estimated cost:

```text
Sequential Scan
        ↓
less competitive
        ↓
Bitmap Index + Heap Scan
```

became the selected alternative.

---

### 4. A scan change does not guarantee a join change

The `enrollment` access method changed, but the higher-level join method remained:

```text
Hash Join
```

This demonstrates that scan selection and join selection are related through the overall plan cost, but changing one component does not necessarily force every other component of the plan to change.

---

# 13. Important Limitation

This project is an **optimizer behavior experiment**, not a PostgreSQL performance improvement.

The modification:

```c
path->total_cost *= 2.0;
```

artificially biases PostgreSQL against Sequential Scan for relations larger than the chosen threshold.

It does not prove that the resulting execution plan is faster at runtime.

The experiment primarily uses:

```sql
EXPLAIN
```

which reports the optimizer's estimated costs.

Therefore:

```text
Lower / Different Estimated Cost
              ≠
Guaranteed Faster Execution Time
```

A proper performance study would require additional measurements such as:

```sql
EXPLAIN ANALYZE
```

repeated execution, cache control, multiple data distributions, and runtime statistics.

Those measurements are outside the scope of this project.

---

# 14. Reproducing the Experiment

## Step 1 — Prepare PostgreSQL

The experiment was performed using PostgreSQL 15.2 source code.

The full PostgreSQL source is not included in this repository.

Place this repository next to, or separately from, a PostgreSQL 15.2 source tree.

---

## Step 2 — Create the Experimental Database

Create a database of your choice.

For example:

```bash
createdb optimizer_test
```

Run the setup:

```bash
psql -d optimizer_test -f sql/01_setup.sql
```

Create indexes and statistics:

```bash
psql -d optimizer_test -f sql/02_indexes.sql
```

---

## Step 3 — Run the Baseline Query

Before applying the patch:

```bash
psql -d optimizer_test -f sql/03_experiment.sql
```

Inspect the execution plan.

The expected important behavior is:

```text
Seq Scan on enrollment
```

The exact estimated costs may vary depending on PostgreSQL statistics, generated random data, system configuration, and environment.

---

## Step 4 — Apply the Experimental Patch

From the PostgreSQL source directory:

```bash
git apply /path/to/postgresql-query-optimizer/patch/cost_seqscan_penalty.patch
```

Rebuild the modified PostgreSQL server using the build procedure appropriate for the local environment.

---

## Step 5 — Run the Query Again

Run:

```bash
psql -d optimizer_test -f sql/03_experiment.sql
```

Compare the new plan with the baseline.

The original experiment produced:

```text
Seq Scan
```

before the modification and:

```text
Bitmap Heap Scan
    +
Bitmap Index Scan
```

after the modification.

---

# 15. What I Learned

This project gave me practical experience with concepts that were previously mostly theoretical.

### PostgreSQL internals

I learned how query planning is distributed across multiple PostgreSQL source files and functions rather than implemented in one isolated optimizer function.

---

### Cost-based optimization

I observed directly that the optimizer compares candidate plans using estimated costs rather than applying a simple rule such as:

```text
if index exists:
    use index
```

---

### Source-code navigation

The experiment required following PostgreSQL's source-code flow from:

```text
planner
   ↓
path generation
   ↓
cost estimation
```

and identifying an appropriate place to make a controlled experimental modification.

---

### Debugging and experimentation

The first modification did not immediately change the plan.

This required:

```text
Modify
   ↓
Build
   ↓
Run EXPLAIN
   ↓
Inspect result
   ↓
Revise hypothesis
```

rather than assuming the first code change would produce the intended behavior.

---

### Query-plan interpretation

The experiment improved my understanding of:

- Sequential Scan
- Index Scan
- Bitmap Index Scan
- Bitmap Heap Scan
- Hash Join
- Predicate filtering
- Selectivity
- Cost estimation
- PostgreSQL statistics

---

# 16. Project Summary

The main experiment can be summarized as:

```text
Index already exists
        ↓
PostgreSQL chooses Seq Scan
        ↓
Inspect optimizer source
        ↓
Locate cost_seqscan()
        ↓
Observe original cost
        ↓
Modify path->total_cost
        ↓
1916.00 → 3832.00
        ↓
Run EXPLAIN again
        ↓
Bitmap Index Scan
        +
Bitmap Heap Scan
```

The project demonstrates how a small change to a base-relation cost estimate can influence PostgreSQL's cost-based optimizer and alter part of the selected execution plan.

---

## Key Technologies

`PostgreSQL` `C` `SQL` `Query Optimization` `DBMS Internals` `Linux` `EXPLAIN` `Cost Model`
