# -*- coding: iso-8859-1 -*-
#Highly Optimized Object-oriented Many-particle Dynamics -- Blue Edition
#(HOOMD-blue) Open Source Software License Copyright 2008, 2009 Ames Laboratory
#Iowa State University and The Regents of the University of Michigan All rights
#reserved.

#HOOMD-blue may contain modifications ("Contributions") provided, and to which
#copyright is held, by various Contributors who have granted The Regents of the
#University of Michigan the right to modify and/or distribute such Contributions.

#Redistribution and use of HOOMD-blue, in source and binary forms, with or
#without modification, are permitted, provided that the following conditions are
#met:

#* Redistributions of source code must retain the above copyright notice, this
#list of conditions, and the following disclaimer.

#* Redistributions in binary form must reproduce the above copyright notice, this
#list of conditions, and the following disclaimer in the documentation and/or
#other materials provided with the distribution.

#* Neither the name of the copyright holder nor the names of HOOMD-blue's
#contributors may be used to endorse or promote products derived from this
#software without specific prior written permission.

#Disclaimer

#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER AND CONTRIBUTORS ``AS IS''
#AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND/OR
#ANY WARRANTIES THAT THIS SOFTWARE IS FREE OF INFRINGEMENT ARE DISCLAIMED.

#IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
#INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
#BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
#LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
#OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# $Id$
# $URL$
# Maintainer: joaander / All Developers are free to add commands for new features

## \package hoomd_script.integrate
# \brief Commands that integrate the equations of motion
#
# Commands beginning with integrate. specify the integrator to use when
# advancing particles forward in time. By default, no integrator is
# specified. An integrator can specified anywhere before executing the 
# run() command, which will then use the last integrator set. 
# If a number of integrators are created in the script,
# the last one is the only one to take effect. For example:
# \code
# integrate.nvt(dt=0.005, T=1.2, tau=0.5)
# integrate.nve(dt=0.005) 
# run(100)
# \endcode
# In this example, the nvt integration is ignored as the creation of the
# nve integrator overwrote it.
#
# However, it is valid to run() a number of time steps with one integrator
# and then replace it with another before the next run().
#
# Some integrators provide parameters that can be changed between runs.
# In order to access the integrator to change it, it needs to be saved
# in a variable. For example:
# \code
# integrator = integrate.nvt(dt=0.005, T=1.2, tau=0.5)
# run(100)
# integrator.set_params(T=1.0)
# run(100)
# \endcode
# This code snippet runs the first 100 time steps with T=1.2 and the next 100 with T=1.0

import hoomd;
import globals;
import sys;
import util;
import variant;

## \internal
# \brief Base class for integrators
#
# An integrator in hoomd_script reflects an Integrator in c++. It is responsible
# for all high-level management that happens behind the scenes for hoomd_script
# writers. 1) The instance of the c++ integrator itself is tracked 2) All
# forces created so far in the simulation are updated in the cpp_integrator
# whenever run() is called.
class _integrator:
    ## \internal
    # \brief Constructs the integrator
    #
    # This doesn't really do much bet set some member variables to None
    def __init__(self):
        # check if initialization has occured
        if globals.system == None:
            print >> sys.stderr, "\n***Error! Cannot create integrator before initialization\n";
            raise RuntimeError('Error creating integrator');
        
        # by default, integrators do not support methods
        self.cpp_integrator = None;
        self.supports_methods = False;
        
        # save ourselves in the global variable
        globals.integrator = self;
        
    ## \var cpp_integrator
    # \internal 
    # \brief Stores the C++ side Integrator managed by this class
    
    ## \var supports_methods
    # \internal
    # \brief True if this integrator supports integration methods
    # \note If hoomd ever needs to support multiple TYPES of methods, we could just change this to a string naming the
    # type that is supported and add a type string to each of the integration_methods.
    
    ## \internal
    # \brief Updates the integrators in the reflected c++ class
    def update_forces(self):
        # check that proper initialization has occured
        if self.cpp_integrator == None:
            print >> sys.stderr, "\nBug in hoomd_script: cpp_integrator not set, please report\n";
            raise RuntimeError('Error updating forces');
        
        # set the forces
        self.cpp_integrator.removeForceComputes();
        for f in globals.forces:
            if f.enabled:
                if f.cpp_force == None:
                    print >> sys.stderr, "\nBug in hoomd_script: cpp_force not set, please report\n";
                    raise RuntimeError('Error updating forces');
                else:
                    self.cpp_integrator.addForceCompute(f.cpp_force);
                    f.update_coeffs();
    
    ## \internal
    # \brief Updates the integration methods in the reflected c++ class
    def update_methods(self):
        # check that proper initialization has occured
        if self.cpp_integrator == None:
            print >> sys.stderr, "\nBug in hoomd_script: cpp_integrator not set, please report\n";
            raise RuntimeError('Error updating integrator methods');
            
        # if we support methods, add them all to the list
        if self.supports_methods:
            self.cpp_integrator.removeAllIntegrationMethods();
            
            if len(globals.integration_methods) == 0:
                print >> sys.stderr, "\nThis integrator requires that one or more integration methods be specified.";
                raise RuntimeError('Error initializing integrator methods');
            
            for m in globals.integration_methods:
                self.cpp_integrator.addIntegrationMethod(m.cpp_method);
        else:
            if len(globals.integration_methods) > 0:
                print >> sys.stderr, "\nThis integrator does not support the use of integration methods,";
                print >> sys.stderr, "but some have been specified in the script. Remove them or use";
                print >> sys.stderr, "a different integrator.\n";
                raise RuntimeError('Error initializing integrator methods');

