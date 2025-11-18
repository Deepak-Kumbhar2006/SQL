-- Q1: Retrieve the total number of orders placed.
SELECT count(*) AS Total_orders FROM orders 

---------------------------------------------------------

-- Q2: Calculate the total revenue generated from pizza sales.

SELECT 
    ROUND(SUM(order_details.quantity * pizzas.price),
            2) AS total_revenue
FROM
    order_details
        JOIN
    pizzas ON order_details.pizza_id = pizzas.pizza_id

---------------------------------------------------------
-- Q3 Sort the Pizza price in descending order and show highest priced pizza labelling with pizza name

SELECT 
    name, price
FROM
    pizzas
        INNER JOIN
    pizza_types ON pizzas.pizza_type_id = pizza_types.pizza_type_id
ORDER BY price DESC
LIMIT 1

---------------------------------------------------------
-- Q4 Identify the most common pizza size ordered

SELECT 
    size, COUNT(quantity)
FROM
    pizzas
        INNER JOIN
    order_details ON pizzas.pizza_id = order_details.pizza_id
GROUP BY size

---------------------------------------------------------
-- List the top 5 most ordered pizza types along with their quantities.

SELECT 
    pizza_type_id, COUNT(order_details_id)
FROM
    pizzas
        INNER JOIN
    order_details ON pizzas.pizza_id = order_details.pizza_id
GROUP BY pizza_type_id
ORDER BY COUNT(order_details_id) DESC
LIMIT 5



