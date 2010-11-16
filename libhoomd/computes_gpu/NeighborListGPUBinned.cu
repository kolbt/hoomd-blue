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

// $Id$
// $URL$
// Maintainer: joaander

#include "NeighborListGPUBinned.cuh"

/*! \file NeighborListGPUBinned.cu
    \brief Defines GPU kernel code for O(N) neighbor list generation on the GPU
*/

//! Kernel call for generating neighbor list on the GPU
/*! \tparam filter_flags Set bit 1 to enable body filtering. Set bit 2 to enable diameter filtering.
    \param d_nlist Neighbor list data structure to write
    \param d_n_neigh Number of neighbors to write
    \param d_last_updated_pos Particle positions at this update are written to this array
    \param d_conditions Conditions array for writing overflow condition
    \param nli Indexer to access \a d_nlist
    \param d_pos Particle positions
    \param d_body Particle body indices
    \param d_diameter Particle diameters
    \param N Number of particles
    \param d_cell_size Number of particles in each cell
    \param d_cell_xyzf Cell contents (xyzf array from CellList with flag=type)
    \param d_cell_tdb Cell contents (tdb array from CellList with)
    \param d_cell_adj Cell adjacency list
    \param ci Cell indexer for indexing cells
    \param cli Cell list indexer for indexing into d_cell_xyzf
    \param cadji Adjacent cell indexer listing the 27 neighboring cells
    \param cell_scale Multiplication factor (in x, y, and z) which converts positions into cell coordinates
    \param cell_dim Dimensions of the cell list
    \param box Simulation box dimensions
    \param r_maxsq The maximum radius for which to include particles as neighbors, squared
    \param r_max The maximum radius for which to include particles as neighbors
    
    \note optimized for Fermi
*/
template<unsigned char filter_flags>
__global__ void gpu_compute_nlist_binned_new_kernel(unsigned int *d_nlist,
                                                    unsigned int *d_n_neigh,
                                                    float4 *d_last_updated_pos,
                                                    unsigned int *d_conditions,
                                                    const Index2D nli,
                                                    const float4 *d_pos,
                                                    const unsigned int *d_body,
                                                    const float *d_diameter,
                                                    const unsigned int N,
                                                    const unsigned int *d_cell_size,
                                                    const float4 *d_cell_xyzf,
                                                    const float4 *d_cell_tdb,
                                                    const unsigned int *d_cell_adj,
                                                    const Index3D ci,
                                                    const Index2D cli,
                                                    const Index2D cadji,
                                                    const float3 cell_scale,
                                                    const uint3 cell_dim,
                                                    const gpu_boxsize box,
                                                    const float r_maxsq,
                                                    const float r_max)
    {
    bool filter_body = filter_flags & 1;
    bool filter_diameter = filter_flags & 2;
    
    // each thread is going to compute the neighbor list for a single particle
    int my_pidx = blockDim.x * blockIdx.x + threadIdx.x;
    
    // quit early if we are past the end of the array
    if (my_pidx >= N)
        return;
    
    // first, determine which bin this particle belongs to
    float4 my_pos = d_pos[my_pidx];
    unsigned int my_body = d_body[my_pidx];
    float my_diameter = d_diameter[my_pidx];
    
    // FLOPS: 9
    unsigned int ib = (unsigned int)((my_pos.x+box.Lx/2.0f)*cell_scale.x);
    unsigned int jb = (unsigned int)((my_pos.y+box.Ly/2.0f)*cell_scale.y);
    unsigned int kb = (unsigned int)((my_pos.z+box.Lz/2.0f)*cell_scale.z);
    
    // need to handle the case where the particle is exactly at the box hi
    if (ib == cell_dim.x)
        ib = 0;
    if (jb == cell_dim.y)
        jb = 0;
    if (kb == cell_dim.z)
        kb = 0;
        
    int my_cell = ci(ib,jb,kb);
    
    // each thread will determine the neighborlist of a single particle
    // count number of neighbors found so far in n_neigh
    int n_neigh = 0;

    // loop over all adjacent bins
    for (unsigned int cur_adj = 0; cur_adj < cadji.getW(); cur_adj++)
        {
        int neigh_cell = d_cell_adj[cadji(cur_adj, my_cell)];
        unsigned int size = d_cell_size[neigh_cell];
        
        // now, we are set to loop through the array
        for (int cur_offset = 0; cur_offset < size; cur_offset++)
            {
            float4 cur_xyzf = d_cell_xyzf[cli(cur_offset, neigh_cell)];
            float4 cur_tdb = make_float4(0.0f, 0.0f, 0.0f, 0.0f);
            if (filter_diameter || filter_body)
                cur_tdb = d_cell_tdb[cli(cur_offset, neigh_cell)];
            unsigned int neigh_body = __float_as_int(cur_tdb.z);
            float neigh_diameter = cur_tdb.y;
                        
            float3 neigh_pos;
            neigh_pos.x = cur_xyzf.x;
            neigh_pos.y = cur_xyzf.y;
            neigh_pos.z = cur_xyzf.z;
            int cur_neigh = __float_as_int(cur_xyzf.w);
            
            // compute the distance between the two particles
            float dx = my_pos.x - neigh_pos.x;
            float dy = my_pos.y - neigh_pos.y;
            float dz = my_pos.z - neigh_pos.z;
            
            // wrap the periodic boundary conditions
            dx = dx - box.Lx * rintf(dx * box.Lxinv);
            dy = dy - box.Ly * rintf(dy * box.Lyinv);
            dz = dz - box.Lz * rintf(dz * box.Lzinv);
            
            // compute dr squared
            float drsq = dx*dx + dy*dy + dz*dz;
            
            bool excluded = (my_pidx == cur_neigh);
            
            if (filter_body && my_body != 0xffffffff)
                excluded = excluded | (my_body == neigh_body);
            
            float sqshift = 0.0f;
            if (filter_diameter)
                {
                // compute the shift in radius to accept neighbors based on their diameters
                float delta = (my_diameter + neigh_diameter) * 0.5f - 1.0f;
                // r^2 < (r_max + delta)^2
                // r^2 < r_maxsq + delta^2 + 2*r_max*delta
                sqshift = (delta + 2.0f * r_max) * delta;
                }

            if (drsq <= (r_maxsq + sqshift) && !excluded)
                {
                if (n_neigh < nli.getH())
                    d_nlist[nli(my_pidx, n_neigh)] = cur_neigh;
                else
                    atomicMax(&d_conditions[0], n_neigh+1);
                
                n_neigh++;
                }
            }
        }
    
    d_n_neigh[my_pidx] = n_neigh;
    d_last_updated_pos[my_pidx] = my_pos;
    }

