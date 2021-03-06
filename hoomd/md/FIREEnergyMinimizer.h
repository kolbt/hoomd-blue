// Copyright (c) 2009-2017 The Regents of the University of Michigan
// This file is part of the HOOMD-blue project, released under the BSD 3-Clause License.


// Maintainer: askeys

#include "IntegratorTwoStep.h"

#include <memory>

#ifndef __FIRE_ENERGY_MINIMIZER_H__
#define __FIRE_ENERGY_MINIMIZER_H__

/*! \file FIREEnergyMinimizer.h
    \brief Declares the FIRE energy minimizer class
*/

#ifdef NVCC
#error This header cannot be compiled by nvcc
#endif

#include <hoomd/extern/pybind/include/pybind11/pybind11.h>

//! Finds the nearest basin in the potential energy landscape
/*! \b Overview

    \ingroup updaters
*/
class FIREEnergyMinimizer : public IntegratorTwoStep
    {
    public:
        //! Constructs the minimizer and associates it with the system
        FIREEnergyMinimizer(std::shared_ptr<SystemDefinition>,  std::shared_ptr<ParticleGroup>, Scalar, bool=true);
        virtual ~FIREEnergyMinimizer();

        //! Reset the minimization
        virtual void reset();

        //! Set the timestep
        virtual void setDeltaT(Scalar);

        //! Perform one minimization iteration
        virtual void update(unsigned int);

        //! Return whether or not the minimization has converged
        bool hasConverged() const {return m_converged;}

        //! Set the minimum number of steps for which the search direction must be bad before finding a new direction
        /*! \param nmin is the new nmin to set
        */
        void setNmin(unsigned int nmin) {m_nmin = nmin;}

        //! Set the fractional increase in the timestep upon a valid search direction
        void setFinc(Scalar finc);

        //! Set the fractional increase in the timestep upon a valid search direction
        void setFdec(Scalar fdec);

        //! Set the relative strength of the coupling between the "f dot v" vs the "v" term
        void setAlphaStart(Scalar alpha0);

        //! Set the fractional decrease in alpha upon finding a valid search direction
        void setFalpha(Scalar falpha);

        //! Set the stopping criterion based on the total force on all particles in the system
        /*! \param ftol is the new force tolerance to set
        */
        void setFtol(Scalar ftol) {m_ftol = ftol;}

        //! Set the stopping criterion based on the change in energy between successive iterations
        /*! \param etol is the new energy tolerance to set
        */
        void setEtol(Scalar etol) {m_etol = etol;}

        //! Set the a minimum number of steps before the other stopping criteria will be evaluated
        /*! \param steps is the minimum number of steps (attempts) that will be made
        */
        void setMinSteps(unsigned int steps) {m_run_minsteps = steps;}

        //! Access the group
        std::shared_ptr<ParticleGroup> getGroup() { return m_group; }

        //! Get needed pdata flags
        /*! FIREEnergyMinimzer needs the potential energy, so its flag is set
        */
        virtual PDataFlags getRequestedPDataFlags()
            {
            PDataFlags flags;
            flags[pdata_flag::potential_energy] = 1;
            return flags;
            }

    protected:
        //! Function to create the underlying integrator
        //virtual void createIntegrator();
        const std::shared_ptr<ParticleGroup> m_group;     //!< The group of particles this method works on
        unsigned int m_nmin;                //!< minimum number of consecutive successful search directions before modifying alpha
        unsigned int m_n_since_negative;    //!< counts the number of consecutive successful search directions
        unsigned int m_n_since_start;       //!< counts the number of consecutvie search attempts
        Scalar m_finc;                      //!< fractional increase in timestep upon successful seach
        Scalar m_fdec;                      //!< fractional decrease in timestep upon unsuccessful seach
        Scalar m_alpha;                     //!< relative coupling strength between alpha
        Scalar m_alpha_start;               //!< starting value of alpha
        Scalar m_falpha;                    //!< fraction to rescale alpha on successful search direction
        Scalar m_ftol;                      //!< stopping tolerance based on total force
        Scalar m_etol;                      //!< stopping tolerance based on the chance in energy
        Scalar m_old_energy;                //!< energy from the previous iteration
        bool m_converged;                   //!< whether the minimization has converged
        Scalar m_deltaT_max;                //!< maximum timesteps after rescaling (set by user)
        Scalar m_deltaT_set;                //!< the initial timestep
        unsigned int m_run_minsteps;        //!< A minimum number of seach attempts the search will use
        bool m_was_reset;                   //!< whether or not the minimizer was reset

    private:

    };

//! Exports the FIREEnergyMinimizer class to python
void export_FIREEnergyMinimizer(pybind11::module& m);

#endif // #ifndef __FIRE_ENERGY_MINIMIZER_H__
