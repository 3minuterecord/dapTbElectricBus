# dapTbElectricDublinBus
Visualization of factors affecting the feasibility of transitioning the Dublin Bus network to electric buses.

stops - stops where vehicles pick up or drop off passengers 
routes -  A route is a group of trips that are advertised to riders as a single service.. e.g. route 14A (note: not a separate file, referenced in trips.txt)
trips - a single scheduled iteration of a route, in a certain direction at a certain time e.g. route 14A at 8AM weekdays, northbound
block - a collection of trips undertaken by a single bus and driver before going back to the depot
stop_times - times that a vehicle arrives at and departs from stops for each trip
calendar - Service dates specified using a weekly schedule with start and end dates
shapes - rules for mapping vehicle travel paths
Python elevation package prerequisites:

Set system variables for:
    1. SQL Password
    2. SQL User
    3. SQL Database Name
    4. SQL Server Name
    5. SQL Driver
    6. PYTHONPATH for package directory
