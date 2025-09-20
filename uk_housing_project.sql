/* ============================================================
   PROJECT: UK Housing Analytics
   DATABASE: uk_housing_project
   AUTHOR: Sundus Ali
   PURPOSE: Build dimension + fact tables for housing analysis
   ============================================================ */

-- ============================================================
-- 1. Create database (if not exists)
-- ============================================================
CREATE DATABASE uk_housing_project;

-- ============================================================
-- 2. Earnings Region Table: Load & Clean
-- ============================================================

-- Drop old tables if they exist
drop table if exists dbo.earnings_region;
drop table if exists dbo.regions_import;

-- Create base table
CREATE TABLE earnings_region(
    Date DATE,
    RegionName NVARCHAR(100),
    Earnings FLOAT
);

-- Add a temporary INT column to clean Median Earnings
Alter TABLE dbo.earnings_region 
ADD Median_Annual_Earnings_int int NULL;

-- Clean Median Annual Earnings → remove £, commas, spaces → convert to INT
UPDATE dbo.earnings_region
SET Median_Annual_Earnings_int=
TRY_CONVERT(INT, REPLACE( REPLACE( REPLACE(LTRIM(RTRIM(Median_Annual_Earnings)), ',', ''),
'£', ''),
' ', '')
);

-- Check for failed conversions
SELECT COUNT(*) AS failed_rows
FROM dbo.earnings_region
WHERE Median_Annual_Earnings IS NOT NULL
  AND Median_Annual_Earnings_int IS NULL;

-- Drop old column and rename cleaned column
ALTER TABLE dbo.earnings_region
DROP COLUMN Median_Annual_Earnings;

EXEC sp_rename
'dbo.earnings_region.Median_Annual_Earnings_int',
'Median_Annual_Earnings',
'COLUMN';

-- ============================================================
-- 3. Rental Median Monthly Table: Clean & Standardize
-- ============================================================

-- Drop unnecessary columns from import
alter table dbo.rental_median_monthly
drop COLUMN throwaway1, throwaway2;

-- Add temporary INT column for Median
alter table dbo.rental_median_monthly
ADD Median_int INT null;

-- Clean Median (remove commas → INT)
UPDATE dbo.rental_median_monthly
SET Median_int = TRY_CONVERT(INT, REPLACE(LTRIM(RTRIM(Median)), ',', ''));

-- Identify rows where conversion failed
SELECT *
FROM dbo.rental_median_monthly
WHERE Median_int IS NULL AND NULLIF(LTRIM(RTRIM(Median)),'') IS NOT NULL;

-- Clean Region & PeriodLabel (trim + null empty)
UPDATE dbo.rental_median_monthly
SET
Region     = NULLIF(LTRIM(RTRIM(Region)), ''),
PeriodLabel= NULLIF(LTRIM(RTRIM(PeriodLabel)), '');

-- Enforce NOT NULL constraints
ALTER table dbo.rental_median_monthly
ALTER COLUMN Median_int INT NOT NULL;

ALTER table dbo.rental_median_monthly
ALTER COLUMN Region NVARCHAR(50) NOT NULL;

ALTER TABLE dbo.rental_median_monthly
ALTER COLUMN PeriodLabel NVARCHAR(50) NOT NUll;

-- Verify no NULLs remain
SELECT *
FROM dbo.rental_median_monthly
WHERE Median_int IS NULL
   OR Region IS NULL
   OR PeriodLabel IS NULL;

-- Delete blank/empty rows
DELETE from dbo.rental_median_monthly
WHERE (Region IS null or LTRIM(RTRIM(Region))= '')
   AND (PeriodLabel IS null or LTRIM(RTRIM(PeriodLabel))= '')
   AND (Median_int is null);

-- Drop old Median column and rename Median_int → Median   
ALTER TABLE dbo.rental_median_monthly DROP COLUMN Median;

EXEC sp_rename 'dbo.rental_median_monthly.Median_int', 'Median', 'COLUMN';

-- ============================================================
-- 4. Region Dimension
-- ============================================================

-- Drop old dimension if exists
IF OBJECT_ID('dbo.dim_region') IS NOT NULL DROP TABLE dbo.dim_region;

-- Create dimension from regions table (England only)
SELECT
  RegionKey = ROW_NUMBER() OVER(ORDER BY r.RegionCode),
  r.RegionCode,
  r.RegionName,
  r.Country
  INTO dbo.dim_region
  FROM dbo.regions r
  WHERE UPPER(r.Country) = 'ENGLAND';

-- Add PK and unique constraints
ALTER TABLE dbo.dim_region ADD CONSTRAINT PK_dim_region PRIMARY KEY (RegionKey);
CREATE UNIQUE INDEX UX_dim_region_code ON dbo.dim_region(RegionCode);
CREATE UNIQUE INDEX UX_dim_region_name ON dbo.dim_region(RegionName);

