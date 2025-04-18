#=
Time Stamps: 
since csv is messed up, assuming values go with time in order, not how presented
changed year to 2023 so data skips leap day and ends on 1/1/24 of next year 
year is arbitrary since data is synthetic anyways.

Gen Data:
The csv was messed up in odd ways so had to hard code some edits to it to make
a dictionary that will be usable down the line. I only needed the gen name and
max capacity columns, and the entries go from rows go from 2 to 328, because
the first row of the csv has the column names, and after row 328, the entries
are null.

Hydro Time Series:
time series created for 16-35, 40-43
1-15, 36-39 monthly budget modified to get hourly
1-15 are dispatchable, rest are non-dispatchable

Deepcopy:
If Real Time system is built, so the variable build_RT == "YES", then deepcopy
is made before DA time series added to system.
=#

# Files and Variables: =================================================================================

# Establishing time series resolution and length

resolution = Dates.Hour(1);
timestamps = range(DateTime("2023-01-01T00:00:00"); step = resolution, length = 8784);

# Loading in and parsing generator names and max capacities

gencsv = CSV.read("Scripts-and-Data/Generators.csv", DataFrame)

gendata = Dict{String, Float64}()
for row in eachrow(gencsv[2:328, :])
    gendata[row[1]] = parse(Float64, replace(row[5], ',' => '.'))
end

# Hydro Time Series: ===================================================================================

hydro1_15 = sort(CSV.read("Scripts-and-Data/TimeSeries/Hydro/118-hydro.csv", DataFrame), [:3])
hydro36_39 = CSV.read("Scripts-and-Data/TimeSeries/Hydro/Hydro_nondispatchable.csv", DataFrame)[21:68, 1:8]
months = []
values = []
hydro_num = []

for row in eachrow(hydro1_15)
	if row[11] !== missing && row[4] == "Max Energy Month"
		push!(months, lpad(row[11][2:end], 2, '0'))
		push!(values, parse(Float64, row[5]))
		push!(hydro_num, row[3])
	end
end

for row in eachrow(hydro36_39)
	push!(months, lpad(row[8][2:end], 2, '0')) 
	push!(values, row[3])
	push!(hydro_num, row[1])
end

hydrobg = sort(DataFrame(Hydro=hydro_num, Month=months, Value=values), [:1, :2]);

# constructing time series from budgets

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

for hydro in collect(get_components(HydroDispatch, sys_DA))
    i = parse(Int, get_name(hydro)[7:end])
	if i<=15
		hydro_array = TimeArray(timestamps, time_series_list[i])
		hydro_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = hydro_array,
		   scaling_factor_multiplier = get_max_active_power,
       	);
	elseif 36<=i<=39
		hydro_array = TimeArray(timestamps, time_series_list[i-20])
		hydro_TS = SingleTimeSeries(;
           name = "max_active_power",
           data = hydro_array,
		   scaling_factor_multiplier = get_max_active_power,
       	);
	else
		local hydrodf = CSV.read("Scripts-and-Data/TimeSeries/Hydro/Hydro$(i).csv", DataFrame)
		deleteat!(hydrodf, 1417:1440)
		hydro_array = TimeArray(timestamps, (hydrodf[:, 2]./maximum(hydrodf[:, 2])))
		hydro_TS = SingleTimeSeries(;
          name = "max_active_power",
          data = hydro_array,
		  scaling_factor_multiplier = get_max_active_power,
       );
	end
    add_time_series!(sys_DA, hydro, hydro_TS)
end

# Solar and Wind RT Time Series: =======================================================================

if build_RT == "YES"

    global sys_RT = deepcopy(sys_DA)

    solar_RT_TS = DataFrame();

    for file in readdir("Scripts-and-Data/TimeSeries/RT/Solar/", join=true)
        num = lpad(file[43:end-6], 2, '0')
        data = CSV.read(file, DataFrame)[:, 2]
        solar_RT_TS[:, "Solar $(num)"] = data
    end

    wind_RT_TS = DataFrame();

    for file in readdir("Scripts-and-Data/TimeSeries/RT/Wind/", join=true)
        num = lpad(file[41:end-6], 2, '0')
        data = CSV.read(file, DataFrame)[:, 2]
        wind_RT_TS[:, "Wind $(num)"] = data
    end

    for renew in collect(get_components(RenewableDispatch, sys_RT))
        name = get_name(renew)
	    norm = gendata[name]
        if get_prime_mover_type(renew) == PrimeMovers.PVe
            renew_array = TimeArray(timestamps, (solar_RT_TS[:, name]./norm))
        elseif get_prime_mover_type(renew) == PrimeMovers.WT
            renew_array = TimeArray(timestamps, (wind_RT_TS[:, name]./norm))
        end
	    local renew_TS = SingleTimeSeries(;
            name = "max_active_power",
            data = renew_array,
		    scaling_factor_multiplier = get_max_active_power,
        );
        add_time_series!(sys_RT, renew, renew_TS)
    end
end

# Solar and Wind DA Time Series: =======================================================================

if build_DA == "YES"

    solar_DA_TS = DataFrame();

    for file in readdir("Scripts-and-Data/TimeSeries/DA/Solar/", join=true)
        num = lpad(file[43:end-6], 2, '0')
        data = CSV.read(file, DataFrame)[:, 2]
        solar_DA_TS[:, "Solar $(num)"] = data
    end

    wind_DA_TS = DataFrame();

    for file in readdir("Scripts-and-Data/TimeSeries/DA/Wind/", join=true)
        num = lpad(file[41:end-6], 2, '0')
        data = CSV.read(file, DataFrame)[:, 2]
        wind_DA_TS[:, "Wind $(num)"] = data
    end

    for renew in collect(get_components(RenewableDispatch, sys_DA))
        name = get_name(renew)
	    norm = gendata[name]
        if get_prime_mover_type(renew) == PrimeMovers.PVe
            renew_array = TimeArray(timestamps, (solar_DA_TS[:, name]./norm))
        elseif get_prime_mover_type(renew) == PrimeMovers.WT
            renew_array = TimeArray(timestamps, (wind_DA_TS[:, name]./norm))
        end
	    local renew_TS = SingleTimeSeries(;
            name = "max_active_power",
            data = renew_array,
		    scaling_factor_multiplier = get_max_active_power,
        );
        add_time_series!(sys_DA, renew, renew_TS)
    end
end
