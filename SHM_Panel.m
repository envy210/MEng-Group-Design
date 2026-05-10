function H = SHM_Panel(C, F, fault_change_callback)
% SHM detail view: per-region strain/stress/FoS table, frame schematic, history plot.
% Inputs: C (constants), F (FBG_v7_Functions), fault_change_callback(faults_cell).

% Fault injection options
S.faults = {'none','none','none','none'};
S.cb     = fault_change_callback;

FAULT_OPTIONS = {'none', 'broken', 'debonded', 'erratic'};
FAULT_LABELS  = {'None', 'Broken sensor', 'Debonded', 'Erratic signal'};

REGION_COLOURS = [ ...
    0.20  0.55  0.85;   % R1 blue
    0.85  0.45  0.20;   % R2 orange
    0.30  0.65  0.30;   % R3 green
    0.65  0.30  0.65 ]; % R4 purple

% =========================================================================
%  BUILD UIFIGURE
% =========================================================================
fig = uifigure('Name','SHM Detail - Structural Health Monitoring', ...
    'Position',[150 80 900 700], ...
    'Color',[0.96 0.96 0.96], ...
    'Resize','off', ...
    'Visible','off');

uilabel(fig,'Position',[20 660 700 30], ...
    'Text','Structural Health Monitoring - Detail View', ...
    'FontSize',16,'FontWeight','bold', ...
    'FontColor',[0.15 0.25 0.55]);

btnSettings = uibutton(fig,'push','Text',[char(9881) ' Settings'], ...
    'Position',[700 665 90 28], ...
    'FontSize',11, ...
    'BackgroundColor',[0.94 0.94 0.94], ...
    'ButtonPushedFcn',@(~,~) onOpenSettings());

btnClose = uibutton(fig,'push','Text','Close', ...
    'Position',[800 665 80 28], ...
    'FontSize',11, ...
    'BackgroundColor',[0.85 0.85 0.85], ...
    'ButtonPushedFcn',@(~,~) hideFig());

% --- Frame schematic panel -----------------------------------------------
pnlFrame = uipanel(fig,'Title','Tank Frame (top-down view)', ...
    'Position',[15 360 540 290], ...
    'FontWeight','bold','FontSize',12, ...
    'BackgroundColor',[1 1 1]);

axFrame = uiaxes(pnlFrame,'Position',[5 5 525 255]);
axFrame.XAxis.Visible = 'off';
axFrame.YAxis.Visible = 'off';
axFrame.Toolbar.Visible = 'off';
axFrame.Box = 'off';
axis(axFrame,'equal');

% --- Per-region status panel ---------------------------------------------
pnlStatus = uipanel(fig,'Title','Per-Region Status', ...
    'Position',[565 360 320 290], ...
    'FontWeight','bold','FontSize',12, ...
    'BackgroundColor',[1 1 1]);

uilabel(pnlStatus,'Position',[15 240 60 20],'Text','Region', ...
    'FontSize',10,'FontWeight','bold','FontColor',[0.45 0.45 0.45]);
uilabel(pnlStatus,'Position',[80 240 50 20],'Text','Status', ...
    'FontSize',10,'FontWeight','bold','FontColor',[0.45 0.45 0.45]);
uilabel(pnlStatus,'Position',[135 240 60 20],'Text','ε (µε)', ...
    'FontSize',10,'FontWeight','bold','FontColor',[0.45 0.45 0.45]);
uilabel(pnlStatus,'Position',[195 240 60 20],'Text','σ (MPa)', ...
    'FontSize',10,'FontWeight','bold','FontColor',[0.45 0.45 0.45]);
uilabel(pnlStatus,'Position',[260 240 50 20],'Text','FoS', ...
    'FontSize',10,'FontWeight','bold','FontColor',[0.45 0.45 0.45]);

rowLamps   = gobjects(1, 4);
rowEps     = gobjects(1, 4);
rowStress  = gobjects(1, 4);
rowFoS     = gobjects(1, 4);
rowStatus  = gobjects(1, 4);
for r = 1:4
    y = 200 - (r-1)*40;
    uilabel(pnlStatus,'Position',[15 y 50 25], ...
        'Text',sprintf('R%d',r), ...
        'FontSize',12,'FontWeight','bold', ...
        'FontColor',REGION_COLOURS(r,:));
    rowLamps(r)  = uilamp(pnlStatus,'Position',[80 y+5 16 16],'Color',[0.7 0.7 0.7]);
    rowStatus(r) = uilabel(pnlStatus,'Position',[100 y 35 22], ...
        'Text','--','FontSize',9,'FontColor',[0.45 0.45 0.45]);
    rowEps(r)    = uilabel(pnlStatus,'Position',[135 y 60 22], ...
        'Text','--','FontSize',11);
    rowStress(r) = uilabel(pnlStatus,'Position',[195 y 60 22], ...
        'Text','--','FontSize',11);
    rowFoS(r)    = uilabel(pnlStatus,'Position',[260 y 60 22], ...
        'Text','--','FontSize',11,'FontWeight','bold');
