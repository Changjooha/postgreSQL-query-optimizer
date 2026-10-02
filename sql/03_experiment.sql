-- ============================================================
-- Query Optimizer Experiment
-- ============================================================

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
