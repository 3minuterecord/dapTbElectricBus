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
            return self.UploadToSQL(args[1], args[2], args[3])
        elif args[0] == "SelectDistinct":
            return self.SelectDistinct(args[1], args[2])
        elif args[0] == "SelectLongLat":
            return self.SelectLongLat(args[1],args[2],args[3],args[4])
        elif args[0] == "UploadToMongo":
            return self.UploadToMongo(args[1],args[2])
        elif args[0] == "SelectFromMongo":
            return self.SelectFromMongo()
        elif args[0] == "AzureDBConn":
            return self.AzureDBConn(args[1])
        elif args[0] == "CreateMongoColl":
            return self.CreateMongoColl(args[1])
        elif args[0] == "dropMongoColl":
            return self.dropMongoColl(args[1])
        else:
            return "Object does not exist."

    def AzureDBConn(self, connStr):
        """Connect to SQL database simple.
           Requires connection string."""
        conn = pyodbc.connect(connStr)
        return conn

    def AzureDBEng(self, conn):
        """Connect to SQL database for pandas to_sql command.
           Requires connection string.
           **Not Callable outside of method**"""
        connStr = 'mssql+pyodbc:///?odbc_connect={}'
        Eng = connStr.format(urllib.parse.quote_plus(conn))
        return Eng 
    
    def AzureMongoConn(self):
        """Connect to MongoDB.
           **Not Callable outside of method**"""
        uri = self.in_config.MongoQuote
        client = pymongo.MongoClient(uri)
        return client

    def UploadToSQL(self, df, tablename, conn):
        """Upload data dataframe to SQL.
           Requires: Dataframe, new table name 
           and SQL connection"""
        conn = self.AzureDBEng(conn)
        df.to_sql(tablename, conn, if_exists='replace')

    def UploadToMongo(self, collection, MongoData):
        """Upload files to MongoDB.
           Requires collection name and Json 
           file to upload to MongoDB"""
        client = self.AzureMongoConn()
        mydb = client[self.in_config.MongoDB]
        mycol = mydb[collection]
        mydict = MongoData
        mycol.insert_one(mydict)
        client.close()
    
    def DropMongoColl(self, collection):
        """Drop MongoDB collection by collection name.
           Requires collection name."""
        client = self.AzureMongoConn()
        mydb = client[self.in_config.MongoDB]
        mycol = mydb[collection]
        mycol.drop()

    def SelectFromMongo(self):
        """Return all docuements in the MongoDB'shapes' 
           collection"""
        client = self.AzureMongoConn()
        db = client.shapes
        collection = db.shapes
        client.close()
        return collection
    
    def CreateMongoColl(self, newDB):
        """Create empty MongoDB collection.
           requires collection name."""
        client = self.AzureMongoConn()
        mydb = client[self.in_config.MongoDB]
        mycol = mydb[newDB]
        client.close()
    
    def SelectDistinct(self, column, tablename):
        """Collect all the distinct shape ID's and loop through each
           returning the elevation data from the portal.
           Requires column and table name"""
        conn = self.AzureDBConn(self.in_config.connQuote)
        SQLString = self.in_config.SQLDistinct.format(column, tablename)
        df = pd.read_sql(SQLString, conn)
        conn.close()
        return df
    
    def SelectLongLat(self, columns, tablename, columnName, shape):
        """Collect all the data in a table that 
           contains the shape name in 
           the shape_id column."""
        conn = self.AzureDBConn(self.in_config.connQuote)
        SQLString = self.in_config.SQLStr.format(columns, 
                                                 tablename, 
                                                 columnName, 
                                                 shape)
        df = pd.read_sql(SQLString, conn)
        conn.close()
        return df

    