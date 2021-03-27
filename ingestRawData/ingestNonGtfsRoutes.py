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

import requests
import json

filepath = 'keys.json'
with open(filepath) as json_file:
    key_data = json.load(json_file)
    subscription_key = key_data['subscription_key']  
    print(subscription_key)

api_version = '1.0'
check_traffic = '0'

begin = {'stop_lat':53.116927776990494, 'stop_lon':-7.325474118853148}
end = {'stop_lat':53.03361922891958, 'stop_lon':-7.303225998037869} 

# Azure Maps route URL (don't check traffic for this simple use-case)
# Use batch mode so that the same query can be used for multiple route requests
route_api_url = 'https://atlas.microsoft.com/route/directions/batch/sync/json?api-version=' + api_version \
                    + '&subscription-key=' + subscription_key + '&traffic=' + check_traffic

# Create query string for start and end coordinates                    
query_item = '?query={0},{1}:{2},{3}'.format(begin['stop_lat'], begin['stop_lon'], end['stop_lat'], end['stop_lon'])
payload = {'batchItems': [{'query': query_item}]}
headers = {'Content-Type': 'application/json'}

# Request the response from Azure maps
response = requests.request("POST", route_api_url, headers=headers, data=json.dumps(payload))

# checking the status code of the request
if response.status_code == 200:
   # Convert json to python dictionary
   response_data = json.loads(response.text)
   print("Successful HTTP request\n")
   print(response_data)
else:   
   print("Error in the HTTP request")

# Save raw data to Azure Cosmos DB for MongoDB API
# ================================================
# Azure Cosmos DB service implements wire protocols for common NoSQL APIs including Cassandra, MongoDB. 
# This allows you to use your familiar NoSQL client drivers and tools to interact with your Cosmos database.
from pymongo import MongoClient
uri = "mongodb://electric-bus-cosmos-east-us:tsz17HxALAfB62dTxIrNkR6bJIYraYFTljK6KzsBK60o462GOhWcxOvLxuXxQnesq5EXvx9loYum6h1MtSKhYg==@electric-bus-cosmos-east-us.mongo.cosmos.azure.com:10255/?ssl=true&retrywrites=false&replicaSet=globaldb&maxIdleTimeMS=120000&appName=@electric-bus-cosmos-east-us@"
client = MongoClient(uri)
# Create database
db = client['bus_routes_nosql']
# Create collection for route data
routes = db.routes
# Grab the route data recieved frm Azure Maps 
route = response_data
# Write Azure maps data to MongoDB
route_id = routes.insert_one(route).inserted_id
route_id

