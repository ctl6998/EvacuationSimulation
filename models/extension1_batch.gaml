/**
* Name: evacuation - Extension 1 with Charts
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
    
    // Parameters for batch experiments
    float shelter_knowledge_ratio <- 0.95 min: 0.1 max: 1.0 step: 0.1;
    int nb_people <- 1000 min: 100 max: 10000 step: 100;
    float alert_duration <- 1800.0;
    
    // For charts
    float evacuation_percentage -> {(nb_evacuee / nb_people) * 100};
    
    init {
        create building from: shapefile_buildings with:[height::int(read("height"))];
        
        // Find the largest building to be the shelter
        shelter <- building with_max_of(each.shape.area);
        shelter.is_shelter <- true;
        
        create road from: shapefile_roads;
        road_network <- as_edge_graph(road);
        
        create inhabitant number: nb_people {
            location <- any_location_in(one_of(building));
            // Only 10% of the population will be aware of the evacuation
            is_aware <- flip(0.1);
            // Shelter knowledge is now controlled by parameter
            knows_shelter_location <- is_aware ? flip(shelter_knowledge_ratio) : false;
            current_building <- one_of(building where (each != shelter));
            target <- any_location_in(current_building);
            distance_to_shelter <- location distance_to shelter.location;
        }
        
        create red_river from: shapefile_river;
    }
    
    reflex check_end when: !simulation_finished {
        if (cycle * step >= alert_duration) or (inhabitant all_match (each.is_evacuated or !each.is_aware)) {
            simulation_finished <- true;
            total_evacuation_time <- cycle * step;
            total_evacuation_time <- cycle * step;
            write "Simulation finished at cycle " + cycle;
            write "Total evacuated: " + nb_evacuee;
            write "Evacuation percentage: " + evacuation_percentage;
            write "Evacuation time: " + total_evacuation_time;
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
        if knows_shelter_location or (distance_to_shelter < 20.0) {
            do goto target: shelter.location on: road_network;
            
            if distance_to_shelter < 2.0 {
                is_evacuated <- true;
                nb_evacuee <- nb_evacuee + 1;
                location <- any_location_in(shelter);
            }
        }
        else {
            do goto target: target on: road_network;
            if location distance_to target < 2.0 {
                current_building <- one_of(building where (each != shelter and each != current_building));
                target <- any_location_in(current_building);
            }
        }
        
        ask inhabitant at_distance 10.0 {
            if !self.is_aware and flip(0.1) {
                self.is_aware <- true;
                self.knows_shelter_location <- flip(shelter_knowledge_ratio);
            }
        }
    }
    
//    reflex evacuate when: is_aware and !is_evacuated {
//        do goto target: shelter.location on: road_network;
//        
//        // Check if reached shelter
//        if location distance_to shelter.location < 2.0 {
//            is_evacuated <- true;
//            nb_evacuee <- nb_evacuee + 1;
//            location <- any_location_in(shelter);
//        }
//        
//        // Inform nearby people at a distance of 10 meters
//        ask inhabitant at_distance 10.0 {
//            if !self.is_aware and flip(0.1) {
//                self.is_aware <- true;
//            }
//        }
//    }
    
    aspect default {
        draw circle(3) color: is_evacuated ? #green : (is_aware ? (knows_shelter_location ? #red : #orange) : #blue);
    }
}

species red_river {
    aspect default {
        draw shape color: #blue;
    }
}

experiment evacuation_single type: gui {
    parameter "Shelter knowledge ratio" var: shelter_knowledge_ratio min: 0.1 max: 1.0 step: 0.2;
    parameter "Number of people" var: nb_people min: 100 max: 10000 step: 100;
    
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
        monitor "Evacuation percentage" value: evacuation_percentage with_precision 2;
        monitor "Aware people" value: inhabitant count (each.is_aware);
        monitor "People knowing shelter" value: inhabitant count (each.knows_shelter_location);
    }
}

// Batch experiment to compare different shelter knowledge ratios
experiment evacuation_batch type: batch repeat: 3 until: simulation_finished {
    parameter "Shelter knowledge ratio" var: shelter_knowledge_ratio among: [0.1, 0.3, 0.5, 0.7, 1.0];
    parameter "Number of people" var: nb_people <- 1000;
    
    reflex save_results {
        save [cycle, shelter_knowledge_ratio, nb_evacuee, evacuation_percentage, total_evacuation_time] 
            to: "../results/evacuation_results.csv";
    }
    
    permanent {
        display "Evacuation Comparison" {
            chart "Evacuation Progress" type: series {
                data "Evacuation %" value: evacuation_percentage color: #blue;
                data "Knowledge ratio" value: shelter_knowledge_ratio * 100 color: #red;
            }
        }
    }
    
}