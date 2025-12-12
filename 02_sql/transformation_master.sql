
-- starting with online_sales table, in a temp table adding tax from tax_amount table and discount from discount_coupon table 
CREATE TABLE temp AS
SELECT 
    online_sales.*,
    tax_amount.GST,
    discount_coupon.Discount_pct
FROM online_sales
LEFT JOIN tax_amount
ON online_sales.Product_Category = tax_amount.product_category
LEFT JOIN discount_coupon
ON online_sales.Product_Category = discount_coupon.product_category
AND online_sales.Month = discount_coupon.Month;



-- account for categories without any discount coupons throughout the year
UPDATE temp SET Discount_pct = 0 WHERE Discount_pct IS NULL;



-- calculating how much of the discount was actually realised based on whether the coupon was used or not
ALTER TABLE temp ADD COLUMN Realised_Discount_Pct NUMERIC;

UPDATE temp
SET Realised_Discount_Pct =
  CASE
    WHEN Coupon_Status = 'Used' THEN Discount_pct
    ELSE 0
  END;



-- adding "Item_Revenue" that uses the formula ((Quantity * Avg_Price) * (1 - Realized_Discount_Pct) * (1 + GST))
ALTER TABLE temp ADD COLUMN Item_Revenue NUMERIC;

UPDATE temp
SET Item_Revenue =
    ROUND(((Quantity * Avg_Price) * (1 - Realised_Discount_Pct) * (1 + GST)), 2);



-- work out the Customer_Acquisition_Month for each customer and add it as a new column to temp
ALTER TABLE temp ADD COLUMN Customer_Acquisition_Month TEXT;

--- Create index on CustomerID and Transaction_Date, much more performant for large datasets than using UPDATE with subquery alone
CREATE INDEX IF NOT EXISTS idx_customer_date ON temp(CustomerID, Transaction_Date);

BEGIN TRANSACTION;

---- The index will automatically be used here
WITH CustomerFirstMonth AS (
  SELECT 
    CustomerID,
    CASE strftime('%m', MIN(Transaction_Date))
      WHEN '01' THEN 'Jan'
      WHEN '02' THEN 'Feb'
      WHEN '03' THEN 'Mar'
      WHEN '04' THEN 'Apr'
      WHEN '05' THEN 'May'
      WHEN '06' THEN 'Jun'
      WHEN '07' THEN 'Jul'
      WHEN '08' THEN 'Aug'
      WHEN '09' THEN 'Sep'
      WHEN '10' THEN 'Oct'
      WHEN '11' THEN 'Nov'
      WHEN '12' THEN 'Dec'
    END AS First_Month
  FROM temp
  GROUP BY CustomerID
)

UPDATE temp
SET Customer_Acquisition_Month = (
  SELECT First_Month 
  FROM CustomerFirstMonth 
  WHERE CustomerFirstMonth.CustomerID = temp.CustomerID
);

COMMIT;

---- See the query execution plan
EXPLAIN QUERY PLAN
SELECT CustomerID, MIN(Transaction_Date)
FROM temp
GROUP BY CustomerID;



-- adding Customer_First_Purchase column to flag the first purchase made by each customer in this dataset
CREATE INDEX IF NOT EXISTS idx_customer_month_txn 
ON temp(CustomerID, Month, Transaction_ID);

BEGIN TRANSACTION;

ALTER TABLE temp ADD COLUMN Customer_First_Purchase INTEGER DEFAULT 0;

UPDATE temp
SET Customer_First_Purchase = CASE
  WHEN Month = Customer_Acquisition_Month
   AND Transaction_ID = (
     SELECT MIN(t2.Transaction_ID)
     FROM temp t2
     WHERE t2.CustomerID = temp.CustomerID
       AND t2.Month = temp.Customer_Acquisition_Month
   )
  THEN 1
  ELSE 0
END;

---- Verification Check 1: Count by Customer_First_Purchase value
SELECT 
  'Count by First Purchase Flag' as Check_Type,
  Customer_First_Purchase,
  COUNT(*) as row_count
FROM temp
GROUP BY Customer_First_Purchase;

---- Verification Check 2: Show examples of first purchases
SELECT 
  'Sample First Purchases' as Check_Type,
  CustomerID, 
  Transaction_ID, 
  Month, 
  Customer_Acquisition_Month, 
  Customer_First_Purchase