-- Sanity checks
SELECT COUNT(*) AS NullKeys FROM dbo.dim_region WHERE RegionKey IS NULL;
SELECT RegionCode, COUNT(*) c FROM dbo.dim_region GROUP BY RegionCode HAVING COUNT(*)>1;
SELECT RegionName, COUNT(*) c FROM dbo.dim_region GROUP BY RegionName HAVING COUNT(*)>1;

-- Ensure RegionKey is NOT NULL
ALTER TABLE dbo.dim_region
ALTER COLUMN RegionKey BIGINT NOT NULL;

-- ============================================================
-- 5. Fact: Earnings
-- ============================================================
IF OBJECT_ID('dbo.fact_earnings') IS NOT NULL DROP TABLE dbo.fact_earnings;

SELECT
  e.Year,
  d.RegionKey,
  e.Median_Annual_Earnings
INTO dbo.fact_earnings
FROM dbo.earnings_region e
JOIN dbo.dim_region d
     ON UPPER(LTRIM(RTRIM(e.Region_name))) = UPPER(LTRIM(RTRIM(d.RegionName)));

ALTER TABLE dbo.fact_earnings
ADD CONSTRAINT PK_dact_earnings PRIMARY KEY (Year, RegionKey);

CREATE INDEX IX_fact_earnings_region ON dbo.fact_earnings(RegionKey);

-- ============================================================
-- 6. Fact: Rent
-- ============================================================

IF OBJECT_ID('dbo.fact_rent') IS NOT NULL DROP TABLE dbo.fact_rent;

SELECT
    PeriodEndYear = TRY_CAST(RIGHT(rm.PeriodLabel, 4) AS INT),
    dr.RegionKey,
    rm.Median      AS MedianMonthlyRent
INTO dbo.fact_rent
FROM dbo.rental_median_monthly rm
JOIN dbo.dim_region dr
  ON UPPER(LTRIM(RTRIM(rm.Region))) = UPPER(LTRIM(RTRIM(dr.RegionName)));

-- Check rows with invalid PeriodEndYear
  SELECT rm.*
FROM dbo.rental_median_monthly rm
WHERE TRY_CAST(RIGHT(rm.PeriodLabel, 4) AS INT) IS NULL;

-- Enforce PK + indexes
ALTER TABLE dbo.fact_rent
ALTER COLUMN PeriodEndYear INT NOT NULL;

ALTER TABLE dbo.fact_rent
ADD CONSTRAINT PK_fact_rent PRIMARY KEY (PeriodEndYear, RegionKey);

CREATE INDEX IX_fact_rent_RegionKey     ON dbo.fact_rent(RegionKey);
CREATE INDEX IX_fact_rent_PeriodEndYear ON dbo.fact_rent(PeriodEndYear);

-- Validate data
SELECT TOP 10 * FROM dbo.fact_rent ORDER BY PeriodEndYear DESC, RegionKey;
SELECT PeriodEndYear, COUNT(*) AS RegionsWithRent
FROM dbo.fact_rent
GROUP BY PeriodEndYear
ORDER BY PeriodEndYear DESC;

-- sanity check
SELECT Region, COUNT(*) 
FROM dbo.rental_median_monthly
GROUP BY Region
ORDER BY Region;

-- Find missing regions
SELECT dr.RegionName
FROM dbo.dim_region dr
LEFT JOIN dbo.fact_rent fr
  ON dr.RegionKey = fr.RegionKey
WHERE fr.RegionKey IS NULL;

-- Find mismatched regions
SELECT DISTINCT rm.Region
FROM dbo.rental_median_monthly rm
LEFT JOIN dbo.dim_region dr
  ON UPPER(LTRIM(RTRIM(rm.Region))) = UPPER(LTRIM(RTRIM(dr.RegionName)))
WHERE dr.RegionKey IS NULL
ORDER BY rm.Region;

-- Fix example: map "EAST" → "East of England"
BEGIN TRAN;
UPDATE dbo.rental_median_monthly
SET Region = 'East of England'
WHERE UPPER(LTRIM(RTRIM(Region))) = 'EAST';
COMMIT;

-- Rebuild fact_rent after fix
DELETE FROM dbo.fact_rent;

INSERT INTO dbo.fact_rent (PeriodEndYear, RegionKey, MedianMonthlyRent)
SELECT
    TRY_CAST(RIGHT(rm.PeriodLabel, 4) AS INT)       AS PeriodEndYear,
    dr.RegionKey,
    rm.Median                                       AS MedianMonthlyRent
FROM dbo.rental_median_monthly rm
JOIN dbo.dim_region dr
  ON UPPER(LTRIM(RTRIM(rm.Region))) = UPPER(LTRIM(RTRIM(dr.RegionName)));

-- Final check
  SELECT PeriodEndYear, COUNT(*) AS RegionsWithRent
FROM dbo.fact_rent
GROUP BY PeriodEndYear
ORDER BY PeriodEndYear DESC;

/* ============================================================
   7. House Price Checks (UKHPI) - Cleaning & Validation
   ============================================================ */

-- Preview latest 10 rows to confirm data loaded correctly

SELECT TOP 10 * FROM dbo.ukhpi_average_price ORDER BY [Date] DESC, RegionName;


