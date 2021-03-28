# Extract Raw Route Data from Cosmos DB & Write to Azure SQL
# ==========================================================
import json
import pandas as pd

filepath = 'C:\MyApps\dapTbElectricDublinBus\keys.json'
with open(filepath) as json_file:
    key_data = json.load(json_file)
    cosmos_key = key_data['cosmos_key']  
    print(cosmos_key)

#%%    
# Extract Data Raw Data from Azure Cosmos DB for MongoDB API
# ==========================================================
# Azure Cosmos DB service implements wire protocols for common NoSQL APIs 
# including Cassandra, MongoDB. This allows you to use your familiar NoSQL 
# client drivers and tools to interact with your Cosmos database.
from pymongo import MongoClient
uri = "mongodb://electric-bus-cosmos-east-us:" + cosmos_key + \
    "@electric-bus-cosmos-east-us.mongo.cosmos.azure.com:10255/?ssl=true&retrywrites=false&replicaSet=globaldb&maxIdleTimeMS=120000&appName=@electric-bus-cosmos-east-us@"
client = MongoClient(uri)

# Create database
import pprint

# Database details
db = client['bus_routes_nosql']

# Collection for route data
routes = db.routes

# Extract data
# Data pretty printer
pprint.pprint(routes.find_one())
raw_data = routes.find_one()


#%%
# Create a tuple of lists to hold parsed JSON data so that it can be 
# easily passed into a dataframe for easy loading to RDMS table.
non_route_id, latitude, longitude, distance_km, time_hrs, mode = ([], [], [], [], [], []) 

# Grab blocks of info from the route data
route_points = raw_data['batchItems'][0]['response']['routes'][0]['legs'][0]['points']
summary_info = raw_data['batchItems'][0]['response']['routes'][0]['summary']
sections_info = raw_data['batchItems'][0]['response']['routes'][0]['sections'][0]

# Now loop through and append data to the lists
for point in route_points :
    non_route_id.append(1)
    latitude.append(point['latitude'])
    longitude.append(point['longitude'])
    distance_km.append(summary_info['lengthInMeters'] / 1000)
    time_hrs.append(round(summary_info['travelTimeInSeconds'] / (60*60), 6))
    mode.append(sections_info['travelMode'])
    
route_df = pd.DataFrame(non_route_id, columns = ['non_route_id'])
route_df['latitude'] = latitude
route_df['longitude'] = longitude
route_df['distance_km'] = distance_km
route_df['time_hrs'] = time_hrs