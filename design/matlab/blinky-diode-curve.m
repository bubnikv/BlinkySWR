clear;
# Read the data produced by ltspice simulating '..\ltspice\blinky-diode-curve-parametric.asc'
simresult = LTspice2Matlab('..\ltspice\blinky-diode-curve-parametric.raw');

# Indices of starts of each of the time sequence produced by ltspice.
starts = find(simresult.time_vect == simresult.time_vect(1));
assert(size(starts)(2) == 1001, "Number of samples must match size(0:0.1:100)");
# Process the ltspice simulation data, 
steps     = size(starts)(2);
vsrc_max  = zeros(steps, 1);
vload_max = zeros(steps, 1);
vadc_mean = zeros(steps, 1);
id_max    = zeros(steps, 1);
for i = 1:steps
	istart = starts(i);
	if (i == steps)
        iend = size(simresult.time_vect)(2);
	else
        iend = starts(i + 1);
	endif
	iend = iend - 1;
	time_vect = simresult.time_vect(istart:iend);
	variable_mat = simresult.variable_mat(:, istart:iend);
	times = diff(time_vect) / (time_vect(end) - time_vect(1));
	# volts
	vsrc_max(i)  = max(abs(variable_mat(1,:) - variable_mat(2, :)));
	# volts
	vload_max(i) = max(abs(variable_mat(3, :)));
	vadc  = variable_mat(4, :);
	# volts, averaged over the time samples
	vadc_mean(i) = sum((vadc(1:end-1)+vadc(2:end)) .* times) / 2;
	# mAmps
	id_max(i) = max(abs(variable_mat(5, :))) * 1000;
end

save "blinky-diode-curve.mat" vload_max vload_max vadc_mean id_max

