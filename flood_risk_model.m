function FloodDepth_new = flood_risk_model(SpatialData, FloodDepth_prev, Q_runoff, dt_hr)
%FLOOD_RISK_MODEL Depression-storage / valley flood routing.
%
%   FloodDepth_new = flood_risk_model(SpatialData, FloodDepth_prev, ...
%                                      Q_runoff, dt_hr)
%
% A cellular flow-routing scheme: runoff volume generated at each cell
% (from water_table_update) is added to a local ponded-depth field, then
% redistributed toward the steepest-descent neighbor of the *water
% surface* elevation (ground elevation + depth) over several relaxation
% sub-iterations, approximating catchment-scale depression filling and
% downslope valley routing without requiring the Image Processing
% Toolbox.
%
% Inputs:
%   SpatialData      struct from load_geospatial_data (.Elevation, .CellSizeM)
%   FloodDepth_prev   MxN previous ponded water depth (m)
%   Q_runoff          MxN runoff depth generated this timestep (m)
%   dt_hr             scalar timestep (hours), used to scale outflow to
%                      the boundary (open drainage at raster edges)
%
% Output:
%   FloodDepth_new    MxN updated ponded water depth (m)

    Elevation = SpatialData.Elevation;
    [rows, cols] = size(Elevation);

    depth = FloodDepth_prev + Q_runoff;
    depth(isnan(depth)) = 0;
    groundValid = ~isnan(Elevation);
    fillElev = Elevation;
    fillElev(~groundValid) = -Inf; % nodata treated as open drain (ocean/void)

    nSubIter = 6;
    flowFraction = 0.35; % fraction of head difference exchanged per sub-step

    % 8-connected neighbor offsets
    dRow = [-1 -1 -1  0 0  1 1 1];
    dCol = [-1  0  1 -1 1 -1 0 1];

    for iter = 1:nSubIter
        waterSurface = fillElev + depth;
        outflow = zeros(rows, cols);
        inflow = zeros(rows, cols);

        for k = 1:8
            shiftedWS = nan(rows, cols);
            r1 = max(1, 1 - dRow(k)); r2 = min(rows, rows - dRow(k));
            c1 = max(1, 1 - dCol(k)); c2 = min(cols, cols - dCol(k));

            srcR1 = r1 + dRow(k); srcR2 = r2 + dRow(k);
            srcC1 = c1 + dCol(k); srcC2 = c2 + dCol(k);

            shiftedWS(r1:r2, c1:c2) = waterSurface(srcR1:srcR2, srcC1:srcC2);

            headDiff = waterSurface - shiftedWS; % positive = flows toward neighbor
            headDiff(isnan(headDiff)) = 0;
            headDiff = max(headDiff, 0);

            transferable = min(depth, headDiff / 2) * flowFraction / 8;
            transferable(isnan(transferable)) = 0;

            outflow = outflow + transferable;

            neighborGetsFlow = zeros(rows, cols);
            neighborGetsFlow(srcR1:srcR2, srcC1:srcC2) = transferable(r1:r2, c1:c2);
            inflow = inflow + neighborGetsFlow;
        end

        depth = max(0, depth - outflow + inflow);

        % Open-boundary drainage: raster edges lose a fraction of their
        % ponded depth each sub-iteration, representing water leaving the
        % modeled catchment via the wider river network.
        edgeDrainRate = 0.05 * dt_hr;
        depth(1, :)   = depth(1, :)   * (1 - edgeDrainRate);
        depth(end, :) = depth(end, :) * (1 - edgeDrainRate);
        depth(:, 1)   = depth(:, 1)   * (1 - edgeDrainRate);
        depth(:, end) = depth(:, end) * (1 - edgeDrainRate);

        depth(~groundValid) = 0;
    end

    FloodDepth_new = depth;
end
