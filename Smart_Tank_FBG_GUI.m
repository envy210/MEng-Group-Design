function Smart_Tank_FBG_GUI
% EG5565 Smart ISO Liquid Tank Container – FBG Sensor Software.
% Requires: FBG_v7_Functions.m, LiveMode_Page.m, fem_strain_data.csv

F = FBG_v7_Functions();

% --- Constants -----------------------------------------------------------
C.R_tank       = 2.1 / 2;              % m
C.L_tank       = 4.8;                  % m
C.h_max        = 2 * C.R_tank;
C.V_cyl_m3     = pi * C.R_tank^2 * C.L_tank;
C.V_total_m3   = 19.034;               % m^3
C.V_max_L      = C.V_total_m3 * 1000;
C.max_fill_frac = 0.90;

C.E_beam         = 2e11;              % Pa
C.sigma_yield    = 275e6;             % Pa, S275
C.FoS_design     = 1.5;
C.sigma_allow    = C.sigma_yield / C.FoS_design;  % 183.3 MPa

C.eps_perm_sensor = 6.5e-5;          % permissible FBG sensor strain
C.FoS_required    = 1.5;
C.safety_tiny     = 1e-12;           % division-by-zero floor

C.n_eff        = 1.45;
C.p11          = 0.121;
C.p12          = 0.270;
C.nu_f         = 0.17;
C.p_e          = (C.n_eff^2/2) * (C.p12 - C.nu_f*(C.p11 + C.p12));
C.K_T          = 8.76e-6;            % 1/degC
C.alpha_db_m   = 0.2;                % dB/m

C.lam_bonded_nm = [1531 1537 1543 1549]; % nm
C.lam_ref_nm    = [1534 1540 1546 1552]; % nm
C.nPairs        = 4;

C.L_grating     = 45e-3;             % m
C.dn            = 1e-4;
C.lambda_span_nm = 2.0;
C.n_lambda_pts  = 2000;
C.n_tmm_seg     = 200;
C.sigma_apod    = 0.35 * C.L_grating;
C.res_pm        = 0.5;               % pm
C.noise_amp     = 0.0;
C.calibration_method = 'linear';

C.rho_default   = 1000;
C.k_eps         = (11e-6) / (C.rho_default * 9.81 * C.h_max);  % hydrostatic fallback

C.T_min_C = -20;  % ISO 1496-3 ambient envelope
C.T_max_C =  40;

% --- Build GUI -----------------------------------------------------------
fig = uifigure('Name','FBG Sensor Software - Smart ISO Tank', ...
    'Position',[80 60 1180 720], 'Color',[0.96 0.96 0.96], 'Resize','off');

m_file = uimenu(fig,'Text','File');
uimenu(m_file,'Text','About...','MenuSelectedFcn',@(~,~)showAbout());
uimenu(m_file,'Text','Exit',    'MenuSelectedFcn',@(~,~)close(fig));
m_help = uimenu(fig,'Text','Help');
uimenu(m_help,'Text','Quick Guide','MenuSelectedFcn',@(~,~)showHelp());

uilabel(fig,'Position',[20 675 800 30], ...
    'Text','Smart ISO Tank Container - FBG Sensor Software', ...
    'FontSize',18,'FontWeight','bold','HorizontalAlignment','left', ...
    'FontColor',[0.15 0.25 0.55]);

swMode = uiswitch(fig,'slider', ...
    'Items',{'Forward','Live'}, ...
    'Position',[1050 685 60 25], ...
    'FontSize',11,'FontWeight','bold', ...
    'ValueChangedFcn',@onModeChanged);

% --- Default Model panel -------------------------------------------------
pnlDefault = uipanel(fig,'Title','Default Model','Position',[20 385 360 270], ...
    'FontWeight','bold','FontSize',12,'BackgroundColor',[1 1 1]);

btnInfo = uibutton(pnlDefault,'push','Text',char(9432), ...
    'Position',[325 220 25 25],'FontSize',14,'FontWeight','bold', ...
    'BackgroundColor',[0.94 0.94 0.94], ...
    'Tooltip',buildSpecTooltip(C), ...
    'ButtonPushedFcn',@(~,~)uialert(fig,buildSpecTooltip(C),'Key Specifications','Icon','info'));

cbDefault = uicheckbox(pnlDefault,'Text','Default Tank (R=1.05 m, L=4.8 m)', ...
    'Position',[15 215 300 25],'Value',1,'FontSize',11, ...
    'ValueChangedFcn',@defaultToggled);

uilabel(pnlDefault,'Text','Chose Input:','Position',[15 175 90 22],'FontSize',11);
ddInputType = uidropdown(pnlDefault, ...
    'Items',{'Liquid Height (mm)','Fill Percentage (%)','Volume (litres)','Mass (kg)'}, ...
    'Position',[115 175 230 25],'FontSize',11,'ValueChangedFcn',@inputTypeChanged);

uilabel(pnlDefault,'Text','Value:','Position',[15 135 90 22],'FontSize',11);
efValue = uieditfield(pnlDefault,'numeric','Position',[115 135 230 25], ...
    'Value',1700,'Limits',[0 Inf],'ValueDisplayFormat','%.2f','FontSize',11);

uilabel(pnlDefault,'Text','Specific Gravity:','Position',[15 95 120 22],'FontSize',11);
efSG = uieditfield(pnlDefault,'numeric','Position',[135 95 210 25], ...
    'Value',1.0,'Limits',[0.5 2.0],'ValueDisplayFormat','%.3f','FontSize',11);