## \internal
# \brief Base class for integration methods
#
# An integration_method in hoomd_script reflects an IntegrationMethod in c++. It is responsible for all high-level
# management that happens behind the scenes for hoomd_script writers. 1) The instance of the c++ integration method
# itself is tracked and added to the integrator and 2) methods are provided for disabling the integration method from
# being active for the next run()
#
# The design of integration_method exactly mirrors that of _force for consistency
class _integration_method:
    ## \internal
    # \brief Constructs the integration_method
    #
    # Initializes the cpp_method to None.
    def __init__(self):
        # check if initialization has occured
        if globals.system == None:
            print >> sys.stderr, "\n***Error! Cannot create an integration method before initialization\n";
            raise RuntimeError('Error creating integration method');
        
        self.cpp_method = None;
        
        self.enabled = True;
        globals.integration_methods.append(self);

    ## \var enabled
    # \internal
    # \brief True if the integration method is enabled

    ## \var cpp_method
    # \internal
    # \brief Stores the C++ side IntegrationMethod managed by this class
    
    ## Disables the integration method
    #
    # \b Examples:
    # \code
    # method.disable()
    # \endcode
    #
    # Executing the disable command will remove the integration method from the simulation.Any run() command executed
    # after disabling an integration method will not apply the integration method to the particles during the
    # simulation. A disabled integration method can be re-enabled with enable()
    #
    # To use this command, you must have saved the force in a variable, as 
    # shown in this example:
    # \code
    # method = integrate.some_method()
    # # ... later in the script
    # method.disable()
    # \endcode
    def disable(self):
        util.print_status_line();
        
        # check that we have been initialized properly
        if self.cpp_method == None:
            print >> sys.stderr, "\nBug in hoomd_script: cpp_method not set, please report\n";
            raise RuntimeError('Error disabling integration method');
        
        # check if we are already disabled
        if not self.enabled:
            print "***Warning! Ignoring command to disable an integration method that is already disabled";
            return;
        
        self.enabled = False;
        globals.integration_methods.remove(self);

    ## Enables the integration method
    #
    # \b Examples:
    # \code
    # method.enable()
    # \endcode
    #
    # See disable() for a detailed description.
    def enable(self):
        util.print_status_line();
        
        # check that we have been initialized properly
        if self.cpp_method == None:
            print >> sys.stderr, "\nBug in hoomd_script: cpp_method not set, please report\n";
            raise RuntimeError('Error enabling integration method');
        
        # check if we are already disabled
        if self.enabled:
            print "***Warning! Ignoring command to enable an integration method that is already enabled";
            return;
        
        self.enabled = True;
        globals.integration_methods.append(self);

