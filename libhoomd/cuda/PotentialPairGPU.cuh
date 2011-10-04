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

#include "HOOMDMath.h"
#include "ParticleData.cuh"
#include "Index1D.h"

#ifdef WIN32
#include <cassert>
#else
#include <assert.h>
#endif

/*! \file PotentialPairGPU.cuh
    \brief Defines templated GPU kernel code for calculating the pair forces.
*/

#ifndef __POTENTIAL_PAIR_GPU_CUH__
#define __POTENTIAL_PAIR_GPU_CUH__

//! Wrapps arguments to gpu_cgpf
struct pair_args_t
    {
    //! Construct a pair_args_t
    pair_args_t(float4 *_d_force,
              float *_d_virial,
              const gpu_pdata_arrays& _pdata,
              const gpu_boxsize &_box,
              const unsigned int *_d_n_neigh,
              const unsigned int *_d_nlist,
              const Index2D& _nli,
              const float *_d_rcutsq, 
              const float *_d_ronsq,
              const unsigned int _ntypes,
              const unsigned int _block_size,
              const unsigned int _shift_mode)
                : d_force(_d_force),
                  d_virial(_d_virial),
                  pdata(_pdata),
                  box(_box),
                  d_n_neigh(_d_n_neigh),
                  d_nlist(_d_nlist),
                  nli(_nli),
                  d_rcutsq(_d_rcutsq),
                  d_ronsq(_d_ronsq),
                  ntypes(_ntypes),
                  block_size(_block_size),
                  shift_mode(_shift_mode)
        {
        };

    float4 *d_force;                //!< Force to write out
    float *d_virial;                //!< Virial to write out
    const gpu_pdata_arrays& pdata;  //!< Particle data to compute forces over
    const gpu_boxsize &box;         //!< Simulation box in GPU format
    const unsigned int *d_n_neigh;  //!< Device array listing the number of neighbors on each particle
    const unsigned int *d_nlist;    //!< Device array listing the neighbors of each particle
    const Index2D& nli;             //!< Indexer for accessing d_nlist
    const float *d_rcutsq;          //!< Device array listing r_cut squared per particle type pair
    const float *d_ronsq;           //!< Device array listing r_on squared per particle type pair
    const unsigned int ntypes;      //!< Number of particle types in the simulation
    const unsigned int block_size;  //!< Block size to execute
    const unsigned int shift_mode;  //!< The potential energy shift mode
    };

#ifdef NVCC
//! Texture for reading particle positions
texture<float4, 1, cudaReadModeElementType> pdata_pos_tex;

//! Texture for reading particle diameters
texture<float, 1, cudaReadModeElementType> pdata_diam_tex;

//! Texture for reading particle charges
texture<float, 1, cudaReadModeElementType> pdata_charge_tex;

