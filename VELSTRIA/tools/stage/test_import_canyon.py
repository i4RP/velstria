"""Geometry regression checks; run with import_canyon.py's uv dependencies."""
import unittest
import numpy as np
from import_canyon import ground_heights, SCALE

class CanyonGroundTests(unittest.TestCase):
    def test_depressed_surfaces_keep_their_depth_order(self):
        source=np.array([-5.,-1.,-.1,-.04,-.01,0.,.2])
        result=ground_heights(source,'PGD_M_20TerrainRock_01_D.png')
        self.assertTrue(np.all(np.diff(result)>0), 'Distinct floor heights must never collapse onto one plane')
        self.assertTrue(np.all(result[:5]<0))
        self.assertEqual(result[-1],source[-1])

    def test_near_ground_source_layers_keep_four_mm_clearance(self):
        layers=ground_heights(np.array([-.113,-.099]),"PGD_M_20BaseGround_01_D.png")*SCALE
        self.assertGreaterEqual(layers[1]-layers[0],.004)

    def test_authored_coplanar_border_has_four_mm_clearance(self):
        source=np.array([-.1,0.,.2])
        rock=ground_heights(source,'PGD_M_20TerrainRock_01_D.png')*SCALE
        border=ground_heights(source,'PGD_M_20TerrainBorder_01_D.png')*SCALE
        self.assertTrue(np.all(rock-border>=.004), 'Opaque overlays must meet GroundLayer clearance')

if __name__=='__main__':unittest.main()
