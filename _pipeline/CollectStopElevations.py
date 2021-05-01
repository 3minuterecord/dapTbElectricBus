from sys import getsizeof as dictsize
import time
import urllib
import pandas as pd
import urllib.request

try:
    import createNewData.data.config as in_config
    from createNewData.pypackages.Azure import Azure
    from createNewData.pypackages.urlHandler import UrlHandler
    AzurePackage = Azure(in_config)
    Url = UrlHandler(in_config)
    
    
except ImportError as e:
    print(in_config.FailedImport)
    print(e)

def collectStopElevations():
    listOfBatches = []
    batches = {"locations" : []}
    try:
        rawShapedf = AzurePackage("SelectAllData", "stops")
        shapesDF = rawShapedf[["stop_id", "stop_lat","stop_lon"]]
        shapesRequest = shapesDF.drop_duplicates(subset=None, 
                                                keep='first', 
                                                inplace=False)
        shapesCoordinates = Url("generateLocationRequest", shapesRequest)
        for key, value in shapesCoordinates.items():
            if key == "locations":
                locations = value
        while len(locations) != 0:
            for each in locations:
                if dictsize(batches["locations"]) +\
                                    dictsize(each) +\
                                    dictsize(batches) < 9700:
                    location = locations.pop(0)
                    batches["locations"].append(location)
                else:
                    location = locations.pop(0)
                    batches["locations"].append(location)
                    listOfBatches.append(batches)
                    batches = {"locations" : []}
            for each in listOfBatches:
                if dictsize(each) > 10000:
                    raise Exception(in_config.RequestToBig)
                else:
                    pass
        else:
            print("All values added to the list of requests.")
    except pd.io.sql.DatabaseError as e:
        print(in_config.NoSQLShema)

    except urllib.request.HTTPError as e:
        if e.code == "403":
            print(in_config.SQLConnectionFail)
        
    except Exception as e:
        print(in_config.UNKMGO)
        print(e)

    listOfObjects = []
    listOfElevations = []
    ListOfDicts = []

    print(f"There are {len(listOfBatches)} batches to collect.")

    Iteration = 0
    try:
        for each in listOfBatches:
                attempts = 0
                while attempts < 5:
                    try:
                        ListOfDicts.append(Url("mineElevationData",each))
                        break
                    except urllib.error.HTTPError:
                        attempts = attempts+1
                Iteration = Iteration + 1
                print(f"Elevation {Iteration} Collected")
                time.sleep(2)
        for each in ListOfDicts:
            for key, value in each.items():
                if type(value) is list:
                    listOfObjects.append(value)

        for each in listOfObjects:
            for elevation in each:
                listOfElevations.append(elevation)
                Iteration = Iteration +1
        df = pd.DataFrame(listOfElevations)
        dfTrimmed = df.drop_duplicates()
        try:
            sumElevation = dfTrimmed["elevation"].sum()
        except: 
            raise Exception("Failed to collect all elevations, please try again.")
    except KeyError as e:
        print(f"Column {e} cannot be found in the dataframe.")
    except NameError as e:
        print(f"The Datatable {e} cannot be found.")
    except Exception as e:
        print(in_config.UNKMGO)
        print(type(e))
        print(e)
    try:
        print("Uploading to SQL.")
        SqlDataCursor = AzurePackage("UploadToSQL",
                                    dfTrimmed,
                                    "stopElevations",
                                    in_config.teamConnQuote)
        print("Upload Complete.")
    except pd.io.sql.DatabaseError as e:
        print(in_config.NoSQLShema)
    except Exception as e:
        print(in_config.UNKMGO)
        print(e)

if __name__ == '__main__':
    collectStopElevations()