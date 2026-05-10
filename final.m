clear; clc; close all;

%% Section 1 Settings and constants

femCsvPath = "fem_strain_data.csv";

rho_liquid_kg_m3 = 1400;
T_operating_degC = 40.0;

lambda0_bonded_nm = [1531 1537 1543 1549];
lambda0_ref_nm    = [1534 1540 1546 1552];
nPairs            = numel(lambda0_bonded_nm);
nSensors          = 2 * nPairs;

sensor_location_name = "Upper saddle support";
sensor_labels        = cell(1, nSensors);
for p = 1:nPairs
    sensor_labels{2*p - 1} = sprintf('Pair %d bonded', p);
    sensor_labels{2*p}     = sprintf('Pair %d temperature sensor', p);
end

n_eff = 1.45;
p11   = 0.121;
p12   = 0.270;
nu_f  = 0.17;
p_e   = (n_eff^2 / 2) * (p12 - nu_f * (p11 + p12));

K_T_bonded_per_degC = 8.76e-6;
K_T_ref_per_degC    = 8.76e-6;
alpha_db_per_m      = 0.2;

L_grating_m       = 45e-3;
dn                = 1e-4;
lambda_span_nm    = 2.0;
n_lambda_pts      = 2000;
n_tmm_segments    = 200;
apod_sigma_factor = 0.35;
sigma_apod_m      = apod_sigma_factor * L_grating_m;

resolution_pm = 0.5;
noise_amp_R   = 0.0;

R_tank_m              = 2.1 / 2;
L_tank_m              = 4.8;
h_max_m               = 2 * R_tank_m;
V_cyl_geom_m3         = pi * R_tank_m^2 * L_tank_m;
V_total_tank_m3       = 19.034;
max_fill_frac_operating = 0.90;
V_working_m3          = max_fill_frac_operating * V_total_tank_m3;

E_structure_Pa = 2e11;

yield_stress_Pa      = 275e6;
FoS_required_filling = 1.5;
allowable_stress_Pa  = yield_stress_Pa / FoS_required_filling;

eps_perm_sensor = 6.5e-5;
safety_tiny     = 1e-12;

calibration_method = 'linear';
focus_pair_idx     = 3;

rng(7, 'twister');
c8 = lines(nSensors);

fprintf('Photoelastic parameter p_e = %.4f\n', p_e);
fprintf('Sensor location = %s\n', sensor_location_name);
fprintf('Grating length = %.3f m\n', L_grating_m);
fprintf('Interrogator resolution = %.1f pm\n', resolution_pm);
fprintf('Cylinder geometry volume = %.3f m^3\n', V_cyl_geom_m3);
fprintf('Total tank volume = %.3f m^3\n', V_total_tank_m3);
fprintf('Working tank volume at %.0f %% fill = %.3f m^3\n', ...
    100 * max_fill_frac_operating, V_working_m3);
fprintf('Yield stress used for filling safety = %.1f MPa\n', yield_stress_Pa / 1e6);
fprintf('Required filling FoS = %.2f\n', FoS_required_filling);
fprintf('Allowable filling stress = %.1f MPa\n', allowable_stress_Pa / 1e6);
fprintf('Permissible sensor strain = %.3f microstrain\n', eps_perm_sensor * 1e6);

%% Section 2 FEM data loading and lookup

fem_raw  = readtable(femCsvPath, 'VariableNamingRule', 'preserve');
pct_all  = fem_raw.("percentage_%");
eps_all  = fem_raw.("strain");
temp_all = fem_raw.("temperature_C");
rho_all  = fem_raw.("density_kg_m3");

pct_grid  = unique(pct_all);
temp_grid = unique(temp_all);
rho_grid  = unique(rho_all);

nPct  = numel(pct_grid);
nTemp = numel(temp_grid);
nRho  = numel(rho_grid);

fprintf('\nFEM table: %d rows | %d fill points x %d temperatures x %d densities\n', ...
    height(fem_raw), nPct, nTemp, nRho);

eps_grid = zeros(nPct, nTemp, nRho);
for i = 1:height(fem_raw)
    ip = find(pct_grid  == pct_all(i),  1);
    it = find(temp_grid == temp_all(i), 1);
    ir = find(rho_grid  == rho_all(i),  1);
    eps_grid(ip, it, ir) = eps_all(i);
end

eps_mech_grid = zeros(size(eps_grid));
for it = 1:nTemp
    for ir = 1:nRho
        eps_mech_grid(:, it, ir) = eps_grid(:, it, ir) - eps_grid(1, it, ir);
    end
end

eps_mech_min = min(eps_mech_grid, [], 'all');
eps_mech_max = max(eps_mech_grid, [], 'all');
T_min_degC   = min(temp_grid);
T_max_degC   = max(temp_grid);

T_query_degC    = min(max(T_operating_degC, T_min_degC), T_max_degC);
rho_query_kg_m3 = min(max(rho_liquid_kg_m3, min(rho_grid)), max(rho_grid));

if T_query_degC ~= T_operating_degC
    warning('T_operating_degC clamped to [%.0f, %.0f] degC', T_min_degC, T_max_degC);
end
if rho_query_kg_m3 ~= rho_liquid_kg_m3
    warning('rho_liquid_kg_m3 clamped to [%.0f, %.0f] kg/m^3', min(rho_grid), max(rho_grid));
end

eps_total_at_pct = zeros(nPct, 1);
for i = 1:nPct
    slice_2d = squeeze(eps_grid(i, :, :));
    eps_total_at_pct(i) = interp2(rho_grid', temp_grid, slice_2d, ...
        rho_query_kg_m3, T_query_degC, 'linear');
end

eps_baseline   = eps_total_at_pct(1);
eps_mechanical = eps_total_at_pct - eps_baseline;

eps_total_for_safety = abs(eps_total_at_pct);
strain_utilisation   = eps_total_for_safety ./ eps_perm_sensor;

strain_utilisation_safe = strain_utilisation;
strain_utilisation_safe(strain_utilisation_safe < safety_tiny) = safety_tiny;

FoS_sensor_proxy = FoS_required_filling ./ strain_utilisation_safe;

fill_frac_true = pct_grid(:) / 100;
h_from_pct_m   = zeros(nPct, 1);
for i = 1:nPct
    V_target_geom_m3 = fill_frac_true(i) * V_cyl_geom_m3;
    h_from_pct_m(i) = invertVolToHeight(V_target_geom_m3, R_tank_m, L_tank_m, h_max_m);
end

h_m   = h_from_pct_m;
eps_s = eps_mechanical;
nH    = numel(h_m);
T_vec_degC = ones(nH, 1) * T_query_degC;

fprintf('Operating point: T = %.1f degC, rho = %.1f kg/m^3\n', ...
    T_query_degC, rho_query_kg_m3);
fprintf('Thermal baseline at 0 %% fill = %.3f microstrain\n', eps_baseline * 1e6);
fprintf('Mechanical strain range = %.3f to %.3f microstrain\n', ...
    min(eps_mechanical) * 1e6, max(eps_mechanical) * 1e6);
fprintf('Total sensor strain range = %.3f to %.3f microstrain\n', ...
    min(eps_total_at_pct) * 1e6, max(eps_total_at_pct) * 1e6);
