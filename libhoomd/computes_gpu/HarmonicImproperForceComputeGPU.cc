/*
Highly Optimized Object-oriented Many-particle Dynamics -- Blue Edition
(HOOMD-blue) Open Source Software License Copyright 2008, 2009 Ames Laboratory
Iowa State University and The Regents of the University of Michigan All rights
reserved.

HOOMD-blue may contain modifications ("Contributions") provided, and to which
copyright is held, by various Contributors who have granted The Regents of the
University of Michigan the right to modify and/or distribute such Contributions.

Redistribution and use of HOOMD-blue, in source and binary forms, with or
without modification, are permitted, provided that the following conditions are
met:

* Redistributions of source code must retain the above copyright notice, this
list of conditions, and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this
list of conditions, and the following disclaimer in the documentation and/or
other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of HOOMD-blue's
contributors may be used to endorse or promote products derived from this
software without specific prior written permission.

Disclaimer

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER AND CONTRIBUTORS ``AS IS''
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND/OR
ANY WARRANTIES THAT THIS SOFTWARE IS FREE OF INFRINGEMENT ARE DISCLAIMED.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// Maintainer: dnlebard

#ifdef WIN32
#pragma warning( push )
#pragma warning( disable : 4244 )
#endif

#include "HarmonicImproperForceComputeGPU.h"

#include <boost/python.hpp>
using namespace boost::python;

#include <boost/bind.hpp>
using namespace boost;

using namespace std;

/*! \param sysdef System to compute improper forces on
*/
HarmonicImproperForceComputeGPU::HarmonicImproperForceComputeGPU(boost::shared_ptr<SystemDefinition> sysdef)
        : HarmonicImproperForceCompute(sysdef), m_block_size(64)
    {
    // can't run on the GPU if there aren't any GPUs in the execution configuration
    if (!exec_conf->isCUDAEnabled())
        {
        cerr << endl 
             << "***Error! Creating a ImproperForceComputeGPU with no GPU in the execution configuration" 
             << endl << endl;
        throw std::runtime_error("Error initializing ImproperForceComputeGPU");
        }
        
    // allocate and zero device memory
    GPUArray<float2> params(m_improper_data->getNDihedralTypes(), exec_conf);
    m_params.swap(params);
    }

HarmonicImproperForceComputeGPU::~HarmonicImproperForceComputeGPU()
    {
    }

/*! \param type Type of the improper to set parameters for
    \param K Stiffness parameter for the force computation.
        \param chi Equilibrium value of the dihedral angle.

    Sets parameters for the potential of a particular improper type and updates the
    parameters on the GPU.
*/
void HarmonicImproperForceComputeGPU::setParams(unsigned int type, Scalar K, Scalar chi)
    {
    HarmonicImproperForceCompute::setParams(type, K, chi);
    
    ArrayHandle<float2> h_params(m_params, access_location::host, access_mode::readwrite);
    // update the local copy of the memory
    h_params.data[type] = make_float2(float(K), float(chi));
    }

/*! Internal method for computing the forces on the GPU.
    \post The force data on the GPU is written with the calculated forces

    \param timestep Current time step of the simulation

    Calls gpu_compute_harmonic_improper_forces to do the dirty work.
*/
void HarmonicImproperForceComputeGPU::computeForces(unsigned int timestep)
    {
    // start the profile
    if (m_prof) m_prof->push(exec_conf, "Harmonic Improper");
    
    gpu_dihedraltable_array& gpu_impropertable = m_improper_data->acquireGPU();
    
    // the improper table is up to date: we are good to go. Call the kernel
    gpu_pdata_arrays& pdata = m_pdata->acquireReadOnlyGPU();
    gpu_boxsize box = m_pdata->getBoxGPU();
      
    ArrayHandle<Scalar4> d_force(m_force,access_location::device,access_mode::overwrite);
    ArrayHandle<Scalar> d_virial(m_virial,access_location::device,access_mode::overwrite);
    ArrayHandle<float2> d_params(m_params, access_location::device, access_mode::read);

    // run the kernel in parallel on all GPUs
    gpu_compute_harmonic_improper_forces(d_force.data,
                                         d_virial.data,
                                         pdata,
                                         box,
                                         gpu_impropertable,
                                         d_params.data,
                                         m_improper_data->getNDihedralTypes(),
                                         m_block_size);
    if (exec_conf->isCUDAErrorCheckingEnabled())
        CHECK_CUDA_ERROR();
     
    m_pdata->release();
    
    if (m_prof) m_prof->pop(exec_conf);
    }

void export_HarmonicImproperForceComputeGPU()
    {
    class_<HarmonicImproperForceComputeGPU, boost::shared_ptr<HarmonicImproperForceComputeGPU>, bases<HarmonicImproperForceCompute>, boost::noncopyable >
    ("HarmonicImproperForceComputeGPU", init< boost::shared_ptr<SystemDefinition> >())
    .def("setBlockSize", &HarmonicImproperForceComputeGPU::setBlockSize)
    ;
    }

