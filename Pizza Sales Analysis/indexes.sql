-- ============================================================================
-- Pizza Sales Database - Index Optimization
-- ============================================================================
--
-- This file defines the recommended CREATE TABLE schemas (with primary keys
-- and foreign keys) and additional indexes to optimize the queries found in
-- queries.sql and queries_intermediate.sql.
--
-- Analysis methodology:
--   1. Identified every column used in JOIN, WHERE, GROUP BY, and ORDER BY
--      across both query files.
--   2. Prioritized indexes by table size and query frequency.
--   3. Evaluated the write-performance cost of each index.
--
-- Table sizes (from pizza_sales dataset):
--   order_details  ~48,620 rows  (largest  - indexes here have the most impact)
--   orders         ~21,350 rows  (medium   - indexes help GROUP BY / JOIN)
--   pizzas             ~96 rows  (small    - indexes optional but low cost)
--   pizza_types        ~32 rows  (tiny     - indexes optional but low cost)
-- ============================================================================


-- ============================================================================
-- 1. TABLE SCHEMAS  (Primary Keys & Foreign Keys)
-- ============================================================================
-- Primary-key columns are automatically indexed by MySQL (clustered index).
-- Foreign-key columns are NOT automatically indexed in all engines, so we
-- add explicit indexes for them below.
-- ============================================================================

