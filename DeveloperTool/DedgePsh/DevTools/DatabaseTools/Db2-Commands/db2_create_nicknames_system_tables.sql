	SELECT
		y.*
	FROM
		 (
		SELECT
			'db2 "CREATE NICKNAME ' || trim(X.SCHEMA) || 'X.' || trim(X.NAME) || ' FOR ¤DB2TE_FED_LINK_DB_NAME¤.' || trim(X.SCHEMA) || '.' || trim(X.NAME) || '"' AS FEDERATED_NICKNAMES
		FROM
			(
			SELECT
				X.TYPE AS TYPE,
				'SYSCAT.TABLES' AS SOURCE,
				X.TABSCHEMA AS SCHEMA,
				X.TABNAME AS NAME,
				CASE
					X."TYPE"
	        WHEN 'A' THEN 'Alias'
					WHEN 'G' THEN 'Created temporary table'
					WHEN 'H' THEN 'Hierarchy table'
					WHEN 'L' THEN 'Detached table'
					WHEN 'N' THEN 'Nickname'
					WHEN 'S' THEN 'Materialized query table'
					WHEN 'T' THEN 'Table (untyped)'
					WHEN 'U' THEN 'Typed table'
					WHEN 'V' THEN 'View (untyped)'
					WHEN 'W' THEN 'Typed view'
					ELSE 'Unknown type'
				END AS SOURCE_TYPE,
				X."DEFINER" AS LAST_CHANGE_BY,
				X.ALTER_TIME AS LAST_CHANGED_DATETIME
			FROM
				SYSCAT.TABLES X
			WHERE
				X.TYPE IN ('V', 'T')
				AND UPPER(X.TABSCHEMA) like '%SYS%' or UPPER(X.TABSCHEMA) like '%IBM%'
	) X ) y
	WHERE
		LOWER(y.FEDERATED_NICKNAMES) NOT LIKE '%dbm.drbi%';
