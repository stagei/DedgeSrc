{
    "serverGroups": [
        {
            "name": "sg-t-Dedge-db",
            "regex": "t-no1(?:[a-z]{3}|[a-z]{6})-db(?:[0-9]{2})?",
            "description": "Db2 servers Test",
            "isInternal": true
        },
        {
            "name": "sg-t-Dedge-app",
            "regex": "t-no1(?:[a-z]{3}|[a-z]{6})-app(?:[0-9]{2})?",
            "description": "Application servers Test",
            "isInternal": true
        },
        {
            "name": "sg-t-Dedge-web",
            "regex": "t-no1(?:[a-z]{3}|[a-z]{6})-web(?:[0-9]{2})?",
            "description": "Web servers Test",
            "isInternal": true
        },
        {
            "name": "sg-t-Dedge-soa",
            "regex": "t-no1(?:[a-z]{3}|[a-z]{6})-soa(?:[0-9]{2})?",
            "description": "SOA servers Test",
            "isInternal": true
        },
                {
            "name": "sg-p-Dedge-db",
            "regex": "p-no1(?:[a-z]{3}|[a-z]{6})-db(?:[0-9]{2})?",
            "description": "Db2 servers Production",
            "isInternal": true
        },
        {
            "name": "sg-p-Dedge-app",
            "regex": "p-no1(?:[a-z]{3}|[a-z]{6})-app(?:[0-9]{2})?",
            "description": "Application servers Production",
            "isInternal": true
        },
        {
            "name": "sg-p-Dedge-web",
            "regex": "p-no1(?:[a-z]{3}|[a-z]{6})-web(?:[0-9]{2})?",
            "description": "Web servers Production",
            "isInternal": true
        },
        {
            "name": "sg-p-Dedge-soa",
            "regex": "p-no1(?:[a-z]{3}|[a-z]{6})-soa(?:[0-9]{2})?",
            "description": "SOA servers Production",
            "isInternal": true
        },
        {
            "name": "sg-kimen",
            "regex": "",
            "description": "Kimen Såvarelaboratorier",
            "isInternal": false
        },
        {
            "name": "sg-mattilsynet",
            "regex": "",
            "description": "Mattilsynet",
            "isInternal": false
        },
        {
            "name": "sg-sms-provider",
            "regex": "",
            "description": "SMS Provider",
            "isInternal": false
        }

    ]
}