## Enables a variety of standard integration methods
#
# integrate.mode_standard performs a standard time step integration technique to move the system forward. At each time
# step, all of the specified forces are evaluated and used in moving the system forward to the next step.
#
# By itself, integrate.mode_standard does nothing. You must specify one or more integration methods to apply to the
# system. Each integration method can be applied to only a specific group of particles enabling advanced simulation
# techniques.
#
# The following commands can be used to specify the integration methods used by integrate.mode_standard.
# - integrate.nve
# - integrate.nvt
# - integrate.bdnvt
#
# There can only be one integration mode active at a time. If there are more than one integrate.mode_* commands in
# a hoomd script, only the most recent before a given run() will take effect.
class mode_standard(_integrator):
    ## Specifies the standard integration mode
    # \param dt Each time step of the simulation run() will advance the real time of the system forward by \a dt
    #
    # \b Examples:
    # \code
    # integrate.mode_standard(dt=0.005)
    # integrator_mode = integrate.mode_standard(dt=0.001)
    # \endcode
    def __init__(self, dt):
        util.print_status_line();
        
        # initialize base class
        _integrator.__init__(self);
        
        # initialize the reflected c++ class
        self.cpp_integrator = hoomd.IntegratorTwoStep(globals.system_definition, dt);
        self.supports_methods = True;
        
        globals.system.setIntegrator(self.cpp_integrator);
    
    ## Changes parameters of an existing integration mode
    # \param dt New time step delta (if set)
    #
    # To change the parameters of an existing integration mode, you must save it in a variable when it is
    # specified, like so:
    # \code
    # integrator_mode = integrate.mode_standard(dt=5e-3)
    # \endcode
    #
    # \b Examples:
    # \code
    # integrator_mode.set_params(dt=0.007)
    # \endcode
    def set_params(self, dt=None):
        util.print_status_line();
        # check that proper initialization has occured
        if self.cpp_integrator == None:
            print >> sys.stderr, "\nBug in hoomd_script: cpp_integrator not set, please report\n";
            raise RuntimeError('Error updating forces');
        
        # change the parameters
        if dt != None:
            self.cpp_integrator.setDeltaT(dt);

## NVT Integration via the Nos&eacute;-Hoover thermostat
#
# integrate.nvt performs constant volume, constant temperature simulations using the standard
# Nos&eacute;-Hoover thermostat.
#
# integrate.nvt is an integration method. It must be used in concert with an integration mode. It can be used while
# the following modes are active:
# - integrate.mode_standard
class nvt(_integration_method):
    ## Specifies the NVT integration method
    # \param group Group of particles on which to apply this method.
    # \param T Temperature set point for the Nos&eacute;-Hoover thermostat.
    # \param tau Coupling constant for the Nos&eacute;-Hoover thermostat.
    #
    # \f$ \tau \f$ is related to the Nos&eacute; mass \f$ Q \f$ by 
    # \f[ \tau = \sqrt{\frac{Q}{g k_B T_0}} \f] where \f$ g \f$ is the number of degrees of freedom,
    # and \f$ T_0 \f$ is the temperature set point (\a T above).
    #
    # \a T can be a variant type, allowing for temperature ramps in simulation runs.
    #
    # \b Examples:
    # \code
    # all = group.all()
    # integrate.nvt(all, T=1.0, tau=0.5)
    # integrator = integrate.nvt(all, tau=1.0, T=0.65)
    # typeA = group.type('A')
    # integrator = integrate.nvt(typeA, tau=1.0, T=variant.linear_interp([(0, 4.0), (1e6, 1.0)]))
    # \endcode
    def __init__(self, group, T, tau):
        util.print_status_line();
        
        # initialize base class
        _integration_method.__init__(self);
        
        # setup the variant inputs
        T = variant._setup_variant_input(T);
        
        # initialize the reflected c++ class
        if globals.system_definition.getParticleData().getExecConf().exec_mode == hoomd.ExecutionConfiguration.executionMode.CPU:
            self.cpp_method = hoomd.TwoStepNVT(globals.system_definition, group.cpp_group, tau, T.cpp_variant);
        elif globals.system_definition.getParticleData().getExecConf().exec_mode == hoomd.ExecutionConfiguration.executionMode.GPU:
            self.cpp_method = hoomd.TwoStepNVTGPU(globals.system_definition, group.cpp_group, tau, T.cpp_variant);
        else:
            print >> sys.stderr, "\n***Error! Invalid execution mode\n";
            raise RuntimeError("Error creating NVT integrator");
    
    ## Changes parameters of an existing integrator
    # \param T New temperature (if set)
    # \param tau New coupling constant (if set)
    #
    # To change the parameters of an existing integrator, you must save it in a variable when it is
    # specified, like so:
    # \code
    # integrator = integrate.nvt(all, tau=1.0, T=0.65)
    # \endcode
    #
    # \b Examples:
    # \code
    # integrator.set_params(tau=0.6)
    # integrator.set_params(tau=0.7, T=2.0)
    # \endcode
    def set_params(self, T=None, tau=None):
        util.print_status_line();
        # check that proper initialization has occured
        if self.cpp_method == None:
            print >> sys.stderr, "\nBug in hoomd_script: cpp_method not set, please report\n";
            raise RuntimeError('Error updating nvt params');
        
        # change the parameters
        if T != None:
            # setup the variant inputs
            T = variant._setup_variant_input(T);
            self.cpp_method.setT(T.cpp_variant);
        if tau != None:
            self.cpp_method.setTau(tau);

