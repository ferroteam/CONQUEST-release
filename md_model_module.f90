!!****h* Conquest/md_model *
!!  NAME
!!   md_model
!!  PURPOSE
!!   Store the current state of the MD run 
!!  AUTHOR
!!   Zamaan Raza
!!  CREATION DATE
!!   2017/10/31 11:50
!!  MODIFICATION HISTORY
!!   2018/05/30 zamaan
!!    Modified dump_stats to print correct header and columns when using
!!    Berendsen equilibration in NVT ensemble
!!
!!  SOURCE
!!
module md_model

  use datatypes
  use numbers
  use force_module,     only: tot_force, stress
  use global_module,    only: ni_in_cell, io_lun, atom_coord, &
                              flag_MDcontinue, flag_MDdebug, x_atom_cell, &
                              y_atom_cell, z_atom_cell, rcellx, rcelly, rcellz
  use species_module,   only: species
  use md_control,       only: md_n_nhc, ion_velocity, type_thermostat, &
                              type_barostat, lattice_vec

  implicit none

  logical       :: md_tdep ! Dump output for a TDEP calculation?
  character(20) :: file_meta      = 'infile.meta' ! filenames for TDEP
  character(20) :: file_positions = 'infile.positions'
  character(20) :: file_forces    = 'infile.forces'
  character(20) :: file_stat      = 'infile.stat'
  character(20) :: file_loto      = 'infile.lotosplitting'

  !!****s* md_model/type_md_model *
  !!  NAME
  !!   type_md_model
  !!  PURPOSE
  !!   Container for one step of MD data 
  !!  AUTHOR
  !!   Zamaan Raza
  !!  SOURCE
  !!  
  type type_md_model

    logical                                 :: append   ! append to file?

    ! Simulation parameters
    integer                                 :: step
    integer                                 :: ndof     ! degrees of freedom
    character(3)                            :: ensemble ! nve, nvt, npt etc
    real(double), dimension(:,:), pointer   :: lattice_vec
    real(double), pointer                   :: volume
    real(double)                            :: timestep
    integer                                 :: nequil   ! equilibration steps

    ! ionic variables
    integer                                 :: natoms
    integer, pointer, dimension(:)          :: species
    real(double), pointer                   :: lat_a, lat_b, lat_c
    real(double), pointer, dimension(:)     :: pos_x, pos_y, pos_z
    real(double), pointer, dimension(:,:)   :: atom_coords
    real(double), pointer, dimension(:,:)   :: atom_velocity
    real(double), pointer, dimension(:,:)   :: atom_force

    ! MD variables
    real(double)                            :: ion_kinetic_energy
    real(double)                            :: dft_total_energy
    real(double)                            :: h_prime  ! conserved qty

    ! Thermodynamic variables
    real(double), pointer                   :: T_int    ! internal temperature
    real(double), pointer                   :: T_ext    ! internal temperature
    real(double), pointer                   :: P_int    ! internal pressure
    real(double), pointer                   :: P_ext    ! internal pressure
    real(double), pointer                   :: PV
    real(double)                            :: enthalpy

    ! Thermostat
    character(20), pointer                  :: thermo_type
    real(double), pointer                   :: lambda   ! velocity scaling fac
    real(double), pointer                   :: tau_T    ! T coupling period
    integer, pointer                        :: n_nhc
    real(double), pointer                   :: nhc_energy
    real(double), pointer                   :: nhc_cell_energy
    real(double), pointer                   :: nhc_ion_energy
    real(double), pointer, dimension(:)     :: eta
    real(double), pointer, dimension(:)     :: v_eta
    real(double), pointer, dimension(:)     :: G_nhc
    real(double), pointer, dimension(:)     :: m_nhc
    real(double), pointer, dimension(:)     :: eta_cell
    real(double), pointer, dimension(:)     :: v_eta_cell
    real(double), pointer, dimension(:)     :: G_nhc_cell
    real(double), pointer, dimension(:)     :: m_nhc_cell

    ! Barostat
    character(20), pointer                  :: baro_type
    real(double), pointer, dimension(:)     :: stress
    real(double), pointer, dimension(:,:)   :: static_stress
    real(double), pointer, dimension(:,:)   :: ke_stress
    real(double), pointer                   :: box_kinetic_energy
    real(double), pointer                   :: m_box
    real(double), pointer                   :: eps
    real(double), pointer                   :: v_eps
    real(double), pointer                   :: G_eps
    real(double), dimension(3,3)            :: c_g
    real(double), dimension(3,3)            :: v_g

    contains

      procedure, public   :: init_model
      procedure, public   :: get_cons_qty
      procedure, public   :: print_md_energy
      procedure, public   :: dump_stats
      procedure, public   :: dump_frame
      procedure, public   :: dump_tdep

      procedure, private  :: dump_mdl_atom_arr

  end type type_md_model
  !!***

