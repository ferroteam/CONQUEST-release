! -*- mode: F90; mode: font-lock; column-number-mode: true; vc-back-end: CVS -*-
! ------------------------------------------------------------------------------
! $Id: support_spec_format.f90,v 1.2 2005/05/26 08:36:28 drb Exp $
! ------------------------------------------------------------------------------
! Module support_spec_format
! ------------------------------------------------------------------------------
! Code area 11: basis functions
! ------------------------------------------------------------------------------

!!****h* Conquest/support_spec_format *
!!  NAME
!!   support_spec_format
!!  PURPOSE
!!   Creates a defined type to specify a support function in terms
!!   of pseudo-atomic orbitals (PAO's), and creates an array variable
!!   called support_info to hold the information specifying
!!   all support functions of all species in terms of PAO's. 
!!  USES
!!
!!  AUTHOR
!!   Mike Gillan 
!!  CREATION DATE
!!   22/6/02
!!  MODIFICATION HISTORY
!!   2006/06/12 07:56 dave
!!    Various other changes made before this, but consolidation under way.  Will remove or relocate 
!!    acz-type variables, and add routines to allocate/deallocate and associate coefficient array.
!!   2006/06/16 17:11 dave
!!    Added flag for PAOs to choose whether we're storing coefficients for all atoms in cell or just primary
!!    set (storage space vs communication choice - as always)
!!  SOURCE
!!
module support_spec_format

  use datatypes

  implicit none

  save
  
  type supp_function_aczs
     integer :: ncoeffs
     real(double), pointer, dimension(:) :: coefficients ! Dimension npaos (sum over l of  acz(l)*(2l+1)
  end type supp_function_aczs

  type support_function
     integer :: nsuppfuncs
     type(supp_function_aczs), pointer, dimension(:) :: supp_func ! coefficients for a sf, dimension nsuppfuncs
     ! Other data used for PAO basis set
     integer :: lmax
     integer, pointer, dimension(:) :: naczs ! Of dimension 0:lmax
  end type support_function

  ! For the PAOs, we can store coefficients for ALL atoms in cell (technically not order-N, but convenient for
  ! relatively small systems - i.e. up to 10,000 atoms) or for the primary set only.  This flag selects the
  ! former if tru and the latter if false (default, set in get_support_pao_rep in ol_rad_table_subs.f90) is
  ! false
  logical :: flag_paos_atoms_in_cell ! Do we store coefficients for ALL atoms in cell, or only in primary set
  integer :: mx_pao_coeff_atoms ! max atoms coefficients stored for
  logical :: read_option, symmetry_breaking
  logical :: TestPAOGrads, TestTot, TestBoth, TestS, TestH

  character(len=80) :: support_pao_file
  
  type(support_function), allocatable, dimension(:), target :: supports_on_atom ! Dimension mx_atoms (flag above)
  type(support_function), allocatable, dimension(:), target :: supports_on_atom_remote 
  type(support_function), allocatable, dimension(:) :: support_gradient
  type(support_function), allocatable, dimension(:) :: support_elec_gradient
  
  ! This is of dimension mx_atoms*nsf*mx_coeffs (roughly !)
  real(double), dimension(:), allocatable, target :: coefficient_array
  ! This is for the case when we don't have all PAO coefficients on a processor
  real(double), dimension(:), allocatable, target :: coefficient_array_remote
  real(double), dimension(:), allocatable, target :: grad_coeff_array, elec_grad_coeff_array
  integer :: coeff_array_size ! size of coefficient_array

  ! -------------------------------------------------------
  ! RCS ident string for object file id
  ! -------------------------------------------------------
  character(len=80), private :: RCSid = "$Id: support_spec_format.f90,v 1.2 2005/05/26 08:36:28 drb Exp $"

!!***

contains

  subroutine allocate_supp_coeff_array(size)

    use global_module, ONLY: iprint_basis, area_basis
    use GenComms, ONLY: cq_abort, inode, ionode
    use memory_module, ONLY: reg_alloc_mem, type_dbl

    implicit none

    ! Passed variables
    integer :: size

    ! Local variables
    integer :: stat

    if(allocated(coefficient_array)) then
       deallocate(coefficient_array)
       if(inode==ionode) write(*,*) 'WARNING ! Allocate call for coefficient_array when allocated !'
    end if
    if(allocated(grad_coeff_array)) then
       deallocate(grad_coeff_array)
       if(inode==ionode) write(*,*) 'WARNING ! Allocate call for coefficient_array when allocated !'
    end if
    if(allocated(elec_grad_coeff_array)) then
       deallocate(elec_grad_coeff_array)
       if(inode==ionode) write(*,*) 'WARNING ! Allocate call for coefficient_array when allocated !'
    end if
    if(allocated(coefficient_array_remote)) then
       deallocate(coefficient_array_remote)
       if(inode==ionode) write(*,*) 'WARNING ! Allocate call for coefficient_array when allocated !'
    end if
    if(inode==ionode.AND.iprint_basis>2) write(*,*) 'Allocating basis set coefficients array, size: ',size
    allocate(coefficient_array(size),STAT=stat)
    if(stat/=0) call cq_abort("Error allocating coefficient_array: ",stat,size)
    call reg_alloc_mem(area_basis, size, type_dbl)
    allocate(grad_coeff_array(size),STAT=stat)
    if(stat/=0) call cq_abort("Error allocating grad_coeff_array: ",stat,size)
    call reg_alloc_mem(area_basis, size, type_dbl)
    allocate(elec_grad_coeff_array(size),STAT=stat)
    if(stat/=0) call cq_abort("Error allocating elec_grad_coeff_array: ",stat,size)
    call reg_alloc_mem(area_basis, size, type_dbl)
    if(flag_paos_atoms_in_cell) then
       allocate(coefficient_array_remote(size),STAT=stat)
       if(stat/=0) call cq_abort("Error allocating coefficient_array_remote: ",stat,size)
       call reg_alloc_mem(area_basis, size, type_dbl)
    end if
  end subroutine allocate_supp_coeff_array
  
  subroutine deallocate_supp_coeff_array

    use GenComms, ONLY: cq_abort, inode, ionode
    use memory_module, ONLY: reg_dealloc_mem, type_dbl
    use global_module, ONLY: area_basis

    implicit none

    integer :: sizearr

    sizearr = size(coefficient_array)
    if(allocated(coefficient_array)) then
       call reg_dealloc_mem(area_basis, sizearr,type_dbl)
       deallocate(coefficient_array)
    end if
    if(allocated(grad_coeff_array)) then
       call reg_dealloc_mem(area_basis, sizearr,type_dbl)
       deallocate(grad_coeff_array)
    end if
    if(allocated(elec_grad_coeff_array)) then
       call reg_dealloc_mem(area_basis, sizearr,type_dbl)
       deallocate(elec_grad_coeff_array)
    end if
    if(flag_paos_atoms_in_cell.AND.allocated(coefficient_array_remote)) then
       call reg_dealloc_mem(area_basis, sizearr,type_dbl)
       deallocate(coefficient_array_remote)
    end if
  end subroutine deallocate_supp_coeff_array

  subroutine associate_supp_coeff_array(supp_struc,n_atoms,array,length)

    use datatypes
    use GenComms, ONLY: cq_abort

    implicit none

    ! Passed variables
    integer :: n_atoms, length
    type(support_function), dimension(n_atoms) :: supp_struc
    real(double), target, dimension(length) :: array

    ! Local variables
    integer :: i, n_sup, count, marker

    marker = 0
    ! n_atoms is passed in so that we can have all atom storage or only primary set storage
    do i=1,n_atoms
       do n_sup = 1, supp_struc(i)%nsuppfuncs
          count = supp_struc(i)%supp_func(n_sup)%ncoeffs
          supp_struc(i)%supp_func(n_sup)%coefficients => array(marker+1:marker+count)
          marker = marker + count
          if(marker>length) call cq_abort("Overflow in associate_supp_coeff_array: ",marker,length)
       end do
    end do
  end subroutine associate_supp_coeff_array
  
end module support_spec_format