--Standardize RegionName formatting: trim spaces + uppercase

UPDATE dbo.ukhpi_average_price
SET RegionName = UPPER(LTRIM(RTRIM(RegionName)));

-- SANITY CHECK: Look for missing critical fields
-- If any RegionName, Date, or AveragePrice is NULL/blank → bad data

SELECT * from dbo.ukhpi_average_price
WHERE RegionName is NULL OR RegionName='' OR Date is NULL OR AveragePrice is NULL;

-- SANITY CHECK: Detect duplicates
-- If the same Date + RegionName combination appears more than once,
-- it could lead to wrong aggregations later

SELECT Date, RegionName, COUNT(*) AS dupes
FROM dbo.ukhpi_average_price
GROUP BY Date, RegionName
HAVING COUNT(*)>1;

-- SANITY CHECK: Check RegionNames that don’t align with dim_region
-- Ensures UKHPI data is compatible with our cleaned region dimension

SELECT DISTINCT hp.RegionName
FROM dbo.ukhpi_average_price hp
LEFT JOIN dbo.dim_region dr
  ON hp.RegionName = UPPER(LTRIM(RTRIM(dr.RegionName)))
WHERE dr.RegionKey IS NULL;



/* ============================================================
   8. ONS Lookup & Bridge Table (LAD → Region)
   ============================================================ */

-- SANITY CHECK: Total row count after import
SELECT COUNT(*) AS TotalRows
FROM dbo.ons_lad_to_region;

-- SANITY CHECK: Count NULLs in each column
SELECT 
    SUM(CASE WHEN ObjectId IS NULL THEN 1 ELSE 0 END) AS Null_ObjectId,
    SUM(CASE WHEN LAD23CD IS NULL THEN 1 ELSE 0 END) AS Null_LAD23CD,
    SUM(CASE WHEN LAD23NM IS NULL THEN 1 ELSE 0 END) AS Null_LAD23NM,
    SUM(CASE WHEN RGN23CD IS NULL THEN 1 ELSE 0 END) AS Null_RGN23CD,
    SUM(CASE WHEN RGN23NM IS NULL THEN 1 ELSE 0 END) AS Null_RGN23NM
FROM dbo.ons_lad_to_region;

-- SANITY CHECK: Detect duplicate Local Authority District codes
SELECT LAD23CD, COUNT(*) AS cnt
FROM dbo.ons_lad_to_region
GROUP BY LAD23CD
HAVING COUNT(*)>1;

-- List distinct region names to verify coverage
SELECT DISTINCT RGN23NM
FROM dbo.ons_lad_to_region
ORDER BY RGN23NM;

-- Preview top 10 rows
SELECT TOP 10 *
FROM dbo.ons_lad_to_region;

-- Add performance indexes for joins

-- Create index on Local Authority District Code
CREATE INDEX IX_ons_lad_to_region_LAD23CD
ON dbo.ons_lad_to_region(LAD23CD);

-- Create index on Region Code
CREATE INDEX IX_ons_lad_to_region_RGN23CD
ON dbo.ons_lad_to_region(RGN23CD);

-- SANITY CHECK: Which ONS regions don’t align with dim_region?
-- This highlights mismatched names between datasets
SELECT DISTINCT o.RGN23NM AS ONS_Region, d.RegionName AS DimRegion
FROM dbo.ons_lad_to_region o
LEFT JOIN dbo.dim_region d
    ON UPPER(LTRIM(RTRIM(o.RGN23NM))) = UPPER(LTRIM(RTRIM(d.RegionName)))
WHERE d.RegionKey IS NULL
ORDER BY o.RGN23NM;

-- Rebuild the bridge table (LAD → RegionKey mapping)
IF OBJECT_ID('dbo.bridge_lad_region') IS NOT NULL
    DROP TABLE dbo.bridge_lad_region;

-- Create a clean mapping with RegionKey
SELECT
    b.LAD23CD,                        -- LAD code (e.g., E06000001)
    b.LAD23NM,                        -- LAD name (Hartlepool, etc.)
    d.RegionKey,                      -- surrogate key from dim_region
    d.RegionCode,                     -- E12000001 etc.
    d.RegionName                      -- North East, etc.
INTO dbo.bridge_lad_region
FROM dbo.ons_lad_to_region AS b
JOIN dbo.dim_region       AS d
  ON UPPER(LTRIM(RTRIM(b.RGN23NM))) = UPPER(LTRIM(RTRIM(d.RegionName)));

-- Add constraints and indexes for integrity + performance
ALTER TABLE dbo.bridge_lad_region
  ALTER COLUMN LAD23CD NVARCHAR(10) NOT NULL;

ALTER TABLE dbo.bridge_lad_region
  ADD CONSTRAINT PK_bridge_lad_region PRIMARY KEY (LAD23CD);

CREATE INDEX IX_bridge_lad_region_RegionKey ON dbo.bridge_lad_region(RegionKey);
CREATE UNIQUE INDEX UX_bridge_lad_region_LADName ON dbo.bridge_lad_region(LAD23NM);

