source('common/db.R')

library(rjson)
library(dplyr)

# The app's database (SQL azure)
DATABASE <- "electricbus-eastus-prod"
DEFAULT_SERVER <- "electricbus.database.windows.net"
PORT <- 1433
USERNAME <- "teamadmin"

conPool <- getDbPool(DATABASE)
con <- poolCheckout(conPool)

toSeconds <- function(x){
  if (!is.character(x)) stop("x must be a character string of the form H:M:S")
  if (length(x)<=0)return(x)
  
  unlist(
    lapply(x,
           function(i){
             i <- as.numeric(strsplit(i, ':', fixed = TRUE)[[1]])
             if (length(i) == 3) 
               i[1] * 3600 + i[2] * 60 + i[3]
             else if (length(i) == 2) 
               i[1] * 60 + i[2]
             else if (length(i) == 1) 
               i[1]
           }  
    )  
  )  
} 

getStopName <- function(stop_id, connection){
  query <- paste0("SELECT stop_name from stops WHERE stop_id = '", stop_id, "'")
  stop_name <- DBI::dbGetQuery(connection, query)$stop_name[1]
  rm(query)
  return(stop_name)
}

REASONABLE_GAP <- 2 * 60 * 60

# Get bus depot coordinates
query <- "SELECT * FROM depots"
depots <- DBI::dbGetQuery(con, query)
rm(query)

# Vector of all routes that have trips with details
query <- "SELECT DISTINCT route_id FROM trips"
routesDf <- DBI::dbGetQuery(con, query)
routesVector <- routesDf$route_id
rm(query)

# Set options digits to its usual defualt
options(digits = 7)

# Create empty data frame for aggregated block data
# Each chunk of aggregated data will be row-binded to this data frame 
blocks <- data.frame()
# Loop through for each route id
for (route in routesVector){
  print(paste0('Route ', which(routesVector %in% route), ' of ', length(routesVector)))
  # Trips 
  query <- paste0("SELECT trip_id, service_id FROM trips WHERE route_id = '", route, "'")
  tripsData <- DBI::dbGetQuery(con, query)
  rm(query)
  
  # Loop through for each service id
  serviceVector <- unique(tripsData$service_id)
  for (service in serviceVector){
    print(paste0('Service ', which(serviceVector %in% service), ' of ', length(serviceVector)))
    # Stops
    query <- paste0("SELECT t.route_id, t.trip_id, t.service_id, s.arrival_time, s.departure_time, 
    s.stop_id, s.stop_headsign, s.shape_dist_traveled, t.direction_id  
    FROM trips t LEFT JOIN stop_times s ON t.trip_id = s.trip_id WHERE t.trip_id IN (",
                    paste0(sprintf("'%s'", unique(tripsData$trip_id)), collapse = ', '), ") AND t.service_id = '", service, "'")
    stops <- DBI::dbGetQuery(con, query) %>% arrange(trip_id)
    
    if(nrow(stops) != 0){
      # Create quasi block number data based on departure time diffs
      stops$diff_time <- c(0, diff(toSeconds(stops$departure_time)))
      stops$quasi_block <- ifelse(stops$diff_time < 0, 1, 0) 
      stops$arrive_to_seconds <- toSeconds(stops$arrival_time)
      stops$depart_to_seconds <- toSeconds(stops$departure_time)
      
      bounds <- length(stops$quasi_block[stops$quasi_block == 1])
      stops$quasi_block[stops$quasi_block == 1] <- (2:(bounds + 1))
      stops$quasi_block[1] <- 1
      stops$quasi_block <- ifelse(stops$quasi_block == 0, NA, stops$quasi_block)
      stops$quasi_block <- zoo::na.locf(stops$quasi_block)
    }
    print(head(stops))
   
    stops$trip_id_order <- paste0(stops$trip_id, '_', stops$quasi_block)
    trips_bounds <- c(1, cumsum(rle(stops$trip_id_order)$lengths))
    
    for (k in 1:(length(trips_bounds) - 1)){
      if (k == 1){
        stops$trip_id_order[trips_bounds[k]:trips_bounds[k + 1]] <- paste0(stops$trip_id_order[trips_bounds[k]], '_', k)  
      } else {
        stops$trip_id_order[(trips_bounds[k] + 1):trips_bounds[k + 1]] <- paste0(stops$trip_id_order[trips_bounds[k + 1]], '_', k)  
      }
    }
    
    stops <- stops %>%
      group_by(trip_id_order) %>%
      mutate(trip_distance = max(shape_dist_traveled)) %>%
      mutate(trip_start = head(arrival_time, 1)) %>%
      mutate(trip_end = tail(departure_time, 1)) %>%
      mutate(trip_first_stop_id = head(stop_id, 1)) %>%
      #mutate(trip_first_stop_name = getStopName(head(trip_first_stop_id, 1), con)) %>%
      mutate(trip_last_stop_id = tail(stop_id, 1)) %>%
      #mutate(trip_last_stop_name = getStopName(head(trip_last_stop_id, 1), con)) %>%
      mutate(trip_total_time_s = tail(depart_to_seconds, 1) - head(arrive_to_seconds, 1)) %>%
      mutate(trip_total_time_hrs = round(trip_total_time_s / (60 * 60), 2)) %>%
      ungroup() %>%
      group_by(quasi_block) %>%
      mutate(block_start = head(arrival_time, 1)) %>%
      mutate(block_end = tail(departure_time, 1)) %>%
      mutate(block_total_time_s = tail(depart_to_seconds, 1) - head(arrive_to_seconds, 1)) %>%
      mutate(block_total_time_hrs = round(block_total_time_s / (60 * 60), 2)) %>%
      mutate(block_first_stop_id = head(stop_id, 1)) %>%
      mutate(block_first_stop_name = getStopName(head(block_first_stop_id, 1), con)) %>%
      mutate(block_last_stop_id = tail(stop_id, 1)) %>%
      mutate(block_last_stop_name = getStopName(head(block_last_stop_id, 1), con)) %>%
      select(route_id, trip_id, trip_id_order, service_id, trip_distance, trip_start, trip_end, trip_total_time_s, trip_total_time_hrs, 
             trip_first_stop_id, trip_last_stop_id, quasi_block, block_start, 
             block_end, block_total_time_s, block_total_time_hrs, block_first_stop_id, 
             block_first_stop_name, block_last_stop_id, block_last_stop_name) %>%
      unique() %>%
      mutate(trips_per_block = n()) %>%
      mutate(block_distance_m = round(sum(trip_distance), 2)) %>%
      mutate(block_distance_km = round(block_distance_m / 1000, 2)) %>%
      ungroup()
    
    blocks <- rbind(blocks, stops)
    if (which(routesVector %in% route) == 1 & which(serviceVector %in% service) == 1){
      print('Creating & writing to database table...')
      DBI::dbWriteTable(con, name = 'blocks', value = stops, overwrite = TRUE)  
    } else {
      print('Appending data to database table...')
      DBI::dbWriteTable(con, name = 'blocks', value = stops, append = TRUE)  
    }
    rm(stops)
  }
}

# Test times for block transitions
#stops <- data.frame(
#  departure_time = c('09:01:55', '19:01:55', '23:59:55', '00:05:55', '00:08:55', '09:01:55', '09:30:55', '23:59:55', '00:10:55', '09:00:55', '09:30:55')
#)



