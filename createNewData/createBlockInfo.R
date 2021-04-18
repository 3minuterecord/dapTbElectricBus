# Load common functions
source('common/db.R')

library(rjson)
library(dplyr)

# The app's database (SQL azure)
DATABASE <- "electricbus-eastus-prod"
DEFAULT_SERVER <- "electricbus.database.windows.net"
PORT <- 1433
USERNAME <- "teamadmin"
# Database password is in local json configs file

# Create database connection pool
conPool <- getDbPool(DATABASE)

# Function for converting time in string H:M:S format to numeric seconds
toSeconds <- function(x){
  if (!is.character(x)) stop("x must be a character string of the form H:M:S")
  if (length(x) <= 0) return(x)
  
  # converts to num vec, i.e., 20 10 10, and check length 
  vec <- as.numeric(strsplit(x, ':', fixed = TRUE)[[1]]) 
  if (length(vec) == 3) {
    hrs = vec[1] 
    min = vec[2]
    sec = vec[3]
    if (min > 59 | sec > 59) stop("Mins & secs must be less than 60")
    secs <- (hrs * 3600 + min * 60 + sec)
    return(secs)
  } else if (length(vec) == 2) { # mins & secs 
    min = vec[2]
    sec = vec[3]
    if (min > 59 | sec > 59) stop("Mins & secs must be less than 60")
    secs <- (min * 60 + sec)
    return(secs)
  } else if (length(vec) == 1) {
    sec = vec[1]
    if (sec > 59) stop("secs must be less than 60")
    secs <- sec  # secs only
    return(secs)
  } 
} 

# Get bus depot coordinates
depots <- getDbData("SELECT * FROM depots", conPool)

# Get stop names
stop_names <- getDbData("SELECT stop_id, stop_name FROM stops", conPool)

# Datframe of all routes that have trips with details
routesDf <- getDbData("SELECT DISTINCT route_id FROM trips", conPool)

# Set options digits to its usual defualt
options(digits = 7)

# Create empty data frame for aggregated block data
# Each chunk of aggregated data will be row-binded to this data frame 
blocks <- data.frame()


# Loop through for each route id & create quasi-block ids
# Gather aggregated block info for use in later analysis
# =======================================================

# NOTE: A block is a collection of trips undertaken by a single bus and driver 
# before going back to the depot. We are not provided this in the Dublin Bus GTFS
# hence we must base it on a practical assessment of trip times, i.e., is it 
# feasible for the same bus to make the next scheduled trip on the route?