-- SANITY CHECKS
-- Row count of bridge table 
SELECT COUNT(*) AS RowsInBridge
FROM dbo.bridge_lad_region;

-- Ensure no NULL RegionKeys (all LADs mapped properly)
SELECT COUNT(*) AS NullRegionKeys
FROM dbo.bridge_lad_region
WHERE RegionKey IS NULL;

-- Count how many LADs exist in each Region
SELECT RegionName, COUNT(*) AS LADs
FROM dbo.bridge_lad_region
GROUP BY RegionName
ORDER BY RegionName;

/* ============================================================
   FACT: House Prices (UKHPI)
   Purpose: Roll up Local Authority District (LAD) house prices
            to ITL1 Regions via bridge_lad_region
   ============================================================ */

--Check Existing table
IF OBJECT_ID('dbo.fact_house_price') IS NOT NULL
DROP TABLE dbo.fact_house_price;

-- Build fact table with aggregation
SELECT
    YearMonth   = DATEFROMPARTS(YEAR(hp.Date), MONTH(hp.Date), 1), -- month-level date
    dr.RegionKey,
    AVG(hp.AveragePrice) AS AveragePrice   -- aggregate LADs up to region level
INTO dbo.fact_house_price
FROM dbo.ukhpi_average_price hp
JOIN dbo.bridge_lad_region br
    ON hp.RegionName = br.LAD23NM
JOIN dbo.dim_region dr
    ON br.RegionKey = dr.RegionKey
GROUP BY DATEFROMPARTS(YEAR(hp.Date), MONTH(hp.Date), 1), dr.RegionKey;

-- SANITY CHECK: Ensure YearMonth was populated
SELECT count(*) AS NullYears
FROM dbo.fact_house_price
where YearMonth IS NULL;

-- Enforce correct data types
-- YearMonth to not null
ALTER TABLE dbo.fact_house_price
ALTER COLUMN YearMonth DATE NOT NULL;

-- Altering datatype of AVeragePrice to accomodate higher prices anytime
ALTER TABLE dbo.fact_house_price
ALTER COLUMN AveragePrice DECIMAL(18,2) NOT NULL;

-- Same alteration with fact_rent and fact_earnings
ALTER TABLE dbo.fact_rent
ALTER COLUMN MedianMonthlyRent DECIMAL(18,2) NOT NULL;

ALTER TABLE dbo.fact_earnings
ALTER COLUMN Median_Annual_Earnings DECIMAL(18,2) NOT NULL;

-- Add constraints and indexes
ALTER TABLE dbo.fact_house_price
ADD CONSTRAINT PK_fact_house_price PRIMARY KEY (YearMonth, RegionKey);

-- Supporting indexes for query performance
CREATE INDEX IX_fact_house_price_RegionKey ON dbo.fact_house_price(RegionKey);
CREATE INDEX IX_fact_house_price_YearMonth ON dbo.fact_house_price(YearMonth);

-- SANITY CHECK: Confirm no duplicate YearMonth + RegionKey
SELECT YearMonth, RegionKey, COUNT(*)
FROM dbo.fact_house_price
GROUP BY YearMonth, RegionKey
HAVING COUNT(*) > 1;

/* ============================================================
   Dimension: Date
   Purpose: Provides full calendar dimension for joining facts
   ============================================================ */

-- Drop existing if re-running
IF OBJECT_ID('dbo.dim_date') IS NOT NULL DROP TABLE dbo.dim_date;

-- Generate dates from 1995 → 2025
WITH DateSequence AS (
    SELECT CAST('1995-01-01' AS DATE) AS DateValue
    UNION ALL
    SELECT DATEADD(DAY, 1, DateValue)
    FROM DateSequence
    WHERE DATEADD(DAY, 1, DateValue) <= '2025-12-31'
)
-- Create dim_date with useful fields
SELECT
    DateValue,
    YEAR(DateValue) AS YEAR,
    MONTH(DateValue) AS MONTH,
    DATENAME(Month, DateValue) AS MonthName,
    YEAR(DateValue) * 100 + MONTH(DateValue) AS YearMonthKey
INTO dbo.dim_date
FROM DateSequence
OPTION (MAXRECURSION 0);

-- Make sure DateValue is NOT NULL
ALTER TABLE dbo.dim_date
ALTER COLUMN DateValue DATE NOT NULL;

-- Enforce PK on DateValue
ALTER TABLE dbo.dim_date
ADD CONSTRAINT PK_dim_date PRIMARY KEY (DateValue);

-- SANITY CHECK: Ensure all fact_house_price rows match dim_date
SELECT f.YearMonth, COUNT(*) AS RowsWithoutMatch
FROM dbo.fact_house_price f
LEFT JOIN dbo.dim_date d
  ON f.YearMonth = d.DateValue
WHERE d.DateValue IS NULL
GROUP BY f.YearMonth;

-- ============================================================
-- Sanity Check: fact_rent ↔ dim_region + dim_date
-- ============================================================