FROM temp
WHERE Customer_First_Purchase = 1
LIMIT 10;

---- Verification Check 3: Check for customers with multiple first purchases (should only be customers that purchased multiple items in their first order)
SELECT 
  'Customers with Multiple First Purchases' as Check_Type,
  CustomerID,
  COUNT(*) as first_purchase_count
FROM temp
WHERE Customer_First_Purchase = 1
GROUP BY CustomerID
HAVING COUNT(*) > 1;

COMMIT;



-- adding Cohort_Discount_Intensity column based on Customer_Acquisition_Month lookup from Discount_Coupon table
BEGIN TRANSACTION;

---- Step 1: Create a temporary lookup table with average discount per month from Discount_Coupon
CREATE TEMP TABLE IF NOT EXISTS CohortDiscountLookup AS
SELECT 
  Month,
  AVG(Discount_pct) as Avg_Discount_pct
FROM Discount_Coupon
GROUP BY Month;

---- Verification Check 1: Show the lookup table we just created
SELECT 
  'Cohort Discount Lookup Table' as Check_Type,
  Month,
  Avg_Discount_pct
FROM CohortDiscountLookup
ORDER BY 
  CASE Month
    WHEN 'Jan' THEN 1 WHEN 'Feb' THEN 2 WHEN 'Mar' THEN 3
    WHEN 'Apr' THEN 4 WHEN 'May' THEN 5 WHEN 'Jun' THEN 6
    WHEN 'Jul' THEN 7 WHEN 'Aug' THEN 8 WHEN 'Sep' THEN 9
    WHEN 'Oct' THEN 10 WHEN 'Nov' THEN 11 WHEN 'Dec' THEN 12
  END;

---- Step 2: Add the column to temp table if it doesn't exist
ALTER TABLE temp ADD COLUMN Cohort_Discount_Intensity REAL;

---- Step 3: Update all rows by looking up discount based on Customer_Acquisition_Month
UPDATE temp
SET Cohort_Discount_Intensity = (
  SELECT cdl.Avg_Discount_pct
  FROM CohortDiscountLookup cdl
  WHERE cdl.Month = temp.Customer_Acquisition_Month
);

---- Verification Check 2: Show discount intensity by acquisition month
SELECT 
  'Cohort Discount Intensity by Acquisition Month' as Check_Type,
  Customer_Acquisition_Month,
  Cohort_Discount_Intensity,
  COUNT(DISTINCT CustomerID) as customer_count,
  COUNT(*) as total_rows
FROM temp
GROUP BY Customer_Acquisition_Month, Cohort_Discount_Intensity
ORDER BY 
  CASE Customer_Acquisition_Month
    WHEN 'Jan' THEN 1 WHEN 'Feb' THEN 2 WHEN 'Mar' THEN 3
    WHEN 'Apr' THEN 4 WHEN 'May' THEN 5 WHEN 'Jun' THEN 6
    WHEN 'Jul' THEN 7 WHEN 'Aug' THEN 8 WHEN 'Sep' THEN 9
    WHEN 'Oct' THEN 10 WHEN 'Nov' THEN 11 WHEN 'Dec' THEN 12
  END;

---- Verification Check 3: Sample rows showing first purchase and other rows
SELECT 
  'Sample Rows' as Check_Type,
  CustomerID,
  Month,
  Customer_Acquisition_Month,
  Customer_First_Purchase,
  Cohort_Discount_Intensity
FROM temp
WHERE CustomerID IN (SELECT DISTINCT CustomerID FROM temp LIMIT 5)
ORDER BY CustomerID, Month;

---- Verification Check 4: Check for NULL values (missing lookups)
SELECT 
  'NULL Check' as Check_Type,
  COUNT(*) as rows_with_null_cohort_discount
FROM temp
WHERE Cohort_Discount_Intensity IS NULL;

---- Verification Check 5: Verify all rows for same customer have same intensity
SELECT 
  'Customer Consistency Check' as Check_Type,
  CustomerID,
  COUNT(DISTINCT Cohort_Discount_Intensity) as unique_intensity_values
FROM temp
GROUP BY CustomerID
HAVING COUNT(DISTINCT Cohort_Discount_Intensity) > 1;

---- Step 4: Clean up the temporary table
DROP TABLE IF EXISTS CohortDiscountLookup;

COMMIT;