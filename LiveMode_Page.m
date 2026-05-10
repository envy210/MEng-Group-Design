function H = LiveMode_Page(parentFig, F, C)
% Live Mode page: simulates real-time tank filling via the FBG pipeline.
% Inputs: parentFig (host uifigure), F (FBG_v7_Functions), C (constants struct).

% Liquid presets: {name, specific gravity, outside_FEM_range}
LIQUIDS = { ...
    'Water',           1.000, false; ...
    'Diesel',          0.850, false; ...
    'Petrol',          0.740, false; ...
    'Jet A-1 fuel',    0.804, false; ...
    'Crude oil',       0.870, false; ...
    'Methanol',        0.791, false; ...
    'Ethanol',         0.789, false; ...
    'Acetone',         0.791, false; ...
    'Toluene',         0.867, false; ...
    'NaOH 30%',        1.320, false; ...
    'H2SO4 98%',       1.840, true;  ...
    'Custom',          1.000, false  };

% Fill rate options: {label, timer period (s), %/tick}
RATES = { ...
    'Slow  (0.5 %/s)',   1.0, 0.5; ...
    'Medium  (2 %/s)',   1.0, 2.0; ...
    'Fast  (5 %/s)',     0.5, 2.5  };

% Reduced TMM resolution for real-time performance.
% Sub-pm accuracy is preserved by the quadratic peak detector.
LIVE_FAST.lambda_span_nm = 0.5;
LIVE_FAST.n_lambda_pts   = 60;
LIVE_FAST.n_tmm_seg      = 15;

VIZ_PERIOD_S    = 0.050;   % 20 fps visual update rate
SMOOTH_ALPHA    = 0.20;    % exponential lerp factor per visual tick
SMOOTH_SNAP_TOL = 0.02;    % %fill below which display snaps to target

% =========================================================================
%  PAGE CONTAINER
% =========================================================================
panel = uipanel(parentFig, ...
    'Position',[10 10 1160 645], ...
    'BorderType','none', ...
    'BackgroundColor',[0.96 0.96 0.96], ...
    'Visible','off');

% =========================================================================
%  LEFT SIDE - INPUTS
% =========================================================================

% --- Fluid Setup panel ---------------------------------------------------
pnlFluid = uipanel(panel,'Title','Fluid Setup','Position',[10 470 360 175], ...
    'FontWeight','bold','FontSize',12,'BackgroundColor',[1 1 1]);

uilabel(pnlFluid,'Text','Liquid type:','Position',[15 115 90 22],'FontSize',11);
ddLiquid = uidropdown(pnlFluid, ...
    'Items', LIQUIDS(:,1)', ...
    'Position',[115 115 230 25],'FontSize',11, ...
    'ValueChangedFcn',@liquidChanged);

uilabel(pnlFluid,'Text','Specific gravity:','Position',[15 75 120 22],'FontSize',11);
efSG = uieditfield(pnlFluid,'numeric','Position',[135 75 210 25], ...
    'Value',1.0,'Limits',[0.5 2.0],'ValueDisplayFormat','%.3f', ...
    'FontSize',11,'Editable','off');

lblFluidNote = uilabel(pnlFluid,'Text', ...
    'Density within FEM validated range.', ...
    'Position',[15 35 330 22],'FontSize',10, ...
    'FontColor',[0.45 0.45 0.45]);

% --- Acquisition panel ---------------------------------------------------
pnlAcq = uipanel(panel,'Title','Acquisition','Position',[10 145 360 315], ...
    'FontWeight','bold','FontSize',12,'BackgroundColor',[1 1 1]);

uilabel(pnlAcq,'Text','Data source:','Position',[15 255 90 22],'FontSize',11);
ddSource = uidropdown(pnlAcq, ...
    'Items',{'Simulated fill (FEM-backed)','I-MON USB (not connected)'}, ...
    'Position',[115 255 230 25],'FontSize',11, ...
    'ValueChangedFcn',@sourceChanged);

uilabel(pnlAcq,'Text','Start fill (%):','Position',[15 215 90 22],'FontSize',11);
efStartFill = uieditfield(pnlAcq,'numeric','Position',[115 215 230 25], ...
    'Value',0,'Limits',[0 90],'ValueDisplayFormat','%.1f','FontSize',11);

uilabel(pnlAcq,'Text','Fill rate:','Position',[15 175 90 22],'FontSize',11);
ddRate = uidropdown(pnlAcq, ...
    'Items', RATES(:,1)', ...
    'Position',[115 175 230 25],'FontSize',11);

lblAcqStatus = uilabel(pnlAcq,'Text','Idle - press Start to begin.', ...
    'Position',[15 130 330 22],'FontSize',10, ...
    'FontColor',[0.45 0.45 0.45], ...
    'HorizontalAlignment','center', ...
    'FontWeight','bold');

btnStart = uibutton(pnlAcq,'push','Text','Start', ...
    'Position',[15 70 100 45],'FontSize',13,'FontWeight','bold', ...
    'BackgroundColor',[0.20 0.55 0.85],'FontColor',[1 1 1], ...
    'ButtonPushedFcn',@onStart);

btnStop = uibutton(pnlAcq,'push','Text','Stop', ...
    'Position',[125 70 100 45],'FontSize',13, ...
    'BackgroundColor',[1.0 0.75 0.20],'FontColor',[0 0 0], ...
    'Enable','off', ...
    'ButtonPushedFcn',@onStop);

btnReset = uibutton(pnlAcq,'push','Text','Reset', ...
    'Position',[235 70 100 45],'FontSize',13, ...
    'BackgroundColor',[0.85 0.85 0.85], ...
    'ButtonPushedFcn',@onReset);

uilabel(pnlAcq,'Text','Elapsed:','Position',[15 25 70 22],'FontSize',11);
lblElapsed = uilabel(pnlAcq,'Text','00:00', ...
    'Position',[90 25 100 22],'FontSize',13,'FontWeight','bold', ...
    'FontColor',[0.15 0.25 0.55]);

% --- SHM compact panel ---------------------------------------------------
pnlSHM = uipanel(panel,'Title','Structural Health Monitor', ...
    'Position',[10 10 360 130], ...
    'FontWeight','bold','FontSize',12,'BackgroundColor',[1 1 1]);

shmLamps = gobjects(1, 4);
shmEpsLbls = gobjects(1, 4);
for r = 1:4
    x0 = 10 + (r-1)*85;
    uilabel(pnlSHM,'Text',sprintf('R%d',r), ...
        'Position',[x0 75 25 18],'FontSize',10,'FontWeight','bold', ...
        'FontColor',[0.30 0.30 0.30]);
    shmLamps(r) = uilamp(pnlSHM,'Position',[x0+22 75 16 16], ...
        'Color',[0.7 0.7 0.7]);
    shmEpsLbls(r) = uilabel(pnlSHM,'Text','--', ...
        'Position',[x0 55 75 18],'FontSize',9, ...
        'FontColor',[0.30 0.30 0.30]);