end

uilabel(pnlStatus,'Position',[15 15 290 50], ...
    'Text',['FoS thresholds:  green > 2.00  |  amber 1.50-2.00  |  red < 1.50', newline, ...
            'Faults: broken sensor / debonded / erratic flagged in Status column.'], ...
    'FontSize',9,'FontColor',[0.55 0.55 0.55]);

% --- Strain history plot panel -------------------------------------------
pnlHistory = uipanel(fig,'Title','Strain History (per region)', ...
    'Position',[15 15 870 335], ...
    'FontWeight','bold','FontSize',12, ...
    'BackgroundColor',[1 1 1]);

axHistory = uiaxes(pnlHistory,'Position',[10 10 850 305]);
axHistory.FontSize = 10;
xlabel(axHistory,'Elapsed time (s)');
ylabel(axHistory,'Mechanical strain (µε)');
grid(axHistory,'on');
box(axHistory,'on');

drawFrameSchematic(repmat([0.7 0.7 0.7], 4, 1), {'OK','OK','OK','OK'});
title(axHistory, 'Awaiting first measurement...');

% =========================================================================
%  PUBLIC API
% =========================================================================
H.fig         = fig;
H.show        = @() showFig();
H.hide        = @() hideFig();
H.update      = @(eps, stress, FoS, statuses, history, faults) ...
                    doUpdate(eps, stress, FoS, statuses, history, faults);
H.set_faults  = @(faults) setFaults(faults);
H.get_faults  = @() S.faults;

