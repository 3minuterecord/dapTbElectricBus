import os

#---------------------------------------
# URL's
#---------------------------------------
url = 'https://api.open-elevation.com/api/v1/looku'


#---------------------------------------
# Secure variables for Azure Connections
#---------------------------------------
SQLPass = os.environ.get("SQL_Pass")
SQLUser = os.environ.get("SQLUser")
SQLDatabase = os.environ.get("SQLDatabase")
SQLServer = os.environ.get("SQLServer")
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

MongoQuote = f'''mongodb://{MongoUser}:{MongoPass}==@{MongoLocation}/?ssl=true&retrywrites=false&replicaSet=globaldb&maxIdleTimeMS=120000&appName=@{MongoUser}@'''


#---------------------------------------
# Local Folder Locations
#---------------------------------------
shapes = r"C:\Users\James\Documents\MSc in Data Analytics\Database and Ananytics\Research Project\dapTbElectricDublinBus\ingestRawData\raw\shapes.txt"
shapesname = ["shapes"]


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


#---------------------------------------
# Custom Exception Messages
#---------------------------------------
URLOOD = "Please ensure that the URL in the config file is not out of date."
NDIDF = "No data present in the current dataframe."
TEC = "Type error in cosmos connection string, please check your environment variables"
FIDB = "File already exists for this key in the database."
UNKMGO = "An unknown exception occured while attempting to upload to mongodb."