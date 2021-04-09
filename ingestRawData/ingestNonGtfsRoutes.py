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
import requests
import json
import pyodbc
from pymongo import MongoClient

# Create a class for access keys, i.e., db passwords, subscription keys, etc.
class keys:
  def __init__(self, maps_sub_key, cosmos_key, sqldb_pwd):
    self.maps_sub_key = maps_sub_key
    self.cosmos_key = cosmos_key
    self.sqldb_pwd = sqldb_pwd
    
# Create a class for trip stop info, i.e., start end end coordinates  
class stop:
  def __init__(self, start_stop_lat, start_stop_lon, end_stop_lat, end_stop_lon):
    self.start_stop_lat = start_stop_lat
    self.start_stop_lon = start_stop_lon
    self.end_stop_lat = end_stop_lat
    self.end_stop_lon = end_stop_lon

# Create a function to load keys file
def load_keys (filepath) :    
    try:
        # Open the file and read the data
        json_file = open(filepath)        
    # Catch file not found error    
    except FileNotFoundError as e:
        print("File not found " + str(e))
    # Catch if file is not readable
    except IOError as e:
        print("Error: File is '" + str(e) + "'.")
    else :
    # Return the imported data if no errors are captured   
        key_data = json.load(json_file)
        keys.maps_sub_key = key_data['subscription_key']
        keys.cosmos_key = key_data['cosmos_key']
        keys.sqldb_pwd = key_data['sqldb_pwd'] 
        return(keys)    
    finally :
     # Close the file   
        json.file.close()

# Create a function for creating stop objects from stop ids
def getStopCoords(start_stop, end_stop, connection) :
    query = "SELECT stop_lat, stop_lon FROM stops WHERE stop_id = '{}'".format(start_stop)   
    start_stop_coords = pd.read_sql_query(query, connection) 
    start_stop_coords = start_stop_coords.values.tolist()[0]
    query = "SELECT stop_lat, stop_lon FROM stops WHERE stop_id = '{}'".format(end_stop)   
    end_stop_coords = pd.read_sql_query(query, connection)
    end_stop_coords = end_stop_coords.values.tolist()[0]
    return(stop(start_stop_coords[0], start_stop_coords[1], end_stop_coords[0], end_stop_coords[1]))  

# Create a function for creating stop objects from stop ids
def getLegCoords(start_stop, end_stop, connection) :    
    query = "SELECT name, lat, lon FROM depots"   
    depots = pd.read_sql_query(query, connection) 
    
    if start_stop[0:3].isdigit() :
        query = "SELECT stop_lat, stop_lon FROM stops WHERE stop_id = '{}'".format(start_stop)   
        start_stop_coords = pd.read_sql_query(query, connection) 
        start_stop_coords = start_stop_coords.values.tolist()[0]
    
    else :
        check_depot_name = depots['name'] == start_stop
        if sum(check_depot_name) != 0 :
            start_stop_coords = []
            start_stop_coords.append(depots['lat'][check_depot_name].values.tolist()[0])
            start_stop_coords.append(depots['lon'][check_depot_name].values.tolist()[0])
        else :
            print("Depot name '{}' not found".format(start_stop))
            return(None)      
                   
    if end_stop[0:3].isdigit() :
        query = "SELECT stop_lat, stop_lon FROM stops WHERE stop_id = '{}'".format(end_stop)   
        end_stop_coords = pd.read_sql_query(query, connection)
        end_stop_coords = end_stop_coords.values.tolist()[0]
    
    else :
        check_depot_name = depots['name'] == end_stop
        if sum(check_depot_name) != 0 :
            end_stop_coords = []
            end_stop_coords.append(depots['lat'][check_depot_name].values.tolist()[0])
            end_stop_coords.append(depots['lon'][check_depot_name].values.tolist()[0])
        else :
            print("Depot name '{}' not found".format(end_stop))
            return(None)       
    
    return(stop(start_stop_coords[0], start_stop_coords[1], end_stop_coords[0], end_stop_coords[1])) 

