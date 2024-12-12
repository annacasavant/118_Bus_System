#!/usr/bin/env julia

using PowerSystems
using CSV
using DataFrames

# creating a system and initializing an array that all
# the buses go into (i.e. to find bus 1, do nodes18[1])
# also reading in bus data to a dataframe

system = System(100.0) #assuming base power 100MVA per-unitization
bus_params = CSV.read("Scripts-and-Data/Buses.csv", DataFrame)

# Defining all the buses and adding them to nodes118

for i in 1:118
	num = lpad(i, 3, '0')
	min_volt = parse(Float64, bus_params[i+1,7])
	max_volt = parse(Float64, bus_params[i+1,6])
	local bus = ACBus(;
           number = i,
           name = "bus$num",
           bustype = ACBusTypes.REF,
           angle = 0.0, #assumption (csv column just empty)
           magnitude = 1.0, #assuming p.u.
           voltage_limits = (min = min_volt, max = max_volt), #in p.u.
           base_voltage = parse(Float64, bus_params[i+1, 8]), #in kV
       )
	add_component!(system, bus)
end

buses = sort!(get_buses(system, Set(1:length(bus_params[:, 1]))), by = n -> n.name);