% =========================================================================
%  CALLBACKS
% =========================================================================

    function showFig()
        set(fig,'Visible','on');
        figure(fig);
    end

    function hideFig()
        set(fig,'Visible','off');
    end

    function setFaults(new_faults)
        if iscell(new_faults) && numel(new_faults) == 4
            S.faults = new_faults;
        end
    end

    function doUpdate(eps_pair, stress_pair, FoS_pair, statuses, history, faults)
        if iscell(faults), S.faults = faults; end

        sensor_colours = zeros(4, 3);
        for r = 1:4
            status = statuses{r};
            switch status
                case 'broken'
                    col = [0.90 0.30 0.30];   txt = 'BRKN';  txt_col = [0.85 0.20 0.20];
                case 'erratic'
                    col = [0.90 0.30 0.30];   txt = 'ERR';   txt_col = [0.85 0.20 0.20];
                case 'debonded'
                    col = [1.00 0.60 0.10];   txt = 'DEBND'; txt_col = [0.85 0.45 0.10];
                otherwise
                    if FoS_pair(r) < 1.50
                        col = [0.90 0.30 0.30];   txt = 'YIELD'; txt_col = [0.85 0.20 0.20];
                    elseif FoS_pair(r) < 2.00
                        col = [1.00 0.75 0.20];   txt = 'WARN';  txt_col = [0.85 0.55 0.10];
                    else
                        col = [0.30 0.75 0.35];   txt = 'OK';    txt_col = [0.30 0.55 0.35];
                    end
            end
            sensor_colours(r, :) = col;
            rowLamps(r).Color    = col;
            rowStatus(r).Text    = txt;
            rowStatus(r).FontColor = txt_col;

            if isnan(eps_pair(r))
                rowEps(r).Text    = '---';
                rowStress(r).Text = '---';
                rowFoS(r).Text    = '---';
            else
                rowEps(r).Text    = sprintf('%.2f', eps_pair(r));
                rowStress(r).Text = sprintf('%.2f', stress_pair(r));
                if isinf(FoS_pair(r))
                    rowFoS(r).Text = '∞';
                else
                    rowFoS(r).Text = sprintf('%.1f', FoS_pair(r));
                end
                rowFoS(r).FontColor = txt_col;
            end
        end

        drawFrameSchematic(sensor_colours, statuses);

        % Rolling 60 s strain history plot
        if ~isempty(history) && size(history, 1) >= 2
            cla(axHistory); hold(axHistory,'on');
            t = history(:, 1);
            for r = 1:4
                plot(axHistory, t, history(:, r+1), '-', ...
                    'LineWidth', 1.6, ...
                    'Color', REGION_COLOURS(r, :), ...
                    'DisplayName', sprintf('Region %d', r));
            end
            hold(axHistory,'off');
            grid(axHistory,'on');
            legend(axHistory,'Location','northwest','FontSize',9);
            xlabel(axHistory,'Elapsed time (s)');
            ylabel(axHistory,'Mechanical strain (µε)');
            xlim(axHistory, [max(0, t(end)-60), max(t(end), 1)]);
            title(axHistory, ...
                sprintf('Strain over last %.1f s of fill session', t(end) - max(0, t(end)-60)));
        end
    end

    % --- Fault injection settings dialog ---------------------------------
    function onOpenSettings()
        d = uifigure('Name','Fault Injection (demo)', ...
            'Position',[fig.Position(1)+250 fig.Position(2)+250 460 320], ...
            'Resize','off');
        uilabel(d,'Position',[15 285 430 22], ...
            'Text','Inject artificial faults for SHM demonstration.', ...
            'FontSize',12,'FontWeight','bold');
        uilabel(d,'Position',[15 260 430 22], ...
            'Text','Faults persist until cleared. Reset does NOT clear them.', ...
            'FontSize',10,'FontColor',[0.45 0.45 0.45]);

        dropdowns = gobjects(1, 4);
        for r = 1:4
            uilabel(d,'Position',[15 220 - (r-1)*32 90 22], ...
                'Text',sprintf('Region %d:', r), ...
                'FontSize',11,'FontWeight','bold');
            dropdowns(r) = uidropdown(d, ...
                'Items', FAULT_LABELS, ...
                'Position',[110 220 - (r-1)*32 200 25], ...
                'FontSize',11);
            current_idx = find(strcmp(FAULT_OPTIONS, S.faults{r}), 1);
            if isempty(current_idx), current_idx = 1; end
            dropdowns(r).Value = FAULT_LABELS{current_idx};
        end

        uibutton(d,'push','Text','Apply', ...
            'Position',[110 25 90 35], ...
            'FontSize',11,'FontWeight','bold', ...
            'BackgroundColor',[0.20 0.55 0.85],'FontColor',[1 1 1], ...
            'ButtonPushedFcn',@(~,~) doApply());

        uibutton(d,'push','Text','Clear All', ...
            'Position',[210 25 90 35], ...
            'FontSize',11, ...
            'BackgroundColor',[0.85 0.85 0.85], ...
            'ButtonPushedFcn',@(~,~) doClearAll());

        uibutton(d,'push','Text','Cancel', ...
            'Position',[310 25 90 35], ...
            'FontSize',11, ...
            'BackgroundColor',[0.85 0.85 0.85], ...
            'ButtonPushedFcn',@(~,~) close(d));

        function doApply()
            new_faults = cell(1, 4);
            for rr = 1:4
                lbl_idx = find(strcmp(FAULT_LABELS, dropdowns(rr).Value), 1);
                new_faults{rr} = FAULT_OPTIONS{lbl_idx};
            end
            S.faults = new_faults;
            if ~isempty(S.cb)
                S.cb(new_faults);
            end
            close(d);
        end

        function doClearAll()
            for rr = 1:4
                dropdowns(rr).Value = FAULT_LABELS{1};
            end
        end
    end

