# Extract Raw Route Data from Cosmos DB & Write to Azure SQL
# ==========================================================
import pandas as pd
import importlib.util

# Load common function file
spec = importlib.util.spec_from_file_location("functions", "C:/MyApps/dapTbElectricDublinBus/common/functions.py")
functs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(functs)

# Load Access Keys
# ================
# File path Open secret key file stored local
access_keys = functs.load_keys('C:\MyApps\dapTbElectricDublinBus\keys.json')

#%%
# Extract Log of Dead TRIPS from Azure SQL DB
# ===========================================

# Create a connection to the Azure SQL database
import pyodbc
 
conn_names = functs.load_connection_names('C:\MyApps\dapTbElectricDublinBus\connection_names.json')
server = conn_names.sql_server
database = conn_names.sql_database
username = conn_names.sql_user
connection_string = 'DRIVER={ODBC Driver 13 for SQL Server};SERVER=' + server + \
    ';DATABASE=' + database +';UID=' + username + ';PWD=' + access_keys.sqldb_pwd
    
conn = pyodbc.connect(connection_string)

# Extract the dead_trip_log table created from R script analysis of GTFS
query = 'SELECT * FROM dead_trip_log'   
dead_trip_log = pd.read_sql_query(query, conn)
del query

#%%
# Extract Log of Dead LEGS from Azure SQL DB
# ==========================================

# Extract the dead_leg_log table created from R script analysis of GTFS
query = 'SELECT * FROM dead_leg_log'   
dead_leg_log = pd.read_sql_query(query, conn)

#%%    
# Extract Raw Route Data from Azure Cosmos DB for MongoDB API
# ===========================================================
# Azure Cosmos DB service implements wire protocols for common NoSQL APIs 
# including Cassandra, MongoDB. This allows you to use your familiar NoSQL 
# client drivers and tools to interact with your Cosmos database.
from pymongo import MongoClient

uri = "mongodb://electric-bus-cosmos-east-us:" + access_keys.cosmos_key + "@electric-bus-cosmos-east-us.mongo.cosmos.azure.com:10255/?ssl=true&retrywrites=false&replicaSet=globaldb&maxIdleTimeMS=120000&appName=@electric-bus-cosmos-east-us@"
client = MongoClient(uri)

# Create database
#import pprint

# Database details
db = client['bus_routes_nosql']

# Collection for route data
routes = db.routes

#%%
# Get Dead TRIP route data from Cosmos, tabulate it, and save to Azure SQL db
dead_trip_shapes_df = functs.tabulateRouteInfo(
    object_vec = dead_trip_log['object_id'], 
    trip_vec = dead_trip_log['dead_unique_id'],             
    collection = routes    
    )


#%%
# Get Dead LEG route data from Cosmos, tabulate it, and save to Azure SQL db
dead_leg_shapes_df = functs.tabulateRouteInfo(
    object_vec = dead_leg_log['object_id'], 
    trip_vec = dead_leg_log['dead_unique_id'],             
    collection = routes    
    )


#%%
# Create code to write a pandas dataframe to SQL table
# Using a similar method to dbWriteTable in R
from sqlalchemy import create_engine
from urllib.parse import quote_plus

quoted = quote_plus(connection_string)
new_con = 'mssql+pyodbc:///?odbc_connect={}'.format(quoted)
engine = create_engine(new_con,  fast_executemany = True)

functs.saveLogInfo(
    table = 'dead_trip_shapes', 
    df = dead_trip_shapes_df,
    eng = engine
    )

functs.saveLogInfo(
    table = 'dead_leg_shapes', 
    df = dead_leg_shapes_df,
    eng = engine
    )
