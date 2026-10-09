-- Nimbus Retail Partners onboarding project
-- database: nimbus_retail (postgres 17)


-- ---------- phase 1: schema ----------

CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100) UNIQUE,
    city VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(customer_id),
    amount DECIMAL(10, 2),
    status VARCHAR(20),
    order_date DATE
);

CREATE TABLE order_items (
    item_id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(order_id),
    product_id INT,
    quantity INT,
    price DECIMAL(10, 2)
);

CREATE TABLE messy_customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    updated_at TIMESTAMP
);

CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    manager_id INT REFERENCES employees(employee_id)
);

-- csvs imported in this order: customers, orders, order_items, messy_customers, employees

-- row count check after import
SELECT 'customers' AS tbl, COUNT(*) FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'messy_customers', COUNT(*) FROM messy_customers
UNION ALL SELECT 'employees', COUNT(*) FROM employees;


-- ---------- phase 2: beginner ----------

-- task 1: customers in lagos, sorted by name
SELECT customer_id, name, email, city
FROM customers
WHERE city = 'Lagos'
ORDER BY name;


-- task 2: order count and revenue per status
SELECT status,
       COUNT(*) AS total_orders,
       SUM(amount) AS total_revenue
FROM orders
GROUP BY status
ORDER BY total_revenue DESC;


-- task 3: ten biggest orders with customer name
SELECT o.order_id, c.name, c.city, o.amount, o.status, o.order_date
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.amount IS NOT NULL
ORDER BY o.amount DESC, o.order_id
LIMIT 10;


-- task 4: customers with no orders
SELECT c.customer_id, c.name, c.email, c.city
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL
ORDER BY c.name;

-- same thing with not exists, to double check the count
SELECT c.customer_id, c.name, c.email, c.city
FROM customers c
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id
)
ORDER BY c.name;


-- task 5: revenue tiers
-- looked at min / avg / max first to pick the cutoffs
SELECT MIN(amount), ROUND(AVG(amount), 2) AS avg_amount, MAX(amount)
FROM orders;

SELECT o.order_id, c.name, o.amount, o.status,
       CASE
           WHEN o.amount >= 350 THEN 'High'
           WHEN o.amount >= 200 THEN 'Medium'
           ELSE 'Low'
       END AS revenue_tier
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
ORDER BY o.amount DESC;


-- ---------- phase 2: intermediate ----------

-- task 6: monthly revenue and month over month change
WITH monthly AS (
    SELECT DATE_TRUNC('month', order_date)::date AS month,
           SUM(amount) AS revenue
    FROM orders
    GROUP BY 1
),
with_prev AS (
    SELECT month,
           revenue,
           LAG(revenue) OVER (ORDER BY month) AS prev_revenue
    FROM monthly
)
SELECT month,
       revenue,
       prev_revenue,
       ROUND((revenue - prev_revenue) * 100.0 / NULLIF(prev_revenue, 0), 2) AS pct_change
FROM with_prev
ORDER BY month;


-- task 7: top 3 orders per customer
WITH ranked AS (
    SELECT customer_id,
           order_id,
           amount,
           RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS amount_rank
    FROM orders
    WHERE amount IS NOT NULL
)
SELECT customer_id, order_id, amount, amount_rank
FROM ranked
WHERE amount_rank <= 3
ORDER BY customer_id, amount_rank;


-- task 8: dedupe messy_customers, keep latest row per email
WITH ranked AS (
    SELECT id, name, email, updated_at,
           ROW_NUMBER() OVER (
               PARTITION BY LOWER(TRIM(email))
               ORDER BY updated_at DESC
           ) AS rn
    FROM messy_customers
)
SELECT id, name, email, updated_at
FROM ranked
WHERE rn = 1
ORDER BY email;


-- task 9: fan-out trap
-- real total straight from orders
SELECT SUM(amount) AS real_total FROM orders;

-- wrong: orders joined to order_items repeats each order once per item
SELECT SUM(o.amount) AS inflated_total
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id;

-- wrong, per customer
SELECT c.customer_id, c.name, SUM(o.amount) AS inflated_revenue
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY c.customer_id, c.name
ORDER BY c.customer_id;


-- real total:      8680.44
-- inflated total: 17053.43

-- fix: collapse order_items to one row per order before joining
WITH item_totals AS (
    SELECT order_id,
           SUM(quantity) AS units,
           SUM(quantity * price) AS items_value
    FROM order_items
    GROUP BY order_id
)
SELECT c.customer_id, c.name,
       SUM(o.amount) AS revenue,
       SUM(it.units) AS units
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
LEFT JOIN item_totals it ON it.order_id = o.order_id
GROUP BY c.customer_id, c.name
ORDER BY c.customer_id;

-- total from the fixed version, should match real_total
WITH item_totals AS (
    SELECT order_id, SUM(quantity) AS units
    FROM order_items
    GROUP BY order_id
)
SELECT SUM(o.amount) AS corrected_total
FROM orders o
LEFT JOIN item_totals it ON it.order_id = o.order_id;


-- task 10: sales per city plus grand total
SELECT CASE WHEN GROUPING(c.city) = 1 THEN 'Grand Total' ELSE c.city END AS city,
       SUM(o.amount) AS total_amount
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
GROUP BY ROLLUP (c.city)
ORDER BY GROUPING(c.city), c.city;


-- ---------- phase 3: performance ----------
-- the project tables are too small for postgres to bother with indexes,
-- so tasks 11 to 13 run on bigger copies built with generate_series

