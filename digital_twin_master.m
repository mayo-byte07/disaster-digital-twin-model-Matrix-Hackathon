%% DIGITAL_TWIN_MASTER
% Predictive Disaster Area Digital Twin & Citizen Evacuation System
% Wayanad, Kerala — Master Simulation Driver
%
% Runs a 48-hour predictive loop coupling live rainfall forecasts,
% transient pore-water pressure slope stability, valley flood routing,
% socio-economic damage assessment, hazard-aware citizen evacuation
% routing, and automated emergency webhook dispatch.
%
% Requires: Mapping Toolbox (readgeoraster, shaperead, geographicToDiscrete)
%           Base MATLAB graph/digraph, shortestpath
%
% Configure the four file paths / webhook URL below, then run this script.

clear; clc; close all;

%% ============================= CONFIGURATION =============================
demFile        = 'wayanad_dem.tif';
roadsFile      = 'wayanad_roads.shp';
buildingsFile  = 'wayanad_buildings.shp';
webhookURL     = 'https://hooks.example-emergency-dispatch.org/wayanad-alert';

% Geotechnical parameters (saturated lateritic soil, Western Ghats)
soilDepth_m    = 2.5;    % m, depth to failure plane
c_eff_kPa      = 8.0;    % kPa, effective cohesion
phi_eff_deg    = 28.0;   % degrees, effective friction angle
gamma_sat_kN   = 19.5;   % kN/m^3, saturated unit weight
gamma_w_kN     = 9.81;   % kN/m^3, unit weight of water
Ksat_m_per_hr  = 0.015;  % m/hr, saturated hydraulic conductivity

% Alert thresholds
FS_CRITICAL      = 1.0;
FLOOD_CRITICAL_M = 0.5;
ALERT_DAMAGE_THRESHOLD = 5; % buildings damaged before RED alert dispatch

% Demo citizen check-in location (can be replaced with live GPS input)
citizenLat = 11.6050 ;
citizenLon = 76.0850;

%% ============================= INITIALIZATION =============================
fprintf('=== Wayanad Predictive Disaster Digital Twin: Initializing ===\n');

SpatialData = load_geospatial_data(demFile, roadsFile, buildingsFile);

[time_vector, rainfall_forecast_mmhr] = fetch_live_weather();

[rows, cols] = size(SpatialData.Elevation);
hw = zeros(rows, cols);              % water table height field (m)
FloodDepth = zeros(rows, cols);      % ponded flood depth field (m)

dt_hr = 1.0;
nSteps = numel(rainfall_forecast_mmhr);

alertDispatched = false;

%% ============================= FIGURE SETUP =============================
fig = figure('Name', 'Wayanad Predictive Disaster Digital Twin', ...
             'Color', [0.08 0.08 0.10], 'Position', [50 50 1400 800]);

axTerrain = subplot(1, 2, 1);
axTelemetry = subplot(1, 2, 2);

[Xgrid, Ygrid] = meshgrid(1:cols, 1:rows);

