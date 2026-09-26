function [hw_new, Q_runoff] = water_table_update(hw_prev, rainfall_mmhr, dt_hr, Ksat, soilDepth)
%WATER_TABLE_UPDATE Dynamic lumped-bucket soil hydrology update.
%
%   [hw_new, Q_runoff] = water_table_update(hw_prev, rainfall_mmhr, ...
%                                            dt_hr, Ksat, soilDepth)
%
% Inputs:
%   hw_prev        MxN water table height above the failure plane (m)
%   rainfall_mmhr  scalar or MxN instantaneous rainfall intensity (mm/hr)
%   dt_hr          scalar timestep (hours)
%   Ksat           MxN (or scalar) saturated hydraulic conductivity (m/hr)
%   soilDepth      MxN (or scalar) total soil column depth (m)
%
% Outputs:
%   hw_new     MxN updated water table height (m), bounded [0, soilDepth]
%   Q_runoff   MxN surface runoff generated this timestep (m), i.e. the
%              rainfall fraction that could not infiltrate because the
%              soil column is already saturated or infiltration capacity
%              (Ksat) was exceeded.

    [rows, cols] = size(hw_prev);

    if isscalar(Ksat)
        Ksat = Ksat * ones(rows, cols);
    end
    if isscalar(soilDepth)
        soilDepth = soilDepth * ones(rows, cols);
    end
    if isscalar(rainfall_mmhr)
        rainfall_mmhr = rainfall_mmhr * ones(rows, cols);
    end

    % Convert rainfall intensity to a depth of water arriving this step (m)
    rainfall_m = (rainfall_mmhr / 1000) .* dt_hr;

    % Infiltration is capped by saturated hydraulic conductivity over the
    % timestep (Green-Ampt-like simplification for a lumped bucket).
    infiltrationCapacity_m = Ksat .* dt_hr;

    infiltrated_m = min(rainfall_m, infiltrationCapacity_m);
    excessRain_m = rainfall_m - infiltrated_m;   % cannot infiltrate -> runoff

    % Update water table storage
    hw_candidate = hw_prev + infiltrated_m;

    % Any storage above the soil column depth becomes additional runoff
    overflow_m = max(0, hw_candidate - soilDepth);
    hw_new = min(hw_candidate, soilDepth);
    hw_new = max(hw_new, 0);

    % Simple baseflow recession: a small fraction of stored water drains
    % slowly downslope/downward, preventing permanently saturated cells
    % once rainfall stops.
    recessionRate = 0.02; % fraction drained per hour
    hw_new = hw_new .* (1 - recessionRate * dt_hr);
    hw_new = max(hw_new, 0);

    Q_runoff = excessRain_m + overflow_m;
    Q_runoff = max(Q_runoff, 0);
end