contains

  !!****m* md_model/init_model *
  !!  NAME
  !!   init_model 
  !!  PURPOSE
  !!   Initialiase the MD model 
  !!  AUTHOR
  !!   Zamaan Raza 
  !!  SOURCE
  !!  
  subroutine init_model(mdl, ensemble, timestep, thermo, baro)

    ! passed variables
    class(type_md_model), intent(inout)       :: mdl
    character(3), intent(in)                  :: ensemble
    real(double), intent(in)                  :: timestep
    type(type_thermostat), intent(in), target :: thermo
    type(type_barostat), intent(in), target   :: baro

    if (flag_MDcontinue) then
      mdl%append = .true.
    else
      mdl%append = .false.
    end if

    ! General MD arrays
    mdl%natoms = ni_in_cell
    mdl%ensemble = ensemble
    mdl%timestep = timestep
    mdl%species       => species
    mdl%lat_a         => rcellx
    mdl%lat_b         => rcelly
    mdl%lat_c         => rcellz
    mdl%pos_x         => x_atom_cell
    mdl%pos_y         => y_atom_cell
    mdl%pos_z         => z_atom_cell
    mdl%atom_coords   => atom_coord
    mdl%atom_force    => tot_force
    mdl%atom_velocity => ion_velocity
    mdl%lattice_vec   => lattice_vec
    mdl%stress        => stress

    ! Thermostat
    mdl%T_int         => thermo%T_int
    mdl%T_ext         => thermo%T_ext
    mdl%thermo_type   => thermo%thermo_type
    mdl%lambda        => thermo%lambda
    mdl%tau_T         => thermo%tau_T
    mdl%n_nhc         => thermo%n_nhc
    mdl%nhc_energy    => thermo%e_nhc
    mdl%nhc_ion_energy  => thermo%e_nhc_ion
    mdl%nhc_cell_energy => thermo%e_nhc_cell
    mdl%eta           => thermo%eta
    mdl%v_eta         => thermo%v_eta
    mdl%G_nhc         => thermo%G_nhc
    mdl%m_nhc         => thermo%m_nhc
    mdl%eta_cell      => thermo%eta_cell
    mdl%v_eta_cell    => thermo%v_eta_cell
    mdl%G_nhc_cell    => thermo%G_nhc_cell
    mdl%m_nhc_cell    => thermo%m_nhc_cell

    ! Barostat
    mdl%P_int         => baro%P_int
    mdl%P_ext         => baro%P_ext
    mdl%volume        => baro%volume
    mdl%PV            => baro%PV
    mdl%box_kinetic_energy => baro%ke_box
    mdl%baro_type     => baro%baro_type
    mdl%static_stress => baro%static_stress
    mdl%ke_stress     => baro%ke_stress
    mdl%m_box         => baro%box_mass
    mdl%eps           => baro%eps
    mdl%v_eps         => baro%v_eps
    mdl%G_eps         => baro%G_eps

  end subroutine init_model
  !!***

  !!****m* md_model/get_cons_qty *
  !!  NAME
  !!   get_cons_qty 
  !!  PURPOSE
  !!   Initialiase the MD model 
  !!  AUTHOR
  !!   Zamaan Raza 
  !!  SOURCE
  !!  
  subroutine get_cons_qty(mdl)

    use input_module,     only: leqi

    ! passed variables
    class(type_md_model), intent(inout)   :: mdl

    select case(mdl%ensemble)
    case("nve")
      mdl%h_prime = mdl%ion_kinetic_energy + mdl%dft_total_energy
    case("nvt")
      if (mdl%thermo_type == 'nhc') then
        mdl%h_prime = mdl%ion_kinetic_energy + mdl%dft_total_energy + &
                      mdl%nhc_energy
      else
        mdl%h_prime = mdl%ion_kinetic_energy + mdl%dft_total_energy
      end if
    case("npt")
      if (leqi(mdl%baro_type, 'iso-mttk') .or. leqi(mdl%baro_type, 'mttk')) then
        mdl%h_prime = mdl%ion_kinetic_energy + mdl%dft_total_energy + &
                      mdl%nhc_energy + mdl%box_kinetic_energy + mdl%PV
      else if (leqi(mdl%baro_type, 'iso-ssm')) then
        mdl%h_prime = mdl%ion_kinetic_energy + mdl%dft_total_energy + &
                      mdl%nhc_energy + mdl%box_kinetic_energy + mdl%PV
      else if (leqi(mdl%baro_type, 'ortho-ssm')) then
        mdl%h_prime = mdl%ion_kinetic_energy + mdl%dft_total_energy + &
                      mdl%nhc_energy + mdl%box_kinetic_energy + mdl%PV
      else if (leqi(mdl%baro_type, 'berendsen')) then
        mdl%h_prime = mdl%ion_kinetic_energy + mdl%dft_total_energy + mdl%PV
      end if
    end select

  end subroutine get_cons_qty
  !!***

  !!****m* md_model/print_md_energy *
  !!  NAME
  !!   print_md_energy 
  !!  PURPOSE
  !!   Print MD output at the end of each ionic step
  !!  AUTHOR
  !!   Zamaan Raza 
  !!  SOURCE
  !!  
  subroutine print_md_energy(mdl)

    use GenComms,         only: inode, ionode

    ! passed variables
    class(type_md_model), intent(inout)   :: mdl

    ! local variables

    if (inode==ionode) then
      write (io_lun, '(4x,"Conserved quantity H''  : ",f15.8)') &
        mdl%h_prime
      write (io_lun, '(4x,a)') "Components of conserved quantity"
      write (io_lun, '(4x,"Kinetic energy          : ",f15.8)') &
        mdl%ion_kinetic_energy
      write (io_lun, '(4x,"Potential energy        : ",f15.8)') &
        mdl%dft_total_energy
      select case(mdl%ensemble)
      case('nvt')
        select case(mdl%thermo_type)
        case('nhc')
          write (io_lun, '(4x,"Nose-Hoover energy      : ",f15.8)') &
            mdl%nhc_energy
        end select
      case('npt')
        select case(mdl%baro_type)
        case('iso-mttk')
          if (mdl%nequil < 1) then
            write (io_lun, '(4x,"Nose-Hoover energy      : ",f15.8)') &
              mdl%nhc_energy
            write (io_lun, '(4x,"Box kinetic energy      : ",f15.8)') &
              mdl%box_kinetic_energy
            write (io_lun, '(4x,"PV                      : ",f15.8)') &
              mdl%PV
          end if
        case('iso-ssm')
          if (mdl%nequil < 1) then
            write (io_lun, '(4x,"Nose-Hoover energy      : ",f15.8)') &
              mdl%nhc_energy
            write (io_lun, '(4x,"Box kinetic energy      : ",f15.8)') &
              mdl%box_kinetic_energy
            write (io_lun, '(4x,"PV                      : ",f15.8)') &
              mdl%PV
          end if
        case('ortho-ssm')
          if (mdl%nequil < 1) then
            write (io_lun, '(4x,"Nose-Hoover energy      : ",f15.8)') &
              mdl%nhc_energy
            write (io_lun, '(4x,"Box kinetic energy      : ",f15.8)') &
              mdl%box_kinetic_energy
            write (io_lun, '(4x,"PV                      : ",f15.8)') &
              mdl%PV
          end if
        end select
      end select
    end if
  end subroutine print_md_energy

  !!****m* md_model/dump_stats *
  !!  NAME
  !!   dump_stats 
  !!  PURPOSE
  !!   dump thermodynamics stats to a file 
  !!  AUTHOR
  !!   Zamaan Raza 
  !!  SOURCE
  !!  
  subroutine dump_stats(mdl, filename)

    use input_module,     only: io_assign, io_close
    use GenComms,         only: inode, ionode
    use md_control,       only: fac_HaBohr32GPa, md_berendsen_equil

    ! passed variables
    class(type_md_model), intent(inout)   :: mdl
    character(len=*), intent(in)          :: filename

    ! local variables
    integer                               :: lun
    real(double)                          :: P_GPa

    if (flag_MDdebug .and. inode==ionode) then
      write(io_lun,*) "Writing statistics to ", filename
    end if

    ! Convert units if necessary
    P_GPa = mdl%P_int*fac_HaBohr32GPA

    if (inode==ionode) then
      call io_assign(lun)

      if (mdl%append) then
        open(unit=lun,file=filename,position='append')
      else 
        open(unit=lun,file=filename,status='replace')
        select case (mdl%ensemble)
        case ('nve')
          write(lun,'(a10,3a18,2a12)') "step", "pe", "ke", "H'", "T", "P"
        case ('nvt')
          if (mdl%thermo_type == 'nhc' .or. md_berendsen_equil > 0) then
            write(lun,'(a10,4a18,2a12)') "step", "pe", "ke", "nhc", "H'", "T", "P"
          else
            write(lun,'(a10,3a16,2a12)') "step", "pe", "ke", "H'", "T", "P"
          end if
        case ('npt')
          select case(mdl%baro_type)
          case('iso-mttk')
            write(lun,'(a10,6a18,2a12,a16)') "step", "pe", "ke", "nhc", &
              "box", "pV", "H'", "T", "P", "V"
          case('iso-ssm')
            write(lun,'(a10,6a18,2a12,a16)') "step", "pe", "ke", "nhc", &
              "box", "pV", "H'", "T", "P", "V"
          case('ortho-ssm')
            write(lun,'(a10,6a18,2a12,a16)') "step", "pe", "ke", "nhc", &
              "box", "pV", "H'", "T", "P", "V"
          case('berendsen')
            if (md_berendsen_equil > 0) then
              write(lun,'(a10,6a18,2a12,a16)') "step", "pe", "ke", "nhc", &
                "box", "pV", "H'", "T", "P", "V"
            else
              write(lun,'(a10,4a18,2a12,a16)') "step", "pe", "ke", "pV", &
                "H'", "T", "P", "V"
            end if
          end select
        case ('nph')
          write(lun,'(a10,5a18,2a12,a16)') "step", "pe", "ke", "box", "pV", &
            "H'", "T", "P", "V"
        end select
      end if
      select case (mdl%ensemble)
      case ('nve')
        write(lun,'(i10,3e18.8,2f12.4)') mdl%step, mdl%dft_total_energy, &
          mdl%ion_kinetic_energy, mdl%h_prime, mdl%T_int, P_GPa
      case ('nvt')
        if (mdl%thermo_type == 'nhc' .or. md_berendsen_equil > 0) then
          write(lun,'(i10,4e18.8,2f12.4)') mdl%step, mdl%dft_total_energy, &
            mdl%ion_kinetic_energy, mdl%nhc_energy, mdl%h_prime, mdl%T_int, &
            P_GPa
        else
          write(lun,'(i10,3e18.8,2f12.4)') mdl%step, mdl%dft_total_energy, &
            mdl%ion_kinetic_energy, mdl%h_prime, mdl%T_int, P_GPa
        end if
      case ('npt')
        select case(mdl%baro_type)
        case('iso-mttk')
          write(lun,'(i10,6e18.8,2f12.4,e16.8)') mdl%step, &
            mdl%dft_total_energy, mdl%ion_kinetic_energy, mdl%nhc_energy, &
            mdl%box_kinetic_energy, mdl%PV, mdl%h_prime, mdl%T_int, P_GPa, &
            mdl%volume
        case('iso-ssm')
          write(lun,'(i10,6e18.8,2f12.4,e16.8)') mdl%step, &
            mdl%dft_total_energy, mdl%ion_kinetic_energy, mdl%nhc_energy, &
            mdl%box_kinetic_energy, mdl%PV, mdl%h_prime, mdl%T_int, P_GPa, &
            mdl%volume
        case('ortho-ssm')
          write(lun,'(i10,6e18.8,2f12.4,e16.8)') mdl%step, &
            mdl%dft_total_energy, mdl%ion_kinetic_energy, mdl%nhc_energy, &
            mdl%box_kinetic_energy, mdl%PV, mdl%h_prime, mdl%T_int, P_GPa, &
            mdl%volume
        case('berendsen')
          if (md_berendsen_equil > 0) then
            write(lun,'(i10,6e18.8,2f12.4,e16.8)') mdl%step, &
              mdl%dft_total_energy, mdl%ion_kinetic_energy, zero, zero, &
              mdl%PV, mdl%h_prime, mdl%T_int, P_GPa, mdl%volume
          else
            write(lun,'(i10,4e18.8,2f12.4,e16.8)') mdl%step, &
              mdl%dft_total_energy, mdl%ion_kinetic_energy, mdl%PV, &
              mdl%h_prime, mdl%T_int, P_GPa, mdl%volume
          end if
        end select
      case ('nph')
          write(lun,'(i10,5e18.8,2f12.4,e16.8)') mdl%step, &
            mdl%dft_total_energy, mdl%ion_kinetic_energy, &
            mdl%box_kinetic_energy, mdl%PV, mdl%h_prime, mdl%T_int, P_GPa, &
            mdl%volume
      end select
      call io_close(lun)
    end if

  end subroutine dump_stats
  !!***

  !!****m* md_model/dump_frame *
  !!  NAME
  !!   dump_frame
  !!  PURPOSE
  !!   Dump all relevant restart/analysis-relevant data to file 
  !!  AUTHOR
  !!   Zamaan Raza 
  !!  SOURCE
  !!  
  subroutine dump_frame(mdl, filename)

    use input_module,     only: io_assign, io_close
    use GenComms,         only: inode, ionode

    ! passed variables
    class(type_md_model), intent(inout)   :: mdl
    character(len=*), intent(in)          :: filename

    ! local variables
    integer                               :: lun, i

    if (flag_MDdebug .and. inode==ionode) then
      write(io_lun,*) "Writing frame to ", filename
    end if

    if (inode==ionode) then
      call io_assign(lun)
      if (mdl%append) then
        open(unit=lun,file=filename,position='append')
      else 
        open(unit=lun,file=filename,status='replace')
      end if

      write(lun,'("frame ",i8)') mdl%step
      write(lun,'(a)') "cell_vectors"
      do i=1,3
        write(lun,'(3f12.6)') mdl%lattice_vec(i,:)
      end do
      write(lun,'(a)') "end cell_vectors"
      write(lun,'(a)') "stress_tensor"
      write(lun,'(3f14.6)') mdl%stress(1), zero, zero
      write(lun,'(3f14.6)') zero, mdl%stress(2), zero
      write(lun,'(3f14.6)') zero, zero, mdl%stress(3)
      write(lun,'(a)') "end stress_tensor"
      write(lun,'(a)') "positions"
      call mdl%dump_mdl_atom_arr(lun, mdl%atom_coords)
      write(lun,'(a)') "end positions"
      write(lun,'(a)') "velocities"
      call mdl%dump_mdl_atom_arr(lun, mdl%atom_velocity)
      write(lun,'(a)') "end velocities"
      write(lun,'(a)') "forces"
      call mdl%dump_mdl_atom_arr(lun, mdl%atom_force)
      write(lun,'(a)') "end forces"
      write(lun,'(a)') "end frame"
    end if

    call io_close(lun)

  end subroutine dump_frame
  !!***

  !!****m* md_model/dump_mdl_atom_arr *
  !!  NAME
  !!   dump_mdl_atom_arr 
  !!  PURPOSE
  !!   dump an array of atomic data to file (positions, velocities, forces) 
  !!  AUTHOR
  !!   Zamaan Raza 
  !!  SOURCE
  !!  
  subroutine dump_mdl_atom_arr(mdl, lun, arr)

    ! passed variables
    class(type_md_model), intent(inout)       :: mdl
    integer, intent(in)                       :: lun
    real(double), dimension(:,:), intent(in)  :: arr

    ! local variables
    integer                           :: i

    do i=1,mdl%natoms
      write(lun,'(2i5,3e20.10)') i, mdl%species(i), arr(:,i)
    end do

  end subroutine dump_mdl_atom_arr
  !!***

  !!****m* md_model/dump_tdep *
  !!  NAME
  !!   dump_tdep_frame
  !!  PURPOSE
  !!   Dump a MD step for TDEP postprocessing
  !!  AUTHOR
  !!   Zamaan Raza
  !!  SOURCE
  !!
  subroutine dump_tdep(mdl)
 
    use input_module,     only: io_assign, io_close
    use GenComms,         only: inode, ionode
    use units,            only: HaToEv, BohrToAng
    use md_control,       only: fac_HaBohr32GPa
 
    ! passed variables
    class(type_md_model), intent(inout)   :: mdl
 
    ! local variables
    integer                               :: lunp, lunm, lunf, luns, lunl, i
 
    if (inode==ionode) then
      if (flag_MDdebug) write(io_lun,*) "Writing TDEP output"
      call io_assign(lunm)
      call io_assign(lunp)
      call io_assign(lunf)
      call io_assign(luns)
      call io_assign(lunl)
 
      open(unit=lunm,file=file_meta,status='replace')
      if (mdl%append) then
        open(unit=lunp,file=file_positions,status='old',position='append')
        open(unit=lunf,file=file_forces,status='old',position='append')
        open(unit=luns,file=file_stat,status='old',position='append')
        open(unit=lunl,file=file_loto,status='old',position='append')
      else 
        open(unit=lunp,file=file_positions,status='replace')
        open(unit=lunf,file=file_forces,status='replace')
        open(unit=luns,file=file_stat,status='replace')
        open(unit=lunl,file=file_loto,status='replace')
      end if

      write(lunm,'(i12,a)') mdl%natoms, " # N atoms"
      write(lunm,'(i12,a)') mdl%step, " # N time steps"
      write(lunm,'(f12.2,a)') mdl%timestep, " # time step in fs"
      write(lunm,'(f12.2,a)') mdl%T_ext, " # temperature in K"
      call io_close(lunm)
 
      do i=1,mdl%natoms
        write(lunp,'(3e20.12)') mdl%pos_x(i)/mdl%lat_a, &
                                mdl%pos_y(i)/mdl%lat_b, &
                                mdl%pos_z(i)/mdl%lat_c
        write(lunf,'(3e20.12)') mdl%atom_force(:,i)*HaToeV/BohrToAng
      end do
      call io_close(lunp)
      call io_close(lunf)

      write(luns,'(i7,f10.1,3e16.8,8e14.6)') mdl%step, mdl%step*mdl%timestep, &
        (mdl%dft_total_energy+mdl%ion_kinetic_energy)*HaToeV, &
        mdl%dft_total_energy*HaToeV, &
        mdl%ion_kinetic_energy*HaToeV, mdl%T_int, mdl%P_int, &
        mdl%stress(1)*fac_HaBohr32GPa, mdl%stress(2)*fac_HaBohr32GPa, &
        mdl%stress(3)*fac_HaBohr32GPa, zero, zero, zero
 
      call io_close(luns)
      call io_close(lunl)
    end if

  end subroutine dump_tdep
  !!***

end module md_model
