import os

#---------------------------------------
# URL's
#---------------------------------------
url = 'https://api.open-elevation.com/api/v1/lookup'
url2 = 'https://gtfsr.transportforireland.ie/v1/?format=json'


#---------------------------------------
# Secure variables for Azure Connections
#---------------------------------------
SQLPass = os.environ.get("SQL_Pass")
SQLUser = os.environ.get("SQLUser")
SQLDatabase = os.environ.get("SQLDatabase")
SQLServer = os.environ.get("SQLServer")
SQLPASSTEAM = os.environ.get("SQLPASSTEAM")
SQLUSERTEAM = os.environ.get("SQLUSERTEAM")
SQLDATABASETEAM = os.environ.get("SQLDATABASETEAM")
SQLSERVERTEAM = os.environ.get("SQLSERVERTEAM")
SQLDRIVERTEAM = os.environ.get("SQLDRIVERTEAM")
SQLDriver = os.environ.get("SQLDriver")
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
# Local Folder Locations
#---------------------------------------
shapes = r"C:\Users\James\Documents\MSc in Data Analytics\Database and Ananytics\Research Project\dapTbElectricDublinBus\ingestRawData\raw\shapes.txt"


#---------------------------------------
# Columns required for returning the distinct shape db values
#---------------------------------------
longLatCol = ['shape_id','shape_pt_lat','shape_pt_lon']


#---------------------------------------
# Standard SQL strings for use in the Azure Module
#---------------------------------------
SQLDistinct = "SELECT DISTINCT {0} FROM {1}"

SQLStr = """SELECT {0} 
             FROM {1}
             WHERE {2} = '{3}'"""

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
UNKMGO = "An unknown exception occured while attempting to upload to mongodb."


elevHeaders = {'Accept':'application/json',
               'Content-Type':'application/json'
               }
RTIheaders = {"x-api-key" : 'd211bcc7f9164b4e81ecda066c1ec7c1'}

MongoDB = "shapes"