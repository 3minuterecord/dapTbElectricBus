import subprocess
import os
import pyodbc
import importlib.util

# ARGUMENTS
# =========
# First define arguments to be passed to the other scripts
root_folder = ['C:/MyApps'] # Only change if youclone he repo to a different location
n = ['30'] # The number of routes to process, select 276 for all routes (for Dublin 6th April) 
# but this could take several hrs to run. 
env = ['test'] # 'test' or 'prod' - Determines which SQL DB to interact with

# Define the pipeline directory location
folder_string = "/dapTbElectricDublinBus/_pipeline"
path = root_folder[0] + folder_string

# Load common function file
spec = importlib.util.spec_from_file_location('functions', path + '/functions.py')
functs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(functs)
    
# Load Access Keys
# ================
# File path Open secret key file stored local
access_keys = functs.load_keys(path + '/keys.json')

# Create a connection to the Azure SQL database
# =============================================
conn_names = functs.load_connection_names(path + '\connection_names.json')
server = conn_names.sql_server
database = conn_names.sql_database + env[0]
username = conn_names.sql_user
connection_string = 'DRIVER={ODBC Driver 13 for SQL Server};SERVER=' + server + ';DATABASE=' + database +';UID=' + username + ';PWD=' + access_keys.sqldb_pwd
    
# Connect to the database    
conn = pyodbc.connect(connection_string, autocommit = True)

# Specify Directories
# ===================
pipeline_dir = path + '/'
rscript_command ='C:/Program Files/R/R-4.0.2/bin/Rscript'

try:
    os.chdir(pipeline_dir)    
# Catch invalid path    
except WindowsError as e:
    print("Error:" + str(e))
# Catch file not found error    
except OSError as e:    
    print("Error:" + str(e))
else :    
    
    # STEP 1 - INGEST RAW GTFS DATA & SAVE TO AZURE SQL DB
    # ====================================================
    # Build & run subprocess command
    # WARNING --- Saving the data to the DB takes sevral hours.
    print('Step 1: Downloading & saving raw GTFS data to SQL DB')
    script ='ingestGtfs.R'
    cmd = [rscript_command, pipeline_dir + script] + root_folder + n + env # Args
    subprocess.check_output(cmd, universal_newlines = True)
    
    # Create some indexes to help speed up later wrangling read times
    functs.createIndex(col = 'trip_id', table = 'trips', connection = conn, curs = conn.cursor())
    functs.createIndex(col = 'route_id', table = 'trips', connection = conn,  curs = conn.cursor())
    functs.createIndex(col = 'route_id', table = 'bus_routes', connection = conn,  curs = conn.cursor())
    functs.createIndex(col = 'shape_id', table = 'shapes', connection = conn,  curs = conn.cursor())
    functs.createIndex(col = 'trip_id', table = 'stop_times', connection = conn,  curs = conn.cursor())
    functs.createIndex(col = 'stop_id', table = 'stops', connection = conn,  curs = conn.cursor())
        
    
    # STEP 2 - CREATE BLOCKS, DEAD TRIP & DEAD LEG INFO
    # =================================================
    # Build & run subprocess command
    # WARNING --- This processing script takes several hours to run (if n not specificed).
    print('Step 2: Create blocks & identify dead trips & legs')
    script ='createBlockInfo.R'
    cmd = [rscript_command, pipeline_dir + script] + root_folder + n + env # Args
    subprocess.check_output(cmd, universal_newlines = True)
        
    print('Creating indexes as part of Step 2...')
    # Create some indexes to help speed up later wrangling read times    
    functs.createIndex(col = 'route_id', table = 'stop_analysis', connection = conn,  curs = conn.cursor())
    functs.createIndex(col = 'service_id', table = 'stop_analysis', connection = conn,  curs = conn.cursor())
    functs.createIndex(col = 'quasi_block', table = 'stop_analysis', connection = conn,  curs = conn.cursor())
    
    # STEP 3 - GET RAW ROUTE INFO FOR DEAD LEGS & DEAD TRIPS
    # ======================================================
    import ingestNonGtfsRoutes
    
    def service_func_ingr():
        print('Step 3: Ingest non-GTFS route data & save to Cosmos DB')
    
    if __name__ == '__main__':
        # if this scipt is executed as script, run:
        service_func_ingr()
        ingestNonGtfsRoutes.run_all_ingr(
            keys = access_keys, 
            conn_string = connection_string, 
            connection = conn)
    
    # STEP 4 - EXTRACT RAW ROUTE DATA & TRANSFORM
    # ======================================================
    import extractTransformLoadRoutes
    
    def service_func_etlr():
        print('Step 4: Extract & transfrom non-GTFS data, save to SQL DB')
    
    if __name__ == '__main__':
        # if this scipt is executed as script, run:
        service_func_etlr()
        extractTransformLoadRoutes.run_all_etlr(
            keys = access_keys, 
            conn_string = connection_string,
            connection = conn)  
    
    print('Creating indexes as part of Step 4...')
    # Create some indexes to help speed up later wrangling read times 
    functs.createIndex(col = 'dead_trip_unique_id', table = 'dead_trip_shapes', connection = conn,  curs = conn.cursor())
    functs.createIndex(col = 'dead_trip_unique_id', table = 'dead_leg_shapes', connection = conn,  curs = conn.cursor())
    
    # STEP 5 - CREATE NETWORK SUMMARY INFO
    # ====================================
    # Build & run subprocess command
    # WARNING --- This processing script takes sevral hours to run (if n not specificed).
    print('Step 5: Create network summary & save to SQL DB')
    script ='createBlockSummary.R'
    cmd = [rscript_command, pipeline_dir + script] + root_folder + n + env # Args
    subprocess.check_output(cmd, universal_newlines = True)    
    
    print('Creating indexes as part of Step 5...')
    # Create some indexes to help speed up app read times
    functs.createIndex(col = 'route_id', table = 'distances', connection = conn,  curs = conn.cursor())
    functs.createIndex(col = 'service_id', table = 'distances', connection = conn,  curs = conn.cursor())
    functs.createIndex(col = 'quasi_block', table = 'distances', connection = conn,  curs = conn.cursor())

    # STEP 6 - COLLECT ELEVATION DATA
    # ====================================
    # Collect all elevations for each coordinate in the stops schema
    # Upload collected elevations to the stopEelevations schema
    import CollectStopElevations
    CollectStopElevations.collectStopElevations()
    
finally :
    # return to root directory
    os.chdir(root_folder[0] + '\dapTbElectricDublinBus')







