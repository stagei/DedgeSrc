# SQLite sample database

## Create the sample database

**Option 1 – SQLite CLI (after `winget install SQLite.SQLite`)**  
Open a **new** terminal (so `sqlite3` is on PATH), then:

```powershell
cd c:\opt\src\DbExplorer\SampleData
sqlite3 sample.db < CreateSampleDb.sql
```

**Option 2 – Let the app create the file**  
In DbExplorer, create a connection with:

- **Provider:** SQLite  
- **Database:** full path to the file, e.g. `c:\opt\src\DbExplorer\SampleData\sample.db`  
- **Server / Port / Username / Password:** leave empty or default  

Connect; if the file does not exist, SQLite creates it. Then run the contents of `CreateSampleDb.sql` in the SQL editor to create tables and data.

## Contents

- **users** – id, username, email, created_at  
- **products** – id, name, price, created_at  
- **orders** – id, user_id, product_id, quantity, created_at  
- **v_order_summary** – view joining orders, users, products  

Sample rows are inserted for users, products, and orders.