fprintf('Maximum strain utilisation = %.3f\n', max(strain_utilisation));
fprintf('Minimum sensor based FoS estimate = %.3f\n', min(FoS_sensor_proxy));

%% Section 3 True Bragg wavelengths for the full sweep

lam_true_bonded_m = zeros(nH, nPairs);
lam_true_ref_m    = zeros(nH, nPairs);

for p = 1:nPairs
    l0b_m = lambda0_bonded_nm(p) * 1e-9;
    l0r_m = lambda0_ref_nm(p) * 1e-9;
    lam_true_bonded_m(:, p) = l0b_m .* (1 + (1 - p_e) .* eps_s + K_T_bonded_per_degC .* T_vec_degC);
    lam_true_ref_m(:, p)    = l0r_m .* (1 + K_T_ref_per_degC .* T_vec_degC);
end

%% Section 4 Interrogator peak detection for the full sweep

fprintf('\nRunning interrogator over full sweep...\n');

lam_meas_bonded_m = zeros(nH, nPairs);
lam_meas_ref_m    = zeros(nH, nPairs);

for p = 1:nPairs
    for hi = 1:nH
        [lam_nm, R] = simulate_spectrum_tmm(lam_true_bonded_m(hi, p), n_eff, ...
            L_grating_m, dn, lambda_span_nm, n_lambda_pts, n_tmm_segments, ...
            sigma_apod_m, alpha_db_per_m);
        lam_meas_bonded_m(hi, p) = detect_peak_quadratic(lam_nm, R, noise_amp_R, resolution_pm);

        [lam_nm, R] = simulate_spectrum_tmm(lam_true_ref_m(hi, p), n_eff, ...
            L_grating_m, dn, lambda_span_nm, n_lambda_pts, n_tmm_segments, ...
            sigma_apod_m, alpha_db_per_m);
        lam_meas_ref_m(hi, p) = detect_peak_quadratic(lam_nm, R, noise_amp_R, resolution_pm);
    end
end

fprintf('Interrogator complete.\n');

%% Section 5 Temperature decoupling for the full sweep

dT_est_degC       = zeros(nH, nPairs);
eps_est           = zeros(nH, nPairs);
lam_strain_only_m = zeros(nH, nPairs);

for p = 1:nPairs
    l0r_m = lambda0_ref_nm(p) * 1e-9;
    l0b_m = lambda0_bonded_nm(p) * 1e-9;

    dT_est_degC(:, p) = (lam_meas_ref_m(:, p) ./ l0r_m - 1) ./ K_T_ref_per_degC;
    dLam_thermal_m    = l0b_m .* K_T_bonded_per_degC .* dT_est_degC(:, p);
    dLam_strain_m     = (lam_meas_bonded_m(:, p) - l0b_m) - dLam_thermal_m;

    eps_est(:, p)           = dLam_strain_m ./ (l0b_m * (1 - p_e));
    lam_strain_only_m(:, p) = l0b_m .* (1 + (1 - p_e) .* eps_est(:, p));
end

%% Section 6 Height fill volume and mass recovery for the full sweep

h_est_per_pair_m = zeros(nH, nPairs);
for p = 1:nPairs
    l0b_m   = lambda0_bonded_nm(p) * 1e-9;
    lam_cal = l0b_m .* (1 + (1 - p_e) .* eps_s);
    h_est_per_pair_m(:, p) = invert_lambda_to_height( ...
        lam_strain_only_m(:, p), lam_cal, h_m, calibration_method);
end

h_est_m = mean(h_est_per_pair_m, 2);
h_err_mm = (h_est_m - h_m) * 1e3;
h_err_per_pair_mm = (h_est_per_pair_m - repmat(h_m, 1, nPairs)) * 1e3;

fill_frac_est = arrayfun(@(h_val) fill_fraction_from_height(h_val, R_tank_m, L_tank_m), h_est_m);
fill_frac_est = min(max(fill_frac_est, 0), 1);

fill_pct_true = fill_frac_true * 100;
fill_pct_est  = fill_frac_est * 100;

vol_true_m3 = fill_frac_true * V_total_tank_m3;
vol_est_m3  = fill_frac_est * V_total_tank_m3;

mass_true_kg = vol_true_m3 * rho_query_kg_m3;
mass_est_kg  = vol_est_m3 * rho_query_kg_m3;

vol_err_m3  = vol_est_m3 - vol_true_m3;
mass_err_kg = mass_est_kg - mass_true_kg;

%% Section 7 Fixed grating metrics

focus_lambda_design_m = lambda0_bonded_nm(focus_pair_idx) * 1e-9;
[lam_fixed_nm, R_fixed] = simulate_spectrum_tmm(focus_lambda_design_m, n_eff, ...
    L_grating_m, dn, lambda_span_nm, n_lambda_pts, n_tmm_segments, ...
    sigma_apod_m, alpha_db_per_m);
[R_peak_fixed, fwhm_nm_fixed, lam_peak_fixed_nm, lam_left_fixed_nm, lam_right_fixed_nm] = ...
    spectrum_metrics(lam_fixed_nm, R_fixed);

%% Section 8 Random operating point simulation

fprintf('\n========= RANDOM OPERATING POINT =========\n');

min_fill_frac = 0.70;
rand_fill_frac = min_fill_frac + (max_fill_frac_operating - min_fill_frac) * rand();
rand_T_degC    = T_min_degC + (T_max_degC - T_min_degC) * rand();

rand_fill_pct = 100 * rand_fill_frac;
rand_vol_m3   = rand_fill_frac * V_total_tank_m3;
rand_mass_kg  = rand_vol_m3 * rho_query_kg_m3;

rand_geom_vol_m3 = rand_fill_frac * V_cyl_geom_m3;
rand_h_true_m = invertVolToHeight(rand_geom_vol_m3, R_tank_m, L_tank_m, h_max_m);

rand_T_query_degC = min(max(rand_T_degC, T_min_degC), T_max_degC);

fprintf('Random conditions generated:\n');
fprintf('  Temperature = %.2f degC\n', rand_T_degC);
fprintf('  Fill level = %.2f %%\n', rand_fill_pct);
fprintf('  True mass = %.3f kg\n', rand_mass_kg);
fprintf('  True height = %.4f m\n', rand_h_true_m);
fprintf('  True volume = %.4f m^3\n', rand_vol_m3);

eps_total_rand_vs_pct = zeros(nPct, 1);
for i = 1:nPct
    slice_2d = squeeze(eps_grid(i, :, :));
    eps_total_rand_vs_pct(i) = interp2(rho_grid', temp_grid, slice_2d, ...
        rho_query_kg_m3, rand_T_query_degC, 'linear');
end

eps_baseline_rand = eps_total_rand_vs_pct(1);
eps_mech_rand     = eps_total_rand_vs_pct - eps_baseline_rand;

rand_eps_true = interp1(pct_grid(:), eps_mech_rand, rand_fill_pct, 'linear');

fprintf('  True strain = %.4f microstrain\n', rand_eps_true * 1e6);

lam_rand_bonded_m = zeros(1, nPairs);
lam_rand_ref_m    = zeros(1, nPairs);

