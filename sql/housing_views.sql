/* ============================================================
   VIEWS SCRIPT
   PROJECT: UK Housing Analytics
   AUTHOR: Sundus Ali
   ============================================================ */


/* ============================================================
   VIEWS : vw_fact_house_prices
   PURPOSE: 
     - Provide a clean, consistent view of house prices fact table
   ============================================================ */

CREATE VIEW dbo.vw_fact_house_prices AS
SELECT 
    YearMonth,
    RegionKey,
    AveragePrice
FROM dbo.fact_house_price;
GO

/* ============================================================
   VIEW: vw_fact_earnings
   PURPOSE: Clean wrapper on fact_earnings for Power BI
   ============================================================ */
CREATE VIEW dbo.vw_fact_earnings AS
SELECT 
    Year,
    RegionKey,
    Median_Annual_Earnings
FROM dbo.fact_earnings;
GO

/* ============================================================
   VIEW: vw_fact_rent
   PURPOSE: Clean wrapper on fact_rent for Power BI
   ============================================================ */
CREATE VIEW dbo.vw_fact_rent AS
SELECT 
    PeriodEndYear, 
    RegionKey, 
    MedianMonthlyRent 
FROM dbo.fact_rent;
GO

/* ============================================================
   VIEW: vw_dim_region
   PURPOSE: Clean wrapper on dim_region for Power BI
   ============================================================ */
CREATE VIEW dbo.vw_dim_region AS
SELECT 
    RegionKey,
    RegionCode,
    RegionName,
    Country
FROM dbo.dim_region;
GO


/* ============================================================
   VIEW: vw_dim_date
   PURPOSE: Clean wrapper on dim_date for Power BI
   ============================================================ */
CREATE VIEW dbo.vw_dim_date AS
SELECT 
    DateValue,
    YEAR,
    MONTH,
    MonthName,
    YearMonthKey
FROM dbo.dim_date;
GO


/* ============================================================
   VIEW: vw_bridge_lad_region
   PURPOSE: Bridge mapping between LAD and Region
   ============================================================ */
CREATE VIEW dbo.vw_bridge_lad_region AS
SELECT 
    LAD23CD,
    LAD23NM,
    RegionKey,
    RegionCode,
    RegionName
FROM dbo.bridge_lad_region;
GO

/* ============================================================
   VIEW: vw_national_avg_house_prices
   PURPOSE: National average house prices by YearMonth
   ============================================================ */
CREATE VIEW dbo.vw_national_avg_house_prices AS
SELECT 
    fhp.YearMonth,
    AVG(fhp.AveragePrice) AS National_AvgPrice
FROM dbo.vw_fact_house_prices fhp
GROUP BY fhp.YearMonth;
GO

/* ============================================================
   VIEW: vw_national_avg_house_rent
   PURPOSE: National average monthly rent by year
   ============================================================ */
CREATE VIEW dbo.vw_national_avg_house_rent AS
SELECT 
    fr.PeriodEndYear,
    AVG(fr.MedianMonthlyRent) AS National_AvgMonthlyRent
FROM dbo.vw_fact_rent fr
GROUP BY fr.PeriodEndYear;
GO

/* ============================================================
   VIEW: vw_national_avg_earnings
   PURPOSE: National average annual earnings by year
   ============================================================ */
CREATE VIEW dbo.vw_national_avg_earnings AS
SELECT
     fe.Year,
     AVG(fe.Median_Annual_Earnings) AS National_AvgAnnualEarnings
FROM dbo.vw_fact_earnings fe
GROUP BY fe.Year;
GO

/* ============================================================
   VIEW: vw_region_avg_house_prices
   PURPOSE: Regional average house prices by YearMonth
   ============================================================ */
CREATE VIEW dbo.vw_region_avg_house_prices AS
SELECT 
    fhp.YearMonth,
    r.RegionName,
    AVG(fhp.AveragePrice) AS Region_AvgPrice
FROM dbo.vw_fact_house_prices fhp
JOIN dbo.vw_dim_region r 
    ON fhp.RegionKey = r.RegionKey
GROUP BY fhp.YearMonth, r.RegionName;
GO

/* ============================================================
   VIEW: vw_region_avg_house_rent
   PURPOSE: Regional average monthly rent by year
   ============================================================ */
CREATE VIEW dbo.vw_region_avg_house_rent AS
SELECT 
    fr.PeriodEndYear,
    r.RegionName,
    AVG(fr.MedianMonthlyRent) AS Region_AvgMonthlyRent
FROM dbo.vw_fact_rent fr
JOIN dbo.vw_dim_region r 
    ON fr.RegionKey = r.RegionKey
GROUP BY fr.PeriodEndYear, r.RegionName;
GO

