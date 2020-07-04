"""Module for tomography."""

import numpy as np
from orthorec.radonortho import radonortho
from scipy import linalg


def getp(a):
    return a.__array_interface__['data'][0]


class OrthoRec(radonortho):
    """Class for tomography reconstruction of orthogonal slices thorugh direct 
    discreatization of line integrals in the Radon transform.
    Attribtues
    ----------
    ntheta : int
        The number of projections.    
    n, nz : int
        The pixel width and height of the projection.
    """

    def __init__(self, ntheta, n, nz):
        """Create class for the tomo solver."""
        super().__init__(ntheta, n, nz)
        self.init_filter('parzen')
       # exit()

    def __enter__(self):
        """Return self at start of a with-block."""
        return self

    def __exit__(self, type, value, traceback):
        """Free GPU memory due at interruptions or with-block exit."""
        self.free()

    def set_flat(self, flat):
        """Copy flat field to GPU for flat field correction"""
        flat = np.ascontiguousarray(flat)
        super().set_flat(getp(flat))

    def rec_ortho(self, data, theta, center, ix, iy, iz):
        """Reconstruction of 3 ortho slices with respect to ix,iy,iz indeces"""
        recx = np.zeros([self.nz, self.n], dtype='float32')
        recy = np.zeros([self.nz, self.n], dtype='float32')
        recz = np.zeros([self.n, self.n], dtype='float32')
        data = np.ascontiguousarray(data)
        theta = np.ascontiguousarray(theta)

        # C++ wrapper, send pointers to GPU arrays
        self.rec(getp(recx), getp(recy),
                 getp(recz), getp(data), getp(theta), center, ix, iy, iz)

        return recx, recy, recz

    def init_filter(self, filter='parzen', p=2):
        """Instead of direct integral discretization in the frequency domain by using the rectangular rule, 
        i.e. \int_a^b |signa| h(\sigma) d\sigma = \sum_k |\sigma_k| h(\sigma_k), 
        use a higher order polynomials for approximation \int_a^b |sigma| h(\sigma) d\sigma = \sum_k w_k h(\sigma_k), where 
        w_k are defined with the inverse Vandermonde matrix.
        Attribtues
        ----------
        p : max polinomial order for approximation
        """

        ne = self.n//2+1  # size of the array in frequencies
        t = np.arange(0, ne)/self.n
        s = np.linspace(0, 1, p)

        # Vandermonde matrix with extra line
        v = np.vander(s, p+2, increasing=True)

        # Inverse Vandermonde matrix for approximation
        iv = linalg.inv(v[:, :-2])
        # Integration over short intervals
        u = np.diff(v[:, 1:]/np.arange(1, p+2), axis=0)

        # Terms used after the change of coordinates (a,b)->(0,1)
        w1 = np.matmul(u[:, 1:p+1], iv)  # x*pn(x) term
        w2 = np.matmul(u[:, 0:p], iv)  # const*pn(x) term

        # Compensation for overlapping short intervals
        c = np.ones(ne-1)/(p-1)
        c[0:p-1] = 1/np.arange(1, p)
        c[ne-p-1:] = c[0:p][::-1]
        w = np.zeros(ne)
        for j in range(ne-p+1):
            # Change coordinates, and constant and linear parts
            wa = (t[j+p-1]-t[j])**2*w1+(t[j+p-1]-t[j])*t[j]*w2
            for k in range(p-1):
                w[j:j+p] += wa[k, :]*c[j+k]  # % Add to weights
        # dont change high frequencies
        w *= self.n
        w[ne-2*p:] = 0.5/ne*np.arange(ne-2*p+1, ne+1)

        if filter == 'parzen':
            w = w * 4 * (1 - t * 2)**3
        # add other filters...

        w = np.ascontiguousarray(w.astype('float32'))
        # set filter in the C++ code
        self.set_filter(getp(w))
