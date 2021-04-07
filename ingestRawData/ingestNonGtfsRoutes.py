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

# Open secret key file stored local
filepath = 'C:\MyApps\dapTbElectricDublinBus\keys.json'
with open(filepath) as json_file:
    key_data = json.load(json_file)
    subscription_key = key_data['subscription_key']
    cosmos_key = key_data['cosmos_key'] 
    sqldb_pwd = key_data['sqldb_pwd'] 

# Create a connection to the Azure SQL database
server = 'tcp:electricbus-temp.database.windows.net'
database = 'electricbus-eastus-prod-temp'
username = 'teamadmin'
password = sqldb_pwd
connection_string = 'DRIVER={ODBC Driver 13 for SQL Server};SERVER=' + server + \
    ';DATABASE=' + database+';UID=' + username + ';PWD=' + password

# Connect to the database    
conn = pyodbc.connect(connection_string)

# Get the stop analysis data from the database and drop duplicates so that 
# We only have unique dead trips
query = 'SELECT * FROM stop_analysis'   
dead_trips = pd.read_sql_query(query, conn)
dead_trips_unique = dead_trips[['dead_trip_unique_id', 'trip_first_stop_id', 'trip_last_stop_id']].drop_duplicates()
# Reset the index after dropping rows
dead_trips_unique = dead_trips_unique.reset_index()
del query

#%%
# Create a tuple of lists to hold log info as we later loop through each dead
# trip and get its route info
dead_trip_unique_id, dead_type, object_id, start_lat, start_lon, end_lat, end_lon = ([], [], [], [], [], [], [])

# Set variable values for Azure Maps post request
api_version = '1.0'
check_traffic = '0'

# Create a class for trip stop info, i.e., start end end coordinates  
class stop:
  def __init__(self, start_stop_lat, start_stop_lon, end_stop_lat, end_stop_lon):
    self.start_stop_lat = start_stop_lat
    self.start_stop_lon = start_stop_lon
    self.end_stop_lat = end_stop_lat
    self.end_stop_lon = end_stop_lon

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
            start_stop_coords.append(depots['lat'][check_depot_name])
            start_stop_coords.append(depots['lon'][check_depot_name])
        else :
            print("Depot name '{}' not found".format(start_stop))
            return(None)      
                   
    if start_stop[0:3].isdigit() :
        query = "SELECT stop_lat, stop_lon FROM stops WHERE stop_id = '{}'".format(end_stop)   
        end_stop_coords = pd.read_sql_query(query, connection)
        end_stop_coords = end_stop_coords.values.tolist()[0]
    
    else :
        check_depot_name = depots['name'] == end_stop
        if sum(check_depot_name) != 0 :
            end_stop_coords = []
            end_stop_coords.append(depots['lat'][check_depot_name])
            end_stop_coords.append(depots['lon'][check_depot_name])
        else :
            print("Depot name '{}' not found".format(end_stop))
            return(None)       
    
    return(stop(start_stop_coords[0], start_stop_coords[1], end_stop_coords[0], end_stop_coords[1]))    
 
    