//! Kernel for calculating pair forces
/*! This kernel is called to calculate the pair forces on all N particles. Actual evaluation of the potentials and 
    forces for each pair is handled via the template class \a evaluator.

    \param d_force Device memory to write computed forces
    \param d_virial Device memory to write computed virials
    \param pdata Particle data on the GPU to calculate forces on
    \param box Box dimensions used to implement periodic boundary conditions
    \param d_n_neigh Device memory array listing the number of neighbors for each particle
    \param d_nlist Device memory array containing the neighbor list contents
    \param nli Indexer for indexing \a d_nlist
    \param d_params Parameters for the potential, stored per type pair
    \param d_rcutsq rcut squared, stored per type pair
    \param d_ronsq ron squared, stored per type pair
    \param ntypes Number of types in the simulation
    
    \a d_params, \a d_rcutsq, and \a d_ronsq must be indexed with an Index2DUpperTriangler(typei, typej) to access the
    unique value for that type pair. These values are all cached into shared memory for quick access, so a dynamic
    amount of shared memory must be allocatd for this kernel launch. The amount is
    (2*sizeof(float) + sizeof(typename evaluator::param_type)) * typpair_idx.getNumElements()
    
    Certain options are controlled via template parameters to avoid the performance hit when they are not enabled.
    \tparam evaluator EvaluatorPair class to evualuate V(r) and -delta V(r)/r
    \tparam shift_mode 0: No energy shifting is done. 1: V(r) is shifted to be 0 at rcut. 2: XPLOR switching is enabled
                       (See PotentialPair for a discussion on what that entails)
    
    <b>Implementation details</b>
    Each block will calculate the forces on a block of particles.
    Each thread will calculate the total force on one particle.
    The neighborlist is arranged in columns so that reads are fully coalesced when doing this.
*/
template< class evaluator, unsigned int shift_mode >
__global__ void gpu_compute_pair_forces_kernel(float4 *d_force,
                                               float *d_virial,
                                               const gpu_pdata_arrays pdata,
                                               const gpu_boxsize box,
                                               const unsigned int *d_n_neigh,
                                               const unsigned int *d_nlist,
                                               const Index2D nli,
                                               const typename evaluator::param_type *d_params,
                                               const float *d_rcutsq,
                                               const float *d_ronsq,
                                               const unsigned int ntypes)
    {
    Index2D typpair_idx(ntypes);
    const unsigned int num_typ_parameters = typpair_idx.getNumElements();

    // shared arrays for per type pair parameters
    extern __shared__ char s_data[];
    typename evaluator::param_type *s_params = 
        (typename evaluator::param_type *)(&s_data[0]);
    float *s_rcutsq = (float *)(&s_data[num_typ_parameters*sizeof(evaluator::param_type)]);
    float *s_ronsq = (float *)(&s_data[num_typ_parameters*(sizeof(evaluator::param_type) + sizeof(float))]);
    
    // load in the per type pair parameters
    for (unsigned int cur_offset = 0; cur_offset < num_typ_parameters; cur_offset += blockDim.x)
        {
        if (cur_offset + threadIdx.x < num_typ_parameters)
            {
            s_rcutsq[cur_offset + threadIdx.x] = d_rcutsq[cur_offset + threadIdx.x];
            s_params[cur_offset + threadIdx.x] = d_params[cur_offset + threadIdx.x];
            if (shift_mode == 2)
                s_ronsq[cur_offset + threadIdx.x] = d_ronsq[cur_offset + threadIdx.x];
            }
        }
    __syncthreads();
    
    // start by identifying which particle we are to handle
    unsigned int idx = blockIdx.x * blockDim.x + threadIdx.x;
    
    if (idx >= pdata.N)
        return;
        
    // load in the length of the neighbor list (MEM_TRANSFER: 4 bytes)
    unsigned int n_neigh = d_n_neigh[idx];
    
    // read in the position of our particle. Texture reads of float4's are faster than global reads on compute 1.0 hardware
    // (MEM TRANSFER: 16 bytes)
    float4 posi = tex1Dfetch(pdata_pos_tex, idx);
    
    float di;
    if (evaluator::needsDiameter())
        di = tex1Dfetch(pdata_diam_tex, idx);
    else
        di += 1.0f; // shutup compiler warning
    float qi;
    if (evaluator::needsCharge())
        qi = tex1Dfetch(pdata_charge_tex, idx);
    else
        qi += 1.0f; // shutup compiler warning
    
        
    // initialize the force to 0
    float4 force = make_float4(0.0f, 0.0f, 0.0f, 0.0f);
    float virial = 0.0f;
    
    // prefetch neighbor index
    unsigned int cur_j = 0;
    unsigned int next_j = d_nlist[nli(idx, 0)];
    
    // loop over neighbors
    // on pre Fermi hardware, there is a bug that causes rare and random ULFs when simply looping over n_neigh
    // the workaround (activated via the template paramter) is to loop over nlist.height and put an if (i < n_neigh)
    // inside the loop
    #if (__CUDA_ARCH__ < 200)
    for (int neigh_idx = 0; neigh_idx < nli.getH(); neigh_idx++)
    #else
    for (int neigh_idx = 0; neigh_idx < n_neigh; neigh_idx++)
    #endif
        {
        #if (__CUDA_ARCH__ < 200)
        if (neigh_idx < n_neigh)
        #endif
            {
            // read the current neighbor index (MEM TRANSFER: 4 bytes)
            // prefetch the next value and set the current one
            cur_j = next_j;
            next_j = d_nlist[nli(idx, neigh_idx+1)];
            
            // get the neighbor's position (MEM TRANSFER: 16 bytes)
            float4 posj = tex1Dfetch(pdata_pos_tex, cur_j);
            
            float dj = 0.0f;
            if (evaluator::needsDiameter())
                dj = tex1Dfetch(pdata_diam_tex, cur_j);
            else
                dj += 1.0f; // shutup compiler warning
                
            float qj = 0.0f;
            if (evaluator::needsCharge())
                qj = tex1Dfetch(pdata_charge_tex, cur_j);
            else
                qj += 1.0f; // shutup compiler warning
                
            // calculate dr (with periodic boundary conditions) (FLOPS: 3)
            float dx = posi.x - posj.x;
            float dy = posi.y - posj.y;
            float dz = posi.z - posj.z;
            
            // apply periodic boundary conditions: (FLOPS 12)
            dx -= box.Lx * rintf(dx * box.Lxinv);
            dy -= box.Ly * rintf(dy * box.Lyinv);
            dz -= box.Lz * rintf(dz * box.Lzinv);
            
            // calculate r squard (FLOPS: 5)
            float rsq = dx*dx + dy*dy + dz*dz;
            
            // access the per type pair parameters
            unsigned int typpair = typpair_idx(__float_as_int(posi.w), __float_as_int(posj.w));
            float rcutsq = s_rcutsq[typpair];
            typename evaluator::param_type param = s_params[typpair];
            float ronsq = 0.0f;
            if (shift_mode == 2)
                ronsq = s_ronsq[typpair];
            
            // design specifies that energies are shifted if
            // 1) shift mode is set to shift
            // or 2) shift mode is explor and ron > rcut
            bool energy_shift = false;
            if (shift_mode == 1)
                energy_shift = true;
            else if (shift_mode == 2)
                {
                if (ronsq > rcutsq)
                    energy_shift = true;
                }
            
            // evaluate the potential
            float force_divr = 0.0f;
            float pair_eng = 0.0f;
            
            evaluator eval(rsq, rcutsq, param);
            if (evaluator::needsDiameter())
                eval.setDiameter(di, dj);
            if (evaluator::needsCharge())
                eval.setCharge(qi, qj);
            
            eval.evalForceAndEnergy(force_divr, pair_eng, energy_shift);
            
            if (shift_mode == 2)
                {
                if (rsq >= ronsq && rsq < rcutsq)
                    {
                    // Implement XPLOR smoothing (FLOPS: 16)
                    Scalar old_pair_eng = pair_eng;
                    Scalar old_force_divr = force_divr;
                    
                    // calculate 1.0 / (xplor denominator)
                    Scalar xplor_denom_inv =
                        Scalar(1.0) / ((rcutsq - ronsq) * (rcutsq - ronsq) * (rcutsq - ronsq));
                    
                    Scalar rsq_minus_r_cut_sq = rsq - rcutsq;
                    Scalar s = rsq_minus_r_cut_sq * rsq_minus_r_cut_sq *
                               (rcutsq + Scalar(2.0) * rsq - Scalar(3.0) * ronsq) * xplor_denom_inv;
                    Scalar ds_dr_divr = Scalar(12.0) * (rsq - ronsq) * rsq_minus_r_cut_sq * xplor_denom_inv;
                    
                    // make modifications to the old pair energy and force
                    pair_eng = old_pair_eng * s;
                    force_divr = s * old_force_divr - ds_dr_divr * old_pair_eng;
                    }
                }
            
            // calculate the virial (FLOPS: 3)
            virial += float(1.0/6.0) * rsq * force_divr;
            
            // add up the force vector components (FLOPS: 7)
            #if (__CUDA_ARCH__ >= 200)
            force.x += dx * force_divr;
            force.y += dy * force_divr;
            force.z += dz * force_divr;
            #else
            // fmad causes momentum drift here, prevent it from being used
            force.x += __fmul_rn(dx, force_divr);
            force.y += __fmul_rn(dy, force_divr);
            force.z += __fmul_rn(dz, force_divr);
            #endif
            
            force.w += pair_eng;
            }
        }
        
    // potential energy per particle must be halved
    force.w *= 0.5f;
    // now that the force calculation is complete, write out the result (MEM TRANSFER: 20 bytes)
    d_force[idx] = force;
    d_virial[idx] = virial;
    }