for p = 1:nPairs
    l0b_m = lambda0_bonded_nm(p) * 1e-9;
    l0r_m = lambda0_ref_nm(p) * 1e-9;
    lam_rand_bonded_m(p) = l0b_m * (1 + (1 - p_e) * rand_eps_true + K_T_bonded_per_degC * rand_T_degC);
    lam_rand_ref_m(p)    = l0r_m * (1 + K_T_ref_per_degC * rand_T_degC);
end

lam_meas_rand_bonded_m = zeros(1, nPairs);
lam_meas_rand_ref_m    = zeros(1, nPairs);

for p = 1:nPairs
    [lam_nm, R] = simulate_spectrum_tmm(lam_rand_bonded_m(p), n_eff, ...
        L_grating_m, dn, lambda_span_nm, n_lambda_pts, n_tmm_segments, ...
        sigma_apod_m, alpha_db_per_m);
    lam_meas_rand_bonded_m(p) = detect_peak_quadratic(lam_nm, R, noise_amp_R, resolution_pm);

    [lam_nm, R] = simulate_spectrum_tmm(lam_rand_ref_m(p), n_eff, ...
        L_grating_m, dn, lambda_span_nm, n_lambda_pts, n_tmm_segments, ...
        sigma_apod_m, alpha_db_per_m);
    lam_meas_rand_ref_m(p) = detect_peak_quadratic(lam_nm, R, noise_amp_R, resolution_pm);
end

eps_rec_rand      = zeros(1, nPairs);
dT_rec_rand_degC  = zeros(1, nPairs);
lam_sOnly_rand_m  = zeros(1, nPairs);

for p = 1:nPairs
    l0r_m = lambda0_ref_nm(p) * 1e-9;
    l0b_m = lambda0_bonded_nm(p) * 1e-9;

    dT_rec_rand_degC(p) = (lam_meas_rand_ref_m(p) / l0r_m - 1) / K_T_ref_per_degC;
    dLam_thermal_m      = l0b_m * K_T_bonded_per_degC * dT_rec_rand_degC(p);
    dLam_strain_m       = (lam_meas_rand_bonded_m(p) - l0b_m) - dLam_thermal_m;

    eps_rec_rand(p)     = dLam_strain_m / (l0b_m * (1 - p_e));
    lam_sOnly_rand_m(p) = l0b_m * (1 + (1 - p_e) * eps_rec_rand(p));
end

eps_rec_avg = mean(eps_rec_rand);

eps_total_true_rand = rand_eps_true + eps_baseline_rand;
eps_total_rec_rand  = eps_rec_avg + eps_baseline_rand;

strain_utilisation_true_rand = abs(eps_total_true_rand) / eps_perm_sensor;
strain_utilisation_rand      = abs(eps_total_rec_rand) / eps_perm_sensor;

strain_utilisation_true_safe = max(strain_utilisation_true_rand, safety_tiny);
strain_utilisation_rand_safe = max(strain_utilisation_rand, safety_tiny);

FoS_sensor_proxy_true_rand = FoS_required_filling / strain_utilisation_true_safe;
FoS_sensor_proxy_rand      = FoS_required_filling / strain_utilisation_rand_safe;

lam_cal_rand_m = zeros(nPct, nPairs);
for p = 1:nPairs
    l0b_m = lambda0_bonded_nm(p) * 1e-9;
    lam_cal_rand_m(:, p) = l0b_m .* (1 + (1 - p_e) .* eps_mech_rand);
end

h_rec_rand_per_pair_m = zeros(1, nPairs);
for p = 1:nPairs
    h_rec_rand_per_pair_m(p) = invert_lambda_to_height( ...
        lam_sOnly_rand_m(p), lam_cal_rand_m(:, p), h_m, calibration_method);
end
h_rec_rand_m = mean(h_rec_rand_per_pair_m);

fill_rec_rand = fill_fraction_from_height(h_rec_rand_m, R_tank_m, L_tank_m);
vol_rec_rand_m3 = fill_rec_rand * V_total_tank_m3;
mass_rec_rand_kg = vol_rec_rand_m3 * rho_query_kg_m3;
fill_rec_rand_pct = fill_rec_rand * 100;

R0_rand = zeros(1, nSensors);
Rdef_rand = zeros(1, nSensors);
FWHM_rand_nm = zeros(1, nSensors);
cwl_all_nm = zeros(1, nSensors);

sensor_idx = 1;
for p = 1:nPairs
    l0b_m = lambda0_bonded_nm(p) * 1e-9;
    [lam_u_nm, R_u] = simulate_spectrum_tmm(l0b_m, n_eff, L_grating_m, dn, ...
        lambda_span_nm, n_lambda_pts, n_tmm_segments, sigma_apod_m, alpha_db_per_m);
    [~, fwhm_u_nm] = spectrum_metrics(lam_u_nm, R_u);
    [~, R_d] = simulate_spectrum_tmm(lam_rand_bonded_m(p), n_eff, L_grating_m, dn, ...
        lambda_span_nm, n_lambda_pts, n_tmm_segments, sigma_apod_m, alpha_db_per_m);

    R0_rand(sensor_idx) = max(R_u);
    Rdef_rand(sensor_idx) = max(R_d);
    FWHM_rand_nm(sensor_idx) = fwhm_u_nm;
    cwl_all_nm(sensor_idx) = lambda0_bonded_nm(p);
    sensor_idx = sensor_idx + 1;

    l0r_m = lambda0_ref_nm(p) * 1e-9;
    [lam_u_nm, R_u] = simulate_spectrum_tmm(l0r_m, n_eff, L_grating_m, dn, ...
        lambda_span_nm, n_lambda_pts, n_tmm_segments, sigma_apod_m, alpha_db_per_m);
    [~, fwhm_u_nm] = spectrum_metrics(lam_u_nm, R_u);
    [~, R_d] = simulate_spectrum_tmm(lam_rand_ref_m(p), n_eff, L_grating_m, dn, ...
        lambda_span_nm, n_lambda_pts, n_tmm_segments, sigma_apod_m, alpha_db_per_m);

    R0_rand(sensor_idx) = max(R_u);
    Rdef_rand(sensor_idx) = max(R_d);
    FWHM_rand_nm(sensor_idx) = fwhm_u_nm;
    cwl_all_nm(sensor_idx) = lambda0_ref_nm(p);
    sensor_idx = sensor_idx + 1;
end

%% Section 9 Validation metrics

rms_lambda_bonded_pm = zeros(1, nPairs);
rms_lambda_ref_pm    = zeros(1, nPairs);
for p = 1:nPairs
    rms_lambda_bonded_pm(p) = rms(lam_meas_bonded_m(:, p) - lam_true_bonded_m(:, p)) * 1e12;
    rms_lambda_ref_pm(p)    = rms(lam_meas_ref_m(:, p) - lam_true_ref_m(:, p)) * 1e12;
end

fprintf('\n============= FULL SWEEP VALIDATION =============\n');
fprintf('%-10s %12s %12s %14s %14s %14s\n', ...
    'Pair', 'dLam B (pm)', 'dLam R (pm)', 'Strain (mu e)', 'dT (degC)', 'Height (mm)');