-- 1. Ensure all RegionKeys in fact_rent exist in dim_region
SELECT COUNT(*) AS MissingRegionKeys_fact_rent
FROM dbo.fact_rent fr
LEFT JOIN dbo.dim_region dr
  ON fr.RegionKey = dr.RegionKey
WHERE dr.RegionKey IS NULL;

-- 2. Check distribution per year (are all years covered?)
SELECT PeriodEndYear, COUNT(*) AS Records
FROM dbo.fact_rent
GROUP BY PeriodEndYear
ORDER BY PeriodEndYear;

-- ============================================================
-- Sanity Check: fact_earnings ↔ dim_region
-- ============================================================

-- 1. Ensure all RegionKeys in fact_earnings exist in dim_region
SELECT COUNT(*) AS MissingRegionKeys_fact_earnings
FROM dbo.fact_earnings fe
LEFT JOIN dbo.dim_region dr
  ON fe.RegionKey = dr.RegionKey
WHERE dr.RegionKey IS NULL;

-- 2. Check yearly coverage
SELECT Year, COUNT(*) AS Records
FROM dbo.fact_earnings
GROUP BY Year
ORDER BY Year;

/* ============================================================
   Insight Queries
   Query 1A: Average House Price vs. Average Rent by Year
   Validates : House Prices and rent trends align correctly 
   per year and region
   ============================================================ */

SELECT 
    YEAR(d.DateValue) AS Year,
    dr.RegionName,
    AVG(fhp.AveragePrice) AS AvgHousePrice,
    AVG(fr.MedianMonthlyRent) AS AvgMonthlyRent
FROM dbo.fact_house_price fhp
JOIN dbo.dim_region dr ON fhp.RegionKey = dr.RegionKey
JOIN dbo.dim_date d ON fhp.YearMonth = d.DateValue
LEFT JOIN dbo.fact_rent fr ON dr.RegionKey = fr.RegionKey AND fr.PeriodEndYear = YEAR(d.DateValue)
GROUP BY YEAR(d.DateValue), dr.RegionName
ORDER BY Year, dr.RegionName;

-- QUERY 1B: House Prices + Rents (only overlapping years/regions)
-- Purpose: Restrict to periods where BOTH datasets are available

SELECT 
    YEAR(d.DateValue) AS Year,
    dr.RegionName,
    AVG(fhp.AveragePrice) AS AvgHousePrice,
    AVG(fr.MedianMonthlyRent) AS AvgMonthlyRent
FROM dbo.fact_house_price fhp
JOIN dbo.dim_region dr 
    ON fhp.RegionKey = dr.RegionKey
JOIN dbo.dim_date d 
    ON fhp.YearMonth = d.DateValue
INNER JOIN dbo.fact_rent fr   -- switched from LEFT JOIN → INNER JOIN
    ON dr.RegionKey = fr.RegionKey 
   AND fr.PeriodEndYear = YEAR(d.DateValue)
GROUP BY YEAR(d.DateValue), dr.RegionName
ORDER BY Year, dr.RegionName;


/* ============================================================
   Insight Queries
   QUERY 2 :Year-over-Year growth in house prices by region
   Validates : how much house prices grew year-on-year for each region
   ============================================================ */

   -- Year-over-Year % change in Average House Price
SELECT 
    dr.RegionName,
    YEAR(fhp.YearMonth) AS Year,
    AVG(fhp.AveragePrice) AS AvgHousePrice,
    LAG(AVG(fhp.AveragePrice)) OVER (
        PARTITION BY dr.RegionName ORDER BY YEAR(fhp.YearMonth)
    ) AS PrevYearPrice,
    ( (AVG(fhp.AveragePrice) - 
        LAG(AVG(fhp.AveragePrice)) OVER (
            PARTITION BY dr.RegionName ORDER BY YEAR(fhp.YearMonth)
        )
      ) * 100.0 
    / NULLIF(LAG(AVG(fhp.AveragePrice)) OVER (
        PARTITION BY dr.RegionName ORDER BY YEAR(fhp.YearMonth)
    ), 0) 
    ) AS YoY_PercentChange
FROM dbo.fact_house_price fhp
JOIN dbo.dim_region dr ON fhp.RegionKey = dr.RegionKey
GROUP BY dr.RegionName, YEAR(fhp.YearMonth)
ORDER BY dr.RegionName, Year;

/* ============================================================
   Insight Queries
   Query 3: House Price-to-Rent Ratio by Year and Region
   Purpose: Measure affordability by comparing average house price
            to annualised rent (12 × monthly rent)
   ============================================================ */

   SELECT 
    YEAR(d.DateValue) AS Year,
    dr.RegionName,
    AVG(fhp.AveragePrice) AS AvgHousePrice,
    AVG(fr.MedianMonthlyRent) AS AvgMonthlyRent,
    CASE 
        WHEN AVG(fr.MedianMonthlyRent) > 0 
        THEN AVG(fhp.AveragePrice) / (AVG(fr.MedianMonthlyRent) * 12.0)
        ELSE NULL
    END AS PriceToRentRatio