CREATE TABLE IF NOT EXISTS pizza_types (
    pizza_type_id VARCHAR(50)  PRIMARY KEY,
    name          VARCHAR(100) NOT NULL,
    category      VARCHAR(50)  NOT NULL,
    ingredients   TEXT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS pizzas (
    pizza_id      VARCHAR(50)  PRIMARY KEY,
    pizza_type_id VARCHAR(50)  NOT NULL,
    size          VARCHAR(5)   NOT NULL,
    price         DECIMAL(5,2) NOT NULL,
    FOREIGN KEY (pizza_type_id) REFERENCES pizza_types(pizza_type_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS orders (
    order_id   INT          PRIMARY KEY AUTO_INCREMENT,
    order_date DATE         NOT NULL,
    order_time TIME         NOT NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS order_details (
    order_details_id INT         PRIMARY KEY AUTO_INCREMENT,
    order_id         INT         NOT NULL,
    pizza_id         VARCHAR(50) NOT NULL,
    quantity         INT         NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (pizza_id) REFERENCES pizzas(pizza_id)
) ENGINE=InnoDB;


-- ============================================================================
-- 2. INDEXES  (ordered by priority / impact)
-- ============================================================================


-- --------------------------------------------------------------------------
-- HIGH PRIORITY - order_details table (48,620 rows)
-- These indexes give the largest performance gain because order_details is
-- the biggest table and is involved in almost every analytical query.
-- --------------------------------------------------------------------------

-- Index: idx_order_details_pizza_id
-- Columns used in:
--   queries.sql        Q2  JOIN order_details ON order_details.pizza_id = pizzas.pizza_id
--   queries.sql        Q4  JOIN order_details ON pizzas.pizza_id = order_details.pizza_id
--   queries.sql        Q5  JOIN order_details ON pizzas.pizza_id = order_details.pizza_id
--   queries_intermediate Q1 JOIN order_details ON pizzas.pizza_id = order_details.pizza_id
--
-- Impact:  Turns full table scans on 48K rows into index lookups for every
--          query that joins order_details to pizzas.
-- Write cost: Moderate - every INSERT/UPDATE/DELETE on order_details must
--             also update this B-tree index. Acceptable because this is an
--             analytics table with infrequent writes relative to reads.
CREATE INDEX idx_order_details_pizza_id
    ON order_details (pizza_id);

-- Index: idx_order_details_order_id
-- Columns used in:
--   queries_intermediate Q3  JOIN order_details ON orders.order_id = order_details.order_id
--
-- Impact:  Speeds up the join between orders and order_details (48K rows).
--          Also benefits any future query that filters or groups by order_id.
-- Write cost: Moderate - same considerations as above. Justified because
--             order_id is a foreign key that should be indexed regardless.
CREATE INDEX idx_order_details_order_id
    ON order_details (order_id);


-- --------------------------------------------------------------------------
-- MEDIUM PRIORITY - orders table (21,350 rows)
-- These indexes help with date/time grouping queries on the orders table.
-- --------------------------------------------------------------------------

-- Index: idx_orders_order_date
-- Columns used in:
--   queries_intermediate Q3  GROUP BY order_date
--
-- Impact:  Allows the optimizer to scan dates in order rather than sorting
--          21K rows after a full table scan. Also enables efficient range
--          queries on dates (e.g., sales in a given month).
-- Write cost: Low - orders table receives one INSERT per order (not per
--             pizza line item), so the write overhead is minimal.
CREATE INDEX idx_orders_order_date
    ON orders (order_date);

-- Index: idx_orders_order_time
-- Columns used in:
--   queries_intermediate Q2  GROUP BY HOUR(order_time)
--
-- Impact:  A plain B-tree index on order_time cannot be used directly by
--          HOUR(order_time) because MySQL does not apply functions to
--          indexes. However, it still helps if queries ever filter by time
--          range (e.g., WHERE order_time BETWEEN '11:00:00' AND '14:00:00').
--          For a more targeted optimization, see the generated-column
--          approach in Section 3 below.
-- Write cost: Low - same as idx_orders_order_date.
CREATE INDEX idx_orders_order_time
    ON orders (order_time);


-- --------------------------------------------------------------------------
-- LOW PRIORITY - pizzas table (96 rows) and pizza_types table (32 rows)
-- These tables are tiny so MySQL can scan them in microseconds. The indexes
-- are still recommended for correctness (foreign key best practice) and to
-- future-proof the schema if the catalog grows.
-- --------------------------------------------------------------------------

-- Index: idx_pizzas_pizza_type_id
-- Columns used in:
--   queries.sql        Q3  JOIN pizzas ON pizzas.pizza_type_id = pizza_types.pizza_type_id
--   queries.sql        Q5  GROUP BY pizza_type_id
--   queries_intermediate Q1 JOIN pizzas ON pizza_types.pizza_type_id = pizzas.pizza_type_id
--
-- Impact:  Negligible on 96 rows, but this is a foreign key column and
--          should be indexed per relational best practices.
-- Write cost: Negligible - very few rows.
CREATE INDEX idx_pizzas_pizza_type_id
    ON pizzas (pizza_type_id);

-- Index: idx_pizzas_price
-- Columns used in:
--   queries.sql Q3  ORDER BY price DESC LIMIT 1
--
-- Impact:  With this index MySQL can satisfy the ORDER BY ... LIMIT 1
--          without a sort (index-ordered scan). Minimal benefit on 96 rows.
-- Write cost: Negligible.
CREATE INDEX idx_pizzas_price
    ON pizzas (price);

-- Index: idx_pizzas_size
-- Columns used in:
--   queries.sql Q4  GROUP BY size
--
-- Impact:  Allows a loose index scan for GROUP BY on size. Minimal benefit
--          on 96 rows.
-- Write cost: Negligible.
CREATE INDEX idx_pizzas_size
    ON pizzas (size);

-- Index: idx_pizza_types_category
-- Columns used in:
--   queries_intermediate Q1  GROUP BY category
--
-- Impact:  Negligible on 32 rows, but useful if the pizza catalog grows
--          or if category is used as a filter in future queries.
-- Write cost: Negligible.
CREATE INDEX idx_pizza_types_category
    ON pizza_types (category);


-- ============================================================================
-- 3. ADVANCED OPTIMIZATION (Optional)
-- ============================================================================
-- For queries_intermediate.sql Q2:
--     SELECT HOUR(order_time), COUNT(order_id) FROM orders
--     GROUP BY HOUR(order_time) ORDER BY COUNT(order_id) DESC;
--
-- MySQL cannot use a standard index when a function is applied to a column.
-- A generated (virtual) column + index lets the optimizer use an index scan:
--
--   ALTER TABLE orders
--       ADD COLUMN order_hour TINYINT
--           GENERATED ALWAYS AS (HOUR(order_time)) STORED;
--
--   CREATE INDEX idx_orders_order_hour ON orders (order_hour);
--
-- After this, rewrite the query to:
--     SELECT order_hour, COUNT(order_id) FROM orders
--     GROUP BY order_hour ORDER BY COUNT(order_id) DESC;
--
-- Trade-off: Adds a stored column (~21K TINYINT values = ~21 KB) and one
-- more index to maintain on writes. Recommended only if Q2 is a frequent
-- or latency-sensitive query.
-- ============================================================================


-- ============================================================================
-- 4. COMPOSITE INDEX OPPORTUNITIES (Optional)
-- ============================================================================
-- If the same multi-table joins run frequently, composite (covering) indexes
-- can eliminate the need to look up the base table row entirely:
--
--   CREATE INDEX idx_order_details_pizza_id_quantity
--       ON order_details (pizza_id, quantity);
--
-- This covers queries.sql Q2 (SUM(quantity)) and Q4 (COUNT(quantity))
-- without an extra table lookup. The trade-off is a wider index that uses
-- more disk/memory and slightly increases write cost.
--
--   CREATE INDEX idx_order_details_order_id_quantity
--       ON order_details (order_id, quantity);
--
-- This covers queries_intermediate.sql Q3 (SUM(quantity) ... GROUP BY
-- order_date via join with orders) as a covering index.
-- ============================================================================


-- ============================================================================
-- 5. WRITE PERFORMANCE SUMMARY
-- ============================================================================
--
-- Table            | # Indexes Added | Write Impact Assessment
-- -----------------+-----------------+----------------------------------------------
-- order_details    | 2               | MODERATE - Largest table (48K rows). Each
--                  |                 | INSERT updates 2 additional B-tree indexes.
--                  |                 | Justified because this table is read-heavy
--                  |                 | in analytics and the indexes eliminate full
--                  |                 | table scans on the two most-used FK columns.
--                  |                 |
-- orders           | 2               | LOW - Medium table (21K rows). Inserts are
--                  |                 | per-order (not per-line-item), so write
--                  |                 | volume is ~4.5x lower than order_details.
--                  |                 |
-- pizzas           | 3               | NEGLIGIBLE - Only 96 rows. Catalog changes
--                  |                 | (adding/removing pizza varieties) are rare.
--                  |                 |
-- pizza_types      | 1               | NEGLIGIBLE - Only 32 rows. Catalog changes
--                  |                 | are extremely rare.
--
-- Overall: 8 new indexes. The total additional storage is small (a few MB)
-- and the write overhead is justified by the analytical read patterns.
-- The only indexes with meaningful write cost are the two on order_details,
-- and those are essential for the most frequently executed joins.
-- ============================================================================