%% ============================= 48-HOUR PREDICTIVE LOOP =============================
for step = 1:nSteps

    currentRainfall = rainfall_forecast_mmhr(step);

    % --- Hydrology: update water table & runoff -----------------------------
    [hw, Q_runoff] = water_table_update(hw, currentRainfall, dt_hr, Ksat_m_per_hr, soilDepth_m);

    % --- Slope stability: transient FS field ---------------------------------
    FS = slope_stability_model(SpatialData, hw, soilDepth_m, c_eff_kPa, phi_eff_deg, ...
                                gamma_sat_kN, gamma_w_kN);

    % --- Flood routing: depression-storage valley routing --------------------
    FloodDepth = flood_risk_model(SpatialData, FloodDepth, Q_runoff, dt_hr);

    % --- Damage & socio-economic triage ---------------------------------------
    ImpactReport = damage_and_loss_assessor(SpatialData, FS, FloodDepth);

    % --- Determine alert level -------------------------------------------------
    if ImpactReport.DamagedBuildings == 0
        alertLevel = 'GREEN';
    elseif ImpactReport.DamagedBuildings < ALERT_DAMAGE_THRESHOLD
        alertLevel = 'YELLOW';
    elseif ImpactReport.DamagedBuildings < 3 * ALERT_DAMAGE_THRESHOLD
        alertLevel = 'ORANGE';
    else
        alertLevel = 'RED';
    end

    % --- Automated webhook dispatch on threshold crossing -----------------------
    if strcmp(alertLevel, 'RED') && ~alertDispatched
        send_alert_webhook(alertLevel, ImpactReport.DisplacedPopulation, ...
            ImpactReport.DirectLoss_INR, webhookURL);
        alertDispatched = true;
    end

    % --- Simulated citizen emergency check-in (mid-simulation trigger) ----------
    evacuation_url = '';
    routeInfo = struct('Status', 'NOT_TRIGGERED');
    if step == round(nSteps / 2)
        try
            [evacuation_url, routeInfo] = citizen_evacuation_routing(SpatialData, FS, ...
                FloodDepth, citizenLat, citizenLon);
        catch ME
            warning('digital_twin_master:RoutingFailed', 'Evacuation routing failed: %s', ME.message);
        end
    end

    %% ---- Panel 1: 3D terrain with FS risk colormap, flood surface, buildings ----
    cla(axTerrain);
    axes(axTerrain); %#ok<LAXES>
    hold(axTerrain, 'on');

    surf(axTerrain, Xgrid, Ygrid, SpatialData.Elevation, FS, ...
        'EdgeColor', 'none', 'FaceAlpha', 0.95);
    colormap(axTerrain, flipud(autumn));
    cb = colorbar(axTerrain);
    cb.Label.String = 'Factor of Safety (FS)';
    cb.Color = [1 1 1];
    caxis(axTerrain, [0 3]);

    floodSurf = SpatialData.Elevation + FloodDepth;
    floodSurf(FloodDepth < 0.02) = NaN;
    surf(axTerrain, Xgrid, Ygrid, floodSurf, ...
        'FaceColor', [0.2 0.5 0.9], 'FaceAlpha', 0.55, 'EdgeColor', 'none');

    Buildings = SpatialData.Buildings;
    for k = 1:numel(Buildings)
        r = Buildings(k).RowIdx;
        c = Buildings(k).ColIdx;
        if isnan(r) || isnan(c)
            continue;
        end
        z = SpatialData.Elevation(r, c) + 5;
        if ImpactReport.BuildingStatus(k)
            plot3(axTerrain, c, r, z, 'rs', 'MarkerFaceColor', 'r', 'MarkerSize', 4);
        else
            plot3(axTerrain, c, r, z, 'gs', 'MarkerFaceColor', 'g', 'MarkerSize', 3);
        end
    end

    if strcmp(routeInfo.Status, 'ROUTE_FOUND')
        pathRow = zeros(size(routeInfo.PathLat));
        pathCol = zeros(size(routeInfo.PathLon));
        for i = 1:numel(routeInfo.PathLat)
            try
                [pr, pc] = geographicToDiscrete(SpatialData.R, routeInfo.PathLat(i), routeInfo.PathLon(i));
                pathRow(i) = pr;
                pathCol(i) = pc;
            catch
                pathRow(i) = NaN;
                pathCol(i) = NaN;
            end
        end
        validPath = ~isnan(pathRow);
        pathZ = interp2(Xgrid, Ygrid, SpatialData.Elevation, pathCol(validPath), pathRow(validPath)) + 15;
        plot3(axTerrain, pathCol(validPath), pathRow(validPath), pathZ, ...
            'c-', 'LineWidth', 2.5);
    end

    hold(axTerrain, 'off');
    view(axTerrain, -35, 55);
    axis(axTerrain, 'tight');
    xlabel(axTerrain, 'Grid Column'); ylabel(axTerrain, 'Grid Row'); zlabel(axTerrain, 'Elevation (m)');
    title(axTerrain, sprintf('Wayanad Digital Twin — Hour %d/%d', step, nSteps), 'Color', [1 1 1]);
    set(axTerrain, 'Color', [0.08 0.08 0.10], 'XColor', [1 1 1], 'YColor', [1 1 1], 'ZColor', [1 1 1]);

    %% ---- Panel 2: Live telemetry metrics -------------------------------------
    cla(axTelemetry);
    axes(axTelemetry); %#ok<LAXES>
    axis(axTelemetry, 'off');
    set(axTelemetry, 'Color', [0.08 0.08 0.10]);

    switch alertLevel
        case 'GREEN',  alertColor = [0.2 0.8 0.3];
        case 'YELLOW', alertColor = [0.95 0.85 0.2];
        case 'ORANGE', alertColor = [0.95 0.55 0.15];
        otherwise,     alertColor = [0.9 0.15 0.15];
    end

    telemetryStr = { ...
        sprintf('TIME: %s', datestr(time_vector(step), 'dd-mmm HH:MM')); %#ok<DATST>
        '';
        sprintf('Rainfall Forecast: %.1f mm/hr', currentRainfall);
        sprintf('Peak Water Table:  %.2f m', max(hw(:)));
        sprintf('Max Flood Depth:   %.2f m', max(FloodDepth(:)));
        '';
        sprintf('Damaged Buildings: %d / %d', ImpactReport.DamagedBuildings, ImpactReport.TotalBuildings);
        sprintf('Displaced Population: %d', ImpactReport.DisplacedPopulation);
        sprintf('Direct Loss: Rs %.0f  (~$%.0f)', ImpactReport.DirectLoss_INR, ImpactReport.DirectLoss_USD);
        sprintf('Priority NDRF Zones: %d', numel(ImpactReport.PriorityZones));
        '';
        sprintf('ALERT STATUS: %s', alertLevel); ...
        sprintf('Webhook Dispatched: %d', alertDispatched); ...
        };

    text(axTelemetry, 0.05, 0.95, telemetryStr, 'Color', [1 1 1], ...
        'FontSize', 12, 'VerticalAlignment', 'top', 'FontName', 'Consolas');

    rectangle(axTelemetry, 'Position', [0.05 0.02 0.9 0.08], 'FaceColor', alertColor, ...
        'EdgeColor', 'none', 'Curvature', 0.3);
    text(axTelemetry, 0.5, 0.06, alertLevel, 'Color', [0 0 0], 'FontWeight', 'bold', ...
        'FontSize', 14, 'HorizontalAlignment', 'center');

    drawnow;
    pause(0.05); % throttle animation; remove/adjust for headless batch runs
end

fprintf('=== 48-hour predictive simulation complete ===\n');
fprintf('Final damaged buildings: %d | Displaced: %d | Loss: Rs %.0f\n', ...
    ImpactReport.DamagedBuildings, ImpactReport.DisplacedPopulation, ImpactReport.DirectLoss_INR);