FROM dbo.fact_house_price fhp
JOIN dbo.dim_region dr 
    ON fhp.RegionKey = dr.RegionKey
JOIN dbo.dim_date d 
    ON fhp.YearMonth = d.DateValue
INNER JOIN dbo.fact_rent fr 
    ON dr.RegionKey = fr.RegionKey
   AND fr.PeriodEndYear = YEAR(d.DateValue)
GROUP BY YEAR(d.DateValue), dr.RegionName
ORDER BY Year, dr.RegionName;

/* ============================================================
   Query 4: House Prices vs. Earnings
   Purpose : Check affordability → how many times annual 
             earnings are needed to buy a house.
   ============================================================ */

SELECT 
    YEAR(d.DateValue) AS Year,
    dr.RegionName,
    AVG(fhp.AveragePrice) AS AvgHousePrice,
    fe.Median_Annual_Earnings,
    CASE 
        WHEN fe.Median_Annual_Earnings > 0 
        THEN AVG(fhp.AveragePrice) / fe.Median_Annual_Earnings
        ELSE NULL
    END AS PriceToEarningsRatio
FROM dbo.fact_house_price fhp
JOIN dbo.dim_region dr 
    ON fhp.RegionKey = dr.RegionKey
JOIN dbo.dim_date d 
    ON fhp.YearMonth = d.DateValue
INNER JOIN dbo.fact_earnings fe
    ON dr.RegionKey = fe.RegionKey
   AND fe.Year = YEAR(d.DateValue)   -- align on same year
GROUP BY YEAR(d.DateValue), dr.RegionName, fe.Median_Annual_Earnings
ORDER BY Year, dr.RegionName;

/* ============================================================
   Query 5: Regional Ranking by House Price Growth
   Purpose : Identify top/bottom performing regions each year
             based on YoY % growth in house prices
   ============================================================ */

WITH HousePriceGrowth AS (
    SELECT 
        dr.RegionName,
        YEAR(d.DateValue) AS Year,
        AVG(fhp.AveragePrice) AS AvgHousePrice,

        -- Previous year's price for the same region
        LAG(AVG(fhp.AveragePrice)) OVER (
            PARTITION BY dr.RegionName ORDER BY YEAR(d.DateValue)
        ) AS PrevYearPrice
    FROM dbo.fact_house_price fhp
    JOIN dbo.dim_region dr ON fhp.RegionKey = dr.RegionKey
    JOIN dbo.dim_date d    ON fhp.YearMonth = d.DateValue
    GROUP BY dr.RegionName, YEAR(d.DateValue)
)

SELECT 
    RegionName,
    Year,
    AvgHousePrice,
    PrevYearPrice,
    ( (AvgHousePrice - PrevYearPrice) * 100.0 / NULLIF(PrevYearPrice,0) ) 
        AS YoY_GrowthPercent,

    -- Ranking: 1 = fastest growth in that year
    RANK() OVER (PARTITION BY Year ORDER BY 
                 (AvgHousePrice - PrevYearPrice) * 1.0 / NULLIF(PrevYearPrice,0) DESC) 
        AS GrowthRank
FROM HousePriceGrowth
WHERE PrevYearPrice IS NOT NULL   -- exclude first year (no prior year to compare)
ORDER BY Year, GrowthRank;


/* ============================================================
   Query 6 (Adapted): Regional Ranking by Rent Level
   Purpose : Since dataset only has 2023 rents, 
             rank regions by average rent in that year
   ============================================================ */

SELECT 
    dr.RegionName,
    fr.PeriodEndYear AS Year,
    AVG(fr.MedianMonthlyRent) AS AvgMonthlyRent,
    RANK() OVER (
        PARTITION BY fr.PeriodEndYear 
        ORDER BY AVG(fr.MedianMonthlyRent) DESC
    ) AS RentRank_Highest,   -- 1 = most expensive region
    RANK() OVER (
        PARTITION BY fr.PeriodEndYear 
        ORDER BY AVG(fr.MedianMonthlyRent) ASC
    ) AS RentRank_Lowest    -- 1 = cheapest region
FROM dbo.fact_rent fr
JOIN dbo.dim_region dr 
    ON fr.RegionKey = dr.RegionKey
GROUP BY dr.RegionName, fr.PeriodEndYear
ORDER BY Year, RentRank_Highest;

/* =========================================================
   Query 7: Correlation Analysis - House Prices vs. Rents
   Purpose : Manually compute Pearson correlation
             between Average House Price and Rent
   ========================================================= */

