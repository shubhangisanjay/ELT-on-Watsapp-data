-- Snowflake Stage File Execution Examples and Error Handling
-- This script demonstrates how to use the stage file executor with proper error handling

-- First, ensure the main executor script has been run
-- Then use these examples to execute files from the CICDPIPELINEAUTOMATION stage

-- Example 1: Execute a file from the root directory of the stage
-- This handles the basic case where files are stored directly in the stage root
BEGIN
    DECLARE
        result VARCHAR;
    BEGIN
        -- Execute a file from stage root (e.g., init.sql)
        CALL EXECUTE_STAGE_FILE('', 'init.sql') INTO result;
        SELECT 'Root file execution result: ' || result;
    EXCEPTION
        WHEN OTHER THEN
            SELECT 'Error executing root file: ' || SQLERRM;
    END;
END;

-- Example 2: Execute a file from a specific subfolder
-- This demonstrates proper subfolder path handling
BEGIN
    DECLARE
        result VARCHAR;
    BEGIN
        -- Execute a file from a subfolder (e.g., scripts/setup.sql)
        CALL EXECUTE_STAGE_FILE('scripts', 'setup.sql') INTO result;
        SELECT 'Subfolder file execution result: ' || result;
    EXCEPTION
        WHEN OTHER THEN
            SELECT 'Error executing subfolder file: ' || SQLERRM;
    END;
END;

-- Example 3: Execute a file with nested subfolder structure
-- This shows how to handle deeper directory structures
BEGIN
    DECLARE
        result VARCHAR;
    BEGIN
        -- Execute a file from nested subfolders (e.g., database/migrations/001_create_tables.sql)
        CALL EXECUTE_STAGE_FILE('database/migrations', '001_create_tables.sql') INTO result;
        SELECT 'Nested subfolder execution result: ' || result;
    EXCEPTION
        WHEN OTHER THEN
            SELECT 'Error executing nested subfolder file: ' || SQLERRM;
    END;
END;

-- Example 4: Batch execution with error handling for multiple files
-- This demonstrates how to handle multiple file executions with proper error reporting
CREATE OR REPLACE PROCEDURE EXECUTE_BATCH_WITH_DETAILED_LOGGING(
    file_paths ARRAY
)
RETURNS TABLE (file_path VARCHAR, status VARCHAR, message VARCHAR)
LANGUAGE SQL
AS
$$
DECLARE
    i NUMBER;
    current_path VARCHAR;
    current_result VARCHAR;
    path_parts ARRAY;
    subfolder VARCHAR;
    filename VARCHAR;
    results TABLE(file_path VARCHAR, status VARCHAR, message VARCHAR);
BEGIN
    -- Clear previous results
    results := ARRAY_CONSTRUCT();
    
    -- Process each file path
    FOR i IN 0 TO ARRAY_SIZE(file_paths) - 1 DO
        current_path := GET(file_paths, i);
        
        BEGIN
            -- Parse the path to extract subfolder and filename
            path_parts := SPLIT(current_path, '/');
            
            IF (ARRAY_SIZE(path_parts) = 1) THEN
                -- File is in root directory
                subfolder := '';
                filename := GET(path_parts, 0);
            ELSE
                -- File is in subfolder(s)
                filename := GET(path_parts, ARRAY_SIZE(path_parts) - 1);
                subfolder := '';
                FOR j IN 0 TO ARRAY_SIZE(path_parts) - 2 DO
                    IF (j > 0) THEN
                        subfolder := subfolder || '/';
                    END IF;
                    subfolder := subfolder || GET(path_parts, j);
                END FOR;
            END IF;
            
            -- Execute the file
            CALL EXECUTE_STAGE_FILE(subfolder, filename) INTO current_result;
            
            -- Add success result
            results := ARRAY_APPEND(results, OBJECT_CONSTRUCT(
                'file_path', current_path,
                'status', 'SUCCESS',
                'message', current_result
            ));
            
        EXCEPTION
            WHEN OTHER THEN
                -- Add error result
                results := ARRAY_APPEND(results, OBJECT_CONSTRUCT(
                    'file_path', current_path,
                    'status', 'ERROR',
                    'message', SQLERRM
                ));
        END;
    END FOR;
    
    -- Return results as table
    RETURN TABLE(SELECT 
        value:file_path::VARCHAR as file_path,
        value:status::VARCHAR as status,
        value:message::VARCHAR as message
    FROM TABLE(FLATTEN(results)));
