# Create blocks & identify dead trips & legs
# ==========================================

# Fetch command line arguments
myArgs <- commandArgs(trailingOnly = TRUE)

# Extract args
# - Define the root folder where the repo has been downloaded to
# - Use test or prod database
root_folder <- as.character(myArgs[1]) # 'C:/MyApps'
db_env <- myArgs[3] # test or prod

# Set the working directory
setwd(paste0(root_folder, '/dapTbElectricDublinBus/_pipeline'))

# Load common functions & libraries
library(rjson)
source('functions.R')
library(lubridate)
library(dplyr)

# Get DB connection details (SQL azure) 
# =====================================
# TODO --- Wrap in tryCatch
KEYS_FILE_NAME <- 'keys.json'
CONS_FILE_NAME <- 'connection_names.json'
DATABASE <- paste0(fromJSON(file = CONS_FILE_NAME)$sql_database, db_env)
DEFAULT_SERVER <- gsub('tcp:', '', fromJSON(file = CONS_FILE_NAME)$sql_server)
PORT <- fromJSON(file = CONS_FILE_NAME)$sql_port
USERNAME <- fromJSON(file = CONS_FILE_NAME)$sql_user
passwordDb_config <- fromJSON(file = KEYS_FILE_NAME)

# Load data
temps <- read.csv("hly532.csv", stringsAsFactors = F, skip = 23) 

# Convert date to datetime format
temps$datetime <- as.POSIXct(temps$date, format = "%d-%b-%Y %H:%M", tz = 'UTC')

# Create week number
temps$week <- lubridate::isoweek(temps$datetime)

# Create hour column
temps$hr <- lubridate::hour(temps$datetime)

# Reduce to column of interest
data <- temps %>%
  select(datetime, week, hr, temp)

# Use t-distribution as this is a sample of population
T_CRIT = 1.97 # df > 200, aplha two-sided = 0.05 (95% confidence)

# Create a data frame to hold the stat data
temperature_stats <- data.frame()

# Loop through each week and hr and gather key temp stats
# min, max, mean and 95% CI (for the mean)
for (week in sequence(53)){
  for (hr in 0:23) {
    select_week = week
    select_hr = hr
    
    data_week_hr <- data %>%
      filter(week == select_week, hr == select_hr)
    
    sample_temp <- data_week_hr$temp
    n <- length(sample_temp)
    sample_sd <- sd(sample_temp, na.rm = TRUE)
    sample_mean <- mean(sample_temp, na.rm = TRUE)
    t_crit <- T_CRIT 
    sample_se <- sample_sd / sqrt(n)
    CI_lower <- sample_mean - (t_crit * sample_se) # Confidence intervals for the mean
    CI_upper <- sample_mean + (t_crit * sample_se)
    
    # Sampling with replacement
    # Comparison with central limit approach
    # N = 10000
    # sample_temp_rep_means <- c()
    # for (nN in sequence(N)){
    #   sample_temp_rep <- sample(sample_temp, replace = TRUE)  
    #   sample_temp_rep_means <- append(sample_temp_rep_means, mean(sample_temp_rep, na.rm = TRUE))
    # }
    # sample_temp_rep_mean <- mean(sample_temp_rep_means, na.rm = TRUE)
    # sample_temp_rep_sd <- sd(sample_temp_rep_means, na.rm = TRUE)
    # sample_temp_rep_lo <- sample_temp_rep_mean - (1.97 * sample_temp_rep_sd)
    # sample_temp_rep_hi <- sample_temp_rep_mean + (1.97 * sample_temp_rep_sd)
    
    temperature_stats_add <- data.frame(
      week = select_week,
      hr = select_hr,
      min_degC = min(sample_temp),
      #min_degC_cl = round(sample_temp_rep_lo, 2),
      ci_lower_degC = round(CI_lower, 2),
      mean_degC = round(sample_mean, 2),
      ci_upper_degC = round(CI_upper, 2),
      #max_degC_cl = round(sample_temp_rep_hi, 2),
      max_degC = max(sample_temp)
    )
    temperature_stats <- rbind(temperature_stats, temperature_stats_add)
  }
}

# Create database connection pool
conPool <- getDbPool(DATABASE)

saveByChunk(
  chunk_size = 5000, 
  dat = temperature_stats, 
  table_name = 'temperature_stats', 
  connection_pool = conPool,
  replace = TRUE
)


