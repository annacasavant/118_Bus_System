
using CSV
using DataFrames
folder_path = "HydroTimeSeries/dispatchable"
csv_files = filter(f -> endswith(f, ".csv"), readdir(folder_path))

function remove_leap_day(df::DataFrame, start_row:: Int, end_row::Int)
    [start_row:end_row]
    return df[Not(start_row:end_row), :]
end

for file in csv_files
    df = CSV.read(joinpath(folder_path, file), DataFrame)
    cleaned_df = remove_leap_day(df, 1417, 1440)
    output_path = joinpath("HydroTimeSeries/dispatchable_cleaned", "cleaned_" * file)
    CSV.write(output_path, cleaned_df)
end
   