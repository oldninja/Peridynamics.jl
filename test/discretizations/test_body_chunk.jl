@testitem "init_body_chunk" begin
    position = [0.0 1.0 0.0 0.0
                0.0 0.0 1.0 0.0
                0.0 0.0 0.0 1.0]
    volume = [1.1, 1.2, 1.3, 1.4]
    mat = BBMaterial()
    body = Body(mat, position, volume)
    material!(body, horizon=2, rho=1, E=1, Gc=1)
    point_set!(body, :a, 1:2)
    point_set!(body, :b, 3:4)
    velocity_ic!(body, :a, :x, 1.0)
    velocity_bc!(t->t, body, :a, :x)
    forcedensity_bc!(t->t, body, :a, :x)
    precrack!(body, :a, :b)
    ts = VelocityVerlet(steps=10)
    pd = Peridynamics.PointDecomposition(body, 2)

    bc = Peridynamics.init_body_chunk(body, ts, pd, 1)
    @test bc.mat == mat
    @test bc.discret isa Peridynamics.BondDiscretization
    @test bc.discret.position == position
    @test bc.discret.volume == volume
    @test bc.discret.bonds == [
        Peridynamics.Bond(2, 1.0, true),
        Peridynamics.Bond(3, 1.0, true),
        Peridynamics.Bond(4, 1.0, true),
        Peridynamics.Bond(1, 1.0, true),
        Peridynamics.Bond(3, √2, true),
        Peridynamics.Bond(4, √2, true),
    ]
    @test bc.discret.n_neighbors == [3, 3]
    @test bc.discret.bond_ids == [1:3, 4:6]

    @test bc.ch.point_ids == [1, 2, 3, 4]
    @test bc.ch.loc_points == pd.decomp[1]
    @test bc.ch.halo_points == [3, 4]
    @test bc.ch.halo_by_src[2] == 3:4
    for i in 1:4
        @test bc.ch.localizer[i] == i
    end

    #TODO: test the other fields!
end


@testitem "chop_body_threads" begin
    position = [0.0 1.0 0.0 0.0
                0.0 0.0 1.0 0.0
                0.0 0.0 0.0 1.0]
    volume = [1.1, 1.2, 1.3, 1.4]
    mat = BBMaterial()
    body = Body(mat, position, volume)
    material!(body, horizon=2, rho=1, E=1, Gc=1)
    point_set!(body, :a, 1:2)
    point_set!(body, :b, 3:4)
    velocity_ic!(body, :a, :x, 1.0)
    velocity_bc!(t->t, body, :a, :x)
    forcedensity_bc!(t->t, body, :a, :x)
    precrack!(body, :a, :b)
    ts = VelocityVerlet(steps=10)
    point_decomp = Peridynamics.PointDecomposition(body, 2)

    body_chunks = Peridynamics.chop_body_threads(body, ts, point_decomp)

    @test body_chunks[1].mat == BBMaterial()
    @test body_chunks[1].discret isa Peridynamics.BondDiscretization
    @test body_chunks[1].discret.position == position
    @test body_chunks[1].discret.volume == volume
    @test body_chunks[1].discret.bonds == [
        Peridynamics.Bond(2, 1.0, true),
        Peridynamics.Bond(3, 1.0, true),
        Peridynamics.Bond(4, 1.0, true),
        Peridynamics.Bond(1, 1.0, true),
        Peridynamics.Bond(3, √2, true),
        Peridynamics.Bond(4, √2, true),
    ]
    @test body_chunks[1].discret.n_neighbors == [3, 3]
    @test body_chunks[1].discret.bond_ids == [1:3, 4:6]

    @test body_chunks[1].ch.point_ids == [1, 2, 3, 4]
    @test body_chunks[1].ch.loc_points == 1:2
    @test body_chunks[1].ch.halo_points == [3, 4]
    @test body_chunks[1].ch.halo_by_src[2] == 3:4
    for i in 1:4
        @test body_chunks[1].ch.localizer[i] == i
    end

    @test body_chunks[2].mat == BBMaterial()
    @test body_chunks[2].discret isa Peridynamics.BondDiscretization
    @test body_chunks[2].discret.position == position[:, [3, 4, 1, 2]]
    @test body_chunks[2].discret.volume == volume[[3, 4, 1, 2]]
    @test body_chunks[2].discret.bonds == [
        Peridynamics.Bond(3, 1.0, true),
        Peridynamics.Bond(4, √2, true),
        Peridynamics.Bond(2, √2, true),
        Peridynamics.Bond(3, 1.0, true),
        Peridynamics.Bond(4, √2, true),
        Peridynamics.Bond(1, √2, true),
    ]
    @test body_chunks[2].discret.n_neighbors == [3, 3]
    @test body_chunks[2].discret.bond_ids == [1:3, 4:6]

    @test body_chunks[2].ch.point_ids == [3, 4, 1, 2]
    @test body_chunks[2].ch.loc_points == [3, 4]
    @test body_chunks[2].ch.halo_points == [1, 2]
    @test body_chunks[2].ch.halo_by_src[1] == 3:4
    @test body_chunks[2].ch.localizer[3] == 1
    @test body_chunks[2].ch.localizer[4] == 2
    @test body_chunks[2].ch.localizer[1] == 3
    @test body_chunks[2].ch.localizer[2] == 4

    #TODO: test the other fields!
end
