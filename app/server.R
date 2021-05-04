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
  
  # Define reactives for storing data after get data action button is pressed
  shapeData <- reactiveValues(shapes = NULL) # This is for standard trips
  deadShapes <- reactiveValues(trips = NULL, legs = NULL) # Dead journyes
  shapeIdsReactive <- reactiveValues() # shape Ids for standard trips
  distanceData <- reactiveValues(data = NULL) # for distance plot info
  elevationData <- reactiveValues(elevation = NULL)
  stops_reactive <- reactiveValues(stops = NULL)
  
  # Create a reactive value for the map CSS class so that its applictaion can be delayed 
  # until data is ready. This simply avoids the box shadow style appearing before the data
  map_class <- reactiveValues(class = NULL)
  
  # Get bus depot coordinates
  # But current version only uses one default location
  depots <- reactive({
    data <- getDbData("SELECT * FROM depots", conPool)
    return(data)
  })
  
  # Get a vector of unique routes that have trips specified
  routesVector <- reactive({
    data <- getDbData("SELECT DISTINCT route_id FROM blocks", conPool) %>% arrange(route_id)
    return(data$route_id)
  })
  
  # Get the short name of the selected route, e.g, 16A
  getRouteName <- function(route) {
    # Route is selected from the UI, hence use of routeCounter reactive
    data <- getDbData(
      paste0("SELECT route_short_name FROM bus_routes WHERE route_id = '", route, "'"), 
      conPool
    )
    return(data$route_short_name[1])
  }
  
  # Get the service_id options for the selected route
  getServices <- function (route) {
    # Route is selected from the UI, hence use of routeCounter reactive
    data <- getDbData(
      paste0("SELECT DISTINCT service_id FROM trips WHERE route_id = '", route, "'"), 
      #paste0("SELECT DISTINCT service_id FROM trips"), 
      conPool
    ) %>% arrange(service_id)
    return(data$service_id)
  }
  
  # Get the service_id options for the selected route
  getBlocks <- function (route, service) {
    data <- getDbData(
      paste0("SELECT DISTINCT quasi_block FROM blocks WHERE route_id = '", route, 
             "' AND service_id = '", service, "'"), conPool) %>% arrange(quasi_block)
    return(data$quasi_block)
  }
  
  getStops <- function (route, service, block) {
    query <- paste0("SELECT * FROM distances WHERE route_id = '", route,
                    "' AND service_id = '", service, "' AND quasi_block = '",
                    block, "'")
    data <- getDbData(query, conPool) %>% arrange(distance_km)
    return(data)
  }
  
  getStopNames <- reactive({
    query <- "SELECT stop_id, stop_name FROM stops"
    data <- getDbData(query, conPool)
    data$stop_name <- iconv(data$stop_name, "latin1", "ASCII", sub = "")
    return(data)
  })
  
  # Get shape ids for the selected block
  getShapeIds <- function (){
    trips <- stops_reactive$stops$trip_id %>% unique()
    trips <- unique(trips[!is.na(trips)])
    
    query <- paste0("SELECT shape_id FROM trips WHERE trip_id IN (", 
                    paste0(sprintf("'%s'", trips), collapse = ', '), ")")
    data <- getDbData(query, conPool)
    return(unique(data$shape_id))
  }
  
  # Get shapes details for the trips associated with the selected route
  getShapeData <- function () {
    if(is.null(stops_reactive$stops)){return(NULL)}
    query <- paste0("SELECT shape_id, shape_pt_lat, shape_pt_lon, shape_pt_sequence FROM shapes WHERE shape_id IN (", 
                    paste0(sprintf("'%s'", shapeIdsReactive$shapes), collapse = ', '), ")")
    data <- getDbData(query, conPool) %>%
      arrange(shape_pt_sequence)
    return(data)
  }
  
  stop_analysis <- reactive({
    req(input$selected_route)
    query <- paste0("SELECT * FROM stop_analysis WHERE route_id = '", input$selected_route, 
                    "' AND service_id = '", input$selected_service, "' AND quasi_block = ", input$selected_block)
    data <- getDbData(query, conPool)
    return(data)
  })
  
  getDeadLegShapes <- function () {
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
  }
  
  getDeadTripShapes <- function () {
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
  }
  
  # Get distance data for selcted route, service and block
  getDistanceData <- function(route, service, block){
    query <- paste0("SELECT * FROM distances WHERE route_id = '", route, "' 
                    AND service_id = '", service, 
                    "' AND quasi_block = ", block)
    data <- getDbData(query, conPool) %>% arrange(distance_km)
    return(data)
  }
  
  getElevationData <- function(route, service, block){
    # Only query the elevations table if it exists
    query_exists <- "SELECT * FROM INFORMATION_SCHEMA.TABLES
                     WHERE TABLE_SCHEMA = 'dbo'
                     AND TABLE_NAME = 'stopElevations';"
    checkElevations <- getDbData(query_exists, conPool)
    
    if(nrow(checkElevations) == 1){
      query <- paste0("SELECT distances.*,
                     stopElevations.elevation
                     FROM distances
                     LEFT JOIN stops ON distances.stop = stops.stop_id
                     LEFT JOIN stopElevations ON stops.stop_lat = stopElevations.latitude AND
                     stops.stop_lon = stopElevations.longitude
                     WHERE
                     route_id = '", route, "'
                     AND service_id = '", service,
                     "' AND quasi_block = ", block)
      stopElevations <- getDbData(query, conPool)
      return(stopElevations)
    } else {
      return(NULL)
    }
  }
  
  temperatureData <- reactive({
    week <- lubridate::isoweek(input$week_selector)
    query <- paste0("SELECT * FROM temperature_stats WHERE week = ", week)
    data <- getDbData(query, conPool) %>% arrange(hr)
    return(data)
  })
  
  # Route selector UI element
  output$showRouteSelector <- renderUI({
    div(
      selectInput(
        'selected_route',
        'Route Id',
        choices = routesVector(),
        width = 150
      ), style = 'display: inline-block;'
    )
  })
  
  # Disabled route name UI element
  output$showRouteNameSelector <- renderUI({
    div(
      shinyjs::disabled(textInput(
        'selected_route_name',
        'Name',
        value = getRouteName(input$selected_route),
        width = 90
        )), style = 'display: inline-block; vertical-align: top;'
      )
  })
  
  # Service selector UI element based on selected route
  output$showServiceSelector <- renderUI({
    div(
      selectInput(
        'selected_service',
        'Service',
        choices = getServices(input$selected_route),
        width = 110
      ), style = 'display: inline-block; vertical-align: top;'
    )
  })
  
  # Block selector UI element based on selected route & service
  output$showBlockSelector <- renderUI({
    div(
      selectInput(
        'selected_block',
        'Block',
        choices = getBlocks(input$selected_route, input$selected_service),
        width = 100
      ), style = 'display: inline-block; margin-left: 15px;'
    )
  })
  
  getDataReactive <- reactiveValues(text = 'Load Data')
  
  # Action button for collecting data from db for selected route, service, block 
  output$showActionButton <- renderUI({
    if(is.null(input$selected_route) | is.null(input$selected_service) | is.null(input$selected_block)){return(NULL)}
    if(input$selected_route == "" | input$selected_service == "" | input$selected_block ==""){return(NULL)}
    div(
      actionButton(
        'get_data',
        getDataReactive$text,
        width = 95,
      class = NULL
      ), style = 'display: inline-block; margin-left: 10px; margin-top: 26px; vertical-align: top;'
    )
  })
  
  # When the Get Data button is pressed, gather the data and save to reactive
  # value stores
  observeEvent(input$get_data, {
    stops_reactive$stops <- getStops(input$selected_route, input$selected_service, input$selected_block)
    shapeIdsReactive$shapes <- getShapeIds()
    shapeData$shapes <- getShapeData()
    deadShapes$trips <- getDeadTripShapes()
    deadShapes$legs <- getDeadLegShapes()
    distanceData$data <- getDistanceData(input$selected_route, input$selected_service, input$selected_block)
    elevationData$data <- getElevationData(input$selected_route, input$selected_service, input$selected_block)
  })
  
  # Create the Geo Map in Leaflet for the selected bus route, 
  # dead trips, legs & home depot
  output$busGeoMap <- renderLeaflet({
    if(is.null(stops_reactive$stops)){return(NULL)}
    
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
    if (!is.null(deadShapes$legs)){
      dead_ids <- as.integer(unique(deadShapes$legs$dead_trip_unique_id))
      
      for (id_dead in dead_ids){
        dead_df <- deadShapes$legs %>% filter(dead_trip_unique_id == id_dead)
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
    shapeIds <- shapeIdsReactive$shapes
    
    # Create a counter for the loader
    j = 1
    withProgress(message = 'Loading shapes...', value = 0, {
      for (id in shapeIds){
        # Show a progress loading bar in bottom right for each shape added...
        incProgress(1 / length(shapeIds), detail = paste(j, " of ", length(shapeIds)))
        j = j + 1 # inc the loader 
        coords <- shapeData$shapes %>% filter(shape_id == id)
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
    if (!is.null(deadShapes$trips)){
      dead_ids <- unique(deadShapes$trips$dead_trip_unique_id)
      for (id_dead in dead_ids){
        dead_df <- deadShapes$trips %>% filter(dead_trip_unique_id == id_dead)
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
    div(leafletOutput("busGeoMap"), class = map_class$class)
  })
  
  # UI render for the distance plot
  output$showRoutePlots <- renderUI({
    div(
      div(plotlyOutput('distancePlot', height = 200), style = 'margin-left: 30px; margin-right: 50px;  margin-top: 20px;'),
      div(plotlyOutput('elevationPlot', height = 200), style = 'margin-left: 30px; margin-right: 50px;  margin-top: 20px;'),
      div(uiOutput('week_slider')),
      div(uiOutput('showTemperaturePlotNotes'), style = 'margin-left: 30px; margin-right: 50px;  margin-top: 20px;'),
      div(plotlyOutput('temperaturePlot', height = 200), style = 'margin-left: 40px; margin-right: 50px;  margin-top: 27px;')
    )
  })
  
  output$week_slider <- renderUI({
    if(is.null(distanceData$data)){return(NULL)}
    div(
      #  min = as.Date("2021-01-01"),max =as.Date("2021-12-31"),value = as.Date("2021-06-01"), timeFormat = "%b %d"
      sliderInput(
        'week_selector',
        'Date',
        min = as.Date("2021-01-01"), 
        max = as.Date("2021-12-31"), 
        value = as.Date("2021-01-01"), 
        timeFormat = "%d-%b"
      ), style = 'margin-left: 55px; margin-right: 50px; margin-top: 20px;'
    )
  })
  
  # UI render for the dead trip & leg summary info
  # Just use simple verbatim output for now
  # These are quick to display & look good
  output$showDeadTripInfo <- renderUI({
    if (is.null(distanceData$data)){
      return(NULL)
    } else if (is.null(dead_shapes_reactive$leg_stats) & is.null(dead_shapes_reactive$stats)){
      header_text <- 'No dead trip or dead leg data...'
    } else if (is.null(dead_shapes_reactive$leg_stats) & !is.null(dead_shapes_reactive$stats)){
      header_text <- 'Dead Trip Details'
    } else if (!is.null(dead_shapes_reactive$leg_stats) & is.null(dead_shapes_reactive$stats)){
      header_text <- 'Dead Legs Details'
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
    if(is.null(distanceData$data)){return(NULL)}
    if(is.null(dead_shapes_reactive$leg_stats)){return(NULL)}
    
    data <- dead_shapes_reactive$leg_stats %>%
      select(-id, -route_id, -quasi_block)
    
    # Label stop id names
    stop_names <- getStopNames()
    data$start[2] <- stop_names$stop_name[stop_names$stop_id == data$start[2]] 
    data$end[1] <- stop_names$stop_name[stop_names$stop_id == data$end[1]]  
    
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
    if(is.null(distanceData$data)){return(NULL)}
    if(is.null(dead_shapes_reactive$stats)){return(NULL)}
    
    data <- dead_shapes_reactive$stats
    
    # Label stop id names
    data <- left_join(data, getStopNames(), by = c('from_stop' = 'stop_id')) %>%
      left_join(getStopNames(), by = c('to_stop' = 'stop_id')) %>%
      select(stop_name.x, stop_name.y, start, end, schedule_hrs, travel_hrs, distance_km) %>%
      rename(from_stop = 'stop_name.x') %>%
      rename(to_stop = 'stop_name.y')
    
    table_height <- ifelse(nrow(data) > 5, 190, 'auto')
    
    reactable(
      data,
      filterable = FALSE,
      pagination = FALSE,
      height = table_height,
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
    if(is.null(distanceData$data)){return(NULL)}
    
    data_plot <- distanceData$data %>%
      arrange(time_axis) %>%
      rename('distance' = distance_km)
    
    # Now create the plot using Plotly
    p <- plot_ly(
      data_plot, 
      x = ~time_axis, 
      y = ~distance, 
      type = 'scatter', 
      mode = 'lines',
      height = 200, 
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
        tickformat = "%H:%M"
      ),
      margin = list(pad = 5)
    )
  })
  
  output$elevationPlot <- renderPlotly({
    if(is.null(elevationData$data)){return(NULL)}
    
    data_plot <- elevationData$data %>%
      arrange(time_axis) %>%
      rename('elevation' = elevation)
    
    # Now create the plot using Plotly
    p <- plot_ly(
      data_plot, 
      x = ~time_axis, 
      y = ~elevation, 
      type = 'scatter', 
      mode = 'lines',
      height = 200, 
      fill = 'tozeroy',
      fillcolor = '#B5DA8A',
      name = 'Distance',
      line = list(color = '#1C2D38', width = 1),
      hoverinfo = 'text', 
      text = ~paste0(elevation, " ASL @ ", format(time_axis, '%H:%M'))
    )
    
    # Add some final layout mods
    p <- p %>% layout(
      title = "",
      yaxis = list(
        title = list(
          text = '<b>Elevation ASL (m)</b>',  
          standoff = 20L
          ),
        range = c(0, (max(data_plot$elevation) + 40))
        ),
      showlegend = FALSE,
      font = list(size = 11),
      xaxis = list(
        title = '',
        range = c((min(data_plot$time_axis)- (1*60*60)), max(data_plot$time_axis) + (2*60*60)),
        type = 'date',
        tickformat = "%H:%M"
      ),
      margin = list(pad = 5)
    )
  })
  
  # Display chart notes, again assigned after plot is ready
  output$showTemperaturePlotNotes <- renderUI({
    if(is.null(titlesNotes_reactive$temperature_note)){return(NULL)}
    notes <- titlesNotes_reactive$temperature_note
    div(span('*', style = 'font-weight: 900; font-size: 15px;'), notes, class = 'plot-notes')
  })
  
  # Create a line chart of temperatures for the route block
  output$temperaturePlot <- renderPlotly({
    if(is.null(distanceData$data)){return(NULL)}
    req(input$week_selector)
    
    distance_times <- c(min((distanceData$data$time_axis)- (1*60*60)), max((distanceData$data$time_axis) + (2*60*60)))
    
    data_plot <- temperatureData() %>%
      mutate(hr = sprintf("%02d", as.numeric(hr))) %>%
      mutate(time_axis = as.POSIXct(
        paste0('2021-01-0', '1', ' ', hr, ':00:00'), 
        format = "%Y-%m-%d %H:%M:%S", tz = 'UTC'
      ))
    
    data_plot_add <- data_plot %>%
      mutate(hr = sprintf("%02d", as.numeric(hr))) %>%
      mutate(time_axis = as.POSIXct(
        paste0('2021-01-0', '2', ' ', hr, ':00:00'), 
        format = "%Y-%m-%d %H:%M:%S", tz = 'UTC'
      ))
    
    data_plot <- rbind(data_plot, data_plot_add)
     
    # Now create the plot using Plotly
    p <- plot_ly(
      data_plot, 
      x = ~time_axis, 
      y = ~ci_upper_degC, 
      type = 'scatter', 
      mode = 'lines',
      height = 200, 
      name = 'Temperature High',
      line = list(color = 'transparent')
    )
    
    p <- p %>% add_trace(
      y = ~ci_lower_degC, 
      type = 'scatter', 
      mode = 'lines',
      name = 'Temperature Low',
      line = list(color = 'transparent'),
      fill = 'tonexty', 
      fillcolor = '#C1C1C160' 
    )
    
    p <- p %>% add_trace(
      y = ~p90_degC, 
      type = 'scatter', 
      mode = 'lines',
      name = 'Temperature p90',
      line = list(color = 'transparent'),
      fill = 'tonexty', 
      fillcolor = '#D43E2A60' 
    )
    
    p <- p %>% add_trace(
      y = ~mean_degC, 
      type = 'scatter', 
      mode = 'lines',
      name = 'Temperature Mean',
      line = list(color = '#1C2D38')
    )
    
    # Add some final layout mods
    p <- p %>% layout(
      title = "",
      yaxis = list(title = list(text = '<b>Temperature (deg C)</b>',  standoff = 20L),
                   range = ~c(min(0, min(ci_lower_degC, p90_degC)), max(ci_upper_degC) + 2)),
      showlegend = FALSE,
      font = list(size = 11),
      xaxis = list(
        title = '',
        range = c(distance_times[1], distance_times[2]),
        type = 'date',
        tickformat = "%H:%M"
      ),
      margin = list(pad = 5)
    )
    titlesNotes_reactive$temperature_note <- 'Grey band represents 95% confidence 
    interval for sample mean.  Red represents the p90 value, i.e., 90% of temperatures in
    the 30-year sample were greater than the lower edge of this band.'  
    return(p)
  })
  
  # Show the reactable table view of trips for selected route
  output$showTripTable <- renderUI({
    div(reactableOutput("tripTable"), class = "reactBox")
  })
  
  # Create reactable table view of trips for selected route
  output$tripTable <- reactable::renderReactable({
    if(is.null(distanceData$data)){return(NULL)}
    
    data <- distanceData$data %>%
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
    # Create a new group field for holding the bar buckets
    data$group <- NA 
    data$group[data$block_length_km <= 96] <- 1
    data$group[data$block_length_km > 96 & data$block_length_km <= 160] <- 2
    data$group[data$block_length_km > 160 & data$block_length_km < 300] <- 3
    data$group[data$block_length_km >= 300] <- 4
    return(data)
  })
  
  # Create a reactive for holding titles and notes
  # this is used a simple way to delay the appearance of titles & notes
  # until data/charts are ready
  titlesNotes_reactive <- reactiveValues(
    range_plot = NULL, range_note = NULL, histo_plot = NULL, temperature_plot = NULL
  )
  
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
    
    # Now clean & consolidate for use in plot 
    data <- data %>%
      group_by(group) %>%
      mutate(pers = round(100 * (n() / nrow(data))), 0) %>%
      select(group, pers) %>%
      unique() %>%
      arrange(group) 
    
    # Create the yaxis labels & assign factor levels so that they appear in the
    # required order
    
    labs <- c(
      '<b>Distances < 96 km<b>', 
      '<b>Distances 96 km to 160 km<b>', 
      '<b>Distances 161 km to 300 km<b>', 
      '<b>Distances > 300 km<b>'
    )
    data$labs <- NA
    for (group in as.integer(data$group)){
      data$labs[data$group == group] <- labs[group]  
    }
    data$labs <- factor(data$labs, levels = data$labs)
    
    # Add explainer notes to add to hover info
    explainer <- c(
      'feasible without en route charging.',
      'may require en route charging in winter',
      'will likely require some en route charging',
      'will require significant en route charging.'
    )
    data$explainer <- NA
    for (group in as.integer(data$group)){
      data$explainer[data$group == group] <- explainer[group]  
    }
    
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
      mode = 'text+markers',
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
        range = c(0, min((max(data$pers) + 40), 110))
      ),
      yaxis = list(title = list(test = "")),
      font = list(size = 11),
      autosize = F,
      margin = list(pad = 10, l = 20),
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
  
  # Display a title for the distance histogram plot
  output$showHistoPlotTitle <- renderUI({
    # Takes the reactive value, assigned after plot is ready
    title <- titlesNotes_reactive$histo_plot 
    div(title, class = 'title-header')
  })
  
  # Create the range breakdown chart
  output$rangeHistoPlot <- renderPlotly({
    # Call the network data
    data <- networkData() %>%
      select(group, block_length_km) %>%
      arrange(group, block_length_km)
    
    # bar labels
    labs <- c(
      '<b>Distances < 96 km<b>', 
      '<b>Distances 96 km to 160 km<b>', 
      '<b>Distances 161 km to 300 km<b>', 
      '<b>Distances > 300 km<b>'
    )
    # Colours for bars
    cols <- c('#70A432', 'FFD869', '#FFBA00', '#D33D29')
    
    p <- plot_ly(type = "histogram", height = 220, width = 700,)
    
    # Loop through and each category
    for (g in sort(unique(data$group))) {
      df <- subset(data, group == g)
      p <- p %>% add_histogram(
        x = df$block_length_km, 
        marker = list(color = cols[g]),
        name = labs[g]
      )
    }
    # Add final layout tweaks
    p <- p %>% layout(barmode = "overlay", margin = list(pad = 10), font = list(size = 11))
    # Now add the title and note details
    titlesNotes_reactive$histo_plot <- paste0('Histogram of total distances (km) for ', format(nrow(networkData()), big.mark = ','), ' blocks') 
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
      searchable = TRUE,
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
      ),
      columns = list(
        group = colDef(
          cell = function(value) {
            # Use solid block unicode for group flag, i.e. red, orange or greeen
            if (!is.na(value)) {
              symb = "\u2587" 
            } else {
              symb = '---'
            }
            symb
          },
          # change color
          style = function(value) {
            if (value == 1) {
              color <- "#70A432"
            } else if (value == 2) {
              color <- "#FFD869"
            } else if (value == 3) {
              color <- "#FFBA00"
            } else {
              color <- "#D33D29"
            }
            list(fontWeight = 600, color = color)
          })
      )
    )
  })
  
}) 