end
uilabel(pnlSHM,'Text','µε', ...
    'Position',[335 55 20 18],'FontSize',9, ...
    'FontColor',[0.45 0.45 0.45]);

lblSHMStatus = uilabel(pnlSHM,'Text','Idle.', ...
    'Position',[10 30 230 18],'FontSize',10, ...
    'FontColor',[0.45 0.45 0.45]);

btnSHMDetail = uibutton(pnlSHM,'push','Text','Open Detail →', ...
    'Position',[245 25 100 28],'FontSize',10, ...
    'BackgroundColor',[0.94 0.94 0.94], ...
    'ButtonPushedFcn',@(~,~) onOpenSHMDetail());

% =========================================================================
%  RIGHT SIDE - OUTPUTS
% =========================================================================

% --- Status strip --------------------------------------------------------
pnlStatus = uipanel(panel,'Title','Status', ...
    'Position',[390 570 760 75], ...
    'FontWeight','bold','FontSize',12,'BackgroundColor',[1 1 1]);

lampStatus = uilamp(pnlStatus,'Position',[15 20 25 25],'Color',[0.7 0.7 0.7]);
lblStatusMsg = uieditfield(pnlStatus,'text','Position',[55 18 685 30], ...
    'Value','Idle - select fluid and press Start to begin acquisition.', ...
    'FontSize',12,'Editable','off','BackgroundColor',[1 1 1]);

% --- Tank diagram panel --------------------------------------------------
pnlTank = uipanel(panel,'Title','Tank Diagram (live)', ...
    'Position',[390 295 480 265], ...
    'FontWeight','bold','FontSize',12,'BackgroundColor',[1 1 1]);

axTank = uiaxes(pnlTank,'Position',[10 10 460 235]);
axTank.XAxis.Visible = 'off'; axTank.YAxis.Visible = 'off';
axTank.Toolbar.Visible = 'off'; axTank.Box = 'off';
axis(axTank,'equal');
try disableDefaultInteractivity(axTank); catch, end 

% --- Key readouts panel --------------------------------------------------
pnlReadouts = uipanel(panel,'Title','Key Readouts', ...
    'Position',[880 295 270 265], ...
    'FontWeight','bold','FontSize',12,'BackgroundColor',[1 1 1]);

[lblFillVal, ~] = makeBigReadout(pnlReadouts, 'Fill',        '%',  [15 175 240 60]);
[lblVolVal,  ~] = makeBigReadout(pnlReadouts, 'Volume',      'L',  [15 115 240 60]);
[lblMassVal, ~] = makeBigReadout(pnlReadouts, 'Mass',        'kg', [15  55 240 60]);
[lblTempVal, ~] = makeBigReadout(pnlReadouts, 'Temperature', '°C', [15  -5 240 60]);

% --- Bottom tab group ----------------------------------------------------
pnlBottom = uipanel(panel,'Title','', ...
    'Position',[390 10 760 280], ...
    'BorderType','none','BackgroundColor',[0.96 0.96 0.96]);

tabGroup = uitabgroup(pnlBottom,'Position',[0 0 760 280]);

% ---- Tab 1: FBG Detail --------------------------------------------------
tabFBG = uitab(tabGroup,'Title','FBG Detail');

uilabel(tabFBG,'Text','Select Sensor:','Position',[15 220 100 22], ...
    'FontSize',11,'FontWeight','bold');
ddSensor = uidropdown(tabFBG, ...
    'Items',buildSensorList(C), ...
    'Position',[120 220 230 25],'FontSize',11, ...
    'ValueChangedFcn',@(~,~)onSensorChanged());

uilabel(tabFBG,'Text','Wavelength shift (nm):', ...
    'Position',[365 220 140 22],'FontSize',11);
efDLam = uieditfield(tabFBG,'numeric','Position',[505 220 100 25], ...
    'Value',0,'Limits',[-10 10],'ValueDisplayFormat','%.4f','FontSize',11,'Editable','off');

uilabel(tabFBG,'Text','Strain (-):', ...
    'Position',[615 220 80 22],'FontSize',11);
efStrainTab = uieditfield(tabFBG,'numeric','Position',[680 220 70 25], ...
    'Value',0,'ValueDisplayFormat','%.2e','FontSize',10,'Editable','off');

% Thermal vs strain breakdown after T-decoupling
lblBreakdown = uilabel(tabFBG, ...
    'Text','  ↳  awaiting first measurement...', ...
    'Position',[365 188 385 20], ...
    'FontSize',10,'FontColor',[0.40 0.40 0.40]);

axSpec = uiaxes(tabFBG,'Position',[10 10 740 165]);
axSpec.FontSize = 10;
xlabel(axSpec,'Wavelength (nm)');
ylabel(axSpec,'Reflectivity (P.U.)');
grid(axSpec,'on'); box(axSpec,'on');
try disableDefaultInteractivity(axSpec); catch, end 

% ---- Tab 2: Acquisition Log ---------------------------------------------
tabLog = uitab(tabGroup,'Title','Acquisition Log');

logTable = uitable(tabLog, ...
    'Position',[10 50 740 200], ...
    'ColumnName',{'Time','Fill (%)','Vol (L)','Mass (kg)','Temp (°C)','Status'}, ...
    'ColumnWidth',{80, 90, 100, 100, 90, 'auto'}, ...
    'FontSize',10, ...
    'RowStriping','on');

uilabel(tabLog,'Text','Log auto-clears on Reset.', ...
    'Position',[10 15 250 22],'FontSize',10, ...
    'FontColor',[0.45 0.45 0.45]);

btnExport = uibutton(tabLog,'push','Text','Export to CSV...', ...
    'Position',[610 12 140 28],'FontSize',11, ...
    'BackgroundColor',[0.85 0.85 0.85], ...
    'ButtonPushedFcn',@onExportLog);

% =========================================================================
%  PAGE STATE
% =========================================================================
S.timer        = [];
S.is_running   = false;
S.fill_pct     = 0;         % hidden ground-truth fill percentage
S.T_session_C  = NaN;       % drawn at Start, fixed for session
S.start_time   = [];
S.tick_period  = 1.0;       % physics period (s)
S.fill_step    = 1.0;       % %fill per physics tick
S.lam_shifted  = [C.lam_bonded_nm(1) C.lam_ref_nm(1) ...
                  C.lam_bonded_nm(2) C.lam_ref_nm(2) ...
                  C.lam_bonded_nm(3) C.lam_ref_nm(3) ...
                  C.lam_bonded_nm(4) C.lam_ref_nm(4)];
S.lam0_all_nm  = S.lam_shifted;
S.computed     = false;
S.log_rows     = {};
S.FEM          = [];

% Smoothing: target = latest physics result; shown = displayed value
S.tick_counter           = 0;
S.physics_every_n_ticks  = 1;
S.target_fill_pct = 0; S.shown_fill_pct = 0;
S.target_vol_L    = 0; S.shown_vol_L    = 0;
S.target_mass_kg  = 0; S.shown_mass_kg  = 0;
S.target_T_C      = NaN; S.shown_T_C    = NaN;

