-- ============================================================
-- Index Creation
-- ============================================================

CREATE INDEX idx_student_year
ON student(entrance_year);

CREATE INDEX idx_department_name
ON department(dept_name);

CREATE INDEX idx_enrollment_grade
ON enrollment(grade);


-- Update PostgreSQL statistics so that the optimizer
-- can estimate relation sizes and predicate selectivity.

ANALYZE;
