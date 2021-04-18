import urllib
import urllib.request
import json

from numpy import empty
import createNewData.data.config as in_config
import pyodbc

class UrlHandler():
    def __init__(self, in_config):
        self.in_config = in_config
        
    def __call__(self, *args):
        if args[0] == "mineElevationData":
            return self.mineElevationData(args[1])
        elif args[0] == "callURL":
            return self.callURL(args[1], args[2], args[3])
        elif args[0] == "generateLocationRequest":
            return self.generateLocationRequest(args[1])
        else:
            return "Object does not exist."

    def callURL(self, url, body, headers):
        if body:
            req = urllib.request.Request(url, body, headers)
        else:
            req = urllib.request.Request(url, headers=headers)
        response = urllib.request.urlopen(req)
        return response
        
    def generateLocationRequest(self, shapeData):
        listofLocations = []
        locationDict = {}
        for index,row in shapeData.iterrows():
            longlatdict = {}
            longlatdict["latitude"] = row[1]
            longlatdict["longitude"] = row[2]
            listofLocations.append(longlatdict.copy())
        locationDict["locations"] = listofLocations
        return locationDict

    def mineElevationData(self, shapeData):
        # data = self.generateLocationRequest(shapeData)
        body = str.encode(json.dumps(shapeData))
        response = self.callURL(in_config.url, body, in_config.elevHeaders)
        jsonReadyData = response.read().decode('utf8').replace("'", '"')
        elevationData = json.loads(jsonReadyData)
        return elevationData