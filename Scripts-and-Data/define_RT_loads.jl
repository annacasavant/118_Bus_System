#!/usr/bin/env julia

using PowerSystems
using CSV
using DataFrames
using Dates
using InfrastructureSystems

# initializing an array that all
# the loads go into (i.e. to find load 1, do loads_RT_118[1])
# reading load data for each region into arrays

R1RTdf = CSV.read("Scripts-and-Data/TimeSeries/RT/Load/LoadR1RT.csv", DataFrame);
R2RTdf = CSV.read("Scripts-and-Data/TimeSeries/RT/Load/LoadR2RT.csv", DataFrame);
R3RTdf = CSV.read("Scripts-and-Data/TimeSeries/RT/Load/LoadR3RT.csv", DataFrame);
partfact = sort!(CSV.read("Scripts-and-Data/partfact.csv", DataFrame));
loads_RT_R1 = []
loads_RT_R2 = []
loads_RT_R3 = []

# Defining all the loads and adding them to lists
# adding loads and time series into system

for i in 1:118 
	num = lpad(i, 3, '0')
	if parse(Int, partfact[i, 2][2]) == 1
		local max1 = maximum(R1RTdf[:, 2])
		local load = PowerLoad(;
    		name = "load$num",
    		available = true,
    		bus = buses[i],
    		active_power = 0.0, #per-unitized by device base_power
    		reactive_power = 0.0, #per-unitized by device base_power
    		base_power = 100.0, # MVA, for loads match system
    		max_active_power = (max1)*(partfact[i, 3]), #per-unitized by device base_power?
    		max_reactive_power = 0.0,
    	);
		add_component!(system, load)
		push!(loads_RT_R1, load)
	elseif parse(Int, partfact[i, 2][2]) == 2 
		local max2 = maximum(R2RTdf[:, 2])
		local load = PowerLoad(;
    		name = "load$num",
    		available = true,
    		bus = buses[i],
    		active_power = 0.0, #per-unitized by device base_power
    		reactive_power = 0.0, #per-unitized by device base_power
    		base_power = 100.0, # MVA, for loads match system
    		max_active_power = (max2)*(partfact[i, 3]), #per-unitized by device base_power?
    		max_reactive_power = 0.0,
    	);
		add_component!(system, load)
		push!(loads_RT_R2, load)
	else parse(Int, partfact[i, 2][2]) == 3
		local max3 = maximum(R3RTdf[:, 2])
		local load = PowerLoad(;
    		name = "load$num",
    		available = true,
    		bus = buses[i],
    		active_power = 0.0, #per-unitized by device base_power
    		reactive_power = 0.0, #per-unitized by device base_power
    		base_power = 100.0, # MVA, for loads match system
    		max_active_power = (max3)*(partfact[i, 3]), #per-unitized by device base_power?
    		max_reactive_power = 0.0,
    	);
		add_component!(system, load)
		push!(loads_RT_R3, load)
	end
end

associations1 = (
    InfrastructureSystems.TimeSeriesAssociation(
        load,
        load_RT_TS[1],)
    for load in loads_RT_R1
)
bulk_add_time_series!(system, associations1)

associations2 = (
    InfrastructureSystems.TimeSeriesAssociation(
        load,
        load_RT_TS[2],)
    for load in loads_RT_R2
)
bulk_add_time_series!(system, associations2)

associations3 = (
    InfrastructureSystems.TimeSeriesAssociation(
        load,
        load_RT_TS[3],)
    for load in loads_RT_R3
)
bulk_add_time_series!(system, associations3)
