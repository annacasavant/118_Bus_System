#!/usr/bin/env julia

using PowerSystems
using CSV
using DataFrames

# creating a system and initializing an array that all
# the buses go into (i.e. to find bus 1, do nodes18[1])
# also reading in bus data to a dataframe

sys_DA= System(100.0) #assuming base power 100MVA per-unitization
sys_RT = System(100.0) #assuming base power 100MVA per-unitization
bus_params = CSV.read("Scripts-and-Data/Buses.csv", DataFrame)

# Defining all the buses 

#buses = []
for i in 1:118
    num = lpad(i, 3, '0')
    min_volt = bus_params[i, "Voltage-Min (pu)"]
    max_volt = bus_params[i, "Voltage-Max (pu)"]
    base_volt = bus_params[i, "Base Voltage kV"]
    if bus_params[i, "Number"] == 69
    bus = ACBus(;
           number = i,
           name = "bus$num",
           bustype = ACBusTypes.REF,
           angle = 0.0,
           magnitude = 1.0,
           voltage_limits = (min = min_volt, max = max_volt),
           base_voltage = base_volt,
       )
    add_component!(sys_DA, bus)
    add_component!(sys_RT, bus)
    push!(buses, bus)
    else 
        bus = ACBus(;
        number = i,
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
 #push!(buses, bus)  
end

buses = sort!(get_buses(sys_DA, Set(1:length(bus_params[:, 1]))), by = n -> n.name);
