import urllib
import urllib.request
import json
from math import sqrt
from geopy.distance import great_circle
from geopy.distance import geodesic

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
        elif args[0] == "EuclideanDist":
            return self.EuclideanDist(args[1], args[2], 
                                      args[3],args[4], 
                                      args[5], args[6])
        else:
            return "Object does not exist."

    def callURL(self, url, body, headers):
        """Send request to URL and return response."""
        if body:
            req = urllib.request.Request(url, body, headers)
        else:
            req = urllib.request.Request(url, headers=headers)
        response = urllib.request.urlopen(req, timeout=2000)
        return response
        
    def generateLocationRequest(self, shapeData):
        """Generate Json request from dataframe input for elevations."""
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
        """Convert returned request into Json file type."""
        body = str.encode(json.dumps(shapeData))
        response = self.callURL(in_config.url, body, in_config.elevHeaders)
        jsonReadyData = response.read().decode('utf8').replace("'", '"')
        elevationData = json.loads(jsonReadyData)
        return elevationData

    def EuclideanDist(self, alt1, alt2, lon1, lat1, lon2, lat2):
        """Determine Euclidean distance between two coordinates and their elevations."""
        alt_1 = alt1
        alt_2 = alt2
        dalt = alt_1-alt_2
        p1 = (lon1, lat1)
        p2 = (lon2, lat2)
        calt = geodesic(p1, p2).meters
        trueDistance = sqrt(calt**2 + dalt**2)
        return trueDistance