## NPT Integration via the Nos&eacute;-Hoover thermostat, Anderson barostat
#
# integrate.npt performs constant pressure, constant temperature simulations using the standard
# Nos&eacute;-Hoover thermosta/Anderson barostat. 
class npt(_integrator):
    ## Specifies the NPT integrator
    # \param dt Each time step of the simulation run() will advance the real time of the system forward by \a dt
    # \param T Temperature set point for the Nos&eacute;-Hoover thermostat
    # \param P Pressure set point for the Anderson barostat
    # \param tau Coupling constant for the Nos&eacute;-Hoover thermostat.
    # \param tauP Coupling constant for the barostat
    #
    # Both \a T and \a P can be variant types, allowing for temperature/pressure ramps in simulation runs.
    #
    # \f$ \tau \f$ is related to the Nos&eacute; mass \f$ Q \f$ by 
    # \f[ \tau = \sqrt{\frac{Q}{g k_B T_0}} \f] where \f$ g \f$ is the number of degrees of freedom,
    # and \f$ T_0 \f$ is the temperature set point (\a T above).
    #
    # \b Examples:
    # \code
    # integrate.npt(dt=0.005, T=1.0, tau=0.5, tauP=1.0, P=2.0)
    # integrator = integrate.npt(tau=1.0, dt=5e-3, T=0.65, tauP = 1.2, P=2.0)
    # \endcode
    def __init__(self, dt, T, tau, P, tauP):
        util.print_status_line();
        
        # initialize base class
        _integrator.__init__(self);
        
        # setup the variant inputs
        T = variant._setup_variant_input(T);
        P = variant._setup_variant_input(P);
        
        # initialize the reflected c++ class
        if globals.system_definition.getParticleData().getExecConf().exec_mode == hoomd.ExecutionConfiguration.executionMode.CPU:
            self.cpp_integrator = hoomd.NPTUpdater(globals.system_definition, dt, tau, tauP, T.cpp_variant, P.cpp_variant);
        elif globals.system_definition.getParticleData().getExecConf().exec_mode == hoomd.ExecutionConfiguration.executionMode.GPU:
            self.cpp_integrator = hoomd.NPTUpdaterGPU(globals.system_definition, dt, tau, tauP, T.cpp_variant, P.cpp_variant);
        else:
            print >> sys.stderr, "\n***Error! Invalid execution mode\n";
            raise RuntimeError("Error creating NVT integrator");
            
        globals.system.setIntegrator(self.cpp_integrator);
    
    ## Changes parameters of an existing integrator
    # \param dt New time step delta (if set)
    # \param T New temperature (if set)
    # \param tau New coupling constant (if set)
    # \param P New pressure (if set)
    # \param tauP New barostat coupling constant (if set)
    #
    # To change the parameters of an existing integrator, you must save it in a variable when it is
    # specified, like so:
    # \code
    # integrator = integrate.npt(tau=1.0, dt=5e-3, T=0.65)
    # \endcode
    #
    # \b Examples:
    # \code
    # integrator.set_params(dt=0.007)
    # integrator.set_params(tau=0.6)
    # integrator.set_params(dt=3e-3, T=2.0, P=1.0)
    # \endcode
    def set_params(self, dt=None, T=None, tau=None, P=None, tauP=None):
        util.print_status_line();
        # check that proper initialization has occurred
        if self.cpp_integrator == None:
            print >> sys.stderr, "\nBug in hoomd_script: cpp_integrator not set, please report\n";
            raise RuntimeError('Error updating forces');
        
        # change the parameters
        if dt != None:
            self.cpp_integrator.setDeltaT(dt);
        if T != None:
            # setup the variant inputs
            T = variant._setup_variant_input(T);
            self.cpp_integrator.setT(T.cpp_variant);
        if tau != None:
            self.cpp_integrator.setTau(tau);
        if P != None:
            # setup the variant inputs
            P = variant._setup_variant_input(P);
            self.cpp_integrator.setP(P.cpp_variant);
        if tauP != None:
            self.cpp_integrator.setTauP(tauP);


