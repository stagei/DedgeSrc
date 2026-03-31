# Using a Local PostgreSQL Instance with DedgeAuth

This guide describes how to run DedgeAuth against a **local** PostgreSQL instance. It focuses on **port configuration** and connection settings; the database name and other options stay as configured unless you change them.

---

## Default Ports

| Component      | Default port | Purpose                    |
|----------------|-------------|----------------------------|
| PostgreSQL     | **8432**    | Server listens here        |
| DedgeAuth API     | **8100**    | Web API and login UI       |

Use these defaults when PostgreSQL and DedgeAuth run on the same machine and no other PostgreSQL or app uses the same ports.

---

## Connection String and Port

DedgeAuth reads the connection string from `ConnectionStrings:AuthDb` (e.g. in `appsettings.json` or environment).

**Format (Npgsql):**

```
Host=<host>;Port=<port>;Database=<database>;Username=<user>;Password=<password>
```

**Local instance, default port (8432):**

```
Host=localhost;Port=8432;Database=DedgeAuth;Username=postgres;Password=postgres
```

**Local instance, custom port (e.g. 5433):**

If your local PostgreSQL runs on a different port (e.g. to avoid conflict with another instance):

```
Host=localhost;Port=5433;Database=DedgeAuth;Username=postgres;Password=postgres
```

- **Host:** `localhost` or `127.0.0.1` for local.
- **Port:** Must match the port your PostgreSQL server is listening on.
- **Database:** Database name (e.g. `DedgeAuth`). Create it if it does not exist (see below).
- **Username / Password:** PostgreSQL user; ensure the user can create databases if the install script creates `DedgeAuth`.

---

## Where to Set the Port

### 1. appsettings.json (DedgeAuth.Api)

Edit `src/DedgeAuth.Api/appsettings.json`:

```json
"ConnectionStrings": {
  "AuthDb": "Host=localhost;Port=8432;Database=DedgeAuth;Username=postgres;Password=postgres"
}
```

Change `Port=8432` to your local PostgreSQL port (e.g. `Port=5433`). Leave database name and rest as needed.

### 2. Install-DedgeAuth.ps1

The install script accepts port (and host/user/password/database):

```powershell
.\scripts\Install-DedgeAuth.ps1 -PostgresHost localhost -PostgresPort 8432 -PostgresUser postgres -PostgresPassword "yourpassword" -DatabaseName DedgeAuth
```

Use `-PostgresPort 5433` (or your port) when the local instance is not on 8432. The script builds the connection string and writes it into the published app’s `appsettings.json`.

### 3. Environment variable

Override at runtime without changing files:

**Windows (PowerShell):**

```powershell
$env:ConnectionStrings__AuthDb = "Host=localhost;Port=8432;Database=DedgeAuth;Username=postgres;Password=postgres"
dotnet run --project src/DedgeAuth.Api
```

**Windows (cmd):**

```cmd
set ConnectionStrings__AuthDb=Host=localhost;Port=8432;Database=DedgeAuth;Username=postgres;Password=postgres
```

Replace `Port=8432` with your local PostgreSQL port.

### 4. User secrets (development)

From the API project directory:

```powershell
cd src/DedgeAuth.Api
dotnet user-secrets set "ConnectionStrings:AuthDb" "Host=localhost;Port=8432;Database=DedgeAuth;Username=postgres;Password=postgres"
```

Again, change the port number to match your local instance.

---

## Checking Which Port PostgreSQL Uses

**Windows:**

1. **Services:** Check the PostgreSQL service; its binary often shows the port in the service parameters or in the installer config.
2. **Listening ports:**
   ```powershell
   Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in 8432, 5433, 5434 }
   ```
3. **postgresql.conf:** In the PostgreSQL data directory, look for:
   ```ini
   port = 8432
   ```
   Change and restart PostgreSQL if you want a different port.

**Connect and test:**

```powershell
# Default port
& "C:\Program Files\PostgreSQL\16\bin\psql.exe" -h localhost -p 8432 -U postgres -d postgres -c "SELECT version();"

# Custom port
& "C:\Program Files\PostgreSQL\16\bin\psql.exe" -h localhost -p 5433 -U postgres -d postgres -c "SELECT version();"
```

Use the same `-p` value in the DedgeAuth connection string.

---

## Creating the Database (Local Instance)

If the database does not exist yet:

**Using psql (replace port if not 8432):**

```powershell
$env:PGPASSWORD = "postgres"
& "C:\Program Files\PostgreSQL\16\bin\psql.exe" -h localhost -p 8432 -U postgres -d postgres -c "CREATE DATABASE DedgeAuth;"
```

**Using Install-DedgeAuth.ps1:**

The script creates the database using the port (and host/user/password) you pass; ensure PostgreSQL is running on that port before running the script.

---

## Multiple Local PostgreSQL Instances (Different Ports)

If you run several PostgreSQL versions or instances on the same machine, each uses a different port (e.g. 8432, 5433, 5434). For DedgeAuth:

1. Choose the instance (and port) you want for DedgeAuth.
2. Set **only the port** (and host if needed) in the connection string; you can keep the same database name (e.g. `DedgeAuth`) on that instance.
3. Point DedgeAuth’s `ConnectionStrings:AuthDb` to that port (via appsettings, install script, or environment as above).

Example for second instance on 5433:

```
Host=localhost;Port=5433;Database=DedgeAuth;Username=postgres;Password=postgres
```

---

## Firewall and Local-Only Access

For a **local-only** setup:

- Bind PostgreSQL to `127.0.0.1` or `localhost` in `postgresql.conf` (`listen_addresses = 'localhost'`).
- No need to open the PostgreSQL port in the Windows firewall for other machines.
- DedgeAuth API can still listen on `0.0.0.0:8100` or `localhost:8100` as configured; that is independent of the PostgreSQL port.

---

## Summary

- **Local PostgreSQL:** Use `Host=localhost` (or `127.0.0.1`) and the correct **port** (default **8432**).
- **Port only:** To use a different local instance, change **only** `Port=` in the connection string; database name and other parameters can stay the same.
- **Where to set:** `appsettings.json`, Install-DedgeAuth.ps1 parameters, environment variables, or user secrets.
- **Verify:** Use `psql -h localhost -p <port>` or `Get-NetTCPConnection` to confirm the port, then run DedgeAuth with the same port in `ConnectionStrings:AuthDb`.
