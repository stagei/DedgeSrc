select rtrim(pkgschema) || '.' || rtrim(pkgname) from syscat.packages where valid = 'N'
quit
