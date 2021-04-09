source('common/db.R')

library(rjson)
library(dplyr)

# The app's database (SQL azure)
DATABASE <- "electricbus-eastus-prod-temp"
DEFAULT_SERVER <- "electricbus-temp.database.windows.net"
PORT <- 1433
USERNAME <- "teamadmin"

conPool <- getDbPool(DATABASE)

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

getStopName <- function(stop_id, connection_pool){
  con <- poolCheckout(connection_pool)
  query <- paste0("SELECT stop_name from stops WHERE stop_id = '", stop_id, "'")
  stop_name <- DBI::dbGetQuery(connection, query)$stop_name[1]
  pool::poolReturn(con)
  rm(query)
  return(stop_name)
}


# Get bus depot coordinates
depots <- getDbData("SELECT * FROM depots", conPool)


# Vector of all routes that have trips with details
routesDf <- getDbData("SELECT DISTINCT route_id FROM trips", conPool)
routesVector <- routesDf$route_id

# Set options digits to its usual defualt
options(digits = 7)

# Create empty data frame for aggregated block data
# Each chunk of aggregated data will be row-binded to this data frame 
blocks <- data.frame()

# Loop through for each route id & create quasi-block ids
# Gather aggregated block info for use in later analysis
# =======================================================

for (route in routesVector){
  print(paste0('Route ', which(routesVector %in% route), ' of ', length(routesVector)))
  # Trips 
  tripsData <- getDbData("SELECT trip_id, service_id FROM trips WHERE route_id = '", route, "'", conPool)
  
  # Loop through for each service id
  serviceVector <- unique(tripsData$service_id)
  for (service in serviceVector){
    print(paste0('Service ', which(serviceVector %in% service), ' of ', length(serviceVector)))
    # Stops
    query <- paste0("SELECT t.route_id, t.trip_id, t.service_id, s.arrival_time, s.departure_time, 
    s.stop_id, s.stop_headsign, s.shape_dist_traveled, t.direction_id  
    FROM trips t LEFT JOIN stop_times s ON t.trip_id = s.trip_id WHERE t.trip_id IN (",
                    paste0(sprintf("'%s'", unique(tripsData$trip_id)), collapse = ', '), ") AND t.service_id = '", service, "'")
    stops <- getDbData(query, conPool) %>% arrange(trip_id)
    
    if(nrow(stops) != 0){
      # Create quasi block number data based on departure time diffs
      stops$diff_time <- c(0, diff(toSeconds(stops$departure_time)))
      # Less than zero indicates a break, i.e., block end
      # The start of the next trip is behind the end of the last trip
      # Not feasible for the same bus to make the trip, new block required
      stops$quasi_block <- ifelse(stops$diff_time < 0, 1, 0)
      stops$arrive_to_seconds <- toSeconds(stops$arrival_time)
      stops$depart_to_seconds <- toSeconds(stops$departure_time)
      
      bounds <- length(stops$quasi_block[stops$quasi_block == 1])
      stops$quasi_block[stops$quasi_block == 1] <- (2:(bounds + 1))
      stops$quasi_block[1] <- 1
      # Fill zeroes with NA so we can use NA last observation carry forward from zoo 
      stops$quasi_block <- ifelse(stops$quasi_block == 0, NA, stops$quasi_block)
      stops$quasi_block <- zoo::na.locf(stops$quasi_block)
    }
    print(head(stops))
    
    # Create a trip id order field
    # This helps with grouping by trips in each block
    stops$trip_id_order <- paste0(stops$trip_id, '_', stops$quasi_block)
    trips_bounds <- c(1, cumsum(rle(stops$trip_id_order)$lengths))
    
    for (k in 1:(length(trips_bounds) - 1)){
      if (k == 1){
        stops$trip_id_order[trips_bounds[k]:trips_bounds[k + 1]] <- paste0(stops$trip_id_order[trips_bounds[k]], '_', k)  
      } else {
        stops$trip_id_order[(trips_bounds[k] + 1):trips_bounds[k + 1]] <- paste0(stops$trip_id_order[trips_bounds[k + 1]], '_', k)  
      }
    }
    
    # Create data frame of aggregated data for trip & block groupings
    stops <- stops %>%
      # By TRIP
      group_by(trip_id_order) %>%
      mutate(trip_distance = max(shape_dist_traveled)) %>%
      mutate(trip_start = head(arrival_time, 1)) %>%
      mutate(trip_end = tail(departure_time, 1)) %>%
      mutate(trip_first_stop_id = head(stop_id, 1)) %>%
      mutate(trip_last_stop_id = tail(stop_id, 1)) %>%
      mutate(trip_total_time_s = tail(depart_to_seconds, 1) - head(arrive_to_seconds, 1)) %>%
      mutate(trip_total_time_hrs = round(trip_total_time_s / (60 * 60), 2)) %>%
      ungroup() %>%
      # By BLOCK
      group_by(quasi_block) %>%
      mutate(block_start = head(arrival_time, 1)) %>%
      mutate(block_end = tail(departure_time, 1)) %>%
      mutate(block_total_time_s = tail(depart_to_seconds, 1) - head(arrive_to_seconds, 1)) %>%
      mutate(block_total_time_hrs = round(block_total_time_s / (60 * 60), 2)) %>%
      mutate(block_first_stop_id = head(stop_id, 1)) %>%
      mutate(block_first_stop_name = getStopName(head(block_first_stop_id, 1), con)) %>%
      mutate(block_last_stop_id = tail(stop_id, 1)) %>%
      mutate(block_last_stop_name = getStopName(head(block_last_stop_id, 1), con)) %>%
      # Now select the required fields
      select(route_id, trip_id, trip_id_order, service_id, trip_distance, trip_start, trip_end, trip_total_time_s, trip_total_time_hrs, 
             trip_first_stop_id, trip_last_stop_id, quasi_block, block_start, 
             block_end, block_total_time_s, block_total_time_hrs, block_first_stop_id, 
             block_first_stop_name, block_last_stop_id, block_last_stop_name) %>%
      unique() %>%
      mutate(trips_per_block = n()) %>%
      mutate(block_distance_m = round(sum(trip_distance), 2)) %>%
      mutate(block_distance_km = round(block_distance_m / 1000, 2)) %>%
      ungroup()
    # Bind to dataframe for previous route & service permutation
    blocks <- rbind(blocks, stops)
    rm(stops)
  }
}


# Trip End-Start Stop Analysis
# ============================
# Now create a data frame of rows identifying where consecutive stops in a block
# are not the same stop, i.e. where there is a dead trip.  Dead trips are where 
# the bus must drive from a stop at the end of a trip to the stop for the start 
# of the next trip in the block

routeVector <- unique(blocks$route_id)
stop_analysis_out <- data.frame()
dead_legs_out <- data.frame()
d = 1 # Counter 1
l = 1 # Counter 2
DEFAULT_DEPOT <- depots$name[3] # Simmonscourt - Assume all buses start from & return to this depot
# The depot location will be used for later fetching of dead leg route info from Azure Maps (separate Python script)

for (route in routesVector){
  print(paste0('Route ', which(routesVector %in% route), ' of ', length(routesVector)))
  # Trips 
  tripsData <- blocks %>% filter(route_id == route)
  # Loop through for each service id
  serviceVector <- unique(tripsData$service_id)
  for (service in serviceVector){
    print(paste0('Service ', which(serviceVector %in% service), ' of ', length(serviceVector)))
    serviceData <- tripsData %>% filter(service_id == service)
    block_count <- max(serviceData$quasi_block)
    for (b in sequence(block_count)){
      stop_analysis_df <- serviceData %>% filter(quasi_block == b)
      # Inter-trip dead trips 
      for (row in sequence(nrow(stop_analysis_df) - 1)){
        stop_1 <- stop_analysis_df$trip_last_stop_id[row]
        stop_2 <- stop_analysis_df$trip_first_stop_id[row + 1]  
        if (stop_1 != stop_2){
          stop_analysis_out_add <- data.frame(
            dead_trip_id = d,
            route_id = stop_analysis_df$route_id[row],
            service_id = service,
            quasi_block = b, #stop_analysis_df$quasi_block[row],
            trip_id_order_1 = stop_analysis_df$trip_id_order[row],
            trip_id_order_2 = stop_analysis_df$trip_id_order[row + 1],
            trip_first_stop_id = stop_1,
            trip_last_stop_id = stop_2,
            dead_start = stop_analysis_df$trip_end[row],
            dead_end = stop_analysis_df$trip_start[row + 1],
            dead_time_hrs = round((toSeconds(stop_analysis_df$trip_start[row + 1]) -  toSeconds(stop_analysis_df$trip_end[row])) / (60*60), 2)
          )
          d = d + 1
          stop_analysis_out <- rbind(stop_analysis_out, stop_analysis_out_add)
          rm(stop_analysis_out_add)
        }
      }
      # Also create a data frame for block to depot trips, i.e., dead legs
      # There will be two dead legs per block, one at the start > depot to first stop
      # & one at the end of the block > last stop to depot
      # Assume for now that all buses are stationed in one depote, i.e., DEFAULT_DEPOT 
      dead_legs_out_add <- data.frame(
        dead_leg_id = l,
        route_id = route,
        service_id = stop_analysis_df$service_id,
        quasi_block = b,
        start_depot = DEFAULT_DEPOT,
        block_first_stop_id =  stop_analysis_df$block_first_stop_id,
        block_last_stop_id = stop_analysis_df$block_last_stop_id,
        end_depot = DEFAULT_DEPOT  
      ) %>% unique()
      dead_legs_out <- rbind(dead_legs_out, dead_legs_out_add)
      rm(stop_analysis_df)
      l = l + 1
    }
  }
}


# Unique Dead Trips
# =================
# Get the number of unique dead trips and use this to create a 
# unique dead trip id for later referencing in Azure Maps data call
check_count_dead_trips <- stop_analysis_out %>%
  select(trip_first_stop_id, trip_last_stop_id) %>%
  unique() %>%
  mutate(dead_trip_unique_id = sequence(n()))
nrow(check_count_dead_trips)

# Add a field for this unique id to the stop_out dataframe, initialize as NA
stop_analysis_out$dead_trip_unique_id <- NA

# No loop through and assign the unique ids to the stop analysis data frame
for (row in sequence(nrow(check_count_dead_trips))){
  stop_analysis_out$dead_trip_unique_id[stop_analysis_out$trip_first_stop_id == check_count_dead_trips$trip_first_stop_id[row] & 
    stop_analysis_out$trip_last_stop_id == check_count_dead_trips$trip_last_stop_id[row]] <- check_count_dead_trips$dead_trip_unique_id[row]
}

# Check that this has been correctly applied
test <- stop_analysis_out %>%
  select(trip_first_stop_id, trip_last_stop_id, dead_trip_unique_id) %>% unique()
if (sum(test != check_count_dead_trips) == 0){
  print('Check is good, exact match with source unique list')
} else {
  print('Check is bad, not an exact match with source unique list')
}

# Unique Dead Legs
# ================
# Get the number of unique dead legs & use this to create a unique 
# dead leg id for later referencing in Azure Maps data call

dead_legs_out_1 <- dead_legs_out %>%
  rename('start' = start_depot) %>%
  rename('end' = block_first_stop_id) %>%
  select(-end_depot, - block_last_stop_id)

dead_legs_out_2 <- dead_legs_out %>%
  rename('start' = block_last_stop_id) %>%
  rename('end' = end_depot) %>%
  select(-start_depot, - block_first_stop_id)

dead_legs_out_mod <- rbind(dead_legs_out_1, dead_legs_out_2) %>%
  select(-dead_leg_id) %>%
  select(route_id, quasi_block, service_id, start, end) %>%
  unique()
  
dead_legs_out_unique <- dead_legs_out_mod %>%
  select(-route_id, -quasi_block, -service_id) %>%
  unique() %>%
  mutate(dead_leg_unique_id = sequence(n()))

# Add a field for this unique id to the stop out dataframe, initialize as NA
dead_legs_out_mod$dead_leg_unique_id <- NA

# No loop through and assign the unique ids to the dead legss data frame
for (row in sequence(nrow(dead_legs_out_unique))){
  dead_legs_out_mod$dead_leg_unique_id[dead_legs_out_mod$start == dead_legs_out_unique$start[row] & 
                                         dead_legs_out_mod$end == dead_legs_out_unique$end[row]] <- dead_legs_out_unique$dead_leg_unique_id[row]
}


# Save the stop_analysis_out data frame to the Azure SQL db 
# =========================================================
# Save data in chunks so that progress can be tracked
chunkSize <- 500 # number of rows to save in each batch
# Split the data frame into chunks of chunk size or less
chunkList <- split(stop_analysis_out, (seq(nrow(stop_analysis_out))-1) %/% chunkSize)

# Now write each data chunk to the database 
for (i in 1:length(chunkList)){
  print(paste0("Processing Batch ", i, " of ", length(chunkList)))
  if (i == 1){
    print('Creating & writing to database table...')
    DBI::dbWriteTable(con, name = 'stop_analysis', value = chunkList[[i]], overwrite = TRUE, row.names = FALSE)  
  } else {
    print('Appending data to database table...')
    DBI::dbWriteTable(con, name = 'stop_analysis', value = chunkList[[i]], append = TRUE, row.names = FALSE)  
  }
} 


# Save the aggregated blocks data frame to the data base 
# ======================================================
# use saveByChunk function from db.R
saveByChunk(
  chunk_size = 500, 
  dat = blocks, 
  table_name = 'blocks', 
  connection_pool = conPool
)

# Save the Dead Leg Data to the data base 
# =======================================
saveByChunk(
  chunk_size = 500, 
  dat = dead_legs_out_mod, 
  table_name = 'dead_leg_summary', 
  connection_pool = conPool
)