## NVE Integration via Velocity-Verlet
#
# integrate.nve performs constant volume, constant energy simulations using the standard
# Velocity-Verlet method. For poor initial conditions that include overlapping atoms, a 
# limit can be specified to the movement a particle is allowed to make in one time step. 
# After a few thousand time steps with the limit set, the system should be in a safe state 
# to continue with unconstrained integration.
#
# \note With an active limit, Newton's third law is effectively \b not obeyed and the system 
# can gain linear momentum. Activate the update.zero_momentum updater during the limited nve
# run to prevent this.
#
# integrate.nve is an integration method. It must be used in concert with an integration mode. It can be used while
# the following modes are active:
# - integrate.mode_standard
class nve(_integration_method):
    ## Specifies the NVE integration method
    # \param group Group of particles on which to apply this method.
    # \param limit (optional) Enforce that no particle moves more than a distance of \a limit in a single time step
    #
    # \b Examples:
    # \code
    # all = group.all()
    # integrate.nve(all)
    # integrator = integrate.nve(all)
    # typeA = group.type('A')
    # integrate.nve(typeA, limit=0.01)
    # \endcode
    def __init__(self, group, limit=None):
        util.print_status_line();
        
        # initialize base class
        _integration_method.__init__(self);
        
        # initialize the reflected c++ class
        if globals.system_definition.getParticleData().getExecConf().exec_mode == hoomd.ExecutionConfiguration.executionMode.CPU:
            self.cpp_method = hoomd.TwoStepNVE(globals.system_definition, group.cpp_group);
        elif globals.system_definition.getParticleData().getExecConf().exec_mode == hoomd.ExecutionConfiguration.executionMode.GPU:
            self.cpp_method = hoomd.TwoStepNVEGPU(globals.system_definition, group.cpp_group);
        else:
            print >> sys.stderr, "\n***Error! Invalid execution mode\n";
            raise RuntimeError("Error creating NVE integration method");
        
        # set the limit
        if limit != None:
            self.cpp_method.setLimit(limit);
    
    ## Changes parameters of an existing integrator
    # \param limit (if set) New limit value to set. Removes the limit if limit is False
    #
    # To change the parameters of an existing integrator, you must save it in a variable when it is
    # specified, like so:
    # \code
    # integrator = integrate.nve(all)
    # \endcode
    #
    # \b Examples:
    # \code
    # integrator.set_params(limit=0.01)
    # integrator.set_params(limit=False)
    # \endcode
    def set_params(self, limit=None):
        util.print_status_line();
        # check that proper initialization has occured
        if self.cpp_method == None:
            print >> sys.stderr, "\nBug in hoomd_script: cpp_method not set, please report\n";
            raise RuntimeError('Error setting nve params');
        
        # change the parameters
        if limit != None:
            if limit == False:
                self.cpp_method.removeLimit();
            else:
                self.cpp_method.setLimit(limit);
            

