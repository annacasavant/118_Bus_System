#!/usr/bin/env julia

using PowerSystems
using CSV
using DataFrames

# reading in line data to a dataframe

line_params = CSV.read("Scripts-and-Data/Lines.csv", DataFrame)

# Defining all the lines
# not using Min Flow (both in MW in csv)

for row in eachrow(line_params) 
    num = lpad(rownumber(row), 3, '0')
    bus_from = parse(Int, row["Bus from "][4:6])
    bus_to = parse(Int, row["Bus to"][4:6])
    if bus_params[bus_to, "Base Voltage kV"] == bus_params[bus_from, "Base Voltage kV"]
        local line = Line(;
            name = "line$num",
            available = true,
            active_power_flow = 0.0,
            reactive_power_flow = 0.0,
            arc = Arc(; from = get_bus(sys_DA, bus_from), to = get_bus(sys_DA, bus_to)),
            r = row["Resistance (p.u.)"],
            x = row["Reactance (p.u.)"],
            b = (from = 0.0, to = 0.0),
            rating = row["Max Flow (MW)"]/100,
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
            arc = Arc(; from = get_bus(sys_DA, bus_from), to = get_bus(sys_DA, bus_to)),
            r = row["Resistance (p.u.)"],
            x = row["Reactance (p.u.)"],
            primary_shunt = 0.0,
            rating = row["Max Flow (MW)"]/100,
        );
        add_component!(sys_DA, tline)
		add_component!(sys_RT, tline)
    end
end
