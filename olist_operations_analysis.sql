CREATE TABLE customers (
    customer_id               TEXT PRIMARY KEY,
    customer_unique_id        TEXT,
    customer_zip_code_prefix  TEXT,
    customer_city             TEXT,
    customer_state            TEXT
);

CREATE TABLE sellers (
    seller_id               TEXT PRIMARY KEY,
    seller_zip_code_prefix  TEXT,
    seller_city             TEXT,
    seller_state            TEXT
);

CREATE TABLE products (
    product_id                  TEXT PRIMARY KEY,
    product_category_name       TEXT,
    product_name_lenght         INT,   -- misspelling is from the source data
    product_description_lenght  INT,
    product_photos_qty          INT,
    product_weight_g            INT,
    product_length_cm           INT,
    product_height_cm           INT,
    product_width_cm            INT
);

CREATE TABLE category_translation (
    product_category_name          TEXT PRIMARY KEY,
    product_category_name_english  TEXT
);

CREATE TABLE orders (
    order_id                       TEXT PRIMARY KEY,
    customer_id                    TEXT REFERENCES customers(customer_id),
    order_status                   TEXT,
    order_purchase_timestamp       TIMESTAMP,
    order_approved_at              TIMESTAMP,
    order_delivered_carrier_date   TIMESTAMP,
    order_delivered_customer_date  TIMESTAMP,
    order_estimated_delivery_date  TIMESTAMP
);

CREATE TABLE order_items (
    order_id             TEXT REFERENCES orders(order_id),
    order_item_id        INT,
    product_id           TEXT REFERENCES products(product_id),
    seller_id            TEXT REFERENCES sellers(seller_id),
    shipping_limit_date  TIMESTAMP,
    price                NUMERIC(10,2),
    freight_value        NUMERIC(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE order_payments (
    order_id              TEXT REFERENCES orders(order_id),
    payment_sequential    INT,
    payment_type          TEXT,
    payment_installments  INT,
    payment_value         NUMERIC(10,2)
);

-- review_id is NOT unique in the source data, so no primary key here
CREATE TABLE order_reviews (
    review_id                TEXT,
    order_id                 TEXT REFERENCES orders(order_id),
    review_score             INT,
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TIMESTAMP,
    review_answer_timestamp  TIMESTAMP
);


-- Row counts per table
SELECT 'customers' AS tbl, COUNT(*) FROM customers
UNION ALL SELECT 'orders',         COUNT(*) FROM orders
UNION ALL SELECT 'order_items',    COUNT(*) FROM order_items
UNION ALL SELECT 'order_reviews',  COUNT(*) FROM order_reviews
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments;

-- Order status breakdown (only 'delivered' orders get delivery analysis)
SELECT order_status, COUNT(*) AS orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- Delivered orders missing a delivery date (should be excluded)
SELECT COUNT(*) AS delivered_but_no_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

-- Orders with more than one review
SELECT COUNT(*) AS orders_with_multiple_reviews
FROM (
    SELECT order_id
    FROM order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
) t;


CREATE OR REPLACE VIEW delivered_orders AS
WITH order_revenue AS (
    SELECT order_id,
           SUM(price)          AS product_revenue,
           SUM(freight_value)  AS freight_revenue,
           COUNT(*)            AS item_count
    FROM order_items
    GROUP BY order_id
),
order_review AS (
    -- average handles the orders that have multiple reviews
    SELECT order_id, AVG(review_score) AS review_score
    FROM order_reviews
    GROUP BY order_id
)
SELECT
    o.order_id,
    c.customer_unique_id,
    c.customer_state,
    o.order_purchase_timestamp,
    DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS order_month,
    r.product_revenue,
    r.freight_revenue,
    r.item_count,
    rv.review_score,
    -- delivery time in days
    EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400
        AS delivery_days,
    -- days late (positive) or early (negative) vs the promised date
    EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_estimated_delivery_date)) / 86400
        AS days_vs_estimate,
    CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
         THEN 1 ELSE 0 END AS is_late
FROM orders o
JOIN customers c        ON c.customer_id = o.customer_id
JOIN order_revenue r    ON r.order_id = o.order_id
LEFT JOIN order_review rv ON rv.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;


-- Q1. Monthly trend: orders, revenue, average order value, late rate
SELECT
    order_month,
    COUNT(*)                                   AS orders,
    ROUND(SUM(product_revenue), 2)             AS revenue,
    ROUND(AVG(product_revenue), 2)             AS avg_order_value,
    ROUND(100.0 * AVG(is_late), 1)             AS late_pct
