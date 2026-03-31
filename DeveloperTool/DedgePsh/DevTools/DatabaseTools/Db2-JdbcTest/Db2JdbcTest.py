"""
DB2 JDBC Connection Test via JayDeBeApi (same JCC driver as DBeaver).
Tests multiple security mechanisms to find one that works.
"""
import sys
import os
import time
import getpass

import jpype
if not jpype.isJVMStarted():
    jpype.startJVM(jpype.getDefaultJVMPath())

import jaydebeapi
import glob

_jcc_base = os.path.join(os.environ.get("APPDATA", ""), "DBeaverData", "drivers",
                         "maven", "maven-central", "com.ibm.db2")
_jcc_candidates = sorted(glob.glob(os.path.join(_jcc_base, "jcc-*.jar")), reverse=True)
JCC_JAR = _jcc_candidates[0] if _jcc_candidates else ""

def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "t-no1inltst-db"
    port = sys.argv[2] if len(sys.argv) > 2 else "3718"
    database = sys.argv[3] if len(sys.argv) > 3 else "FKKTOTST"
    user = sys.argv[4] if len(sys.argv) > 4 else r"DEDGE\fkgeista"
    password = sys.argv[5] if len(sys.argv) > 5 else None
    control_table = sys.argv[6] if len(sys.argv) > 6 else "inl.KONTOTYPE"

    if not password:
        password = getpass.getpass(f"Password for {user}: ")

    jar = JCC_JAR
    if not os.path.isfile(jar):
        print("ERROR: DB2 JCC driver JAR not found")
        sys.exit(1)

    url = f"jdbc:db2://{host}:{port}/{database}"
    print("=" * 55)
    print("  DB2 JDBC Connection Test")
    print("=" * 55)
    print(f"  URL:    {url}")
    print(f"  User:   {user}")
    print(f"  Driver: {os.path.basename(jar)}")
    print()

    security_mechs = [
        (None, "Default (driver-chosen)"),
        ("9",  "EUSRIDPWD - Encrypted User+Password (9)"),
        ("7",  "USRENCPWD - Encrypted Password (7)"),
        ("3",  "USRIDPWD  - Plain User+Password (3)"),
    ]

    for sec_id, sec_name in security_mechs:
        print(f"--- {sec_name} ---")

        conn_props = {
            "user": user,
            "password": password,
        }
        if sec_id is not None:
            conn_props["securityMechanism"] = sec_id

        try:
            t0 = time.time()
            conn = jaydebeapi.connect(
                "com.ibm.db2.jcc.DB2Driver",
                url,
                conn_props,
                jar,
            )
            elapsed = int((time.time() - t0) * 1000)
            print(f"  CONNECTED in {elapsed} ms")

            cursor = conn.cursor()
            cursor.execute(f"SELECT COUNT(*) AS CNT FROM {control_table}")
            row = cursor.fetchone()
            if row:
                print(f"  SELECT COUNT(*) FROM {control_table} = {row[0]}")
            cursor.close()
            conn.close()

            print(f"  SUCCESS")
            print()
            print(f"=== WORKING: {sec_name} ===")
            return 0

        except Exception as e:
            msg = str(e)
            if len(msg) > 200:
                msg = msg[:200] + "..."
            print(f"  FAILED: {msg}")
        print()

    print("=== ALL security mechanisms FAILED ===")
    return 1


if __name__ == "__main__":
    sys.exit(main())
