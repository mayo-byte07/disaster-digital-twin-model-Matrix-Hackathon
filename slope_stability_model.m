function FS = slope_stability_model(SpatialData, hw, soilDepth, c_eff, phi_eff, gamma_sat, gamma_w)
%SLOPE_STABILITY_MODEL Infinite-slope Factor of Safety field with
% transient pore-water pressure driven by a partially saturated soil
% column (Griffiths & Lane style infinite-slope formulation).
%
%   FS = slope_stability_model(SpatialData, hw, soilDepth, c_eff, ...
%                               phi_eff, gamma_sat, gamma_w)
%
% Inputs:
%   SpatialData  struct from load_geospatial_data (uses .Slope, degrees)
%   hw           MxN water table height above failure plane (m)
%   soilDepth    MxN or scalar total soil depth to failure plane Z (m)
%   c_eff        effective cohesion c' (kPa)
%   phi_eff      effective friction angle phi' (degrees)
%   gamma_sat    saturated unit weight of lateritic soil (kN/m^3)
%   gamma_w      unit weight of water (kN/m^3), typically 9.81
%
% Output:
%   FS  MxN Factor of Safety field. Flat/near-flat cells (beta ~ 0) are
%       assigned a high FS ceiling to avoid division-by-zero singularities.

    beta = SpatialData.Slope; % degrees
    [rows, cols] = size(beta);

    if isscalar(soilDepth)
        Z = soilDepth * ones(rows, cols);
    else
        Z = soilDepth;
    end

    % Saturation ratio m = hw/Z, bounded [0, 1]
    Z_safe = max(Z, 0.01);
    m = min(max(hw ./ Z_safe, 0), 1);

    betaRad = deg2rad(beta);
    phiRad = deg2rad(phi_eff);

    sinB = sin(betaRad);
    cosB = cos(betaRad);
    tanB = tan(betaRad);
    tanPhi = tan(phiRad);

    FS_CEILING = 10;
    FS = FS_CEILING * ones(rows, cols);

    flatMask = beta < 1.0;          % effectively flat, not slope-failure prone
    steepMask = ~flatMask;

    denom = gamma_sat .* Z .* sinB .* cosB;
    denom(denom < eps) = eps;

    cohesionTerm = c_eff ./ denom;
    frictionTerm = ((1 - m .* (gamma_w / gamma_sat)) .* tanPhi) ./ max(tanB, eps);

    FS_computed = cohesionTerm + frictionTerm;

    FS(steepMask) = FS_computed(steepMask);
    FS(flatMask) = FS_CEILING;

    FS = min(max(FS, 0), FS_CEILING);
    FS(isnan(FS)) = FS_CEILING;
end
