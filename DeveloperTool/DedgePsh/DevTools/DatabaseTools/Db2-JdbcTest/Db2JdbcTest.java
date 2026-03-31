import java.io.Console;
import java.sql.*;
import java.util.*;

public class Db2JdbcTest {
    public static void main(String[] args) {
        String host = "t-no1inltst-db";
        int port = 3718;
        String database = "INLTST";
        String user = "DEDGE\\fkgeista";
        String password = null;

        // Allow overrides via args: host port database user password
        if (args.length >= 1) host = args[0];
        if (args.length >= 2) port = Integer.parseInt(args[1]);
        if (args.length >= 3) database = args[2];
        if (args.length >= 4) user = args[3];
        if (args.length >= 5) password = args[4];

        if (password == null || password.isEmpty()) {
            Console console = System.console();
            if (console != null) {
                char[] pw = console.readPassword("Password for %s: ", user);
                password = new String(pw);
            } else {
                Scanner sc = new Scanner(System.in);
                System.out.print("Password for " + user + ": ");
                password = sc.nextLine();
            }
        }

        String url = "jdbc:db2://" + host + ":" + port + "/" + database;

        System.out.println("=== DB2 JDBC Connection Test ===");
        System.out.println("URL:  " + url);
        System.out.println("User: " + user);
        System.out.println();

        // Test with different security mechanisms
        int[] secMechs = { 0, 7, 9, 3 };
        String[] secNames = { "(default/driver-chosen)", "ENCRYPTED_PASSWORD (7)", "ENCRYPTED_USER_PASSWORD (9)", "USERID_PASSWORD (3)" };

        for (int i = 0; i < secMechs.length; i++) {
            System.out.println("--- Security mechanism: " + secNames[i] + " ---");
            Properties props = new Properties();
            props.setProperty("user", user);
            props.setProperty("password", password);
            if (secMechs[i] != 0) {
                props.setProperty("securityMechanism", String.valueOf(secMechs[i]));
            }

            try {
                Class.forName("com.ibm.db2.jcc.DB2Driver");
                long t0 = System.currentTimeMillis();
                Connection conn = DriverManager.getConnection(url, props);
                long elapsed = System.currentTimeMillis() - t0;
                System.out.println("  CONNECTED in " + elapsed + " ms");

                try {
                    DatabaseMetaData md = conn.getMetaData();
                    System.out.println("  Server: " + md.getDatabaseProductName() + " " + md.getDatabaseProductVersion());
                    System.out.println("  Driver: " + md.getDriverName() + " " + md.getDriverVersion());

                    Statement stmt = conn.createStatement();
                    ResultSet rs = stmt.executeQuery("SELECT COUNT(*) AS CNT FROM inl.KONTOTYPE");
                    if (rs.next()) {
                        System.out.println("  SELECT COUNT(*) FROM inl.KONTOTYPE = " + rs.getInt(1));
                    }
                    rs.close();
                    stmt.close();
                } finally {
                    conn.close();
                }
                System.out.println("  SUCCESS");
                System.out.println();
                System.out.println("=== WORKING security mechanism: " + secNames[i] + " ===");
                return;

            } catch (Exception e) {
                System.out.println("  FAILED: " + e.getMessage());
            }
            System.out.println();
        }
        System.out.println("=== ALL security mechanisms FAILED ===");
        System.exit(1);
    }
}