cbFixT = uicheckbox(pnlDefault,'Text','Fix ambient T (°C):', ...
    'Position',[15 50 150 25],'Value',0,'FontSize',11,'ValueChangedFcn',@fixTChanged);
efFixT = uieditfield(pnlDefault,'numeric','Position',[170 50 80 25], ...
    'Value',25,'Limits',[C.T_min_C C.T_max_C],'ValueDisplayFormat','%.1f', ...
    'FontSize',11,'Enable','off');
uilabel(pnlDefault,'Text','(else random)','Position',[260 50 90 22], ...
    'FontSize',10,'FontColor',[0.45 0.45 0.45]);

% --- New Model panel -----------------------------------------------------
pnlNew = uipanel(fig,'Title','New Model','Position',[20 100 360 275], ...
    'FontWeight','bold','FontSize',12,'BackgroundColor',[1 1 1]);

cbNew = uicheckbox(pnlNew,'Text','New Tank','Position',[15 228 150 25], ...
    'Value',0,'FontSize',11,'ValueChangedFcn',@newToggled);

btnStrain = uibutton(pnlNew,'push','Text','Insert Strain Response (CSV)', ...
    'Position',[15 193 330 30],'FontSize',11,'Enable','off', ...
    'ButtonPushedFcn',@insertStrain);

uilabel(pnlNew,'Text','Tank Radius R (m):','Position',[15 158 150 22],'FontSize',11);
efNewR = uieditfield(pnlNew,'numeric','Position',[175 158 170 25], ...
    'Value',1.05,'Limits',[0.1 5],'Enable','off','ValueDisplayFormat','%.3f','FontSize',11);

uilabel(pnlNew,'Text','Tank Length L (m):','Position',[15 123 150 22],'FontSize',11);
efNewL = uieditfield(pnlNew,'numeric','Position',[175 123 170 25], ...
    'Value',4.8,'Limits',[0.1 30],'Enable','off','ValueDisplayFormat','%.3f','FontSize',11);

uilabel(pnlNew,'Text','Specific Gravity:','Position',[15 88 150 22],'FontSize',11);
efNewSG = uieditfield(pnlNew,'numeric','Position',[175 88 170 25], ...
    'Value',1.000,'Limits',[0.1 3],'Enable','off','ValueDisplayFormat','%.3f','FontSize',11);

uilabel(pnlNew,'Text','Chose Input:','Position',[15 53 90 22],'FontSize',11);
ddNewInput = uidropdown(pnlNew, ...
    'Items',{'Volume (litres)','Liquid Height (mm)','Fill Percentage (%)','Mass (kg)'}, ...
    'Position',[115 53 230 25],'FontSize',11,'Enable','off');

uilabel(pnlNew,'Text','Value:','Position',[15 18 90 22],'FontSize',11);
efNewValue = uieditfield(pnlNew,'numeric','Position',[115 18 230 25], ...
    'Value',0,'Enable','off','ValueDisplayFormat','%.2f','FontSize',11);

% --- Calculate / Reset ---------------------------------------------------
btnCalc = uibutton(fig,'push','Text','Calculate', ...
    'Position',[60 35 200 45],'FontSize',14,'FontWeight','bold', ...
    'BackgroundColor',[0.20 0.55 0.85],'FontColor',[1 1 1], ...
    'ButtonPushedFcn',@runCalculation);

btnReset = uibutton(fig,'push','Text','Reset', ...
    'Position',[270 35 100 45],'FontSize',13, ...
    'BackgroundColor',[0.85 0.85 0.85],'ButtonPushedFcn',@resetAll);

% --- Status panel --------------------------------------------------------
pnlStatus = uipanel(fig,'Title','Status','Position',[400 580 760 75], ...
    'FontWeight','bold','FontSize',12,'BackgroundColor',[1 1 1]);

lampStatus = uilamp(pnlStatus,'Position',[15 20 25 25],'Color',[0.7 0.7 0.7]);
lblStatusMsg = uieditfield(pnlStatus,'text','Position',[55 18 685 30], ...
    'Value','Enter inputs and press Calculate','FontSize',12,'Editable','off', ...
    'BackgroundColor',[1 1 1]);

% --- Measurements panel --------------------------------------------------
pnlMeas = uipanel(fig,'Title','Measurements','Position',[400 290 760 280], ...
    'FontWeight','bold','FontSize',12,'BackgroundColor',[1 1 1]);

rowY = @(n) 225 - (n-1)*32;

uilabel(pnlMeas,'Text','Factor of Safety:',  'Position',[15 rowY(1) 140 22],'FontSize',10,'FontWeight','bold');
efFoS = uieditfield(pnlMeas,'numeric','Position',[160 rowY(1) 110 25], ...
    'Editable','off','Value',0,'Limits',[0 Inf],'ValueDisplayFormat','%.1f','FontSize',10);

uilabel(pnlMeas,'Text','Total Mass (kg):', 'Position',[15 rowY(2) 140 22],'FontSize',10,'FontWeight','bold');
efMass = uieditfield(pnlMeas,'numeric','Position',[160 rowY(2) 110 25], ...
    'Editable','off','Value',0,'ValueDisplayFormat','%.0f','FontSize',10);

uilabel(pnlMeas,'Text','FBG Strain (-):', 'Position',[15 rowY(3) 140 22],'FontSize',10,'FontWeight','bold');
efStrain = uieditfield(pnlMeas,'numeric','Position',[160 rowY(3) 110 25], ...
    'Editable','off','Value',0,'ValueDisplayFormat','%.7f','FontSize',10);