WITH Stats AS (
    SELECT
        dr.RegionName,
        YEAR(d.DateValue) AS Year,
        AVG(fhp.AveragePrice) AS AvgHousePrice,
        AVG(fr.MedianMonthlyRent) AS AvgMonthlyRent
    FROM dbo.fact_house_price fhp
    JOIN dbo.dim_region dr 
        ON fhp.RegionKey = dr.RegionKey
    JOIN dbo.dim_date d 
        ON fhp.YearMonth = d.DateValue
    INNER JOIN dbo.fact_rent fr 
        ON dr.RegionKey = fr.RegionKey
       AND fr.PeriodEndYear = YEAR(d.DateValue)
    GROUP BY dr.RegionName, YEAR(d.DateValue)
),
RegionStats AS (
    SELECT
        RegionName,
        COUNT(*) AS N,
        AVG(AvgHousePrice) AS MeanPrice,
        AVG(AvgMonthlyRent) AS MeanRent
    FROM Stats
    GROUP BY RegionName
),
Correlation AS (
    SELECT
        s.RegionName,
        SUM( (s.AvgHousePrice - r.MeanPrice) * (s.AvgMonthlyRent - r.MeanRent) ) / NULLIF(r.N - 1,0) AS Covariance,
        SUM( POWER(s.AvgHousePrice - r.MeanPrice, 2) ) / NULLIF(r.N - 1,0) AS VarPrice,
        SUM( POWER(s.AvgMonthlyRent - r.MeanRent, 2) ) / NULLIF(r.N - 1,0) AS VarRent
    FROM Stats s
    JOIN RegionStats r ON s.RegionName = r.RegionName
    GROUP BY s.RegionName, r.N, r.MeanPrice, r.MeanRent
)
SELECT
    RegionName,
    CASE 
        WHEN VarPrice IS NULL OR VarRent IS NULL OR SQRT(VarPrice * VarRent) = 0 
        THEN NULL
        ELSE Covariance / SQRT(VarPrice * VarRent)
    END AS PriceRentCorrelation
FROM Correlation
ORDER BY RegionName;

SELECT 
    dr.RegionName,
    COUNT(DISTINCT YEAR(d.DateValue)) AS OverlappingYears
FROM dbo.fact_house_price fhp
JOIN dbo.dim_region dr 
    ON fhp.RegionKey = dr.RegionKey
JOIN dbo.dim_date d 
    ON fhp.YearMonth = d.DateValue
JOIN dbo.fact_rent fr 
    ON dr.RegionKey = fr.RegionKey
   AND fr.PeriodEndYear = YEAR(d.DateValue)
GROUP BY dr.RegionName
ORDER BY OverlappingYears DESC;

/* ============================================================
   Insight 8: Earnings vs. House Prices
   Metric: Price-to-Income Ratio
   Purpose: Shows affordability → how many years of median income
            are needed to buy an average house.
   ============================================================ */

SELECT 
    YEAR(d.DateValue) AS Year,
    dr.RegionName,
    AVG(fhp.AveragePrice) AS AvgHousePrice,
    AVG(fe.Median_Annual_Earnings) AS AvgEarnings,
    CASE 
        WHEN AVG(fe.Median_Annual_Earnings) > 0 
        THEN AVG(fhp.AveragePrice) / AVG(fe.Median_Annual_Earnings)
        ELSE NULL
    END AS PriceToIncomeRatio
FROM dbo.fact_house_price fhp
JOIN dbo.dim_region dr 
    ON fhp.RegionKey = dr.RegionKey
JOIN dbo.dim_date d 
    ON fhp.YearMonth = d.DateValue
JOIN dbo.fact_earnings fe 
    ON dr.RegionKey = fe.RegionKey
   AND fe.Year = YEAR(d.DateValue)   -- align earnings to house price year
GROUP BY YEAR(d.DateValue), dr.RegionName
ORDER BY Year, dr.RegionName;

/* ============================================================
   Insight Query (National-Level)
   House Price-to-Income Ratio (England as a whole)
   Purpose: Show affordability trend nationally by comparing
            average house prices to average earnings
   ============================================================ */

SELECT 
    YEAR(d.DateValue) AS Year,
    AVG(fhp.AveragePrice) AS National_AvgHousePrice,
    AVG(fe.Median_Annual_Earnings) AS National_AvgEarnings,
    CASE 
        WHEN AVG(fe.Median_Annual_Earnings) > 0 
        THEN AVG(fhp.AveragePrice) / AVG(fe.Median_Annual_Earnings)
        ELSE NULL
    END AS National_PriceToIncomeRatio
FROM dbo.fact_house_price fhp
JOIN dbo.dim_date d 
    ON fhp.YearMonth = d.DateValue
JOIN dbo.fact_earnings fe 
    ON fhp.RegionKey = fe.RegionKey
   AND fe.Year = YEAR(d.DateValue)   -- align year
GROUP BY YEAR(d.DateValue)
ORDER BY Year;

/* ============================================================
   Insight Query 9: Rent Affordability Ratio
   Purpose: Compare annual rent costs vs. annual earnings
            by region and year
   ============================================================ */

SELECT 
    YEAR(d.DateValue) AS Year,
    dr.RegionName,
    AVG(fr.MedianMonthlyRent) AS AvgMonthlyRent,
    AVG(fe.Median_Annual_Earnings) AS AvgEarnings,
    CASE 
        WHEN AVG(fe.Median_Annual_Earnings) > 0 
        THEN (AVG(fr.MedianMonthlyRent) * 12.0) / AVG(fe.Median_Annual_Earnings)
        ELSE NULL
    END AS RentToIncomeRatio
