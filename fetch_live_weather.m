function [time_vector, rainfall_forecast_mmhr] = fetch_live_weather()
%FETCH_LIVE_WEATHER Retrieves a live 48-hour hourly rainfall forecast for
% Wayanad, Kerala (Lat 11.5546, Lon 76.1320) from the free Open-Meteo API.
%
%   [time_vector, rainfall_forecast_mmhr] = fetch_live_weather()
%
% Returns:
%   time_vector             1x48 datetime array (local hourly timestamps)
%   rainfall_forecast_mmhr  1x48 double array, precipitation in mm/hr
%
% If the API is unreachable, a synthetic monsoon-like fallback forecast
% is generated so downstream modules can still run in offline/demo mode.

    lat = 11.5546;
    lon = 76.1320;
    url = sprintf(['https://api.open-meteo.com/v1/forecast?latitude=%f&' ...
        'longitude=%f&hourly=precipitation&forecast_days=2&timezone=Asia%%2FKolkata'], ...
        lat, lon);

    try
        options = weboptions('Timeout', 15, 'ContentType', 'json');
        data = webread(url, options);

        if ~isfield(data, 'hourly') || ~isfield(data.hourly, 'time') || ...
                ~isfield(data.hourly, 'precipitation')
            error('fetch_live_weather:BadResponse', 'Unexpected API schema.');
        end

        rawTimes = data.hourly.time;         % cell array of ISO8601 strings
        rawPrecip = data.hourly.precipitation; % numeric array (mm)

        n = min(48, numel(rawTimes));
        time_vector = datetime(rawTimes(1:n), 'InputFormat', 'yyyy-MM-dd''T''HH:mm');
        rainfall_forecast_mmhr = double(rawPrecip(1:n));
        rainfall_forecast_mmhr = reshape(rainfall_forecast_mmhr, 1, []);
        rainfall_forecast_mmhr(isnan(rainfall_forecast_mmhr)) = 0;

        if n < 48
            pad = 48 - n;
            time_vector = [time_vector, time_vector(end) + hours(1:pad)];
            rainfall_forecast_mmhr = [rainfall_forecast_mmhr, zeros(1, pad)];
        end

        fprintf('[fetch_live_weather] Live Open-Meteo forecast retrieved (%d hourly points).\n', n);

    catch ME
        warning('fetch_live_weather:APIFailure', ...
            'Open-Meteo request failed (%s). Using synthetic fallback forecast.', ME.message);

        time_vector = datetime('now') + hours(0:47);

        % Synthetic monsoon-burst profile: baseline drizzle with two
        % convective rainfall peaks, representative of Western Ghats
        % pre-monsoon/monsoon storm cells over Wayanad.
        t = 0:47;
        baseline = 2 + 1.5 * sin(2 * pi * t / 24);
        peak1 = 35 * exp(-((t - 14).^2) / (2 * 3^2));
        peak2 = 20 * exp(-((t - 30).^2) / (2 * 2^2));
        rainfall_forecast_mmhr = max(0, baseline + peak1 + peak2);
        rainfall_forecast_mmhr = reshape(rainfall_forecast_mmhr, 1, []);
    end
end