fprintf('%s\n', repmat('-', 1, 88));
for p = 1:nPairs
    fprintf('Pair %-5d %12.4f %12.4f %14.4f %14.4f %14.4f\n', p, ...
        rms_lambda_bonded_pm(p), rms_lambda_ref_pm(p), ...
        rms(eps_est(:, p) - eps_s) * 1e6, ...
        rms(dT_est_degC(:, p) - T_vec_degC), ...
        rms(h_err_per_pair_mm(:, p)));
end
fprintf('%s\n', repmat('-', 1, 88));
fprintf('Fused height RMS error = %.4f mm\n', rms(h_err_mm));
fprintf('Maximum height error = %.4f mm\n', max(abs(h_err_mm)));
fprintf('Fill RMS error = %.4f %%\n', rms(fill_pct_est - fill_pct_true));
fprintf('Volume RMS error = %.6f m^3\n', rms(vol_err_m3));
fprintf('Mass RMS error = %.3f kg\n', rms(mass_err_kg));
fprintf('Minimum sensor based FoS estimate = %.3f\n', min(FoS_sensor_proxy));
fprintf('Maximum strain utilisation = %.3f\n', max(strain_utilisation));
fprintf('Permissible sensor strain = %.3f microstrain\n', eps_perm_sensor * 1e6);
fprintf('Selected grating metrics: L = %.3f m, FWHM = %.4f nm, R_peak = %.4f\n', ...
    L_grating_m, fwhm_nm_fixed, R_peak_fixed);
fprintf('Bonded CWLs = %d %d %d %d nm\n', lambda0_bonded_nm);
fprintf('Reference CWLs = %d %d %d %d nm\n', lambda0_ref_nm);
fprintf('p_e = %.4f\n', p_e);
fprintf('=================================================\n');

fprintf('\n============= RANDOM OPERATING POINT SUMMARY =============\n');
fprintf('Liquid density = %.1f kg/m^3\n', rho_query_kg_m3);
fprintf('Temperature = %.2f degC  recovered = %.2f degC\n', ...
    rand_T_degC, mean(dT_rec_rand_degC));
fprintf('%s\n', repmat('-', 1, 66));
fprintf('%-20s %12s %12s %12s\n', 'Quantity', 'True', 'Recovered', 'Error');
fprintf('%s\n', repmat('-', 1, 66));
fprintf('%-20s %12.4f %12.4f %12.4f\n', 'Mechanical strain (mu e)', ...
    rand_eps_true * 1e6, eps_rec_avg * 1e6, (eps_rec_avg - rand_eps_true) * 1e6);
fprintf('%-20s %12.4f %12.4f %12.4f\n', 'Total strain (mu e)', ...
    eps_total_true_rand * 1e6, eps_total_rec_rand * 1e6, ...
    (eps_total_rec_rand - eps_total_true_rand) * 1e6);
fprintf('%-20s %12.4f %12.4f %12.4f\n', 'Strain utilisation', ...
    strain_utilisation_true_rand, strain_utilisation_rand, ...
    strain_utilisation_rand - strain_utilisation_true_rand);
fprintf('%-20s %12.4f %12.4f %12.4f\n', 'FoS estimate', ...
    FoS_sensor_proxy_true_rand, FoS_sensor_proxy_rand, ...
    FoS_sensor_proxy_rand - FoS_sensor_proxy_true_rand);
fprintf('%-20s %12.4f %12.4f %12.4f\n', 'Height (m)', ...
    rand_h_true_m, h_rec_rand_m, h_rec_rand_m - rand_h_true_m);
fprintf('%-20s %12.2f %12.2f %12.2f\n', 'Fill (%)', ...
    rand_fill_pct, fill_rec_rand_pct, fill_rec_rand_pct - rand_fill_pct);
fprintf('%-20s %12.4f %12.4f %12.4f\n', 'Volume (m^3)', ...
    rand_vol_m3, vol_rec_rand_m3, vol_rec_rand_m3 - rand_vol_m3);
fprintf('%-20s %12.3f %12.3f %12.3f\n', 'Mass (kg)', ...
    rand_mass_kg, mass_rec_rand_kg, mass_rec_rand_kg - rand_mass_kg);
fprintf('%s\n', repmat('-', 1, 66));

fprintf('\nPer sensor summary:\n');
fprintf('%-18s %10s %10s %10s %12s %14s %14s\n', ...
    'Sensor', 'CWL (nm)', 'R0', 'Rdef', 'FWHM (nm)', 'eps in (mu e)', 'eps rec (mu e)');
fprintf('%s\n', repmat('-', 1, 102));
for s = 1:nSensors
    p = ceil(s / 2);
    is_bonded = mod(s, 2) == 1;
    if is_bonded
        eps_in_mu = rand_eps_true * 1e6;
        eps_rec_mu = eps_rec_rand(p) * 1e6;
    else
        eps_in_mu = 0;
        eps_rec_mu = 0;
    end
    fprintf('%-18s %10.0f %10.4f %10.4f %12.4f %14.4f %14.4f\n', ...
        sensor_labels{s}, cwl_all_nm(s), R0_rand(s), Rdef_rand(s), ...
        FWHM_rand_nm(s), eps_in_mu, eps_rec_mu);
end
fprintf('%s\n', repmat('-', 1, 102));
fprintf('===========================================================\n\n');

%% Section 10 Wavelength allocation data

lambda_nominal_all_nm = zeros(1, nSensors);
lambda_low_env_nm     = zeros(1, nSensors);
lambda_high_env_nm    = zeros(1, nSensors);
fwhm_nominal_nm       = zeros(1, nSensors);

sensor_idx = 1;
for p = 1:nPairs
    l0b_m = lambda0_bonded_nm(p) * 1e-9;
    candidate_bonded_nm = zeros(4, 1);
    candidate_idx = 1;
    for eps_candidate = [eps_mech_min, eps_mech_max]
        for T_candidate = [T_min_degC, T_max_degC]
            candidate_bonded_nm(candidate_idx) = ...
                l0b_m * (1 + (1 - p_e) * eps_candidate + K_T_bonded_per_degC * T_candidate) * 1e9;
            candidate_idx = candidate_idx + 1;
        end
    end
    [lam_nom_nm, R_nom] = simulate_spectrum_tmm(l0b_m, n_eff, L_grating_m, dn, ...
        lambda_span_nm, n_lambda_pts, n_tmm_segments, sigma_apod_m, alpha_db_per_m);
    [~, fwhm_nominal_nm(sensor_idx)] = spectrum_metrics(lam_nom_nm, R_nom);
    lambda_nominal_all_nm(sensor_idx) = lambda0_bonded_nm(p);
    lambda_low_env_nm(sensor_idx)  = min(candidate_bonded_nm);
    lambda_high_env_nm(sensor_idx) = max(candidate_bonded_nm);
    sensor_idx = sensor_idx + 1;

    l0r_m = lambda0_ref_nm(p) * 1e-9;
    candidate_ref_nm = l0r_m * (1 + K_T_ref_per_degC * [T_min_degC, T_max_degC]) * 1e9;
    [lam_nom_nm, R_nom] = simulate_spectrum_tmm(l0r_m, n_eff, L_grating_m, dn, ...
        lambda_span_nm, n_lambda_pts, n_tmm_segments, sigma_apod_m, alpha_db_per_m);
    [~, fwhm_nominal_nm(sensor_idx)] = spectrum_metrics(lam_nom_nm, R_nom);
    lambda_nominal_all_nm(sensor_idx) = lambda0_ref_nm(p);
    lambda_low_env_nm(sensor_idx)  = min(candidate_ref_nm);
    lambda_high_env_nm(sensor_idx) = max(candidate_ref_nm);
    sensor_idx = sensor_idx + 1;
