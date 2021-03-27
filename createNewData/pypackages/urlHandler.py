import urllib
import json
import createNewData.data.config as in_config

class UrlHandler():
    def __init__(self, locations):
        self.locations = locations
    def __call__(self, callargs):
        if callargs == "Call URL":
            "do something in the URL"
    
    def generateLocationBody(self):
        print("generate the body here from the dataframe.")
    
    def callURL(self, url, body):
        headers = {'Accept':'application/json',
                   'Content-Type':'application/json'
                   }
        req = urllib.request.Request(url, body, headers)
        response = urllib.request.urlopen(req)
        return response
        

    def mineElevationData(self):
        data =  {
        "locations": [{
                "latitude": 53.3296309426544,
                "longitude": -6.24901208670741
                    },
                    {
                "latitude": 53.3293164971423,
                "longitude": -6.24840939073252
                    }]
        }

        body = str.encode(json.dumps(data))
        response = self.callURL(in_config("url"),body)
        jsonReadyData = response.read().decode('utf8').replace("'", '"')
        elevationData = json.loads(jsonReadyData)
        s = json.dumps(elevationData, indent=4, sort_keys=True)
        print(s)