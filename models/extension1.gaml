/**
* Name: evacuation - Extension 1
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
    
    float total_evacuation_time;

    
    init {
        create building from: shapefile_buildings with:[height::int(read("height"))];
        
        // Find the largest building to be the shelter
        shelter <- building with_max_of(each.shape.area);
        shelter.is_shelter <- true;
        
        create road from: shapefile_roads;
        road_network <- as_edge_graph(road);
        
        create inhabitant number: 1000 {
            location <- any_location_in(one_of(building));
            // Only 10% of the population will be aware of the evacuation
            is_aware <- flip(0.1);
            // Among aware people, only 10% know shelter location
            knows_shelter_location <- is_aware ? flip(0.1) : false;
            // Initialize current building and target
            current_building <- one_of(building where (each != shelter));
            target <- any_location_in(current_building);
            // Initialize distance to shelter
            distance_to_shelter <- location distance_to shelter.location;
        }
        
        create red_river from: shapefile_river;
    }
    
    // Simulation ends when all aware people have evacuated
    reflex check_end when: !simulation_finished {
        if(inhabitant all_match (each.is_evacuated or !each.is_aware)) {
            simulation_finished <- true;
            total_evacuation_time <- cycle * step;
            write "Simulation finished at cycle " + cycle;
            write "Evacuation time: " + total_evacuation_time;
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
        draw shape color: #black;
    }
}

species inhabitant skills: [moving] {
    bool is_aware <- false;
    bool is_evacuated <- false;
    bool knows_shelter_location <- false;
    float speed <- 1.0;
    building current_building;
    point target;
    float distance_to_shelter;
    
    reflex update_distance when: !is_evacuated {
        distance_to_shelter <- location distance_to shelter.location;
    }
    
    reflex evacuate when: is_aware and !is_evacuated {
        // If knows shelter location or close to it, go directly there
        // For this map, 20m is too small, I increased to 200m
        if knows_shelter_location or (distance_to_shelter < 200.0) {
            do goto target: shelter.location on: road_network;
            
            // Check if reached shelter
            if distance_to_shelter < 2.0 {
                is_evacuated <- true;
                nb_evacuee <- nb_evacuee + 1;
                location <- any_location_in(shelter);
            }
        }
        // Otherwise, search randomly through buildings
        else {
            do goto target: target on: road_network;
            // If reached current target building, choose a new one
            if location distance_to target < 2.0 {
                current_building <- one_of(building where (each != shelter and each != current_building));
                target <- any_location_in(current_building);
            }
        }
        
        // Inform nearby people at a distance of 10 meters
        ask inhabitant at_distance 10.0 {
            if !self.is_aware and flip(0.1) {
                self.is_aware <- true;
                // 10% chance to also learn shelter location from informed person
                self.knows_shelter_location <- flip(0.1);
            }
        }
    }
    
    // Green: evacuated
    // Not aware: blue
    // Aware + Know shelter location: red
    // Aware + Don't know shelter location: orange
    aspect default {
        draw circle(3) color: is_evacuated ? #green : (is_aware ? (knows_shelter_location ? #red : #orange) : #blue);
    }

}

species red_river {
    aspect default {
        draw shape color: #blue;
    }
}

experiment evacuation_exp type: gui {
    output {
        display map type: 3d{
            species building;
            species road;
            species inhabitant;
            species red_river;
        }
        
        monitor "Number of evacuees" value: nb_evacuee;
        monitor "Aware people" value: inhabitant count (each.is_aware);
        monitor "People knowing shelter" value: inhabitant count (each.knows_shelter_location);
        monitor "Evacuated people" value: inhabitant count (each.is_evacuated);
    }
}