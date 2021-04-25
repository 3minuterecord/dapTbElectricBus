CREATE TABLE stops (
 stop_id varchar(50),
 stop_name varchar(255),
 stop_lat decimal(20,14),
 stop_lon decimal(20,14),
);

CREATE INDEX idx_trip_id
ON trips (trip_id);

CREATE INDEX idx_route_id
ON trips (route_id);

CREATE INDEX idx_route_id
ON bus_routes (route_id);

CREATE INDEX idx_shape_id
ON shapes (shape_id);

CREATE INDEX idx_trip_id
ON stop_times (trip_id);

CREATE INDEX idx_route_id
ON stop_analysis (route_id)

CREATE INDEX idx_service_id
ON stop_analysis (service_id)

CREATE INDEX idx_dead_trip_unique_id
ON dead_leg_shapes (dead_trip_unique_id);

CREATE INDEX idx_stop_id_id
ON stops (stop_id);

CREATE INDEX idx_route_id
ON distances (route_id);

CREATE INDEX idx_service_id
ON distances (service_id);

CREATE INDEX idx_block_num
ON distances (quasi_block);

CREATE INDEX idx_route_id
ON stop_analysis (route_id);

CREATE INDEX idx_service_id
ON stop_analysis (service_id);

CREATE INDEX idx_block_num
ON stop_analysis (quasi_block);

CREATE INDEX idx_route_id
ON bus_routes (route_id);