END;
$$;

-- Example 5: Comprehensive error handling with retry mechanism
CREATE OR REPLACE PROCEDURE EXECUTE_WITH_RETRY(
    SUBFOLDER_PATH VARCHAR,
    FILE_NAME VARCHAR,
    MAX_RETRIES NUMBER DEFAULT 3
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    retry_count NUMBER := 0;
    result VARCHAR;
    last_error VARCHAR;
BEGIN
    WHILE (retry_count < MAX_RETRIES) DO
        BEGIN
            CALL EXECUTE_STAGE_FILE(SUBFOLDER_PATH, FILE_NAME) INTO result;
            
            -- If we get here, execution was successful
            INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
            VALUES (CURRENT_TIMESTAMP(), 'RETRY_SUCCESS', 
                    'File executed successfully on retry ' || retry_count || ': ' || FILE_NAME, 
                    'SUCCESS');
            
            RETURN result;
            
        EXCEPTION
            WHEN OTHER THEN
                retry_count := retry_count + 1;
                last_error := SQLERRM;
                
                INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
                VALUES (CURRENT_TIMESTAMP(), 'RETRY_ATTEMPT', 
                        'Retry ' || retry_count || ' failed for file: ' || FILE_NAME || '. Error: ' || last_error, 
                        'WARNING');
                
                -- Wait a bit before retrying (simulated with a simple operation)
                SELECT SYSTEM$SLEEP(1);
        END;
    END WHILE;
    
    -- If we get here, all retries failed
    result := 'All retries failed for file: ' || FILE_NAME || '. Last error: ' || last_error;
    
    INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
    VALUES (CURRENT_TIMESTAMP(), 'RETRY_EXHAUSTED', result, 'ERROR');
    
    RETURN result;
END;
$$;

-- Example usage of the batch execution with detailed logging:
/*
SELECT * FROM TABLE(EXECUTE_BATCH_WITH_DETAILED_LOGGING(
    ARRAY_CONSTRUCT(
        'init.sql',
        'scripts/setup.sql',
        'database/migrations/001_create_tables.sql',
        'database/migrations/002_insert_data.sql'
    )
));
*/

-- Example 6: Validate stage and files before execution
CREATE OR REPLACE PROCEDURE VALIDATE_AND_EXECUTE(
    SUBFOLDER_PATH VARCHAR,
    FILE_NAME VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    validation_result VARCHAR;
    execution_result VARCHAR;
    stage_name VARCHAR := 'CICDPIPELINEAUTOMATION';
    full_path VARCHAR;
BEGIN
    -- First validate that the stage exists and is accessible
    CALL CHECK_STAGE_STATUS() INTO validation_result;
    
    IF (CONTAINS(validation_result, 'Error')) THEN
        RETURN 'Stage validation failed: ' || validation_result;
    END IF;
    
    -- Construct the file path for validation
    IF (SUBFOLDER_PATH IS NULL OR SUBFOLDER_PATH = '') THEN
        full_path := $$@$$ || stage_name || $$/$$ || FILE_NAME;
    ELSE
        full_path := $$@$$ || stage_name || $$/$$ || TRIM(SUBFOLDER_PATH, '/') || $$/$$ || FILE_NAME;
    END IF;
    
    -- Validate file exists
    BEGIN
        EXECUTE IMMEDIATE 'LIST ' || full_path;
        
        INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
        VALUES (CURRENT_TIMESTAMP(), 'FILE_VALIDATION_SUCCESS', 
                'File validated successfully: ' || full_path, 
                'SUCCESS');
                
    EXCEPTION
        WHEN OTHER THEN
            validation_result := 'File validation failed for: ' || full_path || '. Error: ' || SQLERRM;
            
            INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
            VALUES (CURRENT_TIMESTAMP(), 'FILE_VALIDATION_ERROR', validation_result, 'ERROR');
            
            RETURN validation_result;
    END;
    
    -- If validation passed, execute the file
    CALL EXECUTE_STAGE_FILE(SUBFOLDER_PATH, FILE_NAME) INTO execution_result;
    
    RETURN execution_result;
END;
$$;

-- Example 7: Clean up and monitoring queries
-- Query to check recent execution logs
CREATE OR REPLACE VIEW RECENT_EXECUTION_SUMMARY AS
SELECT 
    DATE_TRUNC('hour', timestamp) as execution_hour,
    operation,
    status,
    COUNT(*) as operation_count,
    MIN(timestamp) as first_occurrence,
    MAX(timestamp) as last_occurrence
FROM EXECUTION_LOG 
WHERE timestamp >= DATEADD(day, -1, CURRENT_TIMESTAMP())
GROUP BY DATE_TRUNC('hour', timestamp), operation, status
ORDER BY execution_hour DESC, operation, status;

-- Query to identify problematic files
CREATE OR REPLACE VIEW PROBLEMATIC_FILES AS
SELECT 
    REGEXP_SUBSTR(message, 'file: ([^.]+\\.sql)', 1, 1, 'e', 1) as file_name,
    COUNT(*) as error_count,
    MAX(timestamp) as last_error,
    LISTAGG(DISTINCT REGEXP_SUBSTR(message, 'Error: (.+)', 1, 1, 'e', 1), '; ') as error_messages
FROM EXECUTION_LOG 
WHERE status = 'ERROR' 
  AND operation LIKE '%FILE%'
  AND timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY file_name
HAVING COUNT(*) > 1
ORDER BY error_count DESC;

-- Maintenance procedure to clean old logs
CREATE OR REPLACE PROCEDURE CLEANUP_OLD_LOGS(
    DAYS_TO_KEEP NUMBER DEFAULT 30
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    deleted_count NUMBER;
    cutoff_date TIMESTAMP;
BEGIN
    cutoff_date := DATEADD(day, -DAYS_TO_KEEP, CURRENT_TIMESTAMP());
    
    DELETE FROM EXECUTION_LOG WHERE timestamp < cutoff_date;
    
    deleted_count := ROW_COUNT();
    
    INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
    VALUES (CURRENT_TIMESTAMP(), 'LOG_CLEANUP', 
            'Deleted ' || deleted_count || ' log entries older than ' || cutoff_date, 
            'INFO');
            
    RETURN 'Cleanup completed. Deleted ' || deleted_count || ' entries.';
END;
$$;

-- Final example showing complete workflow
/*
-- 1. Check stage status
CALL CHECK_STAGE_STATUS();

-- 2. Validate and execute a file
CALL VALIDATE_AND_EXECUTE('scripts', 'setup.sql');

-- 3. Execute with retry mechanism
CALL EXECUTE_WITH_RETRY('database/migrations', '001_create_tables.sql', 3);

-- 4. Batch execute multiple files
SELECT * FROM TABLE(EXECUTE_BATCH_WITH_DETAILED_LOGGING(
    ARRAY_CONSTRUCT('init.sql', 'scripts/setup.sql', 'scripts/cleanup.sql')
));

-- 5. Monitor execution results
SELECT * FROM RECENT_EXECUTION_SUMMARY;

-- 6. Check for problematic files
SELECT * FROM PROBLEMATIC_FILES;

-- 7. Clean up old logs (run periodically)
CALL CLEANUP_OLD_LOGS(30);
*/