cudaError_t gpu_compute_nlist_binned(unsigned int *d_nlist,
                                     unsigned int *d_n_neigh,
                                     float4 *d_last_updated_pos,
                                     unsigned int *d_conditions,
                                     const Index2D& nli,
                                     const float4 *d_pos,
                                     const unsigned int *d_body,
                                     const float *d_diameter,
                                     const unsigned int N,
                                     const unsigned int *d_cell_size,
                                     const float4 *d_cell_xyzf,
                                     const float4 *d_cell_tdb,
                                     const unsigned int *d_cell_adj,
                                     const Index3D& ci,
                                     const Index2D& cli,
                                     const Index2D& cadji,
                                     const float3& cell_scale,
                                     const uint3& cell_dim,
                                     const gpu_boxsize& box,
                                     const float r_maxsq,
                                     const unsigned int block_size,
                                     bool filter_body,
                                     bool filter_diameter)
    {
    int n_blocks = (int)ceil(float(N)/(float)block_size);
    if (!filter_diameter && !filter_body)
        {
        gpu_compute_nlist_binned_new_kernel<0><<<n_blocks, block_size>>>(d_nlist,
                                                                         d_n_neigh,
                                                                         d_last_updated_pos,
                                                                         d_conditions,
                                                                         nli,
                                                                         d_pos,
                                                                         d_body,
                                                                         d_diameter,
                                                                         N,
                                                                         d_cell_size,
                                                                         d_cell_xyzf,
                                                                         d_cell_tdb,
                                                                         d_cell_adj,
                                                                         ci,
                                                                         cli,
                                                                         cadji,
                                                                         cell_scale,
                                                                         cell_dim,
                                                                         box,
                                                                         r_maxsq,
                                                                         sqrtf(r_maxsq));
        }
    if (!filter_diameter && filter_body)
        {
        gpu_compute_nlist_binned_new_kernel<1><<<n_blocks, block_size>>>(d_nlist,
                                                                         d_n_neigh,
                                                                         d_last_updated_pos,
                                                                         d_conditions,
                                                                         nli,
                                                                         d_pos,
                                                                         d_body,
                                                                         d_diameter,
                                                                         N,
                                                                         d_cell_size,
                                                                         d_cell_xyzf,
                                                                         d_cell_tdb,
                                                                         d_cell_adj,
                                                                         ci,
                                                                         cli,
                                                                         cadji,
                                                                         cell_scale,
                                                                         cell_dim,
                                                                         box,
                                                                         r_maxsq,
                                                                         sqrtf(r_maxsq));
        }
    if (filter_diameter && !filter_body)
        {
        gpu_compute_nlist_binned_new_kernel<2><<<n_blocks, block_size>>>(d_nlist,
                                                                         d_n_neigh,
                                                                         d_last_updated_pos,
                                                                         d_conditions,
                                                                         nli,
                                                                         d_pos,
                                                                         d_body,
                                                                         d_diameter,
                                                                         N,
                                                                         d_cell_size,
                                                                         d_cell_xyzf,
                                                                         d_cell_tdb,
                                                                         d_cell_adj,
                                                                         ci,
                                                                         cli,
                                                                         cadji,
                                                                         cell_scale,
                                                                         cell_dim,
                                                                         box,
                                                                         r_maxsq,
                                                                         sqrtf(r_maxsq));
        }
    if (filter_diameter && filter_body)
        {
        gpu_compute_nlist_binned_new_kernel<3><<<n_blocks, block_size>>>(d_nlist,
                                                                         d_n_neigh,
                                                                         d_last_updated_pos,
                                                                         d_conditions,
                                                                         nli,
                                                                         d_pos,
                                                                         d_body,
                                                                         d_diameter,
                                                                         N,
                                                                         d_cell_size,
                                                                         d_cell_xyzf,
                                                                         d_cell_tdb,
                                                                         d_cell_adj,
                                                                         ci,
                                                                         cli,
                                                                         cadji,
                                                                         cell_scale,
                                                                         cell_dim,
                                                                         box,
                                                                         r_maxsq,
                                                                         sqrtf(r_maxsq));
        }

    return cudaSuccess;
    }

