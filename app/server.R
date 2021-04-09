source("global.R")

library(reactable)
library(tidyr)
library(dplyr)

shinyServer(function(input, output, session) {
  
  # Define the default depot location that has been used in the analysis
  # In future iterations/versions, the app could be expanded to handle more than one
  # depot location option
  # All buses are assumed to leave from and return to this depot location
  # at the end of each quasi-block
  DEFAULT_DEPOT <- 'Simmonscourt'
  
  # Create an SQL database connection pool
  conPool <- getDbPool(DATABASE)
  
  # Get bus depot coordinates
  # But current version only uses one default location
  depots <- reactive({
    data <- getDbData("SELECT * FROM depots", conPool)
    return(data)
  })
  
  # Get a vector of unique routes that have trips specified
  routesVector <- reactive({
    data <- getDbData("SELECT DISTINCT route_id FROM trips", conPool)
    return(data$route_id)
  })
  
  # Get the short name of the selected route, e.g, 16A
  routeName <- reactive({
    # Route is selected from the UI, hence use of routeCounter reactive
    selected_route <- routesVector()[routeVectorCounter$num]
    data <- getDbData(
      paste0("SELECT route_short_name FROM bus_routes WHERE route_id = '", selected_route, "'"), 
      conPool
      )
    return(data$route_short_name)
  })
  
  # Get trip details for the selected route
  tripsData <- reactive({
    selected_route <- input$selected_route
    data <- getDbData(
      paste0("SELECT trip_id, service_id FROM trips WHERE route_id = '", selected_route, "'"), 
      conPool
      )
    return(data)
  })
  
  stops <- reactive({
    req(input$selected_route)
    selected_service <- unique(tripsData()$service_id[1])
    query <- paste0("SELECT t.route_id, t.trip_id, t.service_id, s.arrival_time, s.departure_time, 
    s.stop_id, s.stop_headsign, s.shape_dist_traveled, t.direction_id  
    FROM trips t LEFT JOIN stop_times s ON t.trip_id = s.trip_id WHERE t.trip_id IN (",
    paste0(sprintf("'%s'", unique(tripsData()$trip_id)), collapse = ', '), ") AND t.service_id = '", selected_service, "'")
    
    # Important
    # =========
    # Arrange by trip_id is important so that quasi-blocking of routes is effective
    # trips need to be arranged sequentially to enable a reasonable estimate of what trips
    # are feasible (ignoring power/fuel considerations) based on timings
    # trips on the same route are feasible by the same bus if times do not overlap
    data <- getDbData(query, conPool) %>% arrange(trip_id)  
    
    if(nrow(data) != 0){
      # Create quasi block number data based on departure time diffs
      data$quasi_block <- c(0, diff(toSeconds(data$departure_time)))
      # If diff is negative, it is not possible for the same bus to complete
      # the trip, hence block assumed to terminate
      data$quasi_block <- ifelse(data$quasi_block < 0, 1, 0)
      bounds <- length(data$quasi_block[data$quasi_block == 1])
      data$quasi_block[data$quasi_block == 1] <- (2:(bounds + 1))
      data$quasi_block[1] <- 1
      # Now that block bounds have been identified, NA the infill values so
      # that we can use the na last obs carry forward function to fill with 
      # the appropriate block number
      data$quasi_block <- ifelse(data$quasi_block == 0, NA, data$quasi_block)
      data$quasi_block <- zoo::na.locf(data$quasi_block)
    }
    return(data)
  })
  
  stop_analysis <- reactive({
    req(input$selected_route)
    # Selected route and service are defined by the UI 
    selected_route <- input$selected_route
    # TODO --- implement ability to change service id, hardcoded for now
    # to first service id
    selected_service <- unique(tripsData()$service_id[1])
    query <- paste0("SELECT * FROM stop_analysis WHERE route_id = '", selected_route, "' AND service_id = '", selected_service, "'")
    data <- getDbData(query, conPool)
    return(data)
  })
  
  shapeIds <- reactive({
    req(input$selected_block)
    trips <- stops() %>% filter(quasi_block == input$selected_block)
    query <- paste0("SELECT shape_id FROM trips WHERE trip_id IN (", 
                    paste0(sprintf("'%s'", unique(trips$trip_id)), collapse = ', '), ")")
    data <- getDbData(query, conPool)
    return(data$shape_id)
  })

  # Get shapes details for the trips associated with the selected route
  shapeData <- reactive({
    query <- paste0("SELECT shape_id, shape_pt_lat, shape_pt_lon FROM shapes WHERE shape_id IN (", 
                    paste0(sprintf("'%s'", shapeIds()), collapse = ', '), ")")
    data <- getDbData(query, conPool)
    return(data)
  })
  
  # Create UI elements for selecting route to visualize
  output$showRouteSelectorControls <- renderUI({
    div(
      div(
        selectInput(
          'selected_route',
          'Route Id',
          choices = routesVector(),
          selected = routesVector()[routeVectorCounter$num],
          width = 150
        ), style = 'display: inline-block;'
      ),
      # For now, assume navigation is by route id, show (but disable) name
      div(
        shinyjs::disabled(textInput(
          'selected_route_name',
          'Name',
          value = routeName(),
          width = 90
        )), style = 'display: inline-block; vertical-align: top;'
      ),
      div(
        # TODO --- remove disable when ability to select a service is implemented
        shinyjs::disabled(textInput(
          'selected_service',
          'Service',
          value = unique(tripsData()$service_id[1]),
          width = 90
        )), style = 'display: inline-block; vertical-align: top;'
      ),
      # Create forward and back buttons for faster navigation through the list of routes
      div(
        actionButton(
          'last_route',
          'Back',
          width = 60
        ), style = 'display: inline-block; margin-left: 10px; margin-top: 26px; vertical-align: top;'
      ),
      div(
        actionButton(
          'next_route',
          'Next',
          width = 60
        ), style = 'display: inline-block; margin-left: 10px; margin-top: 26px; vertical-align: top;'
      )
    )
  })
  
  # Create UI elements for selecting quasi-block to visualize
  output$showBlockSelectorControls <- renderUI({
    if(nrow(stops()) == 0){return(NULL)}
    div(
      div(
        selectInput(
          'selected_block',
          'Block',
          choices = unique(stops()$quasi_block),
          #selected = routesVector()[routeVectorCounter$num],
          width = 100
        ), style = 'display: inline-block; margin-left: 15px;'
      ),
      # Create forward and back buttons for faster navigation through the list of routes
      div(
        actionButton(
          'last_block',
          'Back',
          width = 60
        ), style = 'display: inline-block; margin-left: 10px; margin-top: 26px; vertical-align: top;'
      ),
      div(
        actionButton(
          'next_block',
          'Next',
          width = 60
        ), style = 'display: inline-block; margin-left: 10px; margin-top: 26px; vertical-align: top;'
      )
    )
  })
  
  # Create a counter for navigating through the list of routes
  # Initialize = 1
  routeVectorCounter <- reactiveValues(num = 1)
  
  # If the drop down for routes is accessed and changes by more that a step of 1
  # Update the counter to the appropriate index
  observeEvent(input$selected_route, {
    blockVectorCounter$num <- 1
    index <- which(routesVector() == input$selected_route)
    if (abs(index - routeVectorCounter$num) != 0) {
      routeVectorCounter$num <- index  
    }
  })
  
  # If the next button is pressed, udpate the drop down selected & increase the counter by 1
  # As long as you are not at the end of the list
  observeEvent(input$next_route, {
    if (routeVectorCounter$num != length(routesVector())){
      updateSelectInput(
        'selected_route',
        'Route Id',
        choices = routesVector(),
        selected = routesVector()[routeVectorCounter$num + 1], 
        session = session
      )
      routeVectorCounter$num <- routeVectorCounter$num + 1  
    }
  })
  
  # If the back button is pressed, udpate the drop down selected & decrease the counter by 1
  # As long as you are not at the start of the list
  observeEvent(input$last_route, {
    if (routeVectorCounter$num != 1){
      updateSelectInput(
        'selected_route',
        'Route Id',
        choices = routesVector(),
        selected = routesVector()[routeVectorCounter$num - 1], 
        session = session
      )
      routeVectorCounter$num <- routeVectorCounter$num - 1  
    }
  })
  
  # Add a block counter similar to that described above for route counter
  blockVectorCounter <- reactiveValues(num = 1)
  
  observeEvent(input$selected_block, {
    index <- which(unique(stops()$quasi_block) == input$selected_block)
    if (abs(index - blockVectorCounter$num) != 0) {
      blockVectorCounter$num <- index  
    }
  })
  
  # If the next button is pressed, update the drop down selected & increase the counter by 1
  # As long as you are not at the end of the list
  observeEvent(input$next_block, {
    if (blockVectorCounter$num != length(unique(stops()$quasi_block))){
      updateSelectInput(
        'selected_block',
        'Block',
        choices = unique(stops()$quasi_block),
        selected = unique(stops()$quasi_block)[blockVectorCounter$num + 1], 
        session = session
      )
      blockVectorCounter$num <- blockVectorCounter$num + 1  
    }
  })
  
  # If the back button is pressed, udpate the drop down selected & decrease the counter by 1
  # As long as you are not at the start of the list
  observeEvent(input$last_block, {
    if (blockVectorCounter$num != 1){
      updateSelectInput(
        'selected_block',
        'Block',
        choices = unique(stops()$quasi_block),
        selected = unique(stops()$quasi_block)[blockVectorCounter$num - 1], 
        session = session
      )
      blockVectorCounter$num <- blockVectorCounter$num - 1  
    }
  })
  
  # Create a reactive value for the map CSS class so that its applictaion can be delayed 
  # until data is ready. This simply avoids the box shadow style appearing before the data
  map_class <- reactiveValues(class = NULL)
  
  # Create the Geo Map in Leaflet for the selected bus route, 
  # dead trips, legs & home depot
  output$busGeoMap <- renderLeaflet({
    if(nrow(stops()) == 0){return(NULL)}
    req(input$selected_route)
    
    outputMap <- leaflet() %>%
      addFullscreenControl(position = "topleft", pseudoFullscreen = FALSE) %>%
      # Add some different map options
      addProviderTiles("OpenStreetMap.Mapnik", group = "OpenStreetMap") %>%
      addProviderTiles("CartoDB.Positron", group = "Greyscale") %>%
      addProviderTiles("Esri.WorldImagery", group = "Satellite") %>%
      addFullscreenControl(position = "topleft", pseudoFullscreen = FALSE) %>%
      
      # Add radio buttons to toggle Pipe and Area layers.
      addLayersControl(
        # Default will be greyscale as route layouts are more visable
        baseGroups = c("Greyscale", "OpenStreetMap", "Satellite"),
        options = layersControlOptions(collapsed = TRUE)
      ) %>% addScaleBar(position = "bottomright")
    
    # Add dead leg routes as layer 1 (so they do not cover main route or dead trips)
    # Dead leg is a route from depot to/from block start/end
    if (!is.null(dead_shapes_reactive$legs)){
      dead_ids <- as.integer(unique(dead_shapes_reactive$legs$dead_trip_unique_id))
      
      for (id_dead in dead_ids){
        dead_df <- dead_shapes_reactive$legs %>% filter(dead_trip_unique_id == id_dead)
        outputMap <- outputMap %>%
          addPolylines(
            data = dead_df,
            lat = ~latitude,
            lng = ~longitude,
            label = 'Dead Leg',
            color = '#FFBA00', # Orange
            weight = 3,
            opacity = 1
          )  
      }
    }
    
    # Now add route trip shape from reactive data
    tripIds  <- unique(shapeData()$shape_id)
    # Create a counter for the loader
    j = 1
    withProgress(message = 'Loading shapes...', value = 0, {
      for (id in tripIds){
        # Show a progress loading bar in bottom right for each shape added...
        incProgress(1 / length(tripIds), detail = paste(j, " of ", length(tripIds)))
        j = j + 1 # inc the loader 
        coords <- shapeData() %>% filter(shape_id == id)
        # Trip shape plot
        outputMap <- outputMap %>%
          addPolylines(
            data = coords,
            lat = ~shape_pt_lat,
            lng = ~shape_pt_lon,
            # TODO -- decide on better label than trip as they mainly just overlap
            label = paste0('Trip-', id),
            color = '#70A432',
            weight = 2,
            opacity = 0.8
          )
      }
    })
    
    # Now add data for the dead trips
    if (!is.null(dead_shapes_reactive$trips)){
      dead_ids <- unique(dead_shapes_reactive$trips$dead_trip_unique_id)
      for (id_dead in dead_ids){
        dead_df <- dead_shapes_reactive$trips %>% filter(dead_trip_unique_id == id_dead)
        outputMap <- outputMap %>%
          addPolylines(
            data = dead_df,
            lat = ~latitude,
            lng = ~longitude,
            label = 'Dead Trip',
            color = '#D43E2A', # Red
            weight = 3,
            opacity = 1
          )  
      }
    }
    
    # Now add bus depot(s) location(s)
    depots_df <- depots() %>%
      # Assume the same depot applies to all routes
      # TODO -- Implement 'best location' depot for each route 
      filter(name == DEFAULT_DEPOT)
    
    outputMap <- outputMap %>% 
      addAwesomeMarkers(
        data = depots_df, lng = ~lon, lat = ~lat,
        label = ~name,
        icon = awesomeIcons(
          text = '',
          markerColor = '#D60000', # Red
          iconColor = 'white'
        )
      ) 
    
    # Add a legend to the map
    outputMap <- outputMap %>% 
      addLegend(
        "bottomleft", 
        colors = c('#70A432', '#D43E2A', '#FFBA00'), 
        labels = c('Route', 'Dead Trip', 'Dead Leg'),
        title = NULL,
        opacity = 1
      )
    
    # Apply the shadow box (div) stying at the end
    map_class$class <- 'map-box'
    return(outputMap)
  })
  
  # UI render for the main bus geo map
  output$showMainBusMap <- renderUI({
    req(input$selected_route)
    req(shapeData())
    req(input$selected_block)
    div(leafletOutput("busGeoMap"), class = map_class$class)
  })
  
  # UI render for the distance plot
  output$showRoutePlots <- renderUI({
    div(plotlyOutput('distancePlot', height = 200), style = 'margin-left: 30px; margin-right: 50px;  margin-top: 20px;')
  })
  
  # UI render for the dead trip & leg summary info
  # Just use simple verbatim output for now
  # These are quick to display & look good
  output$showDeadTripInfo <- renderUI({
    div(
      div('Dead Trips & Legs', class = 'title-header'),
      div(verbatimTextOutput('deadLegTable'), style = 'margin: 20px; margin-left: 40px; margin-right: 72px;'),
      div(verbatimTextOutput('deadTripTable'), style = 'margin: 20px; margin-left: 40px; margin-right: 72px;')
    )
  })
  
  # Create a reactive to store dead trip & leg shape data
  # so that it can be added to the leaflet map
  dead_shapes_reactive <- reactiveValues(trips = NULL, legs = NULL, stats = NULL)
  
  # Use render print to display the data frames as verbatim output
  output$deadLegTable <- renderPrint({
    if (is.null(dead_shapes_reactive$legs)){
      'No dead leg data...'
    } else {
      dead_shapes_reactive$leg_stats  
    }
  })
  
  output$deadTripTable <- renderPrint({
    if (is.null(dead_shapes_reactive$stats)){
      'No dead trip data...'
    } else {
      dead_shapes_reactive$stats  
    }
  })
  
  # Create a line chart of cumulative distance for the route block
  # Include dead trip & leg distances
  output$distancePlot <- renderPlotly({
    req(input$selected_block)
    data <- stops() %>% filter(quasi_block == input$selected_block)  
    
    # Prep data for time and distance modifications
    # Some times could be greater than 24 hrs, e.g., 25:10:30
    # Only times are provided, but days are required for (easier) plotting
    # We need to add dead leg & trip distances to route distances & re-calc cumulative distance
    data <- data %>%
      mutate(time_secs = toSeconds(departure_time)) %>%
      mutate(distance = shape_dist_traveled) %>%
      mutate(type = 'route') %>%
      mutate(time_axis = departure_time)
    
    # Handling for times greater than 24 hrs, e.g., 28:30:00
    data$day_flag <- 1
    data$day_flag[data$time_secs > (1 * 24 * 60 * 60)] <- 2 # change flag for days greater than 24 hrs
    data$day_flag[data$time_secs > (2 * 24 * 60 * 60)] <- 3 # change flag for days greater than 48 hrs
    
    # Use regular expression to select & modify times/hrs greater than 2
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
      mutate(time_axis = as.POSIXct(paste0('2021-03-0', day_flag, ' ', departure_time), format = "%Y-%M-%d %H:%M:%S"))  
    
    # Distances are cumulatve, so get diff so we can calc a new 
    # cumulative distance that includes dead trip & leg distances
    data$distance <- c(0, diff(data$distance))
    # This will produce negative values at trip edges, put this to zero
    data$distance[data$distance < 0] <- 0
    
    # Get dead trip details for selected route, service & block
    deads <- stop_analysis() %>% 
      filter(quasi_block == input$selected_block) %>%
      mutate(dead_trip_id = as.integer(dead_trip_id)) %>%
      mutate(dead_trip_unique_id = as.integer(dead_trip_unique_id))
    
    # If dead trip data exists, get the associated shape data
    # Arrange by point order to ensure the route is correctly defined
    if (nrow(deads) != 0){
      query <- paste0("SELECT * FROM dead_trip_shapes WHERE dead_trip_unique_id IN (", 
                      paste0(sprintf("'%s'", unique(deads$dead_trip_unique_id)), collapse = ', '), ")")
      dead_routes <- getDbData(query, conPool) %>% 
        mutate(dead_trip_unique_id = as.integer(dead_trip_unique_id)) %>%
        arrange(point_order)
      
      # Write the shape data for the dead routes to the reactive so that they 
      # will appear on the route leaflet map
      dead_shapes_reactive$trips <- dead_routes
      
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
      
      # Perform some cleaning on the stats file for presentation as
      # verbatim print output on UI
      dead_shapes_reactive$stats <- dead_routes_stats %>% 
        rename(id = dead_trip_unique_id) %>%
        rename(from_stop = trip_first_stop_id) %>%
        rename(to_stop = trip_last_stop_id) %>%
        rename(start = dead_start) %>%
        rename(scheduled_time = dead_time_hrs) %>%
        mutate(time_hrs = round(time_hrs, 2)) 
      
      # Now we need to add in the dead trip distances to our distance data
      # Add 1 to indices as distance travelled is at available at the end of the trip
      inds <- which(data$arrival_time %in% dead_routes_stats$dead_start) + 1
      data$distance[inds] <- (dead_routes_stats$distance_km * 1000) # Convert from km to m for consistency
      data$type[inds] <- 'dead'
    } else {
      dead_shapes_reactive$trips <- NULL
      dead_shapes_reactive$stats <- NULL
    }
    
    # Now get the dead leg data
    # TODO --- Impement ability to change between service ids
    selected_service <- unique(tripsData()$service_id[1])
    query <- paste0("SELECT * FROM dead_leg_summary WHERE route_id = '", input$selected_route, 
                    "' AND quasi_block =", input$selected_block, " AND service_id = '", selected_service, "'")
    dead_legs <- getDbData(query, conPool) %>% unique()
    
    # Now the dead leg shape data
    query <- paste0("SELECT * FROM dead_leg_shapes WHERE dead_trip_unique_id IN (", 
                    paste0(sprintf("%s", unique(dead_legs$dead_leg_unique_id)), collapse = ', '), ")")
    dead_leg_shapes <- getDbData(query, conPool) %>% arrange(dead_trip_unique_id, point_order)
    
    # Write the shape data to the reactive so they will be added to the geo map
    dead_shapes_reactive$legs <- dead_leg_shapes
    
    # Now create dead leg stats for display as verbatim print output on UI
    dead_shapes_reactive$leg_stats <- dead_legs %>%
      left_join(dead_leg_shapes, by = c('dead_leg_unique_id' = 'dead_trip_unique_id')) %>%
      mutate('id' = dead_leg_unique_id) %>%
      select(id, start, end, route_id, quasi_block, distance_km, time_hrs) %>%
      unique() %>%
      mutate(distance_km = round(distance_km, 2)) %>%
      mutate(time_hrs = round(time_hrs, 2))
    
    # Now we need to add the dead leg distances to our distance vector (for plotting)
    legs_df <- dead_shapes_reactive$leg_stats
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
    data_plot <- data.frame(
      distance = distance_vec,
      time_axis = time_vec
    )
    
    # Now create the plot using Plotly
    p <- plot_ly(
      data_plot, 
      x = ~time_axis, 
      y = ~distance, 
      type = 'scatter', 
      mode = 'lines',
      height = 230, 
      name = 'Distance',
      line = list(color = '#1C2D38'),
      hoverinfo = 'text', 
      text = ~paste0(round(distance, 1), " km @ ", format(time_axis, '%H:%M'))
      )
    
    # Add text for the total distance travelled
    p <- p %>% add_text(
      x = ~max(time_axis),
      y = ~max(distance),
      mode = 'lines + text',
      text = ~paste0("<b> ", round(max(distance), 1), 'km <b>'),
      textposition = 'right',
      textfont = list(color = '#000000', size = 13)
    )
    
    # Add some final layout mods
    p <- p %>% layout(
      title = "",
      yaxis = list(title = list(text = '<b>Distance (km)</b>',  standoff = 20L),
      rangemode = "nonnegative"),
      showlegend = FALSE,
      font = list(size = 11),
      xaxis = list(
        title = '',
        range = ~c(min(time_axis), max(time_axis) + (2*60*60)),
        type = 'date',
        tickformat = "%H:%M",
        margin = list(pad = 5)
        )
    )
  })
  
  # Show the reactable table view of trips for selected route
  output$showTripTable <- renderUI({
    div(reactableOutput("tripTable"), class = "reactBox")
  })
  
  # Create reactable table view of trips for selected route
  output$tripTable <- reactable::renderReactable({
    if(nrow(stops()) == 0){
      data <- stops() %>% mutate(quasi_block = '')  
    } else {
      req(input$selected_block)
      data <- stops() %>% filter(quasi_block == input$selected_block)  
    }
    
    data <- data %>%
      select(-route_id, -service_id, -shape_dist_traveled, -quasi_block) %>%
      rename('direction' = direction_id)
    
    # Convert direction from 1/0 to In/Out
    data$direction[data$direction == '1'] <- 'In'
    data$direction[data$direction == '0'] <- 'Out'
    
    reactable(
      data,
      filterable = FALSE,
      searchable = TRUE,
      defaultPageSize = 1000,
      pagination = FALSE,
      height = 330,
      resizable = TRUE,
      bordered = TRUE,
      highlight = TRUE,
      wrap = FALSE,
      fullWidth = TRUE,
      class = "react-table",
      rowStyle = list(cursor = "pointer"),
      defaultColDef = colDef(
        headerStyle = list(background = "#f7f7f8")
      ),
      columns = list(
        trip_id = colDef(width = 200),
        direction = colDef(
          cell = function(value) {
            # Use arrow unicodes for in/out legs
            if (value == 'Out') "\u2B9E" else "\u2B9C"
          },
          # change color between in and out for better visual differentiation
          style = function(value) {
            if (value == 'Out') {
              color <- "#1C2D38"
            } else if (value == 'In') {
              color <- "#C1C1C1"
            }
          list(fontWeight = 600, color = color)
        })
      )
    )
  })
}) 