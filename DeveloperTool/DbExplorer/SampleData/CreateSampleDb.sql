-- SQLite sample database for DbExplorer
-- Run: sqlite3 sample.db < CreateSampleDb.sql  (after winget install SQLite.SQLite)

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  email TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  price REAL NOT NULL DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS orders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  product_id INTEGER NOT NULL REFERENCES products(id),
  quantity INTEGER NOT NULL DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_product ON orders(product_id);

CREATE VIEW IF NOT EXISTS v_order_summary AS
SELECT o.id, u.username, p.name AS product, o.quantity, (p.price * o.quantity) AS total
FROM orders o
JOIN users u ON u.id = o.user_id
JOIN products p ON p.id = o.product_id;

INSERT OR IGNORE INTO users (id, username, email) VALUES (1, 'alice', 'alice@example.com');
INSERT OR IGNORE INTO users (id, username, email) VALUES (2, 'bob', 'bob@example.com');
INSERT OR IGNORE INTO products (id, name, price) VALUES (1, 'Widget', 9.99);
INSERT OR IGNORE INTO products (id, name, price) VALUES (2, 'Gadget', 19.99);
INSERT OR IGNORE INTO orders (id, user_id, product_id, quantity) VALUES (1, 1, 1, 2);
INSERT OR IGNORE INTO orders (id, user_id, product_id, quantity) VALUES (2, 2, 2, 1);