end

[lambda_nominal_sorted_nm, sort_idx] = sort(lambda_nominal_all_nm);
lambda_low_sorted_nm  = lambda_low_env_nm(sort_idx);
lambda_high_sorted_nm = lambda_high_env_nm(sort_idx);
adjacent_margin_nm    = lambda_low_sorted_nm(2:end) - lambda_high_sorted_nm(1:end-1);
min_adjacent_margin_nm = min(adjacent_margin_nm);

%% Section 11 Figures

figure('Color', 'w', 'Name', 'Fig 1: Strain to wavelength response'); hold on;
for p = 1:nPairs
    dLam_pm = (lam_true_bonded_m(:, p) - lam_true_bonded_m(1, p)) * 1e12;
    plot(eps_s * 1e6, dLam_pm, '-', 'LineWidth', 2.2, 'Color', c8(2*p - 1, :), ...
        'DisplayName', sprintf('Sensor pair %d bonded %.0f nm', p, lambda0_bonded_nm(p)));
end
grid on;
xlabel('Mechanical strain (microstrain)');
ylabel('Bragg wavelength shift (pm)');
title(sprintf('FBG strain to wavelength response at %s', sensor_location_name));
legend('Location', 'northwest', 'FontSize', 9);
sens_pm_per_mu = (1 - p_e) * mean(lambda0_bonded_nm) * 1e-3;
text(0.05, 0.90, sprintf('Sensitivity approx %.2f pm per microstrain', sens_pm_per_mu), ...
    'Units', 'normalized', 'FontSize', 10);
set(gca, 'FontSize', 11);

figure('Color', 'w', 'Name', 'Fig 2: Mechanical strain versus liquid height');
yyaxis left;
plot(h_m, eps_s * 1e6, '-o', 'LineWidth', 2.3, 'MarkerSize', 5);
ylabel('Mechanical strain (microstrain)');
yyaxis right;
plot(h_m, fill_pct_true, '--', 'LineWidth', 1.8);
ylabel('Fill level (%)');
xlabel('Liquid height (m)');
title(sprintf('Mechanical strain at %s versus liquid height', sensor_location_name));
grid on;
legend('Strain', 'Fill level', 'Location', 'northwest');
set(gca, 'FontSize', 11);