% =========================================================================
%  FRAME SCHEMATIC  (top-down view, ISO 1CC geometry)
%  Frame: 6033×2438 mm | Tank: 4800×2100 mm | Saddles: 960 mm from ends
%  Sensor positions: quarter-span on each lower saddle beam
% =========================================================================
    function drawFrameSchematic(sensor_colours, statuses)
        cla(axFrame);
        hold(axFrame,'on');

        Lf = 6033/1000;   % m
        Wf = 2438/1000;   % m
        Lt = 4.8;         % m
        Dt = 2.1;         % m
        thickness = 0.16; % SHS 160 mm member width

        % Outer frame outline
        plot(axFrame, [-Lf/2, Lf/2, Lf/2, -Lf/2, -Lf/2], ...
                      [-Wf/2, -Wf/2, Wf/2, Wf/2, -Wf/2], ...
                      '-','Color',[0.20 0.20 0.20],'LineWidth',2.5);

        % Inner rectangle (member thickness inset)
        plot(axFrame, [-Lf/2+thickness, Lf/2-thickness, Lf/2-thickness, ...
                       -Lf/2+thickness, -Lf/2+thickness], ...
                      [-Wf/2+thickness, -Wf/2+thickness, Wf/2-thickness, ...
                       Wf/2-thickness, -Wf/2+thickness], ...
                      '-','Color',[0.50 0.50 0.50],'LineWidth',1.0);

        % End-panel X-braces
        bx_in  = -Lf/2 + thickness;
        bx_out = -Lf/2 + 0.02;
        plot(axFrame, [bx_out, bx_in], [-Wf/2+thickness, Wf/2-thickness], ...
            '-','Color',[0.50 0.50 0.50],'LineWidth',1.0);
        plot(axFrame, [bx_out, bx_in], [Wf/2-thickness, -Wf/2+thickness], ...
            '-','Color',[0.50 0.50 0.50],'LineWidth',1.0);
        bx_in  =  Lf/2 - thickness;
        bx_out =  Lf/2 - 0.02;
        plot(axFrame, [bx_in, bx_out], [-Wf/2+thickness, Wf/2-thickness], ...
            '-','Color',[0.50 0.50 0.50],'LineWidth',1.0);
        plot(axFrame, [bx_in, bx_out], [Wf/2-thickness, -Wf/2+thickness], ...
            '-','Color',[0.50 0.50 0.50],'LineWidth',1.0);

        % Tank cylinder (top-down: rectangle with rounded-end suggestion)
        fill(axFrame, [-Lt/2, Lt/2, Lt/2, -Lt/2, -Lt/2], ...
                      [-Dt/2, -Dt/2, Dt/2, Dt/2, -Dt/2], ...
             [0.85 0.92 0.97], 'EdgeColor',[0.40 0.55 0.75],'LineWidth',1.5, ...
             'FaceAlpha',0.6);

        % Saddle lines at 960 mm from each tank end
        saddle_offset = 0.96;
        for sx = [-Lt/2 + saddle_offset, Lt/2 - saddle_offset]
            plot(axFrame, [sx sx], [-Dt/2 Dt/2], '--', ...
                'Color',[0.40 0.40 0.40],'LineWidth',1.2);
        end

        % Sensor positions: R1/R2 left beam (+y), R3/R4 right beam (-y)
        sensor_positions = [ ...
            -Lt/4,   Wf/2 - thickness/2;   % R1: left beam, front quarter
             Lt/4,   Wf/2 - thickness/2;   % R2: left beam, rear quarter
            -Lt/4,  -Wf/2 + thickness/2;   % R3: right beam, front quarter
             Lt/4,  -Wf/2 + thickness/2 ]; % R4: right beam, rear quarter

        for r = 1:4
            if any(strcmp(statuses{r}, {'broken','erratic','debonded'}))
                marker = 'x';   msize = 16;
            else
                marker = 'o';   msize = 12;
            end
            plot(axFrame, sensor_positions(r,1), sensor_positions(r,2), ...
                marker, ...
                'MarkerSize', msize, 'LineWidth', 2.5, ...
                'MarkerEdgeColor', sensor_colours(r,:), ...
                'MarkerFaceColor', sensor_colours(r,:));
            label_y = sensor_positions(r,2) + 0.18 * sign(sensor_positions(r,2));
            text(axFrame, sensor_positions(r,1), label_y, sprintf('R%d', r), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'Color', REGION_COLOURS(r,:));
        end

        % Orientation labels
        text(axFrame, -Lf/2 - 0.10, 0, 'Front', 'FontSize', 9, ...
            'HorizontalAlignment', 'right', 'Rotation', 90, 'Color', [0.45 0.45 0.45]);
        text(axFrame,  Lf/2 + 0.10, 0, 'Rear',  'FontSize', 9, ...
            'HorizontalAlignment', 'left',  'Rotation', 90, 'Color', [0.45 0.45 0.45]);
        text(axFrame, 0,  Wf/2 + 0.18, 'Left saddle beam', 'FontSize', 9, ...
            'HorizontalAlignment', 'center', 'Color', [0.45 0.45 0.45]);
        text(axFrame, 0, -Wf/2 - 0.18, 'Right saddle beam', 'FontSize', 9, ...
            'HorizontalAlignment', 'center', 'Color', [0.45 0.45 0.45]);

        axis(axFrame,'equal');
        xlim(axFrame, [-Lf/2 - 0.5, Lf/2 + 0.5]);
        ylim(axFrame, [-Wf/2 - 0.4, Wf/2 + 0.4]);
        axTrim(axFrame);
        hold(axFrame,'off');
    end

    function axTrim(ax)
        ax.XAxis.Visible = 'off';
        ax.YAxis.Visible = 'off';
        ax.Toolbar.Visible = 'off';
        ax.Box = 'off';
    end

end