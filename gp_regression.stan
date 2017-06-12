functions{ // This Stan file is largely cribbed from Mike Lawrence's GP examples
	# GP: computes noiseless Gaussian Process
	vector GP(real volatility, real amplitude, vector normal01, int n_x, real[] x ) {
		matrix[n_x,n_x] cov_mat ;
		real amplitude_sq_plus_jitter ;
		amplitude_sq_plus_jitter = amplitude^2 + 1e-6 ;
		cov_mat = cov_exp_quad(x, amplitude, 1/volatility) ;
		for(i in 1:n_x){
			cov_mat[i,i] = amplitude_sq_plus_jitter ;
		}
		return(cholesky_decompose(cov_mat) * normal01 ) ;
	}
}

data {

	# n_y: number of observations in y
	int n_y ;
	
	# n_subj: number of subjects
	int n_subj ;

	// # n_subj: vector indicating which subject is associated  with each y
	// int<lower=1,upper=n_subj> subj[n_y] ;

	# y: vector of observations for y
	#	 should be scaled to mean=0,sd=1
	vector[10000] y[n_subj] ;

	# n_x: number of unique x values
	int n_x ;

	# x: unique values of x
	#	 should be scaled to min=0,max=1
	real x[n_x] ;

	# x_index: vector indicating which x is associated zith each y
	int x_index[n_y] ;

	# n_z: number of columns in predictor matrix z
	int n_z ;

	# rows_z_unique: number of rows in predictor matrix z
	int rows_z_unique ;

	# z_unique: predictor matrix (each column gets its own GP)
	matrix[rows_z_unique,n_z] z_unique ;

	# z_by_f_by_s_pad:
	int z_by_f_by_s_pad[n_subj, 10000] ;
	
	# vector indicating the length of the GP index vector for each participant
	int subj_obs[n_subj] ;
	
}

parameters {

	# subj_noise: noise per subject
	vector[n_subj] subj_noise ;

	# subj_noise_sd: sd of subj_noise values
	real<lower=0> subj_noise_sd ;

	# volatility_helper: helper for cauchy-distributed volatility (see transformed parameters)
	vector<lower=0,upper=pi()/2>[n_z] volatility_helper ;

	# subj_volatility_helper: helper for cauchy-distributed volitilities per subject (see transformed parameters)
	vector<lower=0,upper=pi()/2>[n_subj] subj_volatility_helper[n_z] ;

	# subj_volatility_sd: sd of subject volitilities
	vector<lower=0>[n_z] subj_volatility_sd ;

	# amplitude: amplitude of population GPs
	vector<lower=0>[n_z] amplitude ;

	# subj_amplitude: amplitude of per-subject GPs
	vector<lower=0>[n_subj] subj_amplitude[n_z] ;

	# subj_amplitude_sd: sd of subj_amplitude
	vector<lower=0>[n_z] subj_amplitude_sd ;

	# f_normal01: helper variable for GPs (see transformed parameters)
	matrix[n_x, n_z] f_normal01 ;

	# f_normal01: helper variable for per-subject GPs (see transformed parameters)
	matrix[n_x, n_z] subj_f_normal01[n_subj] ;

}

transformed parameters{

	# volatility: volatility of population GPs
	vector[n_z] volatility ;

	# volatility: volatility of per-subject GPs
	vector[n_subj] subj_volatility[n_z] ;

	# f: Population GPs
	matrix[n_x,n_z] f ;

	# subj_f: per-subject GPs
	matrix[n_x,n_z] subj_f[n_subj] ;

	#next line implies volatility ~ cauchy(0,10)
	volatility = 10*tan(volatility_helper) ;

	# loop over predictors, computing population GP and per-subject GPs
	for(zi in 1:n_z){

		# next line implies subj_volatility ~ cauchy(0,subj_volatility_sd)
		subj_volatility[zi] = subj_volatility_sd[zi] * tan(subj_volatility_helper[zi]) ;

		# population GP
		f[,zi] = GP(
			  volatility[zi]
			, amplitude[zi]
			, f_normal01[,zi]
			, n_x , x
		) ;

		# loop over subjects, computing per-subject GPs
		for(si in 1:n_subj){

			# per-subject GP
			subj_f[si, ,zi] = f[,zi] +
				GP(
					subj_volatility[zi,si]
					, subj_amplitude[zi,si]
					, subj_f_normal01[si,,zi]
					, n_x , x
				) ;

		}
	}

}

model {

	# noise priors
	subj_noise_sd ~ weibull(2,1) ; #peaked at .8ish
	subj_noise ~ normal(0,subj_noise_sd) ;  #peaked at 0

	# volatility priors:
	# - population GPs have volatility ~ cauchy(0,10)
	# - per-subject GPs have subj_volatility ~ cauchy(0,subj_volatility_sd)
	# - subj_volatility pooled via subj_volatility_sd
	subj_volatility_sd ~ weibull(2,10) ; #peaked around 8

	# amplitude priors
	# - population GPs have amplitude as weibull peaked at .8
	# - per-subject GPs have amplitude as normal peaked at zero with pooled sd
	amplitude ~ weibull(2,1) ; #peaked at .8ish
	subj_amplitude_sd ~ weibull(2,1) ;#peaked at .8ish
	for(zi in 1:n_z){
		subj_amplitude[zi] ~ normal(0,subj_amplitude_sd[zi]) ; #peaked at 0
	}

	# normal(0,1) priors on GP helpers
	to_vector(f_normal01) ~ normal(0,1);
	for(si in 1:n_subj){
		to_vector(subj_f_normal01[si]) ~ normal(0,1) ;
	}
  
  # loop over observations
	{
		# subj_noise_exp: exponentiated subj_noise
		vector[n_subj] subj_noise_exp ;
		matrix[rows_z_unique,n_x] z_by_f[n_subj] ;
		
		subj_noise_exp = exp(subj_noise) ;

		for(i in 1:rows_z_unique){
			for(j in 1:n_x){
			  for(k in 1:n_subj){
				z_by_f[k,i,j] = sum(z_unique[i].*subj_f[k,j,]) ;
			  }
			}
		}
		for(si in 1:n_subj) {
  		y[si,1:subj_obs[si]] ~ normal(
  			  to_vector(z_by_f[si])[z_by_f_by_s_pad[si,1:subj_obs[si]]]
  			, subj_noise_exp[si]
  		);
		}
	}

}