//! Kernel driver that computes lj forces on the GPU for LJForceComputeGPU
/*! \param pair_args Other arugments to pass onto the kernel
    \param d_params Parameters for the potential, stored per type pair
    
    This is just a driver function for gpu_compute_pair_forces_kernel(), see it for details.
*/
template< class evaluator >
cudaError_t gpu_compute_pair_forces(const pair_args_t& pair_args,
                                    const typename evaluator::param_type *d_params)
    {
    assert(d_params);
    assert(pair_args.d_rcutsq);
    assert(pair_args.d_ronsq);
    assert(pair_args.ntypes > 0);
    
    // setup the grid to run the kernel
    dim3 grid( pair_args.pdata.N / pair_args.block_size + 1, 1, 1);
    dim3 threads(pair_args.block_size, 1, 1);
    
    // bind the position texture
    pdata_pos_tex.normalized = false;
    pdata_pos_tex.filterMode = cudaFilterModePoint;
    cudaError_t error = cudaBindTexture(0, pdata_pos_tex, pair_args.pdata.pos, sizeof(float4) * pair_args.pdata.N);
    if (error != cudaSuccess)
        return error;

    // bind the diamter texture
    pdata_diam_tex.normalized = false;
    pdata_diam_tex.filterMode = cudaFilterModePoint;
    error = cudaBindTexture(0, pdata_diam_tex, pair_args.pdata.diameter, sizeof(float) * pair_args.pdata.N);
    if (error != cudaSuccess)
        return error;
    
    pdata_charge_tex.normalized = false;
    pdata_charge_tex.filterMode = cudaFilterModePoint;
    error = cudaBindTexture(0, pdata_charge_tex, pair_args.pdata.charge, sizeof(float) * pair_args.pdata.N);
    if (error != cudaSuccess)
        return error;
    
    Index2D typpair_idx(pair_args.ntypes);
    unsigned int shared_bytes = (2*sizeof(float) + sizeof(typename evaluator::param_type)) 
                                * typpair_idx.getNumElements();
    
    // run the kernel
    switch (pair_args.shift_mode)
        {
        case 0:
            gpu_compute_pair_forces_kernel<evaluator, 0>
              <<<grid, threads, shared_bytes>>>(pair_args.d_force, pair_args.d_virial, pair_args.pdata, pair_args.box, pair_args.d_n_neigh, pair_args.d_nlist, pair_args.nli, d_params, pair_args.d_rcutsq, pair_args.d_ronsq, pair_args.ntypes);
            break;
        case 1:
            gpu_compute_pair_forces_kernel<evaluator, 1>
              <<<grid, threads, shared_bytes>>>(pair_args.d_force, pair_args.d_virial, pair_args.pdata, pair_args.box, pair_args.d_n_neigh, pair_args.d_nlist, pair_args.nli, d_params, pair_args.d_rcutsq, pair_args.d_ronsq, pair_args.ntypes);
            break;
        case 2:
            gpu_compute_pair_forces_kernel<evaluator, 2>
              <<<grid, threads, shared_bytes>>>(pair_args.d_force, pair_args.d_virial, pair_args.pdata, pair_args.box, pair_args.d_n_neigh, pair_args.d_nlist, pair_args.nli, d_params, pair_args.d_rcutsq, pair_args.d_ronsq, pair_args.ntypes);
            break;
        default:
            return cudaErrorUnknown;
        }
        
    return cudaSuccess;
    }
#endif

#endif // __POTENTIAL_PAIR_GPU_CUH__

