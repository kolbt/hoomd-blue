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

/*! \file ClockSource.cc
    \brief Defines the ClockSource class
*/

#ifdef WIN32
#pragma warning( push )
#pragma warning( disable : 4103 4244 )
#endif

#include "ClockSource.h"

#include <sstream>
#include <iomanip>

#include <boost/python.hpp>
using namespace boost::python;
using namespace std;

/*! A newly constructed ClockSource should read ~0 when getTime() is called. There is no other way to reset the clock*/
ClockSource::ClockSource() : m_start_time(0)
    {
    // take advantage of the initial 0 start time to assign a new start time
    m_start_time = getTime();
    }

/*! \param t the time to format
*/
std::string ClockSource::formatHMS(int64_t t)
    {
    // separate out into hours minutes and seconds
    int hours = int(t / (int64_t(3600) * int64_t(1000000000)));
    t -= hours * int64_t(3600) * int64_t(1000000000);
    int minutes = int(t / (int64_t(60) * int64_t(1000000000)));
    t -= minutes * int64_t(60) * int64_t(1000000000);
    int seconds = int(t / int64_t(1000000000));
    
    // format the string
    ostringstream str;
    str <<  setfill('0') << setw(2) << hours << ":" << setw(2) << minutes << ":" << setw(2) << seconds;
    return str.str();
    }

void export_ClockSource()
    {
    class_<ClockSource>("ClockSource")
    .def("getTime", &ClockSource::getTime)
    ;
    }

#ifdef WIN32
#pragma warning( pop )
#endif