/* ============================================================
   VIEW: vw_region_avg_earnings
   PURPOSE: Regional average annual earnings by year
   ============================================================ */
CREATE VIEW dbo.vw_region_avg_earnings AS
SELECT 
    fe.Year,
    r.RegionName,
    AVG(fe.Median_Annual_Earnings) AS Region_AvgAnnualEarnings
FROM dbo.vw_fact_earnings fe
JOIN dbo.vw_dim_region r 
    ON fe.RegionKey = r.RegionKey
GROUP BY fe.Year, r.RegionName;
GO

/* ============================================================
   VIEW: vw_lad_avg_house_prices
   PURPOSE: LAD-level average house prices by YearMonth
   ============================================================ */
CREATE VIEW dbo.vw_lad_avg_house_prices AS
SELECT 
    fhp.YearMonth,
    b.LAD23NM AS LADName,
    AVG(fhp.AveragePrice) AS LAD_AvgPrice
FROM dbo.vw_fact_house_prices fhp
JOIN dbo.vw_bridge_lad_region b 
    ON fhp.RegionKey = b.RegionKey
GROUP BY fhp.YearMonth, b.LAD23NM;
GO

/* ============================================================
   VIEW: vw_lad_avg_house_rent
   PURPOSE: LAD-level average monthly rent by year
   ============================================================ */
CREATE VIEW dbo.vw_lad_avg_house_rent AS
SELECT 
    fr.PeriodEndYear,
    b.LAD23NM AS LADName,
    AVG(fr.MedianMonthlyRent) AS LAD_AvgMonthlyRent
FROM dbo.vw_fact_rent fr
JOIN dbo.vw_bridge_lad_region b 
    ON fr.RegionKey = b.RegionKey
GROUP BY fr.PeriodEndYear, b.LAD23NM;
GO

/* ============================================================
   VIEW: vw_lad_avg_earnings
   PURPOSE: LAD-level average annual earnings by year
   ============================================================ */
CREATE VIEW dbo.vw_lad_avg_earnings AS
SELECT 
    fe.Year,
    b.LAD23NM AS LADName,
    AVG(fe.Median_Annual_Earnings) AS LAD_AvgAnnualEarnings
FROM dbo.vw_fact_earnings fe
JOIN dbo.vw_bridge_lad_region b 
    ON fe.RegionKey = b.RegionKey
GROUP BY fe.Year, b.LAD23NM;
GO

/* ============================================================
   VIEW: vw_lad_price_ratios
   PURPOSE: LAD-level ratios of house prices vs Regional and National averages
   ============================================================ */
CREATE VIEW dbo.vw_lad_price_ratios AS
SELECT 
    lad.YearMonth,
    lad.LADName,
    lad.LAD_AvgPrice,

    r.Region_AvgPrice,
    n.National_AvgPrice,

    -- Ratios
    lad.LAD_AvgPrice / r.Region_AvgPrice   AS LAD_vs_Region_Ratio,
    lad.LAD_AvgPrice / n.National_AvgPrice AS LAD_vs_National_Ratio

FROM dbo.vw_lad_avg_house_prices lad
JOIN dbo.vw_region_avg_house_prices r
    ON lad.YearMonth = r.YearMonth
   AND lad.LADName IN (
       SELECT LAD23NM FROM dbo.vw_bridge_lad_region b
       WHERE b.RegionName = r.RegionName
   )
JOIN dbo.vw_national_avg_house_prices n
    ON lad.YearMonth = n.YearMonth;
GO

/* ============================================================
   VIEW: vw_national_price_income_ratio
   PURPOSE: National-level affordability = House Price ÷ Annual Earnings
   ============================================================ */
CREATE VIEW dbo.vw_national_price_income_ratio AS
SELECT 
    hp.YearMonth,
    hp.National_AvgPrice,
    e.National_AvgAnnualEarnings,
    hp.National_AvgPrice / e.National_AvgAnnualEarnings AS Price_Income_Ratio
FROM dbo.vw_national_avg_house_prices hp
JOIN dbo.vw_national_avg_earnings e
    ON YEAR(hp.YearMonth) = e.Year;
GO

/* ============================================================
   VIEW: vw_national_price_income_ratio
   PURPOSE: National-level affordability = House Price ÷ Annual Earnings
   ============================================================ */
CREATE VIEW dbo.vw_national_price_income_ratio AS
SELECT 
    hp.YearMonth,
    hp.National_AvgPrice,
    e.National_AvgAnnualEarnings,
    hp.National_AvgPrice / e.National_AvgAnnualEarnings AS Price_Income_Ratio
FROM dbo.vw_national_avg_house_prices hp
JOIN dbo.vw_national_avg_earnings e
    ON YEAR(hp.YearMonth) = e.Year;
