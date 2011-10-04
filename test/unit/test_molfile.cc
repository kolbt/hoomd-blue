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
 


#ifdef WIN32
#pragma warning( push )
#pragma warning( disable : 4103 4244 )
#endif

#include <iostream>

//! Name the unit test module
#define BOOST_TEST_MODULE MolFilePluginTests
#include "boost_utf_configure.h"

#include "FileFormatManager.h"

/*! \file molfile_test.cc
    \brief Unit tests for MolFilePlugin and FileFormatManager
    \ingroup unit_tests
*/

using namespace std;

//! perform some simple checks on the Manager module for molfile plugins.
BOOST_AUTO_TEST_CASE(FileFormatManager_test)
    {
    // constructor test
    FileFormatManager mgr;

    // these will not cause any failure, even if the files are not found.
    // the python script layer will make sure that only files that exist
    // will be handed to the plugin manager. for testing set LD_LIBRARY_PATH
    // to an existing VMD molfile plugin installation.
    mgr.loadMolFileDSOFile("hoomdplugin.so");
    mgr.loadMolFileDSOFile("hoomdblueplugin.so");
    mgr.loadMolFileDSOFile("psfplugin.so");
    mgr.loadMolFileDSOFile("pdbplugin.so");
    mgr.loadMolFileDSOFile("xyzplugin.so");

    }

#ifdef WIN32
#pragma warning( pop )
#endif