S.last_T_est_C = NaN;
S.last_eps_rec = 0;

% Per-region SHM tracking (4 sensor pairs / saddle regions)
S.last_eps_per_pair    = zeros(1, 4);
S.last_stress_MPa_pair = zeros(1, 4);
S.last_FoS_per_pair    = inf(1, 4);
S.last_status_per_pair = {'OK','OK','OK','OK'};

% Strain history buffer: rows = [time_s, eps_R1, eps_R2, eps_R3, eps_R4]
S.history_max_rows = 600;
S.history_data     = [];

% Fault injection: 'none' | 'broken' | 'debonded' | 'erratic' per region
S.region_faults = {'none','none','none','none'};

% Rolling buffer of last 5 bonded wavelengths per region (erratic detection)
S.lam_meas_buf = nan(5, 4);

S.shmDetail = [];   % SHM detail panel (lazy-instantiated)

% Spectrum and tank diagram persistent line/patch handles
S.spec_unloaded_cache = cell(1, 8);
S.hSpecUnloaded       = [];
S.hSpecLoaded         = [];
S.spec_legend         = [];
S.hLiquid             = [];
S.hLevelLine          = [];
S.hLevelText          = [];

% Throttle flags: log table and SHM detail flush once per ~20 visual ticks
S.log_table_dirty   = false;
S.shm_update_dirty  = false;
S.throttle_counter  = 0;

% Auto-load FEM CSV; hydrostatic fallback used silently if absent
if exist('fem_strain_data.csv','file')
    try
        S.FEM = F.loadFEMStrainTable('fem_strain_data.csv');
        S.FEM.baseline_raw = buildBaselineLookup('fem_strain_data.csv');
    catch
    end
end

drawTank(0);
redrawSpectrum();

% =========================================================================
%  PUBLIC API
% =========================================================================
H.panel = panel;
H.show  = @() set(panel,'Visible','on');
H.hide  = @() doHide();
H.reset = @() onReset([],[]);

