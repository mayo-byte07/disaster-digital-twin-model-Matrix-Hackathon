function SpatialData = load_geospatial_data(demFile, roadsFile, buildingsFile)
%LOAD_GEOSPATIAL_DATA Ingests DEM raster and road/building shapefiles for
% the Wayanad Digital Twin and returns a unified SpatialData structure.
%
%   SpatialData = load_geospatial_data('wayanad_dem.tif', ...
%                                       'wayanad_roads.shp', ...
%                                       'wayanad_buildings.shp')
%
% SpatialData fields:
%   .Elevation   MxN elevation matrix (meters)
%   .R           Raster spatial reference object returned by readgeoraster
%   .Rows,.Cols  Grid dimensions
%   .Slope       MxN slope field (degrees)
%   .AspectDeg   MxN aspect field (degrees, 0 = North, clockwise)
%   .CellSizeM   Approximate ground cell size (meters) [dy dx]
%   .Roads       Struct array from shaperead(roadsFile)
%   .Buildings   Struct array from shaperead(buildingsFile), augmented
%                with .CentroidLat/.CentroidLon/.RowIdx/.ColIdx

    if nargin < 1 || isempty(demFile)
        demFile = 'wayanad_dem.tif';
    end
    if nargin < 2 || isempty(roadsFile)
        roadsFile = 'wayanad_roads.shp';
    end
    if nargin < 3 || isempty(buildingsFile)
        buildingsFile = 'wayanad_buildings.shp';
    end

    %% --- DEM ingestion -------------------------------------------------
    if exist(demFile, 'file') ~= 2
        error('load_geospatial_data:MissingDEM', ...
            'DEM raster "%s" not found on path.', demFile);
    end
[Elevation, R] = readgeoraster(demFile, 'OutputType', 'double');
    Elevation(Elevation < -1000) = NaN;   % strip nodata sentinels

    % --- SAFE DEM COMPRESSION TO PREVENT CRASHES ---
    MAX_SIZE = 800;
    [r_orig, c_orig] = size(Elevation);
    if max(r_orig, c_orig) > MAX_SIZE
        scale = ceil(max(r_orig, c_orig) / MAX_SIZE);
        Elevation = Elevation(1:scale:end, 1:scale:end);
        if isprop(R, 'LatitudeLimits')
            R = georefcells(R.LatitudeLimits, R.LongitudeLimits, size(Elevation));
        else
            R = maprefcells(R.XWorldLimits, R.YWorldLimits, size(Elevation));
        end
        fprintf('[System] Huge DEM detected. Compressed by factor of %d for stability.\n', scale);
    end
    % -----------------------------------------------

    [rows, cols] = size(Elevation);

    % Approximate ground cell size in meters (handles both Cell and Postings references)
    if isprop(R, 'CellExtentInLatitude') || isprop(R, 'SampleSpacingInLatitude')
        if isprop(R, 'CellExtentInLatitude')
            dy_deg = R.CellExtentInLatitude;
            dx_deg = R.CellExtentInLongitude;
        else
            dy_deg = R.SampleSpacingInLatitude;
            dx_deg = R.SampleSpacingInLongitude;
        end
        latMean = mean(R.LatitudeLimits);
        cellSizeY = dy_deg * 111320;                 
        cellSizeX = dx_deg * 111320 * cosd(latMean); 
    else
        if isprop(R, 'CellExtentInWorldY')
            cellSizeY = R.CellExtentInWorldY;
            cellSizeX = R.CellExtentInWorldX;
        else
            cellSizeY = R.SampleSpacingInWorldY;
            cellSizeX = R.SampleSpacingInWorldX;
        end
    end
    cellSizeM = [cellSizeY, cellSizeX];
    %% --- Slope / Aspect --------------------------------------------------
    [gx, gy] = gradient(Elevation, cellSizeM(2), cellSizeM(1));
    Slope = atand(sqrt(gx.^2 + gy.^2));
    AspectDeg = mod(90 - atan2d(gy, gx), 360);

    %% --- Roads shapefile -------------------------------------------------
    if exist(roadsFile, 'file') == 2
        Roads = shaperead(roadsFile);
    else
        warning('load_geospatial_data:MissingRoads', ...
            'Roads shapefile "%s" not found. Roads set to empty.', roadsFile);
        Roads = struct('X', {}, 'Y', {}, 'Geometry', {});
    end

    %% --- Buildings shapefile -----------------------------------------------
    if exist(buildingsFile, 'file') == 2
        Buildings = shaperead(buildingsFile);
    else
        warning('load_geospatial_data:MissingBuildings', ...
            'Buildings shapefile "%s" not found. Buildings set to empty.', buildingsFile);
        Buildings = struct('X', {}, 'Y', {}, 'Geometry', {});
    end

    isGeographic = isprop(R, 'LatitudeLimits');
    for k = 1:numel(Buildings)
        vx = Buildings(k).X(~isnan(Buildings(k).X));
        vy = Buildings(k).Y(~isnan(Buildings(k).Y));
        if isempty(vx)
            Buildings(k).CentroidLon = NaN;
            Buildings(k).CentroidLat = NaN;
            Buildings(k).RowIdx = NaN;
            Buildings(k).ColIdx = NaN;
            continue;
        end
        cLon = mean(vx);
        cLat = mean(vy);
        Buildings(k).CentroidLon = cLon;
        Buildings(k).CentroidLat = cLat;

        if isGeographic
            try
                [r, c] = geographicToDiscrete(R, cLat, cLon);
            catch
                r = NaN; c = NaN;
            end
        else
            try
                [r, c] = worldToDiscrete(R, [cLon, cLat]);
                r = r; c = c; %#ok<ASGSL>
            catch
                r = NaN; c = NaN;
            end
        end
        if ~isnan(r) && r >= 1 && r <= rows && c >= 1 && c <= cols
            Buildings(k).RowIdx = r;
            Buildings(k).ColIdx = c;
        else
            Buildings(k).RowIdx = NaN;
            Buildings(k).ColIdx = NaN;
        end
    end

    %% --- Assemble output structure -----------------------------------------
    SpatialData = struct();
    SpatialData.Elevation = Elevation;
    SpatialData.R = R;
    SpatialData.Rows = rows;
    SpatialData.Cols = cols;
    SpatialData.Slope = Slope;
    SpatialData.AspectDeg = AspectDeg;
    SpatialData.CellSizeM = cellSizeM;
    SpatialData.Roads = Roads;
    SpatialData.Buildings = Buildings;
    SpatialData.IsGeographic = isGeographic;

    fprintf('[load_geospatial_data] DEM %dx%d loaded | %d road features | %d buildings\n', ...
        rows, cols, numel(Roads), numel(Buildings));
end
