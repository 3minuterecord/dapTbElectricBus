import subprocess
import os
import pyodbc
import importlib.util

# Load common function file
spec = importlib.util.spec_from_file_location("functions", "C:/MyApps/dapTbElectricDublinBus/common/functions.py")
functs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(functs)
    
# Load Access Keys
# ================
# File path Open secret key file stored local
access_keys = functs.load_keys('C:\MyApps\dapTbElectricDublinBus\keys.json')

# Create a connection to the Azure SQL database
# =============================================
conn_names = functs.load_connection_names('C:\MyApps\dapTbElectricDublinBus\connection_names.json')
server = conn_names.sql_server
database = conn_names.sql_database
username = conn_names.sql_user
connection_string = 'DRIVER={ODBC Driver 13 for SQL Server};SERVER=' + server + ';DATABASE=' + database +';UID=' + username + ';PWD=' + access_keys.sqldb_pwd
    
# Connect to the database    
conn = pyodbc.connect(connection_string, autocommit = True)

# Specify Directories
# ===================
pipeline_dir = 'C:/MyApps/dapTbElectricDublinBus/_pipeline/'
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
    script ='ingestGtfs.R'
    cmd = [rscript_command, pipeline_dir + script]
    subprocess.run(cmd)
    
    # Create some indexes to help speed up later wrangling read times
    functs.createIndex (col = 'trip_id', table = 'trips', curs = conn.cursor())
    functs.createIndex (col = 'route_id', table = 'trips', curs = conn.cursor())
    functs.createIndex (col = 'route_id', table = 'bus_routes', curs = conn.cursor())
    functs.createIndex (col = 'shape_id', table = 'shapes', curs = conn.cursor())
    functs.createIndex (col = 'trip_id', table = 'stop_times', curs = conn.cursor())
    functs.createIndex (col = 'stop_id', table = 'stops', curs = conn.cursor())
        
    
    # STEP 2 - CREATE BLOCKS, DEAD TRIP & DEAD LEG INFO
    # =================================================
    # Build & run subprocess command
    # WARNING --- This processing script takes sevral hours to run.
    script ='createBlockInfo.R'
    cmd = [rscript_command, pipeline_dir + script]
    subprocess.run(cmd)
    
    # Create some indexes to help speed up later wrangling read times
    functs.createIndex (col = 'dead_trip_unique_id', table = 'dead_trip_shapes', curs = conn.cursor())
    functs.createIndex (col = 'dead_trip_unique_id', table = 'dead_leg_shapes', curs = conn.cursor())
    functs.createIndex (col = 'route_id', table = 'stop_analysis', curs = conn.cursor())
    functs.createIndex (col = 'service_id', table = 'stop_analysis', curs = conn.cursor())
    functs.createIndex (col = 'quasi_block', table = 'stop_analysis', curs = conn.cursor())
    
    # STEP 3 - GET RAW ROUTE INFO FOR DEAD LEGS & DEAD TRIPS
    # ======================================================
    import ingestNonGtfsRoutes
    
    def service_func_ingr():
        print('Running ingest non-GTFS route script...')
    
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
        print('Running extract & transfrom non-GTFS script...')
    
    if __name__ == '__main__':
        # if this scipt is executed as script, run:
        service_func_etlr()
        extractTransformLoadRoutes.run_all_etlr(
            keys = access_keys, 
            conn_string = connection_string,
            connection = conn)  
    
    # STEP 5 - CREATE NETWORK SUMMARY INFO
    # ====================================
    # Build & run subprocess command
    # WARNING --- This processing script takes sevral hours to run.
    script ='createBlockSummary.R'
    cmd = [rscript_command, pipeline_dir + script]
    subprocess.run(cmd)
    
    # Create some indexes to help speed up app read times
    functs.createIndex (col = 'dead_trip_unique_id', table = 'distances', curs = conn.cursor())
    functs.createIndex (col = 'dead_service_id', table = 'distances', curs = conn.cursor())
    functs.createIndex (col = 'quasi_block', table = 'distances', curs = conn.cursor())
    
finally :
    # return to root directory
    os.chdir('C:\MyApps\dapTbElectricDublinBus')