//! Texture for reading d_cell_adj
texture<unsigned int, 2, cudaReadModeElementType> cell_adj_tex;
//! Texture for reading d_cell_size
texture<unsigned int, 1, cudaReadModeElementType> cell_size_tex;
//! Texture for reading d_cell_xyzf
texture<float4, 2, cudaReadModeElementType> cell_xyzf_tex;
//! Texture for reading d_cell_tdb
texture<float4, 2, cudaReadModeElementType> cell_tdb_tex;

//! Kernel call for generating neighbor list on the GPU
/*! \tparam filter_flags Set bit 1 to enable body filtering. Set bit 2 to enable diameter filtering.
    \param d_nlist Neighbor list data structure to write
    \param d_n_neigh Number of neighbors to write
    \param d_last_updated_pos Particle positions at this update are written to this array
    \param d_conditions Conditions array for writing overflow condition
    \param nli Indexer to access \a d_nlist
    \param d_pos Particle positions
    \param d_body Particle body indices
    \param d_diameter Particle diameters
    \param N Number of particles
    \param ci Cell indexer for indexing cells
    \param cell_scale Multiplication factor (in x, y, and z) which converts positions into cell coordinates
    \param cell_dim Dimensions of the cell list
    \param box Simulation box dimensions
    \param r_maxsq The maximum radius for which to include particles as neighbors, squared
    \param r_max The maximum radius for which to include particles as neighbors
    
    \note optimized for compute 1.x devices
*/
template<unsigned char filter_flags>
__global__ void gpu_compute_nlist_binned_1x_kernel(unsigned int *d_nlist,
                                                   unsigned int *d_n_neigh,
                                                   float4 *d_last_updated_pos,
                                                   unsigned int *d_conditions,
                                                   const Index2D nli,
                                                   const float4 *d_pos,
                                                   const unsigned int *d_body,
                                                   const float *d_diameter,
                                                   const unsigned int N,
                                                   const Index3D ci,
                                                   const float3 cell_scale,
                                                   const uint3 cell_dim,
                                                   const gpu_boxsize box,
                                                   const float r_maxsq,
                                                   const float r_max)
    {
    bool filter_body = filter_flags & 1;
    bool filter_diameter = filter_flags & 2;
    
    // each thread is going to compute the neighbor list for a single particle
    int my_pidx = blockDim.x * blockIdx.x + threadIdx.x;
    
    // quit early if we are past the end of the array
    if (my_pidx >= N)
        return;
    
    // first, determine which bin this particle belongs to
    float4 my_pos = d_pos[my_pidx];
    unsigned int my_body = d_body[my_pidx];
    float my_diameter = d_diameter[my_pidx];

    // FLOPS: 9
    unsigned int ib = (unsigned int)((my_pos.x+box.Lx/2.0f)*cell_scale.x);
    unsigned int jb = (unsigned int)((my_pos.y+box.Ly/2.0f)*cell_scale.y);
    unsigned int kb = (unsigned int)((my_pos.z+box.Lz/2.0f)*cell_scale.z);
    
    // need to handle the case where the particle is exactly at the box hi
    if (ib == cell_dim.x)
        ib = 0;
    if (jb == cell_dim.y)
        jb = 0;
    if (kb == cell_dim.z)
        kb = 0;
        
    int my_cell = ci(ib,jb,kb);
    
    // each thread will determine the neighborlist of a single particle
    // count number of neighbors found so far in n_neigh
    int n_neigh = 0;

    // loop over all adjacent bins
    for (unsigned int cur_adj = 0; cur_adj < 27; cur_adj++)
        {
        int neigh_cell = tex2D(cell_adj_tex, cur_adj, my_cell);
        unsigned int size = tex1Dfetch(cell_size_tex, neigh_cell);
        
        float4 next_xyzf = tex2D(cell_xyzf_tex, 0, neigh_cell);

        // now, we are set to loop through the array
        for (int cur_offset = 0; cur_offset < size; cur_offset++)
            {
            float4 cur_xyzf = next_xyzf;
            next_xyzf = tex2D(cell_xyzf_tex, cur_offset+1, neigh_cell);
            float4 cur_tdb = make_float4(0.0f, 0.0f, 0.0f, 0.0f);
            if (filter_diameter || filter_body)
                cur_tdb = tex2D(cell_tdb_tex, cur_offset, neigh_cell);
            unsigned int neigh_body = __float_as_int(cur_tdb.z);
            float neigh_diameter = cur_tdb.y;

            float3 neigh_pos;
            neigh_pos.x = cur_xyzf.x;
            neigh_pos.y = cur_xyzf.y;
            neigh_pos.z = cur_xyzf.z;
            int cur_neigh = __float_as_int(cur_xyzf.w);
            
            // compute the distance between the two particles
            float dx = my_pos.x - neigh_pos.x;
            float dy = my_pos.y - neigh_pos.y;
            float dz = my_pos.z - neigh_pos.z;
            
            // wrap the periodic boundary conditions
            dx = dx - box.Lx * rintf(dx * box.Lxinv);
            dy = dy - box.Ly * rintf(dy * box.Lyinv);
            dz = dz - box.Lz * rintf(dz * box.Lzinv);
            
            // compute dr squared
            float drsq = dx*dx + dy*dy + dz*dz;
            
            bool excluded = (my_pidx == cur_neigh);
            
            if (filter_body && my_body != 0xffffffff)
                excluded = excluded | (my_body == neigh_body);
            
            float sqshift = 0.0f;
            if (filter_diameter)
                {
                // compute the shift in radius to accept neighbors based on their diameters
                float delta = (my_diameter + neigh_diameter) * 0.5f - 1.0f;
                // r^2 < (r_max + delta)^2
                // r^2 < r_maxsq + delta^2 + 2*r_max*delta
                sqshift = (delta + 2.0f * r_max) * delta;
                }

            if (drsq <= (r_maxsq + sqshift) && !excluded)
                {
                if (n_neigh < nli.getH())
                    d_nlist[nli(my_pidx, n_neigh)] = cur_neigh;
                else
                    atomicMax(&d_conditions[0], n_neigh+1);
                
                n_neigh++;
                }
            }
        }
    
    d_n_neigh[my_pidx] = n_neigh;
    d_last_updated_pos[my_pidx] = my_pos;
    }