# Get & save Raw Data to Azure Cosmos DB for MongoDB API
# ======================================================
# Azure Cosmos DB service implements wire protocols for common NoSQL APIs including Cassandra, MongoDB. 
# This allows you to use your familiar NoSQL client drivers and tools to interact with your Cosmos database.
uri = "mongodb://electricbus-wood:" + cosmos_key + "@electricbus-wood.mongo.cosmos.azure.com:10255/?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=@electricbus-wood@"
#uri = "mongodb://electric-bus-cosmos-east-us:" + cosmos_key + "@electric-bus-cosmos-east-us.mongo.cosmos.azure.com:10255/?ssl=true&retrywrites=false&replicaSet=globaldb&maxIdleTimeMS=120000&appName=@electric-bus-cosmos-east-us@"
client = MongoClient(uri)
# Create database
db = client['bus_routes_nosql']
# Create collection for route data
routes = db.routes
# define the dead type, i.e., either 'trip' or 'leg'.legs will be for depot to 
# and from first/last block stop
dead_trip_type = 'trip'
#%%
# Now loop through each unique dead trip & get route info from Azure Maps
# Save each route as a document to Cosmos DB
for trip in dead_trips_unique['dead_trip_unique_id'] :
    print('Executing trip {} of {}'.format(trip, len(dead_trips_unique['dead_trip_unique_id'])))
    start_stop_id = dead_trips_unique['trip_first_stop_id'][trip - 1]
    end_stop_id = dead_trips_unique['trip_last_stop_id'][trip - 1]

    coords = getStopCoords(start_stop_id, end_stop_id, conn)
    
    # Azure Maps route URL (don't check traffic for this simple use-case)
    # Use batch mode so that the same query can be used for multiple route requests
    route_api_url = 'https://atlas.microsoft.com/route/directions/batch/sync/json?api-version=' + api_version \
                    + '&subscription-key=' + subscription_key + '&traffic=' + check_traffic

    # Create query string for start and end coordinates   
    query_item = '?query={0},{1}:{2},{3}'.format(coords.start_stop_lat, coords.start_stop_lon, 
                                                 coords.end_stop_lat, coords.end_stop_lon)
    payload = {'batchItems': [{'query': query_item}]}
    headers = {'Content-Type': 'application/json'}

    # Request the response from Azure maps
    response = requests.request("POST", route_api_url, headers=headers, data=json.dumps(payload))
    
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
    route_id = routes.insert_one(route).inserted_id
    
    # Collect log data
    dead_trip_unique_id.append(dead_trips_unique['dead_trip_unique_id'][trip - 1])
    dead_type.append(dead_trip_type)
    object_id.append(route_id)
    start_lat.append(coords.start_stop_lat)
    start_lon.append(coords.start_stop_lon)
    end_lat.append(coords.end_stop_lat)
    end_lon.append(coords.end_stop_lon)

    # Create a data frame of log output
    dead_route_log_df = pd.DataFrame(object_id, columns = ['object_id'])
    dead_route_log_df['dead_trip_unique_id'] = dead_trip_unique_id
    dead_route_log_df['dead_type'] = dead_type
    dead_route_log_df['start_lat'] = start_lat
    dead_route_log_df['start_lon'] = start_lon
    dead_route_log_df['end_lat'] = end_lat
    dead_route_log_df['end_lon'] = end_lon
    
    # Convert object_id to string
    dead_route_log_df['object_id'] = dead_route_log_df['object_id'].astype(str)

#%%

# Azure Maps route URL (don't check traffic for this simple use-case)
# Use batch mode so that the same query can be used for multiple route requests
route_api_url = 'https://atlas.microsoft.com/route/directions/batch/sync/json?api-version=' + api_version \
                        + '&subscription-key=' + subscription_key + '&traffic=' + check_traffic

# Function for looping through each unique dead trip/leg & getting route info 
# from Azure Maps. Save each route as a document to Cosmos DB & save a log to 
# Azure SQL db.
def getRouteInfo (trip_vec, start_vec, end_vec, api_url, dead_loc, collection, mode = 'stops'):
    for trip in trip_vec :
        print('Executing trip {} of {}'.format(trip, len(trip_vec)))
        start_stop = start_vec[trip - 1]
        end_stop = end_vec[trip - 1]   
        
        # Getting coordinates, depends on the mode (stops or legs)
        if mode == 'stops' :
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
        
        # Ceate tuple of lists for collection of log data  
        dead_unique_id, dead_type, object_id, start_lat, start_lon, end_lat, end_lon = ([], [], [], [], [], [], [])
        
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
# Get Dead TRIP data & create table of log info
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
# Review the log data that has been converted to data frame
pd.set_option('display.max_columns', 500)
pd.set_option('expand_frame_repr', False)
print(dead_route_log_df)


#%%
# Create code to write a pandas dataframe to SQL table
# Using a similar method to dbWriteTable in R
from sqlalchemy import create_engine
from urllib.parse import quote_plus
import time

quoted = quote_plus(connection_string)
new_con = 'mssql+pyodbc:///?odbc_connect={}'.format(quoted)
engine = create_engine(new_con,  fast_executemany = True)

table_name = 'dead_trip_log'
df = dead_route_log_df

s = time.time()
df.to_sql(table_name, engine, if_exists = 'replace', chunksize = None, index = False)
print('Time taken: ' + str(round(time.time() - s, 1)) + 's')

#%%
# Now Focus on Dead Leg Route Data
query = 'SELECT * FROM dead_leg_log'   
dead_legs = pd.read_sql_query(query, conn)

# Create a tuple of lists to hold log info as we later loop through each dead
# trip and get its route info
dead_leg_unique_id, dead_type, object_id, start_lat, start_lon, end_lat, end_lon = ([], [], [], [], [], [], [])

# define the dead type, i.e., either 'trip' or 'leg'.legs will be for depot to 
# and from first/last block stop
dead_trip_type = 'leg'

#%%
a = 4
b = 7
if a > b : 
    print('hggh')
else :
    print('no') 

if b == a :
    print('bow owo')
else :
    print('yes')    
    
    
    
    