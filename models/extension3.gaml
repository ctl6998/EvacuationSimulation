/**
* Name: evacuation - Extension 3
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
    
    // Parameters for batch experiments
    string awareness_strategy <- "random" among: ["random", "furthest", "closest"];
    int initial_population <- 1000 min: 500 max: 10000 step: 500;
    float alert_duration <- 1800.0 min: 100.0 max: 3600.0 step: 100;  // Alert time in seconds
    
    // Statistics
    float total_evacuation_time;
    float avg_evacuation_time;
    float total_road_time;
    
    init {
        create building from: shapefile_buildings with:[height::int(read("height"))];
        
        shelter <- building with_max_of(each.shape.area);
        shelter.is_shelter <- true;
        
        create road from: shapefile_roads;
        road_network <- as_edge_graph(road);
        traffic_density <- road as_map (each::0.0);
        
        create inhabitant number: initial_population {
            location <- any_location_in(one_of(building));
            current_building <- one_of(building where (each != shelter));
            target <- any_location_in(current_building);
            distance_to_shelter <- location distance_to shelter.location;
            knows_shelter_location <- false;
            road_time <- 0.0;
            
            // Mobility type assignment
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
        
        // Apply awareness strategy
        list<inhabitant> sorted_inhabitants;
        switch awareness_strategy {
            match "random" {
                ask (initial_population * 0.1) among inhabitant {
                    is_aware <- true;
                    knows_shelter_location <- flip(0.1);
                }
            }
            match "furthest" {
                sorted_inhabitants <- inhabitant sort_by (each.distance_to_shelter);
                ask last(int(initial_population * 0.1), sorted_inhabitants)  {
                    is_aware <- true;
                    knows_shelter_location <- flip(0.1);
                }
            }
            match "closest" {
                sorted_inhabitants <- inhabitant sort_by (each.distance_to_shelter);
                ask first((initial_population * 0.1), sorted_inhabitants) {
                    is_aware <- true;
                    knows_shelter_location <- flip(0.1);
                }
            }
        }
        
        create red_river from: shapefile_river;
    }
    
    reflex update_traffic {
        traffic_density <- road as_map (each::0.0);
        ask road {
            float raw_density <- length(inhabitant at_distance 5.0) / shape.perimeter;
            traffic_density[self] <- min(1.0, raw_density / 2.0);
        }
    }
    
    reflex check_end when: !simulation_finished {
        loop i over: inhabitant where (!each.is_evacuated) {
            if i.is_aware and !i.inside_building {
                i.road_time <- i.road_time + step;
            }
        }
        
        if (cycle * step >= alert_duration) or (inhabitant all_match (each.is_evacuated or !each.is_aware)) {
            simulation_finished <- true;
            //For each inhabitant
            total_evacuation_time <- cycle * step;
            total_road_time <- mean(inhabitant collect each.road_time);
            write "Simulation finished - Strategy: " + awareness_strategy;
            

            write "Average time on roads: " + total_road_time;
            write "Efficiency: " + total_evacuation_time/total_road_time;
            write "People evacuated/people awared: " + nb_evacuee + "/" + length(inhabitant where each.is_aware);
            
            do pause;
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
    bool knows_shelter_location;
    bool inside_building <- true;
    string mobility_type;
    float base_speed;
    float traffic_factor;
    building current_building;
    point target;
    float distance_to_shelter;
    float road_time;
    
    reflex update_distance when: !is_evacuated {
        distance_to_shelter <- location distance_to shelter.location;
    }
    
    float get_current_speed(road current_road) {
        return base_speed * (1 - traffic_factor * traffic_density[current_road]);
    }
    
    reflex evacuate when: is_aware and !is_evacuated and (cycle * step < alert_duration) {
        road current_road <- road closest_to self;
        speed <- get_current_speed(current_road);
        inside_building <- false;
        
        // This is important
        if knows_shelter_location or (location distance_to shelter.location < 500.0) {
            do goto target: shelter.location on: road_network;
            
            if location distance_to shelter.location < 2.0 {
                is_evacuated <- true;
                nb_evacuee <- nb_evacuee + 1;
                location <- any_location_in(shelter);
                inside_building <- true;
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

experiment single_run type: gui {
    parameter "Awareness Strategy" var: awareness_strategy <- "random" among: ["random", "furthest", "closest"];
    parameter "Initial Population" var: initial_population <- 1000 min: 500 max: 10000 step: 500;
    parameter "Alert Duration (seconds)" var: alert_duration <- 1800.0 min: 1800.0 max: 7200.0;
    
    output {
        display map type: 3d {
            species building;
            species road;
            species inhabitant;
            species red_river;
        }
        
                // Information spread chart
        display "Information Spread Chart" {
            chart "Information Spread Over Time" type: series {
                data "Aware People" value: inhabitant count (each.is_aware) color: #red;
                data "Evacuated People" value: inhabitant count (each.is_evacuated) color: #green;
                data "Unaware People" value: inhabitant count (!each.is_aware) color: #blue;
            }
        }
        
        // Population statistics
        display "Population Statistics" {
            chart "Population Distribution" type: pie {
                data "Aware (Not Evacuated)" value: (inhabitant count (each.is_aware and !each.is_evacuated)) color: #red;
                data "Evacuated" value: (inhabitant count (each.is_evacuated)) color: #green;
                data "Unaware" value: (inhabitant count (!each.is_aware)) color: #blue;
            }
        }
        
        monitor "Number of evacuees" value: nb_evacuee;
        monitor "Aware people" value: inhabitant count (each.is_aware);
        monitor "People knowing shelter" value: inhabitant count (each.knows_shelter_location);
    }
}

experiment batch_comparison type: batch repeat: 5 keep_seed: true until: simulation_finished {
    // Parameters
    parameter "Awareness Strategy" var: awareness_strategy <- "random" among: ["random", "furthest", "closest"];
    parameter "Initial Population" var: initial_population <- 1000 among: [1000, 1500, 2000, 5000, 10000];
    parameter "Alert Duration (seconds)" var: alert_duration <- 1800.0 min: 100.0 max: 3600.0 step: 100;

    method exploration;

    permanent {
        display ComparisonCharts background: #white {
        	// Chart 1: Efficiency by Strategy
            chart "Efficiency by Strategy" type: histogram background: #white position: {0, 0} size: {1.0, 1.0} {
                data "Random" value: mean(simulations where (each.awareness_strategy = "random") collect 
                    (each.total_evacuation_time / each.total_road_time)) color: #red;
                data "Furthest" value: mean(simulations where (each.awareness_strategy = "furthest") collect 
                    (each.total_evacuation_time / each.total_road_time)) color: #blue;
                data "Closest" value: mean(simulations where (each.awareness_strategy = "closest") collect 
                    (each.total_evacuation_time / each.total_road_time)) color: #green;
            }
        }
    }
}