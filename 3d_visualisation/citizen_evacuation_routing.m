function [evacuation_url, routeInfo] = citizen_evacuation_routing(SpatialData, FS, FloodDepth, citizenLat, citizenLon)
%CITIZEN_EVACUATION_ROUTING Builds a hazard-penalized road digraph,
% snaps a citizen's GPS position to the nearest accessible road node,
% routes to the nearest safe relief camp via Dijkstra shortest path
% (MATLAB's shortestpath on a digraph), and launches a Google Maps
% directions URL in the user's browser.
%
%   [evacuation_url, routeInfo] = citizen_evacuation_routing(SpatialData, ...
%                                       FS, FloodDepth, citizenLat, citizenLon)
%
% Outputs:
%   evacuation_url  string, Google Maps directions URL
%   routeInfo       struct with .PathLat, .PathLon, .DistanceKm, .CampName,
%                    .IsCitizenSafe, .Status

    FS_THRESHOLD = 1.0;
    FLOOD_THRESHOLD = 0.3;

    % --- Default Wayanad relief camp network (Lat, Lon, Name) --------------
    reliefCamps = {
        11.6854, 76.1320, 'Meppadi Community Relief Camp';
        11.6050, 76.0850, 'Kalpetta Govt. Higher Secondary Relief Camp';
        11.7480, 76.0430, 'Vythiri Taluk Relief Camp';
        11.5250, 76.2100, 'Sultan Bathery Relief Camp';
        11.6120, 76.2600, 'Mananthavady Relief Camp'
    };

    %% --- Build road graph ---------------------------------------------------
    [G, nodeLat, nodeLon] = build_hazard_weighted_graph(SpatialData, FS, FloodDepth, ...
        FS_THRESHOLD, FLOOD_THRESHOLD);

    if numel(nodeLat) < 2
        error('citizen_evacuation_routing:NoRoadNetwork', ...
            'Road network graph could not be constructed (insufficient road data).');
    end

    %% --- Check hazard status at citizen's exact grid cell -------------------
    isCitizenSafe = true;
    if SpatialData.IsGeographic
        try
            [rC, cC] = geographicToDiscrete(SpatialData.R, citizenLat, citizenLon);
            if rC >= 1 && rC <= SpatialData.Rows && cC >= 1 && cC <= SpatialData.Cols
                if FS(rC, cC) < FS_THRESHOLD || FloodDepth(rC, cC) > FLOOD_THRESHOLD
                    isCitizenSafe = false;
                end
            end
        catch
            % leave isCitizenSafe as true if lookup fails
        end
    end

    %% --- Snap citizen to nearest node ----------------------------------------
    citizenNodeIdx = nearest_node(citizenLat, citizenLon, nodeLat, nodeLon);

    %% --- Snap each relief camp to nearest node and find shortest path -------
    bestDist = Inf;
    bestPath = [];
    bestCampName = '';
    bestCampLat = NaN;
    bestCampLon = NaN;

    for i = 1:size(reliefCamps, 1)
        campLat = reliefCamps{i, 1};
        campLon = reliefCamps{i, 2};
        campName = reliefCamps{i, 3};

        campNodeIdx = nearest_node(campLat, campLon, nodeLat, nodeLon);

        try
            [path, d] = shortestpath(G, citizenNodeIdx, campNodeIdx);
        catch
            path = [];
            d = Inf;
        end

        if ~isempty(path) && d < bestDist
            bestDist = d;
            bestPath = path;
            bestCampName = campName;
            bestCampLat = campLat;
            bestCampLon = campLon;
        end
    end

    routeInfo = struct();
    routeInfo.IsCitizenSafe = isCitizenSafe;

    if isempty(bestPath)
        routeInfo.Status = 'NO_SAFE_ROUTE_FOUND';
        routeInfo.PathLat = [];
        routeInfo.PathLon = [];
        routeInfo.DistanceKm = Inf;
        routeInfo.CampName = '';
        evacuation_url = '';
        warning('citizen_evacuation_routing:NoRoute', ...
            'No hazard-free route to any relief camp could be found.');
        return;
    end

    pathLat = nodeLat(bestPath);
    pathLon = nodeLon(bestPath);

    routeInfo.Status = 'ROUTE_FOUND';
    routeInfo.PathLat = pathLat;
    routeInfo.PathLon = pathLon;
    routeInfo.DistanceKm = bestDist / 1000;
    routeInfo.CampName = bestCampName;
    routeInfo.CampLat = bestCampLat;
    routeInfo.CampLon = bestCampLon;

    %% --- Build Google Maps directions URL ------------------------------------
    waypointStride = max(1, floor(numel(pathLat) / 8)); % cap waypoints, Google Maps limit
    wpLat = pathLat(2:waypointStride:end-1);
    wpLon = pathLon(2:waypointStride:end-1);

    waypointStr = '';
    for i = 1:numel(wpLat)
        waypointStr = [waypointStr, sprintf('%.6f,%.6f', wpLat(i), wpLon(i))]; %#ok<AGROW>
        if i < numel(wpLat)
            waypointStr = [waypointStr, '|']; %#ok<AGROW>
        end
    end

    baseUrl = 'https://www.google.com/maps/dir/?api=1';
    originStr = sprintf('%.6f,%.6f', citizenLat, citizenLon);
    destStr = sprintf('%.6f,%.6f', bestCampLat, bestCampLon);

    evacuation_url = sprintf('%s&origin=%s&destination=%s&travelmode=driving', ...
        baseUrl, originStr, destStr);
    if ~isempty(waypointStr)
        evacuation_url = sprintf('%s&waypoints=%s', evacuation_url, waypointStr);
    end

    fprintf('[citizen_evacuation_routing] Route to "%s" | %.2f km | Citizen safe: %d\n', ...
        bestCampName, routeInfo.DistanceKm, isCitizenSafe);

    try
        web(evacuation_url, '-browser');
    catch ME
        warning('citizen_evacuation_routing:BrowserLaunchFailed', ...
            'Could not launch browser automatically: %s', ME.message);
    end
end

%% ================= Local helper functions =====================

function [G, nodeLat, nodeLon] = build_hazard_weighted_graph(SpatialData, FS, FloodDepth, fsThresh, floodThresh)
%BUILD_HAZARD_WEIGHTED_GRAPH Converts the road shapefile polylines into a
% weighted digraph where edges crossing hazardous grid cells receive
% weight = Inf (impassable).

    Roads = SpatialData.Roads;
    nodeLat = [];
    nodeLon = [];
    edgeS = [];
    edgeT = [];
    edgeW = [];

    nodeMap = containers.Map('KeyType', 'char', 'ValueType', 'double');

    for k = 1:numel(Roads)
        x = Roads(k).X; % Lon
        y = Roads(k).Y; % Lat

        segStart = 1;
        for i = 1:numel(x)
            if isnan(x(i)) || i == numel(x)
                segEnd = i - 1;
                if isnan(x(i))
                    segEnd = i - 1;
                else
                    segEnd = i;
                end
                if segEnd - segStart >= 1
                    for j = segStart:segEnd-1
                        [nodeLat, nodeLon, nodeMap, idxA] = get_or_add_node(y(j), x(j), nodeLat, nodeLon, nodeMap);
                        [nodeLat, nodeLon, nodeMap, idxB] = get_or_add_node(y(j+1), x(j+1), nodeLat, nodeLon, nodeMap);

                        distM = haversine_m(y(j), x(j), y(j+1), x(j+1));

                        midLat = (y(j) + y(j+1)) / 2;
                        midLon = (x(j) + x(j+1)) / 2;
                        hazardous = false;
                        if SpatialData.IsGeographic
                            try
                                [r, c] = geographicToDiscrete(SpatialData.R, midLat, midLon);
                                if r >= 1 && r <= SpatialData.Rows && c >= 1 && c <= SpatialData.Cols
                                    if FS(r, c) < fsThresh || FloodDepth(r, c) > floodThresh
                                        hazardous = true;
                                    end
                                end
                            catch
                                % leave hazardous = false if lookup fails
                            end
                        end

                        w = distM;
                        if hazardous
                            w = Inf;
                        end

                        edgeS(end+1) = idxA; %#ok<AGROW>
                        edgeT(end+1) = idxB; %#ok<AGROW>
                        edgeW(end+1) = w;     %#ok<AGROW>
                    end
                end
                segStart = i + 1;
            end
        end
    end

    if isempty(edgeS)
        G = digraph();
        return;
    end

    % Remove Inf-weight edges entirely (impassable) rather than keeping
    % them, which keeps shortestpath from ever traversing hazard segments.
    validEdges = ~isinf(edgeW);
    edgeS = edgeS(validEdges);
    edgeT = edgeT(validEdges);
    edgeW = edgeW(validEdges);

    % Build bidirectional graph (roads assumed two-way)
    allS = [edgeS, edgeT];
    allT = [edgeT, edgeS];
    allW = [edgeW, edgeW];

    G = digraph(allS, allT, allW);
end

function [nodeLat, nodeLon, nodeMap, idx] = get_or_add_node(lat, lon, nodeLat, nodeLon, nodeMap)
    key = sprintf('%.6f_%.6f', lat, lon);
    if isKey(nodeMap, key)
        idx = nodeMap(key);
    else
        nodeLat(end+1) = lat; %#ok<AGROW>
        nodeLon(end+1) = lon; %#ok<AGROW>
        idx = numel(nodeLat);
        nodeMap(key) = idx;
    end
end

function idx = nearest_node(lat, lon, nodeLat, nodeLon)
    d = haversine_m(lat, lon, nodeLat, nodeLon);
    [~, idx] = min(d);
end

function d = haversine_m(lat1, lon1, lat2, lon2)
%HAVERSINE_M Great-circle distance in meters between coordinate pairs.
% Supports vectorized lat2/lon2 against a scalar lat1/lon1.
    R_EARTH = 6371000; % meters
    phi1 = deg2rad(lat1);
    phi2 = deg2rad(lat2);
    dPhi = deg2rad(lat2 - lat1);
    dLambda = deg2rad(lon2 - lon1);

    a = sin(dPhi/2).^2 + cos(phi1) .* cos(phi2) .* sin(dLambda/2).^2;
    c = 2 * atan2(sqrt(a), sqrt(1 - a));
    d = R_EARTH * c;
end
