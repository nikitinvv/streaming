/*interface*/
%module radonortho

%{
#define SWIG_FILE_WITH_InIT
#include "radonortho.cuh"
%}

class radonortho
{
public:
  %immutable;
  size_t n;
  size_t ntheta;
  size_t nz;

  %mutable;
  radonortho(size_t ntheta, size_t n, size_t nz);
  ~radonortho();
  void rec(size_t fx, size_t fy, size_t fz, size_t g, size_t theta, float center, int ix, int iy, int iz, int flgx, int flgy, int flgz);  
  void set_filter(size_t filter_);  
  
  void free();
};