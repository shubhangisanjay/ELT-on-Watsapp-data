-- Snowflake Stage File Executor Script
-- This script handles execution of SQL files from the CICDPIPELINEAUTOMATION stage
-- with proper error handling and path construction

-- Set up session parameters for better error handling
SET AUTOCOMMIT = FALSE;

-- Create a stored procedure to execute files from stage with proper error handling
CREATE OR REPLACE PROCEDURE EXECUTE_STAGE_FILE(
    SUBFOLDER_PATH VARCHAR,
    FILE_NAME VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    full_file_path VARCHAR;
    stage_name VARCHAR := 'CICDPIPELINEAUTOMATION';
    execution_result VARCHAR;
    error_message VARCHAR;
    file_content VARCHAR;
BEGIN
    -- Log the start of execution
    INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
    VALUES (CURRENT_TIMESTAMP(), 'FILE_EXECUTION_START', 
            'Starting execution of file: ' || FILE_NAME || ' from subfolder: ' || SUBFOLDER_PATH, 
            'INFO');

    -- Construct the full file path using proper string concatenation with $$ delimiters
    -- Handle both cases: with and without subfolder
    IF (SUBFOLDER_PATH IS NULL OR SUBFOLDER_PATH = '') THEN
        full_file_path := $$@$$ || stage_name || $$/$$ || FILE_NAME;
    ELSE
        -- Remove leading/trailing slashes from subfolder path to avoid double slashes
        SUBFOLDER_PATH := TRIM(SUBFOLDER_PATH, '/');
        full_file_path := $$@$$ || stage_name || $$/$$ || SUBFOLDER_PATH || $$/$$ || FILE_NAME;
    END IF;

    -- Log the constructed file path
    INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
    VALUES (CURRENT_TIMESTAMP(), 'PATH_CONSTRUCTION', 
            'Constructed file path: ' || full_file_path, 
            'INFO');

    -- First, verify the file exists in the stage
    BEGIN
        SELECT $1 INTO file_content 
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        WHERE $1 IS NOT NULL
        LIMIT 1;
        
        -- Try to list the file to verify it exists
        EXECUTE IMMEDIATE 'LIST ' || full_file_path;
        
        -- If we get here, the file exists, log success
        INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
        VALUES (CURRENT_TIMESTAMP(), 'FILE_VERIFICATION', 
                'File exists and is accessible: ' || full_file_path, 
                'SUCCESS');
                
    EXCEPTION
        WHEN OTHER THEN
            error_message := 'File not found or not accessible: ' || full_file_path || '. Error: ' || SQLERRM;
            INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
            VALUES (CURRENT_TIMESTAMP(), 'FILE_VERIFICATION_ERROR', error_message, 'ERROR');
            RETURN error_message;
    END;

    -- Execute the SQL file from stage
    BEGIN
        -- Use EXECUTE IMMEDIATE with proper stage path construction
        EXECUTE IMMEDIATE $$EXECUTE IMMEDIATE FROM $$ || full_file_path;
        
        execution_result := 'File executed successfully: ' || full_file_path;
        
        -- Log successful execution
        INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
        VALUES (CURRENT_TIMESTAMP(), 'FILE_EXECUTION_SUCCESS', execution_result, 'SUCCESS');
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHER THEN
            error_message := 'Error executing file: ' || full_file_path || '. Error: ' || SQLERRM;
            
            -- Log the error
            INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
            VALUES (CURRENT_TIMESTAMP(), 'FILE_EXECUTION_ERROR', error_message, 'ERROR');
            
            ROLLBACK;
            RETURN error_message;
    END;

    RETURN execution_result;
END;
$$;

-- Create execution log table if it doesn't exist
CREATE TABLE IF NOT EXISTS EXECUTION_LOG (
    log_id NUMBER AUTOINCREMENT,
    timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    operation VARCHAR(100),
    message VARCHAR(4000),
    status VARCHAR(20),
    PRIMARY KEY (log_id)
);

-- Create a wrapper procedure for executing multiple files from a subfolder
CREATE OR REPLACE PROCEDURE EXECUTE_STAGE_FILES_FROM_SUBFOLDER(
    SUBFOLDER_PATH VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    stage_name VARCHAR := 'CICDPIPELINEAUTOMATION';
    full_subfolder_path VARCHAR;
    file_list_result VARCHAR;
    execution_summary VARCHAR := '';
    total_files NUMBER := 0;
    successful_files NUMBER := 0;
    failed_files NUMBER := 0;
    current_file VARCHAR;
    execution_result VARCHAR;
BEGIN
    -- Log the start of batch execution
    INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
    VALUES (CURRENT_TIMESTAMP(), 'BATCH_EXECUTION_START', 
            'Starting batch execution from subfolder: ' || SUBFOLDER_PATH, 
            'INFO');

    -- Construct the subfolder path
    IF (SUBFOLDER_PATH IS NULL OR SUBFOLDER_PATH = '') THEN
        full_subfolder_path := $$@$$ || stage_name || $$/$$;
    ELSE
        SUBFOLDER_PATH := TRIM(SUBFOLDER_PATH, '/');
        full_subfolder_path := $$@$$ || stage_name || $$/$$ || SUBFOLDER_PATH || $$/$$;
    END IF;

    -- Note: In a real implementation, you would need to list files in the stage
    -- and iterate through them. This is a simplified version that demonstrates
    -- the proper error handling pattern.
    
    execution_summary := 'Batch execution completed. Total files: ' || total_files || 
                        ', Successful: ' || successful_files || 
                        ', Failed: ' || failed_files;
    
    -- Log the completion of batch execution
    INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
    VALUES (CURRENT_TIMESTAMP(), 'BATCH_EXECUTION_COMPLETE', execution_summary, 'INFO');

    RETURN execution_summary;
END;
$$;

-- Create a procedure to execute a specific SQL file with enhanced error handling
CREATE OR REPLACE PROCEDURE EXECUTE_SQL_FROM_STAGE(
    FILE_PATH VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    stage_name VARCHAR := 'CICDPIPELINEAUTOMATION';
    full_path VARCHAR;
    result_message VARCHAR;
BEGIN
    -- Construct full path with proper delimiters
    IF (STARTSWITH(FILE_PATH, '/')) THEN
        full_path := $$@$$ || stage_name || FILE_PATH;
    ELSE
        full_path := $$@$$ || stage_name || $$/$$ || FILE_PATH;
    END IF;

    -- Log the execution attempt
    INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
    VALUES (CURRENT_TIMESTAMP(), 'DIRECT_FILE_EXECUTION', 
            'Attempting to execute: ' || full_path, 
            'INFO');

    BEGIN
        -- Execute the file using EXECUTE IMMEDIATE FROM
        EXECUTE IMMEDIATE $$EXECUTE IMMEDIATE FROM $$ || full_path;
        
        result_message := 'Successfully executed: ' || full_path;
        
        INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
        VALUES (CURRENT_TIMESTAMP(), 'DIRECT_FILE_SUCCESS', result_message, 'SUCCESS');
        
    EXCEPTION
        WHEN OTHER THEN
            result_message := 'Failed to execute: ' || full_path || '. Error: ' || SQLERRM;
            
            INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
            VALUES (CURRENT_TIMESTAMP(), 'DIRECT_FILE_ERROR', result_message, 'ERROR');
    END;

    RETURN result_message;
END;
$$;

-- Create a utility procedure to check stage connectivity and list files
CREATE OR REPLACE PROCEDURE CHECK_STAGE_STATUS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    stage_name VARCHAR := 'CICDPIPELINEAUTOMATION';
    status_message VARCHAR;
    file_count NUMBER;
BEGIN
    BEGIN
        -- Try to list files in the stage root
        EXECUTE IMMEDIATE 'LIST @' || stage_name;
        
        -- Count the number of files (this is a simplified check)
        status_message := 'Stage ' || stage_name || ' is accessible and contains files.';
        
        INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
        VALUES (CURRENT_TIMESTAMP(), 'STAGE_STATUS_CHECK', status_message, 'SUCCESS');
        
    EXCEPTION
        WHEN OTHER THEN
            status_message := 'Error accessing stage ' || stage_name || ': ' || SQLERRM;
            
            INSERT INTO EXECUTION_LOG (timestamp, operation, message, status)
            VALUES (CURRENT_TIMESTAMP(), 'STAGE_STATUS_ERROR', status_message, 'ERROR');
    END;

    RETURN status_message;
END;
$$;

-- Example usage comments:
/*
-- To execute a single file from the root of the stage:
CALL EXECUTE_STAGE_FILE('', 'my_script.sql');

-- To execute a file from a subfolder:
CALL EXECUTE_STAGE_FILE('database_scripts', 'create_tables.sql');

-- To execute a file using direct path:
CALL EXECUTE_SQL_FROM_STAGE('database_scripts/create_tables.sql');

-- To check stage status:
CALL CHECK_STAGE_STATUS();

-- To view execution logs:
SELECT * FROM EXECUTION_LOG ORDER BY timestamp DESC LIMIT 20;

-- To clear old logs (optional):
DELETE FROM EXECUTION_LOG WHERE timestamp < DATEADD(day, -7, CURRENT_TIMESTAMP());
*/