import urllib
import urllib.request
import json
import createNewData.data.config as in_config
import pyodbc

class UrlHandler():
    def __init__(self, in_config):
        self.in_config = in_config
    def __call__(self, *args):
        if args[0] == "mineElevationData":
            return self.mineElevationData(args[1])

    def callURL(self, url, body):
        headers = {'Accept':'application/json',
                   'Content-Type':'application/json'
                   }
        req = urllib.request.Request(url, body, headers)
        response = urllib.request.urlopen(req)
        return response
    
    def generateLocationRequest(self, shapeData):
        listofLocations = []
        locationDict = {}
        for index,row in shapeData.iterrows():
            longlatdict = {}
            longlatdict["latitude"] = row[1]
            longlatdict["longitude"] = row[1]
            listofLocations.append(longlatdict.copy())
        locationDict["locations"] = listofLocations
        return locationDict

    def mineElevationData(self, shapeData):
        data = self.generateLocationRequest(shapeData)
        body = str.encode(json.dumps(data))
        response = self.callURL(in_config.url,body)
        jsonReadyData = response.read().decode('utf8').replace("'", '"')
        print(jsonReadyData)
        elevationData = json.loads(jsonReadyData)
        s = json.dumps(elevationData, indent=4, sort_keys=True)
        return s