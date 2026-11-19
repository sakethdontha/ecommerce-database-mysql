# E-Commerce Platform Database (MySQL)

A relational database for a multi-vendor online store, built in MySQL 8: schema design, realistic sample data, a transactional purchase procedure, full-text product search, and business analytics queries written with joins, CTEs, and window functions.

All data in this project is fictional sample data. Emails use `example.com` and card numbers are standard public test numbers.

## Goal and data
Model how a marketplace actually runs, where customers, vendors, and admins share one user base; products belong to categories and vendors; and orders carry shipping, payment, coupons, and line items, and then answer business questions with SQL.

| Area | Tables |
|---|---|
| Users and roles | `users` (Customer / Vendor / Admin in one table), `address`, `user_address` |
| Catalog | `category` (self-referencing parent/child), `product`, `inventory` |
| Checkout | `orders`, `order_items`, `shipping_method`, `payment_method`, `users_payment_method`, `sale_coupon` |
| Engagement | `reviews`, `shopping_cart`, `user_search_history` |

Sample data: 112 users (27 vendors), 250 products in 29 categories, 177 orders with 353 order lines from 2020 to 2025, 112 reviews, 336 searches, 336 cart items, and stock levels for every product.

## Data preparation and integrity
- **15 tables and 23 foreign keys**, with junction tables for the many-to-many links (users and addresses, users and payment methods) and composite primary keys on `order_items` and `shopping_cart`.
- **Referential actions chosen per relationship:** deleting a user cascades to their addresses, cart, and search history, but reviews are kept (`SET NULL`); deleting a parent category keeps its subcategories; billing addresses are protected with `RESTRICT`.
- **CHECK constraints and ENUMs** keep bad values out: ratings between 1.0 and 5.0, quantities above zero, non-negative stock, and fixed sets of order statuses, roles, and card providers.
- **`order_items.price` stores the price at the time of the order**, so later price changes never rewrite past revenue.
- **`utf8mb4`** character set so names and reviews with any character, including emoji, store correctly.

## Stored procedure: `process_purchase`
Places an order safely inside one transaction:
1. Locks the product's inventory row (`SELECT ... FOR UPDATE`) so two buyers cannot take the same last unit.
2. If stock is enough, decrements stock, creates the order, and adds the order line at the current price, then commits.
3. Otherwise rolls back and returns `Out of stock`.

```sql
CALL process_purchase(23, 45, 2, 34, 30, 3, NULL, @message);
-- (user_id, product_id, quantity, shipping_address_id, payment_method_id, shipping_method_id, coupon_id)
SELECT @message;   -- 'Purchase successful' or 'Out of stock'
```

## Analysis
Examples of the questions the queries answer:
- Revenue per customer and per order after coupon discounts, excluding cancelled and returned orders
- Top vendors by revenue for each month (`RANK() OVER (PARTITION BY month ...)`)
- Top customers by order count and spend (`DENSE_RANK()`), and repeat buyers in the last three months
- July 2022 vs. July 2023 revenue (year-over-year, with CTEs)
- Active vs. total vendors in a given month
- Highest-rated vendors from product reviews
- Relevance-ranked product and review search with MySQL `FULLTEXT` indexes (`MATCH ... AGAINST`), weighting matches in the product name above the description

Coupon discounts are applied per order line, `quantity * price * (1 - discount / 100)`, so totals stay correct when a customer has a mix of discounted and full-price orders.

## How to run
Requires MySQL 8.0+.
```bash
mysql -u root -p < ecommerce_project.sql
```
The script drops and recreates the `ecommerce` database, loads all data, creates the procedure, and runs every query. It runs end to end with no errors. You can also open it in MySQL Workbench and execute it.

## Production notes
This is a learning project, so some shortcuts were intentional. In a production system, passwords would be stored as salted hashes, card numbers would be tokenized by a payment provider instead of stored, and product images would live in object storage with only the URL in the database.

## Tools
MySQL 8.0, SQL (DDL, DML, joins, subqueries, CTEs, window functions, transactions, stored procedures, full-text search), MySQL Workbench
