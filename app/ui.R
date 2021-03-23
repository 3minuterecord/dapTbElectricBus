source('global.R')
library(shinyalert)

header <- dashboardHeader(title = "DAP Team B Group Project", titleWidth = 220)

sidebar <- dashboardSidebar(
  useShinyjs(), 
  useShinyalert(),  # Set up shinyalert
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "custom.css")),
  tags$style(rel = "stylesheet", type = "text/css", href = "custom.css"),
  width=220,
  sidebarMenu(
    br(),
    div(img(src="bus-front-green.svg"), style="margin-top: 10px; margin-left: 13px; margin-right: 110px; margin-bottom: 10px;"),
    br(),
    menuItem("Analysis", tabName = "analysis", icon = icon("superpowers")),
    br(),
    div(conditionalPanel(condition="$('html').hasClass('shiny-busy')",
                         img(src="gears.gif")), style="margin-left: 25px;")
  )
)

body <- dashboardBody(
  tabItems(
    tabItem(
      tabName = "analysis",
      fluidRow(
        box(width=12,
            title = strong(tags$i(class="fa fa-bullseye fa-fw"), "Electric Dublin Bus"), 
            collapsible = TRUE,
            solidHeader = TRUE,
            status = "primary",
            fluidRow(
              column(12,
                div()
              )
            ),
            br(), br(), br(), br(), br(), br(), br(), br()
        )
      )
    )  
  )
)

dashboardPage(title = "Team B", header, sidebar, body, skin = "green")