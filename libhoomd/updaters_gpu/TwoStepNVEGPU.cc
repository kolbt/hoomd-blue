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

// Maintainer: joaander

#ifdef WIN32
#pragma warning( push )
#pragma warning( disable : 4244 )
#endif

#include <boost/python.hpp>
using namespace boost::python;
#include <boost/bind.hpp>
using namespace boost;

#include "TwoStepNVEGPU.h"
#include "TwoStepNVEGPU.cuh"

/*! \file TwoStepNVEGPU.h
    \brief Contains code for the TwoStepNVEGPU class
*/

/*! \param sysdef SystemDefinition this method will act on. Must not be NULL.
    \param group The group of particles this integration method is to work on
*/
TwoStepNVEGPU::TwoStepNVEGPU(boost::shared_ptr<SystemDefinition> sysdef,
                             boost::shared_ptr<ParticleGroup> group)
    : TwoStepNVE(sysdef, group)
    {
    // only one GPU is supported
    if (!exec_conf->isCUDAEnabled())
        {
        cerr << endl << "***Error! Creating a TwoStepNVEGPU when CUDA is disabled" << endl << endl;
        throw std::runtime_error("Error initializing TwoStepNVEGPU");
        }
    }

/*! \param timestep Current time step
    \post Particle positions are moved forward to timestep+1 and velocities to timestep+1/2 per the velocity verlet
          method.
*/
void TwoStepNVEGPU::integrateStepOne(unsigned int timestep)
    {
    unsigned int group_size = m_group->getNumMembers();
    if (group_size == 0)
        return;
    
    // profile this step
    if (m_prof)
        m_prof->push(exec_conf, "NVE step 1");
    
    // access all the needed data
    gpu_pdata_arrays& d_pdata = m_pdata->acquireReadWriteGPU();
    gpu_boxsize box = m_pdata->getBoxGPU();
    ArrayHandle< unsigned int > d_index_array(m_group->getIndexArray(), access_location::device, access_mode::read);

    // perform the update on the GPU
    gpu_nve_step_one(d_pdata,
                     d_index_array.data,
                     group_size,
                     box,
                     m_deltaT,
                     m_limit,
                     m_limit_val,
                     m_zero_force);

    if (exec_conf->isCUDAErrorCheckingEnabled())
        CHECK_CUDA_ERROR();
    
    m_pdata->release();
    
    // done profiling
    if (m_prof)
        m_prof->pop(exec_conf);
    }
        
/*! \param timestep Current time step
    \post particle velocities are moved forward to timestep+1 on the GPU
*/
void TwoStepNVEGPU::integrateStepTwo(unsigned int timestep)
    {
    unsigned int group_size = m_group->getNumMembers();
    if (group_size == 0)
        return;
    
    const GPUArray< Scalar4 >& net_force = m_pdata->getNetForce();
    
    // profile this step
    if (m_prof)
        m_prof->push(exec_conf, "NVE step 2");
    
    gpu_pdata_arrays& d_pdata = m_pdata->acquireReadWriteGPU();
    ArrayHandle<Scalar4> d_net_force(net_force, access_location::device, access_mode::read);
    ArrayHandle< unsigned int > d_index_array(m_group->getIndexArray(), access_location::device, access_mode::read);

    // perform the update on the GPU
    gpu_nve_step_two(d_pdata,
                     d_index_array.data,
                     group_size,
                     d_net_force.data,
                     m_deltaT,
                     m_limit,
                     m_limit_val,
                     m_zero_force);

    if (exec_conf->isCUDAErrorCheckingEnabled())
        CHECK_CUDA_ERROR();
    
    m_pdata->release();
    
    // done profiling
    if (m_prof)
        m_prof->pop(exec_conf);
    }

void export_TwoStepNVEGPU()
    {
    class_<TwoStepNVEGPU, boost::shared_ptr<TwoStepNVEGPU>, bases<TwoStepNVE>, boost::noncopyable>
        ("TwoStepNVEGPU", init< boost::shared_ptr<SystemDefinition>, boost::shared_ptr<ParticleGroup> >())
        ;
    }

#ifdef WIN32
#pragma warning( pop )
#endif

