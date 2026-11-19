DROP PROCEDURE IF EXISTS ecommerce.process_purchase;
DROP DATABASE IF EXISTS ecommerce;
CREATE DATABASE ecommerce CHARSET utf8mb4; -- orginally set to utf8mb3 to "save space", but did some research that showed utf8mb4 was better
-- in terms of perfomance and that utf8mb4 only used the extra byte of space if it needed it (like a varchar)
-- sources: https://dev.mysql.com/blog-archive/mysql-8-0-when-to-use-utf8mb3-over-utf8mb4/
-- 			https://stackoverflow.com/questions/30074492/what-is-the-difference-between-utf8mb4-and-utf8-charsets-in-mysql
USE ecommerce;
CREATE TABLE users ( -- table that holds all the users of the ecomerce site
    user_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, -- internal identifier
    username VARCHAR(50) UNIQUE NOT NULL, -- screen name/store name
    password VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    firstname VARCHAR(50) NOT NULL,
    lastname VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_role ENUM('Customer','Vendor','Admin') -- role column to keep from needing separate tables for each role
);

SELECT *
FROM users;


CREATE TABLE address ( -- holds all addresses
-- at the moment, only allows US addresses, but can update to allow more countries int the future by adding needed cols and contraint checks
    address_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    address_type ENUM('Home', 'Work', 'Other') NOT NULL,
    address_line1 VARCHAR(50) NOT NULL,
    address_line2 VARCHAR(50),
    city VARCHAR(50) NOT NULL,
    state CHAR(2), 
    country ENUM('United States') ,
    zip VARCHAR(20) NOT NULL, -- depends on city in some instances, but not all
    CONSTRAINT CHECK (country = 'United States' AND state is not NULL) 
);
CREATE TABLE user_address ( -- links users to address to allow for a many-to-many relationship
    user_id INT UNSIGNED,
    address_id INT UNSIGNED,
    PRIMARY KEY (user_id, address_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) 
		ON UPDATE CASCADE ON DELETE CASCADE, -- want changes to user_id to show up here and if user is deleted, delete associated relationship
    FOREIGN KEY (address_id) REFERENCES address(address_id) 
		ON UPDATE CASCADE ON DELETE CASCADE  -- want changes to address_id to show up here and if address is deleted, delete associated relationship
);
CREATE TABLE category ( -- product categories for searching and filtering
    category_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    category_name VARCHAR(20) UNIQUE NOT NULL,
    category_parent_id INT UNSIGNED, -- allow for subcategories
    FOREIGN KEY (category_parent_id) REFERENCES category(category_id) 
		ON UPDATE CASCADE ON DELETE SET NULL -- if category_id is updated, want changes to show here.  if category parent deleted, don't want to delete children
);
CREATE TABLE user_search_history ( -- search history for users
    search_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNSIGNED, -- fk to users to link searches with the user
    search_text TEXT NOT NULL,
    category_id INT UNSIGNED, -- for filtering
    min_price DECIMAL(10,2), -- for filtering
    max_price DECIMAL(10,2), -- for filtering
    search_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) 
		ON UPDATE CASCADE ON DELETE CASCADE, -- if user_id is changed, want to keep search history assoc. with them.  if user deleted, delete search history
    FOREIGN KEY (category_id) REFERENCES category(category_id) 
		ON UPDATE CASCADE ON DELETE SET NULL, -- if category_id is updated, want to update relationship. if category deleted, do not want to delete search history
	FULLTEXT(search_text)
);
CREATE TABLE product ( -- all products on site with details and associated vendor
    product_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, -- internal identifier
    category_id INT UNSIGNED,
    name VARCHAR(50) NOT NULL,
    product_description TEXT, -- allows for more characters than varchar
    price DECIMAL(10,2) NOT NULL,
    product_image_link TEXT, -- better to store image data in BLOB?
    vendor_id INT UNSIGNED, -- fk to users to link products to vendors
    FOREIGN KEY (category_id) REFERENCES category(category_id) 
		ON UPDATE CASCADE ON DELETE SET NULL, -- if category_id is updated, want to update relationship. if category deleted, do not want to delete product
    FOREIGN KEY (vendor_id) REFERENCES users(user_id) 
		ON UPDATE CASCADE ON DELETE CASCADE, -- if vendor's user_id is updated, is updated, want to update relationship. if vendor deleted, delete assoc. products
	FULLTEXT (product_description),
    FULLTEXT (product_image_link),
    FULLTEXT (product_description,product_image_link)
);

