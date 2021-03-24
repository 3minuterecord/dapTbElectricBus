# th

# Function to query time and distance to travel between the two stops
def get_time_and_dist(begin: Stop, end: Stop):
    
    # First search db to find if values already exists.
    tc = TravelCache.objects.filter(from_stop=begin).filter(to_stop=end)
    if len(tc) > 0:
        return tc[0]

    # Otherwise query azure maps API if values not found in DB.
    else:
        # The Synchronous API will return a timeout error (a 408 response) if the request takes longer than 60 seconds.
        # The number of batch items is limited to 100 for this API.
        route_api_url = 'https://atlas.microsoft.com/route/directions/batch/sync/json?api-version=' + API_VERSION \
                    + '&subscription-key=' + SUBSCRIPTION_KEY + '&traffic=' + CHECK_TRAFFIC
        query_item = '?query={0},{1}:{2},{3}'.format(begin.stop_lat, begin.stop_lon, end.stop_lat, end.stop_lon)
        payload = {'batchItems': [{'query': query_item}]}
        headers = {'Content-Type': 'application/json'}
        response = requests.request("POST", route_api_url, headers=headers, data=json.dumps(payload))
        response_data = json.loads(response.text)
        if 'batchItems' in response_data:
            items = response_data['batchItems']
            # for item returned
            #   find time and distance from summary and store in TravelCache
            #   also find the lat/lon points of the route and store in TravelCacheShapes
            for i in items:
                if(i['statusCode'] == 200):
                    summary = i['response']['routes'][0]['summary']

                    # create new cache entry and save to db
                    tc = TravelCache(from_stop=begin,
                                     to_stop=end,
                                     dist_in_meter=summary['lengthInMeters'],
                                     time_in_sec=summary['travelTimeInSeconds'])

                    tc.save()

                    # save the lat/long of this route in TravelCacheShape
                    points = i['response']['routes'][0]['legs'][0]['points']
                    tcs = [TravelCacheShape(travel_cache=tc, shape_pt_lat=p['latitude'], shape_pt_lon=p['longitude'], shape_pt_sequence=i+1) for i, p in enumerate(points)]
                    TravelCacheShape.objects.bulk_create(tcs)
                    return tc
                else:
                    return None
        else:
            return None
