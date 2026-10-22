"""Geometry regression checks; run with import_canyon.py's uv dependencies."""
import unittest
import numpy as np
from shapely.geometry import Point
from import_canyon import ground_heights, structure_anchor, bush_footprint, sim, SCALE, is_wall_mesh

class CanyonPlacementTests(unittest.TestCase):
    def test_authored_masonry_and_rocks_are_solid(self):
        for name in ('PGD_M_20PropsWall_01_0', 'PGD_M_20PropsWall_02_Low_0',
                     'PGD_M_20RockGroupBlue_01_0', 'PGD_M_20RockWall_01_0'):
            self.assertTrue(is_wall_mesh(name))
        self.assertFalse(is_wall_mesh('PGD_M_20JungleGrassGroup_01'))

    def test_structure_uses_authored_origin_not_asymmetric_bounds(self):
        row=dict(origin=[46.07438659667969,30.687740325927734,-.089],
                 lo=[41.5,26.1,-1.3],hi=[51.7,36.2,20.6])
        np.testing.assert_array_equal(structure_anchor(row),sim(row['origin']))
        self.assertGreater(np.linalg.norm(sim((np.array(row['lo'])+row['hi'])/2)-structure_anchor(row)),10)

    def test_grass_keeps_concavity_and_separate_clumps(self):
        def quad(x0,y0,x1,y1):
            return [[x0,y0,0],[x1,y0,0],[x1,y1,1], [x0,y0,0],[x1,y1,1],[x0,y1,1]]
        p=np.array(quad(0,0,2,10)+quad(2,0,10,2)+quad(15,0,17,2))
        shape=bush_footprint(p)
        self.assertTrue(shape.contains(Point(1,5)))
        self.assertTrue(shape.contains(Point(16,1)))
        self.assertFalse(shape.contains(Point(5,5)), 'The empty inside corner is not concealment')
        self.assertFalse(shape.contains(Point(12,1)), 'Separate clumps must not fill their gap')

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
