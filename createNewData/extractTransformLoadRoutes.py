# Extract Raw Route Data from Cosmos DB & Write to Azure SQL
# ==========================================================
import json
import pandas as pd

filepath = 'C:\MyApps\dapTbElectricDublinBus\keys.json'
with open(filepath) as json_file:
    key_data = json.load(json_file)
    cosmos_key = key_data['cosmos_key'] 
    sqldb_pwd = key_data['sqldb_pwd'] 

#%%
# Extract Log of Dead TRIPS from Azure SQL DB
# ===========================================

# Create a connection to the Azure SQL database
import pyodbc
 
server = 'tcp:electricbus-temp.database.windows.net'
database = 'electricbus-eastus-prod-temp'
username = 'teamadmin'
password = sqldb_pwd
 
connection_string = 'DRIVER={ODBC Driver 13 for SQL Server};SERVER=' + server + \
    ';DATABASE=' + database+';UID=' + username + ';PWD=' + password
    
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
from bson import ObjectId
uri = "mongodb://electricbus-wood:" + cosmos_key + "@electricbus-wood.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=@electricbus-wood@"
#uri = "mongodb://electric-bus-cosmos-east-us:" + cosmos_key + "@electric-bus-cosmos-east-us.mongo.cosmos.azure.com:10255/?ssl=true&retrywrites=false&replicaSet=globaldb&maxIdleTimeMS=120000&appName=@electric-bus-cosmos-east-us@"
client = MongoClient(uri)

# Create database
#import pprint

# Database details
db = client['bus_routes_nosql']

# Collection for route data
routes = db.routes

# Create a tuple of lists to hold parsed JSON data so that it can be 
# easily passed into a dataframe for easy loading to RDMS table.
dead_trip_unique_id, latitude, longitude, point_order, distance_km, time_hrs, mode = ([], [], [], [], [], [], []) 

for count, object_id in enumerate(dead_trip_log['object_id']):
    print('Processing dead trip {} of {}'.format(count + 1, len(dead_trip_log['object_id'])))
    post_id = ObjectId(object_id)
    #pprint.pprint(routes.find_one({"_id": post_id}))
    route_data = routes.find_one({"_id": post_id})

    # Grab blocks of info from the route data
    route_points = route_data['batchItems'][0]['response']['routes'][0]['legs'][0]['points']
    summary_info = route_data['batchItems'][0]['response']['routes'][0]['summary']
    sections_info = route_data['batchItems'][0]['response']['routes'][0]['sections'][0]

    # Now loop through and append data to the appropriate lists
    print('Parsing points...')
    for point_count, point in enumerate(route_points) :
        dead_trip_unique_id.append(dead_trip_log['dead_trip_unique_id'][count])
        latitude.append(point['latitude'])
        longitude.append(point['longitude'])
        # Point order is important to ensure correct point
        # order after loading data from SQL db
        point_order.append(point_count + 1)
        distance_km.append(summary_info['lengthInMeters'] / 1000)
        time_hrs.append(round(summary_info['travelTimeInSeconds'] / (60*60), 6))
        mode.append(sections_info['travelMode'])

#%%
# Create a dataframe & populate with the list data    
route_df = pd.DataFrame(dead_trip_unique_id, columns = ['dead_trip_unique_id'])
route_df['latitude'] = latitude
route_df['longitude'] = longitude
route_df['point_order'] = point_order
route_df['distance_km'] = distance_km
route_df['time_hrs'] = time_hrs

#%%
# Create code to write a pandas dataframe to SQL table
# Using a similar method to dbWriteTable in R
from sqlalchemy import create_engine
from urllib.parse import quote_plus
import time

quoted = quote_plus(connection_string)
new_con = 'mssql+pyodbc:///?odbc_connect={}'.format(quoted)
engine = create_engine(new_con,  fast_executemany = True)

table_name = 'dead_leg_shapes'
df = route_df

s = time.time()
df.to_sql(table_name, engine, if_exists = 'replace', chunksize = 10000, index = False)
print('Time taken: ' + str(round(time.time() - s, 1)) + 's')