uilabel(pnlMeas,'Text','Volume (litres):', 'Position',[15 rowY(4) 140 22],'FontSize',10,'FontWeight','bold');
efVolume = uieditfield(pnlMeas,'numeric','Position',[160 rowY(4) 110 25], ...
    'Editable','off','Value',0,'ValueDisplayFormat','%.1f','FontSize',10);

uilabel(pnlMeas,'Text','Stress (MPa):', 'Position',[15 rowY(5) 140 22],'FontSize',10,'FontWeight','bold');
efStressMPa = uieditfield(pnlMeas,'numeric','Position',[160 rowY(5) 110 25], ...
    'Editable','off','Value',0,'ValueDisplayFormat','%.2f','FontSize',10);

uilabel(pnlMeas,'Text','Liquid Height (mm):','Position',[15 rowY(6) 140 22],'FontSize',10,'FontWeight','bold');
efHeight = uieditfield(pnlMeas,'numeric','Position',[160 rowY(6) 110 25], ...
    'Editable','off','Value',0,'ValueDisplayFormat','%.2f','FontSize',10);

uilabel(pnlMeas,'Text','Temperature (°C):','Position',[15 rowY(7) 140 22],'FontSize',10,'FontWeight','bold');
efTempRec = uieditfield(pnlMeas,'numeric','Position',[160 rowY(7) 110 25], ...
    'Editable','off','Value',0,'ValueDisplayFormat','%.2f','FontSize',10);

gVol = uigauge(pnlMeas,'semicircular','Position',[300 90 200 140], ...
    'Limits',[0 100],'Value',0, ...
    'ScaleColors',{[0.30 0.75 0.35],[1.0 0.75 0.20], [0.90 0.30 0.30]}, ...
    'ScaleColorLimits',[0 80; 80 90;90 100],'MajorTicks',0:20:100,'FontSize',10);