figure('Color', 'w', 'Name', 'Fig 3: Effect of liquid density'); hold on;
for k = 1:nRho
    rho_k = rho_grid(k);
    eps_k = zeros(nPct, 1);
    for i = 1:nPct
        slice_2d = squeeze(eps_grid(i, :, :));
        eps_k(i) = interp2(rho_grid', temp_grid, slice_2d, rho_k, T_query_degC, 'linear');
    end
    eps_k = eps_k - eps_k(1);
    plot(h_m, eps_k * 1e6, '-o', 'LineWidth', 2, 'MarkerSize', 5, ...
        'DisplayName', sprintf('rho = %.0f kg per m^3', rho_k));
end
grid on;
xlabel('Liquid height (m)');
ylabel('Mechanical strain (microstrain)');
title(sprintf('Effect of liquid density on mechanical strain at %s', sensor_location_name));
legend('Location', 'northwest', 'FontSize', 9);
set(gca, 'FontSize', 11);

figure('Color', 'w', 'Name', 'Fig 4: All sensor wavelength shifts'); hold on;
for p = 1:nPairs
    dLam_bonded_pm = (lam_true_bonded_m(:, p) - lam_true_bonded_m(1, p)) * 1e12;
    dLam_ref_pm    = (lam_true_ref_m(:, p) - lam_true_ref_m(1, p)) * 1e12;
    plot(h_m, dLam_bonded_pm, '-', 'LineWidth', 2.0, 'Color', c8(2*p - 1, :), ...
        'DisplayName', sprintf('Pair %d bonded %.0f nm', p, lambda0_bonded_nm(p)));
    plot(h_m, dLam_ref_pm, '--', 'LineWidth', 1.5, 'Color', c8(2*p, :), ...
        'DisplayName', sprintf('Pair %d reference %.0f nm', p, lambda0_ref_nm(p)));
end
grid on;
xlabel('Liquid height (m)');
ylabel('Wavelength shift (pm)');
title('All bonded and reference sensor wavelength shifts');
legend('Location', 'eastoutside', 'FontSize', 8);
set(gca, 'FontSize', 11);



figure('Color', 'w', 'Name', 'Fig 5: Temperature compensation');
l0b_fig5_m   = lambda0_bonded_nm(focus_pair_idx) * 1e-9;
dLam_raw5_pm = (lam_true_bonded_m(:, focus_pair_idx) - l0b_fig5_m) * 1e12;
lam_strain_fig5_m = l0b_fig5_m .* (1 + (1 - p_e) .* eps_s);
dLam_clean5_pm = (lam_strain_fig5_m - l0b_fig5_m) * 1e12;
fill([h_m; flipud(h_m)], [dLam_raw5_pm; flipud(dLam_clean5_pm)], ...
    [1 0.85 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.5, 'DisplayName', 'Thermal offset');
hold on;
plot(h_m, dLam_raw5_pm, 'r-', 'LineWidth', 2.0, 'DisplayName', 'Bonded response');
plot(h_m, dLam_clean5_pm, 'b--', 'LineWidth', 2.5, 'DisplayName', 'Temperature compensated');
grid on;
xlabel('Liquid height (m)');
ylabel('Wavelength shift (pm)');
title(sprintf('Temperature compensation for sensor pair %d at %s', ...
    focus_pair_idx, sensor_location_name));
legend('Location', 'northwest', 'FontSize', 9);
set(gca, 'FontSize', 11);

figure('Color', 'w', 'Name', 'Fig 6: Strain recovery'); hold on;
for p = 1:nPairs
    plot(h_m, eps_est(:, p) * 1e6, 'o-', 'LineWidth', 1.4, 'MarkerSize', 4, ...
        'Color', c8(2*p - 1, :), 'DisplayName', sprintf('Sensor pair %d recovered', p));
end
plot(h_m, eps_s * 1e6, 'k--', 'LineWidth', 2.3, 'DisplayName', 'True strain');
grid on;
xlabel('Liquid height (m)');
ylabel('Strain (microstrain)');
title(sprintf('Recovered strain at %s', sensor_location_name));
legend('Location', 'northwest', 'FontSize', 9);
set(gca, 'FontSize', 11);


lB_test_m = lam_true_bonded_m(end, focus_pair_idx);
[lam_u_nm, R_u] = simulate_spectrum_cmt(lB_test_m, n_eff, L_grating_m, dn, lambda_span_nm, n_lambda_pts);
[lam_a_nm, R_a] = simulate_spectrum_tmm(lB_test_m, n_eff, L_grating_m, dn, lambda_span_nm, ...
    n_lambda_pts, n_tmm_segments, sigma_apod_m, alpha_db_per_m);


figure('Color', 'w', 'Name', 'Fig 7: Apodisation comparison');
subplot(1, 2, 1);
plot(lam_u_nm, R_u, '-', 'LineWidth', 2.0, 'Color', [0.8 0.2 0.2]);
grid on;
xlabel('Wavelength (nm)');
ylabel('Reflectivity');
title(sprintf('Uniform grating  Rmax = %.2f %%', max(R_u) * 100));
set(gca, 'FontSize', 10);

subplot(1, 2, 2);
plot(lam_a_nm, R_a, '-', 'LineWidth', 2.2, 'Color', [0.2 0.4 0.8]);
grid on;
xlabel('Wavelength (nm)');
ylabel('Reflectivity');
title(sprintf('Gaussian apodised grating  Rmax = %.2f %%', max(R_a) * 100));
set(gca, 'FontSize', 10);

figure('Color', 'w', 'Name', 'Fig 8: Fixed grating spectrum');
lam_rel_pm = (lam_fixed_nm - lambda0_bonded_nm(focus_pair_idx)) * 1000;
plot(lam_rel_pm, R_fixed, '-', 'LineWidth', 2.2, 'Color', [0.2 0.4 0.8]);
grid on;
xlabel('Relative wavelength (pm)');
ylabel('Reflectivity');
title(sprintf('Fixed grating spectrum  L = %.3f m  FWHM = %.4f nm  Rmax = %.2f %%', ...
    L_grating_m, fwhm_nm_fixed, R_peak_fixed * 100));
set(gca, 'FontSize', 11);

figure('Color', 'w', 'Name', 'Fig 9: Annotated 45 mm apodised spectrum');
plot(lam_fixed_nm, R_fixed, '-', 'LineWidth', 2.2, 'Color', [0.2 0.4 0.8]); hold on;
plot(lam_peak_fixed_nm, R_peak_fixed, 'o', 'MarkerSize', 7, 'MarkerFaceColor', [0.85 0.2 0.2], ...
    'MarkerEdgeColor', 'k', 'DisplayName', 'Peak reflectivity');
yline(R_peak_fixed / 2, '--k', 'LineWidth', 1.2, 'DisplayName', 'Half maximum');
xline(lam_left_fixed_nm, '--', 'LineWidth', 1.1, 'Color', [0.3 0.3 0.3], 'DisplayName', 'FWHM limits');
xline(lam_right_fixed_nm, '--', 'LineWidth', 1.1, 'Color', [0.3 0.3 0.3], 'HandleVisibility', 'off');
xline(lam_peak_fixed_nm, ':', 'LineWidth', 1.2, 'Color', [0.85 0.2 0.2], 'DisplayName', 'Peak wavelength');
plot([lam_left_fixed_nm lam_right_fixed_nm], [R_peak_fixed / 2 R_peak_fixed / 2], ...
    'k-', 'LineWidth', 2.0, 'HandleVisibility', 'off');
text(0.05, 0.82, sprintf(['Selected grating design\n' ...
    'Length = %.3f m\n' ...
    'Peak wavelength = %.4f nm\n' ...
    'Rmax = %.2f %%\n' ...
    'FWHM = %.4f nm'], ...
    L_grating_m, lam_peak_fixed_nm, R_peak_fixed * 100, fwhm_nm_fixed), ...
    'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'w');
grid on;
xlabel('Wavelength (nm)');
ylabel('Reflectivity');
title('Annotated 45 mm Gaussian apodised FBG spectrum');
legend('Location', 'best', 'FontSize', 9);
set(gca, 'FontSize', 11);

figure('Color', 'w', 'Name', 'Fig 10: Wavelength allocation and spacing'); hold on;
for s = 1:nSensors
    y_pos = s;
    x_patch = [lambda_low_env_nm(s) lambda_high_env_nm(s) lambda_high_env_nm(s) lambda_low_env_nm(s)];
    y_patch = [y_pos - 0.28 y_pos - 0.28 y_pos + 0.28 y_pos + 0.28];
    patch(x_patch, y_patch, c8(s, :), 'FaceAlpha', 0.20, 'EdgeColor', c8(s, :), 'LineWidth', 1.5);
    plot(lambda_nominal_all_nm(s), y_pos, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5);
    plot([lambda_nominal_all_nm(s) - 0.5 * fwhm_nominal_nm(s), ...
          lambda_nominal_all_nm(s) + 0.5 * fwhm_nominal_nm(s)], ...
         [y_pos y_pos], 'k-', 'LineWidth', 2.2);
end
grid on;
xlabel('Wavelength (nm)');
ylabel('Sensor channel');
yticks(1:nSensors);
yticklabels(sensor_labels);
xlim([min(lambda_low_env_nm) - 1.0, max(lambda_high_env_nm) + 1.0]);
ylim([0.5, nSensors + 0.5]);
title(sprintf(['Multiplexed FBG wavelength allocation at %s\n' ...
    'Minimum envelope margin = %.3f nm'], ...
    sensor_location_name, min_adjacent_margin_nm));
text(0.03, 0.92, sprintf('Intra pair spacing = 3 nm\nInter pair spacing = 6 nm'), ...
    'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'w');
set(gca, 'FontSize', 11);

figure('Color', 'w', 'Name', 'Fig 11: Spectral migration'); hold on;
for p = 1:nPairs
    [lam_nm, R] = simulate_spectrum_tmm(lambda0_bonded_nm(p) * 1e-9, n_eff, L_grating_m, dn, ...
        lambda_span_nm, 500, n_tmm_segments, sigma_apod_m, alpha_db_per_m);
    plot(lam_nm, R, ':', 'Color', [0.75 0.75 0.75], 'LineWidth', 1, 'HandleVisibility', 'off');

    [lam_nm, R] = simulate_spectrum_tmm(lambda0_ref_nm(p) * 1e-9, n_eff, L_grating_m, dn, ...
        lambda_span_nm, 500, n_tmm_segments, sigma_apod_m, alpha_db_per_m);
    plot(lam_nm, R, ':', 'Color', [0.75 0.75 0.75], 'LineWidth', 1, 'HandleVisibility', 'off');
end
for p = 1:nPairs
    [lam_b_nm, R_b] = simulate_spectrum_tmm(lam_true_bonded_m(end, p), n_eff, L_grating_m, dn, ...
        lambda_span_nm, 500, n_tmm_segments, sigma_apod_m, alpha_db_per_m);
    [lam_r_nm, R_r] = simulate_spectrum_tmm(lam_true_ref_m(end, p), n_eff, L_grating_m, dn, ...
        lambda_span_nm, 500, n_tmm_segments, sigma_apod_m, alpha_db_per_m);
    plot(lam_b_nm, R_b, '-', 'LineWidth', 2.0, 'Color', c8(2*p - 1, :), ...
        'DisplayName', sprintf('Pair %d bonded', p));
    plot(lam_r_nm, R_r, '--', 'LineWidth', 1.5, 'Color', c8(2*p, :), ...
        'DisplayName', sprintf('Pair %d reference', p));
end
grid on;
xlabel('Wavelength (nm)');
ylabel('Reflectivity');
title('Spectral migration from nominal state to full fill state');
legend('Location', 'eastoutside', 'FontSize', 8);
xlim([1529 1556]);
set(gca, 'FontSize', 11);

figure('Color', 'w', 'Name', 'Fig 12: Peak tracking'); hold on;
idx_states = [1, round(nH / 2), nH];
state_labels = {'Empty', 'Mid fill', 'Full fill'};
state_colours = {[0.2 0.4 0.8], [0.9 0.6 0], [0.8 0.15 0.15]};
for k = 1:3
    lB_state_m = lam_true_bonded_m(idx_states(k), focus_pair_idx);
    [lam_nm, R] = simulate_spectrum_tmm(lB_state_m, n_eff, L_grating_m, dn, ...
        lambda_span_nm, n_lambda_pts, n_tmm_segments, sigma_apod_m, alpha_db_per_m);
    plot(lam_nm, R, 'LineWidth', 2.3, 'Color', state_colours{k}, ...
        'DisplayName', sprintf('%s  h = %.2f m  lambdaB = %.3f nm', ...
        state_labels{k}, h_m(idx_states(k)), lB_state_m * 1e9));
end
grid on;
xlabel('Wavelength (nm)');
ylabel('Reflectivity');
title(sprintf('Peak tracking for sensor pair %d', focus_pair_idx));
legend('Location', 'best', 'FontSize', 9);
set(gca, 'FontSize', 11);

figure('Color', 'w', 'Name', 'Fig 13: Height estimation accuracy');
subplot(2, 2, [1 2]);
plot(h_m, h_est_m, 'o', 'MarkerSize', 6, 'LineWidth', 1.5); hold on;
plot([0 h_max_m], [0 h_max_m], '--k', 'LineWidth', 2);
grid on;
xlabel('True height (m)');
ylabel('Estimated height (m)');
title(sprintf('Height estimation  RMS error = %.3f mm', rms(h_err_mm)));
legend('Estimate', 'Ideal', 'Location', 'southeast');
set(gca, 'FontSize', 11);

subplot(2, 2, 3);
plot(h_m, h_err_mm, '-o', 'LineWidth', 1.4, 'MarkerSize', 4);
grid on;
xlabel('True height (m)');
ylabel('Error (mm)');
title('Residual height error');
set(gca, 'FontSize', 10);

subplot(2, 2, 4);
histogram(h_err_mm, 10);
grid on;
xlabel('Error (mm)');
ylabel('Count');
title(sprintf('Error distribution  sigma = %.3f mm', std(h_err_mm)));
set(gca, 'FontSize', 10);

figure('Color', 'w', 'Name', 'Fig 14: Volume and mass recovery');
subplot(1, 2, 1);
plot(vol_true_m3, vol_est_m3, 'o', 'MarkerSize', 6, 'LineWidth', 1.5); hold on;
plot([0 max(vol_true_m3)], [0 max(vol_true_m3)], '--k', 'LineWidth', 2);
grid on;
xlabel('True volume (m^3)');
ylabel('Estimated volume (m^3)');
title(sprintf('Volume recovery  RMS error = %.6f m^3', rms(vol_err_m3)));
legend('Estimate', 'Ideal', 'Location', 'southeast');
set(gca, 'FontSize', 11);

subplot(1, 2, 2);
plot(mass_true_kg, mass_est_kg, 'o', 'MarkerSize', 6, 'LineWidth', 1.5); hold on;
plot([0 max(mass_true_kg)], [0 max(mass_true_kg)], '--k', 'LineWidth', 2);
grid on;
xlabel('True mass (kg)');
ylabel('Estimated mass (kg)');
title(sprintf('Mass recovery  RMS error = %.3f kg', rms(mass_err_kg)));
legend('Estimate', 'Ideal', 'Location', 'southeast');
set(gca, 'FontSize', 11);


operating_mask = fill_pct_true <= 100 * max_fill_frac_operating;

fill_pct_operating = fill_pct_true(operating_mask);
FoS_operating = FoS_sensor_proxy(operating_mask);


figure('Color', 'w', 'Name', 'Fig 15: Sensor based safety margin');

plot(fill_pct_operating, FoS_operating, 'LineWidth', 2.3, ...
    'Color', [0.47 0.67 0.19], ...
    'DisplayName', 'Sensor-based FoS estimate');
hold on;

yline(FoS_required_filling, '--r', 'LineWidth', 2, ...
    'DisplayName', 'Required FoS = 1.5');

xline(100 * max_fill_frac_operating, '--k', 'LineWidth', 1.5, ...
    'DisplayName', 'Maximum operating fill');

grid on;
xlabel('Fill level (%)');
ylabel('Sensor-based FoS estimate');
title(sprintf('Sensor-based filling safety margin at %s', sensor_location_name));
xlim([0 100 * max_fill_frac_operating]);
ylim([0 3]);
legend('Location', 'northeast');
set(gca, 'FontSize', 11);

figure('Color', 'w', 'Name', 'Fig 17: Interrogator sampling at random operating point');
lB_demo_m = lam_rand_bonded_m(focus_pair_idx);
[lam_demo_nm, R_demo] = simulate_spectrum_tmm(lB_demo_m, n_eff, L_grating_m, dn, ...
    lambda_span_nm, n_lambda_pts, n_tmm_segments, sigma_apod_m, alpha_db_per_m);
lam_grid_demo_nm = lam_demo_nm(1):resolution_pm * 1e-3:lam_demo_nm(end);
R_grid_demo = interp1(lam_demo_nm, R_demo, lam_grid_demo_nm, 'linear', 'extrap');
lam_peak_demo_nm = detect_peak_quadratic(lam_demo_nm, R_demo, noise_amp_R, resolution_pm) * 1e9;
plot(lam_demo_nm, R_demo, '-', 'LineWidth', 2, 'DisplayName', 'Continuous TMM spectrum'); hold on;
plot(lam_grid_demo_nm, R_grid_demo, 'o', 'MarkerSize', 4, 'LineWidth', 1, ...
    'DisplayName', sprintf('Sampled points  %.1f pm grid', resolution_pm));
xline(lam_peak_demo_nm, '--r', 'LineWidth', 1.5, ...
    'DisplayName', sprintf('Detected peak %.4f nm', lam_peak_demo_nm));
grid on;
xlabel('Wavelength (nm)');
ylabel('Reflectivity');
title(sprintf('Interrogator sampling for sensor pair %d at the random operating point', focus_pair_idx));
legend('Location', 'best', 'FontSize', 9);
set(gca, 'FontSize', 11);

figure('Color', 'w', 'Name', 'Fig 18: Per sensor spectra at random operating point');
for s = 1:nSensors
    p = ceil(s / 2);
    is_bonded = mod(s, 2) == 1;
    if is_bonded
        lambda_sensor_m = lam_rand_bonded_m(p);
        line_colour = c8(2*p - 1, :);
        subplot_title = sprintf('Pair %d bonded  %.0f nm', p, lambda0_bonded_nm(p));
    else
        lambda_sensor_m = lam_rand_ref_m(p);
        line_colour = c8(2*p, :);
        subplot_title = sprintf('Pair %d reference  %.0f nm', p, lambda0_ref_nm(p));
    end

    [lam_sensor_nm, R_sensor] = simulate_spectrum_tmm(lambda_sensor_m, n_eff, ...
        L_grating_m, dn, lambda_span_nm, n_lambda_pts, n_tmm_segments, ...
        sigma_apod_m, alpha_db_per_m);

    subplot(4, 2, s);
    plot(lam_sensor_nm, R_sensor, '-', 'LineWidth', 1.8, 'Color', line_colour);
    grid on;
    title(subplot_title, 'FontSize', 8);
    xlabel('Wavelength (nm)', 'FontSize', 7);
    ylabel('Reflectivity', 'FontSize', 7);
    set(gca, 'FontSize', 8);
end
sgtitle(sprintf('All sensor spectra at the random operating point  fill = %.1f %%  T = %.1f degC', ...
    rand_fill_pct, rand_T_degC));

%% Local functions

function V = circleSegmentVolume(h, R, L)
    h = max(0, min(h, 2 * R));
    if h <= 0
        V = 0;
        return;
    end
    if h >= 2 * R
        V = pi * R^2 * L;
        return;
    end
    theta = acos((R - h) / R);
    area = R^2 * theta - (R - h) * sqrt(2 * R * h - h^2);
    V = area * L;
end

function fill_frac = fill_fraction_from_height(h, R, L)
    fill_frac = circleSegmentVolume(h, R, L) / (pi * R^2 * L);
    fill_frac = max(0, min(fill_frac, 1));
end

function h = invertVolToHeight(V_target, R, L, h_max)
    V_target = max(0, min(V_target, pi * R^2 * L));
    lo = 0;
    hi = h_max;
    for iter = 1:60
        mid = 0.5 * (lo + hi);
        if circleSegmentVolume(mid, R, L) < V_target
            lo = mid;
        else
            hi = mid;
        end
    end
    h = 0.5 * (lo + hi);
end

function h_est = invert_lambda_to_height(lm, lc, h, method)
    [ls, ix] = sort(lc);
    hs = h(ix);
    lm = min(max(lm, min(ls)), max(ls));
    h_est = interp1(ls, hs, lm, method);
end

function lam_peak_m = detect_peak_quadratic(lam_nm, R, noise_amp_R, res_pm)
    R_noisy = R + noise_amp_R .* randn(size(R));
    R_noisy = max(R_noisy, 0);

    lam_grid_nm = lam_nm(1):res_pm * 1e-3:lam_nm(end);
    R_grid = interp1(lam_nm, R_noisy, lam_grid_nm, 'linear', 'extrap');

    [~, idx] = max(R_grid);
    if idx == 1 || idx == numel(R_grid)
        lam_peak_m = lam_grid_nm(idx) * 1e-9;
        return;
    end

    x1 = lam_grid_nm(idx - 1);
    y1 = R_grid(idx - 1);
    x2 = lam_grid_nm(idx);
    y2 = R_grid(idx);
    x3 = lam_grid_nm(idx + 1);
    y3 = R_grid(idx + 1);

    denom = (x1 - x2) * (x1 - x3) * (x2 - x3);
    if abs(denom) < 1e-18
        lam_peak_m = x2 * 1e-9;
        return;
    end

    A = (x3 * (y2 - y1) + x2 * (y1 - y3) + x1 * (y3 - y2)) / denom;
    B = (x3^2 * (y1 - y2) + x2^2 * (y3 - y1) + x1^2 * (y2 - y3)) / denom;

    if abs(A) < 1e-18
        x_peak_nm = x2;
    else
        x_peak_nm = -B / (2 * A);
    end

    if x_peak_nm < lam_grid_nm(1) || x_peak_nm > lam_grid_nm(end)
        x_peak_nm = x2;
    end

    lam_peak_m = x_peak_nm * 1e-9;
end

function [lam_nm, R] = simulate_spectrum_cmt(lB_m, neff, L, dn, span, nPts)
    lam_nm = linspace(lB_m * 1e9 - span, lB_m * 1e9 + span, nPts);
    lam_m  = lam_nm * 1e-9;
    kap    = pi * dn / lB_m;
    R      = zeros(size(lam_m));

    for i = 1:numel(lam_m)
        detuning = 2 * pi * neff * (1 / lam_m(i) - 1 / lB_m);
        if kap^2 > detuning^2
            g = sqrt(kap^2 - detuning^2);
            R(i) = kap^2 * sinh(g * L)^2 / (g^2 * cosh(g * L)^2 + detuning^2 * sinh(g * L)^2);
        else
            g = sqrt(detuning^2 - kap^2);
            R(i) = kap^2 * sin(g * L)^2 / (g^2 * cos(g * L)^2 + detuning^2 * sin(g * L)^2);
        end
    end
end

function [lam_nm, R] = simulate_spectrum_tmm(lB_m, neff, L, dn, span, nPts, nSeg, sigma, alpha_db_m)
    lam_nm = linspace(lB_m * 1e9 - span, lB_m * 1e9 + span, nPts);
    lam_m  = lam_nm * 1e-9;

    dz = L / nSeg;
    zc = ((1:nSeg) - 0.5) * dz;
    apod = exp(-((zc - L / 2) ./ sigma).^2);

    alpha_np = alpha_db_m * log(10) / 20;
    loss_seg = exp(-alpha_np * dz);

    kap0 = pi * dn / lB_m;
    Lam = lB_m / (2 * neff);

    R = zeros(size(lam_m));

    for w = 1:numel(lam_m)
        detuning = 2 * pi * neff / lam_m(w) - pi / Lam;
        T = eye(2);

        for s = 1:nSeg
            k = kap0 * apod(s);
            g2 = k^2 - detuning^2;

            if g2 > 0
                g = sqrt(g2);
                M = [cosh(g * dz) - 1i * detuning / g * sinh(g * dz), -1i * k / g * sinh(g * dz); ...
                     1i * k / g * sinh(g * dz),  cosh(g * dz) + 1i * detuning / g * sinh(g * dz)];
            elseif g2 < 0
                g = sqrt(-g2);
                M = [cos(g * dz) - 1i * detuning / g * sin(g * dz), -1i * k / g * sin(g * dz); ...
                     1i * k / g * sin(g * dz),  cos(g * dz) + 1i * detuning / g * sin(g * dz)];
            else
                M = [1 - 1i * detuning * dz, -1i * k * dz; ...
                     1i * k * dz, 1 + 1i * detuning * dz];
            end

            T = M * T * loss_seg;
        end

        R(w) = abs(T(2, 1) / T(1, 1))^2;
    end
end

function [R_peak, fwhm_nm, lam_peak_nm, lam_left_nm, lam_right_nm] = spectrum_metrics(lam_nm, R)
    R_peak = max(R);
    [~, idx_peak] = max(R);
    lam_peak_nm = lam_nm(idx_peak);

    idx_half = find(R >= R_peak / 2);
    if numel(idx_half) >= 2
        lam_left_nm = lam_nm(idx_half(1));
        lam_right_nm = lam_nm(idx_half(end));
        fwhm_nm = lam_right_nm - lam_left_nm;
    else
        lam_left_nm = NaN;
        lam_right_nm = NaN;
        fwhm_nm = NaN;
    end
end