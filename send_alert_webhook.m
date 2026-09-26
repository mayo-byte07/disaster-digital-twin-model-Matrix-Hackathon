function response = send_alert_webhook(alert_level, impacted_count, total_loss_inr, webhook_url)
%SEND_ALERT_WEBHOOK Constructs an emergency JSON payload and transmits it
% via HTTP POST to an emergency dispatch webhook (Slack, Discord, Twilio
% Functions gateway, or a custom NDRF/district-authority backend).
%
%   response = send_alert_webhook(alert_level, impacted_count, ...
%                                  total_loss_inr, webhook_url)
%
% Inputs:
%   alert_level      string, e.g. 'GREEN', 'YELLOW', 'ORANGE', 'RED'
%   impacted_count   scalar, number of impacted/displaced individuals
%   total_loss_inr   scalar, estimated direct structural loss in INR
%   webhook_url      string, destination HTTP endpoint
%
% Output:
%   response  the parsed server response (struct/char), or an error
%             status struct if the transmission failed.

    if nargin < 4 || isempty(webhook_url)
        error('send_alert_webhook:MissingURL', ...
            'A webhook_url must be provided for alert dispatch.');
    end

    validLevels = {'GREEN', 'YELLOW', 'ORANGE', 'RED'};
    alert_level = upper(string(alert_level));
    if ~ismember(alert_level, validLevels)
        warning('send_alert_webhook:UnknownLevel', ...
            'Unrecognized alert_level "%s"; defaulting to "ORANGE".', alert_level);
        alert_level = "ORANGE";
    end

    timestampUTC = datetime('now', 'TimeZone', 'UTC');
    timestampStr = datestr(timestampUTC, 'yyyy-mm-ddTHH:MM:SSZ'); %#ok<DATST>

    payload = struct();
    payload.system = 'Wayanad Predictive Disaster Digital Twin';
    payload.event_type = 'LANDSLIDE_FLOOD_HAZARD_ALERT';
    payload.alert_level = char(alert_level);
    payload.timestamp_utc = timestampStr;
    payload.location = struct('region', 'Wayanad, Kerala, India', ...
                               'latitude', 11.5546, ...
                               'longitude', 76.1320);
    payload.impacted_individuals = impacted_count;
    payload.estimated_direct_loss_inr = total_loss_inr;
    payload.message = sprintf(['EMERGENCY ALERT [%s]: Predictive Digital Twin has detected ' ...
        'hazardous slope/flood conditions in Wayanad. Estimated %d individuals impacted. ' ...
        'Estimated direct structural loss: Rs %d. Immediate NDRF triage and citizen ' ...
        'evacuation dispatch recommended.'], char(alert_level), impacted_count, round(total_loss_inr));

    % Slack/Discord-compatible convenience field; ignored by generic backends.
    payload.text = payload.message;

    jsonPayload = jsonencode(payload);

    options = weboptions('MediaType', 'application/json', ...
                          'RequestMethod', 'post', ...
                          'Timeout', 15, ...
                          'ContentType', 'json');

    try
        response = webwrite(webhook_url, jsonPayload, options);
        fprintf('[send_alert_webhook] Alert "%s" dispatched successfully to %s\n', ...
            char(alert_level), webhook_url);
    catch ME
        warning('send_alert_webhook:TransmissionFailed', ...
            'Webhook dispatch failed: %s', ME.message);
        response = struct('status', 'FAILED', 'error', ME.message, 'payload', payload);
    end
end
