function F = FBG_v7_Functions()
% Shared mathematical function library for the FBG sensing system.
% Returns a struct F of function handles.


    % ----- Physics functions ------------
    F.simulate_spectrum_tmm     = @simulate_spectrum_tmm;     
    F.simulate_spectrum_cmt     = @simulate_spectrum_cmt;     
    F.detect_peak_quadratic     = @detect_peak_quadratic;     
    F.invert_lambda_to_height   = @invert_lambda_to_height;   
    F.spectrum_metrics          = @spectrum_metrics;           
    F.circleSegmentVolume       = @circleSegmentVolume;        
    F.invertVolToHeight         = @invertVolToHeight;          
    F.fill_fraction_from_height = @fill_fraction_from_height; 

    % ----- FEM data management -----
    F.loadFEMStrainTable = @loadFEMStrainTable;
    F.femStrainLookup    = @femStrainLookup;
    F.femMechProfile     = @femMechProfile;

    % ----- GUI-specific math helper ---------------------------------------
    F.sampleTriangular   = @sampleTriangular;

end 


% ----- Geometry ---------------------------------
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
    area  = R^2 * theta - (R - h) * sqrt(2 * R * h - h^2);
    V     = area * L;
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


%----Wavelength/Height Inversion--------------------------------------

function h_est = invert_lambda_to_height(lm, lc, h, method)
    [ls, ix] = sort(lc);
    hs = h(ix);
    lm = min(max(lm, min(ls)), max(ls));
    h_est = interp1(ls, hs, lm, method);
end

%----Peak Detection--------------------------------------

function lam_peak_m = detect_peak_quadratic(lam_nm, R, noise_amp_R, res_pm)
% Sub-resolution peak detection via 3-point quadratic fit.
    R_noisy = R + noise_amp_R .* randn(size(R));
    R_noisy = max(R_noisy, 0);

    lam_grid_nm = lam_nm(1):res_pm * 1e-3:lam_nm(end);
    R_grid = interp1(lam_nm, R_noisy, lam_grid_nm, 'linear', 'extrap');

    [~, idx] = max(R_grid);
    if idx == 1 || idx == numel(R_grid)
        lam_peak_m = lam_grid_nm(idx) * 1e-9;
        return;
    end

    x1 = lam_grid_nm(idx - 1);  y1 = R_grid(idx - 1);
    x2 = lam_grid_nm(idx);      y2 = R_grid(idx);
    x3 = lam_grid_nm(idx + 1);  y3 = R_grid(idx + 1);

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

%----Spectrum Simulation--------------------------------------

function [lam_nm, R] = simulate_spectrum_cmt(lB_m, neff, L, dn, span, nPts)
% Coupled-mode theory FBG reflection spectrum.
    lam_nm = linspace(lB_m * 1e9 - span, lB_m * 1e9 + span, nPts);
    lam_m  = lam_nm * 1e-9;
    kap    = pi * dn / lB_m;
    R      = zeros(size(lam_m));

    for i = 1:numel(lam_m)
        detuning = 2 * pi * neff * (1 / lam_m(i) - 1 / lB_m);
        if kap^2 > detuning^2
            g    = sqrt(kap^2 - detuning^2);
            R(i) = kap^2 * sinh(g * L)^2 / ...
                   (g^2 * cosh(g * L)^2 + detuning^2 * sinh(g * L)^2);
        else
            g    = sqrt(detuning^2 - kap^2);
            R(i) = kap^2 * sin(g * L)^2 / ...
                   (g^2 * cos(g * L)^2 + detuning^2 * sin(g * L)^2);
        end
    end
end

function [lam_nm, R] = simulate_spectrum_tmm(lB_m, neff, L, dn, span, ...
        nPts, nSeg, sigma, alpha_db_m)
% Transfer-matrix method FBG spectrum with apodisation and propagation loss.
    lam_nm = linspace(lB_m * 1e9 - span, lB_m * 1e9 + span, nPts);
    lam_m  = lam_nm * 1e-9;

    dz       = L / nSeg;
    zc       = ((1:nSeg) - 0.5) * dz;
    apod     = exp(-((zc - L / 2) ./ sigma).^2);
    alpha_np = alpha_db_m * log(10) / 20;
    loss_seg = exp(-alpha_np * dz);
    kap0     = pi * dn / lB_m;
    Lam      = lB_m / (2 * neff);
    R        = zeros(size(lam_m));

    for w = 1:numel(lam_m)
        detuning = 2 * pi * neff / lam_m(w) - pi / Lam;
        T = eye(2);
        for s = 1:nSeg
            k  = kap0 * apod(s);
            g2 = k^2 - detuning^2;
            if g2 > 0
                g = sqrt(g2);
                M = [cosh(g*dz) - 1i*detuning/g*sinh(g*dz), -1i*k/g*sinh(g*dz); ...
                      1i*k/g*sinh(g*dz),  cosh(g*dz) + 1i*detuning/g*sinh(g*dz)];
            elseif g2 < 0
                g = sqrt(-g2);
                M = [cos(g*dz) - 1i*detuning/g*sin(g*dz), -1i*k/g*sin(g*dz); ...
                      1i*k/g*sin(g*dz),  cos(g*dz) + 1i*detuning/g*sin(g*dz)];
            else
                M = [1 - 1i*detuning*dz, -1i*k*dz; ...
                      1i*k*dz,            1 + 1i*detuning*dz];
            end
            T = M * T * loss_seg;
        end
        R(w) = abs(T(2, 1) / T(1, 1))^2;
    end