FROM delivered_orders
GROUP BY order_month
ORDER BY order_month;


-- Q2. THE HEADLINE FINDING: how late deliveries affect review scores
SELECT
    CASE
        WHEN days_vs_estimate <= -7 THEN '1. 7+ days early'
        WHEN days_vs_estimate <=  0 THEN '2. On time / slightly early'
        WHEN days_vs_estimate <=  3 THEN '3. 1-3 days late'
        WHEN days_vs_estimate <=  7 THEN '4. 4-7 days late'
        ELSE                             '5. 8+ days late'
    END                                        AS delivery_bucket,
    COUNT(*)                                   AS orders,
    ROUND(AVG(review_score), 2)                AS avg_review,
    ROUND(100.0 * AVG(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END), 1)
                                               AS pct_negative_reviews
FROM delivered_orders
WHERE review_score IS NOT NULL
GROUP BY delivery_bucket
ORDER BY delivery_bucket;


-- Q3. Where is it worst? Late rate and delivery time by customer state
SELECT
    customer_state,
    COUNT(*)                                   AS orders,
    ROUND(AVG(delivery_days), 1)               AS avg_delivery_days,
    ROUND(100.0 * AVG(is_late), 1)             AS late_pct,
    ROUND(AVG(review_score), 2)                AS avg_review
FROM delivered_orders
GROUP BY customer_state
HAVING COUNT(*) >= 500        
ORDER BY late_pct DESC;


-- Q4. Category performance: revenue, lateness, satisfaction
SELECT
    COALESCE(t.product_category_name_english, 'unknown') AS category,
    COUNT(DISTINCT d.order_id)                 AS orders,
    ROUND(SUM(oi.price), 2)                    AS revenue,
    ROUND(100.0 * AVG(d.is_late), 1)           AS late_pct,
    ROUND(AVG(d.review_score), 2)              AS avg_review
FROM delivered_orders d
JOIN order_items oi              ON oi.order_id = d.order_id
JOIN products p                  ON p.product_id = oi.product_id
LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
GROUP BY category
HAVING COUNT(DISTINCT d.order_id) >= 300
ORDER BY revenue DESC
LIMIT 15;


-- Q5. Seller scorecard: rank sellers by late rate (window functions)
WITH seller_stats AS (
    SELECT
        oi.seller_id,
        s.seller_state,
        COUNT(DISTINCT d.order_id)             AS orders,
        ROUND(SUM(oi.price), 2)                AS revenue,
        ROUND(100.0 * AVG(d.is_late), 1)       AS late_pct,
        ROUND(AVG(d.review_score), 2)          AS avg_review
    FROM delivered_orders d
    JOIN order_items oi ON oi.order_id = d.order_id
    JOIN sellers s      ON s.seller_id = oi.seller_id
    GROUP BY oi.seller_id, s.seller_state
    HAVING COUNT(DISTINCT d.order_id) >= 50
)
SELECT
    *,
    RANK() OVER (ORDER BY late_pct DESC)       AS late_rank,
    ROUND(100.0 * revenue / SUM(revenue) OVER (), 2) AS pct_of_total_revenue
FROM seller_stats
ORDER BY late_rank
LIMIT 20;


-- Q6. Does a bad delivery stop customers from coming back?
-- Compares repeat purchase rate after a customer's FIRST order
WITH ranked AS (
    SELECT
        customer_unique_id,
        is_late,
        ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                           ORDER BY order_purchase_timestamp) AS order_num,
        COUNT(*)    OVER (PARTITION BY customer_unique_id)    AS total_orders
    FROM delivered_orders
)
SELECT
    CASE WHEN is_late = 1 THEN 'First order late' ELSE 'First order on time' END
                                               AS first_order_experience,
    COUNT(*)                                   AS customers,
    ROUND(100.0 * AVG(CASE WHEN total_orders > 1 THEN 1 ELSE 0 END), 2)
                                               AS repeat_purchase_pct
FROM ranked
WHERE order_num = 1
GROUP BY first_order_experience;


-- Q7. Revenue at risk: how much revenue sits in orders that got
-- a negative review after a late delivery
SELECT
    COUNT(*)                                   AS late_orders_with_bad_review,
    ROUND(SUM(product_revenue), 2)             AS revenue_in_those_orders,
    ROUND(100.0 * SUM(product_revenue) /
          (SELECT SUM(product_revenue) FROM delivered_orders), 2)
                                               AS pct_of_total_revenue
FROM delivered_orders
WHERE is_late = 1
  AND review_score <= 2;
