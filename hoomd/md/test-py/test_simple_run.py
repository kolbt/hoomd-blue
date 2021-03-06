# -*- coding: iso-8859-1 -*-
# Maintainer: jglaser

from hoomd import *
from hoomd import deprecated
from hoomd import md;
context.initialize()
import unittest
import os

# unit test to run a simple polymer system with pair and bond potentials
class replicate(unittest.TestCase):
    def setUp(self):
        self.polymer1 = dict(bond_len=1.2, type=['A']*6 + ['B']*7 + ['A']*6, bond="linear", count=100);
        self.polymer2 = dict(bond_len=1.2, type=['B']*4, bond="linear", count=10)
        self.polymers = [self.polymer1, self.polymer2]
        self.box = data.boxdim(L=35);
        self.separation=dict(A=0.42, B=0.42)
        deprecated.init.create_random_polymers(box=self.box, polymers=self.polymers, separation=self.separation);
        self.assert_(context.current.system_definition);
        self.assert_(context.current.system);
        self.harmonic = md.bond.harmonic();
        self.harmonic.bond_coeff.set('polymer', k=1.0, r0=1.0)

        nl = md.nlist.cell()
        self.pair = md.pair.lj(r_cut=2.5, nlist = nl)
        self.pair.pair_coeff.set('A','A',epsilon=1.0, sigma=1.0)
        self.pair.pair_coeff.set('A','B',epsilon=1.0, sigma=1.0)
        self.pair.pair_coeff.set('B','B',epsilon=1.0, sigma=1.0)

    def test_run(self):
        md.integrate.mode_standard(dt=0.005);
        md.integrate.nve(group.all());
        run(100)

    def tearDown(self):
        del self.harmonic
        del self.pair
        context.initialize();

if __name__ == '__main__':
    unittest.main(argv = ['test.py', '-v'])
