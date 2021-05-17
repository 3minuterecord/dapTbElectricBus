import os
import json

#---------------------------------------
# URL's
#---------------------------------------
url = 'https://api.open-elevation.com/api/v1/lookup'
url2 = 'https://gtfsr.transportforireland.ie/v1/?format=json'
GTFSURL = 'https://www.transportforireland.ie/transitData/google_transit_combined.zip'

#---------------------------------------
# Secure variables for Azure Connections
# for James-DEV
#---------------------------------------
SQLPass = os.environ.get("SQL_Pass")
SQLUser = os.environ.get("SQLUser")
SQLDatabase = os.environ.get("SQLDatabase")
SQLServer = os.environ.get("SQLServer")
SQLDriver = os.environ.get("SQLDriver")

#---------------------------------------
# Secure variables for Azure Connections
# for use on James' personal machine.
#---------------------------------------
with open(os.path.expanduser("~/Documents/keys.json")) as file1:
    password = json.load(file1)
with open(os.path.expanduser("~/Documents/connection_names.json")) as file2:
    connection = json.load(file2)


SQLPASSTEAM = password["sqldb_pwd"]
SQLUSERTEAM = connection["sql_user"]
SQLDATABASETEAM = connection["sql_database"]
SQLSERVERTEAM = connection["sql_server"]
SQLDRIVERTEAM = "{ODBC Driver 13 for SQL Server}"

#---------------------------------------
# Secure variables for Azure Connections
# for use on research machine.
#---------------------------------------
# SQLPASSTEAM = os.environ.get("SQLPASSTEAM")
# SQLUSERTEAM = os.environ.get("SQLUSERTEAM")
# SQLDATABASETEAM = os.environ.get("SQLDATABASETEAM")
# SQLSERVERTEAM = os.environ.get("SQLSERVERTEAM")
# SQLDRIVERTEAM = os.environ.get("SQLDRIVERTEAM")


#---------------------------------------
# Secure variables for Azure Connections
# used to test RTI data collection to CosmosDB
#---------------------------------------
MongoPass = os.environ.get("MongoPass")
MongoUser = os.environ.get("MongoUser")
MongoLocation = os.environ.get("MongoLocation")


#---------------------------------------
# Azure Connections strings
#---------------------------------------
connQuote = f'''DRIVER={SQLDriver};
                SERVER={SQLServer};
                PORT=1433;
                DATABASE={SQLDatabase};
                UID={SQLUser};
                PWD={SQLPass}'''

teamConnQuote = f'''DRIVER={SQLDRIVERTEAM};
                SERVER={SQLSERVERTEAM};
                PORT=1433;
                DATABASE={SQLDATABASETEAM};
                UID={SQLUSERTEAM};
                PWD={SQLPASSTEAM}'''

MongoQuote = f'''mongodb://{MongoUser}:{MongoPass}==@{MongoLocation}/?ssl=true&retrywrites=false&replicaSet=globaldb&maxIdleTimeMS=120000&appName=@{MongoUser}@'''

#---------------------------------------
# SQL misc. vaiables
#---------------------------------------

MongoDB = "shapes"


#---------------------------------------
# Local Folder Locations for development
#---------------------------------------
shapes = r"~\MSc in Data Analytics\Database and Ananytics\Research Project\dapTbElectricDublinBus\ingestRawData\raw\shapes.txt"
stops = r"~\MSc in Data Analytics\Database and Ananytics\Research Project\dapTbElectricDublinBus\ingestRawData\raw\stops.txt"

#---------------------------------------
# Columns required for returning the 
# distinct shape db values
#---------------------------------------
longLatCol = ['shape_id','shape_pt_lat','shape_pt_lon']


#---------------------------------------
# Standard SQL strings for use in the 
# Azure Module
#---------------------------------------
SQLDistinct = "SELECT DISTINCT {0} FROM {1}"

SQLDrop = "DROP TABLE {0}"

SQLStr = """SELECT {0} 
             FROM {1}
             WHERE {2} = '{3}'"""

SQLSelect = SQLStr = """SELECT * FROM {0}"""

SQLElevation = """SELECT
                    [dbo].[shapes].shape_id,[dbo].[shapes].shape_pt_lat,[dbo].[shapes].shape_pt_lon,[dbo].[shapes].shape_pt_sequence,
                    [dbo].[elevations].elevation
                    FROM
                    [dbo].[shapes],[dbo].[elevations]
                    WHERE
                    [dbo].[shapes].shape_pt_lat = [dbo].[elevations].latitude
                    AND
                    [dbo].[shapes].shape_pt_lon = [dbo].[elevations].longitude
               """

#---------------------------------------
# Custom Exception Messages
#---------------------------------------
URLOOD = "Please ensure that the URL in the config file is not out of date."
NDIDF = "No data present in the current dataframe."
TEC = "Type error in cosmos connection string, please check your environment variables"
FIDB = "File already exists for this key in the database."
UNKMGO = "An unexpected exception occured while attempting to complete this function."
FailedImport = "Failed to import critical modules for this script.\nPlease confirm that files exist in the correct locations."
RequestToBig = "Request is too large for API, please review code in order to reduce request size"
NoSQLShema = "Something went wrong while attempting to collect the 'shapes' schema from the team SQL database. Please ensure that the 'shapes' schema exists in the database and all related column names are correct."
SQLConnectionFail = "Failed to connect to SQL database, please ensure that connection details and user credentials are correct."

#---------------------------------------
# API call header data
#---------------------------------------


elevHeaders = {'Accept':'application/json',
               'Content-Type':'application/json'
               }
RTIheaders = {"x-api-key" : os.environ.get("RTIAPIKEY")}

