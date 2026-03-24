#!/usr/bin/env julia

using PowerSystems
using CSV
using DataFrames
using Dates
using TimeSeries

# ============================================================================
# Define Time Series: Dynamic profiles for generators and loads
# ============================================================================
# This script creates time series data that shows how renewable generators
# (solar, wind, hydro) and loads vary throughout the day. Time series are
# essential for realistic power system simulation and optimization.

# Create hourly timestamps for a full year + 1 day (8784 hours = 366 days)
# Note: Year 2023 (not leap) is used as arbitrary reference since data is synthetic
resolution = Dates.Hour(1)
timestamps = range(DateTime("2023-01-01T00:00:00"); step = resolution, length = 8784);
gendata = CSV.read("Scripts-and-Data/Generators.csv", DataFrame)

# ============================================================================
# Hydroelectric Time Series: Monthly energy budgets converted to hourly profiles
# ============================================================================
# Hydro generators are constrained by available water resources (seasonal variation).
# This section reads monthly energy budgets and distributes them uniformly across
# each month to create hourly generation profiles. The approach differs based on
# generator availability:
#   - Hydro 1-15, 36-39: Dispatchable (can be managed up to their monthly budget)
#   - Hydro 16-35, 40-43: Non-dispatchable (must follow fixed pre-computed profiles)

hydro_DA_RT_TS = []
hydro_DA_RT_max = []

# Read monthly budget data from CSV files
# hydro1_15 contains monthly energy budgets for generators 1-15 (from 118-hydro.csv)
# hydro36_39 contains monthly energy budgets for generators 36-39 (from Hydro_nondispatchable.csv)
hydro1_15 = sort(CSV.read("Scripts-and-Data/TimeSeries/Hydro/118-hydro.csv", DataFrame), [:3])
hydro36_39 = CSV.read("Scripts-and-Data/TimeSeries/Hydro/Hydro_nondispatchable.csv", DataFrame)[21:68, 1:8]

# Initialize arrays to store extracted energy budget data
months = []      # Month numbers (01-12)
values = []      # Maximum energy available (MWh) for each hydro in that month
hydro_num = []   # Generator number

# Extract monthly energy budgets for hydro 1-15
# Look for rows marked with "Max Energy Month" which indicate the energy constraint
for row in eachrow(hydro1_15)
	if row[11] !== missing && row[4] == "Max Energy Month"
		push!(months, lpad(row[11][2:end], 2, '0'))
		push!(values, parse(Float64, row[5]))
		push!(hydro_num, row[3])
	end
end

# Extract monthly energy budgets for hydro 36-39
for row in eachrow(hydro36_39)
	push!(months, lpad(row[8][2:end], 2, '0')) 
	push!(values, row[3])
	push!(hydro_num, row[1])
end

# Organize budget data into a sorted DataFrame for easy access by hydro generator and month
hydrobg = sort(DataFrame(Hydro=hydro_num, Month=months, Value=values), [:1, :2])

# ============================================================================
# Convert Monthly Budgets to Hourly Profiles (Dispatchable Hydro: 1-15, 36-39)
# ============================================================================
# Strategy: Distribute monthly energy uniformly across each hour in the month.
# This allows the unit commitment/dispatch algorithm to spread generation
# naturally across the month while respecting the total monthly energy limit.

# Array to store normalized hourly time series profiles
time_series_list = []
time_series_list_max = []

# Days in each month (accounting for additional day end of 2023 in December)
daysofmonth = [31,28,31,30,31,30,31,31,30,31,30,32]

# For each dispatchable hydro unit (1-19 in the database, maps to units 1-15 and 36-39)
for i in 1:19
	local time_series = []
	
	# Get the 12 monthly budget entries for this hydro unit (rows for Jan-Dec)
	for row in eachrow(hydrobg[12i-11:12i, :])
		local month = parse(Int, row[2])
		
		# Distribute the monthly energy budget uniformly across all hours in that month
		# For example: If month has 30 days -> 30 * 24 = 720 hours
		#             If energy budget is 7200 MWh -> 7200 / 720 = 10 MW per hour
		for j in 1:daysofmonth[month]
			for k in 1:24
				push!(time_series, row[3]/(24*daysofmonth[month]))
			end
		end
	end
	
	# Normalize the time series to 0-1 range (will be scaled by generator's rating)
	push!(time_series_list, (time_series./maximum(time_series)))
	push!(time_series_list_max, maximum(time_series))
end

# ============================================================================
# Assign Time Series to Each Hydro Generator (1-43)
# ============================================================================
# Different hydro generators use different data sources based on availability:
#
# Hydro 1-15:   Use computed monthly-budget profiles (dispatchable)
#               Indexed directly from time_series_list [1-15]
#
# Hydro 16-35:  Pre-computed hourly profiles from individual CSV files
#               Loaded directly from TimeSeries/Hydro/Hydro{i}.csv
#
# Hydro 36-39:  Use computed monthly-budget profiles from hydro_nondispatchable data
#               Indexed with offset: time_series_list[i-20]
#
# Hydro 40-43:  Pre-computed hourly profiles from individual CSV files
#               Loaded directly from TimeSeries/Hydro/Hydro{i}.csv

