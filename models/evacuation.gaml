/**
* Name: evacuation - final project
* Based on the internal empty template.
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
    list<int> information_spread_history <- [];
    
    // Parameters for batch experiments
    float alert_duration <- 3600.0;
    
    init {
        create building from: shapefile_buildings with:[height::int(read("height"))];
        // Find the largest building to be the shelter
        shelter <- building with_max_of(each.shape.area);
        shelter.is_shelter <- true;
        
        create road from: shapefile_roads;
        road_network <- as_edge_graph(road);
        
        create inhabitant number: 1000 {
            home <- any_location_in(one_of(building));
            location <- home;
            // Only 10% of the population will be aware of the evacuation
            is_aware <- flip(0.1);
        }
        
        create red_river from: shapefile_river;
        
        // Initialize information spread history
        information_spread_history <- [inhabitant count (each.is_aware)];
    }
    
    // Track information spread over time
    reflex update_information_spread {
        information_spread_history <- information_spread_history + [inhabitant count (each.is_aware)];
    }
    
    // Simulation ends when all aware people have evacuated
    reflex check_end when: !simulation_finished {
        if (cycle * step >= alert_duration) or (inhabitant all_match (each.is_evacuated or !each.is_aware)) {
            simulation_finished <- true;
            write "Simulation finished at cycle " + cycle;
            do pause;
        }
    }
}

species building {
    int height;
    bool is_shelter <- false;
    
    aspect default {
        draw shape color: is_shelter ? #red : #gray;
    }
}

species road {
    aspect default {
        draw shape color: #black;
    }
}

species inhabitant skills: [moving] {
    point home;
    bool is_aware <- false;
    bool is_evacuated <- false;
    float speed <- 1.0;
    
    reflex evacuate when: is_aware and !is_evacuated {
        do goto target: shelter.location on: road_network;
        
        // Check if reached shelter
        if location distance_to shelter.location < 2.0 {
            is_evacuated <- true;
            nb_evacuee <- nb_evacuee + 1;
            location <- any_location_in(shelter);
        }
        
        // Inform nearby people at a distance of 10 meters
        ask inhabitant at_distance 10.0 {
            if !self.is_aware and flip(0.1) {
                self.is_aware <- true;
            }
        }
    }
    
    aspect default {
        draw circle(3) color: is_evacuated ? #green : (is_aware ? #red : #blue);
    }
}

species red_river {
    aspect default {
        draw shape color: #blue;
    }
}

experiment evacuation_exp type: gui {
    output {
        display map {
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
        monitor "Evacuated people" value: inhabitant count (each.is_evacuated);
    }
}