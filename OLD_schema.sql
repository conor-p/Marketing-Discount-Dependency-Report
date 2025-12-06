CREATE TABLE customers(
    Customer_id INTEGER,
    Gender TEXT,
    Location TEXT,
    Tenure_months INTEGER
);

CREATE TABLE discount_coupon(
    Month TEXT,
    Product_Category TEXT,
    Coupon_Code TEXT,
    Discount_pct REAL
);

CREATE TABLE tax_amount(
    product_category TEXT PRIMARY KEY,
    gst_pct REAL
);

CREATE TABLE marketing_spend(
    Date TEXT PRIMARY KEY,
    Offline_Spend REAL,
    Online_Spend REAL
);

CREATE TABLE online_sales(
    CustomerID INTEGER,
    Transaction_ID INTEGER,
    Transaction_Date TEXT,
    Product_SKU TEXT,
    Product_Description TEXT,
    Product_Category TEXT,
    Quantity INTEGER,
    Avg_Price REAL,
    Delivery_Charges REAL,
    Coupon_Status TEXT,
    FOREIGN KEY(CustomerID) REFERENCES customers(Customer_id),
    FOREIGN KEY(Product_Category) REFERENCES tax_amount(product_category)
);
