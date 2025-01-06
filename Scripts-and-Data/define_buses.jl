#!/usr/bin/env julia

using PowerSystems
using CSV
using DataFrames

# defining DA and RT systems
# reading in bus data to a dataframe

sys_DA= System(100.0) #assuming base power 100MVA per-unitization
sys_RT = System(100.0) #assuming base power 100MVA per-unitization
bus_params = CSV.read("Scripts-and-Data/Buses.csv", DataFrame)

# Defining all the buses 

for row in eachrow(bus_params)
    num = lpad(row["Number"], 3, '0')
    min_volt = row["Voltage-Min (pu)"]
    max_volt = row["Voltage-Max (pu)"]
    base_volt = row["Base Voltage kV"]
    if row["Number"] == 69
    	bus = ACBus(;
           number = parse(Int64, num),
           name = "bus$num",
           bustype = ACBusTypes.REF,
           angle = 0.0,
           magnitude = 1.0,
           voltage_limits = (min = min_volt, max = max_volt),
           base_voltage = base_volt,
       	)
    else 
        bus = ACBus(;
        number = parse(Int64, num),
        name = "bus$num",
        bustype = ACBusTypes.PQ,
        angle = 0.0,
        magnitude = 1.0,
        voltage_limits = (min = min_volt, max = max_volt),
        base_voltage = base_volt,
    	)
	end
 	add_component!(sys_DA, bus)
 	add_component!(sys_RT, bus)
end

buses = sort!(get_buses(sys_DA, Set(1:length(bus_params[:, 1]))), by = n -> n.name);
