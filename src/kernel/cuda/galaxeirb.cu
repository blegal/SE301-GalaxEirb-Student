/*
 *  Copyright (c) 2022 Bertrand LE GAL
 *
 *  This software is provided 'as-is', without any express or
 *  implied warranty. In no event will the authors be held
 *  liable for any damages arising from the use of this software.
 *
 *  Permission is granted to anyone to use this software for any purpose,
 *  including commercial applications, and to alter it and redistribute
 *  it freely, subject to the following restrictions:
 *
 *  1. The origin of this software must not be misrepresented;
 *  you must not claim that you wrote the original software.
 *  If you use this software in a product, an acknowledgment
 *  in the product documentation would be appreciated but
 *  is not required.
 *
 *  2. Altered source versions must be plainly marked as such,
 *  and must not be misrepresented as being the original software.
 *
 *  3. This notice may not be removed or altered from any
 *  source distribution.
 *
 */
#include <stdio.h>
#include <cuda_runtime.h>
/*
 *
 *
 *##############################################################################
 *
 *
 */
#if defined(__NVCC__)
#define THREADGROUP_SIZE 256
#define BSIZE 256 			   // Block size in # of threads
#define softeningSquared 0.01f // original plumer softener is 0.025. here the value is square of it.
#define damping          1.00f // 0.999f
#define ep               0.67f // 0.5f
/*
 *
 *
 *##############################################################################
 *
 *
 */
 __global__ void body2Body_copy(
              float4* c_pos,
        const float4* n_pos,
        const float4* v_dat,
        const int   nElements)
{
    int particule_id = blockDim.x * blockIdx.x + threadIdx.x;
    
    if( particule_id < nElements )
    {
        const float4 newPos   = n_pos[ particule_id ];
        c_pos[ particule_id ] = newPos;
    }
}
/*
 *
 *
 *##############################################################################
 *
 *
 */
__global__ void body2Body_exec(
        const float4* c_pos,
              float4* n_pos,
              float4* v_dat,
        const int     nElements)
{

    extern __shared__ float4 shPosition[THREADGROUP_SIZE];

    const int tid          = threadIdx.x;
    const int particule_id = blockIdx.x * blockDim.x + threadIdx.x;

    //
    // Si jamais a cause des threads/grilles ont deborde...
    //

    if (particule_id < nElements)
    {
        //
        // Dans le cas contraire on commence notre calcul !
        //

        float4 myPosition = c_pos[ particule_id ];

        //
        //
        //

//        float4 myVelocity = v_dat[ particule_id ];
        float3 myAccel = {0.f, 0.f, 0.f};

        for (int idx = 0; idx < nElements; idx += blockDim.x)
        {

            shPosition[tid] = c_pos[idx + tid];

            __syncthreads();

            #pragma unroll 4
            for (uint p = 0; p < blockDim.x; p += 1)
            {

                const float4 other = shPosition[p];
                
                float rx = other.x - myPosition.x;
                float ry = other.y - myPosition.y;
                float rz = other.z - myPosition.z;

                float d = (rx * rx) + (ry * ry) + (rz * rz);
                
                float d3  = 10.0f * other.w;
                float div = (sqrt(d) * d);
                if ( d > 1.0f )
                {
                    d3 /= div; // Multi modifiable
                }

                myAccel.x += rx * d3;
                myAccel.y += ry * d3;
                myAccel.z += rz * d3;
            }

            __syncthreads();

        }

        //
        // update position
        //

        __syncthreads();

        float4 myVelocity = v_dat[ particule_id ];
        myVelocity.x += myAccel.x * 2.0f;
        myVelocity.y += myAccel.y * 2.0f;
        myVelocity.z += myAccel.z * 2.0f;

        myPosition.x = myPosition.x + (myVelocity.x * 0.01f);
        myPosition.y = myPosition.y + (myVelocity.y * 0.01f);
        myPosition.z = myPosition.z + (myVelocity.z * 0.01f);

        __syncthreads();

        //
        // update device memory
        //
        
        n_pos[ particule_id ] = myPosition;     // NEXT POSITION !
        v_dat[ particule_id ] = myVelocity;     // NEW  VELOCITY !
    }

        __syncthreads();
}

#endif