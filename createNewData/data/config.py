import os

url = 'https://api.open-elevation.com/api/v1/lookup'


SQLPass = os.environ.get("SQL_Pass")
SQLUser = os.environ.get("SQLUser")
SQLDatabase = os.environ.get("SQLDatabase")
SQLServer = os.environ.get("SQLServer")
SQLDriver = os.environ.get("SQLDriver")
MongoPass = os.environ.get("MongoPass")
MongoUser = os.environ.get("MongoPass")
MongoLocation = os.environ.get("MongoLocation")

connQuote = f'''DRIVER={SQLDriver};
                SERVER={SQLServer};
                PORT=1433;
                DATABASE={SQLDatabase};
                UID={SQLUser};
                PWD={SQLPass}'''

MongoQuote = f'''mongodb://{MongoUser}:{MongoPass}==@{MongoLocation}/?ssl=true&retrywrites=false&replicaSet=globaldb&maxIdleTimeMS=120000&appName=@{MongoUser}@'''




shapes = r"C:\Users\James\Documents\MSc in Data Analytics\Database and Ananytics\Research Project\dapTbElectricDublinBus\ingestRawData\raw\shapes.txt"
shapesname = ["shapes"]


longLatCol = ['shape_id','shape_pt_lat','shape_pt_lon']


SQLDistinct = "SELECT DISTINCT {0} FROM {1}"

SQLStr = """SELECT {0} 
             FROM {1}
             WHERE {2} = '{3}'"""