% =========================================================================
%  CALLBACKS
% =========================================================================

    function liquidChanged(src,~)
        idx = find(strcmp(LIQUIDS(:,1), src.Value), 1);
        if isempty(idx), return; end
        sg          = LIQUIDS{idx,2};
        is_outside  = LIQUIDS{idx,3};
        is_custom   = strcmp(src.Value,'Custom');

        efSG.Value     = sg;
        efSG.Editable  = is_custom;

        if is_outside
            lblFluidNote.Text      = 'Density above FEM range - amber warning will fire.';
            lblFluidNote.FontColor = [0.85 0.55 0.10];
        elseif is_custom
            lblFluidNote.Text      = 'Custom liquid - enter SG manually.';
            lblFluidNote.FontColor = [0.45 0.45 0.45];
        else
            lblFluidNote.Text      = 'Density within FEM validated range.';
            lblFluidNote.FontColor = [0.45 0.45 0.45];
        end
    end

    function sourceChanged(src,~)
        if strcmp(src.Value,'I-MON USB (not connected)')
            uialert(parentFig, ...
                ['No I-MON 256 USB device detected.', newline, ...
                 'Falling back to Simulated fill.'], ...
                'Hardware not connected','Icon','warning');
            src.Value = 'Simulated fill (FEM-backed)';
        end
    end

    function onStart(~,~)
        if S.is_running, return; end

        rate_idx               = find(strcmp(RATES(:,1), ddRate.Value), 1);
        S.tick_period          = RATES{rate_idx, 2};
        S.fill_step            = RATES{rate_idx, 3};
        S.physics_every_n_ticks = max(1, round(S.tick_period / VIZ_PERIOD_S));
        S.tick_counter         = S.physics_every_n_ticks;  % trigger physics on first tick

        S.fill_pct    = max(0, min(efStartFill.Value, 90));
        S.T_session_C = F.sampleTriangular(C.T_min_C, 30, C.T_max_C);
        S.start_time  = tic;
        S.is_running  = true;

        btnStart.Enable      = 'off';
        btnStop.Enable       = 'on';
        ddRate.Enable        = 'off';
        ddLiquid.Enable      = 'off';
        ddSource.Enable      = 'off';
        efStartFill.Enable   = 'off';
        lblAcqStatus.Text    = 'Acquiring...';
        lblAcqStatus.FontColor = [0.20 0.55 0.85];

        runPhysicsTick();
        S.shown_fill_pct = S.target_fill_pct;
        S.shown_vol_L    = S.target_vol_L;
        S.shown_mass_kg  = S.target_mass_kg;
        S.shown_T_C      = S.target_T_C;
        smoothAndDisplay();

        S.timer = timer('ExecutionMode','fixedSpacing', ...
            'Period', VIZ_PERIOD_S, ...
            'BusyMode','drop', ...
            'TimerFcn', @(~,~)unifiedTick());
        start(S.timer);
    end

    function onStop(~,~)
        stopTimerSafely();
        S.is_running         = false;
        btnStart.Enable      = 'on';
        btnStop.Enable       = 'off';
        ddRate.Enable        = 'on';
        ddLiquid.Enable      = 'on';
        ddSource.Enable      = 'on';
        efStartFill.Enable   = 'on';
        lblAcqStatus.Text    = sprintf('Paused at %.1f%%.', S.fill_pct);
        lblAcqStatus.FontColor = [0.85 0.55 0.10];
    end

    function onReset(~,~)
        stopTimerSafely();
        S.is_running    = false;
        S.fill_pct      = efStartFill.Value;
        S.T_session_C   = NaN;
        S.start_time    = [];
        S.computed      = false;
        S.log_rows      = {};
        S.lam_shifted   = S.lam0_all_nm;

        S.tick_counter    = 0;
        S.target_fill_pct = 0; S.shown_fill_pct = 0;
        S.target_vol_L    = 0; S.shown_vol_L    = 0;
        S.target_mass_kg  = 0; S.shown_mass_kg  = 0;
        S.target_T_C      = NaN; S.shown_T_C    = NaN;
        S.last_T_est_C    = NaN;
        S.last_eps_rec    = 0;
        S.last_eps_per_pair    = zeros(1, 4);
        S.last_stress_MPa_pair = zeros(1, 4);
        S.last_FoS_per_pair    = inf(1, 4);
        S.last_status_per_pair = {'OK','OK','OK','OK'};
        S.history_data    = [];
        S.lam_meas_buf    = nan(5, 4);
        % Faults are NOT cleared on Reset; use SHM detail "Clear All".

        S.spec_unloaded_cache = cell(1, 8);
        S.hSpecUnloaded       = [];
        S.hSpecLoaded         = [];
        S.hLiquid             = [];
        S.hLevelLine          = [];
        S.hLevelText          = [];
        S.log_table_dirty     = false;
        S.shm_update_dirty    = false;
        S.throttle_counter    = 0;

        btnStart.Enable      = 'on';
        btnStop.Enable       = 'off';
        ddRate.Enable        = 'on';
        ddLiquid.Enable      = 'on';
        ddSource.Enable      = 'on';
        efStartFill.Enable   = 'on';

        lblFillVal.Text = '0.00';
        lblVolVal.Text  = '0';
        lblMassVal.Text = '0';
        lblTempVal.Text = '--';
        lblElapsed.Text = '00:00';
        efDLam.Value    = 0;
        efStrainTab.Value = 0;
        lblBreakdown.Text = '  ↳  awaiting first measurement...';
        lblBreakdown.FontColor = [0.40 0.40 0.40];
        logTable.Data   = {};
        for r = 1:4
            shmLamps(r).Color = [0.7 0.7 0.7];
            shmEpsLbls(r).Text = '--';
        end
        lblSHMStatus.Text = 'Idle.';
        lblSHMStatus.FontColor = [0.45 0.45 0.45];
        if ~isempty(S.shmDetail) && isvalid(S.shmDetail.fig)
            S.shmDetail.update(S.last_eps_per_pair, S.last_stress_MPa_pair, ...
                S.last_FoS_per_pair, S.last_status_per_pair, ...
                S.history_data, S.region_faults);
        end
        lblAcqStatus.Text = 'Idle - press Start to begin.';
        lblAcqStatus.FontColor = [0.45 0.45 0.45];
        setStatus('default','Idle - select fluid and press Start to begin acquisition.');
        drawTank(0);
        redrawSpectrum();
    end

    % --- Unified timer tick: 20 fps visual; physics every Nth tick -------
    function unifiedTick()
        S.tick_counter = S.tick_counter + 1;

        if S.tick_counter >= S.physics_every_n_ticks
            S.tick_counter = 0;
            if S.fill_pct >= C.max_fill_frac * 100
                stopTimerSafely();
                S.is_running         = false;
                btnStart.Enable      = 'on';
                btnStop.Enable       = 'off';
                ddRate.Enable        = 'on';
                ddLiquid.Enable      = 'on';
                ddSource.Enable      = 'on';
                efStartFill.Enable   = 'on';
                lblAcqStatus.Text    = sprintf('Stopped at %.1f%% (operating max).', S.fill_pct);
                lblAcqStatus.FontColor = [0.85 0.30 0.30];
                setStatus('bad', sprintf( ...
                    'Filling stopped at %.1f%% - %.0f%% operating max reached.', ...
                    S.fill_pct, C.max_fill_frac*100));
                smoothAndDisplay();
                return;
            end

            S.fill_pct = min(S.fill_pct + S.fill_step, C.max_fill_frac * 100);
            runPhysicsTick();
        end

        smoothAndDisplay();

        S.throttle_counter = S.throttle_counter + 1;
        if S.throttle_counter >= 20
            S.throttle_counter = 0;
            flushLogTable();
            if S.shm_update_dirty && ~isempty(S.shmDetail) && ...
                    isvalid(S.shmDetail.fig) && ...
                    strcmp(S.shmDetail.fig.Visible,'on')
                S.shmDetail.update(S.last_eps_per_pair, S.last_stress_MPa_pair, ...
                    S.last_FoS_per_pair, S.last_status_per_pair, ...
                    S.history_data, S.region_faults);
                S.shm_update_dirty = false;
            end
        end
    end

    % --- Full sensing pipeline at LIVE_FAST resolution -------------------
    function runPhysicsTick()
        try
            rho      = efSG.Value * 1000;
            T_true_C = S.T_session_C;
            if isnan(T_true_C)
                T_true_C = F.sampleTriangular(C.T_min_C, 30, C.T_max_C);
                S.T_session_C = T_true_C;
            end
            T_query  = min(max(T_true_C, C.T_min_C), C.T_max_C);

            fill_frac_true = S.fill_pct / 100;
            h_true_m       = F.invertVolToHeight(fill_frac_true*C.V_cyl_m3, ...
                                  C.R_tank, C.L_tank, C.h_max);

            % Strain: FEM lookup or hydrostatic fallback
            if ~isempty(S.FEM)
                eps_mech = F.femStrainLookup(S.FEM, S.fill_pct, T_query, rho);
            else
                eps_mech = C.k_eps * rho * 9.81 * h_true_m;
            end

            % True Bragg wavelengths
            lam0_b = C.lam_bonded_nm * 1e-9;
            lam0_r = C.lam_ref_nm   * 1e-9;
            lam_true_b_m = lam0_b .* (1 + (1-C.p_e)*eps_mech + C.K_T*T_true_C);
            lam_true_r_m = lam0_r .* (1 + C.K_T*T_true_C);

            for p = 1:C.nPairs
                S.lam_shifted(2*p-1) = lam_true_b_m(p)*1e9;
                S.lam_shifted(2*p)   = lam_true_r_m(p)*1e9;
            end

            % Apply debonded fault: bonded sensor sees thermal shift only
            for p = 1:C.nPairs
                if strcmp(S.region_faults{p}, 'debonded')
                    lam_true_b_m(p) = lam0_b(p) * (1 + C.K_T*T_true_C);
                    S.lam_shifted(2*p-1) = lam_true_b_m(p)*1e9;
                end
            end

            % Interrogator: TMM + quadratic peak detection
            lam_meas_b_m = zeros(1, C.nPairs);
            lam_meas_r_m = zeros(1, C.nPairs);
            for p = 1:C.nPairs
                [ln, R] = F.simulate_spectrum_tmm(lam_true_b_m(p), C.n_eff, ...
                    C.L_grating, C.dn, LIVE_FAST.lambda_span_nm, ...
                    LIVE_FAST.n_lambda_pts, LIVE_FAST.n_tmm_seg, ...
                    C.sigma_apod, C.alpha_db_m);
                lam_meas_b_m(p) = F.detect_peak_quadratic(ln, R, C.noise_amp, C.res_pm);

                [ln, R] = F.simulate_spectrum_tmm(lam_true_r_m(p), C.n_eff, ...
                    C.L_grating, C.dn, LIVE_FAST.lambda_span_nm, ...
                    LIVE_FAST.n_lambda_pts, LIVE_FAST.n_tmm_seg, ...
                    C.sigma_apod, C.alpha_db_m);
                lam_meas_r_m(p) = F.detect_peak_quadratic(ln, R, C.noise_amp, C.res_pm);
            end

            % Post-detection fault injection
            % broken -> NaN (no signal); erratic -> ±5 pm jitter
            for p = 1:C.nPairs
                switch S.region_faults{p}
                    case 'broken'
                        lam_meas_b_m(p) = NaN;
                    case 'erratic'
                        lam_meas_b_m(p) = lam_meas_b_m(p) + (2*rand()-1)*5e-12;
                end
            end

            % Propagate fault state into spectrum display wavelengths
            for p = 1:C.nPairs
                switch S.region_faults{p}
                    case 'broken'
                        S.lam_shifted(2*p-1) = NaN;
                    case 'erratic'
                        if ~isnan(lam_meas_b_m(p))
                            S.lam_shifted(2*p-1) = lam_meas_b_m(p) * 1e9;
                        end
                end
            end

            % Update rolling buffer for erratic detection (std > 10 pm over 5 readings)
            S.lam_meas_buf = [S.lam_meas_buf(2:end, :); lam_meas_b_m * 1e9];

            % Temperature recovery
            dT_rec  = (lam_meas_r_m ./ lam0_r - 1) / C.K_T;
            T_est_C = mean(dT_rec, 'omitnan');

            % Erratic detection: std of last 5 readings > 10 pm
            buf_filled  = sum(~isnan(S.lam_meas_buf(:,1))) >= 5;
            sigma_per_p = std(S.lam_meas_buf, 0, 1, 'omitnan');   % nm
            erratic_now = false(1, C.nPairs);
            for p = 1:C.nPairs
                erratic_now(p) = buf_filled && sigma_per_p(p) > 0.010;
            end

            % Strain recovery; broken/erratic/debonded excluded
            eps_rec_per_pair = nan(1, C.nPairs);
            lam_sOnly_m      = nan(1, C.nPairs);
            for p = 1:C.nPairs
                if isnan(lam_meas_b_m(p)), continue; end
                if erratic_now(p), continue; end
                if strcmp(S.region_faults{p}, 'debonded'), continue; end
                dT_local = dT_rec(p);
                if isnan(dT_local), dT_local = T_est_C; end
                dLam_th  = lam0_b(p) * C.K_T * dT_local;
                dLam_str = (lam_meas_b_m(p) - lam0_b(p)) - dLam_th;
                eps_rec_per_pair(p) = dLam_str / (lam0_b(p)*(1-C.p_e));
                lam_sOnly_m(p) = lam0_b(p)*(1 + (1-C.p_e)*eps_rec_per_pair(p));
            end
            eps_rec = mean(eps_rec_per_pair, 'omitnan');

            % Height via calibration curve
            if ~isempty(S.FEM)
                eps_profile = F.femMechProfile(S.FEM, T_query, rho);
                h_profile   = S.FEM.h_profile_m;
            else
                h_profile   = linspace(0, C.h_max, 100)';
                eps_profile = C.k_eps * rho * 9.81 * h_profile;
            end
            h_rec_per_pair = nan(1, C.nPairs);
            for p = 1:C.nPairs
                if isnan(lam_sOnly_m(p)), continue; end
                lam_cal = lam0_b(p) .* (1 + (1-C.p_e).*eps_profile);
                h_rec_per_pair(p) = F.invert_lambda_to_height( ...
                    lam_sOnly_m(p), lam_cal, h_profile, C.calibration_method);
            end
            h_rec_m    = mean(h_rec_per_pair, 'omitnan');
            fill_f_rec = F.fill_fraction_from_height(h_rec_m, C.R_tank, C.L_tank);
            V_rec_L    = fill_f_rec * C.V_total_m3 * 1000;
            mass_rec_k = (V_rec_L/1000) * rho;
            fill_p_rec = fill_f_rec * 100;

            % Set smoothing targets (hold last valid value if all sensors broken)
            S.computed = true;
            if ~isnan(fill_p_rec)
                S.target_fill_pct = fill_p_rec;
                S.target_vol_L    = V_rec_L;
                S.target_mass_kg  = mass_rec_k;
            end
            S.target_T_C   = T_est_C;
            S.last_T_est_C = T_est_C;
            S.last_eps_rec = eps_rec;

            % Per-region stress and FoS 
            stress_MPa_per_pair = (C.E_beam * abs(eps_rec_per_pair)) / 1e6;
            eps_baseline_live   = getEpsBaseline(S.FEM, T_est_C, rho);
            eps_total_per_pair  = eps_rec_per_pair + eps_baseline_live;
            util_per_pair       = abs(eps_total_per_pair) / C.eps_perm_sensor;
            FoS_per_pair        = C.FoS_required ./ max(util_per_pair, C.safety_tiny);

            % Classify each region: broken / debonded / erratic / OK
            statuses = cell(1, 4);
            for p = 1:C.nPairs
                if isnan(lam_meas_b_m(p))
                    statuses{p} = 'broken';
                elseif strcmp(S.region_faults{p}, 'debonded') || ...
                       (S.fill_pct > 30 && abs(eps_rec_per_pair(p)) < ...
                            0.10 * abs(eps_rec))
                    statuses{p} = 'debonded';
                elseif erratic_now(p)
                    statuses{p} = 'erratic';
                else
                    statuses{p} = 'OK';
                end
            end

            S.last_eps_per_pair    = eps_rec_per_pair * 1e6;   % µε
            S.last_stress_MPa_pair = stress_MPa_per_pair;
            S.last_FoS_per_pair    = FoS_per_pair;
            S.last_status_per_pair = statuses;

            % Append to strain history buffer
            if isempty(S.start_time)
                t_now = 0;
            else
                t_now = toc(S.start_time);
            end
            new_row = [t_now, S.last_eps_per_pair];
            S.history_data = [S.history_data; new_row];
            if size(S.history_data, 1) > S.history_max_rows
                S.history_data = S.history_data(end-S.history_max_rows+1:end, :);
            end

            updateSHMCompact();
            if ~isempty(S.shmDetail) && isvalid(S.shmDetail.fig) && ...
                    strcmp(S.shmDetail.fig.Visible,'on')
                S.shm_update_dirty = true;
            end

            efStrainTab.Value = eps_rec;
            updateFBGDetail();

            redrawSpectrum();
            statusKind = applyStatus(fill_p_rec, mass_rec_k, rho);
            appendLog(fill_p_rec, V_rec_L, mass_rec_k, T_est_C, statusKind);

        catch ME
            stopTimerSafely();
            S.is_running = false;
            btnStart.Enable = 'on';
            btnStop.Enable  = 'off';
            setStatus('bad', sprintf('Acquisition error: %s', ME.message));
        end
    end

    % --- Exponential lerp of displayed values toward physics targets -----
    function smoothAndDisplay()
        a = SMOOTH_ALPHA;

        if ~isnan(S.target_fill_pct)
            S.shown_fill_pct = (1-a)*S.shown_fill_pct + a*S.target_fill_pct;
            S.shown_vol_L    = (1-a)*S.shown_vol_L    + a*S.target_vol_L;
            S.shown_mass_kg  = (1-a)*S.shown_mass_kg  + a*S.target_mass_kg;
        end

        if isnan(S.shown_T_C) && ~isnan(S.target_T_C)
            S.shown_T_C = S.target_T_C;
        elseif ~isnan(S.target_T_C)
            S.shown_T_C = (1-a)*S.shown_T_C + a*S.target_T_C;
        end

        if ~isnan(S.target_fill_pct) && abs(S.target_fill_pct - S.shown_fill_pct) < SMOOTH_SNAP_TOL
            S.shown_fill_pct = S.target_fill_pct;
            S.shown_vol_L    = S.target_vol_L;
            S.shown_mass_kg  = S.target_mass_kg;
            S.shown_T_C      = S.target_T_C;
        end

        lblFillVal.Text = sprintf('%.2f', S.shown_fill_pct);
        lblVolVal.Text  = sprintf('%.0f', S.shown_vol_L);
        lblMassVal.Text = sprintf('%.0f', S.shown_mass_kg);
        if ~isnan(S.shown_T_C)
            lblTempVal.Text = sprintf('%.2f', S.shown_T_C);
        end

        drawTank(max(0, min(1, S.shown_fill_pct/100)));
        updateElapsed();
    end

    function statusKind = applyStatus(fill_pct, mass_kg, rho_q)
        max_pct = C.max_fill_frac * 100;
        if fill_pct >= max_pct
            setStatus('bad', sprintf( ...
                'STOP - %.0f%% operating max reached (%.1f%%).', max_pct, fill_pct));
            statusKind = 'STOP';
        elseif fill_pct > max_pct - 10
            setStatus('warn', sprintf( ...
                'Caution: %.1f%% - approaching %.0f%% operating max.', fill_pct, max_pct));
            statusKind = 'CAUTION';
        elseif mass_kg > 26000
            setStatus('bad', sprintf('Overweight: %.0f kg exceeds ISO 26,000 kg limit.', mass_kg));
            statusKind = 'OVERWEIGHT';
        elseif rho_q > 1400
            setStatus('warn', sprintf('Density %.0f kg/m^3 outside FEM validated range.', rho_q));
            statusKind = 'EXTRAPOLATED';
        else
            setStatus('ok', sprintf('Filling normally: %.1f%%.', fill_pct));
            statusKind = 'OK';
        end
    end

    function updateElapsed()
        if isempty(S.start_time)
            lblElapsed.Text = '00:00';
            return;
        end
        secs = round(toc(S.start_time));
        lblElapsed.Text = sprintf('%02d:%02d', floor(secs/60), mod(secs,60));
    end

    % --- SHM compact panel: lamp colours and strain readouts per region --
    % Colour map: broken -> red; erratic/debonded -> amber; FoS < 1.5 -> red;
    % FoS < 2.0 -> amber; otherwise green.
    function updateSHMCompact()
        n_faulted = 0;
        worst_fault = '';
        for r = 1:4
            status = S.last_status_per_pair{r};
            FoS_r  = S.last_FoS_per_pair(r);
            if strcmp(status, 'broken')
                shmLamps(r).Color = [0.90 0.30 0.30];
                n_faulted = n_faulted + 1;
                if isempty(worst_fault), worst_fault = status; end
            elseif any(strcmp(status, {'erratic','debonded'}))
                shmLamps(r).Color = [1.00 0.60 0.10];
                n_faulted = n_faulted + 1;
                if isempty(worst_fault), worst_fault = status; end
            elseif FoS_r < 1.50
                shmLamps(r).Color = [0.90 0.30 0.30];
            elseif FoS_r < 2.00
                shmLamps(r).Color = [1.00 0.75 0.20];
            else
                shmLamps(r).Color = [0.30 0.75 0.35];
            end

            if isnan(S.last_eps_per_pair(r))
                shmEpsLbls(r).Text = '---';
            else
                shmEpsLbls(r).Text = sprintf('%.2f', S.last_eps_per_pair(r));
            end
        end

        if n_faulted == 0
            lblSHMStatus.Text = 'All sensors functioning.';
            lblSHMStatus.FontColor = [0.30 0.55 0.35];
        else
            if strcmp(worst_fault, 'broken')
                msg_color = [0.85 0.20 0.20];
            else
                msg_color = [0.85 0.40 0.10];
            end
            lblSHMStatus.Text = sprintf('%d region(s) flagged: %s.', ...
                n_faulted, worst_fault);
            lblSHMStatus.FontColor = msg_color;
        end
    end

    % --- Open the full SHM detail view (lazy-instantiated) --------------
    function onOpenSHMDetail()
        if isempty(S.shmDetail) || ~isvalid(S.shmDetail.fig)
            S.shmDetail = SHM_Panel(C, F, @onFaultsChanged);
            S.shmDetail.set_faults(S.region_faults);
        end
        S.shmDetail.show();
        S.shmDetail.update(S.last_eps_per_pair, S.last_stress_MPa_pair, ...
            S.last_FoS_per_pair, S.last_status_per_pair, ...
            S.history_data, S.region_faults);
    end

    function onFaultsChanged(new_faults)
        S.region_faults = new_faults;
        S.lam_meas_buf  = nan(5, 4);  % clear erratic buffer on fault change
    end

    function appendLog(fill_pct, vol_L, mass_kg, T_C, statusKind)
        if isempty(S.start_time)
            timestr = '00:00';
        else
            secs = round(toc(S.start_time));
            timestr = sprintf('%02d:%02d', floor(secs/60), mod(secs,60));
        end
        new_row = {timestr, ...
                   sprintf('%.2f', fill_pct), ...
                   sprintf('%.0f',  vol_L), ...
                   sprintf('%.0f',  mass_kg), ...
                   sprintf('%.2f',  T_C), ...
                   statusKind};
        S.log_rows = [new_row; S.log_rows];
        if size(S.log_rows,1) > 200
            S.log_rows = S.log_rows(1:200, :);
        end
        S.log_table_dirty = true;  % flushed periodically by throttle logic
    end

    function flushLogTable()
        if S.log_table_dirty
            logTable.Data = S.log_rows;
            S.log_table_dirty = false;
        end
    end

    function onExportLog(~,~)
        if isempty(S.log_rows)
            uialert(parentFig,'Nothing to export - log is empty.', ...
                'Export','Icon','info');
            return;
        end
        [f,p] = uiputfile({'*.csv','CSV file'}, 'Export acquisition log', ...
            sprintf('fbg_log_%s.csv', datestr(now,'yyyymmdd_HHMMSS')));
        if isequal(f,0), return; end
        try
            T = cell2table(S.log_rows, ...
                'VariableNames',{'Time','Fill_pct','Volume_L','Mass_kg','Temp_C','Status'});
            writetable(T, fullfile(p,f));
            setStatus('ok', sprintf('Log exported to %s.', f));
        catch ME
            uialert(parentFig, sprintf('Export failed: %s', ME.message), ...
                'Export error','Icon','error');
        end
    end

    function onSensorChanged()
        redrawSpectrum();
        updateFBGDetail();
    end

    % --- FBG detail: total Δλ and thermal/strain breakdown ---------------
    function updateFBGDetail()
        if isempty(ddSensor.Value), return; end
        idx = find(strcmp(ddSensor.Items, ddSensor.Value), 1);
        if isempty(idx), return; end

        lam0_nm   = S.lam0_all_nm(idx);
        lamS_nm   = S.lam_shifted(idx);
        is_bonded = mod(idx, 2) == 1;

        if S.computed && ~isnan(lamS_nm)
            efDLam.Value = max(-10, min(10, lamS_nm - lam0_nm));
        end

        if S.computed && ~isnan(S.last_T_est_C)
            lam0_m = lam0_nm * 1e-9;
            dl_thermal_pm = lam0_m * C.K_T * S.last_T_est_C * 1e12;
            pair_idx    = ceil(idx / 2);
            is_debonded = is_bonded && strcmp(S.region_faults{pair_idx}, 'debonded');
            if is_debonded
                lblBreakdown.Text = sprintf( ...
                    '  ↳  thermal: %+.1f pm     strain: 0.00 pm     (debonded - no strain transfer)', ...
                    dl_thermal_pm);
            elseif is_bonded
                dl_strain_pm = lam0_m * (1 - C.p_e) * S.last_eps_rec * 1e12;
                lblBreakdown.Text = sprintf( ...
                    '  ↳  thermal: %+.1f pm     strain: %+.2f pm     (after T-decoupling)', ...
                    dl_thermal_pm, dl_strain_pm);
            else
                lblBreakdown.Text = sprintf( ...
                    '  ↳  thermal: %+.1f pm     strain: 0.00 pm    (T-sensor, not bonded)', ...
                    dl_thermal_pm);
            end
            lblBreakdown.FontColor = [0.20 0.30 0.55];
        end
    end

