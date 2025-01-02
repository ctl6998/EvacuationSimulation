/**
* Name: evacuation - Extension 2
* Author: ctl
* Tags: 
*/

model evacuation

global {
    shape_file shapefile_buildings <- shape_file("../includes/buildings.shp");
    shape_file shapefile_roads <- shape_file("../includes/clean_roads.shp");
    shape_file shapefile_river <- shape_file("../includes/RedRiver_scnr1.shp");

    geometry shape <- envelope(shapefile_roads);
    graph road_network;
    float step <- 10#s;
    
    // Global variables
    building shelter;
    int nb_evacuee <- 0;
    bool simulation_finished <- false;
    map<road, float> traffic_density;
    
    init {
        create building from: shapefile_buildings with:[height::int(read("height"))];
        
        // Find the largest building to be the shelter
        shelter <- building with_max_of(each.shape.area);
        shelter.is_shelter <- true;
        
        create road from: shapefile_roads;
        road_network <- as_edge_graph(road);
        
        // Initialize traffic density
        traffic_density <- road as_map (each::0.0);
        
        create inhabitant number: 1000 {
            location <- any_location_in(one_of(building));
            is_aware <- flip(0.1);
            knows_shelter_location <- is_aware ? flip(0.1) : false;
            current_building <- one_of(building where (each != shelter));
            target <- any_location_in(current_building);
            distance_to_shelter <- location distance_to shelter.location;
            
            // Create randomness: 20% for car, 70% for bike, 10% for walk
            float random_mobility <- rnd(0.0, 1.0);
            if (random_mobility < 0.2) {
                mobility_type <- "car";
                base_speed <- 1.0;
                traffic_factor <- 1.0;
            } else if (random_mobility < 0.9) {
                mobility_type <- "motorcycle";
                base_speed <- 0.85;
                traffic_factor <- 0.5;
            } else {
                mobility_type <- "walking";
                base_speed <- 0.1;
                traffic_factor <- 0.2;
            }
        }
        
        create red_river from: shapefile_river;
    }
    
    // Update traffic density every step
    // Trafic density: 0% to 100%
    reflex update_traffic {
        traffic_density <- road as_map (each::0.0);
        ask road {
            // Normalize traffic density to be between 0 and 1
            float raw_density <- length(inhabitant at_distance 5.0) / shape.perimeter;
            traffic_density[self] <- min(1.0, raw_density / 2.0);  // Assuming max realistic density is ~ 2 agents per meter
        }
    }
    
    reflex check_end when: !simulation_finished {
        if(inhabitant all_match (each.is_evacuated or !each.is_aware)) {
            simulation_finished <- true;
            write "Simulation finished at cycle " + cycle;
        }
    }
}

species building {
    int height;
    bool is_shelter <- false;
    
    aspect default {
        draw shape color: is_shelter ? #black : #gray;
    }
}

species road {
   aspect default {
       float traffic_intensity <- traffic_density[self];
       float thickness <- 1 + (traffic_intensity * 4);
       rgb base_color <- rgb(55 + min(200, int(255 * traffic_intensity * 4)), 55, 55, 100);
       
       draw shape + thickness color: base_color;
       draw shape + (thickness * 1.5) color: rgb(base_color.red, base_color.green, base_color.blue, 200); //Opacity 0.5
       draw shape + (thickness * 2) color: rgb(base_color.red, base_color.green, base_color.blue, 128); //Opacity 0.2
   }
}

species inhabitant skills: [moving] {
    bool is_aware <- false;
    bool is_evacuated <- false;
    bool knows_shelter_location <- false;
    string mobility_type;
    float base_speed;
    float traffic_factor;
    building current_building;
    point target;
    float distance_to_shelter;
    
    reflex update_distance when: !is_evacuated {
        distance_to_shelter <- location distance_to shelter.location;
    }
    
    // Calculate actual speed based on traffic
    // actual_speed = base_speed * (1 - traffic_factor * traffic_density)
    // so if traffic_density = 1, car can not move
    float get_current_speed(road current_road) {
        return base_speed * (1 - traffic_factor * traffic_density[current_road]);
    }
    
    reflex evacuate when: is_aware and !is_evacuated {
        road current_road <- road closest_to self;
        speed <- get_current_speed(current_road);
        
        if knows_shelter_location or (location distance_to shelter.location < 200.0) {
            do goto target: shelter.location on: road_network;
            
            if location distance_to shelter.location < 2.0 {
                is_evacuated <- true;
                nb_evacuee <- nb_evacuee + 1;
                location <- any_location_in(shelter);
            }
        } else {
            do goto target: target on: road_network;
            if location distance_to target < 2.0 {
                current_building <- one_of(building where (each != shelter and each != current_building));
                target <- any_location_in(current_building);
            }
        }
        
        ask inhabitant at_distance 10.0 {
            if !self.is_aware and flip(0.1) {
                self.is_aware <- true;
                self.knows_shelter_location <- flip(0.1);
            }
        }
    }
    
    aspect default {
        rgb agent_color <- is_evacuated ? #green : (is_aware ? 
            (knows_shelter_location ? #purple : #orange) : #blue);
        
        if mobility_type = "car" {
            draw square(4) color: agent_color;
        } else if mobility_type = "motorcycle" {
            draw triangle(4) color: agent_color;
        } else {
            draw circle(2) color: agent_color;
        }
    }
}

species red_river {
    aspect default {
        draw shape color: #blue;
    }
}

experiment evacuation_exp type: gui {
    output {
        display map type: 3d {
            species building;
            species road;
            species inhabitant;
            species red_river;
        }
        
        monitor "Number of evacuees" value: nb_evacuee;
        monitor "Aware people" value: inhabitant count (each.is_aware);
        monitor "People knowing shelter" value: inhabitant count (each.knows_shelter_location);
        monitor "Cars" value: inhabitant count (each.mobility_type = "car");
        monitor "Motorcycles" value: inhabitant count (each.mobility_type = "motorcycle");
        monitor "Pedestrians" value: inhabitant count (each.mobility_type = "walking");
    }
}