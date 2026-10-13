% --- 物理参数 ---
Lq = 0.00056; 
R = 0.6;
flux = 0.005753;
J = 0.00002;
Pn = 4;
Ts = 1e-06; 


fc = 1000000;
Wc = 2 * pi * fc;
Kp_c_q = Lq * Wc;
Ki_c = R * Wc; 
Kp_c_d = Ld * Wc;


fsp = 100000; 
Wsp = 2 * pi * fsp;
Kp_s = (J * Wsp) / (1.5 * Pn * flux);
Ki_s = Kp_s * (Wsp / 5);

fpos = 500000;