% =========================================================================
%  TANK DIAGRAM RENDERING  (horizontal cylinder, circular-segment fill)
% =========================================================================

    function initTankCanvas()
        cla(axTank);
        hold(axTank,'on');

        Lt = C.L_tank; Rt = C.R_tank;
        xl_c = -Lt/2 + Rt;
        xr_c =  Lt/2 - Rt;

        % Stadium outline (drawn once)
        n_arc = 60;
        theta_R = linspace(pi/2, -pi/2, n_arc);
        theta_L = linspace(-pi/2, -3*pi/2, n_arc);
        outline_x = [linspace(xl_c, xr_c, 2), ...
                     xr_c + Rt*cos(theta_R(2:end)), ...
                     linspace(xr_c, xl_c, 2), ...
                     xl_c + Rt*cos(theta_L(2:end))];
        outline_y = [Rt, Rt, ...
                     Rt*sin(theta_R(2:end)), ...
                     -Rt, -Rt, ...
                     Rt*sin(theta_L(2:end))];
        fill(axTank, outline_x, outline_y, [0.97 0.97 0.97], ...
             'EdgeColor',[0.30 0.30 0.30],'LineWidth',2, ...
             'PickableParts','none');

        % Colour-coded fill bands (drawn once): slosh/amber, normal/green, caution/amber, stop/red
        x_band = Lt/2 + 0.18*Rt;
        w_band = 0.10*Rt;
        bands = {  ...
            0.00, 0.20, [0.40 0.80 0.40]; ...   
            0.20, 0.80, [0.95 0.75 0.30]; ...   
            0.80, 0.90, [0.40 0.80 0.40]; ...   
            0.90, 1.00, [0.85 0.30 0.30]  };    
        for k = 1:size(bands,1)
            y0 = -Rt + 2*Rt*bands{k,1};
            y1 = -Rt + 2*Rt*bands{k,2};
            fill(axTank, [x_band x_band+w_band x_band+w_band x_band], ...
                 [y0 y0 y1 y1], bands{k,3}, ...
                 'EdgeColor','none','FaceAlpha',0.85, ...
                 'PickableParts','none');
        end

        % Liquid patch and level line handles (updated each tick)
        S.hLiquid = fill(axTank, NaN, NaN, [0.30 0.65 0.95], ...
             'EdgeColor',[0.10 0.40 0.75],'LineWidth',1.0, ...
             'FaceAlpha',0.85, 'PickableParts','none');
        S.hLevelLine = plot(axTank, [NaN NaN], [NaN NaN], '--', ...
            'Color',[0.10 0.40 0.75],'LineWidth',1.5);
        S.hLevelText = text(axTank, NaN, NaN, '', ...
            'FontSize',10,'FontWeight','bold', ...
            'VerticalAlignment','middle','HorizontalAlignment','left');

        axis(axTank,'equal');
        xlim(axTank, [-Lt/2 - 0.4*Rt, Lt/2 + 0.7*Rt]);
        ylim(axTank, [-Rt - 0.2*Rt, Rt + 0.2*Rt]);
        axTank.XAxis.Visible = 'off';
        axTank.YAxis.Visible = 'off';
        axTank.Toolbar.Visible = 'off';
        disableDefaultInteractivity(axTank);
        hold(axTank,'off');
    end

    function drawTank(fill_frac)
        if isempty(S.hLiquid) || ~isvalid(S.hLiquid)
            initTankCanvas();
        end

        Lt = C.L_tank; Rt = C.R_tank;
        xl_c = -Lt/2 + Rt;
        xr_c =  Lt/2 - Rt;

        if fill_frac > 0.001
            h_liq      = -Rt + 2*Rt*fill_frac;
            theta_surf = asin(max(-1, min(1, h_liq/Rt)));
            theta_R = linspace(theta_surf, -pi/2, 30);
            theta_L = linspace(-pi/2, theta_surf, 30);

            liq_x = [ xl_c - Rt*cos(theta_surf), ...
                      xr_c + Rt*cos(theta_surf), ...
                      xr_c + Rt*cos(theta_R),    ...
                      xl_c,                      ...
                      xl_c - Rt*cos(theta_L)     ];
            liq_y = [ h_liq,                     ...
                      h_liq,                     ...
                      Rt*sin(theta_R),           ...
                      -Rt,                       ...
                      Rt*sin(theta_L)            ];

            set(S.hLiquid, 'XData', liq_x, 'YData', liq_y);
            set(S.hLevelLine, ...
                'XData', [-Lt/2 - 0.3*Rt, Lt/2 + 0.5*Rt], ...
                'YData', [h_liq h_liq]);
            set(S.hLevelText, ...
                'Position', [Lt/2 + 0.32*Rt, h_liq, 0], ...
                'String', sprintf(' %.1f%%', fill_frac*100));
        else
            set(S.hLiquid,    'XData', NaN, 'YData', NaN);
            set(S.hLevelLine, 'XData', [NaN NaN], 'YData', [NaN NaN]);
            set(S.hLevelText, 'String', '');
        end
    end

