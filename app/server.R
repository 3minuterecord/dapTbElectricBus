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
    data <- getDbData("SELECT DISTINCT route_id FROM trips", conPool) %>% arrange(route_id)
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
  
  # Get the service_id options for the selected route
  services <- reactive({
    # Route is selected from the UI, hence use of routeCounter reactive
    selected_route <- routesVector()[routeVectorCounter$num]
    data <- getDbData(
      paste0("SELECT DISTINCT service_id FROM trips WHERE route_id = '", selected_route, "'"), 
      conPool
    ) %>% arrange(service_id)
   
    return(data$service_id)
  })
  
  stops <- reactive({
    req(input$selected_route)
    req(input$selected_service)
    query <- paste0("SELECT t.route_id, t.trip_id, t.service_id, s.arrival_time, s.departure_time, 
    s.stop_id, s.stop_headsign, s.shape_dist_traveled, t.direction_id  
    FROM trips t LEFT JOIN stop_times s ON t.trip_id = s.trip_id WHERE t.route_id = '",
    input$selected_route, "' AND t.service_id = '", input$selected_service, "'")
    
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
    query <- paste0("SELECT * FROM stop_analysis WHERE route_id = '", input$selected_route, 
                    "' AND service_id = '", input$selected_service, "' AND quasi_block = ", input$selected_block)
    data <- getDbData(query, conPool)
    return(data)
  })
  
  # Get distance data
  distanceData <- reactive({
    query <- paste0("SELECT * FROM distances WHERE route_id = '", input$selected_route, "' 
                    AND service_id = '", input$selected_service, 
                    "' AND quasi_block = ", input$selected_block)
    data <- getDbData(query, conPool)
    return(data)
  })
  
  # Get shape ids for the selected block
  shapeIds <- reactive({
    req(input$selected_block)
    if(is.null(stops())){return(NULL)}
    if(nrow(stops()) == 0){return(NULL)}
    
    trips <- stops() %>% filter(quasi_block == input$selected_block)
    query <- paste0("SELECT shape_id FROM trips WHERE trip_id IN (", 
                    paste0(sprintf("'%s'", unique(trips$trip_id)), collapse = ', '), ")")
    data <- getDbData(query, conPool)
    return(data$shape_id)
  })

  # Get shapes details for the trips associated with the selected route
  shapeData <- reactive({
    if(is.null(shapeIds())){return(NULL)}
    query <- paste0("SELECT shape_id, shape_pt_lat, shape_pt_lon, shape_pt_sequence FROM shapes WHERE shape_id IN (", 
                    paste0(sprintf("'%s'", shapeIds()), collapse = ', '), ")")
    data <- getDbData(query, conPool) %>%
      arrange(shape_pt_sequence)
    return(data)
  })
  
  deadLegShapes <- reactive({
    # Get the dead leg data
    query <- paste0("SELECT * FROM dead_leg_summary WHERE route_id = '", input$selected_route, 
                    "' AND quasi_block =", input$selected_block, " AND service_id = '", input$selected_service, "'")
    dead_legs <- getDbData(query, conPool) %>% unique()
    
    # Now the dead leg shape data
    query <- paste0("SELECT * FROM dead_leg_shapes WHERE dead_trip_unique_id IN (", 
                    paste0(sprintf("%s", unique(dead_legs$dead_leg_unique_id)), collapse = ', '), ")")
    dead_leg_shapes <- getDbData(query, conPool) %>% arrange(dead_trip_unique_id, point_order)
    
    # Now create dead leg stats for display as verbatim print output on UI
    dead_shapes_reactive$leg_stats <- dead_legs %>%
      left_join(dead_leg_shapes, by = c('dead_leg_unique_id' = 'dead_trip_unique_id')) %>%
      mutate('id' = dead_leg_unique_id) %>%
      select(id, start, end, route_id, quasi_block, distance_km, time_hrs) %>%
      unique() %>%
      mutate(distance_km = round(distance_km, 2)) %>%
      mutate(time_hrs = round(time_hrs, 2))
    return(dead_leg_shapes)
  })
  
  deadTripShapes <- reactive({
    # Get dead trip details for selected route, service & block
    deads <- stop_analysis() %>% 
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
      
      # Reduce to just shape distance and time for join with stats
      dead_routes_unique <- dead_routes %>%
        select(dead_trip_unique_id, distance_km, time_hrs) %>%
        unique()
      
      # Add to reactive to display as verbatim output
      dead_shapes_reactive$stats <- deads %>%
        left_join(dead_routes_unique, by = 'dead_trip_unique_id') %>%
        select(trip_first_stop_id, trip_last_stop_id, dead_start, dead_end, dead_time_hrs, time_hrs, distance_km) %>%
        rename('from_stop' = trip_first_stop_id) %>%
        rename('to_stop' = trip_last_stop_id) %>%
        rename('start' = dead_start) %>%
        rename('end' = dead_end) %>%
        rename('schedule_hrs' = dead_time_hrs) %>%
        rename('travel_hrs' = time_hrs)
    } else {
      dead_shapes_reactive$stats <- NULL
      dead_routes <- NULL
    }
    
    return(dead_routes)
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
        selectInput(
          'selected_service',
          'Service',
          choices = services(),
          selected = services()[1],
          width = 110
        ), style = 'display: inline-block; vertical-align: top;'
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
    if(is.null(shapeIds())){return(NULL)}
    
    req(input$selected_route)
    req(input$selected_service)
    req(input$selected_block)
    
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
    if (!is.null(deadLegShapes())){
      dead_ids <- as.integer(unique(deadLegShapes()$dead_trip_unique_id))
      
      for (id_dead in dead_ids){
        dead_df <- deadLegShapes() %>% filter(dead_trip_unique_id == id_dead)
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
    if (!is.null(deadTripShapes())){
      dead_ids <- unique(deadTripShapes()$dead_trip_unique_id)
      for (id_dead in dead_ids){
        dead_df <- deadTripShapes() %>% filter(dead_trip_unique_id == id_dead)
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
    div(
      div(plotlyOutput('distancePlot', height = 200), style = 'margin-left: 30px; margin-right: 50px;  margin-top: 20px;'),
      div(plotlyOutput('elevationPlot', height = 200), style = 'margin-left: 30px; margin-right: 50px;  margin-top: 20px;')
    )
  })
  
  # UI render for the dead trip & leg summary info
  # Just use simple verbatim output for now
  # These are quick to display & look good
  output$showDeadTripInfo <- renderUI({
    if (is.null(dead_shapes_reactive$leg_stats) & is.null(dead_shapes_reactive$stats)){
      header_text <- 'No dead trip or dead leg data...'
    } else if (is.null(dead_shapes_reactive$leg_stats) & !is.null(dead_shapes_reactive$stats)){
      'Dead Trip Details'
    } else if (!is.null(dead_shapes_reactive$leg_stats) & is.null(dead_shapes_reactive$stats)){
      'Dead Legs Details'
    } else {
      header_text <- 'Dead Trip & Dead Leg Details'  
    }
    
    div(
      div(header_text, class = 'title-header-neg'),
      div(reactableOutput("deadLegTable"), style = 'margin-right: 30px;', class = "reactBox"),
      div(reactableOutput("deadTripTable"), style = 'margin-right: 30px;', class = "reactBox")
    )
  })
  
  # Create a reactive to store dead trip & leg shape data
  # so that it can be added to the leaflet map
  dead_shapes_reactive <- reactiveValues(trips = NULL, legs = NULL, stats = NULL, leg_stats = NULL)
  
  # Create reactable table view of dead legs
  output$deadLegTable <- reactable::renderReactable({
    if(is.null(dead_shapes_reactive$leg_stats)){return(NULL)}
    data <- dead_shapes_reactive$leg_stats %>%
      select(-id, -route_id, -quasi_block)
      
    reactable(
      data,
      filterable = FALSE,
      pagination = FALSE,
      resizable = TRUE,
      bordered = TRUE,
      highlight = TRUE,
      wrap = FALSE,
      fullWidth = TRUE,
      class = "react-table",
      rowStyle = list(cursor = "pointer"),
      defaultColDef = colDef(
        headerStyle = list(background = "#f7f7f8")
      )
    )
  })
  
  # Create reactable table view of dead trips
  output$deadTripTable <- reactable::renderReactable({
    if(is.null(dead_shapes_reactive$stats)){return(NULL)}
    reactable(
      dead_shapes_reactive$stats,
      filterable = FALSE,
      pagination = FALSE,
      height = 190,
      resizable = TRUE,
      bordered = TRUE,
      highlight = TRUE,
      wrap = FALSE,
      fullWidth = TRUE,
      class = "react-table",
      rowStyle = list(cursor = "pointer"),
      defaultColDef = colDef(
        headerStyle = list(background = "#f7f7f8")
      )
    )
  })
  
  # Create a line chart of cumulative distance for the route block
  # Include dead trip & leg distances
  output$distancePlot <- renderPlotly({
    req(input$selected_block)
    
    data_plot <- distanceData() %>%
      # time was saved as BST hence adjusted to UTC
      # Add the hour back now, BST is 1 hr ahead of UTC
      # TODO --- regenerate db data with times as UTC and not BST
      mutate(time_axis = time_axis + (1*60*60)) %>%
      arrange(time_axis) %>%
      rename('distance' = distance_km)
    
    

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
    
    #Add text for the total distance traveled
    p <- p %>% add_text(
      x = max(data_plot$time_axis),
      y = max(data_plot$distance),
      mode = 'text',
      text = paste0("<b> ", round(max(data_plot$distance), 1), 'km <b>'),
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
        range = c((min(data_plot$time_axis)- (1*60*60)), max(data_plot$time_axis) + (2*60*60)),
        type = 'date',
        tickformat = "%H:%M",
        margin = list(pad = 5)
        )
    )
  })
  
  output$elevationPlot <- renderPlotly({
    req(input$selected_block)
    
    data_plot <- distanceData() %>%
      # time was saved as BST hence adjusted to UTC
      # Add the hour back now, BST is 1 hr ahead of UTC
      # TODO --- regenerate db data with times as UTC and not BST
      mutate(time_axis = time_axis + (1*60*60)) %>%
      arrange(time_axis) %>%
      rename('distance' = distance_km)
    
    
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
    
    #Add text for the total distance traveled
    p <- p %>% add_text(
      x = max(data_plot$time_axis),
      y = max(data_plot$distance),
      mode = 'text',
      text = paste0("<b> ", round(max(data_plot$distance), 1), 'km <b>'),
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
        range = c((min(data_plot$time_axis)- (1*60*60)), max(data_plot$time_axis) + (2*60*60)),
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
    req(input$selected_block)
    data <- distanceData() %>%
      select(arrival_time, departure_time, stop_headsign, stop_name, type, direction)

    # Convert direction from 1/0 to In/Out
    data$direction[data$direction == '1'] <- 'In'
    data$direction[data$direction == '0'] <- 'Out'
   
    reactable(
      data,
      filterable = FALSE,
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
        arrival_time = colDef(na = "\uFE4D"),
        departure_time = colDef(na = "\uFE4D"),
        stop_headsign = colDef(na = "\uFE4D"),
        trip_id = colDef(width = 200),
        direction = colDef(
          na = "–",
          cell = function(value) {
            # Use arrow unicodes for in/out legs
            if (is.na(value)) {
              symb = "\uFE4D" 
            } else if (value == 'Out') {
              symb = "\u2B9E"
            } else {
              symb = "\u2B9C"
            }
            symb
          },
          # change color between in and out for better visual differentiation
          style = function(value) {
            if (is.na(value)) {
              color <- "#C1C1C1"
            } else if (value == 'Out') {
              color <- "#1C2D38"
            } else if (value == 'In') {
              color <- "#C1C1C1"
            } else {
              color <- "#1C2D38"
            }
          list(fontWeight = 600, color = color)
        })
      )
    )
  })
  
  # Pull network summary data for visualization
  networkData <- reactive({
    data <- getDbData("SELECT * FROM block_summary", conPool)
    return(data)
  })
  
  # Create a reactive for holding titles and notes
  # this is used a simple way to delay the appearance of titles & notes
  # until data/charts are ready
  titlesNotes_reactive <- reactiveValues(range_plot = NULL, range_note = NULL)
  
  # Display a title for the range plot
  output$showRangePlotTitle <- renderUI({
    # Takes the reactive value, assigned after plot is ready
    title <- titlesNotes_reactive$range_plot 
    div(title, class = 'title-header')
  })
  
  # Display chart notes, again assigned after plot is ready
  output$showRangePlotNotes <- renderUI({
    notes <- titlesNotes_reactive$range_note
    div(span('*', style = 'font-weight: 900; font-size: 15px;'), notes, class = 'plot-notes')
  })
  
  # Create the range breakdown chart
  output$rangeBreakdownPlot <- renderPlotly({
    # Call the network data
    data <- networkData()
    # Create a new group field for holding the bar buckets
    data$group <- NA 
    data$group[data$block_length_km <= 96] <- 1
    data$group[data$block_length_km > 96 & data$block_length_km <= 160] <- 2
    data$group[data$block_length_km > 160 & data$block_length_km < 300] <- 3
    data$group[data$block_length_km >= 300] <- 4
    
    # Now clean & consolidate for use in plot 
    data <- data %>%
      group_by(group) %>%
      mutate(pers = round(100 * (n() / nrow(data))), 0) %>%
      select(group, pers) %>%
      unique() %>%
      arrange(group) 
    
    # Create the yaxis labels & assign factor levels so that they appear in the
    # required order
    data$labs <- c(
      '<b>Distances < 96 km<b>', 
      '<b>Distances 96 km to 160 km<b>', 
      '<b>Distances 161 km to 300 km<b>', 
      '<b>Distances > 300 km<b>'
      )
    data$labs <- factor(data$labs, levels = data$labs)
    
    # Add explainer notes to add to hover info
    data$explainer <- c(
      'feasible without en route charging.',
      'may require en route charging in winter',
      'will likely require some en route charging',
      'will require significant en route charging.'
    )
    
    p <- plot_ly(
      data,
      x = ~pers, 
      y = ~labs, 
      marker = list(color = c('#70A432', '#FFD869', '#FFBA00', '#D33D29')),
      type = 'bar', 
      orientation = 'h',
      height = 190,
      width = 800,
      hoverinfo = 'text',
      text = ~paste(paste0(round(pers, 0), '%'), explainer)
    ) %>% add_text(
        x = ~pers,
        y = ~labs,
        mode = 'text',
        text = ~paste0("<b> ", round(pers, 0), '% <b>'),
        textposition = 'right',
        textfont = list(color = '#000000', size = 12),
        hoverinfo = 'none'
    ) %>% layout(
      xaxis = list(
        title = list(test = ""),
        showticklabels = F, 
        showline = F,
        showgrid = F,
        range = c(0, min((max(data$per) + 40), 110))
        ),
      yaxis = list(title = list(test = "")),
      
      font = list(size = 11),
      autosize = F,
      margin = list(pad = 10),
      showlegend = F
    )
    
    # Now add the title and note details
    titlesNotes_reactive$range_plot <- 'Block breakdown by total distance travelled (km)'  
    titlesNotes_reactive$range_note <- 'A typical 12-m long bus with a 320-kWh 
      battery can cover up to 300 km on favourable days. But in unfavourable cold 
      conditions, the same bus may only cover between 96 km and 160 km, depending on 
      the method of heating (i.e., electric or diesel).'  
    
    # Return the final plot
    return(p)
  })
  
  # Create reactable table view of network summary
  output$networkTable <- reactable::renderReactable({
    data <- networkData() %>%
      arrange(desc(block_length_km)) %>%
      select(-start_stop_id, -last_stop_id) %>%
      mutate(block_length_km = round(block_length_km, 0))
    
    reactable(
      data,
      filterable = FALSE,
      sortable = TRUE,
      defaultPageSize = 20,
      showPageSizeOptions = TRUE,
      pageSizeOptions = c(15, 25, 50, 100, 500),
      resizable = TRUE,
      bordered = TRUE,
      highlight = TRUE,
      wrap = FALSE,
      fullWidth = TRUE,
      class = "react-table",
      rowStyle = list(cursor = "pointer"),
      defaultColDef = colDef(
        headerStyle = list(background = "#f7f7f8")
      )
    )
  })
}) 