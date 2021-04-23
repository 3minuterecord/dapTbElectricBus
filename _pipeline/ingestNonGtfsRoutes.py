# Azure Maps API Interaction
# ========================== 
# Create an ingestion script for pulling route info from Azure maps
# based on provided lat and long coordinates for the start and end
# journey points.

# This is required for finding 'dead head' route info, e.g., 
# travel by the bus from the depot to the block starting point, 
# and back again in the evening.
# Also applicable to certain blocks where the buss will nee to travel between
# the end and starting point of two successive trips.

import pandas as pd
import pyodbc
from pymongo import MongoClient
import importlib.util

def run_all_ingr () :

    # Load common function file
    spec = importlib.util.spec_from_file_location("functions", "C:/MyApps/dapTbElectricDublinBus/common/functions.py")
    functs = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(functs)
    
    
    #%%
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
    connection_string = 'DRIVER={ODBC Driver 13 for SQL Server};SERVER=' + server + \
        ';DATABASE=' + database +';UID=' + username + ';PWD=' + access_keys.sqldb_pwd
    
    # Connect to the database    
    conn = pyodbc.connect(connection_string)
    
    # Create Azure Cosmos DB for MongoDB API Connection
    # =================================================
    # Azure Cosmos DB service implements wire protocols for common NoSQL APIs including Cassandra, MongoDB. 
    # This allows you to use your familiar NoSQL client drivers and tools to interact with your Cosmos database.
    uri = "mongodb://electric-bus-cosmos-east-us:" + access_keys.cosmos_key + "@electric-bus-cosmos-east-us.mongo.cosmos.azure.com:10255/?ssl=true&retrywrites=false&replicaSet=globaldb&maxIdleTimeMS=120000&appName=@electric-bus-cosmos-east-us@"
    client = MongoClient(uri)
    # Create database
    db = client['bus_routes_nosql']
    # Create collection for route data
    routes = db.routes
    
    # Define Azure Maps API URL
    # ==============================================
    # No need to check traffic for this simple use-case
    # Use batch mode so that the same query can be used for multiple route requests
    api_version = '1.0'
    check_traffic = '0'
    route_api_url = 'https://atlas.microsoft.com/route/directions/batch/sync/json?api-version=' + api_version \
                            + '&subscription-key=' + access_keys.maps_sub_key + '&traffic=' + check_traffic
    
    #%%
    # Focus on Dead TRIPs
    # ===================
    # Get the stop analysis data from the database and drop duplicates so that 
    # We only have unique dead trips
    query = 'SELECT * FROM stop_analysis'   
    dead_trips = pd.read_sql_query(query, conn)
    dead_trips_unique = dead_trips[['dead_trip_unique_id', 'trip_first_stop_id', 'trip_last_stop_id']].drop_duplicates()
    # Reset the index after dropping rows
    dead_trips_unique = dead_trips_unique.reset_index()
    del query
    
    #%%
    # Now get Dead TRIP route data & create table of log info
    dead_trip_log_df = functs.getRouteInfo(
        trip_vec = dead_trips_unique['dead_trip_unique_id'], 
        start_vec = dead_trips_unique['trip_first_stop_id'], 
        end_vec = dead_trips_unique['trip_last_stop_id'], 
        api_url = route_api_url, 
        dead_loc = 'trip',
        collection = routes,
        connection = conn,
        mode = 'stops'
        )
    
    #%%
    # Focus on Dead LEGs
    # ===================
    # First get log info from Azure SQL db
    query = 'SELECT * FROM dead_leg_summary'   
    dead_legs = pd.read_sql_query(query, conn)
    dead_legs_unique = dead_legs[['dead_leg_unique_id', 'start', 'end']].drop_duplicates()
    # Reset the index after dropping rows
    dead_legs_unique = dead_legs_unique.reset_index()
    del query
    
    #%%
    # Now get the dead LEG route data & create table of log info
    dead_leg_log_df = functs.getRouteInfo(
        trip_vec = dead_legs_unique['dead_leg_unique_id'], 
        start_vec = dead_legs_unique['start'], 
        end_vec = dead_legs_unique['end'], 
        api_url = route_api_url, 
        dead_loc = 'leg',
        collection = routes,
        connection = conn,
        mode = 'legs'
        )
    
    #%%
    # Review Log Tables
    # =================
    # Review the log data that has been converted to data frame
    pd.set_option('display.max_columns', 500)
    pd.set_option('expand_frame_repr', False)
    print(dead_trip_log_df)
    print(dead_leg_log_df)
    
    #%%
    # Save Logs to Azure SQL db
    # =========================
    # Logs relate object id to specific dead trips / legs
    # Create code to write a pandas dataframe to SQL table
    # Using a similar method to dbWriteTable in R
    from sqlalchemy import create_engine
    from urllib.parse import quote_plus
    
    quoted = quote_plus(connection_string)
    new_con = 'mssql+pyodbc:///?odbc_connect={}'.format(quoted)
    engine = create_engine(new_con,  fast_executemany = True)
    
    # Save Dead TRIP log to Azure SQL db
    functs.saveLogInfo(
        table = 'dead_trip_log', 
        df = dead_trip_log_df,
        eng = engine
        )
    
    # Save Dead TRIP log to Azure SQL db
    functs.saveLogInfo(
        table = 'dead_leg_log', 
        df = dead_leg_log_df,
        eng = engine
        )

if __name__ == '__main__':
    # when executed as script, run this function
    run_all_ingr()        