function ImpactReport = damage_and_loss_assessor(SpatialData, FS, FloodDepth)
%DAMAGE_AND_LOSS_ASSESSOR Estimates building collapse, displaced
% population, direct structural loss (INR), and priority NDRF rescue
% zones ranked by building density.
%
%   ImpactReport = damage_and_loss_assessor(SpatialData, FS, FloodDepth)
%
% Failure criterion per building: FS < 1.0 (landslide) OR
% FloodDepth > 0.5 m (inundation) at the building's raster grid cell.
%
% ImpactReport fields:
%   .TotalBuildings         total buildings evaluated
%   .DamagedBuildings       count meeting failure criterion
%   .DisplacedPopulation    DamagedBuildings * 4 (persons/household)
%   .DirectLoss_INR         DamagedBuildings * Rs 25,00,000
%   .DirectLoss_USD         DirectLoss_INR / 83 (approx conversion) or
%                            DamagedBuildings * $30,000, whichever the
%                            caller prefers; both are reported.
%   .BuildingStatus         Nx1 logical, true = damaged, indexed as Buildings
%   .PriorityZones          struct array of high-density damage clusters,
%                            sorted descending by damaged-building density,
%                            each with .RowIdx, .ColIdx, .DamagedCount

    RS_PER_BUILDING = 2500000;   % Rs 25,00,000
    USD_PER_BUILDING = 30000;    % $30,000
    PERSONS_PER_HOUSEHOLD = 4;
    FLOOD_THRESHOLD_M = 0.5;
    FS_THRESHOLD = 1.0;

    Buildings = SpatialData.Buildings;
    nBuildings = numel(Buildings);
    BuildingStatus = false(nBuildings, 1);

    for k = 1:nBuildings
        r = Buildings(k).RowIdx;
        c = Buildings(k).ColIdx;
        if isnan(r) || isnan(c)
            continue;
        end
        fsVal = FS(r, c);
        floodVal = FloodDepth(r, c);
        if fsVal < FS_THRESHOLD || floodVal > FLOOD_THRESHOLD_M
            BuildingStatus(k) = true;
        end
    end

    DamagedBuildings = sum(BuildingStatus);
    DisplacedPopulation = DamagedBuildings * PERSONS_PER_HOUSEHOLD;
    DirectLoss_INR = DamagedBuildings * RS_PER_BUILDING;
    DirectLoss_USD = DamagedBuildings * USD_PER_BUILDING;

    %% --- Priority rescue zone clustering (grid-cell density binning) -----
    binSize = 10; % aggregate into 10x10 cell blocks for density ranking
    rows = SpatialData.Rows;
    cols = SpatialData.Cols;
    nBlockRows = ceil(rows / binSize);
    nBlockCols = ceil(cols / binSize);

    densityGrid = zeros(nBlockRows, nBlockCols);
    for k = 1:nBuildings
        if ~BuildingStatus(k)
            continue;
        end
        r = Buildings(k).RowIdx;
        c = Buildings(k).ColIdx;
        if isnan(r) || isnan(c)
            continue;
        end
        br = ceil(r / binSize);
        bc = ceil(c / binSize);
        br = min(max(br, 1), nBlockRows);
        bc = min(max(bc, 1), nBlockCols);
        densityGrid(br, bc) = densityGrid(br, bc) + 1;
    end

    [sortedCounts, linIdx] = sort(densityGrid(:), 'descend');
    keep = sortedCounts > 0;
    sortedCounts = sortedCounts(keep);
    linIdx = linIdx(keep);

    nZones = min(10, numel(sortedCounts)); % top-10 priority clusters
    PriorityZones = struct('RowIdx', {}, 'ColIdx', {}, 'DamagedCount', {});
    for i = 1:nZones
        [br, bc] = ind2sub(size(densityGrid), linIdx(i));
        centerRow = min(rows, (br - 1) * binSize + round(binSize / 2));
        centerCol = min(cols, (bc - 1) * binSize + round(binSize / 2));
        PriorityZones(i).RowIdx = centerRow;
        PriorityZones(i).ColIdx = centerCol;
        PriorityZones(i).DamagedCount = sortedCounts(i);
    end

    %% --- Assemble report ---------------------------------------------------
    ImpactReport = struct();
    ImpactReport.TotalBuildings = nBuildings;
    ImpactReport.DamagedBuildings = DamagedBuildings;
    ImpactReport.DisplacedPopulation = DisplacedPopulation;
    ImpactReport.DirectLoss_INR = DirectLoss_INR;
    ImpactReport.DirectLoss_USD = DirectLoss_USD;
    ImpactReport.BuildingStatus = BuildingStatus;
    ImpactReport.PriorityZones = PriorityZones;

    fprintf(['[damage_and_loss_assessor] %d/%d buildings damaged | %d displaced | ' ...
        'Loss: Rs %s | %d priority NDRF zones\n'], ...
        DamagedBuildings, nBuildings, DisplacedPopulation, ...
        addCommasINR(DirectLoss_INR), numel(PriorityZones));
end

function s = addCommasINR(val)
%ADDCOMMASINR Formats a numeric INR value with Indian-style comma grouping.
    val = round(val);
    s = num2str(val);
    if numel(s) <= 3
        return;
    end
    lastThree = s(end-2:end);
    remainder = s(1:end-3);
    parts = {};
    while numel(remainder) > 2
        parts{end+1} = remainder(end-1:end); %#ok<AGROW>
        remainder = remainder(1:end-2);
    end
    if ~isempty(remainder)
        parts{end+1} = remainder; %#ok<AGROW>
    end
    s = [strjoin(fliplr(parts), ','), ',', lastThree];
end