CREATE TABLE inventory (
    inventory_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id INT UNSIGNED NOT NULL,
    stock_quantity INT UNSIGNED NOT NULL CHECK (stock_quantity >= 0),
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    minimum_stock INT UNSIGNED DEFAULT 10 CHECK (minimum_stock >= 0),
    UNIQUE KEY (product_id),
    FOREIGN KEY (product_id) REFERENCES product(product_id) 
		ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE shipping_method (  -- allow for different shipping methods at different prices
    shipping_method_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name ENUM('Regular', 'Fast', 'Express') NOT NULL,
    price DECIMAL(10,2) NOT NULL
);

CREATE TABLE payment_method ( -- saves a user's payment method for an order, only allows credit and debit cards
    payment_method_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    payment_type ENUM('Credit Card', 'Debit Card') NOT NULL,
    provider ENUM('Visa','Mastercard','Discover','American Express') NOT NULL,
    card_number VARCHAR(20) NOT NULL,
    expiry_date CHAR(5) NOT NULL,
    ccv CHAR(4),
    billing_address_id INT UNSIGNED, 
	FOREIGN KEY (billing_address_id) REFERENCES address(address_id)
		ON UPDATE CASCADE ON DELETE RESTRICT -- don't want to delete address without updating relationship first
);

CREATE TABLE users_payment_method( -- allows for a many-to-many relationship between users and payment methods
	user_id INT UNSIGNED,
    payment_method_id INT UNSIGNED,
    PRIMARY KEY (user_id, payment_method_id),
	FOREIGN KEY (user_id) REFERENCES users(user_id)
		ON UPDATE CASCADE ON DELETE CASCADE, -- want changes to user_id to show up here and if user is deleted, delete associated relationship
    FOREIGN KEY (payment_method_id) REFERENCES payment_method(payment_method_id)
		ON UPDATE CASCADE ON DELETE CASCADE -- want changes to payment_method_id to show up here and if payment_method is deleted, delete associated relationship
);

CREATE TABLE sale_coupon( -- allow for sales and coupons to be applied to orders
	coupon_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    coupon_code VARCHAR(10) NOT NULL,
    coupon_name VARCHAR(50),
    coupon_desc VARCHAR(100),
    discount INT NOT NULL, -- percentage off, ex. if discount = 20, sale is 20% off
    start_date DATE,
    expiry_date DATE
);

CREATE TABLE orders ( -- holds all orders
    order_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNSIGNED, -- fk to link order to customer
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    shipping_address_id INT UNSIGNED, -- fk to address
    payment_method_id INT UNSIGNED, -- fk to payment method
    shipping_method_id INT UNSIGNED, -- fk to shipping method
    order_status ENUM('Pending', 'Shipped', 'Delivered', 'Cancelled', 'Returned') DEFAULT 'Pending', -- order status
    order_status_time_stamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    coupon_id INT UNSIGNED, -- fk to sale_coupon
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    -- for these, don't want to delete/change anything while order is in progress, but want to allow if order is complete 
    -- maybe use trigger (saw mentioned on stack overflow)
    FOREIGN KEY (shipping_address_id) REFERENCES address(address_id),
    FOREIGN KEY (payment_method_id) REFERENCES payment_method(payment_method_id),
    FOREIGN KEY (shipping_method_id) REFERENCES shipping_method(shipping_method_id),
    FOREIGN KEY (coupon_id) REFERENCES sale_coupon(coupon_id)
);
CREATE TABLE shopping_cart ( -- allows users to save products to purchase
    user_id INT UNSIGNED,
    product_id INT UNSIGNED,
    quantity INT UNSIGNED NOT NULL CHECK (quantity > 0), -- only quantities greater than zero make sense (0 is included in unsigned, so add addtional check)
    PRIMARY KEY(user_id, product_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) 
		ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES product(product_id) 
		ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE reviews ( -- allow users to leave reviews for products or vendors
    review_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNSIGNED, -- customer leaving review, fk to users
    product_id INT UNSIGNED, -- product associated with review
    vendor_id INT UNSIGNED,
    rating_value DECIMAL(2,1) CHECK (rating_value BETWEEN 1.0 AND 5.0),
    content TEXT, 
    review_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    review_helpfulness SMALLINT,
    FOREIGN KEY (user_id) REFERENCES users(user_id) -- customer
		ON DELETE SET NULL, -- want to keep reviews if customer user is deleted
	FOREIGN KEY (product_id) REFERENCES product(product_id)
		ON UPDATE CASCADE ON DELETE CASCADE, -- want changes to product to show here
    FOREIGN KEY (vendor_id) REFERENCES users(user_id) 
		ON UPDATE CASCADE ON DELETE CASCADE, -- want changes to vendor to show here
	FULLTEXT(content)
);

CREATE TABLE order_items ( -- links orders and line items
    order_id INT UNSIGNED,                              -- Foreign Key to Invoice table
    product_id INT UNSIGNED,                            -- Foreign Key to Products table
    quantity INT UNSIGNED CHECK (quantity > 0),         -- Quantity of the product in the order
    price DECIMAL(10, 2),                       -- Price of the product at the time of the order
    PRIMARY KEY (order_id, product_id),         -- Composite Primary Key for order and product
    FOREIGN KEY (order_id) REFERENCES orders(order_id), -- Reference to the orders table
    FOREIGN KEY (product_id) REFERENCES product(product_id) -- Reference to the Products table
);

-- Insert 100 users into the users table with unique, realistic passwords
INSERT INTO users (username, password, email, firstname, lastname, user_role, created_at)
VALUES
('john_doe', 'Sun@2023!', 'john.doe@example.com', 'John', 'Doe', 'Customer', '2021-03-15 08:34:21'),
('jane_smith', 'Pine$apple7', 'jane.smith@example.com', 'Jane', 'Smith', 'Customer', '2022-07-22 14:56:43'),
('michael_johnson', 'M0untain#1', 'michael.johnson@example.com', 'Michael', 'Johnson', 'Customer', '2020-11-30 09:12:54'),
('emily_brown', 'R@inbow99', 'emily.brown@example.com', 'Emily', 'Brown', 'Customer', '2023-05-18 17:45:32'),
('david_wilson', 'T1ger$2023', 'david.wilson@example.com', 'David', 'Wilson', 'Admin', '2024-01-10 10:23:11'),
('sarah_miller', 'C@ndlelight5', 'sarah.miller@example.com', 'Sarah', 'Miller', 'Vendor', '2021-09-05 12:34:56'),
('james_davis', 'F!rework$23', 'james.davis@example.com', 'James', 'Davis', 'Vendor', '2022-12-25 19:08:42'),
('linda_garcia', 'St@rlight8', 'linda.garcia@example.com', 'Linda', 'Garcia', 'Customer', '2020-06-14 07:59:33'),
('robert_rodriguez', 'B@nanaSplit1', 'robert.rodriguez@example.com', 'Robert', 'Rodriguez', 'Customer', '2023-08-20 16:22:44'),
('mary_martinez', 'L!me$oda99', 'mary.martinez@example.com', 'Mary', 'Martinez', 'Customer', '2021-02-28 22:11:05'),
('william_hernandez', 'C0ffee#2023', 'william.hernandez@example.com', 'William', 'Hernandez', 'Vendor', '2024-04-12 13:45:27'),
('elizabeth_lopez', 'M@pleSyrup7', 'elizabeth.lopez@example.com', 'Elizabeth', 'Lopez', 'Customer', '2022-10-08 18:37:19'),
('richard_gonzalez', 'P!zzaSlice1', 'richard.gonzalez@example.com', 'Richard', 'Gonzalez', 'Customer', '2020-04-19 11:53:47'),
('joseph_anderson', 'B@sketball2', 'joseph.anderson@example.com', 'Joseph', 'Anderson', 'Customer', '2023-07-03 20:14:38'),
('thomas_taylor', 'T0m@Tay789', 'thomas.taylor@example.com', 'Thomas', 'Taylor', 'Vendor', '2021-12-11 09:27:55'),
('jennifer_moore', 'J3nn!ferM', 'jennifer.moore@example.com', 'Jennifer', 'Moore', 'Customer', '2024-06-29 15:48:12'),
('charles_jackson', 'Ch@rlesJ23', 'charles.jackson@example.com', 'Charles', 'Jackson', 'Customer', '2020-08-24 10:36:49'),
('margaret_thompson', 'M@rgaretT1', 'margaret.thompson@example.com', 'Margaret', 'Thompson', 'Customer', '2022-03-17 14:22:33'),
('christopher_white', 'Chr!sW789', 'christopher.white@example.com', 'Christopher', 'White', 'Vendor', '2023-11-21 08:45:16'),
('dorothy_harris', 'D0rothyH23', 'dorothy.harris@example.com', 'Dorothy', 'Harris', 'Customer', '2021-05-09 19:53:27'),
('daniel_martin', 'D@nielM456', 'daniel.martin@example.com', 'Daniel', 'Martin', 'Admin', '2024-02-14 12:34:56'),
('patricia_clark', 'P@triciaC1', 'patricia.clark@example.com', 'Patricia', 'Clark', 'Customer', '2020-09-26 16:47:38'),
('matthew_lewis', 'M@tthewL23', 'matthew.lewis@example.com', 'Matthew', 'Lewis', 'Vendor', '2022-01-07 07:12:45'),
('lisa_robinson', 'L!saR789', 'lisa.robinson@example.com', 'Lisa', 'Robinson', 'Customer', '2023-04-30 21:08:19'),
('anthony_walker', 'A@nthonyW1', 'anthony.walker@example.com', 'Anthony', 'Walker', 'Customer', '2021-08-15 13:56:42'),
('susan_young', 'S@sanY456', 'susan.young@example.com', 'Susan', 'Young', 'Vendor', '2024-05-22 18:24:37'),
('mark_allen', 'M@rkA789', 'mark.allen@example.com', 'Mark', 'Allen', 'Vendor', '2020-12-31 23:59:59'),
('nancy_king', 'N@ncyK123', 'nancy.king@example.com', 'Nancy', 'King', 'Customer', '2022-06-18 10:11:12'),
('donald_scott', 'D0naldS456', 'donald.scott@example.com', 'Donald', 'Scott', 'Customer', '2023-09-14 14:33:44'),
('karen_green', 'K@renG789', 'karen.green@example.com', 'Karen', 'Green', 'Customer', '2021-01-25 09:45:27'),
('george_adams', 'G3orgeA123', 'george.adams@example.com', 'George', 'Adams', 'Vendor', '2024-03-08 17:22:11'),
('betty_baker', 'B@ttyB456', 'betty.baker@example.com', 'Betty', 'Baker', 'Customer', '2020-07-12 12:34:56'),
('paul_nelson', 'P@ulN789', 'paul.nelson@example.com', 'Paul', 'Nelson', 'Vendor', '2022-02-28 20:45:38'),
('helen_hill', 'H3lenH123', 'helen.hill@example.com', 'Helen', 'Hill', 'Customer', '2023-10-05 08:56:49'),
('steven_ramirez', 'St3venR456', 'steven.ramirez@example.com', 'Steven', 'Ramirez', 'Vendor', '2021-04-17 15:27:33'),
('sandra_campbell', 'S@ndraC789', 'sandra.campbell@example.com', 'Sandra', 'Campbell', 'Customer', '2024-07-19 11:48:22'),
('kevin_mitchell', 'K3vinM123', 'kevin.mitchell@example.com', 'Kevin', 'Mitchell', 'Customer', '2020-03-22 18:34:56'),
('carol_roberts', 'C@rolR456', 'carol.roberts@example.com', 'Carol', 'Roberts', 'Customer', '2022-08-09 14:12:45'),
('brian_carter', 'Br!anC789', 'brian.carter@example.com', 'Brian', 'Carter', 'Vendor', '2023-12-24 09:27:38'),
('ruth_phillips', 'RuthP123!', 'ruth.phillips@example.com', 'Ruth', 'Phillips', 'Customer', '2021-06-30 22:11:05'),
('edward_evans', 'Edw@rdE456', 'edward.evans@example.com', 'Edward', 'Evans', 'Customer', '2024-09-11 16:45:27'),
('sharon_turner', 'Sh@ronT789', 'sharon.turner@example.com', 'Sharon', 'Turner', 'Customer', '2020-05-14 10:53:47'),
('ronald_torres', 'R0naldT123', 'ronald.torres@example.com', 'Ronald', 'Torres', 'Vendor', '2022-11-23 19:08:42'),
('michelle_parker', 'M!chelleP456', 'michelle.parker@example.com', 'Michelle', 'Parker', 'Customer', '2023-02-16 12:34:56'),
('gary_collins', 'G@ryC789', 'gary.collins@example.com', 'Gary', 'Collins', 'Customer', '2021-07-28 08:45:16'),
('laura_edwards', 'L@uraE123', 'laura.edwards@example.com', 'Laura', 'Edwards', 'Customer', '2024-08-03 17:22:11'),
('jason_stewart', 'J@sonS456', 'jason.stewart@example.com', 'Jason', 'Stewart', 'Vendor', '2020-10-29 14:33:44'),
('deborah_flores', 'Deb0rahF789', 'deborah.flores@example.com', 'Deborah', 'Flores', 'Customer', '2022-04-13 09:27:55'),
('jeffrey_morris', 'J3ffreyM123', 'jeffrey.morris@example.com', 'Jeffrey', 'Morris', 'Admin', '2023-06-07 18:24:37'),
('cynthia_nguyen', 'Cynth!aN456', 'cynthia.nguyen@example.com', 'Cynthia', 'Nguyen', 'Customer', '2021-09-21 13:56:42'),
('ryan_murphy', 'R@yanM789', 'ryan.murphy@example.com', 'Ryan', 'Murphy', 'Vendor', '2024-10-12 21:08:19'),
('amy_rivera', 'A@myR123', 'amy.rivera@example.com', 'Amy', 'Rivera', 'Vendor', '2020-02-18 07:12:45'),
('jacob_cook', 'J@cobC456', 'jacob.cook@example.com', 'Jacob', 'Cook', 'Customer', '2022-05-26 16:47:38'),
('brenda_rogers', 'B@rendaR789', 'brenda.rogers@example.com', 'Brenda', 'Rogers', 'Admin', '2023-01-09 10:36:49'),
('gary_morgan', 'G@ryM123', 'gary.morgan@example.com', 'Gary', 'Morgan', 'Vendor', '2021-03-04 19:53:27'),
('emma_peterson', 'E@mmaP456', 'emma.peterson@example.com', 'Emma', 'Peterson', 'Customer', '2024-11-15 14:22:33'),
('aaron_cooper', 'A@ronC789', 'aaron.cooper@example.com', 'Aaron', 'Cooper', 'Customer', '2020-08-07 12:34:56'),
('anna_reed', 'A@nnaR123', 'anna.reed@example.com', 'Anna', 'Reed', 'Customer', '2022-09-30 18:37:19'),
('frank_bailey', 'Fr@nkB456', 'frank.bailey@example.com', 'Frank', 'Bailey', 'Vendor', '2023-03-25 09:45:27'),
('virginia_bell', 'V@rginiaB789', 'virginia.bell@example.com', 'Virginia', 'Bell', 'Customer', '2021-10-11 17:45:32'),
('noah_gomez', 'N@ahG123', 'noah.gomez@example.com', 'Noah', 'Gomez', 'Customer', '2024-12-20 22:11:05'),
('kathleen_kelly', 'K@thleenK456', 'kathleen.kelly@example.com', 'Kathleen', 'Kelly', 'Customer', '2020-01-05 08:34:21'),
('dennis_howard', 'D@nnisH789', 'dennis.howard@example.com', 'Dennis', 'Howard', 'Vendor', '2022-07-14 14:56:43'),
('maria_ward', 'M@riaW123', 'maria.ward@example.com', 'Maria', 'Ward', 'Customer', '2023-04-08 09:12:54'),
('peter_cox', 'P@terC456', 'peter.cox@example.com', 'Peter', 'Cox', 'Customer', '2021-11-19 17:45:32'),
('heather_diaz', 'H@atherD789', 'heather.diaz@example.com', 'Heather', 'Diaz', 'Customer', '2024-06-02 10:23:11'),
('harry_richardson', 'H@rryR123', 'harry.richardson@example.com', 'Harry', 'Richardson', 'Vendor', '2020-12-13 12:34:56'),
('sophia_wood', 'S@phiaW456', 'sophia.wood@example.com', 'Sophia', 'Wood', 'Customer', '2022-03-28 19:08:42'),
('patrick_watson', 'P@trickW789', 'patrick.watson@example.com', 'Patrick', 'Watson', 'Customer', '2023-08-11 16:22:44'),
('olivia_brooks', 'O@liviaB123', 'olivia.brooks@example.com', 'Olivia', 'Brooks', 'Customer', '2021-02-14 22:11:05'),
('justin_bennett', 'J@stinB456', 'justin.bennett@example.com', 'Justin', 'Bennett', 'Vendor', '2024-05-07 13:45:27'),
('grace_gray', 'G@raceG789', 'grace.gray@example.com', 'Grace', 'Gray', 'Vendor', '2020-04-19 18:37:19'),
('terry_james', 'T@rryJ123', 'terry.james@example.com', 'Terry', 'James', 'Customer', '2022-10-25 11:53:47'),
('judy_reyes', 'J@udyR456', 'judy.reyes@example.com', 'Judy', 'Reyes', 'Customer', '2023-07-17 20:14:38'),
('ralph_cruz', 'R@lphC789', 'ralph.cruz@example.com', 'Ralph', 'Cruz', 'Vendor', '2021-05-29 09:27:55'),
('beverly_hughes', 'B@verlyH123', 'beverly.hughes@example.com', 'Beverly', 'Hughes', 'Admin', '2024-09-03 15:48:12'),
('benjamin_price', 'B@njaminP456', 'benjamin.price@example.com', 'Benjamin', 'Price', 'Customer', '2020-06-22 10:36:49'),
('evelyn_myers', 'E@velynM789', 'evelyn.myers@example.com', 'Evelyn', 'Myers', 'Customer', '2022-01-14 14:22:33'),
('philip_long', 'P@hilipL123', 'philip.long@example.com', 'Philip', 'Long', 'Vendor', '2023-12-08 08:45:16'),
('cheryl_foster', 'C@herylF456', 'cheryl.foster@example.com', 'Cheryl', 'Foster', 'Customer', '2021-08-27 19:53:27'),
('samuel_sanders', 'S@muelS789', 'samuel.sanders@example.com', 'Samuel', 'Sanders', 'Admin', '2024-02-19 12:34:56'),
('mildred_ross', 'M@ldredR123', 'mildred.ross@example.com', 'Mildred', 'Ross', 'Admin', '2020-09-10 16:47:38'),
('raymond_morales', 'R@ymondM456', 'raymond.morales@example.com', 'Raymond', 'Morales', 'Vendor', '2022-04-05 07:12:45'),
('katherine_powell', 'K@therineP789', 'katherine.powell@example.com', 'Katherine', 'Powell', 'Customer', '2023-11-29 21:08:19'),
('louis_simmons', 'L@uisS123', 'louis.simmons@example.com', 'Louis', 'Simmons', 'Customer', '2021-07-12 13:56:42'),
('joan_russell', 'J@anR456', 'joan.russell@example.com', 'Joan', 'Russell', 'Customer', '2024-08-25 18:24:37'),
('alfred_ortiz', 'A@lfredO789', 'alfred.ortiz@example.com', 'Alfred', 'Ortiz', 'Vendor', '2020-03-17 23:59:59'),
('rose_jenkins', 'R@seJ123', 'rose.jenkins@example.com', 'Rose', 'Jenkins', 'Customer', '2022-06-28 10:11:12'),
('gloria_gutierrez', 'G@loriaG456', 'gloria.gutierrez@example.com', 'Gloria', 'Gutierrez', 'Customer', '2023-05-14 14:33:44'),
('jerry_perry', 'J@rryP789', 'jerry.perry@example.com', 'Jerry', 'Perry', 'Customer', '2021-01-20 09:45:27'),
('marie_butler', 'M@rieB123', 'marie.butler@example.com', 'Marie', 'Butler', 'Customer', '2024-04-09 17:22:11'),
('victor_barnes', 'V@ctorB456', 'victor.barnes@example.com', 'Victor', 'Barnes', 'Admin', '2020-07-23 12:34:56'),
('ruby_fisher', 'R@ubyF789', 'ruby.fisher@example.com', 'Ruby', 'Fisher', 'Customer', '2022-02-15 20:45:38'),
('martin_henderson', 'M@rtinH123', 'martin.henderson@example.com', 'Martin', 'Henderson', 'Customer', '2023-10-18 08:56:49'),
('irene_coleman', 'I@reneC456', 'irene.coleman@example.com', 'Irene', 'Coleman', 'Vendor', '2021-04-30 15:27:33'),
('clarence_jenkins', 'C@larenceJ789', 'clarence.jenkins@example.com', 'Clarence', 'Jenkins', 'Customer', '2024-07-11 11:48:22'),
('eleanor_west', 'E@leanW123', 'eleanor.west@example.com', 'Eleanor', 'West', 'Customer', '2020-05-28 18:34:56'),
('albert_gardner', 'A@lbertG456', 'albert.gardner@example.com', 'Albert', 'Gardner', 'Customer', '2022-08-19 14:12:45'),
('doris_hanson', 'D@risH789', 'doris.hanson@example.com', 'Doris', 'Hanson', 'Customer', '2023-12-31 09:27:38'),
('roger_webb', 'R@gerW123', 'roger.webb@example.com', 'Roger', 'Webb', 'Admin', '2021-06-14 22:11:05'),
-- New users for 2025 (January to March 25)
('leo_hunter', 'W!nter$2025', 'leo.hunter@example.com', 'Leo', 'Hunter', 'Customer', '2025-01-03 09:15:30'),
('mason_rivers', 'F3b$Rain2025', 'mason.rivers@example.com', 'Mason', 'Rivers', 'Customer', '2025-01-05 08:22:11'),
('clara_fox', 'Sn0wFlake#1', 'clara.fox@example.com', 'Clara', 'Fox', 'Customer', '2025-01-12 14:27:45'),
('ethan_blake', 'Fr0st!Bite2', 'ethan.blake@example.com', 'Ethan', 'Blake', 'Customer', '2025-01-20 11:33:22'),
('isabella_pearl', 'Ic3Queen$25', 'isabella.pearl@example.com', 'Isabella', 'Pearl', 'Customer', '2025-01-28 16:48:19'),
('ava_snow', 'M@rchHare25', 'ava.snow@example.com', 'Ava', 'Snow', 'Customer', '2025-02-02 12:18:33'),
('zoe_storm', 'Thund3r!Hub', 'zoe.storm@example.com', 'Zoe', 'Storm', 'Customer', '2025-02-14 13:55:37'),
('lily_fern', 'Bl0ssom#25', 'lily.fern@example.com', 'Lily', 'Fern', 'Customer', '2025-02-19 17:10:44'),
('owen_clay', 'M@udPie2025', 'owen.clay@example.com', 'Owen', 'Clay', 'Customer', '2025-02-27 10:45:58'),
('jaxon_leaf', 'Spr!ng$2025', 'jaxon.leaf@example.com', 'Jaxon', 'Leaf', 'Customer', '2025-03-10 15:29:47'),
('mia_rose', 'P3tal$Bloom', 'mia.rose@example.com', 'Mia', 'Rose', 'Customer', '2025-03-17 09:37:12'),
('caleb_wind', 'Br33ze!2025', 'caleb.wind@example.com', 'Caleb', 'Wind', 'Customer', '2025-03-24 14:52:09');

SELECT * 
from users;


INSERT INTO address (address_type, address_line1, address_line2, city, state, country, zip)
VALUES
('Home', '123 Main St', 'Apt 1', 'New York', 'NY', 'United States', '10001'),
('Work', '1010 Elm St', 'Suite 300', 'San Francisco', 'CA', 'United States', '94101'),
('Home', '456 Elm St', 'Suite 100', 'Los Angeles', 'CA', 'United States', '90001'),
('Other', '2121 Ash St', 'Apt 40', 'Portland', 'OR', 'United States', '97201'),
('Home', '789 Oak St', 'Apt 2B', 'Chicago', 'IL', 'United States', '60601'),
('Work', '1212 Oak St', 'Floor 15', 'Indianapolis', 'IN', 'United States', '46201'),
('Home', '321 Pine St', 'Floor 3', 'Houston', 'TX', 'United States', '77001'),
('Other', '2222 Birch St', 'Suite 600', 'Las Vegas', 'NV', 'United States', '89101'),
('Home', '654 Maple St', 'Unit 5', 'Phoenix', 'AZ', 'United States', '85001'),
('Work', '1313 Pine St', 'Apt 20', 'Seattle', 'WA', 'United States', '98101'),
('Home', '987 Cedar St', 'Apt 12', 'Philadelphia', 'PA', 'United States', '19101'),
('Other', '2323 Cedar St', 'Floor 8', 'Memphis', 'TN', 'United States', '37501'),
('Home', '111 Birch St', 'Suite 200', 'San Antonio', 'TX', 'United States', '78201'),
('Work', '1414 Maple St', 'Unit 25', 'Denver', 'CO', 'United States', '80201'),
('Home', '222 Walnut St', 'Apt 10', 'San Diego', 'CA', 'United States', '92101'),
('Other', '2424 Elm St', 'Unit 45', 'Louisville', 'KY', 'United States', '40201'),
('Home', '333 Cherry St', 'Floor 7', 'Dallas', 'TX', 'United States', '75201'),
('Work', '1515 Cedar St', 'Suite 400', 'Washington', 'DC', 'United States', '20001'),
('Home', '444 Spruce St', 'Unit 8', 'San Jose', 'CA', 'United States', '95101'),
('Other', '2525 Oak St', 'Apt 50', 'Baltimore', 'MD', 'United States', '21201'),
('Work', '1616 Walnut St', 'Floor 10', 'Boston', 'MA', 'United States', '02101'),
('Other', '2626 Pine St', 'Suite 700', 'Milwaukee', 'WI', 'United States', '53201'),
('Work', '1717 Cherry St', 'Apt 30', 'El Paso', 'TX', 'United States', '79901'),
('Other', '2727 Maple St', 'Floor 12', 'Albuquerque', 'NM', 'United States', '87101'),
('Work', '1818 Spruce St', 'Suite 500', 'Nashville', 'TN', 'United States', '37201'),
('Other', '2828 Cedar St', 'Unit 55', 'Tucson', 'AZ', 'United States', '85701'),
('Work', '1919 Willow St', 'Floor 5', 'Detroit', 'MI', 'United States', '48201'),
('Other', '2929 Walnut St', 'Apt 60', 'Fresno', 'CA', 'United States', '93650'),
('Work', '2020 Poplar St', 'Unit 35', 'Oklahoma City', 'OK', 'United States', '73101'),
('Other', '3030 Cherry St', 'Suite 800', 'Sacramento', 'CA', 'United States', '94203'),
('Home', '3131 Spruce St', 'Apt 65', 'Kansas City', 'MO', 'United States', '64101'),
('Other', '5151 Oak St', 'Apt 115', 'Stockton', 'CA', 'United States', '95201'),
('Home', '3232 Willow St', 'Floor 20', 'Atlanta', 'GA', 'United States', '30301'),
('Other', '5252 Pine St', 'Floor 45', 'Henderson', 'NV', 'United States', '89002'),
('Home', '3333 Poplar St', 'Unit 70', 'Miami', 'FL', 'United States', '33101'),
('Other', '5353 Maple St', 'Unit 120', 'Saint Paul', 'MN', 'United States', '55101'),
('Home', '3434 Ash St', 'Suite 900', 'Raleigh', 'NC', 'United States', '27601'),
('Other', '5454 Cedar St', 'Suite 1400', 'Cincinnati', 'OH', 'United States', '45201'),
('Home', '3535 Birch St', 'Apt 75', 'Omaha', 'NE', 'United States', '68101'),
('Other', '5555 Walnut St', 'Apt 125', 'Greensboro', 'NC', 'United States', '27401'),
('Home', '3636 Cedar St', 'Floor 25', 'Minneapolis', 'MN', 'United States', '55401'),
('Other', '5656 Cherry St', 'Floor 50', 'Pittsburgh', 'PA', 'United States', '15201'),
('Home', '3737 Elm St', 'Unit 80', 'Tulsa', 'OK', 'United States', '74101'),
('Other', '5757 Spruce St', 'Unit 130', 'St. Louis', 'MO', 'United States', '63101'),
('Home', '3838 Oak St', 'Suite 1000', 'Wichita', 'KS', 'United States', '67201'),
('Other', '5858 Willow St', 'Suite 1500', 'Lincoln', 'NE', 'United States', '68501'),
('Home', '3939 Pine St', 'Apt 85', 'New Orleans', 'LA', 'United States', '70112'),
('Other', '5959 Poplar St', 'Apt 135', 'Plano', 'TX', 'United States', '75001'),
('Home', '4040 Maple St', 'Floor 30', 'Arlington', 'TX', 'United States', '76001'),
('Other', '6060 Ash St', 'Floor 55', 'Orlando', 'FL', 'United States', '32801'),
('Work', '4141 Cedar St', 'Unit 90', 'Cleveland', 'OH', 'United States', '44101'),
('Other', '8181 Walnut St', 'Apt 205', 'Richmond', 'VA', 'United States', '23218'),
('Work', '4242 Walnut St', 'Suite 1100', 'Bakersfield', 'CA', 'United States', '93301'),
('Other', '8282 Cherry St', 'Suite 2100', 'Baton Rouge', 'LA', 'United States', '70801'),
('Work', '4343 Cherry St', 'Apt 95', 'Tampa', 'FL', 'United States', '33601'),
('Other', '8383 Spruce St', 'Floor 85', 'Spokane', 'WA', 'United States', '99201'),
('Work', '4444 Spruce St', 'Floor 35', 'Aurora', 'CO', 'United States', '80010'),
('Other', '8484 Willow St', 'Unit 210', 'Des Moines', 'IA', 'United States', '50301'),
('Work', '4545 Willow St', 'Unit 100', 'Anaheim', 'CA', 'United States', '92801'),
('Other', '8585 Poplar St', 'Apt 215', 'Tacoma', 'WA', 'United States', '98401'),
('Work', '4646 Poplar St', 'Suite 1200', 'Honolulu', 'HI', 'United States', '96801'),
('Other', '8686 Ash St', 'Suite 2200', 'San Bernardino', 'CA', 'United States', '92401'),
('Work', '4747 Ash St', 'Apt 105', 'Santa Ana', 'CA', 'United States', '92701'),
('Other', '8787 Birch St', 'Floor 90', 'Modesto', 'CA', 'United States', '95350'),
('Work', '4848 Birch St', 'Floor 40', 'Riverside', 'CA', 'United States', '92501'),
('Other', '8888 Cedar St', 'Unit 220', 'Fontana', 'CA', 'United States', '92335'),
('Work', '4949 Cedar St', 'Unit 110', 'Corpus Christi', 'TX', 'United States', '78401'),
('Other', '8989 Elm St', 'Apt 225', 'Santa Clarita', 'CA', 'United States', '91350'),
('Work', '5050 Elm St', 'Suite 1300', 'Lexington', 'KY', 'United States', '40501'),
('Other', '9090 Oak St', 'Suite 2300', 'Fayetteville', 'NC', 'United States', '28301'),
('Home', '6161 Birch St', 'Apt 20', 'Irvine', 'CA', 'United States', '92602'),
('Other', '11111 Poplar St', 'Floor 120', 'Overland Park', 'KS', 'United States', '66204'),
('Home', '6262 Cedar St', 'Suite 1500', 'Newark', 'NJ', 'United States', '07101'),
('Other', '11212 Ash St', 'Unit 280', 'Knoxville', 'TN', 'United States', '37901'),
('Home', '6363 Elm St', 'Floor 60', 'Durham', 'NC', 'United States', '27701'),
('Other', '11313 Birch St', 'Apt 285', 'Vancouver', 'WA', 'United States', '98660'),
('Home', '6464 Oak St', 'Unit 160', 'Chula Vista', 'CA', 'United States', '91909'),
('Other', '11414 Cedar St', 'Suite 2900', 'Providence', 'RI', 'United States', '02901'),
('Home', '6565 Pine St', 'Apt 165', 'Toledo', 'OH', 'United States', '43601'),
('Other', '11515 Elm St', 'Floor 125', 'Brownsville', 'TX', 'United States', '78520'),
('Home', '6666 Maple St', 'Suite 1700', 'Fort Wayne', 'IN', 'United States', '46801'),
('Other', '11616 Oak St', 'Unit 290', 'Newport News', 'VA', 'United States', '23601'),
('Home', '6767 Cedar St', 'Floor 65', 'St. Petersburg', 'FL', 'United States', '33701'),
('Other', '11717 Pine St', 'Apt 295', 'Chattanooga', 'TN', 'United States', '37401'),
('Home', '6868 Walnut St', 'Unit 170', 'Laredo', 'TX', 'United States', '78040'),
('Other', '11818 Maple St', 'Suite 3000', 'Fort Lauderdale', 'FL', 'United States', '33301'),
('Home', '6969 Cherry St', 'Apt 175', 'Jersey City', 'NJ', 'United States', '07302'),
('Other', '11919 Cedar St', 'Floor 130', 'Tempe', 'AZ', 'United States', '85281'),
('Home', '7070 Spruce St', 'Suite 1800', 'Chandler', 'AZ', 'United States', '85224'),
('Other', '12020 Walnut St', 'Unit 300', 'Santa Rosa', 'CA', 'United States', '95401'),
('Work', '7171 Willow St', 'Floor 70', 'Madison', 'WI', 'United States', '53701'),
('Home', '9191 Pine St', 'Floor 95', 'Birmingham', 'AL', 'United States', '35201'),
('Work', '7272 Poplar St', 'Unit 180', 'Lubbock', 'TX', 'United States', '79401'),
('Home', '9292 Maple St', 'Unit 230', 'Oxnard', 'CA', 'United States', '93030'),
('Work', '7373 Ash St', 'Apt 185', 'Scottsdale', 'AZ', 'United States', '85250'),
('Home', '9393 Cedar St', 'Apt 235', 'Aurora', 'IL', 'United States', '60502'),
('Work', '7474 Birch St', 'Suite 1900', 'Reno', 'NV', 'United States', '89501'),
('Home', '9494 Walnut St', 'Suite 2400', 'Moreno Valley', 'CA', 'United States', '92551'),
('Work', '7575 Cedar St', 'Floor 75', 'Buffalo', 'NY', 'United States', '14201'),
('Home', '9595 Cherry St', 'Floor 100', 'Rochester', 'NY', 'United States', '14602'),
('Work', '7676 Elm St', 'Unit 190', 'Gilbert', 'AZ', 'United States', '85233'),
('Home', '9696 Spruce St', 'Unit 240', 'Yonkers', 'NY', 'United States', '10701'),
('Work', '7777 Oak St', 'Apt 195', 'Glendale', 'AZ', 'United States', '85301'),
('Home', '9797 Willow St', 'Apt 245', 'Huntington Beach', 'CA', 'United States', '92647'),
('Work', '7878 Pine St', 'Suite 2000', 'North Las Vegas', 'NV', 'United States', '89030'),
('Home', '9898 Poplar St', 'Suite 2500', 'Montgomery', 'AL', 'United States', '36101'),
('Work', '7979 Maple St', 'Floor 80', 'Fremont', 'CA', 'United States', '94536'),
('Home', '9999 Ash St', 'Floor 105', 'Little Rock', 'AR', 'United States', '72201'),
('Work', '8080 Cedar St', 'Unit 200', 'Boise', 'ID', 'United States', '83701'),
('Home', '10000 Birch St', 'Unit 250', 'Akron', 'OH', 'United States', '44301'),
('Work', '10101 Cedar St', 'Apt 255', 'Augusta', 'GA', 'United States', '30901'),
('Work', '10202 Elm St', 'Suite 2600', 'Shreveport', 'LA', 'United States', '71101'),
('Work', '10303 Oak St', 'Floor 110', 'Grand Rapids', 'MI', 'United States', '49501'),
('Work', '10404 Pine St', 'Unit 260', 'Huntsville', 'AL', 'United States', '35801'),
('Work', '10505 Maple St', 'Apt 265', 'Salt Lake City', 'UT', 'United States', '84101'),
('Work', '10606 Cedar St', 'Suite 2700', 'Tallahassee', 'FL', 'United States', '32301'),
('Work', '10707 Walnut St', 'Floor 115', 'Amarillo', 'TX', 'United States', '79101'),
('Work', '10808 Cherry St', 'Unit 270', 'Glendale', 'CA', 'United States', '91201'),
('Work', '10909 Spruce St', 'Apt 275', 'Mobile', 'AL', 'United States', '36601'),
('Work', '11010 Willow St', 'Suite 2800', 'Grand Prairie', 'TX', 'United States', '75050'),
('Home', '1212 Laurel St', 'Apt 3C', 'Columbus', 'OH', 'United States', '43201'),
('Work', '2525 Magnolia St', 'Suite 300', 'Charlotte', 'NC', 'United States', '28201'),
('Other', '3434 Hazel St', 'Unit 15', 'Jacksonville', 'FL', 'United States', '32201'),
('Home', '4545 Ivy St', 'Floor 4', 'Anchorage', 'AK', 'United States', '99501'),
('Work', '5656 Juniper St', 'Apt 22', 'Burlington', 'VT', 'United States', '05401'),
('Other', '6767 Linden St', 'Suite 500', 'Bridgeport', 'CT', 'United States', '06601'),
('Home', '7878 Olive St', 'Unit 7', 'Salem', 'OR', 'United States', '97301'),
('Work', '8989 Palm St', 'Floor 10', 'Billings', 'MT', 'United States', '59101'),
('Other', '9090 Rose St', 'Apt 33', 'Sioux Falls', 'SD', 'United States', '57101'),
('Home', '10101 Sage St', 'Suite 600', 'Fargo', 'ND', 'United States', '58102');

SELECT *
from address;

INSERT INTO user_address (user_id, address_id) VALUES
(1, 1), (1, 4), (2, 3), (2, 5), (3, 2), (4, 6), (4, 7), (5, 9), (5, 8), (5, 10),
(6, 11), (7, 12), (8, 13), (8, 14), (9, 15), (10, 16), (10, 17), (11, 18), (12, 19),
(13, 20), (13, 21), (14, 22), (15, 23), (16, 24), (16, 25), (17, 26), (18, 27),
(19, 28), (19, 29), (20, 30), (21, 31), (21, 32), (22, 33), (23, 34), (24, 35),
(24, 36), (25, 37), (26, 38), (27, 39), (27, 40), (28, 41), (29, 42), (30, 43),
(30, 44), (31, 45), (32, 46), (33, 47), (33, 48), (34, 49), (35, 50), (36, 51),
(36, 52), (37, 53), (38, 54), (39, 55), (39, 56), (40, 57), (41, 58), (42, 59),
(42, 60), (43, 61), (44, 62), (45, 63), (45, 64), (46, 65), (47, 66), (48, 67),
(48, 68), (49, 69), (50, 70), (51, 71), (51, 72), (52, 73), (53, 74), (54, 75),
(54, 76), (55, 77), (56, 78), (57, 79), (57, 80), (58, 81), (59, 82), (60, 83),
(60, 84), (61, 85), (62, 86), (63, 87), (63, 88), (64, 89), (65, 90), (66, 91),
(66, 92), (67, 93), (68, 94), (69, 95), (69, 96), (70, 97), (71, 98), (72, 99),
(72, 100), (73, 101), (74, 102), (75, 103), (75, 104), (76, 105), (77, 106), (78, 107), (78, 108),
(79, 109), (80, 110), (81, 111), (81, 112), (82, 113), (83, 114), (84, 115), (84, 116),
(85, 117), (86, 118), (87, 119), (87, 120), (88, 21), (89, 22), (90, 23), (90, 24),
(91, 25), (92, 26), (93, 27), (93, 28), (94, 29), (95, 30), (96, 31), (96, 32),
(97, 33), (98, 34), (99, 35), (99, 36), (100, 37),
(101, 121),         
(102, 122), (102, 123), 
(103, 124),          
(104, 125), (104, 126), 
(105, 127),        
(106, 128), (106, 129), 
(107, 130), (107, 123), 
(108, 122),          
(109, 123), (109, 125), 
(110, 127), (110, 129), 
(111, 130),          
(112, 125), (112, 126);

SELECT *
from user_address;

SELECT u.user_id, a.address_type
from user_address u
JOIN address a ON a.address_id=u.address_id
WHERE address_type="other"
ORDER BY user_id;

SELECT u.user_id, u.username, u.email, a.address_type, a.address_line1, a.city, a.state, a.country, a.zip
FROM users u
JOIN user_address ua ON u.user_id = ua.user_id
JOIN address a ON ua.address_id = a.address_id
ORDER BY u.user_id;

INSERT INTO shipping_method (name, price) VALUES
('Regular', 3.99),
('Fast', 5.99),
('Express', 7.99);

select * 
from shipping_method;

INSERT INTO payment_method (payment_type, provider, card_number, expiry_date, ccv, billing_address_id) VALUES
('Credit Card', 'Visa', '4111111111111111', '12/31', '123', 1),
('Debit Card', 'Mastercard', '5555555555554444', '11/31', '456', 3),
('Credit Card', 'Discover', '6011111111111117', '10/31', '789', 2),
('Debit Card', 'American Express', '378282246310005', '09/31', '321', 6),
('Credit Card', 'Visa', '4111111111111112', '08/31', '654', 8),
('Debit Card', 'Mastercard', '5555555555554446', '07/31', '987', 11),
('Credit Card', 'Discover', '6011111111111118', '06/31', '234', 12),
('Debit Card', 'American Express', '378282246310006', '05/31', '567', 13),
('Credit Card', 'Visa', '4111111111111113', '04/31', '890', 15),
('Debit Card', 'Mastercard', '5555555555554448', '03/31', '123', 16),
('Credit Card', 'Discover', '6011111111111119', '12/31', '124', 18),
('Debit Card', 'American Express', '378282246310007', '11/31', '457', 19),
('Credit Card', 'Visa', '5555555555554450', '10/31', '790', 20),
('Debit Card', 'Mastercard', '4012888888881883', '09/31', '322', 22),
('Credit Card', 'Discover', '6011111111111120', '08/31', '655', 23),
('Debit Card', 'American Express', '378282246310008', '07/31', '988', 24),
('Credit Card', 'Visa', '4012888888881884', '06/31', '235', 26),
('Debit Card', 'Mastercard', '5555555555554452', '05/31', '568', 27),
('Credit Card', 'Discover', '6011111111111121', '04/31', '891', 28),
('Debit Card', 'American Express', '378282246310009', '03/31', '124', 30),
('Credit Card', 'Visa', '4111111111111117', '12/31', '125', 31),
('Debit Card', 'Mastercard', '5555555555554454', '11/31', '458', 33),
('Credit Card', 'Discover', '6011111111111122', '10/31', '791', 34),
('Debit Card', 'American Express', '378282246310010', '09/31', '323', 35),
('Credit Card', 'Visa', '4111111111111118', '08/31', '656', 37),
('Credit Card', 'Discover', '6011111111111123', '12/31', '126', 38),
('Debit Card', 'Mastercard', '5555555555554456', '11/31', '459', 39),
('Credit Card', 'Visa', '5555555555554457', '10/31', '792', 41),
('Debit Card', 'American Express', '4012888888881886', '09/31', '324', 42),
('Credit Card', 'Discover', '6011111111111124', '08/31', '657', 43),
('Debit Card', 'Mastercard', '5555555555554458', '07/31', '989', 45),
('Credit Card', 'Visa', '4012888888881887', '06/31', '236', 46),
('Debit Card', 'American Express', '5555555555554459', '05/31', '569', 47),
('Credit Card', 'Discover', '6011111111111125', '04/31', '892', 49),
('Debit Card', 'Mastercard', '5555555555554460', '03/31', '125', 50),
('Credit Card', 'Visa', '4012888888881888', '12/31', '237', 51),
('Credit Card', 'Discover', '6011111111111126', '12/31', '127', 53),
('Debit Card', 'American Express', '5555555555554461', '11/31', '460', 54),
('Credit Card', 'Visa', '5555555555554462', '10/31', '793', 55),
('Debit Card', 'Mastercard', '4012888888881889', '09/31', '325', 57),
('Credit Card', 'Discover', '6011111111111127', '08/31', '658', 58),
('Debit Card', 'American Express', '5555555555554463', '07/31', '990', 59),
('Credit Card', 'Visa', '4012888888881890', '06/31', '238', 61),
('Debit Card', 'Mastercard', '5555555555554464', '05/31', '570', 62),
('Credit Card', 'Discover', '6011111111111128', '04/31', '893', 63),
('Credit Card', 'Visa', '4111111111111125', '12/31', '128', 65),
('Debit Card', 'American Express', '5555555555554465', '11/31', '461', 66),
('Credit Card', 'Discover', '6011111111111129', '10/31', '794', 67),
('Debit Card', 'Mastercard', '4012888888881891', '09/31', '326', 69),
('Credit Card', 'Visa', '4111111111111126', '08/31', '659', 70),
('Debit Card', 'American Express', '5555555555554467', '07/31', '991', 71),
('Credit Card', 'Discover', '6011111111111130', '06/31', '239', 73),
('Debit Card', 'Mastercard', '5555555555554468', '05/31', '571', 74),
('Credit Card', 'Visa', '4111111111111127', '04/31', '894', 75),
('Debit Card', 'American Express', '5555555555554469', '03/31', '126', 77),
('Credit Card', 'Discover', '6011111111111131', '12/31', '240', 78),
('Credit Card', 'Visa', '4111111111111128', '12/31', '129', 79),
('Debit Card', 'Mastercard', '5555555555554470', '11/31', '462', 81),
('Credit Card', 'Discover', '6011111111111132', '10/31', '795', 82),
('Debit Card', 'American Express', '4012888888881894', '09/31', '327', 83),
('Credit Card', 'Visa', '4111111111111129', '08/31', '660', 85),
('Debit Card', 'Mastercard', '5555555555554472', '07/31', '992', 86),
('Credit Card', 'Discover', '6011111111111133', '06/31', '241', 87),
('Debit Card', 'American Express', '5555555555554473', '05/31', '572', 89),
('Credit Card', 'Visa', '4111111111111130', '04/31', '895', 90),
('Credit Card', 'Discover', '6011111111111134', '12/31', '130', 91),
('Debit Card', 'Mastercard', '5555555555554474', '11/31', '463', 93),
('Credit Card', 'Visa', '5555555555554475', '10/31', '796', 94),
('Debit Card', 'American Express', '4012888888881896', '09/31', '328', 95),
('Credit Card', 'Discover', '6011111111111135', '08/31', '661', 97),
('Debit Card', 'Mastercard', '5555555555554476', '07/31', '993', 98),
('Credit Card', 'Visa', '4012888888881897', '06/31', '242', 99),
('Debit Card', 'American Express', '5555555555554477', '05/31', '573', 101),
('Credit Card', 'Discover', '6011111111111136', '04/31', '896', 102),
('Debit Card', 'Mastercard', '5555555555554478', '03/31', '127', 103),
('Credit Card', 'Visa', '4012888888881898', '12/31', '243', 104),
('Credit Card', 'Discover', '6011111111111137', '12/31', '131', 106),
('Debit Card', 'American Express', '5555555555554479', '11/31', '464', 107),
('Credit Card', 'Visa', '5555555555554480', '10/31', '797', 109),
('Debit Card', 'Mastercard', '4012888888881899', '09/31', '329', 110),
('Credit Card', 'Discover', '6011111111111138', '08/31', '662', 111),
('Debit Card', 'American Express', '5555555555554481', '07/31', '994', 113),
('Credit Card', 'Visa', '4012888888881900', '06/31', '244', 114),
('Debit Card', 'Mastercard', '5555555555554482', '05/31', '574', 115),
('Credit Card', 'Discover', '6011111111111139', '04/31', '897', 117),
('Credit Card', 'Visa', '4111111111111137', '12/31', '132', 118),
('Debit Card', 'American Express', '5555555555554483', '11/31', '465', 119),
('Credit Card', 'Discover', '6011111111111140', '10/31', '798', 21),
('Debit Card', 'Mastercard', '4012888888881901', '09/31', '330', 22),
('Credit Card', 'Visa', '4111111111111138', '08/31', '663', 23),
('Debit Card', 'American Express', '5555555555554485', '07/31', '995', 25),
('Credit Card', 'Discover', '6011111111111141', '06/31', '245', 26),
('Debit Card', 'Mastercard', '5555555555554486', '05/31', '575', 27),
('Credit Card', 'Visa', '4111111111111139', '04/31', '898', 29),
('Debit Card', 'American Express', '5555555555554487', '03/31', '128', 30),
('Credit Card', 'Discover', '6011111111111142', '12/31', '246', 31),
('Credit Card', 'Visa', '4111111111111140', '12/31', '133', 33),
('Debit Card', 'Mastercard', '5555555555554488', '11/31', '466', 34),
('Credit Card', 'Discover', '6011111111111143', '10/31', '799', 35),
('Debit Card', 'American Express', '4012888888881904', '09/31', '331', 37),
('Credit Card', 'Mastercard', '5555555555554489', '12/32', '901', 21),  -- Users 88, 13
('Debit Card', 'Discover', '6011111111111144', '12/32', '902', 23),    -- Users 90, 15
('Credit Card', 'American Express', '378282246310011', '12/32', '903', 24), -- Users 90, 16
('Debit Card', 'Visa', '4111111111111157', '12/32', '904', 25),         -- Users 91, 17
('Credit Card', 'Mastercard', '5555555555554490', '12/32', '905', 26),  -- Users 92, 17
('Debit Card', 'Discover', '6011111111111145', '12/32', '906', 27),    -- Users 93, 18
('Credit Card', 'American Express', '378282246310012', '12/32', '907', 28), -- Users 93, 19
('Debit Card', 'Visa', '4111111111111158', '12/32', '908', 29),         -- Users 94, 19
('Credit Card', 'Mastercard', '5555555555554491', '12/32', '909', 30),  -- Users 95, 20
('Debit Card', 'Discover', '6011111111111146', '12/32', '910', 31),    -- Users 96, 21
('Credit Card', 'Visa', '4111111111111159', '12/32', '911', 32),        -- Users 96, 21
('Debit Card', 'Mastercard', '5555555555554492', '12/32', '912', 33),   -- Users 97, 22
('Credit Card', 'American Express', '378282246310013', '12/32', '913', 34), -- Users 98, 23
('Debit Card', 'Discover', '6011111111111147', '12/32', '914', 35),    -- Users 99, 24
('Credit Card', 'Visa', '4111111111111160', '12/32', '915', 36),
('Credit Card', 'Visa', '4111111111111141', '12/32', '999', 22),

('Credit Card', 'Visa', '4222222222222221', '03/27', '201', 121),        -- User 101: Leo Hunter
('Debit Card', 'Mastercard', '5444444444444441', '02/27', '202', 122),   -- User 102: Clara Fox
('Credit Card', 'Discover', '6222222222222221', '01/27', '203', 124),    -- User 103: Ethan Blake
('Debit Card', 'American Express', '388888888888881', '12/26', '204', 125), -- User 104: Isabella Pearl
('Credit Card', 'Visa', '4222222222222222', '11/26', '205', 127),        -- User 105: Mason Rivers
('Debit Card', 'Mastercard', '5444444444444442', '10/26', '206', 128),   -- User 106: Zoe Storm
('Credit Card', 'Discover', '6222222222222222', '09/26', '207', 130),    -- User 107: Lily Fern
('Debit Card', 'American Express', '388888888888882', '08/26', '208', 122), -- User 108: Owen Clay
('Credit Card', 'Visa', '4222222222222223', '07/26', '209', 123),        -- User 109: Ava Snow
('Debit Card', 'Mastercard', '5444444444444443', '06/26', '210', 127),   -- User 110: Jaxon Leaf
('Credit Card', 'Discover', '6222222222222223', '05/26', '211', 130),    -- User 111: Mia Rose
('Debit Card', 'American Express', '388888888888883', '04/26', '212', 125);

SELECT * 
from orders
where user_id=3;


INSERT INTO users_payment_method (user_id, payment_method_id) VALUES
(1, 1),
(2, 2),
(3, 3),
(4, 4),
(5, 5),
(6, 6),
(7, 7),
(8, 8),
(9, 9),
(10, 10),
(11, 11),
(12, 12),
(13, 13),
(14, 14),
(15, 15),
(16, 16),
(17, 17),
(18, 18),
(19, 19),
(20, 20),
(21, 21),
(22, 22),
(23, 23),
(24, 24),
(25, 25),
(26, 26),
(27, 27),
(28, 28),
(29, 29),
(30, 30),
(31, 31),
(32, 32),
(33, 33),
(34, 34),
(35, 35),
(36, 36),
(37, 37),
(38, 38),
(39, 39),
(40, 40),
(41, 41),
(42, 42),
(43, 43),
(44, 44),
(45, 45),
(46, 46),
(47, 47),
(48, 48),
(49, 49),
(50, 50),
(51, 51),
(52, 52),
(53, 53),
(54, 54),
(55, 55),
(56, 56),
(57, 57),
(58, 58),
(59, 59),
(60, 60),
(61, 61),
(62, 62),
(63, 63),
(64, 64),
(65, 65),
(66, 66),
(67, 67),
(68, 68),
(69, 69),
(70, 70),
(71, 71),
(72, 72),
(73, 73),
(74, 74),
(75, 75),
(76, 76),
(77, 77),
(78, 78),
(79, 79),
(80, 80),
(81, 81),
(82, 82),
(83, 83),
(84, 84),
(85, 85),
(86, 86),
(87, 87),
(88, 88),
(89, 89),
(90, 90),
(91, 91),
(92, 92),
(93, 93),
(94, 94),
(95, 95),
(96, 96),
(97, 97),
(98, 98),
(99, 99),
(100, 100),
(88, 101), (13, 101),  -- Shared address_id 21
(14, 116), (89, 116),  -- Shared address_id 22 (already done)
(90, 102), (15, 102),  -- Shared address_id 23
(90, 103), (16, 103),  -- Shared address_id 24
(91,104),  (16,104),
(92, 105), (17, 105),  -- Shared address_id 26
(93, 106), (18, 106),  -- Shared address_id 27
(93, 107), (19, 107),  -- Shared address_id 28
(94, 108), (19, 108),  -- Shared address_id 29
(95, 109), (20, 109),  -- Shared address_id 30
(96, 110), (21, 110),  -- Shared address_id 31
(97, 112), (22, 112),  -- Shared address_id 33
(98, 113), (23, 113),  -- Shared address_id 34
(99, 114), (24, 114),
(101,117),
(102,118),
(103,119),
(104,120),
(105,121),
(106,122),
(107,123),
(108,124),
(109,125),
(110,126),
(111,127),
(112,128);

select *
from users_payment_method;

-- Insert Spring Sale Coupons
INSERT INTO sale_coupon (coupon_code, coupon_name, coupon_desc, discount, start_date, expiry_date)
VALUES 
('SPR21', 'Spring Bloom 2021', 'Spring Sale 2021 Discount', 20, '2021-03-01', '2021-03-31'),
('WIN21', 'Winter Chill 2021', 'Winter Sale 2021 Discount', 15, '2021-12-01', '2021-12-31'),
('BF21', 'Black Friday Bonanza 2021', 'Black Friday 2021 Deal', 30, '2021-11-26', '2021-11-26'),
('SPR22', 'Spring Refresh 2022', 'Spring Sale 2022 Discount', 25, '2022-03-01', '2022-03-31'),
('WIN22', 'Winter Frost 2022', 'Winter Sale 2022 Discount', 20, '2022-12-01', '2022-12-31'),
('BF22', 'Black Friday Frenzy 2022', 'Black Friday 2022 Deal', 45, '2022-11-25', '2022-11-25'),
('SPR23', 'Spring Awakening 2023', 'Spring Sale 2023 Discount', 30, '2023-03-01', '2023-03-31'),
('WIN23', 'Winter Wonderland 2023', 'Winter Sale 2023 Discount', 25, '2023-12-01', '2023-12-31'),
('BF23', 'Black Friday Madness 2023', 'Black Friday 2023 Deal', 40, '2023-11-24', '2023-11-24'),
('SPR24', 'Spring Blossom 2024', 'Spring Sale 2024 Discount', 35, '2024-03-01', '2024-03-31'),
('WIN24', 'Winter Magic 2024', 'Winter Sale 2024 Discount', 30, '2024-12-01', '2024-12-31'),
('BF24', 'Black Friday Blowout 2024', 'Black Friday 2024 Deal', 50, '2024-11-29', '2024-11-29'); 

SELECT *
from sale_coupon;

INSERT INTO orders (user_id, order_date, shipping_address_id, payment_method_id, shipping_method_id, order_status, order_status_time_stamp, coupon_id)
VALUES
-- User 1: 5 orders (payment_method_id: 1 only)
(1, '2021-04-01 10:15:23', 1, 1, 1, 'Shipped', '2021-04-02 10:15:23', NULL),
(1, '2021-12-15 14:30:45', 4, 1, 2, 'Delivered', '2021-12-17 14:30:45', 2),
(1, '2023-11-24 08:00:00', 1, 1, 3, 'Delivered', '2023-11-26 08:00:00', 9),
(1, '2022-03-15 09:45:12', 4, 1, 1, 'Shipped', '2022-03-16 09:45:12', 4),
(1, '2024-03-01 11:20:23', 1, 1, 2, 'Pending', '2024-03-01 14:20:23', 10),

(2, '2022-08-10 09:22:11', 3, 2, 3, 'Delivered', '2022-08-12 09:22:11', NULL),
(2, '2022-12-01 15:45:32', 5, 2, 1, 'Delivered', '2022-12-03 15:45:32', 5),
(3, '2021-01-05 16:45:32', 2, 3, 1, 'Shipped', '2021-01-06 16:45:32', NULL),
(3, '2020-12-15 10:30:43', 2, 3, 2, 'Delivered', '2020-12-17 10:30:43', NULL),
(4, '2023-11-24 08:00:00', 6, 4, 3, 'Delivered', '2023-11-26 08:00:00', 9),
(4, '2023-03-15 12:10:19', 7, 4, 2, 'Returned', '2023-03-19 12:10:19', 7),

-- User 5: 5 orders (payment_method_id: 5 only)
(5, '2024-03-15 12:10:19', 9, 5, 2, 'Pending', '2024-03-15 15:10:19', 10),
(5, '2024-11-29 09:30:00', 10, 5, 3, 'Delivered', '2024-12-01 09:30:00', 12),
(5, '2024-12-15 14:45:11', 8, 5, 1, 'Pending', '2024-12-15 17:45:11', 11),
(5, '2024-06-01 16:00:22', 9, 5, 2, 'Shipped', '2024-06-02 16:00:22', NULL),
(5, '2024-09-15 08:15:33', 10, 5, 3, 'Delivered', '2024-09-17 08:15:33', NULL),

(6, '2022-01-20 17:55:43', 11, 6, 1, 'Cancelled', '2022-01-21 03:55:43', NULL),
(6, '2021-10-01 14:20:54', 11, 6, 2, 'Shipped', '2021-10-02 14:20:54', NULL),
(7, '2023-03-10 13:25:56', 12, 7, 2, 'Shipped', '2023-03-11 13:25:56', 7),
(7, '2023-12-15 15:40:38', 12, 7, 1, 'Delivered', '2023-12-17 15:40:38', 8),
(8, '2021-07-01 11:33:27', 13, 8, 3, 'Delivered', '2021-07-03 11:33:27', NULL),
(8, '2020-07-01 09:15:48', 14, 8, 1, 'Shipped', '2020-07-02 09:15:48', NULL),

(9, '2023-12-05 15:40:38', 15, 9, 1, 'Shipped', '2023-12-06 15:40:38', 8),
(10, '2021-03-15 09:12:49', 16, 10, 2, 'Delivered', '2021-03-17 09:12:49', 1),
(10, '2021-12-01 14:25:59', 17, 10, 3, 'Shipped', '2021-12-02 14:25:59', 2),
(10, '2022-11-25 10:30:00', 16, 10, 1, 'Delivered', '2022-11-27 10:30:00', 6),
(10, '2023-03-01 12:45:11', 17, 10, 2, 'Shipped', '2023-03-02 12:45:11', 7),
(10, '2023-11-24 08:15:22', 16, 10, 3, 'Delivered', '2023-11-26 08:15:22', 9),

(11, '2024-03-20 14:20:15', 18, 11, 3, 'Pending', '2024-03-20 17:20:15', 10),
(11, '2024-12-01 16:35:06', 18, 11, 1, 'Pending', '2024-12-01 19:35:06', 11),
(12, '2022-11-25 07:30:00', 19, 12, 1, 'Delivered', '2022-11-27 07:30:00', 6),
(12, '2022-03-10 10:55:11', 19, 12, 2, 'Shipped', '2022-03-11 10:55:11', 4),
(13, '2020-05-01 18:45:22', 20, 13, 2, 'Delivered', '2020-05-03 18:45:22', NULL),
(14, '2023-07-15 10:10:33', 22, 14, 3, 'Delivered', '2023-07-17 10:10:33', NULL),
(14, '2023-11-24 11:00:00', 22, 14, 1, 'Delivered', '2023-11-26 11:00:00', 9),
(15, '2022-03-20 12:55:44', 23, 15, 1, 'Returned', '2022-03-24 12:55:44', 4),
(16, '2024-07-05 16:30:57', 24, 16, 2, 'Pending', '2024-07-05 19:30:57', NULL),
(16, '2024-12-15 13:45:08', 25, 16, 3, 'Pending', '2024-12-15 16:45:08', 11),
(17, '2020-09-01 08:25:11', 26, 17, 3, 'Delivered', '2020-09-03 08:25:11', NULL),
(18, '2022-04-10 14:15:28', 27, 18, 1, 'Delivered', '2022-04-12 14:15:28', NULL),
(18, '2022-12-01 09:30:39', 27, 18, 2, 'Returned', '2022-12-05 09:30:39', 5),
(19, '2023-11-24 09:00:00', 28, 19, 2, 'Delivered', '2023-11-26 09:00:00', 9),
(19, '2023-03-01 15:20:19', 29, 19, 1, 'Shipped', '2023-03-02 15:20:19', 7),
(20, '2021-06-01 11:40:39', 30, 20, 3, 'Delivered', '2021-06-03 11:40:39', NULL),
(21, '2024-03-25 13:50:50', 31, 21, 1, 'Pending', '2024-03-25 16:50:50', 10),
(21, '2024-11-29 10:05:01', 32, 21, 2, 'Delivered', '2024-12-01 10:05:01', 12),
(22, '2020-10-15 15:20:01', 33, 22, 2, 'Delivered', '2020-10-17 15:20:01', NULL),
(23, '2022-02-01 09:35:12', 34, 23, 3, 'Returned', '2022-02-06 09:35:12', NULL),
(23, '2022-11-25 10:30:00', 34, 23, 1, 'Delivered', '2022-11-27 10:30:00', 6),
(24, '2023-05-10 17:10:23', 35, 24, 1, 'Delivered', '2023-05-12 17:10:23', NULL),
(24, '2023-11-24 12:15:34', 36, 24, 2, 'Delivered', '2023-11-26 12:15:34', 9),

-- User 25: 4 orders (payment_method_id: 25 only)
(25, '2021-09-01 12:25:34', 37, 25, 2, 'Shipped', '2021-09-02 12:25:34', NULL),
(25, '2021-12-01 14:40:45', 37, 25, 1, 'Delivered', '2021-12-03 14:40:45', 2),
(25, '2022-03-15 09:55:56', 37, 25, 3, 'Shipped', '2022-03-16 09:55:56', 4),
(25, '2023-11-24 11:00:07', 37, 25, 2, 'Delivered', '2023-11-26 11:00:07', 9),

(26, '2024-12-10 14:40:45', 38, 26, 3, 'Returned', '2024-12-15 14:40:45', 11),
(26, '2024-03-15 09:55:56', 38, 26, 1, 'Shipped', '2024-03-16 09:55:56', 10),
(27, '2021-01-15 10:55:56', 39, 27, 1, 'Delivered', '2021-01-17 10:55:56', NULL),
(27, '2020-12-31 16:00:07', 40, 27, 2, 'Shipped', '2021-01-01 16:00:07', NULL),
(28, '2022-07-01 16:05:07', 41, 28, 2, 'Shipped', '2022-07-02 16:05:07', NULL),
(29, '2023-11-24 10:00:00', 42, 29, 3, 'Delivered', '2023-11-26 10:00:00', 9),
(29, '2023-03-01 08:15:18', 42, 29, 1, 'Shipped', '2023-03-02 08:15:18', 7),
(30, '2021-02-01 08:15:18', 43, 30, 1, 'Shipped', '2021-02-02 08:15:18', NULL),
(30, '2021-03-15 14:30:29', 44, 30, 2, 'Delivered', '2021-03-17 14:30:29', 1),
(31, '2024-03-01 11:30:29', 45, 31, 2, 'Pending', '2024-03-01 14:30:29', 10),
(32, '2020-08-01 13:45:40', 46, 32, 3, 'Returned', '2020-08-06 13:45:40', NULL),
(33, '2022-03-15 15:00:51', 47, 33, 1, 'Shipped', '2022-03-16 15:00:51', 4),
(33, '2022-12-01 09:15:02', 48, 33, 2, 'Delivered', '2022-12-03 09:15:02', 5),
(34, '2023-10-15 09:10:02', 49, 34, 2, 'Delivered', '2023-10-17 09:10:02', NULL),
(35, '2021-05-01 17:25:13', 50, 35, 3, 'Shipped', '2021-05-02 17:25:13', NULL),
(35, '2021-12-15 12:40:24', 50, 35, 1, 'Delivered', '2021-12-17 12:40:24', 2),
(36, '2024-08-01 12:40:24', 51, 36, 1, 'Cancelled', '2024-08-01 22:40:24', NULL),
(36, '2024-11-29 14:55:35', 52, 36, 2, 'Delivered', '2024-12-01 14:55:35', 12),
(37, '2020-04-01 14:55:35', 53, 37, 2, 'Delivered', '2020-04-03 14:55:35', NULL),
(38, '2022-09-01 16:10:46', 54, 38, 3, 'Returned', '2022-09-06 16:10:46', NULL),
(39, '2023-12-15 08:25:57', 55, 39, 1, 'Delivered', '2023-12-17 08:25:57', 8),
(39, '2023-03-01 10:40:08', 56, 39, 2, 'Shipped', '2023-03-02 10:40:08', 7),
(40, '2021-07-15 10:40:08', 57, 40, 2, 'Shipped', '2021-07-16 10:40:08', NULL),
(41, '2024-09-15 13:55:19', 58, 41, 3, 'Pending', '2024-09-15 16:55:19', NULL),
(42, '2020-06-01 15:05:30', 59, 42, 1, 'Delivered', '2020-06-03 15:05:30', NULL),
(42, '2020-05-15 09:20:41', 60, 42, 2, 'Shipped', '2020-05-16 09:20:41', NULL),
(43, '2022-11-25 11:00:00', 61, 43, 2, 'Returned', '2022-11-30 11:00:00', 6),
(44, '2023-03-01 09:15:41', 62, 44, 3, 'Delivered', '2023-03-03 09:15:41', 7),
(45, '2021-08-01 17:30:52', 63, 45, 1, 'Shipped', '2021-08-02 17:30:52', NULL),
(45, '2021-12-01 12:45:03', 64, 45, 2, 'Delivered', '2021-12-03 12:45:03', 2),

(46, '2024-08-15 12:45:03', 65, 46, 2, 'Pending', '2024-08-15 15:45:03', NULL),
(47, '2020-11-01 14:00:14', 66, 47, 3, 'Delivered', '2020-11-03 14:00:14', NULL),
(48, '2022-04-15 16:15:25', 67, 48, 1, 'Returned', '2022-04-20 16:15:25', 4),
(48, '2022-11-25 13:30:36', 68, 48, 2, 'Delivered', '2022-11-27 13:30:36', 6),
(49, '2023-06-15 08:30:36', 69, 49, 2, 'Delivered', '2023-06-17 08:30:36', NULL),
(50, '2021-10-01 10:45:47', 70, 50, 3, 'Cancelled', '2021-10-01 20:45:47', NULL),
(50, '2021-12-15 13:00:58', 70, 50, 1, 'Delivered', '2021-12-17 13:00:58', 2),
(50, '2022-03-15 15:15:09', 70, 50, 2, 'Shipped', '2022-03-16 15:15:09', 4),
(50, '2023-11-24 09:30:20', 70, 50, 3, 'Delivered', '2023-11-26 09:30:20', 9),
(50, '2024-03-01 11:45:31', 70, 50, 1, 'Pending', '2024-03-01 14:45:31', 10),

(51, '2024-10-15 15:15:09', 71, 51, 2, 'Pending', '2024-10-15 18:15:09', NULL),
(52, '2020-03-01 09:30:20', 73, 52, 1, 'Delivered', '2020-03-03 09:30:20', NULL),
(53, '2022-06-01 11:45:31', 74, 53, 3, 'Shipped', '2022-06-02 11:45:31', NULL),
(54, '2023-01-15 14:00:42', 75, 54, 2, 'Delivered', '2023-01-17 14:00:42', NULL),
(55, '2021-03-15 16:15:53', 77, 55, 1, 'Returned', '2021-03-20 16:15:53', 1),
(56, '2024-11-29 08:30:04', 78, 56, 3, 'Delivered', '2024-12-01 08:30:04', 12),
(57, '2020-08-15 10:45:15', 79, 57, 2, 'Cancelled', '2020-08-16 10:45:15', NULL),
(58, '2022-10-15 13:00:26', 81, 58, 1, 'Delivered', '2022-10-17 13:00:26', NULL),
(59, '2023-04-01 15:15:37', 82, 59, 3, 'Shipped', '2023-04-02 15:15:37', NULL),
(60, '2024-12-25 11:30:00', 83, 60, 2, 'Returned', '2024-12-30 11:30:00', 11),
(60, '2024-11-29 09:45:48', 84, 60, 1, 'Delivered', '2024-12-01 09:45:48', 12),
(61, '2020-01-15 08:00:59', 85, 61, 2, 'Shipped', '2020-01-16 08:00:59', NULL),
(62, '2022-08-01 10:15:10', 86, 62, 1, 'Delivered', '2022-08-03 10:15:10', NULL),
(63, '2023-04-15 12:30:21', 87, 63, 3, 'Returned', '2023-04-20 12:30:21', NULL),
(64, '2021-12-01 14:45:32', 89, 64, 2, 'Delivered', '2021-12-03 14:45:32', 2),
(65, '2024-06-15 16:00:43', 90, 65, 1, 'Pending', '2024-06-15 19:00:43', NULL),
(66, '2020-12-15 09:15:54', 91, 66, 3, 'Cancelled', '2020-12-15 19:15:54', NULL),
(67, '2022-04-01 11:30:05', 93, 67, 2, 'Delivered', '2022-04-03 11:30:05', NULL),
(68, '2023-08-15 13:45:16', 94, 68, 1, 'Returned', '2023-08-20 13:45:16', NULL),
(69, '2021-03-01 15:00:27', 95, 69, 3, 'Delivered', '2021-03-03 15:00:27', 1),
(70, '2023-03-15 09:45:21', 97, 70, 1, 'Shipped', '2023-03-16 09:45:21', 7),
(71, '2024-05-15 12:00:38', 98, 71, 2, 'Pending', '2024-05-15 15:00:38', NULL),
(72, '2020-05-01 14:15:49', 99, 72, 1, 'Delivered', '2020-05-03 14:15:49', NULL),
(73, '2022-11-01 16:30:00', 101, 73, 3, 'Delivered', '2022-11-03 16:30:00', NULL),
(74, '2023-08-01 08:45:11', 102, 74, 2, 'Delivered', '2023-08-03 08:45:11', NULL),

-- User 75: 4 orders (payment_method_id: 75 only from users_payment_method)
(75, '2021-06-15 10:00:22', 103, 75, 1, 'Cancelled', '2021-06-15 20:00:22', NULL),
(75, '2021-12-01 12:15:33', 104, 75, 2, 'Delivered', '2021-12-03 12:15:33', 2),
(75, '2022-03-15 14:30:44', 103, 75, 3, 'Shipped', '2022-03-16 14:30:44', 4),
(75, '2023-11-24 16:45:55', 104, 75, 1, 'Delivered', '2023-11-26 16:45:55', 9),

(76, '2024-09-15 12:15:33', 105, 76, 3, 'Pending', '2024-09-15 15:15:33', NULL),
(77, '2020-07-01 14:30:44', 106, 77, 2, 'Delivered', '2020-07-03 14:30:44', NULL),
(78, '2022-02-01 16:45:55', 107, 78, 1, 'Shipped', '2022-02-02 16:45:55', NULL),
(79, '2023-12-15 09:00:06', 109, 79, 3, 'Delivered', '2023-12-17 09:00:06', 8),
(80, '2024-09-01 14:20:32', 110, 80, 3, 'Pending', '2024-09-01 17:20:32', NULL),
(81, '2021-09-01 16:35:43', 111, 81, 2, 'Cancelled', '2021-09-02 16:35:43', NULL),
(82, '2020-10-01 08:50:54', 113, 82, 1, 'Delivered', '2020-10-03 08:50:54', NULL),
(83, '2022-04-15 11:05:05', 114, 83, 3, 'Returned', '2022-04-20 11:05:05', NULL),
(84, '2023-12-01 13:20:16', 115, 84, 2, 'Delivered', '2023-12-03 13:20:16', 8),
(85, '2021-08-01 15:35:27', 117, 85, 1, 'Shipped', '2021-08-02 15:35:27', NULL),
(86, '2024-09-01 09:50:38', 118, 86, 3, 'Pending', '2024-09-01 12:50:38', NULL),
(87, '2020-04-01 12:05:49', 119, 87, 2, 'Delivered', '2020-04-03 12:05:49', NULL),
(88, '2022-07-01 14:20:00', 21, 88, 1, 'Cancelled', '2022-07-02 00:20:00', NULL),
(89, '2023-05-15 16:35:11', 22, 89, 3, 'Delivered', '2023-05-17 16:35:11', NULL),
(90, '2021-07-10 16:35:43', 23, 90, 2, 'Shipped', '2021-07-11 16:35:43', NULL),

(91, '2024-03-15 08:50:54', 25, 91, 1, 'Pending', '2024-03-15 11:50:54', 10),
(92, '2020-08-01 11:05:05', 26, 92, 3, 'Delivered', '2020-08-03 11:05:05', NULL),
(93, '2022-03-01 13:20:16', 27, 93, 2, 'Shipped', '2022-03-02 13:20:16', 4),
(94, '2023-11-01 15:35:27', 29, 94, 1, 'Delivered', '2023-11-03 15:35:27', NULL),
(95, '2021-05-15 09:50:38', 30, 95, 3, 'Cancelled', '2021-05-15 19:50:38', NULL),
(96, '2024-07-15 12:05:49', 31, 96, 2, 'Returned', '2024-07-20 12:05:49', NULL),
(97, '2020-06-01 14:20:00', 33, 97, 1, 'Delivered', '2020-06-03 14:20:00', NULL),
(98, '2022-09-01 16:35:11', 34, 98, 3, 'Delivered', '2022-09-03 16:35:11', NULL),
(99, '2023-12-15 08:50:54', 35, 99, 2, 'Delivered', '2023-12-17 08:50:54', 8),
(100, '2021-06-20 08:50:54', 37, 100, 1, 'Shipped', '2021-06-21 08:50:54', NULL),
(100, '2021-12-01 11:05:05', 37, 100, 2, 'Delivered', '2021-12-03 11:05:05', 2),
(100, '2022-03-15 13:20:16', 37, 100, 3, 'Delivered', '2022-03-17 13:20:16', 4),
(100, '2023-11-24 15:35:27', 37, 100, 1, 'Delivered', '2023-11-26 15:35:27', 9),
(100, '2024-03-01 09:50:38', 37, 100, 2, 'Pending', '2024-03-01 12:50:38', 10),
(101, '2025-01-04 10:30:00', 121, 117, 1, 'Delivered', '2025-01-06 10:30:00', NULL),  -- Regular shipping, Delivered: +2 days
(101, '2025-01-05 14:00:00', 121, 117, 2, 'Pending', '2025-01-05 17:30:00', NULL),    -- Fast shipping, Pending: +3.5 hrs
(102, '2025-01-13 09:15:00', 122, 118, 3, 'Shipped', '2025-01-14 09:15:00', NULL),     -- Express shipping, Shipped: +1 day
(102, '2025-01-14 16:00:00', 123, 118, 1, 'Returned', '2025-01-21 16:00:00', NULL),    -- Regular shipping, Returned: +7 days
(103, '2025-01-21 13:45:00', 124, 119, 2, 'Delivered', '2025-01-23 13:45:00', NULL),   -- Fast shipping, Delivered: +2 days
(103, '2025-01-22 08:30:00', 124, 119, 3, 'Cancelled', '2025-01-22 13:00:00', NULL),   -- Express shipping, Cancelled: +4.5 hrs
(104, '2025-01-29 11:00:00', 125, 120, 1, 'Shipped', '2025-01-30 11:00:00', NULL),     -- Regular shipping, Shipped: +1 day
(104, '2025-01-30 15:30:00', 126, 120, 2, 'Pending', '2025-01-30 19:00:00', NULL),     -- Fast shipping, Pending: +3.5 hrs
(105, '2025-01-06 12:15:00', 127, 121, 3, 'Delivered', '2025-01-08 12:15:00', NULL),   -- Express shipping, Delivered: +2 days
(105, '2025-01-07 09:00:00', 127, 121, 1, 'Returned', '2025-01-14 09:00:00', NULL),    -- Regular shipping, Returned: +7 days
(106, '2025-02-15 14:30:00', 128, 122, 2, 'Shipped', '2025-02-16 14:30:00', NULL),     -- Fast shipping, Shipped: +1 day
(106, '2025-02-16 10:45:00', 129, 122, 3, 'Cancelled', '2025-02-17 10:45:00', NULL),   -- Express shipping, Cancelled: +1 day
(107, '2025-02-20 16:00:00', 130, 123, 1, 'Delivered', '2025-02-22 16:00:00', NULL),   -- Regular shipping, Delivered: +2 days
(107, '2025-02-21 08:15:00', 123, 123, 2, 'Pending', '2025-02-21 11:45:00', NULL),     -- Fast shipping, Pending: +3.5 hrs
(108, '2025-02-28 13:00:00', 122, 124, 3, 'Shipped', '2025-03-01 13:00:00', NULL),     -- Express shipping, Shipped: +1 day
(108, '2025-03-01 09:30:00', 122, 124, 1, 'Returned', '2025-03-08 09:30:00', NULL),    -- Regular shipping, Returned: +7 days
(109, '2025-02-03 11:15:00', 123, 125, 2, 'Delivered', '2025-02-05 11:15:00', NULL),   -- Fast shipping, Delivered: +2 days
(109, '2025-02-04 14:45:00', 125, 125, 3, 'Cancelled', '2025-02-04 19:15:00', NULL),   -- Express shipping, Cancelled: +4.5 hrs
(110, '2025-03-11 10:00:00', 127, 126, 1, 'Shipped', '2025-03-12 10:00:00', NULL),     -- Regular shipping, Shipped: +1 day
(110, '2025-03-12 15:30:00', 129, 126, 2, 'Pending', '2025-03-12 19:00:00', NULL),     -- Fast shipping, Pending: +3.5 hrs
(111, '2025-03-18 14:00:00', 130, 127, 3, 'Delivered', '2025-03-20 14:00:00', NULL),   -- Express shipping, Delivered: +2 days
(111, '2025-03-19 09:15:00', 130, 127, 1, 'Returned', '2025-03-26 09:15:00', NULL),    -- Regular shipping, Returned: +7 days
(112, '2025-03-25 10:00:00', 125, 128, 2, 'Shipped', '2025-03-26 10:00:00', NULL),     -- Fast shipping, Shipped: +1 day
(112, '2025-03-25 15:30:00', 126, 128, 3, 'Cancelled', '2025-03-25 20:00:00', NULL);

SELECT *
from orders;

SELECT 
    o.user_id, 
    o.order_date, 
    o.order_status, 
    SUM(i.quantity * i.price) AS Total_order, 
    c.coupon_name
FROM orders o
JOIN order_items i ON o.order_id = i.order_id
JOIN product p ON i.product_id = p.product_id
JOIN sale_coupon c ON o.coupon_id = c.coupon_id
WHERE o.coupon_id IS NOT NULL
GROUP BY o.order_id, o.user_id, o.order_date, o.order_status, c.coupon_name;


INSERT INTO category (category_name, category_parent_id)
VALUES
-- Parent Categories
('Fashion', NULL),              
('Home Appliances', NULL),      
('Electronic Gadgets', NULL),   
('Books', NULL),    

-- Child Categories
('mens formal shirts', 1),
('women tops', 1),
('mens trackpants', 1),
('women watches', 1),
('mens cargo', 1),
('men watches', 1),
('women jeans', 1),
('mens casual shirts', 1),
('women t-shirts', 1),
('smart TVs', 2),
('refrigerator', 2),
('air conditioners', 2),
('washing machines', 2),
('laptops', 3),
('gaming laptops', 3),
('desktop PCs', 3),
('tablets', 3),
('DSLR cameras', 3),
('mobile phones', 3),
('Academic', 4),
('non-fiction', 4),
('young readers', 4),
('fiction', 4),
('literature', 4),
('audio books', 4);

select * 
from category;

INSERT INTO product (category_id, name, product_description, price, product_image_link, vendor_id)
VALUES
-- mens formal shirts (category_id: 5)
(5, 'Blue Formal Shirt', 'Classic blue formal shirt for men, 100% cotton', 29.99, 'images/mens_formal_blue.jpg', 6),
(5, 'White Dress Shirt', 'White dress shirt with slim fit design', 34.99, 'images/mens_formal_white.jpg', 7),
(5, 'Black Formal Shirt', 'Black formal shirt, perfect for office wear', 32.50, 'images/mens_formal_black.jpg', 11),
(5, 'Striped Formal Shirt', 'Blue and white striped formal shirt', 31.75, 'images/mens_formal_striped.jpg', 15),
(5, 'Grey Formal Shirt', 'Grey formal shirt with modern fit', 28.99, 'images/mens_formal_grey.jpg', 19),
(5, 'Checkered Dress Shirt', 'Checkered pattern formal shirt for men', 33.25, 'images/mens_formal_checkered.jpg', 23),
(5, 'Navy Formal Shirt', 'Navy blue formal shirt, wrinkle-resistant', 30.50, 'images/mens_formal_navy.jpg', 26),
(5, 'Red Formal Shirt', 'Bold red formal shirt for special occasions', 35.99, 'images/mens_formal_red.jpg', 27),
(5, 'Slim Fit Formal Shirt', 'Slim fit white formal shirt for men', 29.50, 'images/mens_formal_slimfit.jpg', 31),
(5, 'Formal Shirt with Tie', 'Formal shirt with matching tie, blue', 39.99, 'images/mens_formal_tie.jpg', 33),

-- women tops (category_id: 6)
(6, 'Floral Blouse', 'Floral print blouse for women, casual wear', 24.99, 'images/women_floral_blouse.jpg', 35),
(6, 'Sleeveless Top', 'White sleeveless top, perfect for summer', 19.99, 'images/women_sleeveless_top.jpg', 39),
(6, 'Off-Shoulder Top', 'Black off-shoulder top for women', 22.50, 'images/women_offshoulder_top.jpg', 43),
(6, 'Lace Crop Top', 'White lace crop top, elegant design', 27.75, 'images/women_lace_crop.jpg', 47),
(6, 'Red Peplum Top', 'Red peplum top with flared hem', 26.99, 'images/women_red_peplum.jpg', 51),
(6, 'Striped Tank Top', 'Blue and white striped tank top', 18.50, 'images/women_striped_tank.jpg', 52),
(6, 'Silk Blouse', 'Green silk blouse for formal occasions', 34.99, 'images/women_silk_blouse.jpg', 60),
(6, 'Denim Shirt', 'Denim shirt for women, casual style', 29.50, 'images/women_denim_shirt.jpg', 63),
(6, 'Polka Dot Top', 'Black polka dot top with short sleeves', 23.25, 'images/women_polka_dot.jpg', 67),
(6, 'Chiffon Blouse', 'Pink chiffon blouse, lightweight fabric', 28.99, 'images/women_chiffon_blouse.jpg', 71),

-- mens trackpants (category_id: 7)
(7, 'Black Trackpants', 'Black trackpants for men, gym wear', 19.99, 'images/mens_trackpants_black.jpg', 72),
(7, 'Grey Joggers', 'Grey joggers with elastic waistband', 22.50, 'images/mens_joggers_grey.jpg', 76),
(7, 'Navy Trackpants', 'Navy blue trackpants, breathable fabric', 21.75, 'images/mens_trackpants_navy.jpg', 80),
(7, 'Red Trackpants', 'Red trackpants for men, casual fit', 20.99, 'images/mens_trackpants_red.jpg', 84),
(7, 'Green Joggers', 'Green joggers with side pockets', 23.50, 'images/mens_joggers_green.jpg', 88),
(7, 'Blue Trackpants', 'Blue trackpants, ideal for running', 19.50, 'images/mens_trackpants_blue.jpg', 96),
(7, 'Striped Trackpants', 'Striped trackpants, black and white', 24.99, 'images/mens_trackpants_striped.jpg', 6),
(7, 'Cotton Trackpants', 'Cotton trackpants for men, grey', 22.25, 'images/mens_trackpants_cotton.jpg', 7),
(7, 'Slim Fit Joggers', 'Slim fit joggers, dark blue', 21.99, 'images/mens_joggers_slimfit.jpg', 11),
(7, 'Mesh Trackpants', 'Mesh trackpants for ventilation, black', 25.50, 'images/mens_trackpants_mesh.jpg', 15),

-- women watches (category_id: 8)
(8, 'Rose Gold Watch', 'Rose gold women’s watch with leather strap', 49.99, 'images/women_watch_rosegold.jpg', 19),
(8, 'Silver Analog Watch', 'Silver analog watch for women', 45.50, 'images/women_watch_silver.jpg', 23),
(8, 'Smart Watch Pink', 'Pink smart watch for women, fitness tracking', 79.99, 'images/women_smartwatch_pink.jpg', 26),
(8, 'Gold Bracelet Watch', 'Gold bracelet watch, elegant design', 59.75, 'images/women_watch_gold.jpg', 27),
(8, 'Black Leather Watch', 'Black leather strap watch for women', 39.99, 'images/women_watch_black.jpg', 31),
(8, 'Diamond Studded Watch', 'Diamond studded watch, luxury design', 99.50, 'images/women_watch_diamond.jpg', 33),
(8, 'Blue Strap Watch', 'Blue strap watch, casual style', 35.25, 'images/women_watch_blue.jpg', 35),
(8, 'Fitness Tracker Watch', 'Fitness tracker watch for women, white', 69.99, 'images/women_fitness_watch.jpg', 39),
(8, 'Minimalist Watch', 'Minimalist women’s watch, silver', 42.50, 'images/women_watch_minimalist.jpg', 43),
(8, 'Chronograph Watch', 'Chronograph watch for women, black', 55.99, 'images/women_watch_chrono.jpg', 47),

-- mens cargo (category_id: 9)
(9, 'Khaki Cargo Pants', 'Khaki cargo pants for men, multiple pockets', 34.99, 'images/mens_cargo_khaki.jpg', 51),
(9, 'Black Cargo Pants', 'Black cargo pants, durable fabric', 32.50, 'images/mens_cargo_black.jpg', 52),
(9, 'Olive Green Cargo', 'Olive green cargo pants, casual fit', 33.75, 'images/mens_cargo_olive.jpg', 60),
(9, 'Navy Cargo Pants', 'Navy blue cargo pants for men', 31.99, 'images/mens_cargo_navy.jpg', 63),
(9, 'Grey Cargo Pants', 'Grey cargo pants with side pockets', 35.50, 'images/mens_cargo_grey.jpg', 67),
(9, 'Camouflage Cargo', 'Camouflage cargo pants, rugged design', 37.25, 'images/mens_cargo_camo.jpg', 71),
(9, 'Brown Cargo Pants', 'Brown cargo pants, relaxed fit', 34.50, 'images/mens_cargo_brown.jpg', 72),
(9, 'Slim Fit Cargo', 'Slim fit cargo pants, black', 36.99, 'images/mens_cargo_slimfit.jpg', 76),
(9, 'Cargo Shorts', 'Cargo shorts for men, khaki', 29.99, 'images/mens_cargo_shorts.jpg', 80),
(9, 'Ripstop Cargo Pants', 'Ripstop cargo pants, olive green', 38.50, 'images/mens_cargo_ripstop.jpg', 84),

-- men watches (category_id: 10)
(10, 'Black Sports Watch', 'Black sports watch for men, water-resistant', 49.99, 'images/men_watch_black.jpg', 88),
(10, 'Silver Chronograph', 'Silver chronograph watch for men', 59.50, 'images/men_watch_silver.jpg', 96),
(10, 'Smart Watch Black', 'Black smart watch for men, fitness tracking', 89.99, 'images/men_smartwatch_black.jpg', 6),
(10, 'Leather Strap Watch', 'Brown leather strap watch, classic design', 45.75, 'images/men_watch_leather.jpg', 7),
(10, 'Gold Analog Watch', 'Gold analog watch for men, luxury style', 69.99, 'images/men_watch_gold.jpg', 11),
(10, 'Dive Watch', 'Dive watch for men, 200m water-resistant', 79.50, 'images/men_watch_dive.jpg', 15),
(10, 'Blue Strap Watch', 'Blue strap watch, casual design', 39.25, 'images/men_watch_blue.jpg', 19),
(10, 'Fitness Tracker', 'Fitness tracker watch for men, black', 65.99, 'images/men_fitness_watch.jpg', 23),
(10, 'Minimalist Watch', 'Minimalist men’s watch, silver', 42.50, 'images/men_watch_minimalist.jpg', 26),
(10, 'Automatic Watch', 'Automatic watch for men, black dial', 99.99, 'images/men_watch_automatic.jpg', 27),

-- women jeans (category_id: 11)
(11, 'High-Waist Jeans', 'High-waist blue jeans for women', 39.99, 'images/women_jeans_highwaist.jpg', 31),
(11, 'Skinny Jeans', 'Black skinny jeans, stretch fabric', 34.50, 'images/women_jeans_skinny.jpg', 33),
(11, 'Ripped Jeans', 'Ripped blue jeans, casual style', 37.75, 'images/women_jeans_ripped.jpg', 35),
(11, 'Bootcut Jeans', 'Bootcut jeans for women, dark wash', 36.99, 'images/women_jeans_bootcut.jpg', 39),
(11, 'Flare Jeans', 'Flare jeans, light blue', 38.50, 'images/women_jeans_flare.jpg', 43),
(11, 'Mom Jeans', 'High-waist mom jeans, vintage style', 35.25, 'images/women_jeans_mom.jpg', 47),
(11, 'White Jeans', 'White jeans for women, slim fit', 39.50, 'images/women_jeans_white.jpg', 51),
(11, 'Distressed Jeans', 'Distressed blue jeans, relaxed fit', 37.99, 'images/women_jeans_distressed.jpg', 52),
(11, 'Ankle-Length Jeans', 'Ankle-length jeans, black', 34.99, 'images/women_jeans_ankle.jpg', 60),
(11, 'Stretch Jeans', 'Stretch jeans for women, dark blue', 36.50, 'images/women_jeans_stretch.jpg', 63),

-- mens casual shirts (category_id: 12)
(12, 'Plaid Casual Shirt', 'Plaid casual shirt for men, red and black', 24.99, 'images/mens_casual_plaid.jpg', 67),
(12, 'Denim Casual Shirt', 'Denim casual shirt, light blue', 29.50, 'images/mens_casual_denim.jpg', 71),
(12, 'Graphic Tee', 'Graphic t-shirt for men, black', 19.75, 'images/mens_casual_graphic.jpg', 72),
(12, 'Polo Shirt', 'Navy blue polo shirt, casual fit', 22.99, 'images/mens_casual_polo.jpg', 76),
(12, 'Henley Shirt', 'Grey henley shirt for men', 21.50, 'images/mens_casual_henley.jpg', 80),
(12, 'Striped Casual Shirt', 'Striped casual shirt, blue and white', 23.25, 'images/mens_casual_striped.jpg', 84),
(12, 'Linen Shirt', 'White linen shirt, perfect for summer', 27.99, 'images/mens_casual_linen.jpg', 88),
(12, 'Checkered Shirt', 'Checkered casual shirt, green', 25.50, 'images/mens_casual_checkered.jpg', 96),
(12, 'Short Sleeve Shirt', 'Short sleeve casual shirt, black', 20.99, 'images/mens_casual_shortsleeve.jpg', 6),
(12, 'Casual Button-Down', 'Casual button-down shirt, grey', 26.75, 'images/mens_casual_buttondown.jpg', 7),

-- women t-shirts (category_id: 13)
(13, 'Graphic T-Shirt', 'Graphic t-shirt for women, white', 14.99, 'images/women_tshirt_graphic.jpg', 11),
(13, 'V-Neck T-Shirt', 'Black v-neck t-shirt, soft fabric', 12.50, 'images/women_tshirt_vneck.jpg', 15),
(13, 'Striped T-Shirt', 'Striped t-shirt, red and white', 13.75, 'images/women_tshirt_striped.jpg', 19),
(13, 'Crew Neck Tee', 'Crew neck t-shirt, blue', 11.99, 'images/women_tshirt_crewneck.jpg', 23),
(13, 'Long Sleeve Tee', 'Long sleeve t-shirt, grey', 16.50, 'images/women_tshirt_longsleeve.jpg', 26),
(13, 'Crop T-Shirt', 'Crop t-shirt for women, black', 15.25, 'images/women_tshirt_crop.jpg', 27),
(13, 'Slogan T-Shirt', 'Slogan t-shirt, white', 14.50, 'images/women_tshirt_slogan.jpg', 31),
(13, 'Tie-Dye T-Shirt', 'Tie-dye t-shirt, multicolour', 17.99, 'images/women_tshirt_tiedye.jpg', 33),
(13, 'Basic T-Shirt', 'Basic t-shirt for women, pink', 10.99, 'images/women_tshirt_basic.jpg', 35),
(13, 'Oversized T-Shirt', 'Oversized t-shirt, grey', 18.50, 'images/women_tshirt_oversized.jpg', 39),

-- smart TVs (category_id: 14)
(14, '55-Inch 4K Smart TV', '55-inch 4K smart TV with HDR', 499.99, 'images/smart_tv_55inch.jpg', 43),
(14, '65-Inch OLED TV', '65-inch OLED smart TV, ultra slim', 799.50, 'images/smart_tv_65inch.jpg', 47),
(14, '43-Inch LED TV', '43-inch LED smart TV, full HD', 349.75, 'images/smart_tv_43inch.jpg', 51),
(14, '75-Inch 8K TV', '75-inch 8K smart TV, premium quality', 1299.99, 'images/smart_tv_75inch.jpg', 52),
(14, '50-Inch QLED TV', '50-inch QLED smart TV, vibrant colors', 599.50, 'images/smart_tv_50inch.jpg', 60),
(14, '32-Inch Smart TV', '32-inch smart TV, compact design', 249.25, 'images/smart_tv_32inch.jpg', 63),
(14, '60-Inch 4K TV', '60-inch 4K smart TV with voice control', 699.99, 'images/smart_tv_60inch.jpg', 67),
(14, '70-Inch LED TV', '70-inch LED smart TV, wide viewing angle', 899.50, 'images/smart_tv_70inch.jpg', 71),
(14, '40-Inch Smart TV', '40-inch smart TV, streaming apps', 299.99, 'images/smart_tv_40inch.jpg', 72),
(14, '85-Inch 4K TV', '85-inch 4K smart TV, cinematic experience', 1999.99, 'images/smart_tv_85inch.jpg', 76),

-- refrigerator (category_id: 15)
(15, 'Double Door Fridge', 'Double door refrigerator, 300L', 599.99, 'images/fridge_double_door.jpg', 80),
(15, 'Side-by-Side Fridge', 'Side-by-side refrigerator, 500L', 899.50, 'images/fridge_sidebyside.jpg', 84),
(15, 'Single Door Fridge', 'Single door refrigerator, 200L', 349.75, 'images/fridge_single_door.jpg', 88),
(15, 'French Door Fridge', 'French door refrigerator, 400L', 999.99, 'images/fridge_french_door.jpg', 96),
(15, 'Mini Fridge', 'Mini refrigerator, 50L, compact', 199.50, 'images/fridge_mini.jpg', 6),
(15, 'Inverter Fridge', 'Inverter refrigerator, 350L, energy efficient', 649.25, 'images/fridge_inverter.jpg', 7),
(15, 'Frost-Free Fridge', 'Frost-free refrigerator, 320L', 579.99, 'images/fridge_frostfree.jpg', 11),
(15, 'Smart Fridge', 'Smart refrigerator with touchscreen, 450L', 1299.50, 'images/fridge_smart.jpg', 15),
(15, 'Top Freezer Fridge', 'Top freezer refrigerator, 280L', 499.99, 'images/fridge_topfreezer.jpg', 19),
(15, 'Bottom Freezer Fridge', 'Bottom freezer refrigerator, 310L', 699.99, 'images/fridge_bottomfreezer.jpg', 23),

-- air conditioners (category_id: 16)
(16, '1.5 Ton Split AC', '1.5 ton split air conditioner, 5-star rating', 399.99, 'images/ac_split_1.5ton.jpg', 26),
(16, 'Window AC 1 Ton', '1 ton window air conditioner, energy efficient', 299.50, 'images/ac_window_1ton.jpg', 27),
(16, '2 Ton Inverter AC', '2 ton inverter split AC, low noise', 499.75, 'images/ac_inverter_2ton.jpg', 31),
(16, 'Portable AC', 'Portable air conditioner, 1 ton', 349.99, 'images/ac_portable.jpg', 33),
(16, '1 Ton Split AC', '1 ton split air conditioner, 3-star rating', 329.50, 'images/ac_split_1ton.jpg', 35),
(16, '1.5 Ton Window AC', '1.5 ton window AC, fast cooling', 319.25, 'images/ac_window_1.5ton.jpg', 39),
(16, '2.5 Ton Split AC', '2.5 ton split air conditioner, premium model', 599.99, 'images/ac_split_2.5ton.jpg', 43),
(16, 'Inverter AC 1.5 Ton', '1.5 ton inverter AC, eco-friendly', 429.50, 'images/ac_inverter_1.5ton.jpg', 47),
(16, 'Smart AC 1 Ton', 'Smart air conditioner with Wi-Fi, 1 ton', 379.99, 'images/ac_smart_1ton.jpg', 51),
(16, 'Cassette AC 2 Ton', '2 ton cassette air conditioner, ceiling mount', 699.99, 'images/ac_cassette_2ton.jpg', 52),

-- washing machines (category_id: 17)
(17, 'Front Load Washer', 'Front load washing machine, 7kg', 449.99, 'images/washer_frontload_7kg.jpg', 60),
(17, 'Top Load Washer', 'Top load washing machine, 6kg', 349.50, 'images/washer_topload_6kg.jpg', 63),
(17, 'Semi-Automatic Washer', 'Semi-automatic washing machine, 5kg', 199.75, 'images/washer_semiauto_5kg.jpg', 67),
(17, '8kg Front Load', '8kg front load washing machine, inverter', 499.99, 'images/washer_frontload_8kg.jpg', 71),
(17, '7kg Top Load', '7kg top load washing machine, 5-star rating', 379.50, 'images/washer_topload_7kg.jpg', 72),
(17, 'Portable Washer', 'Portable washing machine, 3kg', 149.25, 'images/washer_portable.jpg', 76),
(17, '10kg Front Load', '10kg front load washing machine, smart', 599.99, 'images/washer_frontload_10kg.jpg', 80),
(17, '6.5kg Semi-Automatic', '6.5kg semi-automatic washing machine', 229.50, 'images/washer_semiauto_6.5kg.jpg', 84),
(17, '9kg Top Load', '9kg top load washing machine, fast wash', 429.99, 'images/washer_topload_9kg.jpg', 88),
(17, 'Inverter Washer', 'Inverter washing machine, 8kg', 479.99, 'images/washer_inverter_8kg.jpg', 96),

-- laptops (category_id: 18)
(18, '15-Inch Laptop', '15-inch laptop, Intel i5, 8GB RAM', 699.99, 'images/laptop_15inch_i5.jpg', 6),
(18, '13-Inch Ultrabook', '13-inch ultrabook, Intel i7, 16GB RAM', 999.50, 'images/laptop_13inch_i7.jpg', 7),
(18, '14-Inch Laptop', '14-inch laptop, AMD Ryzen 5, 8GB RAM', 649.75, 'images/laptop_14inch_ryzen.jpg', 11),
(18, '17-Inch Laptop', '17-inch laptop, Intel i9, 32GB RAM', 1499.99, 'images/laptop_17inch_i9.jpg', 15),
(18, '15-Inch Touchscreen', '15-inch touchscreen laptop, Intel i5', 799.50, 'images/laptop_15inch_touch.jpg', 19),
(18, '13-Inch MacBook', '13-inch MacBook, M1 chip, 8GB RAM', 1199.25, 'images/laptop_macbook_13inch.jpg', 23),
(18, '14-Inch Business Laptop', '14-inch business laptop, Intel i7', 899.99, 'images/laptop_14inch_business.jpg', 26),
(18, '15-Inch Budget Laptop', '15-inch budget laptop, Intel i3, 4GB RAM', 499.50, 'images/laptop_15inch_budget.jpg', 27),
(18, '16-Inch Laptop', '16-inch laptop, AMD Ryzen 7, 16GB RAM', 1099.99, 'images/laptop_16inch_ryzen.jpg', 31),
(18, '13-Inch Lightweight', '13-inch lightweight laptop, Intel i5', 799.99, 'images/laptop_13inch_light.jpg', 33),

-- gaming laptops (category_id: 19)
(19, 'Gaming Laptop RTX 3060', 'Gaming laptop with RTX 3060, 16GB RAM', 1299.99, 'images/gaming_laptop_rtx3060.jpg', 35),
(19, 'Gaming Laptop RTX 3070', 'Gaming laptop with RTX 3070, 32GB RAM', 1799.50, 'images/gaming_laptop_rtx3070.jpg', 39),
(19, 'Gaming Laptop Ryzen 9', 'Gaming laptop, Ryzen 9, RTX 3080', 1999.75, 'images/gaming_laptop_ryzen9.jpg', 43),
(19, '15-Inch Gaming Laptop', '15-inch gaming laptop, Intel i7, RTX 3060', 1399.99, 'images/gaming_laptop_15inch.jpg', 47),
(19, '17-Inch Gaming Laptop', '17-inch gaming laptop, Intel i9, RTX 3070', 1899.50, 'images/gaming_laptop_17inch.jpg', 51),
(19, 'Gaming Laptop RGB', 'Gaming laptop with RGB keyboard, RTX 3060', 1499.25, 'images/gaming_laptop_rgb.jpg', 52),
(19, 'Budget Gaming Laptop', 'Budget gaming laptop, GTX 1650, 8GB RAM', 999.99, 'images/gaming_laptop_budget.jpg', 60),
(19, 'Gaming Laptop 144Hz', 'Gaming laptop with 144Hz display, RTX 3060', 1599.50, 'images/gaming_laptop_144hz.jpg', 63),
(19, '16-Inch Gaming Laptop', '16-inch gaming laptop, Ryzen 7, RTX 3070', 1699.99, 'images/gaming_laptop_16inch.jpg', 67),
(19, 'High-End Gaming Laptop', 'High-end gaming laptop, RTX 3080, 32GB RAM', 2499.99, 'images/gaming_laptop_highend.jpg', 71),

-- desktop PCs (category_id: 20)
(20, 'Gaming Desktop PC', 'Gaming desktop PC, RTX 3060, 16GB RAM', 1199.99, 'images/desktop_gaming_rtx3060.jpg', 72),
(20, 'Workstation PC', 'Workstation PC, Intel i9, 32GB RAM', 1799.50, 'images/desktop_workstation.jpg', 76),
(20, 'Budget Desktop PC', 'Budget desktop PC, Intel i3, 8GB RAM', 599.75, 'images/desktop_budget.jpg', 80),
(20, 'All-in-One PC', 'All-in-one PC, Intel i5, 16GB RAM', 999.99, 'images/desktop_allinone.jpg', 84),
(20, 'Mini Desktop PC', 'Mini desktop PC, AMD Ryzen 5, 8GB RAM', 699.50, 'images/desktop_mini.jpg', 88),
(20, 'High-End Desktop', 'High-end desktop PC, RTX 3080, 32GB RAM', 2499.25, 'images/desktop_highend.jpg', 96),
(20, 'Office Desktop PC', 'Office desktop PC, Intel i5, 8GB RAM', 799.99, 'images/desktop_office.jpg', 6),
(20, 'Custom Desktop PC', 'Custom desktop PC, Ryzen 7, 16GB RAM', 1399.50, 'images/desktop_custom.jpg', 7),
(20, 'Compact Desktop PC', 'Compact desktop PC, Intel i7, 16GB RAM', 1099.99, 'images/desktop_compact.jpg', 11),
(20, 'Media Desktop PC', 'Media desktop PC, AMD Ryzen 5, 16GB RAM', 899.99, 'images/desktop_media.jpg', 15),

-- tablets (category_id: 21)
(21, '10-Inch Tablet', '10-inch tablet, 4GB RAM, 64GB storage', 199.99, 'images/tablet_10inch.jpg', 19),
(21, '8-Inch Tablet', '8-inch tablet, 3GB RAM, 32GB storage', 149.50, 'images/tablet_8inch.jpg', 23),
(21, '12-Inch Tablet', '12-inch tablet, 6GB RAM, 128GB storage', 349.75, 'images/tablet_12inch.jpg', 26),
(21, 'Tablet with Stylus', 'Tablet with stylus, 10-inch, 4GB RAM', 249.99, 'images/tablet_stylus.jpg', 27),
(21, 'Kids Tablet', 'Kids tablet, 8-inch, parental controls', 129.50, 'images/tablet_kids.jpg', 31),
(21, 'High-End Tablet', 'High-end tablet, 11-inch, 8GB RAM', 499.25, 'images/tablet_highend.jpg', 33),
(21, 'Budget Tablet', 'Budget tablet, 7-inch, 2GB RAM', 99.99, 'images/tablet_budget.jpg', 35),
(21, 'Tablet with Keyboard', 'Tablet with keyboard, 10-inch, 4GB RAM', 299.50, 'images/tablet_keyboard.jpg', 39),
(21, 'Android Tablet', 'Android tablet, 9-inch, 3GB RAM', 179.99, 'images/tablet_android.jpg', 43),
(21, 'iPad 10-Inch', 'iPad 10-inch, 4GB RAM, 64GB storage', 399.99, 'images/tablet_ipad.jpg', 47),

-- DSLR cameras (category_id: 22)
(22, 'Entry-Level DSLR', 'Entry-level DSLR camera, 24MP', 499.99, 'images/dslr_entrylevel.jpg', 51),
(22, 'Professional DSLR', 'Professional DSLR camera, 45MP', 1999.50, 'images/dslr_professional.jpg', 52),
(22, 'Mid-Range DSLR', 'Mid-range DSLR camera, 30MP', 999.75, 'images/dslr_midrange.jpg', 60),
(22, 'DSLR with Kit Lens', 'DSLR with 18-55mm kit lens, 24MP', 599.99, 'images/dslr_kitlens.jpg', 63),
(22, 'Full-Frame DSLR', 'Full-frame DSLR camera, 36MP', 1499.50, 'images/dslr_fullframe.jpg', 67),
(22, 'DSLR for Vlogging', 'DSLR for vlogging, 24MP, flip screen', 799.25, 'images/dslr_vlogging.jpg', 71),
(22, 'Sports DSLR', 'DSLR for sports photography, 20MP', 1299.99, 'images/dslr_sports.jpg', 72),
(22, 'Compact DSLR', 'Compact DSLR camera, 24MP', 699.50, 'images/dslr_compact.jpg', 76),
(22, 'DSLR with Wi-Fi', 'DSLR with Wi-Fi, 24MP', 899.99, 'images/dslr_wifi.jpg', 80),
(22, 'Advanced DSLR', 'Advanced DSLR camera, 30MP', 1599.99, 'images/dslr_advanced.jpg', 84),

-- mobile phones (category_id: 23)
(23, 'Smartphone 128GB', 'Smartphone with 128GB storage, 6GB RAM', 399.99, 'images/phone_128gb.jpg', 88),
(23, 'Flagship Phone', 'Flagship smartphone, 256GB, 12GB RAM', 999.50, 'images/phone_flagship.jpg', 96),
(23, 'Budget Smartphone', 'Budget smartphone, 64GB, 4GB RAM', 199.75, 'images/phone_budget.jpg', 6),
(23, '5G Smartphone', '5G smartphone, 128GB, 8GB RAM', 599.99, 'images/phone_5g.jpg', 7),
(23, 'Gaming Smartphone', 'Gaming smartphone, 256GB, 16GB RAM', 799.50, 'images/phone_gaming.jpg', 11),
(23, 'Camera Phone', 'Camera-focused smartphone, 48MP, 128GB', 499.25, 'images/phone_camera.jpg', 15),
(23, 'Foldable Phone', 'Foldable smartphone, 256GB, 12GB RAM', 1299.99, 'images/phone_foldable.jpg', 19),
(23, 'Mid-Range Phone', 'Mid-range smartphone, 128GB, 6GB RAM', 349.50, 'images/phone_midrange.jpg', 23),
(23, 'iPhone 14', 'iPhone 14, 128GB, 6GB RAM', 799.99, 'images/phone_iphone14.jpg', 26),
(23, 'Android Phone', 'Android smartphone, 64GB, 4GB RAM', 299.99, 'images/phone_android.jpg', 27),

-- Academic (category_id: 24)
(24, 'Calculus Textbook', 'Calculus textbook for college students', 59.99, 'images/book_calculus.jpg', 31),
(24, 'Physics for Engineers', 'Physics textbook for engineering students', 49.50, 'images/book_physics.jpg', 33),
(24, 'Organic Chemistry', 'Organic chemistry textbook, 2nd edition', 69.75, 'images/book_chemistry.jpg', 35),
(24, 'Economics 101', 'Introductory economics textbook', 39.99, 'images/book_economics.jpg', 39),
(24, 'Computer Science Basics', 'Computer science basics textbook', 45.50, 'images/book_compsci.jpg', 43),
(24, 'Statistics for Beginners', 'Statistics textbook for beginners', 55.25, 'images/book_statistics.jpg', 47),
(24, 'Biology Textbook', 'Biology textbook for high school', 49.99, 'images/book_biology.jpg', 51),
(24, 'Algebra Made Easy', 'Algebra textbook, simplified concepts', 35.50, 'images/book_algebra.jpg', 52),
(24, 'History of Science', 'History of science textbook', 42.99, 'images/book_history_science.jpg', 60),
(24, 'Engineering Mechanics', 'Engineering mechanics textbook', 65.99, 'images/book_mechanics.jpg', 63),

-- non-fiction (category_id: 25)
(25, 'Sapiens', 'Sapiens: A Brief History of Humankind', 19.99, 'images/book_sapiens.jpg', 67),
(25, 'Becoming', 'Becoming by Michelle Obama', 24.50, 'images/book_becoming.jpg', 71),
(25, 'The Power of Habit', 'The Power of Habit by Charles Duhigg', 15.75, 'images/book_powerofhabit.jpg', 72),
(25, 'Educated', 'Educated: A Memoir by Tara Westover', 22.99, 'images/book_educated.jpg', 76),
(25, 'Atomic Habits', 'Atomic Habits by James Clear', 18.50, 'images/book_atomichabits.jpg', 80),
(25, 'Thinking, Fast and Slow', 'Thinking, Fast and Slow by Daniel Kahneman', 21.25, 'images/book_thinkingfast.jpg', 84),
(25, 'The Subtle Art', 'The Subtle Art of Not Giving a F*ck', 17.99, 'images/book_subtleart.jpg', 88),
(25, 'Outliers', 'Outliers by Malcolm Gladwell', 16.50, 'images/book_outliers.jpg', 96),
(25, 'Grit', 'Grit: The Power of Passion and Perseverance', 19.99, 'images/book_grit.jpg', 6),
(25, 'Man’s Search for Meaning', 'Man’s Search for Meaning by Viktor Frankl', 14.99, 'images/book_manssearch.jpg', 7),

-- young readers (category_id: 26)
(26, 'Harry Potter Book 1', 'Harry Potter and the Sorcerer’s Stone', 12.99, 'images/book_harrypotter1.jpg', 11),
(26, 'The Hobbit', 'The Hobbit by J.R.R. Tolkien', 14.50, 'images/book_hobbit.jpg', 15),
(26, 'Percy Jackson Book 1', 'Percy Jackson: The Lightning Thief', 11.75, 'images/book_percyjackson1.jpg', 19),
(26, 'Charlotte’s Web', 'Charlotte’s Web by E.B. White', 9.99, 'images/book_charlottesweb.jpg', 23),
(26, 'The Lion, the Witch', 'The Lion, the Witch and the Wardrobe', 10.50, 'images/book_narnia.jpg', 26),
(26, 'Diary of a Wimpy Kid', 'Diary of a Wimpy Kid by Jeff Kinney', 13.25, 'images/book_wimpykid.jpg', 27),
(26, 'Matilda', 'Matilda by Roald Dahl', 8.99, 'images/book_matilda.jpg', 31),
(26, 'The Secret Garden', 'The Secret Garden by Frances Hodgson Burnett', 9.50, 'images/book_secretgarden.jpg', 33),
(26, 'Holes', 'Holes by Louis Sachar', 11.99, 'images/book_holes.jpg', 35),
(26, 'Wonder', 'Wonder by R.J. Palacio', 12.50, 'images/book_wonder.jpg', 39),

-- fiction (category_id: 27)
(27, 'To Kill a Mockingbird', 'To Kill a Mockingbird by Harper Lee', 14.99, 'images/book_mockingbird.jpg', 43),
(27, '1984', '1984 by George Orwell', 12.50, 'images/book_1984.jpg', 47),
(27, 'Pride and Prejudice', 'Pride and Prejudice by Jane Austen', 11.75, 'images/book_prideprejudice.jpg', 51),
(27, 'The Great Gatsby', 'The Great Gatsby by F. Scott Fitzgerald', 10.99, 'images/book_gatsby.jpg', 52),
(27, 'The Catcher in the Rye', 'The Catcher in the Rye by J.D. Salinger', 13.50, 'images/book_catcherrye.jpg', 60),
(27, 'Lord of the Flies', 'Lord of the Flies by William Golding', 9.25, 'images/book_lordoftheflies.jpg', 63),
(27, 'Animal Farm', 'Animal Farm by George Orwell', 8.99, 'images/book_animalfarm.jpg', 67),
(27, 'Brave New World', 'Brave New World by Aldous Huxley', 12.50, 'images/book_bravenewworld.jpg', 71),
(27, 'The Alchemist', 'The Alchemist by Paulo Coelho', 14.99, 'images/book_alchemist.jpg', 72),
(27, 'Dune', 'Dune by Frank Herbert', 16.50, 'images/book_dune.jpg', 76),

-- literature (category_id: 28)
(28, 'Moby-Dick', 'Moby-Dick by Herman Melville', 19.99, 'images/book_mobydick.jpg', 80),
(28, 'War and Peace', 'War and Peace by Leo Tolstoy', 24.50, 'images/book_warandpeace.jpg', 84),
(28, 'Ulysses', 'Ulysses by James Joyce', 22.75, 'images/book_ulysses.jpg', 88),
(28, 'The Odyssey', 'The Odyssey by Homer', 15.99, 'images/book_odyssey.jpg', 96),
(28, 'Crime and Punishment', 'Crime and Punishment by Fyodor Dostoevsky', 18.50, 'images/book_crimepunishment.jpg', 6),
(28, 'Les Misérables', 'Les Misérables by Victor Hugo', 21.25, 'images/book_lesmiserables.jpg', 7),
(28, 'Jane Eyre', 'Jane Eyre by Charlotte Brontë', 14.99, 'images/book_janeeyre.jpg', 11),
(28, 'Wuthering Heights', 'Wuthering Heights by Emily Brontë', 13.50, 'images/book_wutheringheights.jpg', 15),
(28, 'Great Expectations', 'Great Expectations by Charles Dickens', 16.99, 'images/book_greatexpectations.jpg', 19),
(28, 'Anna Karenina', 'Anna Karenina by Leo Tolstoy', 20.50, 'images/book_annakarenina.jpg', 23),

-- audio books (category_id: 29)
(29, 'Sapiens Audiobook', 'Sapiens audiobook, narrated by Derek Perkins', 29.99, 'images/audiobook_sapiens.jpg', 26),
(29, 'Becoming Audiobook', 'Becoming audiobook, narrated by Michelle Obama', 34.50, 'images/audiobook_becoming.jpg', 27),
(29, 'Harry Potter Audiobook', 'Harry Potter Book 1 audiobook', 24.75, 'images/audiobook_harrypotter.jpg', 31),
(29, '1984 Audiobook', '1984 audiobook, narrated by Simon Prebble', 19.99, 'images/audiobook_1984.jpg', 33),
(29, 'The Alchemist Audiobook', 'The Alchemist audiobook, narrated by Jeremy Irons', 22.50, 'images/audiobook_alchemist.jpg', 35),
(29, 'Atomic Habits Audiobook', 'Atomic Habits audiobook, narrated by James Clear', 27.25, 'images/audiobook_atomichabits.jpg', 39),
(29, 'Pride and Prejudice Audiobook', 'Pride and Prejudice audiobook', 18.99, 'images/audiobook_prideprejudice.jpg', 43),
(29, 'The Hobbit Audiobook', 'The Hobbit audiobook, narrated by Andy Serkis', 26.50, 'images/audiobook_hobbit.jpg', 47),
(29, 'Dune Audiobook', 'Dune audiobook, narrated by Scott Brick', 29.99, 'images/audiobook_dune.jpg', 51),
(29, 'Educated Audiobook', 'Educated audiobook, narrated by Tara Westover', 31.50, 'images/audiobook_educated.jpg', 52);

SELECT *
FROM product;

SELECT U.user_id,U.username,p.name,p.price
from product p
JOIN users U ON U.user_id=p.vendor_id
ORDER BY user_id;

INSERT INTO order_items (order_id, product_id, quantity, price) VALUES
-- Order 1
(1, 1, 2, 29.99), -- Blue Formal Shirt
(1, 11, 1, 24.99), -- Floral Blouse

-- Order 2
(2, 2, 1, 34.99), -- White Dress Shirt
(2, 21, 2, 19.99), -- Black Trackpants

-- Order 3
(3, 3, 3, 32.50), -- Black Formal Shirt
(3, 31, 1, 49.99), -- Rose Gold Watch

-- Order 4
(4, 4, 1, 31.75), -- Striped Formal Shirt
(4, 41, 2, 34.99), -- Khaki Cargo Pants

-- Order 5
(5, 5, 2, 28.99), -- Grey Formal Shirt
(5, 51, 1, 49.99), -- Black Sports Watch

-- Order 6
(6, 6, 1, 33.25), -- Checkered Dress Shirt
(6, 12, 2, 19.99), -- Sleeveless Top

-- Order 7
(7, 7, 3, 30.50), -- Navy Formal Shirt
(7, 22, 1, 22.50), -- Grey Joggers

-- Order 8
(8, 8, 1, 35.99), -- Red Formal Shirt
(8, 32, 2, 45.50), -- Silver Analog Watch

-- Order 9
(9, 9, 2, 29.50), -- Slim Fit Formal Shirt
(9, 42, 1, 32.50), -- Black Cargo Pants

-- Order 10
(10, 10, 1, 39.99), -- Formal Shirt with Tie
(10, 52, 2, 59.50), -- Silver Chronograph

-- Order 11
(11, 13, 3, 22.50), -- Off-Shoulder Top
(11, 61, 1, 39.99), -- High-Waist Jeans

-- Order 12
(12, 14, 1, 27.75), -- Lace Crop Top
(12, 71, 2, 24.99), -- Plaid Casual Shirt

-- Order 13
(13, 15, 2, 26.99), -- Red Peplum Top
(13, 81, 1, 14.99), -- Graphic T-Shirt

-- Order 14
(14, 16, 1, 18.50), -- Striped Tank Top
(14, 91, 2, 499.99), -- 55-Inch 4K Smart TV

-- Order 15
(15, 17, 3, 34.99), -- Silk Blouse
(15, 101, 1, 599.99), -- Double Door Fridge

-- Order 16
(16, 18, 1, 29.50), -- Denim Shirt
(16, 111, 2, 399.99), -- 1.5 Ton Split AC

-- Order 17
(17, 19, 2, 23.25), -- Polka Dot Top
(17, 121, 1, 449.99), -- Front Load Washer

-- Order 18
(18, 20, 1, 28.99), -- Chiffon Blouse
(18, 131, 2, 699.99), -- 15-Inch Laptop

-- Order 19
(19, 23, 3, 21.75), -- Navy Trackpants
(19, 141, 1, 1299.99), -- Gaming Laptop RTX 3060

-- Order 20
(20, 24, 1, 20.99), -- Red Trackpants
(20, 151, 2, 1199.99), -- Gaming Desktop PC

-- Order 21
(21, 25, 2, 23.50), -- Green Joggers
(21, 161, 1, 199.99), -- 10-Inch Tablet

-- Order 22
(22, 26, 1, 19.50), -- Blue Trackpants
(22, 171, 2, 499.99), -- Entry-Level DSLR

-- Order 23
(23, 27, 3, 24.99), -- Striped Trackpants
(23, 181, 1, 399.99), -- Smartphone 128GB

-- Order 24
(24, 28, 1, 22.25), -- Cotton Trackpants
(24, 191, 2, 59.99), -- Calculus Textbook

-- Order 25
(25, 29, 2, 21.99), -- Slim Fit Joggers
(25, 201, 1, 19.99), -- Sapiens

-- Order 26
(26, 30, 1, 25.50), -- Mesh Trackpants
(26, 211, 2, 12.99), -- Harry Potter Book 1

-- Order 27
(27, 33, 3, 79.99), -- Smart Watch Pink
(27, 221, 1, 14.99), -- To Kill a Mockingbird

-- Order 28
(28, 34, 1, 59.75), -- Gold Bracelet Watch
(28, 231, 2, 19.99), -- Moby-Dick

-- Order 29
(29, 35, 2, 39.99), -- Black Leather Watch
(29, 241, 1, 29.99), -- Sapiens Audiobook

-- Order 30
(30, 36, 1, 99.50), -- Diamond Studded Watch
(30, 62, 2, 34.50), -- Skinny Jeans

-- Order 31
(31, 37, 3, 35.25), -- Blue Strap Watch
(31, 72, 1, 29.50), -- Denim Casual Shirt

-- Order 32
(32, 38, 1, 69.99), -- Fitness Tracker Watch
(32, 82, 2, 12.50), -- V-Neck T-Shirt

-- Order 33
(33, 39, 2, 42.50), -- Minimalist Watch
(33, 92, 1, 799.50), -- 65-Inch OLED TV

-- Order 34
(34, 40, 1, 55.99), -- Chronograph Watch
(34, 102, 2, 899.50), -- Side-by-Side Fridge

-- Order 35
(35, 43, 3, 33.75), -- Olive Green Cargo
(35, 112, 1, 299.50), -- Window AC 1 Ton

-- Order 36
(36, 44, 1, 31.99), -- Navy Cargo Pants
(36, 122, 2, 349.50), -- Top Load Washer

-- Order 37
(37, 45, 2, 35.50), -- Grey Cargo Pants
(37, 132, 1, 999.50), -- 13-Inch Ultrabook

-- Order 38
(38, 46, 1, 37.25), -- Camouflage Cargo
(38, 142, 2, 1799.50), -- Gaming Laptop RTX 3070

-- Order 39
(39, 47, 3, 34.50), -- Brown Cargo Pants
(39, 152, 1, 1799.50), -- Workstation PC

-- Order 40
(40, 48, 1, 36.99), -- Slim Fit Cargo
(40, 162, 2, 149.50), -- 8-Inch Tablet

-- Order 41
(41, 49, 2, 29.99), -- Cargo Shorts
(41, 172, 1, 1999.50), -- Professional DSLR

-- Order 42
(42, 50, 1, 38.50), -- Ripstop Cargo Pants
(42, 182, 2, 999.50), -- Flagship Phone

-- Order 43
(43, 53, 3, 89.99), -- Smart Watch Black
(43, 192, 1, 49.50), -- Physics for Engineers

-- Order 44
(44, 54, 1, 45.75), -- Leather Strap Watch
(44, 202, 2, 24.50), -- Becoming

-- Order 45
(45, 55, 2, 69.99), -- Gold Analog Watch
(45, 212, 1, 14.50), -- The Hobbit

-- Order 46
(46, 56, 1, 79.50), -- Dive Watch
(46, 222, 2, 12.50), -- 1984

-- Order 47
(47, 57, 3, 39.25), -- Blue Strap Watch
(47, 232, 1, 24.50), -- War and Peace

-- Order 48
(48, 58, 1, 65.99), -- Fitness Tracker
(48, 242, 2, 34.50), -- Becoming Audiobook

-- Order 49
(49, 59, 2, 42.50), -- Minimalist Watch
(49, 63, 1, 37.75), -- Ripped Jeans

-- Order 50
(50, 60, 1, 99.99), -- Automatic Watch
(50, 73, 2, 19.75), -- Graphic Tee

-- Order 51
(51, 64, 3, 36.99), -- Bootcut Jeans
(51, 83, 1, 13.75), -- Striped T-Shirt

-- Order 52
(52, 65, 1, 38.50), -- Flare Jeans
(52, 93, 2, 349.75), -- 43-Inch LED TV

-- Order 53
(53, 66, 2, 35.25), -- Mom Jeans
(53, 103, 1, 349.75), -- Single Door Fridge

-- Order 54
(54, 67, 1, 39.50), -- White Jeans
(54, 113, 2, 499.75), -- 2 Ton Inverter AC

-- Order 55
(55, 68, 3, 37.99), -- Distressed Jeans
(55, 123, 1, 199.75), -- Semi-Automatic Washer

-- Order 56
(56, 69, 1, 34.99), -- Ankle-Length Jeans
(56, 133, 2, 649.75), -- 14-Inch Laptop

-- Order 57
(57, 70, 2, 36.50), -- Stretch Jeans
(57, 143, 1, 1999.75), -- Gaming Laptop Ryzen 9

-- Order 58
(58, 74, 1, 22.99), -- Polo Shirt
(58, 153, 2, 599.75), -- Budget Desktop PC

-- Order 59
(59, 75, 3, 21.50), -- Henley Shirt
(59, 163, 1, 349.75), -- 12-Inch Tablet

-- Order 60
(60, 76, 1, 23.25), -- Striped Casual Shirt
(60, 173, 2, 999.75), -- Mid-Range DSLR

-- Order 61
(61, 77, 2, 27.99), -- Linen Shirt
(61, 183, 1, 199.75), -- Budget Smartphone

-- Order 62
(62, 78, 1, 25.50), -- Checkered Shirt
(62, 193, 2, 69.75), -- Organic Chemistry

-- Order 63
(63, 79, 3, 20.99), -- Short Sleeve Shirt
(63, 203, 1, 15.75), -- The Power of Habit

-- Order 64
(64, 80, 1, 26.75), -- Casual Button-Down
(64, 213, 2, 11.75), -- Percy Jackson Book 1

-- Order 65
(65, 84, 2, 11.99), -- Crew Neck Tee
(65, 223, 1, 11.75), -- Pride and Prejudice

-- Order 66
(66, 85, 1, 16.50), -- Long Sleeve Tee
(66, 233, 2, 22.75), -- Ulysses

-- Order 67
(67, 86, 3, 15.25), -- Crop T-Shirt
(67, 243, 1, 24.75), -- Harry Potter Audiobook

-- Order 68
(68, 87, 1, 14.50), -- Slogan T-Shirt
(68, 94, 2, 1299.99), -- 75-Inch 8K TV

-- Order 69
(69, 88, 2, 17.99), -- Tie-Dye T-Shirt
(69, 104, 1, 999.99), -- French Door Fridge

-- Order 70
(70, 89, 1, 10.99), -- Basic T-Shirt
(70, 114, 2, 349.99), -- Portable AC

-- Order 71
(71, 90, 3, 18.50), -- Oversized T-Shirt
(71, 124, 1, 499.99), -- 8kg Front Load

-- Order 72
(72, 95, 1, 599.50), -- 50-Inch QLED TV
(72, 134, 2, 1499.99), -- 17-Inch Laptop

-- Order 73
(73, 96, 2, 249.25), -- 32-Inch Smart TV
(73, 144, 1, 1399.99), -- 15-Inch Gaming Laptop

-- Order 74
(74, 97, 1, 699.99), -- 60-Inch 4K TV
(74, 154, 2, 999.99), -- All-in-One PC

-- Order 75
(75, 98, 3, 899.50), -- 70-Inch LED TV
(75, 164, 1, 249.99), -- Tablet with Stylus

-- Order 76
(76, 99, 1, 299.99), -- 40-Inch Smart TV
(76, 174, 2, 599.99), -- DSLR with Kit Lens

-- Order 77
(77, 100, 2, 1999.99), -- 85-Inch 4K TV
(77, 184, 1, 599.99), -- 5G Smartphone

-- Order 78
(78, 105, 1, 199.50), -- Mini Fridge
(78, 194, 2, 39.99), -- Economics 101

-- Order 79
(79, 106, 3, 649.25), -- Inverter Fridge
(79, 204, 1, 22.99), -- Educated

-- Order 80
(80, 107, 1, 579.99), -- Frost-Free Fridge
(80, 214, 2, 9.99), -- Charlotte’s Web

-- Order 81
(81, 108, 2, 1299.50), -- Smart Fridge
(81, 224, 1, 10.99), -- The Great Gatsby

-- Order 82
(82, 109, 1, 499.99), -- Top Freezer Fridge
(82, 234, 2, 15.99), -- The Odyssey

-- Order 83
(83, 110, 3, 699.99), -- Bottom Freezer Fridge
(83, 244, 1, 19.99), -- 1984 Audiobook

-- Order 84
(84, 115, 1, 329.50), -- 1 Ton Split AC
(84, 125, 2, 379.50), -- 7kg Top Load

-- Order 85
(85, 116, 2, 319.25), -- 1.5 Ton Window AC
(85, 135, 1, 799.50), -- 15-Inch Touchscreen

-- Order 86
(86, 117, 1, 599.99), -- 2.5 Ton Split AC
(86, 145, 2, 1899.50), -- 17-Inch Gaming Laptop

-- Order 87
(87, 118, 3, 429.50), -- Inverter AC 1.5 Ton
(87, 155, 1, 699.50), -- Mini Desktop PC

-- Order 88
(88, 119, 1, 379.99), -- Smart AC 1 Ton
(88, 165, 2, 129.50), -- Kids Tablet

-- Order 89
(89, 120, 2, 699.99), -- Cassette AC 2 Ton
(89, 175, 1, 1499.50), -- Full-Frame DSLR

-- Order 90
(90, 126, 1, 149.25), -- Portable Washer
(90, 185, 2, 799.50), -- Gaming Smartphone

-- Order 91
(91, 127, 3, 599.99), -- 10kg Front Load
(91, 195, 1, 45.50), -- Computer Science Basics

-- Order 92
(92, 128, 1, 229.50), -- 6.5kg Semi-Automatic
(92, 205, 2, 18.50), -- Atomic Habits

-- Order 93
(93, 129, 2, 429.99), -- 9kg Top Load
(93, 215, 1, 10.50), -- The Lion, the Witch

-- Order 94
(94, 130, 1, 479.99), -- Inverter Washer
(94, 225, 2, 13.50), -- The Catcher in the Rye

-- Order 95
(95, 136, 3, 1199.25), -- 13-Inch MacBook
(95, 235, 1, 18.50), -- Crime and Punishment

-- Order 96
(96, 137, 1, 899.99), -- 14-Inch Business Laptop
(96, 245, 2, 22.50), -- The Alchemist Audiobook

-- Order 97
(97, 138, 2, 499.50), -- 15-Inch Budget Laptop
(97, 1, 1, 29.99), -- Blue Formal Shirt (reusing)

-- Order 98
(98, 139, 1, 1099.99), -- 16-Inch Laptop
(98, 11, 2, 24.99), -- Floral Blouse (reusing)

-- Order 99
(99, 140, 3, 799.99), -- 13-Inch Lightweight
(99, 21, 1, 19.99), -- Black Trackpants (reusing)

-- Order 100
(100, 146, 1, 1499.25), -- Gaming Laptop RGB
(100, 31, 2, 49.99), -- Rose Gold Watch (reusing)

-- Order 101
(101, 147, 2, 999.99), -- Budget Gaming Laptop
(101, 41, 1, 34.99), -- Khaki Cargo Pants (reusing)

-- Order 102
(102, 148, 1, 1599.50), -- Gaming Laptop 144Hz
(102, 51, 2, 49.99), -- Black Sports Watch (reusing)

-- Order 103
(103, 149, 3, 1699.99), -- 16-Inch Gaming Laptop
(103, 61, 1, 39.99), -- High-Waist Jeans (reusing)

-- Order 104
(104, 150, 1, 2499.99), -- High-End Gaming Laptop
(104, 71, 2, 24.99), -- Plaid Casual Shirt (reusing)

-- Order 105
(105, 156, 2, 2499.25), -- High-End Desktop
(105, 81, 1, 14.99), -- Graphic T-Shirt (reusing)

-- Order 106
(106, 157, 1, 799.99), -- Office Desktop PC
(106, 91, 2, 499.99), -- 55-Inch 4K Smart TV (reusing)

-- Order 107
(107, 158, 3, 1399.50), -- Custom Desktop PC
(107, 101, 1, 599.99), -- Double Door Fridge (reusing)

-- Order 108
(108, 159, 1, 1099.99), -- Compact Desktop PC
(108, 111, 2, 399.99), -- 1.5 Ton Split AC (reusing)

-- Order 109
(109, 160, 2, 899.99), -- Media Desktop PC
(109, 121, 1, 449.99), -- Front Load Washer (reusing)

-- Order 110
(110, 166, 1, 499.25), -- High-End Tablet
(110, 131, 2, 699.99), -- 15-Inch Laptop (reusing)

-- Order 111
(111, 167, 3, 99.99), -- Budget Tablet
(111, 141, 1, 1299.99), -- Gaming Laptop RTX 3060 (reusing)

-- Order 112
(112, 168, 1, 299.50), -- Tablet with Keyboard
(112, 151, 2, 1199.99), -- Gaming Desktop PC (reusing)

-- Order 113
(113, 169, 2, 179.99), -- Android Tablet
(113, 161, 1, 199.99), -- 10-Inch Tablet (reusing)

-- Order 114
(114, 170, 1, 399.99), -- iPad 10-Inch
(114, 171, 2, 499.99), -- Entry-Level DSLR (reusing)

-- Order 115
(115, 176, 3, 799.25), -- DSLR for Vlogging
(115, 181, 1, 399.99), -- Smartphone 128GB (reusing)

-- Order 116
(116, 177, 1, 1299.99), -- Sports DSLR
(116, 191, 2, 59.99), -- Calculus Textbook (reusing)

-- Order 117
(117, 178, 2, 699.50), -- Compact DSLR
(117, 201, 1, 19.99), -- Sapiens (reusing)

-- Order 118
(118, 179, 1, 899.99), -- DSLR with Wi-Fi
(118, 211, 2, 12.99), -- Harry Potter Book 1 (reusing)

-- Order 119
(119, 180, 3, 1599.99), -- Advanced DSLR
(119, 221, 1, 14.99), -- To Kill a Mockingbird (reusing)

-- Order 120
(120, 186, 1, 499.25), -- Camera Phone
(120, 231, 2, 19.99), -- Moby-Dick (reusing)

-- Order 121
(121, 187, 2, 1299.99), -- Foldable Phone
(121, 241, 1, 29.99), -- Sapiens Audiobook (reusing)

-- Order 122
(122, 188, 1, 349.50), -- Mid-Range Phone
(122, 62, 2, 34.50), -- Skinny Jeans (reusing)

-- Order 123
(123, 189, 3, 799.99), -- iPhone 14
(123, 72, 1, 29.50), -- Denim Casual Shirt (reusing)

-- Order 124
(124, 190, 1, 299.99), -- Android Phone
(124, 82, 2, 12.50), -- V-Neck T-Shirt (reusing)

-- Order 125
(125, 196, 2, 55.25), -- Statistics for Beginners
(125, 92, 1, 799.50), -- 65-Inch OLED TV (reusing)

-- Order 126
(126, 197, 1, 49.99), -- Biology Textbook
(126, 102, 2, 899.50), -- Side-by-Side Fridge (reusing)

-- Order 127
(127, 198, 3, 35.50), -- Algebra Made Easy
(127, 112, 1, 299.50), -- Window AC 1 Ton (reusing)

-- Order 128
(128, 199, 1, 42.99), -- History of Science
(128, 122, 2, 349.50), -- Top Load Washer (reusing)

-- Order 129
(129, 200, 2, 65.99), -- Engineering Mechanics
(129, 132, 1, 999.50), -- 13-Inch Ultrabook (reusing)

-- Order 130
(130, 206, 1, 21.25), -- Thinking, Fast and Slow
(130, 142, 2, 1799.50), -- Gaming Laptop RTX 3070 (reusing)

-- Order 131
(131, 207, 3, 17.99), -- The Subtle Art
(131, 152, 1, 1799.50), -- Workstation PC (reusing)

-- Order 132
(132, 208, 1, 16.50), -- Outliers
(132, 162, 2, 149.50), -- 8-Inch Tablet (reusing)

-- Order 133
(133, 209, 2, 19.99), -- Grit
(133, 172, 1, 1999.50), -- Professional DSLR (reusing)

-- Order 134
(134, 210, 1, 14.99), -- Man’s Search for Meaning
(134, 182, 2, 999.50), -- Flagship Phone (reusing)

-- Order 135
(135, 216, 3, 13.25), -- Diary of a Wimpy Kid
(135, 192, 1, 49.50), -- Physics for Engineers (reusing)

-- Order 136
(136, 217, 1, 8.99), -- Matilda
(136, 202, 2, 24.50), -- Becoming (reusing)

-- Order 137
(137, 218, 2, 9.50), -- The Secret Garden
(137, 212, 1, 14.50), -- The Hobbit (reusing)

-- Order 138
(138, 219, 1, 11.99), -- Holes
(138, 222, 2, 12.50), -- 1984 (reusing)

-- Order 139
(139, 220, 3, 12.50), -- Wonder
(139, 232, 1, 24.50), -- War and Peace (reusing)

-- Order 140
(140, 226, 1, 9.25), -- Lord of the Flies
(140, 242, 2, 34.50), -- Becoming Audiobook (reusing)

-- Order 141
(141, 227, 2, 8.99), -- Animal Farm
(141, 63, 1, 37.75), -- Ripped Jeans (reusing)

-- Order 142
(142, 228, 1, 12.50), -- Brave New World
(142, 73, 2, 19.75), -- Graphic Tee (reusing)

-- Order 143
(143, 229, 3, 14.99), -- The Alchemist
(143, 83, 1, 13.75), -- Striped T-Shirt (reusing)

-- Order 144
(144, 230, 1, 16.50), -- Dune
(144, 93, 2, 349.75), -- 43-Inch LED TV (reusing)

-- Order 145
(145, 236, 2, 21.25), -- Les Misérables
(145, 103, 1, 349.75), -- Single Door Fridge (reusing)

-- Order 146
(146, 237, 1, 14.99), -- Jane Eyre
(146, 113, 2, 499.75), -- 2 Ton Inverter AC (reusing)

-- Order 147
(147, 238, 3, 13.50), -- Wuthering Heights
(147, 123, 1, 199.75), -- Semi-Automatic Washer (reusing)

-- Order 148
(148, 239, 1, 16.99), -- Great Expectations
(148, 133, 2, 649.75), -- 14-Inch Laptop (reusing)

-- Order 149
(149, 240, 2, 20.50), -- Anna Karenina
(149, 143, 1, 1999.75), -- Gaming Laptop Ryzen 9 (reusing)

-- Order 150
(150, 246, 1, 27.25), -- Atomic Habits Audiobook
(150, 153, 2, 599.75), -- Budget Desktop PC (reusing)

-- Order 151
(151, 247, 3, 18.99), -- Pride and Prejudice Audiobook
(151, 163, 1, 349.75), -- 12-Inch Tablet (reusing)

-- Order 152
(152, 248, 1, 26.50), -- The Hobbit Audiobook
(152, 173, 2, 999.75), -- Mid-Range DSLR (reusing)

-- Order 153
(153, 249, 2, 29.99),

-- Order 154 (User 101, Delivered)
(154, 1, 2, 29.99),    -- Blue Formal Shirt
(154, 91, 1, 499.99),  -- 55-Inch 4K Smart TV

-- Order 155 (User 101, Pending)
(155, 11, 1, 24.99),   -- Floral Blouse
(155, 21, 3, 19.99),   -- Black Trackpants

-- Order 156 (User 102, Shipped)
(156, 31, 2, 49.99),   -- Rose Gold Watch
(156, 61, 1, 39.99),   -- High-Waist Jeans

-- Order 157 (User 102, Returned)
(157, 71, 1, 24.99),   -- Plaid Casual Shirt
(157, 101, 2, 599.99), -- Double Door Fridge

-- Order 158 (User 103, Delivered)
(158, 2, 3, 34.99),    -- White Dress Shirt
(158, 131, 1, 699.99), -- 15-Inch Laptop

-- Order 159 (User 103, Cancelled)
(159, 41, 2, 34.99),   -- Khaki Cargo Pants
(159, 81, 1, 14.99),   -- Graphic T-Shirt

-- Order 160 (User 104, Shipped)
(160, 51, 1, 49.99),   -- Black Sports Watch
(160, 111, 2, 399.99), -- 1.5 Ton Split AC

-- Order 161 (User 104, Pending)
(161, 12, 3, 19.99),   -- Sleeveless Top
(161, 141, 1, 1299.99),-- Gaming Laptop RTX 3060

-- Order 162 (User 105, Delivered)
(162, 22, 2, 22.50),   -- Grey Joggers
(162, 151, 1, 1199.99),-- Gaming Desktop PC

-- Order 163 (User 105, Returned)
(163, 32, 1, 45.50),   -- Silver Analog Watch
(163, 161, 2, 199.99), -- 10-Inch Tablet

-- Order 164 (User 106, Shipped)
(164, 3, 3, 32.50),    -- Black Formal Shirt
(164, 171, 1, 499.99), -- Entry-Level DSLR

-- Order 165 (User 106, Cancelled)
(165, 13, 2, 22.50),   -- Off-Shoulder Top
(165, 181, 1, 399.99), -- Smartphone 128GB

-- Order 166 (User 107, Delivered)
(166, 23, 1, 21.75),   -- Navy Trackpants
(166, 191, 2, 59.99),  -- Calculus Textbook

-- Order 167 (User 107, Pending)
(167, 33, 3, 79.99),   -- Smart Watch Pink
(167, 201, 1, 19.99),  -- Sapiens

-- Order 168 (User 108, Shipped)
(168, 42, 2, 32.50),   -- Black Cargo Pants
(168, 211, 1, 12.99),  -- Harry Potter Book 1

-- Order 169 (User 108, Returned)
(169, 52, 1, 59.50),   -- Silver Chronograph
(169, 221, 2, 14.99),  -- To Kill a Mockingbird

-- Order 170 (User 109, Delivered)
(170, 4, 3, 31.75),    -- Striped Formal Shirt
(170, 231, 1, 19.99),  -- Moby-Dick

-- Order 171 (User 109, Cancelled)
(171, 14, 2, 27.75),   -- Lace Crop Top
(171, 241, 1, 29.99),  -- Sapiens Audiobook

-- Order 172 (User 110, Shipped)
(172, 24, 1, 20.99),   -- Red Trackpants
(172, 62, 2, 34.50),   -- Skinny Jeans

-- Order 173 (User 110, Pending)
(173, 34, 3, 59.75),   -- Gold Bracelet Watch
(173, 72, 1, 29.50),   -- Denim Casual Shirt

-- Order 174 (User 111, Delivered)
(174, 5, 2, 28.99),    -- Grey Formal Shirt
(174, 82, 1, 12.50),   -- V-Neck T-Shirt

-- Order 175 (User 111, Returned)
(175, 15, 1, 26.99),   -- Red Peplum Top
(175, 92, 2, 799.50),  -- 65-Inch OLED TV

-- Order 176 (User 112, Shipped)
(176, 25, 3, 23.50),   -- Green Joggers
(176, 102, 1, 899.50), -- Side-by-Side Fridge

-- Order 177 (User 112, Cancelled)
(177, 35, 2, 39.99),   -- Black Leather Watch
(177, 112, 1, 299.50); -- Window AC 1 Ton

SELECT *
FROM order_items;

SELECT u.user_id, u.username, SUM(i.quantity) AS total_quantity, SUM(i.quantity * i.price) AS order_sub_total, SUM(i.quantity * i.price * (1 - COALESCE(s.discount, 0) / 100)) AS user_revenue
FROM users u
JOIN orders o ON o.user_id = u.user_id
JOIN order_items i ON o.order_id = i.order_id
LEFT JOIN sale_coupon s ON o.coupon_id = s.coupon_id
WHERE o.order_status != 'Cancelled' AND year(o.order_date)=2021
GROUP BY o.user_id, u.username
ORDER BY user_revenue DESC;

SELECT t1.user_id, t1.username, SUM(t1.quantity) as quantities, SUM(t1.revenue) as total_revenue
FROM
(
	SELECT users.user_id as user_id, users.username as username, orders.order_id as order_id,SUM(order_items.quantity)as quantity,ANY_VALUE(IF(ISNULL(orders.coupon_id),SUM(order_items.price* order_items.quantity),SUM(order_items.price* order_items.quantity) *(1-sale_coupon.discount/100))) as revenue
    FROM users
    JOIN orders ON users.user_id = orders.user_id
    JOIN order_items ON order_items.order_id = orders.order_id
    LEFT JOIN sale_coupon ON sale_coupon.coupon_id = orders.coupon_id
    WHERE  orders.order_status != 'Cancelled'
    GROUP BY users.user_id, users.username, order_id ) as t1
GROUP BY t1.user_id, t1.username
ORDER BY t1.revenue DESC;

SELECT users.user_id as user_id, users.username as username, orders.order_id as order_id,SUM(order_items.quantity)as quantity,ANY_VALUE(IF(ISNULL(orders.coupon_id),SUM(order_items.price* order_items.quantity),SUM(order_items.price* order_items.quantity) *(1-sale_coupon.discount/100))) as revenue
FROM users
JOIN orders ON users.user_id = orders.user_id
JOIN order_items ON order_items.order_id = orders.order_id
LEFT JOIN sale_coupon ON sale_coupon.coupon_id = orders.coupon_id
WHERE  orders.order_status != 'Cancelled' AND YEAR(orders.order_date) = 2021
GROUP BY users.user_id, users.username, order_id;




SELECT o.user_id, u.username, COUNT(DISTINCT i.order_id) AS orders_placed, SUM(i.quantity) AS units, SUM(i.quantity*i.price) AS gross_sales
FROM order_items i
JOIN orders o ON i.order_id=o.order_id
JOIN users u ON u.user_id=o.user_id
WHERE YEAR(o.order_date)=2022 AND o.order_status != 'Cancelled'
GROUP BY o.user_id, u.username
ORDER BY gross_sales DESC LIMIT 5;

INSERT INTO reviews (user_id, product_id, vendor_id, rating_value, content, review_date, review_helpfulness)
VALUES
-- User 1 reviewing product 1 (Blue Formal Shirt, vendor 6)
(1, 1, 6, 4.5, 'Love this shirt! Fits perfectly and looks sharp for work. 😊👔', '2021-04-02 10:15:23', 5),

-- User 2 reviewing product 6 (Checkered Dress Shirt, vendor 23)
(2, 6, 23, 3.8, 'Nice shirt, but the color faded a bit after washing. 😐', '2022-08-11 09:22:11', 2),

-- User 3 reviewing product 8 (Red Formal Shirt, vendor 27)
(3, 8, 27, 5.0, 'Amazing quality! Perfect for my presentation. ⭐⭐⭐⭐⭐', '2020-12-16 10:30:43', 8),

-- User 4 reviewing product 10 (Formal Shirt with Tie, vendor 33)
(4, 10, 33, 4.0, 'Great combo! The tie matches perfectly. 👍', '2023-03-16 12:10:19', 4),

-- User 5 reviewing product 14 (Lace Crop Top, vendor 47)
(5, 14, 47, 4.2, 'Super cute top! Love the lace design. 💃', '2024-03-16 12:10:19', 6),

-- User 6 reviewing product 19 (Polka Dot Top, vendor 67)
(6, 19, 67, 3.5, 'Cute but a bit tight. Material is nice though! 😊', '2021-10-02 14:20:54', 3),

-- User 7 reviewing product 23 (Navy Trackpants, vendor 80)
(7, 23, 80, 4.8, 'Perfect for running! So comfy. 🏃‍♂️', '2023-03-11 13:25:56', 7),

-- User 8 reviewing product 25 (Green Joggers, vendor 88)
(8, 25, 88, 4.0, 'Good fit, love the pockets! Great for casual wear. 😎', '2020-07-02 09:15:48', 4),

-- User 9 reviewing product 27 (Striped Trackpants, vendor 6)
(9, 27, 6, 3.0, 'Okay, but the stripes started peeling off. 😕', '2023-12-06 15:40:38', 1),

-- User 10 reviewing product 28 (Cotton Trackpants, vendor 7)
(10, 28, 7, 4.5, 'Super soft and comfy! Great for lounging. 🛋️', '2021-03-16 09:12:49', 5),

-- User 11 reviewing product 35 (Black Leather Watch, vendor 31)
(11, 35, 31, 4.7, 'Elegant watch! Looks great with formal outfits. ⌚', '2024-03-21 14:20:15', 6),

-- User 12 reviewing product 37 (Blue Strap Watch, vendor 35)
(12, 37, 35, 3.9, 'Nice casual watch, but the strap feels a bit cheap. 😐', '2022-03-11 10:55:11', 3),

-- User 13 reviewing product 39 (Minimalist Watch, vendor 43)
(13, 39, 43, 4.3, 'Love the minimalist design! Perfect for daily wear. 😊', '2020-05-02 18:45:22', 5),

-- User 14 reviewing product 40 (Chronograph Watch, vendor 47)
(14, 40, 47, 5.0, 'Stunning watch! Worth every penny. ⭐⭐⭐⭐⭐', '2023-07-16 10:10:33', 9),

-- User 15 reviewing product 43 (Olive Green Cargo, vendor 60)
(15, 43, 60, 4.1, 'Great cargo pants! Lots of pockets for storage. 🎒', '2022-03-21 12:55:44', 4),

-- User 16 reviewing product 45 (Grey Cargo Pants, vendor 67)
(16, 45, 67, 3.7, 'Good fit, but the color faded a bit. Still decent! 😐', '2024-07-06 16:30:57', 2),

-- User 17 reviewing product 47 (Brown Cargo Pants, vendor 72)
(17, 47, 72, 4.6, 'Love these pants! Super durable for outdoor use. 🌲', '2020-09-02 08:25:11', 6),

-- User 18 reviewing product 48 (Slim Fit Cargo, vendor 76)
(18, 48, 76, 4.0, 'Nice slim fit! Looks stylish and practical. 👍', '2022-04-11 14:15:28', 4),

-- User 19 reviewing product 50 (Ripstop Cargo Pants, vendor 84)
(19, 50, 84, 4.8, 'Tough and rugged! Perfect for hiking. 🏞️', '2023-03-02 15:20:19', 7),

-- User 20 reviewing product 54 (Leather Strap Watch, vendor 7)
(20, 54, 7, 4.4, 'Classic watch! The leather strap is so comfy. ⌚', '2021-06-02 11:40:39', 5),

-- User 21 reviewing product 55 (Gold Analog Watch, vendor 11)
(21, 55, 11, 4.9, 'Luxury at its best! Looks amazing on my wrist. ✨', '2024-03-26 13:50:50', 8),

-- User 22 reviewing product 57 (Blue Strap Watch, vendor 19)
(22, 57, 19, 3.5, 'Looks nice but the strap broke after a month. 😕', '2020-10-16 15:20:01', 2),

-- User 23 reviewing product 58 (Fitness Tracker, vendor 23)
(23, 58, 23, 4.2, 'Great for tracking my runs! Battery life is good. 🏃', '2022-02-02 09:35:12', 5),

-- User 24 reviewing product 60 (Automatic Watch, vendor 27)
(24, 60, 27, 5.0, 'Absolutely stunning! A must-have for watch lovers. ⭐', '2023-05-11 17:10:23', 9),

-- User 25 reviewing product 65 (Flare Jeans, vendor 43)
(25, 65, 43, 4.0, 'Love the flare style! Perfect for a retro look. 👖', '2021-09-02 12:25:34', 4),

-- User 26 reviewing product 69 (Ankle-Length Jeans, vendor 60)
(26, 69, 60, 3.8, 'Nice fit, but the color isn’t as vibrant as shown. 😐', '2024-03-16 09:55:56', 3),

-- User 27 reviewing product 74 (Polo Shirt, vendor 76)
(27, 74, 76, 4.5, 'Comfy and stylish! Great for casual outings. 😎', '2021-01-01 16:00:07', 6),

-- User 28 reviewing product 76 (Striped Casual Shirt, vendor 84)
(28, 76, 84, 4.1, 'Love the stripes! Perfect for summer days. 🌞', '2022-07-02 16:05:07', 5),

-- User 29 reviewing product 77 (Linen Shirt, vendor 88)
(29, 77, 88, 4.7, 'So breathable! Ideal for hot weather. 🥳', '2023-03-02 08:15:18', 7),

-- User 30 reviewing product 79 (Short Sleeve Shirt, vendor 6)
(30, 79, 6, 3.9, 'Good shirt, but the fit is a bit loose. 😐', '2021-02-02 08:15:18', 3),

-- User 31 reviewing product 84 (Crew Neck Tee, vendor 26)
(31, 84, 26, 4.3, 'Soft and comfy tee! Great for everyday wear. 😊', '2024-03-02 11:30:29', 5),

-- User 32 reviewing product 85 (Long Sleeve Tee, vendor 27)
(32, 85, 27, 4.0, 'Nice tee, keeps me warm in cooler weather. ❄️', '2020-08-02 13:45:40', 4),

-- User 33 reviewing product 86 (Crop T-Shirt, vendor 31)
(33, 86, 31, 4.6, 'Super trendy! Love wearing this with jeans. 💃', '2022-03-16 15:00:51', 6),

-- User 34 reviewing product 88 (Tie-Dye T-Shirt, vendor 35)
(34, 88, 35, 4.2, 'Fun colors! Perfect for casual outings. 🌈', '2023-10-16 09:10:02', 5),

-- User 35 reviewing product 89 (Basic T-Shirt, vendor 39)
(35, 89, 39, 3.5, 'Basic but comfy. Good for the price. 😊', '2021-05-02 17:25:13', 3),

-- User 36 reviewing product 95 (50-Inch QLED TV, vendor 60)
(36, 95, 60, 4.8, 'Amazing picture quality! Love watching movies on this. 📺', '2024-08-02 12:40:24', 8),

-- User 37 reviewing product 97 (60-Inch 4K TV, vendor 67)
(37, 97, 67, 4.5, 'Great TV! The sound could be better though. 🎥', '2020-04-02 14:55:35', 6),

-- User 38 reviewing product 98 (70-Inch LED TV, vendor 71)
(38, 98, 71, 5.0, 'Fantastic TV! Feels like a home theater. ⭐⭐⭐⭐⭐', '2022-09-02 16:10:46', 9),

-- User 39 reviewing product 99 (40-Inch Smart TV, vendor 72)
(39, 99, 72, 4.0, 'Good TV for the price. Streaming apps work well. 📺', '2023-03-02 10:40:08', 4),

-- User 40 reviewing product 105 (Mini Fridge, vendor 6)
(40, 105, 6, 4.3, 'Perfect for my dorm! Keeps drinks cold. 🥤', '2021-07-16 10:40:08', 5),

-- User 41 reviewing product 106 (Inverter Fridge, vendor 7)
(41, 106, 7, 4.7, 'Energy efficient and spacious! Love it. ❄️', '2024-09-16 13:55:19', 7),

-- User 42 reviewing product 107 (Frost-Free Fridge, vendor 11)
(42, 107, 11, 4.1, 'Works well, but a bit noisy at times. 😐', '2020-05-16 09:20:41', 3),

-- User 43 reviewing product 109 (Top Freezer Fridge, vendor 19)
(43, 109, 19, 4.5, 'Great fridge! Keeps everything fresh. 🥕', '2022-11-26 11:00:00', 6),

-- User 44 reviewing product 110 (Bottom Freezer Fridge, vendor 23)
(44, 110, 23, 4.8, 'Love the design! So convenient to use. ❄️', '2023-03-02 09:15:41', 8),

-- User 45 reviewing product 115 (1 Ton Split AC, vendor 35)
(45, 115, 35, 4.0, 'Cools quickly! Good for small rooms. 🌬️', '2021-08-02 17:30:52', 4),

-- User 46 reviewing product 117 (2.5 Ton Split AC, vendor 43)
(46, 117, 43, 4.9, 'Powerful AC! Keeps my living room cool. 🥶', '2024-08-16 12:45:03', 9),

-- User 47 reviewing product 118 (Inverter AC 1.5 Ton, vendor 47)
(47, 118, 47, 4.2, 'Good AC, but installation took too long. 😐', '2020-11-02 14:00:14', 3),

-- User 48 reviewing product 119 (Smart AC 1 Ton, vendor 51)
(48, 119, 51, 4.6, 'Love the smart features! Works with my phone. 📱', '2022-04-16 16:15:25', 7),

-- User 49 reviewing product 126 (Portable Washer, vendor 76)
(49, 126, 76, 3.8, 'Compact and handy, but a bit slow. 🧼', '2023-06-16 08:30:36', 4),

-- User 50 reviewing product 127 (10kg Front Load, vendor 80)
(50, 127, 80, 5.0, 'Best washer ever! Clothes come out spotless. 🧼⭐', '2021-10-02 10:45:47', 9),

-- User 51 reviewing product 137 (14-Inch Business Laptop, vendor 26)
(51, 137, 26, 4.4, 'Great for work! Fast and reliable. 💻', '2024-10-16 15:15:09', 6),

-- User 52 reviewing product 138 (15-Inch Budget Laptop, vendor 27)
(52, 138, 27, 3.5, 'Decent for the price, but a bit slow. 😐', '2020-03-02 09:30:20', 2),

-- User 53 reviewing product 139 (16-Inch Laptop, vendor 31)
(53, 139, 31, 4.7, 'Love this laptop! Perfect for multitasking. 💻', '2022-06-02 11:45:31', 8),

-- User 54 reviewing product 140 (13-Inch Lightweight, vendor 33)
(54, 140, 33, 4.3, 'Super light and portable! Great for travel. ✈️', '2023-01-16 14:00:42', 5),

-- User 55 reviewing product 146 (Gaming Laptop RGB, vendor 52)
(55, 146, 52, 4.8, 'Amazing gaming laptop! The RGB is a bonus. 🎮', '2021-03-16 16:15:53', 7),

-- User 56 reviewing product 147 (Budget Gaming Laptop, vendor 60)
(56, 147, 60, 4.0, 'Good for casual gaming. Gets a bit hot though. 🎮', '2024-11-30 08:30:04', 4),

-- User 57 reviewing product 148 (Gaming Laptop 144Hz, vendor 63)
(57, 148, 63, 4.9, 'Smooth gameplay! The 144Hz display is awesome. 🕹️', '2020-08-16 10:45:15', 8),

-- User 58 reviewing product 149 (16-Inch Gaming Laptop, vendor 67)
(58, 149, 67, 4.5, 'Powerful laptop! Handles all my games easily. 🎮', '2022-10-16 13:00:26', 6),

-- User 59 reviewing product 150 (High-End Gaming Laptop, vendor 71)
(59, 150, 71, 5.0, 'Top-notch performance! Worth every penny. ⭐⭐⭐⭐⭐', '2023-04-02 15:15:37', 9),

-- User 60 reviewing product 156 (High-End Desktop, vendor 96)
(60, 156, 96, 4.7, 'Beast of a PC! Perfect for gaming and editing. 🖥️', '2024-11-30 09:45:48', 8),

-- User 61 reviewing product 158 (Custom Desktop PC, vendor 7)
(61, 158, 7, 4.2, 'Great custom build! Could use more USB ports. 🖥️', '2020-01-16 08:00:59', 5),

-- User 62 reviewing product 159 (Compact Desktop PC, vendor 11)
(62, 159, 11, 4.0, 'Compact and efficient! Good for small spaces. 🖱️', '2022-08-02 10:15:10', 4),

-- User 63 reviewing product 160 (Media Desktop PC, vendor 15)
(63, 160, 15, 4.5, 'Perfect for media editing! Runs smoothly. 🎬', '2023-04-16 12:30:21', 6),

-- User 64 reviewing product 166 (High-End Tablet, vendor 33)
(64, 166, 33, 4.8, 'Amazing tablet! Great for drawing and work. 📝', '2021-12-02 14:45:32', 7),

-- User 65 reviewing product 167 (Budget Tablet, vendor 35)
(65, 167, 35, 3.7, 'Good for basic use, but a bit slow. 😐', '2024-06-16 16:00:43', 3),

-- User 66 reviewing product 168 (Tablet with Keyboard, vendor 39)
(66, 168, 39, 4.4, 'Love the keyboard! Makes working on the go easy. 💼', '2020-12-16 09:15:54', 6),

-- User 67 reviewing product 169 (Android Tablet, vendor 43)
(67, 169, 43, 4.1, 'Nice tablet! Good for streaming and browsing. 📱', '2022-04-02 11:30:05', 5),

-- User 68 reviewing product 170 (iPad 10-Inch, vendor 47)
(68, 170, 47, 4.9, 'Best tablet I’ve owned! So smooth and fast. 🍎', '2023-08-16 13:45:16', 8),

-- User 69 reviewing product 176 (DSLR for Vlogging, vendor 71)
(69, 176, 71, 4.6, 'Great for vlogging! The flip screen is a lifesaver. 📸', '2021-03-02 15:00:27', 7),

-- User 70 reviewing product 177 (Sports DSLR, vendor 72)
(70, 177, 72, 4.3, 'Captures fast action perfectly! Love it. 📷', '2023-03-16 09:45:21', 6),

-- User 71 reviewing product 178 (Compact DSLR, vendor 76)
(71, 178, 76, 4.0, 'Compact and easy to carry! Good for beginners. 📸', '2024-05-16 12:00:38', 4),

-- User 72 reviewing product 179 (DSLR with Wi-Fi, vendor 80)
(72, 179, 80, 4.5, 'Love the Wi-Fi feature! Easy to transfer photos. 📷', '2020-05-02 14:15:49', 6),

-- User 73 reviewing product 180 (Advanced DSLR, vendor 84)
(73, 180, 84, 4.8, 'Professional quality! Amazing for photography. 📸', '2022-11-02 16:30:00', 8),

-- User 74 reviewing product 186 (Camera Phone, vendor 15)
(74, 186, 15, 4.2, 'Takes great photos! Battery life could be better. 📱', '2023-08-02 08:45:11', 5),

-- User 75 reviewing product 187 (Foldable Phone, vendor 19)
(75, 187, 19, 4.9, 'Innovative design! Love the foldable screen. 📱', '2021-06-16 10:00:22', 9),

-- User 76 reviewing product 196 (Statistics for Beginners, vendor 47)
(76, 196, 47, 4.0, 'Helpful book! Made stats easier to understand. 📚', '2024-09-16 12:15:33', 4),

-- User 77 reviewing product 197 (Biology Textbook, vendor 51)
(77, 197, 51, 4.5, 'Great for studying! Clear explanations. 📖', '2020-07-02 14:30:44', 6),

-- User 78 reviewing product 198 (Algebra Made Easy, vendor 52)
(78, 198, 52, 3.8, 'Good book, but some concepts were still tricky. 😐', '2022-02-02 16:45:55', 3),

-- User 79 reviewing product 199 (History of Science, vendor 60)
(79, 199, 60, 4.3, 'Fascinating read! Learned a lot about science history. 📜', '2023-12-16 09:00:06', 5),

-- User 80 reviewing product 200 (Engineering Mechanics, vendor 63)
(80, 200, 63, 4.7, 'Excellent textbook! Helped me ace my exams. 📘', '2024-09-02 14:20:32', 7),

-- User 81 reviewing product 206 (Thinking, Fast and Slow, vendor 84)
(81, 206, 84, 4.4, 'Thought-provoking book! Really enjoyed it. 📚', '2021-09-02 16:35:43', 6),

-- User 82 reviewing product 207 (The Subtle Art, vendor 88)
(82, 207, 88, 4.0, 'Funny and insightful! A good read. 😂', '2020-10-02 08:50:54', 4),

-- User 83 reviewing product 208 (Outliers, vendor 96)
(83, 208, 96, 4.5, 'Interesting perspective! Loved the stories. 📖', '2022-04-16 11:05:05', 6),

-- User 84 reviewing product 209 (Grit, vendor 6)
(84, 209, 6, 4.2, 'Motivational book! Helped me stay focused. 💪', '2023-12-02 13:20:16', 5),

-- User 85 reviewing product 210 (Man’s Search for Meaning, vendor 7)
(85, 210, 7, 4.8, 'Deeply moving! A must-read for everyone. 📚', '2021-08-02 15:35:27', 8),

-- User 86 reviewing product 216 (Diary of a Wimpy Kid, vendor 27)
(86, 216, 27, 4.0, 'My kid loves this book! So funny. 😂', '2024-09-02 09:50:38', 4),

-- User 87 reviewing product 217 (Matilda, vendor 31)
(87, 217, 31, 4.6, 'Such a charming story! My daughter loved it. 📖', '2020-04-02 12:05:49', 6),

-- User 88 reviewing product 218 (The Secret Garden, vendor 33)
(88, 218, 33, 4.3, 'Beautiful story! Perfect for young readers. 🌸', '2022-07-02 14:20:00', 5),

-- User 89 reviewing product 219 (Holes, vendor 35)
(89, 219, 35, 4.1, 'Great book! Kept my son engaged. 📚', '2023-05-16 16:35:11', 4),

-- User 90 reviewing product 220 (Wonder, vendor 39)
(90, 220, 39, 4.7, 'Heartwarming story! Teaches great lessons. ❤️', '2021-07-11 16:35:43', 7),

-- User 91 reviewing product 226 (Lord of the Flies, vendor 63)
(91, 226, 63, 4.0, 'Interesting read! A bit dark but thought-provoking. 📖', '2024-03-16 08:50:54', 4),

-- User 92 reviewing product 227 (Animal Farm, vendor 67)
(92, 227, 67, 4.5, 'Powerful allegory! Really makes you think. 🐷', '2020-08-02 11:05:05', 6),

-- User 93 reviewing product 228 (Brave New World, vendor 71)
(93, 228, 71, 4.2, 'Fascinating dystopia! A bit unsettling though. 📚', '2022-03-02 13:20:16', 5),

-- User 94 reviewing product 229 (The Alchemist, vendor 72)
(94, 229, 72, 4.8, 'Inspiring story! Loved the journey. 🌟', '2023-11-02 15:35:27', 7),

-- User 95 reviewing product 230 (Dune, vendor 76)
(95, 230, 76, 4.6, 'Epic sci-fi! Couldn’t put it down. 🚀', '2021-05-16 09:50:38', 6),

-- User 96 reviewing product 236 (Les Misérables, vendor 7)
(96, 236, 7, 4.4, 'Beautifully written! A literary masterpiece. 📜', '2024-07-16 12:05:49', 5),

-- User 97 reviewing product 237 (Jane Eyre, vendor 11)
(97, 237, 11, 4.7, 'Loved this classic! Jane is so inspiring. ❤️', '2020-06-02 14:20:00', 7),

-- User 98 reviewing product 238 (Wuthering Heights, vendor 15)
(98, 238, 15, 4.0, 'Intense story! A bit too dramatic for me. 📖', '2022-09-02 16:35:11', 4),

-- User 99 reviewing product 239 (Great Expectations, vendor 19)
(99, 239, 19, 4.5, 'Classic Dickens! Really enjoyed it. 📚', '2023-12-16 08:50:54', 6),

-- User 100 reviewing product 240 (Anna Karenina, vendor 23)
(100, 240, 23, 4.3, 'Beautifully written! A bit long but worth it. 📜', '2021-06-21 08:50:54', 5),

-- User 101 (Order 154, Delivered)
(101, 1, 6, 4.5, 'Really sharp shirt! Perfect for work meetings. 👔', '2025-01-08 10:30:00', 6),

-- User 102 (Order 157, Returned)
(102, 71, 67, 2.5, 'Disappointing shirt. Faded after one wash, had to return it. 😞', '2025-01-23 16:00:00', 2),

-- User 103 (Order 158, Delivered)
(103, 2, 7, 4.8, 'Fantastic dress shirt! Looks great and fits perfectly. ⭐', '2025-01-25 13:45:00', 7),

-- User 104 (Order 160, Shipped)
(104, 51, 88, 4.0, 'Cool sports watch! Shipping was quick, excited to use it. ⌚', '2025-02-01 11:00:00', 5),

-- User 105 (Order 162, Delivered)
(105, 22, 76, 4.6, 'Super comfy joggers! Great for workouts. 🏃‍♂️', '2025-01-10 12:15:00', 6),

-- User 106 (Order 165, Cancelled)
(106, 13, 43, 3.0, 'Looked nice online, but order got cancelled. Disappointing. 😕', '2025-02-19 10:45:00', 3),

-- User 107 (Order 166, Delivered)
(107, 23, 80, 4.7, 'Love these trackpants! So comfortable for running. 🏃', '2025-02-24 16:00:00', 7),

-- User 108 (Order 169, Returned)
(108, 52, 96, 2.8, 'Watch stopped working after a week. Had to return it. 😞', '2025-03-10 09:30:00', 2),

-- User 109 (Order 170, Delivered)
(109, 4, 15, 4.4, 'Stylish formal shirt! Perfect for office wear. 👕', '2025-02-07 11:15:00', 6),

-- User 110 (Order 172, Shipped)
(110, 24, 84, 3.8, 'Nice trackpants, shipped on time. Can’t wait to try them! 😊', '2025-03-14 10:00:00', 4),

-- User 111 (Order 174, Delivered)
(111, 5, 19, 4.9, 'Awesome grey shirt! Looks sharp and feels great. ⭐⭐⭐⭐⭐', '2025-03-22 14:00:00', 8),

-- User 112 (Order 177, Cancelled)
(112, 35, 31, 3.2, 'Wanted this watch, but order got cancelled. Not happy. 😐', '2025-03-27 20:00:00', 3);


SELECT *
FROM reviews;



INSERT INTO shopping_cart (user_id, product_id, quantity)
VALUES
-- User 1: Purchased formal shirts (e.g., product_id 1: Blue Formal Shirt), so add related items like shirts and ties
(1, 2, 2), -- White Dress Shirt (similar to Blue Formal Shirt)
(1, 10, 1), -- Formal Shirt with Tie (complementary item)
(1, 35, 1), -- Black Leather Watch (formal accessory)

-- User 2: Purchased shirts (e.g., product_id 6: Checkered Dress Shirt), add more shirts and a watch
(2, 7, 1), -- Navy Dress Shirt
(2, 9, 2), -- Green Formal Shirt
(2, 37, 1), -- Blue Strap Watch (casual accessory)

-- User 3: Purchased shirts (e.g., product_id 8: Red Formal Shirt), add shirts and pants
(3, 1, 3), -- Blue Formal Shirt
(3, 41, 1), -- Khaki Cargo Pants (to pair with shirts)
(3, 54, 1), -- Leather Strap Watch

-- User 4: Purchased shirts (e.g., product_id 10: Formal Shirt with Tie), add shirts and accessories
(4, 3, 2), -- Black Formal Shirt
(4, 39, 1), -- Minimalist Watch
(4, 79, 1), -- Short Sleeve Shirt (casual option)

-- User 5: Purchased tops (e.g., product_id 14: Lace Crop Top), add more tops and jeans
(5, 15, 2), -- Off-Shoulder Top
(5, 65, 1), -- Flare Jeans (to pair with tops)
(5, 86, 1), -- Crop T-Shirt

-- User 6: Purchased tops (e.g., product_id 19: Polka Dot Top), add tops and accessories
(6, 11, 1), -- Floral Blouse
(6, 17, 2), -- Striped Crop Top
(6, 31, 1), -- Rose Gold Watch

-- User 7: Purchased trackpants (e.g., product_id 23: Navy Trackpants), add more trackpants and a watch
(7, 24, 2), -- Grey Trackpants
(7, 28, 1), -- Cotton Trackpants
(7, 58, 1), -- Fitness Tracker (for running)

-- User 8: Purchased joggers (e.g., product_id 25: Green Joggers), add joggers and casual shirts
(8, 26, 1), -- Blue Joggers
(8, 74, 2), -- Polo Shirt
(8, 85, 1), -- Long Sleeve Tee

-- User 9: Purchased trackpants (e.g., product_id 27: Striped Trackpants), add trackpants and casual wear
(9, 21, 3), -- Black Trackpants
(9, 76, 1), -- Striped Casual Shirt
(9, 89, 1), -- Basic T-Shirt

-- User 10: Purchased trackpants (e.g., product_id 28: Cotton Trackpants), add trackpants and fitness gear
(10, 22, 2), -- White Trackpants
(10, 23, 1), -- Navy Trackpants
(10, 58, 1), -- Fitness Tracker

-- User 11: Purchased watches (e.g., product_id 35: Black Leather Watch), add watches and formal shirts
(11, 36, 1), -- Silver Analog Watch
(11, 40, 1), -- Chronograph Watch
(11, 1, 2), -- Blue Formal Shirt

-- User 12: Purchased watches (e.g., product_id 37: Blue Strap Watch), add watches and casual shirts
(12, 38, 2), -- Gold Strap Watch
(12, 55, 1), -- Gold Analog Watch
(12, 77, 1), -- Linen Shirt

-- User 13: Purchased watches (e.g., product_id 39: Minimalist Watch), add watches and accessories
(13, 31, 1), -- Rose Gold Watch
(13, 54, 1), -- Leather Strap Watch
(13, 74, 2), -- Polo Shirt

-- User 14: Purchased watches (e.g., product_id 40: Chronograph Watch), add watches and formal wear
(14, 35, 1), -- Black Leather Watch
(14, 3, 2), -- Black Formal Shirt
(14, 41, 1), -- Khaki Cargo Pants

-- User 15: Purchased cargo pants (e.g., product_id 43: Olive Green Cargo), add cargo pants and casual shirts
(15, 44, 2), -- Black Cargo Pants
(15, 48, 1), -- Slim Fit Cargo
(15, 76, 1), -- Striped Casual Shirt

-- User 16: Purchased cargo pants (e.g., product_id 45: Grey Cargo Pants), add cargo pants and tees
(16, 46, 1), -- Navy Cargo Pants
(16, 50, 1), -- Ripstop Cargo Pants
(16, 84, 2), -- Crew Neck Tee

-- User 17: Purchased cargo pants (e.g., product_id 47: Brown Cargo Pants), add cargo pants and outdoor gear
(17, 43, 2), -- Olive Green Cargo
(17, 49, 1), -- Beige Cargo Pants
(17, 85, 1), -- Long Sleeve Tee

-- User 18: Purchased cargo pants (e.g., product_id 48: Slim Fit Cargo), add cargo pants and casual wear
(18, 44, 1), -- Black Cargo Pants
(18, 77, 2), -- Linen Shirt
(18, 89, 1), -- Basic T-Shirt

-- User 19: Purchased cargo pants (e.g., product_id 50: Ripstop Cargo Pants), add cargo pants and outdoor gear
(19, 45, 1), -- Grey Cargo Pants
(19, 47, 2), -- Brown Cargo Pants
(19, 58, 1), -- Fitness Tracker

-- User 20: Purchased watches (e.g., product_id 54: Leather Strap Watch), add watches and formal shirts
(20, 36, 1), -- Silver Analog Watch
(20, 39, 1), -- Minimalist Watch
(20, 2, 2), -- White Dress Shirt

-- User 21: Purchased watches (e.g., product_id 55: Gold Analog Watch), add watches and formal wear
(21, 37, 1), -- Blue Strap Watch
(21, 60, 1), -- Automatic Watch
(21, 10, 2), -- Formal Shirt with Tie

-- User 22: Purchased watches (e.g., product_id 57: Blue Strap Watch), add watches and casual shirts
(22, 38, 2), -- Gold Strap Watch
(22, 54, 1), -- Leather Strap Watch
(22, 79, 1), -- Short Sleeve Shirt

-- User 23: Purchased fitness trackers (e.g., product_id 58: Fitness Tracker), add fitness gear and trackpants
(23, 23, 1), -- Navy Trackpants
(23, 24, 2), -- Grey Trackpants
(23, 85, 1), -- Long Sleeve Tee

-- User 24: Purchased watches (e.g., product_id 60: Automatic Watch), add watches and formal shirts
(24, 35, 1), -- Black Leather Watch
(24, 55, 1), -- Gold Analog Watch
(24, 3, 2), -- Black Formal Shirt

-- User 25: Purchased jeans (e.g., product_id 65: Flare Jeans), add jeans and tops
(25, 66, 2), -- High-Waisted Jeans
(25, 15, 1), -- Off-Shoulder Top
(25, 86, 1), -- Crop T-Shirt

-- User 26: Purchased jeans (e.g., product_id 69: Ankle-Length Jeans), add jeans and casual wear
(26, 65, 1), -- Flare Jeans
(26, 17, 2), -- Striped Crop Top
(26, 88, 1), -- Tie-Dye T-Shirt

-- User 27: Purchased polo shirts (e.g., product_id 74: Polo Shirt), add casual shirts and pants
(27, 76, 1), -- Striped Casual Shirt
(27, 79, 2), -- Short Sleeve Shirt
(27, 41, 1), -- Khaki Cargo Pants

-- User 28: Purchased casual shirts (e.g., product_id 76: Striped Casual Shirt), add casual shirts and tees
(28, 74, 2), -- Polo Shirt
(28, 77, 1), -- Linen Shirt
(28, 84, 1), -- Crew Neck Tee

-- User 29: Purchased linen shirts (e.g., product_id 77: Linen Shirt), add casual shirts and pants
(29, 79, 1), -- Short Sleeve Shirt
(29, 85, 2), -- Long Sleeve Tee
(29, 43, 1), -- Olive Green Cargo

-- User 30: Purchased short sleeve shirts (e.g., product_id 79: Short Sleeve Shirt), add casual shirts and tees
(30, 74, 1), -- Polo Shirt
(30, 88, 2), -- Tie-Dye T-Shirt
(30, 89, 1), -- Basic T-Shirt

-- User 31: Purchased tees (e.g., product_id 84: Crew Neck Tee), add tees and casual pants
(31, 85, 1), -- Long Sleeve Tee
(31, 86, 2), -- Crop T-Shirt
(31, 21, 1), -- Black Trackpants

-- User 32: Purchased tees (e.g., product_id 85: Long Sleeve Tee), add tees and casual shirts
(32, 84, 2), -- Crew Neck Tee
(32, 88, 1), -- Tie-Dye T-Shirt
(32, 76, 1), -- Striped Casual Shirt

-- User 33: Purchased crop tees (e.g., product_id 86: Crop T-Shirt), add tops and jeans
(33, 15, 1), -- Off-Shoulder Top
(33, 17, 2), -- Striped Crop Top
(33, 65, 1), -- Flare Jeans

-- User 34: Purchased tie-dye tees (e.g., product_id 88: Tie-Dye T-Shirt), add tees and casual wear
(34, 84, 1), -- Crew Neck Tee
(34, 86, 2), -- Crop T-Shirt
(34, 69, 1), -- Ankle-Length Jeans

-- User 35: Purchased basic tees (e.g., product_id 89: Basic T-Shirt), add tees and casual shirts
(35, 85, 2), -- Long Sleeve Tee
(35, 74, 1), -- Polo Shirt
(35, 77, 1), -- Linen Shirt

-- User 36: Purchased TVs (e.g., product_id 95: 50-Inch QLED TV), add electronics and accessories
(36, 97, 1), -- 60-Inch 4K TV
(36, 99, 1), -- 40-Inch Smart TV
(36, 137, 1), -- 14-Inch Business Laptop

-- User 37: Purchased TVs (e.g., product_id 97: 60-Inch 4K TV), add electronics
(37, 98, 1), -- 70-Inch LED TV
(37, 95, 1), -- 50-Inch QLED TV
(37, 146, 1), -- Gaming Laptop RGB

-- User 38: Purchased TVs (e.g., product_id 98: 70-Inch LED TV), add electronics
(38, 99, 1), -- 40-Inch Smart TV
(38, 95, 1), -- 50-Inch QLED TV
(38, 147, 1), -- Budget Gaming Laptop

-- User 39: Purchased TVs (e.g., product_id 99: 40-Inch Smart TV), add electronics
(39, 97, 1), -- 60-Inch 4K TV
(39, 98, 1), -- 70-Inch LED TV
(39, 148, 1), -- Gaming Laptop 144Hz

-- User 40: Purchased fridges (e.g., product_id 105: Mini Fridge), add fridges and appliances
(40, 106, 1), -- Inverter Fridge
(40, 107, 1), -- Frost-Free Fridge
(40, 115, 1), -- 1 Ton Split AC

-- User 41: Purchased fridges (e.g., product_id 106: Inverter Fridge), add fridges and appliances
(41, 105, 1), -- Mini Fridge
(41, 109, 1), -- Top Freezer Fridge
(41, 117, 1), -- 2.5 Ton Split AC

-- User 42: Purchased fridges (e.g., product_id 107: Frost-Free Fridge), add fridges and appliances
(42, 106, 1), -- Inverter Fridge
(42, 110, 1), -- Bottom Freezer Fridge
(42, 118, 1), -- Inverter AC 1.5 Ton

-- User 43: Purchased fridges (e.g., product_id 109: Top Freezer Fridge), add fridges and appliances
(43, 105, 1), -- Mini Fridge
(43, 107, 1), -- Frost-Free Fridge
(43, 119, 1), -- Smart AC 1 Ton

-- User 44: Purchased fridges (e.g., product_id 110: Bottom Freezer Fridge), add fridges and appliances
(44, 106, 1), -- Inverter Fridge
(44, 109, 1), -- Top Freezer Fridge
(44, 126, 1), -- Portable Washer

-- User 45: Purchased ACs (e.g., product_id 115: 1 Ton Split AC), add ACs and appliances
(45, 117, 1), -- 2.5 Ton Split AC
(45, 118, 1), -- Inverter AC 1.5 Ton
(45, 105, 1), -- Mini Fridge

-- User 46: Purchased ACs (e.g., product_id 117: 2.5 Ton Split AC), add ACs and appliances
(46, 115, 1), -- 1 Ton Split AC
(46, 119, 1), -- Smart AC 1 Ton
(46, 127, 1), -- 10kg Front Load Washer

-- User 47: Purchased ACs (e.g., product_id 118: Inverter AC 1.5 Ton), add ACs and appliances
(47, 115, 1), -- 1 Ton Split AC
(47, 117, 1), -- 2.5 Ton Split AC
(47, 106, 1), -- Inverter Fridge

-- User 48: Purchased ACs (e.g., product_id 119: Smart AC 1 Ton), add ACs and appliances
(48, 118, 1), -- Inverter AC 1.5 Ton
(48, 115, 1), -- 1 Ton Split AC
(48, 109, 1), -- Top Freezer Fridge

-- User 49: Purchased washers (e.g., product_id 126: Portable Washer), add washers and appliances
(49, 127, 1), -- 10kg Front Load Washer
(49, 105, 1), -- Mini Fridge
(49, 117, 1), -- 2.5 Ton Split AC

-- User 50: Purchased washers (e.g., product_id 127: 10kg Front Load), add washers and appliances
(50, 126, 1), -- Portable Washer
(50, 106, 1), -- Inverter Fridge
(50, 119, 1), -- Smart AC 1 Ton

-- User 51: Purchased laptops (e.g., product_id 137: 14-Inch Business Laptop), add laptops and electronics
(51, 138, 1), -- 15-Inch Budget Laptop
(51, 139, 1), -- 16-Inch Laptop
(51, 166, 1), -- High-End Tablet

-- User 52: Purchased laptops (e.g., product_id 138: 15-Inch Budget Laptop), add laptops and electronics
(52, 137, 1), -- 14-Inch Business Laptop
(52, 140, 1), -- 13-Inch Lightweight Laptop
(52, 167, 1), -- Budget Tablet

-- User 53: Purchased laptops (e.g., product_id 139: 16-Inch Laptop), add laptops and electronics
(53, 138, 1), -- 15-Inch Budget Laptop
(53, 146, 1), -- Gaming Laptop RGB
(53, 168, 1), -- Tablet with Keyboard

-- User 54: Purchased laptops (e.g., product_id 140: 13-Inch Lightweight), add laptops and electronics
(54, 137, 1), -- 14-Inch Business Laptop
(54, 147, 1), -- Budget Gaming Laptop
(54, 169, 1), -- Android Tablet

-- User 55: Purchased gaming laptops (e.g., product_id 146: Gaming Laptop RGB), add gaming laptops and electronics
(55, 147, 1), -- Budget Gaming Laptop
(55, 148, 1), -- Gaming Laptop 144Hz
(55, 156, 1), -- High-End Desktop

-- User 56: Purchased gaming laptops (e.g., product_id 147: Budget Gaming Laptop), add gaming laptops and electronics
(56, 146, 1), -- Gaming Laptop RGB
(56, 149, 1), -- 16-Inch Gaming Laptop
(56, 158, 1), -- Custom Desktop PC

-- User 57: Purchased gaming laptops (e.g., product_id 148: Gaming Laptop 144Hz), add gaming laptops and electronics
(57, 147, 1), -- Budget Gaming Laptop
(57, 150, 1), -- High-End Gaming Laptop
(57, 159, 1), -- Compact Desktop PC

-- User 58: Purchased gaming laptops (e.g., product_id 149: 16-Inch Gaming Laptop), add gaming laptops and electronics
(58, 146, 1), -- Gaming Laptop RGB
(58, 148, 1), -- Gaming Laptop 144Hz
(58, 160, 1), -- Media Desktop PC

-- User 59: Purchased gaming laptops (e.g., product_id 150: High-End Gaming Laptop), add gaming laptops and electronics
(59, 149, 1), -- 16-Inch Gaming Laptop
(59, 147, 1), -- Budget Gaming Laptop
(59, 156, 1), -- High-End Desktop

-- User 60: Purchased desktops (e.g., product_id 156: High-End Desktop), add desktops and electronics
(60, 158, 1), -- Custom Desktop PC
(60, 159, 1), -- Compact Desktop PC
(60, 166, 1), -- High-End Tablet

-- User 61: Purchased desktops (e.g., product_id 158: Custom Desktop PC), add desktops and electronics
(61, 156, 1), -- High-End Desktop
(61, 160, 1), -- Media Desktop PC
(61, 167, 1), -- Budget Tablet

-- User 62: Purchased desktops (e.g., product_id 159: Compact Desktop PC), add desktops and electronics
(62, 158, 1), -- Custom Desktop PC
(62, 156, 1), -- High-End Desktop
(62, 168, 1), -- Tablet with Keyboard

-- User 63: Purchased desktops (e.g., product_id 160: Media Desktop PC), add desktops and electronics
(63, 159, 1), -- Compact Desktop PC
(63, 156, 1), -- High-End Desktop
(63, 169, 1), -- Android Tablet

-- User 64: Purchased tablets (e.g., product_id 166: High-End Tablet), add tablets and electronics
(64, 167, 1), -- Budget Tablet
(64, 168, 1), -- Tablet with Keyboard
(64, 137, 1), -- 14-Inch Business Laptop

-- User 65: Purchased tablets (e.g., product_id 167: Budget Tablet), add tablets and electronics
(65, 166, 1), -- High-End Tablet
(65, 169, 1), -- Android Tablet
(65, 138, 1), -- 15-Inch Budget Laptop

-- User 66: Purchased tablets (e.g., product_id 168: Tablet with Keyboard), add tablets and electronics
(66, 167, 1), -- Budget Tablet
(66, 170, 1), -- iPad 10-Inch
(66, 139, 1), -- 16-Inch Laptop

-- User 67: Purchased tablets (e.g., product_id 169: Android Tablet), add tablets and electronics
(67, 166, 1), -- High-End Tablet
(67, 168, 1), -- Tablet with Keyboard
(67, 140, 1), -- 13-Inch Lightweight Laptop

-- User 68: Purchased tablets (e.g., product_id 170: iPad 10-Inch), add tablets and electronics
(68, 169, 1), -- Android Tablet
(68, 167, 1), -- Budget Tablet
(68, 146, 1), -- Gaming Laptop RGB

-- User 69: Purchased cameras (e.g., product_id 176: DSLR for Vlogging), add cameras and electronics
(69, 177, 1), -- Sports DSLR
(69, 178, 1), -- Compact DSLR
(69, 186, 1), -- Camera Phone

-- User 70: Purchased cameras (e.g., product_id 177: Sports DSLR), add cameras and electronics
(70, 176, 1), -- DSLR for Vlogging
(70, 179, 1), -- DSLR with Wi-Fi
(70, 187, 1), -- Foldable Phone

-- User 71: Purchased cameras (e.g., product_id 178: Compact DSLR), add cameras and electronics
(71, 177, 1), -- Sports DSLR
(71, 180, 1), -- Advanced DSLR
(71, 186, 1), -- Camera Phone

-- User 72: Purchased cameras (e.g., product_id 179: DSLR with Wi-Fi), add cameras and electronics
(72, 176, 1), -- DSLR for Vlogging
(72, 178, 1), -- Compact DSLR
(72, 187, 1), -- Foldable Phone

-- User 73: Purchased cameras (e.g., product_id 180: Advanced DSLR), add cameras and electronics
(73, 179, 1), -- DSLR with Wi-Fi
(73, 177, 1), -- Sports DSLR
(73, 186, 1), -- Camera Phone

-- User 74: Purchased phones (e.g., product_id 186: Camera Phone), add phones and electronics
(74, 187, 1), -- Foldable Phone
(74, 166, 1), -- High-End Tablet
(74, 176, 1), -- DSLR for Vlogging

-- User 75: Purchased phones (e.g., product_id 187: Foldable Phone), add phones and electronics
(75, 186, 1), -- Camera Phone
(75, 167, 1), -- Budget Tablet
(75, 177, 1), -- Sports DSLR

-- User 76: Purchased books (e.g., product_id 196: Statistics for Beginners), add books
(76, 197, 1), -- Biology Textbook
(76, 198, 1), -- Algebra Made Easy
(76, 199, 1), -- History of Science

-- User 77: Purchased books (e.g., product_id 197: Biology Textbook), add books
(77, 196, 1), -- Statistics for Beginners
(77, 200, 1), -- Engineering Mechanics
(77, 198, 1), -- Algebra Made Easy

-- User 78: Purchased books (e.g., product_id 198: Algebra Made Easy), add books
(78, 199, 1), -- History of Science
(78, 200, 1), -- Engineering Mechanics
(78, 196, 1), -- Statistics for Beginners

-- User 79: Purchased books (e.g., product_id 199: History of Science), add books
(79, 196, 1), -- Statistics for Beginners
(79, 197, 1), -- Biology Textbook
(79, 200, 1), -- Engineering Mechanics

-- User 80: Purchased books (e.g., product_id 200: Engineering Mechanics), add books
(80, 198, 1), -- Algebra Made Easy
(80, 199, 1), -- History of Science
(80, 197, 1), -- Biology Textbook

-- User 81: Purchased books (e.g., product_id 206: Thinking, Fast and Slow), add books
(81, 207, 1), -- The Subtle Art
(81, 208, 1), -- Outliers
(81, 209, 1), -- Grit

-- User 82: Purchased books (e.g., product_id 207: The Subtle Art), add books
(82, 206, 1), -- Thinking, Fast and Slow
(82, 210, 1), -- Man’s Search for Meaning
(82, 208, 1), -- Outliers

-- User 83: Purchased books (e.g., product_id 208: Outliers), add books
(83, 209, 1), -- Grit
(83, 210, 1), -- Man’s Search for Meaning
(83, 206, 1), -- Thinking, Fast and Slow

-- User 84: Purchased books (e.g., product_id 209: Grit), add books
(84, 208, 1), -- Outliers
(84, 207, 1), -- The Subtle Art
(84, 210, 1), -- Man’s Search for Meaning

-- User 85: Purchased books (e.g., product_id 210: Man’s Search for Meaning), add books
(85, 206, 1), -- Thinking, Fast and Slow
(85, 209, 1), -- Grit
(85, 207, 1), -- The Subtle Art

-- User 86: Purchased books (e.g., product_id 216: Diary of a Wimpy Kid), add books
(86, 217, 1), -- Matilda
(86, 218, 1), -- The Secret Garden
(86, 219, 1), -- Holes

-- User 87: Purchased books (e.g., product_id 217: Matilda), add books
(87, 216, 1), -- Diary of a Wimpy Kid
(87, 220, 1), -- Wonder
(87, 218, 1), -- The Secret Garden

-- User 88: Purchased books (e.g., product_id 218: The Secret Garden), add books
(88, 219, 1), -- Holes
(88, 220, 1), -- Wonder
(88, 216, 1), -- Diary of a Wimpy Kid

-- User 89: Purchased books (e.g., product_id 219: Holes), add books
(89, 218, 1), -- The Secret Garden
(89, 217, 1), -- Matilda
(89, 220, 1), -- Wonder

-- User 90: Purchased books (e.g., product_id 220: Wonder), add books
(90, 216, 1), -- Diary of a Wimpy Kid
(90, 219, 1), -- Holes
(90, 217, 1), -- Matilda

-- User 91: Purchased books (e.g., product_id 226: Lord of the Flies), add books
(91, 227, 1), -- Animal Farm
(91, 228, 1), -- Brave New World
(91, 229, 1), -- The Alchemist

-- User 92: Purchased books (e.g., product_id 227: Animal Farm), add books
(92, 226, 1), -- Lord of the Flies
(92, 230, 1), -- Dune
(92, 228, 1), -- Brave New World

-- User 93: Purchased books (e.g., product_id 228: Brave New World), add books
(93, 229, 1), -- The Alchemist
(93, 230, 1), -- Dune
(93, 226, 1), -- Lord of the Flies

-- User 94: Purchased books (e.g., product_id 229: The Alchemist), add books
(94, 228, 1), -- Brave New World
(94, 227, 1), -- Animal Farm
(94, 230, 1), -- Dune

-- User 95: Purchased books (e.g., product_id 230: Dune), add books
(95, 226, 1), -- Lord of the Flies
(95, 229, 1), -- The Alchemist
(95, 227, 1), -- Animal Farm

-- User 96: Purchased books (e.g., product_id 236: Les Misérables), add books
(96, 237, 1), -- Jane Eyre
(96, 238, 1), -- Wuthering Heights
(96, 239, 1), -- Great Expectations

-- User 97: Purchased books (e.g., product_id 237: Jane Eyre), add books
(97, 236, 1), -- Les Misérables
(97, 240, 1), -- Anna Karenina
(97, 238, 1), -- Wuthering Heights

-- User 98: Purchased books (e.g., product_id 238: Wuthering Heights), add books
(98, 239, 1), -- Great Expectations
(98, 240, 1), -- Anna Karenina
(98, 236, 1), -- Les Misérables

-- User 99: Purchased books (e.g., product_id 239: Great Expectations), add books
(99, 238, 1), -- Wuthering Heights
(99, 237, 1), -- Jane Eyre
(99, 240, 1), -- Anna Karenina

-- User 100: Purchased books (e.g., product_id 240: Anna Karenina), add books
(100, 236, 1), -- Les Misérables
(100, 239, 1), -- Great Expectations
(100, 237, 1), -- Jane Eyre

(101, 146, 1), -- Gaming Laptop RGB (exploring electronics)
(101, 23, 2),  -- Navy Trackpants (casual wear)
(101, 208, 1), -- Outliers (book for leisure)

-- User 102: Previously bought a watch, jeans, shirt, fridge (order 156, 157)
(102, 95, 1),  -- 50-Inch QLED TV (home entertainment)
(102, 15, 2),  -- Red Peplum Top (fashion variety)
(102, 179, 1), -- DSLR with Wi-Fi (photography interest)

-- User 103: Previously bought a shirt, laptop, pants, tee (order 158, 159)
(103, 117, 1), -- 2.5 Ton Split AC (home appliance)
(103, 86, 2),  -- Crop T-Shirt (casual fashion)
(103, 230, 1), -- Dune (sci-fi book)

-- User 104: Previously bought a watch, AC, top, gaming laptop (order 160, 161)
(104, 166, 1), -- High-End Tablet (portable tech)
(104, 44, 2),  -- Black Cargo Pants (practical clothing)
(104, 196, 1), -- Statistics for Beginners (learning interest)

-- User 105: Previously bought joggers, desktop, watch, tablet (order 162, 163)
(105, 105, 1), -- Mini Fridge (dorm convenience)
(105, 74, 2),  -- Polo Shirt (casual style)
(105, 219, 1), -- Holes (fun read)

-- User 106: Previously bought a shirt, DSLR, top, smartphone (order 164, 165)
(106, 127, 1), -- 10kg Front Load Washer (home upgrade)
(106, 35, 2),  -- Black Leather Watch (accessory addition)
(106, 210, 1), -- Man’s Search for Meaning (deep read)

-- User 107: Previously bought trackpants, textbook, watch, book (order 166, 167)
(107, 138, 1), -- 15-Inch Budget Laptop (affordable tech)
(107, 65, 2),  -- Flare Jeans (retro style)
(107, 226, 1), -- Lord of the Flies (classic literature)

-- User 108: Previously bought pants, book, watch, another book (order 168, 169)
(108, 99, 1),  -- 40-Inch Smart TV (compact entertainment)
(108, 17, 2),  -- Striped Crop Top (trendy fashion)
(108, 186, 1), -- Camera Phone (photography on the go)

-- User 109: Previously bought a shirt, top, audiobook (order 170, 171)
(109, 119, 1), -- Smart AC 1 Ton (smart home addition)
(109, 84, 2),  -- Crew Neck Tee (basic wardrobe)
(109, 237, 1), -- Jane Eyre (classic novel)

-- User 110: Previously bought trackpants, jeans, watch, shirt (order 172, 173)
(110, 156, 1), -- High-End Desktop (powerful tech)
(110, 48, 2),  -- Slim Fit Cargo (versatile pants)
(110, 197, 1), -- Biology Textbook (study material)

-- User 111: Previously bought a shirt, top, TV (order 174, 175)
(111, 170, 1), -- iPad 10-Inch (premium tablet)
(111, 76, 2),  -- Striped Casual Shirt (casual look)
(111, 229, 1), -- The Alchemist (inspirational read)

-- User 112: Previously bought joggers, fridge, watch, AC (order 176, 177)
(112, 140, 1), -- 13-Inch Lightweight Laptop (portable tech)
(112, 31, 2),  -- Rose Gold Watch (stylish accessory)
(112, 216, 1); -- Diary of a Wimpy Kid (light reading)

SELECT * 
FROM shopping_cart;

INSERT INTO user_search_history (user_id, search_text, category_id, min_price, max_price, search_date)
VALUES
-- User 1
(1, 'formal shirt for men', 5, 26.99, 43.99, '2021-03-30 10:15:23'), -- Category 5: $29.99 to $39.99
(1, 'leather watch', 9, 89.99, 109.99, '2021-03-30 10:15:23'), -- Category 9: $99.99
(1, 'calculus textbook', 24, 31.95, 76.73, '2021-03-30 10:15:23'), -- Category 24: $35.50 to $69.75
-- User 2
(2, 'dress shirt', 5, 32.39, 43.99, '2022-08-08 09:22:11'), -- Category 5: $35.99 to $39.99
(2, 'blue strap watch', 9, 80.99, 98.99, '2022-08-08 09:22:11'), -- Category 9: $89.99
(2, 'laptop for work', 18, 449.55, 1649.99, '2022-08-08 09:22:11'), -- Category 18: $499.50 to $1499.99
-- User 3
(3, 'red formal shirt', 5, 26.99, 36.29, '2021-09-23 12:45:32'), -- Category 5: $29.99 to $32.99
(3, 'cargo pants', 8, 53.99, 65.99, '2021-09-23 12:45:32'), -- Category 8: $59.99
(3, 'leather strap watch', 9, 71.99, 87.99, '2021-09-23 12:45:32'), -- Category 9: $79.99
-- User 4
(4, 'formal shirt with tie', 5, 26.09, 43.99, '2023-02-15 15:30:00'), -- Category 5: $28.99 to $39.99
(4, 'minimalist watch', 9, 134.99, 164.99, '2023-02-15 15:30:00'), -- Category 9: $149.99
(4, 'casual short sleeve shirt', 11, 22.49, 27.49, '2023-02-15 15:30:00'), -- Category 11: $24.99
-- User 5
(5, 'lace crop top', 6, 26.99, 38.49, '2024-02-10 08:00:00'), -- Category 6: $29.99 to $34.99
(5, 'flare jeans', 10, 44.99, 54.99, '2024-02-10 08:00:00'), -- Category 10: $49.99
(5, 'business laptop', 18, 449.55, 1649.99, '2024-02-10 08:00:00'), -- Category 18: Admin interest
-- User 6
(6, 'polka dot top', 6, 17.99, 32.99, '2022-02-12 11:30:45'), -- Category 6: $19.99 to $29.99
(6, 'rose gold watch', 9, 116.99, 142.99, '2022-02-12 11:30:45'), -- Category 9: $129.99
(6, 'formal shirt for men', 5, 26.09, 43.99, '2022-02-12 11:30:45'), -- Category 5: Vendor sells
-- User 7
(7, 'navy trackpants', 7, 26.99, 32.99, '2023-05-25 14:20:11'), -- Category 7: $29.99
(7, 'grey trackpants', 7, 26.99, 32.99, '2023-05-25 14:20:11'), -- Category 7: $29.99
(7, 'fitness tracker', 9, 71.99, 87.99, '2023-05-25 14:20:11'), -- Category 9: $79.99
-- User 8
(8, 'green joggers', 7, 26.99, 32.99, '2021-06-18 09:45:27'), -- Category 7: $29.99
(8, 'polo shirt', 11, 22.49, 27.49, '2021-06-18 09:45:27'), -- Category 11: $24.99
(8, 'long sleeve tee', 12, 17.99, 22.49, '2021-06-18 09:45:27'), -- Category 12: $19.99
-- User 9
(9, 'striped trackpants', 7, 26.99, 32.99, '2023-08-12 16:22:44'), -- Category 7: $29.99
(9, 'striped casual shirt', 11, 22.49, 27.49, '2023-08-12 16:22:44'), -- Category 11: $24.99
(9, 'basic t-shirt', 12, 17.99, 22.49, '2023-08-12 16:22:44'), -- Category 12: $19.99
-- User 10
(10, 'cotton trackpants', 7, 26.99, 32.99, '2021-02-26 22:11:05'), -- Category 7: $29.99
(10, 'navy trackpants', 7, 26.99, 32.99, '2021-02-26 22:11:05'), -- Category 7: $29.99
(10, 'fitness tracker', 9, 71.99, 87.99, '2021-02-26 22:11:05'), -- Category 9: $79.99
-- User 11
(11, 'black leather watch', 9, 89.99, 109.99, '2024-04-10 13:45:27'), -- Category 9: $99.99
(11, 'silver analog watch', 9, 89.99, 109.99, '2024-04-10 13:45:27'), -- Category 9: $99.99
(11, 'formal shirt for men', 5, 26.09, 43.99, '2024-04-10 13:45:27'), -- Category 5: Vendor sells
-- User 12
(12, 'blue strap watch', 9, 80.99, 98.99, '2022-10-06 18:37:19'), -- Category 9: $89.99
(12, 'gold strap watch', 9, 80.99, 98.99, '2022-10-06 18:37:19'), -- Category 9: $89.99
(12, 'linen shirt', 11, 22.49, 27.49, '2022-10-06 18:37:19'), -- Category 11: $24.99
-- User 13
(13, 'minimalist watch', 9, 134.99, 164.99, '2020-04-17 11:53:47'), -- Category 9: $149.99
(13, 'rose gold watch', 9, 116.99, 142.99, '2020-04-17 11:53:47'), -- Category 9: $129.99
(13, 'polo shirt', 11, 22.49, 27.49, '2020-04-17 11:53:47'), -- Category 11: $24.99
-- User 14
(14, 'chronograph watch', 9, 89.99, 109.99, '2023-07-01 20:14:38'), -- Category 9: $99.99
(14, 'black formal shirt', 5, 26.09, 43.99, '2023-07-01 20:14:38'), -- Category 5: $28.99 to $39.99
(14, 'cargo pants', 8, 53.99, 65.99, '2023-07-01 20:14:38'), -- Category 8: $59.99
-- User 15
(15, 'olive green cargo', 8, 53.99, 65.99, '2021-12-09 09:27:55'), -- Category 8: $59.99
(15, 'black cargo pants', 8, 53.99, 65.99, '2021-12-09 09:27:55'), -- Category 8: $59.99
(15, 'striped casual shirt', 11, 22.49, 27.49, '2021-12-09 09:27:55'), -- Category 11: $24.99
-- User 16
(16, 'grey cargo pants', 8, 53.99, 65.99, '2024-06-27 15:48:12'), -- Category 8: $59.99
(16, 'navy cargo pants', 8, 53.99, 65.99, '2024-06-27 15:48:12'), -- Category 8: $59.99
(16, 'crew neck tee', 12, 17.99, 22.49, '2024-06-27 15:48:12'), -- Category 12: $19.99
-- User 17
(17, 'brown cargo pants', 8, 53.99, 65.99, '2020-08-22 10:36:49'), -- Category 8: $59.99
(17, 'olive green cargo', 8, 53.99, 65.99, '2020-08-22 10:36:49'), -- Category 8: $59.99
(17, 'long sleeve tee', 12, 17.99, 22.49, '2020-08-22 10:36:49'), -- Category 12: $19.99
-- User 18
(18, 'slim fit cargo', 8, 53.99, 65.99, '2022-03-15 14:22:33'), -- Category 8: $59.99
(18, 'linen shirt', 11, 22.49, 27.49, '2022-03-15 14:22:33'), -- Category 11: $24.99
(18, 'basic t-shirt', 12, 17.99, 22.49, '2022-03-15 14:22:33'), -- Category 12: $19.99
-- User 19
(19, 'ripstop cargo pants', 8, 53.99, 65.99, '2023-11-19 08:45:16'), -- Category 8: $59.99
(19, 'grey cargo pants', 8, 53.99, 65.99, '2023-11-19 08:45:16'), -- Category 8: $59.99
(19, 'fitness tracker', 9, 71.99, 87.99, '2023-11-19 08:45:16'), -- Category 9: $79.99
-- User 20
(20, 'leather strap watch', 9, 71.99, 87.99, '2021-05-07 19:53:27'), -- Category 9: $79.99
(20, 'silver analog watch', 9, 89.99, 109.99, '2021-05-07 19:53:27'), -- Category 9: $99.99
(20, 'white dress shirt', 5, 26.09, 43.99, '2021-05-07 19:53:27'), -- Category 5: $28.99 to $39.99
-- User 21
(21, 'gold analog watch', 9, 89.99, 109.99, '2024-02-12 12:34:56'), -- Category 9: $99.99
(21, 'blue strap watch', 9, 80.99, 98.99, '2024-02-12 12:34:56'), -- Category 9: $89.99
(21, 'formal shirt for men', 5, 26.09, 43.99, '2024-02-12 12:34:56'), -- Category 5: Admin interest
-- User 22
(22, 'blue strap watch', 9, 71.99, 87.99, '2020-09-24 16:47:38'), -- Category 9: $79.99
(22, 'gold strap watch', 9, 80.99, 98.99, '2020-09-24 16:47:38'), -- Category 9: $89.99
(22, 'short sleeve shirt', 11, 22.49, 27.49, '2020-09-24 16:47:38'), -- Category 11: $24.99
-- User 23
(23, 'fitness tracker', 9, 71.99, 87.99, '2022-01-05 07:12:45'), -- Category 9: $79.99
(23, 'navy trackpants', 7, 26.99, 32.99, '2022-01-05 07:12:45'), -- Category 7: $29.99
(23, 'long sleeve tee', 12, 17.99, 22.49, '2022-01-05 07:12:45'), -- Category 12: $19.99
-- User 24
(24, 'automatic watch', 9, 89.99, 109.99, '2023-04-28 21:08:19'), -- Category 9: $99.99
(24, 'black leather watch', 9, 89.99, 109.99, '2023-04-28 21:08:19'), -- Category 9: $99.99
(24, 'black formal shirt', 5, 26.09, 43.99, '2023-04-28 21:08:19'), -- Category 5: $28.99 to $39.99
-- User 25
(25, 'flare jeans', 10, 44.99, 54.99, '2021-08-13 13:56:42'), -- Category 10: $49.99
(25, 'off-shoulder top', 6, 26.99, 38.49, '2021-08-13 13:56:42'), -- Category 6: $29.99 to $34.99
(25, 'crop t-shirt', 7, 17.99, 22.49, '2021-08-13 13:56:42'), -- Category 7: $19.99
-- User 26
(26, 'ankle-length jeans', 10, 44.99, 54.99, '2024-05-20 18:24:37'), -- Category 10: $49.99
(26, 'striped crop top', 6, 17.99, 32.99, '2024-05-20 18:24:37'), -- Category 6: $19.99 to $29.99
(26, 'tie-dye t-shirt', 12, 17.99, 22.49, '2024-05-20 18:24:37'), -- Category 12: $19.99
-- User 27
(27, 'polo shirt', 11, 22.49, 27.49, '2020-12-29 23:59:59'), -- Category 11: $24.99
(27, 'striped casual shirt', 11, 22.49, 27.49, '2020-12-29 23:59:59'), -- Category 11: $24.99
(27, 'khaki cargo pants', 8, 53.99, 65.99, '2020-12-29 23:59:59'), -- Category 8: $59.99
-- User 28
(28, 'striped casual shirt', 11, 22.49, 27.49, '2022-06-16 10:11:12'), -- Category 11: $24.99
(28, 'polo shirt', 11, 22.49, 27.49, '2022-06-16 10:11:12'), -- Category 11: $24.99
(28, 'crew neck tee', 12, 17.99, 22.49, '2022-06-16 10:11:12'), -- Category 12: $19.99
-- User 29
(29, 'linen shirt', 11, 22.49, 27.49, '2023-09-12 14:33:44'), -- Category 11: $24.99
(29, 'long sleeve tee', 12, 17.99, 22.49, '2023-09-12 14:33:44'), -- Category 12: $19.99
(29, 'olive green cargo', 8, 53.99, 65.99, '2023-09-12 14:33:44'), -- Category 8: $59.99
-- User 30
(30, 'short sleeve shirt', 11, 22.49, 27.49, '2021-01-23 09:45:27'), -- Category 11: $24.99
(30, 'polo shirt', 11, 22.49, 27.49, '2021-01-23 09:45:27'), -- Category 11: $24.99
(30, 'tie-dye t-shirt', 12, 17.99, 22.49, '2021-01-23 09:45:27'), -- Category 12: $19.99
-- User 31
(31, 'crew neck tee', 12, 17.99, 22.49, '2024-03-06 17:22:11'), -- Category 12: $19.99
(31, 'long sleeve tee', 12, 17.99, 22.49, '2024-03-06 17:22:11'), -- Category 12: $19.99
(31, 'black trackpants', 7, 26.99, 32.99, '2024-03-06 17:22:11'), -- Category 7: $29.99
-- User 32
(32, 'long sleeve tee', 12, 17.99, 22.49, '2020-07-10 12:34:56'), -- Category 12: $19.99
(32, 'crew neck tee', 12, 17.99, 22.49, '2020-07-10 12:34:56'), -- Category 12: $19.99
(32, 'striped casual shirt', 11, 22.49, 27.49, '2020-07-10 12:34:56'), -- Category 11: $24.99
-- User 33
(33, 'crop t-shirt', 7, 17.99, 22.49, '2022-02-26 20:45:38'), -- Category 7: $19.99
(33, 'off-shoulder top', 6, 26.99, 38.49, '2022-02-26 20:45:38'), -- Category 6: $29.99 to $34.99
(33, 'flare jeans', 10, 44.99, 54.99, '2022-02-26 20:45:38'), -- Category 10: $49.99
-- User 34
(34, 'tie-dye t-shirt', 12, 17.99, 22.49, '2023-10-03 08:56:49'), -- Category 12: $19.99
(34, 'crew neck tee', 12, 17.99, 22.49, '2023-10-03 08:56:49'), -- Category 12: $19.99
(34, 'ankle-length jeans', 10, 44.99, 54.99, '2023-10-03 08:56:49'), -- Category 10: $49.99
-- User 35
(35, 'basic t-shirt', 12, 17.99, 22.49, '2021-04-15 15:27:33'), -- Category 12: $19.99
(35, 'polo shirt', 11, 22.49, 27.49, '2021-04-15 15:27:33'), -- Category 11: $24.99
(35, 'linen shirt', 11, 22.49, 27.49, '2021-04-15 15:27:33'), -- Category 11: $24.99
-- User 36
(36, 'qled tv 50 inch', 13, 719.99, 879.99, '2024-07-17 11:48:22'), -- Category 13: $799.99
(36, '60-inch 4k tv', 13, 719.99, 879.99, '2024-07-17 11:48:22'), -- Category 13: $799.99
(36, 'business laptop', 18, 449.55, 1649.99, '2024-07-17 11:48:22'), -- Category 18: $499.50 to $1499.99
-- User 37
(37, '60-inch 4k tv', 13, 719.99, 879.99, '2020-03-20 18:34:56'), -- Category 13: $799.99
(37, '70-inch led tv', 13, 719.99, 879.99, '2020-03-20 18:34:56'), -- Category 13: $799.99
(37, 'gaming laptop rgb', 18, 449.55, 1649.99, '2020-03-20 18:34:56'), -- Category 18: $499.50 to $1499.99
-- User 38
(38, '70-inch led tv', 13, 719.99, 879.99, '2022-08-07 14:12:45'), -- Category 13: $799.99
(38, '40-inch smart tv', 13, 719.99, 879.99, '2022-08-07 14:12:45'), -- Category 13: $799.99
(38, 'budget gaming laptop', 18, 449.55, 1649.99, '2022-08-07 14:12:45'), -- Category 18: $499.50 to $1499.99
-- User 39
(39, '40-inch smart tv', 13, 719.99, 879.99, '2023-12-22 09:27:38'), -- Category 13: $799.99
(39, '60-inch 4k tv', 13, 719.99, 879.99, '2023-12-22 09:27:38'), -- Category 13: $799.99
(39, 'gaming laptop 144hz', 18, 449.55, 1649.99, '2023-12-22 09:27:38'), -- Category 18: $499.50 to $1499.99
-- User 40
(40, 'mini fridge', 14, 179.99, 219.99, '2021-06-28 22:11:05'), -- Category 14: $199.99
(40, 'inverter fridge', 14, 179.99, 219.99, '2021-06-28 22:11:05'), -- Category 14: $199.99
(40, '1 ton split ac', 15, 359.99, 439.99, '2021-06-28 22:11:05'), -- Category 15: $399.99
-- User 41
(41, 'inverter fridge', 14, 179.99, 219.99, '2024-09-09 16:45:27'), -- Category 14: $199.99
(41, 'mini fridge', 14, 179.99, 219.99, '2024-09-09 16:45:27'), -- Category 14: $199.99
(41, '2.5 ton split ac', 15, 359.99, 439.99, '2024-09-09 16:45:27'), -- Category 15: $399.99
-- User 42
(42, 'frost-free fridge', 14, 179.99, 219.99, '2020-05-12 10:53:47'), -- Category 14: $199.99
(42, 'inverter fridge', 14, 179.99, 219.99, '2020-05-12 10:53:47'), -- Category 14: $199.99
(42, 'inverter ac 1.5 ton', 15, 359.99, 439.99, '2020-05-12 10:53:47'), -- Category 15: $399.99
-- User 43
(43, 'top freezer fridge', 14, 179.99, 219.99, '2022-11-21 19:08:42'), -- Category 14: $199.99
(43, 'mini fridge', 14, 179.99, 219.99, '2022-11-21 19:08:42'), -- Category 14: $199.99
(43, 'smart ac 1 ton', 15, 359.99, 439.99, '2022-11-21 19:08:42'), -- Category 15: $399.99
-- User 44
(44, 'bottom freezer fridge', 14, 179.99, 219.99, '2023-02-14 12:34:56'), -- Category 14: $199.99
(44, 'inverter fridge', 14, 179.99, 219.99, '2023-02-14 12:34:56'), -- Category 14: $199.99
(44, 'portable washer', 16, 269.99, 329.99, '2023-02-14 12:34:56'), -- Category 16: $299.99
-- User 45
(45, '1 ton split ac', 15, 359.99, 439.99, '2021-07-26 08:45:16'), -- Category 15: $399.99
(45, '2.5 ton split ac', 15, 359.99, 439.99, '2021-07-26 08:45:16'), -- Category 15: $399.99
(45, 'mini fridge', 14, 179.99, 219.99, '2021-07-26 08:45:16'), -- Category 14: $199.99
-- User 46
(46, '2.5 ton split ac', 15, 359.99, 439.99, '2024-08-01 17:22:11'), -- Category 15: $399.99
(46, '1 ton split ac', 15, 359.99, 439.99, '2024-08-01 17:22:11'), -- Category 15: $399.99
(46, '10kg front load washer', 16, 269.99, 329.99, '2024-08-01 17:22:11'), -- Category 16: $299.99
-- User 47
(47, 'inverter ac 1.5 ton', 15, 359.99, 439.99, '2020-10-27 14:33:44'), -- Category 15: $399.99
(47, '1 ton split ac', 15, 359.99, 439.99, '2020-10-27 14:33:44'), -- Category 15: $399.99
(47, 'inverter fridge', 14, 179.99, 219.99, '2020-10-27 14:33:44'), -- Category 14: $199.99
-- User 48
(48, 'smart ac 1 ton', 15, 359.99, 439.99, '2022-04-11 09:27:55'), -- Category 15: $399.99
(48, 'inverter ac 1.5 ton', 15, 359.99, 439.99, '2022-04-11 09:27:55'), -- Category 15: $399.99
(48, 'top freezer fridge', 14, 179.99, 219.99, '2022-04-11 09:27:55'), -- Category 14: $199.99
-- User 49
(49, 'portable washer', 16, 269.99, 329.99, '2023-06-05 18:24:37'), -- Category 16: $299.99
(49, '10kg front load washer', 16, 269.99, 329.99, '2023-06-05 18:24:37'), -- Category 16: $299.99
(49, '2.5 ton split ac', 15, 359.99, 439.99, '2023-06-05 18:24:37'), -- Category 15: $399.99
-- User 50
(50, '10kg front load washer', 16, 269.99, 329.99, '2021-09-19 13:56:42'), -- Category 16: $299.99
(50, 'portable washer', 16, 269.99, 329.99, '2021-09-19 13:56:42'), -- Category 16: $299.99
(50, 'smart ac 1 ton', 15, 359.99, 439.99, '2021-09-19 13:56:42'), -- Category 15: $399.99
-- User 51
(51, '14-inch business laptop', 18, 449.55, 1649.99, '2024-10-10 21:08:19'), -- Category 18: $499.50 to $1499.99
(51, '15-inch budget laptop', 18, 449.55, 1649.99, '2024-10-10 21:08:19'), -- Category 18: $499.50 to $1499.99
(51, 'high-end tablet', 20, 179.99, 219.99, '2024-10-10 21:08:19'), -- Category 20: $199.99
-- User 52
(52, '15-inch budget laptop', 18, 449.55, 1649.99, '2020-02-16 07:12:45'), -- Category 18: $499.50 to $1499.99
(52, '14-inch business laptop', 18, 449.55, 1649.99, '2020-02-16 07:12:45'), -- Category 18: $499.50 to $1499.99
(52, 'budget tablet', 20, 179.99, 219.99, '2020-02-16 07:12:45'), -- Category 20: $199.99
-- User 53
(53, '16-inch laptop', 18, 449.55, 1649.99, '2022-05-24 16:47:38'), -- Category 18: $499.50 to $1499.99
(53, '15-inch budget laptop', 18, 449.55, 1649.99, '2022-05-24 16:47:38'), -- Category 18: $499.50 to $1499.99
(53, 'tablet with keyboard', 20, 179.99, 219.99, '2022-05-24 16:47:38'), -- Category 20: $199.99
-- User 54
(54, '13-inch lightweight laptop', 18, 449.55, 1649.99, '2023-01-07 10:36:49'), -- Category 18: $499.50 to $1499.99
(54, '14-inch business laptop', 18, 449.55, 1649.99, '2023-01-07 10:36:49'), -- Category 18: $499.50 to $1499.99
(54, 'android tablet', 20, 179.99, 219.99, '2023-01-07 10:36:49'), -- Category 20: $199.99
-- User 55
(55, 'gaming laptop rgb', 18, 449.55, 1649.99, '2021-03-02 19:53:27'), -- Category 18: $499.50 to $1499.99
(55, 'budget gaming laptop', 18, 449.55, 1649.99, '2021-03-02 19:53:27'), -- Category 18: $499.50 to $1499.99
(55, 'high-end desktop', 19, 899.99, 1099.99, '2021-03-02 19:53:27'), -- Category 19: $999.99
-- User 56
(56, 'budget gaming laptop', 18, 449.55, 1649.99, '2024-11-13 14:22:33'), -- Category 18: $499.50 to $1499.99
(56, 'gaming laptop rgb', 18, 449.55, 1649.99, '2024-11-13 14:22:33'), -- Category 18: $499.50 to $1499.99
(56, 'custom desktop pc', 19, 899.99, 1099.99, '2024-11-13 14:22:33'), -- Category 19: $999.99
-- User 57
(57, 'gaming laptop 144hz', 18, 449.55, 1649.99, '2020-08-05 12:34:56'), -- Category 18: $499.50 to $1499.99
(57, 'budget gaming laptop', 18, 449.55, 1649.99, '2020-08-05 12:34:56'), -- Category 18: $499.50 to $1499.99
(57, 'compact desktop pc', 19, 899.99, 1099.99, '2020-08-05 12:34:56'), -- Category 19: $999.99
-- User 58
(58, '16-inch gaming laptop', 18, 449.55, 1649.99, '2022-09-28 18:37:19'), -- Category 18: $499.50 to $1499.99
(58, 'gaming laptop rgb', 18, 449.55, 1649.99, '2022-09-28 18:37:19'), -- Category 18: $499.50 to $1499.99
(58, 'media desktop pc', 19, 899.99, 1099.99, '2022-09-28 18:37:19'), -- Category 19: $999.99
-- User 59
(59, 'high-end gaming laptop', 18, 449.55, 1649.99, '2023-03-23 09:45:27'), -- Category 18: $499.50 to $1499.99
(59, '16-inch gaming laptop', 18, 449.55, 1649.99, '2023-03-23 09:45:27'), -- Category 18: $499.50 to $1499.99
(59, 'high-end desktop', 19, 899.99, 1099.99, '2023-03-23 09:45:27'), -- Category 19: $999.99
-- User 60
(60, 'high-end desktop', 19, 899.99, 1099.99, '2024-12-18 22:11:05'), -- Category 19: $999.99
(60, 'custom desktop pc', 19, 899.99, 1099.99, '2024-12-18 22:11:05'), -- Category 19: $999.99
(60, 'high-end tablet', 20, 179.99, 219.99, '2024-12-18 22:11:05'), -- Category 20: $199.99
-- User 61
(61, 'custom desktop pc', 19, 899.99, 1099.99, '2020-01-03 08:34:21'), -- Category 19: $999.99
(61, 'high-end desktop', 19, 899.99, 1099.99, '2020-01-03 08:34:21'), -- Category 19: $999.99
(61, 'budget tablet', 20, 179.99, 219.99, '2020-01-03 08:34:21'), -- Category 20: $199.99
-- User 62
(62, 'compact desktop pc', 19, 899.99, 1099.99, '2022-07-12 14:56:43'), -- Category 19: $999.99
(62, 'custom desktop pc', 19, 899.99, 1099.99, '2022-07-12 14:56:43'), -- Category 19: $999.99
(62, 'tablet with keyboard', 20, 179.99, 219.99, '2022-07-12 14:56:43'), -- Category 20: $199.99
-- User 63
(63, 'media desktop pc', 19, 899.99, 1099.99, '2023-04-06 09:12:54'), -- Category 19: $999.99
(63, 'compact desktop pc', 19, 899.99, 1099.99, '2023-04-06 09:12:54'), -- Category 19: $999.99
(63, 'android tablet', 20, 179.99, 219.99, '2023-04-06 09:12:54'), -- Category 20: $199.99
-- User 64
(64, 'high-end tablet', 20, 179.99, 219.99, '2021-11-17 17:45:32'), -- Category 20: $199.99
(64, 'budget tablet', 20, 179.99, 219.99, '2021-11-17 17:45:32'), -- Category 20: $199.99
(64, '14-inch business laptop', 18, 449.55, 1649.99, '2021-11-17 17:45:32'), -- Category 18: $499.50 to $1499.99
-- User 65
(65, 'budget tablet', 20, 179.99, 219.99, '2024-05-31 10:23:11'), -- Category 20: $199.99
(65, 'high-end tablet', 20, 179.99, 219.99, '2024-05-31 10:23:11'), -- Category 20: $199.99
(65, '15-inch budget laptop', 18, 449.55, 1649.99, '2024-05-31 10:23:11'), -- Category 18: $499.50 to $1499.99
-- User 66
(66, 'tablet with keyboard', 20, 179.99, 219.99, '2020-12-11 12:34:56'), -- Category 20: $199.99
(66, 'budget tablet', 20, 179.99, 219.99, '2020-12-11 12:34:56'), -- Category 20: $199.99
(66, '16-inch laptop', 18, 449.55, 1649.99, '2020-12-11 12:34:56'), -- Category 18: $499.50 to $1499.99
-- User 67
(67, 'android tablet', 20, 179.99, 219.99, '2022-03-26 19:08:42'), -- Category 20: $199.99
(67, 'high-end tablet', 20, 179.99, 219.99, '2022-03-26 19:08:42'), -- Category 20: $199.99
(67, '13-inch lightweight laptop', 18, 449.55, 1649.99, '2022-03-26 19:08:42'), -- Category 18: $499.50 to $1499.99
-- User 68
(68, 'ipad 10-inch', 20, 179.99, 219.99, '2023-08-09 16:22:44'), -- Category 20: $199.99
(68, 'android tablet', 20, 179.99, 219.99, '2023-08-09 16:22:44'), -- Category 20: $199.99
(68, 'gaming laptop rgb', 18, 449.55, 1649.99, '2023-08-09 16:22:44'), -- Category 18: $499.50 to $1499.99
-- User 69
(69, 'dslr for vlogging', 21, 449.99, 549.99, '2021-02-12 22:11:05'), -- Category 21: $499.99
(69, 'sports dslr', 21, 449.99, 549.99, '2021-02-12 22:11:05'), -- Category 21: $499.99
(69, 'camera phone', 22, 629.99, 769.99, '2021-02-12 22:11:05'), -- Category 22: $699.99
-- User 70
(70, 'sports dslr', 21, 449.99, 549.99, '2024-05-05 13:45:27'), -- Category 21: $499.99
(70, 'dslr for vlogging', 21, 449.99, 549.99, '2024-05-05 13:45:27'), -- Category 21: $499.99
(70, 'foldable phone', 22, 629.99, 769.99, '2024-05-05 13:45:27'), -- Category 22: $699.99
-- User 71
(71, 'compact dslr', 21, 449.99, 549.99, '2020-04-17 18:37:19'), -- Category 21: $499.99
(71, 'sports dslr', 21, 449.99, 549.99, '2020-04-17 18:37:19'), -- Category 21: $499.99
(71, 'camera phone', 22, 629.99, 769.99, '2020-04-17 18:37:19'), -- Category 22: $699.99
-- User 72
(72, 'dslr with wi-fi', 21, 449.99, 549.99, '2022-10-23 11:53:47'), -- Category 21: $499.99
(72, 'dslr for vlogging', 21, 449.99, 549.99, '2022-10-23 11:53:47'), -- Category 21: $499.99
(72, 'foldable phone', 22, 629.99, 769.99, '2022-10-23 11:53:47'), -- Category 22: $699.99
-- User 73
(73, 'advanced dslr', 21, 449.99, 549.99, '2023-07-15 20:14:38'), -- Category 21: $499.99
(73, 'dslr with wi-fi', 21, 449.99, 549.99, '2023-07-15 20:14:38'), -- Category 21: $499.99
(73, 'camera phone', 22, 629.99, 769.99, '2023-07-15 20:14:38'), -- Category 22: $699.99
-- User 74
(74, 'camera phone', 22, 629.99, 769.99, '2021-05-27 09:27:55'), -- Category 22: $699.99
(74, 'foldable phone', 22, 629.99, 769.99, '2021-05-27 09:27:55'), -- Category 22: $699.99
(74, 'dslr for vlogging', 21, 449.99, 549.99, '2021-05-27 09:27:55'), -- Category 21: $499.99
-- User 75
(75, 'foldable phone', 22, 629.99, 769.99, '2024-09-01 15:48:12'), -- Category 22: $699.99
(75, 'camera phone', 22, 629.99, 769.99, '2024-09-01 15:48:12'), -- Category 22: $699.99
(75, 'sports dslr', 21, 449.99, 549.99, '2024-09-01 15:48:12'), -- Category 21: $499.99
-- User 76
(76, 'statistics for beginners', 24, 31.95, 76.73, '2020-06-20 10:36:49'), -- Category 24: $35.50 to $69.75
(76, 'biology textbook', 24, 31.95, 76.73, '2020-06-20 10:36:49'), -- Category 24: $35.50 to $69.75
(76, 'algebra made easy', 24, 31.95, 76.73, '2020-06-20 10:36:49'), -- Category 24: $35.50 to $69.75
-- User 77
(77, 'biology textbook', 24, 31.95, 76.73, '2022-01-12 14:22:33'), -- Category 24: $35.50 to $69.75
(77, 'statistics for beginners', 24, 31.95, 76.73, '2022-01-12 14:22:33'), -- Category 24: $35.50 to $69.75
(77, 'engineering mechanics', 24, 31.95, 76.73, '2022-01-12 14:22:33'), -- Category 24: $35.50 to $69.75
-- User 78
(78, 'algebra made easy', 24, 31.95, 76.73, '2023-12-06 08:45:16'), -- Category 24: $35.50 to $69.75
(78, 'history of science', 24, 31.95, 76.73, '2023-12-06 08:45:16'), -- Category 24: $35.50 to $69.75
(78, 'statistics for beginners', 24, 31.95, 76.73, '2023-12-06 08:45:16'), -- Category 24: $35.50 to $69.75
-- User 79
(79, 'history of science', 24, 31.95, 76.73, '2021-08-25 19:53:27'), -- Category 24: $35.50 to $69.75
(79, 'statistics for beginners', 24, 31.95, 76.73, '2021-08-25 19:53:27'), -- Category 24: $35.50 to $69.75
(79, 'engineering mechanics', 24, 31.95, 76.73, '2021-08-25 19:53:27'), -- Category 24: $35.50 to $69.75
-- User 80
(80, 'engineering mechanics', 24, 31.95, 76.73, '2024-02-17 12:34:56'), -- Category 24: $35.50 to $69.75
(80, 'algebra made easy', 24, 31.95, 76.73, '2024-02-17 12:34:56'), -- Category 24: $35.50 to $69.75
(80, 'biology textbook', 24, 31.95, 76.73, '2024-02-17 12:34:56'), -- Category 24: $35.50 to $69.75
-- User 81
(81, 'thinking fast and slow', 25, 13.49, 16.49, '2020-09-08 16:47:38'), -- Category 25: $14.99
(81, 'the subtle art', 25, 13.49, 16.49, '2020-09-08 16:47:38'), -- Category 25: $14.99
(81, 'outliers', 25, 13.49, 16.49, '2020-09-08 16:47:38'), -- Category 25: $14.99
-- User 82
(82, 'the subtle art', 25, 13.49, 16.49, '2022-04-03 07:12:45'), -- Category 25: $14.99
(82, 'thinking fast and slow', 25, 13.49, 16.49, '2022-04-03 07:12:45'), -- Category 25: $14.99
(82, 'man’s search for meaning', 25, 13.49, 16.49, '2022-04-03 07:12:45'), -- Category 25: $14.99
-- User 83
(83, 'outliers', 25, 13.49, 16.49, '2023-11-27 21:08:19'), -- Category 25: $14.99
(83, 'grit', 25, 13.49, 16.49, '2023-11-27 21:08:19'), -- Category 25: $14.99
(83, 'thinking fast and slow', 25, 13.49, 16.49, '2023-11-27 21:08:19'), -- Category 25: $14.99
-- User 84
(84, 'grit', 25, 13.49, 16.49, '2021-07-10 13:56:42'), -- Category 25: $14.99
(84, 'outliers', 25, 13.49, 16.49, '2021-07-10 13:56:42'), -- Category 25: $14.99
(84, 'the subtle art', 25, 13.49, 16.49, '2021-07-10 13:56:42'), -- Category 25: $14.99
-- User 85
(85, 'man’s search for meaning', 25, 13.49, 16.49, '2024-08-23 18:24:37'), -- Category 25: $14.99
(85, 'thinking fast and slow', 25, 13.49, 16.49, '2024-08-23 18:24:37'), -- Category 25: $14.99
(85, 'grit', 25, 13.49, 16.49, '2024-08-23 18:24:37'), -- Category 25: $14.99
-- User 86
(86, 'diary of a wimpy kid', 26, 8.99, 10.99, '2020-03-15 23:59:59'), -- Category 26: $9.99
(86, 'matilda', 26, 8.99, 10.99, '2020-03-15 23:59:59'), -- Category 26: $9.99
(86, 'the secret garden', 26, 8.99, 10.99, '2020-03-15 23:59:59'), -- Category 26: $9.99
-- User 87
(87, 'matilda', 26, 8.99, 10.99, '2022-06-14 10:11:12'), -- Category 26: $9.99
(87, 'diary of a wimpy kid', 26, 8.99, 10.99, '2022-06-14 10:11:12'), -- Category 26: $9.99
(87, 'wonder', 26, 8.99, 10.99, '2022-06-14 10:11:12'), -- Category 26: $9.99
-- User 88
(88, 'the secret garden', 26, 8.99, 10.99, '2023-09-10 14:33:44'), -- Category 26: $9.99
(88, 'holes', 26, 8.99, 10.99, '2023-09-10 14:33:44'), -- Category 26: $9.99
(88, 'diary of a wimpy kid', 26, 8.99, 10.99, '2023-09-10 14:33:44'), -- Category 26: $9.99
-- User 89
(89, 'holes', 26, 8.99, 10.99, '2021-01-18 09:45:27'), -- Category 26: $9.99
(89, 'the secret garden', 26, 8.99, 10.99, '2021-01-18 09:45:27'), -- Category 26: $9.99
(89, 'wonder', 26, 8.99, 10.99, '2021-01-18 09:45:27'), -- Category 26: $9.99
-- User 90
(90, 'wonder', 26, 8.99, 10.99, '2024-03-04 17:22:11'), -- Category 26: $9.99
(90, 'diary of a wimpy kid', 26, 8.99, 10.99, '2024-03-04 17:22:11'), -- Category 26: $9.99
(90, 'matilda', 26, 8.99, 10.99, '2024-03-04 17:22:11'), -- Category 26: $9.99
-- User 91
(91, 'lord of the flies', 27, 7.19, 8.79, '2020-07-08 12:34:56'), -- Category 27: $7.99
(91, 'animal farm', 27, 7.19, 8.79, '2020-07-08 12:34:56'), -- Category 27: $7.99
(91, 'brave new world', 27, 7.19, 8.79, '2020-07-08 12:34:56'), -- Category 27: $7.99
-- User 92
(92, 'animal farm', 27, 7.19, 8.79, '2022-02-13 20:45:38'), -- Category 27: $7.99
(92, 'lord of the flies', 27, 7.19, 8.79, '2022-02-13 20:45:38'), -- Category 27: $7.99
(92, 'dune', 27, 7.19, 8.79, '2022-02-13 20:45:38'), -- Category 27: $7.99
-- User 93
(93, 'brave new world', 27, 7.19, 8.79, '2023-10-01 08:56:49'), -- Category 27: $7.99
(93, 'the alchemist', 27, 7.19, 8.79, '2023-10-01 08:56:49'), -- Category 27: $7.99
(93, 'lord of the flies', 27, 7.19, 8.79, '2023-10-01 08:56:49'), -- Category 27: $7.99
-- User 94
(94, 'the alchemist', 27, 7.19, 8.79, '2021-04-13 15:27:33'), -- Category 27: $7.99
(94, 'brave new world', 27, 7.19, 8.79, '2021-04-13 15:27:33'), -- Category 27: $7.99
(94, 'dune', 27, 7.19, 8.79, '2021-04-13 15:27:33'), -- Category 27: $7.99
-- User 95
(95, 'dune', 27, 7.19, 8.79, '2024-07-09 11:48:22'), -- Category 27: $7.99
(95, 'lord of the flies', 27, 7.19, 8.79, '2024-07-09 11:48:22'), -- Category 27: $7.99
(95, 'animal farm', 27, 7.19, 8.79, '2024-07-09 11:48:22'), -- Category 27: $7.99
-- User 96
(96, 'les misérables', 29, 11.69, 14.29, '2020-05-26 18:34:56'), -- Category 29: $12.99
(96, 'jane eyre', 29, 11.69, 14.29, '2020-05-26 18:34:56'), -- Category 29: $12.99
(96, 'wuthering heights', 29, 11.69, 14.29, '2020-05-26 18:34:56'), -- Category 29: $12.99
-- User 97
(97, 'jane eyre', 29, 11.69, 14.29, '2022-08-17 14:12:45'), -- Category 29: $12.99
(97, 'les misérables', 29, 11.69, 14.29, '2022-08-17 14:12:45'), -- Category 29: $12.99
(97, 'anna karenina', 29, 11.69, 14.29, '2022-08-17 14:12:45'), -- Category 29: $12.99
-- User 98
(98, 'wuthering heights', 29, 11.69, 14.29, '2023-12-29 09:27:38'), -- Category 29: $12.99
(98, 'great expectations', 29, 11.69, 14.29, '2023-12-29 09:27:38'), -- Category 29: $12.99
(98, 'les misérables', 29, 11.69, 14.29, '2023-12-29 09:27:38'), -- Category 29: $12.99
-- User 99
(99, 'great expectations', 29, 11.69, 14.29, '2021-06-12 22:11:05'), -- Category 29: $12.99
(99, 'wuthering heights', 29, 11.69, 14.29, '2021-06-12 22:11:05'), -- Category 29: $12.99
(99, 'anna karenina', 29, 11.69, 14.29, '2021-06-12 22:11:05'), -- Category 29: $12.99
-- User 100
(100, 'anna karenina', 29, 11.69, 14.29, '2021-06-18 08:50:54'), -- Category 29: $12.99
(100, 'les misérables', 29, 11.69, 14.29, '2021-06-18 08:50:54'), -- Category 29: $12.99
(100, 'great expectations', 29, 11.69, 14.29, '2021-06-18 08:50:54'),-- Category 29: $12.99

-- User 101: Shirts ($29.99), TV ($499.99), Top ($24.99), Trackpants ($19.99)
(101, 'business casual shirt', 5, 26.99, 35.99, '2025-01-04 09:00:00'), -- Before order 154
(101, 'smart tv 40 inch', 13, 449.99, 549.99, '2025-01-05 12:00:00'), -- Between orders
(101, 'women’s casual top', 6, 22.49, 27.49, '2025-01-06 12:00:00'), -- After delivery

-- User 102: Watch ($49.99), Jeans ($39.99), Shirt ($24.99), Fridge ($599.99)
(102, 'sports watch', 9, 44.99, 54.99, '2025-01-13 08:00:00'), -- Before order 156
(102, 'denim jeans slim', 10, 35.99, 43.99, '2025-01-14 12:00:00'), -- Between orders
(102, 'mini fridge for dorm', 14, 539.99, 659.99, '2025-01-21 18:00:00'), -- After return

-- User 103: Shirt ($34.99), Laptop ($699.99), Pants ($34.99), Tee ($14.99)
(103, 'white formal shirt', 5, 31.49, 38.49, '2025-01-21 12:00:00'), -- Before order 158
(103, 'budget laptop 15 inch', 18, 629.99, 769.99, '2025-01-22 10:00:00'), -- Between orders
(103, 'khaki casual pants', 8, 31.49, 38.49, '2025-01-23 15:00:00'), -- After delivery

-- User 104: Watch ($49.99), AC ($399.99), Top ($19.99), Gaming Laptop ($1299.99)
(104, 'black sports watch', 9, 44.99, 54.99, '2025-01-29 09:00:00'), -- Before order 160
(104, 'split ac 1.5 ton', 15, 359.99, 439.99, '2025-01-30 13:00:00'), -- Between orders
(104, 'gaming laptop rgb', 18, 1169.99, 1429.99, '2025-01-31 10:00:00'), -- After pending

-- User 105: Joggers ($22.50), Desktop ($1199.99), Watch ($45.50), Tablet ($199.99)
(105, 'grey joggers men', 7, 20.25, 24.75, '2025-01-06 10:00:00'), -- Before order 162
(105, 'high-end desktop pc', 19, 1079.99, 1319.99, '2025-01-07 11:00:00'), -- Between orders
(105, 'android tablet 10 inch', 20, 179.99, 219.99, '2025-01-14 11:00:00'), -- After return

-- User 106: Shirt ($32.50), DSLR ($499.99), Top ($22.50), Smartphone ($399.99)
(106, 'black dress shirt', 5, 29.25, 35.75, '2025-02-15 12:00:00'), -- Before order 164
(106, 'dslr camera vlogging', 21, 449.99, 549.99, '2025-02-16 12:00:00'), -- Between orders
(106, 'camera phone 5g', 22, 359.99, 439.99, '2025-02-17 12:00:00'), -- After cancellation

-- User 107: Trackpants ($21.75), Textbook ($59.99), Watch ($79.99), Self-Help ($19.99)
(107, 'navy running pants', 7, 19.58, 23.93, '2025-02-20 14:00:00'), -- Before order 166
(107, 'science textbook college', 24, 53.99, 65.99, '2025-02-21 10:00:00'), -- Between orders
(107, 'smart watch fitness', 9, 71.99, 87.99, '2025-02-22 18:00:00'), -- After delivery

-- User 108: Pants ($32.50), Children’s Book ($12.99), Watch ($59.50), Fiction ($14.99)
(108, 'black cargo pants', 8, 29.25, 35.75, '2025-02-28 11:00:00'), -- Before order 168
(108, 'kids adventure book', 26, 11.69, 14.29, '2025-03-01 11:00:00'), -- Between orders
(108, 'chronograph watch men', 9, 53.55, 65.45, '2025-03-08 11:00:00'), -- After return

-- User 109: Shirt ($31.75), Audiobook ($11.99), Top ($27.75), Classic ($12.99)
(109, 'striped formal shirt', 5, 28.58, 34.93, '2025-02-03 09:00:00'), -- Before order 170
(109, 'audiobook fiction', 28, 10.79, 13.19, '2025-02-04 12:00:00'), -- Between orders
(109, 'lace women’s top', 6, 24.98, 30.53, '2025-02-05 13:00:00'), -- After delivery

-- User 110: Trackpants ($20.99), Jeans ($39.99), Watch ($59.75), Shirt ($24.99)
(110, 'red trackpants', 7, 18.89, 23.09, '2025-03-11 08:00:00'), -- Before order 172
(110, 'gold watch men', 9, 53.78, 65.73, '2025-03-12 12:00:00'), -- Between orders
(110, 'slim fit jeans', 10, 35.99, 43.99, '2025-03-13 10:00:00'), -- After shipped

-- User 111: Shirt ($28.99), TV ($499.99), Top ($26.99), Fridge ($599.99)
(111, 'grey dress shirt', 5, 26.09, 31.89, '2025-03-18 12:00:00'), -- Before order 174
(111, 'qled tv 50 inch', 13, 449.99, 549.99, '2025-03-19 11:00:00'), -- Between orders
(111, 'inverter fridge', 14, 539.99, 659.99, '2025-03-20 16:00:00'), -- After delivery

-- User 112: Joggers ($23.50), AC ($399.99), Watch ($39.99), Washer ($799.99)
(112, 'green joggers men', 7, 21.15, 25.85, '2025-03-25 08:00:00'), -- Before order 176
(112, 'smart ac 1 ton', 15, 359.99, 439.99, '2025-03-25 12:00:00'), -- Between orders
(112, 'leather strap watch', 9, 35.99, 43.99, '2025-03-26 12:00:00');

SELECT * 
from user_search_history;

SELECT search_id,user_id,search_text,h.category_id,c.category_name,min_price,max_price,search_date
FROM user_search_history h
JOIN category c ON h.category_id=c.category_id
ORDER BY search_id;


SELECT *,
MATCH(search_text) AGAINST ('textbook') as relsearch
FROM user_search_history
WHERE MATCH(search_text) AGAINST ('textbook')
ORDER BY relsearch DESC;

ALTER TABLE product
ADD FULLTEXT (product_description,name,product_image_link);

ALTER TABLE product
ADD FULLTEXT (name);

ALTER TABLE product
ADD FULLTEXT (product_description,name);

SELECT *,
MATCH(product_description) AGAINST ('smartphone') as reldescr,
MATCH(name) AGAINST ('smartphone') as relname
FROM product
WHERE MATCH(product_description,name) AGAINST ('smartphone')
ORDER BY reldescr*2+relname*1 DESC;

SELECT *,
MATCH(product_description) AGAINST('blue') as reldescr
FROM product
WHERE MATCH(product_description) AGAINST ('cargo')
ORDER BY product_id;


SELECT * 
from product;

SELECT *,
MATCH(content) AGAINST ('watch') as relcon
FROM reviews
WHERE MATCH(content) AGAINST ('watch')
ORDER BY relcon DESC;

SELECT *
FROM reviews;

INSERT INTO inventory (product_id, stock_quantity, minimum_stock)
VALUES
-- Category 5: Men's Formal Shirts (30-60 stock, min 15)
(1, 45, 15), -- Blue Formal Shirt
(2, 50, 15), -- White Dress Shirt
(3, 40, 15), -- Black Formal Shirt
(4, 55, 15), -- Striped Formal Shirt
(5, 35, 15), -- Grey Formal Shirt
(6, 60, 15), -- Checkered Dress Shirt
(7, 50, 15), -- Navy Formal Shirt
(8, 45, 15), -- Red Formal Shirt
(9, 40, 15), -- Slim Fit Formal Shirt
(10, 55, 15), -- Formal Shirt with Tie

-- Category 6: Women's Tops (30-60 stock, min 15)
(11, 50, 15), -- Floral Blouse
(12, 45, 15), -- Sleeveless Top
(13, 40, 15), -- Off-Shoulder Top
(14, 55, 15), -- Lace Crop Top
(15, 60, 15), -- Red Peplum Top
(16, 50, 15), -- Striped Tank Top
(17, 45, 15), -- Silk Blouse
(18, 40, 15), -- Denim Shirt
(19, 55, 15), -- Polka Dot Top
(20, 60, 15), -- Chiffon Blouse

-- Category 7: Men's Trackpants (30-60 stock, min 15)
(21, 50, 15), -- Black Trackpants
(22, 45, 15), -- Grey Joggers
(23, 40, 15), -- Navy Trackpants
(24, 55, 15), -- Red Trackpants
(25, 60, 15), -- Green Joggers
(26, 50, 15), -- Blue Trackpants
(27, 45, 15), -- Striped Trackpants
(28, 40, 15), -- Cotton Trackpants
(29, 55, 15), -- Slim Fit Joggers
(30, 60, 15), -- Mesh Trackpants

-- Category 8: Women's Watches (20-40 stock, min 10)
(31, 30, 10), -- Rose Gold Watch
(32, 25, 10), -- Silver Analog Watch
(33, 35, 10), -- Smart Watch Pink
(34, 20, 10), -- Gold Bracelet Watch
(35, 40, 10), -- Black Leather Watch
(36, 30, 10), -- Diamond Studded Watch
(37, 25, 10), -- Blue Strap Watch
(38, 35, 10), -- Fitness Tracker Watch
(39, 20, 10), -- Minimalist Watch
(40, 40, 10), -- Chronograph Watch

-- Category 9: Men's Cargo Pants (30-60 stock, min 15)
(41, 40, 15), -- Khaki Cargo Pants
(42, 45, 15), -- Black Cargo Pants
(43, 50, 15), -- Olive Green Cargo
(44, 55, 15), -- Navy Cargo Pants
(45, 60, 15), -- Grey Cargo Pants
(46, 40, 15), -- Camouflage Cargo
(47, 45, 15), -- Brown Cargo Pants
(48, 50, 15), -- Slim Fit Cargo
(49, 55, 15), -- Cargo Shorts
(50, 60, 15), -- Ripstop Cargo Pants

-- Category 10: Men's Watches (20-40 stock, min 10)
(51, 30, 10), -- Black Sports Watch
(52, 25, 10), -- Silver Chronograph
(53, 35, 10), -- Smart Watch Black
(54, 20, 10), -- Leather Strap Watch
(55, 40, 10), -- Gold Analog Watch
(56, 30, 10), -- Dive Watch
(57, 25, 10), -- Blue Strap Watch
(58, 35, 10), -- Fitness Tracker
(59, 20, 10), -- Minimalist Watch
(60, 40, 10), -- Automatic Watch

-- Category 11: Women's Jeans (30-60 stock, min 15)
(61, 50, 15), -- High-Waist Jeans
(62, 45, 15), -- Skinny Jeans
(63, 40, 15), -- Ripped Jeans
(64, 55, 15), -- Bootcut Jeans
(65, 60, 15), -- Flare Jeans
(66, 50, 15), -- Mom Jeans
(67, 45, 15), -- White Jeans
(68, 40, 15), -- Distressed Jeans
(69, 55, 15), -- Ankle-Length Jeans
(70, 60, 15), -- Stretch Jeans

-- Category 12: Men's Casual Shirts (30-60 stock, min 15)
(71, 55, 15), -- Plaid Casual Shirt
(72, 60, 15), -- Denim Casual Shirt
(73, 50, 15), -- Graphic Tee
(74, 45, 15), -- Polo Shirt
(75, 40, 15), -- Henley Shirt
(76, 55, 15), -- Striped Casual Shirt
(77, 60, 15), -- Linen Shirt
(78, 50, 15), -- Checkered Shirt
(79, 45, 15), -- Short Sleeve Shirt
(80, 40, 15), -- Casual Button-Down

-- Category 13: Women's T-Shirts (30-60 stock, min 15)
(81, 50, 15), -- Graphic T-Shirt
(82, 45, 15), -- V-Neck T-Shirt
(83, 40, 15), -- Striped T-Shirt
(84, 55, 15), -- Crew Neck Tee
(85, 60, 15), -- Long Sleeve Tee
(86, 50, 15), -- Crop T-Shirt
(87, 45, 15), -- Slogan T-Shirt
(88, 40, 15), -- Tie-Dye T-Shirt
(89, 55, 15), -- Basic T-Shirt
(90, 60, 15), -- Oversized T-Shirt

-- Category 14: Smart TVs (5-20 stock, min 5)
(91, 15, 5), -- 55-Inch 4K Smart TV
(92, 10, 5), -- 65-Inch OLED TV
(93, 12, 5), -- 43-Inch LED TV
(94, 8, 5), -- 75-Inch 8K TV
(95, 15, 5), -- 50-Inch QLED TV
(96, 10, 5), -- 32-Inch Smart TV
(97, 12, 5), -- 60-Inch 4K TV
(98, 8, 5), -- 70-Inch LED TV
(99, 15, 5), -- 40-Inch Smart TV
(100, 10, 5), -- 85-Inch 4K TV

-- Category 15: Refrigerators (5-20 stock, min 5)
(101, 15, 5), -- Double Door Fridge
(102, 10, 5), -- Side-by-Side Fridge
(103, 12, 5), -- Single Door Fridge
(104, 8, 5), -- French Door Fridge
(105, 15, 5), -- Mini Fridge
(106, 10, 5), -- Inverter Fridge
(107, 12, 5), -- Frost-Free Fridge
(108, 8, 5), -- Smart Fridge
(109, 15, 5), -- Top Freezer Fridge
(110, 10, 5), -- Bottom Freezer Fridge

-- Category 16: Air Conditioners (5-20 stock, min 5)
(111, 15, 5), -- 1.5 Ton Split AC
(112, 10, 5), -- Window AC 1 Ton
(113, 12, 5), -- 2 Ton Inverter AC
(114, 8, 5), -- Portable AC
(115, 15, 5), -- 1 Ton Split AC
(116, 10, 5), -- 1.5 Ton Window AC
(117, 12, 5), -- 2.5 Ton Split AC
(118, 8, 5), -- Inverter AC 1.5 Ton
(119, 15, 5), -- Smart AC 1 Ton
(120, 10, 5), -- Cassette AC 2 Ton

-- Category 17: Washing Machines (5-20 stock, min 5)
(121, 15, 5), -- Front Load Washer
(122, 10, 5), -- Top Load Washer
(123, 12, 5), -- Semi-Automatic Washer
(124, 8, 5), -- 8kg Front Load
(125, 15, 5), -- 7kg Top Load
(126, 10, 5), -- Portable Washer
(127, 12, 5), -- 10kg Front Load
(128, 8, 5), -- 6.5kg Semi-Automatic
(129, 15, 5), -- 9kg Top Load
(130, 10, 5), -- Inverter Washer

-- Category 18: Laptops (5-20 stock, min 5)
(131, 15, 5), -- 15-Inch Laptop
(132, 10, 5), -- 13-Inch Ultrabook
(133, 12, 5), -- 14-Inch Laptop
(134, 8, 5), -- 17-Inch Laptop
(135, 15, 5), -- 15-Inch Touchscreen
(136, 10, 5), -- 13-Inch MacBook
(137, 12, 5), -- 14-Inch Business Laptop
(138, 8, 5), -- 15-Inch Budget Laptop
(139, 15, 5), -- 16-Inch Laptop
(140, 10, 5), -- 13-Inch Lightweight

-- Category 19: Gaming Laptops (5-20 stock, min 5)
(141, 15, 5), -- Gaming Laptop RTX 3060
(142, 10, 5), -- Gaming Laptop RTX 3070
(143, 12, 5), -- Gaming Laptop Ryzen 9
(144, 8, 5), -- 15-Inch Gaming Laptop
(145, 15, 5), -- 17-Inch Gaming Laptop
(146, 10, 5), -- Gaming Laptop RGB
(147, 12, 5), -- Budget Gaming Laptop
(148, 8, 5), -- Gaming Laptop 144Hz
(149, 15, 5), -- 16-Inch Gaming Laptop
(150, 10, 5), -- High-End Gaming Laptop

-- Category 20: Desktop PCs (5-20 stock, min 5)
(151, 15, 5), -- Gaming Desktop PC
(152, 10, 5), -- Workstation PC
(153, 12, 5), -- Budget Desktop PC
(154, 8, 5), -- All-in-One PC
(155, 15, 5), -- Mini Desktop PC
(156, 10, 5), -- High-End Desktop
(157, 12, 5), -- Office Desktop PC
(158, 8, 5), -- Custom Desktop PC
(159, 15, 5), -- Compact Desktop PC
(160, 10, 5), -- Media Desktop PC

-- Category 21: Tablets (5-20 stock, min 5)
(161, 15, 5), -- 10-Inch Tablet
(162, 10, 5), -- 8-Inch Tablet
(163, 12, 5), -- 12-Inch Tablet
(164, 8, 5), -- Tablet with Stylus
(165, 15, 5), -- Kids Tablet
(166, 10, 5), -- High-End Tablet
(167, 12, 5), -- Budget Tablet
(168, 8, 5), -- Tablet with Keyboard
(169, 15, 5), -- Android Tablet
(170, 10, 5), -- iPad 10-Inch

-- Category 22: DSLR Cameras (5-20 stock, min 5)
(171, 15, 5), -- Entry-Level DSLR
(172, 10, 5), -- Professional DSLR
(173, 12, 5), -- Mid-Range DSLR
(174, 8, 5), -- DSLR with Kit Lens
(175, 15, 5), -- Full-Frame DSLR
(176, 10, 5), -- DSLR for Vlogging
(177, 12, 5), -- Sports DSLR
(178, 8, 5), -- Compact DSLR
(179, 15, 5), -- DSLR with Wi-Fi
(180, 10, 5), -- Advanced DSLR

-- Category 23: Mobile Phones (5-20 stock, min 5)
(181, 15, 5), -- Smartphone 128GB
(182, 10, 5), -- Flagship Phone
(183, 12, 5), -- Budget Smartphone
(184, 8, 5), -- 5G Smartphone
(185, 15, 5), -- Gaming Smartphone
(186, 10, 5), -- Camera Phone
(187, 12, 5), -- Foldable Phone
(188, 8, 5), -- Mid-Range Phone
(189, 15, 5), -- iPhone 14
(190, 10, 5), -- Android Phone

-- Category 24: Academic Books (50-100 stock, min 20)
(191, 75, 20), -- Calculus Textbook
(192, 80, 20), -- Physics for Engineers
(193, 70, 20), -- Organic Chemistry
(194, 85, 20), -- Economics 101
(195, 90, 20), -- Computer Science Basics
(196, 75, 20), -- Statistics for Beginners
(197, 80, 20), -- Biology Textbook
(198, 70, 20), -- Algebra Made Easy
(199, 85, 20), -- History of Science
(200, 90, 20), -- Engineering Mechanics

-- Category 25: Non-Fiction Books (50-100 stock, min 20)
(201, 75, 20), -- Sapiens
(202, 80, 20), -- Becoming
(203, 70, 20), -- The Power of Habit
(204, 85, 20), -- Educated
(205, 90, 20), -- Atomic Habits
(206, 75, 20), -- Thinking, Fast and Slow
(207, 80, 20), -- The Subtle Art
(208, 70, 20), -- Outliers
(209, 85, 20), -- Grit
(210, 90, 20), -- Man’s Search for Meaning

-- Category 26: Young Readers (50-100 stock, min 20)
(211, 75, 20), -- Harry Potter Book 1
(212, 80, 20), -- The Hobbit
(213, 70, 20), -- Percy Jackson Book 1
(214, 85, 20), -- Charlotte’s Web
(215, 90, 20), -- The Lion, the Witch
(216, 75, 20), -- Diary of a Wimpy Kid
(217, 80, 20), -- Matilda
(218, 70, 20), -- The Secret Garden
(219, 85, 20), -- Holes
(220, 90, 20), -- Wonder

-- Category 27: Fiction Books (50-100 stock, min 20)
(221, 75, 20), -- To Kill a Mockingbird
(222, 80, 20), -- 1984
(223, 70, 20), -- Pride and Prejudice
(224, 85, 20), -- The Great Gatsby
(225, 90, 20), -- The Catcher in the Rye
(226, 75, 20), -- Lord of the Flies
(227, 80, 20), -- Animal Farm
(228, 70, 20), -- Brave New World
(229, 85, 20), -- The Alchemist
(230, 90, 20), -- Dune

-- Category 28: Literature (50-100 stock, min 20)
(231, 75, 20), -- Moby-Dick
(232, 80, 20), -- War and Peace
(233, 70, 20), -- Ulysses
(234, 85, 20), -- The Odyssey
(235, 90, 20), -- Crime and Punishment
(236, 75, 20), -- Les Misérables
(237, 80, 20), -- Jane Eyre
(238, 70, 20), -- Wuthering Heights
(239, 85, 20), -- Great Expectations
(240, 90, 20), -- Anna Karenina

-- Category 29: Audiobooks (50-100 stock, min 20)
(241, 75, 20), -- Sapiens Audiobook
(242, 80, 20), -- Becoming Audiobook
(243, 70, 20), -- Harry Potter Audiobook
(244, 85, 20), -- 1984 Audiobook
(245, 90, 20), -- The Alchemist Audiobook
(246, 75, 20), -- Atomic Habits Audiobook
(247, 80, 20), -- Pride and Prejudice Audiobook
(248, 70, 20), -- The Hobbit Audiobook
(249, 85, 20), -- Dune Audiobook
(250, 90, 20); -- Educated Audiobook

SELECT *
FROM inventory;

DELIMITER //

CREATE PROCEDURE process_purchase(
    IN p_user_id INT UNSIGNED,
    IN p_product_id INT UNSIGNED,
    IN p_requested_quantity INT UNSIGNED,
    IN p_shipping_address INT unsigned,
    IN p_payment_method_id INT unsigned,
    IN p_shipping_method_id INT unsigned,
    IN p_coupon_id INT unsigned,
    OUT p_message VARCHAR(100)
)
BEGIN
    DECLARE current_stock INT UNSIGNED;
    DECLARE product_price DECIMAL(10, 2) DEFAULT 0.0;
    DECLARE new_order_id INT UNSIGNED;
    START TRANSACTION;
    SELECT stock_quantity
    INTO current_stock
    FROM inventory
    WHERE product_id = p_product_id
    FOR UPDATE;
    IF current_stock >= p_requested_quantity THEN
        UPDATE inventory
        SET stock_quantity = stock_quantity - p_requested_quantity
        WHERE product_id = p_product_id;
		INSERT INTO orders (user_id,shipping_address_id,payment_method_id,shipping_method_id,coupon_id)
		VALUES (p_user_id,p_shipping_address,p_payment_method_id,p_shipping_method_id,p_coupon_id);
        SET new_order_id = LAST_INSERT_ID();
        SELECT price INTO product_price
        FROM product
        WHERE product_id=p_product_id;
        INSERT INTO order_items(order_id,product_id, quantity, price)
        VALUES(new_order_id,p_product_id,p_requested_quantity,product_price);
        COMMIT;
        SET p_message = 'Purchase successful';
    ELSE
        ROLLBACK;
        SET p_message = 'Out of stock';
    END IF;
END //

DELIMITER ;

CALL process_purchase(23,45,2,34,30,3,NULL,@message); -- (user_id, product_id, requested_quantity, shipping_address_id, payment_method_id, shipping_method_id, coupon_id)
SELECT @message AS message;

SELECT *
FROM inventory;


SELECT *
FROM orders;


SELECT *
FROM orders;

SELECT *
FROM inventory;

SELECT *
FROM order_items;

SELECT *
FROM product;

SELECT *
FROM orders;

SELECT user_id, COUNT(order_id) as count
FROM orders
WHERE MONTH(order_date)=2
GROUP BY user_id
ORDER BY COUNT(order_id) DESC
LIMIT 3;

WITH vendors AS(
SELECT user_id as vend
FROM users
WHERE user_role='Vendor')
SELECT v.vend
FROM vendors v
LEFT JOIN orders o
ON o.user_id=v.vend
WHERE year(o.order_date)=2025 and MONTH(o.order_date)=1
GROUP BY v.vend
HAVING COUNT(o.order_id)=1;

SET @THIS_YEAR = 2025, @THIS_MONTH = 3;

SELECT (SELECT COUNT(DISTINCT users.user_id) 
		FROM users, product, orders, order_items
		WHERE users.user_id = product.vendor_id and product.product_id = order_items.product_id and order_items.order_id = orders.order_id
        and MONTH(orders.order_date) = @THIS_MONTH and YEAR(orders.order_date) = @THIS_YEAR) as active_vendors, COUNT(users.user_id) as all_vendors
FROM users
WHERE users.user_role = 'Vendor';


SELECT *
FROM product;



SELECT vendor_id
FROM(
SELECT vendor_id, COUNT(*),DENSE_RANK() OVER(ORDER BY COUNT(*) DESC) as r
FROM product
GROUP BY vendor_id
ORDER  BY vendor_id) as t
WHERE t.r=1;

SELECT user_id
FROM(
SELECT user_id, COUNT(*), DENSE_RANK() OVER(ORDER BY COUNT(*) DESC) AS r
FROM orders
GROUP BY user_id
ORDER BY COUNT(*) DESC) AS t
WHERE t.r=1
ORDER BY user_id;

SELECT MONTH(o.order_date) AS mon, p.vendor_id, SUM(i.quantity*i.price) AS gross_sales, RANK() OVER(PARTITION BY MONTH(o.order_date) ORDER BY SUM(i.quantity*i.price) DESC) AS revenue_rank
FROM product p
JOIN order_items i ON p.product_id=i.product_id
JOIN orders o ON o.order_id=i.order_id
WHERE YEAR(order_date)=2022
GROUP BY MONTH(o.order_date), p.vendor_id;

SELECT MONTH(o.order_date) AS mon, p.vendor_id, SUM(i.quantity * i.price * (1 - COALESCE(sale_coupon.discount, 0) / 100)) as revenue, RANK() OVER(PARTITION BY MONTH(o.order_date) ORDER BY SUM(i.quantity * i.price * (1 - COALESCE(sale_coupon.discount, 0) / 100)) DESC) as r 
FROM product p
JOIN order_items i ON p.product_id=i.product_id
JOIN orders o ON o.order_id=i.order_id
LEFT JOIN sale_coupon ON o.coupon_id=sale_coupon.coupon_id
WHERE YEAR(order_date)=2022
GROUP BY MONTH(o.order_date), p.vendor_id
ORDER BY MONTH(o.order_date);

SELECT t.mon,t.vendor, t.revenue as rev
from (
SELECT MONTH(o.order_date) as mon,p.vendor_id as vendor, SUM(i.quantity * i.price * (1 - COALESCE(sale_coupon.discount, 0) / 100)) as revenue, RANK() OVER(PARTITION BY MONTH(o.order_date) ORDER BY SUM(i.quantity * i.price * (1 - COALESCE(sale_coupon.discount, 0) / 100)) DESC) as r 
FROM product p
JOIN order_items i ON p.product_id=i.product_id
JOIN orders o ON o.order_id=i.order_id
LEFT JOIN sale_coupon ON o.coupon_id=sale_coupon.coupon_id
WHERE YEAR(order_date)=2022
GROUP BY MONTH(o.order_date), p.vendor_id
ORDER BY MONTH(o.order_date)) AS t
WHERE t.r=1;

SELECT o.user_id, SUM(i.quantity*i.price) as gross_sales, DENSE_RANK() OVER(ORDER BY SUM(i.quantity*i.price) DESC) as sales_rank
FROM orders o
JOIN order_items i ON o.order_id=i.order_id
GROUP BY user_id
ORDER BY gross_sales DESC
LIMIT 5;

SELECT o.user_id, SUM(i.quantity * i.price * (1 - COALESCE(sale_coupon.discount, 0) / 100)) as revenue, DENSE_RANK() OVER(ORDER BY SUM(i.quantity * i.price * (1 - COALESCE(sale_coupon.discount, 0) / 100)) DESC) as revenue_rank
FROM orders o
JOIN order_items i ON o.order_id=i.order_id
LEFT JOIN sale_coupon ON o.coupon_id=sale_coupon.coupon_id
GROUP BY user_id
ORDER BY revenue DESC
LIMIT 5;

SELECT p.vendor_id, AVG(r.rating_value) as rating
FROM product p
JOIN reviews r ON p.product_id=r.product_id
GROUP BY vendor_id
ORDER BY AVG(r.rating_value) DESC
LIMIT 5;

SELECT *
FROM orders;

SELECT t.id,t.name,t.orderid,t.order_value
FROM(
SELECT u.user_id as id, u.username as name, o.order_id as orderid,ANY_VALUE(IF(ISNULL(o.coupon_id), SUM(i.price*i.quantity), SUM(i.price*i.quantity)*(1-(sale_coupon.discount/100)))) as order_value, DENSE_RANK() OVER(PARTITION BY u.user_id ORDER BY ANY_VALUE(IF(ISNULL(o.coupon_id), SUM(i.price*i.quantity), SUM(i.price*i.quantity)*(1-(sale_coupon.discount/100)))) DESC) as ranking
FROM users u
JOIN orders o ON u.user_id=o.user_id
JOIN order_items i ON o.order_id=i.order_id
LEFT JOIN sale_coupon ON o.coupon_id=sale_coupon.coupon_id
GROUP BY u.user_id, o.order_id
ORDER BY u.user_id) as t
WHERE t.ranking=1;

SELECT user_id, COUNT(order_id)
FROM orders
GROUP BY user_id
ORDER BY user_id;

SELECT user_id, COUNT(order_id), DENSE_RANK() OVER(ORDER BY COUNT(order_id) DESC)
FROM orders
WHERE MONTH(order_date)=2 and YEAR(order_date)=2025
GROUP BY user_id;


SELECT t.id, t.coun
from (
SELECT user_id AS id, COUNT(order_id) AS coun
FROM orders
WHERE order_date >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
GROUP BY user_id) as t
WHERE t.coun>=2;

WITH rev AS(
SELECT YEAR(order_date) as y, MONTH(order_date) as m, SUM(i.quantity * i.price * (1 - COALESCE(sale_coupon.discount, 0) / 100)) as revenue
FROM orders o
JOIN order_items i ON o.order_id=i.order_id
LEFT JOIN sale_coupon ON sale_coupon.coupon_id=o.coupon_id
GROUP BY YEAR(order_date), MONTH(order_date)
ORDER BY YEAR(order_date), MONTH(order_date)),
year_1 as (
SELECT rev.revenue as y1
FROM rev
WHERE rev.y=2022 AND rev.m=7),
year_2 as (
SELECT rev.revenue as y2
FROM rev
WHERE rev.y=2023 AND rev.m=7
)
SELECT y1, y2 FROM year_1, year_2;


SELECT COUNT(user_id)
FROM users
WHERE user_role='Vendor';

SELECT COUNT(p.vendor_id)
FROM orders o 
JOIN order_items i ON o.order_id=i.order_id
JOIN product p ON i.product_id=p.product_id
WHERE YEAR(order_date)=2025 AND MONTH(order_date)=3;

SELECT t.id, t.coun
FROM
(SELECT vendor_id as id , COUNT(product_id) as coun, DENSE_RANK() OVER(ORDER BY COUNT(product_id) DESC) as r
FROM product
GROUP BY vendor_id) as t
WHERE t.r=1;

SELECT user_id, COUNT(order_id), DENSE_RANK() OVER(ORDER BY COUNT(order_id) DESC) 
FROM orders
WHERE YEAR(order_date)=2025 AND MONTH(order_date)=3
GROUP BY user_id;

SELECT t.mon, t.id, t.revenue
FROM(
SELECT MONTH(o.order_date) as mon, p.vendor_id as id, SUM(i.quantity * i.price * (1 - COALESCE(sale_coupon.discount, 0) / 100)) as revenue, RANK() OVER(PARTITION BY MONTH(order_date) ORDER BY SUM(i.quantity * i.price * (1 - COALESCE(sale_coupon.discount, 0) / 100)) DESC) as r
FROM orders o
JOIN order_items i ON o.order_id=i.order_id
LEFT JOIN sale_coupon ON sale_coupon.coupon_id=o.coupon_id
JOIN product p ON i.product_id=p.product_id
WHERE YEAR(order_date)=2022
GROUP BY MONTH(o.order_date),p.vendor_id) t
WHERE t.r<=5;

SELECT t.id, SUM(t.order_total)
FROM (
SELECT o.user_id as id ,o.order_id ,ANY_VALUE(IF(ISNULL(o.coupon_id),(SUM(i.quantity*i.price)), SUM(i.quantity*i.price)*(1-(sale_coupon.discount/100)))) as order_total
FROM orders o
JOIN order_items i ON i.order_id=o.order_id
LEFT JOIN sale_coupon ON sale_coupon.coupon_id=o.coupon_id
WHERE YEAR(order_date)=2022 AND o.order_status != 'Cancelled' and o.order_status != 'Returned'
GROUP BY o.user_id,o.order_id) t
GROUP BY t.id
ORDER BY SUM(t.order_total) DESC;

SELECT *
FROM sale_coupon;

SELECT *
from orders;

SELECT *
FROM order_items; 

SELECT t1.user_id, SUM(t1.revenue) as total_revenue
FROM(SELECT users.user_id as user_id, users.username as username, orders.order_id as order_id,
		ANY_VALUE(IF(ISNULL(orders.coupon_id),SUM(order_items.price* order_items.quantity), 
			SUM(order_items.price* order_items.quantity) *(1-sale_coupon.discount/100))) as revenue
	FROM users 
		JOIN orders ON users.user_id = orders.user_id
		JOIN order_items ON order_items.order_id = orders.order_id
		LEFT JOIN sale_coupon ON sale_coupon.coupon_id = orders.coupon_id
		WHERE  orders.order_status != 'Cancelled' and orders.order_status != 'Returned' and YEAR(orders.order_date) = 2022
	GROUP BY users.user_id, users.username, order_id ) as t1
GROUP BY t1.user_id
ORDER BY t1.revenue DESC;


SELECT t1.user_id, t1.username, SUM(t1.revenue) as total_revenue
FROM(SELECT users.user_id as user_id, users.username as username, orders.order_id as order_id,
		ANY_VALUE(IF(ISNULL(orders.coupon_id),SUM(order_items.price* order_items.quantity), 
			SUM(order_items.price* order_items.quantity) *(1-sale_coupon.discount/100))) as revenue
	FROM users 
		JOIN orders ON users.user_id = orders.user_id
		JOIN order_items ON order_items.order_id = orders.order_id
		LEFT JOIN sale_coupon ON sale_coupon.coupon_id = orders.coupon_id
		WHERE  orders.order_status != 'Cancelled' and orders.order_status != 'Returned' and YEAR(orders.order_date) = 2022
	GROUP BY users.user_id, users.username, order_id ) as t1
GROUP BY t1.user_id, t1.username
ORDER BY total_revenue DESC;

SELECT *
FROM reviews;

SELECT vendor_id, AVG(rating_value)
FROM reviews
GROUP BY vendor_id
ORDER BY AVG(rating_value) DESC;



SELECT *,
MATCH(name) AGAINST('trackpants') as relname,
MATCH(product_description) AGAINST('blue') as reldescr
FROM product
WHERE MATCH(name,product_description) AGAINST ('trackpants blue') 
ORDER BY relname*2+reldescr DESC;
























