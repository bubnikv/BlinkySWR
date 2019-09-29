clear;
simresult = LTspice2Matlab('..\ltspice\blinky-diode-curve-parametric.raw');
starts = find(simresult.time_vect == simresult.time_vect(1));

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

save "blinky-diode-curve.mat" vsrc_max vload_max vadc_mean id_max

vadc_corr = vsrc_max * 2.2 / ((39+2.2) * 4) - vadc_mean;
plot(vadc_mean, vadc_corr)

cntr = ceil(size(vadc_mean)(1)/2);
slope = (vadc_corr(end) - vadc_corr(cntr)) / (vadc_mean(end) - vadc_mean(cntr));
offset = vadc_corr(cntr) - vadc_mean(cntr) * slope;
hold
plot(vadc_mean, vadc_mean * slope + offset)

#cntr2 = ceil(cntr/2);
#slope2 = (vadc_corr(cntr) - vadc_corr(cntr2)) / (vadc_mean(cntr) - vadc_mean(cntr2));
#offset2 = vadc_corr(cntr2) - vadc_mean(cntr2) * slope2;
#plot(vadc_mean, vadc_mean * slope2 + offset2)