# Interpolate the load voltage 'vload_max' with a line crossing [0, 0]. The splinefit function fits in a least squares sense.
# Robust fitting is used to eliminate outliers.
load_slope = splinefit(0:1:size(vload_max)(1)-1, vload_max', [0 size(vload_max)(1)-1], "order", 1, "beta", 0.9, "constraints", struct ("xc", [0], "yc", [0])).coefs(1);
# Interpolate 'vload_max' described by 'load_slope'.
vload = (0:1:size(vsrc_max)(1)-1)' * load_slope;
# Relative approximation error.
plot((vload - vload_max) ./ vload)
# Absolute approximation error.
plot(vload - vload_max)

# Correction of the diode drop with a 150kOhm / 10kOhm resistive divider.
resistor_divider_ratio = 10 / (150 + 10);
vadc_corr = vload * resistor_divider_ratio - vadc_mean;
plot(vadc_mean, vadc_corr)

# ADC reference.
adc_vmax = 1.1;
# Size of the low resolution table, capturing the rest of the diode curve.
table_size = 32;
corr_step_x = adc_vmax / table_size;
# Size of the high resolution table, capturing the diode curve knee.
table_size2 = 16;
corr_step_x2 = corr_step_x / 16;
# Samples of the correction table, to be fitted with a linear interpolation curve.
corr_samples = [0:corr_step_x2:corr_step_x-corr_step_x2, corr_step_x:corr_step_x:adc_vmax];

# Fit the polyline to the rough table with a fine table knee over the ADC interval <0, adc_vmax).
vadc_mean_trimmed = [vadc_mean(1:find(vadc_mean >= adc_vmax)(1)-1); adc_vmax];
vadc_corr_trimmed = [vadc_corr(1:find(vadc_mean >= adc_vmax)(1)-1); interp1(vadc_mean, vadc_corr, adc_vmax)];
vadc_corr_poly1 = splinefit(vadc_mean_trimmed, vadc_corr_trimmed, corr_samples, "order", 1);
corr_firmware_knee = vadc_corr_poly1.coefs(1:table_size2,2);
corr_firmware_rough = [ vadc_corr_poly1.coefs(table_size2+1:end,2); vadc_corr_poly1.coefs(end, 2) + vadc_corr_poly1.coefs(end, 1) * corr_step_x ];

# Visualize interpolation errors.
err_samples = 0:adc_vmax/1024:adc_vmax;
interp_error = interp1(vadc_mean, vadc_corr, err_samples) - interp1(corr_samples, [corr_firmware_knee; corr_firmware_rough], err_samples);
plot(corr_samples, [corr_firmware_knee; corr_firmware_rough], 'g+', vadc_mean, vadc_corr, 'b', err_samples, interp_error, 'r');

# Scale the measured value, so that 10V will be a multiple of 2^N.
adc_vmax_corrected = adc_vmax+corr_firmware_rough(end);
# Maximum power measured at full ADC input scale including the correction.
vpp_max = 2 * adc_vmax_corrected / resistor_divider_ratio;
pwr_max = vpp_max^2 / 100;
# Scale voltage, so that the maximum corrected input will correspond to 16 watts transceiver power.
adc_scale = sqrt(pwr_max / 16);
# When the corrected ADC voltage is scaled with adc_scale, the maximum ADC value corresponds to 16 Watts
# and 1/4 of the ADC value corresponds conveniently to 1 Watt.
vpp_test_16 = (2 * adc_vmax_corrected / adc_scale) / resistor_divider_ratio;
pwr_test_16 = vpp_test_16^2 / 100;
assert(abs(pwr_test_16 - 16) < 1e-4);

# Scaling to 13 + 2 = 15 bits of resolution, where 32768 corresponds to 16 Watts of input power.
scale = adc_scale * 8 * 1024 * 4 / adc_vmax_corrected;
corr_firmware_rough_scaled = round(scale * (corr_samples(table_size2+1:end) .+ corr_firmware_rough'));

% Writing corr_firmware_rough_scaled into Intel HEX file to be stored into EEPROM of the AtTiny13A. 
fname = "../../firmware/eeprom.hex";
delete(fname);
fileID = fopen(fname, 'w');
for (line_idx = 0:3)
	words = corr_firmware_rough_scaled(line_idx * 8 + 1 : (line_idx + 1) * 8);
	line = [ 16, 0, line_idx * 16, 0, [ mod(words, 256); floor(words / 256); ](:)' ];
	checksum = mod(256 - mod(sum(line), 256), 256);
	fprintf(fileID, ":%s\n", strcat(dec2hex([ line, checksum ],2)'(:)'));
end
fprintf(fileID, ":00000001FF\n");
fclose(fileID);

% Writing corr_firmware_fine_scaled into a C file to be included into the firmware source.
corr_firmware_knee_scaled = round(scale * (corr_samples(1:table_size2) .+ corr_firmware_knee'));
corr_firmware_knee_scaled_hexcstr = strcat("0x", dec2hex(corr_firmware_knee_scaled, 4), ", ")'(:)'(1:end-1);
fname = "../../firmware/table_fine.inc";
delete(fname);
fileID = fopen(fname, 'w');
fprintf(fileID, "%s\n", corr_firmware_knee_scaled_hexcstr);
fclose(fileID);

% Verifying the diode curve interpolation against the data captured by a logic analyzer from the firmware
% from_firmware(:,1) - sequence from 0 to (1023 * 8): Possible sum of 8 ADC samples.
% from_firmware(:,2) - interpolation by the firmware's correct_diode(uint16_t v) function.
load from_firmware.mat
fw_adc = from_firmware(:,1) * adc_vmax / (1024 * 8);
fw_corrected = from_firmware(:,2);
poly_corrected = scale * (fw_adc + ppval(vadc_corr_poly1, fw_adc));
fw_error = fw_corrected - poly_corrected;
% Interpolation error is lower than 2 LSB of a 15 bit value, reaching resolution of 13 bits.
assert(max(abs(fw_error)) < 3);


% Approximately 0.2W
vfwd = 104 * 8;
% Approximately 0.8W
vfwd = vfwd * 2;
vref = 0:1:floor(vfwd * 6.3 / 8);
swr = (vfwd + vref) ./ (vfwd - vref);
scale = 8;
div = floor(((vfwd - vref) * scale + 15) / 32);
swr_approx = floor(((vfwd + vref) * scale + floor(div/2)) ./ div) / 32;
swr_err = abs(swr - swr_approx) ./ swr;