cudaError_t gpu_compute_nlist_binned_1x(unsigned int *d_nlist,
                                        unsigned int *d_n_neigh,
                                        float4 *d_last_updated_pos,
                                        unsigned int *d_conditions,
                                        const Index2D& nli,
                                        const float4 *d_pos,
                                        const unsigned int *d_body,
                                        const float *d_diameter,
                                        const unsigned int N,
                                        const unsigned int *d_cell_size,
                                        const cudaArray *dca_cell_xyzf,
                                        const cudaArray *dca_cell_tdb,
                                        const cudaArray *dca_cell_adj,
                                        const Index3D& ci,
                                        const float3& cell_scale,
                                        const uint3& cell_dim,
                                        const gpu_boxsize& box,
                                        const float r_maxsq,
                                        const unsigned int block_size,
                                        bool filter_body,
                                        bool filter_diameter)
    {
    int n_blocks = (int)ceil(float(N)/(float)block_size);
    
    cudaError_t err = cudaBindTextureToArray(cell_adj_tex, dca_cell_adj);
    if (err != cudaSuccess)
        return err;
    
    err = cudaBindTextureToArray(cell_xyzf_tex, dca_cell_xyzf);
    if (err != cudaSuccess)
        return err;
    
    err = cudaBindTextureToArray(cell_tdb_tex, dca_cell_tdb);
    if (err != cudaSuccess)
        return err;
    
    err = cudaBindTexture(0, cell_size_tex, d_cell_size, sizeof(unsigned int)*cell_dim.x*cell_dim.y*cell_dim.z);
    if (err != cudaSuccess)
        return err;
    
    if (!filter_diameter && !filter_body)
        {
        gpu_compute_nlist_binned_1x_kernel<0><<<n_blocks, block_size>>>(d_nlist,
                                                                        d_n_neigh,
                                                                        d_last_updated_pos,
                                                                        d_conditions,
                                                                        nli,
                                                                        d_pos,
                                                                        d_body,
                                                                        d_diameter,
                                                                        N,
                                                                        ci,
                                                                        cell_scale,
                                                                        cell_dim,
                                                                        box,
                                                                        r_maxsq,
                                                                        sqrtf(r_maxsq));
        }
    if (!filter_diameter && filter_body)
        {
        gpu_compute_nlist_binned_1x_kernel<1><<<n_blocks, block_size>>>(d_nlist,
                                                                        d_n_neigh,
                                                                        d_last_updated_pos,
                                                                        d_conditions,
                                                                        nli,
                                                                        d_pos,
                                                                        d_body,
                                                                        d_diameter,
                                                                        N,
                                                                        ci,
                                                                        cell_scale,
                                                                        cell_dim,
                                                                        box,
                                                                        r_maxsq,
                                                                        sqrtf(r_maxsq));
        }
    if (filter_diameter && !filter_body)
        {
        gpu_compute_nlist_binned_1x_kernel<2><<<n_blocks, block_size>>>(d_nlist,
                                                                        d_n_neigh,
                                                                        d_last_updated_pos,
                                                                        d_conditions,
                                                                        nli,
                                                                        d_pos,
                                                                        d_body,
                                                                        d_diameter,
                                                                        N,
                                                                        ci,
                                                                        cell_scale,
                                                                        cell_dim,
                                                                        box,
                                                                        r_maxsq,
                                                                        sqrtf(r_maxsq));
        }
    if (filter_diameter && filter_body)
        {
        gpu_compute_nlist_binned_1x_kernel<3><<<n_blocks, block_size>>>(d_nlist,
                                                                        d_n_neigh,
                                                                        d_last_updated_pos,
                                                                        d_conditions,
                                                                        nli,
                                                                        d_pos,
                                                                        d_body,
                                                                        d_diameter,
                                                                        N,
                                                                        ci,
                                                                        cell_scale,
                                                                        cell_dim,
                                                                        box,
                                                                        r_maxsq,
                                                                        sqrtf(r_maxsq));
        }
    return cudaSuccess;
    }

/*! Call this method once at initialization. It specifies that gpu_compute_nlist_binned_new_kernel() utilize the 48k
    L1 cache on Fermi.
*/
cudaError_t gpu_setup_compute_nlist_binned()
    {
    cudaError_t error;
    error = cudaFuncSetCacheConfig(gpu_compute_nlist_binned_new_kernel<0>, cudaFuncCachePreferL1);
    if (error != cudaSuccess)
        return error;
    error = cudaFuncSetCacheConfig(gpu_compute_nlist_binned_new_kernel<1>, cudaFuncCachePreferL1);
    if (error != cudaSuccess)
        return error;
    error = cudaFuncSetCacheConfig(gpu_compute_nlist_binned_new_kernel<2>, cudaFuncCachePreferL1);
    if (error != cudaSuccess)
        return error;
    error = cudaFuncSetCacheConfig(gpu_compute_nlist_binned_new_kernel<3>, cudaFuncCachePreferL1);
    return error;
    }