% =========================================================================
%  SPECTRUM DISPLAY  (persistent line handles; unloaded spectrum cached)
% =========================================================================
    function redrawSpectrum()
        idx = find(strcmp(ddSensor.Items, ddSensor.Value), 1);
        if isempty(idx), idx = 1; end
        lam0 = S.lam0_all_nm(idx);
        lamS = S.lam_shifted(idx);

        % Cache unloaded spectrum per sensor (depends only on fixed lam0)
        if isempty(S.spec_unloaded_cache{idx})
            DSP_PTS  = 600;
            DSP_SEG  = 50;
            DSP_SPAN = 1.2;
            [lam_u, R_u] = F.simulate_spectrum_tmm(lam0*1e-9, C.n_eff, ...
                C.L_grating, C.dn, DSP_SPAN, DSP_PTS, DSP_SEG, ...
                C.sigma_apod, C.alpha_db_m);
            S.spec_unloaded_cache{idx} = struct('lam_nm', lam_u, 'R', R_u);
        end
        cached = S.spec_unloaded_cache{idx};

        % First-time or post-reset: create persistent line handles
        need_init = isempty(S.hSpecUnloaded) || ~isvalid(S.hSpecUnloaded);
        if need_init
            cla(axSpec); hold(axSpec,'on');
            S.hSpecUnloaded = plot(axSpec, cached.lam_nm, cached.R, '-', ...
                'LineWidth', 1.4, 'Color', [0.45 0.45 0.45]);
            S.hSpecLoaded = plot(axSpec, NaN, NaN, '-', ...
                'LineWidth', 1.8, 'Color', [0.10 0.35 0.85]);
            hold(axSpec,'off');
            xlabel(axSpec,'Wavelength (nm)');
            ylabel(axSpec,'Reflectivity (P.U.)');
            grid(axSpec,'on');
            ylim(axSpec, [0 1.05]);
        end

        if ~all(get(S.hSpecUnloaded, 'XData') == cached.lam_nm)
            set(S.hSpecUnloaded, 'XData', cached.lam_nm, 'YData', cached.R);
        end

        if ~S.computed
            set(S.hSpecLoaded, 'XData', NaN, 'YData', NaN);
            S.hSpecLoaded.DisplayName = '';
        elseif isnan(lamS)
            % Broken sensor: show noise floor instead of a peak
            noise_x = linspace(lam0 - 1, lam0 + 1, 200);
            noise_y = 0.003 * abs(randn(1, 200));
            set(S.hSpecLoaded, 'XData', noise_x, 'YData', noise_y);
            S.hSpecLoaded.Color = [0.85 0.30 0.30];
            S.hSpecLoaded.DisplayName = 'No signal (broken sensor)';
        else
            DSP_PTS  = 600;
            DSP_SEG  = 50;
            DSP_SPAN = 1.2;
            [lam_l, R_l] = F.simulate_spectrum_tmm(lamS*1e-9, C.n_eff, ...
                C.L_grating, C.dn, DSP_SPAN, DSP_PTS, DSP_SEG, ...
                C.sigma_apod, C.alpha_db_m);
            set(S.hSpecLoaded, 'XData', lam_l, 'YData', R_l);
            S.hSpecLoaded.Color = [0.10 0.35 0.85];
            S.hSpecLoaded.DisplayName = sprintf('Loaded (\\lambda = %.3f nm)', lamS);
        end

        title(axSpec, sprintf('%s', ddSensor.Value));
        xlim(axSpec, [lam0-1 lam0+1]);
        S.hSpecUnloaded.DisplayName = sprintf('Unloaded (\\lambda_0 = %.3f nm)', lam0);
        legend(axSpec, 'Location','northeast','FontSize',9);
    end

