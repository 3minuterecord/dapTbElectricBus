import pandas as pd
import json
from bson import ObjectId
import requests
import time


# Create a class for access keys, i.e., db passwords, subscription keys, etc.
class keys:
  def __init__(self, maps_sub_key, cosmos_key, sqldb_pwd):
    self.maps_sub_key = maps_sub_key
    self.cosmos_key = cosmos_key
    self.sqldb_pwd = sqldb_pwd

# Create a class for access keys, i.e., db passwords, subscription keys, etc.
class con_names:
  def __init__(self, sql_server, sql_database, sql_user):
    self.sql_server = sql_server
    self.sql_database = sql_database
    self.sql_user = sql_user
    
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
        key_data = json.load(json_file)
        keys.maps_sub_key = key_data['subscription_key']
        keys.cosmos_key = key_data['cosmos_key']
        keys.sqldb_pwd = key_data['sqldb_pwd'] 
    # Catch file not found error    
    except FileNotFoundError as e:
        print("File not found " + str(e))
    # Catch if file is not readable
    except IOError as e:
        print("Error: File is '" + str(e) + "'.")
    # Catch if attribute does not exist in file
    except KeyError as e:
        print("Error: Attribute " + str(e) + " not found in file.")        
    else :
    # Return the imported data if no errors are captured           
        return(keys)    
    finally :
     # Close the file   
        json_file.close()


# Create a function to load keys file
def load_connection_names (filepath) :    
    try:
        # Open the file and read the data
        json_file = open(filepath)     
        name_data = json.load(json_file)
        con_names.sql_server = name_data['sql_server']
        con_names.sql_database = name_data['sql_database']
        con_names.sql_user = name_data['sql_user']
    # Catch file not found error    
    except FileNotFoundError as e:
        print("File not found " + str(e))
    # Catch if file is not readable
    except IOError as e:
        print("Error: File is '" + str(e) + "'.")
    # Catch if attribute does not exist in file
    except KeyError as e:
        print("Error: Attribute " + str(e) + " not found in file.")
    else :
    # Return the imported data if no errors are captured            
        return(con_names)    
    finally :
     # Close the file   
        json_file.close()
        
        
# Create function to save tabulated data to Azure SQL db
def saveLogInfo (table, df, eng, chunks = 10000):
    s = time.time()
    df.to_sql(table, eng, if_exists = 'replace', chunksize = chunks, index = False)
    print('Time taken: ' + str(round(time.time() - s, 1)) + 's')
    return(None)


# Create a function for tabulating json route data
def tabulateRouteInfo (object_vec, trip_vec, collection):
    # Create a tuple of lists to hold parsed JSON data so that it can be 
    # easily passed into a dataframe for easy loading to RDMS table.
    dead_trip_unique_id, latitude, longitude, point_order, distance_km, time_hrs, mode = ([], [], [], [], [], [], []) 
    for count, object_id in enumerate(object_vec):
        print('Processing dead trip {} of {}'.format(count + 1, len(object_vec)))
        post_id = ObjectId(object_id)        
        route_data = collection.find_one({"_id": post_id})
    
        # Grab blocks of info from the route data
        route_points = route_data['batchItems'][0]['response']['routes'][0]['legs'][0]['points']
        summary_info = route_data['batchItems'][0]['response']['routes'][0]['summary']
        sections_info = route_data['batchItems'][0]['response']['routes'][0]['sections'][0]
    
        # Now loop through and append data to the appropriate lists
        print('Parsing points...')
        for point_count, point in enumerate(route_points) :
            dead_trip_unique_id.append(trip_vec[count])
            latitude.append(point['latitude'])
            longitude.append(point['longitude'])
            # Point order is important to ensure correct point
            # order after loading data from SQL db
            point_order.append(point_count + 1)
            distance_km.append(summary_info['lengthInMeters'] / 1000)
            time_hrs.append(round(summary_info['travelTimeInSeconds'] / (60*60), 6))
            mode.append(sections_info['travelMode'])

    # Create a dataframe & populate with the list data    
    route_df = pd.DataFrame(dead_trip_unique_id, columns = ['dead_trip_unique_id'])
    route_df['latitude'] = latitude
    route_df['longitude'] = longitude
    route_df['point_order'] = point_order
    route_df['distance_km'] = distance_km
    route_df['time_hrs'] = time_hrs
    
    return(route_df)


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
def getRouteInfo (trip_vec, start_vec, end_vec, api_url, dead_loc, collection, connection, mode = 'stops'):
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
                coords = getStopCoords(start_stop, end_stop, connection)
        elif mode == 'legs' :
            coords = getLegCoords(start_stop, end_stop, connection)
        else :
            print("Enter a valid mode, either '{}' or '{}'".format('stops', 'legs'))
            return(None)
        
        # Create query string for start and end coordinates   
        query_item = '?query={0},{1}:{2},{3}'.format(coords.start_stop_lat, coords.start_stop_lon, 
                                                     coords.end_stop_lat, coords.end_stop_lon)
        payload = {'batchItems': [{'query': query_item}]}
        headers = {'Content-Type': 'application/json'}
        
        # Send the POST request 
        try :
            # Request the response from Azure maps
            response = requests.request("POST", api_url, headers=headers, data=json.dumps(payload))
            # checking the status code of the request
            if response.status_code == 200:
                # Convert json to python dictionary
                response_data = json.loads(response.text)
                print("Successful HTTP request")
            else:   
                raise Exception('Error in the HTTP request')
        except Exception as e:
            print('Error1' + str(e))     
            
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

# Create a simple function for adding an index to an SQL DB
def createIndex (col, table, curs) :
    query_string = 'CREATE INDEX idx_{0} ON {1} ({0})'.format(col, table)  
    curs.execute(query_string)

        