routesVector <- routesDf$route_id
for (route in routesVector){
  print(paste0('Route ', which(routesVector %in% route), ' of ', length(routesVector)))
  
  # Trips 
  tripsData <- getDbData(paste0("SELECT trip_id, service_id FROM trips WHERE route_id = '", route, "'"), conPool)
  
  # Service Ids
  serviceVector <- unique(tripsData$service_id)
  # Loop through for each service id
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
      mutate(block_first_stop_name = getStopName(head(block_first_stop_id, 1), conPool)) %>%
      mutate(block_last_stop_id = tail(stop_id, 1)) %>%
      mutate(block_last_stop_name = getStopName(head(block_last_stop_id, 1), conPool)) %>%
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
#
# DEAD TRIPS
# ----------
# Now create a data frame of rows identifying where consecutive stops in a block
# are not the same stop, i.e. where there is a DEAD TRIP.  Dead trips are where 
# the bus must drive from a stop at the end of a trip to the stop for the start 
# of the next trip in the block. We will use this later for getting the route 
# information from Azure Maps (see ingestNonGtfs.py, Python script).
#
# DEAD LEGS
# ---------
# In the same analysis, define DEAD LEGs, i.e., the trips that the bus will
# need to make from depot to start of block and from end of block to depot when
# the shift is finished.  We will use this later for getting the route information
# from Azure Maps (see ingestNonGtfs.py, Python script).

routeVector <- unique(blocks$route_id)
stop_analysis_out <- data.frame()
dead_legs_out <- data.frame()
d = 1 # Counter 1
l = 1 # Counter 2
DEFAULT_DEPOT <- depots$name[3] # Simmonscourt - Assume all buses start from & 
# return to this depot. The depot location will be used for later fetching of 
# dead leg route info from Azure Maps (separate Python script)

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
    # Now loop through each block
    for (b in sequence(block_count)){
      stop_analysis_df <- serviceData %>% filter(quasi_block == b)
      # Inter-trip dead trips 
      for (row in sequence(nrow(stop_analysis_df) - 1)){
        stop_1 <- stop_analysis_df$trip_last_stop_id[row]
        stop_2 <- stop_analysis_df$trip_first_stop_id[row + 1]  
        if (stop_1 != stop_2){ # it it's not the same stop, record the dead trip
          stop_analysis_out_add <- data.frame(
            dead_trip_id = d,
            route_id = stop_analysis_df$route_id[row],
            service_id = service,
            quasi_block = b, 
            trip_id_order_1 = stop_analysis_df$trip_id_order[row],
            trip_id_order_2 = stop_analysis_df$trip_id_order[row + 1],
            trip_first_stop_id = stop_1,
            trip_last_stop_id = stop_2,
            dead_start = stop_analysis_df$trip_end[row],
            dead_end = stop_analysis_df$trip_start[row + 1],
            dead_time_hrs = round((toSeconds(stop_analysis_df$trip_start[row + 1]) -  
                                     toSeconds(stop_analysis_df$trip_end[row])) / (60*60), 2)
          )
          d = d + 1
          stop_analysis_out <- rbind(stop_analysis_out, stop_analysis_out_add)
          rm(stop_analysis_out_add)
        }
      }
      # Now create the DEAD LEG data frame for block to depot trips, i.e., dead legs
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
# dead leg id for later referencing in Azure Maps data call.
# Also reshape the dead leg dataframe for easier processing.

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

# Now loop through and assign the unique ids to the dead legs data frame
for (row in sequence(nrow(dead_legs_out_unique))){
  dead_legs_out_mod$dead_leg_unique_id[dead_legs_out_mod$start == dead_legs_out_unique$start[row] & 
                                         dead_legs_out_mod$end == dead_legs_out_unique$end[row]] <- dead_legs_out_unique$dead_leg_unique_id[row]
}


# Summary Table & Distance vs Time Plot Data
# ==========================================
# Create main block summary table with distances for visualization in
# the Shiny app.  This data will also be used for the main Distance vs Time plot
# This wranlging could be done in the backend of the application but for the 
# this project, in order to reduce the complexity of in-app wrangling, it 
# is done here and output is saved to the Azure SQL db linked ot the app

ind = 0
slice_length = 20
slice <- c(1, slice_length)
repeat{
  if (slice[2] == length(routeVector)) {break}
  if (ind != 0) {
    slice <- slice + slice_length
  } 
  if(slice[2] > length(routeVector)){
    slice[2] <- length(routeVector)
  }
  print(paste0('Processing slice ', slice[1], ' to ', slice[2]))
  routesVectorSlice <- routesVector[slice[1]:slice[2]]
  data_plot <- data.frame()
  for (route in routesVectorSlice){
    print(paste0('Route ', which(routesVector %in% route), ' of ', length(routesVector)))
    # Trips
    tripsData <- getDbData(paste0("SELECT trip_id, service_id FROM trips WHERE route_id = '", route, "'"), conPool)
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
        stops$quasi_block <- c(0, diff(toSeconds(stops$departure_time)))
        # If diff is negative, it is not possible for the same bus to complete
        # the trip, hence block assumed to terminate
        stops$quasi_block <- ifelse(stops$quasi_block < 0, 1, 0)
        bounds <- length(stops$quasi_block[stops$quasi_block == 1])
        stops$quasi_block[stops$quasi_block == 1] <- (2:(bounds + 1))
        stops$quasi_block[1] <- 1
        # Now that block bounds have been identified, NA the infill values so
        # that we can use the na last obs carry forward function to fill with
        # the appropriate block number
        stops$quasi_block <- ifelse(stops$quasi_block == 0, NA, stops$quasi_block)
        stops$quasi_block <- zoo::na.locf(stops$quasi_block)
      }
      blockVector <- sort(unique(stops$quasi_block))
      for (block in blockVector){
        print(paste0('Block ', which(blockVector %in% block), ' of ', length(blockVector)))
        # Blocks
        data <- stops %>% filter(quasi_block == block)

        # Prep data for time and distance modifications
        # Some times could be greater than 24 hrs, e.g., 25:10:30
        # Only times are provided, but days are required for (easier) plotting
        # We need to add dead leg & trip distances to route distances & re-calc cumulative distance
        data <- data %>%
          mutate(time_secs = toSeconds(departure_time)) %>%
          mutate(distance = shape_dist_traveled) %>%
          mutate(time_axis = departure_time)

        # Handling for times greater than 24 hrs, e.g., 28:30:00
        # Start by giving all days a flag of 1 (first day)
        data$day_flag <- 1
        # Use regular expression to identify locations of times greater than 24 hr
        high_times_loc <- grepl("^[2-9][4-9]:", data$departure_time)
        # If there are times greater than 24 hrs, assign a new day flag, e.g., 2, 3, 4, n days
        if (sum(high_times_loc) != 0){
          high_times <- data$departure_time[high_times_loc]
          high_times_hrs <- as.integer(substr(high_times, 1, 2))
          day_count <- ceiling(max(high_times_hrs)) # round up to nearest day
          # Iterate & add day flags
          for (days in sequence(day_count)){
            data$day_flag[data$time_secs > (days * 24 * 60 * 60)] <- (days + 1) # change flag for days greater than days x 24 hrs
          }
        }

        # Now that day flags/markers are in place, we can re-base the hours
        # e.g., convert 24:30:30 to 00:30:30
        # Use regular expression to select & modify times/hrs greater than 24
        mod_times <- c()
        for (time in data$departure_time[grepl("^2[4-9]:", data$departure_time)]){
          hr <- as.integer(substr(time, 1, 2))
          hr <- hr - 24 # Rebase to 00
          mod_times <- append(mod_times, gsub("^2[4-9]:", paste0(sprintf("%02d", hr), ':'), time))
        }
        # Now apply replace old times with mod times
        data$departure_time[grepl("^2[4-9]:", data$departure_time)] <- mod_times

        # Convert times to dummay day-time format for plot visualization
        data <- data %>%
          mutate(
            time_axis = as.POSIXct(
              paste0('2021-01-0', day_flag, ' ', departure_time), 
              format = "%Y-%m-%d %H:%M:%S", tz = 'UTC'
              ) 
            )

        # Distances are cumulative, so get diff so we can calc a new
        # cumulative distance that includes dead trip & leg distances
        data$distance <- c(0, diff(data$distance))
        # This will produce negative values at trip edges, put this to zero
        data$distance[data$distance < 0] <- 0

        # Create a file called type for easier filtering of data between route,
        # dead trip & dead leg
        data$type <- 'route'

        # Grab stop analysis output
        stop_analysis <- stop_analysis_out %>%
          filter(route_id == route & service_id == service)

        # Get dead trip details for selected route, service & block
        deads <- stop_analysis %>%
          filter(quasi_block == block) %>%
          mutate(dead_trip_id = as.integer(dead_trip_id)) %>%
          mutate(dead_trip_unique_id = as.integer(dead_trip_unique_id))

        if (nrow(deads) != 0){
          query <- paste0("SELECT DISTINCT dead_trip_unique_id, distance_km, time_hrs FROM dead_trip_shapes WHERE dead_trip_unique_id IN (",
                            paste0(sprintf("'%s'", unique(deads$dead_trip_unique_id)), collapse = ', '), ")")
          dead_routes <- getDbData(query, conPool) %>% mutate(dead_trip_unique_id = as.integer(dead_trip_unique_id))

          # Calculate the distance stats & join with stop analysis data for
          # dead_start time so indices where dead route distyances can be derived
          dead_routes_stats <- dead_routes %>%
            select(dead_trip_unique_id, distance_km, time_hrs) %>%
            unique() %>%
            left_join(deads, by = 'dead_trip_unique_id') %>%
            select(dead_trip_unique_id, trip_first_stop_id, trip_last_stop_id, dead_start, distance_km, time_hrs, dead_time_hrs) %>%
            # Ensure time order is correct for later insertion by index
            mutate(dead_start_secs = toSeconds(dead_start)) %>%
            arrange(dead_start_secs) %>%
            select(-dead_start_secs)

          # Now we need to add in the dead trip distances to our distance data
          # Add 1 to indices as distance travelled is at available at the end of the trip
          inds <- which(data$arrival_time %in% dead_routes_stats$dead_start) + 1
          data$distance[inds] <- (dead_routes_stats$distance_km * 1000) # Convert from km to m for consistency
          # Warning messages:
          # 1: In data$distance[inds] <- (dead_routes_stats$distance_km * 1000) :
          # number of items to replace is not a multiple of replacement length
          # Tag as dead trips
          data$type[inds] <- 'dead trip'
        }

        # Now get the dead leg data
        query <- paste0("SELECT * FROM dead_leg_summary WHERE route_id = '", route,
                        "' AND quasi_block =", block, " AND service_id = '", service, "'")
        dead_legs <- getDbData(query, conPool) %>% unique()

        # Now the dead leg distance & time data
        query <- paste0("SELECT DISTINCT dead_trip_unique_id, distance_km, time_hrs FROM dead_leg_shapes WHERE dead_trip_unique_id IN (",
                        paste0(sprintf("%s", unique(dead_legs$dead_leg_unique_id)), collapse = ', '), ")")
        dead_leg_shapes <- getDbData(query, conPool)

        # Now create dead leg stats for display as verbatim print output on UI
        legs_df <- dead_legs %>%
          left_join(dead_leg_shapes, by = c('dead_leg_unique_id' = 'dead_trip_unique_id')) %>%
          mutate('id' = dead_leg_unique_id) %>%
          select(id, start, end, route_id, quasi_block, distance_km, time_hrs) %>%
          unique() %>%
          mutate(distance_km = round(distance_km, 2)) %>%
          mutate(time_hrs = round(time_hrs, 2))

        # Now we need to add the dead leg distances to our distance vector (for plotting)
        distance_vec <- c(0, legs_df$distance_km[legs_df$start == DEFAULT_DEPOT] * 1000,
                          tail(data$distance, (length(data$distance) - 1)),
                          legs_df$distance_km[legs_df$start != DEFAULT_DEPOT] * 1000)

        # we now have all the distance data (route, dead trips & dead legs)
        # Get the cumulative sum of distance & convert back to km
        distance_vec <- cumsum(distance_vec) / 1000

        # We now need a new time vector for the x-axis of our plot
        # Bus will start at first stop time minus depot to start drive time
        new_start <- head(data$time_axis, 1) - (legs_df$time_hrs[legs_df$start == DEFAULT_DEPOT] * 60 * 60)
        # Bus will end at last stop time plus last stop to depot drive time
        new_end <- tail(data$time_axis, 1) + (legs_df$time_hrs[legs_df$start != DEFAULT_DEPOT] * 60 * 60)
        time_vec <- c(new_start, data$time_axis, new_end)

        # Create a simple data frame for plotting
        data_plot_add <- data.frame(
          route_id = rep(route, length(distance_vec)),
          service_id = rep(service, length(distance_vec)),
          quasi_block = rep(block, length(distance_vec)),
          trip_id = c(NA, data$trip_id, NA),
          arrival_time = c(NA, data$arrival_time, format(tail(time_vec, 1), format = "%H:%M:%S")),
          departure_time = c(format(head(time_vec, 1), format = "%H:%M:%S"), data$departure_time, NA),
          stop = c(DEFAULT_DEPOT, data$stop_id, DEFAULT_DEPOT),
          stop_headsign = c(NA, data$stop_headsign, NA),
          distance_km = distance_vec,
          time_axis = time_vec,
          direction = c(NA, data$direction_id, NA),
          type = c('dead leg', data$type, 'dead leg')
        )
        # Now add stop names
        data_plot_add <- data_plot_add %>%
          left_join(stop_names, by = c('stop' = 'stop_id'))
        # Add depot name as stop name for start and end
        data_plot_add$stop_name[c(1, nrow(data_plot_add))] <- DEFAULT_DEPOT
        # Bind with previous & move to next
        data_plot <- rbind(data_plot, data_plot_add)
      }
    }
  }
  ind <- ifelse(ind == 0, TRUE, FALSE)
  # Save the plot_out data frame to the Azure SQL db 
  print('Saving data to database...')
  saveByChunk(
    chunk_size = 5000,
    dat = data_plot,
    table_name = 'distances',
    connection_pool = conPool,
    replace = mode
  )
  if(ind == 0) ind <- ind + 1
}


# Save the stop_analysis_out data frame to the Azure SQL db 
# =========================================================
# use saveByChunk function from db.R
saveByChunk(
  chunk_size = 500, 
  dat = stop_analysis_out, 
  table_name = 'stop_analysis', 
  connection_pool = conPool,
  replace = TRUE
)


# Save the aggregated blocks data frame to the data base 
# ======================================================
# use saveByChunk function from db.R
saveByChunk(
  chunk_size = 500, 
  dat = blocks, 
  table_name = 'blocks', 
  connection_pool = conPool,
  replace = TRUE
)

# Save the Dead Leg Data to the data base 
# =======================================
# use saveByChunk function from db.R
saveByChunk(
  chunk_size = 500, 
  dat = dead_legs_out_mod, 
  table_name = 'dead_leg_summary', 
  connection_pool = conPool,
  replace = TRUE
)
