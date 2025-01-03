#!/usr/bin/env julia

using PowerSystems
using CSV
using DataFrames

# reading in line data to a dataframe

line_params = CSV.read("Scripts-and-Data/Lines.csv", DataFrame)

# Defining all the lines
# not using Max Flow or Min Flow (both in MW in csv)

lines = []

for i in 1:186
    num = lpad(i, 3, '0')
    bus_from = parse(Int, line_params[i, "Bus from "][4:6])
    bus_to = parse(Int, line_params[i, "Bus to"][4:6])
    if bus_params[bus_to, "Base Voltage kV"] == bus_params[bus_from, "Base Voltage kV"]
        local line = Line(;
            name = "line$num",
            available = true,
            active_power_flow = 0.0,
            reactive_power_flow = 0.0,
            arc = Arc(; from = buses[bus_from], to = buses[bus_to]),
            r = line_params[i, 7],
            x = line_params[i, 6],
            b = (from = 0.0, to = 0.0),
            rating = line_params[i, "Max Flow (MW)"]/100,
            angle_limits = (min = 0.0, max = 0.0),
        );
        add_component!(sys_DA, line)
		add_component!(sys_RT, line)
    else
        local tline = Transformer2W(;
            name = "line$num",
            available = true,
            active_power_flow = 0.0,
            reactive_power_flow = 0.0,
            arc = Arc(; from = buses[bus_from], to = buses[bus_to]),
            r = line_params[i, 7],
            x = line_params[i, 6],
            primary_shunt = 0.0,
            rating = line_params[i, "Max Flow (MW)"]/100,
        );
        add_component!(sys_DA, tline)
		add_component!(sys_RT, tline)
    end
end