# Function for looping through each unique dead trip/leg & getting route info 
# from Azure Maps. Save each route as a document to Cosmos DB & save a log to 
# Azure SQL db.
# Define the dead location (loc) type, i.e., either 'trip' or 'leg'. legs will  
# be for depot to & from first/last block stop
def getRouteInfo (trip_vec, start_vec, end_vec, api_url, dead_loc, collection, mode = 'stops'):
    # Ceate tuple of lists for collection of log data  
    dead_unique_id, dead_type, object_id, start_lat, start_lon, end_lat, end_lon = ([], [], [], [], [], [], [])
    for trip in trip_vec :
        print('Executing trip {} of {}'.format(trip, len(trip_vec)))
        start_stop = start_vec[trip - 1]
        end_stop = end_vec[trip - 1]   
        
        # Getting coordinates, depends on the mode (stops or legs)
        if mode == 'stops' :
            if not start_stop[0:3].isdigit() :
                print("Stop id '{}' is not in the correct format - Check the mode!".format(start_stop))
                return(None)
            else :
                coords = getStopCoords(start_stop, end_stop, conn)
        elif mode == 'legs' :
            coords = getLegCoords(start_stop, end_stop, conn)
        else :
            print("Enter a valid mode, either '{}' or '{}'".format('stops', 'legs'))
            return(None)
        
        # Create query string for start and end coordinates   
        query_item = '?query={0},{1}:{2},{3}'.format(coords.start_stop_lat, coords.start_stop_lon, 
                                                     coords.end_stop_lat, coords.end_stop_lon)
        payload = {'batchItems': [{'query': query_item}]}
        headers = {'Content-Type': 'application/json'}
    
        # Request the response from Azure maps
        response = requests.request("POST", api_url, headers=headers, data=json.dumps(payload))
        
        # checking the status code of the request
        if response.status_code == 200:
           # Convert json to python dictionary
           response_data = json.loads(response.text)
           print("Successful HTTP request")
        else:   
           print("Error in the HTTP request")
    
        # Grab the route data recieved frm Azure Maps 
        route = response_data
        # Write Azure maps data to MongoDB & return the ID
        print('Writing data to Cosmos DB...\n')
        route_id = collection.insert_one(route).inserted_id
                     
        # Collect log data
        dead_unique_id.append(trip_vec[trip - 1])
        dead_type.append(dead_loc)
        object_id.append(route_id)
        start_lat.append(coords.start_stop_lat)
        start_lon.append(coords.start_stop_lon)
        end_lat.append(coords.end_stop_lat)
        end_lon.append(coords.end_stop_lon)
        
    # Create a data frame of log output
    dead_route_log_df = pd.DataFrame(object_id, columns = ['object_id'])
    dead_route_log_df['dead_unique_id'] = dead_unique_id
    dead_route_log_df['dead_type'] = dead_type
    dead_route_log_df['start_lat'] = start_lat
    dead_route_log_df['start_lon'] = start_lon
    dead_route_log_df['end_lat'] = end_lat
    dead_route_log_df['end_lon'] = end_lon
       
    # Convert object_id to string
    dead_route_log_df['object_id'] = dead_route_log_df['object_id'].astype(str)
        
    return(dead_route_log_df)

#%%
# Load Access Keys
# ================
# File path Open secret key file stored local
access_keys = load_keys('C:\MyApps\dapTbElectricDublinBus\keys.json')

# Create a connection to the Azure SQL database
# =============================================
server = 'tcp:electricbus-temp.database.windows.net'
database = 'electricbus-eastus-prod-temp'
username = 'teamadmin'
connection_string = 'DRIVER={ODBC Driver 13 for SQL Server};SERVER=' + server + \
    ';DATABASE=' + database +';UID=' + username + ';PWD=' + access_keys.sqldb_pwd

# Connect to the database    
conn = pyodbc.connect(connection_string)

# Create Azure Cosmos DB for MongoDB API Connection
# =================================================
# Azure Cosmos DB service implements wire protocols for common NoSQL APIs including Cassandra, MongoDB. 
# This allows you to use your familiar NoSQL client drivers and tools to interact with your Cosmos database.
uri = "mongodb://electricbus-wood:" + access_keys.cosmos_key + "@electricbus-wood.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=@electricbus-wood@"
#uri = "mongodb://electric-bus-cosmos-east-us:" + cosmos_key + "@electric-bus-cosmos-east-us.mongo.cosmos.azure.com:10255/?ssl=true&retrywrites=false&replicaSet=globaldb&maxIdleTimeMS=120000&appName=@electric-bus-cosmos-east-us@"
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
dead_trip_log_df = getRouteInfo(
    trip_vec = dead_trips_unique['dead_trip_unique_id'], 
    start_vec = dead_trips_unique['trip_first_stop_id'], 
    end_vec = dead_trips_unique['trip_last_stop_id'], 
    api_url = route_api_url, 
    dead_loc = 'trip',
    collection = routes,
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
dead_leg_log_df = getRouteInfo(
    trip_vec = dead_legs_unique['dead_leg_unique_id'], 
    start_vec = dead_legs_unique['start'], 
    end_vec = dead_legs_unique['end'], 
    api_url = route_api_url, 
    dead_loc = 'leg',
    collection = routes,
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

import importlib.util
spec = importlib.util.spec_from_file_location("functions", "C:/MyApps/dapTbElectricDublinBus/common/functions.py")
functs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(functs)

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

        