end

% Peak Reflectivity, FWHM, and half-power wavelengths.
function [R_peak, fwhm_nm, lam_peak_nm, lam_left_nm, lam_right_nm] = ...
        spectrum_metrics(lam_nm, R)
    R_peak = max(R);
    [~, idx_peak] = max(R);
    lam_peak_nm = lam_nm(idx_peak);
    idx_half = find(R >= R_peak / 2);
    if numel(idx_half) >= 2
        lam_left_nm  = lam_nm(idx_half(1));
        lam_right_nm = lam_nm(idx_half(end));
        fwhm_nm      = lam_right_nm - lam_left_nm;
    else
        lam_left_nm  = NaN;
        lam_right_nm = NaN;
        fwhm_nm      = NaN;
    end
end


%----FEM Data Management--------------------------------------

function FEM = loadFEMStrainTable(fname)
% Load fem_strain_data.csv and build 3-D strain grid eps_grid(iPct,iTemp,iRho).n.
    fem_raw  = readtable(fname, 'VariableNamingRule', 'preserve');
    pct_all  = fem_raw.("percentage_%");
    eps_all  = fem_raw.("strain");
    temp_all = fem_raw.("temperature_C");
    rho_all  = fem_raw.("density_kg_m3");

    FEM.pct_grid  = unique(pct_all);
    FEM.temp_grid = unique(temp_all);
    FEM.rho_grid  = unique(rho_all);
    nPct  = numel(FEM.pct_grid);
    nTemp = numel(FEM.temp_grid);
    nRho  = numel(FEM.rho_grid);

    FEM.eps_grid = zeros(nPct, nTemp, nRho);
    for i = 1:height(fem_raw)
        ip = find(FEM.pct_grid  == pct_all(i),  1);
        it = find(FEM.temp_grid == temp_all(i), 1);
        ir = find(FEM.rho_grid  == rho_all(i),  1);
        FEM.eps_grid(ip, it, ir) = eps_all(i);
    end
    FEM.nRows = height(fem_raw);

    % Pre-compute fill-height profile for calibration-curve inversion
    R_t   = 2.1 / 2;
    L_t   = 4.8;
    h_max = 2 * R_t;
    V_cyl = pi * R_t^2 * L_t;
    h_prof = zeros(nPct, 1);
    for i = 1:nPct
        V_geom   = (FEM.pct_grid(i) / 100) * V_cyl;
        h_prof(i) = invertVolToHeight(V_geom, R_t, L_t, h_max);
    end
    FEM.h_profile_m = h_prof;

    fprintf('FEM table loaded: %d rows | %d fill x %d T x %d rho\n', ...
        FEM.nRows, nPct, nTemp, nRho);
end



function eps_mech = femStrainLookup(FEM, fill_pct, T_C, rho_kgm3)
% Mechanical strain across all fill levels (used for calibration curve).

    T_q   = min(max(T_C,       min(FEM.temp_grid)), max(FEM.temp_grid));
    rho_q = min(max(rho_kgm3,  min(FEM.rho_grid)),  max(FEM.rho_grid));
    pct_q = min(max(fill_pct,  min(FEM.pct_grid)),   max(FEM.pct_grid));

    nPct = numel(FEM.pct_grid);
    eps_total_at_pct = zeros(nPct, 1);
    for i = 1:nPct
        slice_2d = squeeze(FEM.eps_grid(i, :, :)); 
        eps_total_at_pct(i) = interp2(FEM.rho_grid', FEM.temp_grid, ...
            slice_2d, rho_q, T_q, 'linear');
    end

    eps_baseline    = eps_total_at_pct(1);          
    eps_mech_at_pct = eps_total_at_pct - eps_baseline;
    eps_mech = interp1(FEM.pct_grid, eps_mech_at_pct, pct_q, 'linear');
end


% femMechProfile  Mechanical strain profile over all fill levels.
function eps_mech_profile = femMechProfile(FEM, T_C, rho_kgm3)
    T_q   = min(max(T_C,       min(FEM.temp_grid)), max(FEM.temp_grid));
    rho_q = min(max(rho_kgm3,  min(FEM.rho_grid)),  max(FEM.rho_grid));
    nPct  = numel(FEM.pct_grid);
    eps_total = zeros(nPct, 1);
    for i = 1:nPct
        slice_2d = squeeze(FEM.eps_grid(i, :, :));
        eps_total(i) = interp2(FEM.rho_grid', FEM.temp_grid, ...
            slice_2d, rho_q, T_q, 'linear');
    end
    eps_mech_profile = eps_total - eps_total(1);
end



%   Used by the GUI to generate warm-biased ambient temperatures.
function x = sampleTriangular(a, c, b)
    u   = rand();
    F_c = (c - a) / (b - a);
    if u < F_c
        x = a + sqrt(u * (b - a) * (c - a));
    else
        x = b - sqrt((1 - u) * (b - a) * (b - c));
    end
end