-- ============================================================
-- PostgreSQL Query Optimizer Experiment
-- Database Setup
-- ============================================================


-- ------------------------------------------------------------
-- 1. department
-- 10 rows
-- Small relation used as a comparison case.
-- ------------------------------------------------------------

CREATE TABLE department (
    dept_id INT PRIMARY KEY,
    dept_name VARCHAR(50)
);

INSERT INTO department
SELECT
    i,
    'Dept_' || i
FROM generate_series(1, 10) i;



-- ------------------------------------------------------------
-- 2. course
-- 1,000 rows
-- ------------------------------------------------------------

CREATE TABLE course (
    course_id INT PRIMARY KEY,
    dept_id INT,
    title VARCHAR(100),
    credits INT
);

INSERT INTO course
SELECT
    i,
    floor(random() * 10 + 1)::int,
    'Course_' || i,
    floor(random() * 3 + 1)::int
FROM generate_series(1, 1000) i;



-- ------------------------------------------------------------
-- 3. student
-- 10,000 rows
--
-- entrance_year is distributed from 2015 to 2023.
-- ------------------------------------------------------------

CREATE TABLE student (
    student_id INT PRIMARY KEY,
    dept_id INT,
    name VARCHAR(50),
    entrance_year INT
);

INSERT INTO student
SELECT
    i,
    floor(random() * 10 + 1)::int,
    'Student_' || i,
    2015 + floor(random() * 9)::int
FROM generate_series(1, 10000) i;



-- ------------------------------------------------------------
-- 4. enrollment
-- 100,000 rows
--
-- Grades A, B, C, F are generated with approximately
-- equal probability.
-- ------------------------------------------------------------

CREATE TABLE enrollment (
    enroll_id SERIAL PRIMARY KEY,
    student_id INT,
    course_id INT,
    grade VARCHAR(2)
);

INSERT INTO enrollment (
    student_id,
    course_id,
    grade
)
SELECT
    floor(random() * 10000 + 1)::int,
    floor(random() * 1000 + 1)::int,

    CASE floor(random() * 4)::int
        WHEN 0 THEN 'A'
        WHEN 1 THEN 'B'
        WHEN 2 THEN 'C'
        ELSE 'F'
    END

FROM generate_series(1, 100000) i;
