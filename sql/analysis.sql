-- =====================================================================
-- Vienna Housing Affordability by District — SQL pipeline (SQLite)
-- =====================================================================
-- How to reproduce:
--   1. Create an empty database in DB Browser for SQLite.
--   2. File → Import → Table from CSV file (tick "Column names in first line"):
--        data/prepared/real_estate_prices.csv  → table name: raw_prices
--        data/prepared/district_income.csv     → table name: raw_income
--   3. Run this whole script in the "Execute SQL" tab, then Write Changes.
-- =====================================================================

PRAGMA foreign_keys = ON;   -- SQLite does NOT enforce foreign keys by default


-- ---------------------------------------------------------------------
-- STEP 1: Schema (small star schema)
-- ---------------------------------------------------------------------

-- Reference table: one row per district
CREATE TABLE districts (
    district TEXT PRIMARY KEY
);

-- Fact table: average price per m² by district and year
CREATE TABLE real_estate_prices (
    district      TEXT    NOT NULL,
    year          INTEGER NOT NULL,
    avg_price_sqm REAL    NOT NULL,
    PRIMARY KEY (district, year),                          -- composite key
    FOREIGN KEY (district) REFERENCES districts(district)
);

-- Fact table: average net annual income by district
CREATE TABLE district_income (
    district   TEXT    NOT NULL,
    year       INTEGER NOT NULL,
    net_income REAL    NOT NULL,
    PRIMARY KEY (district, year),
    FOREIGN KEY (district) REFERENCES districts(district)
);


-- ---------------------------------------------------------------------
-- STEP 2: Load + clean
-- ---------------------------------------------------------------------
-- Data-quality issue: the price CSV (exported from Google Sheets) uses a
-- NON-BREAKING SPACE (U+00A0, bytes C2 A0) as thousands separator,
-- e.g. '8 496'. A plain REPLACE(x, ' ', '') does not remove it, and
-- CAST('8 496' AS REAL) silently returns 8.0 instead of 8496.0.
-- Diagnosed with:  SELECT avg_price_sqm, hex(avg_price_sqm) FROM raw_prices;
-- Fix: remove CHAR(160) before casting.

INSERT INTO districts (district)
SELECT DISTINCT district FROM raw_prices;

INSERT INTO real_estate_prices (district, year, avg_price_sqm)
SELECT district,
       CAST(year AS INTEGER),
       CAST(REPLACE(avg_price_sqm, CHAR(160), '') AS REAL)
FROM raw_prices;

INSERT INTO district_income (district, year, net_income)
SELECT district,
       CAST(year AS INTEGER),
       CAST(REPLACE(net_income, CHAR(160), '') AS REAL)
FROM raw_income;

-- Staging tables are no longer needed
DROP TABLE raw_prices;
DROP TABLE raw_income;


-- ---------------------------------------------------------------------
-- STEP 3: Affordability metric as a reusable view
-- ---------------------------------------------------------------------
-- years_to_afford_70sqm = years of net income needed to buy a 70 m² flat
-- Note: income is only available for 2018, so every price year is
-- compared against 2018 income (documented limitation, see README).

CREATE VIEW affordability_view AS
SELECT p.district,
       p.year,
       p.avg_price_sqm,
       i.net_income,
       ROUND((p.avg_price_sqm * 70.0) / i.net_income, 1) AS years_to_afford_70sqm
FROM real_estate_prices p
JOIN district_income i ON i.district = p.district;


-- ---------------------------------------------------------------------
-- STEP 4: Analysis queries
-- ---------------------------------------------------------------------

-- 4a. Least affordable districts in 2024
SELECT district, years_to_afford_70sqm
FROM affordability_view
WHERE year = 2024
ORDER BY years_to_afford_70sqm DESC
LIMIT 5;

-- 4b. Most affordable districts in 2024
SELECT district, years_to_afford_70sqm
FROM affordability_view
WHERE year = 2024
ORDER BY years_to_afford_70sqm ASC
LIMIT 5;

-- 4c. Districts that are less affordable than the city average in 2024
SELECT district, years_to_afford_70sqm
FROM affordability_view
WHERE year = 2024
  AND years_to_afford_70sqm > (
      SELECT AVG(years_to_afford_70sqm)
      FROM affordability_view
      WHERE year = 2024
  )
ORDER BY years_to_afford_70sqm DESC;

-- ---------------------------------------------------------------------
-- STEP 5: Foreign-key test (expected to FAIL — that's the point)
-- ---------------------------------------------------------------------
-- 'Innere Stadtt' does not exist in districts, so SQLite rejects it with:
--   FOREIGN KEY constraint failed
-- INSERT INTO real_estate_prices (district, year, avg_price_sqm)
-- VALUES ('Innere Stadtt', 2025, 9000);
