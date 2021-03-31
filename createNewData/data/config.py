import os

url = 'https://api.open-elevation.com/api/v1/lookup'


SQLPass = os.environ.get("SQL_Pass")
SQLUser = os.environ.get("SQLUser")
SQLDatabase = os.environ.get("SQLDatabase")
SQLServer = os.environ.get("SQLServer")
SQLDriver = os.environ.get("SQLDriver")

connQuote = f'''DRIVER={SQLDriver};
                SERVER={SQLServer};
                PORT=1433;
                DATABASE={SQLDatabase};
                UID={SQLUser};
                PWD={SQLPass}'''




shapes = r"C:\Users\James\Documents\MSc in Data Analytics\Database and Ananytics\Research Project\dapTbElectricDublinBus\ingestRawData\raw\shapes.txt"
shapesname = ["shapes"]


SQLDistinct = "SELECT DISTINCT {0} FROM {1}"