uilabel(pnlMeas,'Text','Volume (%)','Position',[360 235 90 20], ...
    'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

gStrain = uigauge(pnlMeas,'semicircular','Position',[540 90 200 140], ...
    'Limits',[0 15],'Value',0, ...
    'ScaleColors',{[0.30 0.75 0.35],[1.0 0.75 0.20],[0.90 0.30 0.30]}, ...
    'ScaleColorLimits',[0 9; 9 12; 12 15], ...
    'MajorTicks',0:3:15,'FontSize',10);
uilabel(pnlMeas,'Text','Strain (µε)','Position',[600 235 90 20], ...
    'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

% --- Spectral Response panel ---------------------------------------------
pnlSpec = uipanel(fig,'Title','Spectral Response','Position',[400 20 760 260], ...
    'FontWeight','bold','FontSize',12,'BackgroundColor',[1 1 1]);

uilabel(pnlSpec,'Text','FBG Sensor','Position',[15 205 90 22],'FontSize',11,'FontWeight','bold');
uilabel(pnlSpec,'Text','Select Sensor:','Position',[115 205 90 22],'FontSize',11);

ddSensor = uidropdown(pnlSpec,'Items',buildSensorList(C), ...
    'Position',[210 205 230 25],'FontSize',11,'ValueChangedFcn',@sensorChanged);

uilabel(pnlSpec,'Text','Wavelength shift (nm):','Position',[465 205 140 22],'FontSize',11);
efDLam = uieditfield(pnlSpec,'numeric','Position',[605 205 120 25], ...
    'Editable','off','Value',0,'ValueDisplayFormat','%.4f','FontSize',11);

axSpec = uiaxes(pnlSpec,'Position',[15 10 735 190]);
axSpec.XLabel.String = 'Wavelength (nm)';
axSpec.YLabel.String = 'Reflectivity (P.U.)';
axSpec.FontSize = 10;
grid(axSpec,'on'); box(axSpec,'on');

% --- App state -----------------------------------------------------------
S.computed       = false;
S.lam0_all_nm    = [C.lam_bonded_nm(1) C.lam_ref_nm(1) ...
                    C.lam_bonded_nm(2) C.lam_ref_nm(2) ...
                    C.lam_bonded_nm(3) C.lam_ref_nm(3) ...
                    C.lam_bonded_nm(4) C.lam_ref_nm(4)];
S.lam_shifted_nm = S.lam0_all_nm;
S.is_bonded      = logical([1 0 1 0 1 0 1 0]);
S.T_ambient_C    = [];

% Auto-load default FEM table; falls back to hydrostatic model if absent.
DEFAULT_FEM_FILE = 'fem_strain_data.csv';
if isfile(DEFAULT_FEM_FILE)
    try
        S.FEM = F.loadFEMStrainTable(DEFAULT_FEM_FILE);
        S.FEM.baseline_raw = buildBaselineLookup(DEFAULT_FEM_FILE);
        fprintf('Default FEM table auto-loaded: %s\n', DEFAULT_FEM_FILE);
    catch ME
        S.FEM = [];
        warning('Smart_Tank_GUI:femLoad', ...
            'Could not auto-load %s: %s. Using hydrostatic fallback.', ...
            DEFAULT_FEM_FILE, ME.message);
    end
else
    S.FEM = [];
    warning('Smart_Tank_GUI:femMissing', ...
        '%s not found in working directory. Using hydrostatic fallback.', ...
        DEFAULT_FEM_FILE);
end

plotSpectrumForCurrentSensor();

% --- Page management -----------------------------------------------------
forwardHandles = {pnlDefault, pnlNew, pnlStatus, pnlMeas, pnlSpec, btnCalc, btnReset};

livePage = LiveMode_Page(fig, F, C);

swMode.Value = 'Forward';
showForwardMode();

% =========================================================================
%  CALLBACKS
% =========================================================================

    function defaultToggled(src,~)
        if src.Value
            cbNew.Value = 0;
            setNewEnabled(false);
            setDefaultEnabled(true);
        else
            setDefaultEnabled(false);
        end
    end

    function newToggled(src,~)
        if src.Value
            cbDefault.Value = 0;
            setDefaultEnabled(false);
            setNewEnabled(true);
        else
            setNewEnabled(false);
        end
    end

    function setDefaultEnabled(tf)
        s = onoff(tf);
        ddInputType.Enable = s; efValue.Enable = s;
        efSG.Enable = s; cbFixT.Enable = s;
    end

    function setNewEnabled(tf)
        s = onoff(tf);
        btnStrain.Enable  = s; efNewR.Enable     = s;
        efNewL.Enable     = s; efNewSG.Enable    = s;
        ddNewInput.Enable = s; efNewValue.Enable = s;
    end

    function inputTypeChanged(src,~)
        switch src.Value
            case 'Liquid Height (mm)',   efValue.Value = 1700;
            case 'Fill Percentage (%)',  efValue.Value = 80;
            case 'Volume (litres)',      efValue.Value = 15000;
            case 'Mass (kg)',            efValue.Value = 15000;
        end
    end

    function fixTChanged(src,~)
        efFixT.Enable = onoff(src.Value);
    end

    function insertStrain(~,~)
        [f, p] = uigetfile({'*.csv','CSV (strain table)';'*.txt','Text file'}, ...
            'Select FEM strain response');
        if isequal(f, 0), return; end
        try
            full_path = fullfile(p, f);
            S.FEM = F.loadFEMStrainTable(full_path);
            S.FEM.baseline_raw = buildBaselineLookup(full_path);
            setStatus('ok', sprintf('FEM table loaded: %s  (%d rows)', f, S.FEM.nRows));
        catch ME
            setStatus('bad', sprintf('Failed to load %s: %s', f, ME.message));
        end
    end

    function sensorChanged(~,~)
        plotSpectrumForCurrentSensor();
        updateShiftReadout();
    end

    function resetAll(~,~)
        efFoS.Value = 0;    efMass.Value = 0;    efStrain.Value = 0;
        efVolume.Value = 0; efStressMPa.Value = 0; efHeight.Value = 0;
        efTempRec.Value = 0; efDLam.Value = 0;
        gVol.Value = 0;     gStrain.Value = 0;
        lampStatus.Color = [0.7 0.7 0.7];
        lblStatusMsg.Value = 'Enter inputs and press Calculate';
        S.computed = false;
        S.lam_shifted_nm = S.lam0_all_nm;
        S.T_ambient_C = [];
        plotSpectrumForCurrentSensor();
    end

    function runCalculation(~,~)
        try
            if cbDefault.Value
                btnCalc.Enable = 'off';
                btnCalc.Text   = 'Computing...';
                setStatus('warn', 'Computing — running TMM spectral simulation...');
                drawnow;  % flush UI before blocking on TMM
                doDefaultCalculation();
                btnCalc.Text   = 'Calculate';
                btnCalc.Enable = 'on';
            elseif cbNew.Value
                btnCalc.Enable = 'off';
                btnCalc.Text   = 'Computing...';
                setStatus('warn', 'Computing - running TMM spectral simulation...');
                drawnow;
                doNewCalculation();
                btnCalc.Text   = 'Calculate';
                btnCalc.Enable = 'on';
            else
                setStatus('bad', 'Select Default Tank or New Tank first.');
            end
        catch ME
            btnCalc.Text   = 'Calculate';
            btnCalc.Enable = 'on';
            setStatus('bad', sprintf('Error: %s', ME.message));
        end
    end

    function onModeChanged(src,~)
        if strcmp(src.Value,'Live')
            hideForwardMode();
            livePage.show();
        else
            livePage.hide();
            showForwardMode();
        end
    end

    function showForwardMode()
        for k = 1:numel(forwardHandles)
            forwardHandles{k}.Visible = 'on';
        end
    end

    function hideForwardMode()
        for k = 1:numel(forwardHandles)
            forwardHandles{k}.Visible = 'off';
        end
    end

% =========================================================================
%  CALCULATION PIPELINE
% =========================================================================

    function doDefaultCalculation()

        % 1. Operator inputs ----------------------------------------------
        rho  = efSG.Value * 1000;   % kg/m^3
        val  = efValue.Value;
        typ  = ddInputType.Value;

        if cbFixT.Value
            S.T_ambient_C = efFixT.Value;
        else
            S.T_ambient_C = F.sampleTriangular(C.T_min_C, 30, C.T_max_C);
        end
        T_true_C = S.T_ambient_C;
        T_query  = min(max(T_true_C, C.T_min_C), C.T_max_C);

        % 2. Convert input to height / fill fraction -----------------------
        switch typ
            case 'Liquid Height (mm)'
                h_m       = val / 1000;
                fill_frac = F.fill_fraction_from_height(h_m, C.R_tank, C.L_tank);
            case 'Fill Percentage (%)'
                fill_frac = val / 100;
                h_m = F.invertVolToHeight(fill_frac*C.V_cyl_m3, C.R_tank, C.L_tank, C.h_max);
            case 'Volume (litres)'
                fill_frac = (val/1000) / C.V_total_m3;
                h_m = F.invertVolToHeight(fill_frac*C.V_cyl_m3, C.R_tank, C.L_tank, C.h_max);
            case 'Mass (kg)'
                fill_frac = (val/rho) / C.V_total_m3;
                h_m = F.invertVolToHeight(fill_frac*C.V_cyl_m3, C.R_tank, C.L_tank, C.h_max);
        end
        fill_frac = max(0, min(fill_frac, 1));
        h_m       = max(0, min(h_m, C.h_max));
        fill_p    = fill_frac * 100;

        V_L    = fill_frac * C.V_total_m3 * 1000;
        mass_k = (V_L / 1000) * rho;

        % 3. Mechanical strain --------------------------------------------
        if ~isempty(S.FEM)
            eps_mech = F.femStrainLookup(S.FEM, fill_p, T_query, rho);
        else
            eps_mech = C.k_eps * rho * 9.81 * h_m;  % hydrostatic fallback
        end

        % 4. True Bragg wavelengths --------------------
        lam0_b = C.lam_bonded_nm * 1e-9;
        lam0_r = C.lam_ref_nm   * 1e-9;
        lam_true_bonded_m = lam0_b .* (1 + (1-C.p_e)*eps_mech + C.K_T*T_true_C);
        lam_true_ref_m    = lam0_r .* (1 + C.K_T*T_true_C);

        for p = 1:C.nPairs
            S.lam_shifted_nm(2*p-1) = lam_true_bonded_m(p) * 1e9;
            S.lam_shifted_nm(2*p)   = lam_true_ref_m(p)   * 1e9;
        end

        % 5. Interrogator: TMM spectrum + quadratic peak detection ---------
        lam_meas_bonded_m = zeros(1, C.nPairs);
        lam_meas_ref_m    = zeros(1, C.nPairs);
        for p = 1:C.nPairs
            [lam_nm, R] = F.simulate_spectrum_tmm(lam_true_bonded_m(p), ...
                C.n_eff, C.L_grating, C.dn, C.lambda_span_nm, ...
                C.n_lambda_pts, C.n_tmm_seg, C.sigma_apod, C.alpha_db_m);
            lam_meas_bonded_m(p) = F.detect_peak_quadratic(lam_nm, R, C.noise_amp, C.res_pm);

            [lam_nm, R] = F.simulate_spectrum_tmm(lam_true_ref_m(p), ...
                C.n_eff, C.L_grating, C.dn, C.lambda_span_nm, ...
                C.n_lambda_pts, C.n_tmm_seg, C.sigma_apod, C.alpha_db_m);
            lam_meas_ref_m(p) = F.detect_peak_quadratic(lam_nm, R, C.noise_amp, C.res_pm);
        end

        % 6. Temperature recovery --------------------------
        dT_rec  = (lam_meas_ref_m ./ lam0_r - 1) / C.K_T;
        T_est_C = mean(dT_rec);

        % 7. Strain recovery -------------------------------
        eps_rec_per_pair = zeros(1, C.nPairs);
        lam_sOnly_m      = zeros(1, C.nPairs);
        for p = 1:C.nPairs
            dLam_th  = lam0_b(p) * C.K_T * dT_rec(p);
            dLam_str = (lam_meas_bonded_m(p) - lam0_b(p)) - dLam_th;
            eps_rec_per_pair(p) = dLam_str / (lam0_b(p) * (1 - C.p_e));
            lam_sOnly_m(p) = lam0_b(p) * (1 + (1-C.p_e) * eps_rec_per_pair(p));
        end
        eps_rec = mean(eps_rec_per_pair);

        % 8. Height via calibration curve ---------------------------------
        if ~isempty(S.FEM)
            eps_profile = F.femMechProfile(S.FEM, T_query, rho);
            h_profile   = S.FEM.h_profile_m;
        else
            h_profile   = linspace(0, C.h_max, 100)';
            eps_profile = C.k_eps * rho * 9.81 * h_profile;
        end

        h_rec_per_pair = zeros(1, C.nPairs);
        for p = 1:C.nPairs
            lam_cal = lam0_b(p) .* (1 + (1-C.p_e) .* eps_profile);
            h_rec_per_pair(p) = F.invert_lambda_to_height( ...
                lam_sOnly_m(p), lam_cal, h_profile, C.calibration_method);
        end
        h_rec_m    = mean(h_rec_per_pair);
        fill_f_rec = F.fill_fraction_from_height(h_rec_m, C.R_tank, C.L_tank);
        V_rec_L    = fill_f_rec * C.V_total_m3 * 1000;
        mass_rec_k = (V_rec_L / 1000) * rho;
        fill_p_rec = fill_f_rec * 100;

        % 9. Stress and Factor of Safety  ------------------
        % eps_total = eps_mech_recovered + eps_baseline (raw FEM at 0% fill)
        eps_baseline = getEpsBaseline(S.FEM, T_query, rho);
        eps_total    = eps_rec + eps_baseline;
        strain_util  = abs(eps_total) / C.eps_perm_sensor;
        FoS          = C.FoS_required / max(strain_util, C.safety_tiny);
        sigma_Pa     = C.E_beam * abs(eps_rec);
        sigma_MPa    = sigma_Pa / 1e6;

        % 10. Update display -----------------------------------------------
        efHeight.Value    = h_rec_m * 1000;
        efVolume.Value    = V_rec_L;
        efMass.Value      = mass_rec_k;
        efStrain.Value    = eps_rec;
        efStressMPa.Value = sigma_MPa;
        efFoS.Value       = FoS;
        efTempRec.Value   = T_est_C;
        gVol.Value        = max(0, min(100, fill_p_rec));
        gStrain.Value     = max(0, min(15, abs(eps_rec) * 1e6));

        applyStatusLogic(fill_p_rec, mass_rec_k, rho, sigma_MPa, FoS);

        S.computed = true;
        plotSpectrumForCurrentSensor();
        updateShiftReadout();
    end

% =========================================================================
%  NEW MODEL CALCULATION  (operator-supplied geometry + custom FEM CSV)
% =========================================================================

    function doNewCalculation()
        if isempty(S.FEM)
            setStatus('bad', 'Load a strain response CSV via Insert Strain Response first.');
            return;
        end
        R_new = efNewR.Value;
        L_new = efNewL.Value;
        rho   = efNewSG.Value * 1000;
        if R_new <= 0 || L_new <= 0
            setStatus('bad', 'Tank radius and length must both be greater than zero.');
            return;
        end

        h_max_new   = 2 * R_new;
        V_cyl_new   = pi * R_new^2 * L_new;
        V_total_new = V_cyl_new;

        T_true_C = F.sampleTriangular(C.T_min_C, 30, C.T_max_C);
        T_query  = min(max(T_true_C, C.T_min_C), C.T_max_C);

        val = efNewValue.Value;
        typ = ddNewInput.Value;
        switch typ
            case 'Liquid Height (mm)'
                h_m       = val / 1000;
                fill_frac = F.fill_fraction_from_height(h_m, R_new, L_new);
            case 'Fill Percentage (%)'
                fill_frac = val / 100;
                h_m = F.invertVolToHeight(fill_frac*V_cyl_new, R_new, L_new, h_max_new);
            case 'Volume (litres)'
                fill_frac = (val/1000) / V_total_new;
                h_m = F.invertVolToHeight(fill_frac*V_cyl_new, R_new, L_new, h_max_new);
            case 'Mass (kg)'
                fill_frac = (val/rho) / V_total_new;
                h_m = F.invertVolToHeight(fill_frac*V_cyl_new, R_new, L_new, h_max_new);
        end
        fill_frac = max(0, min(fill_frac, 1));
        h_m       = max(0, min(h_m, h_max_new));
        fill_p    = fill_frac * 100;
        V_L       = fill_frac * V_total_new * 1000;
        mass_k    = (V_L / 1000) * rho;

        eps_mech = F.femStrainLookup(S.FEM, fill_p, T_query, rho);

        lam0_b = C.lam_bonded_nm * 1e-9;
        lam0_r = C.lam_ref_nm   * 1e-9;
        lam_true_bonded_m = lam0_b .* (1 + (1-C.p_e)*eps_mech + C.K_T*T_true_C);
        lam_true_ref_m    = lam0_r .* (1 + C.K_T*T_true_C);

        for p = 1:C.nPairs
            S.lam_shifted_nm(2*p-1) = lam_true_bonded_m(p) * 1e9;
            S.lam_shifted_nm(2*p)   = lam_true_ref_m(p)   * 1e9;
        end

        lam_meas_bonded_m = zeros(1, C.nPairs);
        lam_meas_ref_m    = zeros(1, C.nPairs);
        for p = 1:C.nPairs
            [lam_nm, Rspec] = F.simulate_spectrum_tmm(lam_true_bonded_m(p), ...
                C.n_eff, C.L_grating, C.dn, C.lambda_span_nm, ...
                C.n_lambda_pts, C.n_tmm_seg, C.sigma_apod, C.alpha_db_m);
            lam_meas_bonded_m(p) = F.detect_peak_quadratic(lam_nm, Rspec, C.noise_amp, C.res_pm);

            [lam_nm, Rspec] = F.simulate_spectrum_tmm(lam_true_ref_m(p), ...
                C.n_eff, C.L_grating, C.dn, C.lambda_span_nm, ...
                C.n_lambda_pts, C.n_tmm_seg, C.sigma_apod, C.alpha_db_m);
            lam_meas_ref_m(p) = F.detect_peak_quadratic(lam_nm, Rspec, C.noise_amp, C.res_pm);
        end

        dT_rec  = (lam_meas_ref_m ./ lam0_r - 1) / C.K_T;
        T_est_C = mean(dT_rec);

        eps_rec_per_pair = zeros(1, C.nPairs);
        lam_sOnly_m      = zeros(1, C.nPairs);
        for p = 1:C.nPairs
            dLam_th  = lam0_b(p) * C.K_T * dT_rec(p);
            dLam_str = (lam_meas_bonded_m(p) - lam0_b(p)) - dLam_th;
            eps_rec_per_pair(p) = dLam_str / (lam0_b(p) * (1 - C.p_e));
            lam_sOnly_m(p) = lam0_b(p) * (1 + (1-C.p_e) * eps_rec_per_pair(p));
        end
        eps_rec = mean(eps_rec_per_pair);

        % Rebuild height profile for custom geometry ----------------------
        nPct = numel(S.FEM.pct_grid);
        h_profile_new = zeros(nPct, 1);
        for i = 1:nPct
            V_geom = (S.FEM.pct_grid(i) / 100) * V_cyl_new;
            h_profile_new(i) = F.invertVolToHeight(V_geom, R_new, L_new, h_max_new);
        end

        eps_profile = F.femMechProfile(S.FEM, T_query, rho);
        h_rec_per_pair = zeros(1, C.nPairs);
        for p = 1:C.nPairs
            lam_cal = lam0_b(p) .* (1 + (1-C.p_e) .* eps_profile);
            h_rec_per_pair(p) = F.invert_lambda_to_height( ...
                lam_sOnly_m(p), lam_cal, h_profile_new, C.calibration_method);
        end
        h_rec_m    = mean(h_rec_per_pair);
        fill_f_rec = F.fill_fraction_from_height(h_rec_m, R_new, L_new);
        V_rec_L    = fill_f_rec * V_total_new * 1000;
        mass_rec_k = (V_rec_L / 1000) * rho;
        fill_p_rec = fill_f_rec * 100;

        eps_baseline = getEpsBaseline(S.FEM, T_query, rho);
        eps_total    = eps_rec + eps_baseline;
        strain_util  = abs(eps_total) / C.eps_perm_sensor;
        FoS          = C.FoS_required / max(strain_util, C.safety_tiny);
        sigma_Pa     = C.E_beam * abs(eps_rec);
        sigma_MPa    = sigma_Pa / 1e6;

        efHeight.Value    = h_rec_m * 1000;
        efVolume.Value    = V_rec_L;
        efMass.Value      = mass_rec_k;
        efStrain.Value    = eps_rec;
        efStressMPa.Value = sigma_MPa;
        efFoS.Value       = FoS;
        efTempRec.Value   = T_est_C;
        gVol.Value        = max(0, min(100, fill_p_rec));
        gStrain.Value     = max(0, min(15, abs(eps_rec) * 1e6));

        applyStatusLogic(fill_p_rec, mass_rec_k, rho, sigma_MPa, FoS);

        S.computed    = true;
        S.T_ambient_C = T_true_C;
        plotSpectrumForCurrentSensor();
        updateShiftReadout();
    end

    function applyStatusLogic(fill_pct, mass_kg, rho_kgm3, sigma_MPa, FoS)
        payload_limit_kg = 26000;
        issues = {};

        if fill_pct > 97
            issues(end+1,:) = {'bad', sprintf('Overfill (%.1f%%) – no thermal expansion margin.', fill_pct)};
        elseif fill_pct > 90
            issues(end+1,:) = {'warn', sprintf('Near max fill (%.1f%%) – above 90%% operating limit.', fill_pct)};
        end

        if mass_kg > payload_limit_kg
            issues(end+1,:) = {'bad', sprintf('Overweight: %.0f kg exceeds 26,000 kg ISO payload limit.', mass_kg)};
        end

        if rho_kgm3 > 1400
            issues(end+1,:) = {'warn', sprintf('Density %.0f kg/m3 outside FEM validated range (<=1400).', rho_kgm3)};
        end

        if fill_pct >= 20 && fill_pct <= 80
            issues(end+1,:) = {'warn', sprintf('Fill %.1f%% in sloshing range (20-80%%) - ISO 1496-3 advisory.', fill_pct)};
        end

        if FoS < 1.5
            issues(end+1,:) = {'bad', sprintf('Factor of Safety %.2f - sensor strain at or above permissible limit.', FoS)};
        elseif FoS < 2.0
            issues(end+1,:) = {'warn', sprintf('Factor of Safety %.2f - sensor strain above 75%% of permissible limit.', FoS)};
        end

        eps_rec_now = (sigma_MPa * 1e6) / C.E_beam;
        strain_util = abs(eps_rec_now) / C.eps_perm_sensor;
        if strain_util > 0.90
            issues(end+1,:) = {'warn', sprintf('Sensor strain at %.0f%% of permissible limit (%.1f microstrain).', strain_util*100, C.eps_perm_sensor*1e6)};
        end

        if isempty(issues)
            setStatus('ok', 'Tank is ready for transportation.');
        elseif any(strcmp(issues(:,1), 'bad'))
            idx = find(strcmp(issues(:,1), 'bad'), 1);
            setStatus('bad', issues{idx, 2});
        else
            setStatus('warn', issues{1, 2});
        end
    end

% =========================================================================
%  SPECTRUM DISPLAY
% =========================================================================

    function plotSpectrumForCurrentSensor()
        idx  = sensorIndexFromDropdown();
        lam0 = S.lam0_all_nm(idx);
        lamS = S.lam_shifted_nm(idx);

        DSP_PTS  = 1000;
        DSP_SEG  = 50;
        DSP_SPAN = 1.2;

        [lam_u, R_u] = F.simulate_spectrum_tmm(lam0*1e-9, C.n_eff, ...
            C.L_grating, C.dn, DSP_SPAN, DSP_PTS, DSP_SEG, ...
            C.sigma_apod, C.alpha_db_m);

        cla(axSpec); hold(axSpec,'on');
        plot(axSpec, lam_u, R_u, '-', 'LineWidth',1.4, 'Color',[0.45 0.45 0.45], ...
            'DisplayName', sprintf('Unloaded (\\lambda_0 = %.3f nm)', lam0));

        if S.computed
            [lam_l, R_l] = F.simulate_spectrum_tmm(lamS*1e-9, C.n_eff, ...
                C.L_grating, C.dn, DSP_SPAN, DSP_PTS, DSP_SEG, ...
                C.sigma_apod, C.alpha_db_m);
            plot(axSpec, lam_l, R_l, '-', 'LineWidth',1.8, 'Color',[0.10 0.35 0.85], ...
                'DisplayName', sprintf('Loaded (\\lambda = %.3f nm)', lamS));
        end

        hold(axSpec,'off');
        legend(axSpec,'Location','northeast','FontSize',9);
        xlabel(axSpec,'Wavelength (nm)'); ylabel(axSpec,'Reflectivity (P.U.)');
        title(axSpec, sprintf('%s – Reflection Spectrum', ddSensor.Value));
        grid(axSpec,'on');
        xlim(axSpec,[lam0-1 lam0+1]); ylim(axSpec,[0 1.05]);
    end

    function updateShiftReadout()
        idx = sensorIndexFromDropdown();
        efDLam.Value = S.lam_shifted_nm(idx) - S.lam0_all_nm(idx);
    end

    function idx = sensorIndexFromDropdown()
        idx = find(strcmp(ddSensor.Items, ddSensor.Value), 1);
        if isempty(idx), idx = 1; end
    end

% =========================================================================
%  UI HELPERS
% =========================================================================

    function setStatus(kind, msg)
        colours = struct('ok',[0.30 0.75 0.35],'warn',[1.0 0.75 0.20], ...
                         'bad',[0.90 0.30 0.30],'default',[0.7 0.7 0.7]);
        if isfield(colours, kind), lampStatus.Color = colours.(kind);
        else,                      lampStatus.Color = colours.default; end
        lblStatusMsg.Value = msg;
    end

    function showAbout()
        msg = sprintf(['Smart ISO Tank – FBG Sensor Software\n', ...
            'EG5565 MEng Group Design Project\n\n', ...
            'Maths engine: FBG_v7_Functions.m\n', ...
            '  (functions verbatim from Sensor8_FBG_v7.m)\n\n', ...
            '8-sensor array: 4 bonded + 4 temperature sensors\n', ...
            'Bonded:       1531, 1537, 1543, 1549 nm\n', ...
            'Temp sensors: 1534, 1540, 1546, 1552 nm\n\n', ...
            'R = %.3f m | L = %.1f m | V = %.0f L\n', ...
            'p_e = %.4f (derived from p11, p12, nu_f)'], ...
            C.R_tank, C.L_tank, C.V_max_L, C.p_e);
        uialert(fig, msg, 'About', 'Icon','info');
    end

    function showHelp()
        msg = sprintf(['Quick Guide\n\n', ...
            '1. Tick "Default Tank" to use the standard ISO tank.\n', ...
            '2. Choose input type and enter a value.\n', ...
            '3. Set specific gravity for the liquid cargo.\n', ...
            '4. Optionally fix ambient temperature; otherwise a warm-\n', ...
            '   biased random value is drawn per ISO operating range.\n', ...
            '5. Press Calculate.\n', ...
            '6. Use the FBG Sensor dropdown to inspect any of the\n', ...
            '   8 sensors in the Spectral Response panel.\n\n', ...
            'For FEM-backed results, load fem_strain_data.csv via\n', ...
            '"Insert Strain Response" in the New Model panel.']);
        uialert(fig, msg, 'Quick Guide', 'Icon','info');
    end

end % ========================= END Smart_Tank_FBG_GUI ======================


% ==========================================================================
%  FILE-LEVEL HELPERS
% ==========================================================================

function lst = buildSensorList(C)
% Dropdown items for the 8-sensor array.
    lst = cell(1, 8);
    for p = 1:4
        lst{2*p-1} = sprintf('Bonded FBG %d  (design: %d nm)', p, C.lam_bonded_nm(p));
        lst{2*p}   = sprintf('Temp. Sensor %d  (design: %d nm)', p, C.lam_ref_nm(p));
    end
end

function txt = buildSpecTooltip(C)
% Info-icon tooltip: key specs for operator reference.
    lines = { ...
        'TANK GEOMETRY  (Sensor8_FBG_v7)', ...
        sprintf('  R = %.4f m   L = %.1f m   h_max = %.4f m', C.R_tank, C.L_tank, C.h_max), ...
        sprintf('  V_cyl = %.1f L   V_total = %.0f L', C.V_cyl_m3*1000, C.V_max_L), ...
        sprintf('  Max operating fill: %.0f%%', C.max_fill_frac*100), ...
        '', ...
        'MATERIAL  (S355 steel)', ...
        sprintf('  E = %.0f GPa   sigma_y = %.0f MPa', C.E_beam/1e9, C.sigma_yield/1e6), ...
        '', ...
        'FBG ARRAY  (8 sensors, 3 nm spacing)', ...
        sprintf('  Bonded:       %d, %d, %d, %d nm', C.lam_bonded_nm), ...
        sprintf('  Temp sensors: %d, %d, %d, %d nm', C.lam_ref_nm), ...
        sprintf('  L_grating = %.0f mm   dn = %.0e', C.L_grating*1000, C.dn), ...
        '', ...
        'FIBRE CONSTANTS', ...
        sprintf('  n_eff = %.2f   p_e = %.4f (derived)', C.n_eff, C.p_e), ...
        sprintf('  K_T = %.2e /degC   alpha = %.1f dB/m', C.K_T, C.alpha_db_m), ...
        sprintf('  Interrogator res = %.1f pm', C.res_pm), ...
        '', ...
        'ISO OPERATING ENVELOPE (ISO 1496-3)', ...
        sprintf('  T: %+.0f to %+.0f degC', C.T_min_C, C.T_max_C), ...
        '  Fill: 20-90%  (slosh / thermal expansion / op. limit)'};
    txt = strjoin(lines, newline);
end

function v = onoff(tf)
    if tf, v = 'on'; else, v = 'off'; end
end

% --- Baseline lookup helpers (FoS formula: eps_total = eps_mech + eps_baseline) ---

function bl = buildBaselineLookup(csv_path)
% Extract raw FEM strain at 0% fill for each (T, rho) pair.
    raw      = readtable(csv_path, 'VariableNamingRule', 'preserve');
    mask0    = raw.("percentage_%") == 0;
    rows0    = raw(mask0, :);
    bl.temp_grid = unique(rows0.("temperature_C"));
    bl.rho_grid  = unique(rows0.("density_kg_m3"));
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
    bl = FEM.baseline_raw;
    T_c   = min(max(T_query,   min(bl.temp_grid)), max(bl.temp_grid));
    rho_c = min(max(rho_query, min(bl.rho_grid)),  max(bl.rho_grid));
    eps_bl = interp2(bl.rho_grid', bl.temp_grid, bl.baseline_grid, ...
                     rho_c, T_c, 'linear', 0);
end