# Pagination and Preferences Features

## Overview
The application now includes **pagination controls** and a **preferences system** to handle large result sets efficiently and prevent memory/performance issues.

## Key Features Implemented

### 1. Automatic Row Limiting (Pagination)
- **Default Limit**: 1000 rows per page
- Queries automatically add `OFFSET x ROWS FETCH NEXT y ROWS ONLY` clause to DB2 SQL
- **Navigation**: Use "◀ Previous" and "Next ▶" buttons in the status bar to navigate pages
- **Page Indicator**: Shows current page number (e.g., "Page 3")
- Row count displays: "1000 rows (Page 1)"

### 2. Preferences System (`preferences.json`)
The application creates a `preferences.json` file in the application directory that you can manually edit to customize behavior.

#### Preference Options:

```json
{
  "maxRowsPerQuery": 1000,              // Max rows per page (default: 1000)
  "defaultTheme": "Dark",                // "Dark" or "Light"
  "editorFontFamily": "Consolas",        // SQL editor font
  "editorFontSize": 14,                  // SQL editor font size
  "autoFormatOnExecute": false,          // Auto-format SQL before executing
  "queryTimeoutSeconds": 30,             // Query timeout (seconds)
  "handleDecimalErrorsGracefully": true  // Handle DB2Decimal format errors
}
```

#### To Change Max Rows Per Query:
1. Close the application
2. Open `preferences.json` in the application directory (e.g., `bin\Debug\net10.0-windows\preferences.json`)
3. Change `"maxRowsPerQuery"` to your desired value (e.g., 500, 5000, etc.)
4. Save the file
5. Restart the application

**Example** - Limit to 500 rows per page:
```json
{
  "maxRowsPerQuery": 500,
  ...
}
```

### 3. DB2Decimal Format Error Handling
The application now gracefully handles the `System.FormatException` error you encountered:
```
The input string '2<00000.00' was not in a correct format
```

**How it works:**
- When a `FormatException` occurs with DB2Decimal values, the system automatically:
  1. Logs a warning about the format error
  2. Retries the query using a `DataReader` with manual value conversion
  3. Converts all values to strings to avoid format errors
  4. Displays "[ERROR: ...]" for any cells that still fail to read

This is controlled by the `handleDecimalErrorsGracefully` preference (default: `true`).

### 4. Debug Logging
All pagination and error handling operations are logged at DEBUG level:
- Page navigation events
- SQL modifications (adding OFFSET/FETCH clauses)
- Decimal format error detection and fallback
- DataReader value conversions

Check `logs\db2editor-{date}.log` for detailed information.

## Usage Examples

### Example 1: Query Large Table
```sql
SELECT * FROM MY_LARGE_TABLE;
```
**Result:**
- Automatically loads first 1000 rows
- "Next ▶" button enabled if more rows exist
- Click "Next ▶" to load rows 1001-2000
- Click "◀ Previous" to go back

### Example 2: Custom Pagination in SQL
If your query already has pagination:
```sql
SELECT * FROM MY_TABLE
OFFSET 5000 ROWS FETCH NEXT 100 ROWS ONLY;
```
The application detects existing pagination and **does NOT modify** the query.

### Example 3: Handling Format Errors
If you encounter the DB2Decimal error with malformed data:
1. The application automatically retries using DataReader
2. Values are displayed as strings
3. Malformed values show as "[ERROR: ...]"
4. Query completes successfully without crashing

## Files Modified/Created

### New Files:
- `Models/UserPreferences.cs` - Preferences model
- `Services/PreferencesService.cs` - Preferences management
- `preferences.json` - User-editable preferences file
- `PAGINATION_AND_PREFERENCES_README.md` - This file

### Modified Files:
- `Data/DB2ConnectionManager.cs` - Added pagination and error handling
- `Controls/ConnectionTabControl.xaml` - Added pagination UI controls
- `Controls/ConnectionTabControl.xaml.cs` - Added pagination logic

## Technical Details

### DB2 Pagination Syntax
The application uses DB2's standard pagination syntax:
```sql
SELECT * FROM TABLE_NAME
OFFSET 1000 ROWS FETCH NEXT 1000 ROWS ONLY
```

### Error Handling Flow
1. Execute query with `DB2DataAdapter`
2. If `FormatException` occurs → catch it
3. Re-execute with `DB2DataReader`
4. Manually convert each cell value to string
5. Handle individual cell errors gracefully
6. Return complete dataset

## Performance Notes

- **Memory**: Limiting to 1000 rows prevents loading millions of rows into memory
- **Network**: Reduces network transfer for large result sets
- **UI Responsiveness**: DataGrid renders faster with fewer rows
- **Query Speed**: DB2 `FETCH NEXT` is optimized for pagination

## Troubleshooting

### Pagination Buttons Not Working?
- Ensure you've executed a query first
- "Previous" is disabled on Page 1
- "Next" is disabled when fewer rows than max are returned

### Preferences Not Loading?
- Check `logs\db2editor-{date}.log` for errors
- Verify `preferences.json` is valid JSON
- File is created automatically on first run if missing

### Still Getting Decimal Errors?
- Check that `handleDecimalErrorsGracefully` is `true` in preferences
- Review logs for DataReader fallback messages
- Report specific error details if problem persists

## Future Enhancements
Potential future features:
- Jump to specific page number
- Display total row count
- Export all pages (not just current page)
- Preferences UI dialog (instead of manual JSON edit)
- Per-connection preferences

## Support
For issues or questions:
- Check the application logs in `logs\` directory
- Enable DEBUG-level logging in `nlog.config`
- Review `DB2_Application_Development_Guide.md` for more details

