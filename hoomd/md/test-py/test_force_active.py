# -*- coding: iso-8859-1 -*-
# Maintainer: joaander

from hoomd import *
from hoomd import deprecated
from hoomd import md
import unittest
import os, math, numpy as np
context.initialize();

# tests md.force.active
class force_active_tests (unittest.TestCase):
    def setUp(self):
        print
        deprecated.init.create_random(N=100, phi_p=0.05);

        context.current.sorter.set_params(grid=8)

    # test to see that can create a md.force.active
    def test_create(self):
        np.random.seed(1)
        activity = [ tuple(((np.random.rand(3) - 0.5) * 2.0)) for i in range(100)] # random forces
        md.force.active(seed=7, f_lst=activity, group=group.all())

    # tests options to md.force.active
    def test_options(self):
        np.random.seed(2,)
        activity = [ tuple(((np.random.rand(3) - 0.5) * 2.0)) for i in range(100)] # random forces
        md.force.active(seed=2, f_lst=activity, group=group.all(), rotation_diff=1.0, orientation_link=False)
        md.force.active(seed=2, f_lst=activity, group=group.all(), rotation_diff=0.0, orientation_link=True)
        # ellipsoid = update.constraint_ellipsoid(P=(0,0,0), rx=3, ry=3, rz=3)
        # md.force.active(seed=2, f_lst=activity, constraint=ellipsoid)

    # test the initialization checks
    def test_init_checks(self):
        activity = [ tuple(((np.random.rand(3) - 0.5) * 2.0)) for i in range(100)]
        act = md.force.active(seed=10, f_lst=activity, group=group.all());
        act.cpp_force = None;

        self.assertRaises(RuntimeError, act.enable);
        self.assertRaises(RuntimeError, act.disable);

    def tearDown(self):
        context.initialize();


if __name__ == '__main__':
    unittest.main(argv = ['test.py', '-v'])