{
    "portGroups": [
        {
            "name": "pg-kerberos",
            "description": "Standard Kerberos Ports",
            "required": true,
            "ports": [
                {
                    "port": 88,
                    "protocols": ["TCP", "UDP"],
                    "description": "Main port used for Kerberos authentication traffic between clients and the KDC",
                    "hosts": ["p-no1dc-vm01", "p-no1dc-vm02"],
                    "internetAccess": false,
                    "required": true
                },
                {
                    "port": 749,
                    "protocols": ["TCP"],
                    "description": "Administrative access to Kerberos database (kadmin)",
                    "hosts": ["p-no1dc-vm01", "p-no1dc-vm02"],
                    "internetAccess": false,
                    "required": true
                },
                {
                    "port": 464,
                    "protocols": ["TCP", "UDP"],
                    "description": "Password changes (kpasswd)",
                    "hosts": ["p-no1dc-vm01", "p-no1dc-vm02"],
                    "internetAccess": false,
                    "required": true
                }
            ]
        },
        {
            "name": "pg-db2",
            "description": "Db2 ports",
            "required": true,
            "ports": [
                {
                    "portRange": {
                        "start": 3700,
                        "end": 3720
                    },
                    "protocols": ["TCP"],
                    "description": "DB2 port range",
                    "required": true
                },
                {
                    "port": 50000,
                    "protocols": ["TCP"],
                    "description": "DB2 main port",
                    "required": true
                }
            ]
        },
        {
            "name": "pg-fileSharing",
            "description": "File sharing ports",
            "required": true,
            "ports": [
                {
                    "port": 445,
                    "protocols": ["TCP"],
                    "description": "SMB",
                    "required": true
                },
                {
                    "port": 139,
                    "protocols": ["TCP"],
                    "description": "NetBIOS",
                    "required": true
                }
            ]
        },
        {
            "name": "pg-soa",
            "description": "SOA ports",
            "required": true,
            "ports": [
                {
                    "port": 9003,
                    "protocols": ["TCP"],
                    "description": "SOA main port",
                    "required": true
                },
                {
                    "port": 86,
                    "protocols": ["TCP"],
                    "description": "SOAWeb",
                    "required": true
                }
            ]
        },
        {
            "name": "pg-bulk",
            "description": "Bulk transfer port",
            "required": true,
            "ports": [
                {
                    "port": 80,
                    "protocols": ["TCP"],
                    "description": "Bulk transfer",
                    "required": true
                }
            ]
        }
        {
            "name": "pg-produsentregisteret",
            "description": "Produsentregisteret connection",
            "required": true,
            "ports": [
                {
                    "port": 21,
                    "protocols": ["TCP"],
                    "description": "FTP connection",
                    "hosts": ["ftp.prodreg.no"],
                    "required": true
                }
            ]
        },
        {
            "name": "pg-kimen",
            "description": "Kimen SQL Server connection",
            "required": true,
            "ports": [
                {
                    "port": 41433,
                    "protocols": ["TCP"],
                    "description": "SQL Server connection",
                    "hosts": ["79.160.38.90"],
                    "required": true
                }
            ]
        },
        {
            "name": "pg-mattilsynet",
            "description": "Mattilsynet SQL Server connection",
            "required": true,
            "ports": [
                {
                    "port": 1433,
                    "protocols": ["TCP"],
                    "description": "SQL Server connection",
                    "hosts": ["194.19.30.142"],
                    "required": true
                }
            ]
        },
        {
            "name": "pg-smsProvider",
            "description": "SMS Provider connection",
            "required": true,
            "ports": [
                {
                    "port": 80,
                    "protocols": ["TCP"],
                    "description": "SMS service",
                    "hosts": ["sms3.pswin.com"],
                    "required": true
                }
            ]
        },
        {
            "name": "pg-webserver",
            "description": "FKM Webserver ports",
            "required": true,
            "ports": [
                {
                    "port": 80,
                    "protocols": ["TCP"],
                    "description": "HTTP port",
                    "required": true
                },
                {
                    "portRange": {
                        "start": 8080,
                        "end": 9300
                    },
                    "protocols": ["TCP"],
                    "description": "Service port range 1",
                    "required": true
                },
                {
                    "portRange": {
                        "start": 17000,
                        "end": 17300
                    },
                    "protocols": ["TCP"],
                    "description": "Service port range 2",
                    "required": true
                }
            ]
        }
    ]
}

