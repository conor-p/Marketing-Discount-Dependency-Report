
-- taking online_sales table, in a temp table adding tax from tax_amount table and discount from discount_coupon table 
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