FROM dbo.fact_rent fr
JOIN dbo.dim_region dr 
    ON fr.RegionKey = dr.RegionKey
JOIN dbo.fact_earnings fe 
    ON fr.RegionKey = fe.RegionKey
   AND fe.Year = fr.PeriodEndYear   -- align rent year with earnings year
JOIN dbo.dim_date d 
    ON fr.PeriodEndYear = YEAR(d.DateValue)
GROUP BY YEAR(d.DateValue), dr.RegionName
ORDER BY Year, dr.RegionName;

/* ============================================================
   Insight Query 9 (Adapted): Rent Affordability Ratio
   Purpose: Compare annual rent vs. annual earnings by region
            Note: 2023 rents matched with 2024 earnings (project limitation)
   ============================================================ */

SELECT 
    dr.RegionName,
    AVG(fr.MedianMonthlyRent) AS AvgMonthlyRent_2023,
    AVG(fe.Median_Annual_Earnings) AS AvgEarnings_2024,
    CASE 
        WHEN AVG(fe.Median_Annual_Earnings) > 0 
        THEN (AVG(fr.MedianMonthlyRent) * 12.0) / AVG(fe.Median_Annual_Earnings)
        ELSE NULL
    END AS RentToIncomeRatio
FROM dbo.fact_rent fr
JOIN dbo.dim_region dr 
    ON fr.RegionKey = dr.RegionKey
JOIN dbo.fact_earnings fe 
    ON fr.RegionKey = fe.RegionKey   -- region-based join, no year restriction
GROUP BY dr.RegionName
ORDER BY RentToIncomeRatio DESC;

/* ============================================================
   Insight Query 9 (National): Rent Affordability Ratio
   Purpose: Compare national average rent burden vs. earnings
   Note: Uses 2023 rents and 2024 earnings due to dataset overlap
   ============================================================ */

SELECT 
    AVG(fr.MedianMonthlyRent) AS National_AvgMonthlyRent_2023,
    AVG(fe.Median_Annual_Earnings) AS National_AvgEarnings_2024,
    CASE 
        WHEN AVG(fe.Median_Annual_Earnings) > 0 
        THEN (AVG(fr.MedianMonthlyRent) * 12.0) / AVG(fe.Median_Annual_Earnings)
        ELSE NULL
    END AS National_RentToIncomeRatio
FROM dbo.fact_rent fr
JOIN dbo.fact_earnings fe 
    ON fr.RegionKey = fe.RegionKey;   -- region alignment, no year restriction



/* ==========================================================
   Query 10 (Final with Ratios): National Trend Comparison
   Purpose:
   - Combine national averages of house prices, earnings, and rents
   - Add Price-to-Income and Rent-to-Income ratios for affordability
   ========================================================== */

WITH National_House_Earnings AS (
    -- Covers 2024 (House Prices + Earnings)
    SELECT 
        YEAR(d.DateValue) AS Year,
        AVG(fhp.AveragePrice) AS National_AvgHousePrice,
        AVG(fe.Median_Annual_Earnings) AS National_AvgEarnings,
        NULL AS National_AvgMonthlyRent
    FROM dbo.fact_house_price fhp
    JOIN dbo.dim_date d 
        ON fhp.YearMonth = d.DateValue
    JOIN dbo.fact_earnings fe 
        ON fhp.RegionKey = fe.RegionKey
       AND fe.Year = YEAR(d.DateValue)
    GROUP BY YEAR(d.DateValue)
),
National_Rent AS (
    -- Covers 2023 (Rents only)
    SELECT 
        fr.PeriodEndYear AS Year,
        NULL AS National_AvgHousePrice,
        NULL AS National_AvgEarnings,
        AVG(fr.MedianMonthlyRent) AS National_AvgMonthlyRent
    FROM dbo.fact_rent fr
    JOIN dbo.dim_region dr 
        ON fr.RegionKey = dr.RegionKey
    GROUP BY fr.PeriodEndYear
)
SELECT 
    t.Year,
    t.National_AvgHousePrice,
    t.National_AvgEarnings,
    t.National_AvgMonthlyRent,
    -- Ratio: House Price ÷ Earnings (2024 only)
    CASE 
        WHEN t.National_AvgEarnings > 0 
             AND t.National_AvgHousePrice IS NOT NULL
        THEN t.National_AvgHousePrice / t.National_AvgEarnings
        ELSE NULL
    END AS PriceToIncomeRatio,
    -- Ratio: Rent ÷ Earnings (2023 only)
    CASE 
        WHEN t.National_AvgEarnings > 0 
             AND t.National_AvgMonthlyRent IS NOT NULL
        THEN (t.National_AvgMonthlyRent * 12.0) / t.National_AvgEarnings
        ELSE NULL
    END AS RentToIncomeRatio
FROM (
    SELECT * FROM National_House_Earnings
    UNION ALL
    SELECT * FROM National_Rent
) t
WHERE t.Year IN (2023, 2024)
ORDER BY t.Year;