{
    "serverGroupsPortGroups": [
        {
            "serverGroupName": "sg-t-Dedge-db",
            "providerPortGroupNames": ["pg-db2","pg-fileSharing"],
            "consumerPortGroupNames": ["pg-kerberos", "pg-fileSharing", "pg-smsProvider", "pg-webserver"]
        },
        {
            "serverGroupName": "sg-t-Dedge-app", 
            "providerPortGroupNames": ["pg-fileSharing"],
            "consumerPortGroupNames": ["pg-kerberos", "pg-fileSharing", "pg-smsProvider", "pg-webserver", "pg-produsentregisteret", "pg-kimen", "pg-mattilsynet"]
        },
        {
            "serverGroupName": "sg-t-Dedge-web",
            "providerPortGroupNames": ["pg-fileSharing", "pg-webserver"],
            "consumerPortGroupNames": ["pg-kerberos", "pg-fileSharing", "pg-produsentregisteret"]
        },
        {
            "serverGroupName": "sg-t-Dedge-soa",
            "providerPortGroupNames": ["pg-soa","pg-bulk","pg-fileSharing"],
            "consumerPortGroupNames": ["pg-kerberos", "pg-fileSharing"]
        },
        {
            "serverGroupName": "sg-p-Dedge-db",
            "providerPortGroupNames": ["pg-db2","pg-fileSharing"],
            "consumerPortGroupNames": ["pg-kerberos", "pg-fileSharing", "pg-smsProvider", "pg-webserver"]
        },
        {
            "serverGroupName": "sg-p-Dedge-app",
            "providerPortGroupNames": ["pg-fileSharing"],
            "consumerPortGroupNames": ["pg-kerberos", "pg-fileSharing", "pg-smsProvider", "pg-webserver", "pg-produsentregisteret", "pg-kimen", "pg-mattilsynet"]
        },
        {
            "serverGroupName": "sg-p-Dedge-web", 
            "providerPortGroupNames": ["pg-db2","pg-fileSharing", "pg-webserver"],
            "consumerPortGroupNames": ["pg-kerberos", "pg-fileSharing", "pg-webserver, "pg-produsentregisteret"]
        },
        {
            "serverGroupName": "sg-p-Dedge-soa",
            "providerPortGroupNames": ["pg-soa","pg-bulk","pg-fileSharing"],
            "consumerPortGroupNames": ["pg-kerberos", "pg-fileSharing"]
        },
        {
            "serverGroupName": "sg-kimen",
            "providerPortGroupNames": ["pg-kimen"],
            "consumerPortGroupNames": ["pg-kerberos", "pg-fileSharing", "pg-smsProvider", "pg-webserver", "pg-produsentregisteret", "pg-kimen", "pg-mattilsynet"]
        },
        {
            "serverGroupName": "sg-mattilsynet",
            "providerPortGroupNames": ["pg-mattilsynet"],
            "consumerPortGroupNames": ["pg-kerberos", "pg-fileSharing", "pg-smsProvider", "pg-webserver", "pg-produsentregisteret", "pg-kimen", "pg-mattilsynet"]
        }
    ]
}


Standard Kerberos Ports
Port 88 (TCP/UDP) - This is the main port used for Kerberos authentication traffic between clients and the KDC (Key Distribution Center)
Port 749 (TCP) - Used for administrative access to the Kerberos database (kadmin)
Port 464 (TCP/UDP) - Used for password changes (kpasswd)

Db2 ports
Port 3700-3720, 50000 (TCP) - DB2

SMB ports
Port 445 (TCP) - SMB

NetBIOS ports
Port 139 (TCP) - NetBIOS

SOA ports
Port 9003 (TCP) - SOA
Port 86 (TCP) - SOAWeb

Bulk ports
Port 80 (TCP) - Bulk

Webserver ports
Port 8080 (TCP) - Webserver


Produsentregisteret ports
Port 21 (FTP) - FTP Addresse: ftp.prodreg.no

Kimen SQL Server ports
Port 41433 (TCP) - SQL Server Addresse: 79.160.38.90

Mattilsynet SQL Server ports
Port 1433 (TCP) - SQL Server Addresse: 194.19.30.142

Sms Provider
Port 80 (TCP) - Sms Provider Addresse: sms3.pswin.com

webserver 
Port 80 (TCP)
Port 8080-9300 (TCP)
Port 17000-17300 (TCP)









| p-no1fkxprd-db | * | 3700-3720,50000 | TCP | DB2 ports |
| p-no1fkxprd-db | * | 445 | TCP | SMB |
| p-no1fkxprd-db | * | 139 | TCP | NetBIOS |



t-Dedge_to_Produsentregisteret 10.33.103.145,10.33.103.146 21 ftp.prodreg.no
t-Dedge_to_Mattilsynet 10.33.103.145,10.33.103.146 1433 194.19.30.142
t-Dedge_to_Kimen_Såvarelaboratorier 10.33.103.145,10.33.103.146 41433 79.160.38.90

| From Server | To Server | Port or Range | Protocol | Description |
|------------|-----------|------|----------|-------------|
| t-no1fkmdev-db | sfkad04.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| t-no1fkmdev-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| t-no1fkmdev-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| t-no1fkmdev-db | * | 3700-3720,50000 | TCP | DB2 ports |
| t-no1fkmdev-db | * | 445 | TCP | SMB |
| t-no1fkmdev-db | * | 139 | TCP | NetBIOS |
| t-no1inldev-db | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| t-no1inldev-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| t-no1inldev-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| t-no1inldev-db | * | 3700-3720,50000 | TCP | DB2 ports |
| t-no1inldev-db | * | 445 | TCP | SMB |
| t-no1inldev-db | * | 139 | TCP | NetBIOS |
| t-no1inltst-db | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| t-no1inltst-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| t-no1inltst-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| t-no1inltst-db | * | 3700-3720,50000 | TCP | DB2 ports |
| t-no1inltst-db | * | 445 | TCP | SMB |
| t-no1inltst-db | * | 139 | TCP | NetBIOS |
| t-no1fkmtst-db | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| t-no1fkmtst-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| t-no1fkmtst-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| t-no1fkmtst-db | * | 3700-3720,50000 | TCP | DB2 ports |
| t-no1fkmtst-db | * | 445 | TCP | SMB |
| t-no1fkmtst-db | * | 139 | TCP | NetBIOS |
| t-no1fkmvft-db | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| t-no1fkmvft-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| t-no1fkmvft-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| t-no1fkmvft-db | * | 3700-3720,50000 | TCP | DB2 ports |
| t-no1fkmvft-db | * | 445 | TCP | SMB |
| t-no1fkmvft-db | * | 139 | TCP | NetBIOS |
| t-no1fkmvfk-db | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| t-no1fkmvfk-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| t-no1fkmvfk-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| t-no1fkmvfk-db | * | 3700-3720,50000 | TCP | DB2 ports |
| t-no1fkmvfk-db | * | 445 | TCP | SMB |
| t-no1fkmvfk-db | * | 139 | TCP | NetBIOS |
| t-no1fkmsit-db | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| t-no1fkmsit-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| t-no1fkmsit-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| t-no1fkmsit-db | * | 3700-3720,50000 | TCP | DB2 ports |
| t-no1fkmsit-db | * | 445 | TCP | SMB |
| t-no1fkmsit-db | * | 139 | TCP | NetBIOS |
| t-no1fkmmig-db | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| t-no1fkmmig-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| t-no1fkmmig-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| t-no1fkmmig-db | * | 3700-3720,50000 | TCP | DB2 ports |
| t-no1fkmmig-db | * | 445 | TCP | SMB |
| t-no1fkmmig-db | * | 139 | TCP | NetBIOS |
| p-no1fkmprd-db | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| p-no1fkmprd-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| p-no1fkmprd-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| p-no1fkmprd-db | * | 3700-3720,50000 | TCP | DB2 ports |
| p-no1fkmprd-db | * | 445 | TCP | SMB |
| p-no1fkmprd-db | * | 139 | TCP | NetBIOS |
| p-no1hstprd-db | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| p-no1hstprd-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| p-no1hstprd-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| p-no1hstprd-db | * | 3700-3720,50000 | TCP | DB2 ports |
| p-no1hstprd-db | * | 445 | TCP | SMB |
| p-no1hstprd-db | * | 139 | TCP | NetBIOS |
| p-no1inlprd-db | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| p-no1inlprd-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| p-no1inlprd-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| p-no1inlprd-db | * | 3700-3720,50000 | TCP | DB2 ports |
| p-no1inlprd-db | * | 445 | TCP | SMB |
| p-no1inlprd-db | * | 139 | TCP | NetBIOS |
| p-no1fkmrap-db | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| p-no1fkmrap-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| p-no1fkmrap-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| p-no1fkmrap-db | * | 3700-3720,50000 | TCP | DB2 ports |
| p-no1fkmrap-db | * | 445 | TCP | SMB |
| p-no1fkmrap-db | * | 139 | TCP | NetBIOS |
| p-no1fkxprd-db | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| p-no1fkxprd-db | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| p-no1fkxprd-db | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |
| p-no1fkxprd-db | * | 3700-3720,50000 | TCP | DB2 ports |
| p-no1fkxprd-db | * | 445 | TCP | SMB |
| p-no1fkxprd-db | * | 139 | TCP | NetBIOS |
| p-Dedge-vm01 | kdc2.DEDGE.fk.no | 88 | TCP/UDP | Kerberos authentication traffic between clients and KDC |
| p-Dedge-vm01 | kdc2.DEDGE.fk.no | 749 | TCP | Administrative access to Kerberos database (kadmin) |
| p-Dedge-vm01 | kdc2.DEDGE.fk.no | 464 | TCP/UDP | Password changes (kpasswd) |


t-no1inltst-app
t-no1fkmtst-app
t-no1fkmtst-soa
p-no1fkmprd-app
p-no1inlprd-app

dedge-server

t-no1fkmtst-web
p-no1fkmprd-web

t-no1fkmtst-soa
p-no1fkmprd-soa

sfk-erp-03


BESTILLE P-NO1VISPRD-DB

setspn -A db2/p-no1fkxprd-db.DEDGE.fk.no DEDGE\p1_srv_fkx_db01
ktpass -princ db2/p-no1fkxprd-db@DEDGE.FK.NO -mapuser DEDGE\p1_srv_fkx_db01 -crypto AES256-SHA1 -ptype KRB5_NT_PRINCIPAL -pass [PASSORD] -out db2.keytab
 