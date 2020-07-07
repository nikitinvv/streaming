#include "radonortho.cuh"
#include "kernels.cuh"
#include  <stdio.h>
radonortho::radonortho(size_t ntheta, size_t n, size_t nz)
 : ntheta(ntheta), n(n), nz(nz) 
{
	// arrays allocation on GPU
	cudaMalloc((void **)&fx, n * nz * sizeof(float));
	cudaMalloc((void **)&fy, n * nz * sizeof(float));
	cudaMalloc((void **)&fz, n * n * sizeof(float));
	cudaMalloc((void **)&g, n * ntheta * nz * sizeof(float));
	cudaMalloc((void **)&gs, n * ntheta * nz * sizeof(unsigned char));	
	cudaMalloc((void **)&flat, n * nz * sizeof(unsigned char));
	
	cudaMalloc((void **)&fg, (n / 2 + 1) * ntheta * nz * sizeof(float2));
	cudaMalloc((void **)&filter, (n / 2 + 1) * sizeof(float));	
	cudaMalloc((void **)&theta, ntheta * sizeof(float));

	cudaMemset(fx,0,n*nz*sizeof(float));
	cudaMemset(fy,0,n*nz*sizeof(float));
	cudaMemset(fz,0,n*n*sizeof(float));
	
	//fft plans for filtering
	int ffts[] = {n};
	int idist = n;
	int odist = n / 2 + 1;
	int inembed[] = {n};
	int onembed[] = {n / 2 + 1};
	cufftPlanMany(&plan_forward, 1, ffts, inembed, 1, idist, onembed, 1, odist, CUFFT_R2C, ntheta * nz);
	cufftPlanMany(&plan_inverse, 1, ffts, onembed, 1, odist, inembed, 1, idist, CUFFT_C2R, ntheta * nz);

	//init thread blocks and block grids
	BS3d.x = 32;
	BS3d.y = 32;
	BS3d.z = 1;

	GS3d1.x = ceil(n / (float)BS3d.x);
	GS3d1.y = ceil(ntheta / (float)BS3d.y);
	GS3d1.z = ceil(nz / (float)BS3d.z);

	GS3d2.x = ceil(n / (float)BS3d.x);
	GS3d2.y = ceil(n / (float)BS3d.y);
	
	GS3d3.x = ceil(n / (float)BS3d.x);
	GS3d3.y = ceil(nz / (float)BS3d.y);

	is_free = false;	
}


// destructor, memory deallocation
radonortho::~radonortho() { free(); }


void radonortho::free()
{
	if (!is_free) 
	{
		cudaFree(g);
		cudaFree(gs);		
		cudaFree(fg);
		cudaFree(fx);
		cudaFree(fy);
		cudaFree(fz);
		cudaFree(filter);

		cudaFree(theta);
		cufftDestroy(plan_forward);
		cufftDestroy(plan_inverse);
		is_free = true;   
	}
	
}


void radonortho::rec(size_t fx_,size_t fy_,size_t fz_, size_t g_, size_t theta_, float center, int ix, int iy, int iz)
{
	// copy data and angles to GPU
	cudaMemcpy(gs, (unsigned char *)g_, n * ntheta * nz * sizeof(unsigned char), cudaMemcpyDefault);	
	cudaMemcpy(theta, (float *)theta_, ntheta * sizeof(float), cudaMemcpyDefault);
	
	//cudaMemcpy(g, (float *)g_, n * ntheta * nz * sizeof(float), cudaMemcpyDefault);	
	
	// convert short to float
	correction<<<GS3d1, BS3d>>>(g, gs, flat, n, ntheta, nz);	
	

	// fft for filtering in the frequency domain
	cufftExecR2C(plan_forward, (cufftReal *)g, (cufftComplex *)fg);
	// parzen filtering
	applyfilter<<<GS3d1, BS3d>>>(fg, filter, n, ntheta, nz);
	// fft back
	cufftExecC2R(plan_inverse, (cufftComplex *)fg, (cufftReal *)g);
	//cudaMemcpy((float *)g_, g, n * ntheta * nz * sizeof(float), cudaMemcpyDefault);	
	
	// reconstruct slices via summation over lines	
	ortho_kerx<<<GS3d3, BS3d>>>(fx, g, theta, center, ix, n, ntheta, nz);
	ortho_kery<<<GS3d3, BS3d>>>(fy, g, theta, center, iy, n, ntheta, nz);	
	ortho_kerz<<<GS3d2, BS3d>>>(fz, g, theta, center, iz, n, ntheta, nz);
	
	//copy result to cpu
	cudaMemcpy((float *)fx_, fx, n * nz * sizeof(float), cudaMemcpyDefault);
	cudaMemcpy((float *)fy_, fy, n * nz * sizeof(float), cudaMemcpyDefault);
	cudaMemcpy((float *)fz_, fz, n * n * sizeof(float), cudaMemcpyDefault);
}

void radonortho::set_filter(size_t filter_)
{
	cudaMemcpy(filter, (float*) filter_, (n/2+1)*sizeof(float),cudaMemcpyDefault);
}

void radonortho::set_flat(size_t flat_)
{
	cudaMemcpy(flat, (unsigned char*) flat_, n*nz*sizeof(unsigned char),cudaMemcpyDefault);
	
}