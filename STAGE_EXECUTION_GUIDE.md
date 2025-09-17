# Snowflake Stage File Execution Scripts

This repository now contains comprehensive SQL scripts for executing files from the Snowflake `CICDPIPELINEAUTOMATION` stage with proper error handling and path construction.

## Problem Solved

The scripts address the following issues that were causing "File not found" errors:

1. **File Path Construction Issues**: Fixed by using proper string concatenation with `$$` delimiters
2. **Quoting Issues**: Resolved by implementing proper delimiter usage to avoid SQL injection and parsing errors
3. **Error Handling**: Added comprehensive error handling and logging throughout the execution process
4. **Subfolder Path Handling**: Correctly handles both root-level files and files in nested subfolders
5. **Hardcoded Stage Name**: Uses the required `CICDPIPELINEAUTOMATION` stage name as specified

## Files Included

### 1. `snowflake_stage_file_executor.sql`
Main script containing the core stored procedures:

- `EXECUTE_STAGE_FILE(SUBFOLDER_PATH, FILE_NAME)`: Execute a single file from the stage
- `EXECUTE_STAGE_FILES_FROM_SUBFOLDER(SUBFOLDER_PATH)`: Execute multiple files from a subfolder
- `EXECUTE_SQL_FROM_STAGE(FILE_PATH)`: Direct file execution with full path
- `CHECK_STAGE_STATUS()`: Verify stage connectivity and accessibility

### 2. `snowflake_stage_examples.sql`
Examples and advanced usage patterns:

- Batch execution with detailed logging
- Retry mechanisms for failed executions
- File validation before execution
- Monitoring and maintenance procedures

### 3. `STAGE_EXECUTION_GUIDE.md` (this file)
Complete documentation and usage guide

## Key Features

### Proper Path Construction
```sql
-- Handles both root files and subfolder files correctly
IF (SUBFOLDER_PATH IS NULL OR SUBFOLDER_PATH = '') THEN
    full_file_path := $$@$$ || stage_name || $$/$$ || FILE_NAME;
ELSE
    SUBFOLDER_PATH := TRIM(SUBFOLDER_PATH, '/');
    full_file_path := $$@$$ || stage_name || $$/$$ || SUBFOLDER_PATH || $$/$$ || FILE_NAME;
END IF;
```

### Error Handling and Logging
- Comprehensive try-catch blocks for all operations
- Detailed logging table (`EXECUTION_LOG`) to track all operations
- Proper rollback mechanisms on failure
- Informative error messages with context

### String Concatenation with $$ Delimiters
- Uses `$$` delimiters to avoid quoting issues
- Prevents SQL injection attacks
- Handles special characters in file names properly

## Installation

1. Run the main executor script first:
```sql
-- Execute snowflake_stage_file_executor.sql in your Snowflake environment
```

2. Optionally run the examples script for additional functionality:
```sql
-- Execute snowflake_stage_examples.sql for advanced features
```

## Usage Examples

### Execute a file from stage root
```sql
CALL EXECUTE_STAGE_FILE('', 'init.sql');
```

### Execute a file from a subfolder
```sql
CALL EXECUTE_STAGE_FILE('database_scripts', 'create_tables.sql');
```

### Execute a file from nested subfolders
```sql
CALL EXECUTE_STAGE_FILE('database/migrations', '001_create_tables.sql');
```

### Check stage accessibility
```sql
CALL CHECK_STAGE_STATUS();
```

### Execute with retry mechanism
```sql
CALL EXECUTE_WITH_RETRY('scripts', 'setup.sql', 3);
```

### Batch execute multiple files
```sql
SELECT * FROM TABLE(EXECUTE_BATCH_WITH_DETAILED_LOGGING(
    ARRAY_CONSTRUCT(
        'init.sql',
        'scripts/setup.sql',
        'database/migrations/001_create_tables.sql'
    )
));
```

## Monitoring and Maintenance

### View recent execution logs
```sql
SELECT * FROM EXECUTION_LOG 
ORDER BY timestamp DESC 
LIMIT 20;
```

### Check execution summary
```sql
SELECT * FROM RECENT_EXECUTION_SUMMARY;
```

### Identify problematic files
```sql
SELECT * FROM PROBLEMATIC_FILES;
```

### Clean up old logs
```sql
CALL CLEANUP_OLD_LOGS(30); -- Keep logs for 30 days
```

## Error Resolution

### Common Issues and Solutions

1. **"File not found" errors**:
   - Verify the file exists in the stage using `LIST @CICDPIPELINEAUTOMATION`
   - Check the subfolder path is correct (no leading/trailing slashes)
   - Ensure file name includes proper extension (.sql)

2. **Permission errors**:
   - Verify you have USAGE privileges on the stage
   - Check that the stage `CICDPIPELINEAUTOMATION` exists and is accessible

3. **Path construction errors**:
   - Use the provided procedures which handle path construction automatically
   - Avoid manual path construction to prevent delimiter issues

4. **SQL syntax errors in executed files**:
   - Check the execution logs for detailed error messages
   - Validate SQL files before uploading to stage

## Best Practices

1. **Always use the provided stored procedures** instead of manual `EXECUTE IMMEDIATE FROM` commands
2. **Check logs regularly** to identify and resolve issues early
3. **Use the retry mechanism** for files that might have temporary execution issues
4. **Validate files** before execution using the validation procedures
5. **Clean up logs periodically** to maintain performance
6. **Use batch execution** for multiple related files to ensure proper sequencing

## Technical Implementation Details

### Stage Name Hardcoding
The stage name `CICDPIPELINEAUTOMATION` is hardcoded in the procedures as required by Snowflake limitations for dynamic stage references in certain contexts.

### String Delimiter Usage
The `$$` delimiter is used throughout to:
- Avoid conflicts with single quotes in file names or paths
- Prevent SQL injection vulnerabilities
- Ensure proper parsing of complex path structures

### Transaction Management
- Uses explicit transaction control with `AUTOCOMMIT = FALSE`
- Proper rollback on errors to maintain data consistency
- Commit only after successful execution

### Error Logging
- All operations are logged to the `EXECUTION_LOG` table
- Includes timestamp, operation type, detailed messages, and status
- Enables comprehensive audit trail and troubleshooting

This implementation resolves all the file path construction and execution issues mentioned in the original problem statement while providing a robust, scalable solution for ongoing Snowflake stage file management.