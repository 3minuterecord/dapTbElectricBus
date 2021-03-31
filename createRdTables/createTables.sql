CREATE TABLE stops (
 stop_id varchar(50),
 stop_name varchar(255),
 stop_lat decimal(20,14),
 stop_lon decimal(20,14),
);

CREATE TABLE stops (
  shape_id,
  shape_pt_lat,
  shape_pt_lon,
  shape_pt_sequence,
  shape_dist_traveled
);

CREATE INDEX idx_trip_id
ON trips (trip_id);

CREATE INDEX idx_route_id
ON trips (route_id);

CREATE INDEX idx_shape_id
ON shapes (shape_id);