GO

/* ============================================================
   VIEW: vw_region_price_income_ratio
   PURPOSE: Regional-level affordability = House Price ÷ Annual Earnings
   ============================================================ */
CREATE VIEW dbo.vw_region_price_income_ratio AS
SELECT 
    hp.YearMonth,
    hp.RegionName,
    hp.Region_AvgPrice,
    e.Region_AvgAnnualEarnings,
    hp.Region_AvgPrice / e.Region_AvgAnnualEarnings AS Price_Income_Ratio
FROM dbo.vw_region_avg_house_prices hp
JOIN dbo.vw_region_avg_earnings e
    ON YEAR(hp.YearMonth) = e.Year
   AND hp.RegionName = e.RegionName;
GO

/* ============================================================
   VIEW: vw_lad_price_income_ratio
   PURPOSE: LAD-level affordability = House Price ÷ Annual Earnings
   ============================================================ */
CREATE VIEW dbo.vw_lad_price_income_ratio AS
SELECT 
    hp.YearMonth,
    hp.LADName,
    hp.LAD_AvgPrice,
    e.LAD_AvgAnnualEarnings,
    hp.LAD_AvgPrice / e.LAD_AvgAnnualEarnings AS Price_Income_Ratio
FROM dbo.vw_lad_avg_house_prices hp
JOIN dbo.vw_lad_avg_earnings e
    ON YEAR(hp.YearMonth) = e.Year
   AND hp.LADName = e.LADName;
GO

/* ============================================================
   VIEW: vw_national_rent_income_ratio
   PURPOSE: National-level affordability = (Monthly Rent × 12) ÷ Annual Earnings
   ============================================================ */
CREATE VIEW dbo.vw_national_rent_income_ratio AS
SELECT 
    r.PeriodEndYear,
    r.National_AvgMonthlyRent,
    e.National_AvgAnnualEarnings,
    (r.National_AvgMonthlyRent * 12.0) / e.National_AvgAnnualEarnings AS Rent_Income_Ratio
FROM dbo.vw_national_avg_house_rent r
JOIN dbo.vw_national_avg_earnings e
    ON r.PeriodEndYear = e.Year;
GO

/* ============================================================
   VIEW: vw_region_rent_income_ratio
   PURPOSE: Regional-level affordability = (Monthly Rent × 12) ÷ Annual Earnings
   ============================================================ */
CREATE VIEW dbo.vw_region_rent_income_ratio AS
SELECT 
    r.PeriodEndYear,
    r.RegionName,
    r.Region_AvgMonthlyRent,
    e.Region_AvgAnnualEarnings,
    (r.Region_AvgMonthlyRent * 12.0) / e.Region_AvgAnnualEarnings AS Rent_Income_Ratio
FROM dbo.vw_region_avg_house_rent r
JOIN dbo.vw_region_avg_earnings e
    ON r.PeriodEndYear = e.Year
   AND r.RegionName = e.RegionName;
GO

/* ============================================================
   VIEW: vw_lad_rent_income_ratio
   PURPOSE: LAD-level affordability = (Monthly Rent × 12) ÷ Annual Earnings
   ============================================================ */
CREATE VIEW dbo.vw_lad_rent_income_ratio AS
SELECT 
    r.PeriodEndYear,
    r.LADName,
    r.LAD_AvgMonthlyRent,
    e.LAD_AvgAnnualEarnings,
    (r.LAD_AvgMonthlyRent * 12.0) / e.LAD_AvgAnnualEarnings AS Rent_Income_Ratio
FROM dbo.vw_lad_avg_house_rent r
JOIN dbo.vw_lad_avg_earnings e
    ON r.PeriodEndYear = e.Year
   AND r.LADName = e.LADName;
GO

/* ============================================================
   VIEW: vw_housing_affordability_index
   PURPOSE: National-level affordability index combining
            - Price-to-Income Ratio
            - Rent-to-Income Ratio
   ============================================================ */
CREATE VIEW dbo.vw_housing_affordability_index AS
SELECT 
    hp.YearMonth,
    hp.National_AvgPrice,
    e.National_AvgAnnualEarnings,
    hp.National_AvgPrice / e.National_AvgAnnualEarnings AS Price_Income_Ratio,
    r.National_AvgMonthlyRent,
    (r.National_AvgMonthlyRent * 12.0) / e.National_AvgAnnualEarnings AS Rent_Income_Ratio
FROM dbo.vw_national_avg_house_prices hp
JOIN dbo.vw_national_avg_earnings e
    ON YEAR(hp.YearMonth) = e.Year
JOIN dbo.vw_national_avg_house_rent r
    ON r.PeriodEndYear = e.Year;
GO
