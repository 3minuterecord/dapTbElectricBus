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

blocks <- data.frame()
for (route in routesVector){
  print(paste0(which(routesVector %in% route), ' of ', length(routesVector)))
  # Trips 
  query <- paste0("SELECT trip_id, service_id FROM trips WHERE route_id = '", route, "'")
  tripsData <- DBI::dbGetQuery(con, query)
  rm(query)

  # Stops
  query <- paste0("SELECT t.route_id, t.trip_id, t.service_id, s.arrival_time, s.departure_time, 
  s.stop_id, s.stop_headsign, s.shape_dist_traveled, t.direction_id  
  FROM trips t LEFT JOIN stop_times s ON t.trip_id = s.trip_id WHERE t.trip_id IN (",
                  # TODO --- Expand loop to include service Ids
                  paste0(sprintf("'%s'", unique(tripsData$trip_id)), collapse = ', '), ") AND t.service_id = '", unique(tripsData$service_id[1]), "'")
  stops <- DBI::dbGetQuery(con, query) %>% arrange(trip_id)
  
  if(nrow(stops) != 0){
    # Create quasi block number data based on departure time diffs
    stops$diff_time <- c(0, diff(toSeconds(stops$departure_time)))
    stops$quasi_block <- ifelse(stops$diff_time < 0, 1, 0) 
    stops$to_seconds <- toSeconds(stops$departure_time)
    # Add 24hrs to all transitions so that we can cehck for the scenario where a consecutive 
    # stops on a trip straddle midnight
    stops$mod_time <- toSeconds(stops$departure_time) + (stops$quasi_block * 24 * 60 * 60)
    stops$diff_mod <- c(0, diff(stops$mod_time))
    
    # How many of these cases are less than a reasonable gap
    # i.e., if there is greater than a couple of hrs there it is not practical to assume 
    # it is part of the same block
    checks <- sum(stops$diff_mod < REASONABLE_GAP & stops$quasi_block == 1)
    if (checks >= 1){
      # Get the index of cases where there is a short gap
      index <- which(stops$diff_mod < REASONABLE_GAP & stops$quasi_block == 1)
      # Reset the block markers to zero
      stops$quasi_block[index] <- 0
      # For each index, check the next time to see if it is reasonable to 
      # say it is connected to the block or part of a new block
      for (i in 1:checks){
        j = 1
        repeat{
          chk_i <- stops$diff_time[index[i] + j]
          if (chk_i < REASONABLE_GAP){
            j = j + 1 # It is assumed to be part of the block, check the next...
          } else {
            # When there is an unreasonable gap, mark the block transition & break...
            stops$quasi_block[index[i] + j] <- 1
            break
          } 
        }  
      }
    }
    bounds <- length(stops$quasi_block[stops$quasi_block == 1])
    stops$quasi_block[stops$quasi_block == 1] <- (2:(bounds + 1))
    stops$quasi_block[1] <- 1
    stops$quasi_block <- ifelse(stops$quasi_block == 0, NA, stops$quasi_block)
    stops$quasi_block <- zoo::na.locf(stops$quasi_block)
  }
  print(head(stops))
  stops <- stops %>%
    group_by(trip_id) %>%
    mutate(trip_distance = max(shape_dist_traveled)) %>%
    group_by(quasi_block) %>% 
    mutate(block_start = head(arrival_time, 1)) %>%
    mutate(block_end = tail(departure_time, 1)) %>%
    select(route_id, trip_id, service_id, trip_distance, quasi_block, block_start, block_end) %>%
    unique() %>%
    mutate(trips_per_block = n()) %>%
    mutate(block_distance_m = round(sum(trip_distance), 2)) %>%
    mutate(block_distance_km = round(block_distance_m / 1000, 2)) %>%
    ungroup()
  blocks <- rbind(blocks, stops)
  rm(stops)
}

# Test times for block transitions
#stops <- data.frame(
#  departure_time = c('09:01:55', '19:01:55', '23:59:55', '00:05:55', '00:08:55', '09:01:55', '09:30:55', '23:59:55', '00:10:55', '09:00:55', '09:30:55')
#)