% =========================================================================
%  HELPERS
% =========================================================================

    function setStatus(kind, msg)
        switch kind
            case 'ok',   lampStatus.Color = [0.30 0.75 0.35];
            case 'warn', lampStatus.Color = [1.0 0.75 0.20];
            case 'bad',  lampStatus.Color = [0.90 0.30 0.30];
            otherwise,   lampStatus.Color = [0.7 0.7 0.7];
        end
        lblStatusMsg.Value = msg;
    end

    function stopTimerSafely()
        if ~isempty(S.timer) && isvalid(S.timer)
            try stop(S.timer); end %#ok<TRYNC>
            try delete(S.timer); end %#ok<TRYNC>
        end
        S.timer = [];
    end

    function doHide()
        stopTimerSafely();
        S.is_running    = false;
        btnStart.Enable = 'on';
        btnStop.Enable  = 'off';
        ddRate.Enable        = 'on';
        ddLiquid.Enable      = 'on';
        ddSource.Enable      = 'on';
        efStartFill.Enable   = 'on';
        if ~isempty(S.start_time)
            lblAcqStatus.Text = sprintf('Paused at %.1f%% (mode switched).', S.fill_pct);
            lblAcqStatus.FontColor = [0.85 0.55 0.10];
        end
        if ~isempty(S.shmDetail) && isvalid(S.shmDetail.fig)
            S.shmDetail.hide();
        end
        set(panel,'Visible','off');
    end

