#!/usr/bin/env julia

using PowerSystems
using CSV
using DataFrames
using Dates
using TimeSeries

# Time Stamps: 
# since csv is messed up, assuming values go with time in order, not how presented
# changed year to 2023 so data skips leap day and ends on 1/1/25 of next year 
# year is arbitrary since data is synthetic anyways

resolution = Dates.Hour(1);
timestamps = range(DateTime("2023-01-01T00:00:00"); step = resolution, length = 8784);
gendata = CSV.read("Scripts-and-Data/Generators.csv", DataFrame)

# Hydro RT and DA ==========================================================================
hydro_DA_RT_TS = []

#time series created for 16-35, 40-43
#1-15, 36-39 monthly budget modified to get hourly
#1-15 are dispatchable, rest are non-dispatchable

hydro1_15 = sort(CSV.read("Scripts-and-Data/TimeSeries/Hydro/118-hydro.csv", DataFrame), [:3])
hydro36_39 = CSV.read("Scripts-and-Data/TimeSeries/Hydro/Hydro_nondispatchable.csv", DataFrame)[21:68, 1:8]
months = []
values = []
hydro_num = []

for i in 1:length(hydro1_15[:, 1])
	if hydro1_15[i, 11] !== missing && hydro1_15[i, 4] == "Max Energy Month"
		push!(months, lpad(hydro1_15[i, 11][2:end], 2, '0'))
		push!(values, parse(Float64, hydro1_15[i, 5]))
		push!(hydro_num, hydro1_15[i, 3])
	end
end

for i in 1:48
	push!(months, lpad(hydro36_39[i, 8][2:end], 2, '0')) 
	push!(values, hydro36_39[i, 3])
	push!(hydro_num, hydro36_39[i, 1])
end

hydrobg = sort(DataFrame(Hydro=hydro_num, Month=months, Value=values), [:1, :2])

#constructing time series from budgets
time_series_list = []
daysofmonth = [31,28,31,30,31,30,31,31,30,31,30,32]

for i in 1:19
	local time_series = []
	for row in eachrow(hydrobg[12i-11:12i, :])
		local month = parse(Int, row[2])
		for j in 1:daysofmonth[month]
			for k in 1:24
				push!(time_series, row[3]/(24*daysofmonth[month]))
			end
		end
	end
	push!(time_series_list, (time_series./maximum(time_series)))
end

for i in 1:43
	if i<=15
		local hydro_array = TimeArray(timestamps, time_series_list[i])
		local hydro_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = hydro_array,
		   scaling_factor_multiplier = get_max_active_power, #assumption?
       	);
		push!(hydro_DA_RT_TS, hydro_TS);
	elseif 36<=i<=39
		local hydro_array = TimeArray(timestamps, time_series_list[i-20])
		local hydro_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = hydro_array,
		   scaling_factor_multiplier = get_max_active_power, #assumption?
       	);
		push!(hydro_DA_RT_TS, hydro_TS);
	else
		local hydrodf = CSV.read("Scripts-and-Data/TimeSeries/Hydro/Hydro$(i).csv", DataFrame)
		deleteat!(hydrodf, 1417:1440)
		local hydro_array = TimeArray(timestamps, (hydrodf[:, 2]./maximum(hydrodf[:, 2])))
		local hydro_TS = SingleTimeSeries(;
          name = "max_active_power",
          data = hydro_array,
		  scaling_factor_multiplier = get_max_active_power, #assumption?
       );
		push!(hydro_DA_RT_TS, hydro_TS);
	end
end

# Real Time: ====================================================================================

# loads: -------------------------
load_RT_TS = []

for i in 1:3
	local loaddf = CSV.read("Scripts-and-Data/TimeSeries/RT/Load/LoadR$(i)RT.csv", DataFrame)
	local load_array = TimeArray(timestamps, (loaddf[:, 2]./maximum(loaddf[:, 2])))
	local load_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = load_array,
		   scaling_factor_multiplier = get_max_active_power, #assumption?
       );
	push!(load_RT_TS, load_TS);
end

# solar: -------------------------
solar_RT_TS = []

for i in 1:75
	local solardf = CSV.read("Scripts-and-Data/TimeSeries/RT/Solar/Solar$(i)RT.csv", DataFrame)
	local norm = parse(Float64, replace(gendata[i+223,5], ',' => '.'))
	local solar_array = TimeArray(timestamps, (solardf[:, 2]./norm))
	local solar_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = solar_array,
		   scaling_factor_multiplier = get_max_active_power, #assumption?
       );
	push!(solar_RT_TS, solar_TS);
end

# wind: --------------------------
wind_RT_TS = []

for i in 1:17
	local winddf = CSV.read("Scripts-and-Data/TimeSeries/RT/Wind/Wind$(i)RT.csv", DataFrame)
	local norm = parse(Float64, replace(gendata[i+311,5], ',' => '.'))
	local wind_array = TimeArray(timestamps, (winddf[:, 2]./norm))
	local wind_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = wind_array,
		   scaling_factor_multiplier = get_max_active_power, #assumption?
       );
	push!(wind_RT_TS, wind_TS);
end

# Day Ahead: ===================================================================================

# loads: -------------------------
load_DA_TS = []

for i in 1:3
	local loaddf = CSV.read("Scripts-and-Data/TimeSeries/DA/Load/LoadR$(i)DA.csv", DataFrame)
	local load_array = TimeArray(timestamps, (loaddf[:, 2]./maximum(loaddf[:, 2])))
	local load_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = load_array,
		   scaling_factor_multiplier = get_max_active_power, #assumption?
       );
	push!(load_DA_TS, load_TS);
end

# solar: -------------------------
solar_DA_TS = []

for i in 1:75
	local solardf = CSV.read("Scripts-and-Data/TimeSeries/DA/Solar/Solar$(i)DA.csv", DataFrame)
	local norm = parse(Float64, replace(gendata[i+223,5], ',' => '.'))
	local solar_array = TimeArray(timestamps, (solardf[:, 2]./norm))
	local solar_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = solar_array,
		   scaling_factor_multiplier = get_max_active_power, #assumption?
       );
	push!(solar_DA_TS, solar_TS);
end

# wind: --------------------------
wind_DA_TS = []

for i in 1:17
	local winddf = CSV.read("Scripts-and-Data/TimeSeries/DA/Wind/Wind$(i)DA.csv", DataFrame)
	local norm = parse(Float64, replace(gendata[i+311,5], ',' => '.'))
	local wind_array = TimeArray(timestamps, (winddf[:, 2]./norm))
	local wind_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = wind_array,
		   scaling_factor_multiplier = get_max_active_power, #assumption?
       );
	push!(wind_DA_TS, wind_TS);
end