## NVT integration via Brownian dynamics
#
# integrate.bdnvt performs constant volume, fixed average temperature simulation based on a 
# NVE simulation with added damping and stochastic heat bath forces.
#
# The total added %force \f$ \vec{F}\f$ is
# \f[ \vec{F} = -\gamma \cdot \vec{v} + \vec{F}_{\mathrm{rand}} \f]
# where \f$ \vec{v} \f$ is the particle's velocity and \f$ \vec{F}_{\mathrm{rand}} \f$
# is a random force with magnitude chosen via the fluctuation-dissipation theorem
# to be consistent with the specified drag (\a gamma) and temperature (\a T).
# 
# For poor initial conditions that include overlapping atoms, a 
# limit can be specified to the movement a particle is allowed to make in one time step. 
# After a few thousand time steps with the limit set, the system should be in a safe state 
# to continue with unconstrained integration.
#
# \note With an active limit, Newton's third law is effectively \b not obeyed and the system 
# can gain linear momentum. Activate the update.zero_momentum updater during the limited bdnvt
# run to prevent this.
#
# integrate.bdnvt is an integration method. It must be used in concert with an integration mode. It can be used while
# the following modes are active:
# - integrate.mode_standard
class bdnvt(_integration_method):
    ## Specifies the BD NVT integrator
    # \param group Group of particles on which to apply this method.
    # \param T Temperature of the simulation \a T
    # \param seed Random seed to use for the run. Simulations that are identical, except for the seed, will follow 
    # different trajectories.
    # \param gamma_diam If True, then then gamma for each particle will be assigned to its diameter. If False (the
    #                   default), gammas are assigned per particle type via set_gamma().
    # \param limit (optional) Enforce that no particle moves more than a distance of \a limit in a single time step
    #
    # \a T can be a variant type, allowing for temperature ramps in simulation runs.
    #
    # \b Examples:
    # \code
    # all = group.all();
    # integrate.bdnvt(all, T=1.0, seed=5)
    # integrator = integrate.bdnvt(all, T=1.0, seed=100)
    # integrate.bdnvt(all, T=1.0, limit=0.01, gamma_diam=1)
    # typeA = group.type('A');
    # integrate.bdnvt(typeA, T=variant.linear_interp([(0, 4.0), (1e6, 1.0)]))
    # \endcode
    def __init__(self, group, T, seed=0, gamma_diam=False, limit=None):
        util.print_status_line();
        
        # initialize base class
        _integration_method.__init__(self);
        
        # setup the variant inputs
        T = variant._setup_variant_input(T);
        
        # initialize the reflected c++ class
        if globals.system_definition.getParticleData().getExecConf().exec_mode == hoomd.ExecutionConfiguration.executionMode.CPU:
            self.cpp_method = hoomd.TwoStepBDNVT(globals.system_definition, group.cpp_group, T.cpp_variant, seed, gamma_diam);
        elif globals.system_definition.getParticleData().getExecConf().exec_mode == hoomd.ExecutionConfiguration.executionMode.GPU:
            self.cpp_method = hoomd.TwoStepBDNVTGPU(globals.system_definition, group.cpp_group, T.cpp_variant, seed, gamma_diam);
        else:
            print >> sys.stderr, "\n***Error! Invalid execution mode\n";
            raise RuntimeError("Error creating BD NVT integrator");
        
        # set the limit
        if limit != None:
            self.cpp_method.setLimit(limit);
    
    ## Changes parameters of an existing integrator
    # \param T New temperature (if set)
    #
    # To change the parameters of an existing integrator, you must save it in a variable when it is
    # specified, like so:
    # \code
    # integrator = integrate.bdnvt(all, T=1.0)
    # \endcode
    #
    # \b Examples:
    # \code
    # integrator.set_params(T=2.0)
    # \endcode
    def set_params(self, T=None):
        util.print_status_line();
        # check that proper initialization has occured
        if self.cpp_method == None:
            print >> sys.stderr, "\nBug in hoomd_script: cpp_method not set, please report\n";
            raise RuntimeError('Error updating bdnvt params');
        
        # change the parameters
        if T != None:
            # setup the variant inputs
            T = variant._setup_variant_input(T);
            self.cpp_method.setT(T.cpp_variant);

    ## Sets gamma parameter for a particle type
    # \param a Particle type
    # \param gamma \f$ \gamma \f$ for particle type (see below for examples)
    #
    # set_gamma() sets the coefficient \f$ \gamma \f$ for a single particle type, identified
    # by name.
    #
    # The gamma parameter determines how strongly a particular particle is coupled to 
    # the stochastic bath.  The higher the gamma, the more strongly coupled: see 
    # integrate.bdnvt.
    #
    # If gamma is not set for any particle type, it will automatically default to  1.0.
    # It is not an error to specify gammas for particle types that do not exist in the simulation.
    # This can be useful in defining a single simulation script for many different types of particles 
    # even when some simulations only include a subset.
    #
    # \b Examples:
    # \code
    # bd.set_gamma('A', gamma=2.0)
    # \endcode
    #
    def set_gamma(self, a, gamma):
        util.print_status_line();
        
        # check that proper initialization has occured
        if self.cpp_method == None:
            print >> sys.stderr, "\nBug in hoomd_script: cpp_method not set, please report\n";
            raise RuntimeError('Error updating bdnvt gamma');
        
        ntypes = globals.system_definition.getParticleData().getNTypes();
        type_list = [];
        for i in xrange(0,ntypes):
            type_list.append(globals.system_definition.getParticleData().getNameByType(i));
        
        # change the parameters
        for i in xrange(0,ntypes):
            if a == type_list[i]:
                self.method.setGamma(i,gamma);

