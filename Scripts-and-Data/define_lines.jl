#!/usr/bin/env julia

using PowerSystems
using CSV
using DataFrames

# reading in line data to a dataframe

line_params = CSV.read("Scripts-and-Data/Lines.csv", DataFrame)

# Defining all the lines
# not using Max Flow or Min Flow (both in MW in csv)

for i in 1:length(line_params[:, 1])
	num = lpad(i, 3, '0')
	bus_from = parse(Int, line_params[i, 2][4:6])
	bus_to = parse(Int, line_params[i, 3][4:6])
	if bus_params[bus_to+1, 8] == bus_params[bus_from+1, 8]
		local line = Line(;
           	name = "line$num",
           	available = true, #assumption
           	active_power_flow = 0.0, #assumption
           	reactive_power_flow = 0.0, #assumption
		   	arc = Arc(; from = buses[bus_from], to = buses[bus_to]),
           	r = line_params[i, 7], #in p.u.
           	x = line_params[i, 6], #in p.u.
           	b = (from = 0.0, to = 0.0), #assumption
           	rating = 0.0, #assumption
           	angle_limits = (min = 0.0, max = 0.0), #assumption
       	);
		add_component!(system, line)
	else
		local tline = Transformer2W(; #assuming if base volts diff, line is Trans2W as opposed to another kind of Transformer line
			name = "line$num",
           	available = true, #assumption
           	active_power_flow = 0.0, #assumption
           	reactive_power_flow = 0.0, #assumption
		   	arc = Arc(; from = buses[bus_from], to = buses[bus_to]),
           	r = line_params[i, 7], #in p.u.
           	x = line_params[i, 6], #in p.u.
			primary_shunt = 0.0, #assumption
           	rating = 0.0, #assumption
		);
		add_component!(system, tline)
	end
end