for i in 1:43
	if i<=15
		# Dispatchable hydro with monthly budgets (1-15)
		local hydro_array = TimeArray(timestamps, time_series_list[i])
		local hydro_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = hydro_array,
		   scaling_factor_multiplier = get_max_active_power,
       	);
		push!(hydro_DA_RT_TS, hydro_TS);
		push!(hydro_DA_RT_max, time_series_list_max[i]);
	elseif 36<=i<=39
		# Dispatchable hydro with managed water resources (36-39)
		# Maps to indices 16-19 in time_series_list (19-20 through 22-20)
		local hydro_array = TimeArray(timestamps, time_series_list[i-20])
		local hydro_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = hydro_array,
		   scaling_factor_multiplier = get_max_active_power,
       	);
		push!(hydro_DA_RT_TS, hydro_TS);
		push!(hydro_DA_RT_max, time_series_list_max[i-20]);
	else
		# Non-dispatchable hydro with fixed hourly profiles (16-35, 40-43)
		# These read pre-computed profiles that cannot be adjusted by the solver
		local hydrodf = CSV.read("Scripts-and-Data/TimeSeries/Hydro/Hydro$(i).csv", DataFrame)
		# Remove last 24 hours (row 1417-1440) to match 8784-hour annual data
		deleteat!(hydrodf, 1417:1440)
		local hydro_array = TimeArray(timestamps, (hydrodf[:, 2]./maximum(hydrodf[:, 2])))
		local hydro_TS = SingleTimeSeries(;
          name = "max_active_power",
          data = hydro_array,
		  scaling_factor_multiplier = get_max_active_power,
       );
		push!(hydro_DA_RT_TS, hydro_TS);
		push!(hydro_DA_RT_max, maximum(hydrodf[:, 2]));
	end
end

# ============================================================================
# Real-Time (RT) Time Series for Solar and Wind
# ============================================================================
# Real-time profiles capture actual (or simulated actual) generation output
# at each hour. They are used in real-time dispatch simulations that operate
# closer to the actual operating hour when conditions are better known.
#
# Normalization: Each generator's output (MW) is divided by its rated capacity
# (also in MW from Generators.csv) and then by sys_base_power (100 MVA) to
# convert to per-unit on the system base. This ensures values are in [0, 1].

solar_RT_TS = []
solar_RT_max = []
sys_base_power = 100.0

# Create time series for each of the 75 solar generators
# Solar generators start at row 224 in Generators.csv (offset i+223)
for i in 1:75
	local solardf = CSV.read("Scripts-and-Data/TimeSeries/RT/Solar/Solar$(i)RT.csv", DataFrame)
	# norm is the rated capacity (MW) of this generator, used to normalize output
	local norm = parse(Float64, replace(gendata[i+223,5], ',' => '.'))
	# Divide by rated capacity then by system base to get per-unit values
	local solar_array = TimeArray(timestamps, (solardf[:, 2]./norm))
	local solar_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = solar_array,
		   # scaling_factor_multiplier tells PowerSystems how to scale the [0,1]
		   # profile back to actual power using the component's max_active_power
		   scaling_factor_multiplier = get_max_active_power,
       );
	push!(solar_RT_TS, solar_TS);
	push!(solar_RT_max, norm);
end

# Create time series for each of the 17 wind generators
# Wind generators start at row 312 in Generators.csv (offset i+311)
wind_RT_TS = []
wind_RT_max = []

for i in 1:17
	local winddf = CSV.read("Scripts-and-Data/TimeSeries/RT/Wind/Wind$(i)RT.csv", DataFrame)
	# norm is the rated capacity (MW) of this generator, used to normalize output
	local norm = parse(Float64, replace(gendata[i+311,5], ',' => '.'))
	local wind_array = TimeArray(timestamps, (winddf[:, 2]./norm))
	local wind_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = wind_array,
		   scaling_factor_multiplier = get_max_active_power,
       );
	push!(wind_RT_TS, wind_TS);
	push!(wind_RT_max, norm);
end

# ============================================================================
# Day-Ahead (DA) Time Series for Solar and Wind
# ============================================================================
# Day-ahead profiles represent forecasted renewable output, typically produced
# 12-24 hours before actual operation. Schedulers use these forecasts to plan
# generator commitments and economic dispatch for the upcoming day.
#
# The normalization procedure is identical to RT: divide raw MW output by the
# generator's rated capacity and system base power to obtain per-unit values.
# The DA and RT profiles may differ, reflecting forecast vs. actual output.

# Create day-ahead time series for each of the 75 solar generators
solar_DA_TS = []
solar_DA_max = []

for i in 1:75
	local solardf = CSV.read("Scripts-and-Data/TimeSeries/DA/Solar/Solar$(i)DA.csv", DataFrame)
	# norm is the rated capacity (MW) — same offset as RT since it's the same generator
	local norm = parse(Float64, replace(gendata[i+223,5], ',' => '.'))
	local solar_array = TimeArray(timestamps, (solardf[:, 2]./norm))
	local solar_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = solar_array,
		   scaling_factor_multiplier = get_max_active_power,
       );
	push!(solar_DA_TS, solar_TS);
	push!(solar_DA_max, norm);
end

# Create day-ahead time series for each of the 17 wind generators
wind_DA_TS = []
wind_DA_max = []

for i in 1:17
	local winddf = CSV.read("Scripts-and-Data/TimeSeries/DA/Wind/Wind$(i)DA.csv", DataFrame)
	# norm is the rated capacity (MW) — same offset as RT since it's the same generator
	local norm = parse(Float64, replace(gendata[i+311,5], ',' => '.'))
	local wind_array = TimeArray(timestamps, (winddf[:, 2]./norm))
	local wind_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = wind_array,
		   scaling_factor_multiplier = get_max_active_power,
       );
	push!(wind_DA_TS, wind_TS);
	push!(wind_DA_max, norm);
end
