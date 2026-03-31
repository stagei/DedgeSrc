# DBeaver DB2 Connection Guide - Windows SSO

## 🚨 Important: Security Mechanism 15 Requires SSL

**securityMechanism=15 (Windows SSPI) only works with SSL connections.** If you get the error:
```
non-SSL connection are not supported for security mechanism 15(PLUGIN_SECURITY)
```

You need to use one of these solutions:

## ✅ Working Connection Options

### Option 1: SSL + Windows SSPI (Recommended)
```
Host: t-no1fkmdev-db.DEDGE.fk.no
Port: 50001 (SSL port)
Database: FKAVDNT
URL: jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:50001/FKAVDNT:securityMechanism=15;sslConnection=true;
```

**DBeaver Settings:**
- SSL Tab: ✅ Use SSL = Yes
- Driver Properties: `securityMechanism=15`, `sslConnection=true`
- Username/Password: **Leave EMPTY**

### Option 2: Non-SSL + Kerberos (Alternative)
```
Host: t-no1fkmdev-db.DEDGE.fk.no
Port: 3710 (non-SSL port)
Database: FKAVDNT
URL: jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:3710/FKAVDNT:securityMechanism=11;kerberosServerPrincipal=db2srv/t-no1fkmdev-db.DEDGE.fk.no@DEDGE.FK.NO;
```

**DBeaver Settings:**
- SSL Tab: ❌ Use SSL = No
- Driver Properties: `securityMechanism=11`, `kerberosServerPrincipal=db2srv/t-no1fkmdev-db.DEDGE.fk.no@DEDGE.FK.NO`
- Username/Password: **Leave EMPTY**

### Option 3: SSL + Kerberos (Full Security)
```
Host: t-no1fkmdev-db.DEDGE.fk.no
Port: 50001 (SSL port)
Database: FKAVDNT
URL: jdbc:db2://t-no1fkmdev-db.DEDGE.fk.no:50001/FKAVDNT:securityMechanism=11;sslConnection=true;kerberosServerPrincipal=db2srv/t-no1fkmdev-db.DEDGE.fk.no@DEDGE.FK.NO;
```

**DBeaver Settings:**
- SSL Tab: ✅ Use SSL = Yes
- Driver Properties: `securityMechanism=11`, `sslConnection=true`, `kerberosServerPrincipal=db2srv/t-no1fkmdev-db.DEDGE.fk.no@DEDGE.FK.NO`
- Username/Password: **Leave EMPTY**

## 🔧 DBeaver Configuration Steps

1. **Create New Connection**
   - Database: DB2 LUW
   - Choose your preferred option above

2. **Main Tab**
   - Server Host: `t-no1fkmdev-db.DEDGE.fk.no`
   - Port: `50001` (SSL) or `3710` (non-SSL)
   - Database: `FKAVDNT`
   - **Username: LEAVE EMPTY**
   - **Password: LEAVE EMPTY**

3. **SSL Tab** (for SSL options)
   - Use SSL: Yes
   - SSL Mode: Require

4. **Driver Properties Tab**
   - Add the properties from your chosen option above

## 🚨 Common Mistakes

❌ **Wrong:** Using securityMechanism=15 with non-SSL port
❌ **Wrong:** Entering username/password (should be empty)
❌ **Wrong:** Not enabling SSL when using securityMechanism=15

✅ **Correct:** Match security mechanism with SSL settings
✅ **Correct:** Leave username/password empty for SSO
✅ **Correct:** Enable SSL for securityMechanism=15

## 🧪 Testing Order

Try in this order:
1. **Option 1** (SSL + Windows SSPI) - Simplest if SSL is working
2. **Option 2** (Non-SSL + Kerberos) - If SSL certificate issues
3. **Option 3** (SSL + Kerberos) - Most secure option

## 📋 Troubleshooting

### SSL Certificate Issues
- Run the certificate import script first
- Restart DBeaver after certificate import
- Check that SSL port (50001) is accessible

### Kerberos Issues  
- Ensure krb5.ini is in C:\Windows\
- Check Kerberos tickets: `klist`
- Verify domain authentication is working 