end 


% ==========================================================================
%  FILE-LEVEL HELPERS
% ==========================================================================

function [valLbl, unitLbl] = makeBigReadout(parent, title, unit, pos)
% Create one large readout block: title label above, big number below.
    titleH = 22;
    numH   = pos(4) - titleH - 4;
    uilabel(parent, ...
        'Position',[pos(1) pos(2)+numH 100 titleH], ...
        'Text', title, 'FontSize',11,'FontWeight','bold', ...
        'FontColor',[0.30 0.30 0.30]);
    unitLbl = uilabel(parent, ...
        'Position',[pos(1)+pos(3)-50 pos(2)+numH 50 titleH], ...
        'Text', unit, 'FontSize',11, ...
        'FontColor',[0.30 0.30 0.30], ...
        'HorizontalAlignment','right');
    valLbl = uilabel(parent, ...
        'Position',[pos(1) pos(2) pos(3) numH], ...
        'Text','--', ...
        'FontSize',26,'FontWeight','bold', ...
        'FontColor',[0.15 0.25 0.55], ...
        'HorizontalAlignment','center');
end

function lst = buildSensorList(C)
% Dropdown items for the 8-sensor array.
    lst = cell(1, 8);
    for p = 1:4
        lst{2*p-1} = sprintf('Bonded FBG %d  (design: %d nm)', p, C.lam_bonded_nm(p));
        lst{2*p}   = sprintf('Temp. Sensor %d  (design: %d nm)', p, C.lam_ref_nm(p));
    end
end

function bl = buildBaselineLookup(csv_path)
% Extract raw FEM strain at 0% fill for each (T, rho) pair.
    raw   = readtable(csv_path, 'VariableNamingRule', 'preserve');
    mask0 = raw.("percentage_%") == 0;
    rows0 = raw(mask0, :);
    bl.temp_grid     = unique(rows0.("temperature_C"));
    bl.rho_grid      = unique(rows0.("density_kg_m3"));
    nT = numel(bl.temp_grid);
    nR = numel(bl.rho_grid);
    bl.baseline_grid = zeros(nT, nR);
    for i = 1:height(rows0)
        it = find(bl.temp_grid == rows0.("temperature_C")(i), 1);
        ir = find(bl.rho_grid  == rows0.("density_kg_m3")(i), 1);
        if ~isempty(it) && ~isempty(ir)
            bl.baseline_grid(it, ir) = rows0.("strain")(i);
        end
    end
end

function eps_bl = getEpsBaseline(FEM, T_query, rho_query)
% Interpolate raw FEM strain at 0% fill; returns 0 in fallback mode.
    if isempty(FEM) || ~isfield(FEM, 'baseline_raw')
        eps_bl = 0;
        return;
    end
    bl    = FEM.baseline_raw;
    T_c   = min(max(T_query,   min(bl.temp_grid)), max(bl.temp_grid));
    rho_c = min(max(rho_query, min(bl.rho_grid)),  max(bl.rho_grid));
    eps_bl = interp2(bl.rho_grid', bl.temp_grid, bl.baseline_grid, ...
                     rho_c, T_c, 'linear', 0);
end