from typing import Collection
import pyodbc
import pandas as pd
import urllib
import pymongo


class Azure():
    def __init__(self,in_config):
        self.in_config = in_config
    def __call__(self, *args):
        if args[0] == "UploadToSQL":
            return self.UploadToSQL(args[1], args[2])
        if args[0] == "SelectDistinct":
            return self.SelectDistinct(args[1], args[2])
        if args[0] == "SelectLongLat":
            return self.SelectLongLat(args[1],args[2],args[3],args[4])
        if args[0] == "UploadToMongo":
            return self.UploadToMongo(args[1],args[2])
        if args[0] == "SelectFromMongo":
            return self.SelectFromMongo()

    def AzureDBConn(self):
        conn = pyodbc.connect(self.in_config.connQuote)
        return conn

    def AzureDBEng(self):
        connStr = 'mssql+pyodbc:///?odbc_connect={}'
        Eng = connStr.format(urllib.parse.quote_plus(self.in_config.connQuote))
        return Eng 
    
    def AzureMongoConn(self):
        uri = self.in_config.MongoQuote
        print(uri)
        client = pymongo.MongoClient(uri)
        return client

    def UploadToSQL(self, df, tablename):
        conn = self.AzureDBEng()
        df.to_sql(tablename, conn, if_exists='replace')

    def UploadToMongo(self, collection, MongoData):
        client = self.AzureMongoConn()
        mydb = client[collection]
        mycol = mydb[collection]
        mydict = MongoData
        mycol.insert_one(mydict)
        client.close()

    def SelectFromMongo(self):
        client = self.AzureMongoConn()
        db = client.shapes
        collection = db.shapes
        client.close()
        return collection
    
    def SelectDistinct(self, column, tablename):
        """ Collect all the distinct shape ID's and loop through each
            returning the elevation data from the portal."""
        conn = self.AzureDBConn()
        SQLString = self.in_config.SQLDistinct.format(column, tablename)
        df = pd.read_sql(SQLString, conn)
        conn.close()
        return df
    
    def SelectLongLat(self, columns, tablename, columnName, shape):
        """ Collect all the data in a table that contains the shape name in 
            the shape_id column."""
        conn = self.AzureDBConn()
        SQLString = self.in_config.SQLStr.format(columns, 
                                                 tablename, 
                                                 columnName, 
                                                 shape)
        df = pd.read_sql(SQLString, conn)
        conn.close()
        return df

    