CREATE TABLE perf_orders AS
SELECT g AS order_id,
       (random() * 4999 + 1)::int AS customer_id,
       ROUND((random() * 500)::numeric, 2) AS amount,
       DATE '2026-01-01' + (random() * 270)::int AS order_date
FROM generate_series(1, 200000) g;

CREATE TABLE perf_order_items AS
SELECT g AS item_id,
       (random() * 199999 + 1)::int AS order_id,
       (random() * 49 + 1)::int AS product_id,
       (random() * 4 + 1)::int AS quantity,
       ROUND((random() * 100)::numeric, 2) AS price
FROM generate_series(1, 600000) g;

CREATE TABLE perf_customers AS
SELECT g AS customer_id,
       'User ' || g AS name,
       'user' || g || '@example.com' AS email
FROM generate_series(1, 200000) g;

ANALYZE perf_orders;
ANALYZE perf_order_items;
ANALYZE perf_customers;


-- task 11: profiling the slow join (no indexes on any of these)
EXPLAIN ANALYZE
SELECT p.order_id, p.customer_id, p.amount, i.product_id, i.quantity
FROM perf_orders p
JOIN perf_order_items i ON i.order_id = p.order_id
WHERE p.customer_id = 42;

-- notes from the plan:
-- join method: Parallel Hash Join (under a Gather node, 2 workers)
-- most expensive node: Parallel Seq Scan on perf_orders (about 102 ms)
-- execution time: 289.8 ms


-- task 12: add indexes and run the same query again
CREATE INDEX idx_perf_orders_customer ON perf_orders (customer_id);
CREATE INDEX idx_perf_items_order ON perf_order_items (order_id);
ANALYZE perf_orders;
ANALYZE perf_order_items;

EXPLAIN ANALYZE
SELECT p.order_id, p.customer_id, p.amount, i.product_id, i.quantity
FROM perf_orders p
JOIN perf_order_items i ON i.order_id = p.order_id
WHERE p.customer_id = 42;

-- execution time before: 289.8 ms
-- execution time after:  2.9 ms


-- task 13: lower(email) and the index
CREATE INDEX idx_perf_customers_email ON perf_customers (email);
ANALYZE perf_customers;

-- plain index is used for an exact match
EXPLAIN ANALYZE
SELECT * FROM perf_customers WHERE email = 'user1@example.com';

-- wrapping the column in lower() hides it from the plain index, seq scan
EXPLAIN ANALYZE
SELECT * FROM perf_customers WHERE LOWER(email) = 'user1@example.com';

-- expression index built on lower(email)
CREATE INDEX idx_perf_customers_lower_email ON perf_customers (LOWER(email));
ANALYZE perf_customers;

EXPLAIN ANALYZE
SELECT * FROM perf_customers WHERE LOWER(email) = 'user1@example.com';


-- task 14: org chart with a recursive cte
WITH RECURSIVE org AS (
    SELECT employee_id, name, manager_id, 1 AS level
    FROM employees
    WHERE manager_id IS NULL

    UNION ALL

    SELECT e.employee_id, e.name, e.manager_id, org.level + 1
    FROM employees e
    JOIN org ON e.manager_id = org.employee_id
)
SELECT org.employee_id,
       org.name,
       m.name AS manager,
       org.level
FROM org
LEFT JOIN employees m ON m.employee_id = org.manager_id
ORDER BY org.level, org.employee_id;


-- task 15: concurrency, two query tool tabs
-- run each block in the tab named, in the order shown

-- [session A]
BEGIN;
SELECT amount FROM orders WHERE order_id = 1;

-- [session B]
UPDATE orders SET amount = amount + 100 WHERE order_id = 1;
COMMIT;

-- [session A] same select again, the value has changed inside one transaction
SELECT amount FROM orders WHERE order_id = 1;
ROLLBACK;

-- now the same test with repeatable read

-- [session A]
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT amount FROM orders WHERE order_id = 1;

-- [session B]
UPDATE orders SET amount = amount + 100 WHERE order_id = 1;
COMMIT;

-- [session A] value is the same as the first read this time
SELECT amount FROM orders WHERE order_id = 1;
ROLLBACK;

-- [session A] after the rollback it shows the new value
SELECT amount FROM orders WHERE order_id = 1;

-- put the order back how it was (two +100 updates ran)
UPDATE orders SET amount = amount - 200 WHERE order_id = 1;


-- ---------- phase 4: normalization ----------

-- task 16b: 3NF tables for the flat legacy export
CREATE SCHEMA nimbus_3nf;

CREATE TABLE nimbus_3nf.customers (
    customer_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    address VARCHAR(255) NOT NULL
);

CREATE TABLE nimbus_3nf.categories (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE nimbus_3nf.products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    category_id INT NOT NULL REFERENCES nimbus_3nf.categories (category_id),
    list_price DECIMAL(10, 2) NOT NULL CHECK (list_price >= 0)
);

CREATE TABLE nimbus_3nf.orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES nimbus_3nf.customers (customer_id),
    order_date DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE nimbus_3nf.order_lines (
    order_id INT NOT NULL REFERENCES nimbus_3nf.orders (order_id),
    product_id INT NOT NULL REFERENCES nimbus_3nf.products (product_id),
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10, 2) NOT NULL CHECK (unit_price >= 0),
    PRIMARY KEY (order_id, product_id)
);